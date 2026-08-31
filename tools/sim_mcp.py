#!/usr/bin/env python3
"""MCP server exposing the Connect IQ simulator as typed tools.

Definitions only — every tool is a thin call into ``tools/simctl``, which is also usable
from the shell. Keeping the logic out of here is what lets the behaviour be tested
without an MCP client, and keeps this file readable as an inventory of what the
simulator can be asked to do.

Tools default to **this checkout's own simulator instance**, so parallel sessions do not
queue behind each other. Pass ``instance="shared"`` to drive the machine's normal
simulator instead — the one ``make sim`` and ``make test`` use — which is serialised
through ``tools/sim_lock.sh`` so it interoperates with sessions that never use this
server.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mcp.server.fastmcp import FastMCP, Image

from simctl import instance as instances
from simctl import paths, settings as settings_module, window
from simctl.runner import Runner

mcp = FastMCP("crossover-simulator")

SHOT_DIR = Path(paths.shared_tmpdir()) / "crossover-shots"


#: Which watch a call means when it does not say. The face targets five.
DEFAULT_DEVICE = paths.DEFAULT_DEVICE


def _runner(instance: str | None, device: str | None = None) -> Runner:
    return Runner(instances.resolve(instance), device=device or DEFAULT_DEVICE)


@mcp.tool()
def sim_status(instance: str | None = None, device: str | None = None) -> dict:
    """What state the simulator is in: running, which window, settings, anything wrong.

    One call to answer "where am I", including whether the Mac display has slept, which
    stops the simulator's VM and makes a healthy face look like a hung test run.
    """
    target = instances.resolve(instance)
    pid = target.pid()
    found = window.main_window(pid) if pid else None
    report: dict = {
        "instance": target.name,
        "isolated": target.isolated,
        "port": target.port,
        "running": pid is not None,
        "pid": pid,
        "device_root": str(target.root),
        "display_asleep": window.display_is_asleep(),
    }
    if found is not None:
        report["window"] = {"id": found.window_id, "title": found.title,
                            "size": [found.width, found.height],
                            "on_screen": found.on_screen}
    runner = _runner(instance, device)
    if not target.isolated:
        report["lock_holder"] = runner.lock.holder() if runner.lock else None
    try:
        schema = settings_module.Schema.load(prg=runner.prg)
        report["settings"] = settings_module.describe(target.root, schema,
                                                      prg=runner.prg)
    except settings_module.SettingsError as error:
        report["settings_error"] = str(error)
    return report


@mcp.tool()
def sim_screenshot(instance: str | None = None, device: str | None = None, crop: str = "face") -> list:
    """Capture what the simulator is drawing.

    ``crop``: ``face`` for the raw display at its own resolution - 390x390 on the
    Crossover, 454x454 on an Epix 2 Pro 51mm - which is what tools/luminance.py
    expects; ``device`` for the watch without window chrome, ``window`` for everything.

    ``device`` must name the same watch the running face was built for, because the
    crop is measured against that watch's own artwork.

    The reported luminance **includes the simulator's drawing of any physical analogue
    hands**, which emit no light on the real watch, so on the Crossover it runs well
    above the design figure and is not the 10% budget number. Use it to compare
    captures, not to judge the budget.
    """
    target = instances.resolve(instance)
    pid = target.pid()
    if pid is None:
        return [f"instance {target.name!r} is not running — call sim_load first"]
    found = window.main_window(pid)
    if found is None:
        return [f"instance {target.name!r} has no capturable window"]

    try:
        shot = window.capture(found)
    except window.CaptureError as error:
        return [f"capture failed: {error}"]

    watch = device or DEFAULT_DEVICE
    if crop == "face":
        shot = window.crop_face(shot, device=watch)
    elif crop == "device":
        shot = window.crop_device(shot, device=watch)

    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    path = SHOT_DIR / f"{target.name}-{watch}-{crop}.png"
    shot.save(path)

    note = f"{crop} {shot.width}x{shot.height} -> {path}"
    if window.is_black(shot):
        note += ("  ALL BLACK: nothing is being drawn. If the whole screen is black the "
                 "Mac display has slept, which also stops the VM.")
    elif crop == "face":
        note += (f"  luminance {window.measure_luminance(shot) * 100:.1f}% "
                 f"({window.LUMINANCE_CAVEAT})")
    return [note, Image(path=str(path))]


@mcp.tool()
def sim_settings_get(instance: str | None = None, device: str | None = None) -> dict:
    """Every setting, its value and label, and whether it is persisted or a default.

    The distinction matters: a persisted value beats resources/properties.xml, so
    editing that file changes nothing once the app has ever stored a value — and every
    test run stores some.
    """
    target = instances.resolve(instance)
    try:
        schema = settings_module.Schema.load(prg=paths.prg_for(device or DEFAULT_DEVICE))
    except settings_module.SettingsError as error:
        return {"error": str(error)}
    return {"instance": target.name,
            "settings": settings_module.describe(
                target.root, schema, prg=paths.prg_for(device or DEFAULT_DEVICE))}


@mcp.tool()
def sim_settings_set(settings: dict[str, int], instance: str | None = None, device: str | None = None,
                     reload: bool = True) -> dict:
    """Persist settings, e.g. ``{"ring1": 2, "dotRotation": 1}``.

    Values are checked against the schema the compiler generates, so an out-of-range
    value is refused rather than written. The running app is stopped first: a live app
    can flush its in-memory properties back over the file and silently undo the write.
    """
    runner = _runner(instance, device)
    try:
        schema = settings_module.Schema.load(prg=runner.prg)
    except settings_module.SettingsError as error:
        return {"ok": False, "error": str(error)}

    result = runner.write_settings(settings, schema)
    if not result["ok"]:
        return result
    if reload:
        result["reload"] = runner.load(build=False)
    else:
        result["note"] = "not reloaded; the face still shows the previous settings"
    result["settings"] = settings_module.describe(runner.instance.root, schema,
                                                  prg=runner.prg)
    return result


@mcp.tool()
def sim_settings_reset(instance: str | None = None, device: str | None = None) -> dict:
    """Forget every persisted setting — the scriptable *Reset All App Data*."""
    target = instances.resolve(instance)
    removed = settings_module.reset(target.root)
    return {"ok": True, "cleared": removed,
            "note": "defaults from resources/properties.xml apply on the next load"}


@mcp.tool()
def sim_load(instance: str | None = None, device: str | None = None, build: bool = True) -> dict:
    """Build, start the instance if needed, and sideload the face.

    Returns once the face is actually drawing — the push having landed and the capture
    no longer being black — rather than after a fixed wait. When that never happens it
    reports which failure it was: a slept display, or a crash with its stack.
    """
    return _runner(instance, device).load(build=build)


@mcp.tool()
def sim_release(instance: str | None = None, device: str | None = None) -> dict:
    """Stop our sideload and, in shared mode, give the lock back to other sessions."""
    runner = _runner(instance, device)
    return {"instance": runner.instance.name, **runner.release()}


@mcp.tool()
def sim_test(instance: str | None = None, device: str | None = None) -> dict:
    """Run the Monkey C suite and return it parsed.

    Distinguishes a real failure from contention: monkeydo's exit status is not a
    verdict, and a run that produced no ``Ran N tests`` line means something took the
    simulator mid-run rather than that a test failed.
    """
    report = _runner(instance, device).run_tests()
    return {
        "ok": report.ok, "ran": report.ran, "passed": report.passed,
        "failures": report.failures, "errors": report.errors,
        "contention": report.contention, "summary": report.summary,
        "crash": report.crash,
        "failed_tests": [t for t in report.tests if t["status"] != "PASS"],
        "total_reported": len(report.tests),
    }


if __name__ == "__main__":
    mcp.run()
