import Toybox.Lang;

//! Every number that changes when the face moves to a different screen.
//!
//! This file has one copy per screen size, and `monkey.jungle` puts exactly one
//! of them on each device's source path. Nothing here is read at run time:
//! they are `const`, so `DotGrid` folds them at compile time and the render
//! loop keeps the rule the whole face is built around — nothing computed that
//! `DotGrid.build()` could compute once.
//!
//! **Epix 2 Pro 51mm: 454 x 454.**
//! The largest screen the face runs on, and the one with no hands of its own
//! - so these hand numbers are what the field draws rather than what sits
//! over it. Scaled from the 390 lattice by 222/190.
module Lattice {

    //! The display, square, from the device's own simulator.json.
    const SCREEN as Number = 454;

    //! A cross lights 9 of the 25 pixels a filled square of the same extent
    //! would, so the same luminance buys a much finer lattice.
    //!
    //! PITCH and DOT are shared by every device rather than scaled with the
    //! screen, and that is deliberate twice over. `Drift`'s -2/+3 offsets are
    //! exactly DOT apart and consume exactly the slack a 10px pitch leaves, so
    //! moving either breaks the burn-in cycle. And holding them fixed is what
    //! makes the luminance budget scale-invariant: dot density is 1/PITCH^2
    //! whatever the radius, so every theme keeps its measured figure.
    const PITCH as Number = 10;
    const DOT as Number = 5;

    //! Both grid dimensions are even, so no dot ever sits on an axis and every
    //! dot belongs to exactly one quadrant. DotGrid.build() leans on that.
    //!
    //! COLS is the largest even count that keeps the outermost dot on screen
    //! once the drift has pushed it: offsetAt(COLS-1) + Drift.MAX_OFFSET +
    //! DOT/2 must stay inside SCREEN/2 - 1. Here that is 205 + 3 + 2 = 210
    //! against 226.
    const COLS as Number = 42;
    const ROWS as Number = 42;

    //! The largest lattice that fits the drawn-hand watchdog. A native 222px
    //! radius with 1512 dots trips; this 210px radius is the measured safe
    //! boundary while retaining the same 10px grain as the other watches.
    const RADIUS as Number = 210;

    //! Radius punched out of the middle. On the Crossover this is what the
    //! physical hand pivot covers; on a drawn-hands device it is where the two
    //! hands cross, and is kept for the same reason — a dot there is never
    //! legible.
    const HUB as Number = 23;

    //! What DotGrid.measureRows() counts from the values above. Asserted, not
    //! trusted: it is a claim about this lattice that the suite re-derives.
    const EXPECTED_DOTS as Number = 1380;

    // --- the hands -----------------------------------------------------------
    //
    // Read off Devices/instinctcrossoveramoled/simulator.json: both hands are
    // 28px wide with a 46px counterweight behind the pivot, the hour hand
    // reaches 131px and the minute hand 176px. A device with no hands of its
    // own scales these by its radius, so the drawn hands sit in the field the
    // same way the brass ones sit over the glass.

    const HAND_HALF_WIDTH as Number = 15;
    const HAND_COUNTERWEIGHT as Number = 51;
    const HOUR_REACH as Number = 145;
    const MINUTE_REACH as Number = 195;
}
