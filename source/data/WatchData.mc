import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.UserProfile;

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
module WatchData {

    //! Heart rate is mapped between the user's resting rate and this ceiling.
    //! A fixed ceiling beats a 220-minus-age estimate here: the face wants a
    //! stable visual range, not a training-zone calculation.
    const HR_FLOOR = 50;
    const HR_CEILING = 180;

    function steps() as Float {
        var info = ActivityMonitor.getInfo();
        var count = info.steps;
        var goal = info.stepGoal;
        if (count == null || goal == null || goal <= 0) {
            return 0.0;
        }
        return ratio(count.toFloat() / goal);
    }

    //! Weekly intensity minutes against the weekly goal. Garmin counts a
    //! vigorous minute twice, which `ActiveMinutes.total` already does, so this
    //! is the same figure the watch's own widget shows.
    function intensityMinutes() as Float {
        var info = ActivityMonitor.getInfo();
        var minutes = info.activeMinutesWeek;
        var goal = info.activeMinutesWeekGoal;
        if (minutes == null || goal == null || goal <= 0) {
            return 0.0;
        }
        return ratio(minutes.total.toFloat() / goal);
    }

    function heartRate() as Float {
        var rate = Activity.getActivityInfo().currentHeartRate;
        if (rate == null) {
            return 0.0;
        }
        var floor = HR_FLOOR;
        var resting = UserProfile.getProfile().restingHeartRate;
        if (resting != null && resting > 0) {
            floor = resting;
        }
        if (floor >= HR_CEILING) {
            return 0.0;
        }
        return clamp((rate - floor).toFloat() / (HR_CEILING - floor));
    }

    function battery() as Float {
        return clamp(System.getSystemStats().battery / 100.0);
    }

    function bodyBattery() as Float {
        if (!(Toybox has :SensorHistory) ||
            !(SensorHistory has :getBodyBatteryHistory)) {
            return 0.0;
        }
        var history = SensorHistory.getBodyBatteryHistory(
            {:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
        var sample = history.next();
        if (sample == null) {
            return 0.0;
        }
        var level = sample.data;
        if (level == null) {
            return 0.0;
        }
        return clamp(level / 100.0);
    }

    //! A goal ratio. Floored at zero, and deliberately *not* capped at one:
    //! past the goal the excess is the reading, and Source.lap() is what turns
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
