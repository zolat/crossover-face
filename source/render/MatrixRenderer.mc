import Toybox.Graphics;
import Toybox.Lang;

//! Draws the dot field. Awake and always-on differ only in which palette they
//! are handed, so there is one renderer rather than two.
//!
//! This loop runs against a hard watchdog budget: roughly 1100 dots, every
//! frame, in interpreted bytecode. The rule that keeps it inside that budget
//! is that nothing is computed here which DotGrid could compute once — an
//! earlier version that worked out each dot's ring and position inline
//! tripped the watchdog outright.
//!
//! The one deliberate exception is StatMap.isLit(), called per dot rather than
//! inlined. Measured, that call costs about 6ms a frame. It buys a single
//! definition of what "inside the span" means, shared with the tests; the
//! inline copy it replaced had already drifted out of test coverage entirely.
//! At 0.06% CPU in always-on — where the face spends nearly all its life —
//! that is a trade worth making.
//!
//! The lattice also cannot be cached to a BufferedBitmap: a full-screen
//! 390x390 buffer at 16bpp is ~304KB against a 128KB watch-face budget.
module MatrixRenderer {

    function draw(dc as Dc, spans as Array<Array<Float> >,
                  palette as Array<Number>, ramp as Array<Number>,
                  backing as Number?) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var size = DotGrid.DOT;
        var half = size / 2;

        // Drift shifts where dots are drawn, never which dots exist, so the
        // field translates rigidly instead of popping dots in and out.
        var drift = Drift.current();
        var originX = (dc.getWidth() / 2) - half + drift[0];
        var originY = (dc.getHeight() / 2) - half + drift[1];

        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var ringOf = DotGrid.ringOf;
        var positionOf = DotGrid.positionOf;
        var count = DotGrid.count;
        var rings = StatMap.rings;
        var rampTop = Palette.RAMP_STEPS - 1;

        var axes = (backing != null) ? HandBacking.axes() : null;
        var backingColour = (backing != null) ? backing : 0;

        var lastColour = -1;
        for (var i = 0; i < count; i++) {
            var dx = xs[i];
            var dy = ys[i];
            var colour;

            if (axes != null && HandBacking.covers(dx, dy, axes)) {
                colour = backingColour;
            } else {
                var ring = ringOf[i];
                var span = spans[ring];
                var position = positionOf[i];
                if (StatMap.isLit(position, span)) {
                    colour = (rings[ring] == Source.SOURCE_TEMPERATURE)
                        ? ramp[(position * rampTop).toNumber()]
                        : palette[ring * 2 + 1];
                } else {
                    colour = palette[ring * 2];
                }
            }

            // Runs of dots share a colour, especially in the band layouts, so
            // only change pen when it actually differs.
            if (colour != lastColour) {
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                lastColour = colour;
            }
            // A cross: one horizontal stroke, one vertical.
            var x = originX + dx;
            var y = originY + dy;
            dc.fillRectangle(x, y + half, size, 1);
            dc.fillRectangle(x + half, y, 1, size);
        }
    }
}
