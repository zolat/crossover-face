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
    const PITCH = 10;
    const DOT = 5;
    const COLS = 38;
    const ROWS = 38;

    const RADIUS = 190;
    const HUB = 21;             //! Radius the physical hand pivot covers.

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
    var xs as Array<Number> = [] as Array<Number>;      //! dx from centre
    var ys as Array<Number> = [] as Array<Number>;      //! dy from centre
    var ringOf as Array<Number> = [] as Array<Number>;  //! which ring
    var positionOf as Array<Float> = [] as Array<Float>;//! 0.0-1.0 along it
    var armOf as Array<Number> = [] as Array<Number>;   //! offset into ARMS

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

    //! Where each ring's dots begin, with a final entry holding the total.
    //! The dots are stored grouped by ring, so the renderer can walk one ring
    //! at a time and hoist that ring's span, colours and lit test out of its
    //! inner loop — the loop that runs ~1100 times every frame.
    var ringStart as Array<Number> = [] as Array<Number>;

    //! Set while the cache does not yet describe the lattice.
    var stale as Boolean = true;

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
        var from = window[0];
        var to = window[1];
        var wraps = (from > to);
        var middle = markMiddle[ring];
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
            ringOf = new [total] as Array<Number>;
            positionOf = new [total] as Array<Float>;
            armOf = new [total] as Array<Number>;
        }

        var ringCount = StatMap.RINGS;
        var lastRing = ringCount - 1;
        var bounds = ringBounds(ringCount);
        markerHalf = markerWidths(ringCount);
        markMiddle = markMiddles(ringCount);

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

                ringOf[topLeft] = ring;         ringOf[bottomLeft] = ring;
                ringOf[topRight] = ring;        ringOf[bottomRight] = ring;

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

        stale = false;
    }
}
