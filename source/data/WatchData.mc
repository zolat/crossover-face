import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Reads device state and formats it for display. Pure queries — no drawing,
//! so the always-on renderer can pull only what it is allowed to show.
module WatchData {

    //! "9:41" or "21:41" depending on the user's 24-hour setting.
    function timeText() as String {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour.format("%d"), clock.min.format("%02d")]);
    }

    //! "MON 24 AUG"
    function dateText() as String {
        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var weekday = now.day_of_week;
        var month = now.month;
        return Lang.format("$1$ $2$ $3$", [
            weekday == null ? "" : weekday.toString().toUpper(),
            now.day.format("%02d"),
            month == null ? "" : month.toString().toUpper()
        ]);
    }

    //! Battery charge, 0-100.
    function batteryPercent() as Number {
        return System.getSystemStats().battery.toNumber();
    }

    //! Steps so far today, or null if unavailable.
    function steps() as Number? {
        return ActivityMonitor.getInfo().steps;
    }

    //! Current heart rate in bpm, or null when there is no reading.
    function heartRate() as Number? {
        return Activity.getActivityInfo().currentHeartRate;
    }
}
