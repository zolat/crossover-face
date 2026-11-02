"""Export what the web configurator needs to know about the face, from the face's own files.

The configurator offers every setting, names every value, builds every theme's colour
tiers and knows which ring may carry which source. All of that already lives in the
watch's sources of truth, and copying it by hand into TypeScript would add a sixth place
the settings have to be kept in step. So it is read from them:

- ``resources/settings/settings.xml``: every setting, its type, its values in picker
  order and its bounds. The ring lists are what the phone offers per ring, which is
  ``Source.offeredFor()``.
- ``resources/strings/strings.xml``: the labels. The schema still carries a second,
  "drawn" copy for the watches that tell the time in a ring; since those lost their drawn
  hands they name everything as the Crossover does, so it is the same strings.
- ``source/render/Palette.mc``: the shipping themes, their ramp stops and every tier
  factor.
- ``source/data/Source.mc``: which sources draw blocks and which a temperature range.
- ``source/matrix/HourBands.mc``: the narrowest partial block window each ring draws.
- ``source-hands/*/HandStyle.mc``, ``StatMap.TIME_RING`` and ``Palette.TIME_*``: which
  watches tell the time in a ring, which ring, its styles and their colours. The styles
  are in no settings list, because ``StatMap.load()`` places them rather than offering
  them beside the other sources, so their labels come from the source names in
  ``strings.xml``.

Usage::

    python3 tools/face_schema_export.py           # write web/configurator/src/generated/
    python3 tools/face_schema_export.py --check   # fail if it is stale
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from xml.etree import ElementTree

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "web" / "configurator" / "src" / "generated" / "face-schema.json"


def strings(path: Path) -> dict[str, str]:
    root = ElementTree.parse(path).getroot()
    return {entry.attrib["id"]: entry.text or "" for entry in root.findall("string")}


def resolve(reference: str | None, table: dict[str, str]) -> str | None:
    if reference is None:
        return None
    return table.get(reference.removeprefix("@Strings."), reference)


def settings(base: dict[str, str], drawn: dict[str, str]) -> list[dict]:
    root = ElementTree.parse(REPO / "resources" / "settings" / "settings.xml").getroot()
    out = []
    for setting in root.findall("setting"):
        config = setting.find("settingConfig")
        key = setting.attrib["propertyKey"].removeprefix("@Properties.")
        entry = {
            "key": key,
            "type": config.attrib["type"],
            "title": resolve(setting.attrib.get("title"), base),
            "titleDrawn": resolve(setting.attrib.get("title"), drawn),
            "prompt": resolve(setting.attrib.get("prompt"), base),
            "promptDrawn": resolve(setting.attrib.get("prompt"), drawn),
        }
        options = [
            {"value": int(option.attrib["value"]),
             "label": resolve(option.text, base),
             "labelDrawn": resolve(option.text, drawn)}
            for option in config.findall("listEntry")
        ]
        if options:
            entry["options"] = options
        for bound in ("min", "max", "maxLength"):
            if bound in config.attrib:
                entry[bound] = int(config.attrib[bound])
        out.append(entry)
    return out


def _const(source: str, name: str) -> str:
    match = re.search(rf"\bconst {name}\s*=\s*([^;]+);", source)
    if not match:
        raise SystemExit(f"could not find const {name}")
    return match.group(1).strip()


def _number(source: str, name: str) -> float:
    raw = _const(source, name)
    if re.fullmatch(r"[A-Z_]+", raw):        # an alias of another const
        return _number(source, raw)
    return float(int(raw, 16)) if raw.startswith("0x") else float(raw)


def _array(source: str, name: str) -> list[int]:
    body = _const(source, name)
    body = re.sub(r"//[^\n]*", "", body)    # strip //! comments between entries
    return [int(token, 0) for token in re.findall(r"0x[0-9A-Fa-f]+|-?\d+", body.split(" as ")[0])]


def _floats(source: str, name: str) -> list[float]:
    body = _const(source, name).split(" as ")[0]
    return [float(token) for token in re.findall(r"-?\d+(?:\.\d+)?", body)]


def palette() -> dict:
    source = (REPO / "source" / "render" / "Palette.mc").read_text()
    colours = _array(source, "THEMES")
    stops = _array(source, "RAMP_STOPS")
    per_theme = int(_number(source, "THEME_COLOURS"))
    points = int(_number(source, "RAMP_POINTS"))
    factors = {name: _number(source, name) for name in (
        "WEAK_ACTIVE", "WEAK_ALWAYS_ON", "WEAK_HELD_BACK", "WEAK_UNKNOWN", "LIFT",
        "MARKER", "MARKER_TINT", "SOFT_MARK_TINT", "OVER_TINT", "SUN_TINT",
        "BACKING_WHITE", "BACKING_DARK", "RAMP_STEPS")}
    factors["MARKER"] = int(factors["MARKER"])
    factors["BACKING_WHITE"] = int(factors["BACKING_WHITE"])
    factors["BACKING_DARK"] = int(factors["BACKING_DARK"])
    factors["RAMP_STEPS"] = int(factors["RAMP_STEPS"])
    factors["SUN_HUES"] = _array(source, "SUN_HUES")
    return {
        "themeColours": [colours[i:i + per_theme] for i in range(0, len(colours), per_theme)],
        "rampStops": [stops[i:i + points] for i in range(0, len(stops), points)],
        "factors": factors,
    }


def sources() -> dict:
    source = (REPO / "source" / "data" / "Source.mc").read_text()
    kinds = {name: int(value) for name, value in
             re.findall(r"\b(SOURCE_[A-Z_]+)\s*=\s*(\d+)", source)}

    def predicate(function: str) -> list[int]:
        body = re.search(rf"function {function}\(.*?\{{(.*?)\n    \}}", source, re.S).group(1)
        return sorted(kinds[name] for name in re.findall(r"SOURCE_[A-Z_]+", body))

    return {
        "kinds": kinds,
        "blocks": predicate("usesBlocks"),
        "temperatureRange": predicate("isTemperatureRange"),
        "blocksTopRing": int(_number(source, "BLOCKS_TOP_RING")),
        "blockWindowFloor": _floats((REPO / "source" / "matrix" / "HourBands.mc").read_text(),
                                    "WINDOW_FLOOR"),
    }


def _camel(kind: str) -> str:
    """SOURCE_TIME_OVERLAP -> SourceTimeOverlap, the string id SettingsMenu names it by."""
    return "Source" + "".join(word.capitalize() for word in kind.removeprefix("SOURCE_").split("_"))


def time_ring(kinds: dict[str, int], drawn: dict[str, str]) -> dict:
    source = (REPO / "source" / "data" / "Source.mc").read_text()
    statmap = (REPO / "source" / "matrix" / "StatMap.mc").read_text()
    paint = (REPO / "source" / "render" / "Palette.mc").read_text()

    def hands(kind: str) -> bool:
        text = (REPO / "source-hands" / kind / "HandStyle.mc").read_text()
        return _const(text, "TIME_RING") == "true"

    styles = re.findall(r"SOURCE_[A-Z_]+", _const(source, "TIME_STYLES").split(" as ")[0])
    return {
        "ring": int(_number(statmap, "TIME_RING")),
        "drawn": hands("none"),
        "physical": hands("physical"),
        "styles": [{"value": kinds[name], "label": drawn[_camel(name)]} for name in styles],
        "default": kinds[_const(source, "TIME_DEFAULT")],
        "split": kinds["SOURCE_TIME"],
        "colours": {name.lower(): int(_number(paint, f"TIME_{name}"))
                    for name in ("LIT", "UNLIT")},
        "splitDegrees": _number(paint, "TIME_SPLIT_DEGREES"),
        "splitChroma": _number(paint, "TIME_SPLIT_CHROMA"),
    }


def themes(entries: list[dict], paint: dict) -> list[dict]:
    statmap = (REPO / "source" / "matrix" / "StatMap.mc").read_text()
    ids = _array(statmap, "THEME_IDS")
    labels = {option["value"]: option["label"]
              for option in next(e for e in entries if e["key"] == "theme")["options"]}
    return [{"id": theme_id, "name": labels[theme_id],
             "colours": paint["themeColours"][slot], "ramp": paint["rampStops"][slot]}
            for slot, theme_id in enumerate(ids)]


def property_defaults(path: Path) -> dict[str, int | str]:
    root = ElementTree.parse(path).getroot()
    out: dict[str, int | str] = {}
    for prop in root.findall("property"):
        text = prop.text or ""
        out[prop.attrib["id"]] = int(text) if prop.attrib["type"] == "number" else text
    return out


def build() -> dict:
    base = strings(REPO / "resources" / "strings" / "strings.xml")
    drawn = dict(base)
    entries = settings(base, drawn)
    paint = palette()
    statmap = (REPO / "source" / "matrix" / "StatMap.mc").read_text()
    return {
        "_comment": "Generated by tools/face_schema_export.py from the face's own "
                    "resources and sources. Do not edit.",
        "settings": entries,
        "defaults": property_defaults(REPO / "resources" / "properties.xml"),
        "defaultsDrawn": property_defaults(REPO / "resources" / "properties.xml"),
        "themes": themes(entries, paint),
        "themeCustom": int(_number(statmap, "THEME_CUSTOM")),
        "palette": paint["factors"],
        "sources": sources(),
        "timeRing": time_ring(sources()["kinds"], drawn),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    text = json.dumps(build(), indent=2) + "\n"
    if OUT.exists() and OUT.read_text() == text:
        return 0
    if args.check:
        print(f"stale: {OUT.relative_to(REPO)} - run python3 tools/face_schema_export.py",
              file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
