import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;

//! Current Body Battery and its last twelve clock hours from one data owner.
//!
//! The live ring and the history ring used to be separate-looking questions but
//! they read the same sensor iterator. Keeping them here prevents two rings from
//! sampling two different "current" values in one frame.
//!
//! History reads backwards from the hour hand. The current clock hour carries
//! the newest valid value; each of the preceding eleven clock positions carries
//! the mean of every valid sample in that completed hour. Averages are taken in
//! raw 0–100 units and quantised only once, after the hour is complete.
module BodyBatteryData {

    const WINDOW_S = HourBands.HOURS * 3600;

    var currentTakenAt as Number = 0;
    var currentSampled as Boolean = false;
    var currentKnown as Boolean = false;
    var currentValue as Float = 0.0;

    var historySampled as Boolean = false;
    var anchorHour as Number = -1;
    var levels as Array<Number> = [0, 0] as Array<Number>;
    var known as Number = 0;

    // Reused scratch storage. A full history refresh is hourly, but allocating
    // two arrays every time would still leave garbage for no benefit.
    var sums as Array<Float> = new [HourBands.HOURS] as Array<Float>;
    var counts as Array<Number> = new [HourBands.HOURS] as Array<Number>;

    //! Current Body Battery as a 0.0–1.0 fraction. Missing data keeps the
    //! existing level source empty, as it did before this module existed.
    function current() as Float {
        refreshCurrent();
        return currentKnown ? currentValue : 0.0;
    }

    //! Fill one ring's three packed block values.
    function fillHistory(out as Array<Number>, at as Number) as Void {
        refreshHistory();
        refreshCurrent();
        writeCurrent();
        out[at] = levels[0];
        out[at + 1] = levels[1];
        out[at + 2] = known;
    }

    //! Read just the newest entry once a minute. A full history read seeds this
    //! cache too, so a face showing both Body Battery sources does not call the
    //! iterator twice after the history source has run.
    function refreshCurrent() as Void {
        if (!Sample.due(currentTakenAt, currentSampled)) {
            return;
        }
        currentTakenAt = Sample.now();
        currentSampled = true;
        currentKnown = false;
        currentValue = 0.0;

        if (!(Toybox has :SensorHistory) ||
            !(SensorHistory has :getBodyBatteryHistory)) {
            return;
        }
        var history = SensorHistory.getBodyBatteryHistory(
            {:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
        var sample = history.next();
        if (sample == null) {
            return;
        }
        var data = sample.data;
        if (data == null) {
            return;
        }
        currentValue = fraction(data);
        currentKnown = true;
    }

    //! Rebuild completed-hour averages on first use and each local-hour change.
    function refreshHistory() as Void {
        var clock = System.getClockTime();
        if (historySampled && clock.hour == anchorHour) {
            return;
        }
        historySampled = true;
        anchorHour = clock.hour;
        resetHistory();

        if (!(Toybox has :SensorHistory) ||
            !(SensorHistory has :getBodyBatteryHistory)) {
            return;
        }

        var nowEpoch = Time.now().value();
        var anchorEpoch = nowEpoch - (clock.min * 60 + clock.sec);
        var oldestEpoch = anchorEpoch - ((HourBands.HOURS - 1) * 3600);
        var history = SensorHistory.getBodyBatteryHistory(
            {:period => new Time.Duration(WINDOW_S),
             :order => SensorHistory.ORDER_NEWEST_FIRST});
        var sample = history.next();
        var newest = false;
        while (sample != null) {
            var data = sample.data;
            var secs = sample.when.value();
            if (data != null && secs >= oldestEpoch && secs <= nowEpoch) {
                var value = percent(data);
                if (!newest) {
                    currentValue = value / 100.0;
                    currentKnown = true;
                    newest = true;
                }

                // Current hour is a live value, never an average. Gregorian.info
                // maps completed samples to the clock position the hand occupied
                // then; repeated DST hours therefore combine and skipped hours
                // remain unknown.
                if (secs < anchorEpoch) {
                    var info = Time.Gregorian.info(sample.when,
                                                   Time.FORMAT_SHORT);
                    var block = blockForHour(info.hour);
                    if (block != (anchorHour % HourBands.HOURS)) {
                        addPast(block, value);
                    }
                }
            }
            sample = history.next();
        }

        finishPast(anchorHour % HourBands.HOURS);
        currentTakenAt = Sample.now();
        currentSampled = true;
        writeCurrent();
    }

    function resetHistory() as Void {
        levels[0] = 0;
        levels[1] = 0;
        known = 0;
        currentKnown = false;
        currentValue = 0.0;
        for (var i = 0; i < HourBands.HOURS; i++) {
            sums[i] = 0.0;
            counts[i] = 0;
        }
    }

    //! The absolute clock block occupied by a local hour. With an anchor H,
    //! hours H-1, H-2 ... therefore walk counter-clockwise without rotating the
    //! renderer. Repeated DST hours intentionally return the same block.
    function blockForHour(hour as Number) as Number {
        return hour % HourBands.HOURS;
    }

    //! Add one clamped, unquantised 0–100 sample to a completed hour.
    function addPast(block as Number, value as Float) as Void {
        sums[block] += value;
        counts[block]++;
    }

    //! Quantise completed-hour means after every raw sample has been included.
    function finishPast(currentBlock as Number) as Void {
        for (var block = 0; block < HourBands.HOURS; block++) {
            if (block == currentBlock || counts[block] == 0) {
                continue;
            }
            var average = (sums[block] / counts[block]) / 100.0;
            HourBands.setLevel(levels, block,
                               HourBands.levelFromFraction(average));
            known = known | (1 << block);
        }
    }

    //! Replace the current block rather than raising it: Body Battery drains.
    function writeCurrent() as Void {
        if (anchorHour < 0) {
            return;
        }
        var block = anchorHour % HourBands.HOURS;
        var bit = 1 << block;
        if ((known & bit) != 0) {
            known -= bit;
        }
        HourBands.setLevel(levels, block, 0);
        if (currentKnown) {
            HourBands.setLevel(levels, block,
                               HourBands.levelFromFraction(currentValue));
            known = known | bit;
        }
    }

    function fraction(value as Numeric) as Float {
        return percent(value) / 100.0;
    }

    function percent(value as Numeric) as Float {
        var reading = value.toFloat();
        if (reading < 0.0) { return 0.0; }
        if (reading > 100.0) { return 100.0; }
        return reading;
    }

    function forget() as Void {
        currentSampled = false;
        historySampled = false;
        anchorHour = -1;
    }
}
