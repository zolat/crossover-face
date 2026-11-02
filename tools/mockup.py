"""Render dot-matrix watch-face mockups for every supported device.

Iterating on colour through a compile + sideload loop costs a minute a time;
this costs a second. It renders each target's native geometry, composites it
into Garmin's device art, and adds the physical hands where a watch has them —
so what you review is the watch, not an abstract grid.

Device art comes from the installed profile. Lattice and hand constants
mirror ``source-lattice/*/Lattice.mc`` and are pinned by the Monkey C tests.

Usage:  python3 tools/mockup.py [outdir] [device]
"""

from __future__ import annotations

import colorsys
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
    #                 SIZE COLS RADIUS HUB rings halfW  cw  hour minute  hands
    "instinctcrossoveramoled": (390, 38, 190, 21, 4, 14, 46, 131, 176, True),
    "epix2pro42mm":            (390, 38, 190, 21, 4, 14, 46, 131, 176, False),
    "epix2":                   (416, 40, 203, 22, 4, 15, 49, 140, 188, False),
    "epix2pro47mm":            (416, 40, 203, 22, 4, 15, 49, 140, 188, False),
    "epix2pro51mm":            (454, 42, 210, 23, 5, 15, 51, 145, 195, False),
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
    global DEVICE, DEVICE_DIR, SIZE, COLS, ROWS, RADIUS, HUB, RINGS
    global HAND_HALF_WIDTH, HAND_COUNTERWEIGHT, HOUR_REACH, MINUTE_REACH
    global HANDS
    if name not in LATTICES:
        raise SystemExit(f"unknown device {name!r}; known: "
                         + ", ".join(sorted(LATTICES)))
    (SIZE, COLS, RADIUS, HUB, RINGS, HAND_HALF_WIDTH, HAND_COUNTERWEIGHT,
     HOUR_REACH, MINUTE_REACH, HANDS) = LATTICES[name]
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
    ("UV, next 12h", (0xFF, 0xCC, 0x00)),
    ("Body Battery, last 12h", (0x33, 0x88, 0xFF)),
    ("Temp, next 12h", (0xFF, 0xAA, 0x00)),
]
SOURCE_TEMPERATURE = 4
SOURCE_RAIN_HOURS = 9
SOURCE_UV_HOURS = 10
SOURCE_BODY_BATTERY_HOURS = 11
SOURCE_TEMP_HOURS = 12
BLOCK_SOURCES = (SOURCE_RAIN_HOURS, SOURCE_UV_HOURS,
                 SOURCE_BODY_BATTERY_HOURS, SOURCE_TEMP_HOURS)
#: The clock, on a watch with no hands. Never offered in a picker; a hands-free
#: build pins it to the outermost ring. Mirrors Source.SOURCE_TIME.
SOURCE_TIME = 14
#: The time again, hour and minute each filling the whole ring and overlapping.
#: Mirrors Source.SOURCE_TIME_OVERLAP.
SOURCE_TIME_OVERLAP = 15
TIME_SOURCES = (SOURCE_TIME, SOURCE_TIME_OVERLAP)

# Shipping ring colours, outermost first. These mirror Palette.THEMES exactly;
# keeping them separate from CANDIDATE_THEMES is what prevents a palette being
# mistaken for a selectable watch setting before it has been reviewed.
#
# Terrain is orchid, moss, ice, rust. Activity is the accent colours the watch
# itself uses, read off the peak-chroma pixel of the device's own swatches in
# ~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled/{nwidget,D_list_select}_*.png
# rather than guessed: red, green, blue, gold.
#
# Neighbours blurring together, not the set average, decides whether two rings
# can be told apart. Activity keeps gold on the smallest, innermost ring.
SHIPPING_THEMES = {
    "terrain": [(0xE8, 0x79, 0xF9), (0xB8, 0xD6, 0x4B),
                (0x7F, 0xD4, 0xFF), (0xFF, 0x6B, 0x5B), (0xE5, 0xB3, 0x3A)],
    "activity": [(0xFE, 0x46, 0x46), (0x6D, 0xC5, 0x4F),
                 (0x1F, 0x8F, 0xFE), (0xE5, 0x9A, 0x0A), (0x8E, 0x7B, 0xFF)],
    "beacon": [(0x5C, 0xD9, 0xF0), (0xFE, 0x46, 0x46),
               (0x8E, 0x7B, 0xFF), (0xE5, 0x9A, 0x0A), (0xB8, 0xD6, 0x4B)],
    "pulse": [(0xFE, 0x46, 0x46), (0x2F, 0xD9, 0xC5),
              (0xE8, 0x79, 0xF9), (0xB8, 0xD6, 0x4B), (0x7F, 0xD4, 0xFF)],
}

# Mockup-only candidates. They deliberately have no production IDs, resource
# labels or settings entries; this sheet is the review boundary before any one
# of them can become a shipping theme.
CANDIDATE_THEMES = {
    "arcade": [(0xF4, 0x5B, 0xD8), (0xB8, 0xD6, 0x4B),
               (0x1F, 0x8F, 0xFE), (0xFF, 0x99, 0x00)],
}

SHIPPING_RAMP_STOPS = {
    "terrain": (2, 0, 3),           # ice -> orchid -> rust
    "activity": (2, 3, 0),          # blue -> gold -> red
    "beacon": (0, 3, 1),            # cyan -> gold -> red
    "pulse": (1, 3, 0),             # teal -> lime -> red
}

CANDIDATE_RAMP_STOPS = {
    "arcade": (2, 3, 0),            # blue -> gold -> magenta
}

THEME_NAME = "terrain"
THEME = SHIPPING_THEMES[THEME_NAME]


def use_theme(name: str) -> None:
    """Swap the theme every colour here is derived from.

    Same move as the WEAK_ACTIVE sweep in main(): this file mirrors Monkey C
    module constants, so varying one means assigning to the global.
    """
    themes = SHIPPING_THEMES if name in SHIPPING_THEMES else CANDIDATE_THEMES
    globals()["THEME_NAME"] = name
    globals()["THEME"] = themes[name]

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
    thickness = (RADIUS - ring_floor()) / RINGS
    inner = RADIUS - (ring + 1) * thickness
    # A centre ball's inner edge is the centre: sized half a ring out instead.
    inner = max(inner, thickness / 2.0)
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
    thickness = (RADIUS - ring_floor()) / RINGS
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
            if d > RADIUS * RADIUS or d < clear_sq():
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
    stops = (SHIPPING_RAMP_STOPS if THEME_NAME in SHIPPING_RAMP_STOPS
             else CANDIDATE_RAMP_STOPS)
    cold_i, mid_i, hot_i = stops[THEME_NAME]
    cold, mid, hot = THEME[cold_i], THEME[mid_i], THEME[hot_i]
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

# The block ring's geometry. Mirrors HourBands.mc: twelve blocks round the ring,
# a gutter after each, three radial sub-bands across the ring's thickness, and a
# partial band whose *width* carries whatever the bands cannot. A block holds a
# level from 0 to HOUR_LEVELS; what filled it is the source's business.
HOURS = 12
HOUR_BANDS = 3
HOUR_LEVELS = 15
HOUR_LEVELS_PER_BAND = HOUR_LEVELS // HOUR_BANDS
HOUR_BLOCK_DEGREES = 22.5
HOUR_FILL = HOUR_BLOCK_DEGREES / (360.0 / HOURS)
# The block sits in the MIDDLE of its wedge, so half the gutter falls either
# side and each hour mark lands in the middle of a gutter. Mirrors
# HourBands.LEAD/TRAIL/BLOCK_CENTRE — and note LEAD + FILL/2 is exactly 0.5 for
# any FILL, which is what centring buys.
HOUR_LEAD = (1.0 - HOUR_FILL) / 2
HOUR_TRAIL = HOUR_LEAD + HOUR_FILL
HOUR_CENTRE = HOUR_LEAD + HOUR_FILL / 2


def hour_block(position: float) -> int:
    return min(HOURS - 1, int(position * HOURS))


def inside_block(position: float) -> bool:
    """False in the gutter after the block. Mirrors HourBands.insideBlock."""
    at = position * HOURS
    into = at - int(at)
    return HOUR_LEAD <= into < HOUR_TRAIL


def band_edge(ring: int, tier: int) -> float:
    """Squared outer radius of a sub-band. Mirrors DotGrid.bandEdges: integer
    thickness, matching the edges that decide a dot's ring, and the top band
    takes the ring's own outer edge rather than stacking three steps."""
    thickness = (RADIUS - ring_floor()) // RINGS
    step = thickness // HOUR_BANDS
    inner = RADIUS - (ring + 1) * thickness
    edge = inner + thickness if tier == HOUR_BANDS else inner + tier * step
    return edge * edge


def temp_level_for(celsius, low, high):
    """A Celsius reading on the wearer's scale. Mirrors
    HourlyWeatherData.tempLevelFor: low is empty, high is full, clamped."""
    if celsius is None:
        return None
    return level_for((celsius - low) * 100.0 / (high - low))


def level_for(percent):
    """A percentage as a block level. Mirrors HourlyWeatherData.rainLevelFor:
    truncating,
    so a reading has to reach a full rung before it lights anything."""
    if percent is None:
        return None
    if percent <= 0:
        return 0
    return min(HOUR_LEVELS, int(percent / 100.0 * HOUR_LEVELS))


def full_bands_for(level: int) -> int:
    """Whole sub-bands a level fills. Mirrors HourBands.fullBandsFor."""
    return (level * HOUR_BANDS) // HOUR_LEVELS


def partial_half_for(level: int) -> float:
    """Half-width of the partial band's window, in wedge units. Mirrors
    HourBands.partialHalfFor — no minimum, because on this lattice the geometry
    already lights at least one dot at every level."""
    return (HOUR_FILL / 2) * (((level * HOUR_BANDS) % HOUR_LEVELS) / HOUR_LEVELS)


# Mirrors HourBands.WINDOW_FLOOR: only ring 2 (menu ring 3) is floored.
WINDOW_FLOOR = (0.0, 0.0, 0.12, 0.0, 0.0)


def partial_half_on(level: int, ring: int) -> float:
    """Mirrors HourBands.partialHalfOn: floored, but zero stays zero."""
    window = partial_half_for(level)
    return WINDOW_FLOOR[ring] if 0.0 < window < WINDOW_FLOOR[ring] else window


def hourly_colour(ring, position, dist_sq, levels, always_on, held_back):
    """One dot of a block ring. Mirrors MatrixRenderer's second inner loop.

    `levels` is twelve entries, each 0-HOUR_LEVELS or None for a block the
    source said nothing about. A level fills whole sub-bands outward and then
    part of the way across the next band, centred in the block."""
    colour = THEME[ring % len(THEME)]
    if always_on:
        colour = scale(colour, LIFT)
    weak = WEAK_HELD_BACK if held_back else (
        WEAK_ALWAYS_ON if always_on else WEAK_ACTIVE)
    if held_back or levels is None:
        # Held back, every hour reads known and empty — never unknown, which
        # would draw the dim tier right round the ring and put data in the one
        # mode whose whole purpose is to carry none.
        return scale(colour, weak)
    at = position * HOURS
    block = int(at)
    into = at - block
    if not (HOUR_LEAD <= into < HOUR_TRAIL):
        return scale(colour, weak)          # a gutter, either side of the block
    level = levels[block]
    if level is None:
        return scale(colour, WEAK_UNKNOWN)
    bands = full_bands_for(level)
    if bands > 0 and dist_sq <= band_edge(ring, bands):
        return colour
    window = partial_half_on(level, ring)
    if (window > 0.0 and dist_sq <= band_edge(ring, bands + 1)
            and abs(into - HOUR_CENTRE) < window):
        return colour                       # the partial band
    return scale(colour, weak)


def time_fractions(hour: int, minute: int) -> tuple[float, float]:
    """How far round the dial each half of the time ring runs. Mirrors
    Source.fillTime: the hour is continuous like an hour hand, the minute reads
    like a minute hand — empty on the hour, a quarter at :15."""
    return ((hour % 12 + minute / 60.0) / 12.0, minute / 60.0)


#: Elapsed time is drawn white: the Crossover's own hour hand, and the one
#: colour no theme uses, so it reads as the clock rather than as a fifth stat.
#: Mirrors Palette.TIME_LIT.
TIME_LIT = (0xFF, 0xFF, 0xFF)
#: What has not elapsed yet, as a fraction of the ring's colour. At the
#: ordinary unfilled tier (0.55) white against hue barely separated at 1:1;
#: 0.25 is what made the split readable. Mirrors Palette.TIME_UNLIT.
TIME_UNLIT = 0.25

#: The overlapping style: where both have passed is the ring's own theme
#: colour, and the hour and minute are its hue turned TIME_SPLIT_DEGREES either
#: way in OKLCH at its own lightness, chroma floored at TIME_SPLIT_CHROMA and
#: given up where the screen cannot show it. Mirrors Palette.TIME_* and
#: HueSplit.pair; unfilled is a neutral grey.
TIME_SPLIT_DEGREES = 60.0
TIME_SPLIT_CHROMA = 0.08
TIME_OVERLAP_UNLIT = (0x3A, 0x3A, 0x3A)


def _linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _byte(x: float) -> int:
    """A linear channel as an sRGB byte, rounded half up, as HueSplit.toByte."""
    x = min(1.0, max(0.0, x))
    encoded = 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    return max(0, min(255, math.floor(encoded * 255.0 + 0.5)))


def to_oklch(colour):
    """(lightness, chroma, hue in degrees). Mirrors HueSplit.toOklch."""
    r, g, b = (_linear(c / 255.0) for c in colour)
    cbrt = lambda x: 0.0 if x <= 0 else x ** (1 / 3)
    l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    L = 0.2104542553 * l + 0.7936177850 * m_ - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m_ + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m_ - 0.8086757660 * s
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360


def _linear_rgb(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m_ + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m_ - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m_ + 1.7076147010 * s)


def _in_gamut(rgb) -> bool:
    return all(-1e-4 <= x <= 1 + 1e-4 for x in rgb)


def _fit(L, C, h):
    """The most chroma up to C the screen can show here. Mirrors HueSplit.fit."""
    if _in_gamut(_linear_rgb(L, C, h)):
        return C
    lo, hi = 0.0, C
    for _ in range(24):
        mid = (lo + hi) / 2
        if _in_gamut(_linear_rgb(L, mid, h)):
            lo = mid
        else:
            hi = mid
    return lo


def hue_split(colour, degrees=TIME_SPLIT_DEGREES, floor=TIME_SPLIT_CHROMA):
    """[turned back, turned on] for an RGB colour. Mirrors HueSplit.pair."""
    L, C, h = to_oklch(colour)
    C = max(C, floor)
    out = []
    for d in (-degrees, degrees):
        hue = (h + d) % 360
        out.append(tuple(_byte(x) for x in _linear_rgb(L, _fit(L, C, hue), hue)))
    return out


def time_overlap_colours(ring):
    """(hour, minute, both) for the overlapping ring. Mirrors Palette.timeOverlap."""
    both = THEME[ring % len(THEME)]
    hour, minute = hue_split(both)
    return hour, minute, both


def time_colour(ring, position, dist_sq, time, always_on, held_back,
                style=SOURCE_TIME):
    """One dot of the time ring. Mirrors TimeRing.draw.

    The hour fills the innermost sub-band and the minute the outer two, both
    clockwise from twelve. Where both have passed the ring is whole; where one
    has, half of it. The same in every mode, held back included: on a watch
    with no hands this ring is the only thing saying what o'clock it is."""
    hour_end, minute_end = time
    if style == SOURCE_TIME_OVERLAP:
        # Each fills the whole ring; the colour says which have passed.
        hour, minute = position < hour_end, position < minute_end
        hour_colour, minute_colour, both = time_overlap_colours(ring)
        if hour and minute:
            return both
        if hour:
            return hour_colour
        if minute:
            return minute_colour
        return TIME_OVERLAP_UNLIT
    end = hour_end if dist_sq <= band_edge(ring, 1) else minute_end
    if position < end:
        return TIME_LIT
    return scale(THEME[ring % len(THEME)], TIME_UNLIT)


def scale(rgb: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(c * factor))) for c in rgb)


# --- dot -> stat mapping -----------------------------------------------------
# The seam. Mirrors StatMap.ringFor and StatMap.positionOf: a dot's radius
# picks its ring, and its angle is its position along it.


RINGS = 4


def ring_map(dx: int, dy: int):
    """Radius picks the ring, position runs clockwise from 12."""
    dist = math.hypot(dx, dy)
    thickness = (RADIUS - ring_floor()) / RINGS
    ring = min(RINGS - 1, max(0, int((RADIUS - dist) / thickness)))
    return ring, ((math.degrees(math.atan2(dx, -dy)) + 360) % 360) / 360.0


# --- analogue hands ----------------------------------------------------------
# Mirrors source/matrix/HandBacking.mc. Geometry from the device simulator.json.

HAND_HALF_WIDTH = 14
HAND_COUNTERWEIGHT = 46
HOUR_REACH = 131
MINUTE_REACH = 176
HAND_MARGIN = 0

#: Whether this watch has hands to back. Set by use_device(). Mirrors
#: HandStyle.HANDS: on a watch with none, no backing is ever drawn.
HANDS = True

def ring_floor() -> int:
    """Where ring thickness is measured from: the hub under hands, the centre
    without them, so the centre ball's radius is one ring. Mirrors
    DotGrid.INNER."""
    return HUB if HANDS else 0


def clear_sq() -> int:
    """Inside this, squared, no dots: the hub under hands, nothing without them,
    so the innermost ring runs to the centre. Mirrors DotGrid.CLEAR_SQ."""
    return HUB * HUB if HANDS else 0


#: What handAt()'s three answers paint.
NO_HAND, HOUR, MINUTE = 0, 1, 2


def hand_colours(backing):
    """Mirrors HandBacking.coloursFor: one backing colour for both hands."""
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


# --- the date ----------------------------------------------------------------
# Mirrors source/matrix/DateGlyph.mc. The numeral's dots are drawn like every
# other; a faint outline joins them, dot centre to dot centre, tracing the
# numeral's edge at LINE_PERCENT of the colour of the dot each line leaves from.
# Each line fills only the gap between two crosses, never their arms.
#
# Awake only: always-on carries no date, because a line does not escape itself
# when the drift moves the field one DOT, and some of its pixels would sit lit
# through two of the four drift phases. CrossoverView draws the outline in on
# a wake; render() draws it complete.
#
# The struck watermark this replaced -- one stroke of each numeral dot instead
# of two -- measured well here and was invisible on the wrist. 65% was chosen on
# the watch between 50, 65 and 80; 100 was too obvious and 40 vanished.

SCALE = 2                       # lattice cells per font pixel
FONT_COLS, FONT_ROWS = 3, 5
FONT_SPAN = 2 * FONT_COLS + 1   # two digits with a one-column gutter
GUTTER = FONT_COLS
GLYPH_COLS = FONT_SPAN * SCALE  # 14
GLYPH_ROWS = FONT_ROWS * SCALE  # 10

def glyph_origin():
    """The centred window used by DateGlyph on the selected lattice."""
    return ((COLS - GLYPH_COLS) // 2, ROWS // 2 + 4)

# 3x5 digits, row-major, bit 14 top-left.
DIGITS = [
    0b111101101101111,      # 0
    0b010110010010111,      # 1
    0b111001111100111,      # 2
    0b111001111001111,      # 3
    0b101101111001001,      # 4
    0b111100111001111,      # 5
    0b111100111101111,      # 6
    0b111001001001001,      # 7
    0b111101111101111,      # 8
    0b111101111001111,      # 9
]

LINE_PERCENTS = [50, 65, 80]            # the dateOutline setting's levels
LINE_PERCENT = LINE_PERCENTS[1]         # its default
GAP_FROM = DOT // 2 + 1                 # first pixel past an arm tip
GAP_LENGTH = PITCH - 2 * GAP_FROM + 1   # to one short of the next arm


def digit_lit(digit: int, col: int, row: int) -> bool:
    """Is this pixel of this digit lit?"""
    return bool(DIGITS[digit] >> (14 - (row * FONT_COLS + col)) & 1)


def glyph_cells(day: int, origin=None) -> set:
    """The lattice cells today's numeral covers, as (col, row) pairs."""
    origin = glyph_origin() if origin is None else origin
    col0, row0 = origin
    out = set()
    for r in range(GLYPH_ROWS):
        for c in range(GLYPH_COLS):
            font_col = c // SCALE
            if font_col == GUTTER:
                continue
            digit = (day // 10) if font_col < GUTTER else (day % 10)
            if digit_lit(digit % 10, font_col % (GUTTER + 1), r // SCALE):
                out.add((col0 + c, row0 + r))
    return out


def contour_segments(day: int, origin=None) -> list:
    """The numeral's outline: pairs of neighbouring cells, dot centre to centre.

    Mirrors DateGlyph.trace(). The numeral inset by half a pitch is the union
    of the squares between the centres of every 2x2 block of its cells; a unit
    edge between neighbouring centres is on the outline exactly when that shape
    lies on one side of it and not the other.
    """
    origin = glyph_origin() if origin is None else origin
    col0, row0 = origin
    cells = glyph_cells(day, origin)

    def numeral(c, r):
        return (col0 + c, row0 + r) in cells

    def inside(c, r):
        return (numeral(c, r) and numeral(c + 1, r) and
                numeral(c, r + 1) and numeral(c + 1, r + 1))

    out = []
    for r in range(GLYPH_ROWS):
        for c in range(GLYPH_COLS):
            here = (col0 + c, row0 + r)
            if c + 1 < GLYPH_COLS and inside(c, r - 1) != inside(c, r):
                out.append((here, (col0 + c + 1, row0 + r)))
            if r + 1 < GLYPH_ROWS and inside(c - 1, r) != inside(c, r):
                out.append((here, (col0 + c, row0 + r + 1)))
    return out


def arm_for(dx: int, dy: int, rotate: bool):
    """Which strokes this dot draws: turned to follow the ring, or upright."""
    # Mirrors StatMap.Rotation.
    return ARMS[orientation_at(dx, dy)] if rotate else ARMS[0]


def draw_outline(draw, day: int, colours: dict, drift) -> None:
    """Ink the numeral's outline in the gaps between its crosses."""
    centre = SIZE // 2
    for a, b in contour_segments(day):
        colour = colours.get(a)
        if colour is None:
            continue
        colour = scale(colour, LINE_PERCENT / 100)
        (ca, ra), (cb, rb) = a, b
        x = centre + (2 * ca - (COLS - 1)) * (PITCH // 2) + drift[0]
        y = centre + (2 * ra - (ROWS - 1)) * (PITCH // 2) + drift[1]
        if ra == rb:
            draw.line([x + GAP_FROM, y, x + GAP_FROM + GAP_LENGTH - 1, y],
                      fill=colour)
        else:
            draw.line([x, y + GAP_FROM, x, y + GAP_FROM + GAP_LENGTH - 1],
                      fill=colour)


# --- rendering ---------------------------------------------------------------


def _pad(values, filler):
    """A per-ring list extended to RINGS, or None left alone."""
    if values is None:
        return None
    values = list(values)
    return values + [filler] * (RINGS - len(values))


def render(spans, *, assign=(0, 1, 2, 3), always_on: bool = False,
           held_back: bool = False, hourly=None,
           backing: tuple[int, int, int] | None = None,
           at_time: tuple[int, int] = (10, 9),
           drift: tuple[int, int] = (0, 0), marks=None,
           overs=None, rotate: bool = True,
           date: int | None = None,
           time: tuple[float, float] | None = None) -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    # Scenes are written for four rings; a five-ring watch's centre ball shows
    # Steps at its default reading, as StatMap.RING_DEFAULTS has it.
    spans, assign = _pad(spans, (0.0, 0.68)), _pad(assign, 0)
    marks, overs = _pad(marks, -1.0), _pad(overs, False)
    # The watermark's cells, resolved once rather than per dot.
    # Awake only. Mirrors CrossoverView.showsDate().
    dating = date is not None and not always_on
    # A watch with no hands never backs a dot. Mirrors
    # CrossoverView.backingColour().
    if not HANDS:
        backing = None
    glyph = glyph_cells(date) if dating else set()
    # The colour each numeral dot is drawn in, which its outline is inked in.
    glyph_colours = {}
    draw = ImageDraw.Draw(img)
    # Which dot each ring marks, worked out once rather than per dot.
    mark_dots = {}
    if marks is not None and not held_back:
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
            if dist_sq > RADIUS * RADIUS or dist_sq < clear_sq():
                continue

            x, y = centre + dx, centre + dy
            marked_here = False
            hand = hand_at(dx, dy, axes) if axes is not None else NO_HAND
            if hand != NO_HAND:
                colour = hands[hand]
            else:
                ring, position = ring_map(dx, dy)
                # Held back with the fills and in no other mode, and it
                # outranks the fill: the mark has to be legible whether or not
                # now falls inside today's range.
                if mark_dots.get(ring) == (dx, dy):
                    colour = marker_colour(ring)
                    marked_here = True
                else:
                    source = assign[ring]
                    if source in TIME_SOURCES:
                        colour = time_colour(ring, position, dist_sq,
                                             time or (0.0, 0.0), always_on,
                                             held_back, source)
                        if (col, row) in glyph:
                            glyph_colours[(col, row)] = colour
                        draw_dot(draw, x - half + drift[0],
                                 y - half + drift[1], colour,
                                 arm_for(dx, dy, rotate))
                        continue
                    if source in BLOCK_SOURCES:
                        # Its own path, mirroring the renderer's own loop: the
                        # forecast reads a radius as well as an angle, so it
                        # cannot be said with a span.
                        colour = hourly_colour(
                            ring, position, dist_sq,
                            (hourly or {}).get(ring), always_on, held_back)
                        if (col, row) in glyph:
                            glyph_colours[(col, row)] = colour
                        draw_dot(draw, x - half + drift[0],
                                 y - half + drift[1], colour,
                                 arm_for(dx, dy, rotate))
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
            if (col, row) in glyph:
                glyph_colours[(col, row)] = colour
            draw_dot(draw, left, top, colour, arm_for(dx, dy, rotate))
    if dating:
        draw_outline(draw, date, glyph_colours, drift)
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
          f"hub {HUB}, hands {'physical' if HANDS else 'none'}")
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

    # 6. Physical backing, shown in all three configured states. Only where
    #    there are hands to back.
    if HANDS:
        when = (10, 9)
        panels = []
        for label, backing in (("OFF", None), ("WHITE", (255, 255, 255)),
                               ("DARK", (16, 16, 16))):
            face = render(values, backing=backing, at_time=when)
            panels.append((f"{label}   luminance {measure(face) * 100:.2f}%",
                           composite(face, at_time=when)))
        path = os.path.join(outdir, "05-hand-backing.png")
        sheet(panels, "Behind physical hands — awake only, hands held at "
                      "system time").save(path)
        written.append(path)

    # 7. Rings assigned to weather — temperature is a range, not a level, and
    #    the mark says where in that range now falls.
    weather_assign = (4, 5, 2, 0)          # temperature, rain, battery, steps
    weather_spans = [(11 / 60, 22 / 60), (0.0, 0.35), (0.0, 0.82), (0.0, 0.68)]
    NO_MARK = -1.0
    weather_marks = [17 / 60, NO_MARK, NO_MARK, NO_MARK]   # 17C right now
    face = render(weather_spans, assign=weather_assign, marks=weather_marks)
    # The mark draws asleep too; only the held-back mode drops it.
    asleep = render(weather_spans, assign=weather_assign, marks=weather_marks,
                    always_on=True)
    path = os.path.join(outdir, "07-weather-assignment.png")
    sheet([(f"WEATHER   lum {measure(face) * 100:.2f}%", composite(face)),
           (f"ALWAYS-ON   lum {measure(asleep) * 100:.2f}%",
            composite(asleep))],
          "Ring 1 = temperature 11-22C on a 0-60 scale, "
          "white mark = 17C now").save(path)
    written.append(path)

    # 7b. The hourly rain forecast on the outermost ring. Where round the ring
    #     says when, how deep into the ring's own thickness says how likely.
    #     Two hours are left as None so the unknown tier is visible: a forecast
    #     that ran short must not read as a forecast of no rain.
    # Percentages, so the scale is exercised as the watch would fill it: a
    # 10% hour is a pip rather than the nothing the old four-step scale drew.
    hours = [level_for(p) for p in
             (0, 5, 10, 20, 35, 55, 75, 90, 100, 60, None, None)]
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
                  "0/5/10/20/35/55/75/90/100/60%; last two unforecast"
          ).save(path)
    written.append(path)

    # 7c. The scale itself, every level in turn, so the sixteen readings can be
    #     compared side by side rather than inferred from one forecast.
    panels = []
    for first in (0, HOUR_LEVELS + 1 - HOURS):
        levels = list(range(first, first + HOURS))
        face = render(values, assign=hourly_assign, hourly={0: levels})
        panels.append((f"LEVELS {levels[0]}-{levels[-1]}", composite(face)))
    path = os.path.join(outdir, "07c-block-levels.png")
    sheet(panels, "Every rung of the 16-step block scale: whole sub-bands "
                  "outward, then width across the block").save(path)
    written.append(path)

    # 7d. Forward and reverse time share the same block geometry. At 09:30 the
    #     UV forecast runs clockwise from the hour hand; Body Battery starts at
    #     its live value and walks backwards through completed-hour averages.
    def relative_blocks(anchor, readings, direction):
        blocks = [None] * HOURS
        for offset, reading in enumerate(readings):
            blocks[(anchor + direction * offset) % HOURS] = level_for(reading)
        return blocks

    anchor = 9
    when = (anchor, 30)
    # level_for takes percentages. UV's 0-10 index is ten percentage points per
    # unit on the same 0-1 block scale.
    uv = relative_blocks(anchor,
                         [v * 10 for v in (2, 4, 6, 8, 10, 9,
                                           7, 4, 2, 1, 0, 0)], 1)
    body = relative_blocks(anchor,
                           (80, 75, 68, 60, 52, 45,
                            38, 32, 28, 24, 22, 20), -1)
    panels = []
    cases = [
        ("UV AHEAD", (SOURCE_UV_HOURS, 6, 2, 3), {0: uv}),
        ("BODY BATTERY HISTORY",
         (SOURCE_BODY_BATTERY_HOURS, 6, 2, 3), {0: body}),
        ("BOTH DIRECTIONS",
         (SOURCE_UV_HOURS, SOURCE_BODY_BATTERY_HOURS, 2, 3),
         {0: uv, 1: body}),
    ]
    for label, assign, block_values in cases:
        face = render(values, assign=assign, hourly=block_values, at_time=when)
        panels.append((f"{label}   lum {measure(face) * 100:.2f}%",
                       composite(face, at_time=when)))
    path = os.path.join(outdir, "07d-uv-body-history.png")
    sheet(panels, "At 09:30: UV runs clockwise into the next 12h; "
                  "Body Battery runs counter-clockwise through the last 12h"
          ).save(path)
    written.append(path)

    # 7e. Temperature ahead, on the wearer's own scale. The same Adelaide
    #     summer day on the default 0-45C, then a mild day on that scale and
    #     on a tighter 5-25C one: why the two ends are a setting.
    summer = (24, 28, 32, 36, 39, 41, 42, 40, 35, 30, 27, 25)
    mild = (11, 13, 15, 17, 18, 19, 19, 18, 16, 14, 12, 11)

    def temp_blocks(readings, low, high):
        blocks = [None] * HOURS
        for offset, reading in enumerate(readings):
            blocks[(anchor + offset) % HOURS] = temp_level_for(reading, low,
                                                               high)
        return blocks

    panels = []
    for label, readings, low, high in (("SUMMER 0-45C", summer, 0, 45),
                                       ("MILD 0-45C", mild, 0, 45),
                                       ("MILD 5-25C", mild, 5, 25)):
        face = render(values, assign=(SOURCE_TEMP_HOURS, 6, 2, 3),
                      hourly={0: temp_blocks(readings, low, high)},
                      at_time=when)
        panels.append((f"{label}   lum {measure(face) * 100:.2f}%",
                       composite(face, at_time=when)))
    path = os.path.join(outdir, "07e-temp-next-12h.png")
    sheet(panels, "At 09:30: temperature ahead, empty at the low end and "
                  "full at the high end the wearer sets").save(path)
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
    for name in ("terrain", "activity", "beacon", "pulse"):
        use_theme(name)
        for mode, always_on in (("awake", False), ("always-on", True)):
            face = render(values, always_on=always_on)
            panels.append((f"{name.upper()} {mode}   "
                           f"lum {measure(face) * 100:.2f}%",
                           composite(face)))
    use_theme("terrain")
    path = os.path.join(outdir, "09-themes.png")
    sheet(panels, "Shipping colour themes — Terrain, Activity, Beacon and "
                  "Pulse; awake and always-on").save(path)
    written.append(path)

    # 10. Non-shipping candidates, kept together and visibly separate from the
    #     production theme sheet above. Each candidate gets the same three
    #     views: awake, always-on, and the temperature range that exercises all
    #     three of its explicit ramp stops.
    panels = []
    for name in ("arcade",):
        use_theme(name)
        label = name.upper()
        awake = render(values)
        panels.append((f"{label} awake   lum {measure(awake) * 100:.2f}%",
                       composite(awake)))
        always_on = render(values, always_on=True)
        panels.append((f"{label} always-on   "
                       f"lum {measure(always_on) * 100:.2f}%",
                       composite(always_on)))
        weather = render(weather_spans, assign=weather_assign,
                         marks=weather_marks)
        panels.append((f"{label} temp range   "
                       f"lum {measure(weather) * 100:.2f}%",
                       composite(weather)))
    use_theme("terrain")
    path = os.path.join(outdir, "10-candidates.png")
    sheet(panels, "Mockup-only candidate — Arcade; awake, always-on and "
                  "temperature range").save(path)
    written.append(path)

    # 12. The date: the day of the month outlined through the dots, awake.
    #     Always-on carries none, so its sheet is the plain field.
    panels = []
    plain = render(values, rotate=False)
    panels.append((f"NO DATE   lum {measure(plain) * 100:.2f}%",
                   composite(plain)))
    for day in (5, 15, 28):
        face = render(values, rotate=False, date=day)
        panels.append((f"DAY {day:02d}   lum {measure(face) * 100:.2f}%",
                       composite(face)))
    path = os.path.join(outdir, "13-date.png")
    sheet(panels, "Date - the dots joined into the day's numeral, "
                  "awake only").save(path)
    written.append(path)

    # The same faces uncomposited and at 1:1, which is the honest look at it:
    # the device art and its bezel shrink the dial by a third. Both rotations,
    # since the date is its own setting and draws on either field.
    panels = [("UPRIGHT", render(values, rotate=False)),
              ("UPRIGHT + DATE", render(values, rotate=False, date=15)),
              ("RINGS + DATE", render(values, date=15)),
              ("ALWAYS-ON",
               render(values, rotate=False, date=15, always_on=True))]
    panels = [(f"{n}   lum {measure(f) * 100:.2f}%", f) for n, f in panels]
    path = os.path.join(outdir, "13b-date-true-size.png")
    sheet(panels, "Date at 1:1 - on both fields, and absent in always-on"
          ).save(path)
    written.append(path)

    # 14. The time ring: the hour fills the inner sub-band and the minute the
    #     outer two, so where both have passed the ring is whole. Ring 0 on a
    #     watch with no hands; the other three keep their data.
    time_assign = (SOURCE_TIME, 1, 2, 3)
    panels = []
    for h, m in ((12, 0), (3, 15), (6, 30), (9, 45), (11, 59), (10, 9)):
        face = render(values, assign=time_assign, time=time_fractions(h, m))
        panels.append((f"{h}:{m:02d}   lum {measure(face) * 100:.2f}%",
                       composite(face, hands=False)))
    path = os.path.join(outdir, "14-time-ring.png")
    sheet(panels, "Time ring - hour inside, minute outside, "
                  "both clockwise from twelve").save(path)
    written.append(path)

    #     The time survives every mode, held-back included: on a watch with no
    #     hands it is the one ring that must.
    at = time_fractions(10, 9)
    panels = []
    for label, kwargs in (("AWAKE", {}),
                          ("ALWAYS-ON", {"always_on": True}),
                          ("HELD BACK", {"always_on": True,
                                         "held_back": True}),
                          ("AWAKE + DATE", {"date": 23})):
        spans = nothing if kwargs.get("held_back") else values
        face = render(spans, assign=time_assign, time=at, **kwargs)
        panels.append((f"{label}   lum {measure(face) * 100:.2f}%",
                       composite(face, hands=False)))
    path = os.path.join(outdir, "14b-time-ring-modes.png")
    sheet(panels, "Time ring at 10:09 - awake, always-on, held back, "
                  "and under the date").save(path)
    written.append(path)

    # 14c. True size, uncomposited, so the split can be judged at 1:1.
    panels = [(f"{h}:{m:02d}",
               render(values, assign=time_assign, time=time_fractions(h, m)))
              for h, m in ((3, 15), (10, 9), (7, 52))]
    path = os.path.join(outdir, "14c-time-ring-true-size.png")
    sheet(panels, "Time ring at 1:1").save(path)
    written.append(path)

    # 14d. The overlapping style: hour blue, minute red, purple where both
    #      have passed, each over the whole ring. The tail past the purple is
    #      the one ahead, so the sheet leans on times where it is a sliver.
    overlap_assign = (SOURCE_TIME_OVERLAP, 1, 2, 3)
    panels = []
    for h, m in ((12, 5), (3, 15), (6, 30), (10, 9), (11, 59)):
        face = render(values, assign=overlap_assign, time=time_fractions(h, m))
        panels.append((f"{h}:{m:02d}   lum {measure(face) * 100:.2f}%", face))
    worst = render(values, assign=overlap_assign, always_on=True,
                   time=time_fractions(11, 59))
    panels.append((f"ALWAYS-ON 11:59   lum {measure(worst) * 100:.2f}%", worst))
    path = os.path.join(outdir, "14d-time-overlap.png")
    sheet(panels, "Time ring, overlapping - the ring's colour where both have "
                  "passed, its hue split for hour and minute").save(path)
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
