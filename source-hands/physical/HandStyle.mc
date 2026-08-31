import Toybox.Lang;

//! What the hands are, on a watch that has its own.
//!
//! One copy of this module per hand style, put on a device's source path by
//! `monkey.jungle`. It answers three questions the rest of the face asks and
//! never decides for itself: are the hands ours to draw, do they belong in
//! always-on, and what colour is a dot one of them covers.
//!
//! **Instinct Crossover AMOLED: two brass hands stand over the glass.**
//! The face draws no hands at all. `HandBacking` exists only to give the dots
//! *underneath* them a contrasting colour, so what you see is the lit field
//! emerging along a hand's edge.
module HandStyle {

    //! False when the hardware carries the hands. The view asks the watch to
    //! hold them at system time, since backing is only correct while they show
    //! it, and nothing else about the time is the face's business.
    const DRAWN = false;

    //! Backing is awake-only here. In always-on it would cost luminance for a
    //! detail nobody is looking at, and the hands keep telling the time
    //! whether the face lights the dots behind them or not.
    const ALWAYS_ON = false;

    //! Colour for each slot `HandBacking.handAt()` can return: nothing, the
    //! hour hand, the minute hand.
    //!
    //! Both hands take the one backing colour, because the hands themselves
    //! are what distinguishes them — the dots only have to sit behind. So this
    //! is exactly the single `backingColour` the renderer used before the slot
    //! existed, in a shape the drawn style can also fill.
    function coloursFor(backing as Number) as Array<Number> {
        return [0, backing, backing] as Array<Number>;
    }
}
