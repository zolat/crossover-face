import Toybox.Lang;

//! Colour for every dot state, in both power modes.
//!
//! One colour per ring, from a fixed theme. The filled portion carries the
//! colour at full read; the unfilled portion is the same colour dimmed enough
//! to tint the field without reading as lit. Awake and always-on share their
//! filled colours and differ only in that unfilled tier, which is what keeps
//! the two modes looking like the same image rather than two designs.
//!
//! Both tables are indexed by ring * 2, plus 1 when lit.
module Palette {

    //! Terrain: amber, ice, rust, moss. Bright and saturated, because tuned in
    //! a dark room the face was legible and outdoors in daylight it was not.
    //!
    //! The order is not decorative. Amber and rust are by far the closest pair
    //! in the set — 40 apart in CIELAB, against 90-98 for every other pair — so
    //! they are deliberately kept non-adjacent. Interleaving warm and cool this
    //! way lifts the *weakest neighbouring pair* from 40 to 90, and it is
    //! neighbours blurring together, not the set average, that decides whether
    //! two rings can be told apart at a glance.
    //!
    //! Ring 1 is outermost, or leftmost in the band layouts.
    const THEME = [
        0xFFA94D,   //! amber
        0x7FD4FF,   //! ice
        0xFF6B5B,   //! rust
        0xB8D64B    //! moss
    ] as Array<Number>;

    const WEAK_ACTIVE = 0.55;
    const WEAK_ALWAYS_ON = 0.45;

    //! Always-on used to lift the colours to survive the panel's own dimming.
    //! With this palette there is nothing left to lift: ice and moss are
    //! already at or near a full channel, so scaling up would clamp and shift
    //! the hue rather than brighten it. Always-on and awake now draw the same
    //! filled colours and differ only in their unfilled tier — which is what
    //! "minimal change between modes" wanted in the first place.
    const LIFT = 1.0;

    //! Backing drawn under the analogue hands when that option is on.
    const BACKING_WHITE = 0xFFFFFF;
    const BACKING_DARK = 0x101010;

    //! Temperature is drawn on a ramp so its band reads as a temperature and
    //! not just a length. Ice through amber to rust — cold to hot, and every
    //! stop is a theme colour, so it stays inside the palette.
    //! Precomputed: working it out per dot costs too much inside the frame.
    const RAMP_STEPS = 32;

    var active as Array<Number> = [] as Array<Number>;
    var alwaysOn as Array<Number> = [] as Array<Number>;
    var rampActive as Array<Number> = [] as Array<Number>;
    var rampAlwaysOn as Array<Number> = [] as Array<Number>;

    function build() as Void {
        var awake = [] as Array<Number>;
        var asleep = [] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var colour = THEME[ring % THEME.size()];
            var lifted = scale(colour, LIFT);
            awake.add(scale(colour, WEAK_ACTIVE));
            awake.add(colour);
            asleep.add(scale(lifted, WEAK_ALWAYS_ON));
            asleep.add(lifted);
        }
        active = awake;
        alwaysOn = asleep;

        var ramp = [] as Array<Number>;
        var rampLifted = [] as Array<Number>;
        for (var step = 0; step < RAMP_STEPS; step++) {
            var along = step.toFloat() / (RAMP_STEPS - 1);
            var colour = (along <= 0.5)
                ? mix(THEME[1], THEME[0], along * 2.0)           // ice -> amber
                : mix(THEME[0], THEME[2], (along - 0.5) * 2.0);  // amber -> rust
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
