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
//! A ring may also carry the **hourly rain forecast**, which is the one source
//! that does not light an arc. Its ring is twelve blocks of 30 degrees, one per
//! hour ahead, and how far each block reaches out through the ring's own
//! thickness is the chance of rain in that hour. That needs a radius as well as
//! an angle, so it gets its own loop rather than a branch in the one below, and
//! its payload arrives beside the spans rather than inside them. It never
//! deltas: it changes once an hour, and evaluating the previous frame's
//! lit-ness per dot would cost more than the draws it saved.
//!
//! A ring may also be *over* — past a goal it can beat, running a second lap.
//! That costs the dot loop nothing at all. Such a ring is full by definition, so
//! its unfilled tier has nothing left to say; the span already describes the
//! overflow, and the two colours the loop reads are simply swapped underneath
//! it — unfilled becomes "goal met", filled becomes "gone past it". Four
//! assignments a frame, hoisted with everything else, and the innermost
//! statement in the face is untouched.
//!
//! Grouping also keeps the pen still. The renderer only calls setColor when the
//! colour actually changes, and because each ring keeps the lattice's scan
//! order, its dots arrive in whole rows — so a run of them on the same side of
//! the fill's leading edge shares a colour, instead of alternating every few
//! dots as it did when the rings interleaved.
//!
//! The lattice is deliberately not cached to a BufferedBitmap, though **not
//! for the memory reason this comment used to give**. A full-screen 390x390
//! buffer allocates fine and costs the app heap 616 bytes, because the
//! graphics pool is separate from it. What rules it out is frame cost:
//! presenting such a buffer measured ~20ms against the 36ms of the whole
//! one-ring redraw it would replace. See ROADMAP Phase 4.
module MatrixRenderer {

    //! Which mark each ring currently has on screen, so a ring being
    //! repainted can rub out the one it drew last time.
    //!
    //! A mark is a solid block and a dot is a cross, so repainting a ring
    //! covers only 9 of the 25 pixels a mark occupies — the other 16 would
    //! survive as a ghost of the previous reading. Blacking the cell first is
    //! what stops that, and it is done whether or not the mark moved: the ring
    //! is being fully repainted anyway, so erase-then-draw is the same picture
    //! either way and needs no reasoning about which frame a move landed on.
    var drawnMark as Array<Number> = [] as Array<Number>;

    //! The cell each ring marked *before* that, still owed an erase.
    //!
    //! One slot is not enough once a change is repeated into HOLD draws. Say
    //! the mark moves P to Q. The first draw rubs out P and lands in one
    //! buffer; the second draw is for the *other* buffer, and with only
    //! drawnMark to go on it would rub out Q — leaving P's sixteen stray
    //! pixels in that buffer with nothing but a nine-pixel cross over them.
    //! So both cells are rubbed out on every repaint, which costs one extra
    //! fillRectangle on a marked ring and needs no reasoning about which
    //! buffer this draw is for.
    var previousMark as Array<Number> = [] as Array<Number>;

    //! Which rings the last draw actually walked, and how many marks it rubbed
    //! out. Four writes and an integer per frame.
    //!
    //! Here because the central claim of the per-ring gate — that a ring which
    //! did not move is not walked — is otherwise unassertable. The screen
    //! cannot be read back: Dc has no getPixel, and a simulator screenshot
    //! needs a titled window, which is a permission away from being available.
    //! So the renderer says what it did, and a test holds it to the dirty set
    //! it was handed.
    var walked as Array<Boolean> = new [StatMap.RINGS] as Array<Boolean>;
    var erased as Number = 0;

    //! How many dots the last draw actually put down. The delta redraw's whole
    //! claim is that this is a handful rather than a ring, and like `walked` it
    //! is otherwise unassertable: the screen cannot be read back.
    var painted as Number = 0;

    //! **The span each ring was last drawn with, and the one before that.**
    //!
    //! A dirty ring used to be repainted in full. Measured, the two drawLine
    //! calls per dot are ~55% of a drawn frame — and between one draw and the
    //! next a seconds ring moves its edge about five dots. So the ring is still
    //! *walked*, which is cheap, and only the dots whose lit-ness actually
    //! changed are drawn.
    //!
    //! Two spans rather than one, for exactly the reason `previousMark` keeps
    //! two cells. A partial draw is only correct in the buffer it lands in, and
    //! on a double-buffered device that buffer was last written two draws ago —
    //! which is why FrameGate repeats every change into `HOLD` draws. So a dot
    //! is repainted when it differs from *either* remembered span: that set is
    //! right for whichever of the two buffers this draw is for, and needs no
    //! reasoning about which one that is.
    var lastFrom as Array<Float> = [] as Array<Float>;
    var lastTo as Array<Float> = [] as Array<Float>;
    var priorFrom as Array<Float> = [] as Array<Float>;
    var priorTo as Array<Float> = [] as Array<Float>;

    //! Everything about a ring that is *not* its span, folded into one key.
    //!
    //! The span is the only thing a delta may differ by. Its two colours, the
    //! over flag, whether it draws the ramp and what the hands are backed with
    //! all repaint the ring wholesale, and a delta would leave the other tier
    //! stale. Rather than enumerate the settings that can move them — power
    //! mode, theme, a ring reassignment — the values themselves are compared,
    //! so a cause nobody thought of cannot slip through.
    var lastWeak as Array<Number> = [] as Array<Number>;
    var lastStrong as Array<Number> = [] as Array<Number>;
    var lastBacking as Array<Number> = [] as Array<Number>;
    var lastOver as Array<Boolean> = [] as Array<Boolean>;
    var lastRamp as Array<Boolean> = [] as Array<Boolean>;

    //! Consecutive draws this ring has been drawn with the key above unchanged.
    //!
    //! A delta needs **two**: both buffers must already hold this ring in these
    //! colours, or the one this draw is not landing in keeps a tier that no
    //! longer exists. Counting is what makes that checkable without storing a
    //! second copy of every value.
    var stableFor as Array<Number> = [] as Array<Number>;

    //! Whether each ring drew the hourly forecast last time.
    //!
    //! Part of the key above, and it has to be, because the palette is keyed by
    //! *ring* rather than by source: switching a ring from battery to the
    //! forecast changes neither of its two colours, so nothing else in the key
    //! moves. The direction that bites is the other one — hourly back to
    //! battery leaves blocks, gutters and dim dots in a buffer while the
    //! remembered spans describe the EMPTY span an hourly ring reports, and a
    //! delta would skip every dot that is unlit under both.
    var lastHourly as Array<Boolean> = [] as Array<Boolean>;

    //! Per-block scratch for an hourly ring: the squared radius each block is
    //! lit out to, and the colour its unlit dots take.
    //!
    //! Resolved twelve times per drawn hourly ring instead of once per dot, so
    //! the inner loop is left with one array lookup and one comparison. Both
    //! carry a thirteenth entry mirroring the first: a position is 0.0 up to
    //! but not including 1.0 by construction, so the block index cannot reach
    //! 12 — but float arithmetic near the wrap is exactly the kind of thing
    //! that produces one once on a watch and never in a test, and a spare slot
    //! is cheaper than a bounds check on every dot.
    var hourEdge as Array<Number> = [] as Array<Number>;
    var hourUnlit as Array<Number> = [] as Array<Number>;

    function draw(dc as Dc, spans as Array<Array<Float> >,
                  markers as Array<Float>, overs as Array<Boolean>,
                  hourly as Array<Number>,
                  palette as Array<Number>, ramp as Array<Number>,
                  backing as Number?,
                  dirty as Array<Boolean>, clears as Boolean) as Void {
        // Normally a no-op: onLayout has already built the cache. This is the
        // safety net for a settings change, which comes back through onShow.
        DotGrid.ensureBuilt();

        // Anti-aliasing is sticky on the Dc, and it is ruinous here: measured,
        // the same frame costs about four times as much with it on, because a
        // cross turned to follow its ring is mostly diagonal strokes. The dots
        // are meant to be crisp anyway, so it is turned off explicitly rather
        // than left to whatever the last drawer wanted.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);
        }
        // Only when something moved every dot at once. A frame that repaints
        // one ring must leave the other three where they are, which is the
        // whole point of being told which are dirty.
        if (clears) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
        }
        if (drawnMark.size() != StatMap.RINGS) {
            drawnMark = new [StatMap.RINGS] as Array<Number>;
            previousMark = new [StatMap.RINGS] as Array<Number>;
            lastFrom = new [StatMap.RINGS] as Array<Float>;
            lastTo = new [StatMap.RINGS] as Array<Float>;
            priorFrom = new [StatMap.RINGS] as Array<Float>;
            priorTo = new [StatMap.RINGS] as Array<Float>;
            lastWeak = new [StatMap.RINGS] as Array<Number>;
            lastStrong = new [StatMap.RINGS] as Array<Number>;
            lastBacking = new [StatMap.RINGS] as Array<Number>;
            lastOver = new [StatMap.RINGS] as Array<Boolean>;
            lastRamp = new [StatMap.RINGS] as Array<Boolean>;
            lastHourly = new [StatMap.RINGS] as Array<Boolean>;
            stableFor = new [StatMap.RINGS] as Array<Number>;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                drawnMark[ring] = -1;
                previousMark[ring] = -1;
                lastFrom[ring] = 0.0;
                lastTo[ring] = 0.0;
                priorFrom[ring] = 0.0;
                priorTo[ring] = 0.0;
                lastWeak[ring] = -1;
                lastStrong[ring] = -1;
                lastBacking[ring] = -1;
                lastOver[ring] = false;
                lastRamp[ring] = false;
                lastHourly[ring] = false;
                stableFor[ring] = 0;
            }
        }
        if (hourEdge.size() != HourBands.HOURS + 1) {
            hourEdge = new [HourBands.HOURS + 1] as Array<Number>;
            hourUnlit = new [HourBands.HOURS + 1] as Array<Number>;
        }
        if (clears && drawnMark.size() == StatMap.RINGS) {
            // The screen is black; nothing is on it to rub out.
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                drawnMark[ring] = -1;
                previousMark[ring] = -1;
            }
        }


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
        var markerColour = Palette.markerOf;
        var overColour = Palette.overOf;
        var dimColour = Palette.dimOf;
        var bandEdge = DotGrid.bandEdge;

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
        // The backing folded into one comparable value, so a ring can tell
        // "the hands were backed white last draw" from "they were not backed
        // at all" with one integer. -1 is off; a colour is any real value.
        var backingKey = (backing != null) ? backing : -1;

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

        var half = DotGrid.DOT / 2;
        var lastColour = -1;
        erased = 0;
        painted = 0;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            walked[ring] = dirty[ring];
            if (!dirty[ring]) {
                // Already on screen and still correct. Not walking it is the
                // saving; note that its mark stays put too, which is why
                // drawnMark is only touched for the rings being repainted.
                markAt[ring] = -1;
                continue;
            }
            // Rub out every cell this ring may still have a mark in, before
            // its dots go back down over them. Both slots, every time — see
            // previousMark for why one is not enough.
            for (var slot = 0; slot < 2; slot++) {
                var stale = (slot == 0) ? drawnMark[ring] : previousMark[ring];
                if (stale < 0) {
                    continue;
                }
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(centreX + xs[stale] - half,
                                 centreY + ys[stale] - half,
                                 DotGrid.DOT, DotGrid.DOT);
                lastColour = Graphics.COLOR_BLACK;
                erased++;
            }
            // Everything this ring's dots share, read once instead of ~280
            // times: where its span starts and ends, whether it wraps past the
            // origin, its two colours, and whether it draws the ramp.
            var span = spans[ring];
            var from = span[0];
            var to = span[1];
            var wraps = (from > to);
            var weak = palette[ring * 2];
            var strong = palette[ring * 2 + 1];
            // Past the goal, the span describes the second lap rather than the
            // fill, so the two tiers are re-pointed to match. The ring is full
            // either way, which is why its unfilled tier is free to be reused:
            // "not yet in the overflow" is exactly "goal met".
            if (overs[ring]) {
                weak = strong;
                strong = overColour[ring];
            }
            var isRamp = (rings[ring] == Source.SOURCE_TEMPERATURE);
            var isHourly = (rings[ring] == Source.SOURCE_RAIN_HOURS);
            var last = ringStart[ring + 1];

            // Twelve blocks resolved once, not once per dot. A block reaching
            // tier t is lit out to that sub-band's squared edge; tier 0 and an
            // unknown hour are lit to zero, which no dot can be inside since
            // none sits closer to the centre than the hub.
            if (isHourly) {
                var levels = hourly[ring * StatMap.HOURLY_VALUES];
                var known = hourly[ring * StatMap.HOURLY_VALUES + 1];
                var edgeBase = ring * HourBands.BANDS;
                var dim = dimColour[ring];
                for (var b = 0; b < HourBands.HOURS; b++) {
                    var tier = HourBands.tierOf(levels, known, b);
                    if (tier == HourBands.UNKNOWN) {
                        hourEdge[b] = 0;
                        hourUnlit[b] = dim;
                    } else {
                        hourEdge[b] = (tier == 0)
                            ? 0 : bandEdge[edgeBase + tier - 1];
                        hourUnlit[b] = weak;
                    }
                }
                hourEdge[HourBands.HOURS] = hourEdge[0];
                hourUnlit[HourBands.HOURS] = hourUnlit[0];
            }

            // Is this ring's span the only thing that moved since it was last
            // drawn, and has it been so for both of the draws sitting in the
            // two buffers? Then the dots that agree with both remembered spans
            // are already on screen, in the right colour, in whichever buffer
            // this draw is for — and drawing them again is the cost this whole
            // change exists to remove.
            //
            // `clears` rules a delta out on its own: the screen has just been
            // blacked, so nothing is on it to keep.
            // An hourly ring opts out of the delta outright. The delta exists
            // to spare the two drawLine calls on a ring whose edge moves about
            // five dots a second; this one moves once an hour, and when it does
            // the change is a whole block or several. Evaluating the previous
            // lit-ness per dot would need a second block index, a second table
            // lookup and a second radius test — roughly doubling the expensive
            // half of the loop, every frame the ring is walked, to save draws on
            // a once-an-hour event.
            //
            // Because it never deltas, its masks need not join the key below:
            // being in the frame print is what makes the ring dirty, and a
            // dirty hourly ring is always repainted in full.
            var delta = !clears && !isHourly && stableFor[ring] >= 2 &&
                        lastWeak[ring] == weak && lastStrong[ring] == strong &&
                        lastOver[ring] == overs[ring] &&
                        lastRamp[ring] == isRamp &&
                        lastHourly[ring] == isHourly &&
                        lastBacking[ring] == backingKey;
            var fromA = lastFrom[ring];
            var toA = lastTo[ring];
            var wrapsA = (fromA > toA);
            var fromB = priorFrom[ring];
            var toB = priorTo[ring];
            var wrapsB = (fromB > toB);
            // The cells the mark erase just blacked. Their dots are owed a
            // cross whatever the span did, or a delta leaves a hole where the
            // mark was.
            var forceA = delta ? drawnMark[ring] : -1;
            var forceB = delta ? previousMark[ring] : -1;

            // Remember what this draw is about to put down, before the loop
            // consumes the locals. A ring drawn with the same key as last time
            // is one draw closer to being delta-eligible; anything else starts
            // the count again, which is what costs a changed ring its two full
            // repaints and gives HOLD something to be right about.
            stableFor[ring] = (lastWeak[ring] == weak &&
                               lastStrong[ring] == strong &&
                               lastOver[ring] == overs[ring] &&
                               lastRamp[ring] == isRamp &&
                               lastHourly[ring] == isHourly &&
                               lastBacking[ring] == backingKey)
                            ? stableFor[ring] + 1 : 1;
            lastWeak[ring] = weak;
            lastStrong[ring] = strong;
            lastOver[ring] = overs[ring];
            lastRamp[ring] = isRamp;
            lastHourly[ring] = isHourly;
            lastBacking[ring] = backingKey;
            priorFrom[ring] = fromA;
            priorTo[ring] = toA;
            lastFrom[ring] = from;
            lastTo[ring] = to;

            // Which dot this ring marks. The dot loop below never learns
            // about it: the mark is drawn afterwards, so the innermost
            // statement in the face is exactly what it was before marks
            // existed. DotGrid remembers the answer between frames — placing a
            // mark walks the whole ring, and the mark moves with the
            // temperature rather than with the frame.
            markAt[ring] = DotGrid.markedDotFor(ring, markers[ring]);

            // The hourly forecast walks its ring in its own loop, and the span
            // loop below is left byte-for-byte as it was. A branch inside that
            // one would be paid on all ~1100 dots to serve a ring that may not
            // exist, and the statement it guards is the innermost in the face.
            //
            // `continue` is safe here because markAt is already assigned and
            // nothing else follows the dot loop inside the ring loop; the marks
            // are drawn in their own pass afterwards.
            if (isHourly) {
                for (var i = ringStart[ring]; i < last; i++) {
                    var dx = xs[i];
                    var dy = ys[i];
                    var colour;
                    if (hasBacking && HandBacking.covers(dx, dy, hourX, hourY,
                                                         minuteX, minuteY)) {
                        colour = backingColour;
                    } else {
                        // HourBands.litAt()'s body, inlined — the same trade
                        // litBetween gets, and the same obligation: HourBands
                        // keeps the readable definition and a test pins the
                        // two together at the block, gutter and band edges.
                        var at = positionOf[i] * HourBands.HOURS;
                        var block = at.toNumber();
                        if ((at - block) >= HourBands.FILL) {
                            colour = weak;              //! the gutter
                        } else if (dx * dx + dy * dy <= hourEdge[block]) {
                            colour = strong;
                        } else {
                            colour = hourUnlit[block];
                        }
                    }
                    if (colour != lastColour) {
                        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                        lastColour = colour;
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
                    painted++;
                }
                continue;
            }

            for (var i = ringStart[ring]; i < last; i++) {
                var position = positionOf[i];
                // StatMap.litBetween()'s body, inlined. This is the innermost
                // statement in the whole face.
                var lit = wraps
                    ? ((position >= from) || (position <= to))
                    : ((position >= from) && (position <= to));

                // The delta. A dot that reads the same against both remembered
                // spans is already correct in both buffers, so it is not drawn.
                // Two comparisons and a branch replace two native drawLine
                // calls, on all but the handful of dots the fill edge crossed.
                if (delta) {
                    var litA = wrapsA
                        ? ((position >= fromA) || (position <= toA))
                        : ((position >= fromA) && (position <= toA));
                    var litB = wrapsB
                        ? ((position >= fromB) || (position <= toB))
                        : ((position >= fromB) && (position <= toB));
                    if (lit == litA && lit == litB && i != forceA &&
                            i != forceB) {
                        continue;
                    }
                }

                var dx = xs[i];
                var dy = ys[i];
                var colour;

                // The hands win over the fill, so this is tested second but
                // decides first. A backed dot keeps its colour whatever the
                // span did — the hands only move on a minute, and that changes
                // the field print, which clears the screen and rules out a
                // delta — so letting one through the test above only costs it
                // a redundant repaint, never a wrong one.
                if (hasBacking && HandBacking.covers(dx, dy, hourX, hourY,
                                                     minuteX, minuteY)) {
                    colour = backingColour;
                } else if (lit) {
                    colour = isRamp
                        ? ramp[(position * rampTop).toNumber()]
                        : strong;
                } else {
                    colour = weak;
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
                painted++;
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
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (!dirty[ring]) {
                continue;
            }
            var at = markAt[ring];
            if (at != drawnMark[ring]) {
                // The mark moved. The cell it left is owed an erase in the
                // other buffer too, which the next held draw will do.
                previousMark[ring] = drawnMark[ring];
            }
            drawnMark[ring] = at;
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
