import Toybox.Lang;
import Toybox.Weather;

//! Today's weather, normalised for drawing. Pure queries, no drawing.
//!
//! Temperatures arrive from Garmin in Celsius regardless of the watch's display
//! units, and the ring shows no numbers, so no conversion is needed.
module WeatherData {

    //! The temperature scale the ring spans: 0C at twelve o'clock, running
    //! clockwise to 60C back at twelve.
    //!
    //! 60 is far wider than any weather needs, and that is the point: it puts
    //! one degree on every minute mark, so the band can be read off the dial
    //! the same way you read the minute hand. 18C sits where :18 does. A
    //! tighter scale would use the ring better and be harder to read.
    const SCALE_MIN_C = 0.0;
    const SCALE_MAX_C = 60.0;

    //! Today's low and high as fractions of the scale, or null when there is
    //! no forecast — a watch that has never synced has no weather at all.
    function dayRange() as Array<Float>? {
        if (!(Toybox has :Weather)) {
            return null;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return null;
        }
        var low = conditions.lowTemperature;
        var high = conditions.highTemperature;
        if (low == null || high == null) {
            return null;
        }
        return [fraction(low.toFloat()), fraction(high.toFloat())] as Array<Float>;
    }

    //! Where the temperature right now sits on the same scale, or null when
    //! there is no forecast.
    //!
    //! This is what turns the band from a slab into a reading: a day of 11C to
    //! 22C looks the same at dawn and at noon until something says where in it
    //! you are. It is deliberately not clamped to the day's range — an
    //! overnight low or a stale forecast routinely puts the current
    //! temperature outside it, and the honest answer is to draw it where it
    //! actually falls.
    function currentFraction() as Float? {
        if (!(Toybox has :Weather)) {
            return null;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return null;
        }
        var now = conditions.temperature;
        if (now == null) {
            return null;
        }
        return fraction(now.toFloat());
    }

    //! Chance of precipitation, 0.0-1.0, or null when unknown.
    function rainChance() as Float? {
        if (!(Toybox has :Weather)) {
            return null;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return null;
        }
        var chance = conditions.precipitationChance;
        if (chance == null) {
            return null;
        }
        return clamp(chance / 100.0);
    }

    //! Where a Celsius temperature sits on the ring's scale, 0.0-1.0.
    //!
    //! Wraps rather than clamps, which is what the minute-mark scale implies:
    //! -5C belongs at :55, exactly where minute 55 sits, and reads as five
    //! degrees anticlockwise of twelve. Clamping instead would fold every
    //! sub-zero reading onto twelve o'clock and quietly show a -5 to 3 day as
    //! 0 to 3 — a wrong reading rather than a missing one.
    //!
    //! -5C and 55C therefore share a position. In practice nothing confuses
    //! them, and the scale already wraps 60 onto 0 the same way.
    function fraction(celsius as Float) as Float {
        var turns = (celsius - SCALE_MIN_C) / (SCALE_MAX_C - SCALE_MIN_C);
        turns = turns - turns.toNumber();   // truncates toward zero
        if (turns < 0.0) {
            turns += 1.0;
        }
        return turns.toFloat();
    }

    function clamp(value as Float) as Float {
        if (value < 0.0) { return 0.0; }
        if (value > 1.0) { return 1.0; }
        return value;
    }
}
