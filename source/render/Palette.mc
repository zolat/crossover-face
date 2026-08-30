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

    //! Ring colours for every theme, flat: THEMES[theme * THEME_COLOURS + n].
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
    //! **Activity** — gold, blue, green, red: the accent colours this watch
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
    //! inside the band Terrain already occupies. Activity is also the darker
    //! theme, at 84% of Terrain's luminance weighted by dots per ring, so it
    //! costs the burn-in budget nothing.
    //!
    //! The order is decorative in neither theme: it is the arrangement that
    //! maximises the distance between rings which sit *next to* each other —
    //! 93 for Terrain against 78 for its worst arrangement, and 118 for
    //! Activity. Neighbours blurring together, not the set average, is what
    //! decides whether two rings can be told apart. Activity keeps gold, its
    //! one awkward colour at 59 from red and 71 from green, at the end of the
    //! run with only blue beside it.
    //!
    //! **Frost**, **Lagoon** and **Nocturne** are duotones: two hues
    //! alternating rather than four distinct ones, so slots 0 and 2 hold the
    //! same colour and so do 1 and 3. That costs nothing, because rings 1 and
    //! 3 never touch — a repeat is only a defect between neighbours, and
    //! alternating makes *every* neighbour a hue flip rather than a hue step.
    //! Measured, the worst neighbour pair is 102, 99 and 103 against the 93
    //! Terrain ships with.
    //!
    //! The repeat has to be exact. The obvious alternative — the same hue at
    //! two lightnesses, which would keep four distinct values and leave the
    //! tests alone — is the one arrangement that actually breaks the face: a
    //! dimmed A sits on top of A's own unfilled tier, so ring 3 *lit* becomes
    //! indistinguishable from ring 1 *unlit*. Measured at a CIELAB distance of
    //! 5 to 16, against 61 to 67 for the four-hue themes. An exact repeat has
    //! no such collision, because the only pair it creates is A against
    //! 0.55*A, which is the band-to-unfilled contrast every ring already
    //! relies on.
    //!
    //! What does constrain a duotone is the temperature ramp. With two hues
    //! there is no third colour to turn through, so the ramp runs straight
    //! from one to the other and *that blend* is the scale's middle — where
    //! most readings sit. A complementary pair blends through grey and reads
    //! as no data at all: violet-lime drops to a chroma of 4, teal-coral to
    //! 14. These three hold 30, 40 and 27 respectively, which is what put
    //! them in and kept better-contrasting pairs out.
    //!
    //! Lagoon's gold and Nocturne's rust are deliberately the values Activity
    //! and Terrain already carry, rather than new ones a shade off them.
    //!
    //! **Alpinist** is after the Seiko Alpinist: a dark sunburst green dial
    //! under gold indices. It is the one theme here that could not be
    //! transcribed, and the reason is the medium — that dial is a surface
    //! lit from outside, while this face emits its own light on black, so
    //! the dial's own ~#1E3A2F falls below the unfilled tier and simply is
    //! not there. What carries over is the *relationship*: a cool forest
    //! green against a warm brass, taken up in luminance until the dim tier
    //! still reads.
    //!
    //! Green and gold sit close on the wheel, so this pair is the hardest of
    //! the duotones to separate — the obvious brass-on-forest choices land at
    //! 64 to 75, well under the 93 Terrain ships. The green had to move to a
    //! true leaf green and the gold toward orange to reach 94. Two things
    //! were tried and rejected on measurement: the dial's actual green (the
    //! dim tier collapses to a relative luminance of 0.012, invisible), and
    //! adding the cream lume as a third colour, which *lowers* the worst
    //! neighbour pair to 52 and pushes the field past Terrain's luminance —
    //! cream is bright and nearly achromatic, so it separates from nothing.
    //!
    //! Pushing further gets a better number and a worse theme: the top of the
    //! sweep drifts the green to teal and the gold to orange, which scores 100
    //! and lands 16 from Lagoon's teal. This green sits 41 away, which is what
    //! keeps it a different theme rather than a better-contrasting Lagoon.
    //!
    //! **Alpinist 4** is the whole watch rather than the dial: the strap and
    //! the lume join the green and the gold. It is the only four-colour theme
    //! added since Activity, and it exists because of one fact that is not
    //! obvious until it is measured.
    //!
    //! **Brown is what gold looks like unlit.** Gold at the unfilled tier is
    //! 0x8C5400; a cocoa brown is 0x8B5A2B. Those are 15 apart in CIELAB
    //! against the ~37 that separates a lit dot from an unlit one *within* a
    //! ring — so a lit brown dot and an unlit gold dot are the same colour,
    //! and a brown ring beside a gold one is unreadable. Brown is not a hue;
    //! it is dark orange, which is precisely the thing this face makes when
    //! it dims a gold. Every brown tried lands 15-24 from unlit gold.
    //!
    //! So the strap is a brick rather than a leather brown. Sweeping the brown
    //! toward red, it has to reach a hue of about 4 degrees before it clears
    //! that bar — at which point it is no longer brown. The alternative was to
    //! drop the gold and keep a true brown, which works and was rendered: it
    //! reaches only 65 between neighbours against this one's 86, and the brown
    //! ring goes muddy against the green.
    //!
    //! The white sits on the **innermost** ring on purpose. Ring order is free
    //! here, and the rings hold 436/340/244/92 dots outermost-in, so the
    //! brightest colour on the smallest ring is what keeps a white-bearing
    //! theme inside the luminance budget at all: 4.95% worst-case always-on,
    //! which is lower than Terrain.
    //!
    //! Ring 1 is the outermost.
    const THEME_COLOURS = 4;
    const THEME_COUNT = 7;
    const THEMES = [
        0xE879F9,   //! Terrain:  orchid
        0xB8D64B,   //!           moss
        0x7FD4FF,   //!           ice
        0xFF6B5B,   //!           rust
        0xE59A0A,   //! Activity: gold
        0x1F8FFE,   //!           blue
        0x6DC54F,   //!           green
        0xFE4646,   //!           red
        0x5CD9F0,   //! Frost:    cyan
        0xF45BD8,   //!           magenta
        0x5CD9F0,   //!           cyan again — see the duotone note above
        0xF45BD8,   //!           magenta
        0x2FD9C5,   //! Lagoon:   teal
        0xE59A0A,   //!           gold, the same one Activity carries
        0x2FD9C5,   //!           teal
        0xE59A0A,   //!           gold
        0x8E7BFF,   //! Nocturne: indigo
        0xFF6B5B,   //!           rust, the same one Terrain carries
        0x8E7BFF,   //!           indigo
        0xFF6B5B,   //!           rust
        0x44C265,   //! Alpinist: forest green
        0xFF9900,   //!           gold
        0x44C265,   //!           forest green
        0xFF9900,   //!           gold
        0xC75A5A,   //! Alpinist 4: brick, the strap. See the note above for
        0x44C265,   //!             why it is not brown.
        0xFF9900,   //!             gold
        0xF5F5F5    //!             white, the lume, on the innermost ring
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
    //! There is no always-on tier because there is no always-on mark: this is
    //! the most luminous thing the face can draw, and always-on is the mode
    //! measured against the burn-in budget. CrossoverView holds the mark back
    //! there the same way it holds back the hand backing.
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

    //! Temperature is drawn on a ramp so its band reads as a temperature and
    //! not just a length. Cold through a middle to hot, and every stop is one
    //! of the theme's own four colours, so it stays inside the palette.
    //! Precomputed: working it out per dot costs too much inside the frame.
    const RAMP_STEPS = 32;

    //! Which of a theme's colours the ramp runs through, flat and in cold,
    //! mid, hot order: RAMP_STOPS[theme * RAMP_POINTS + n].
    //!
    //! Indices into the theme rather than colours of their own, because a ramp
    //! stop *is* a ring colour and writing the value a second time is how the
    //! two drift apart. Named per theme rather than fixed at 2, 0, 3, because
    //! which slot holds the cold hue falls out of the ring ordering — and that
    //! ordering answers to neighbour contrast, not to keeping the ramp's
    //! indices where they were. Terrain runs ice -> orchid -> rust, Activity
    //! blue -> gold -> red.
    //! A mid stop of RAMP_LINEAR means the theme has only two hues to ramp
    //! through, so the middle is the midpoint of cold and hot rather than a
    //! colour of its own — the two segments become one straight run. It is a
    //! sentinel rather than a fourth colour because a duotone genuinely has
    //! no third stop to name, and inventing one here would be writing a
    //! colour value in the one table that exists to avoid exactly that.
    const RAMP_LINEAR = -1;

    //! The -1s below are RAMP_LINEAR, written as a literal on purpose. Naming
    //! the const inside a const array's initialiser is the same shape as the
    //! nested const array that resolves in the simulator and comes back empty
    //! on the watch, and an empty RAMP_STOPS would not draw wrong — it would
    //! index out of bounds and the face would not load. Not worth finding out
    //! on the device. RAMP_LINEAR is still the name everything compares
    //! against, which is a runtime read and safe.
    const RAMP_POINTS = 3;
    const RAMP_STOPS = [
        2, 0, 3,                    //! Terrain:  ice -> orchid -> rust
        1, 0, 3,                    //! Activity: blue -> gold -> red
        0, -1, 1,                   //! Frost:    cyan -> magenta
        0, -1, 1,                   //! Lagoon:   teal -> gold
        0, -1, 1,                   //! Nocturne: indigo -> rust
        0, -1, 1,                   //! Alpinist: green -> gold
        1, 2, 0                     //! Alpinist 4: green -> gold -> brick
    ] as Array<Number>;

    var active as Array<Number> = [] as Array<Number>;
    var alwaysOn as Array<Number> = [] as Array<Number>;
    var heldBack as Array<Number> = [] as Array<Number>;

    //! The mark's colour on each ring. One entry per ring, not per slot.
    var markerOf as Array<Number> = [] as Array<Number>;

    //! The second lap's colour on each ring — what a ring past its goal draws
    //! where it would otherwise draw the plain filled colour. One entry per
    //! ring, not per slot: the renderer swaps it into the ring's filled slot
    //! for the frame, so the dot loop still reads exactly two colours.
    //!
    //! Awake only, like markerOf and for the same reason, so there is no
    //! always-on tier to keep in step.
    var overOf as Array<Number> = [] as Array<Number>;

    //! The unknown-hour tier on each ring. One entry per ring, not per slot —
    //! the same shape as markerOf and overOf, and for the same reason: it is a
    //! third colour the renderer swaps in, not a fourth palette slot, so the
    //! ring * 2 + lit indexing every other table and test uses is untouched.
    //!
    //! One table for both power modes, because LIFT is 1.0 and an always-on
    //! variant would be a duplicate of this one. If LIFT ever moves off 1.0
    //! this owes a second table, exactly as heldBack does.
    var dimOf as Array<Number> = [] as Array<Number>;
    var rampActive as Array<Number> = [] as Array<Number>;
    var rampAlwaysOn as Array<Number> = [] as Array<Number>;

    //! One colour of the theme in force, by its index within that theme.
    function themeColour(index as Number) as Number {
        return THEMES[(StatMap.theme * THEME_COLOURS) +
                      (index % THEME_COLOURS)];
    }

    function build() as Void {
        var awake = [] as Array<Number>;
        var asleep = [] as Array<Number>;
        var held = [] as Array<Number>;
        var marks = [] as Array<Number>;
        var beyond = [] as Array<Number>;
        var faint = [] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var colour = themeColour(ring);
            marks.add(mix(MARKER, colour, MARKER_TINT));
            faint.add(scale(colour, WEAK_UNKNOWN));
            beyond.add(mix(MARKER, colour, OVER_TINT));
            var lifted = scale(colour, LIFT);
            awake.add(scale(colour, WEAK_ACTIVE));
            awake.add(colour);
            asleep.add(scale(lifted, WEAK_ALWAYS_ON));
            asleep.add(lifted);
            // Unfilled from the awake colour, because matching the awake field
            // is the whole point of this tier and that must hold whatever LIFT
            // does. Filled from the lifted one, because this table draws in
            // always-on — no dot is lit while the fills are held back, but a
            // table that is merely unreachable should still be right.
            held.add(scale(colour, WEAK_HELD_BACK));
            held.add(lifted);
        }
        active = awake;
        alwaysOn = asleep;
        heldBack = held;
        markerOf = marks;
        overOf = beyond;
        dimOf = faint;

        var ramp = [] as Array<Number>;
        var rampLifted = [] as Array<Number>;
        // Hoisted: the stops are fixed for the whole ramp, so looking them up
        // per step would pay for the indirection 32 times over for nothing.
        var stops = StatMap.theme * RAMP_POINTS;
        var cold = themeColour(RAMP_STOPS[stops]);
        var hot = themeColour(RAMP_STOPS[stops + 2]);
        // Branch before themeColour rather than inside it: the sentinel is not
        // an index, and themeColour would wrap it into a real slot.
        var midStop = RAMP_STOPS[stops + 1];
        var mid = (midStop == RAMP_LINEAR)
            ? mix(cold, hot, 0.5)
            : themeColour(midStop);
        for (var step = 0; step < RAMP_STEPS; step++) {
            var along = step.toFloat() / (RAMP_STEPS - 1);
            var colour = (along <= 0.5)
                ? mix(cold, mid, along * 2.0)
                : mix(mid, hot, (along - 0.5) * 2.0);
            ramp.add(colour);
            rampLifted.add(scale(colour, LIFT));
        }
        rampActive = ramp;
        rampAlwaysOn = rampLifted;
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
