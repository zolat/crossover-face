import Toybox.Lang;
import Toybox.System;

//! Where the current second sits inside its minute, normalised to 0.0-1.0 the
//! way every other reading the face draws is. Pure queries — nothing here draws.
//!
//! The Crossover's physical hands carry hours and minutes only, so there is no
//! second hand on the glass and the face has never had a use for the clock's
//! finest field before now. A ring assigned to this one fills through the
//! minute and resets, which in the rings layout puts the leading edge of the
//! fill exactly where a second hand would point.
//!
//! Split the way WeatherData is: fraction() is the arithmetic and can be
//! asserted without owning the clock, minuteSweep() is the reading.
module ClockData {

    const PER_MINUTE = 60;

    //! Fraction of the minute elapsed. 0.0 at :00, and never quite 1.0 — :59
    //! sits at 59/60, and the tick after it is the next minute's zero.
    //!
    //! The modulo is not decoration: ClockTime.sec is documented as 0-59, but a
    //! span end above 1.0 would light a ring's dots in the wrong order rather
    //! than simply saturating, and one guarded division is cheaper than finding
    //! that out on the wrist.
    function fraction(second as Number) as Float {
        return (second % PER_MINUTE).toFloat() / PER_MINUTE;
    }

    //! How far through the current minute the watch is, right now.
    function minuteSweep() as Float {
        return fraction(System.getClockTime().sec);
    }
}
