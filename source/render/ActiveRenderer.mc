import Toybox.Graphics;
import Toybox.Lang;

//! Full-brightness face, drawn while the watch is awake.
module ActiveRenderer {

    function draw(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        dc.setColor(Palette.BACKGROUND, Palette.BACKGROUND);
        dc.clear();

        // Date, above the hand pivot.
        dc.setColor(Palette.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 120, Graphics.FONT_SMALL, WatchData.dateText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Time, centred.
        dc.setColor(Palette.PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_NUMBER_HOT, WatchData.timeText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawStatRow(dc, cx, cy + 120);
    }

    //! Heart rate | battery | steps, below the hand pivot.
    function drawStatRow(dc as Dc, cx as Number, y as Number) as Void {
        var hr = WatchData.heartRate();
        var steps = WatchData.steps();

        dc.setColor(Palette.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 105, y, Graphics.FONT_TINY, hr == null ? "--" : hr.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 105, y, Graphics.FONT_TINY, steps == null ? "--" : steps.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Palette.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_TINY, WatchData.batteryPercent().format("%d") + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
