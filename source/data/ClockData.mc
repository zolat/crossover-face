import Toybox.Lang;
import Toybox.System;

//! Where the current second sits inside its minute, normalised to 0.0-1.0 the
//! way every other reading the face draws is. Pure queries — nothing here draws.
//!
//! The Crossover's physical hands carry hours and minutes only, so there is no
//! second hand on the glass and the face has never had a use for the clock's
//! finest field before now. A ring assigned to this one fills through the
//! minute and completes its turn on the last second, then starts the next
//! minute from a single segment.
//!
//! Split the way WeatherData is: fraction() is the arithmetic and can be
//! asserted without owning the clock, minuteSweep() is the reading.
module ClockData {

    const PER_MINUTE = 60;

    //! Fraction of the minute elapsed, counting the second in progress. 1/60 at
    //! :00, climbing one stop a tick, and exactly 1.0 at :59 — a completed turn.
    //!
    //! The `+ 1` is the whole point and is not an off-by-one. A bare
    //! `second / 60` tops out at 59/60, which leaves the last stop of the ring
    //! permanently dark: the sweep's leading edge never reaches twelve, it
    //! jumps back from just short of it. Counting the second in progress reads
    //! the fill as *elapsed time* rather than *the instant the second arrived*,
    //! which is what a filled bar means everywhere else on this face, and it
    //! lands :59 on a full ring. 100% is the next minute, so the last second of
    //! this one is the honest moment to draw it.
    //!
    //! The modulo is not decoration, and it must stay **before** the `+ 1`.
    //! ClockTime.sec is documented as 0-59, but a span end above 1.0 would
    //! light a ring's dots in the wrong order rather than simply saturating,
    //! and one guarded division is cheaper than finding that out on the wrist.
    //! `(second + 1) % PER_MINUTE` would look equivalent and is not — it sends
    //! :59 back to 0.0 and reintroduces the empty stop at the other end.
    function fraction(second as Number) as Float {
        return ((second % PER_MINUTE) + 1).toFloat() / PER_MINUTE;
    }

    //! How far through the current minute the watch is, right now.
    function minuteSweep() as Float {
        return fraction(System.getClockTime().sec);
    }

    const MINUTES_PER_HOUR = 60.0;
    const HOURS_PER_DIAL = 12;

    //! The time ring's two ends, into `out`: how far round the dial the hour
    //! has come, then the minute. Both 0.0 up to below 1.0.
    //!
    //! These read like hands, which is the job, so the minute does **not** take
    //! fraction()'s `+ 1`. That convention is right for a fill that completes on
    //! the last second; here the half-ring is where a minute hand would point,
    //! so it is empty on the hour and exactly a quarter at :15. The hour moves
    //! on with the minutes the way an hour hand does, rather than jumping on
    //! the hour, so its end sits between the hour marks just as a hand would.
    function timeFractions(hour as Number, minute as Number,
                           out as Array<Float>) as Void {
        var withinHour = minute / MINUTES_PER_HOUR;
        out[0] = ((hour % HOURS_PER_DIAL) + withinHour) / HOURS_PER_DIAL;
        out[1] = withinHour;
    }

    //! The time ring's two ends, right now.
    function fillTime(out as Array<Float>) as Void {
        var clock = System.getClockTime();
        timeFractions(clock.hour, clock.min, out);
    }
}
