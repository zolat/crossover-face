import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! SPIKE — measurement only. Nothing in this file is meant to ship.
//!
//! It answers three questions the face cannot decide by reasoning:
//!
//!   1. does a full-screen BufferedBitmap actually allocate on this device,
//!      and does it come out of the graphics pool rather than the app heap?
//!   2. what does drawing the field into that buffer and blitting it cost,
//!      against drawing straight to the screen?
//!   3. how much of a frame is the native drawing, and how much is the
//!      interpreted loop that decides what to draw?
//!
//! Four legs, chosen per drawn frame:
//!
//!   A  the renderer as it ships, straight to the screen Dc     — the baseline
//!   B  the same loop with the two drawLine calls removed       — native vs loop
//!   C  the renderer into the mirror's Dc, then one blit        — the mirror path
//!   D  the blit alone, no field walk                           — the repair frame
//!
//! **The leg is picked at random, not round-robin.** With a seconds ring every
//! tick draws and FrameGate repairs every sixth frame; `frame % 4` shares a
//! factor with that cadence, so every expensive clear-and-redraw would land on
//! two of the legs and none of the others. That one aliasing would inflate
//! A - B, which is the number this whole exercise exists to produce.
//!
//! **Costs are stratified by frame class, never blended.** A repair frame
//! (clears) and a partial one are different work, for the same reason
//! Diagnostics already keeps drawn and idle apart. Leg D models the
//! *replacement for a repair frame*, so it is read against A-repair.
//!
//! Legs B and D draw a deliberately wrong frame. The face visibly flickers
//! under this build; that is the spike working, not a fault.
module Spike {

    //! SPIKE: force the ring assignment rather than going through persisted
    //! settings. The simulator's .SET store is per-app-name and the face and
    //! the test build do not share one here, so a run kept coming up on the
    //! defaults however the file was written. The config is an input to the
    //! measurement, not part of what is being measured, so it is pinned.
    //!
    //! null leaves whatever Config.reload() loaded. The two rows of the
    //! ROADMAP table are two runs, which is what they have always been.
    //! Empty leaves whatever Config.reload() loaded, which is the real
    //! shipped default — properties.xml supplies it, so it is not a list worth
    //! transcribing here and getting subtly wrong.
    const FORCE_RINGS = [] as Array<Number>;

    function forceRings() as Void {
        if (FORCE_RINGS.size() == StatMap.RINGS) {
            StatMap.rings = FORCE_RINGS;
        }
    }

    //! Which legs this build actually runs.
    //!
    //! **Leg C is off for the first watch pass on purpose.** In the simulator
    //! it reached 22,688ms a frame; on the watch a frame like that does not
    //! come back at all — it trips the watchdog and takes the app with it,
    //! before any of the other four legs have reported anything. So the safe
    //! four are measured first and C is turned on for its own pass, where the
    //! only thing at risk is a run that was going to be about C anyway.
    const RUN_C = true;

    const LEGS = 5;
    const LEG_A = 0;
    const LEG_B = 1;
    const LEG_C = 2;
    const LEG_D = 3;
    const LEG_E = 4;
    const NAMES = ["A", "B", "C", "D", "E"] as Array<String>;

    //! Per leg, split by frame class. [partial, repair] side by side.
    var partialCount as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;
    var partialMs as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;
    var repairCount as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;
    var repairMs as Array<Number> = [0, 0, 0, 0, 0] as Array<Number>;

    //! A small LCG. Seeded from the clock so two runs are not identical, and
    //! deliberately not sharing a period with FrameGate's repair cadence.
    var _seed as Number = 12345;

    //! The legs this build runs, as an array so a disabled one costs no share
    //! of the frames rather than being silently folded into another leg.
    var enabled as Array<Number> = [] as Array<Number>;

    function armLegs() as Void {
        enabled = RUN_C ? ([LEG_A, LEG_B, LEG_C, LEG_D, LEG_E] as Array<Number>)
                        : ([LEG_A, LEG_B, LEG_D, LEG_E] as Array<Number>);
    }

    function nextLeg() as Number {
        _seed = (_seed * 1103515245 + 12345) & 0x3FFFFFFF;
        return enabled[(_seed >> 8) % enabled.size()];
    }

    // ---------------------------------------------------------------- mirror

    var mirror as BufferedBitmapReference? = null;

    //! **A strong reference to the bitmap itself, held for the session.**
    //!
    //! Not redundant with `mirror`. The reference is only a handle: the SDK
    //! documents the allocation as happening in get(), and the resource as
    //! locked in the graphics pool only "as long as the object returned is in
    //! scope". Taking get() per frame and letting the result fall out of scope
    //! measured **~5200ms a frame** against leg A's ~100ms — the pool purging
    //! and reloading 304KB every single frame. Holding the object pins it and
    //! is what a mirror would have to do anyway.
    var held as BufferedBitmap? = null;

    //! Leg E's surface: the paletted one, pinned the same way.
    //!
    //! Separate from the mirror because the two answer different questions and
    //! cannot be the same object: a paletted buffer refuses setAntiAlias, which
    //! MatrixRenderer calls unconditionally, so leg C cannot use this one and
    //! leg E cannot use leg C's.
    var swatch as BufferedBitmap? = null;
    var swatchRef as BufferedBitmapReference? = null;
    var swatchPalette as Array<Number> = [] as Array<Number>;

    //! The mirror's Dc, cached for the session.
    //!
    //! Taking getDc() per frame is a third artifact on top of the two already
    //! found: with the bitmap pinned but the Dc re-fetched, leg C's average
    //! *grew* run to run (387ms -> 1171ms over eight frames) rather than
    //! settling, which is allocation pressure rather than drawing cost. A real
    //! mirror would hold one Dc, so this one does.
    var mirrorContext as Dc? = null;
    var verdict as String = "not tried";
    var ladder as String = "";

    //! The ladder squeezed onto one 390px line, for the on-watch overlay.
    var rungs as String = "";
    var allocated as Number = 0;

    //! Try the whole ladder, report every rung, and keep the first rung that
    //! both allocates and is usable for the mirror.
    //!
    //! `get()` matters: the SDK documents the allocation as happening there,
    //! not in createBufferedBitmap, so a ladder that only constructs the
    //! reference would measure nothing at all.
    function allocate() as Void {
        armLegs();
        if (!(Toybox.Graphics has :createBufferedBitmap)) {
            verdict = "no createBufferedBitmap";
            ladder = verdict;
            return;
        }
        ladder = "";
        rungs = "";
        allocated = 0;
        var full = attempt(0);
        var eight = attempt(1);
        var eightPal = attempt(2);
        var four = attempt(3);

        // **The live mirror is the 16bpp rung, not the shallowest that fits.**
        //
        // A paletted buffer refuses setAntiAlias outright — it throws
        // "Anti aliased primitives cannot be drawn to a paletted buffer", and
        // `dc has :setAntiAlias` still answers true, so the guard already in
        // MatrixRenderer does not catch it. Measured here: leg C crashed the
        // face on its first frame against an 8bpp+palette mirror.
        //
        // Functionally that is harmless — a paletted buffer has no
        // anti-aliasing to turn off, which is what the face wants anyway — but
        // it means a paletted mirror needs MatrixRenderer to stop making that
        // call, and leg A has to stay byte-identical for the baseline to mean
        // anything. So the mirror takes the rung that needs no such change,
        // and the ladder still reports whether the shallower ones allocate,
        // which is the memory question either way.
        swatchRef = eightPal;
        if (eightPal != null) {
            var res = eightPal.get();
            if (res instanceof BufferedBitmap) {
                swatch = res;
                swatchPalette = buildPalette(128);
                var into = res.getDc();
                into.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
                into.clear();
            }
        }

        if (full != null) {
            mirror = full;
            verdict = "mirror 16bpp";
        } else if (eight != null) {
            mirror = eight;
            verdict = "mirror 8bpp";
        } else if (eightPal != null) {
            mirror = eightPal;
            verdict = "mirror 8bpp+pal";
        } else if (four != null) {
            mirror = four;
            verdict = "mirror 4bpp";
        } else {
            mirror = null;
            verdict = "NO MIRROR";
        }
    }

    //! One rung. Reports the app-heap delta either side, which is the actual
    //! evidence for the graphics-pool claim — an exception not being thrown
    //! says only that something was allocated, not from where.
    //!
    //! The delta is never zero even when the pool claim holds: the reference
    //! object and the palette array are themselves on the heap. Tens or a few
    //! hundred bytes confirms it; anything near the buffer's own size refutes it.
    function attempt(rung as Number) as BufferedBitmapReference? {
        var label = ["16bpp", "8bpp", "8bpp+pal", "4bpp+pal"][rung];
        var before = System.getSystemStats().freeMemory;
        var kept = null;
        var note = "?";
        try {
            var ref;
            if (rung == 0) {
                ref = Graphics.createBufferedBitmap(
                    {:width => 390, :height => 390});
            } else if (rung == 1) {
                ref = Graphics.createBufferedBitmap(
                    {:width => 390, :height => 390, :colorDepth => 8});
            } else if (rung == 2) {
                ref = Graphics.createBufferedBitmap(
                    {:width => 390, :height => 390, :colorDepth => 8,
                     :palette => buildPalette(128)});
            } else {
                ref = Graphics.createBufferedBitmap(
                    {:width => 390, :height => 390, :colorDepth => 4,
                     :palette => buildPalette(16)});
            }
            var res = ref.get();
            if (res instanceof BufferedBitmap) {
                kept = ref;
                note = "ok";
            } else {
                note = "get()=null";
            }
        } catch (e) {
            note = "threw:" + e.getErrorMessage();
        }
        var after = System.getSystemStats().freeMemory;
        ladder += label + "=" + note + "(heap " + (before - after) + ") ";
        // The overlay gets a version that fits 390px: how many rungs
        // allocated, and each one's app-heap delta. The full ladder with the
        // failure reasons stays in `ladder` for the simulator's log.
        if (note.equals("ok")) {
            allocated++;
        }
        rungs += (before - after) + " ";
        return kept;
    }

    //! Every colour the face can put on screen, uniqued, padded with black.
    //! Palette.build() has already run — Config.reload() precedes this.
    function buildPalette(size as Number) as Array<Number> {
        var out = new [size] as Array<Number>;
        for (var i = 0; i < size; i++) {
            out[i] = 0x000000;
        }
        var at = 0;
        at = pour(out, at, Palette.active);
        at = pour(out, at, Palette.alwaysOn);
        at = pour(out, at, Palette.heldBack);
        at = pour(out, at, Palette.markerOf);
        at = pour(out, at, Palette.overOf);
        at = pour(out, at, Palette.rampActive);
        at = pour(out, at, Palette.rampAlwaysOn);
        at = pour(out, at, [Palette.BACKING_WHITE, Palette.BACKING_DARK]
                            as Array<Number>);
        return out;
    }

    function pour(out as Array<Number>, at as Number,
                  from as Array<Number>) as Number {
        var cursor = at;
        for (var i = 0; i < from.size(); i++) {
            if (cursor >= out.size()) {
                return cursor;
            }
            var colour = from[i];
            var seen = false;
            for (var j = 0; j < cursor; j++) {
                if (out[j] == colour) {
                    seen = true;
                    break;
                }
            }
            if (!seen && colour != 0x000000) {
                out[cursor] = colour;
                cursor++;
            }
        }
        return cursor;
    }

    //! The mirror's own Dc, or null if the pool has purged it. A purge is
    //! survivable — the caller falls back to leg A — and is worth knowing
    //! about, so it is counted rather than hidden.
    var purges as Number = 0;

    //! Leg B's dead-code guard. A module var, so an assignment to it cannot be
    //! elided the way an unused local can.
    var sink as Number = 0;

    function mirrorDc() as Dc? {
        var cached = mirrorContext;
        if (cached != null) {
            return cached;
        }
        var bitmap = held;
        if (bitmap == null) {
            var ref = mirror;
            if (ref == null) {
                return null;
            }
            var res = ref.get();
            if (!(res instanceof BufferedBitmap)) {
                purges++;
                return null;
            }
            held = res;          //! pin it, or the pool reloads it per frame
            bitmap = res;
        }
        mirrorContext = bitmap.getDc();
        return mirrorContext;
    }

    // ------------------------------------------------------------- dispatch

    //! Stands in for MatrixRenderer.draw() while the spike is in place. Picks
    //! a leg, times just the drawing, and books the cost against that leg and
    //! that frame class.
    function draw(dc as Dc, spans as Array<Array<Float> >,
                  markers as Array<Float>, overs as Array<Boolean>,
                  palette as Array<Number>, ramp as Array<Number>,
                  backing as Number?,
                  dirty as Array<Boolean>, clears as Boolean) as Void {
        var leg = nextLeg();
        ring0 = StatMap.rings[0];
        span0 = spans[0][0];
        span1 = spans[0][1];

        // Resolve the mirror before the clock starts. A leg that wants it and
        // cannot have it falls back to A and says so through `purges`, rather
        // than booking a cheap no-op as if it were a blit.
        var ref = mirror;
        var buffer = null;
        if (leg == LEG_C || leg == LEG_D) {
            buffer = mirrorDc();
            if (ref == null || buffer == null) {
                leg = LEG_A;
            }
        }
        var swatchBitmap = swatch;
        var swatchHandle = swatchRef;
        if (leg == LEG_E && (swatchBitmap == null || swatchHandle == null)) {
            leg = LEG_A;
        }

        var started = System.getTimer();
        if (leg == LEG_A) {
            MatrixRenderer.draw(dc, spans, markers, overs, palette, ramp,
                                backing, dirty, clears);
        } else if (leg == LEG_B) {
            drawNoLines(dc, spans, overs, palette, ramp, backing, dirty,
                        clears);
        } else if (leg == LEG_E && swatchBitmap != null &&
                   swatchHandle != null) {
            // The whole per-frame cost the setPalette design would pay: swap
            // the colours behind every pixel, then present. No dot loop at all.
            //
            // The buffer holds black rather than the field — setPalette and the
            // blit are per-pixel work independent of content, so this measures
            // the mechanism honestly. What it does *not* measure is the one-off
            // fill, which the design pays once rather than per frame.
            rotate(swatchPalette);
            swatchBitmap.setPalette(swatchPalette);
            dc.drawBitmap(0, 0, swatchHandle);
        } else if (ref != null && buffer != null) {
            if (leg == LEG_C) {
                MatrixRenderer.draw(buffer, spans, markers, overs, palette,
                                    ramp, backing, dirty, clears);
            }
            dc.drawBitmap(0, 0, ref);
        }
        var cost = System.getTimer() - started;

        if (clears) {
            repairCount[leg]++;
            repairMs[leg] += cost;
        } else {
            partialCount[leg]++;
            partialMs[leg] += cost;
        }
        if (OVERLAY) {
            overlay(dc);
        }
    }

    //! Shift the palette by one so setPalette is doing real work rather than
    //! being handed the values it already holds.
    function rotate(colours as Array<Number>) as Void {
        var first = colours[0];
        for (var i = 0; i < colours.size() - 1; i++) {
            colours[i] = colours[i + 1];
        }
        colours[colours.size() - 1] = first;
    }

    // ----------------------------------------------------------------- leg B

    //! MatrixRenderer.draw's dot loop with the two drawLine calls deleted.
    //!
    //! A **clone**, not a flag inside the real loop: a per-dot `if` would add
    //! ~1100 compares to leg A as well and corrupt the baseline this is
    //! measured against. The mark pass is left out too — three native calls
    //! against ~2200, and it needs the erase history leg A owns.
    function drawNoLines(dc as Dc, spans as Array<Array<Float> >,
                         overs as Array<Boolean>, palette as Array<Number>,
                         ramp as Array<Number>, backing as Number?,
                         dirty as Array<Boolean>, clears as Boolean) as Void {
        DotGrid.ensureBuilt();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);
        }
        if (clears) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
        }

        var drift = Drift.current();
        var centreX = (dc.getWidth() / 2) + drift[0];
        var centreY = (dc.getHeight() / 2) + drift[1];

        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var armOf = DotGrid.armOf;
        var arms = DotGrid.ARMS;
        var positionOf = DotGrid.positionOf;
        var ringStart = DotGrid.ringStart;
        var rings = StatMap.rings;
        var rampTop = Palette.RAMP_STEPS - 1;
        var overColour = Palette.overOf;

        var hasBacking = (backing != null);
        var axes = hasBacking ? HandBacking.axes()
                              : ([0.0, 0.0, 0.0, 0.0] as Array<Float>);
        var hourX = axes[0];
        var hourY = axes[1];
        var minuteX = axes[2];
        var minuteY = axes[3];
        var backingColour = (backing != null) ? backing : 0;

        var turned = (StatMap.rotation == StatMap.ROTATION_RADIAL);
        var ax = arms[0];
        var ay = arms[1];
        var bx = arms[2];
        var by = arms[3];

        var lastColour = -1;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (!dirty[ring]) {
                continue;
            }
            var span = spans[ring];
            var from = span[0];
            var to = span[1];
            var wraps = (from > to);
            var weak = palette[ring * 2];
            var strong = palette[ring * 2 + 1];
            if (overs[ring]) {
                weak = strong;
                strong = overColour[ring];
            }
            var isRamp = (rings[ring] == Source.SOURCE_TEMPERATURE);
            var last = ringStart[ring + 1];

            for (var i = ringStart[ring]; i < last; i++) {
                var dx = xs[i];
                var dy = ys[i];
                var colour;

                if (hasBacking && HandBacking.covers(dx, dy, hourX, hourY,
                                                     minuteX, minuteY)) {
                    colour = backingColour;
                } else {
                    var position = positionOf[i];
                    var lit = wraps
                        ? ((position >= from) || (position <= to))
                        : ((position >= from) && (position <= to));
                    if (lit) {
                        colour = isRamp
                            ? ramp[(position * rampTop).toNumber()]
                            : strong;
                    } else {
                        colour = weak;
                    }
                }

                if (colour != lastColour) {
                    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                    lastColour = colour;
                }
                var x = centreX + dx;
                var y = centreY + dy;
                if (turned) {
                    var a = armOf[i];
                    ax = arms[a];
                    ay = arms[a + 1];
                    bx = arms[a + 2];
                    by = arms[a + 3];
                }
                // The two dc.drawLine calls that would be here are the
                // measurement. `sink` is what stops the compiler eliding the
                // coordinates and arm reads as dead — without it leg B would
                // drop work leg A is being credited with, and A - B would come
                // back too large. It costs 5 additions where leg A's two
                // drawLine calls cost 8 plus the calls themselves, so A - B is
                // "the two native calls, plus about three additions".
                sink = x + y + ax + ay + bx + by;
            }
        }
    }

    //! Off. The overlay existed to read the table off the watch, which cannot
    //! print — but the legs draw deliberately wrong frames, so the build is not
    //! a usable face and has no business on a wrist. The watch leg is dropped;
    //! the simulator's println is the instrument.
    const OVERLAY = false;

    //! Paint the table over the field, because the watch had no other way out.
    //!
    //! `println` reaches the simulator only, `CIQ_LOG` is written on a fault
    //! only, and tools/mtp_push.py can upload but not download — so on the
    //! watch this overlay *is* the instrument. Drawn after the clock has been
    //! stopped, so it costs the whole-frame figure in Diagnostics but none of
    //! the per-leg figures this exists to report.
    function overlay(dc as Dc) as Void {
        var lines = [
            "A " + cell(LEG_A),
            "B " + cell(LEG_B),
            "C " + cell(LEG_C),
            "D " + cell(LEG_D),
            "E " + cell(LEG_E),
            verdict + "  pool " + allocated + "/4",
            "heap " + rungs
        ] as Array<String>;
        var height = 17;
        // Shifted above the pivot rather than centred on it. The physical
        // hands are 28px wide and cross the middle of the glass whatever the
        // time, so a block centred there is unreadable at half the hours.
        var top = (dc.getHeight() / 2) - (lines.size() * height) - 10;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(10, top - 5, dc.getWidth() - 20,
                         (lines.size() * height) + 10);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(dc.getWidth() / 2, top + (i * height),
                        Graphics.FONT_XTINY, lines[i],
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function cell(leg as Number) as String {
        return average(partialMs, partialCount, leg) + "/" +
               partialCount[leg] + "p " +
               average(repairMs, repairCount, leg) + "/" +
               repairCount[leg] + "r";
    }

    // ------------------------------------------------------------ reporting

    function average(total as Array<Number>, count as Array<Number>,
                     leg as Number) as Number {
        return (count[leg] == 0) ? -1 : (total[leg] / count[leg]);
    }

    //! Enough repair samples in every leg for the D-vs-A-repair comparison to
    //! mean anything. Roughly one frame in six is a repair.
    function ready() as Boolean {
        for (var leg = 0; leg < LEGS; leg++) {
            if (repairCount[leg] < 30) {
                return false;
            }
        }
        return true;
    }

    function table() as String {
        var out = "";
        for (var leg = 0; leg < LEGS; leg++) {
            out += NAMES[leg] + " " +
                   average(partialMs, partialCount, leg) + "/" +
                   partialCount[leg] + "p " +
                   average(repairMs, repairCount, leg) + "/" +
                   repairCount[leg] + "r  ";
        }
        return out;
    }

    //! SPIKE diagnostic: what the face believes it is showing, because a
    //! screenshot cannot tell a weak purple dot from a strong one.
    var ring0 as Number = -1;
    var span0 as Float = -1.0;
    var span1 as Float = -1.0;
    var lowPower as Boolean = false;

    function summary() as String {
        return verdict + " | " + table() + "| purges " + purges +
               " | ring0=" + ring0 + " span=" + span0 + ".." + span1 +
               " low=" + lowPower;
    }
}
