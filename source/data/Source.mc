import Toybox.Lang;

//! The data a ring can be assigned to.
//!
//! Every source reports a *span* — a start and end position, both 0.0-1.0 —
//! rather than a single level. Most are levels and simply return [0, value],
//! filling from the origin. Temperature is a genuine range: today's low to
//! today's high. One shape covers both, so the layouts do not care which is
//! which and a range works in bands and rings alike.
module Source {

    enum Kind {
        SOURCE_STEPS = 0,
        SOURCE_HEART_RATE = 1,
        SOURCE_BATTERY = 2,
        SOURCE_BODY_BATTERY = 3,
        SOURCE_TEMPERATURE = 4,
        SOURCE_RAIN = 5,
        SOURCE_INTENSITY_MINUTES = 6,
        SOURCE_OFF = 7
    }

    const COUNT = 8;

    const EMPTY = [0.0, 0.0] as Array<Float>;

    //! Colour for each source. Temperature is drawn on a cold-to-hot ramp
    //! instead, so its entry here is only the fallback tint.
    const HUES = [
        0xFF6600,   // steps
        0xFF3322,   // heart rate
        0x33CC55,   // battery
        0x3388FF,   // body battery
        0xFFAA00,   // temperature
        0x00CCDD,   // rain
        0xCC44FF,   // intensity minutes
        0x444444    // off
    ] as Array<Number>;

    function hue(source as Number) as Number {
        if (source < 0 || source >= COUNT) {
            return HUES[SOURCE_OFF];
        }
        return HUES[source];
    }

    //! Current [start, end] for a source. Reading is done once per frame, so
    //! this is called four times per draw, not once per dot.
    function span(source as Number) as Array<Float> {
        switch (source) {
            case SOURCE_STEPS:
                return level(WatchData.steps());
            case SOURCE_HEART_RATE:
                return level(WatchData.heartRate());
            case SOURCE_BATTERY:
                return level(WatchData.battery());
            case SOURCE_BODY_BATTERY:
                return level(WatchData.bodyBattery());
            case SOURCE_TEMPERATURE:
                var range = WeatherData.dayRange();
                return (range != null) ? range : EMPTY;
            case SOURCE_RAIN:
                var rain = WeatherData.rainChance();
                return (rain != null) ? level(rain) : EMPTY;
            case SOURCE_INTENSITY_MINUTES:
                return level(WatchData.intensityMinutes());
            default:
                return EMPTY;
        }
    }

    //! A level fills from the origin, so its span starts at zero.
    function level(value as Float) as Array<Float> {
        return [0.0, value] as Array<Float>;
    }

    //! A position no ring can hold, meaning "this source has nothing to mark".
    //!
    //! Positions run 0.0 to below 1.0, so a negative one is unreachable. The
    //! renderer tests for it once per ring rather than once per dot.
    const NO_MARKER = -1.0;

    //! A single position on the ring to mark, on top of the span.
    //!
    //! Kept apart from span() rather than folded into it: that a span is
    //! exactly two numbers is what lets every layout treat a range and a level
    //! alike, and the tests lean on it throughout. A marker is a different
    //! thing — one point rather than an interval — so it travels beside the
    //! span, not inside it.
    //!
    //! Read once per frame per ring, like span().
    function marker(source as Number) as Float {
        if (source == SOURCE_TEMPERATURE) {
            var now = WeatherData.currentFraction();
            return (now != null) ? now : NO_MARKER;
        }
        return NO_MARKER;
    }
}
