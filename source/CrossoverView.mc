import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The watch face view. Its only job is choosing the palette for the current
//! power mode; the lattice, the mapping and the colours all live elsewhere.
class CrossoverView extends WatchUi.WatchFace {

    //! Tracks sleep state for devices that predate System.getDisplayMode().
    private var _asleep as Boolean = false;

    //! The complete face lives here rather than in whichever screen Dc Garmin
    //! supplies to a particular callback. Layers are composited by the system
    //! during regular updates and transition animations, so an unchanged frame
    //! can leave these pixels alone without exposing a cleared screen surface.
    const LAYER_COLOR_DEPTH = 16;
    private var _faceDc as Dc? = null;

    //! The two prints, allocated once and refilled every frame. FrameGate copies
    //! the values it needs, so handing it the same buffer every frame is safe.
    private var _fieldPrint as Array<Float> = new [6] as Array<Float>;
    private var _ringPrint as Array<Float> =
        new [StatMap.RINGS * FrameGate.PER_RING] as Array<Float>;

    //! Refilled in place on every accepted update. These used to account for
    //! eight short-lived arrays on an ordinary frame before the gate could even
    //! decide to skip it.
    private var _spans as Array<Array<Float> > = [
        [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]
    ] as Array<Array<Float> >;
    private var _blocks as Array<Number> =
        new [StatMap.RINGS * StatMap.BLOCK_VALUES] as Array<Number>;
    private var _overs as Array<Boolean> =
        new [StatMap.RINGS] as Array<Boolean>;
    private var _markers as Array<Float> =
        new [StatMap.RINGS] as Array<Float>;
    private var _drift as Array<Number> = [0, 0] as Array<Number>;

    function initialize() {
        WatchFace.initialize();
    }

    //! Build the fixed lattice and the one authoritative render surface. The
    //! screen itself is cleared only as the opaque backing behind that layer;
    //! every later pixel mutation happens off-screen in the layer's own Dc.
    function onLayout(dc as Dc) as Void {
        clearLayers();
        var layer = new WatchUi.Layer({
            :locX => 0,
            :locY => 0,
            :width => dc.getWidth(),
            :height => dc.getHeight(),
            :colorDepth => LAYER_COLOR_DEPTH
        });
        _faceDc = layer.getDc();
        addLayer(layer);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        DotGrid.ensureBuilt();
        FrameGate.forget();
        holdHandsAtSystemTime();
    }

    //! The layer survives system overlays and view transitions. Settings reload
    //! at the point they change and invalidate FrameGate there; merely becoming
    //! visible again does not make an unchanged layer stale.
    function onShow() as Void {
        DotGrid.ensureBuilt();
    }

    function onUpdate(dc as Dc) as Void {
        updateForMode(dc, displayMode());
    }

    //! The body of an update, separated so lifecycle tests can drive OFF and
    //! hidden states without depending on the simulator's display controls.
    function updateForMode(dc as Dc, mode as Number) as Void {
        var started = System.getTimer();
        if (!shouldUpdate(mode)) {
            return;
        }
        var lowPower = (mode == System.DISPLAY_MODE_LOW_POWER);
        // Held back in always-on when asked: the field keeps its colour but
        // loses its waterlines, and the data comes back on a wrist raise.
        //
        // The power mode also reaches the sources themselves, which is how a
        // seconds ring goes quiet in always-on: there is one frame a minute
        // there, so a per-second reading could only be stale.
        var hideFills = lowPower &&
                        StatMap.alwaysOnFill == StatMap.ALWAYS_ON_FILL_HIDDEN;
        // Read blocks first. A Body Battery history refresh seeds the current
        // value too, so a face showing both forms makes one sensor-history call
        // on its hourly rebuild rather than asking for current and then history.
        var blocks = _blocks;
        var spans = _spans;
        if (hideFills) {
            StatMap.fillNoBlocks(blocks);
            StatMap.fillNoSpans(spans);
        } else {
            StatMap.fillBlocks(blocks);
            StatMap.fillSpans(spans, !lowPower);
        }
        // Which rings are past a goal they can beat, read from the same power
        // mode the spans were: a lap span without its flag would read as a
        // fill of the same length. Always-on never reports one, so held-back
        // always-on needs nothing extra here.
        var overs = _overs;
        if (hideFills) {
            StatMap.fillNoOvers(overs);
        } else {
            StatMap.fillOvers(overs, !lowPower);
        }
        // Awake-only, for the same reason the hand backing is: the mark is a
        // dozen white dots, which is the most expensive thing per dot the face
        // can draw, in the mode that is measured against the burn-in budget and
        // the mode nobody is reading closely. It comes back on a wrist raise.
        var markers = _markers;
        if (lowPower) {
            StatMap.fillNoMarkers(markers);
        } else {
            StatMap.fillMarkers(markers, spans, overs);
        }
        // The block channel is handed to both the print and the
        // renderer. The renderer must never read the clock for itself: an hour
        // rolling over between the two would leave the gate certain a ring had
        // not moved while the renderer drew a different picture, and the ring
        // would stay wrong until the periodic repair.
        //
        // Held back like the spans rather than like the marks, because it is
        // the ring's data rather than an annotation on it.
        // Backing is awake-only: in always-on it would cost luminance for a
        // detail nobody is looking at.
        var backing = lowPower ? null : backingColour();

        // The date watermark, brought up to date before anything reads it.
        //
        // Here rather than in fieldPrint(), because the glyph cache has to be
        // current before either the gate or renderer reads it. It costs nothing
        // in always-on that it does not cost awake: a struck dot lights fewer
        // pixels than the dot it replaces, so the mode measured against the
        // burn-in budget can only come out lower.
        //
        // Off the mode, nothing is read at all: today() is arithmetic on the
        // epoch second in the common case, but it is still two system calls
        // that a face with the watermark off has no reason to pay.
        var dating = (StatMap.rotation == StatMap.ROTATION_UPRIGHT_DATE);
        var day = 0;
        if (dating) {
            day = DateGlyph.today();
            DateGlyph.ensure(day);
        }

        // What of the authoritative layer needs changing. Most callbacks see
        // the same visual state and leave it untouched; Garmin still composites
        // the complete layer for the callback and for every animation frame.
        var clock = System.getClockTime();
        Drift.fillFor(clock.min, _drift);
        var field = fieldPrint(backing, day, _drift, clock.min, mode);
        var rings = ringPrint(spans, markers, overs, blocks);
        if (!FrameGate.plan(field, rings)) {
            Diagnostics.recordSkip(System.getTimer() - started);
            return;
        }

        // onLayout establishes this on the real watch. The explicit fallback
        // keeps the face functional if a device cannot provide a layer Dc: it
        // draws a complete direct frame on every callback rather than applying
        // unsafe deltas to an unowned screen surface.
        var targetDc = dc;
        var persistent = false;
        var layerDc = _faceDc;
        if (layerDc != null) {
            targetDc = layerDc;
            persistent = true;
        } else {
            FrameGate.everything();
        }

        // Held back, the unfilled tier is the entire image rather than a
        // backdrop to the fills, so it gets its own table — brighter than the
        // ordinary always-on one, and matching the awake field exactly so the
        // background does not shift when the wrist comes up.
        var palette = hideFills
            ? Palette.heldBack
            : (lowPower ? Palette.alwaysOn : Palette.active);
        MatrixRenderer.drawAt(targetDc, spans, markers, overs, blocks, palette,
                              lowPower ? Palette.rampAlwaysOn : Palette.rampActive,
                              backing, FrameGate.dirty, FrameGate.clears, _drift);
        if (persistent) {
            FrameGate.commit(field, rings);
        } else {
            // Do not remember direct-screen pixels: Garmin may clear them
            // before the next callback, which is the failure this layer fixes.
            FrameGate.forget();
        }
        Diagnostics.record(System.getTimer() - started);
    }

    //! What moves every dot at once: the burn-in drift, and the hands.
    //!
    //! Kept apart from the per-ring print because the consequences differ. A
    //! ring whose span moved needs that ring redrawn; a drift step moves the
    //! whole lattice, so there is nothing on screen worth keeping and the
    //! frame starts from black.
    //!
    //! The minute is in here only when the backing is on, because that is the
    //! only time the hands' own position decides which dots are lit — and when
    //! it is on, the hands cross every ring, so a minute is a whole-field
    //! change like the drift.
    //!
    //! So is the day, and it belongs in *this* print rather than a ring's. The
    //! watermark spans all four rings, and a dot that was struck yesterday and
    //! is not today has four stray pixels on screen that only a clear removes —
    //! a partial repaint would draw the cross's other stroke over them and
    //! leave the dot looking normal, which is right, but the dots that went the
    //! other way would keep both strokes. Zero when the watermark is off, so a
    //! face without it never re-prints on a date change.
    //!
    //! Filled into a buffer this view owns rather than returned fresh: it is
    //! built every frame, and FrameGate keeps values rather than the array.
    function fieldPrint(backing as Number?, day as Number,
                        drift as Array<Number>, minute as Number,
                        mode as Number) as Array<Float> {
        var out = _fieldPrint;
        out[0] = drift[0].toFloat();
        out[1] = drift[1].toFloat();
        out[2] = (backing == null) ? -1.0 : backing.toFloat();
        out[3] = (backing == null) ? 0.0 : minute.toFloat();
        out[4] = day.toFloat();
        // Defensive as well as descriptive: if Garmin changes display mode
        // before delivering the matching sleep callback, the palette change is
        // still a whole-field change and cannot be skipped.
        out[5] = mode.toFloat();
        return out;
    }

    //! Everything that can change one ring without touching the others: its
    //! span, its mark, its over flag and its packed blocks — PER_RING values
    //! each, laid out flat.
    //!
    //! The marks have to be in here. The current temperature moves while the
    //! day's low and high sit still, so a print of spans alone would call that
    //! ring unchanged and freeze the mark until the skip cap fired.
    //!
    //! So do the over flags, and for a sharper reason: a ring crossing its goal
    //! goes from a fill of 0.05 to a lap of 0.05, which is the *same span*. The
    //! frame it changes colour on is one the gate would otherwise skip. The
    //! waterline dot happens to move at the same moment and would cover for it
    //! today, but that leaves redrawing correct only for as long as the dot
    //! exists, so the flags are named here in their own right.
    //!
    //! And so do the block words, for the sharpest reason of the three: a
    //! block ring's span is EMPTY on every frame it ever draws, and it carries
    //! no mark and no overflow. Without its three words in here nothing about
    //! that ring ever changes, and the forecast would only appear when the
    //! periodic repair happened to fire.
    //!
    //! Not private, so the redraw tests can call it. What either print leaves
    //! out is invisible from anywhere else: the ring simply stops updating,
    //! which looks like nothing at all going wrong.
    function ringPrint(spans as Array<Array<Float> >,
                       markers as Array<Float>,
                       overs as Array<Boolean>,
                       blocks as Array<Number>) as Array<Float> {
        var out = _ringPrint;
        for (var i = 0; i < StatMap.RINGS; i++) {
            var at = i * FrameGate.PER_RING;
            var packed = i * StatMap.BLOCK_VALUES;
            out[at] = spans[i][0];
            out[at + 1] = spans[i][1];
            out[at + 2] = markers[i];
            out[at + 3] = overs[i] ? 1.0 : 0.0;
            // All three words are inside a Float's exact integer range by
            // construction — 0xFFFFFF, 0xFFFFFF and 0xFFF — so this round trip
            // loses nothing, and the gate's element-wise compare sees every bit.
            out[at + 4] = blocks[packed].toFloat();
            out[at + 5] = blocks[packed + 1].toFloat();
            out[at + 6] = blocks[packed + 2].toFloat();
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
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _asleep = false;
        holdHandsAtSystemTime();
        // High-power mode schedules its own immediate onUpdate. Requesting one
        // here creates an extra synchronous callback just as a button press may
        // be trying to leave the face; Garmin's Analog sample likewise only
        // requests the enter-sleep repaint, not the wake repaint.
    }

    //! Display state for the frame about to be drawn.
    private function displayMode() as Number {
        if (System has :getDisplayMode) {
            return System.getDisplayMode();
        }
        // Pre-5.0.0 devices have no OFF state to distinguish here.
        return _asleep ? System.DISPLAY_MODE_LOW_POWER
                       : System.DISPLAY_MODE_HIGH_POWER;
    }

    //! Display-off callbacks have no visible consumer. All other callbacks are
    //! accepted even during transitions: the layer makes them cheap and safe,
    //! so no lifecycle timing or debounce is needed.
    function shouldUpdate(mode as Number) as Boolean {
        return mode != System.DISPLAY_MODE_OFF;
    }
}
