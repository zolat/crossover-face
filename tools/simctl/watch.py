"""Put a config code on a real watch over the cable.

The face keeps its settings in ``/GARMIN/Apps/SETTINGS/CrossoverFace.SET``, the same
format the simulator writes (``setfile`` round-trips a watch's file byte for byte). The
face runs ``ConfigCode.sync()`` when it starts, and a watch restarts the face when the
cable comes out, so a code written into that file's ``configCode`` is applied as soon
as the watch is unplugged. Both were confirmed on an Instinct Crossover AMOLED on
2026-11-01.

Only ``configCode`` changes. Every other value is written back exactly as the watch had
it. The code carries all of them, so the face replaces them itself when it applies the
code, which is the same thing a code pasted into Garmin Connect does. The watch's
previous file is kept as a local backup before anything is written.

Two cases are refused rather than guessed at:

- no settings file yet. A face that has never saved a setting has none, and whether the
  watch reads a file it did not write has not been tested;
- a file with no ``configCode``. The face on the watch predates config codes and would
  ignore it.
"""

from __future__ import annotations

import sys
import tempfile
import time
from pathlib import Path

from simctl import paths, setfile
from simctl.configcode import decode, encode

SETTINGS_DIR = "/GARMIN/Apps/SETTINGS"
SETTINGS_NAME = "CrossoverFace.SET"


class WatchError(RuntimeError):
    pass


def backup_dir() -> Path:
    return paths.repo_root() / "build" / "watch-settings"


def _mtp():
    """The MTP binding lives beside simctl, in tools/mtp_push.py."""
    tools = str(Path(__file__).resolve().parent.parent)
    if tools not in sys.path:
        sys.path.insert(0, tools)
    import mtp_push
    return mtp_push


def open_watch(attempts: int = 2):
    """Claim the watch. The first probe after plugging in can fail on its own."""
    mtp = _mtp()
    last = None
    for attempt in range(attempts):
        try:
            return mtp.Kalam().__enter__()
        except mtp.KalamError as error:
            last = error
            if attempt + 1 < attempts:
                time.sleep(2)
    raise WatchError(f"could not reach the watch: {last}. Is it plugged in, and OpenMTP closed?")


def _storage(kalam) -> int:
    storages = kalam.storages() or []
    if not storages:
        raise WatchError("the watch reported no storage")
    first = storages[0]
    return int(first.get("Sid", first.get("sid", first.get("storageId"))))


def _entries(walked) -> list[dict]:
    if walked is None:
        return []
    return list(walked.values()) if isinstance(walked, dict) else list(walked)


def find_settings(kalam, storage: int) -> str | None:
    """The face's settings file name as the watch spells it, or None."""
    for entry in _entries(kalam.walk(storage, SETTINGS_DIR)):
        name = entry.get("name", "")
        if name.lower() == SETTINGS_NAME.lower() and not entry.get("isFolder"):
            return name
    return None


def _pull(kalam, storage: int, name: str, into: Path) -> bytes:
    kalam.download(storage, [f"{SETTINGS_DIR}/{name}"], str(into))
    landed = into / name
    if not landed.exists():
        raise WatchError(f"could not read {SETTINGS_DIR}/{name} from the watch")
    return landed.read_bytes()


def push_code(code: str, kalam, backups: Path | None = None) -> dict:
    """Write a code into the watch's settings file. Raises WatchError, or ConfigCodeError."""
    canonical = encode(decode(code))
    storage = _storage(kalam)
    name = find_settings(kalam, storage)
    if name is None:
        raise WatchError(
            "the watch has no settings file for the face yet. Make it the active face, "
            "change any setting in its menu once, then run this again")

    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        raw = _pull(kalam, storage, name, scratch / "before")
        values = setfile.decode(raw)
        if "configCode" not in values:
            raise WatchError(
                "the face on the watch predates config codes, so it would ignore one. "
                "Run `make install` first")

        backups = backups if backups is not None else backup_dir()
        backups.mkdir(parents=True, exist_ok=True)
        backup = backups / f"{Path(name).stem}-{time.strftime('%Y%m%d-%H%M%S')}.SET"
        backup.write_bytes(raw)

        previous = values["configCode"]
        values["configCode"] = canonical
        written = setfile.encode(values)
        outgoing = scratch / "out"
        outgoing.mkdir()
        (outgoing / name).write_bytes(written)
        kalam.upload(storage, [str(outgoing / name)], SETTINGS_DIR)

        # Read it back rather than trusting the transfer.
        if _pull(kalam, storage, name, scratch / "after") != written:
            raise WatchError(
                f"the file read back from the watch is not the one written. "
                f"The previous one is saved at {backup}")

    return {"ok": True, "code": canonical, "previous": previous, "backup": str(backup),
            "file": f"{SETTINGS_DIR}/{name}"}


def push(code: str) -> dict:
    decode(code)  # refuse a damaged code before claiming the watch
    kalam = open_watch()
    try:
        return push_code(code, kalam)
    finally:
        kalam.__exit__(None, None, None)
