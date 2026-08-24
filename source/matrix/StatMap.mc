import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

//! Decides which stat a dot belongs to and whether it reads as filled.
//!
//! This is the seam between layouts: they share one lattice and one palette,
//! and differ only in how a dot's position maps to a stat and a fill test.
//! Adding a layout means adding a branch here and a list entry in
//! resources/settings/settings.xml — nothing else moves.
module StatMap {

    enum Backing {
        BACKING_OFF = 0,
        BACKING_WHITE = 1,
        BACKING_DARK = 2
    }

    enum Layout {
        LAYOUT_BANDS_BOTTOM = 0,    //! Column picks the stat, fill rises from the rim.
        LAYOUT_BANDS_CENTRE = 1,    //! As above, but fill grows out from the midline.
        LAYOUT_RINGS = 2            //! Radius picks the ring, fill sweeps clockwise.
    }

    const PROPERTY_LAYOUT = "layout";
    const PROPERTY_BACKING = "handBacking";
    const STATS = 4;
    const RING_THICKNESS = (DotGrid.RADIUS - DotGrid.HUB) / STATS;

    //! Current layout. Owned here, refreshed from app settings by load().
    var layout as Number = LAYOUT_BANDS_BOTTOM;

    //! Whether to back the analogue hands, and with what. Active mode only.
    var backing as Number = BACKING_OFF;

    //! Re-read the user's choice. Safe to call at any time; falls back to the
    //! default rather than throwing if the property is missing or malformed.
    function load() as Void {
        var chosen = LAYOUT_BANDS_BOTTOM;
        try {
            var stored = Properties.getValue(PROPERTY_LAYOUT);
            if (stored != null) {
                chosen = (stored as Number).toNumber();
            }
        } catch (ex) {
            chosen = LAYOUT_BANDS_BOTTOM;
        }
        if (chosen < LAYOUT_BANDS_BOTTOM || chosen > LAYOUT_RINGS) {
            chosen = LAYOUT_BANDS_BOTTOM;
        }
        layout = chosen;
        backing = readNumber(PROPERTY_BACKING, BACKING_OFF, BACKING_OFF, BACKING_DARK);
    }

    //! Read a numeric property, falling back to a default rather than throwing
    //! when it is missing, the wrong type, or outside the expected range.
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

    //! Classify one dot into a palette slot: stat * 2, plus 1 when filled.
    //! Returning a packed index lets the renderer look the colour up directly
    //! instead of branching per dot.
    function classify(col as Number, dx as Number, dy as Number,
                      values as Array<Float>) as Number {
        if (layout == LAYOUT_RINGS) {
            return classifyRing(dx, dy, values);
        }
        return classifyBand(col, dy, values);
    }

    //! Bands: the column decides the stat, the row decides the fill.
    function classifyBand(col as Number, dy as Number,
                          values as Array<Float>) as Number {
        var stat = col * STATS / DotGrid.COLS;
        if (stat >= STATS) { stat = STATS - 1; }
        var value = values[stat];

        var filled;
        if (layout == LAYOUT_BANDS_CENTRE) {
            // Grows symmetrically about the midline, so the face reads as a
            // level meter opening outwards rather than a rising tide.
            filled = dy.abs() <= value * DotGrid.RADIUS;
        } else {
            // Waterline measured down from the top of the circle.
            filled = dy >= DotGrid.RADIUS - (value * 2 * DotGrid.RADIUS);
        }
        return stat * 2 + (filled ? 1 : 0);
    }

    //! Rings: the radius decides the ring, the angle decides the fill.
    function classifyRing(dx as Number, dy as Number,
                          values as Array<Float>) as Number {
        var distance = Math.sqrt(dx * dx + dy * dy);
        var stat = ((DotGrid.RADIUS - distance) / RING_THICKNESS).toNumber();
        if (stat < 0) { stat = 0; }
        if (stat >= STATS) { stat = STATS - 1; }

        // Degrees clockwise from twelve o'clock.
        var angle = Math.toDegrees(Math.atan2(dx, -dy));
        if (angle < 0) { angle += 360; }
        return stat * 2 + (angle <= values[stat] * 360 ? 1 : 0);
    }
}
