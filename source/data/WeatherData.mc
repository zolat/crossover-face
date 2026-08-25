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
    function fraction(celsius as Float) as Float {
        return clamp((celsius - SCALE_MIN_C) / (SCALE_MAX_C - SCALE_MIN_C));
    }

    function clamp(value as Float) as Float {
        if (value < 0.0) { return 0.0; }
        if (value > 1.0) { return 1.0; }
        return value;
    }
}
