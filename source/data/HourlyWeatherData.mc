import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

//! Hourly weather fields packed into the shared twelve-block ring shape.
//!
//! One Weather.getHourlyForecast() supplies every hourly weather source. Rain
//! and UV therefore cannot disagree because two calls happened to straddle a
//! sync, and assigning both outer rings still costs one watch query a minute.
//! Each field keeps its own known bits: an entry can know rain and omit UV, or
//! the other way round, without either one inventing an answer for the other.
//!
//! The hour-hand anchoring is free. At local hour H, a forecast N hours ahead
//! belongs at (H + N) mod 12, exactly where the hand will point. The packed
//! table is never rotated downstream.
module HourlyWeatherData {

    //! One complete turn of the dial, beginning at the current local hour.
    const WINDOW_S = HourBands.HOURS * 3600;

    //! Garmin documents the hourly UV index as 0–10 on this target.
    const UV_MAX = 10.0;

    var takenAt as Number = 0;
    var sampled as Boolean = false;
    var anchorHour as Number = -1;

    var rainLevels as Array<Number> = [0, 0] as Array<Number>;
    var rainKnown as Number = 0;
    var uvLevels as Array<Number> = [0, 0] as Array<Number>;
    var uvKnown as Number = 0;

    //! Refresh once a minute, and immediately when the local hour changes.
    function refresh() as Void {
        var clock = System.getClockTime();
        if (sampled && clock.hour == anchorHour &&
                !Sample.due(takenAt, sampled)) {
            return;
        }
        takenAt = Sample.now();
        sampled = true;
        anchorHour = clock.hour;
        clear();

        if (!(Toybox has :Weather) || !(Weather has :getHourlyForecast)) {
            return;
        }
        var forecast = Weather.getHourlyForecast();
        if (forecast == null) {
            return;
        }

        // Start of the current local hour expressed as a UTC epoch. Subtracting
        // local minute and second also works in half- and quarter-hour zones.
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
            if (chance != null) {
                HourBands.raise(rainLevels, block, rainLevelFor(chance));
                rainKnown = rainKnown | (1 << block);
            }

            // uvIndex arrived in API 5.1. The target is API 6, while the has
            // guard keeps this source honest if another product is added later.
            if (entry has :uvIndex) {
                var uv = entry.uvIndex;
                if (uv != null) {
                    HourBands.raise(uvLevels, block, uvLevelFor(uv));
                    uvKnown = uvKnown | (1 << block);
                }
            }
        }
    }

    function clear() as Void {
        rainLevels[0] = 0;
        rainLevels[1] = 0;
        rainKnown = 0;
        uvLevels[0] = 0;
        uvLevels[1] = 0;
        uvKnown = 0;
    }

    //! Copy rain from the shared sample into one ring's block channel.
    function fillRain(out as Array<Number>, at as Number) as Void {
        refresh();
        copy(out, at, rainLevels, rainKnown);
    }

    //! Copy UV from the shared sample into one ring's block channel.
    function fillUv(out as Array<Number>, at as Number) as Void {
        refresh();
        copy(out, at, uvLevels, uvKnown);
    }

    function copy(out as Array<Number>, at as Number,
                  words as Array<Number>, known as Number) as Void {
        out[at] = words[0];
        out[at + 1] = words[1];
        out[at + 2] = known;
    }

    //! Which absolute clock block a forecast epoch occupies, or -1 outside the
    //! forward twelve-hour window.
    function blockFor(anchor as Number, anchorEpoch as Number,
                      secs as Number) as Number {
        var offset = secs - anchorEpoch;
        if (offset < 0 || offset >= WINDOW_S) {
            return -1;
        }
        return (anchor + (offset / 3600)) % HourBands.HOURS;
    }

    function rainLevelFor(percent as Number) as Number {
        return HourBands.levelFromFraction(percent / 100.0);
    }

    function uvLevelFor(index as Float) as Number {
        return HourBands.levelFromFraction(index / UV_MAX);
    }

    function forget() as Void {
        sampled = false;
        anchorHour = -1;
    }
}
