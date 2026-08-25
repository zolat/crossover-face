import Toybox.Lang;

//! Where a point sits around the dial, as turns clockwise from twelve.
//!
//! Deliberately avoids Math.atan2. The dot cache computes this for every dot
//! in the lattice, and at ~1100 dots the cost of a native call per dot was
//! enough on its own to trip the watchdog. A polynomial approximation in plain
//! arithmetic is both faster and accurate to well under half a degree, which
//! is far finer than the spacing between neighbouring dots.
//!
//! One definition, used by both StatMap.positionOf() and the cache build, so
//! the readable path and the fast path cannot disagree.
module Angle {

    const FULL_TURN = 6.2831853;

    //! Guards against dividing by zero on the axes.
    const TINY = 0.000001;

    //! atan(z) for 0 <= z <= 1, expressed in turns rather than radians.
    //! Max error about 0.005 radians, or 0.0008 of a turn.
    function atanTurn(z as Float) as Float {
        return (z * (0.9724 - 0.1919 * z * z)) / FULL_TURN;
    }

    //! Turns clockwise from twelve o'clock, 0.0 up to but not including 1.0.
    function turnOf(dx as Number, dy as Number) as Float {
        var x = dx.toFloat();
        var y = -dy.toFloat();          //! screen y runs down; up is positive
        var ax = (x < 0.0) ? -x : x;
        var ay = (y < 0.0) ? -y : y;

        var turn;
        if (ax <= ay) {
            turn = atanTurn(ax / (ay + TINY));
        } else {
            turn = 0.25 - atanTurn(ay / (ax + TINY));
        }
        if (y < 0.0) {
            turn = 0.5 - turn;
        }
        if (x < 0.0) {
            turn = 1.0 - turn;
        }
        if (turn >= 1.0) {
            turn -= 1.0;
        }
        if (turn < 0.0) {
            turn += 1.0;
        }
        return turn.toFloat();
    }
}
