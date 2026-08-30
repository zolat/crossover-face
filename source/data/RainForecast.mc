import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

//! The next twelve hours of rain, packed into two integers.
//!
//! Beside WeatherData rather than inside it. The one-call rule there is about
//! three readings that must not disagree with each other — the band and the
//! mark drawn inside it come from a single `getCurrentConditions()`. This is a
//! different API product with no such coupling, and folding it in would make
//! every face pay for a call that only matters when a ring is assigned to it.
//! Source.fillHours() is the early return that keeps that promise.
//!
//! **The anchoring is free, and that is the whole trick.** The hour hand at
//! local hour `H` points at clock position `H mod 12`, and the forecast `N`
//! hours ahead has to sit at `(H + N) mod 12` — which is exactly that forecast
//! hour's own hour-of-day, mod 12. So a forecast entry is bucketed by *its own*
//! local hour and lands where the hand will be when it arrives. Nothing rotates.
//!
//! Two words rather than a twelve-entry array: they ride in the frame print,
//! which FrameGate compares as floats element by element, and they must survive
//! that intact. `levels` is two bits a block and tops out at 0xFFFFFF, `known`
//! is one bit a block and tops out at 0xFFF — both inside the range a Float
//! represents exactly, which theHourlyMasksSurviveTheFramePrint pins.
module RainForecast {

    //! How far ahead the ring reaches. One turn of the dial.
    const WINDOW_S = HourBands.HOURS * 3600;

    //! One sub-band per this many percent. tierFor() derives from it, so the
    //! scale and the geometry cannot drift apart.
    const STEP_PERCENT = 100 / (HourBands.BANDS + 1);

    //! Every block known. Not a forecast — what always-on reports when the
    //! fills are held back, where "known and dry everywhere" is the only
    //! reading that draws a plain unfilled ring.
    const ALL_KNOWN = 0xFFF;

    //! The last sample, and when it was taken. Nulls are cached like any other
    //! answer: a watch that has never synced has no forecast, and rediscovering
    //! that every frame is the same wasted question.
    var takenAt as Number = 0;
    var sampled as Boolean = false;

    //! The local hour this sample was bucketed against. See refresh().
    var anchorHour as Number = -1;

    var levels as Number = 0;
    var known as Number = 0;

    //! Take a fresh sample if the last one has expired — or if the hour has
    //! rolled over.
    //!
    //! **The hour test is load-bearing and is not an optimisation.** A sample
    //! bucketed against hour 14 is wrong the instant the clock reads 15,
    //! however recently it was taken: block 14 would still hold this
    //! afternoon's expired reading rather than tomorrow morning's. Sample.due()
    //! alone would leave that on screen for up to a minute. It also absorbs a
    //! time-zone or DST jump at the next read rather than at the next minute.
    function refresh() as Void {
        var clock = System.getClockTime();
        if (sampled && clock.hour == anchorHour &&
                !Sample.due(takenAt, sampled)) {
            return;
        }
        takenAt = Sample.now();
        sampled = true;
        anchorHour = clock.hour;
        levels = 0;
        known = 0;

        if (!(Toybox has :Weather) || !(Weather has :getHourlyForecast)) {
            return;
        }
        var forecast = Weather.getHourlyForecast();
        if (forecast == null) {
            return;
        }
        // The start of the current *local* hour, as a UTC epoch. Subtracting
        // the local minutes and seconds rather than taking a modulus is what
        // makes the half-hour and forty-five-minute zones bucket correctly:
        // forecastTime is UTC, and in Kathmandu the top of the local hour is
        // not the top of a UTC one.
        var anchorEpoch = Time.now().value() - (clock.min * 60 + clock.sec);
        for (var i = 0; i < forecast.size(); i++) {
            var entry = forecast[i];
            var when = entry.forecastTime;
            if (when == null) {
                continue;
            }
            var block = blockFor(anchorHour, anchorEpoch, when.value());
            if (block < 0) {
                continue;
            }
            var chance = entry.precipitationChance;
            if (chance == null) {
                // Known when, unknown how much. That is still no forecast for
                // the hour, so the block stays dim rather than reading as dry.
                continue;
            }
            levels = withTier(levels, block, tierFor(chance));
            known = known | (1 << block);
        }
    }

    //! Which block a forecast time belongs in, or -1 when it is outside the
    //! window this ring covers.
    //!
    //! The lower bound is tested explicitly rather than left to the division.
    //! Monkey C truncates toward zero, so an entry an hour in the past would
    //! divide to 0 and land on the current hour — showing yesterday's weather
    //! as now, with nothing to say it had happened.
    function blockFor(anchor as Number, anchorEpoch as Number,
                      secs as Number) as Number {
        var offset = secs - anchorEpoch;
        if (offset < 0 || offset >= WINDOW_S) {
            return -1;
        }
        return (anchor + (offset / 3600)) % HourBands.HOURS;
    }

    //! Which sub-band a percentage reaches: 0 dry, up to BANDS soaked.
    function tierFor(percent as Number) as Number {
        if (percent < 0) {
            return 0;
        }
        var tier = percent / STEP_PERCENT;
        return (tier > HourBands.BANDS) ? HourBands.BANDS : tier;
    }

    //! `levels` with this block raised to `tier`, never lowered.
    //!
    //! Garmin should give one entry per hour, but nothing documents that, and
    //! two entries landing in one block is the case where "will it rain in this
    //! hour" has an obvious answer: whichever said more. Taking the maximum is
    //! also what makes the merge order-independent, so a reordered forecast
    //! array cannot change the picture.
    //!
    //! Subtracting the existing bits rather than masking them out: they are
    //! exactly the bits being replaced, so the subtraction clears them, and it
    //! avoids leaning on how Monkey C widens a bitwise complement.
    function withTier(packed as Number, block as Number,
                      tier as Number) as Number {
        var shift = block * 2;
        var existing = (packed >> shift) & 3;
        if (tier <= existing) {
            return packed;
        }
        return packed - (existing << shift) + (tier << shift);
    }

    //! Drop the sample, so the next read goes to the watch. For the tests, and
    //! for anything that needs to prove it is seeing a fresh reading.
    function forget() as Void {
        sampled = false;
        anchorHour = -1;
    }
}
