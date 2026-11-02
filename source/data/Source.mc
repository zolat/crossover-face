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
        SOURCE_BODY_BATTERY_HOURS = 11,
        //! The next twelve hours of temperature, filled linearly between two
        //! temperatures the wearer sets (StatMap.tempAheadLow / tempAheadHigh):
        //! an hour at or below the low end is an empty block, at or above the
        //! high end a full one. A fixed scale cannot suit both Adelaide and
        //! Oslo, so the range is a setting rather than a constant.
        SOURCE_TEMP_HOURS = 12,
        //! Temperature range, with today's sunrise and sunset called out on
        //! the same ring: the band, ramp and current-temperature mark exactly
        //! as SOURCE_TEMPERATURE draws them, plus one dot at each sun time.
        //! See SunData for where those sit and fillSuns() for how they travel.
        SOURCE_TEMP_SUN = 13,
        //! The time, on a watch with no hands, split: the hour fills the
        //! ring's inner sub-band and the minute its outer two, both clockwise
        //! from twelve, in white.
        //!
        //! **Never in OFFERED and never in settings.xml.** A watch whose
        //! HandStyle carries the time in a ring has StatMap.load() put a time
        //! style on the outermost ring whatever else that ring stores, so a
        //! face can never end up without the time; the ring's own picker
        //! offers the styles and nothing else (offeredFor). Anywhere else a
        //! stored time reads as Off, which keeps it off the Crossover, whose
        //! brass hands already say what o'clock it is.
        //!
        //! Its span is not a start and an end like every other source's. It is
        //! the two hands' ends — [hour, minute] — which TimeRing reads as two
        //! fills of the same ring. Riding the span is what puts the time in the
        //! ring print, and so in the gate, for free.
        SOURCE_TIME = 14,
        //! The time again, overlapping: hour and minute each fill the *whole*
        //! ring from twelve. Where both have passed is the ring's own theme
        //! colour, and the hour and minute are its hue split either way, as
        //! blue and red make purple; whichever sticks out past the ring's
        //! colour is the one ahead. The same span as SOURCE_TIME; only the
        //! drawing differs.
        SOURCE_TIME_OVERLAP = 15
    }

    const COUNT = 16;

    //! The time styles, in picker order: what the time ring offers instead
    //! of OFFERED.
    const TIME_STYLES = [SOURCE_TIME_OVERLAP, SOURCE_TIME] as Array<Number>;

    //! The style a hands-free watch starts on, and falls back to when its time
    //! ring stores anything that is not a time style.
    const TIME_DEFAULT = SOURCE_TIME_OVERLAP;

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
        SOURCE_TEMP_SUN,
        SOURCE_TEMP_HOURS,
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
        0x3388FF,   // Body Battery, last 12h
        0xFFAA00,   // temperature, next 12h
        0xFFAA00,   // temperature range with sunrise and sunset
        0xFFFFFF,   // time, split (drawn from Palette; this is the fallback)
        0x9B5CFF    // time, overlap (drawn from the theme; likewise)
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
        var out = [0.0, 0.0] as Array<Float>;
        fillSpan(source, awake, out);
        return out;
    }

    //! Refill a caller-owned span. The watch-face view uses this path so the
    //! once-per-second preamble does not allocate one two-float array per ring.
    function fillSpan(source as Number, awake as Boolean,
                      out as Array<Float>) as Void {
        switch (source) {
            case SOURCE_STEPS:
                fillGoal(WatchData.steps(), awake, out);
                return;
            case SOURCE_BATTERY:
                fillLevel(WatchData.battery(), out);
                return;
            case SOURCE_BODY_BATTERY:
                fillLevel(BodyBatteryData.current(), out);
                return;
            case SOURCE_TEMPERATURE:
            case SOURCE_TEMP_SUN:
                if (!WeatherData.fillDayRange(out)) {
                    fillEmpty(out);
                }
                return;
            case SOURCE_RAIN:
                var rain = WeatherData.rainChance();
                if (rain != null) {
                    fillLevel(rain, out);
                } else {
                    fillEmpty(out);
                }
                return;
            case SOURCE_RAIN_HOURS:
            case SOURCE_UV_HOURS:
            case SOURCE_BODY_BATTERY_HOURS:
            case SOURCE_TEMP_HOURS:
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
                fillEmpty(out);
                return;
            case SOURCE_INTENSITY_MINUTES:
                fillGoal(WatchData.intensityMinutes(), awake, out);
                return;
            case SOURCE_SECONDS:
                // Awake only, and deliberately so. Always-on is asked for one
                // frame a minute, so a per-second reading could only ever be
                // stale there — and it is the mode the burn-in and luminance
                // rules are written against, which is no place to add motion.
                if (awake) {
                    fillLevel(ClockData.minuteSweep(), out);
                } else {
                    fillEmpty(out);
                }
                return;
            case SOURCE_TIME:
            case SOURCE_TIME_OVERLAP:
                // Both power modes. The minute is all always-on is asked for,
                // and it is the one mode a watch without hands most needs it.
                ClockData.fillTime(out);
                return;
            default:
                fillEmpty(out);
                return;
        }
    }

    function fillEmpty(out as Array<Float>) as Void {
        out[0] = EMPTY[0];
        out[1] = EMPTY[1];
    }

    function fillLevel(value as Float, out as Array<Float>) as Void {
        out[0] = 0.0;
        out[1] = value;
    }

    function fillGoal(value as Float, awake as Boolean,
                      out as Array<Float>) as Void {
        out[0] = 0.0;
        if (!isOver(value, awake)) {
            out[1] = value > 1.0 ? 1.0 : value;
        } else {
            out[1] = value >= 2.0 ? 1.0 : value - 1.0;
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
    //! reason the hand backing is: it costs luminance for a detail nobody is
    //! reading, in the mode measured against the burn-in budget — a whole
    //! ring's worth, where the temperature mark that does draw asleep costs a
    //! single dot. A ring that met its goal still reads as full there, which is
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
        if (isTemperatureRange(source)) {
            var now = WeatherData.currentFraction();
            return (now != null) ? now : NO_MARKER;
        }
        return NO_MARKER;
    }

    //! Does this source draw today's temperature range — the band on the
    //! cold-to-hot ramp with the current reading marked inside it?
    //!
    //! The predicate rather than the enum value, for the reason usesBlocks()
    //! is one: the span, the mark and the renderer's ramp all have to agree on
    //! which rings carry it, and a consumer still testing for
    //! SOURCE_TEMPERATURE alone would draw the sun variant as a flat band.
    function isTemperatureRange(source as Number) as Boolean {
        return source == SOURCE_TEMPERATURE || source == SOURCE_TEMP_SUN;
    }

    //! Does this ring tell the time? A predicate for usesBlocks()'s reason:
    //! the loader, the held-back mode and the renderer all have to agree.
    function isTime(source as Number) as Boolean {
        return source == SOURCE_TIME || source == SOURCE_TIME_OVERLAP;
    }

    //! Values per ring in the sun channel: sunrise, then sunset.
    const SUN_VALUES = 2;

    //! This ring's sun positions, [sunrise, sunset], into `out` at `at` —
    //! NO_MARKER for each when the ring has none to show.
    //!
    //! A channel of its own beside the marker rather than more markers. A
    //! marker is one position and one dot, and the tests and the gate both
    //! lean on that; the sun times are two more positions that a single source
    //! carries, and they travel beside the mark the way the blocks travel
    //! beside the span.
    //!
    //! Read once per frame per ring. A ring without the variant never reads a
    //! complication for it.
    function fillSuns(source as Number, out as Array<Float>,
                      at as Number) as Void {
        if (source == SOURCE_TEMP_SUN) {
            SunData.fill(out, at);
            return;
        }
        out[at] = NO_MARKER;
        out[at + 1] = NO_MARKER;
    }

    //! The innermost ring a block source may be assigned to (index 0 is the
    //! outermost, so this is "ring 3" in the menu).
    //!
    //! It needs twelve blocks, each three sub-bands deep and enough dots wide
    //! to read. Rings 0 and 1 have 436 and 340 dots — 26.7 and 20.0 an hour at
    //! a 22.5-degree block — and their thinnest sub-band holds 8 and 6. Ring 2
    //! has 224, and its thinnest sub-band holds 4: coarser, but it draws every
    //! rung of the level scale, so it was let in as a trade the wearer can
    //! choose rather than kept out on a threshold. Ring 3 has 112, its thinnest
    //! sub-band holds 2, and sixteen (block, level) pairs light no dot at all —
    //! part of the scale is invisible there, which no choice makes readable.
    //! blockRingsResolveTwelveHoursInThreeBands measures both.
    const BLOCKS_TOP_RING = 2;

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
               source == SOURCE_BODY_BATTERY_HOURS ||
               source == SOURCE_TEMP_HOURS;
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
    //!
    //! A hands-free watch's time ring is the exception: it offers the time
    //! styles and only them, so the face can be restyled but never left
    //! without the time.
    function offeredFor(ring as Number) as Array<Number> {
        if (HandStyle.TIME_RING && ring == StatMap.TIME_RING) {
            return TIME_STYLES;
        }
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
            case SOURCE_TEMP_HOURS:
                HourlyWeatherData.fillTemp(out, at);
                return;
            default:
                out[at] = 0;
                out[at + 1] = 0;
                out[at + 2] = 0;
                return;
        }
    }
}
