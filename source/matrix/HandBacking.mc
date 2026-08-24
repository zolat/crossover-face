import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Works out which dots sit underneath the physical analogue hands, so they
//! can be given a contrasting colour and the hands read cleanly against a
//! plain backing instead of a busy field of colour.
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

    //! How far the backing extends past the hand's own outline. The hands are
    //! opaque, so a backing cut exactly to their shape is invisible — it hides
    //! underneath them. 10px clears a corridor you can actually see either
    //! side; much more and it starts eating the design.
    const MARGIN = 10;

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
    function covers(dx as Number, dy as Number, axes as Array<Float>) as Boolean {
        return under(dx, dy, axes[0], axes[1], HOUR_REACH) ||
               under(dx, dy, axes[2], axes[3], MINUTE_REACH);
    }

    //! Project the dot onto the hand's axis: `along` runs tip-wards, `across`
    //! is the perpendicular offset. A dot is covered when it falls inside the
    //! hand's length and half-width.
    function under(dx as Number, dy as Number, ux as Float, uy as Float,
                   reach as Number) as Boolean {
        var along = dx * ux + dy * uy;
        if (along > reach + MARGIN || along < -(COUNTERWEIGHT + MARGIN)) {
            return false;
        }
        var across = (dx * -uy) + (dy * ux);
        return across.abs() <= HALF_WIDTH + MARGIN;
    }
}
