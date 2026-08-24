import Toybox.Lang;

//! Colour for every dot state, in both power modes.
//!
//! Placeholder theme: rings alternate between navy and olive rather than each
//! carrying a hue of its own. Proper themes come later.
//!
//! The filled portion carries the colour at full read; the unfilled portion is
//! the same colour dark enough to tint the field without reading as lit.
//! Always-on dims both tiers by a constant, which is what keeps the two modes
//! looking like the same image rather than two designs.
//!
//! Both tables are indexed by ring * 2, plus 1 when lit.
module Palette {

    //! Navy and olive, tuned for AMOLED rather than for a paint chart.
    //!
    //! The trick on a black panel is to spend the budget on *chroma* rather
    //! than brightness: these sit at 25% and 38% luminance but 51% and 33%
    //! chroma, so they read as deep saturated colour against true black
    //! instead of as washed-out pastels. Lifting the brightness instead — an
    //! earlier attempt — turned the navy into a medium blue.
    //!
    //! Olive is naturally the brighter of the two (yellow-green carries far
    //! more luma than blue), so it is deliberately drabbed down to keep the
    //! pair within about 1.5x of each other.
    const THEME = [0x1D3F9E, 0x5C6A16] as Array<Number>;   //! navy, olive

    //! Unfilled tier, relative to the colour. Awake gets the brighter of the
    //! two: at full panel brightness a very dark tint reads as nothing at all,
    //! and the point of the design is that every dot carries its ring's colour.
    const WEAK_ACTIVE = 0.42;
    const WEAK_ALWAYS_ON = 0.30;

    //! Always-on *lifts* the colours rather than dimming them.
    //!
    //! This looks backwards until you account for the panel: the system already
    //! drops screen brightness in always-on, so rendering darker values on top
    //! of that compounds into near-invisibility. Raising the values compensates,
    //! and the frame still lands around 3% against a 10% burn-in budget.
    //! Awake needs no such correction, so it draws the colours as they are.
    const LIFT = 1.5;

    //! Backing drawn under the analogue hands when that option is on.
    const BACKING_WHITE = 0xFFFFFF;
    const BACKING_DARK = 0x101010;

    //! Temperature is drawn on a ramp so its band reads as a temperature and
    //! not just a length. The ramp runs between the theme's two colours, so it
    //! stays inside the palette instead of importing a rainbow.
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
            var colour = mix(THEME[0], THEME[1],
                             step.toFloat() / (RAMP_STEPS - 1));
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
