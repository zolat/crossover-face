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
    // dots times a handful of calls each — with a square root and an arctangent
    // per dot in the rings layout — trips "Code Executed Too Long".
    //
    // None of that work depends on the data, only on the geometry and the
    // layout. So it is done once, here, and onUpdate becomes a flat walk of
    // parallel arrays with no calls in the inner loop.

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

    //! Local copies of the layout ids and the band scale, so build() needs no
    //! call out of its loop to read them.
    const LAYOUT_RINGS_LOCAL = 2;
    const LAYOUT_BANDS_CENTRE_LOCAL = 1;
    const BAND_SPAN = 2 * RADIUS;

    var count as Number = 0;
    var xs as Array<Number> = [] as Array<Number>;      //! dx from centre
    var ys as Array<Number> = [] as Array<Number>;      //! dy from centre
    var ringOf as Array<Number> = [] as Array<Number>;  //! which ring
    var positionOf as Array<Float> = [] as Array<Float>;//! 0.0-1.0 along it
    var armOf as Array<Number> = [] as Array<Number>;   //! offset into ARMS

    //! Set when the layout has changed and the cache no longer describes it.
    var stale as Boolean = true;

    //! Mark the cache for rebuilding, without doing the work here. Settings
    //! are reloaded from app callbacks, whose watchdog budget is far tighter
    //! than a view's; the rebuild belongs in onLayout, not in onStart.
    function invalidate() as Void {
        stale = true;
    }

    //! Build the cache if the layout has moved on since it was last built.
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
    //! every rebuild — only the layout moves.
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

    //! Work out every dot's ring, position and orientation, in one pass.
    //!
    //! This has to finish inside a single watchdog budget, and earlier versions
    //! did not. Four things keep it inside one now:
    //!
    //!   - it runs from onLayout, whose budget is a view's rather than an app
    //!     callback's. Building in onStart tripped the watchdog outright;
    //!   - the maths is inlined rather than calling out to StatMap, Angle and
    //!     orientationFor per dot. Three interpreted calls across ~1100 dots
    //!     was the bulk of the cost;
    //!   - the expensive part is done once per *four* dots. The lattice is
    //!     symmetric about both axes, so a dot in the top-left quadrant fixes
    //!     its three mirror images: they share a ring and a cross orientation,
    //!     and their positions round the dial are reflections of one angle.
    //!     Only the array writes are paid per dot;
    //!   - the ring index comes from comparing *squared* distances against
    //!     squared boundaries, so there is no square root, and the angle comes
    //!     from a polynomial rather than Math.atan2.
    //!
    //! StatMap.ringFor(), StatMap.positionOf() and orientationFor() remain the
    //! readable definition of this maths, and tests assert that this fast path
    //! agrees with them for every dot — and that it fills every slot exactly
    //! once, which is the failure mode the agreement check cannot see.
    function build() as Void {
        var lengths = measureRows();
        var total = count;

        // Reuse the arrays when the lattice has not changed size, which is
        // every rebuild in practice — only the layout moves.
        if (xs.size() != total) {
            xs = new [total] as Array<Number>;
            ys = new [total] as Array<Number>;
            ringOf = new [total] as Array<Number>;
            positionOf = new [total] as Array<Float>;
            armOf = new [total] as Array<Number>;
        }

        var layout = StatMap.layout;
        var radial = (layout == LAYOUT_RINGS_LOCAL);
        var centreFill = (layout == LAYOUT_BANDS_CENTRE_LOCAL);
        var ringCount = StatMap.RINGS;
        var lastRing = ringCount - 1;

        // Squared outer edge of each ring, so the ring test needs no sqrt.
        var thickness = (RADIUS - HUB) / ringCount;
        var bounds = new [ringCount] as Array<Number>;
        for (var k = 0; k < ringCount; k++) {
            var edge = RADIUS - (k + 1) * thickness;
            bounds[k] = edge * edge;
        }

        var topStart = 0;
        for (var r = 0; r < HALF; r++) {
            var rowLen = lengths[r] * 2;
            if (rowLen == 0) {
                continue;
            }
            // Rows mirror about the midline, so the bottom row that matches
            // this one holds the same columns in the same order.
            var bottomStart = total - topStart - rowLen;
            var rowEnd = rowLen - 1;

            var y = (2 * r - LAST) * STEP;      //! negative: the top half
            var v = -y;
            var vSq = v * v;
            var vFloat = v.toFloat();

            // In the band layouts every dot in a row shares its position, so
            // it is worked out once here rather than once per dot.
            var topPosition = 0.0;
            var bottomPosition = 0.0;
            if (!radial) {
                if (centreFill) {
                    // Out from the midline, so a level opens symmetrically.
                    topPosition = vFloat / RADIUS;
                    bottomPosition = topPosition;
                } else {
                    // Up from the rim, so a level rises like a tide.
                    topPosition = (RADIUS + v).toFloat() / BAND_SPAN;
                    bottomPosition = (RADIUS - v).toFloat() / BAND_SPAN;
                }
            }

            var j = 0;
            for (var c = 0; c < HALF; c++) {
                var x = (2 * c - LAST) * STEP;  //! negative: the left half
                var u = -x;
                var distanceSq = u * u + vSq;
                if (distanceSq > RADIUS_SQ || distanceSq < HUB_SQ) {
                    continue;
                }

                // The four dots this one piece of work fills.
                var topLeft = topStart + j;
                var topRight = topStart + rowEnd - j;
                var bottomLeft = bottomStart + j;
                var bottomRight = bottomStart + rowEnd - j;

                xs[topLeft] = x;        ys[topLeft] = y;
                xs[topRight] = u;       ys[topRight] = y;
                xs[bottomLeft] = x;     ys[bottomLeft] = v;
                xs[bottomRight] = u;    ys[bottomRight] = v;

                if (radial) {
                    var ring = 0;
                    while (ring < lastRing && distanceSq < bounds[ring]) {
                        ring++;
                    }
                    ringOf[topLeft] = ring;     ringOf[topRight] = ring;
                    ringOf[bottomLeft] = ring;  ringOf[bottomRight] = ring;

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
                } else {
                    var leftRing = c * ringCount / COLS;
                    var rightRing = (LAST - c) * ringCount / COLS;
                    if (leftRing > lastRing) { leftRing = lastRing; }
                    if (rightRing > lastRing) { rightRing = lastRing; }
                    ringOf[topLeft] = leftRing;     ringOf[bottomLeft] = leftRing;
                    ringOf[topRight] = rightRing;   ringOf[bottomRight] = rightRing;

                    positionOf[topLeft] = topPosition;
                    positionOf[topRight] = topPosition;
                    positionOf[bottomLeft] = bottomPosition;
                    positionOf[bottomRight] = bottomPosition;

                    armOf[topLeft] = 0;         armOf[topRight] = 0;
                    armOf[bottomLeft] = 0;      armOf[bottomRight] = 0;
                }
                j++;
            }
            topStart += rowLen;
        }

        stale = false;
    }
}
