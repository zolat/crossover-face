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

    function draw(dc as Dc, values as Array<Float>, palette as Array<Number>) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var centreX = dc.getWidth() / 2;
        var centreY = dc.getHeight() / 2;
        var size = DotGrid.DOT;
        var half = size / 2;

        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            var y = centreY + dy - half;

            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                dc.setColor(palette[StatMap.classify(col, dx, dy, values)],
                            Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(centreX + dx - half, y, size, size);
            }
        }
    }
}
