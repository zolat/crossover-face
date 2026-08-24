import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The watch face view. Its only job is choosing the palette for the current
//! power mode; the lattice, the mapping and the colours all live elsewhere.
class CrossoverView extends WatchUi.WatchFace {

    //! Tracks sleep state for devices that predate System.getDisplayMode().
    private var _asleep as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        Palette.build();
    }

    function onUpdate(dc as Dc) as Void {
        var palette = isLowPower() ? Palette.alwaysOn : Palette.active;
        MatrixRenderer.draw(dc, WatchData.normalised(), palette);
    }

    function onEnterSleep() as Void {
        _asleep = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _asleep = false;
        WatchUi.requestUpdate();
    }

    //! True when the frame about to be drawn is subject to AMOLED burn-in
    //! protection, i.e. always-on mode.
    private function isLowPower() as Boolean {
        if (System has :getDisplayMode) {
            return System.getDisplayMode() == System.DISPLAY_MODE_LOW_POWER;
        }
        // Pre-5.0.0 devices: the rules apply whenever a protected screen sleeps.
        return System.getDeviceSettings().requiresBurnInProtection && _asleep;
    }
}
