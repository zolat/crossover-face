import Toybox.Lang;
import Toybox.Math;

//! Two colours that read as mixing into a third: its hue turned the same way
//! each side, the way blue and red sit either side of purple.
//!
//! The overlapping time ring is drawn in these. Its ring's own theme colour is
//! where hour and minute have both passed; the hour is that hue turned back by
//! `degrees` and the minute turned on, so the three read as a family on any
//! theme, a custom one included, with no table of pairs to keep.
//!
//! Run once a Palette.build(), never per dot. HSV in the formulation Python's
//! colorsys uses, so tools/mockup.py and the web configurator — which mirror
//! this — agree with it to a unit per channel.
module HueSplit {

    //! [turned back, turned on] for `colour`, a packed 0xRRGGBB.
    //!
    //! Saturation is raised to at least `floor`: a pale colour has almost no
    //! hue to turn, and its pair would come out the same grey. Value is kept,
    //! so the pair is as bright as the theme made the ring.
    function pair(colour as Number, degrees as Float,
                  floor as Float) as Array<Number> {
        var hsv = toHsv(colour);
        var s = (hsv[1] < floor) ? floor : hsv[1];
        var turn = degrees / 360.0;
        return [fromHsv(wrap(hsv[0] - turn), s, hsv[2]),
                fromHsv(wrap(hsv[0] + turn), s, hsv[2])] as Array<Number>;
    }

    //! [hue in turns, saturation, value], each 0..1.
    function toHsv(colour as Number) as Array<Float> {
        var r = ((colour >> 16) & 0xFF) / 255.0;
        var g = ((colour >> 8) & 0xFF) / 255.0;
        var b = (colour & 0xFF) / 255.0;
        var high = (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b);
        var low = (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b);
        if (high == low) {
            return [0.0, 0.0, high] as Array<Float>;
        }
        var span = high - low;
        var rc = (high - r) / span;
        var gc = (high - g) / span;
        var bc = (high - b) / span;
        var h;
        if (r == high) {
            h = bc - gc;
        } else if (g == high) {
            h = 2.0 + rc - bc;
        } else {
            h = 4.0 + gc - rc;
        }
        return [wrap(h / 6.0), span / high, high] as Array<Float>;
    }

    //! Packed 0xRRGGBB from hue in turns, saturation and value.
    function fromHsv(h as Float, s as Float, v as Float) as Number {
        var sixth = h * 6.0;
        var i = sixth.toNumber();
        var f = sixth - i;
        var p = v * (1.0 - s);
        var q = v * (1.0 - s * f);
        var t = v * (1.0 - s * (1.0 - f));
        i = i % 6;
        var rgb;
        if (i == 0) {
            rgb = [v, t, p];
        } else if (i == 1) {
            rgb = [q, v, p];
        } else if (i == 2) {
            rgb = [p, v, t];
        } else if (i == 3) {
            rgb = [p, q, v];
        } else if (i == 4) {
            rgb = [t, p, v];
        } else {
            rgb = [v, p, q];
        }
        return (toByte(rgb[0] as Float) << 16) |
               (toByte(rgb[1] as Float) << 8) |
                toByte(rgb[2] as Float);
    }

    //! A 0..1 channel as a byte, rounded half up — the rounding the mirrors use.
    function toByte(x as Float) as Number {
        var byte = Math.floor(x * 255.0 + 0.5).toNumber();
        return (byte < 0) ? 0 : ((byte > 255) ? 255 : byte);
    }

    //! A hue folded back into 0..1.
    function wrap(h as Float) as Float {
        while (h < 0.0) {
            h += 1.0;
        }
        while (h >= 1.0) {
            h -= 1.0;
        }
        return h;
    }
}
