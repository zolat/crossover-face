import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Works out which of the two analogue hands a dot sits under, so it can be
//! given a colour of that hand's own.
//!
//! On the Crossover that colour is a *backing*: the hands are brass over the
//! glass, and what is lit is what sits behind them. The footprint is their own
//! outline exactly — no wider — which is how Garmin's own faces do it, so what
//! you see is the lit field emerging along a hand's edge.
//!
//! On a watch with no hands the same answer means something else. Lighting the
//! covered dots *is* the hand. That is the whole of how the Epix 2 family tells
//! the time: no polygon, no new primitive, and not a line of FrameGate. Which
//! reading applies is HandStyle's business, not this module's — here there are
//! only hands and dots.
//!
//! Hand geometry lives in `Lattice`, so it moves with the screen. The numbers
//! start as a property of the hardware — read off the Crossover's own
//! simulator.json, where both hands are 28px wide with a 46px counterweight
//! behind the pivot, the hour hand reaching 131px and the minute 176px — and a
//! larger screen scales them by its radius, so the drawn hands reach into the
//! field the way the brass ones reach across the glass.
//!
//! On a watch whose hands are real, this is correct only while they show system
//! time; the view asks for that explicitly via View.setClockHandPosition().
//! A watch with no hands never backs anything, so none of this runs there.
module HandBacking {

    //! What handAt() answers with, and the slots a colour table is indexed by.
    const NONE = 0;
    const HOUR = 1;
    const MINUTE = 2;
    const SLOTS = 3;

    //! Colour for each slot handAt() can return: nothing, the hour hand, the
    //! minute hand. Both hands take the one backing colour, because the brass
    //! hands themselves are what tell them apart — the dots only have to sit
    //! behind. A table rather than one colour so the renderer's loop is an
    //! index, whichever hand a dot is under.
    function coloursFor(backing as Number) as Array<Number> {
        return [0, backing, backing] as Array<Number>;
    }

    const HALF_WIDTH as Number = Lattice.HAND_HALF_WIDTH;
    const COUNTERWEIGHT as Number = Lattice.HAND_COUNTERWEIGHT;
    const HOUR_REACH as Number = Lattice.HOUR_REACH;
    const MINUTE_REACH as Number = Lattice.MINUTE_REACH;

    var _axes as Array<Float> =
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] as Array<Float>;

    //! Unit vectors and turn positions for both hands:
    //! [hourX, hourY, minuteX, minuteY, hourTurn, minuteTurn].
    //!
    //! One clock read owns both representations. The renderer needs the axes
    //! for the exact bar and the turns for its cheap angular gate; deriving
    //! them in separate calls used to read the clock twice and allocate a
    //! second array on every drawn frame.
    function axes() as Array<Float> {
        var clock = System.getClockTime();
        var hourDegrees = ((clock.hour % 12) * 30.0) + (clock.min * 0.5);
        var minuteDegrees = clock.min * 6.0;
        var hour = Math.toRadians(hourDegrees);
        var minute = Math.toRadians(minuteDegrees);
        // Screen y grows downward and 0 degrees points at twelve o'clock.
        _axes[0] = Math.sin(hour).toFloat();
        _axes[1] = -Math.cos(hour).toFloat();
        _axes[2] = Math.sin(minute).toFloat();
        _axes[3] = -Math.cos(minute).toFloat();
        _axes[4] = (hourDegrees / 360.0).toFloat();
        _axes[5] = (minuteDegrees / 360.0).toFloat();
        return _axes;
    }

    //! Which hand covers this dot: NONE, HOUR or MINUTE.
    //!
    //! Takes the axes already unpacked into scalars, and tests both hands
    //! itself rather than calling a helper twice. This is called once per dot
    //! with the hands on — measured at 11ms a frame in that mode, a third of
    //! the whole frame — and at ~1100 dots the call overhead was most of it.
    //! Three interpreted calls per dot became one.
    //!
    //! Projects the dot onto each hand's axis: `along` runs tip-wards, `across`
    //! is the perpendicular offset. A dot is covered when it falls inside the
    //! hand's length and half-width.
    //!
    //! **The minute hand is tested first, so where the two cross it wins.**
    //! That is the physical stack — the minute hand is the upper of the brass
    //! pair — and a drawn face that stacked them the other way would read as
    //! the hour hand passing in front, which no watch does. It costs nothing:
    //! the answer was already one branch or the other.
    //!
    //! Returning which hand rather than whether one covers is what lets a drawn
    //! face colour them differently while the Crossover, which needs only one
    //! backing colour, points both slots at it. The caller indexes a three-slot
    //! array, so neither style pays a branch the other does not.
    function handAt(dx as Number, dy as Number,
                    hourX as Float, hourY as Float,
                    minuteX as Float, minuteY as Float) as Number {
        var along = dx * minuteX + dy * minuteY;
        if (along <= MINUTE_REACH && along >= -COUNTERWEIGHT) {
            var across = (dx * -minuteY) + (dy * minuteX);
            if (across >= -HALF_WIDTH && across <= HALF_WIDTH) {
                return MINUTE;
            }
        }
        along = dx * hourX + dy * hourY;
        if (along <= HOUR_REACH && along >= -COUNTERWEIGHT) {
            var across = (dx * -hourY) + (dy * hourX);
            if (across >= -HALF_WIDTH && across <= HALF_WIDTH) {
                return HOUR;
            }
        }
        return NONE;
    }
}
