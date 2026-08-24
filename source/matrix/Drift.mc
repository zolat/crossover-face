import Toybox.Lang;
import Toybox.System;

//! Burn-in mitigation: walks the whole lattice around a small cycle so no
//! screen pixel stays lit indefinitely.
//!
//! The numbers are forced by the geometry. Dots are DotGrid.DOT (5px) wide, so
//! consecutive phases must differ by at least 5px for a pixel lit in one phase
//! to be dark in the next. The outermost dots sit 189px from centre and the
//! screen half-width is 195, leaving 195 - 189 - DOT/2 = 4px of headroom. An
//! amplitude of 3 gives 6px between opposite phases — decorrelated — while
//! keeping every dot on screen.
//!
//! Drift is applied when drawing only, never when deciding which dots exist,
//! so the field translates rigidly instead of popping dots in and out at the rim.
module Drift {

    //! Pixels either side of centre. See the note above before changing it:
    //! 3 is the largest value that does not clip the rim.
    const AMPLITUDE = 3;

    //! How long each phase holds, in minutes. Two keeps any pixel lit for less
    //! than the three minutes older Garmin AMOLEDs treated as burn-in risk,
    //! while being slow enough that the shift is not noticeable.
    const PERIOD_MINUTES = 2;

    //! Four corners, ordered so consecutive phases sit diagonally opposite and
    //! therefore share no pixels at all.
    const PHASES = [[-1, -1], [1, 1], [1, -1], [-1, 1]] as Array<Array<Number>>;

    function phaseFor(minute as Number) as Number {
        return (minute / PERIOD_MINUTES) % PHASES.size();
    }

    //! Offset as [x, y] for a given minute of the hour.
    function offsetFor(minute as Number) as Array<Number> {
        var phase = PHASES[phaseFor(minute)];
        return [phase[0] * AMPLITUDE, phase[1] * AMPLITUDE] as Array<Number>;
    }

    //! Offset for right now.
    function current() as Array<Number> {
        return offsetFor(System.getClockTime().min);
    }
}
