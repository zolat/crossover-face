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
//! is what `awake` is for. Seconds goes dark there, and the two goals stop
//! reporting their overflow; everything else is worth the same in either mode,
//! and always-on gets one frame a minute anyway.
//!
//! Two of the sources are *goals* rather than bounded quantities, and a goal
//! can be beaten. Past 100% the span stops describing the fill and describes
//! the *second lap* instead — see goal() and over().
module Source {

    enum Kind {
        SOURCE_STEPS = 0,
        SOURCE_HEART_RATE = 1,
        SOURCE_BATTERY = 2,
        SOURCE_BODY_BATTERY = 3,
        SOURCE_TEMPERATURE = 4,
        SOURCE_RAIN = 5,
        SOURCE_INTENSITY_MINUTES = 6,
        SOURCE_SECONDS = 7,
        SOURCE_OFF = 8
    }

    const COUNT = 9;

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
                return goal(WatchData.steps(), awake);
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
                return goal(WatchData.intensityMinutes(), awake);
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

    //! What a goal reports: the fill up to 100%, or the *second lap* past it.
    //!
    //! Once the goal is met the ring is full, so a span that went on describing
    //! the fill would say nothing more however far past the goal the reading
    //! went — 100% and 250% draw the same band. Past it the span describes the
    //! overflow instead, and MatrixRenderer swaps that ring's two tiers to
    //! match: the unfilled tier becomes "goal met" and the filled one becomes
    //! "gone past it". No dot in the render loop learns any of this.
    //!
    //! Asleep it is an ordinary capped level. Over-ness is awake-only, for the
    //! reason the mark and the hand backing are: it costs luminance for a
    //! detail nobody is reading, in the mode measured against the burn-in
    //! budget. A ring that met its goal still reads as full there, which is
    //! true — it just stops saying by how much.
    function goal(value as Float, awake as Boolean) as Array<Float> {
        if (!isOver(value, awake)) {
            return level(value > 1.0 ? 1.0 : value);
        }
        // At or past double, the second lap is full too. Carrying on round
        // would say "only just started" at the moment of doing twice the goal,
        // so it stops at one completed lap instead.
        return level(value >= 2.0 ? 1.0 : value - 1.0);
    }

    //! Whether a goal reading is past 100%, and so drawing its second lap.
    //!
    //! Strictly greater: at exactly the goal the ring is simply full. Treating
    //! that as over would hand the renderer a zero-length lap and put a mark on
    //! the origin at the very moment the goal was met.
    //!
    //! goal() and over() both decide over-ness here rather than each testing
    //! for themselves. If the two could ever disagree, a ring at 105% would
    //! draw its lap span without the tier swap and read as 5%.
    function isOver(value as Float, awake as Boolean) as Boolean {
        return awake && (value > 1.0);
    }

    //! Is this ring past its goal? Read once per frame per ring, beside
    //! span() — the two cannot be told apart from the span alone, since a lap
    //! of 0.34 and a fill of 0.34 are the same two numbers.
    function over(source as Number, awake as Boolean) as Boolean {
        switch (source) {
            case SOURCE_STEPS:
                return isOver(WatchData.steps(), awake);
            case SOURCE_INTENSITY_MINUTES:
                return isOver(WatchData.intensityMinutes(), awake);
            default:
                // Nothing else has a goal to beat. Battery, body battery and
                // rain are bounded by what they measure; heart rate's ceiling
                // is a display range rather than a goal; seconds is cyclic;
                // and temperature is a range whose wrap past twelve is the
                // design rather than an overflow.
                return false;
        }
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
