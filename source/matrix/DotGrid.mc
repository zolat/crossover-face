import Toybox.Lang;
import Toybox.Math;

//! The dot lattice: a square grid clipped to the round display, with the
//! hand-pivot hub punched out. Pure geometry — nothing here draws.
//!
//! Coordinates are kept as offsets from the screen centre in whole pixels, so
//! the whole lattice is exact integer arithmetic: for a 28-wide grid at 14 px
//! pitch, offset = (2 * index - 27) * 7.
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

    //! Offset from centre, in pixels, of the dot at this column or row index.
    function offsetAt(index as Number) as Number {
        return (2 * index - (COLS - 1)) * (PITCH / 2);
    }

    //! Is there a dot at this offset from centre? False in the corners the
    //! round screen does not have, and under the hub where nothing is visible.
    function contains(dx as Number, dy as Number) as Boolean {
        var distanceSq = dx * dx + dy * dy;
        return distanceSq <= RADIUS_SQ && distanceSq >= HUB_SQ;
    }

    // --- cached dot list -----------------------------------------------------
    //
    // Monkey C is interpreted, and a watch face gets a hard watchdog budget per
    // frame. Working out each dot's ring and position during onUpdate blew it:
    // ~1100 dots times a handful of calls each — with a square root and an
    // arctangent per dot in the rings layout — trips "Code Executed Too Long".
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

    //! Local copies of the layout ids, so build() needs no call to read them.
    const LAYOUT_RINGS_LOCAL = 2;
    const LAYOUT_BANDS_CENTRE_LOCAL = 1;

    var count as Number = 0;
    var xs as Array<Number> = [] as Array<Number>;      //! dx from centre
    var ys as Array<Number> = [] as Array<Number>;      //! dy from centre
    var ringOf as Array<Number> = [] as Array<Number>;  //! which ring
    var positionOf as Array<Float> = [] as Array<Float>;//! 0.0-1.0 along it
    var armOf as Array<Number> = [] as Array<Number>;   //! offset into ARMS

    //! How many dots to work out per frame.
    //!
    //! Building all ~1100 at once trips the watchdog on the watch, and no
    //! amount of tightening the arithmetic fixed that — the work is simply
    //! too much for one synchronous pass. So it is spread across frames: the
    //! face draws the dots it has and fills in the rest over the next few
    //! updates. The layout rarely changes, so this is paid once.
    const CHUNK = 150;

    //! Dots worked out so far. The renderer draws only these.
    var ready as Number = 0;
    var _allocated as Boolean = false;

    //! Mark the cache for rebuilding, without doing the work here.
    function invalidate() as Void {
        ready = 0;
        _allocated = false;
    }

    //! Build the whole cache in one call. For tests and tooling only — the
    //! face itself must go through ensureBuilt(), because doing it all at
    //! once is exactly what trips the watchdog on the watch.
    function buildAll() as Void {
        allocate();
        _allocated = true;
        while (ready < count) {
            fill(CHUNK);
        }
    }

    //! Advance the build by at most one chunk. Called from the renderer, so
    //! the work lands inside a frame rather than inside onStart, whose
    //! watchdog is far tighter.
    function ensureBuilt() as Void {
        if (!_allocated) {
            allocate();
            _allocated = true;
        }
        if (ready < count) {
            fill(CHUNK);
        }
    }

    //! Radians, so no Math.toDegrees call per dot.
    const QUARTER_TURN = 1.5707963;
    const FULL_TURN = 6.2831853;

    //! Tangents of the boundaries between orientations — 11.25, 33.75 and
    //! 56.25 degrees. Above the last one the cross is upright again.
    const TAN_11_25 = 0.198912;
    const TAN_33_75 = 0.668179;
    const TAN_56_25 = 1.496606;

    //! Which ARMS entry aligns a dot's cross with the circle it sits on: one
    //! arm pointing out from the centre, the other across it.
    //!
    //! A cross repeats every 90 degrees, so only the ratio of |y| to |x|
    //! matters and the bucket can be found by comparison. No trig at all:
    //! calling atan2 a second time here is what tipped the startup watchdog.
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
            else if (ratio < 5.027339)  { step = 3; }
            else                        { step = 0; }
        }
        // Mirror for the other diagonal: the sign of x*y flips the tilt.
        if (step != 0 && ((dx < 0) != (dy < 0))) {
            step = ORIENTATIONS - step;
        }
        return step * ARM_VALUES;   //! offset straight into ARMS
    }

    //! Rebuild the cache. Must be called whenever the layout changes, since
    //! ring, position and orientation all depend on it.
    //!
    //! This runs synchronously inside onStart against a watchdog, and an
    //! earlier version tripped it on the watch. Three things keep it inside
    //! the budget now, all of them about the *rings* layout, which is the only
    //! expensive one:
    //!
    //!   - the maths is inlined rather than calling out to StatMap per dot.
    //!     Three interpreted calls across ~1100 dots was the bulk of the cost;
    //!   - the ring index comes from comparing *squared* distances against
    //!     squared boundaries, so there is no square root;
    //!   - one atan2 serves both position and orientation. Computing the angle
    //!     twice is what pushed the earlier version over the edge.
    //!
    //! Counting first and allocating exactly also avoids holding full-size
    //! arrays and their trimmed copies at the same moment.
    //!
    //! StatMap.ringFor() and positionOf() remain the readable definition of
    //! this maths, and a test asserts this fast path agrees with them for
    //! every dot — so the two cannot drift apart.
    //! Count the lattice and allocate exactly. Pure arithmetic — offsetAt()
    //! and contains() are the readable form of this, but calling them ~1400
    //! times was itself enough to trip the watchdog.
    function allocate() as Void {
        var half = PITCH / 2;
        var last = COLS - 1;

        var n = 0;
        for (var row = 0; row < ROWS; row++) {
            var y = (2 * row - last) * half;
            var ySq = y * y;
            for (var col = 0; col < COLS; col++) {
                var x = (2 * col - last) * half;
                var d = x * x + ySq;
                if (d <= RADIUS_SQ && d >= HUB_SQ) {
                    n++;
                }
            }
        }

        count = n;
        ready = 0;
        xs = new [n] as Array<Number>;
        ys = new [n] as Array<Number>;
        ringOf = new [n] as Array<Number>;
        positionOf = new [n] as Array<Float>;
        armOf = new [n] as Array<Number>;
    }

    //! Work out the next `limit` dots, resuming where the last call stopped.
    function fill(limit as Number) as Void {
        var half = PITCH / 2;
        var last = COLS - 1;
        var layout = StatMap.layout;
        var radial = (layout == LAYOUT_RINGS_LOCAL);
        var centreFill = (layout == LAYOUT_BANDS_CENTRE_LOCAL);

        var thickness = (RADIUS - HUB) / StatMap.RINGS;
        var bounds = new [StatMap.RINGS] as Array<Number>;
        for (var k = 0; k < StatMap.RINGS; k++) {
            var edge = RADIUS - (k + 1) * thickness;
            bounds[k] = edge * edge;
        }

        var seen = 0;              //! dots passed over, to find where to resume
        var done = 0;
        for (var row = 0; row < ROWS && done < limit; row++) {
            var y = (2 * row - last) * half;
            var ySq = y * y;
            for (var col = 0; col < COLS && done < limit; col++) {
                var x = (2 * col - last) * half;
                var distanceSq = x * x + ySq;
                if (distanceSq > RADIUS_SQ || distanceSq < HUB_SQ) {
                    continue;
                }
                if (seen < ready) {      //! already done on an earlier frame
                    seen++;
                    continue;
                }

                var i = seen;
                xs[i] = x;
                ys[i] = y;
                if (radial) {
                    var r = 0;
                    while (r < StatMap.RINGS - 1 && distanceSq < bounds[r]) {
                        r++;
                    }
                    ringOf[i] = r;
                    positionOf[i] = Angle.turnOf(x, y);
                    armOf[i] = orientationFor(x, y);
                } else {
                    var band = col * StatMap.RINGS / COLS;
                    ringOf[i] = (band >= StatMap.RINGS) ? StatMap.RINGS - 1 : band;
                    positionOf[i] = centreFill
                        ? (y.abs().toFloat() / RADIUS)
                        : ((RADIUS - y).toFloat() / (2 * RADIUS));
                    armOf[i] = 0;
                }
                seen++;
                done++;
            }
        }
        ready = seen;
    }
}