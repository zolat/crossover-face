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

    //! How much brighter than awake always-on draws. The watch turns its whole
    //! screen down in always-on, which the face cannot change; this draws the
    //! always-on tables from a lighter copy of the theme instead (Palette.boost).
    enum AlwaysOnBoost {
        BOOST_OFF = 0,
        BOOST_BRIGHT = 1,
        BOOST_BRIGHTEST = 2
    }

    //! Whether each cross turns to follow the ring it sits on.
    //!
    //! Turned, one stroke points out from the centre and the other lies across
    //! it, so the field reads as `+` on the axes and `×` on the diagonals and
    //! carries the same radial grain the rings do. Upright, every cross is the
    //! same `+` and the field reads as a plain lattice with the rings drawn on
    //! it. Both light nine pixels a dot, so neither costs luminance.
    //!
    //! The third value was "Upright + date", from when the date was a
    //! marking of the dots themselves and needed the even field to show in.
    //! The date is its own setting now (`PROPERTY_DATE`) and works on either
    //! field, so the value is **retired, not reused**: load() reads a stored 2
    //! as Upright — what that wearer was looking at — and the date setting's
    //! default of On keeps their date. Never hand 2 to anything new.
    enum Rotation {
        ROTATION_RADIAL = 0,        //! Each cross follows its ring.
        ROTATION_UPRIGHT = 1,       //! Every cross stays upright.
        ROTATION_RETIRED_DATE = 2   //! Was Upright + date; reads as Upright.
    }

    //! Whether the day of the month is drawn into the field. See DateGlyph.
    //! On by default: a face without the date was the gap this closed.
    enum DateDisplay {
        DATE_OFF = 0,
        DATE_ON = 1
    }

    //! How bright the date's connecting lines are: an index into
    //! DateGlyph.LINE_PERCENTS, the three levels chosen between on the wrist.
    enum DateOutline {
        OUTLINE_50 = 0,
        OUTLINE_65 = 1,             //! The pick, and the default.
        OUTLINE_80 = 2
    }

    //! Which set of colours the rings carry. The theme decides every colour
    //! the face draws; see Palette.THEMES for what each one is and why.
    //!
    //! IDs 2 through 6 belonged to retired themes. They stay reserved so an
    //! old stored value can never silently become a different colour scheme.
    //! New themes started at 7 and are appended to THEME_IDS explicitly; the
    //! array position is the dense index used by Palette's compact tables.
    enum Theme {
        THEME_TERRAIN = 0,          //! Orchid, moss, ice, rust.
        THEME_ACTIVITY = 1,         //! The watch's own activity accents.
        THEME_BEACON = 7,           //! Cyan, red, indigo, gold.
        THEME_PULSE = 8             //! Red, teal, orchid, lime.
    }

    const THEME_RETIRED_FIRST = 2;
    const THEME_RETIRED_LAST = 6;
    const THEME_NEXT_ID = 9;

    //! The wearer's own four colours, set only by a config code (see
    //! ConfigCode). Far outside the production sequence on purpose: the next
    //! shipping theme is still THEME_NEXT_ID, and a custom theme is not one of
    //! THEME_IDS, which lists what Palette's const tables hold.
    const THEME_CUSTOM = 99;

    //! Where the custom theme lives: Application.Storage, as
    //! [colour1 .. colour5, cold, mid, hot]. Not Properties,
    //! because it has no phone-side field, and a property Garmin Connect does
    //! not know about is one a phone-side save has no reason to preserve.
    const STORAGE_CUSTOM_THEME = "customTheme";
    const CUSTOM_THEME_SIZE = 8;

    //! What a custom theme stored before themes had five colours holds: four
    //! colours and three stops. Read with the default fifth colour slotted in.
    const CUSTOM_THEME_SIZE_V1 = 7;

    //! Terrain, so a face that never received a custom theme still has a
    //! sensible one to switch to. Its fifth colour is Terrain's gold, which is
    //! also what a four-colour custom theme gains.
    const CUSTOM_DEFAULT = [0xE879F9, 0xB8D64B, 0x7FD4FF, 0xFF6B5B, 0xE5B33A,
                            2, 0, 3] as Array<Number>;
    const CUSTOM_FIFTH_DEFAULT = 0xE5B33A;

    //! The highest ramp stop a custom theme may name: any of its five colours.
    //! The version-2 config code carries a stop's third bit, so the 454's
    //! centre colour can be a stop too.
    const CUSTOM_STOP_MAX = 4;
    // Literal values because Monkey C const arrays have failed on-device when
    // their initialisers refer to other consts. The tests pin these to the enum.
    const THEME_IDS = [0, 1, 7, 8] as Array<Number>;

    const PROPERTY_THEME = "theme";
    const PROPERTY_BACKING = "handBacking";
    const PROPERTY_ALWAYS_ON_FILL = "alwaysOnFill";
    const PROPERTY_BOOST = "alwaysOnBoost";
    const PROPERTY_ROTATION = "dotRotation";
    const PROPERTY_DATE = "showDate";
    const PROPERTY_DATE_OUTLINE = "dateOutline";

    //! The temperature-ahead ring's scale, in whole degrees Celsius.
    //!
    //! **Values, not list indices** — the one pair of settings that stores the
    //! thing itself, because a temperature has no enum to renumber. The bounds
    //! are what both pickers offer and what settings.xml enforces phone-side.
    const PROPERTY_TEMP_AHEAD_LOW = "tempAheadLow";
    const PROPERTY_TEMP_AHEAD_HIGH = "tempAheadHigh";
    const TEMP_AHEAD_MIN_C = -20;
    const TEMP_AHEAD_MAX_C = 50;
    const TEMP_AHEAD_LOW_DEFAULT = 0;
    const TEMP_AHEAD_HIGH_DEFAULT = 45;

    //! The rings, each independently assigned to a Source: four, or five on
    //! the 454 (Lattice.RINGS). A per-screen const, so every array and loop
    //! sized by it still folds at compile time.
    const RINGS as Number = Lattice.RINGS;

    //! One property per ring the face can have. Every watch carries ring5;
    //! only a five-ring watch reads it, the way only the Crossover reads
    //! handBacking. It is not in settings.xml, so Garmin Connect never offers
    //! a ring a watch cannot draw — the on-device menu sets it.
    const PROPERTY_RINGS = ["ring1", "ring2", "ring3", "ring4", "ring5"]
                           as Array<String>;

    //! What each ring shows until set: Steps, intensity minutes, battery, Body
    //! Battery, and Steps again for the 454's centre ball — its outer ring
    //! tells the time, so Steps is otherwise nowhere on a fresh face. Literal
    //! values for the reason THEME_IDS gives; the tests pin them to the enum.
    const RING_DEFAULTS = [0, 6, 2, 3, 0] as Array<Number>;

    const RING_THICKNESS = (DotGrid.RADIUS - DotGrid.INNER) / RINGS;

    var theme as Number = THEME_TERRAIN;
    //! The custom theme, always loaded whichever theme is in force, so a
    //! config code can carry it while a shipping theme is selected.
    var customTheme as Array<Number> = CUSTOM_DEFAULT;
    var backing as Number = BACKING_OFF;
    var alwaysOnFill as Number = ALWAYS_ON_FILL_SHOWN;
    var boost as Number = BOOST_OFF;
    var rotation as Number = ROTATION_RADIAL;
    var date as Number = DATE_ON;
    var dateOutline as Number = OUTLINE_65;
    //! Always high > low after load(); HourlyWeatherData divides by the gap.
    var tempAheadLow as Number = TEMP_AHEAD_LOW_DEFAULT;
    var tempAheadHigh as Number = TEMP_AHEAD_HIGH_DEFAULT;

    //! Which source each ring shows. Index 0 is the outermost ring. Sized and
    //! filled by load(); this placeholder only has to be long enough for any
    //! ring a watch can have.
    var rings as Array<Number> = [0, 6, 2, 3, 0] as Array<Number>;

    //! Re-read every setting. Safe at any time; anything missing or out of
    //! range falls back to its default rather than throwing.
    function load() as Void {
        var storedTheme = readNumber(PROPERTY_THEME, THEME_TERRAIN,
                                     THEME_TERRAIN, THEME_CUSTOM);
        theme = (storedTheme == THEME_CUSTOM)
            ? THEME_CUSTOM
            : THEME_IDS[themeIndex(storedTheme)];
        customTheme = readCustomTheme();
        backing = readNumber(PROPERTY_BACKING, BACKING_OFF,
                             BACKING_OFF, BACKING_DARK);
        alwaysOnFill = readNumber(PROPERTY_ALWAYS_ON_FILL, ALWAYS_ON_FILL_SHOWN,
                                  ALWAYS_ON_FILL_SHOWN, ALWAYS_ON_FILL_HIDDEN);
        boost = readNumber(PROPERTY_BOOST, BOOST_OFF, BOOST_OFF, BOOST_BRIGHTEST);
        rotation = readNumber(PROPERTY_ROTATION, ROTATION_RADIAL,
                              ROTATION_RADIAL, ROTATION_RETIRED_DATE);
        if (rotation == ROTATION_RETIRED_DATE) {
            rotation = ROTATION_UPRIGHT;
        }
        date = readNumber(PROPERTY_DATE, DATE_ON, DATE_OFF, DATE_ON);
        dateOutline = readNumber(PROPERTY_DATE_OUTLINE, OUTLINE_65,
                                 OUTLINE_50, OUTLINE_80);
        loadTempAheadScale();

        var loaded = new [RINGS] as Array<Number>;
        for (var i = 0; i < RINGS; i++) {
            var stored = readNumber(PROPERTY_RINGS[i], RING_DEFAULTS[i],
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
            // The time is placed, never chosen, so a stored one is not a
            // wearer's choice to honour: it reads as Off like any value the
            // menu cannot have written.
            if (Source.isTime(stored)) {
                stored = Source.SOURCE_OFF;
            }
            loaded[i] = stored;
        }
        // On a watch with no hands the outermost ring *is* the clock, whatever
        // else ring1 says. Overriding rather than defaulting is the point: a
        // watch that has carried this face before already stores ring1 —
        // Steps, most likely — and a new default would never reach it. Only a
        // time style, which the ring's own picker writes, is kept.
        if (HandStyle.TIME_RING) {
            var style = readNumber(PROPERTY_RINGS[TIME_RING],
                                   Source.TIME_DEFAULT, 0, Source.COUNT - 1);
            loaded[TIME_RING] = Source.isTime(style) ? style
                                                     : Source.TIME_DEFAULT;
        }
        rings = loaded;
    }

    //! The ring a hands-free watch tells the time on: the outermost, which has
    //! the most dots round it and so the finest minute.
    const TIME_RING = 0;

    //! Read the two ends and make them a usable scale whatever was stored.
    //!
    //! The phone accepts each end on its own, so nothing stops a wearer setting
    //! the low end above the high one. That is read as the same range written
    //! backwards and swapped; two equal ends are widened by a degree. Either
    //! way the fill always runs cold-empty to hot-full and never divides by
    //! zero, and the menu shows these normalised values, so it agrees with
    //! what is drawn.
    function loadTempAheadScale() as Void {
        var low = readNumber(PROPERTY_TEMP_AHEAD_LOW, TEMP_AHEAD_LOW_DEFAULT,
                             TEMP_AHEAD_MIN_C, TEMP_AHEAD_MAX_C);
        var high = readNumber(PROPERTY_TEMP_AHEAD_HIGH, TEMP_AHEAD_HIGH_DEFAULT,
                              TEMP_AHEAD_MIN_C, TEMP_AHEAD_MAX_C);
        if (low > high) {
            var swap = low;
            low = high;
            high = swap;
        }
        if (low == high) {
            if (high == TEMP_AHEAD_MAX_C) {
                low = high - 1;
            } else {
                high = low + 1;
            }
        }
        tempAheadLow = low;
        tempAheadHigh = high;
    }

    //! The stored custom theme, or the default when it is missing or malformed
    //! — whole, never partly, for the reason a config code is all-or-nothing.
    function readCustomTheme() as Array<Number> {
        var stored = null;
        try {
            stored = Storage.getValue(STORAGE_CUSTOM_THEME);
        } catch (ex) {
            stored = null;
        }
        if (!(stored instanceof Array)) {
            return CUSTOM_DEFAULT;
        }
        // Stored before themes had five colours: slot the default fifth in
        // after the four, ahead of the stops.
        if (stored.size() == CUSTOM_THEME_SIZE_V1) {
            // Its stops index four colours, so a 4 there was never valid.
            for (var i = Palette.THEME_COLOURS - 1; i < CUSTOM_THEME_SIZE_V1; i++) {
                var stop = stored[i];
                if (!(stop instanceof Number) || stop >= Palette.THEME_COLOURS - 1) {
                    return CUSTOM_DEFAULT;
                }
            }
            var widened = stored.slice(0, Palette.THEME_COLOURS - 1);
            widened.add(CUSTOM_FIFTH_DEFAULT);
            widened.addAll(stored.slice(Palette.THEME_COLOURS - 1, null));
            stored = widened;
        }
        if (stored.size() != CUSTOM_THEME_SIZE) {
            return CUSTOM_DEFAULT;
        }
        for (var i = 0; i < CUSTOM_THEME_SIZE; i++) {
            var value = stored[i];
            if (!(value instanceof Number)) {
                return CUSTOM_DEFAULT;
            }
            var high = (i < Palette.THEME_COLOURS) ? 0xFFFFFF : CUSTOM_STOP_MAX;
            if (value < 0 || value > high) {
                return CUSTOM_DEFAULT;
            }
        }
        return stored as Array<Number>;
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

    //! Dense table index for a persisted theme ID. Unknown and retired IDs
    //! resolve to Terrain, keeping Palette's shipping tables gap-free without
    //! ever making the reserved values selectable again.
    function themeIndex(id as Number) as Number {
        for (var i = 0; i < THEME_IDS.size(); i++) {
            if (THEME_IDS[i] == id) {
                return i;
            }
        }
        return 0;
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

    //! Refill an existing span table with spans nothing can light — except a
    //! ring telling the time, which keeps it. Holding the fills back hides the
    //! data; the time is not data, and on a watch with no hands it is the one
    //! thing the glass must still say.
    function fillNoSpans(out as Array<Array<Float> >) as Void {
        for (var i = 0; i < RINGS; i++) {
            if (Source.isTime(rings[i])) {
                Source.fillSpan(rings[i], false, out[i]);
                continue;
            }
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

    //! Every ring's sunrise and sunset positions, flat: ring * SUN_VALUES,
    //! then sunrise, sunset. Read once per frame, beside markers().
    //!
    //! Like the temperature mark, the sun dots take no power mode: they are
    //! two dots a ring, worth as much asleep as awake, and only holding the
    //! fills back hides them.
    function fillSuns(out as Array<Float>) as Void {
        for (var i = 0; i < RINGS; i++) {
            Source.fillSuns(rings[i], out, i * Source.SUN_VALUES);
        }
    }

    //! No ring shows a sun time, for always-on when the fills are held back.
    function fillNoSuns(out as Array<Float>) as Void {
        for (var i = 0; i < RINGS * Source.SUN_VALUES; i++) {
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
