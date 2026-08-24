import Toybox.Graphics;
import Toybox.Lang;

//! Colours shared by both renderers. AMOLED rule of thumb: black is free,
//! everything else costs battery and counts against the burn-in budget.
module Palette {
    const BACKGROUND = Graphics.COLOR_BLACK;
    const PRIMARY = 0xFFFFFF;
    const ACCENT = 0xFF6600;
    const MUTED = 0x777777;

    //! Deliberately dim: always-on frames must stay under 10% of the
    //! screen's luminance or the system blanks the display.
    const ALWAYS_ON = 0x555555;
}
