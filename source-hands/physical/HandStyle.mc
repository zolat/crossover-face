import Toybox.Lang;

//! What the hands are, on a watch that has its own.
//!
//! One copy of this module per hand style, put on a device's source path by
//! `monkey.jungle`. It answers the two questions the rest of the face asks and
//! never decides for itself: are there hands to light the dots behind, and does
//! a ring tell the time instead.
//!
//! **Instinct Crossover AMOLED: two brass hands stand over the glass.**
//! The face draws no hands at all. `HandBacking` exists only to give the dots
//! *underneath* them a contrasting colour, so what you see is the lit field
//! emerging along a hand's edge. Backing is awake-only: in always-on it would
//! cost luminance for a detail nobody is looking at, and the brass keeps
//! telling the time whether the dots behind it are lit or not.
module HandStyle {

    //! True: there are hands, so the Hands setting lights the dots behind
    //! them, and the view asks the watch to hold them at system time, since
    //! backing is only correct while they show it.
    const HANDS = true;

    //! False: the brass hands tell the time, so no ring is given over to it.
    const TIME_RING = false;
}
