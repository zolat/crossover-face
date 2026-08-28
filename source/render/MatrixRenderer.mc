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
//! The dots are stored grouped by ring, so this walks one ring at a time. That
//! is what lets the whole per-ring decision — the span's two ends, whether it
//! wraps, the lit and unlit colours, and whether it is the temperature ramp —
//! hoist out of the dot loop, leaving two float comparisons where there used to
//! be four array lookups and a call into StatMap.isLit.
//!
//! Those two comparisons are the body of StatMap.litBetween(), inlined. That is
//! the same trade DotGrid.build() makes with the geometry, and it carries the
//! same obligation: StatMap keeps the readable definition, and a test asserts
//! the two agree at the span boundaries, where a copied comparison drifts.
//!
//! Grouping also keeps the pen still. The renderer only calls setColor when the
//! colour actually changes, and because each ring keeps the lattice's scan
//! order, a band layout's ring draws as two long runs — unfilled, then filled —
//! instead of alternating every few dots as it did when the rings interleaved.
//!
//! The lattice also cannot be cached to a BufferedBitmap: a full-screen
//! 390x390 buffer at 16bpp is ~304KB against a 128KB watch-face budget.
module MatrixRenderer {

    function draw(dc as Dc, spans as Array<Array<Float> >,
                  palette as Array<Number>, ramp as Array<Number>,
                  backing as Number?) as Void {
        // Normally a no-op: onLayout has already built the cache. This is the
        // safety net for a settings change, which comes back through onShow.
        DotGrid.ensureBuilt();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();


        // Drift shifts where dots are drawn, never which dots exist, so the
        // field translates rigidly instead of popping dots in and out.
        var drift = Drift.current();
        var centreX = (dc.getWidth() / 2) + drift[0];
        var centreY = (dc.getHeight() / 2) + drift[1];

        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var armOf = DotGrid.armOf;
        var arms = DotGrid.ARMS;
        var positionOf = DotGrid.positionOf;
        var ringStart = DotGrid.ringStart;
        var rings = StatMap.rings;
        var rampTop = Palette.RAMP_STEPS - 1;

        var axes = (backing != null) ? HandBacking.axes() : null;
        var backingColour = (backing != null) ? backing : 0;

        var lastColour = -1;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            // Everything this ring's dots share, read once instead of ~280
            // times: where its span starts and ends, whether it wraps past the
            // origin, its two colours, and whether it draws the ramp.
            var span = spans[ring];
            var from = span[0];
            var to = span[1];
            var wraps = (from > to);
            var weak = palette[ring * 2];
            var strong = palette[ring * 2 + 1];
            var isRamp = (rings[ring] == Source.SOURCE_TEMPERATURE);
            var last = ringStart[ring + 1];

            for (var i = ringStart[ring]; i < last; i++) {
                var dx = xs[i];
                var dy = ys[i];
                var colour;

                if (axes != null && HandBacking.covers(dx, dy, axes)) {
                    colour = backingColour;
                } else {
                    var position = positionOf[i];
                    // StatMap.litBetween()'s body, inlined. This is the
                    // innermost statement in the whole face.
                    var lit = wraps
                        ? ((position >= from) || (position <= to))
                        : ((position >= from) && (position <= to));
                    if (lit) {
                        colour = isRamp
                            ? ramp[(position * rampTop).toNumber()]
                            : strong;
                    } else {
                        colour = weak;
                    }
                }

                // Runs of dots share a colour, so only change pen when it
                // actually differs.
                if (colour != lastColour) {
                    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                    lastColour = colour;
                }
                // A cross of two strokes through the dot's centre. In the rings
                // layout each dot's pair is turned to follow the circle it sits
                // on; elsewhere they stay upright. drawLine measured *faster*
                // than the two fillRectangle calls this replaced.
                var x = centreX + dx;
                var y = centreY + dy;
                var a = armOf[i];
                var ax = arms[a];
                var ay = arms[a + 1];
                var bx = arms[a + 2];
                var by = arms[a + 3];
                dc.drawLine(x - ax, y - ay, x + ax, y + ay);
                dc.drawLine(x - bx, y - by, x + bx, y + by);
            }
        }
    }
}
