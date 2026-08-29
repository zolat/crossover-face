"""Where the simulator keeps things, for a given instance.

The simulated device filesystem is a real directory tree on the Mac, rooted at
``$TMPDIR/com.garmin.connectiq`` — the device's ``0:/``. Because the simulator reads
``TMPDIR`` from its environment, pointing an instance at a private temp directory gives
it a private device filesystem, which is what lets several sessions run their own
simulator without sharing settings or app data.

``TMPDIR`` is per-user and per-boot, so it is resolved at run time. Never hard-code it.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

#: Subdirectory the simulator creates inside whatever temp directory it is given.
SIM_DIRNAME = "com.garmin.connectiq"


def shared_tmpdir() -> Path:
    """The temp directory the machine's default simulator uses."""
    out = subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()
    return Path(out)


def root_for(tmpdir: Path | str | None = None) -> Path:
    """The device filesystem root (``0:/``) for an instance, or the shared one."""
    base = Path(tmpdir) if tmpdir is not None else shared_tmpdir()
    return base / SIM_DIRNAME


def app_name(prg: Path | str) -> str:
    """The simulator names an app's files after its PRG, upper-cased."""
    return Path(prg).stem.upper()


def settings_file(root: Path, prg: Path | str) -> Path:
    """The persisted ``Application.Properties`` store."""
    return root / "GARMIN" / "APPS" / "SETTINGS" / f"{app_name(prg)}.SET"


def installed_prg(root: Path, prg: Path | str) -> Path:
    """Where a sideloaded app lands."""
    return root / "GARMIN" / "APPS" / "MEDIA" / f"{app_name(prg)}.PRG"


def crash_log(root: Path) -> Path:
    """The device's crash log. YAML, with a symbolicated stack."""
    return root / "GARMIN" / "APPS" / "LOGS" / "CIQ_LOG.YML"


def repo_root() -> Path:
    """The project checkout this module lives in — worktree-safe."""
    return Path(__file__).resolve().parent.parent.parent
