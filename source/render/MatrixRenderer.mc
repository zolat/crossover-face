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
//! A ring may also carry a *mark* — one position called out on top of the span,
//! which is how the temperature ring shows where the current reading falls
//! inside today's low-to-high. The mark is handed here as a position and turned
//! into an ordinary span once per ring, so it is lit by the same two
//! comparisons rather than by a lit test of its own.
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
                  markers as Array<Float>,
                  palette as Array<Number>, ramp as Array<Number>,
                  backing as Number?) as Void {
        // Normally a no-op: onLayout has already built the cache. This is the
        // safety net for a settings change, which comes back through onShow.
        DotGrid.ensureBuilt();

        // Anti-aliasing is sticky on the Dc, and it is ruinous here: measured,
        // the same frame costs about four times as much with it on, because a
        // cross in the rings layout is mostly diagonal strokes. The dots are
        // meant to be crisp anyway, so it is turned off explicitly rather than
        // left to whatever the last drawer wanted.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);
        }
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
        var markerHalf = DotGrid.markerHalf;
        var rings = StatMap.rings;
        var rampTop = Palette.RAMP_STEPS - 1;
        var markerColour = Palette.MARKER;

        // Unpack the hand axes once. With the backing on, covers() is the only
        // call left in the dot loop; reading its four floats out of an array
        // per dot as well would put most of that cost straight back.
        var hasBacking = (backing != null);
        var axes = hasBacking ? HandBacking.axes()
                              : ([0.0, 0.0, 0.0, 0.0] as Array<Float>);
        var hourX = axes[0];
        var hourY = axes[1];
        var minuteX = axes[2];
        var minuteY = axes[3];
        // Written as an explicit null test so the type narrows; hasBacking is
        // the same condition, kept for the dot loop.
        var backingColour = (backing != null) ? backing : 0;

        // Only the rings layout turns its crosses, so in the band layouts every
        // dot shares one orientation. Reading it here rather than per dot saves
        // five array lookups on every dot of two layouts out of three.
        var radial = (StatMap.layout == StatMap.LAYOUT_RINGS);
        var ax = arms[0];
        var ay = arms[1];
        var bx = arms[2];
        var by = arms[3];

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

            // The mark, hoisted the same way the span is. Rings with nothing to
            // mark leave `marked` false, and their dots pay one local read.
            var mark = markers[ring];
            var marked = (mark >= 0.0);
            var markFrom = 0.0;
            var markTo = 0.0;
            var markWraps = false;
            if (marked) {
                // An ordinary span, so the same two comparisons light it.
                var window = StatMap.windowAround(mark, markerHalf[ring]);
                markFrom = window[0];
                markTo = window[1];
                markWraps = (markFrom > markTo);
            }

            for (var i = ringStart[ring]; i < last; i++) {
                var dx = xs[i];
                var dy = ys[i];
                var colour;

                if (hasBacking && HandBacking.covers(dx, dy, hourX, hourY,
                                                     minuteX, minuteY)) {
                    colour = backingColour;
                } else {
                    var position = positionOf[i];
                    // StatMap.litBetween()'s body, inlined. This is the
                    // innermost statement in the whole face, and it appears
                    // twice here: once for the ring's span, once for the mark's
                    // window. litTestsAgreeAtTheBoundaries pins both to the
                    // readable definition.
                    if (marked && (markWraps
                            ? ((position >= markFrom) || (position <= markTo))
                            : ((position >= markFrom) && (position <= markTo)))) {
                        // The mark outranks the fill: it has to be legible
                        // whether or not now falls inside today's range.
                        colour = markerColour;
                    } else {
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
                if (radial) {
                    var a = armOf[i];
                    ax = arms[a];
                    ay = arms[a + 1];
                    bx = arms[a + 2];
                    by = arms[a + 3];
                }
                dc.drawLine(x - ax, y - ay, x + ax, y + ay);
                dc.drawLine(x - bx, y - by, x + bx, y + by);
            }
        }
    }
}
