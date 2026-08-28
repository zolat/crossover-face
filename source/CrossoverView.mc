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

    //! The dot cache is built here rather than in the app's onStart, which
    //! has a far tighter watchdog budget and tripped on it. onLayout runs once,
    //! before the first frame, so the face is complete the first time it draws.
    function onLayout(dc as Dc) as Void {
        Config.reload();
        DotGrid.ensureBuilt();
        holdHandsAtSystemTime();
    }

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        var lowPower = isLowPower();
        var palette = lowPower ? Palette.alwaysOn : Palette.active;
        // Backing is awake-only: in always-on it would cost luminance for a
        // detail nobody is looking at.
        MatrixRenderer.draw(dc, StatMap.spans(), palette,
                            lowPower ? Palette.rampAlwaysOn : Palette.rampActive,
                            lowPower ? null : backingColour());
        Diagnostics.record(System.getTimer() - started);
    }

    //! The colour to place under the hands, or null when the option is off.
    private function backingColour() as Number? {
        if (StatMap.backing == StatMap.BACKING_WHITE) {
            return Palette.BACKING_WHITE;
        }
        if (StatMap.backing == StatMap.BACKING_DARK) {
            return Palette.BACKING_DARK;
        }
        return null;
    }

    //! Backing is only correct while the hands show the time, so ask for that
    //! explicitly rather than hoping the watch has not parked them elsewhere.
    private function holdHandsAtSystemTime() as Void {
        if (StatMap.backing == StatMap.BACKING_OFF) {
            return;
        }
        if (self has :setClockHandPosition &&
            WatchUi has :ANALOG_CLOCK_STATE_SYSTEM_TIME) {
            setClockHandPosition(
                {:clockState => WatchUi.ANALOG_CLOCK_STATE_SYSTEM_TIME});
        }
    }

    function onEnterSleep() as Void {
        _asleep = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _asleep = false;
        holdHandsAtSystemTime();
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
