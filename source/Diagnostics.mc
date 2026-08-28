import Toybox.Lang;
import Toybox.System;

//! What a frame actually costs, on the watch.
//!
//! The simulator's drawing primitives are far slower than the watch's silicon,
//! so a frame time measured there says very little about the device — but the
//! watch has nowhere to print to. So the face keeps the figure itself and the
//! settings menu shows it back.
//!
//! Cheap enough to leave running: two clock reads and a few additions on a
//! frame that already costs tens of milliseconds.
module Diagnostics {

    //! Halve the running totals past this many frames, so the average tracks
    //! recent frames instead of averaging away a change over the whole session.
    const WINDOW = 512;

    var frames as Number = 0;
    var totalMs as Number = 0;
    var worstMs as Number = 0;

    function record(ms as Number) as Void {
        if (frames >= WINDOW) {
            frames = frames / 2;
            totalMs = totalMs / 2;
        }
        frames++;
        totalMs += ms;
        if (ms > worstMs) {
            worstMs = ms;
        }
    }

    function averageMs() as Number {
        return (frames == 0) ? 0 : totalMs / frames;
    }

    //! One line for a menu sub-label: "31ms avg / 44 worst / 76k free".
    function summary() as String {
        if (frames == 0) {
            return "no frames yet";
        }
        var free = System.getSystemStats().freeMemory / 1024;
        return averageMs() + "ms avg / " + worstMs + " worst / " + free + "k free";
    }
}
