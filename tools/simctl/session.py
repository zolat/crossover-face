"""Own the isolated simulators used by one long-lived MCP server.

The simulator process deliberately outlives the command that launches it. That is useful
inside one agent session, where load/settings/test/screenshot calls should reuse it, but
it also means a forgotten release used to leave every one-off verification instance
running forever.

Each MCP server gets a session-scoped name and holds an advisory lock beside every
instance it touches. Normal shutdown releases all of them. If the server is killed too
abruptly to run cleanup, the kernel drops its locks and the next server can prove those
instances are abandoned before stopping them. No process-list guesses and no global
``pkill`` are involved.
"""

from __future__ import annotations

import fcntl
import os
import re
import shutil
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import BinaryIO

from simctl import instance as instances

LEASE_FILE = ".mcp-session.lock"
_SAFE_LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
_SAFE_RESOLVED_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$")


class SessionInstances:
    """Resolve, lease, and enumerate the isolated instances owned by this server."""

    def __init__(self) -> None:
        self.client = instances.client_name()
        self.scope = instances.default_name()
        if self.scope == self.client:
            # Normally the launcher supplies this token. Keep direct `python sim_mcp.py`
            # invocations just as isolated and cleanable instead of silently sharing.
            self.scope = f"{self.client}-{os.getpid()}"
        self._targets: dict[str, instances.Instance] = {}
        self._leases: dict[str, BinaryIO] = {}
        self._operations: dict[str, threading.RLock] = {}
        self._mutex = threading.Lock()
        self.reap_errors: list[str] = []
        self.reaped = self._reap_abandoned()

    def resolve(self, which: str | None) -> instances.Instance:
        """Resolve a shared target or a private name scoped to this MCP session."""
        if which == "shared":
            name = "shared"
        elif which is None:
            name = self.scope
        elif which == self.scope or which.startswith(f"{self.scope}-"):
            # Status/load responses report the resolved name. Accepting it back makes
            # release idempotent for clients that echo that field rather than the short
            # label they originally supplied.
            if not _SAFE_RESOLVED_NAME.fullmatch(which):
                raise ValueError("resolved instance name contains unsafe characters")
            name = which
        else:
            if not _SAFE_LABEL.fullmatch(which):
                raise ValueError(
                    "instance names must start with a letter or digit and contain only "
                    "letters, digits, '.', '_' or '-' (64 characters maximum)"
                )
            name = f"{self.scope}-{which}"

        with self._mutex:
            target = self._targets.get(name)
            if target is not None:
                return target
            if name == "shared":
                target = instances.shared()
            else:
                target = instances.isolated(name)
                instance_lease = self._claim(target)
                try:
                    target.reserve_port()
                except Exception:
                    Path(instance_lease.name).unlink(missing_ok=True)
                    instance_lease.close()
                    raise
                self._leases[name] = instance_lease
            self._targets[name] = target
            self._operations[name] = threading.RLock()
            return target

    @contextmanager
    def use(self, which: str | None):
        """Serialize one complete tool operation against its target instance."""
        target = self.resolve(which)
        with self._mutex:
            operation = self._operations[target.name]
        with operation:
            yield target

    def tracked(self) -> list[instances.Instance]:
        """A snapshot of instances to release without holding the registry mutex."""
        with self._mutex:
            return list(self._targets.values())

    def forget(self, target: instances.Instance, remove_sandbox: bool = False) -> None:
        """Drop a lease, optionally removing session state that cannot be reused."""
        with self._mutex:
            self._targets.pop(target.name, None)
            self._operations.pop(target.name, None)
            lease = self._leases.pop(target.name, None)
        if not target.isolated:
            return
        if lease is not None:
            marker = Path(lease.name)
            try:
                marker.unlink(missing_ok=True)
            finally:
                lease.close()
            if remove_sandbox:
                shutil.rmtree(marker.parent, ignore_errors=True)
        target.release_port()

    def _claim(self, target: instances.Instance) -> BinaryIO:
        base = target.home.parent
        base.mkdir(parents=True, exist_ok=True)
        marker = base / LEASE_FILE
        lease = marker.open("a+b")
        try:
            fcntl.flock(lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            lease.close()
            raise RuntimeError(
                f"simulator instance {target.name!r} is owned by another MCP session"
            ) from error
        lease.seek(0)
        lease.truncate()
        lease.write(f"{os.getpid()}\n".encode())
        lease.flush()
        return lease

    def _reap_abandoned(self) -> list[str]:
        """Stop only instances whose previous MCP owner no longer holds its lease."""
        reaped = []
        pattern = f"{self.client}-*/{LEASE_FILE}"
        for marker in sorted(instances.SANDBOX_HOME.glob(pattern)):
            remove_sandbox = False
            port_lease = None
            try:
                lease = marker.open("a+b")
            except FileNotFoundError:
                continue  # its owner completed normal cleanup after globbing
            try:
                try:
                    fcntl.flock(lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    continue
                try:
                    port = int((marker.parent / "port").read_text().strip())
                    if not instances.PORT_RANGE[0] <= port <= instances.PORT_RANGE[1]:
                        raise ValueError(f"invalid recorded port {port}")
                    port_dir = instances.SANDBOX_HOME / instances.PORT_LOCK_DIR
                    port_dir.mkdir(parents=True, exist_ok=True)
                    port_lease = (port_dir / f"{port}.lock").open("a+b")
                    try:
                        fcntl.flock(
                            port_lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB
                        )
                    except BlockingIOError:
                        port_lease.close()
                        port_lease = None
                        continue
                    target = instances.isolated(marker.parent.name)
                    stopped = target.stop()
                    if stopped:
                        reaped.append(target.name)
                    remaining_pid = target.pid()
                    if remaining_pid is None:
                        marker.unlink(missing_ok=True)
                        remove_sandbox = True
                    elif not target.is_running():
                        self.reap_errors.append(
                            f"{target.name}: simulator pid {remaining_pid} does not own "
                            f"recorded port {target.port}"
                        )
                except Exception as error:
                    self.reap_errors.append(f"{marker.parent.name}: {error}")
            finally:
                if port_lease is not None:
                    port_lease.close()
                lease.close()
            if remove_sandbox:
                shutil.rmtree(marker.parent, ignore_errors=True)
        return reaped
