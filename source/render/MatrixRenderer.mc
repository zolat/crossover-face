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
//! inside today's low-to-high. It is a single dot: a whole row of them, drawn
//! out of crosses, reads as a bumpy dotted band rather than a line, and a
//! radial run of dots on a square lattice staggers instead of lining up. The
//! dot is chosen once per ring by DotGrid.markedDot() and drawn after the loop,
//! so the loop itself never learns marks exist.
//!
//! Grouping also keeps the pen still. The renderer only calls setColor when the
//! colour actually changes, and because each ring keeps the lattice's scan
//! order, its dots arrive in whole rows — so a run of them on the same side of
//! the fill's leading edge shares a colour, instead of alternating every few
//! dots as it did when the rings interleaved.
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
        // cross turned to follow its ring is mostly diagonal strokes. The dots are
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
        var markerColour = Palette.markerOf;

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

        // Whether the crosses follow their rings, read once. Upright, every
        // dot shares one orientation, so hoisting it here rather than reading
        // armOf per dot saves five array lookups on all ~1100 of them — the
        // orientations stay cached either way, because which way a cross
        // points is geometry and this setting only decides whether to use it.
        var turned = (StatMap.rotation == StatMap.ROTATION_RADIAL);
        var ax = arms[0];
        var ay = arms[1];
        var bx = arms[2];
        var by = arms[3];

        var markAt = new [StatMap.RINGS] as Array<Number>;

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

            // Which dot this ring marks, found once here. The dot loop below
            // never learns about it: the mark is drawn afterwards, so the
            // innermost statement in the face is exactly what it was before
            // marks existed.
            var mark = markers[ring];
            markAt[ring] = (mark >= 0.0)
                ? DotGrid.markedDot(
                      ring, StatMap.windowAround(mark, markerHalf[ring]))
                : -1;

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
                // A cross of two strokes through the dot's centre, turned to
                // follow the circle it sits on unless the setting says upright.
                // drawLine measured *faster* than the two fillRectangle calls
                // this replaced.
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
        }

        // The marks, last, so each covers whatever the loop drew there.
        // At most one per ring, so this costs four tests a frame rather than
        // anything per dot.
        //
        // Filled, not a cross. Every other dot on the face is two thin
        // strokes, so a white cross among them is just another cross — it was
        // tried and it vanished. A solid block is the only shape on the field
        // that is not a cross, and that, rather than the colour, is what makes
        // it read as a mark. Nine lit pixels become twenty-five, on one dot.
        var half = DotGrid.DOT / 2;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var at = markAt[ring];
            if (at < 0) {
                continue;
            }
            var dx = xs[at];
            var dy = ys[at];
            // The hands still win: a marked dot under one stays backed.
            if (hasBacking && HandBacking.covers(dx, dy, hourX, hourY,
                                                 minuteX, minuteY)) {
                continue;
            }
            dc.setColor(markerColour[ring], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(centreX + dx - half, centreY + dy - half,
                             DotGrid.DOT, DotGrid.DOT);
        }
    }
}
