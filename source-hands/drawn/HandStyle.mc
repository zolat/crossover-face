import Toybox.Lang;

//! What the hands are, on a watch that has none.
//!
//! One copy of this module per hand style, put on a device's source path by
//! `monkey.jungle`. It answers three questions the rest of the face asks and
//! never decides for itself: are the hands ours to draw, do they belong in
//! always-on, and what colour is a dot one of them covers.
//!
//! **The Epix 2 family: the face carries the time itself.**
//!
//! It carries it in dots. `HandBacking.handAt()` already answers "which hand
//! covers this dot?" once per dot inside the paint loop, and on a watch with no
//! hands, lighting those dots *is* the hand. That is the whole mechanism —
//! there is no polygon, no new primitive, and not one line of `FrameGate`
//! changes. Hand motion is already modelled as a whole-field invalidation,
//! because the minute is in the field print whenever the hands are on, so the
//! face redraws once a minute exactly as it does on the Crossover.
//!
//! Two things fall out of that and are worth stating, because both look like
//! oversights:
//!
//!   - a drawn hand costs almost no luminance. It *recolours* dots that were
//!     already lit at the unfilled tier rather than adding lit area, which is
//!     about +0.6% of screen against the 10% always-on budget. Solid polygons
//!     of the same geometry measure 5.03% at 390, on top of the worst theme's
//!     5.73% field — over the cliff on their own;
//!   - there is still no second hand. Drawing one would put seconds in the
//!     field print and clear the screen every frame, taking the skip rate from
//!     ~82% to nothing. The seconds ring is the face's answer to that and
//!     predates this device.
module HandStyle {

    //! True: these hands are the face's to draw. The watch has no hands to ask
    //! to hold at system time, so the view does not.
    const DRAWN = true;

    //! **The hands are the time, so they stay lit in always-on.** This is the
    //! one place the Epix inverts a Crossover decision rather than reusing it:
    //! there, backing is a detail suppressed to save light; here it is the only
    //! thing on the glass saying what o'clock it is.
    const ALWAYS_ON = true;

    //! True: the outermost ring tells the time. See Source.SOURCE_TIME.
    const TIME_RING = true;

    //! Colour for each slot `HandBacking.handAt()` can return: nothing, the
    //! hour hand, the minute hand.
    //!
    //! Light means the Crossover's own two hands — white hour, grey minute —
    //! so the hands the field draws are the hands the sister watch wears, and
    //! every theme's measurements carry over untouched.
    //!
    //! Dark is a silhouette rather than a pair, and takes one colour for both.
    //! There is nothing to distinguish: a hand cut out of the field reads by
    //! its shape, and two different darks would only muddy where they cross.
    function coloursFor(backing as Number) as Array<Number> {
        if (backing == Palette.BACKING_WHITE) {
            return [0, Palette.HAND_HOUR, Palette.HAND_MINUTE] as Array<Number>;
        }
        return [0, backing, backing] as Array<Number>;
    }
}
