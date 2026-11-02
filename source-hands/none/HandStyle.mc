import Toybox.Lang;

//! What the hands are, on a watch that has none.
//!
//! One copy of this module per hand style, put on a device's source path by
//! `monkey.jungle`. It answers the two questions the rest of the face asks and
//! never decides for itself: are there hands to light the dots behind, and does
//! a ring tell the time instead.
//!
//! **The Epix 2 family: the outer ring is the clock.** It used to draw an hour
//! and a minute hand out of the field's own dots. Those were the face's most
//! expensive feature — a per-dot hand test that held the 454 lattice below its
//! natural size, and that, with the date and a busy ring beside it, crossed
//! the watchdog — and they hid the data they were drawn over, which is what
//! the touch-and-hold peek existed to undo. The time ring (Source.SOURCE_TIME
//! and SOURCE_TIME_OVERLAP) replaces all three: no hand test, no peek, and a
//! date that never has to wait.
module HandStyle {

    //! False: there are no hands, so there is nothing to back. The view never
    //! passes a backing colour, and the per-dot hand test never runs.
    const HANDS = false;

    //! True: the outermost ring tells the time. See Source.SOURCE_TIME.
    const TIME_RING = true;
}
