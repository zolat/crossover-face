import Toybox.Lang;
import Toybox.Math;

//! The dot lattice: a square grid clipped to the round display, with the
//! hand-pivot hub punched out. Pure geometry — nothing here draws.
//!
//! Coordinates are kept as offsets from the screen centre in whole pixels, so
//! the whole lattice is exact integer arithmetic: for a 38-wide grid at 10 px
//! pitch, offset = (2 * index - 37) * 5.
module DotGrid {

    //! A cross lights 9 of the 25 pixels a filled square of the same extent
    //! would, so the same luminance buys a much finer lattice: at this pitch
    //! there are ~1100 dots against ~570 of squares, for less light.
    //!
    //! **The six numbers below are the face's only screen-dependent geometry,
    //! and they live in `Lattice`** — one copy per screen size, one of them on
    //! each device's source path. They are re-declared here rather than read
    //! through, so everything downstream stays a compile-time `const` and the
    //! render loop's rule holds: nothing computed that build() could compute
    //! once. Point a device at a different `Lattice` and the ring bounds, the
    //! marker windows, the sub-band edges and the dot count all follow.
    const PITCH as Number = Lattice.PITCH;
    const DOT as Number = Lattice.DOT;
    const COLS as Number = Lattice.COLS;
    const ROWS as Number = Lattice.ROWS;

    const RADIUS as Number = Lattice.RADIUS;
    const HUB as Number = Lattice.HUB;    //! Where the hands cross; never legible.

    const RADIUS_SQ = RADIUS * RADIUS;
    const HUB_SQ = HUB * HUB;

    //! Both grid dimensions are even, so no dot ever sits on an axis and
    //! every dot belongs to exactly one quadrant. build() leans on that.
    const HALF = COLS / 2;
    const LAST = COLS - 1;
    const STEP = PITCH / 2;

    //! Offset from centre, in pixels, of the dot at this column or row index.
    function offsetAt(index as Number) as Number {
        return (2 * index - LAST) * STEP;
    }

    //! Is there a dot at this offset from centre? False in the corners the
    //! round screen does not have, and under the hub where nothing is visible.
    function contains(dx as Number, dy as Number) as Boolean {
        var distanceSq = dx * dx + dy * dy;
        return distanceSq <= RADIUS_SQ && distanceSq >= HUB_SQ;
    }

    // --- cached dot list -----------------------------------------------------
    //
    // Monkey C is interpreted, and every callback gets a hard watchdog budget.
    // Working out each dot's ring and position during onUpdate blew it: ~1100
    // dots times a handful of calls each, with a square root and an arctangent
    // apiece, trips "Code Executed Too Long".
    //
    // None of that work depends on the data — it is all geometry. So it is done
    // once, here, and onUpdate becomes a flat walk of parallel arrays with no
    // calls in the inner loop.

    //! Arm offsets for each orientation a cross can take, as
    //! [armA x, armA y, armB x, armB y] half-lengths.
    //!
    //! A cross has 90-degree rotational symmetry, so four steps of 22.5 cover
    //! every distinct orientation. At this dot size that is also about all the
    //! resolution there is — a 5px cross rotated less than ~22 degrees looks
    //! identical. Offsets are scaled so the larger component is always half a
    //! dot, which keeps every orientation the same visual weight; scaling by
    //! true length instead would make the diagonal ones visibly shorter.
    //! Flat, four values per orientation, rather than an array of arrays.
    //! A const array of arrays is a step further than Monkey C's const is
    //! meant to cover, and nesting it is the kind of thing that resolves in
    //! the simulator and comes back empty on the watch. Flat also saves an
    //! array dereference per dot.
    const ARM_VALUES = 4;
    const ARMS = [
        2, 0, 0, 2,     //!  0     +
        2, 1, -1, 2,    //! 22.5
        2, 2, -2, 2,    //! 45     x
        1, 2, -2, 1     //! 67.5
    ] as Array<Number>;
    const ORIENTATIONS = 4;

    var count as Number = 0;
    //! One entry per dot, in ring-grouped scan order. There is deliberately no
    //! ringOf array: the dots are stored grouped by ring, so ringStart already
    //! says which ring any index belongs to and a parallel copy was 1112
    //! entries that nothing ever read.
    var xs as Array<Number> = [] as Array<Number>;      //! dx from centre
    var ys as Array<Number> = [] as Array<Number>;      //! dy from centre
    var positionOf as Array<Float> = [] as Array<Float>;//! 0.0-1.0 along it
    var armOf as Array<Number> = [] as Array<Number>;   //! offset into ARMS
    //! Which hour block each dot sits in, or HourBands.GUTTER — a byte a dot.
    //!
    //! The one per-dot cache that is not about drawing every ring: only a
    //! block ring reads it. It exists because working the block out per dot
    //! (a multiply, a toNumber() and two gutter comparisons) is what pushed
    //! three block rings past the watchdog; read from here it is one byte.
    //! A ByteArray, so it costs a fifth of what another Array would.
    var blockAt as ByteArray = []b;

    //! Half the width, in position units, of the window a mark occupies on
    //! each ring. Geometry, so it is cached here with everything else.
    //!
    //! One constant cannot serve every ring. A lattice row is 0.026 of a turn
    //! on the outermost ring but 0.076 of one on the innermost, so a window
    //! tuned to the outer ring falls clean between dots on the inner one and
    //! the mark disappears. Sized per ring from its *inner* edge — where its
    //! dots are furthest apart in position — the window always catches at least
    //! one dot, and widens outward into the few-dot tick a radial mark should
    //! be.
    var markerHalf as Array<Float> = [] as Array<Float>;

    //! The middle of each ring, measured *across* it rather than along it:
    //! the squared radius halfway between the ring's two edges.
    //!
    //! A mark is a single dot, and this is what decides which one. The window
    //! above says which dots are close enough to the marked position; this
    //! picks the one of those sitting furthest from the ring's edges, so the
    //! mark lands in the middle of a band rather than trailing off at the rim.
    var markMiddle as Array<Number> = [] as Array<Number>;

    //! Each ring's inner radius, and how far round it a hand can possibly
    //! reach from there — in turns, so it compares against `positionOf`.
    //!
    //! **This is what keeps the hands affordable.** The bar test is eight float
    //! multiplies, and paying it on every dot of a 1544-dot lattice trips the
    //! watchdog outright — measured, on a 454 screen, with the face refusing to
    //! load. But a hand is a *narrow* thing: a dot at radius r is under a bar of
    //! half-width W only if its angle is within asin(W / r) of the hand's, and
    //! that angle is widest at the ring's inner edge. So each ring carries the
    //! widest window it could possibly need, the renderer places it on the
    //! hand's own angle, and the two comparisons that gate it are the same
    //! comparisons the fill already makes. The bar test then runs on the few
    //! percent inside the window rather than on everything.
    //!
    //! Two rings answer it without any window at all. The counterweight sticks
    //! out behind the pivot, so a ring close enough to the middle is reachable
    //! in *both* directions and its window would be most of the turn anyway —
    //! those get 0.5, which `StatMap.windowAround` already turns into the whole
    //! ring. And a hand that does not reach a ring's inner edge never touches
    //! it: at every screen size the hour hand falls short of ring 0, which is
    //! where 40% of the dots live, so the outermost ring tests one hand rather
    //! than two.
    var ringInner as Array<Number> = [] as Array<Number>;
    var handHalf as Array<Float> = [] as Array<Float>;

    //! Squared outer radius of each radial sub-band, flat: ring * BANDS + band.
    //!
    //! What a block ring reads instead of a span. A block filling t whole
    //! sub-bands lights every dot in its ring out to
    //! bandEdge[ring * BANDS + t - 1], so the renderer's radial test is one
    //! array lookup and one comparison against dx*dx + dy*dy, which the dot
    //! loop already has to hand. The partial band beyond it reads the next
    //! entry along and adds a window across the block's width.
    //!
    //! Per *ring*, twelve numbers in all — not per dot. A per-dot band index
    //! would be a fifth parallel array of 1112 entries for something two
    //! multiplies recover, and theDotCacheFitsItsShareOfMemory exists to catch
    //! exactly that.
    var bandEdge as Array<Number> = [] as Array<Number>;

    //! Squared outer edge of each ring below the first, as build() assigns
    //! them — kept so nearDot() can ask which ring a cell is in the same way.
    var ringEdge as Array<Number> = [] as Array<Number>;

    //! The mark each ring last landed on, and the position it was asked for.
    //!
    //! markedDot() walks a whole ring to answer, so a marked ring used to be
    //! walked twice per drawn frame — once to place the mark, once to draw. The
    //! mark itself moves with the current temperature, which is to say hourly,
    //! so almost every one of those walks re-derived the answer it gave a
    //! second ago. A miss now goes to nearDot(), which gives the walk's answer
    //! from a few cells rather than the ring; the cache still spares it that.
    //!
    //! Keyed on the position asked for rather than timed: the mark is allowed
    //! to move the instant its reading does, and a position that has not
    //! changed cannot have landed on a different dot. Seeded with a position no
    //! ring can hold — Source.NO_MARKER is -1.0 and is a legitimate *answer*,
    //! so the empty key has to sit outside even that.
    const NO_MARK_KEY = -2.0;
    var markedFor as Array<Float> = [] as Array<Float>;
    var markedAt as Array<Number> = [] as Array<Number>;

    //! The same cache for the sun dots: Source.SUN_VALUES slots per ring,
    //! sunrise then sunset, flat. A slot of its own rather than a second key on
    //! markedFor, because the temperature mark and the two sun times move
    //! independently and a shared one-entry cache would thrash between them —
    //! walking the ring three times per drawn frame to re-derive answers it had
    //! a second ago.
    var sunFor as Array<Float> = [] as Array<Float>;
    var sunAt as Array<Number> = [] as Array<Number>;

    //! Where across its ring each sun dot sits, as the squared radius the
    //! search closes on. Sunset takes the **outer** edge and sunrise the
    //! **inner**, with the temperature mark between them in the middle.
    //!
    //! Opposite edges, not one, because on a twelve-hour dial the two times
    //! are routinely the same position: 06:05 and 18:10 are five minutes
    //! apart round it. Two dots chasing one window would land on one dot. Kept
    //! apart radially they cannot, and theSunDotsNeverShareADot holds that on
    //! every ring of every lattice.
    //!
    //! Zero and anything past the rim are not radii any dot has, and that is
    //! the point: closest to zero is simply the innermost dot in the window,
    //! closest to four times the rim the outermost.
    const SUN_OUTWARD = RADIUS_SQ * 4;
    const SUN_INWARD = 0;

    //! Where each ring's dots begin, with a final entry holding the total.
    //! The dots are stored grouped by ring, so the renderer can walk one ring
    //! at a time and hoist that ring's span, colours and lit test out of its
    //! inner loop — the loop that runs ~1100 times every frame.
    var ringStart as Array<Number> = [] as Array<Number>;

    //! Set while the cache does not yet describe the lattice.
    var stale as Boolean = true;

    //! Bumped by every build(), so anything caching an index into the arrays
    //! above can tell that they have been rewritten under it.
    //!
    //! A rebuild reuses the arrays when the lattice has not changed size, which
    //! is every rebuild there is — so a stale cache of dot indices cannot be
    //! spotted by comparing sizes or references. DateGlyph keeps such a cache;
    //! this counter is how it knows.
    var generation as Number = 0;

    //! Mark the cache for rebuilding, without doing the work here. Settings
    //! are reloaded from app callbacks, whose watchdog budget is far tighter
    //! than a view's; the rebuild belongs in onLayout, not in onStart.
    function invalidate() as Void {
        stale = true;
    }

    //! Build the cache if it does not already describe the lattice.
    function ensureBuilt() as Void {
        if (stale) {
            build();
        }
    }

    //! Radians per turn, for the arctangent approximation below.
    const FULL_TURN = 6.2831853;

    //! Tangents of the boundaries between orientations — 11.25, 33.75, 56.25
    //! and 78.75 degrees. Above the last one the cross is upright again.
    const TAN_11_25 = 0.198912;
    const TAN_33_75 = 0.668179;
    const TAN_56_25 = 1.496606;
    const TAN_78_75 = 5.027339;

    //! Which ARMS entry aligns a dot's cross with the circle it sits on: one
    //! arm pointing out from the centre, the other across it.
    //!
    //! A cross repeats every 90 degrees, so only the ratio of |y| to |x|
    //! matters and the bucket can be found by comparison. No trig at all:
    //! calling atan2 a second time here is what tipped the startup watchdog.
    //!
    //! This is the readable definition. build() inlines the same comparisons
    //! and derives three of every four dots by symmetry; a test asserts the
    //! two agree for every dot in the lattice.
    function orientationFor(dx as Number, dy as Number) as Number {
        var ax = dx.abs();
        var ay = dy.abs();
        var step;
        if (ax == 0) {
            step = 0;                       //! straight up: 90 == 0 for a cross
        } else {
            var ratio = ay.toFloat() / ax;
            if (ratio < TAN_11_25)      { step = 0; }
            else if (ratio < TAN_33_75) { step = 1; }
            else if (ratio < TAN_56_25) { step = 2; }
            else if (ratio < TAN_78_75) { step = 3; }
            else                        { step = 0; }
        }
        // Mirror for the other diagonal: the sign of x*y flips the tilt.
        if (step != 0 && ((dx < 0) != (dy < 0))) {
            step = ORIENTATIONS - step;
        }
        return step * ARM_VALUES;   //! offset straight into ARMS
    }

    //! Cached row lengths. The lattice never changes shape, so this survives
    //! every rebuild.
    var rowLengths as Array<Number> = [] as Array<Number>;

    //! How many dots the left half of each row in the top half holds, and the
    //! lattice total that follows from it. A quarter of the grid is scanned
    //! rather than all of it, and the row lengths it yields are what let
    //! build() write four dots per piece of work.
    function measureRows() as Array<Number> {
        if (rowLengths.size() == HALF) {
            return rowLengths;
        }
        var lengths = new [HALF] as Array<Number>;
        var total = 0;
        for (var r = 0; r < HALF; r++) {
            var v = (LAST - 2 * r) * STEP;          //! |dy| for this row
            var vSq = v * v;
            var n = 0;
            for (var c = 0; c < HALF; c++) {
                var u = (LAST - 2 * c) * STEP;      //! |dx| for this column
                var d = u * u + vSq;
                if (d <= RADIUS_SQ && d >= HUB_SQ) {
                    n++;
                }
            }
            lengths[r] = n;
            total += n;
        }
        count = total * 4;
        rowLengths = lengths;
        return lengths;
    }

    //! Squared outer edge of each ring, so a ring test needs no square root.
    function ringBounds(ringCount as Number) as Array<Number> {
        var thickness = (RADIUS - HUB) / ringCount;
        var bounds = new [ringCount] as Array<Number>;
        for (var k = 0; k < ringCount; k++) {
            var edge = RADIUS - (k + 1) * thickness;
            bounds[k] = edge * edge;
        }
        return bounds;
    }

    //! Half-widths for the marker window, one per ring. See markerHalf.
    //!
    //! Spacing along a ring is angular and grows as the radius shrinks, so each
    //! ring is sized from the radius at its inner edge.
    function markerWidths(ringCount as Number) as Array<Float> {
        var out = new [ringCount] as Array<Float>;
        var thickness = (RADIUS - HUB).toFloat() / ringCount;
        for (var k = 0; k < ringCount; k++) {
            var inner = RADIUS - (k + 1) * thickness;
            out[k] = PITCH.toFloat() / (2.0 * FULL_TURN * inner);
        }
        return out;
    }

    //! The across-the-ring middle of each ring. See markMiddle.
    function markMiddles(ringCount as Number) as Array<Number> {
        var out = new [ringCount] as Array<Number>;
        var thickness = (RADIUS - HUB).toFloat() / ringCount;
        for (var k = 0; k < ringCount; k++) {
            var mid = RADIUS - (k + 0.5) * thickness;
            out[k] = (mid * mid).toNumber();
        }
        return out;
    }

    //! The inner radius of each ring.
    //!
    //! The innermost takes HUB rather than its nominal edge. Integer thickness
    //! leaves the last ring's nominal inner edge a pixel or two above the hub —
    //! 26 against 24 on a 454 screen — while build() puts every dot below it in
    //! that ring regardless, since it never consults bounds[lastRing]. Naming
    //! the hub keeps this an honest floor rather than one that is nearly right.
    function ringInners(ringCount as Number) as Array<Number> {
        var thickness = (RADIUS - HUB) / ringCount;
        var out = new [ringCount] as Array<Number>;
        for (var k = 0; k < ringCount; k++) {
            out[k] = (k == ringCount - 1) ? HUB
                                          : RADIUS - (k + 1) * thickness;
        }
        return out;
    }

    //! Half-widths for the hand window, one per ring. See handHalf.
    function handWindows(inners as Array<Number>) as Array<Float> {
        var out = new [inners.size()] as Array<Float>;
        var w = HandBacking.HALF_WIDTH;
        // Where the counterweight can still reach: a dot no further out than
        // the corner of the bar behind the pivot is reachable in both
        // directions, so no single window describes it.
        var behindSq = (HandBacking.COUNTERWEIGHT * HandBacking.COUNTERWEIGHT)
                     + (w * w);
        for (var k = 0; k < inners.size(); k++) {
            var inner = inners[k];
            // Opened by the cache's own angular error. `positionOf` is a
            // polynomial approximation while the bar test below it is exact
            // integer geometry, so a window sized to the true half-angle
            // clips dots the hand really covers — measured at 0.00027 of a
            // turn on ring 1, which is a hand cut off along its length and
            // nothing that reads as an arithmetic bug.
            out[k] = (inner <= w || inner * inner <= behindSq)
                ? 0.5                       //! windowAround: the whole turn
                : ((Math.asin(w.toFloat() / inner) / FULL_TURN)
                    + Angle.MAX_TURN_ERROR).toFloat();
        }
        return out;
    }

    //! Squared sub-band edges, one row of BANDS per ring. See bandEdge.
    //!
    //! **Integer thickness, matching ringBounds() rather than markerWidths().**
    //! Two thicknesses coexist in this file: 42 exactly, which is what decides
    //! the ring a dot lands in, and 42.25, which sizes the marker window. A
    //! sub-band table built on the float one would put ring 1's outer edge at
    //! 147.75 while ring 1 itself reaches 148, and the topmost dots would fall
    //! outside their own ring's top band. On this lattice the outermost ring-1
    //! dot happens to sit at 147.1 and it would work by 0.65px of luck. The
    //! integer edges are the ring's own, so a full tier provably lights the
    //! whole block.
    function bandEdges(ringCount as Number) as Array<Number> {
        var thickness = (RADIUS - HUB) / ringCount;
        var step = thickness / HourBands.BANDS;
        var out = new [ringCount * HourBands.BANDS] as Array<Number>;
        for (var k = 0; k < ringCount; k++) {
            var inner = RADIUS - (k + 1) * thickness;
            for (var b = 0; b < HourBands.BANDS; b++) {
                // The top band takes the ring's own outer edge rather than
                // inner + BANDS * step, so a scale whose steps do not divide
                // the thickness cannot leave a dead rim inside the ring.
                var edge = (b == HourBands.BANDS - 1)
                    ? inner + thickness
                    : inner + (b + 1) * step;
                out[k * HourBands.BANDS + b] = edge * edge;
            }
        }
        return out;
    }

    //! Which dot this ring marks, remembered between frames.
    //!
    //! The entry point the renderer uses. It owns the window as well as the
    //! search, so the caller passes a position and gets a dot — which is also
    //! what lets the answer be cached against that position, since the window
    //! is a pure function of it.
    //!
    //! A negative position means the ring marks nothing, and is cached like any
    //! other: an unmarked ring should not pay a comparison per frame to
    //! rediscover that.
    function markedDotFor(ring as Number, mark as Float) as Number {
        if (markedFor[ring] == mark) {
            return markedAt[ring];
        }
        var at = (mark >= 0.0)
            ? nearDot(ring, mark, markMiddle[ring],
                      Math.sqrt(markMiddle[ring]).toFloat())
            : -1;
        markedFor[ring] = mark;
        markedAt[ring] = at;
        return at;
    }

    //! Which dot this ring's sunrise (slot 0) or sunset (slot 1) lands on,
    //! remembered between frames like markedDotFor(). -1 when the position is
    //! Source.NO_MARKER or no dot falls inside its window.
    //!
    //! The window is the temperature mark's own, so a sun dot is found exactly
    //! where a mark at that position would be — only closer to an edge.
    function sunDotFor(ring as Number, slot as Number, at as Float) as Number {
        var key = ring * Source.SUN_VALUES + slot;
        if (sunFor[key] == at) {
            return sunAt[key];
        }
        var outer = (ring == 0) ? RADIUS.toFloat()
                                : Math.sqrt(ringEdge[ring - 1]).toFloat();
        var dot = (at >= 0.0)
            ? nearDot(ring, at, (slot == 1) ? SUN_OUTWARD : SUN_INWARD,
                      (slot == 1) ? outer : ringInner[ring].toFloat())
            : -1;
        sunFor[key] = at;
        sunAt[key] = dot;
        return dot;
    }

    //! How many lattice cells either side of a mark's anchor nearDot() looks.
    //! Two is what every ring of every lattice needs to agree with the full
    //! walk, and theQuickMarkSearchAgreesWithTheWalk is what says so.
    const NEAR_REACH = 2;

    //! markedDotNear() over the window round `at`, without walking the ring.
    //!
    //! **Why it exists: the walk did not fit.** Placing a dot walks every dot
    //! of its ring, and a frame that has to place one — the first after a load,
    //! or the first after the reading moves — pays that on top of a full
    //! redraw. One walk for the temperature mark already sat at the 416
    //! lattice's edge with the hands drawn; the sun dots' two more tripped the
    //! watchdog there and the face would not load.
    //!
    //! The answer is never far from where it is being looked for: a window one
    //! pitch of arc wide, closing on a given radius, lands within a cell or two
    //! of the point at that radius on the window's centre line. So this
    //! enumerates the (2 * NEAR_REACH + 1)² lattice cells round that point,
    //! applies the walk's own tests to each — on the ring, inside the window,
    //! closest to `scoreSq`, first in scan order on a tie — and binary-searches
    //! the winner's index. The position it compares is computed with build()'s
    //! own arithmetic, so the window test cannot round differently from the
    //! cached one. markedDotNear() remains the definition.
    function nearDot(ring as Number, at as Float, scoreSq as Number,
                     anchor as Float) as Number {
        var window = StatMap.windowAround(at, markerHalf[ring]);
        var from = window[0];
        var to = window[1];
        var wraps = (from > to);
        var angle = at * FULL_TURN;
        var col = cellNear((anchor * Math.sin(angle)).toFloat());
        var row = cellNear((-anchor * Math.cos(angle)).toFloat());
        var lastRing = StatMap.RINGS - 1;
        var bestX = 0;
        var bestY = 0;
        var bestOff = -1;
        for (var r = row - NEAR_REACH; r <= row + NEAR_REACH; r++) {
            if (r < 0 || r > LAST) {
                continue;
            }
            var dy = offsetAt(r);
            for (var c = col - NEAR_REACH; c <= col + NEAR_REACH; c++) {
                if (c < 0 || c > LAST) {
                    continue;
                }
                var dx = offsetAt(c);
                var d = dx * dx + dy * dy;
                if (d > RADIUS_SQ || d < HUB_SQ) {
                    continue;
                }
                // build()'s ring test, so the two agree on every edge.
                var k = 0;
                while (k < lastRing && d < ringEdge[k]) {
                    k++;
                }
                if (k != ring) {
                    continue;
                }
                var off = (d - scoreSq).abs();
                // Strictly less, in scan order: the walk's own tie-break.
                if (bestOff >= 0 && off >= bestOff) {
                    continue;
                }
                var p = turnAt(dx, dy);
                var inside = wraps ? ((p >= from) || (p <= to))
                                   : ((p >= from) && (p <= to));
                if (inside) {
                    bestX = dx;
                    bestY = dy;
                    bestOff = off;
                }
            }
        }
        return (bestOff < 0) ? -1 : indexOf(ring, bestX, bestY);
    }

    //! The column or row whose offset is nearest `offset`, clamped onto the
    //! lattice. offsetAt() run backwards.
    function cellNear(offset as Float) as Number {
        var cell = Math.round((offset / STEP + LAST) / 2.0).toNumber();
        if (cell < 0) { return 0; }
        if (cell > LAST) { return LAST; }
        return cell;
    }

    //! A dot's position along its ring, by exactly the arithmetic build()
    //! caches it with — the same quadrant, the same floats, the same
    //! polynomial — so a window test on it lands as one on positionOf would.
    function turnAt(dx as Number, dy as Number) as Float {
        var u = dx.abs();
        var v = dy.abs();
        var uFloat = u.toFloat();
        var vFloat = v.toFloat();
        var z;
        var q;
        if (u <= v) {
            z = uFloat / vFloat;
            q = (z * (0.9724 - 0.1919 * z * z)) / FULL_TURN;
        } else {
            z = vFloat / uFloat;
            q = 0.25 - (z * (0.9724 - 0.1919 * z * z)) / FULL_TURN;
        }
        if (dy < 0) {
            return (dx > 0) ? q : 1.0 - q;
        }
        return (dx > 0) ? 0.5 - q : 0.5 + q;
    }

    //! The index of the dot at this offset in its ring, by binary search: a
    //! ring is stored in scan order, which is (row, then column) ascending.
    function indexOf(ring as Number, dx as Number, dy as Number) as Number {
        var lo = ringStart[ring];
        var hi = ringStart[ring + 1] - 1;
        while (lo <= hi) {
            var mid = (lo + hi) / 2;
            var y = ys[mid];
            if (y == dy && xs[mid] == dx) {
                return mid;
            }
            if (y < dy || (y == dy && xs[mid] < dx)) {
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return -1;
    }

    //! Forget every cached mark. The dots themselves have moved, so an index
    //! remembered against the old lattice means nothing.
    function forgetMarks(ringCount as Number) as Void {
        markedFor = new [ringCount] as Array<Float>;
        markedAt = new [ringCount] as Array<Number>;
        for (var k = 0; k < ringCount; k++) {
            markedFor[k] = NO_MARK_KEY;
            markedAt[k] = -1;
        }
        var suns = ringCount * Source.SUN_VALUES;
        sunFor = new [suns] as Array<Float>;
        sunAt = new [suns] as Array<Number>;
        for (var k = 0; k < suns; k++) {
            sunFor[k] = NO_MARK_KEY;
            sunAt[k] = -1;
        }
    }

    //! Which dot of this ring the mark lands on, or -1 when none does.
    //!
    //! A mark is one dot, not a row of them: a row drawn out of crosses reads
    //! as a bumpy dotted band rather than a line, and on a square lattice a
    //! radial run of them staggers instead of lining up. One dot cannot be
    //! crooked.
    //!
    //! Of the dots inside the mark's window, the one taken is whichever sits
    //! closest to the middle of the ring, so the mark lands in the band rather
    //! than trailing off at its edge.
    //!
    //! Called once per marked ring per frame — never per dot. The render loop
    //! is left comparing an index, which is cheaper than the two float
    //! comparisons a window test costs.
    function markedDot(ring as Number, window as Array<Float>) as Number {
        return markedDotNear(ring, window, markMiddle[ring]);
    }

    //! markedDot(), closing on any squared radius rather than the ring's
    //! middle. The sun dots ask for its edges; see SUN_OUTWARD.
    function markedDotNear(ring as Number, window as Array<Float>,
                           middle as Number) as Number {
        var from = window[0];
        var to = window[1];
        var wraps = (from > to);
        var last = ringStart[ring + 1];
        var best = -1;
        var bestOff = 0;
        for (var i = ringStart[ring]; i < last; i++) {
            var p = positionOf[i];
            // StatMap.litBetween()'s body again, over the mark's window.
            var inside = wraps ? ((p >= from) || (p <= to))
                               : ((p >= from) && (p <= to));
            if (!inside) {
                continue;
            }
            var dx = xs[i];
            var dy = ys[i];
            var off = (dx * dx + dy * dy - middle).abs();
            // Strictly less, so a tie keeps the first in scan order and the
            // choice is repeatable frame to frame.
            if (best < 0 || off < bestOff) {
                best = i;
                bestOff = off;
            }
        }
        return best;
    }

    //! Work out every dot's ring, position and orientation, and store them
    //! grouped by ring.
    //!
    //! This has to finish inside a single watchdog budget, and earlier versions
    //! did not. Four things keep it inside one:
    //!
    //!   - it runs from onLayout, whose budget is a view's rather than an app
    //!     callback's. Building in onStart tripped the watchdog outright;
    //!   - the maths is inlined rather than calling out to StatMap, Angle and
    //!     orientationFor per dot;
    //!   - the expensive part is done once per *four* dots. The lattice is
    //!     symmetric about both axes, and with an even grid no dot sits on one,
    //!     so every dot has three mirror images. They share a ring and a cross
    //!     orientation, and their positions round the dial are reflections of a
    //!     single angle. Only the array writes are paid per dot;
    //!   - the ring index comes from comparing *squared* distances against
    //!     squared boundaries, and the angle from a polynomial rather than
    //!     Math.atan2.
    //!
    //! The grouping is what the render loop is built around, and it is not just
    //! a sort: within each ring the dots keep the order the lattice is scanned
    //! in, top row to bottom, left to right. That is what lets the renderer
    //! hold its pen — a ring is walked as whole rows, so a run of dots on the
    //! same side of the fill's leading edge shares a colour and costs one
    //! setColor between them.
    //!
    //! Reconciling the two — compute by mirrored quadruple, store in scan order
    //! — is what the cursors below are for: a dot's slot is decided by its ring
    //! and its row, not by when it happens to be computed.
    //!
    //! StatMap.ringFor(), StatMap.positionOf() and orientationFor() remain the
    //! readable definition of this maths, and tests assert that this fast path
    //! agrees with them for every dot, fills every slot exactly once, and
    //! leaves each ring in scan order.
    function build() as Void {
        measureRows();
        var total = count;

        // Reuse the arrays when the lattice has not changed size, which is
        // every rebuild in practice — the lattice is fixed.
        if (xs.size() != total) {
            xs = new [total] as Array<Number>;
            ys = new [total] as Array<Number>;
            positionOf = new [total] as Array<Float>;
            armOf = new [total] as Array<Number>;
            blockAt = new [total]b;
        }

        var ringCount = StatMap.RINGS;
        var lastRing = ringCount - 1;
        var bounds = ringBounds(ringCount);
        ringEdge = bounds;
        markerHalf = markerWidths(ringCount);
        markMiddle = markMiddles(ringCount);
        bandEdge = bandEdges(ringCount);
        ringInner = ringInners(ringCount);
        handHalf = handWindows(ringInner);
        // The cached marks are indices into the arrays about to be rewritten.
        forgetMarks(ringCount);

        // --- which ring every dot belongs to, and how many per ring per row --
        //
        // Worked out for the top-left quadrant only and mirrored, like the fill
        // below. A ring is a band of radius, so all four mirror images of a
        // cell share one — which is why a single table serves both halves of a
        // row. The rings are kept so the fill need not derive them twice;
        // -1 marks a lattice cell that holds no dot.
        var ringAt = new [HALF * HALF] as Array<Number>;
        var blocks = ringCount * ROWS;
        var blockCount = new [blocks] as Array<Number>;
        for (var i = 0; i < blocks; i++) {
            blockCount[i] = 0;
        }

        for (var r = 0; r < HALF; r++) {
            var v = (LAST - 2 * r) * STEP;
            var vSq = v * v;
            var mirrorRow = LAST - r;
            var base = r * HALF;
            for (var c = 0; c < HALF; c++) {
                var u = (LAST - 2 * c) * STEP;
                var distanceSq = u * u + vSq;
                if (distanceSq > RADIUS_SQ || distanceSq < HUB_SQ) {
                    ringAt[base + c] = -1;
                    continue;
                }
                var ring = 0;
                while (ring < lastRing && distanceSq < bounds[ring]) {
                    ring++;
                }
                ringAt[base + c] = ring;
                // Two dots per row, one each side of the vertical axis, and
                // the same again in the mirrored row.
                blockCount[ring * ROWS + r] += 2;
                blockCount[ring * ROWS + mirrorRow] += 2;
            }
        }

        // --- turn those counts into a slot for every dot ---------------------
        //
        // Rings come one after another, and inside a ring the rows come in scan
        // order. Each row's block is filled from both ends: the left half of the
        // lattice is scanned outward-in so it fills forward, the right half is
        // scanned inward-out so it fills backward. They meet in the middle, and
        // the block ends up in column order.
        ringStart = new [ringCount + 1] as Array<Number>;
        var leftCursor = new [blocks] as Array<Number>;
        var rightCursor = new [blocks] as Array<Number>;
        var at = 0;
        for (var ring = 0; ring < ringCount; ring++) {
            ringStart[ring] = at;
            for (var row = 0; row < ROWS; row++) {
                var slot = ring * ROWS + row;
                leftCursor[slot] = at;
                at += blockCount[slot];
                rightCursor[slot] = at - 1;
            }
        }
        ringStart[ringCount] = at;

        // --- the fill --------------------------------------------------------
        for (var r = 0; r < HALF; r++) {
            var y = (2 * r - LAST) * STEP;      //! negative: the top half
            var v = -y;
            var vFloat = v.toFloat();
            var mirrorRow = LAST - r;
            var base = r * HALF;

            for (var c = 0; c < HALF; c++) {
                var ring = ringAt[base + c];
                if (ring < 0) {
                    continue;
                }
                var x = (2 * c - LAST) * STEP;  //! negative: the left half
                var u = -x;

                // The four dots this one piece of work fills. All four share a
                // ring, so the two rows they fall in are the only slots needed.
                var topSlot = ring * ROWS + r;
                var bottomSlot = ring * ROWS + mirrorRow;

                var topLeft = leftCursor[topSlot];
                var topRight = rightCursor[topSlot];
                var bottomLeft = leftCursor[bottomSlot];
                var bottomRight = rightCursor[bottomSlot];
                leftCursor[topSlot] = topLeft + 1;
                rightCursor[topSlot] = topRight - 1;
                leftCursor[bottomSlot] = bottomLeft + 1;
                rightCursor[bottomSlot] = bottomRight - 1;

                xs[topLeft] = x;        ys[topLeft] = y;
                xs[topRight] = u;       ys[topRight] = y;
                xs[bottomLeft] = x;     ys[bottomLeft] = v;
                xs[bottomRight] = u;    ys[bottomRight] = v;

                // Turns clockwise from twelve for the top-right quadrant,
                // strictly between 0.0 and 0.25 — no dot sits on an axis.
                // The other three quadrants are reflections of it.
                var uFloat = u.toFloat();
                var z;
                var q;
                if (u <= v) {
                    z = uFloat / vFloat;
                    q = (z * (0.9724 - 0.1919 * z * z)) / FULL_TURN;
                } else {
                    z = vFloat / uFloat;
                    q = 0.25 - (z * (0.9724 - 0.1919 * z * z)) / FULL_TURN;
                }
                positionOf[topRight] = q;
                positionOf[bottomRight] = 0.5 - q;
                positionOf[bottomLeft] = 0.5 + q;
                positionOf[topLeft] = 1.0 - q;

                var ratio = vFloat / uFloat;
                var step;
                if (ratio < TAN_11_25)      { step = 0; }
                else if (ratio < TAN_33_75) { step = 1; }
                else if (ratio < TAN_56_25) { step = 2; }
                else if (ratio < TAN_78_75) { step = 3; }
                else                        { step = 0; }
                // A cross tilts one way in the quadrants where x and y
                // share a sign, the other way where they differ.
                var aligned = step * ARM_VALUES;
                var mirrored = (step == 0) ? 0
                             : (ORIENTATIONS - step) * ARM_VALUES;
                armOf[topLeft] = aligned;       armOf[bottomRight] = aligned;
                armOf[topRight] = mirrored;     armOf[bottomLeft] = mirrored;
            }
        }

        fillBlockCodes(total);

        stale = false;
        generation++;
    }

    //! The block every dot falls in, into blockAt.
    //!
    //! HourBands.blockCodeOf(), inlined: the build is ~1400 dots against the
    //! same watchdog as a frame, and a call per dot is most of the cost.
    //! theBlockCacheMatchesItsDefinition pins the two together.
    //!
    //! A function of its own for the stack's sake, as drawAt()'s helpers are:
    //! build() can run from inside drawAt(), and its locals inline here
    //! overflowed the test runner's stack.
    function fillBlockCodes(total as Number) as Void {
        for (var i = 0; i < total; i++) {
            var turns = positionOf[i] * HourBands.HOURS;
            var block = turns.toNumber();
            var into = turns - block;
            blockAt[i] = (into < HourBands.LEAD || into >= HourBands.TRAIL)
                ? HourBands.GUTTER : block;
        }
    }
}
