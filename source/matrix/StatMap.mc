import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

//! Decides which ring a dot belongs to, and whether it falls inside that
//! ring's span.
//!
//! The mapping is the seam every other module is written against: a dot's
//! radius picks its ring, and its angle becomes a single 0.0-1.0 position
//! along that ring. Because a position is one number rather than a coordinate,
//! a source that reports a range works everywhere a level does.
module StatMap {

    enum Backing {
        BACKING_OFF = 0,
        BACKING_WHITE = 1,
        BACKING_DARK = 2
    }

    //! Whether always-on shows the data or just the bare field of dots.
    enum AlwaysOnFill {
        ALWAYS_ON_FILL_SHOWN = 0,   //! The same image awake and asleep.
        ALWAYS_ON_FILL_HIDDEN = 1   //! Colour only; the data appears on a raise.
    }

    //! Whether each cross turns to follow the ring it sits on.
    //!
    //! Turned, one stroke points out from the centre and the other lies across
    //! it, so the field reads as `+` on the axes and `×` on the diagonals and
    //! carries the same radial grain the rings do. Upright, every cross is the
    //! same `+` and the field reads as a plain lattice with the rings drawn on
    //! it. Both light nine pixels a dot, so neither costs luminance.
    //!
    //! The third is Upright with the day of the month written into it — see
    //! DateGlyph. It is a *rotation* value because it is a choice about the
    //! shape of the field's own dots and nothing else, and because the field it
    //! is drawn on has to be the even one for a numeral to show in it at all.
    //! Appended, never inserted: the stored value is an index.
    enum Rotation {
        ROTATION_RADIAL = 0,        //! Each cross follows its ring.
        ROTATION_UPRIGHT = 1,       //! Every cross stays upright.
        ROTATION_UPRIGHT_DATE = 2   //! Upright, with today's date struck in.
    }

    //! Which set of colours the rings carry. The theme decides every colour
    //! the face draws; see Palette.THEMES for what each one is and why.
    //! Appended to, never reordered: the stored value is an index, so moving
    //! one renames every theme above it on watches already carrying a setting.
    enum Theme {
        THEME_TERRAIN = 0,          //! Orchid, moss, ice, rust.
        THEME_ACTIVITY = 1,         //! The watch's own activity accents.
        THEME_FROST = 2,            //! Duotone: cyan and magenta.
        THEME_LAGOON = 3,           //! Duotone: teal and gold.
        THEME_NOCTURNE = 4,         //! Duotone: indigo and rust.
        THEME_ALPINIST = 5,         //! Duotone: forest green and gold.
        THEME_ALPINIST4 = 6         //! Brick, green, gold and white.
    }

    const PROPERTY_THEME = "theme";
    const PROPERTY_BACKING = "handBacking";
    const PROPERTY_ALWAYS_ON_FILL = "alwaysOnFill";
    const PROPERTY_ROTATION = "dotRotation";

    //! Four rings, each independently assigned to a Source.
    const RINGS = 4;
    const PROPERTY_RINGS = ["ring1", "ring2", "ring3", "ring4"] as Array<String>;

    const RING_THICKNESS = (DotGrid.RADIUS - DotGrid.HUB) / RINGS;

    var theme as Number = THEME_TERRAIN;
    var backing as Number = BACKING_OFF;
    var alwaysOnFill as Number = ALWAYS_ON_FILL_SHOWN;
    var rotation as Number = ROTATION_RADIAL;

    //! Which source each ring shows. Index 0 is the outermost ring.
    var rings as Array<Number> = [
        Source.SOURCE_STEPS,
        Source.SOURCE_INTENSITY_MINUTES,
        Source.SOURCE_BATTERY,
        Source.SOURCE_BODY_BATTERY
    ] as Array<Number>;

    //! Re-read every setting. Safe at any time; anything missing or out of
    //! range falls back to its default rather than throwing.
    function load() as Void {
        theme = readNumber(PROPERTY_THEME, THEME_TERRAIN,
                           THEME_TERRAIN, THEME_ALPINIST4);
        backing = readNumber(PROPERTY_BACKING, BACKING_OFF,
                             BACKING_OFF, BACKING_DARK);
        alwaysOnFill = readNumber(PROPERTY_ALWAYS_ON_FILL, ALWAYS_ON_FILL_SHOWN,
                                  ALWAYS_ON_FILL_SHOWN, ALWAYS_ON_FILL_HIDDEN);
        rotation = readNumber(PROPERTY_ROTATION, ROTATION_RADIAL,
                              ROTATION_RADIAL, ROTATION_UPRIGHT_DATE);

        var defaults = [Source.SOURCE_STEPS, Source.SOURCE_INTENSITY_MINUTES,
                        Source.SOURCE_BATTERY, Source.SOURCE_BODY_BATTERY]
                       as Array<Number>;
        var loaded = new [RINGS] as Array<Number>;
        for (var i = 0; i < RINGS; i++) {
            var stored = readNumber(PROPERTY_RINGS[i], defaults[i],
                                    0, Source.COUNT - 1);
            // A ring still set to the retired source reads as Off. The slot is
            // kept so no *other* setting changes meaning, but a ring pointed at
            // it has nothing left to show, and saying so is better than drawing
            // an empty band the menu cannot name.
            if (stored == Source.SOURCE_RETIRED) {
                stored = Source.SOURCE_OFF;
            }
            // A source this ring cannot show reads as Off, for the same reason
            // the retired one does: the ring has nothing to draw, and saying so
            // is better than a band the menu cannot name. Falling back to the
            // ring's *default* instead would quietly resurrect a source the
            // wearer never chose.
            if (!Source.allowedOn(stored, i)) {
                stored = Source.SOURCE_OFF;
            }
            loaded[i] = stored;
        }
        rings = loaded;
    }

    function readNumber(key as String, fallback as Number,
                        low as Number, high as Number) as Number {
        var value = fallback;
        try {
            var stored = Properties.getValue(key);
            if (stored != null) {
                value = (stored as Number).toNumber();
            }
        } catch (ex) {
            value = fallback;
        }
        if (value < low || value > high) {
            value = fallback;
        }
        return value;
    }

    //! A span nothing is inside.
    //!
    //! Positions run from 0.0 to below 1.0, so a span sitting out at 2.0 can
    //! never contain one. It also does not read as wrapping, since its start
    //! is not after its end — a wrapping span would light everything *outside*
    //! itself, which is the opposite of what this is for.
    //!
    //! This is how always-on hides the fills: not a branch in the render loop
    //! that runs ~1100 times a frame, just a span nothing falls in.
    const NEVER_LIT = [2.0, 2.0] as Array<Float>;

    //! Every ring empty, for always-on when the fills are held back.
    function noSpans() as Array<Array<Float> > {
        var out = new [RINGS] as Array<Array<Float> >;
        for (var i = 0; i < RINGS; i++) {
            out[i] = [0.0, 0.0] as Array<Float>;
        }
        fillNoSpans(out);
        return out;
    }

    //! Refill an existing span table with spans nothing can light.
    function fillNoSpans(out as Array<Array<Float> >) as Void {
        for (var i = 0; i < RINGS; i++) {
            out[i][0] = NEVER_LIT[0];
            out[i][1] = NEVER_LIT[1];
        }
    }

    //! Current span for every ring. Read once per frame.
    //!
    //! `awake` is passed straight through to the sources rather than acted on
    //! here: whether a reading still means anything in always-on is a property
    //! of the reading, so it belongs beside the reading's own definition. Only
    //! seconds cares. The view decides the value, because its power test has a
    //! fallback that reads the view's own sleep state.
    function spans(awake as Boolean) as Array<Array<Float> > {
        var out = new [RINGS] as Array<Array<Float> >;
        for (var i = 0; i < RINGS; i++) {
            out[i] = [0.0, 0.0] as Array<Float>;
        }
        fillSpans(out, awake);
        return out;
    }

    //! Refill an existing table without allocating an outer array or one span
    //! per ring. This is the path used by the once-per-second view callback.
    function fillSpans(out as Array<Array<Float> >, awake as Boolean) as Void {
        for (var i = 0; i < RINGS; i++) {
            Source.fillSpan(rings[i], awake, out[i]);
        }
    }

    //! Values per ring in the block channel: two words of packed levels,
    //! then the known bits. See HourBands for the layout.
    const BLOCK_VALUES = 3;

    //! Every ring's packed blocks, laid out flat. Read once per frame, beside
    //! spans().
    //!
    //! A parallel channel rather than a wider span. That a span is exactly two
    //! numbers is what lets a level and a range be treated alike everywhere
    //! downstream, and twelve disjoint blocks with a radial axis is a different
    //! shape entirely — so it travels beside the span, exactly as a marker does.
    //!
    //! Named for the shape rather than for the forecast that first filled it.
    //! Any source with one reading per clock position rides this channel, and
    //! the renderer never learns which one did.
    //!
    //! No `awake` parameter, deliberately. What rides here moves hourly at
    //! best, so it is worth precisely as much in always-on as awake; only
    //! seconds has a reading that goes stale between the one frame a minute
    //! that mode gets.
    function blocks() as Array<Number> {
        var out = new [RINGS * BLOCK_VALUES] as Array<Number>;
        fillBlocks(out);
        return out;
    }

    //! Refill the block channel in caller-owned storage.
    function fillBlocks(out as Array<Number>) as Void {
        for (var i = 0; i < RINGS; i++) {
            Source.fillBlocks(rings[i], out, i * BLOCK_VALUES);
        }
    }

    //! Every block known and empty, for always-on when the fills are held back.
    //!
    //! **Not all zeroes**, which is the trap. Zero `known` means every block is
    //! *unknown*, which draws the dim tier across the whole ring — that is data,
    //! in the one mode whose entire purpose is to show none. Known-and-empty is
    //! what renders the plain unfilled field the mode is asking for.
    function noBlocks() as Array<Number> {
        var out = new [RINGS * BLOCK_VALUES] as Array<Number>;
        fillNoBlocks(out);
        return out;
    }

    //! Refill the block channel with known-and-empty values.
    function fillNoBlocks(out as Array<Number>) as Void {
        for (var i = 0; i < RINGS; i++) {
            out[i * BLOCK_VALUES] = 0;
            out[i * BLOCK_VALUES + 1] = 0;
            out[i * BLOCK_VALUES + 2] = HourBands.ALL_KNOWN;
        }
    }

    //! Which rings are past their goal, and so drawing a second lap. Read once
    //! per frame, beside spans() and from the same `awake`.
    //!
    //! There is no noOvers() to match noSpans() and noMarkers(). Those exist
    //! because a span and a mark are worth the same in either power mode and
    //! have to be held back deliberately; over-ness is awake-only at its
    //! source, so passing always-on's `awake` through here already returns
    //! nothing lit up.
    function overs(awake as Boolean) as Array<Boolean> {
        var out = new [RINGS] as Array<Boolean>;
        fillOvers(out, awake);
        return out;
    }

    //! Refill the overflow flags in caller-owned storage.
    function fillOvers(out as Array<Boolean>, awake as Boolean) as Void {
        for (var i = 0; i < RINGS; i++) {
            out[i] = Source.over(rings[i], awake);
        }
    }

    //! No overflow flags, without reading goal sources that are invisible in
    //! the held-back always-on mode.
    function fillNoOvers(out as Array<Boolean>) as Void {
        for (var i = 0; i < RINGS; i++) {
            out[i] = false;
        }
    }

    //! The position each ring marks, or Source.NO_MARKER. Read once per frame.
    //!
    //! A ring running a second lap marks its waterline — where the overflow
    //! has reached — and that is taken from the end of the lap span rather than
    //! read from the source again. The dot is then *by definition* the end of
    //! the arc it terminates and cannot drift from it, and the source is read
    //! twice a frame rather than three times.
    //!
    //! A lap that reached 1.0 marks nothing. Its waterline is the ring's own
    //! edge, so there is no boundary left to point at, and a window centred on
    //! 1.0 would wrap past the origin and let markedDot pick from both ends of
    //! the ring at once. A band tinted end to end already says "well past it".
    function markers(spans as Array<Array<Float> >,
                     overs as Array<Boolean>) as Array<Float> {
        var out = new [RINGS] as Array<Float>;
        fillMarkers(out, spans, overs);
        return out;
    }

    //! Refill marker positions in caller-owned storage.
    function fillMarkers(out as Array<Float>,
                         spans as Array<Array<Float> >,
                         overs as Array<Boolean>) as Void {
        for (var i = 0; i < RINGS; i++) {
            if (overs[i]) {
                var lap = spans[i][1];
                out[i] = (lap >= 1.0) ? Source.NO_MARKER : lap;
            } else {
                out[i] = Source.marker(rings[i]);
            }
        }
    }

    //! Every ring unmarked, for always-on when the fills are held back. The
    //! mark is part of the data, so it goes when the data does.
    function noMarkers() as Array<Float> {
        var out = new [RINGS] as Array<Float>;
        fillNoMarkers(out);
        return out;
    }

    //! Refill marker positions with the sentinel in caller-owned storage.
    function fillNoMarkers(out as Array<Float>) as Void {
        for (var i = 0; i < RINGS; i++) {
            out[i] = Source.NO_MARKER;
        }
    }

    //! The span a mark occupies: a window of the given half-width around a
    //! position, normalised onto the ring.
    //!
    //! Returned as an ordinary span so the renderer lights it with litBetween()
    //! rather than a second lit test of its own. That also means it wraps for
    //! free, which it must: a current temperature of half a degree sits just
    //! past twelve and its window straddles the origin, exactly as a sub-zero
    //! day range does.
    function windowAround(centre as Float, half as Float) as Array<Float> {
        var lo = centre - half;
        var hi = centre + half;
        if (hi - lo >= 1.0) {
            return [0.0, 1.0] as Array<Float>;      //! wider than the ring
        }
        if (lo < 0.0) { lo += 1.0; }
        if (hi >= 1.0) { hi -= 1.0; }
        return [lo, hi] as Array<Float>;
    }

    //! Which ring this dot belongs to: the outermost is 0, and the rings are
    //! of equal thickness between the rim and the hub.
    function ringFor(dx as Number, dy as Number) as Number {
        var distance = Math.sqrt(dx * dx + dy * dy);
        var ring = ((DotGrid.RADIUS - distance) / RING_THICKNESS).toNumber();
        if (ring < 0) { return 0; }
        if (ring >= RINGS) { return RINGS - 1; }
        return ring;
    }

    //! Where this dot sits along its ring: turns clockwise from twelve, 0.0 up
    //! to but not including 1.0. A span lights every dot between its start and
    //! its end.
    function positionOf(dx as Number, dy as Number) as Float {
        return Angle.turnOf(dx, dy);
    }

    //! Is a dot at this position inside the span, given the span already
    //! unpacked into its ends and whether it wraps?
    //!
    //! This is the exact shape MatrixRenderer inlines. The renderer walks the
    //! dots ring by ring, so the unpacking and the wrap test hoist out of its
    //! inner loop and only the two comparisons are left — and at ~1100 dots a
    //! frame, a call here rather than a comparison cost about 6ms every frame.
    //! isLit() below is this plus the unpacking, and litTestsAgree pins the two
    //! together at the boundaries, which is where a copy of a comparison drifts.
    function litBetween(position as Float, start as Float, end as Float,
                        wraps as Boolean) as Boolean {
        if (wraps) {
            return (position >= start) || (position <= end);
        }
        return (position >= start) && (position <= end);
    }

    //! Is a dot at this position inside the span?
    //!
    //! A span whose end is before its start wraps past the ring's origin —
    //! a sub-zero temperature range crossing twelve o'clock does exactly this,
    //! running from, say, :55 round to :03. This is the readable definition,
    //! used by the tests and by anything not in the render loop.
    function isLit(position as Float, span as Array<Float>) as Boolean {
        return litBetween(position, span[0], span[1], span[0] > span[1]);
    }

    //! Classify a dot into a palette slot: ring * 2, plus 1 when lit.
    function classify(dx as Number, dy as Number,
                      spans as Array<Array<Float> >) as Number {
        var ring = ringFor(dx, dy);
        return ring * 2 + (isLit(positionOf(dx, dy), spans[ring]) ? 1 : 0);
    }
}
