import Toybox.Lang;

//! The data a ring can be assigned to.
//!
//! Every source reports a *span* — a start and end position, both 0.0-1.0 —
//! rather than a single level. Most are levels and simply return [0, value],
//! filling from the origin. Temperature is a genuine range: today's low to
//! today's high. One shape covers both, so nothing downstream has to care
//! which is which — a range fills the same way a level does.
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
        //! Retired. Was heart rate, taken off the face as not worth a ring.
        //!
        //! The slot stays rather than the ones after it shifting down. Stored
        //! settings are **list indices**, so renumbering would not remove a
        //! source, it would silently rename every source above it — a watch
        //! with Battery on ring 3 would come back showing Body Battery, and
        //! nothing would report that it had happened. StatMap.load() maps a
        //! stored 1 to SOURCE_OFF, which is the honest reading of "the source
        //! this ring had is gone", and Source.OFFERED is what keeps it out of
        //! the picker.
        SOURCE_RETIRED = 1,
        SOURCE_BATTERY = 2,
        SOURCE_BODY_BATTERY = 3,
        SOURCE_TEMPERATURE = 4,
        SOURCE_RAIN = 5,
        SOURCE_INTENSITY_MINUTES = 6,
        SOURCE_SECONDS = 7,
        SOURCE_OFF = 8,
        //! The next twelve hours of rain: where round the ring says *when*,
        //! and how much of that hour's block is filled says *how likely* —
        //! outward through the ring's three sub-bands, then wider across the
        //! block, for sixteen readings an hour. See HourBands.
        //!
        //! **Appended after Off, which looks wrong and is the whole point.**
        //! Stored settings are list indices, so a new source inserted anywhere
        //! below Off would renumber Off and everything above it on every watch
        //! already carrying a setting. Going after it is what keeps every
        //! existing index meaning what it has always meant. Source.OFFERED
        //! decides picker *order*, and there this sits next to the other rain.
        SOURCE_RAIN_HOURS = 9,
        //! The next twelve hours of UV, on Garmin's bounded 0–10 scale.
        SOURCE_UV_HOURS = 10,
        //! Current Body Battery and the preceding eleven hours, read backwards
        //! from the hour hand. Completed hours are averages; current is live.
        SOURCE_BODY_BATTERY_HOURS = 11
    }

    const COUNT = 12;

    //! The sources a ring may actually be assigned to, in picker order.
    //!
    //! Not "every value below COUNT" any more: SOURCE_RETIRED is a number that
    //! still has to mean what it always meant to a stored setting, but must
    //! never be offered again. The picker walks this; the tables above stay
    //! indexed by the enum, so the two cannot drift.
    const OFFERED = [
        SOURCE_STEPS,
        SOURCE_BATTERY,
        SOURCE_BODY_BATTERY,
        SOURCE_BODY_BATTERY_HOURS,
        SOURCE_TEMPERATURE,
        SOURCE_RAIN,
        SOURCE_RAIN_HOURS,
        SOURCE_UV_HOURS,
        SOURCE_INTENSITY_MINUTES,
        SOURCE_SECONDS,
        SOURCE_OFF
    ] as Array<Number>;

    const EMPTY = [0.0, 0.0] as Array<Float>;

    //! Colour for each source. Temperature is drawn on a cold-to-hot ramp
    //! instead, so its entry here is only the fallback tint.
    const HUES = [
        0xFF6600,   // steps
        0xFF3322,   // retired (was heart rate)
        0x33CC55,   // battery
        0x3388FF,   // body battery
        0xFFAA00,   // temperature
        0x00CCDD,   // rain
        0xCC44FF,   // intensity minutes
        0xCCCCCC,   // seconds
        0x444444,   // off
        0x0088CC,   // rain, next 12h
        0xFFCC00,   // UV, next 12h
        0x3388FF    // Body Battery, last 12h
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
    //! reports EMPTY, which lights nothing: no dot sits exactly at twelve, so
    //! a zero-length span at the origin is genuinely dark rather than a
    //! hairline of lit dots.
    function span(source as Number, awake as Boolean) as Array<Float> {
        switch (source) {
            case SOURCE_STEPS:
                return goal(WatchData.steps(), awake);
            case SOURCE_BATTERY:
                return level(WatchData.battery());
            case SOURCE_BODY_BATTERY:
                return level(BodyBatteryData.current());
            case SOURCE_TEMPERATURE:
                var range = WeatherData.dayRange();
                return (range != null) ? range : EMPTY;
            case SOURCE_RAIN:
                var rain = WeatherData.rainChance();
                return (rain != null) ? level(rain) : EMPTY;
            case SOURCE_RAIN_HOURS:
            case SOURCE_UV_HOURS:
            case SOURCE_BODY_BATTERY_HOURS:
                // Twelve disjoint blocks with a radial axis is not something
                // two floats can say, and widening the span so it could would
                // make every consumer of one branch on shape. So this source
                // lights nothing *through the span* and reports its real
                // payload beside it, in fillBlocks() below — the same move
                // marker() makes, for the same reason.
                //
                // EMPTY rather than StatMap.NEVER_LIT: sourceTablesCoverEveryKind
                // holds every kind's span inside 0.0-1.0, and NEVER_LIT sits
                // out at 2.0 deliberately. Both light nothing here, because the
                // block ring never reads its span at all.
                return EMPTY;
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
                // Nothing else has a goal to beat. Battery, body battery,
                // rain and UV are bounded by what they measure; seconds is
                // cyclic; and temperature is a range whose wrap past twelve
                // is the design rather than an overflow.
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
    //! exactly two numbers is what lets a range and a level be treated alike,
    //! and the tests lean on it throughout. A marker is a different
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

    //! The outermost ring a block source may be assigned to.
    //!
    //! It needs twelve blocks, each three sub-bands deep and a good handful of
    //! dots wide, and only the outer two rings have them: 436 and 340 dots,
    //! which at a 22.5-degree block is 26.7 and 20.0 dots an hour. Ring 2 has
    //! 224 and ring 3 has 112, where a sub-band is one or two dots wide and the
    //! hours stop being countable.
    //!
    //! The block *level* sharpens that on the ring where it bites hardest.
    //! Its bottom rungs are a fraction of one band's width, and on the
    //! innermost ring sixteen (block, level) pairs light no dot at all — the
    //! scale is not merely cramped down there, part of it is invisible. Ring 2
    //! draws every rung, so its exclusion rests on the dot count above and on
    //! nothing else. onlyTheOuterTwoRingsResolveTwelveHoursInThreeBands
    //! measures both.
    const BLOCKS_TOP_RING = 1;

    //! Does this source draw twelve blocks rather than a span?
    //!
    //! **The predicate, not the enum value.** A block source is a shape, and
    //! the renderer, the loader, the picker and the gate all have to ask which
    //! shape a ring is drawing. Nothing outside this function names individual
    //! block kinds, so adding one cannot leave it drawn as an empty span in a
    //! forgotten consumer.
    function usesBlocks(source as Number) as Boolean {
        return source == SOURCE_RAIN_HOURS ||
               source == SOURCE_UV_HOURS ||
               source == SOURCE_BODY_BATTERY_HOURS;
    }

    //! May this source be assigned to this ring? Index 0 is the outermost.
    //!
    //! One definition, because the restriction is enforced in three places —
    //! the loader, the on-device picker and settings.xml — and three copies of
    //! a rule is how the three stop agreeing.
    function allowedOn(source as Number, ring as Number) as Boolean {
        return !(usesBlocks(source) && ring > BLOCKS_TOP_RING);
    }

    //! The sources this particular ring may be assigned to, in picker order.
    function offeredFor(ring as Number) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < OFFERED.size(); i++) {
            if (allowedOn(OFFERED[i], ring)) {
                out.add(OFFERED[i]);
            }
        }
        return out;
    }

    //! This ring's packed blocks: two words of levels, then the known bits.
    //!
    //! Three slots filled from **one** refresh, so no two blocks can come from
    //! different samples — the same correctness argument WeatherData makes for
    //! taking its three readings from one call.
    //!
    //! The early return is what keeps this free for every face with no ring
    //! assigned to a block source: it is called four times a frame, in the
    //! preamble that runs before the gate decides, and a face without one never
    //! reads a clock for it.
    //!
    //! A new block source is one more case here and nothing else. The channel,
    //! packing and drawing are shape-shaped rather than source-shaped.
    function fillBlocks(source as Number, out as Array<Number>,
                        at as Number) as Void {
        switch (source) {
            case SOURCE_RAIN_HOURS:
                HourlyWeatherData.fillRain(out, at);
                return;
            case SOURCE_UV_HOURS:
                HourlyWeatherData.fillUv(out, at);
                return;
            case SOURCE_BODY_BATTERY_HOURS:
                BodyBatteryData.fillHistory(out, at);
                return;
            default:
                out[at] = 0;
                out[at + 1] = 0;
                out[at + 2] = 0;
                return;
        }
    }
}
