"""Take the shared simulator's turn, from a process that outlives one turn.

``tools/sim_lock.sh`` serialises the machine's single simulator across parallel sessions.
It is the right mechanism and this wraps it rather than replacing it, so the MCP server
queues with plain ``make sim`` and ``make test`` instead of racing them.

The wrapping needs one piece of care that a shell caller never hits. The script records
the owner's **pid** and treats a lock whose owner has exited as stale, which fits a make
recipe perfectly: the recipe shell is the owner and dies when the recipe ends. A
long-lived server has neither property:

* Acquiring again with the same pid would block on the lock it already holds, wait out
  the full timeout and fail — the server deadlocking against itself.
* Shelling out ``acquire $$`` per operation instead records a pid that dies immediately,
  so the very next caller, in any session, proves the lock stale and takes it. The lock
  would still exist and protect nothing.

So the owner is this process, and holding is re-entrant: an acquire that finds our own
pid already recorded returns without touching the lock. Only ``release`` gives it up.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from simctl import paths

DEFAULT_LOCK = Path(os.environ.get("CROSSOVER_SIM_LOCK", "/tmp/crossover-face-simulator.lock"))


class SimulatorLock:
    """The shared simulator's lock, held re-entrantly by this process."""

    def __init__(self, script: Path | None = None, owner: int | None = None):
        self.script = script or paths.repo_root() / "tools" / "sim_lock.sh"
        self.owner = owner or os.getpid()
        self.lock_dir = DEFAULT_LOCK

    def holder(self) -> int | None:
        """The pid recorded in the lock, or None when it is free."""
        try:
            text = (self.lock_dir / "owner").read_text().strip()
        except OSError:
            return None
        return int(text) if text.isdigit() else None

    def held_by_us(self) -> bool:
        return self.holder() == self.owner

    def acquire(self, timeout: int | None = None) -> bool:
        """Wait our turn. Returns False if the wait ran out."""
        if self.held_by_us():
            return True  # re-entrant: we already have it
        environment = dict(os.environ)
        if timeout is not None:
            environment["CROSSOVER_SIM_LOCK_WAIT"] = str(timeout)
        result = subprocess.run(
            [str(self.script), "acquire", str(self.owner)],
            capture_output=True, text=True, env=environment,
        )
        return result.returncode == 0

    def release(self) -> None:
        """Give the lock back. Harmless when we do not hold it."""
        if not self.held_by_us():
            return
        subprocess.run([str(self.script), "release", str(self.owner)],
                       capture_output=True, text=True)

    def __enter__(self) -> "SimulatorLock":
        if not self.acquire():
            raise TimeoutError(
                f"the simulator is still held by pid {self.holder()} - "
                f"another session is using it"
            )
        return self

    def __exit__(self, *exception) -> None:
        self.release()
