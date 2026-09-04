import Toybox.Lang;

//! Decides what of a frame is worth drawing.
//!
//! Awake, the system asks for a frame every second. The face has no second
//! hand and the hands themselves are physical, so most of those frames are
//! pixel-for-pixel the frame before: steps, heart rate and battery move
//! slowly, and the burn-in drift shifts only every two minutes. Drawing ~1100
//! dots to reproduce an identical image is the single largest avoidable cost
//! the face has.
//!
//! So each frame is fingerprinted and an unchanged one is not drawn. The
//! fingerprint is in **two parts**, and that split is the whole design:
//!
//!   - the **field** print — the burn-in drift and the hands — covers anything
//!     that moves every dot at once. When it changes there is nothing to
//!     salvage, so the screen is cleared and all four rings are redrawn;
//!   - a **ring** print per ring — its span, its mark, its over flag. A ring
//!     whose print is unchanged is already on screen, correct, and is simply
//!     not walked.
//!
//! The second part is what a whole-frame gate could not do. A ring assigned to
//! seconds moves its span every tick, so the frame differs every second and an
//! all-or-nothing gate opens every second — redrawing four rings because one of
//! them moved. This module's own comment used to accept that as "the cost of
//! asking for a second hand". It is not: the cost of a second hand is drawing
//! the seconds ring, and now that is what it costs.
//!
//! Four things keep not-drawing safe:
//!
//!   - **one complete always-on frame per minute.** The view explicitly starts
//!     a transition frame when the minute changes, so only duplicate callbacks
//!     inside that minute can be skipped;
//!   - **a cap on consecutive skips.** Anything that damages the frame buffer
//!     from outside — a notification banner, a system alert — is repaired only
//!     by a draw. Past the cap the next frame is a full clear and redraw;
//!   - **an explicit transition().** Shows, power-mode changes and settings
//!     changes draw one complete frame before duplicates may be skipped;
//!   - **every change is drawn HOLD times, not once.** See HOLD.
//!
//! Prints are compared value by value rather than hashed. A collision here
//! would freeze a stale ring until the cap fired, and the comparison is a
//! handful of floats against the ~280-dot walk it saves.
module FrameGate {

    //! Draw at least this often regardless. Thirty seconds keeps a bounded
    //! repair while avoiding a complete field repaint inside the roughly
    //! ten-second high-power window of an ordinary wrist raise.
    const MAX_SKIPS = 30;

    //! How many consecutive draws a change is repeated into.
    //!
    //! Not drawing at all is safe whatever the device does with its buffers:
    //! whatever is on screen stays on screen. Drawing *part* of a frame is
    //! only safe if the buffer handed to onUpdate is the one that was last
    //! presented — and on a double-buffered device it is the one from two
    //! draws ago. Repeating each change into two consecutive draws puts it
    //! into both buffers either way. The cost is that a ring which moved is
    //! walked twice; the alternative is a ring that is right in one buffer and
    //! a second stale in the other.
    const HOLD = 2;

    var skipped as Number = 0;          //! consecutive frames skipped
    var drawn as Number = 0;
    var suppressed as Number = 0;       //! total skipped, for the diagnostics

    //! Which rings this frame must draw, and whether the screen must be
    //! cleared first. Read by the view straight after plan() says yes.
    var dirty as Array<Boolean> = new [StatMap.RINGS] as Array<Boolean>;
    var clears as Boolean = true;

    //! Draws each ring, and the clear, still owe. See HOLD.
    var held as Array<Number> = new [StatMap.RINGS] as Array<Number>;
    var clearsHeld as Number = HOLD;

    //! Frames since the screen was last cleared, skipped ones included.
    //!
    //! This is the repair, and it counts frames rather than skips because a
    //! partial redraw repairs no more than a skip does outside the ring it
    //! draws. Damage from outside the face — a notification banner, a system
    //! alert — lands anywhere, so only a clear is certain to remove it, and a
    //! face drawing one ring a second would otherwise never clear at all.
    var sinceClear as Number = MAX_SKIPS;

    var _field as Array<Float>? = null;
    var _rings as Array<Float>? = null;
    var _forceFull as Boolean = true;

    //! A lifecycle transition draws one complete frame immediately, but does
    //! not blindly draw the same field again on the following callback. The
    //! other buffer is primed on the next frame that genuinely needed drawing
    //! anyway. Until then a skipped callback leaves the presented buffer alone.
    var _firstAfterTransition as Boolean = false;
    var _transitionNeedsSecondBuffer as Boolean = false;

    //! Values per ring in the ring print: span start, span end, mark, over,
    //! and the block channel's three packed words.
    //!
    //! The block words have to be here or their source does not work at all. A
    //! block ring's span, mark and over flag never move — the span is EMPTY
    //! every frame — so without them the ring would never be marked dirty, and
    //! a forecast change would surface only when the periodic repair fired.
    //!
    //! Their own slots rather than borrowed span ones: `spans[ring]` flows
    //! straight into the renderer's from/to and its remembered deltas, and a
    //! number that means two different things depending on the ring is exactly
    //! the sort of thing that reads fine and breaks a year later.
    const PER_RING = 7;

    //! Work out what this frame has to draw. True when that is anything at all.
    //!
    //! `field` is what moves every dot at once; `rings` is PER_RING values for
    //! each ring, laid out flat.
    function plan(field as Array<Float>, rings as Array<Float>) as Boolean {
        var firstAfterTransition = _firstAfterTransition;
        // Holds are armed by a *change*, never by the state of this frame.
        // Re-arming them every frame the clear is still owed would stop them
        // ever draining, and the face would redraw itself forever.
        var previousField = _field;
        if (_forceFull || previousField == null ||
                !same(previousField, field)) {
            // A real change to the whole field — a drift step, or the hands
            // moving under the backing. Held like any other change, because it
            // is one.
            var repeat = firstAfterTransition ? 1 : HOLD;
            clearsHeld = repeat;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                held[ring] = repeat;
            }
        } else if (sinceClear >= MAX_SKIPS) {
            // The periodic repair, and deliberately **one** frame rather than
            // HOLD of them. HOLD exists because a partial draw is only correct
            // in the buffer it lands in; a clear followed by all four rings
            // defines the whole buffer by itself, so repeating it buys nothing
            // and costs the most expensive frame the face has. Repeating it is
            // also what a measurement caught: at default rings, where the gate
            // skips most frames and the repair is nearly every draw there is,
            // holding it took the skip rate from 82% to 68% — the face doing
            // half as much again for no picture anyone could see.
            clearsHeld = 1;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                held[ring] = 1;
            }
        }
        var previousRings = _rings;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (previousRings == null ||
                    ringMoved(previousRings, rings, ring)) {
                held[ring] = firstAfterTransition ? 1 : HOLD;
            }
        }

        clears = (clearsHeld > 0);
        var anything = false;

        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            dirty[ring] = (held[ring] > 0);
            if (dirty[ring]) {
                anything = true;
            }
        }

        // After the first transition frame, the other buffer may still hold the
        // previous picture. Do not manufacture a draw merely to replace it;
        // when a real change eventually opens the gate, make that draw a full
        // one. It primes the second buffer before any later delta can depend on
        // both buffers carrying the active palette.
        var primesTransitionBuffer = _transitionNeedsSecondBuffer &&
                                     !firstAfterTransition && anything;
        if (primesTransitionBuffer) {
            clears = true;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                dirty[ring] = true;
            }
        }

        _field = copy(field, _field);
        _rings = copy(rings, _rings);

        if (!anything) {
            skipped++;
            suppressed++;
            sinceClear++;      //! a skip repairs nothing
            return false;
        }
        // Only a draw retires a hold, so a change is repeated into consecutive
        // *draws* rather than merely surviving a couple of seconds.
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (held[ring] > 0) {
                held[ring]--;
            }
        }
        if (clearsHeld > 0) {
            clearsHeld--;
        }
        sinceClear = clears ? 0 : (sinceClear + 1);
        if (firstAfterTransition) {
            _firstAfterTransition = false;
        } else if (primesTransitionBuffer) {
            _transitionNeedsSecondBuffer = false;
        }
        _forceFull = false;
        skipped = 0;
        drawn++;
        return true;
    }

    //! Every ring, cleared and redrawn — always-on, and anything that cannot
    //! vouch for what is on screen.
    function everything() as Array<Boolean> {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            dirty[ring] = true;
        }
        clears = true;
        sinceClear = 0;
        return dirty;
    }

    //! Force the next frames to be drawn in full. Anything that can change the
    //! face without changing a print has to say so here.
    function forget() as Void {
        _forceFull = true;
        skipped = 0;
        sinceClear = MAX_SKIPS;
        clearsHeld = HOLD;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            held[ring] = HOLD;
        }
        _firstAfterTransition = false;
        _transitionNeedsSecondBuffer = false;
    }

    //! Force one complete frame after a show, wake, sleep or settings boundary,
    //! then defer the second buffer's complete repaint until some visible value
    //! actually changes. Transition bursts therefore get one render followed by
    //! cheap identical-frame returns in either power mode.
    function transition() as Void {
        _forceFull = true;
        skipped = 0;
        sinceClear = MAX_SKIPS;
        clearsHeld = 1;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            held[ring] = 1;
        }
        _firstAfterTransition = true;
        _transitionNeedsSecondBuffer = true;
    }

    //! Has this ring's slice of the print moved?
    function ringMoved(previous as Array<Float>, current as Array<Float>,
                       ring as Number) as Boolean {
        var at = ring * PER_RING;
        for (var i = 0; i < PER_RING; i++) {
            if (previous[at + i] != current[at + i]) {
                return true;
            }
        }
        return false;
    }

    //! Element-wise, because a hash collision would freeze a stale frame.
    function same(a as Array<Float>, b as Array<Float>) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    //! Keep the values, not the caller's array.
    //!
    //! The view fills one buffer every frame and hands the same one back, so
    //! storing the reference would compare an array with itself — always equal,
    //! and the face would freeze to one draw per cap. Copying is what lets the
    //! caller stop allocating.
    function copy(from as Array<Float>, into as Array<Float>?) as Array<Float> {
        var out = into;
        if (out == null || out.size() != from.size()) {
            out = new [from.size()] as Array<Float>;
        }
        for (var i = 0; i < from.size(); i++) {
            out[i] = from[i];
        }
        return out;
    }

    //! Share of frames that needed no drawing at all.
    function skipPercent() as Number {
        var total = drawn + suppressed;
        return (total == 0) ? 0 : (suppressed * 100) / total;
    }
}
