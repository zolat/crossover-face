import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! Always-on frame. Must stay inside the AMOLED burn-in budget:
//! under 10% of screen luminance, and no pixel lit for more than 3 minutes.
//! Hence: black field, one thin dim string, and a position that walks
//! around the centre so no pixel stays on.
module AlwaysOnRenderer {

    //! Pixels of drift per step, and how many steps before the pattern repeats.
    const DRIFT_STEP = 8;
    const DRIFT_STEPS = 5;

    function draw(dc as Dc) as Void {
        dc.setColor(Palette.BACKGROUND, Palette.BACKGROUND);
        dc.clear();

        var minute = System.getClockTime().min;
        var offsetX = ((minute % DRIFT_STEPS) - 2) * DRIFT_STEP;
        var offsetY = (((minute / DRIFT_STEPS) % DRIFT_STEPS) - 2) * DRIFT_STEP;

        dc.setColor(Palette.ALWAYS_ON, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2 + offsetX,
            dc.getHeight() / 2 + offsetY,
            Graphics.FONT_NUMBER_MILD,
            WatchData.timeText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
