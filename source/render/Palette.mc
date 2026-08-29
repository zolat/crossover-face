import Toybox.Lang;

//! Colour for every dot state, in both power modes.
//!
//! One colour per ring, from a fixed theme. The filled portion carries the
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

    //! Terrain: orchid, moss, ice, rust. Bright and saturated, because tuned in
    //! a dark room the face was legible and outdoors in daylight it was not.
    //!
    //! Orchid replaces an amber that looked right at full strength and turned
    //! brown the moment it was dimmed for the unfilled tier. That tier covers
    //! most of a ring most of the time, so how a colour *dims* matters as much
    //! as how it looks lit — and warm oranges dim to mud while violets stay
    //! chromatic. Orchid holds a CIELAB chroma of 47 when dimmed, against
    //! amber's 39 of brown.
    //!
    //! The order is not decorative: it is the arrangement that maximises the
    //! distance between rings which sit *next to* each other, 93 here against
    //! 78 for the worst arrangement. Neighbours blurring together, not the set
    //! average, is what decides whether two rings can be told apart.
    //!
    //! Ring 1 is the outermost.
    const THEME = [
        0xE879F9,   //! orchid
        0xB8D64B,   //! moss
        0x7FD4FF,   //! ice
        0xFF6B5B    //! rust
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
    //! Near-white, carrying a third of the colour of the band it sits in. It
    //! was pure white, on the reasoning that every ramp stop is saturated so
    //! only an unsaturated colour reads as a marker rather than as more data.
    //! That is true but it overshot: pure white read as a hole punched through
    //! the field rather than a point on it.
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
    const MARKER = 0xFFFFFF;
    const MARKER_TINT = 0.35;

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
    //! not just a length. Ice through orchid to rust — cold to hot, and every
    //! stop is a theme colour, so it stays inside the palette.
    //! Precomputed: working it out per dot costs too much inside the frame.
    const RAMP_STEPS = 32;

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
    var rampActive as Array<Number> = [] as Array<Number>;
    var rampAlwaysOn as Array<Number> = [] as Array<Number>;

    function build() as Void {
        var awake = [] as Array<Number>;
        var asleep = [] as Array<Number>;
        var held = [] as Array<Number>;
        var marks = [] as Array<Number>;
        var beyond = [] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var colour = THEME[ring % THEME.size()];
            marks.add(mix(MARKER, colour, MARKER_TINT));
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

        var ramp = [] as Array<Number>;
        var rampLifted = [] as Array<Number>;
        for (var step = 0; step < RAMP_STEPS; step++) {
            var along = step.toFloat() / (RAMP_STEPS - 1);
            var colour = (along <= 0.5)
                ? mix(THEME[2], THEME[0], along * 2.0)            // ice -> orchid
                : mix(THEME[0], THEME[3], (along - 0.5) * 2.0);   // orchid -> rust
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
