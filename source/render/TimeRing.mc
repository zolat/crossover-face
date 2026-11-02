import Toybox.Graphics;
import Toybox.Lang;

//! The time, drawn as one ring: two fills clockwise from twelve, the hour's
//! and the minute's, whose two ends are where the hands would point. Two
//! styles, which differ only in where each fill may go and what it is painted:
//!
//!   - **split** (SOURCE_TIME): the hour fills the innermost sub-band and the
//!     minute the outer two, both white over the ring's dim tier;
//!   - **overlap** (SOURCE_TIME_OVERLAP): each fills the whole thickness;
//!     where both have passed is the ring's own theme colour, and the hour
//!     and minute are its hue split either way (Palette.timeOverlap), over a
//!     neutral grey.
//!
//! So a dot is in one of four slots — neither, hour, minute, both — and the
//! style is two radius bounds and a four-colour table, settled before the
//! walk. There is no per-dot style test.
//!
//! **Its own module, called once per ring rather than inlined in the dot loop.**
//! MatrixRenderer.drawAt() is already as wide a frame as the test runner's
//! stack can hold, and the span loop must not grow a per-dot test for a ring
//! most faces never have. So drawAt() does everything a ring needs before its
//! loop — the delta key, the mark, the numeral cursor — and hands the walk to
//! this, the way a block ring has a loop of its own.
//!
//! A time ring never shares the screen with hand backing: only a watch with no
//! hands carries one. So there is no hand test here at all.
module TimeRing {

    //! Slot colours, indexed by slotOf(): neither, hour, minute, both.
    const NEITHER = 0;
    const HOUR = 1;
    const MINUTE = 2;
    const BOTH = 3;

    //! Walk one ring and paint every dot of it. Never a delta: the print moves
    //! once a minute, and drawAt() keeps the ring out of the delta path.
    //!
    //! `hourEnd` and `minuteEnd` are the ring's span — see Source.SOURCE_TIME.
    //! `dim` is the ring's dim tier, which only the split style draws. The pen
    //! colour is left wherever the last dot set it; the caller forgets its own
    //! cached pen afterwards.
    //!
    //! Returns how many dots it painted — every one in the ring — for the
    //! caller to add to its own count, which it publishes once a draw.
    function draw(dc as Dc, ring as Number, centreX as Number,
                  centreY as Number, hourEnd as Float, minuteEnd as Float,
                  source as Number, dim as Number) as Number {
        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var positionOf = DotGrid.positionOf;
        var armOf = DotGrid.armOf;
        var arms = DotGrid.ARMS;
        var turned = (StatMap.rotation == StatMap.ROTATION_RADIAL);
        var ax = arms[0];
        var ay = arms[1];
        var bx = arms[2];
        var by = arms[3];
        var colours = coloursFor(source, dim);
        var hourOut = hourBound(ring, source);
        var minuteIn = minuteBound(ring, source);

        // This ring's slice of the date, as drawAt() seeds it for the others.
        var dating = DateGlyph.active && DateGlyph.lit > 0;
        var glyphIndex = DateGlyph.index;
        var glyphColour = DateGlyph.colours;
        var glyphAt = dating ? DateGlyph.firstFor[ring] : 0;
        var glyphEnd = dating ? DateGlyph.firstFor[ring + 1] : 0;
        var glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt] : -1;

        var lastColour = -1;
        var last = DotGrid.ringStart[ring + 1];
        for (var i = DotGrid.ringStart[ring]; i < last; i++) {
            var dx = xs[i];
            var dy = ys[i];
            // slotOf(), inlined: this is the loop it defines.
            var radiusSq = dx * dx + dy * dy;
            var position = positionOf[i];
            var slot = (radiusSq <= hourOut && position < hourEnd) ? HOUR
                                                                   : NEITHER;
            if (radiusSq > minuteIn && position < minuteEnd) {
                slot += MINUTE;
            }
            var colour = colours[slot];
            if (colour != lastColour) {
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                lastColour = colour;
            }
            if (i == glyphNext) {
                glyphColour[glyphAt] = colour;
                glyphAt++;
                glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt] : -1;
                MatrixRenderer.recorded++;
            }
            var x = centreX + dx;
            var y = centreY + dy;
            if (turned) {
                var a = armOf[i];
                ax = arms[a];
                ay = arms[a + 1];
                bx = arms[a + 2];
                by = arms[a + 3];
            }
            dc.drawLine(x - ax, y - ay, x + ax, y + ay);
            dc.drawLine(x - bx, y - by, x + bx, y + by);
        }
        return last - DotGrid.ringStart[ring];
    }

    //! What each slot is painted, for this style.
    function coloursFor(source as Number, dim as Number) as Array<Number> {
        if (source == Source.SOURCE_TIME_OVERLAP) {
            return Palette.timeOverlap;
        }
        return [dim, Palette.TIME_LIT, Palette.TIME_LIT, Palette.TIME_LIT]
               as Array<Number>;
    }

    //! The squared radius the hour's fill reaches out to. Split, the innermost
    //! sub-band's outer edge — integer, like every edge the block ring reads,
    //! so it agrees with the edges that made the ring. Overlapping, past the
    //! ring, so every dot qualifies.
    function hourBound(ring as Number, source as Number) as Number {
        if (source == Source.SOURCE_TIME_OVERLAP) {
            return DotGrid.RADIUS * DotGrid.RADIUS;
        }
        return DotGrid.bandEdge[ring * HourBands.BANDS];
    }

    //! The squared radius the minute's fill starts beyond: the same edge
    //! split, so the two halves tile the ring; nothing, overlapping.
    function minuteBound(ring as Number, source as Number) as Number {
        if (source == Source.SOURCE_TIME_OVERLAP) {
            return -1;
        }
        return DotGrid.bandEdge[ring * HourBands.BANDS];
    }

    //! Which fills cover the dot at (dx, dy), at this position round its ring:
    //! NEITHER, HOUR, MINUTE or BOTH. The readable definition of the loop
    //! above, for the tests.
    function slotOf(ring as Number, dx as Number, dy as Number,
                    position as Float, hourEnd as Float, minuteEnd as Float,
                    source as Number) as Number {
        var radiusSq = dx * dx + dy * dy;
        var slot = NEITHER;
        if (radiusSq <= hourBound(ring, source) && position < hourEnd) {
            slot += HOUR;
        }
        if (radiusSq > minuteBound(ring, source) && position < minuteEnd) {
            slot += MINUTE;
        }
        return slot;
    }

    //! Is the dot lit at all, in the split style? Split never reaches BOTH —
    //! the bounds tile the ring — so lit is any slot but NEITHER.
    function isLit(ring as Number, dx as Number, dy as Number,
                   position as Float, hourEnd as Float,
                   minuteEnd as Float) as Boolean {
        return slotOf(ring, dx, dy, position, hourEnd, minuteEnd,
                      Source.SOURCE_TIME) != NEITHER;
    }
}
