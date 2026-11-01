"""A simulator of one's own, so parallel sessions stop taking turns.

The Connect IQ simulator is a singleton by habit rather than by necessity. Three
environment variables, all confirmed present in the binary, move everything that made it
one:

``TMPDIR``
    the simulated device filesystem (``0:/``), so settings and app data are private.
``HOME``
    the ``Sim-$USER`` file it writes its own pid into, which is what refuses a second
    instance.
``SHELL_SERVER_PORT``
    the control channel it listens on.

A sandboxed ``HOME`` also moves ``~/.Garmin/ConnectIQ`` and the ``Application Support``
alias the compiler resolves devices through, so both are symlinked back to the real ones
- the instance is isolated, not a separate installation. It must also be exec'd directly:
``bin/connectiq`` uses ``open -a``, which reuses the running instance and drops the
environment entirely.

Ports are allocated well above the SDK's 1234-1238 scan range on purpose. A plain
``make sim`` in another worktree probes that range and takes the first simulator that
answers, so keeping isolated instances outside it means an unaware session can never
find one by accident.
"""

from __future__ import annotations

import hashlib
import fcntl
import os
import re
import signal
import socket
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import BinaryIO

from simctl import paths

SIMULATOR_PROCESS = "ConnectIQ.app/Contents/MacOS/simulator"
SHARED_PORT = 1234
#: Above the SDK's 1234-1238 scan, so an unaware monkeydo cannot stumble onto ours.
PORT_RANGE = (13000, 13999)
SANDBOX_HOME = Path.home() / ".cache" / "crossover-sim"
PORT_LOCK_DIR = ".port-locks"
PORT_ALLOCATOR_LOCK = ".port-allocation.lock"


def sdk_path() -> Path:
    """Resolved at run time, exactly as the Makefile does, so an SDK upgrade needs no edit."""
    out = subprocess.check_output(
        ["connect-iq-sdk-manager", "sdk", "current-path"], text=True
    ).strip()
    return Path(out)


def simulator_binary() -> Path:
    return sdk_path() / "bin" / "ConnectIQ.app" / "Contents" / "MacOS" / "simulator"


def client_name() -> str:
    """The stable part of an instance name: MCP client plus checkout."""
    checkout = paths.repo_root().name
    namespace = os.environ.get("CROSSOVER_SIM_NAMESPACE", "").strip()
    return f"{namespace}-{checkout}" if namespace else checkout


def default_name() -> str:
    """One instance per MCP server session, stable for that session's lifetime.

    ``tools/sim_mcp.sh`` supplies its own pid as the session token. Direct CLI users do
    not, and retain the old one-per-client-and-checkout behaviour so separate commands
    can deliberately reuse an instance.
    """
    client = client_name()
    session = os.environ.get("CROSSOVER_SIM_SESSION", "").strip()
    return f"{client}-{session}" if session else client


def _port_for(name: str) -> int:
    """Deterministic, so the same checkout keeps its port across sessions."""
    span = PORT_RANGE[1] - PORT_RANGE[0] + 1
    digest = hashlib.sha256(name.encode()).digest()
    return PORT_RANGE[0] + int.from_bytes(digest[:2], "big") % span


def _listening(port: int) -> bool:
    """Is something accepting connections here?

    Asked by connecting rather than by trying to bind: the simulator binds ``*:<port>``,
    and a probe bind on ``127.0.0.1`` with SO_REUSEADDR succeeds anyway, so bind-probing
    reports a busy port as free.
    """
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.3):
            return True
    except OSError:
        return False


def _alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, TypeError):
        return False
    except PermissionError:
        return True


def _simulator_process(pid: int) -> bool:
    """Does this pid still belong to a Connect IQ simulator executable?"""
    result = subprocess.run(
        ["lsof", "-nP", "-a", "-p", str(pid), "-d", "txt", "-Fn"],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0 and any(
        line.startswith("n") and line[1:].endswith(SIMULATOR_PROCESS)
        for line in result.stdout.splitlines()
    )


def _owns_port(pid: int, port: int) -> bool:
    """Does this exact process own the instance's listening control port?"""
    result = subprocess.run(
        [
            "lsof", "-nP", "-a", "-p", str(pid), f"-iTCP:{port}",
            "-sTCP:LISTEN", "-t",
        ],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0 and str(pid) in result.stdout.splitlines()


@dataclass
class Instance:
    """One simulator: either the machine's shared one, or a private sandboxed one."""

    name: str
    port: int
    home: Path | None = None      # None for the shared instance
    tmpdir: Path | None = None
    _process: subprocess.Popen | None = field(default=None, repr=False, compare=False)
    _sideload_process: subprocess.Popen | None = field(
        default=None, repr=False, compare=False
    )
    _port_lease: BinaryIO | None = field(default=None, repr=False, compare=False)

    @property
    def isolated(self) -> bool:
        return self.home is not None

    @property
    def root(self) -> Path:
        """The device filesystem root for this instance."""
        return paths.root_for(self.tmpdir)

    @property
    def state_dir(self) -> Path:
        """Where this instance's own bookkeeping lives (logs, child pids)."""
        return self.home if self.isolated else paths.shared_tmpdir()

    @property
    def pid_file(self) -> Path:
        """The simulator records its own pid here — authoritative, and self-maintaining."""
        home = self.home or Path.home()
        return home / f"Sim-{os.environ.get('USER', 'user')}"

    @property
    def port_file(self) -> Path | None:
        """The selected collision-free port, persisted for an isolated instance."""
        return self.home.parent / "port" if self.isolated else None

    def pid(self) -> int | None:
        try:
            text = self.pid_file.read_text(errors="ignore")
        except OSError:
            return None
        # The simulator writes the pid NUL-terminated, which strip() does not remove,
        # so take the leading digits rather than trusting the whole string.
        match = re.match(r"\s*(\d+)", text)
        pid = int(match.group(1)) if match else None
        if pid is not None and _alive(pid) and _simulator_process(pid):
            return pid
        if self.isolated:
            # The sandbox owns this file. Removing a stale/recycled pid prevents a later
            # launch or cleanup from ever treating an unrelated process as the simulator.
            self.pid_file.unlink(missing_ok=True)
        return None

    def is_running(self) -> bool:
        pid = self.pid()
        return pid is not None and _owns_port(pid, self.port)

    def environment(self) -> dict:
        """The environment that makes a launch land in this instance."""
        env = dict(os.environ)
        # SHELL_SERVER_PORT is read by the simulator itself; CROSSOVER_SIM_PORT is what
        # the pinned monkeydo/shell wrappers route through. Both, or a sideload reaches
        # the wrong instance - or, as the wrappers insist, refuses to guess.
        env["SHELL_SERVER_PORT"] = str(self.port)
        env["CROSSOVER_SIM_PORT"] = str(self.port)
        if self.isolated:
            env["HOME"] = str(self.home)
            env["TMPDIR"] = f"{self.tmpdir}/"
        return env

    # -- lifecycle ----------------------------------------------------------

    def reserve_port(self) -> None:
        """Reserve this instance's port against not-yet-listening parallel launches."""
        if not self.isolated or self._port_lease is not None:
            return
        SANDBOX_HOME.mkdir(parents=True, exist_ok=True)
        port_dir = SANDBOX_HOME / PORT_LOCK_DIR
        port_dir.mkdir(exist_ok=True)
        allocator_path = SANDBOX_HOME / PORT_ALLOCATOR_LOCK
        with allocator_path.open("a+b") as allocator:
            fcntl.flock(allocator.fileno(), fcntl.LOCK_EX)
            first = self.port
            port = first
            while True:
                lease = (port_dir / f"{port}.lock").open("a+b")
                try:
                    fcntl.flock(lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    lease.close()
                else:
                    if not _listening(port):
                        self.port = port
                        self.home.parent.mkdir(parents=True, exist_ok=True)
                        port_file = self.port_file
                        if port_file is None:  # isolated is checked above
                            raise RuntimeError("private simulator has no port file")
                        port_file.write_text(f"{port}\n")
                        self._port_lease = lease
                        return
                    lease.close()

                port = PORT_RANGE[0] + (port - PORT_RANGE[0] + 1) % (
                    PORT_RANGE[1] - PORT_RANGE[0] + 1
                )
                if port == first:
                    raise RuntimeError("no free isolated simulator ports are available")

    def release_port(self) -> None:
        """Release a reservation when its owning MCP session is finished."""
        if self._port_lease is not None:
            self._port_lease.close()
            self._port_lease = None

    def prepare(self) -> None:
        """Create the sandbox, linking the SDK data back to the real home."""
        if not self.isolated:
            return
        self.home.mkdir(parents=True, exist_ok=True)
        self.tmpdir.mkdir(parents=True, exist_ok=True)
        port_file = self.port_file
        if port_file is not None:
            try:
                port_is_current = int(port_file.read_text().strip()) == self.port
            except (OSError, ValueError):
                port_is_current = False
            if not port_is_current:
                port_file.write_text(f"{self.port}\n")
        support = self.home / "Library" / "Application Support" / "Garmin"
        support.mkdir(parents=True, exist_ok=True)
        # Devices and the signing key stay shared; only the runtime state is private.
        for link, target in (
            (self.home / ".Garmin", Path.home() / ".Garmin"),
            (support / "ConnectIQ", Path.home() / ".Garmin" / "ConnectIQ"),
        ):
            if link.is_symlink():
                continue
            if link.is_dir():
                # Something ran with this HOME before the links existed and made a real
                # directory. Reclaim it when it is empty; refuse when it holds anything,
                # rather than deleting state we did not create.
                try:
                    link.rmdir()
                except OSError as error:
                    raise RuntimeError(
                        f"{link} is a real directory with contents; expected a symlink "
                        f"to {target}. Remove it by hand if it is not wanted."
                    ) from error
            else:
                link.unlink(missing_ok=True)
            link.symlink_to(target)

    def start(self, timeout: float = 30.0) -> int:
        """Launch if not already up, and wait until it is listening. Returns the pid."""
        existing = self.pid()
        if existing:
            if _owns_port(existing, self.port):
                return existing
            raise RuntimeError(
                f"simulator pid {existing} for instance {self.name!r} is not listening "
                f"on its recorded port {self.port}"
            )
        self.reserve_port()
        self.prepare()
        log = (self.home or Path(paths.shared_tmpdir())) / "simulator.log"
        with open(log, "ab") as stream:
            self._process = subprocess.Popen(
                [str(simulator_binary())],
                env=self.environment(), stdout=stream, stderr=stream,
                start_new_session=True,
            )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pid = self.pid()
            if pid and _owns_port(pid, self.port):
                time.sleep(1.0)  # let the UI settle before anything sideloads
                return pid
            time.sleep(0.3)
        raise TimeoutError(
            f"simulator for instance {self.name!r} did not come up on port {self.port} "
            f"within {timeout:g}s — see {log}"
        )

    def stop(self, timeout: float = 10.0) -> bool:
        """Stop *this* instance only, never another session's."""
        deadline = time.monotonic() + timeout
        if self._process is not None:
            # The Popen handle is stronger ownership proof than a pid file or a port.
            # It also lets us reap the child instead of polling a zombie until timeout.
            process = self._process
            if process.poll() is None:
                try:
                    process.terminate()
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=max(0.0, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1.0)
            self._process = None
            return True

        pid = self.pid()
        if pid is None:
            return False
        # A stale Sim-$USER file can outlive its process and its pid can be recycled.
        # Never signal unless this exact simulator still owns this instance's port.
        if not _owns_port(pid, self.port):
            return False
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            return True
        while time.monotonic() < deadline:
            if not _alive(pid):
                return True
            time.sleep(0.2)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            return True
        return True


def shared() -> Instance:
    """The machine's normal simulator — the one `make sim` and `make test` drive."""
    return Instance(name="shared", port=SHARED_PORT)


def isolated(name: str | None = None) -> Instance:
    """A private instance for this checkout, created on first use."""
    name = name or default_name()
    base = SANDBOX_HOME / name
    port_file = base / "port"
    has_saved_port = False
    try:
        saved_port = int(port_file.read_text().strip())
        has_saved_port = PORT_RANGE[0] <= saved_port <= PORT_RANGE[1]
        port = saved_port if has_saved_port else _port_for(name)
    except (OSError, ValueError):
        port = _port_for(name)
    if not has_saved_port and not (base / "home").exists():
        # First use: step past anything already listening. Once the sandbox exists the
        # selected port is persisted, so resolving after a hash collision still finds
        # this same instance rather than reverting to the occupied hash-derived port.
        first = port
        while _listening(port):
            port = PORT_RANGE[0] + (port - PORT_RANGE[0] + 1) % (
                PORT_RANGE[1] - PORT_RANGE[0] + 1
            )
            if port == first:
                raise RuntimeError("no free isolated simulator ports are available")
    return Instance(name=name, port=port, home=base / "home", tmpdir=base / "tmp")


def resolve(which: str | None) -> Instance:
    """``"shared"`` for the machine simulator, anything else for a private instance."""
    if which == "shared":
        return shared()
    return isolated(which)
