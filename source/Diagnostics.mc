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
//!
//! **Two costs are tracked, not one.** A drawn frame and a skipped one are
//! different work and averaging them together would describe neither. The
//! drawn average answers "does a draw still fit the watchdog"; the skipped
//! average answers "what does the face pay to decide it has nothing to do" —
//! and until it was measured, nobody knew. Everything before FrameGate runs on
//! every frame either way: four sources read, their spans, marks and over
//! flags built, and a fingerprint compared. On a face that skips 83% of its
//! frames that preamble is the most-executed code there is.
module Diagnostics {

    //! Halve the running totals past this many frames, so the average tracks
    //! recent frames instead of averaging away a change over the whole session.
    const WINDOW = 512;

    //! Print the summary to the console every this many frames. The watch has
    //! nowhere to print, so this is for `make sim` and the MCP runner's log —
    //! it is how every before/after figure in this module's history was taken.
    //! One const rather than a build annotation, so a measurement run is one
    //! edit away and the shipped default is silence.
    const TRACE = false;
    const TRACE_EVERY = 10;

    var frames as Number = 0;
    var totalMs as Number = 0;
    var worstMs as Number = 0;

    //! The skipped frame's own cost, kept apart from the drawn one above.
    var skips as Number = 0;
    var skipTotalMs as Number = 0;
    var skipWorstMs as Number = 0;

    var _sinceTrace as Number = 0;

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
        trace();
    }

    //! A frame the gate skipped, and what deciding that cost.
    //!
    //! Counted and averaged separately, never folded into the drawn average:
    //! a skipped frame's few milliseconds mixed into that figure would make it
    //! describe how often the face draws rather than what a draw costs.
    function recordSkip(ms as Number) as Void {
        if (skips >= WINDOW) {
            skips = skips / 2;
            skipTotalMs = skipTotalMs / 2;
        }
        skips++;
        skipTotalMs += ms;
        if (ms > skipWorstMs) {
            skipWorstMs = ms;
        }
        trace();
    }

    function averageMs() as Number {
        return (frames == 0) ? 0 : totalMs / frames;
    }

    //! What a frame costs when the gate decides not to draw it — the preamble
    //! every frame pays before anything is drawn.
    function skipAverageMs() as Number {
        return (skips == 0) ? 0 : skipTotalMs / skips;
    }

    //! One line for a menu sub-label: "31ms avg / 44 worst / 3ms idle /
    //! 76% skipped / 61k of 128k".
    //!
    //! Memory is reported as used against the total rather than as free, which
    //! is what it used to say. Free on its own is a number with nothing to
    //! measure it against, and it was misread once already — as a share of the
    //! wrong budget entirely, by comparing a debug .prg's *file size* to the
    //! device's runtime limit. Used-against-total states the position outright.
    function summary() as String {
        if (frames == 0 && skips == 0) {
            return "no frames yet";
        }
        var stats = System.getSystemStats();
        return averageMs() + "ms avg / " + worstMs + " worst / " +
               skipAverageMs() + "ms idle / " +
               FrameGate.skipPercent() + "% skipped / " +
               (stats.usedMemory / 1024) + "k of " +
               (stats.totalMemory / 1024) + "k";
    }

    //! Print the summary periodically, for a measurement run. Silent unless
    //! TRACE is on, and the counter is kept regardless so turning it on does
    //! not have to wait for a fresh session.
    function trace() as Void {
        _sinceTrace++;
        if (_sinceTrace < TRACE_EVERY) {
            return;
        }
        _sinceTrace = 0;
        if (TRACE) {
            System.println(summary());
        }
    }
}
