import Toybox.Lang;

//! The data a ring can be assigned to.
//!
//! Every source reports a *span* — a start and end position, both 0.0-1.0 —
//! rather than a single level. Most are levels and simply return [0, value],
//! filling from the origin. Temperature is a genuine range: today's low to
//! today's high. One shape covers both, so the layouts do not care which is
//! which and a range works in bands and rings alike.
//!
//! A source may also decline to report while the watch is in always-on, which
//! is what `awake` is for. Only seconds uses it: everything else is worth the
//! same in either mode, and always-on gets one frame a minute anyway.
module Source {

    enum Kind {
        SOURCE_STEPS = 0,
        SOURCE_HEART_RATE = 1,
        SOURCE_BATTERY = 2,
        SOURCE_BODY_BATTERY = 3,
        SOURCE_TEMPERATURE = 4,
        SOURCE_RAIN = 5,
        SOURCE_SECONDS = 6,
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
        0xCCCCCC,   // seconds
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
    //!
    //! `awake` is false in always-on. A source that has nothing to say there
    //! reports EMPTY, which lights nothing: no dot sits at position 0.0 in any
    //! layout, so a zero-length span at the origin is genuinely dark rather
    //! than a hairline of lit dots.
    function span(source as Number, awake as Boolean) as Array<Float> {
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
            case SOURCE_SECONDS:
                // Awake only, and deliberately so. Always-on is asked for one
                // frame a minute, so a per-second reading could only ever be
                // stale there — and it is the mode the burn-in and luminance
                // rules are written against, which is no place to add motion.
                return awake ? level(ClockData.minuteSweep()) : EMPTY;
            default:
                return EMPTY;
        }
    }

    //! A level fills from the origin, so its span starts at zero.
    function level(value as Float) as Array<Float> {
        return [0.0, value] as Array<Float>;
    }
}
