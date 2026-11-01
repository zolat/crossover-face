import Toybox.Graphics;
import Toybox.Lang;

//! The time, drawn as one ring split by radius: the hour fills the ring's
//! innermost sub-band and the minute its outer two, both clockwise from twelve.
//! Where both have passed the ring is whole; where one has, part of it; and the
//! two ends of the white are where the two hands would point.
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

    //! Walk one ring and paint every dot of it. Never a delta: the print moves
    //! once a minute, and drawAt() keeps the ring out of the delta path.
    //!
    //! `hourEnd` and `minuteEnd` are the ring's span — see Source.SOURCE_TIME.
    //! The pen colour is left wherever the last dot set it; the caller forgets
    //! its own cached pen afterwards.
    function draw(dc as Dc, ring as Number, centreX as Number,
                  centreY as Number, hourEnd as Float, minuteEnd as Float,
                  lit as Number, unlit as Number) as Void {
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
        // The innermost sub-band's outer edge, squared: the one number that
        // decides which hand a dot belongs to. Integer, like every edge the
        // block ring reads, so it agrees with the edges that made the ring.
        var split = DotGrid.bandEdge[ring * HourBands.BANDS];

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
            var end = (dx * dx + dy * dy <= split) ? hourEnd : minuteEnd;
            var colour = (positionOf[i] < end) ? lit : unlit;
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
            MatrixRenderer.painted++;
        }
    }

    //! Is the dot at (dx, dy), at this position round its ring, lit by the
    //! time? The readable definition of the loop above, for the tests.
    function isLit(ring as Number, dx as Number, dy as Number,
                   position as Float, hourEnd as Float,
                   minuteEnd as Float) as Boolean {
        var split = DotGrid.bandEdge[ring * HourBands.BANDS];
        return position < ((dx * dx + dy * dy <= split) ? hourEnd : minuteEnd);
    }
}
