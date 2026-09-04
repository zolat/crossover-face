import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.System;

//! Reads device state and normalises it for drawing, which is all the face
//! needs: the design shows no numbers, only fill levels. Pure queries — nothing
//! here draws, so the renderer stays ignorant of where data comes from.
//!
//! Most readings are bounded by what they measure and come back inside 0.0-1.0.
//! The two *goals* — steps and intensity minutes — do not: they report the raw
//! ratio to the goal and go past 1.0 when the goal is beaten, because a beaten
//! goal is exactly the thing the face wants to show. Source turns the excess
//! into a second lap; capping it here would throw the reading away before
//! anything could.
//!
//! **One sample a minute, all of it from one pass.** None of these move faster
//! than that in a way the face can show: a step ring resolves about 36 steps to
//! a dot, intensity minutes are counted by the minute, battery moves over
//! hours. Body Battery has its own owner now because its current value and its
//! hourly history must come from the same sensor sample; see BodyBatteryData.
//! See Sample for why a minute and why it is timed the way it is.
//!
//! It also removes a duplicate read that was there from the start. Source asks
//! for steps twice a frame — once for the span, once to decide whether the goal
//! is beaten — and each ask used to be its own ActivityMonitor.getInfo(). Worse
//! than the cost, the two could disagree: a step landing between them would put
//! a span and its over flag one reading apart, which is the pair whose
//! disagreement draws a lap of 0.05 as a fill of 0.05.
module WatchData {

    //! The last sample, and when it was taken.
    var takenAt as Number = 0;
    var sampled as Boolean = false;
    var stepRatio as Float = 0.0;
    var intensityRatio as Float = 0.0;
    var batteryLevel as Float = 0.0;

    //! Take a fresh sample if the last one has expired.
    function refresh() as Void {
        if (!Sample.due(takenAt, sampled)) {
            return;
        }
        takenAt = Sample.now();
        sampled = true;

        var info = ActivityMonitor.getInfo();
        stepRatio = readSteps(info);
        intensityRatio = readIntensity(info);
        batteryLevel = clamp(System.getSystemStats().battery / 100.0);
    }

    //! Drop the sample, so the next read goes to the watch. For the tests, and
    //! for anything that needs to prove it is seeing a fresh reading.
    function forget() as Void {
        sampled = false;
    }

    function steps() as Float {
        refresh();
        return stepRatio;
    }

    //! Weekly intensity minutes against the weekly goal. Garmin counts a
    //! vigorous minute twice, which `ActiveMinutes.total` already does, so this
    //! is the same figure the watch's own widget shows.
    function intensityMinutes() as Float {
        refresh();
        return intensityRatio;
    }

    function battery() as Float {
        refresh();
        return batteryLevel;
    }

    // -- the readings themselves --------------------------------------------

    function readSteps(info as ActivityMonitor.Info) as Float {
        var count = info.steps;
        var goal = info.stepGoal;
        if (count == null || goal == null || goal <= 0) {
            return 0.0;
        }
        return ratio(count.toFloat() / goal);
    }

    function readIntensity(info as ActivityMonitor.Info) as Float {
        var minutes = info.activeMinutesWeek;
        var goal = info.activeMinutesWeekGoal;
        if (minutes == null || goal == null || goal <= 0) {
            return 0.0;
        }
        return ratio(minutes.total.toFloat() / goal);
    }

    //! A goal ratio. Floored at zero, and deliberately *not* capped at one:
    //! past the goal the excess is the reading, and Source.goal() is what turns
    //! it into a second lap round the ring.
    function ratio(value as Float) as Float {
        if (value < 0.0) { return 0.0; }
        return value;
    }

    //! For the readings that genuinely cannot exceed their range.
    function clamp(value as Float) as Float {
        if (value < 0.0) { return 0.0; }
        if (value > 1.0) { return 1.0; }
        return value;
    }
}
