import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

//! Decides which ring a dot belongs to, and whether it falls inside that
//! ring's span.
//!
//! Layout is the seam: every layout shares one lattice and one palette, and
//! differs only in how a dot's position becomes a ring index and a position
//! along that ring. Because a dot's position is a single 0.0-1.0 number in
//! every layout, a source that reports a range works everywhere a level does.
module StatMap {

    enum Layout {
        LAYOUT_BANDS_BOTTOM = 0,    //! Column picks the ring, fill rises from the rim.
        LAYOUT_BANDS_CENTRE = 1,    //! As above, but position is measured out from the midline.
        LAYOUT_RINGS = 2            //! Radius picks the ring, position runs clockwise.
    }

    enum Backing {
        BACKING_OFF = 0,
        BACKING_WHITE = 1,
        BACKING_DARK = 2
    }

    //! Whether always-on shows the data or just the bare field of dots.
    enum AlwaysOnFill {
        ALWAYS_ON_FILL_SHOWN = 0,   //! The same image awake and asleep.
        ALWAYS_ON_FILL_HIDDEN = 1   //! Colour only; the data appears on a raise.
    }

    const PROPERTY_LAYOUT = "layout";
    const PROPERTY_BACKING = "handBacking";
    const PROPERTY_ALWAYS_ON_FILL = "alwaysOnFill";

    //! Four rings, each independently assigned to a Source.
    const RINGS = 4;
    const PROPERTY_RINGS = ["ring1", "ring2", "ring3", "ring4"] as Array<String>;

    const RING_THICKNESS = (DotGrid.RADIUS - DotGrid.HUB) / RINGS;
    const SPAN = 2 * DotGrid.RADIUS;

    var layout as Number = LAYOUT_BANDS_BOTTOM;
    var backing as Number = BACKING_OFF;
    var alwaysOnFill as Number = ALWAYS_ON_FILL_SHOWN;

    //! Which source each ring shows. Index 0 is the leftmost band, or the
    //! outermost ring.
    var rings as Array<Number> = [
        Source.SOURCE_STEPS,
        Source.SOURCE_HEART_RATE,
        Source.SOURCE_BATTERY,
        Source.SOURCE_BODY_BATTERY
    ] as Array<Number>;

    //! Re-read every setting. Safe at any time; anything missing or out of
    //! range falls back to its default rather than throwing.
    function load() as Void {
        layout = readNumber(PROPERTY_LAYOUT, LAYOUT_BANDS_BOTTOM,
                            LAYOUT_BANDS_BOTTOM, LAYOUT_RINGS);
        backing = readNumber(PROPERTY_BACKING, BACKING_OFF,
                             BACKING_OFF, BACKING_DARK);
        alwaysOnFill = readNumber(PROPERTY_ALWAYS_ON_FILL, ALWAYS_ON_FILL_SHOWN,
                                  ALWAYS_ON_FILL_SHOWN, ALWAYS_ON_FILL_HIDDEN);

        var defaults = [Source.SOURCE_STEPS, Source.SOURCE_HEART_RATE,
                        Source.SOURCE_BATTERY, Source.SOURCE_BODY_BATTERY]
                       as Array<Number>;
        var loaded = new [RINGS] as Array<Number>;
        for (var i = 0; i < RINGS; i++) {
            loaded[i] = readNumber(PROPERTY_RINGS[i], defaults[i],
                                   0, Source.COUNT - 1);
        }
        rings = loaded;
    }

    function readNumber(key as String, fallback as Number,
                        low as Number, high as Number) as Number {
        var value = fallback;
        try {
            var stored = Properties.getValue(key);
            if (stored != null) {
                value = (stored as Number).toNumber();
            }
        } catch (ex) {
            value = fallback;
        }
        if (value < low || value > high) {
            value = fallback;
        }
        return value;
    }

    //! A span nothing is inside.
    //!
    //! Positions run from 0.0 to below 1.0, so a span sitting out at 2.0 can
    //! never contain one. It also does not read as wrapping, since its start
    //! is not after its end — a wrapping span would light everything *outside*
    //! itself, which is the opposite of what this is for.
    //!
    //! This is how always-on hides the fills: not a branch in the render loop
    //! that runs ~1100 times a frame, just a span nothing falls in.
    const NEVER_LIT = [2.0, 2.0] as Array<Float>;

    //! Every ring empty, for always-on when the fills are held back.
    function noSpans() as Array<Array<Float> > {
        var out = new [RINGS] as Array<Array<Float> >;
        for (var i = 0; i < RINGS; i++) {
            out[i] = NEVER_LIT;
        }
        return out;
    }

    //! Current span for every ring. Read once per frame.
    function spans() as Array<Array<Float> > {
        var out = new [RINGS] as Array<Array<Float> >;
        for (var i = 0; i < RINGS; i++) {
            out[i] = Source.span(rings[i]);
        }
        return out;
    }

    //! The position each ring marks, or Source.NO_MARKER. Read once per frame.
    function markers() as Array<Float> {
        var out = new [RINGS] as Array<Float>;
        for (var i = 0; i < RINGS; i++) {
            out[i] = Source.marker(rings[i]);
        }
        return out;
    }

    //! Every ring unmarked, for always-on when the fills are held back. The
    //! mark is part of the data, so it goes when the data does.
    function noMarkers() as Array<Float> {
        var out = new [RINGS] as Array<Float>;
        for (var i = 0; i < RINGS; i++) {
            out[i] = Source.NO_MARKER;
        }
        return out;
    }

    //! The span a mark occupies: a window of the given half-width around a
    //! position, normalised onto the ring.
    //!
    //! Returned as an ordinary span so the renderer lights it with litBetween()
    //! rather than a second lit test of its own. That also means it wraps for
    //! free, which it must: a current temperature of half a degree sits just
    //! past twelve and its window straddles the origin, exactly as a sub-zero
    //! day range does.
    function windowAround(centre as Float, half as Float) as Array<Float> {
        var lo = centre - half;
        var hi = centre + half;
        if (hi - lo >= 1.0) {
            return [0.0, 1.0] as Array<Float>;      //! wider than the ring
        }
        if (lo < 0.0) { lo += 1.0; }
        if (hi >= 1.0) { hi -= 1.0; }
        return [lo, hi] as Array<Float>;
    }

    //! Which ring this dot belongs to.
    function ringFor(col as Number, dx as Number, dy as Number) as Number {
        var ring;
        if (layout == LAYOUT_RINGS) {
            var distance = Math.sqrt(dx * dx + dy * dy);
            ring = ((DotGrid.RADIUS - distance) / RING_THICKNESS).toNumber();
        } else {
            ring = col * RINGS / DotGrid.COLS;
        }
        if (ring < 0) { return 0; }
        if (ring >= RINGS) { return RINGS - 1; }
        return ring;
    }

    //! Where this dot sits along its ring, 0.0 at the ring's origin to 1.0 at
    //! its far end. A span lights every dot between its start and end.
    function positionOf(dx as Number, dy as Number) as Float {
        if (layout == LAYOUT_RINGS) {
            return Angle.turnOf(dx, dy);
        }
        if (layout == LAYOUT_BANDS_CENTRE) {
            // Out from the midline, so a level opens symmetrically.
            return (dy.abs().toFloat() / DotGrid.RADIUS);
        }
        // Up from the rim, so a level rises like a tide.
        return ((DotGrid.RADIUS - dy).toFloat() / SPAN);
    }

    //! Is a dot at this position inside the span, given the span already
    //! unpacked into its ends and whether it wraps?
    //!
    //! This is the exact shape MatrixRenderer inlines. The renderer walks the
    //! dots ring by ring, so the unpacking and the wrap test hoist out of its
    //! inner loop and only the two comparisons are left — and at ~1100 dots a
    //! frame, a call here rather than a comparison cost about 6ms every frame.
    //! isLit() below is this plus the unpacking, and litTestsAgree pins the two
    //! together at the boundaries, which is where a copy of a comparison drifts.
    function litBetween(position as Float, start as Float, end as Float,
                        wraps as Boolean) as Boolean {
        if (wraps) {
            return (position >= start) || (position <= end);
        }
        return (position >= start) && (position <= end);
    }

    //! Is a dot at this position inside the span?
    //!
    //! A span whose end is before its start wraps past the ring's origin —
    //! a sub-zero temperature range crossing twelve o'clock does exactly this,
    //! running from, say, :55 round to :03. This is the readable definition,
    //! used by the tests and by anything not in the render loop.
    function isLit(position as Float, span as Array<Float>) as Boolean {
        return litBetween(position, span[0], span[1], span[0] > span[1]);
    }

    //! Classify a dot into a palette slot: ring * 2, plus 1 when lit.
    function classify(col as Number, dx as Number, dy as Number,
                      spans as Array<Array<Float> >) as Number {
        var ring = ringFor(col, dx, dy);
        return ring * 2 + (isLit(positionOf(dx, dy), spans[ring]) ? 1 : 0);
    }
}
