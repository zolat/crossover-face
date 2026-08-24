import Toybox.Lang;

//! The dot lattice: a square grid clipped to the round display, with the
//! hand-pivot hub punched out. Pure geometry — nothing here draws.
//!
//! Coordinates are kept as offsets from the screen centre in whole pixels, so
//! the whole lattice is exact integer arithmetic: for a 28-wide grid at 14 px
//! pitch, offset = (2 * index - 27) * 7.
module DotGrid {

    const PITCH = 14;
    const DOT = 5;
    const COLS = 28;
    const ROWS = 28;

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
}
