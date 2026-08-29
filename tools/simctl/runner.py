"""Load the face, run the tests, and say what went wrong when nothing appears.

Two things here are not just wrapping ``make``.

**Telling the failures apart.** A run that produces nothing can mean the tests failed,
that another session took the simulator mid-run, or that the Mac display slept and
stopped the VM. All three look identical - an empty result - and two of them are not
about the code at all. Each is reported as itself.

**Reading the crash log.** ``GARMIN/APPS/LOGS/CIQ_LOG.YML`` carries a symbolicated stack,
which is what a tripped watchdog leaves behind - the failure mode this face's frame
budget exists to avoid. It persists between runs, so it is only reported when it is
newer than the run that just happened; otherwise an old crash gets blamed on new code.
"""

from __future__ import annotations

import os
import re
import signal
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from simctl import instance as instances
from simctl import paths, window
from simctl.lock import SimulatorLock

DEFAULT_PRG = "bin/CrossoverFace.prg"
DEFAULT_TEST_PRG = "bin/CrossoverFace-test.prg"
DEFAULT_DEVICE = "instinctcrossoveramoled"


@dataclass
class TestReport:
    """What a test run actually did, rather than a wall of text."""

    ran: int = 0
    passed: bool = False
    failures: int = 0
    errors: int = 0
    tests: list[dict] = field(default_factory=list)
    contention: bool = False
    crash: dict | None = None
    summary: str = ""
    output: str = ""

    @property
    def ok(self) -> bool:
        return self.passed and not self.contention


def parse_tests(text: str) -> TestReport:
    """Read monkeydo's Run No Evil output.

    monkeydo's exit status is not a verdict — it is non-zero even when everything
    passes — so the summary line is what decides, exactly as the Makefile does.
    """
    report = TestReport(output=text)

    for line in text.splitlines():
        stripped = line.strip()
        match = re.match(r"^(\w[\w.]*)\s+(PASS|FAIL|ERROR)\s*$", stripped, re.IGNORECASE)
        if match and match.group(1).lower() not in ("test", "results"):
            report.tests.append(
                {"name": match.group(1), "status": match.group(2).upper()}
            )

    ran = re.search(r"^Ran (\d+) test", text, re.MULTILINE)
    if ran:
        report.ran = int(ran.group(1))
    else:
        # Nothing ran at all: the simulator went away mid-run rather than the code failing.
        report.contention = True

    # The counters inside the parentheses are not stable across SDK versions - 9.2.0
    # prints "PASSED (passed=60, failed=0, errors=0)" where the docs show
    # "PASSED (failures=0, errors=0)" - so read whatever key=value pairs are there
    # rather than pinning one shape.
    summary = re.search(r"^(PASSED|FAILED)\s*\(([^)]*)\)", text, re.MULTILINE)
    if summary:
        report.summary = summary.group(0)
        report.passed = summary.group(1) == "PASSED"
        counters = {key: int(value)
                    for key, value in re.findall(r"(\w+)=(\d+)", summary.group(2))}
        report.failures = counters.get("failed", counters.get("failures", 0))
        report.errors = counters.get("errors", 0)
    return report


def read_crash(root: Path, newer_than: float | None = None) -> dict | None:
    """The device's last crash, if it belongs to the run we just did."""
    log = paths.crash_log(root)
    if not log.exists():
        return None
    if newer_than is not None and log.stat().st_mtime < newer_than:
        return None  # a leftover from an earlier run; not this one's fault
    text = log.read_text(errors="replace")
    error = re.search(r"^Error:\s*(.+)$", text, re.MULTILINE)
    stack = re.findall(r"File:\s*'?([^'\n]+)'?\s*\n\s*Line:\s*(\d+)\s*\n\s*Function:\s*(\S+)",
                       text)
    return {
        "error": error.group(1).strip() if error else "unknown",
        "stack": [{"file": f.strip(), "line": int(l), "function": fn} for f, l, fn in stack],
        "path": str(log),
    }


class Runner:
    """Drives one instance: build, sideload, capture-until-ready, test."""

    def __init__(self, target: instances.Instance, prg: str = DEFAULT_PRG,
                 device: str = DEFAULT_DEVICE):
        self.instance = target
        self.prg = prg
        self.device = device
        self.repo = paths.repo_root()
        self.lock = SimulatorLock() if not target.isolated else None

    # -- helpers ------------------------------------------------------------

    @property
    def _child_pid_file(self) -> Path:
        return self.instance.state_dir / f"monkeydo-{self.instance.name}.pid"

    def _make_environment(self) -> dict:
        return self.instance.environment()

    def _make_overrides(self) -> list[str]:
        """Point the existing Makefile at this instance without editing it.

        Command-line assignments beat the Makefile's ``:=``, so an isolated run reuses
        the real recipe: no lock (this instance is ours alone) and a pinned monkeydo.
        """
        if not self.instance.isolated:
            # Shared mode: if this process already holds the lock (sim_load keeps it, the
            # way `make sim` does), the recipe must not try to take it again. It would
            # find a live holder that is us, wait out the full timeout and fail - and a
            # run that produced no output parses as contention, so a self-inflicted stall
            # would be reported as another session's fault.
            return ["SIM_LOCK=true"] if (self.lock and self.lock.held_by_us()) else []
        # SDK and KEY are passed in because the Makefile resolves the SDK by running
        # connect-iq-sdk-manager, which keeps its licence agreement outside ~/.Garmin and
        # so reports "agreement is not accepted" under a sandboxed HOME. Resolving once
        # here, with the real environment, keeps the sandbox to what it is actually for:
        # the simulator's own runtime state. The trailing slash matters - the Makefile
        # writes $(SDK)bin/monkeyc with no separator.
        return [
            f"SDK={instances.sdk_path()}/",
            f"KEY={Path.home() / '.Garmin' / 'ConnectIQ' / 'developer_key.der'}",
            "SIM_LOCK=true",
            f"MONKEYDO={self.repo / 'tools' / 'simctl' / 'monkeydo_pinned.sh'}",
        ]

    def _monkeydo(self) -> list[str]:
        if self.instance.isolated:
            return [str(self.repo / "tools" / "simctl" / "monkeydo_pinned.sh")]
        return [str(instances.sdk_path() / "bin" / "monkeydo")]

    def build(self) -> subprocess.CompletedProcess:
        """A clean build is also the type check: monkey.jungle sets strict typechecking."""
        return subprocess.run(
            ["make", "-s", "build", *self._make_overrides()],
            cwd=self.repo, env=self._make_environment(),
            capture_output=True, text=True,
        )

    # -- lifecycle ----------------------------------------------------------

    def release(self) -> dict:
        """Stop *our* sideload. Never `pkill monkeydo` — that kills every session's.

        Says which of the three things happened, because "False" covers two very
        different situations: nothing was ever loaded, and the sideload had already
        exited (a test run replaces the app, which ends the attached monkeydo).
        """
        try:
            pid = int(self._child_pid_file.read_text().strip())
        except (OSError, ValueError):
            pid = None

        if pid is None:
            outcome = "nothing was loaded by this session"
            stopped = False
        else:
            try:
                os.killpg(os.getpgid(pid), signal.SIGTERM)
                outcome, stopped = f"stopped sideload {pid}", True
            except (ProcessLookupError, PermissionError):
                outcome, stopped = f"sideload {pid} had already exited", False
            self._child_pid_file.unlink(missing_ok=True)

        released = False
        if self.lock is not None and self.lock.held_by_us():
            self.lock.release()
            released = True
        return {"stopped": stopped, "detail": outcome, "lock_released": released}

    def load(self, build: bool = True, timeout: float = 45.0) -> dict:
        """Get the face running and wait until it is actually drawing.

        Readiness is "the capture stopped being black", which is a real signal rather
        than a fixed sleep — and when it never arrives, the reason is diagnosed instead
        of being reported as a bare timeout.
        """
        # The sandbox must exist before anything runs with its HOME: the SDK manager
        # will otherwise create real directories where the symlinks belong.
        self.instance.prepare()

        if build:
            built = self.build()
            if built.returncode != 0:
                return {"ok": False, "stage": "build",
                        "error": (built.stderr or built.stdout).strip()[-2000:]}

        if self.lock is not None and not self.lock.acquire():
            return {"ok": False, "stage": "lock",
                    "error": f"the shared simulator is held by pid {self.lock.holder()}"}

        started = time.time()
        self.instance.start()
        self.release_child_only()

        log = self.instance.state_dir / f"monkeydo-{self.instance.name}.log"
        with open(log, "wb") as stream:
            child = subprocess.Popen(
                [*self._monkeydo(), self.prg, self.device],
                cwd=self.repo, env=self._make_environment(),
                stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
            )
        self._child_pid_file.write_text(str(child.pid))

        # Readiness needs two facts, not one. Killing monkeydo does not stop the app
        # inside the simulator, so a reload leaves the previous face on screen and a
        # "not black" test passes instantly against the *old* build. So wait for this
        # push to actually land - the app binary in the device filesystem is rewritten
        # by the push - and only then for something to be drawn.
        installed = paths.installed_prg(self.instance.root, self.prg)
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            pushed = installed.exists() and installed.stat().st_mtime >= started
            if pushed:
                found = window.main_window(self.instance.pid())
                if found is not None:
                    try:
                        shot = window.capture(found)
                        if not window.is_black(shot):
                            return {"ok": True, "pid": self.instance.pid(),
                                    "port": self.instance.port, "window": found.window_id,
                                    "monkeydo": child.pid,
                                    "seconds": round(time.time() - started, 1)}
                        last = "the face is drawing black"
                    except window.CaptureError as error:
                        last = str(error)
            else:
                last = "the app was never pushed to this instance"
            time.sleep(1.0)

        return {"ok": False, "stage": "ready", "error": last or "no simulator window appeared",
                "display_asleep": window.display_is_asleep(),
                "crash": read_crash(self.instance.root, started),
                "log": str(log)}

    def release_child_only(self) -> None:
        """Drop a previous sideload without giving up the lock."""
        try:
            pid = int(self._child_pid_file.read_text().strip())
        except (OSError, ValueError):
            return
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
            time.sleep(1.0)
        except (ProcessLookupError, PermissionError):
            pass
        self._child_pid_file.unlink(missing_ok=True)

    # -- tests --------------------------------------------------------------

    def run_tests(self, timeout: float = 600.0) -> TestReport:
        """Run the Monkey C suite and return it parsed.

        In shared mode the lock is taken here rather than left to the recipe, so that a
        session which already holds it (from ``sim_load``) keeps holding it straight
        through instead of deadlocking against itself. Holding continuously also beats
        releasing and re-acquiring, which would open a gap another session could win
        halfway through the run.
        """
        started = time.time()
        mine = False
        if self.instance.isolated:
            self.instance.start()
        elif self.lock is not None and not self.lock.held_by_us():
            if not self.lock.acquire():
                report = TestReport(contention=True)
                report.summary = (f"did not start: the shared simulator is held by pid "
                                  f"{self.lock.holder()}")
                return report
            mine = True  # ours to give back; a lock sim_load took stays held

        try:
            result = subprocess.run(
                ["make", "test", *self._make_overrides()],
                cwd=self.repo, env=self._make_environment(),
                capture_output=True, text=True, timeout=timeout,
            )
        finally:
            if mine and self.lock is not None:
                self.lock.release()

        report = parse_tests(result.stdout + result.stderr)
        report.crash = read_crash(self.instance.root, started)
        return report

    def write_settings(self, updates: dict, schema) -> dict:
        """Persist settings safely: stop the app, hold the lock, then write.

        The app must be stopped first because a live one flushes its in-memory properties
        over the file on termination, silently undoing the write. In shared mode the lock
        is held across the write too, so a neighbouring test run cannot be part-way
        through using these values while they change underneath it.
        """
        from simctl import settings as settings_module

        mine = False
        if self.lock is not None and not self.lock.held_by_us():
            if not self.lock.acquire():
                return {"ok": False,
                        "error": f"the shared simulator is held by pid {self.lock.holder()}"}
            mine = True
        try:
            self.release_child_only()
            settings_module.write(self.instance.root, updates, schema)
        except (settings_module.SettingsError, ValueError) as error:
            return {"ok": False, "error": str(error)}
        finally:
            if mine and self.lock is not None:
                self.lock.release()
        return {"ok": True, "applied": updates}
