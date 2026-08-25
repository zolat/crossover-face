"""Push a file to the watch over MTP, without a GUI.

This device generation is MTP-only: it never appears in /Volumes, so there is
nothing to `cp` to. libmtp cannot write to it either — Garmin's MTP stack does
not support the bulk-metadata call libmtp uses to resolve a parent folder, so
every `mtp-sendfile` ends in "could not get storage id from parent id". OpenMTP
works because it walks the tree itself, but it is a GUI, and dragging the .prg
in by hand costs a minute in the middle of every build loop.

OpenMTP's MTP engine is not the GUI, though. It is a Go library, kalam, shipped
inside the app bundle as a plain arm64 dylib with a C ABI:

    /Applications/OpenMTP.app/Contents/Resources/bin/arm64/kalam.dylib

This drives that dylib directly through ctypes, so `make install` becomes as
automatic as `make sim` — the same engine already proven against this watch,
minus the drag. Nothing is reimplemented and nothing is patched; the library is
loaded from the installed app exactly as OpenMTP loads it.

The JSON contract below is transcribed from OpenMTP 3.3.0's own bindings, which
ship unminified inside app.asar, rather than guessed from the exported symbols.

Only one process may claim the watch's USB interface at a time, so OpenMTP must
be quit before this runs.

Usage:
    python3 tools/mtp_push.py --info                 # device and storages
    python3 tools/mtp_push.py --ls /GARMIN/Apps      # list a folder
    python3 tools/mtp_push.py bin/CrossoverFace.prg  # push, then verify
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import sys
import threading

DYLIB = os.environ.get(
    "KALAM_DYLIB",
    "/Applications/OpenMTP.app/Contents/Resources/bin/arm64/kalam.dylib",
)

#! Where Connect IQ apps live on the watch.
APPS_DIR = "/GARMIN/Apps"

#! Every kalam entry point reports through this: void (*)(char*), handed a JSON
#! envelope of {error, errorType, data}. An empty error string means success.
CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_char_p)


class KalamError(RuntimeError):
    pass


class Kalam:
    """Thin ctypes binding over OpenMTP's kalam MTP library.

    Every call is fire-and-wait: kalam reports through a callback rather than a
    return value, so each one blocks on an Event until that callback fires. The
    callback objects are held on the instance because a garbage-collected
    ctypes callback that Go still holds a pointer to is a segfault.
    """

    def __init__(self, dylib: str = DYLIB, timeout: float = 180.0,
                 abi: str = "byref"):
        if not os.path.exists(dylib):
            raise KalamError(
                f"kalam not found at {dylib}\n"
                "Install OpenMTP (brew install --cask openmtp), or set "
                "KALAM_DYLIB to its location."
            )
        self._lib = ctypes.CDLL(dylib)
        self._timeout = timeout
        self._abi = abi
        self._alive: list = []

    # --- plumbing ------------------------------------------------------------

    def _as_arg(self, callback):
        """How a callback is handed over.

        The exported signature is `on_cb_result_t*` — a pointer to a function
        pointer — so byref() is the reading that matches the header. Whether
        cgo actually dereferences it is not something the header settles, so
        the other reading stays available behind --abi for one experiment.
        """
        return ctypes.byref(callback) if self._abi == "byref" else callback

    def _call(self, name: str, payload: dict | None = None, *, extra=()):
        done = threading.Event()
        result: dict = {}

        def on_done(raw):
            # Copy out before returning; Go owns the buffer afterwards.
            result["raw"] = bytes(raw) if raw else b""
            done.set()

        args = []
        if payload is not None:
            args.append(json.dumps(payload).encode("utf-8"))

        callbacks = [CALLBACK(handler) for handler in extra]
        callbacks.append(CALLBACK(on_done))
        self._alive.extend(callbacks)
        args.extend(self._as_arg(cb) for cb in callbacks)

        fn = getattr(self._lib, name)
        fn.restype = None
        fn(*args)

        if not done.wait(self._timeout):
            raise KalamError(
                f"{name} did not report back within {self._timeout:g}s. "
                "Is OpenMTP still running, or the watch asleep?"
            )
        return self._unwrap(name, result["raw"])

    @staticmethod
    def _unwrap(name: str, raw: bytes):
        if not raw:
            raise KalamError(f"{name} returned nothing")
        envelope = json.loads(raw.decode("utf-8", "replace"))
        error = envelope.get("error") or ""
        if error:
            kind = envelope.get("errorType") or "unknown"
            raise KalamError(f"{name} failed [{kind}]: {error}")
        return envelope.get("data")

    # --- lifecycle -----------------------------------------------------------

    def __enter__(self):
        self._call("Initialize")
        return self

    def __exit__(self, *exc):
        # Always release the USB claim: a leaked one blocks the next run and
        # OpenMTP alike until the watch is unplugged.
        try:
            self._call("Dispose")
        except Exception:
            pass
        return False

    # --- api -----------------------------------------------------------------

    def device_info(self):
        return self._call("FetchDeviceInfo")

    def storages(self):
        return self._call("FetchStorages")

    def walk(self, storage_id: int, full_path: str, recursive: bool = False):
        return self._call("Walk", {
            "storageId": int(storage_id),
            "fullPath": full_path,
            "recursive": recursive,
            "skipDisallowedFiles": False,
            "skipHiddenFiles": False,
        })

    def file_exists(self, storage_id: int, files: list[str]):
        return self._call("FileExists", {
            "storageId": int(storage_id), "files": files})

    def make_directory(self, storage_id: int, full_path: str):
        return self._call("MakeDirectory", {
            "storageId": int(storage_id), "fullPath": full_path})

    def upload(self, storage_id: int, sources: list[str], destination: str,
               on_progress=None):
        def progress(raw):
            if on_progress and raw:
                try:
                    on_progress(json.loads(raw.decode("utf-8", "replace")))
                except (ValueError, KeyError):
                    pass

        return self._call(
            "UploadFiles",
            {
                "storageId": int(storage_id),
                "sources": sources,
                "destination": destination,
                "preprocessFiles": True,
            },
            # Preprocess is counted but not reported on; progress is.
            extra=(lambda raw: None, progress),
        )


# --- storage / listing helpers -----------------------------------------------


def pick_storage(kalam: Kalam, wanted: int | None) -> int:
    storages = kalam.storages() or []
    if not storages:
        raise KalamError("the watch reported no storage")
    if wanted is not None:
        return wanted
    first = storages[0]
    # kalam returns storages keyed by Sid with a description alongside.
    return int(first.get("Sid", first.get("sid", first.get("storageId"))))


def entries(walked) -> list[dict]:
    """Normalise Walk's payload to a plain list of entries."""
    if walked is None:
        return []
    if isinstance(walked, dict):
        return list(walked.values())
    return list(walked)


def show_progress(state: dict) -> None:
    percent = state.get("progress")
    speed = state.get("speed")
    if percent is None:
        return
    line = f"\r  {percent:5.1f}%"
    if speed:
        line += f"   {speed:.1f} MB/s"
    sys.stderr.write(line)
    sys.stderr.flush()


# --- commands ----------------------------------------------------------------


def cmd_info(kalam: Kalam) -> int:
    print(json.dumps(kalam.device_info(), indent=2))
    print(json.dumps(kalam.storages(), indent=2))
    return 0


def cmd_ls(kalam: Kalam, path: str, storage: int | None) -> int:
    sid = pick_storage(kalam, storage)
    for entry in entries(kalam.walk(sid, path)):
        kind = "d" if entry.get("isFolder") else "-"
        print(f"{kind} {entry.get('size', 0):>10}  {entry.get('name')}")
    return 0


def cmd_push(kalam: Kalam, source: str, dest: str, storage: int | None) -> int:
    source = os.path.abspath(source)
    if not os.path.isfile(source):
        print(f"no such file: {source}", file=sys.stderr)
        return 1

    sid = pick_storage(kalam, storage)
    name = os.path.basename(source)
    expected = os.path.getsize(source)

    print(f"pushing {name} ({expected:,} bytes) -> {dest}")
    kalam.upload(sid, [source], dest, on_progress=show_progress)
    sys.stderr.write("\r")

    # Verify from the device's own listing rather than trusting the transfer.
    landed = next((e for e in entries(kalam.walk(sid, dest))
                   if e.get("name") == name), None)
    if landed is None:
        print(f"upload reported success but {name} is not in {dest}",
              file=sys.stderr)
        return 1
    actual = landed.get("size")
    if actual is not None and int(actual) != expected:
        print(f"size mismatch: {actual} on watch, {expected} locally",
              file=sys.stderr)
        return 1

    print(f"done — {name} verified on the watch ({expected:,} bytes)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Push a file to a Garmin watch over MTP.")
    parser.add_argument("file", nargs="?", help="local file to push")
    parser.add_argument("--dest", default=APPS_DIR,
                        help=f"folder on the watch (default {APPS_DIR})")
    parser.add_argument("--info", action="store_true",
                        help="print device info and storages, then exit")
    parser.add_argument("--ls", metavar="PATH",
                        help="list a folder on the watch, then exit")
    parser.add_argument("--storage", type=int,
                        help="storage id (default: the first reported)")
    parser.add_argument("--timeout", type=float, default=180.0,
                        help="seconds to wait for any one call")
    parser.add_argument("--abi", choices=("byref", "direct"), default="byref",
                        help="how callbacks are passed (see Kalam._as_arg)")
    args = parser.parse_args(argv)

    if not (args.info or args.ls or args.file):
        parser.print_help()
        return 2

    try:
        with Kalam(timeout=args.timeout, abi=args.abi) as kalam:
            if args.info:
                return cmd_info(kalam)
            if args.ls:
                return cmd_ls(kalam, args.ls, args.storage)
            return cmd_push(kalam, args.file, args.dest, args.storage)
    except KalamError as err:
        print(f"\n{err}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
