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
    var skips as Number = 0;

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

    //! A frame the gate skipped. Counted, never averaged in: folding a
    //! skipped frame's ~0ms into the average would make the readout describe
    //! how often the face draws rather than what a draw costs.
    function recordSkip() as Void {
        skips++;
    }

    function averageMs() as Number {
        return (frames == 0) ? 0 : totalMs / frames;
    }

    //! One line for a menu sub-label: "31ms avg / 44 worst / 76% skipped /
    //! 61k of 128k".
    //!
    //! Memory is reported as used against the total rather than as free, which
    //! is what it used to say. Free on its own is a number with nothing to
    //! measure it against, and it was misread once already — as a share of the
    //! wrong budget entirely, by comparing a debug .prg's *file size* to the
    //! device's runtime limit. Used-against-total states the position outright.
    function summary() as String {
        if (frames == 0) {
            return "no frames yet";
        }
        var stats = System.getSystemStats();
        return averageMs() + "ms avg / " + worstMs + " worst / " +
               FrameGate.skipPercent() + "% skipped / " +
               (stats.usedMemory / 1024) + "k of " +
               (stats.totalMemory / 1024) + "k";
    }
}
