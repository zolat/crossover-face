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

    const PROPERTY_LAYOUT = "layout";
    const PROPERTY_BACKING = "handBacking";

    //! Four rings, each independently assigned to a Source.
    const RINGS = 4;
    const PROPERTY_RINGS = ["ring1", "ring2", "ring3", "ring4"] as Array<String>;

    const RING_THICKNESS = (DotGrid.RADIUS - DotGrid.HUB) / RINGS;
    const SPAN = 2 * DotGrid.RADIUS;

    var layout as Number = LAYOUT_BANDS_BOTTOM;
    var backing as Number = BACKING_OFF;

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

    //! Current span for every ring. Read once per frame.
    function spans() as Array<Array<Float> > {
        var out = new [RINGS] as Array<Array<Float> >;
        for (var i = 0; i < RINGS; i++) {
            out[i] = Source.span(rings[i]);
        }
        return out;
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
            var angle = Math.toDegrees(Math.atan2(dx, -dy));
            if (angle < 0) { angle += 360; }
            return (angle / 360.0).toFloat();
        }
        if (layout == LAYOUT_BANDS_CENTRE) {
            // Out from the midline, so a level opens symmetrically.
            return (dy.abs().toFloat() / DotGrid.RADIUS);
        }
        // Up from the rim, so a level rises like a tide.
        return ((DotGrid.RADIUS - dy).toFloat() / SPAN);
    }

    //! Is a dot at this position inside the span?
    //!
    //! A span whose end is before its start wraps past the ring's origin —
    //! a sub-zero temperature range crossing twelve o'clock does exactly this,
    //! running from, say, :55 round to :03. The renderer calls this per dot
    //! rather than keeping its own copy, so the two cannot drift apart.
    function isLit(position as Float, span as Array<Float>) as Boolean {
        if (span[0] <= span[1]) {
            return (position >= span[0]) && (position <= span[1]);
        }
        return (position >= span[0]) || (position <= span[1]);
    }

    //! Classify a dot into a palette slot: ring * 2, plus 1 when lit.
    function classify(col as Number, dx as Number, dy as Number,
                      spans as Array<Array<Float> >) as Number {
        var ring = ringFor(col, dx, dy);
        return ring * 2 + (isLit(positionOf(dx, dy), spans[ring]) ? 1 : 0);
    }
}
