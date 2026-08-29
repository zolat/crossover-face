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
PITCH = 10
DOT = 5
COLS = ROWS = 38
RADIUS = 190
HUB = 21

# --- palette -----------------------------------------------------------------
# Strong = the stat's hue at full read. Weak = the same hue, dark enough to tint
# the field without reading as lit. WEAK_FACTOR and DIM_FACTOR are the two knobs
# the mockups exist to settle.

# Source.Kind order, matching source/data/Source.mc
SOURCES = [
    ("Steps", (0xFF, 0x66, 0x00)),
    ("Heart rate", (0xFF, 0x33, 0x22)),
    ("Battery", (0x33, 0xCC, 0x55)),
    ("Body Battery", (0x33, 0x88, 0xFF)),
    ("Temperature", (0xFF, 0xAA, 0x00)),
    ("Rain", (0x00, 0xCC, 0xDD)),
    ("Intensity minutes", (0xCC, 0x44, 0xFF)),
    ("Seconds", (0xCC, 0xCC, 0xCC)),
    ("Off", (0x44, 0x44, 0x44)),
]
SOURCE_TEMPERATURE = 4

# Placeholder theme: rings alternate between navy and olive. Mirrors
# Palette.THEME in Monkey C.
THEME = [(0xE8, 0x79, 0xF9), (0xB8, 0xD6, 0x4B), (0x7F, 0xD4, 0xFF), (0xFF, 0x6B, 0x5B)]

# Mirrors Palette.MARKER: the current temperature called out on the range it
# sits in. Near-white, carrying a third of its own band's colour — what makes a
# mark read is that it is the only solid dot on a field of crosses, not that it
# is white, so the hue can settle into the palette. Awake only.
MARKER = (0xFF, 0xFF, 0xFF)
MARKER_TINT = 0.35

# Mirrors Palette.OVER_TINT: the tier a ring draws once it is past a goal it can
# beat. "Stronger" cannot be a brightening — LIFT is 1.0 precisely because these
# hues already sit at a full channel — so it is the band mixed toward white, the
# same move the mark makes and stopping well short of it. Awake only.
OVER_TINT = 0.70


def marker_colour(ring: int):
    return mix(MARKER, THEME[ring % len(THEME)], MARKER_TINT)


def over_colour(ring: int):
    return mix(MARKER, THEME[ring % len(THEME)], OVER_TINT)


def marker_half(ring: int) -> float:
    """Half-width of a mark's window on this ring. Mirrors DotGrid.markerWidths.

    One constant cannot serve every ring: a lattice row is 0.026 of a turn on
    the outermost but 0.076 of one on the innermost, where an outer-tuned
    window falls between dots and the mark disappears.
    """
    thickness = (RADIUS - HUB) / RINGS
    inner = RADIUS - (ring + 1) * thickness
    return PITCH / (2.0 * 2.0 * math.pi * inner)


def marked(position: float, mark: float, half: float) -> bool:
    """Is this dot inside the mark's window? Wraps, as StatMap.isLit does."""
    lo, hi = mark - half, mark + half
    if hi - lo >= 1.0:
        return True
    if lo < 0.0:
        lo += 1.0
    if hi >= 1.0:
        hi -= 1.0
    return (position >= lo or position <= hi) if lo > hi \
        else (lo <= position <= hi)


def mark_middle(ring: int) -> float:
    """The across-the-ring middle. Mirrors DotGrid.markMiddles."""
    thickness = (RADIUS - HUB) / RINGS
    mid = RADIUS - (ring + 0.5) * thickness
    return mid * mid


def marked_dot(ring: int, mark: float):
    """The single dot a mark lands on, as (dx, dy), or None.

    Mirrors DotGrid.markedDot: of the dots inside the mark's window, the one
    nearest the middle of its ring. A mark is one dot rather than a row of
    them — a row of crosses reads as a bumpy band, and on a square lattice a
    radial run of them staggers instead of lining up.
    """
    if mark is None or mark < 0.0:
        return None
    half, middle = marker_half(ring), mark_middle(ring)
    best, best_off = None, None
    for row in range(ROWS):
        dy = (2 * row - (ROWS - 1)) * (PITCH // 2)
        for col in range(COLS):
            dx = (2 * col - (COLS - 1)) * (PITCH // 2)
            d = dx * dx + dy * dy
            if d > RADIUS * RADIUS or d < HUB * HUB:
                continue
            r, position = ring_map(dx, dy)
            if r != ring or not marked(position, mark, half):
                continue
            off = abs(d - middle)
            if best_off is None or off < best_off:
                best, best_off = (dx, dy), off
    return best


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def temperature_colour(fraction: float):
    """Ice -> orchid -> rust, mirroring Palette.build()."""
    if fraction <= 0.5:
        return mix(THEME[2], THEME[0], fraction * 2.0)
    return mix(THEME[0], THEME[3], (fraction - 0.5) * 2.0)

# Dot shape. A square is the densest; a cross lights 9 of the 25 pixels a
# square would, which reads as finer texture and costs proportionally less
# luminance. Mirrors DotGrid.SHAPE in Monkey C.
DOT_SHAPE = "cross"    # square | cross | cross-thick

# Mirrors Palette.mc: awake carries the brighter unfilled tier, and always-on
# lifts the colours rather than dimming them, because the panel is already
# dimmed by the system in that mode.
WEAK_ACTIVE = 0.55
WEAK_ALWAYS_ON = 0.45
LIFT = 1.0

# Always-on with the fills held back draws nothing lit at all, so the unfilled
# tier is the whole image rather than a backdrop to it. It matches the awake
# field deliberately, so the background does not change brightness on a raise.
WEAK_HELD_BACK = WEAK_ACTIVE


def scale(rgb: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(c * factor))) for c in rgb)


# --- dot -> stat mapping -----------------------------------------------------
# The seam. Mirrors StatMap.ringFor and StatMap.positionOf: a dot's radius
# picks its ring, and its angle is its position along it.


RINGS = 4


def ring_map(dx: int, dy: int):
    """Radius picks the ring, position runs clockwise from 12."""
    dist = math.hypot(dx, dy)
    thickness = (RADIUS - HUB) / RINGS
    ring = min(RINGS - 1, max(0, int((RADIUS - dist) / thickness)))
    return ring, ((math.degrees(math.atan2(dx, -dy)) + 360) % 360) / 360.0


# --- analogue hands ----------------------------------------------------------
# Mirrors source/matrix/HandBacking.mc. Geometry from the device simulator.json.

HAND_HALF_WIDTH = 14
HAND_COUNTERWEIGHT = 46
HOUR_REACH = 131
MINUTE_REACH = 176
HAND_MARGIN = 0


def hand_axes(hour: int, minute: int):
    """Unit vectors for both hands at a given time, screen y downward."""
    out = []
    for degrees in (((hour % 12) * 30.0) + minute * 0.5, minute * 6.0):
        r = math.radians(degrees)
        out.append((math.sin(r), -math.cos(r)))
    return out


def hand_covers(dx: float, dy: float, axes) -> bool:
    for (ux, uy), reach in zip(axes, (HOUR_REACH, MINUTE_REACH)):
        along = dx * ux + dy * uy
        if along > reach + HAND_MARGIN or along < -(HAND_COUNTERWEIGHT + HAND_MARGIN):
            continue
        if abs(dx * -uy + dy * ux) <= HAND_HALF_WIDTH + HAND_MARGIN:
            return True
    return False


# --- rendering ---------------------------------------------------------------


def render(spans, *, assign=(0, 1, 2, 3), always_on: bool = False,
           held_back: bool = False,
           backing: tuple[int, int, int] | None = None,
           at_time: tuple[int, int] = (10, 9),
           drift: tuple[int, int] = (0, 0), marks=None,
           overs=None, rotate: bool = True) -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Which dot each ring marks, worked out once rather than per dot.
    mark_dots = {}
    if marks is not None and not always_on:
        for r in range(RINGS):
            at = marked_dot(r, marks[r])
            if at is not None:
                mark_dots[r] = at
    axes = hand_axes(*at_time) if backing else None
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
            marked_here = False
            if axes is not None and hand_covers(dx, dy, axes):
                colour = backing
            else:
                ring, position = ring_map(dx, dy)
                # Awake only, and it outranks the fill: the mark has to be
                # legible whether or not now falls inside today's range.
                if not always_on and mark_dots.get(ring) == (dx, dy):
                    colour = marker_colour(ring)
                    marked_here = True
                else:
                    start, end = spans[ring]
                    lit = start <= position <= end
                    source = assign[ring]
                    over = bool(overs and overs[ring]) and not always_on
                    if lit and source == SOURCE_TEMPERATURE:
                        colour = temperature_colour(position)
                    elif lit and over:
                        # Past the goal the span is the second lap, so the
                        # filled tier becomes "gone past it" — mirrors the
                        # per-ring swap in MatrixRenderer.
                        colour = over_colour(ring)
                    else:
                        colour = THEME[ring % len(THEME)]
                    if always_on:
                        colour = scale(colour, LIFT)
                    if not lit:
                        if over:
                            # The ring is full either way, so its unfilled tier
                            # is free to mean "goal met" — no dimming at all.
                            weak = 1.0
                        elif held_back:
                            weak = WEAK_HELD_BACK
                        elif always_on:
                            weak = WEAK_ALWAYS_ON
                        else:
                            weak = WEAK_ACTIVE
                        colour = scale(colour, weak)

            # PIL's rectangle() includes both endpoints, so the far corner is
            # +DOT-1, not +DOT. Getting this wrong drew 6x6 dots against the
            # watch's 5x5 and inflated every luminance reading by ~44%.
            left, top = x - half + drift[0], y - half + drift[1]
            if marked_here:
                # Filled, not a cross - mirrors MatrixRenderer. On a field of
                # thin crosses only a solid block reads as a mark.
                draw.rectangle([left, top, left + DOT - 1, top + DOT - 1],
                               fill=colour)
                continue
            # Mirrors StatMap.Rotation: turned to follow the ring, or upright.
            arm = ARMS[orientation_at(dx, dy)] if rotate else ARMS[0]
            draw_dot(draw, left, top, colour, arm)
    return img


# Mirrors DotGrid.ARMS: half-arm offsets for each cross orientation.
ARMS = [(2, 0, 0, 2), (2, 1, -1, 2), (2, 2, -2, 2), (1, 2, -2, 1)]


def orientation_at(dx: int, dy: int) -> int:
    """Which ARMS entry aligns a cross with the circle it sits on."""
    return int(math.degrees(math.atan2(dy, dx)) / 22.5 + 0.5) % len(ARMS)


def draw_dot(draw, left: int, top: int, colour, arm=ARMS[0]) -> None:
    """One dot: two strokes through its centre, at the given orientation."""
    x, y = left + DOT // 2, top + DOT // 2
    draw.line([x - arm[0], y - arm[1], x + arm[0], y + arm[1]], fill=colour)
    draw.line([x - arm[2], y - arm[3], x + arm[2], y + arm[3]], fill=colour)


# --- device compositing ------------------------------------------------------


def _hand_polygon(hand: dict, reach_scale: float = 1.0, degrees: float | None = None):
    """Rotate a hand polyline from simulator.json into screen coordinates.

    The polylines are authored pointing +y (6 o'clock); `position` is degrees
    clockwise from 12. So the rotation applied is position - 180.
    """
    rot = math.radians((hand["position"] if degrees is None else degrees) - 180.0)
    cos_r, sin_r = math.cos(rot), math.sin(rot)
    pts = []
    for p in hand["polyline"]:
        x, y = p["x"], p["y"] * reach_scale
        pts.append((x * cos_r - y * sin_r, x * sin_r + y * cos_r))
    return pts


def composite(face: Image.Image, *, hands: bool = True,
              at_time: tuple[int, int] | None = None) -> Image.Image:
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

        angles = None
        if at_time is not None:
            h, m = at_time
            angles = {"hour": ((h % 12) * 30.0) + m * 0.5, "minute": m * 6.0}

        for name, fill_key, outline_key, width_key in (
            ("hour", "hourHand", "hourOutline", "hourHandOutlineWidth"),
            ("minute", "minuteHand", "minuteOutline", "minuteHandOutlineWidth"),
        ):
            deg = angles[name] if angles else None
            pts = [(cx + px, cy + py)
                   for px, py in _hand_polygon(ah[name], degrees=deg)]
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
    # steps, heart rate, battery, body battery — as levels
    values = [(0.0, 0.68), (0.0, 0.55), (0.0, 0.82), (0.0, 0.40)]
    written = []

    # 1. Dot rotation: the same face with its crosses turned and upright.
    panels = []
    for label, rotate in (("FOLLOW THE RINGS", True), ("UPRIGHT", False)):
        face = render(values, rotate=rotate)
        panels.append((f"{label}   luminance {measure(face) * 100:.2f}%",
                       composite(face)))
    path = os.path.join(outdir, "01-rotation.png")
    sheet(panels, "Dot rotation — each cross turned to follow its ring, "
                  "or left upright").save(path)
    written.append(path)

    # 2. Weak-tier sweep: how dark before the hues stop reading.
    global WEAK_ACTIVE
    original = WEAK_ACTIVE
    panels = []
    for factor in (0.10, 0.18, 0.30):
        globals()['WEAK_ACTIVE'] = factor
        face = render(values)
        panels.append((f"weak {factor:.2f}   lum {measure(face) * 100:.2f}%",
                       composite(face)))
    WEAK_ACTIVE = original
    path = os.path.join(outdir, "02-weak-tier.png")
    sheet(panels, "Unfilled-tier strength").save(path)
    written.append(path)

    # 3. Active vs always-on: proof the modes read as the same image.
    panels = []
    for label, always_on in (("ACTIVE", False), ("ALWAYS-ON", True)):
        face = render(values, always_on=always_on)
        panels.append((f"{label}   luminance {measure(face) * 100:.2f}%",
                       composite(face)))
    path = os.path.join(outdir, "03-modes.png")
    sheet(panels, "Active vs always-on").save(path)
    written.append(path)

    # 4. Always-on with the fills held back: the data appears when you look.
    #    A span of (2, 2) can never contain a position, which is how the face
    #    itself hides them — no branch in the render loop, just a span that
    #    nothing falls inside.
    nothing = [(2.0, 2.0)] * 4
    panels = []
    for label, spans in (("ALWAYS-ON, data shown", values),
                         ("ALWAYS-ON, data hidden", nothing)):
        held = spans is nothing
        face = render(spans, always_on=True, held_back=held)
        panels.append((f"{label}   lum {measure(face) * 100:.2f}%",
                       composite(face)))
    path = os.path.join(outdir, "06-always-on-fill.png")
    sheet(panels, "Always-on with and without the fills").save(path)
    written.append(path)

    # 5. Worst case: every stat at 100%, the frame the luminance test guards.
    face = render([(0.0, 1.0)] * 4, always_on=True)
    path = os.path.join(outdir, "04-worst-case.png")
    sheet([(f"ALWAYS-ON   lum {measure(face) * 100:.2f}%", composite(face))],
          "Worst case — every stat 100%, always-on").save(path)
    written.append(path)

    # 6. Hand backing — the awake-only option, hands drawn at system time.
    when = (10, 9)
    panels = []
    for label, backing in (("OFF", None), ("WHITE", (255, 255, 255)),
                           ("DARK", (16, 16, 16))):
        face = render(values, backing=backing, at_time=when)
        panels.append((f"{label}   luminance {measure(face) * 100:.2f}%",
                       composite(face, at_time=when)))
    path = os.path.join(outdir, "05-hand-backing.png")
    sheet(panels, "Behind hands — awake only, hands held at system time").save(path)
    written.append(path)

    # 7. Rings assigned to weather — temperature is a range, not a level, and
    #    the mark says where in that range now falls.
    weather_assign = (4, 5, 2, 0)          # temperature, rain, battery, steps
    weather_spans = [(11 / 60, 22 / 60), (0.0, 0.35), (0.0, 0.82), (0.0, 0.68)]
    NO_MARK = -1.0
    weather_marks = [17 / 60, NO_MARK, NO_MARK, NO_MARK]   # 17C right now
    face = render(weather_spans, assign=weather_assign, marks=weather_marks)
    path = os.path.join(outdir, "07-weather-assignment.png")
    sheet([(f"WEATHER   lum {measure(face) * 100:.2f}%", composite(face))],
          "Ring 1 = temperature 11-22C on a 0-60 scale, "
          "white mark = 17C now").save(path)
    written.append(path)

    # 8. Past the goal — steps on ring 1, read as a second lap. Mirrors
    #    Source.goal()/over() and StatMap.markers(): the span stops describing
    #    the fill and describes the overflow, the ring's two tiers become
    #    "goal met" and "gone past it", and the solid dot is the lap's
    #    waterline. A completed lap carries no dot — its waterline is the
    #    ring's own edge, so there is nothing left to point at.
    def goal_lap(reading: float):
        """(span, over, mark) for a goal reading. Mirrors Source.goal()."""
        if reading <= 1.0:
            return (0.0, reading), False, NO_MARK
        end = 1.0 if reading >= 2.0 else reading - 1.0
        return (0.0, end), True, (NO_MARK if end >= 1.0 else end)

    def goal_face(reading: float):
        span, over, mark = goal_lap(reading)
        return render([span] + values[1:],
                      marks=[mark, NO_MARK, NO_MARK, NO_MARK],
                      overs=[over, False, False, False])

    panels = []
    for reading in (0.34, 1.0, 1.34, 2.5):
        face = goal_face(reading)
        panels.append((f"steps {reading * 100:.0f}%   "
                       f"lum {measure(face) * 100:.2f}%", composite(face)))
    path = os.path.join(outdir, "08-over-goal.png")
    sheet(panels, "Ring 1 = steps past its goal — the overflow runs a second "
                  "lap, dot = the waterline").save(path)
    written.append(path)

    # 9. Burn-in drift: how long any one pixel stays lit over a full cycle.
    phases = [(-2, -2), (3, 3), (3, -2), (-2, 3)]
    duty = {}
    for dx, dy in phases:
        img = render([(0.0, 1.0)] * 4, drift=(dx, dy))
        px = img.load()
        for y in range(SIZE):
            for x in range(SIZE):
                if px[x, y] != (0, 0, 0):
                    duty[(x, y)] = duty.get((x, y), 0) + 1
    worst = max(duty.values()) if duty else 0
    print(f"burn-in drift: {len(duty)} pixels touched, "
          f"worst duty cycle {worst}/{len(phases)} phases "
          f"({worst / len(phases) * 100:.0f}%)")

    for p in written:
        print(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(*sys.argv[1:]))
