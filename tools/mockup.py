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

DEVICES_DIR = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")

# --- lattice -----------------------------------------------------------------
# PITCH and DOT are shared by every watch: Drift's offsets are tuned to them,
# and holding them fixed is what makes the luminance budget scale-invariant.
# Everything else moves with the screen, mirroring source-lattice/*/Lattice.mc
# one table per file. Any change there has to land here too.

PITCH = 10
DOT = 5

LATTICES = {
    #                 SIZE COLS RADIUS HUB  halfW  cw  hour minute  drawn
    "instinctcrossoveramoled": (390, 38, 190, 21, 14, 46, 131, 176, False),
    "epix2pro42mm":            (390, 38, 190, 21, 14, 46, 131, 176, True),
    "epix2":                   (416, 40, 203, 22, 15, 49, 140, 188, True),
    "epix2pro47mm":            (416, 40, 203, 22, 15, 49, 140, 188, True),
    "epix2pro51mm":            (454, 42, 210, 23, 15, 51, 145, 195, True),
}
DEFAULT_DEVICE = "instinctcrossoveramoled"

DEVICE = DEFAULT_DEVICE
DEVICE_DIR = os.path.join(DEVICES_DIR, DEFAULT_DEVICE)
SIZE = 390
COLS = ROWS = 38
RADIUS = 190
HUB = 21


def use_device(name: str) -> None:
    """Point every lattice and hand constant at one watch.

    The Monkey C picks its Lattice at compile time from the jungle; there is no
    such seam in a script, so the module's globals are rebound instead. Same
    numbers, same source of truth - see the note on LATTICES.
    """
    global DEVICE, DEVICE_DIR, SIZE, COLS, ROWS, RADIUS, HUB
    global HAND_HALF_WIDTH, HAND_COUNTERWEIGHT, HOUR_REACH, MINUTE_REACH
    global DRAWN_HANDS
    if name not in LATTICES:
        raise SystemExit(f"unknown device {name!r}; known: "
                         + ", ".join(sorted(LATTICES)))
    (SIZE, COLS, RADIUS, HUB, HAND_HALF_WIDTH, HAND_COUNTERWEIGHT,
     HOUR_REACH, MINUTE_REACH, DRAWN_HANDS) = LATTICES[name]
    ROWS = COLS
    DEVICE = name
    DEVICE_DIR = os.path.join(DEVICES_DIR, name)

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
    ("Rain, next 12h", (0x00, 0x88, 0xCC)),
]
SOURCE_TEMPERATURE = 4
SOURCE_RAIN_HOURS = 9

# Ring colours per theme, outermost first, and which three of each theme's four
# the temperature ramp runs through as cold, mid and hot. Mirrors Palette.THEMES
# and Palette.RAMP_STOPS in Monkey C — flat over there because a const array of
# arrays comes back empty on the watch, named here because nothing forces it.
#
# Terrain is orchid, moss, ice, rust. Activity is the accent colours the watch
# itself uses, read off the peak-chroma pixel of the device's own swatches in
# ~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled/{nwidget,D_list_select}_*.png
# rather than guessed: gold, blue, green, red.
#
# Each theme's order maximises the CIELAB distance between rings that sit next
# to each other — 93 for Terrain, 118 for Activity — because neighbours blurring
# together, not the set average, decides whether two rings can be told apart.
THEMES = {
    "terrain": [(0xE8, 0x79, 0xF9), (0xB8, 0xD6, 0x4B),
                (0x7F, 0xD4, 0xFF), (0xFF, 0x6B, 0x5B)],
    "activity": [(0xE5, 0x9A, 0x0A), (0x1F, 0x8F, 0xFE),
                 (0x6D, 0xC5, 0x4F), (0xFE, 0x46, 0x46)],
    # Not a shipping theme: Activity with the watch's *other* blue, #1852E6, so
    # the choice between the two is made on a rendered face and not on a hex.
    "activity-navy": [(0xE5, 0x9A, 0x0A), (0x18, 0x52, 0xE6),
                      (0x6D, 0xC5, 0x4F), (0xFE, 0x46, 0x46)],
    # Duotones: two hues alternating, so every ring's neighbour is a hue flip
    # and rings 1 and 3 -- which never touch -- may share a colour. Slots still
    # run outermost first; they just repeat. The repeat is exact rather than
    # the same hue at two lightnesses, because a dimmed A collides with A's own
    # unfilled tier -- see the duotone note in Palette.mc.
    "frost": [(0x5C, 0xD9, 0xF0), (0xF4, 0x5B, 0xD8)] * 2,
    "lagoon": [(0x2F, 0xD9, 0xC5), (0xE5, 0x9A, 0x0A)] * 2,
    "nocturne": [(0x8E, 0x7B, 0xFF), (0xFF, 0x6B, 0x5B)] * 2,
    # After the Seiko Alpinist: a dark sunburst green dial under gold indices.
    # Not transcribed -- that dial is a surface lit from outside and this face
    # emits its own light on black, so the dial's ~#1E3A2F falls below the
    # unfilled tier and is not there at all. The relationship carries over,
    # the values do not. See the Alpinist note in Palette.mc for what the
    # green and gold had to give up to separate at all.
    "alpinist": [(0x44, 0xC2, 0x65), (0xFF, 0x99, 0x00)] * 2,
    # The whole watch rather than the dial: strap, dial, indices, lume. The
    # strap is a brick and not a leather brown because brown is what gold
    # looks like unlit -- see the Alpinist 4 note in Palette.mc. White goes on
    # the innermost ring, which holds 92 dots against the outermost's 436;
    # that placement is what keeps a white-bearing theme inside the budget.
    "alpinist4": [(0xC7, 0x5A, 0x5A), (0x44, 0xC2, 0x65),
                  (0xFF, 0x99, 0x00), (0xF5, 0xF5, 0xF5)],
}

# Which three of a theme's four slots the temperature ramp runs through, as
# cold, mid and hot. A mid of RAMP_LINEAR means the theme has only two hues to
# ramp through, so the middle is the midpoint of cold and hot rather than a
# colour of its own -- see temperature_colour and Palette.RAMP_LINEAR.
RAMP_LINEAR = -1

RAMP_STOPS = {
    "terrain": (2, 0, 3),           # ice -> orchid -> rust
    "activity": (1, 0, 3),          # blue -> gold -> red
    "activity-navy": (1, 0, 3),
    "frost": (0, RAMP_LINEAR, 1),      # cyan -> magenta
    "lagoon": (0, RAMP_LINEAR, 1),     # teal -> gold
    "nocturne": (0, RAMP_LINEAR, 1),   # indigo -> rust
    "alpinist": (0, RAMP_LINEAR, 1),   # green -> gold
    "alpinist4": (1, 2, 0),            # green -> gold -> brick
}

THEME_NAME = "terrain"
THEME = THEMES[THEME_NAME]


def use_theme(name: str) -> None:
    """Swap the theme every colour here is derived from.

    Same move as the WEAK_ACTIVE sweep in main(): this file mirrors Monkey C
    module constants, so varying one means assigning to the global.
    """
    globals()["THEME_NAME"] = name
    globals()["THEME"] = THEMES[name]

# Mirrors Palette.MARKER: the current temperature called out on the range it
# sits in. Carrying rather more than half its own band's colour — what makes a
# mark read is that it is the only solid dot on a field of crosses, not that it
# is white, so the hue can settle into the palette. Awake only.
#
# Tinted rather than dimmed: scaling drags the colour off the band-to-white line
# and collides with the over tier the waterline dot sits on. See Palette.mc.
MARKER = (0xFF, 0xFF, 0xFF)
MARKER_TINT = 0.55

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
    """Cold -> mid -> hot through the theme's own colours.

    Mirrors Palette.build(), including that the stops are indices into the
    theme rather than colours of their own: a ramp stop *is* a ring colour, and
    writing the value a second time is how the two drift apart.
    """
    cold_i, mid_i, hot_i = RAMP_STOPS[THEME_NAME]
    cold, hot = THEME[cold_i], THEME[hot_i]
    # A two-hue theme has no third colour to turn through, so its middle is
    # simply the midpoint -- which makes the two segments one straight run.
    mid = mix(cold, hot, 0.5) if mid_i == RAMP_LINEAR else THEME[mid_i]
    if fraction <= 0.5:
        return mix(cold, mid, fraction * 2.0)
    return mix(mid, hot, (fraction - 0.5) * 2.0)

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

# An hour the forecast said nothing about. Darker than the unfilled tier, so
# "no data" does not read as "forecast says dry" — and so luminance can only
# fall. Mirrors Palette.WEAK_UNKNOWN.
WEAK_UNKNOWN = 0.25

# The hourly forecast's geometry. Mirrors HourBands.mc: twelve blocks round the
# ring, a gutter after each, three radial sub-bands across the ring's thickness.
HOURS = 12
HOUR_BANDS = 3
HOUR_BLOCK_DEGREES = 22.5
HOUR_FILL = HOUR_BLOCK_DEGREES / (360.0 / HOURS)


def hour_block(position: float) -> int:
    return min(HOURS - 1, int(position * HOURS))


def inside_block(position: float) -> bool:
    """False in the gutter after the block. Mirrors HourBands.insideBlock."""
    at = position * HOURS
    return (at - int(at)) < HOUR_FILL


def band_edge(ring: int, tier: int) -> float:
    """Squared outer radius of a sub-band. Mirrors DotGrid.bandEdges: integer
    thickness, matching the edges that decide a dot's ring, and the top band
    takes the ring's own outer edge rather than stacking three steps."""
    thickness = (RADIUS - HUB) // RINGS
    step = thickness // HOUR_BANDS
    inner = RADIUS - (ring + 1) * thickness
    edge = inner + thickness if tier == HOUR_BANDS else inner + tier * step
    return edge * edge


def hourly_colour(ring, position, dist_sq, tiers, always_on, held_back):
    """One dot of a forecast ring. Mirrors MatrixRenderer's second inner loop.

    `tiers` is twelve entries, each 0-HOUR_BANDS or None for an hour the
    forecast said nothing about."""
    colour = THEME[ring % len(THEME)]
    if always_on:
        colour = scale(colour, LIFT)
    weak = WEAK_HELD_BACK if held_back else (
        WEAK_ALWAYS_ON if always_on else WEAK_ACTIVE)
    if held_back or tiers is None:
        # Held back, every hour reads known and dry — never unknown, which
        # would draw the dim tier right round the ring and put data in the one
        # mode whose whole purpose is to carry none.
        return scale(colour, weak)
    if not inside_block(position):
        return scale(colour, weak)
    tier = tiers[hour_block(position)]
    if tier is None:
        return scale(colour, WEAK_UNKNOWN)
    if tier > 0 and dist_sq <= band_edge(ring, tier):
        return colour
    return scale(colour, weak)


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

#: Whether this watch's hands are the face's to draw. Set by use_device().
DRAWN_HANDS = False

#: What handAt()'s three answers paint, mirroring source-hands/*/HandStyle.mc.
NO_HAND, HOUR, MINUTE = 0, 1, 2
HAND_HOUR = (0xFF, 0xFF, 0xFF)
HAND_MINUTE = (0x80, 0x80, 0x80)


def hand_colours(backing):
    """Mirrors HandStyle.coloursFor: one backing colour, or a real pair."""
    if DRAWN_HANDS and backing == (0xFF, 0xFF, 0xFF):
        return (None, HAND_HOUR, HAND_MINUTE)
    return (None, backing, backing)


def hand_axes(hour: int, minute: int):
    """Unit vectors for both hands at a given time, screen y downward."""
    out = []
    for degrees in (((hour % 12) * 30.0) + minute * 0.5, minute * 6.0):
        r = math.radians(degrees)
        out.append((math.sin(r), -math.cos(r)))
    return out


def hand_at(dx: float, dy: float, axes) -> int:
    """Which hand covers this dot: NO_HAND, HOUR or MINUTE.

    Mirrors HandBacking.handAt, minute first so it wins where the two cross.
    ``axes`` arrives hour-first, as hand_axes returns it.
    """
    for hand, index, reach in ((MINUTE, 1, MINUTE_REACH), (HOUR, 0, HOUR_REACH)):
        ux, uy = axes[index]
        along = dx * ux + dy * uy
        if along > reach + HAND_MARGIN or along < -(HAND_COUNTERWEIGHT + HAND_MARGIN):
            continue
        if abs(dx * -uy + dy * ux) <= HAND_HALF_WIDTH + HAND_MARGIN:
            return hand
    return NO_HAND


# --- rendering ---------------------------------------------------------------


def render(spans, *, assign=(0, 1, 2, 3), always_on: bool = False,
           held_back: bool = False, hourly=None,
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
    hands = hand_colours(backing) if backing else None
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
            hand = hand_at(dx, dy, axes) if axes is not None else NO_HAND
            if hand != NO_HAND:
                colour = hands[hand]
            else:
                ring, position = ring_map(dx, dy)
                # Awake only, and it outranks the fill: the mark has to be
                # legible whether or not now falls inside today's range.
                if not always_on and mark_dots.get(ring) == (dx, dy):
                    colour = marker_colour(ring)
                    marked_here = True
                else:
                    source = assign[ring]
                    if source == SOURCE_RAIN_HOURS:
                        # Its own path, mirroring the renderer's own loop: the
                        # forecast reads a radius as well as an angle, so it
                        # cannot be said with a span.
                        colour = hourly_colour(
                            ring, position, dist_sq,
                            (hourly or {}).get(ring), always_on, held_back)
                        arm = ARMS[orientation_at(dx, dy)] if rotate \
                            else ARMS[0]
                        draw_dot(draw, x - half + drift[0],
                                 y - half + drift[1], colour, arm)
                        continue
                    start, end = spans[ring]
                    lit = start <= position <= end
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
    # The artwork is named by the profile: only the Crossover calls it
    # device.png, while the Epix family names the file after the device.
    device = Image.open(
        os.path.join(DEVICE_DIR, sim.get("image", "device.png"))).convert("RGBA")

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


def main(outdir: str = "build/mockups", device: str = DEFAULT_DEVICE) -> int:
    use_device(device)
    os.makedirs(outdir, exist_ok=True)
    print(f"{device}: {SIZE}x{SIZE}, {COLS}x{ROWS} lattice, radius {RADIUS}, "
          f"hub {HUB}, hands {'drawn' if DRAWN_HANDS else 'physical'}")
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

    # 7b. The hourly rain forecast on the outermost ring. Where round the ring
    #     says when, how deep into the ring's own thickness says how likely.
    #     Two hours are left as None so the unknown tier is visible: a forecast
    #     that ran short must not read as a forecast of no rain.
    hours = [0, 0, 1, 2, 3, 3, 2, 1, 0, 0, None, None]
    hourly_assign = (SOURCE_RAIN_HOURS, 6, 2, 3)
    panels = []
    for label, kwargs in (("AWAKE", {}),
                          ("ALWAYS-ON", {"always_on": True}),
                          ("HELD BACK", {"always_on": True,
                                         "held_back": True})):
        face = render(values, assign=hourly_assign, hourly={0: hours},
                      **kwargs)
        panels.append((f"{label}   lum {measure(face) * 100:.2f}%",
                       composite(face)))
    path = os.path.join(outdir, "07b-rain-next-12h.png")
    sheet(panels, "Ring 1 = rain next 12h — one block per hour ahead, "
                  "deeper = more likely; last two hours unforecast").save(path)
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

    # 9. Themes — the same face in each set of ring colours, in both modes.
    panels = []
    for name, label in (("terrain", "TERRAIN"), ("activity", "ACTIVITY")):
        use_theme(name)
        for mode, always_on in (("awake", False), ("always-on", True)):
            face = render(values, always_on=always_on)
            panels.append((f"{label} {mode}   lum {measure(face) * 100:.2f}%",
                           composite(face)))
    use_theme("terrain")
    path = os.path.join(outdir, "09-themes.png")
    sheet(panels, "Colour themes — Terrain and Activity, awake and "
                  "always-on").save(path)
    written.append(path)

    # 10. Which blue Activity should carry. The watch ships two, and the blue
    #     is also the ramp's cold stop, so the weather face is shown beside the
    #     plain one — the two hues separate most at the cold end of the ramp.
    panels = []
    for name, label in (("activity", "LIGHT BLUE #1F8FFE"),
                        ("activity-navy", "NAVY #1852E6")):
        use_theme(name)
        plain = render(values)
        panels.append((f"{label}   lum {measure(plain) * 100:.2f}%",
                       composite(plain)))
        weather = render(weather_spans, assign=weather_assign,
                         marks=weather_marks)
        panels.append((f"{label} / temp ramp   "
                       f"lum {measure(weather) * 100:.2f}%",
                       composite(weather)))
    use_theme("terrain")
    path = os.path.join(outdir, "10-activity-blue.png")
    sheet(panels, "Activity's blue — the watch ships two, and it is the "
                  "temperature ramp's cold stop").save(path)
    written.append(path)

    # 12. The duotones. Two hues alternating rather than four distinct ones --
    #     rings 1 and 3 never touch, so a repeat costs no legibility, and every
    #     neighbour pair becomes a hue flip.
    #
    #     The temperature face is shown beside each, because the ramp is the
    #     one place a duotone can fail: with only two hues it runs straight
    #     from one to the other, and a complementary pair blends through grey
    #     exactly where most readings sit. These three were picked by
    #     measurement -- neighbour dE at or above the 93 Terrain ships with, a
    #     blend that holds its chroma, and no more luminance than Terrain.
    #     Ember (amber + rose) was rendered and dropped: its ramp was the best
    #     of the set but its rings only reached 70.
    panels = []
    for name in ("frost", "lagoon", "nocturne", "alpinist", "alpinist4"):
        use_theme(name)
        for mode, always_on in (("awake", False), ("always-on", True)):
            face = render(values, always_on=always_on)
            panels.append((f"{name.upper()} {mode}   "
                           f"lum {measure(face) * 100:.2f}%", composite(face)))
        weather = render(weather_spans, assign=weather_assign,
                         marks=weather_marks)
        panels.append((f"{name.upper()} temp ramp   "
                       f"lum {measure(weather) * 100:.2f}%",
                       composite(weather)))
    use_theme("terrain")
    path = os.path.join(outdir, "12-duotones.png")
    sheet(panels, "Duotones - two alternating hues, awake, always-on and "
                  "the temperature ramp").save(path)
    written.append(path)

    # 11. Burn-in drift: how long any one pixel stays lit over a full cycle.
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
