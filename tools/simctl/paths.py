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

#: The watch this project started on, and still the default everywhere.
DEFAULT_DEVICE = "instinctcrossoveramoled"

#: The application name, which is also the PRG stem and so the .SET name.
APP = "CrossoverFace"


def prg_for(device: str = DEFAULT_DEVICE, *, test: bool = False) -> str:
    """Where ``make build``/``make test`` leave the binary for a device.

    Build output is namespaced by device (``bin/<device>/``) because the face now
    targets five of them and a flat ``bin/`` let one overwrite another's ``.prg``
    with nothing recording which watch it was compiled for. The *stem* is
    deliberately unchanged: the simulator names an app's persisted settings after
    it, so ``CROSSOVERFACE.SET`` stays where every other tool expects it.
    """
    suffix = "-test" if test else ""
    return f"bin/{device}/{APP}{suffix}.prg"


def settings_schema(repo: Path, prg: Path | str) -> Path:
    """The settings schema ``monkeyc`` emits beside a build.

    Resolved from the PRG's own directory rather than a fixed ``bin/``, so it
    follows the device namespacing. It is build output, which is why callers are
    expected to report "run `make build` first" rather than write unvalidated.
    """
    prg = Path(prg)
    return repo / prg.parent / f"{prg.stem}-settings.json"


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
