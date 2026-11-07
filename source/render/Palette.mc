import Toybox.Lang;

//! Colour for every dot state, in both power modes.
//!
//! One colour per ring, from the theme in force. The filled portion carries the
//! colour at full read; the unfilled portion is the same colour dimmed enough
//! to tint the field without reading as lit. Awake and always-on share their
//! filled colours and differ only in that unfilled tier, which is what keeps
//! the two modes looking like the same image rather than two designs.
//!
//! There is a third table for the one mode where the unfilled tier is the
//! whole picture: always-on with the fills held back. See WEAK_HELD_BACK.
//!
//! Every table is indexed by ring * 2, plus 1 when lit.
module Palette {

    //! Ring colours for every theme, flat: THEMES[themeIndex * THEME_COLOURS + n].
    //!
    //! Flat rather than an array of arrays, for the same reason DotGrid.ARMS
    //! is flat: a const array of arrays is a step further than Monkey C's
    //! const is meant to cover, and nesting it is the kind of thing that
    //! resolves in the simulator and comes back empty on the watch.
    //!
    //! **Terrain** — orchid, moss, ice, rust. Bright and saturated, because
    //! tuned in a dark room the face was legible and outdoors in daylight it
    //! was not.
    //!
    //! Orchid replaces an amber that looked right at full strength and turned
    //! brown the moment it was dimmed for the unfilled tier. That tier covers
    //! most of a ring most of the time, so how a colour *dims* matters as much
    //! as how it looks lit — and warm oranges dim to mud while violets stay
    //! chromatic. Orchid holds a CIELAB chroma of 47 when dimmed, against
    //! amber's 39 of brown.
    //!
    //! **Activity** — red, green, blue, gold: the accent colours this watch
    //! itself uses, read off the device's own artwork rather than guessed.
    //! Each nwidget_*.png and D_list_select_*.png in the installed device
    //! directory is a ramp from black to one accent, so the peak-chroma pixel
    //! *is* the accent — and the hue agrees to a tenth of a degree across both
    //! sets, which is what makes these the real values and not one image's
    //! artefact.
    //!
    //! Gold is the rejected amber's cousin, so it was held to the same test:
    //! dimmed to the unfilled tier it is #7D5405, a CIELAB chroma of 47.3 —
    //! level with orchid's 47.0, and every Activity colour dims to a chroma
    //! inside the band Terrain already occupies.
    //!
    //! **Beacon** — cyan, red, indigo, gold. **Pulse** — red, teal, orchid,
    //! lime. Both began as mockup candidates and keep the exact ring order and
    //! temperature stops reviewed there.
    //!
    //! **Lemon & Azure**, **Emerald & Violet** and **Orchid & Lime** are
    //! duo-tones: two colours alternating ring by ring, A B A B A, because
    //! five hues plus the colour the data brings (the ramp, the sun dots, the
    //! time ring's split) had made every theme busy. They were chosen from ten
    //! candidates in the web configurator, which keeps the other seven. With
    //! two hues the ramp runs from the bluer to the warmer and holds there.
    //!
    //! The order is decorative in no theme. Neighbours blurring together,
    //! not the set average, decides whether two rings can be told apart.
    //! Activity puts gold on the innermost ring, which has by far the fewest
    //! dots, and leaves it beside blue rather than either of the closer hues.
    //!
    //! Ring 1 is the outermost.
    //!
    //! **Five colours, for the 454's five rings.** A four-ring watch never
    //! reads the fifth. Each was picked on the five-ring mockup as the hue the
    //! theme did not already have and its neighbour does not crowd: gold beside
    //! Terrain's rust, indigo beside Activity's gold, lime beside Beacon's gold,
    //! ice beside Pulse's lime.
    const THEME_COLOURS = 5;
    const THEME_COUNT = 7;
    const THEMES = [
        0xE879F9,   //! Terrain:  orchid
        0xB8D64B,   //!           moss
        0x7FD4FF,   //!           ice
        0xFF6B5B,   //!           rust
        0xE5B33A,   //!           gold
        0xFE4646,   //! Activity: red
        0x6DC54F,   //!           green
        0x1F8FFE,   //!           blue
        0xE59A0A,   //!           gold
        0x8E7BFF,   //!           indigo
        0x5CD9F0,   //! Beacon:   cyan
        0xFE4646,   //!           red
        0x8E7BFF,   //!           indigo
        0xE59A0A,   //!           gold
        0xB8D64B,   //!           lime
        0xFE4646,   //! Pulse:    red
        0x2FD9C5,   //!           teal
        0xE879F9,   //!           orchid
        0xB8D64B,   //!           lime
        0x7FD4FF,   //!           ice
        0xF0DC50,   //! Lemon & Azure:    lemon
        0x3D9BFF,   //!                   azure
        0xF0DC50,
        0x3D9BFF,
        0xF0DC50,
        0x3FE08A,   //! Emerald & Violet: emerald
        0xB07CFF,   //!                   violet
        0x3FE08A,
        0xB07CFF,
        0x3FE08A,
        0xE879F9,   //! Orchid & Lime:    orchid
        0xB8D64B,   //!                   lime
        0xE879F9,
        0xB8D64B,
        0xE879F9
    ] as Array<Number>;

    const WEAK_ACTIVE = 0.55;
    const WEAK_ALWAYS_ON = 0.45;

    //! The unfilled tier when always-on holds the fills back.
    //!
    //! In that mode nothing is ever lit, so this tier is not a backdrop to the
    //! data — it *is* the image, and 0.45 was chosen against a face that also
    //! had filled dots to carry it. On its own it read too dark.
    //!
    //! Written as WEAK_ACTIVE rather than as its value, because the decision is
    //! "match the awake face", not "be 0.55". The field then does not change
    //! brightness at all when the wrist comes up: the raise purely adds the
    //! filled dots, with nothing shifting underneath them.
    //!
    //! The burn-in budget is nowhere near this: the held-back frame goes from
    //! 2.8% to 3.4% of screen luminance against a limit of 10%, and even every
    //! dot at full colour would only reach 6.1%. What bounds this tier is that
    //! the mode has to stay visibly darker than showing the data, or the option
    //! stops meaning anything — heldBackFillsCutAlwaysOnLuminance asserts it.
    const WEAK_HELD_BACK = WEAK_ACTIVE;

    //! The tier for an hour the forecast said nothing about.
    //!
    //! The face never draws black, so a dry hour is not dark — it is the
    //! unfilled tier. "No forecast" therefore needs a *third* value, or it
    //! reads as a confident forecast of no rain.
    //!
    //! Darker than unfilled rather than brighter, which buys two things: it
    //! reads as absence, the field visibly thinning where the data runs out;
    //! and luminance only ever falls, so the always-on budget cannot be
    //! threatened from this direction and no theme needs re-measuring for it.
    //!
    //! 0.25 is chosen against always-on, not awake, because always-on is the
    //! tighter pair: its unfilled tier is 0.45, and the lit-to-unfilled step
    //! the face already lives on is 1 / 0.55, so 0.45 / 1.82 reproduces that
    //! same contrast one rung down. Awake then gets 0.55 / 0.25, which is more
    //! separation than it needs.
    const WEAK_UNKNOWN = 0.25;

    //! How far each always-on boost level lightens the theme, as a share of
    //! the way to white in OKLCH (HueSplit.lighten), in StatMap.AlwaysOnBoost
    //! order. Off is no lightening at all, so every table is today's.
    //!
    //! The 10% budget does not bound these: an all-white field with every mark
    //! and sun measures under 9.1% (anAllWhiteCustomThemeFitsTheAlwaysOnBudget),
    //! so any colours fit. What bounds them is how pale a strong colour may go
    //! before the theme stops being itself — a call made on the wrist.
    const BOOST_AMOUNTS = [0.0d, 0.35d, 0.65d] as Array<Double>;

    //! Always-on used to lift the colours to survive the panel's own dimming.
    //! With this palette there is nothing left to lift: ice and orchid are
    //! already at or near a full channel, so scaling up would clamp and shift
    //! the hue rather than brighten it. Always-on and awake now draw the same
    //! filled colours and differ only in their unfilled tier — which is what
    //! "minimal change between modes" wanted in the first place.
    const LIFT = 1.0;

    //! The colour of a mark called out on a ring — today, the current
    //! temperature against the day's range.
    //!
    //! Carrying rather more than half the colour of the band it sits in. It
    //! was pure white, on the reasoning that every ramp stop is saturated so
    //! only an unsaturated colour reads as a marker rather than as more data.
    //! That is true but it overshot: pure white read as a hole punched through
    //! the field rather than a point on it. A third of the band's colour was
    //! the first correction and did not go far enough — on an AMOLED the mark
    //! still read as a white pixel rather than as part of the palette.
    //!
    //! Tinting costs less legibility than it looks like it should, because
    //! colour is not what carries the mark. MatrixRenderer makes the point from
    //! the other side — a white *cross* among crosses was tried and vanished.
    //! What reads is that the mark is the only solid dot on a field of crosses,
    //! so the hue is free to settle into the palette.
    //!
    //! Tinted per ring rather than toward one fixed hue, so the mark still
    //! belongs to its band if temperature is assigned to a different ring.
    //!
    //! There is no always-on tier, though the mark draws in always-on: LIFT is
    //! 1.0, so the band it sits on is the same in both modes and so is the
    //! mark. Only the held-back mode drops it — see
    //! CrossoverView.fillMarksFor().
    //! Why tint further rather than dim: the obvious way to take brightness
    //! out of the mark is to scale it down, and that does not work here. The
    //! waterline dot on an over-goal ring lands on the over tier and has to
    //! stay above it, and scaling drags the colour off the band-to-white line
    //! the tier sits on — measured, it collides on the moss and ice rings after
    //! about 6%, which is not enough to see. Tinting slides the mark down that
    //! same line toward its own band, so it stays clear of the tier for as long
    //! as MARKER_TINT stays below OVER_TINT, and that is the only bound.
    //!
    //! Measured at this tint, with the ordering the tests pin —
    //! band < over < mark — on the two rings where it is tightest:
    //!
    //!     moss   band 0.77   over 0.84   mark 0.87
    //!     orchid band 0.60   over 0.72   mark 0.78
    const MARKER = 0xFFFFFF;
    const MARKER_TINT = 0.55;

    //! The two sun dots on the temperature-and-sun ring start from these
    //! hues: sunrise, then sunset, in Source.SUN_VALUES order — a light
    //! yellow and a mid blue.
    //!
    //! Drawn as they are, they read as stickers on the field: the same two
    //! colours on every theme and ring, belonging to none of them. So each is
    //! mixed toward its ring's band by SUN_TINT, the move the temperature mark
    //! makes toward white — warm and cool still say rise and set, and the dot
    //! sits in the theme. See sunOf.
    const SUN_HUES = [0xFFE680, 0x4D8CFF] as Array<Number>;

    //! How far each sun dot is mixed toward its band. Just under the mark's
    //! MARKER_TINT, so the sun's own hue still leads;
    //! theSunDotsCarryATouchOfTheirBand holds that the blend never lands a
    //! dot on its band, its mark or the other sun.
    const SUN_TINT = 0.70;

    //! How far the current-temperature mark is mixed toward its band — far
    //! further than MARKER_TINT, which now governs only the over-goal
    //! waterline.
    //!
    //! At MARKER_TINT the mark was nearly half white and glared. It never
    //! needed the white to be found: it is the only solid square on a field of
    //! thin crosses, and density is what reads. So the reading mark is mostly
    //! its own band, lifted a touch — easy to find when looked for, quiet
    //! otherwise. The waterline keeps the brighter mix because it has to stand
    //! above the lap's own tint (everyThemeKeepsTheTierOrder).
    const SOFT_MARK_TINT = 0.85;

    //! How far the time ring's current-hour mark is mixed toward its own
    //! colour (TimeRing.drawHourMarks). The other eleven are solid in the
    //! colour the ring has there — density alone, the quietest mark the face
    //! has — and this one is lifted toward white between the soft mark and
    //! the waterline, so it is findable without glaring. Chosen on the
    //! mockups (`14h-time-marks.png`).
    const HOUR_MARK_TINT = 0.6;

    //! How far an over-goal ring's second lap is tinted toward the mark.
    //!
    //! "Slightly stronger" cannot mean scaling the colour up: that is the whole
    //! reason LIFT is 1.0, since ice and orchid already sit at a full channel
    //! and multiplying would clamp and shift the hue rather than brighten it.
    //! So the tier is the band mixed toward white, the same move the mark
    //! makes, stopping well short of it.
    //!
    //! It sits about midway between the mark's tint and the band itself, which
    //! is what leaves room on both sides: clearly stronger than a ring that
    //! merely met its goal, and clearly dimmer than the solid dot marking the
    //! lap's waterline, which lands *on* this tier and has to stay legible
    //! against it. theOverTierReadsBrighterThanTheBand holds that order.
    const OVER_TINT = 0.70;

    //! Backing drawn under the analogue hands when that option is on.
    const BACKING_WHITE = 0xFFFFFF;
    const BACKING_DARK = 0x101010;

    //! The time ring's elapsed dots. White, because that is the Crossover's own
    //! hour hand and the one colour no theme uses, so it reads as the clock
    //! rather than as a fifth reading. What has not elapsed draws from dimOf —
    //! the ring's colour at WEAK_UNKNOWN — because at the ordinary unfilled
    //! tier the split between the two halves did not read at 1:1 (ROADMAP,
    //! Epix time ring, Phase 0). The same colours in every power mode: the
    //! time is never held back.
    const TIME_LIT = BACKING_WHITE;

    //! The overlapping time ring's colours come from the theme: where hour and
    //! minute have both passed is the ring's own colour, and the hour and
    //! minute are its hue turned TIME_SPLIT_DEGREES either way in OKLCH at its
    //! own lightness (HueSplit), so the three read as mixing — Terrain's orchid
    //! splits into a light blue hour and a salmon minute, the way blue and red
    //! make purple. 60 rather than 45,
    //! chosen on the mockups: at 45 the pair is hard to tell apart on the red
    //! themes. A fixed rule rather than steering clear of the other rings'
    //! colours, so a custom theme's ring splits predictably.
    const TIME_SPLIT_DEGREES = 60.0;

    //! The least OKLCH chroma the split pair takes, so a pale ring still
    //! splits into two colours rather than two greys.
    const TIME_SPLIT_CHROMA = 0.08;

    //! Unfilled dots on the overlapping ring: a neutral grey rather than the
    //! ring's colour, because a dim copy of the ring beside its own hue reads
    //! as more of the fill.
    const TIME_UNLIT = 0x3A3A3A;

    //! Temperature is drawn on a ramp so its band reads as a temperature and
    //! not just a length. Cold through a middle to hot, and every stop is one
    //! of the theme's own four colours, so it stays inside the palette.
    //! Precomputed: working it out per dot costs too much inside the frame.
    const RAMP_STEPS = 32;

    //! Which of a theme's colours the ramp runs through, flat and in cold,
    //! mid, hot order: RAMP_STOPS[themeIndex * RAMP_POINTS + n].
    //!
    //! Indices into the theme rather than colours of their own, because a ramp
    //! stop *is* a ring colour and writing the value a second time is how the
    //! two drift apart. Named per theme rather than fixed at 2, 0, 3, because
    //! which slot holds the cold hue falls out of the ring ordering — and that
    //! ordering answers to neighbour contrast, not to keeping the ramp's
    //! indices where they were. Terrain runs ice -> orchid -> rust, Activity
    //! blue -> gold -> red, Beacon cyan -> gold -> red, and Pulse teal -> lime
    //! -> red. Every shipping theme has three explicit stops; a duo-tone's mid
    //! and hot are both its warmer colour, so its ramp turns over the first
    //! half of the scale, 0 to 30C, and holds there.
    const RAMP_POINTS = 3;
    const RAMP_STOPS = [
        2, 0, 3,                    //! Terrain:  ice -> orchid -> rust
        2, 3, 0,                    //! Activity: blue -> gold -> red
        0, 3, 1,                    //! Beacon:   cyan -> gold -> red
        1, 3, 0,                    //! Pulse:    teal -> lime -> red
        1, 0, 2,                    //! Lemon & Azure:    azure -> lemon
        1, 0, 2,                    //! Emerald & Violet: violet -> emerald
        0, 1, 3                     //! Orchid & Lime:    orchid -> lime
    ] as Array<Number>;

    var active as Array<Number> = [] as Array<Number>;
    var alwaysOn as Array<Number> = [] as Array<Number>;
    var heldBack as Array<Number> = [] as Array<Number>;

    //! The mark's colour on each ring. One entry per ring, not per slot.
    var markerOf as Array<Number> = [] as Array<Number>;

    //! The sun dots' colours, flat: ring * Source.SUN_VALUES, then sunrise,
    //! sunset. Indexed exactly as MatrixRenderer.drawnSun is. Always-on's
    //! version is sunAsleep, from the boosted colours; useMode() picks.
    var sunOf as Array<Number> = [] as Array<Number>;

    //! The current-temperature mark's colour on each ring. See SOFT_MARK_TINT.
    //! It draws in always-on too, so it has a boosted version (softAsleep).
    var softMarkOf as Array<Number> = [] as Array<Number>;

    //! The second lap's colour on each ring — what a ring past its goal draws
    //! where it would otherwise draw the plain filled colour. One entry per
    //! ring, not per slot: the renderer swaps it into the ring's filled slot
    //! for the frame, so the dot loop still reads exactly two colours.
    //!
    //! Awake only — over-ness is awake-only at its source, so no always-on
    //! frame reads this table and there is no second tier to keep in step.
    //! markerOf is awake-only for the same reason: in always-on every mark is
    //! a reading, which takes softMarkOf.
    var overOf as Array<Number> = [] as Array<Number>;

    //! The unknown-hour tier on each ring. One entry per ring, not per slot —
    //! the same shape as markerOf and overOf, and for the same reason: it is a
    //! third colour the renderer swaps in, not a fourth palette slot, so the
    //! ring * 2 + lit indexing every other table and test uses is untouched.
    //!
    //! Always-on's version is dimAsleep, from the boosted colours, and
    //! useMode() picks: with the boost off the two are one array, since LIFT
    //! is 1.0 and the band under it is identical in both modes.
    var dimOf as Array<Number> = [] as Array<Number>;

    //! The overlapping time ring's slot colours, indexed as TimeRing's slots:
    //! neither, hour, minute, both. Built from the theme with the rest.
    var timeOverlap as Array<Number> = [] as Array<Number>;

    //! The tables above that always-on draws too, in each mode's version. The
    //! renderer reads dimOf, softMarkOf, sunOf and timeOverlap as they stand;
    //! useMode() points them at one set or the other before a frame, so it
    //! needs no notion of a boost. With the boost off the two sets are the same
    //! arrays. markerOf and overOf have no always-on set: a lap, and with it
    //! the waterline, is awake-only (StatMap.overs).
    var dimAwake as Array<Number> = [] as Array<Number>;
    var dimAsleep as Array<Number> = [] as Array<Number>;
    var softAwake as Array<Number> = [] as Array<Number>;
    var softAsleep as Array<Number> = [] as Array<Number>;
    var sunAwake as Array<Number> = [] as Array<Number>;
    var sunAsleep as Array<Number> = [] as Array<Number>;
    var timeAwake as Array<Number> = [] as Array<Number>;
    var timeAsleep as Array<Number> = [] as Array<Number>;

    //! The theme's colours as always-on draws them: lightened by the boost.
    var bright as Array<Number> = [] as Array<Number>;
    var rampActive as Array<Number> = [] as Array<Number>;
    var rampAlwaysOn as Array<Number> = [] as Array<Number>;

    //! The theme in force as four colours and three ramp stops, whichever
    //! table it came from. build() is the only thing that fills it and the only
    //! thing that reads THEMES or RAMP_STOPS, so a custom theme is a choice of
    //! *source* here and nothing downstream can tell the difference.
    var colours as Array<Number> = [] as Array<Number>;
    var stops as Array<Number> = [] as Array<Number>;

    //! One colour of the theme in force, by its index within that theme.
    function themeColour(index as Number) as Number {
        return colours[index % THEME_COLOURS];
    }

    //! Fill colours and stops from the theme StatMap loaded.
    function selectTheme() as Void {
        var chosen = new [THEME_COLOURS] as Array<Number>;
        var ramp = new [RAMP_POINTS] as Array<Number>;
        if (StatMap.theme == StatMap.THEME_CUSTOM) {
            var custom = StatMap.customTheme;
            for (var i = 0; i < THEME_COLOURS; i++) {
                chosen[i] = custom[i];
            }
            for (var i = 0; i < RAMP_POINTS; i++) {
                ramp[i] = custom[THEME_COLOURS + i];
            }
        } else {
            var slot = StatMap.themeIndex(StatMap.theme);
            for (var i = 0; i < THEME_COLOURS; i++) {
                chosen[i] = THEMES[slot * THEME_COLOURS + i];
            }
            for (var i = 0; i < RAMP_POINTS; i++) {
                ramp[i] = RAMP_STOPS[slot * RAMP_POINTS + i];
            }
        }
        colours = chosen;
        stops = ramp;
    }

    //! The theme colours always-on draws: themselves, or lightened.
    function boosted() as Array<Number> {
        var amount = BOOST_AMOUNTS[StatMap.boost];
        if (amount == 0.0d) {
            return colours;
        }
        var out = new [THEME_COLOURS] as Array<Number>;
        for (var i = 0; i < THEME_COLOURS; i++) {
            out[i] = HueSplit.lighten(colours[i], amount);
        }
        return out;
    }

    //! Point the shared tables at awake's or always-on's set. Cheap — four
    //! references — and called before every frame, so the renderer draws
    //! whichever mode the view is in with no test of its own.
    function useMode(lowPower as Boolean) as Void {
        dimOf = lowPower ? dimAsleep : dimAwake;
        softMarkOf = lowPower ? softAsleep : softAwake;
        sunOf = lowPower ? sunAsleep : sunAwake;
        timeOverlap = lowPower ? timeAsleep : timeAwake;
    }

    //! Marks, sun dots and the unknown-hour tier for one set of colours.
    function sharedFrom(source as Array<Number>) as Array<Array<Number> > {
        var soft = [] as Array<Number>;
        var suns = [] as Array<Number>;
        var faint = [] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var colour = source[ring % THEME_COLOURS];
            soft.add(mix(MARKER, colour, SOFT_MARK_TINT));
            for (var slot = 0; slot < SUN_HUES.size(); slot++) {
                suns.add(mix(SUN_HUES[slot], colour, SUN_TINT));
            }
            faint.add(scale(colour, WEAK_UNKNOWN));
        }
        var both = source[StatMap.TIME_RING % THEME_COLOURS];
        var split = HueSplit.pair(both, TIME_SPLIT_DEGREES, TIME_SPLIT_CHROMA);
        return [faint, soft, suns,
                [TIME_UNLIT, split[0], split[1], both] as Array<Number>]
               as Array<Array<Number> >;
    }

    function build() as Void {
        selectTheme();
        bright = boosted();
        var awake = [] as Array<Number>;
        var asleep = [] as Array<Number>;
        var held = [] as Array<Number>;
        var marks = [] as Array<Number>;
        var beyond = [] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var colour = themeColour(ring);
            marks.add(mix(MARKER, colour, MARKER_TINT));
            beyond.add(mix(MARKER, colour, OVER_TINT));
            awake.add(scale(colour, WEAK_ACTIVE));
            awake.add(colour);
            // Always-on from the boosted colour, which is the colour itself
            // while the boost is off.
            var lifted = scale(bright[ring % THEME_COLOURS], LIFT);
            asleep.add(scale(lifted, WEAK_ALWAYS_ON));
            asleep.add(lifted);
            // Unfilled at the awake tier, because matching the awake field is
            // the whole point of this tier: with the boost off it is the awake
            // field exactly, and with it on the same field lightened. Filled
            // from the lifted one, because this table draws in always-on — no
            // dot is lit while the fills are held back, but a table that is
            // merely unreachable should still be right.
            held.add(scale(lifted, WEAK_HELD_BACK));
            held.add(lifted);
        }
        active = awake;
        alwaysOn = asleep;
        heldBack = held;
        markerOf = marks;
        overOf = beyond;

        var day = sharedFrom(colours);
        var night = (bright == colours) ? day : sharedFrom(bright);
        dimAwake = day[0];
        softAwake = day[1];
        sunAwake = day[2];
        timeAwake = day[3];
        dimAsleep = night[0];
        softAsleep = night[1];
        sunAsleep = night[2];
        timeAsleep = night[3];
        // Awake until the view says otherwise, as these tables always were.
        useMode(false);

        rampActive = rampFrom(colours, 1.0);
        rampAlwaysOn = rampFrom(bright, LIFT);
    }

    //! The temperature ramp through this set's three stops.
    function rampFrom(source as Array<Number>, lift as Float) as Array<Number> {
        var ramp = [] as Array<Number>;
        // Hoisted: the stops are fixed for the whole ramp, so looking them up
        // per step would pay for the indirection 32 times over for nothing.
        var cold = scale(source[stops[0] % THEME_COLOURS], lift);
        var mid = scale(source[stops[1] % THEME_COLOURS], lift);
        var hot = scale(source[stops[2] % THEME_COLOURS], lift);
        for (var step = 0; step < RAMP_STEPS; step++) {
            var along = step.toFloat() / (RAMP_STEPS - 1);
            ramp.add((along <= 0.5)
                ? mix(cold, mid, along * 2.0)
                : mix(mid, hot, (along - 0.5) * 2.0));
        }
        return ramp;
    }

    //! Linear blend between two packed RGB colours.
    function mix(from as Number, to as Number, amount as Float) as Number {
        var r = channel(from, 16) + ((channel(to, 16) - channel(from, 16)) * amount);
        var g = channel(from, 8) + ((channel(to, 8) - channel(from, 8)) * amount);
        var b = channel(from, 0) + ((channel(to, 0) - channel(from, 0)) * amount);
        return (r.toNumber() << 16) | (g.toNumber() << 8) | b.toNumber();
    }

    function channel(colour as Number, shift as Number) as Number {
        return (colour >> shift) & 0xFF;
    }

    //! Multiply each channel of a packed RGB colour. Clamped, because LIFT
    //! scales above 1.0 and an overflowing channel would bleed into the next
    //! one's bits and change the hue outright.
    function scale(colour as Number, factor as Float) as Number {
        return (channelScaled(colour, 16, factor) << 16) |
               (channelScaled(colour, 8, factor) << 8) |
                channelScaled(colour, 0, factor);
    }

    function channelScaled(colour as Number, shift as Number,
                           factor as Float) as Number {
        var value = (channel(colour, shift) * factor).toNumber();
        if (value > 0xFF) { return 0xFF; }
        if (value < 0) { return 0; }
        return value;
    }
}
