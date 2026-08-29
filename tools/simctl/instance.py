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
import os
import re
import socket
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from simctl import paths

SIMULATOR_PROCESS = "ConnectIQ.app/Contents/MacOS/simulator"
SHARED_PORT = 1234
#: Above the SDK's 1234-1238 scan, so an unaware monkeydo cannot stumble onto ours.
PORT_RANGE = (13000, 13999)
SANDBOX_HOME = Path.home() / ".cache" / "crossover-sim"


def sdk_path() -> Path:
    """Resolved at run time, exactly as the Makefile does, so an SDK upgrade needs no edit."""
    out = subprocess.check_output(
        ["connect-iq-sdk-manager", "sdk", "current-path"], text=True
    ).strip()
    return Path(out)


def simulator_binary() -> Path:
    return sdk_path() / "bin" / "ConnectIQ.app" / "Contents" / "MacOS" / "simulator"


def default_name() -> str:
    """One instance per checkout, so sibling worktrees never share a simulator."""
    return paths.repo_root().name


def _port_for(name: str) -> int:
    """Deterministic, so the same checkout keeps its port across sessions."""
    span = PORT_RANGE[1] - PORT_RANGE[0]
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
    except (ProcessLookupError, PermissionError, TypeError):
        return False


@dataclass
class Instance:
    """One simulator: either the machine's shared one, or a private sandboxed one."""

    name: str
    port: int
    home: Path | None = None      # None for the shared instance
    tmpdir: Path | None = None

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

    def pid(self) -> int | None:
        try:
            text = self.pid_file.read_text(errors="ignore")
        except OSError:
            return None
        # The simulator writes the pid NUL-terminated, which strip() does not remove,
        # so take the leading digits rather than trusting the whole string.
        match = re.match(r"\s*(\d+)", text)
        pid = int(match.group(1)) if match else None
        return pid if _alive(pid) else None

    def is_running(self) -> bool:
        return self.pid() is not None

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

    def prepare(self) -> None:
        """Create the sandbox, linking the SDK data back to the real home."""
        if not self.isolated:
            return
        self.home.mkdir(parents=True, exist_ok=True)
        self.tmpdir.mkdir(parents=True, exist_ok=True)
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
            return existing
        self.prepare()
        log = (self.home or Path(paths.shared_tmpdir())) / "simulator.log"
        with open(log, "ab") as stream:
            subprocess.Popen(
                [str(simulator_binary())],
                env=self.environment(), stdout=stream, stderr=stream,
                start_new_session=True,
            )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pid = self.pid()
            if pid and _listening(self.port):
                time.sleep(1.0)  # let the UI settle before anything sideloads
                return pid
            time.sleep(0.3)
        raise TimeoutError(
            f"simulator for instance {self.name!r} did not come up on port {self.port} "
            f"within {timeout:g}s — see {log}"
        )

    def stop(self, timeout: float = 10.0) -> bool:
        """Stop *this* instance only, never another session's."""
        pid = self.pid()
        if pid is None:
            return False
        os.kill(pid, 15)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not _alive(pid):
                return True
            time.sleep(0.2)
        os.kill(pid, 9)
        return True


def shared() -> Instance:
    """The machine's normal simulator — the one `make sim` and `make test` drive."""
    return Instance(name="shared", port=SHARED_PORT)


def isolated(name: str | None = None) -> Instance:
    """A private instance for this checkout, created on first use."""
    name = name or default_name()
    base = SANDBOX_HOME / name
    port = _port_for(name)
    if not (base / "home").exists():
        # First use: step past anything already listening. Once the sandbox exists the
        # port is kept, so a running instance of ours is found rather than duplicated.
        while _listening(port):
            port += 1
    return Instance(name=name, port=port, home=base / "home", tmpdir=base / "tmp")


def resolve(which: str | None) -> Instance:
    """``"shared"`` for the machine simulator, anything else for a private instance."""
    if which == "shared":
        return shared()
    return isolated(which)
