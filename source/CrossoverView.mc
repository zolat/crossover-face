import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The watch face view. Its only job is choosing the palette for the current
//! power mode; the lattice, the mapping and the colours all live elsewhere.
class CrossoverView extends WatchUi.WatchFace {

    //! Tracks sleep state for devices that predate System.getDisplayMode().
    private var _asleep as Boolean = false;

    //! True while a drawn-hands watch is showing its unobstructed data field.
    //! Transient by design: sleep restores the time without touching settings.
    private var _peeking as Boolean = false;

    //! The two prints, allocated once and refilled every frame. FrameGate copies
    //! the values it needs, so handing it the same buffer every frame is safe.
    private var _fieldPrint as Array<Float> = new [5] as Array<Float>;
    private var _ringPrint as Array<Float> =
        new [StatMap.RINGS * FrameGate.PER_RING] as Array<Float>;

    function initialize() {
        WatchFace.initialize();
    }

    //! The dot cache is built here rather than in the app's onStart, which
    //! has a far tighter watchdog budget and tripped on it. onLayout runs once,
    //! before the first frame, so the face is complete the first time it draws.
    function onLayout(dc as Dc) as Void {
        _peeking = false;
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
        _peeking = false;
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
        // Which rings are past a goal they can beat, read from the same power
        // mode the spans were: a lap span without its flag would read as a
        // fill of the same length. Always-on never reports one, so held-back
        // always-on needs nothing extra here.
        var overs = StatMap.overs(!lowPower);
        // Awake-only, for the same reason the hand backing is: the mark is a
        // dozen white dots, which is the most expensive thing per dot the face
        // can draw, in the mode that is measured against the burn-in budget and
        // the mode nobody is reading closely. It comes back on a wrist raise.
        var markers = lowPower ? StatMap.noMarkers()
                               : StatMap.markers(spans, overs);
        // The block channel, read once and handed to both the print and the
        // renderer. The renderer must never read the clock for itself: an hour
        // rolling over between the two would leave the gate certain a ring had
        // not moved while the renderer drew a different picture, and the ring
        // would stay wrong until the periodic repair.
        //
        // Held back like the spans rather than like the marks, because it is
        // the ring's data rather than an annotation on it.
        var blocks = hideFills ? StatMap.noBlocks() : StatMap.blocks();
        // Backing is awake-only where the hands are real: in always-on it would
        // cost luminance for a detail nobody is looking at, and the brass keeps
        // telling the time whether the dots behind it are lit or not.
        //
        // **Where the face draws the hands, that inverts.** They are the only
        // thing on the glass saying what o'clock it is, so they stay through
        // always-on and through the held-back mode both. It is close to free:
        // a hand recolours dots that were already lit at the unfilled tier
        // rather than adding lit area, which is why HandStyle can simply say so
        // rather than trading it against the budget.
        var backing = (_peeking || (lowPower && !HandStyle.ALWAYS_ON))
            ? null : backingColour();

        // The date watermark, brought up to date before anything reads it.
        //
        // Here rather than in fieldPrint(), because always-on never calls that
        // — and the watermark stays on in always-on. It costs nothing there
        // that it does not cost awake: a struck dot lights fewer pixels than
        // the dot it replaces, so the mode measured against the burn-in budget
        // can only come out lower.
        //
        // Off the mode, nothing is read at all: today() is arithmetic on the
        // epoch second in the common case, but it is still two system calls
        // that a face with the watermark off has no reason to pay.
        var dating = showsDate(backing);
        var day = 0;
        if (dating) {
            day = DateGlyph.today();
            DateGlyph.ensure(day);
        }

        // What of this frame is worth drawing. Awake, most frames repeat the
        // one before and are not drawn at all; of the rest, almost all move a
        // single ring and only that ring is walked. Always-on never asks: a
        // frame comes once a minute there, so there is nothing to save and its
        // compositing is the least predictable.
        var dirty;
        if (lowPower) {
            dirty = FrameGate.everything();
        } else {
            if (!FrameGate.plan(fieldPrint(backing, day),
                                ringPrint(spans, markers, overs, blocks))) {
                Diagnostics.recordSkip(System.getTimer() - started);
                return;
            }
            dirty = FrameGate.dirty;
        }

        // Held back, the unfilled tier is the entire image rather than a
        // backdrop to the fills, so it gets its own table — brighter than the
        // ordinary always-on one, and matching the awake field exactly so the
        // background does not shift when the wrist comes up.
        var palette = hideFills
            ? Palette.heldBack
            : (lowPower ? Palette.alwaysOn : Palette.active);
        MatrixRenderer.draw(dc, spans, markers, overs, blocks, palette,
                            lowPower ? Palette.rampAlwaysOn : Palette.rampActive,
                            backing, dirty, FrameGate.clears);
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
    function fieldPrint(backing as Number?, day as Number) as Array<Float> {
        var drift = Drift.current();
        var out = _fieldPrint;
        out[0] = drift[0].toFloat();
        out[1] = drift[1].toFloat();
        out[2] = (backing == null) ? -1.0 : backing.toFloat();
        out[3] = (backing == null) ? 0.0
                                   : System.getClockTime().min.toFloat();
        out[4] = day.toFloat();
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
    //!
    //! Nothing to ask where the face draws its own: there are no hands to park,
    //! and `handAt()` reads the same clock the rest of the frame does. The `has`
    //! guard below would no-op anyway, but saying it outright is what keeps the
    //! two styles readable side by side.
    private function holdHandsAtSystemTime() as Void {
        if (HandStyle.DRAWN || StatMap.backing == StatMap.BACKING_OFF) {
            return;
        }
        if (self has :setClockHandPosition &&
            WatchUi has :ANALOG_CLOCK_STATE_SYSTEM_TIME) {
            setClockHandPosition(
                {:clockState => WatchUi.ANALOG_CLOCK_STATE_SYSTEM_TIME});
        }
    }

    //! Toggle the Epix's temporary unobstructed-data view.
    //!
    //! Returning false on a physical-hands watch leaves the system's hold
    //! gesture alone. On Epix, forgetting the frame forces both buffers to be
    //! repainted without the hand silhouettes.
    function togglePeek() as Boolean {
        if (!HandStyle.DRAWN) {
            return false;
        }
        _peeking = !_peeking;
        FrameGate.forget();
        WatchUi.requestUpdate();
        return true;
    }

    function isPeeking() as Boolean {
        return _peeking;
    }

    //! The date and drawn hands cannot share the larger Epix hot path without
    //! crossing its watchdog. The date is detail in the field, so hands win
    //! while telling time and a peek (or Hands: Off) reveals it.
    function showsDate(backing as Number?) as Boolean {
        return StatMap.rotation == StatMap.ROTATION_UPRIGHT_DATE &&
               (!HandStyle.DRAWN || backing == null);
    }

    function onEnterSleep() as Void {
        _asleep = true;
        _peeking = false;
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
