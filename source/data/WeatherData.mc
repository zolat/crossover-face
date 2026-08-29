import Toybox.Lang;
import Toybox.System;
import Toybox.Weather;

//! Today's weather, normalised for drawing. Pure queries, no drawing.
//!
//! Temperatures arrive from Garmin in Celsius regardless of the watch's display
//! units, and the ring shows no numbers, so no conversion is needed.
//!
//! **One sample a minute, and one sample for all three readings.** The watch
//! syncs weather from the phone on the order of tens of minutes, so a face
//! asking every second was asking a question whose answer could not have
//! changed a thousand times over. A minute is what always-on already gets — it
//! is handed one frame a minute — so this makes the awake face agree with the
//! asleep one rather than being sixty times more eager about data that does not
//! move.
//!
//! The saving is not why it is worth doing: the whole per-frame preamble this
//! sits in measures 0-1ms against a ~70ms frame, and `Diagnostics`'s *idle*
//! figure is what would notice if that ever changed. What is worth doing is
//! the second half — the three readings now come from **one** call. They used
//! to take a `getCurrentConditions()` each, so on a temperature ring the band
//! and the mark drawn inside it could come from two different samples. One
//! sample cannot disagree with itself.
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

    //! The last sample, and when it was taken. Nulls are cached like any other
    //! answer: a watch that has never synced has no weather, and rediscovering
    //! that every second is the same wasted question.
    var takenAt as Number = 0;
    var sampled as Boolean = false;
    var lowC as Float? = null;
    var highC as Float? = null;
    var nowC as Float? = null;
    var rain as Float? = null;

    //! Take a fresh sample if the last one has expired. Sample owns when that
    //! is, and why it is timed on a monotonic counter rather than the clock.
    function refresh() as Void {
        if (!Sample.due(takenAt, sampled)) {
            return;
        }
        takenAt = Sample.now();
        sampled = true;
        lowC = null;
        highC = null;
        nowC = null;
        rain = null;

        if (!(Toybox has :Weather)) {
            return;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return;
        }
        var low = conditions.lowTemperature;
        var high = conditions.highTemperature;
        if (low != null && high != null) {
            lowC = low.toFloat();
            highC = high.toFloat();
        }
        var current = conditions.temperature;
        if (current != null) {
            nowC = current.toFloat();
        }
        var chance = conditions.precipitationChance;
        if (chance != null) {
            rain = clamp(chance / 100.0);
        }
    }

    //! Drop the sample, so the next read goes to the watch. For the tests, and
    //! for anything that needs to prove it is seeing a fresh reading.
    function forget() as Void {
        sampled = false;
    }

    //! Today's low and high as fractions of the scale, or null when there is
    //! no forecast — a watch that has never synced has no weather at all.
    function dayRange() as Array<Float>? {
        refresh();
        var low = lowC;
        var high = highC;
        if (low == null || high == null) {
            return null;
        }
        return [fraction(low), fraction(high)] as Array<Float>;
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
    //!
    //! A minute's staleness is invisible here, and that is measurable rather
    //! than hopeful: the mark is a single dot, and a ring's dots are 0.026 to
    //! 0.076 of a turn apart, so the mark does not move until the reading has
    //! shifted by something between one and a half and four and a half degrees.
    function currentFraction() as Float? {
        refresh();
        var current = nowC;
        if (current == null) {
            return null;
        }
        return fraction(current);
    }

    //! Chance of precipitation, 0.0-1.0, or null when unknown.
    function rainChance() as Float? {
        refresh();
        return rain;
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
