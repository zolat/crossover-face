import Toybox.Graphics;
import Toybox.Lang;

//! Draws the dot field. Awake and always-on differ only in which palette they
//! are handed, so there is one renderer rather than two.
//!
//! The lattice cannot be cached to a BufferedBitmap: a full-screen 390x390
//! buffer at 16bpp is ~304KB against a 128KB watch-face budget. Every dot is
//! drawn each frame, which is why they are square (fillRectangle) and why the
//! inside-circle test avoids a square root.
module MatrixRenderer {

    function draw(dc as Dc, spans as Array<Array<Float> >,
                  palette as Array<Number>, backing as Number?,
                  dim as Float) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var centreX = dc.getWidth() / 2;
        var centreY = dc.getHeight() / 2;
        var size = DotGrid.DOT;
        var half = size / 2;

        // Burn-in drift shifts where dots are drawn, never which dots exist —
        // so the field translates rigidly instead of popping at the rim.
        var drift = Drift.current();
        var shiftX = centreX - half + drift[0];
        var shiftY = centreY - half + drift[1];

        // Hand axes cost two trig calls, so they are computed per frame rather
        // than per dot; the test itself is then only dot products.
        var axes = (backing != null) ? HandBacking.axes() : null;
        var lastColour = -1;

        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            var y = shiftY + dy;

            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }

                var colour;
                if (axes != null && HandBacking.covers(dx, dy, axes)) {
                    colour = backing as Number;
                } else {
                    colour = dotColour(col, dx, dy, spans, palette, dim);
                }
                // Runs of dots share a colour, especially in the band layouts,
                // so only change pen when it actually differs. With ~1100 dots
                // a frame this saves far more calls than it costs.
                if (colour != lastColour) {
                    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                    lastColour = colour;
                }
                // A cross, not a square: two strokes through the dot's centre.
                dc.fillRectangle(shiftX + dx, y + half, size, 1);
                dc.fillRectangle(shiftX + dx + half, y, 1, size);
            }
        }
    }

    //! Colour for one dot. Temperature is the one source drawn on a ramp
    //! rather than a flat hue, so the band reads as cold-to-hot instead of
    //! just as a length.
    function dotColour(col as Number, dx as Number, dy as Number,
                       spans as Array<Array<Float> >, palette as Array<Number>,
                       dim as Float) as Number {
        var slot = StatMap.classify(col, dx, dy, spans);
        var lit = (slot % 2) == 1;
        if (lit && StatMap.rings[slot / 2] == Source.SOURCE_TEMPERATURE) {
            var colour = Palette.temperature(StatMap.positionOf(dx, dy));
            return (dim < 1.0) ? Palette.scale(colour, dim) : colour;
        }
        return palette[slot];
    }
}
