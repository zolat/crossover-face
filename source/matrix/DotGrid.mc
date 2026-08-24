import Toybox.Lang;

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

    var count as Number = 0;
    var xs as Array<Number> = [] as Array<Number>;      //! dx from centre
    var ys as Array<Number> = [] as Array<Number>;      //! dy from centre
    var ringOf as Array<Number> = [] as Array<Number>;  //! which ring
    var positionOf as Array<Float> = [] as Array<Float>;//! 0.0-1.0 along it

    //! Rebuild the cache. Must be called whenever the layout changes, since
    //! ring and position both depend on it.
    function build() as Void {
        var dx = new [COLS * ROWS] as Array<Number>;
        var dy = new [COLS * ROWS] as Array<Number>;
        var ring = new [COLS * ROWS] as Array<Number>;
        var position = new [COLS * ROWS] as Array<Float>;

        var n = 0;
        for (var row = 0; row < ROWS; row++) {
            var y = offsetAt(row);
            for (var col = 0; col < COLS; col++) {
                var x = offsetAt(col);
                if (!contains(x, y)) {
                    continue;
                }
                dx[n] = x;
                dy[n] = y;
                ring[n] = StatMap.ringFor(col, x, y);
                position[n] = StatMap.positionOf(x, y);
                n++;
            }
        }

        xs = dx.slice(0, n);
        ys = dy.slice(0, n);
        ringOf = ring.slice(0, n);
        positionOf = position.slice(0, n);
        count = n;
    }
}
