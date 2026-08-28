import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Works out which dots sit underneath the physical analogue hands, so they
//! can be given a contrasting colour.
//!
//! The footprint is the hands' own outline exactly — no wider. This matches
//! how Garmin's own faces do it: what is lit is what sits *behind* the hand,
//! not a cleared corridor around it. The hands stand above the glass, so what
//! you actually see is the lit area emerging along their edge.
//!
//! Hand geometry is a property of the hardware, taken from the device's
//! simulator.json (Devices/instinctcrossoveramoled/simulator.json):
//! both hands are 28px wide with a 46px counterweight behind the pivot; the
//! hour hand reaches 131px and the minute hand 176px.
//!
//! Correct only while the hands are showing system time. The view asks for
//! that explicitly via View.setClockHandPosition() before enabling this.
module HandBacking {

    const HALF_WIDTH = 14;
    const COUNTERWEIGHT = 46;
    const HOUR_REACH = 131;
    const MINUTE_REACH = 176;

    //! Unit vectors for both hands: [hourX, hourY, minuteX, minuteY].
    //! Computed once per frame — the per-dot test is then just dot products.
    function axes() as Array<Float> {
        var clock = System.getClockTime();
        var hourDegrees = ((clock.hour % 12) * 30.0) + (clock.min * 0.5);
        var minuteDegrees = clock.min * 6.0;
        var hour = Math.toRadians(hourDegrees);
        var minute = Math.toRadians(minuteDegrees);
        // Screen y grows downward and 0 degrees points at twelve o'clock.
        return [
            Math.sin(hour).toFloat(), -Math.cos(hour).toFloat(),
            Math.sin(minute).toFloat(), -Math.cos(minute).toFloat()
        ] as Array<Float>;
    }

    //! Is this dot underneath either hand?
    //!
    //! Takes the axes already unpacked into scalars, and tests both hands
    //! itself rather than calling a helper twice. This is called once per dot
    //! with the hand backing on — measured at 11ms a frame in that mode, a
    //! third of the whole frame — and at ~1100 dots the call overhead was most
    //! of it. Three interpreted calls per dot became one.
    //!
    //! Projects the dot onto each hand's axis: `along` runs tip-wards, `across`
    //! is the perpendicular offset. A dot is covered when it falls inside the
    //! hand's length and half-width.
    function covers(dx as Number, dy as Number,
                    hourX as Float, hourY as Float,
                    minuteX as Float, minuteY as Float) as Boolean {
        var along = dx * hourX + dy * hourY;
        if (along <= HOUR_REACH && along >= -COUNTERWEIGHT) {
            var across = (dx * -hourY) + (dy * hourX);
            if (across >= -HALF_WIDTH && across <= HALF_WIDTH) {
                return true;
            }
        }
        along = dx * minuteX + dy * minuteY;
        if (along <= MINUTE_REACH && along >= -COUNTERWEIGHT) {
            var across = (dx * -minuteY) + (dy * minuteX);
            return across >= -HALF_WIDTH && across <= HALF_WIDTH;
        }
        return false;
    }
}
