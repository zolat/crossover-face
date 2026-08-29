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
        FrameGate.forget();
        holdHandsAtSystemTime();
    }

    //! Coming back from the settings menu, which pops rather than re-laying
    //! out. Rebuilding the cache here keeps it off the first frame back — the
    //! menu's own Config.reload() only marks it stale — and the gate must
    //! forget a frame it can no longer vouch for.
    function onShow() as Void {
        Config.reload();
        DotGrid.ensureBuilt();
        FrameGate.forget();
    }

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        var lowPower = isLowPower();
        // Held back in always-on when asked: the field keeps its colour but
        // loses its waterlines, and the data comes back on a wrist raise.
        //
        // The power mode also reaches the sources themselves, which is how a
        // seconds ring goes quiet in always-on: there is one frame a minute
        // there, so a per-second reading could only be stale.
        var hideFills = lowPower &&
                        StatMap.alwaysOnFill == StatMap.ALWAYS_ON_FILL_HIDDEN;
        var spans = hideFills ? StatMap.noSpans() : StatMap.spans(!lowPower);
        // Awake-only, for the same reason the hand backing is: the mark is a
        // dozen white dots, which is the most expensive thing per dot the face
        // can draw, in the mode that is measured against the burn-in budget and
        // the mode nobody is reading closely. It comes back on a wrist raise.
        var markers = lowPower ? StatMap.noMarkers() : StatMap.markers();
        // Backing is awake-only: in always-on it would cost luminance for a
        // detail nobody is looking at.
        var backing = lowPower ? null : backingColour();

        // Awake, this frame is almost always identical to the last one, and
        // redrawing ~1100 dots to reproduce it is the largest avoidable cost
        // the face has. Always-on is never skipped: a frame comes once a
        // minute there, so there is nothing to save and its compositing is
        // the least predictable.
        if (!lowPower &&
            !FrameGate.shouldDraw(fingerprint(spans, markers, backing))) {
            Diagnostics.recordSkip();
            return;
        }

        // Held back, the unfilled tier is the entire image rather than a
        // backdrop to the fills, so it gets its own table — brighter than the
        // ordinary always-on one, and matching the awake field exactly so the
        // background does not shift when the wrist comes up.
        var palette = hideFills
            ? Palette.heldBack
            : (lowPower ? Palette.alwaysOn : Palette.active);
        MatrixRenderer.draw(dc, spans, markers, palette,
                            lowPower ? Palette.rampAlwaysOn : Palette.rampActive,
                            backing);
        Diagnostics.record(System.getTimer() - started);
    }

    //! Everything that can change what the face looks like: the burn-in drift,
    //! whether the hands are being backed, and every ring's span and mark. The
    //! minute is in there only when the backing is on, because that is the only
    //! time the hands' own position decides which dots are lit.
    //!
    //! The marks have to be in here. The current temperature moves while the
    //! day's low and high sit still, so a fingerprint of spans alone would call
    //! that frame identical and freeze the mark until the skip cap fired.
    //! Not private so markMovesForceARedraw can call it. What this function
    //! leaves out is invisible from anywhere else: the face simply stops
    //! updating, which looks like nothing at all going wrong.
    function fingerprint(spans as Array<Array<Float> >,
                         markers as Array<Float>,
                         backing as Number?) as Array<Float> {
        var drift = Drift.current();
        var out = new [4 + (StatMap.RINGS * 3)] as Array<Float>;
        out[0] = drift[0].toFloat();
        out[1] = drift[1].toFloat();
        out[2] = (backing == null) ? -1.0 : backing.toFloat();
        out[3] = (backing == null) ? 0.0
                                   : System.getClockTime().min.toFloat();
        for (var i = 0; i < StatMap.RINGS; i++) {
            out[4 + (i * 3)] = spans[i][0];
            out[5 + (i * 3)] = spans[i][1];
            out[6 + (i * 3)] = markers[i];
        }
        return out;
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
        FrameGate.forget();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _asleep = false;
        holdHandsAtSystemTime();
        FrameGate.forget();
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
