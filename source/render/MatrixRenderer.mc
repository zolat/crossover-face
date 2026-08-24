import Toybox.Graphics;
import Toybox.Lang;

//! Draws the dot field. The only difference between awake and always-on is
//! which palette it is handed, so there is one renderer rather than two that
//! differ by a constant.
//!
//! The lattice cannot be cached to a BufferedBitmap: a full-screen 390x390
//! buffer at 16bpp is ~304 KB against a 128 KB watch-face budget. So every dot
//! is drawn each frame, which is why they are square (fillRectangle) and why
//! the inside-circle test avoids a square root.
module MatrixRenderer {

    //! backing is the colour to give dots lying under the analogue hands, or
    //! null to leave them alone. Only ever set while the watch is awake.
    function draw(dc as Dc, values as Array<Float>, palette as Array<Number>,
                  backing as Number?) as Void {
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
                    colour = palette[StatMap.classify(col, dx, dy, values)];
                }
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(shiftX + dx, y, size, size);
            }
        }
    }
}
