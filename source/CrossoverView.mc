import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The watch face view. Its only job is deciding *which* renderer runs;
//! all drawing lives in ActiveRenderer / AlwaysOnRenderer.
class CrossoverView extends WatchUi.WatchFace {

    //! Tracks sleep state for devices that predate System.getDisplayMode().
    private var _asleep as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setClip(0, 0, dc.getWidth(), dc.getHeight());
        if (isLowPower()) {
            AlwaysOnRenderer.draw(dc);
        } else {
            ActiveRenderer.draw(dc);
        }
    }

    function onEnterSleep() as Void {
        _asleep = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _asleep = false;
        WatchUi.requestUpdate();
    }

    //! True when the frame we are about to draw is subject to AMOLED
    //! burn-in protection (always-on mode).
    private function isLowPower() as Boolean {
        if (System has :getDisplayMode) {
            return System.getDisplayMode() == System.DISPLAY_MODE_LOW_POWER;
        }
        // Pre-5.0.0 devices: burn-in rules apply whenever a protected
        // screen is asleep.
        return System.getDeviceSettings().requiresBurnInProtection && _asleep;
    }
}
