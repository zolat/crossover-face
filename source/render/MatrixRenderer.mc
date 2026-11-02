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
//! dot is chosen once per ring by DotGrid.markedDotFor() and drawn after the
//! loop, so the loop itself never learns marks exist. The sun dots on the
//! temperature-and-sun ring are two more of the same, placed by
//! DotGrid.sunDotFor() at the ring's edges.
//!
//! A ring may also carry **blocks** rather than an arc — twelve of them, one
//! per clock position, each filled from the ring's inner edge outward through
//! its three sub-bands and then partway across its own width. That is a level
//! per block on a sixteen-step scale, and it needs a radius and a window as
//! well as an angle, so it gets its own loop rather than a branch in the one
//! below, and its payload arrives beside the spans rather than inside them.
//! The renderer never learns *which* source filled those blocks — today the
//! twelve-hour rain forecast, tomorrow whatever else has one reading an hour.
//! It never deltas: it changes once an hour, and evaluating the previous
//! frame's lit-ness per dot would cost more than the draws it saved.
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
//! The lattice is cached in the view's buffered frame. This renderer mutates
//! that one authoritative surface; the view then blits it whole onto every
//! transient screen surface Garmin supplies.
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

    //! Which sun dots each ring has on screen: Source.SUN_VALUES per ring,
    //! sunrise then sunset, flat. -1 for none.
    //!
    //! Rubbed out only when one *moves*, unlike the mark, and that move costs
    //! the ring its delta for one frame. A sun time shifts by a minute a day,
    //! so the dot changes perhaps once a week — paying a full ring repaint then
    //! is free, where forcing two more indices through the delta's per-dot test
    //! would be paid on every dot of every ring. A sun dot that stayed put is
    //! simply drawn over again after the loop, which covers whatever cross the
    //! loop may have put back underneath it.
    var drawnSun as Array<Number> = [] as Array<Number>;

    //! How many sun dots the last draw put down. Like `painted`, a claim the
    //! screen cannot be read back to check.
    var sunsDrawn as Number = 0;

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

    //! How many of those were the date's own dots, whose colour the draw
    //! recorded into `DateGlyph.colours` for the outline to be inked in.
    //!
    //! Here for the reason `painted` and `walked` are: the screen cannot be
    //! read back, so the claim that exactly the numeral's dots are recorded and
    //! no others is otherwise unassertable — and a dot missed here is a stretch
    //! of the outline that silently never draws.
    var recorded as Number = 0;

    //! **The span each ring was last drawn with.**
    //!
    //! A dirty ring used to be repainted in full. Measured, the two drawLine
    //! calls per dot are ~55% of a drawn frame — and between one draw and the
    //! next a seconds ring moves its edge about five dots. So the ring is still
    //! *walked*, which is cheap, and only the dots whose lit-ness actually
    //! changed are drawn.
    //!
    //! One span is enough because every partial draw targets the same buffer.
    //! A dot is repainted exactly when it differs from that authoritative
    //! previous value.
    var lastFrom as Array<Float> = [] as Array<Float>;
    var lastTo as Array<Float> = [] as Array<Float>;

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

    //! Whether this ring has been drawn at least once with the key above.
    //! A changed key forces one full ring; after that the buffer is authoritative
    //! and span-only changes may use the delta path immediately.
    var stableFor as Array<Number> = [] as Array<Number>;

    //! Whether each ring drew blocks rather than a span last time.
    //!
    //! Part of the key above, and it has to be, because the palette is keyed by
    //! *ring* rather than by source: switching a ring from battery to the
    //! forecast changes neither of its two colours, so nothing else in the key
    //! moves. The direction that bites is the other one — blocks back to
    //! battery leaves blocks, gutters and dim dots in a buffer while the
    //! remembered spans describe the EMPTY span a block ring reports, and a
    //! delta would skip every dot that is unlit under both.
    var lastBlocks as Array<Boolean> = [] as Array<Boolean>;

    //! Per-block scratch for a block ring: how far out each block is lit at
    //! full width, how far out its one partial band reaches, the two sides of
    //! that band's window, and the colour its unlit dots take.
    //!
    //! Resolved twelve times per drawn block ring instead of once per dot, so
    //! the inner loop is left with an array lookup and a comparison for the
    //! full bands and three more for the partial one. Every table carries a
    //! thirteenth entry mirroring the first: a position is 0.0 up to but not
    //! including 1.0 by construction, so the block index cannot reach 12 — but
    //! float arithmetic near the wrap is exactly the kind of thing that
    //! produces one once on a watch and never in a test, and a spare slot is
    //! cheaper than a bounds check on every dot.
    var blockFull as Array<Number> = [] as Array<Number>;
    var blockPart as Array<Number> = [] as Array<Number>;
    var blockLo as Array<Float> = [] as Array<Float>;
    var blockHi as Array<Float> = [] as Array<Float>;
    var blockUnlit as Array<Number> = [] as Array<Number>;

    //! Per-frame mark scratch, retained with the renderer's other tables.
    var markAt as Array<Number> = new [StatMap.RINGS] as Array<Number>;
    var sunDrawAt as Array<Number> =
        new [StatMap.RINGS * Source.SUN_VALUES] as Array<Number>;

    //! No ring shows a sun time. What draw() hands drawAt(), so the many
    //! callers that predate the sun channel need not learn it exists.
    //! Literals, because a const array initialised from other consts has come
    //! back empty on the watch; noSunsCoverEveryRing pins it to the shape.
    //! Long enough for five rings, the most any watch has; a four-ring watch
    //! reads the first eight.
    const NO_SUNS = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0,
                     -1.0, -1.0] as Array<Float>;

    //! Axes and turn positions ignored while hand backing is off. A constant
    //! avoids allocating a six-float placeholder on every drawn frame.
    const NO_AXES =
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] as Array<Float>;

    function draw(dc as Dc, spans as Array<Array<Float> >,
                  markers as Array<Float>, overs as Array<Boolean>,
                  blocks as Array<Number>,
                  palette as Array<Number>, ramp as Array<Number>,
                  backing as Number?,
                  dirty as Array<Boolean>, clears as Boolean) as Void {
        drawAt(dc, spans, markers, NO_SUNS, overs, blocks, palette, ramp,
               backing, dirty, clears, Drift.current());
    }

    //! Draw with the drift snapshot already used by the frame fingerprint.
    //! The live view calls this path so it reads the clock once and cannot
    //! allocate or cross a drift boundary between planning and rendering.
    //! Which dots this ring's sun times land on this frame, into sunDrawAt,
    //! and true when either differs from the one on screen — whose cell is
    //! rubbed out here, before the ring is repainted over it.
    //!
    //! Its own function, not inline in drawAt(), for the stack's sake rather
    //! than readability's: Monkey C gives every local in a function a slot
    //! for the whole call, and drawAt() is already as wide a frame as the
    //! test runner's stack can hold — inlined, these few locals overflowed it.
    function placeSuns(dc as Dc, ring as Number, suns as Array<Float>,
                       centreX as Number, centreY as Number) as Boolean {
        var key = ring * Source.SUN_VALUES;
        var moved = false;
        for (var slot = 0; slot < Source.SUN_VALUES; slot++) {
            var at = DotGrid.sunDotFor(ring, slot, suns[key + slot]);
            var gone = drawnSun[key + slot];
            sunDrawAt[key + slot] = at;
            if (gone == at) {
                continue;
            }
            moved = true;
            if (gone >= 0) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(centreX + DotGrid.xs[gone] - DotGrid.DOT / 2,
                                 centreY + DotGrid.ys[gone] - DotGrid.DOT / 2,
                                 DotGrid.DOT, DotGrid.DOT);
                erased++;
            }
        }
        return moved;
    }

    //! The sun dots, after the dot loop and before the marks. Solid for the
    //! reason the mark is — a tinted cross vanishes among crosses — in a light
    //! yellow for the sun coming up and a blue for it going down, each mixed
    //! toward its ring's band (Palette.sunOf).
    //!
    //! The temperature mark outranks them. It is the ring's own reading, and
    //! on the innermost ring a mark window can be one dot wide, so when both
    //! land on the same dot the sun dot gives way. The hands outrank both, as
    //! they outrank the mark. `axes` is null when nothing is backed.
    function drawSuns(dc as Dc, dirty as Array<Boolean>,
                      centreX as Number, centreY as Number,
                      axes as Array<Float>?) as Void {
        var half = DotGrid.DOT / 2;
        for (var k = 0; k < sunDrawAt.size(); k++) {
            var ring = k / Source.SUN_VALUES;
            if (!dirty[ring]) {
                continue;
            }
            var at = sunDrawAt[k];
            drawnSun[k] = at;
            if (at < 0 || at == markAt[ring]) {
                continue;
            }
            var dx = DotGrid.xs[at];
            var dy = DotGrid.ys[at];
            if (axes != null && HandBacking.handAt(dx, dy, axes[0], axes[1],
                                                   axes[2], axes[3])
                    != HandBacking.NONE) {
                continue;
            }
            dc.setColor(Palette.sunOf[k], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(centreX + dx - half, centreY + dy - half,
                             DotGrid.DOT, DotGrid.DOT);
            sunsDrawn++;
        }
    }

    function drawAt(dc as Dc, spans as Array<Array<Float> >,
                    markers as Array<Float>, suns as Array<Float>,
                    overs as Array<Boolean>,
                    blocks as Array<Number>,
                    palette as Array<Number>, ramp as Array<Number>,
                    backing as Number?, dirty as Array<Boolean>,
                    clears as Boolean, drift as Array<Number>) as Void {
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
            lastFrom = new [StatMap.RINGS] as Array<Float>;
            lastTo = new [StatMap.RINGS] as Array<Float>;
            lastWeak = new [StatMap.RINGS] as Array<Number>;
            lastStrong = new [StatMap.RINGS] as Array<Number>;
            lastBacking = new [StatMap.RINGS] as Array<Number>;
            lastOver = new [StatMap.RINGS] as Array<Boolean>;
            lastRamp = new [StatMap.RINGS] as Array<Boolean>;
            lastBlocks = new [StatMap.RINGS] as Array<Boolean>;
            stableFor = new [StatMap.RINGS] as Array<Number>;
            drawnSun = new [StatMap.RINGS * Source.SUN_VALUES] as Array<Number>;
            for (var k = 0; k < drawnSun.size(); k++) {
                drawnSun[k] = -1;
            }
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                drawnMark[ring] = -1;
                lastFrom[ring] = 0.0;
                lastTo[ring] = 0.0;
                lastWeak[ring] = -1;
                lastStrong[ring] = -1;
                lastBacking[ring] = -1;
                lastOver[ring] = false;
                lastRamp[ring] = false;
                lastBlocks[ring] = false;
                stableFor[ring] = 0;
            }
        }
        if (blockFull.size() != HourBands.HOURS + 1) {
            blockFull = new [HourBands.HOURS + 1] as Array<Number>;
            blockPart = new [HourBands.HOURS + 1] as Array<Number>;
            blockLo = new [HourBands.HOURS + 1] as Array<Float>;
            blockHi = new [HourBands.HOURS + 1] as Array<Float>;
            blockUnlit = new [HourBands.HOURS + 1] as Array<Number>;
        }
        if (clears && drawnMark.size() == StatMap.RINGS) {
            // The screen is black; nothing is on it to rub out.
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                drawnMark[ring] = -1;
            }
            for (var k = 0; k < drawnSun.size(); k++) {
                drawnSun[k] = -1;
            }
        }


        // Drift shifts where dots are drawn, never which dots exist, so the
        // field translates rigidly instead of popping dots in and out.
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
        // Palette.markerOf and Palette.overOf are read where they are used,
        // once a ring, rather than hoisted: drawAt()'s frame sits at the test
        // runner's stack limit whenever build() runs inside it, and those two
        // slots buy nothing per dot — the dot counter below needs one.
        var dimColour = Palette.dimOf;
        var bandEdge = DotGrid.bandEdge;
        // Which hour block each dot sits in, cached by DotGrid.build(); only
        // the block loop reads it.
        var blockAt = DotGrid.blockAt;

        // Unpack the hand axes once. With the hands on, handAt() is the only
        // call left in the dot loop; reading its four floats out of an array
        // per dot as well would put most of that cost straight back.
        var hasBacking = (backing != null);
        var axes = hasBacking ? HandBacking.axes() : NO_AXES;
        var hourX = axes[0];
        var hourY = axes[1];
        var minuteX = axes[2];
        var minuteY = axes[3];
        // Written as an explicit null test so the type narrows; hasBacking is
        // the same condition, kept for the dot loop.
        var backingColour = (backing != null) ? backing : 0;
        // What each hand paints, indexed by the slot handAt() returns. Resolved
        // once a frame, not once a dot — the loop is left with an array lookup
        // where it used to have a colour, which is the same work.
        var handColour = HandBacking.coloursFor(backingColour);
        // The hand footprint, hoisted. handAt() keeps the readable definition
        // of the test below; these are the numbers its body reads, lifted out
        // so the inlined copy costs no lookups. They are consts, so this is
        // documentation as much as it is hoisting.
        var halfWidth = HandBacking.HALF_WIDTH;
        var behind = -HandBacking.COUNTERWEIGHT;
        var hourReach = HandBacking.HOUR_REACH;
        var minuteReach = HandBacking.MINUTE_REACH;
        var NO_HAND = HandBacking.NONE;
        // Where the hands point, in turns, from the same clock read that made
        // their axes. A second HandBacking call here used to allocate and read
        // the clock again on every drawn frame.
        var hourTurn = axes[4];
        var minuteTurn = axes[5];
        var ringInner = DotGrid.ringInner;
        var handHalf = DotGrid.handHalf;
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

        // The date, read the same way: which dots the numeral covers is a list
        // this module walks with a cursor, so the dot loop is left with one
        // integer comparison. Those dots are drawn like any other; the loop
        // only records the colour each one got, because the outline joining
        // them is inked in that colour afterwards (DateGlyph.drawContour). The
        // view decides whether this frame carries the date and brings DateGlyph
        // up to date before calling in — the renderer must not read the clock
        // for itself, for the reason the block channel must not either.
        var dating = DateGlyph.active && DateGlyph.lit > 0;
        var glyphIndex = DateGlyph.index;
        var glyphFirst = DateGlyph.firstFor;
        var glyphColour = DateGlyph.colours;

        var half = DotGrid.DOT / 2;
        var lastColour = -1;
        erased = 0;
        // Counted in a local and published once after the dot loops: the
        // increment runs on every dot drawn, and a module variable costs a
        // lookup each time that a local does not.
        var drew = 0;
        recorded = 0;
        sunsDrawn = 0;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            walked[ring] = dirty[ring];
            if (!dirty[ring]) {
                // Already on screen and still correct. Not walking it is the
                // saving; note that its mark stays put too, which is why
                // drawnMark is only touched for the rings being repainted.
                markAt[ring] = -1;
                continue;
            }
            // Rub out the cell this ring may still have a mark in, before its
            // dot goes back down over it on the same authoritative buffer.
            var stale = drawnMark[ring];
            if (stale >= 0) {
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
                strong = Palette.overOf[ring];
            }
            // The hands, narrowed to this ring. A hand that cannot reach the
            // ring's inner edge never touches it — the hour hand falls short of
            // ring 0 at every screen size — and one that can gets an angular
            // window sized for this ring's own innermost dots. The bar test in
            // the loop then runs on what is inside the window, which is a few
            // percent of it. See DotGrid.handHalf.
            var inner = hasBacking ? ringInner[ring] : 0;
            var hourHere = hasBacking && HandBacking.HOUR_REACH >= inner;
            var minuteHere = hasBacking && HandBacking.MINUTE_REACH >= inner;
            // StatMap.windowAround() inlined twice. These windows are made for
            // every ring of every drawn frame; keeping them as scalars avoids
            // up to eight temporary arrays and calls before the hot loop.
            var windowHalf = handHalf[ring];
            var hourFrom = 2.0;
            var hourTo = 2.0;
            if (hourHere) {
                if (windowHalf >= 0.5) {
                    hourFrom = 0.0;
                    hourTo = 1.0;
                } else {
                    hourFrom = hourTurn - windowHalf;
                    hourTo = hourTurn + windowHalf;
                    if (hourFrom < 0.0) { hourFrom += 1.0; }
                    if (hourTo >= 1.0) { hourTo -= 1.0; }
                }
            }
            var hourWraps = (hourFrom > hourTo);
            var minuteFrom = 2.0;
            var minuteTo = 2.0;
            if (minuteHere) {
                if (windowHalf >= 0.5) {
                    minuteFrom = 0.0;
                    minuteTo = 1.0;
                } else {
                    minuteFrom = minuteTurn - windowHalf;
                    minuteTo = minuteTurn + windowHalf;
                    if (minuteFrom < 0.0) { minuteFrom += 1.0; }
                    if (minuteTo >= 1.0) { minuteTo -= 1.0; }
                }
            }
            var minuteWraps = (minuteFrom > minuteTo);

            var isRamp = Source.isTemperatureRange(rings[ring]);
            var isBlocks = Source.usesBlocks(rings[ring]);
            // A ring telling the time draws white over its colour at the
            // unknown-hour rung, in every power mode. Swapped into the ring's
            // two tiers before the delta key reads them, so a ring that starts
            // or stops telling the time is repainted whole like any recolour.
            //
            // Asked of Source three times a ring rather than held in a local:
            // drawAt()'s frame is at the test runner's stack limit, and one
            // more local overflowed it. Three calls a ring cost nothing.
            if (Source.isTime(rings[ring])) {
                weak = dimColour[ring];
                strong = Palette.TIME_LIT;
            }
            var last = ringStart[ring + 1];

            // Twelve blocks resolved once, not once per dot. A level fills
            // whole sub-bands out to their squared edges, and then part of the
            // way across the next band out — an edge and a window, both of
            // which the dot loop only has to compare against. A zero edge is
            // lit to nothing, which no dot can be inside since none sits
            // closer to the centre than the hub, so level 0 and an unknown
            // block need no branch of their own down there.
            if (isBlocks) {
                var lo = blocks[ring * StatMap.BLOCK_VALUES];
                var hi = blocks[ring * StatMap.BLOCK_VALUES + 1];
                var known = blocks[ring * StatMap.BLOCK_VALUES + 2];
                var edgeBase = ring * HourBands.BANDS;
                var dim = dimColour[ring];
                for (var b = 0; b < HourBands.HOURS; b++) {
                    var level = HourBands.levelAt(lo, hi, known, b);
                    if (level == HourBands.UNKNOWN) {
                        blockFull[b] = 0;
                        blockPart[b] = 0;
                        blockLo[b] = 0.0;
                        blockHi[b] = 0.0;
                        blockUnlit[b] = dim;
                        continue;
                    }
                    var full = HourBands.fullBandsFor(level);
                    var window = HourBands.partialHalfOn(level, ring);
                    blockFull[b] = (full == 0) ? 0 : bandEdge[edgeBase + full - 1];
                    // A level landing exactly on a band edge has no partial
                    // band, and that is also what keeps the lookup in range:
                    // the top of the scale fills every band, so there is no
                    // band above it to read.
                    blockPart[b] = (window > 0.0)
                        ? bandEdge[edgeBase + full] : 0;
                    blockLo[b] = HourBands.BLOCK_CENTRE - window;
                    blockHi[b] = HourBands.BLOCK_CENTRE + window;
                    blockUnlit[b] = weak;
                }
                blockFull[HourBands.HOURS] = blockFull[0];
                blockPart[HourBands.HOURS] = blockPart[0];
                blockLo[HourBands.HOURS] = blockLo[0];
                blockHi[HourBands.HOURS] = blockHi[0];
                blockUnlit[HourBands.HOURS] = blockUnlit[0];
            }

            // Is this ring's span the only thing that moved since it was last
            // drawn? Then the dots that agree with the remembered span are
            // already correct in the buffer, and drawing them again is the cost
            // this whole change exists to remove.
            //
            // `clears` rules a delta out on its own: the screen has just been
            // blacked, so nothing is on it to keep.
            // A block ring opts out of the delta outright. The delta exists
            // to spare the two drawLine calls on a ring whose edge moves about
            // five dots a second; this one moves once an hour, and when it does
            // the change is a whole block or several. Evaluating the previous
            // lit-ness per dot would need a second set of five tables and a
            // second window test — more than doubling the expensive half of the
            // loop, every frame the ring is walked, to save draws on a
            // once-an-hour event.
            //
            // Because it never deltas, its packed words need not join the key
            // below: being in the frame print is what makes the ring dirty, and
            // a dirty block ring is always repainted in full.
            // The sun dots, placed now rather than with the mark below, because
            // whether they moved decides whether this ring may delta at all.
            // A moved one has its old cell blacked and the whole ring
            // repainted, which puts that dot's cross back without the delta
            // having to know about it.
            var sunMoved = placeSuns(dc, ring, suns, centreX, centreY);
            if (sunMoved) {
                lastColour = -1;    //! the erase moved the pen
            }

            // The time ring opts out for the block ring's reason: its print
            // moves once a minute, and its lit test reads a radius as well as
            // a position, which the span delta below cannot say.
            var delta = !clears && !isBlocks && !Source.isTime(rings[ring]) &&
                        !sunMoved &&
                        stableFor[ring] >= 1 &&
                        lastWeak[ring] == weak && lastStrong[ring] == strong &&
                        lastOver[ring] == overs[ring] &&
                        lastRamp[ring] == isRamp &&
                        lastBlocks[ring] == isBlocks &&
                        lastBacking[ring] == backingKey;
            var fromA = lastFrom[ring];
            var toA = lastTo[ring];
            var wrapsA = (fromA > toA);
            // The cells the mark erase just blacked. Their dots are owed a
            // cross whatever the span did, or a delta leaves a hole where the
            // mark was.
            var forceA = delta ? drawnMark[ring] : -1;

            // Remember what this draw is about to put down, before the loop
            // consumes the locals. A ring drawn with the same key as last time
            // stays delta-eligible; anything else starts the count again and
            // costs one full repaint before a later span-only change may delta.
            stableFor[ring] = (lastWeak[ring] == weak &&
                               lastStrong[ring] == strong &&
                               lastOver[ring] == overs[ring] &&
                               lastRamp[ring] == isRamp &&
                               lastBlocks[ring] == isBlocks &&
                               lastBacking[ring] == backingKey && !sunMoved)
                            ? stableFor[ring] + 1 : 1;
            lastWeak[ring] = weak;
            lastStrong[ring] = strong;
            lastOver[ring] = overs[ring];
            lastRamp[ring] = isRamp;
            lastBlocks[ring] = isBlocks;
            lastBacking[ring] = backingKey;
            lastFrom[ring] = from;
            lastTo[ring] = to;

            // Which dot this ring marks. The dot loop below never learns
            // about it: the mark is drawn afterwards, so the innermost
            // statement in the face is exactly what it was before marks
            // existed. DotGrid remembers the answer between frames — placing a
            // mark walks the whole ring, and the mark moves with the
            // temperature rather than with the frame.
            markAt[ring] = DotGrid.markedDotFor(ring, markers[ring]);

            // This ring's slice of the watermark. Seeded per ring rather than
            // carried on from the last one, because a ring the gate left clean
            // is never walked and would leave the cursor pointing into it.
            var glyphAt = dating ? glyphFirst[ring] : 0;
            var glyphEnd = dating ? glyphFirst[ring + 1] : 0;
            var glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt] : -1;

            // A block ring walks in its own loop, and the span loop below is
            // left byte-for-byte as it was. A branch inside that one would be
            // paid on all ~1100 dots to serve a ring that may not exist, and
            // the statement it guards is the innermost in the face.
            //
            // `continue` is safe here because markAt is already assigned and
            // nothing else follows the dot loop inside the ring loop; the marks
            // are drawn in their own pass afterwards.
            if (Source.isTime(rings[ring])) {
                drew += TimeRing.draw(dc, ring, centreX, centreY, from, to,
                                      rings[ring], weak);
                lastColour = -1;    //! TimeRing moved the pen
                continue;
            }
            if (isBlocks) {
                for (var i = ringStart[ring]; i < last; i++) {
                    var dx = xs[i];
                    var dy = ys[i];
                    var colour;
                    var position = positionOf[i];
                    // HandBacking.handAt()'s body, gated and inlined. The window
                    // test is the cheap half: a hand covers a narrow wedge of any
                    // ring, so almost every dot is decided by two float comparisons
                    // — litBetween's body again — and the eight multiplies below
                    // run on the few percent left. A plain call here tripped the
                    // watchdog outright at 1544 dots, and so did inlining it
                    // ungated. HandBacking keeps the readable definition and
                    // theGatedHandTestAgreesWithHandBacking pins the two together.
                    //
                    // Minute first, so it wins where the hands cross.
                    var hand = NO_HAND;
                    if (minuteHere) {
                        var near = minuteWraps
                            ? ((position >= minuteFrom) || (position <= minuteTo))
                            : ((position >= minuteFrom) && (position <= minuteTo));
                        if (near) {
                            var along = dx * minuteX + dy * minuteY;
                            if (along <= minuteReach && along >= behind) {
                                var across = (dx * -minuteY) + (dy * minuteX);
                                if (across >= -halfWidth && across <= halfWidth) {
                                    hand = 2;                       //! HandBacking.MINUTE
                                }
                            }
                        }
                    }
                    if (hand == NO_HAND && hourHere) {
                        var near = hourWraps
                            ? ((position >= hourFrom) || (position <= hourTo))
                            : ((position >= hourFrom) && (position <= hourTo));
                        if (near) {
                            var along = dx * hourX + dy * hourY;
                            if (along <= hourReach && along >= behind) {
                                var across = (dx * -hourY) + (dy * hourX);
                                if (across >= -halfWidth && across <= halfWidth) {
                                    hand = 1;                       //! HandBacking.HOUR
                                }
                            }
                        }
                    }
                    if (hand != NO_HAND) {
                        colour = handColour[hand];
                    } else {
                        // HourBands.litInBlock()'s body, inlined — the same
                        // trade litBetween gets, and the same obligation:
                        // HourBands keeps the readable definition and
                        // theCachedBlockCodeLightsWhatLitAtDoes pins it to
                        // litAt() on every dot. The block and the gutter are
                        // read from DotGrid.blockAt rather than worked out per
                        // dot, which was a multiply, a toNumber() and two
                        // comparisons on every dot of every block ring; only a
                        // dot inside the partial band's radius still pays for
                        // how far into its block it sits.
                        var block = blockAt[i];
                        if (block == HourBands.GUTTER) {
                            colour = weak;              //! a gutter, either side
                        } else {
                            var radiusSq = dx * dx + dy * dy;
                            if (radiusSq <= blockFull[block]) {
                                colour = strong;
                            } else if (radiusSq <= blockPart[block]) {
                                var into = position * HourBands.HOURS - block;
                                colour = (into > blockLo[block] &&
                                          into < blockHi[block])
                                    ? strong            //! the partial band
                                    : blockUnlit[block];
                            } else {
                                colour = blockUnlit[block];
                            }
                        }
                    }
                    if (colour != lastColour) {
                        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                        lastColour = colour;
                    }
                    // A numeral dot: the same record the span loop below makes.
                    if (i == glyphNext) {
                        glyphColour[glyphAt] = colour;
                        glyphAt++;
                        glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt]
                                                         : -1;
                        recorded++;
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
                    drew++;
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
                // span is already correct in the buffer, so it is not drawn.
                // One comparison and a branch replace two native drawLine
                // calls, on all but the handful of dots the fill edge crossed.
                if (delta) {
                    var litA = wrapsA
                        ? ((position >= fromA) || (position <= toA))
                        : ((position >= fromA) && (position <= toA));
                    // `i != glyphNext` is not about correctness of colour —
                    // a numeral dot's lit-ness reads the same as any other's.
                    // It keeps the cursor in step: the advance lives in the
                    // draw below, and a dot the delta skipped would never
                    // reach it, leaving the outline's recorded colours shifted
                    // along the ring. So a numeral dot is never skipped. There
                    // are a couple of dozen of them in a ring, against the
                    // twenty or so a moved span repaints anyway.
                    if (lit == litA && i != forceA && i != glyphNext) {
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
                // HandBacking.handAt()'s body, gated and inlined. The window
                // test is the cheap half: a hand covers a narrow wedge of any
                // ring, so almost every dot is decided by two float comparisons
                // — litBetween's body again — and the eight multiplies below
                // run on the few percent left. A plain call here tripped the
                // watchdog outright at 1544 dots, and so did inlining it
                // ungated. HandBacking keeps the readable definition and
                // theGatedHandTestAgreesWithHandBacking pins the two together.
                //
                // Minute first, so it wins where the hands cross.
                var hand = NO_HAND;
                if (minuteHere) {
                    var near = minuteWraps
                        ? ((position >= minuteFrom) || (position <= minuteTo))
                        : ((position >= minuteFrom) && (position <= minuteTo));
                    if (near) {
                        var along = dx * minuteX + dy * minuteY;
                        if (along <= minuteReach && along >= behind) {
                            var across = (dx * -minuteY) + (dy * minuteX);
                            if (across >= -halfWidth && across <= halfWidth) {
                                hand = 2;                       //! HandBacking.MINUTE
                            }
                        }
                    }
                }
                if (hand == NO_HAND && hourHere) {
                    var near = hourWraps
                        ? ((position >= hourFrom) || (position <= hourTo))
                        : ((position >= hourFrom) && (position <= hourTo));
                    if (near) {
                        var along = dx * hourX + dy * hourY;
                        if (along <= hourReach && along >= behind) {
                            var across = (dx * -hourY) + (dy * hourX);
                            if (across >= -halfWidth && across <= halfWidth) {
                                hand = 1;                       //! HandBacking.HOUR
                            }
                        }
                    }
                }
                if (hand != NO_HAND) {
                    colour = handColour[hand];
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
                // A numeral dot is drawn like any other; what it adds is a
                // record of the colour it got, which the outline is inked in.
                // A hand-covered one records the hand's colour, so the outline
                // stays continuous wherever a hand happens to cross it.
                //
                // The cursor advances *here*, in the branch that consumed it,
                // rather than at the top of the loop — the delta above is what
                // makes that safe, since it never skips a dot this branch is
                // owed. Upright, this is the one comparison the struck
                // watermark already cost every dot; turned, it is new, and
                // ROADMAP has the A/B that measured it.
                if (i == glyphNext) {
                    glyphColour[glyphAt] = colour;
                    glyphAt++;
                    glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt] : -1;
                    recorded++;
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
                drew++;
            }
        }
        painted = drew;

        drawSuns(dc, dirty, centreX, centreY, hasBacking ? axes : null);

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
            drawnMark[ring] = at;
            if (at < 0) {
                continue;
            }
            var dx = xs[at];
            var dy = ys[at];
            // The hands still win: a marked dot under one keeps the hand.
            if (hasBacking && HandBacking.handAt(dx, dy, hourX, hourY,
                                                 minuteX, minuteY)
                    != HandBacking.NONE) {
                continue;
            }
            // A waterline keeps the bright mix; a reading takes the soft one.
            dc.setColor(overs[ring] ? Palette.markerOf[ring]
                                    : Palette.softMarkOf[ring],
                        Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(centreX + dx - half, centreY + dy - half,
                             DotGrid.DOT, DotGrid.DOT);
        }
    }
}
