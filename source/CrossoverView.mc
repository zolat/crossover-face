import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The watch face view. Its only job is choosing the palette for the current
//! power mode; the lattice, the mapping and the colours all live elsewhere.
class CrossoverView extends WatchUi.WatchFace {

    //! Tracks sleep state for devices that predate System.getDisplayMode().
    private var _asleep as Boolean = false;

    //! The wake reveal: the date's outline grows in over REVEAL_STEPS ticks of
    //! a high-power timer, about 0.8s. A watch face gets timers only while
    //! awake, which is the only time the outline is drawn anyway. Resting at
    //! REVEAL_STEPS means "fully drawn", so a frame no reveal led up to — a
    //! settings change, say — shows the whole outline.
    const REVEAL_STEPS = 12;
    const REVEAL_TICK_MS = 70;
    private var _revealStep as Number = REVEAL_STEPS;
    //! The step last inked into the frame buffer, so a frame the gate skips
    //! re-inks only when the reveal has actually moved on.
    private var _inkedStep as Number = -1;
    private var _revealTimer as Timer.Timer? = null;

    //! The complete face lives here rather than in whichever screen Dc Garmin
    //! supplies to a particular callback. Every visible onUpdate explicitly
    //! blits this buffer to that Dc, so a firmware-cleared transition surface
    //! receives complete pixels without rerunning the dot renderer.
    const BUFFER_COLOR_DEPTH = 16;
    private var _frameBuffer as Graphics.BufferedBitmap? = null;
    private var _frameDc as Dc? = null;

    //! Observable presentation count for lifecycle tests. A duplicate callback
    //! must present the cached frame even though it does not mutate it.
    var presented as Number = 0;

    //! The two prints, allocated once and refilled every frame. FrameGate copies
    //! the values it needs, so handing it the same buffer every frame is safe.
    private var _fieldPrint as Array<Float> = new [6] as Array<Float>;
    private var _ringPrint as Array<Float> =
        new [StatMap.RINGS * FrameGate.PER_RING] as Array<Float>;

    //! Refilled in place on every accepted update. These used to account for
    //! eight short-lived arrays on an ordinary frame before the gate could even
    //! decide to skip it.
    private var _spans as Array<Array<Float> > =
        new [StatMap.RINGS] as Array<Array<Float> >;
    private var _blocks as Array<Number> =
        new [StatMap.RINGS * StatMap.BLOCK_VALUES] as Array<Number>;
    private var _overs as Array<Boolean> =
        new [StatMap.RINGS] as Array<Boolean>;
    private var _markers as Array<Float> =
        new [StatMap.RINGS] as Array<Float>;
    private var _suns as Array<Float> =
        new [StatMap.RINGS * Source.SUN_VALUES] as Array<Float>;
    private var _drift as Array<Number> = [0, 0] as Array<Number>;

    function initialize() {
        WatchFace.initialize();
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            _spans[ring] = [0.0, 0.0] as Array<Float>;
        }
    }

    //! Build the fixed lattice and one authoritative off-screen frame. Holding
    //! the BufferedBitmap object (not only its reference) pins its contents in
    //! Garmin's graphics pool; a purged dynamic buffer cannot be restored from
    //! the executable.
    function onLayout(dc as Dc) as Void {
        _frameBuffer = null;
        _frameDc = null;
        try {
            var resource = Graphics.createBufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight(),
                :colorDepth => BUFFER_COLOR_DEPTH
            }).get();
            if (resource instanceof Graphics.BufferedBitmap) {
                _frameBuffer = resource;
                _frameDc = resource.getDc();
            }
        } catch (ex instanceof Graphics.OutOfGraphicsMemoryException) {
            // updateForMode falls back to a complete direct redraw on every
            // callback. Slower, but never blank or dependent on stale pixels.
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        DotGrid.ensureBuilt();
        FrameGate.forget();
        holdHandsAtSystemTime();
    }

    //! The buffer survives system overlays and view transitions. Settings
    //! reload at the point they change and invalidate FrameGate there; merely
    //! becoming visible again does not make its pixels stale.
    function onShow() as Void {
        DotGrid.ensureBuilt();
        startReveal();
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
        // The power mode does not reach the mark; only holding the fills back
        // does. See fillMarksFor().
        var markers = _markers;
        fillMarksFor(hideFills, markers, spans, overs);
        // The sun dots follow the mark: both modes, held back with the fills.
        var suns = _suns;
        if (hideFills) {
            StatMap.fillNoSuns(suns);
        } else {
            StatMap.fillSuns(suns);
        }
        // The block channel is handed to both the print and the
        // renderer. The renderer must never read the clock for itself: an hour
        // rolling over between the two would leave the gate certain a ring had
        // not moved while the renderer drew a different picture, and the ring
        // would stay wrong until the periodic repair.
        //
        // Held back with the spans and the marks: all three are the ring's
        // data, and that mode is the one that carries none.
        // Backing is awake-only: in always-on it would cost luminance for a
        // detail nobody is looking at, and the brass keeps telling the time
        // whether the dots behind it are lit or not.
        var backing = lowPower ? null : backingColour();

        // The date, brought up to date before anything reads it.
        //
        // Here rather than in fieldPrint(), because the numeral's cache has to
        // be current before either the gate or renderer reads it. Awake only:
        // see showsDate(). And the day is in the field print only while it is
        // shown, which is what makes falling asleep clear the outline away —
        // the slot drops to 0, the print moves, and the always-on frame is
        // drawn from black. `fallingAsleepClearsTheOutline` holds that.
        //
        // Off, nothing is read at all: today() is arithmetic on the epoch
        // second in the common case, but it is still two system calls that a
        // frame without the date has no reason to pay.
        var dating = showsDate(lowPower);
        DateGlyph.active = dating;
        var day = 0;
        if (dating) {
            day = DateGlyph.today();
            DateGlyph.ensure(day);
        }

        // What of the authoritative frame needs changing. Most callbacks see
        // the same visual state and skip the renderer, but still present the
        // complete cached bitmap below.
        var clock = System.getClockTime();
        Drift.fillFor(clock.min, _drift);
        var field = fieldPrint(backing, day, _drift, clock.min, mode);
        var rings = ringPrint(spans, markers, overs, blocks, suns);
        if (!FrameGate.plan(field, rings)) {
            // The buffer already holds the outline as far as it was last
            // inked; only a reveal that has moved on needs another pass.
            var frameDc = _frameDc;
            if (dating && frameDc != null && _inkedStep != _revealStep) {
                inkOutline(frameDc, false);
            }
            present(dc);
            Diagnostics.recordSkip(System.getTimer() - started);
            return;
        }

        // onLayout establishes this on the real watch. The explicit fallback
        // keeps the face functional if a device cannot provide a frame buffer: it
        // draws a complete direct frame on every callback rather than applying
        // unsafe deltas to an unowned screen surface.
        var targetDc = dc;
        var persistent = false;
        var frameDc = _frameDc;
        if (frameDc != null && _frameBuffer != null) {
            targetDc = frameDc;
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
        MatrixRenderer.drawAt(targetDc, spans, markers, suns, overs, blocks,
                              palette,
                              lowPower ? Palette.rampAlwaysOn : Palette.rampActive,
                              backing, FrameGate.dirty, FrameGate.clears, _drift);
        // Cleared, or drawn straight to a screen surface that holds nothing
        // of the last frame: either way no segment is standing.
        if (dating) {
            inkOutline(targetDc, FrameGate.clears || !persistent);
        }
        if (persistent) {
            FrameGate.commit(field, rings);
            present(dc);
        } else {
            // Do not remember direct-screen pixels: Garmin may clear them
            // before the next callback, which is the failure this buffer fixes.
            FrameGate.forget();
        }
        Diagnostics.record(System.getTimer() - started);
    }

    //! Copy the complete authoritative frame to the callback's actual screen
    //! surface. This runs even when the fingerprint is unchanged; it is the
    //! cheap, explicit contract transition callbacks were missing.
    private function present(dc as Dc) as Void {
        var frame = _frameBuffer;
        if (frame == null) {
            return;
        }
        dc.drawBitmap(0, 0, frame);
        presented++;
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
    //! And the sun positions, for the mark's reason: they move while the
    //! band and the mark sit still, and a print without them would freeze a
    //! sun dot on yesterday's minute — or never draw it, if the first frame
    //! came before the complications had an answer.
    //!
    //! Not private, so the redraw tests can call it. What either print leaves
    //! out is invisible from anywhere else: the ring simply stops updating,
    //! which looks like nothing at all going wrong.
    function ringPrint(spans as Array<Array<Float> >,
                       markers as Array<Float>,
                       overs as Array<Boolean>,
                       blocks as Array<Number>,
                       suns as Array<Float>) as Array<Float> {
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
            out[at + 7] = suns[i * Source.SUN_VALUES];
            out[at + 8] = suns[i * Source.SUN_VALUES + 1];
        }
        return out;
    }

    //! The colour to place under the hands, or null when the option is off —
    //! and always null on a watch with no hands, whatever the setting stores.
    function backingColour() as Number? {
        if (!HandStyle.HANDS) {
            return null;
        }
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
    //!
    //! Nothing to ask on a watch with no hands. The `has` guard below would
    //! no-op anyway, but saying it outright keeps the two styles readable side
    //! by side.
    private function holdHandsAtSystemTime() as Void {
        if (!HandStyle.HANDS || StatMap.backing == StatMap.BACKING_OFF) {
            return;
        }
        if (self has :setClockHandPosition &&
            WatchUi has :ANALOG_CLOCK_STATE_SYSTEM_TIME) {
            setClockHandPosition(
                {:clockState => WatchUi.ANALOG_CLOCK_STATE_SYSTEM_TIME});
        }
    }

    //! Which position each ring marks this frame, into `out`.
    //!
    //! **It takes no power mode, and that is the decision.** The mark used to
    //! be awake only, alongside the hand backing, on the reasoning that a solid
    //! dot is the most luminous thing per dot the face can draw. Priced, that
    //! does not hold: it is one dot per ring, so even four rings on temperature
    //! move the always-on field by well under a tenth of a point against about
    //! four of headroom, and the drift carries it a whole DOT per phase like
    //! every other lit dot. `theAlwaysOnMarkFitsTheBudget` measures it on every
    //! theme. What it buys is the reading: without it a day of 11 to 22 is the
    //! same picture at dawn and at noon, in the mode the face spends nearly all
    //! of its time in.
    //!
    //! The waterline on an over-goal ring stays awake only with no word here:
    //! over-ness is awake-only at its source, so always-on hands in overs that
    //! are all false and the temperature is the only thing left to mark.
    //!
    //! Held back with the fills, because the mark is the ring's data and that
    //! mode exists to carry none.
    function fillMarksFor(hideFills as Boolean, out as Array<Float>,
                          spans as Array<Array<Float> >,
                          overs as Array<Boolean>) as Void {
        if (hideFills) {
            StatMap.fillNoMarkers(out);
        } else {
            StatMap.fillMarkers(out, spans, overs);
        }
    }

    //! Whether this frame carries the date.
    //!
    //! **Never in always-on.** A line, unlike a cross, does not escape itself
    //! when the burn-in drift moves the field by one DOT, so an always-on
    //! outline would hold some pixels lit through two of the four drift phases
    //! against one for every dot pixel. It also looks better: the field rests
    //! plain, and waking connects the dots.
    function showsDate(lowPower as Boolean) as Boolean {
        return StatMap.date == StatMap.DATE_ON && !lowPower;
    }

    //! Ink the outline into `target` as far as the reveal has got. `cleared`
    //! when `target` was just blacked, so nothing of the outline is standing.
    private function inkOutline(target as Dc, cleared as Boolean) as Void {
        DateGlyph.drawContour(target, _drift,
                              _revealStep.toFloat() / REVEAL_STEPS, cleared);
        _inkedStep = _revealStep;
    }

    //! Begin drawing the outline in from nothing.
    //!
    //! The day's dots and outline are worked out here, in a callback with its
    //! own watchdog budget, so the frame that follows pays only for drawing:
    //! traced inside onUpdate, on top of the full redraw a new day is, the
    //! outline tripped the watchdog in the simulator.
    private function startReveal() as Void {
        // The awake decision, made before there is a frame to make it for.
        if (!showsDate(false)) {
            stopReveal();
            return;
        }
        DateGlyph.ensure(DateGlyph.today());
        DateGlyph.ensureTraced();
        // **A watch face may only use a timer while it is awake**, and the
        // watch calls onShow in low power too — returning from a glance or a
        // notification after the screen has dimmed. Starting one there is not
        // an exception the face can catch: the watch logged "Symbol 'start'
        // not available to 'Watch Face'" and killed the face, three times in a
        // morning. The simulator never shows a face in low power, so nothing
        // short of the watch's own CIQ_LOG caught it. Asleep, the outline is
        // traced and left for the wake to draw in; always-on draws none.
        if (!canAnimate()) {
            stopReveal();
            return;
        }
        _revealStep = 0;
        var timer = _revealTimer;
        if (timer == null) {
            timer = new Timer.Timer();
            _revealTimer = timer;
        }
        timer.stop();
        timer.start(method(:onRevealTick), REVEAL_TICK_MS, true);
    }

    //! Awake by both accounts: no sleep since the last wake, and a display in
    //! high power. Either alone has been wrong on a lifecycle edge before.
    function canAnimate() as Boolean {
        return !_asleep && displayMode() == System.DISPLAY_MODE_HIGH_POWER;
    }

    //! Stop the reveal where it is and let the outline rest fully drawn.
    private function stopReveal() as Void {
        var timer = _revealTimer;
        if (timer != null) {
            timer.stop();
        }
        _revealStep = REVEAL_STEPS;
    }

    function onRevealTick() as Void {
        _revealStep++;
        if (_revealStep >= REVEAL_STEPS) {
            stopReveal();
        }
        WatchUi.requestUpdate();
    }

    //! How far the reveal has got, 0 to REVEAL_STEPS. For the tests.
    function revealStep() as Number {
        return _revealStep;
    }

    function onHide() as Void {
        stopReveal();
    }

    function onEnterSleep() as Void {
        _asleep = true;
        stopReveal();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _asleep = false;
        holdHandsAtSystemTime();
        startReveal();
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
    //! accepted even during transitions: the cached blit makes them cheap and safe,
    //! so no lifecycle timing or debounce is needed.
    function shouldUpdate(mode as Number) as Boolean {
        return mode != System.DISPLAY_MODE_OFF;
    }
}
