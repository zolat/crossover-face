"""Config codes for finding how dull a ring colour can be before it stops reading.

Each code is a custom theme whose rings step down in one quantity, outermost ring the
strongest: a chroma ladder at fixed OKLCH lightness for each of a few hues, and a
lightness ladder at fixed chroma. Every ring shows Battery, so each fills to the same
point and only the colour differs; the date is off so nothing crosses the rings.

Push one with ``make push-config TO=watch CODE=...``, unplug, and note the last ring that
still reads as a colour. On the Epix the outer ring tells the time in its own colours, so
read rings 2-5 there. The web configurator's DULL floor is set from what this finds.

    python3 tools/dull_ladder.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mockup import _byte, _fit, _linear_rgb  # noqa: E402
from simctl import configcode  # noqa: E402

BATTERY = 2

#: (name, hue in degrees) for the chroma ladders.
HUES = [("red", 25.0), ("green", 140.0), ("blue", 255.0)]
CHROMA_STEPS = [0.16, 0.12, 0.09, 0.06, 0.03]
# The lightest at which every hue here reaches the top step: blue tops out at 0.148 at 0.72.
CHROMA_LIGHTNESS = 0.68

LIGHTNESS_STEPS = [0.75, 0.65, 0.55, 0.45, 0.35]
LIGHTNESS_CHROMA = 0.12
LIGHTNESS_HUE = ("orange", 55.0)


def colour(L: float, C: float, h: float) -> int:
    r, g, b = (_byte(x) for x in _linear_rgb(L, _fit(L, C, h), h))
    return (r << 16) | (g << 8) | b


def ladder(colours: list[int]) -> str:
    config = dict(configcode.DEFAULTS)
    config.update(theme=configcode.THEME_CUSTOM, showDate=0, customColours=colours, customRamp=[0, 1, 2])
    for key in ("ring1", "ring2", "ring3", "ring4", "ring5"):
        config[key] = BATTERY
    return configcode.encode(config)


def ladders() -> list[tuple[str, list[str], str]]:
    out = []
    for name, hue in HUES:
        colours = [colour(CHROMA_LIGHTNESS, c, hue) for c in CHROMA_STEPS]
        out.append((f"{name}, chroma " + " / ".join(f"{c:.2f}" for c in CHROMA_STEPS),
                    [f"#{c:06x}" for c in colours], ladder(colours)))
    name, hue = LIGHTNESS_HUE
    colours = [colour(L, LIGHTNESS_CHROMA, hue) for L in LIGHTNESS_STEPS]
    out.append((f"{name}, lightness " + " / ".join(f"{L:.2f}" for L in LIGHTNESS_STEPS),
                [f"#{c:06x}" for c in colours], ladder(colours)))
    return out


if __name__ == "__main__":
    for title, hexes, code in ladders():
        print(f"{title}\n  {' '.join(hexes)}\n  {code}\n")
