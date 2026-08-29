import Toybox.Lang;
import Toybox.System;

//! When a reading of the world is stale enough to take again.
//!
//! Everything the face draws except the second hand moves slower than the
//! frame rate, and most of it far slower: the watch syncs weather from the
//! phone on the order of tens of minutes, body battery updates every few
//! minutes, a step ring moves one dot per ~36 steps and intensity minutes are
//! counted by the minute. Asking every second was asking questions whose
//! answers could not have changed.
//!
//! So the data modules take one sample a minute and answer from it. A minute
//! is not arbitrary: it is what always-on already gets, because the system
//! hands it one frame a minute. This makes the awake face agree with the
//! asleep one rather than being sixty times more eager about data that does
//! not move.
//!
//! **Seconds is the exception, and the only one.** ClockData is deliberately
//! not sampled: a ring assigned to seconds is asking for a second hand, and a
//! second hand read once a minute is a stopped one.
//!
//! One module rather than a constant copied into two, because the wrap below
//! is the kind of thing that gets written correctly once and subtly wrong the
//! second time.
module Sample {

    //! How long a sample is reused before the watch is asked again.
    const INTERVAL_MS = 60000;

    //! Is a sample taken at `takenAt` too old to use?
    //!
    //! `System.getTimer()` and not the clock: it is monotonic, where the wall
    //! clock jumps on a time-zone change or a sync and would then either
    //! freeze the sample or expire it on every frame.
    //!
    //! It does wrap — it is a millisecond count in a 32-bit Number, so about
    //! every 25 days — and the wrap is why this is a function rather than one
    //! subtraction at each call site. A sample that appears to have been taken
    //! in the *future* is that wrap rather than a fresh reading, and treating
    //! it as fresh would freeze the face's data for as long as it took the
    //! counter to catch up.
    function due(takenAt as Number, taken as Boolean) as Boolean {
        if (!taken) {
            return true;
        }
        var now = System.getTimer();
        if (now < takenAt) {
            return true;        //! the counter wrapped
        }
        return (now - takenAt) >= INTERVAL_MS;
    }

    //! The stamp to record against a sample taken now.
    function now() as Number {
        return System.getTimer();
    }
}
