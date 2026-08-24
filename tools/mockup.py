"""Render dot-matrix watch face mockups for the Instinct Crossover AMOLED.

Iterating on colour through a compile + sideload loop costs a minute a time;
this costs a second. Renders the real geometry at true 390x390, composites it
into Garmin's own device art, and overlays the analogue hands using the exact
polylines the simulator uses — so what you review is the watch, not a grid.

Geometry and hand data come from the installed device files, never hard-coded:
    ~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled/{simulator.json,device.png}

Usage:  python3 tools/mockup.py [outdir]
"""

from __future__ import annotations

import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luminance import measure  # noqa: E402

DEVICE_DIR = os.path.expanduser(
    "~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled"
)

# --- lattice -----------------------------------------------------------------

SIZE = 390
PITCH = 14
DOT = 5
COLS = ROWS = 28
RADIUS = 190
HUB = 21

# --- palette -----------------------------------------------------------------
# Strong = the stat's hue at full read. Weak = the same hue, dark enough to tint
# the field without reading as lit. WEAK_FACTOR and DIM_FACTOR are the two knobs
# the mockups exist to settle.

HUES = [
    ("STEPS", (0xFF, 0x66, 0x00)),
    ("HR", (0xFF, 0x33, 0x22)),
    ("BATTERY", (0x33, 0xCC, 0x55)),
    ("BODY BATT", (0x33, 0x88, 0xFF)),
]

WEAK_FACTOR = 0.18   # unfilled portion, relative to the strong hue
DIM_FACTOR = 0.45    # always-on, applied to both tiers


def scale(rgb: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(c * factor))) for c in rgb)


# --- dot -> stat mapping -----------------------------------------------------
# The seam. Both variants share the lattice; only this differs, which is why
# swapping them in Monkey C is one module.


def band_map(col: int, row: int, x: float, y: float, values: list[float]):
    """Variant A — column picks the stat, y picks the fill."""
    stat = min(len(values) - 1, col * len(values) // COLS)
    waterline = SIZE / 2 + RADIUS - values[stat] * 2 * RADIUS
    return stat, y >= waterline


def ring_map(col: int, row: int, x: float, y: float, values: list[float]):
    """Variant B — radius picks the ring, angle picks the fill."""
    dx, dy = x - SIZE / 2, y - SIZE / 2
    dist = math.hypot(dx, dy)
    thickness = (RADIUS - HUB) / len(values)
    stat = min(len(values) - 1, int((RADIUS - dist) / thickness))
    angle = (math.degrees(math.atan2(dx, -dy)) + 360) % 360
    return stat, angle <= values[stat] * 360


VARIANTS = {"bands": band_map, "rings": ring_map}


# --- rendering ---------------------------------------------------------------


def render(variant: str, values: list[float], *, always_on: bool = False) -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    mapper = VARIANTS[variant]
    centre = SIZE // 2
    half = DOT // 2

    for row in range(ROWS):
        dy = (2 * row - (ROWS - 1)) * (PITCH // 2)
        for col in range(COLS):
            dx = (2 * col - (COLS - 1)) * (PITCH // 2)
            dist_sq = dx * dx + dy * dy
            if dist_sq > RADIUS * RADIUS or dist_sq < HUB * HUB:
                continue

            x, y = centre + dx, centre + dy
            stat, filled = mapper(col, row, x, y, values)
            colour = HUES[stat][1]
            if not filled:
                colour = scale(colour, WEAK_FACTOR)
            if always_on:
                colour = scale(colour, DIM_FACTOR)

            # PIL's rectangle() includes both endpoints, so the far corner is
            # +DOT-1, not +DOT. Getting this wrong drew 6x6 dots against the
            # watch's 5x5 and inflated every luminance reading by ~44%.
            left, top = x - half, y - half
            draw.rectangle(
                [left, top, left + DOT - 1, top + DOT - 1], fill=colour
            )
    return img


# --- device compositing ------------------------------------------------------


def _hand_polygon(hand: dict, reach_scale: float = 1.0):
    """Rotate a hand polyline from simulator.json into screen coordinates.

    The polylines are authored pointing +y (6 o'clock); `position` is degrees
    clockwise from 12. So the rotation applied is position - 180.
    """
    rot = math.radians(hand["position"] - 180.0)
    cos_r, sin_r = math.cos(rot), math.sin(rot)
    pts = []
    for p in hand["polyline"]:
        x, y = p["x"], p["y"] * reach_scale
        pts.append((x * cos_r - y * sin_r, x * sin_r + y * cos_r))
    return pts


def composite(face: Image.Image, *, hands: bool = True) -> Image.Image:
    """Drop a rendered face into the device art, optionally with the hands."""
    with open(os.path.join(DEVICE_DIR, "simulator.json")) as fh:
        sim = json.load(fh)
    device = Image.open(os.path.join(DEVICE_DIR, "device.png")).convert("RGBA")

    loc = sim["display"]["location"]
    ox, oy = loc["x"], loc["y"]

    # The display is round: mask the square render so the bezel shows through
    # instead of being covered by black corners that do not exist on hardware.
    mask = Image.new("L", (loc["width"], loc["height"]), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, loc["width"] - 1, loc["height"] - 1], fill=255)

    shot = device.copy()
    shot.paste(face.convert("RGBA"), (ox, oy), mask)

    if hands and "analogHands" in sim:
        ah = sim["analogHands"]
        colours = ah["colors"]
        draw = ImageDraw.Draw(shot)
        cx, cy = ox + loc["width"] / 2, oy + loc["height"] / 2

        def rgb(key):
            return tuple(int(colours[key][i : i + 2], 16) for i in (0, 2, 4))

        for name, fill_key, outline_key, width_key in (
            ("hour", "hourHand", "hourOutline", "hourHandOutlineWidth"),
            ("minute", "minuteHand", "minuteOutline", "minuteHandOutlineWidth"),
        ):
            pts = [(cx + px, cy + py) for px, py in _hand_polygon(ah[name])]
            draw.polygon(pts, fill=rgb(fill_key), outline=rgb(outline_key),
                         width=ah[width_key])

        draw.ellipse(
            [cx - ah["baseRadius"], cy - ah["baseRadius"],
             cx + ah["baseRadius"], cy + ah["baseRadius"]],
            fill=rgb("baseCircle"),
        )
        draw.ellipse(
            [cx - ah["foregroundRadius"], cy - ah["foregroundRadius"],
             cx + ah["foregroundRadius"], cy + ah["foregroundRadius"]],
            fill=rgb("foregroundCircle"),
        )
    return shot.convert("RGB")


# --- sheets ------------------------------------------------------------------


def _font(size: int):
    for path in (
        "/System/Library/Fonts/SFNSMono.ttf",
        "/System/Library/Fonts/Supplemental/Menlo.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def sheet(panels: list[tuple[str, Image.Image]], title: str) -> Image.Image:
    pad, header, caption = 24, 64, 40
    pw, ph = panels[0][1].size
    width = pad + len(panels) * (pw + pad)
    height = header + ph + caption + pad

    out = Image.new("RGB", (width, height), (18, 18, 20))
    draw = ImageDraw.Draw(out)
    draw.text((pad, pad), title, fill=(235, 235, 235), font=_font(26))

    for i, (label, img) in enumerate(panels):
        x = pad + i * (pw + pad)
        out.paste(img, (x, header))
        draw.text((x, header + ph + 10), label, fill=(190, 190, 195), font=_font(19))
    return out


def main(outdir: str = "build/mockups") -> int:
    os.makedirs(outdir, exist_ok=True)
    values = [0.68, 0.55, 0.82, 0.40]   # steps, hr, battery, body battery
    written = []

    # 1. Layout comparison, hands on, identical palette and values.
    panels = []
    for variant in ("bands", "rings"):
        face = render(variant, values)
        lum = measure(face) * 100
        panels.append((f"{variant.upper()}   luminance {lum:.2f}%", composite(face)))
    path = os.path.join(outdir, "01-layout-bands-vs-rings.png")
    sheet(panels, "Variant A vs B — same palette, same values, hands overlaid").save(path)
    written.append(path)

    # 2. Weak-tier sweep on each layout: how dark before the hues stop reading.
    global WEAK_FACTOR
    original = WEAK_FACTOR
    for variant in ("bands", "rings"):
        panels = []
        for factor in (0.10, 0.18, 0.30):
            WEAK_FACTOR = factor
            face = render(variant, values)
            panels.append((f"weak {factor:.2f}   lum {measure(face) * 100:.2f}%",
                           composite(face)))
        WEAK_FACTOR = original
        path = os.path.join(outdir, f"02-weak-tier-{variant}.png")
        sheet(panels, f"{variant.upper()} — unfilled-tier strength").save(path)
        written.append(path)

    # 3. Active vs always-on: proof the modes read as the same image.
    for variant in ("bands", "rings"):
        panels = []
        for label, always_on in (("ACTIVE", False), ("ALWAYS-ON", True)):
            face = render(variant, values, always_on=always_on)
            panels.append((f"{label}   luminance {measure(face) * 100:.2f}%",
                           composite(face)))
        path = os.path.join(outdir, f"03-modes-{variant}.png")
        sheet(panels, f"{variant.upper()} — active vs always-on").save(path)
        written.append(path)

    # 4. Worst case: every stat at 100%, the frame the luminance test guards.
    panels = []
    for variant in ("bands", "rings"):
        face = render(variant, [1.0] * 4, always_on=True)
        panels.append((f"{variant.upper()} always-on   lum {measure(face) * 100:.2f}%",
                       composite(face)))
    path = os.path.join(outdir, "04-worst-case.png")
    sheet(panels, "Worst case — every stat 100%, always-on").save(path)
    written.append(path)

    for p in written:
        print(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(*sys.argv[1:]))
