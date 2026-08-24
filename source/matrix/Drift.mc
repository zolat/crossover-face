import Toybox.Lang;
import Toybox.System;

//! Burn-in mitigation: walks the whole lattice around a small cycle so no
//! screen pixel stays lit indefinitely.
//!
//! The numbers are forced by the geometry — see OFFSETS below.
//!
//! Drift is applied when drawing only, never when deciding which dots exist,
//! so the field translates rigidly instead of popping dots in and out at the rim.
module Drift {

    //! The two positions each axis takes. They are asymmetric on purpose.
    //!
    //! At PITCH 10 with DOT 5 there is exactly 5px of slack between one dot
    //! and its neighbour, and two competing requirements for it: a dot must
    //! move at least DOT to stop sharing pixels with *itself*, and no more
    //! than the slack or it starts landing on its *neighbour*. Offsets of -2
    //! and +3 are exactly DOT apart and consume exactly the slack, satisfying
    //! both. A symmetric range of the same width would not: +3/-3 spans 6px
    //! and collides with the next dot along.
    const OFFSETS = [-2, 3] as Array<Number>;

    //! Furthest a dot is ever pushed from its nominal position.
    const MAX_OFFSET = 3;

    //! How long each phase holds, in minutes. Two keeps any pixel lit for less
    //! than the three minutes older Garmin AMOLEDs treated as burn-in risk,
    //! while being slow enough that the shift is not noticeable.
    const PERIOD_MINUTES = 2;

    //! Four corners, ordered so consecutive phases sit diagonally opposite.
    const PHASES = [[0, 0], [1, 1], [1, 0], [0, 1]] as Array<Array<Number>>;

    function phaseFor(minute as Number) as Number {
        return (minute / PERIOD_MINUTES) % PHASES.size();
    }

    //! Offset as [x, y] for a given minute of the hour.
    function offsetFor(minute as Number) as Array<Number> {
        var phase = PHASES[phaseFor(minute)];
        return [OFFSETS[phase[0]], OFFSETS[phase[1]]] as Array<Number>;
    }

    //! Offset for right now.
    function current() as Array<Number> {
        return offsetFor(System.getClockTime().min);
    }
}
