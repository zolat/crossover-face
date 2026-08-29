"""See what the simulator is actually drawing.

The Connect IQ SDK has no screenshot command — there is no such token in the simulator
binary and none in its shell command table — so capturing the face means capturing the
macOS window. That is not a shortcut around a nicer API; it is the only route there is.

Window lookup goes through CoreGraphics via ``ctypes`` rather than pyobjc, so the module
runs on the stock system Python with no virtualenv (``tools/mtp_push.py`` drives a Go
dylib the same way). Windows are matched by owning **process id**, which is what lets a
session screenshot its own simulator while other sessions are running theirs.

Two things this module knows that a bare screenshot does not:

* **Where the face is.** The capture includes the title bar, the device artwork and the
  status bar. The device image is a known 704x805 asset drawn to fit the window width,
  so its vertical offset is recovered by matching bezel pixels against the asset on disk
  rather than by hard-coding a title-bar height that a macOS update could change.
* **What black means.** An all-black capture is the documented tell that the Mac display
  has slept and stopped the Monkey C VM — a hang that reads exactly like a failing test
  suite. Reporting it as a distinct state is most of the value here.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from simctl import paths

SIMULATOR_OWNER = "Connect IQ Device Simulator"
DEVICE_DIR = Path.home() / ".Garmin" / "ConnectIQ" / "Devices"
DEFAULT_DEVICE = "instinctcrossoveramoled"

# CGWindowListOption
_OPTION_ALL = 0
_OPTION_ON_SCREEN = 1
_EXCLUDE_DESKTOP = 16
_NULL_WINDOW = 0
_NUMBER_SINT64, _NUMBER_FLOAT64 = 4, 6
_UTF8 = 0x08000100

_cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))
_cg = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreGraphics"))

_cf.CFStringCreateWithCString.restype = ctypes.c_void_p
_cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
_cf.CFArrayGetCount.restype = ctypes.c_long
_cf.CFArrayGetCount.argtypes = [ctypes.c_void_p]
_cf.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
_cf.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
_cf.CFDictionaryGetValue.restype = ctypes.c_void_p
_cf.CFDictionaryGetValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
_cf.CFNumberGetValue.restype = ctypes.c_bool
_cf.CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
_cf.CFStringGetCString.restype = ctypes.c_bool
_cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
_cf.CFRelease.argtypes = [ctypes.c_void_p]
_cg.CGWindowListCopyWindowInfo.restype = ctypes.c_void_p
_cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]


def _cfstr(text: str) -> ctypes.c_void_p:
    return ctypes.c_void_p(_cf.CFStringCreateWithCString(None, text.encode(), _UTF8))


def _string(dictionary, key) -> str:
    value = _cf.CFDictionaryGetValue(dictionary, key)
    if not value:
        return ""
    buffer = ctypes.create_string_buffer(512)
    if not _cf.CFStringGetCString(ctypes.c_void_p(value), buffer, 512, _UTF8):
        return ""
    return buffer.value.decode(errors="replace")


def _number(dictionary, key, kind=_NUMBER_SINT64):
    value = _cf.CFDictionaryGetValue(dictionary, key)
    if not value:
        return None
    out = ctypes.c_double() if kind == _NUMBER_FLOAT64 else ctypes.c_longlong()
    if not _cf.CFNumberGetValue(ctypes.c_void_p(value), kind, ctypes.byref(out)):
        return None
    return out.value


@dataclass
class SimulatorWindow:
    """A simulator window, identified by the process that owns it."""

    window_id: int
    pid: int
    title: str
    x: int
    y: int
    width: int
    height: int
    on_screen: bool

    @property
    def is_main(self) -> bool:
        """The device view lives in the main window; helper panels are small or unnamed."""
        return self.title.startswith("CIQ Simulator") and self.width > 200 and self.height > 200


def find_windows(pid: int | None = None, on_screen_only: bool = False) -> list[SimulatorWindow]:
    """Every simulator window, optionally just the ones owned by ``pid``.

    Minimised and off-screen windows are included by default because
    ``screencapture -l`` can still capture them — which is what allows a screenshot
    without stealing focus from whatever the user is doing.
    """
    options = (_OPTION_ON_SCREEN if on_screen_only else _OPTION_ALL) | _EXCLUDE_DESKTOP
    array = _cg.CGWindowListCopyWindowInfo(options, _NULL_WINDOW)
    if not array:
        return []
    keys = {name: _cfstr(name) for name in
            ("kCGWindowOwnerName", "kCGWindowOwnerPID", "kCGWindowNumber", "kCGWindowName",
             "kCGWindowBounds", "kCGWindowIsOnscreen")}
    bounds_keys = {name: _cfstr(name) for name in ("X", "Y", "Width", "Height")}
    found = []
    try:
        for index in range(_cf.CFArrayGetCount(ctypes.c_void_p(array))):
            entry = _cf.CFArrayGetValueAtIndex(ctypes.c_void_p(array), index)
            if _string(entry, keys["kCGWindowOwnerName"]) != SIMULATOR_OWNER:
                continue
            owner = _number(entry, keys["kCGWindowOwnerPID"])
            if pid is not None and owner != pid:
                continue
            box = _cf.CFDictionaryGetValue(entry, keys["kCGWindowBounds"])
            geometry = {
                name: int(_number(box, key, _NUMBER_FLOAT64) or 0)
                for name, key in bounds_keys.items()
            }
            found.append(
                SimulatorWindow(
                    window_id=int(_number(entry, keys["kCGWindowNumber"]) or 0),
                    pid=int(owner or 0),
                    title=_string(entry, keys["kCGWindowName"]),
                    x=geometry["X"], y=geometry["Y"],
                    width=geometry["Width"], height=geometry["Height"],
                    on_screen=bool(_number(entry, keys["kCGWindowIsOnscreen"]) or 0),
                )
            )
    finally:
        _cf.CFRelease(ctypes.c_void_p(array))
    return found


def main_window(pid: int | None = None) -> SimulatorWindow | None:
    """The window the device is drawn in, for one instance."""
    candidates = [window for window in find_windows(pid) if window.is_main]
    # A titled window sorts first; among equals prefer the largest, which is the device view.
    candidates.sort(key=lambda window: window.width * window.height, reverse=True)
    return candidates[0] if candidates else None


class CaptureError(RuntimeError):
    """The window could not be captured."""


def display_is_asleep() -> bool:
    """A slept display captures as pure black — and stops the Monkey C VM with it.

    This is worth a positive test rather than an inference: when the display sleeps,
    window capture fails outright with "could not create image from window", which looks
    exactly like a missing Screen Recording permission and sends you fixing the wrong
    thing. Measured, not assumed.
    """
    probe = Path(tempfile.mkstemp(suffix=".png")[1])
    try:
        if subprocess.run(["screencapture", "-x", str(probe)],
                          capture_output=True).returncode != 0:
            return False
        with Image.open(probe) as screen:
            return screen.convert("L").getextrema() == (0, 0)
    except OSError:
        return False
    finally:
        probe.unlink(missing_ok=True)


def wake_display(seconds: int = 5) -> None:
    """Nudge an idle display awake. A *locked* screen cannot be woken from the shell."""
    subprocess.run(["caffeinate", "-u", "-t", str(seconds)], capture_output=True)


def _screencapture(window_id: int, target: Path) -> subprocess.CompletedProcess:
    # -o omits the window shadow, -x silences the shutter sound. Neither raises the
    # window, which is what keeps a screenshot from stealing the user's focus.
    return subprocess.run(
        ["screencapture", "-o", "-x", "-l", str(window_id), str(target)],
        capture_output=True, text=True,
    )


def capture(window: SimulatorWindow, destination: Path | None = None,
            wake: bool = True) -> Image.Image:
    """Grab a window, including when it is off-screen, without raising or focusing it."""
    target = destination or Path(tempfile.mkstemp(suffix=".png")[1])

    def failed(result) -> bool:
        return result.returncode != 0 or not target.exists() or target.stat().st_size == 0

    result = _screencapture(window.window_id, target)
    if failed(result) and wake and display_is_asleep():
        wake_display()
        result = _screencapture(window.window_id, target)

    if failed(result):
        if display_is_asleep():
            raise CaptureError(
                "the Mac display is asleep, which also stops the simulator's VM. "
                "`caffeinate -u -t 5` wakes an idle display; a locked screen cannot be "
                "woken from the shell, so unlock it and retry."
            )
        raise CaptureError(
            f"screencapture failed for window {window.window_id} "
            f"({result.stderr.strip() or 'no error text'}). If the display is awake, "
            f"the usual cause is Screen Recording permission for the terminal; a window "
            f"minimised to the Dock also has no backing store to capture."
        )
    image = Image.open(target)
    image.load()
    return image


def device_image(device: str = DEFAULT_DEVICE) -> Image.Image:
    return Image.open(DEVICE_DIR / device / "device.png").convert("RGB")


def display_location(device: str = DEFAULT_DEVICE) -> dict:
    data = json.loads((DEVICE_DIR / device / "simulator.json").read_text())
    return data["display"]["location"]


def locate_device(shot: Image.Image, device: str = DEFAULT_DEVICE) -> tuple[float, int, float]:
    """Find the device artwork inside a window capture.

    Returns ``(scale, y_offset, mismatch)``. The artwork is drawn to fit the window
    width, so the scale follows from the capture width; only the vertical offset is
    unknown, and it is found by comparing bezel pixels against ``device.png`` instead of
    assuming a title-bar height. ``mismatch`` is the mean per-channel difference at the
    best offset — near zero when the match is real, large when the window is showing
    something else (a dialog, a different device).
    """
    art = device_image(device)
    scale = shot.width / art.width
    art_height = int(round(art.height * scale))
    if art_height > shot.height:
        raise CaptureError("capture is shorter than the device artwork; window too small")

    # Sample the bezel only: the display area changes every frame, the artwork never does.
    display = display_location(device)
    probes = []
    for row in range(4, art.height, 37):
        for column in range(4, art.width, 53):
            inside = (display["x"] <= column < display["x"] + display["width"]
                      and display["y"] <= row < display["y"] + display["height"])
            if not inside:
                probes.append((column, row))
    reference = [art.getpixel(point) for point in probes]

    small = shot.convert("RGB").resize((art.width, int(shot.height / scale)), Image.BILINEAR)
    best, best_score = 0, None
    for offset in range(0, small.height - art.height + 1):
        total = 0
        for (column, row), expected in zip(probes, reference):
            actual = small.getpixel((column, row + offset))
            total += (abs(actual[0] - expected[0]) + abs(actual[1] - expected[1])
                      + abs(actual[2] - expected[2]))
            if best_score is not None and total >= best_score:
                break  # already worse than the incumbent
        else:
            if best_score is None or total < best_score:
                best, best_score = offset, total
    mismatch = (best_score or 0) / (len(probes) * 3)
    return scale, int(round(best * scale)), mismatch


def crop_face(shot: Image.Image, device: str = DEFAULT_DEVICE) -> Image.Image:
    """The raw 390x390 display, which is what tools/luminance.py expects."""
    scale, y_offset, _ = locate_device(shot, device)
    display = display_location(device)
    left = int(round(display["x"] * scale))
    top = y_offset + int(round(display["y"] * scale))
    right = left + int(round(display["width"] * scale))
    bottom = top + int(round(display["height"] * scale))
    face = shot.convert("RGB").crop((left, top, right, bottom))
    if face.size != (display["width"], display["height"]):
        face = face.resize((display["width"], display["height"]), Image.LANCZOS)
    return face


def crop_device(shot: Image.Image, device: str = DEFAULT_DEVICE) -> Image.Image:
    """The watch without the window chrome."""
    scale, y_offset, _ = locate_device(shot, device)
    art = device_image(device)
    return shot.convert("RGB").crop(
        (0, y_offset, shot.width, y_offset + int(round(art.height * scale)))
    )


def is_black(image: Image.Image) -> bool:
    """All-black means the VM is not drawing — usually a slept display, not a bug."""
    return image.convert("L").getextrema() == (0, 0)


#: Why a screenshot's luminance is not the 10% budget figure.
LUMINANCE_CAVEAT = (
    "includes the simulator's rendering of the physical hands, which emit no light on "
    "the real watch — not the budget figure"
)


def measure_luminance(face: Image.Image) -> float:
    """Mean relative luminance of a captured face, using the project's own metric.

    **This is not the number the 10% AMOLED budget is measured against.** The budget
    applies to light the panel emits; a capture also contains the simulator's drawing of
    the two *physical* analogue hands, which are metal and emit nothing. Measured on this
    face: 11.17% as captured against 5.43% with the neutral-grey pixels removed, so the
    hands are more than half the reading. Reporting the raw figure as a budget number
    would flag a compliant face as over budget and send someone hunting a regression that
    is not there.

    The authorities remain ``MatrixTest.alwaysOnWorstCaseFitsBudget`` and
    ``tools/mockup.py``, both of which measure the dot field before any hands are drawn.
    Use this to watch for *relative* change between captures.
    """
    sys.path.insert(0, str(paths.repo_root() / "tools"))
    from luminance import measure  # noqa: E402  (path set above)

    return measure(face)


def main(argv: list[str] | None = None) -> int:
    # Shared as a parent so --pid works either side of the subcommand.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--pid", type=int, help="restrict to one simulator instance")
    common.add_argument("--device", default=DEFAULT_DEVICE)

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0], parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="show simulator windows", parents=[common])
    shot = sub.add_parser("shot", help="capture the face", parents=[common])
    shot.add_argument("output", type=Path)
    shot.add_argument("--crop", choices=("face", "device", "window"), default="face")

    args = parser.parse_args(argv)

    if args.command == "list":
        windows = find_windows(args.pid)
        if not windows:
            print("no simulator windows found", file=sys.stderr)
            return 1
        for window in windows:
            flag = "main" if window.is_main else "    "
            print(f"{flag} pid={window.pid} id={window.window_id} "
                  f"{window.width}x{window.height} onscreen={window.on_screen} {window.title!r}")
        return 0

    window = main_window(args.pid)
    if window is None:
        print("no simulator window found — is the simulator running?", file=sys.stderr)
        return 1
    try:
        image = capture(window)
        if args.crop == "face":
            image = crop_face(image, args.device)
        elif args.crop == "device":
            image = crop_device(image, args.device)
        image.save(args.output)
    except CaptureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    blank = is_black(image)
    note = " ALL BLACK — the display may have slept, which stops the VM" if blank else ""
    detail = ""
    if args.crop == "face":
        detail = (f" luminance={measure_luminance(image) * 100:.1f}%"
                  f" ({LUMINANCE_CAVEAT})")
    print(f"wrote {args.output} {image.width}x{image.height}{detail}{note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
