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

    //! Steps, heart rate, battery, body battery.
    const HUES = [0xFF6600, 0xFF3322, 0x33CC55, 0x3388FF] as Array<Number>;

    const WEAK = 0.18;          //! Unfilled tier, relative to the hue.
    const DIM = 0.45;           //! Always-on, applied on top of either tier.

    //! Backing drawn under the analogue hands when that option is on.
    //! White silhouettes the hands' dark outlines; dark lets the white hour
    //! hand shine. Which reads better is a matter for the wrist, so both ship.
    const BACKING_WHITE = 0xFFFFFF;
    const BACKING_DARK = 0x101010;

    //! Every colour the face can draw. Built once — see build().
    var active as Array<Number> = [] as Array<Number>;
    var alwaysOn as Array<Number> = [] as Array<Number>;

    function build() as Void {
        var lit = [] as Array<Number>;
        var dimmed = [] as Array<Number>;
        for (var stat = 0; stat < HUES.size(); stat++) {
            var hue = HUES[stat];
            var weak = scale(hue, WEAK);
            lit.add(weak);
            lit.add(hue);
            dimmed.add(scale(weak, DIM));
            dimmed.add(scale(hue, DIM));
        }
        active = lit;
        alwaysOn = dimmed;
    }

    //! Multiply each channel of a packed RGB colour.
    function scale(colour as Number, factor as Float) as Number {
        var r = (((colour >> 16) & 0xFF) * factor).toNumber();
        var g = (((colour >> 8) & 0xFF) * factor).toNumber();
        var b = ((colour & 0xFF) * factor).toNumber();
        return (r << 16) | (g << 8) | b;
    }
}
