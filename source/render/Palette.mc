import Toybox.Lang;

//! Colour for every dot state, in both power modes.
//!
//! One hue per stat. The filled portion carries the hue at full read; the
//! unfilled portion is the same hue dark enough to tint the field without
//! reading as lit. Always-on dims both tiers by a constant, which is what keeps
//! the two modes looking like the same image rather than two designs.
//!
//! Both tables are indexed by StatMap.classify(): stat * 2, plus 1 when filled.
module Palette {

    const WEAK = 0.18;          //! Unfilled tier, relative to the hue.
    const DIM = 0.45;           //! Always-on, applied on top of either tier.

    //! Backing drawn under the analogue hands when that option is on.
    //! White silhouettes the hands' dark outlines; dark lets the white hour
    //! hand shine. Which reads better is a matter for the wrist, so both ship.
    const BACKING_WHITE = 0xFFFFFF;
    const BACKING_DARK = 0x101010;

    //! Weather ring. The temperature band is tinted along a cold-to-hot ramp
    //! so the arc reads as a temperature, not just a length. Rain gets a hue
    //! of its own, kept away from the four stat hues.
    const TEMP_COLD = 0x3366FF;
    const TEMP_MILD = 0xFFAA00;
    const TEMP_HOT = 0xFF2200;
    const RAIN = 0x00CCDD;

    //! Every colour the face can draw. Built once — see build().
    var active as Array<Number> = [] as Array<Number>;
    var alwaysOn as Array<Number> = [] as Array<Number>;

    function build() as Void {
        var lit = [] as Array<Number>;
        var dimmed = [] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var hue = Source.hue(StatMap.rings[ring]);
            var weak = scale(hue, WEAK);
            lit.add(weak);
            lit.add(hue);
            dimmed.add(scale(weak, DIM));
            dimmed.add(scale(hue, DIM));
        }
        active = lit;
        alwaysOn = dimmed;
    }

    //! Colour for a point on the temperature scale, 0.0 cold to 1.0 hot.
    function temperature(fraction as Float) as Number {
        if (fraction <= 0.5) {
            return mix(TEMP_COLD, TEMP_MILD, fraction * 2.0);
        }
        return mix(TEMP_MILD, TEMP_HOT, (fraction - 0.5) * 2.0);
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

    //! Multiply each channel of a packed RGB colour.
    function scale(colour as Number, factor as Float) as Number {
        var r = (((colour >> 16) & 0xFF) * factor).toNumber();
        var g = (((colour >> 8) & 0xFF) * factor).toNumber();
        var b = ((colour & 0xFF) * factor).toNumber();
        return (r << 16) | (g << 8) | b;
    }
}
