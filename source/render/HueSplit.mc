import Toybox.Lang;
import Toybox.Math;

//! Two colours that read as mixing into a third: its hue turned the same way
//! each side, at its own lightness.
//!
//! The overlapping time ring is drawn in these. Its ring's own theme colour is
//! where hour and minute have both passed; the hour is that hue turned back by
//! `degrees` and the minute turned on, so the three read as a family on any
//! theme, a custom one included, with no table of pairs to keep.
//!
//! **In OKLCH, not HSV.** OKLCH's lightness is perceptual, so the pair keeps
//! the ring's own lightness and neither half outshines the other. The HSV split
//! shipped first kept HSV's value, the brightest channel, which is not what the
//! eye sees: Activity's red split into a magenta hour and a far brighter yellow
//! minute. A turned hue the screen cannot show at that lightness keeps its hue
//! and gives up chroma (fit()), rather than clipping a channel and shifting.
//! Chosen on the mockups, after a playground the concept was sketched in.
//!
//! Run once a Palette.build(), never per dot, in Doubles so tools/mockup.py and
//! the web configurator — which mirror this — agree with it to a unit a channel.
module HueSplit {

    //! [turned back, turned on] for `colour`, a packed 0xRRGGBB.
    //!
    //! Chroma is raised to at least `floor`: a pale colour has almost no hue
    //! to turn, and its pair would come out the same grey.
    function pair(colour as Number, degrees as Float,
                  floor as Float) as Array<Number> {
        var lch = toOklch(colour);
        var lightness = lch[0];
        var chroma = (lch[1] < floor) ? floor.toDouble() : lch[1];
        var out = new [2] as Array<Number>;
        for (var side = 0; side < 2; side++) {
            var hue = lch[2] + ((side == 0) ? -degrees : degrees);
            hue = hue - 360.0d * Math.floor(hue / 360.0d);
            out[side] = fromOklch(lightness, fit(lightness, chroma, hue), hue);
        }
        return out;
    }

    //! `colour` lightened `amount` of the way to white in OKLCH: hue kept, and
    //! chroma kept wherever the screen can show it at the new lightness.
    //!
    //! The always-on boost (Palette.boost). Perceptual lightness rather than a
    //! channel multiply, because a theme colour already sits at a full channel
    //! and multiplying would clamp it and turn the hue; and rather than a mix
    //! toward white, which greys every colour by the same share whatever it
    //! needed. A dark colour gains the most, a light one little.
    function lighten(colour as Number, amount as Double) as Number {
        var lch = toOklch(colour);
        var lightness = lch[0] + amount * (1.0d - lch[0]);
        return fromOklch(lightness, fit(lightness, lch[1], lch[2]), lch[2]);
    }

    //! [lightness, chroma, hue in degrees].
    function toOklch(colour as Number) as Array<Double> {
        var r = linear(((colour >> 16) & 0xFF) / 255.0d);
        var g = linear(((colour >> 8) & 0xFF) / 255.0d);
        var b = linear((colour & 0xFF) / 255.0d);
        var l = cubeRoot(0.4122214708d * r + 0.5363325363d * g + 0.0514459929d * b);
        var m = cubeRoot(0.2119034982d * r + 0.6806995451d * g + 0.1073969566d * b);
        var s = cubeRoot(0.0883024619d * r + 0.2817188376d * g + 0.6299787005d * b);
        var lightness = 0.2104542553d * l + 0.7936177850d * m - 0.0040720468d * s;
        var a = 1.9779984951d * l - 2.4285922050d * m + 0.4505937099d * s;
        var bb = 0.0259040371d * l + 0.7827717662d * m - 0.8086757660d * s;
        var hue = Math.toDegrees(Math.atan2(bb, a));
        hue = hue - 360.0d * Math.floor(hue / 360.0d);
        return [lightness, Math.sqrt(a * a + bb * bb), hue] as Array<Double>;
    }

    //! Linear sRGB for an OKLCH colour, possibly outside 0..1.
    function linearRgb(lightness as Double, chroma as Double,
                       hue as Double) as Array<Double> {
        var radians = Math.toRadians(hue);
        var a = chroma * Math.cos(radians);
        var b = chroma * Math.sin(radians);
        var l = cube(lightness + 0.3963377774d * a + 0.2158037573d * b);
        var m = cube(lightness - 0.1055613458d * a - 0.0638541728d * b);
        var s = cube(lightness - 0.0894841775d * a - 1.2914855480d * b);
        return [4.0767416621d * l - 3.3077115913d * m + 0.2309699292d * s,
                -1.2684380046d * l + 2.6097574011d * m - 0.3413193965d * s,
                -0.0041960863d * l - 0.7034186147d * m + 1.7076147010d * s]
               as Array<Double>;
    }

    //! The most chroma, up to `chroma`, the screen can show at this lightness
    //! and hue. Bisected: 24 halvings is well under a unit a channel.
    function fit(lightness as Double, chroma as Double,
                 hue as Double) as Double {
        if (inGamut(linearRgb(lightness, chroma, hue))) {
            return chroma;
        }
        var low = 0.0d;
        var high = chroma;
        for (var i = 0; i < 24; i++) {
            var mid = (low + high) / 2.0d;
            if (inGamut(linearRgb(lightness, mid, hue))) {
                low = mid;
            } else {
                high = mid;
            }
        }
        return low;
    }

    function inGamut(rgb as Array<Double>) as Boolean {
        for (var i = 0; i < 3; i++) {
            if (rgb[i] < -0.0001d || rgb[i] > 1.0001d) {
                return false;
            }
        }
        return true;
    }

    //! Packed 0xRRGGBB for an OKLCH colour inside the gamut.
    function fromOklch(lightness as Double, chroma as Double,
                       hue as Double) as Number {
        var rgb = linearRgb(lightness, chroma, hue);
        return (toByte(rgb[0]) << 16) | (toByte(rgb[1]) << 8) | toByte(rgb[2]);
    }

    //! A linear channel as an sRGB byte, rounded half up — the mirrors' rounding.
    function toByte(x as Double) as Number {
        var clamped = (x < 0.0d) ? 0.0d : ((x > 1.0d) ? 1.0d : x);
        var encoded = (clamped <= 0.0031308d)
            ? 12.92d * clamped
            : 1.055d * Math.pow(clamped, 1.0d / 2.4d) - 0.055d;
        var byte = Math.floor(encoded * 255.0d + 0.5d).toNumber();
        return (byte < 0) ? 0 : ((byte > 255) ? 255 : byte);
    }

    function linear(c as Double) as Double {
        return (c <= 0.04045d) ? c / 12.92d
                               : Math.pow((c + 0.055d) / 1.055d, 2.4d).toDouble();
    }

    function cubeRoot(x as Double) as Double {
        return (x <= 0.0d) ? 0.0d : Math.pow(x, 1.0d / 3.0d).toDouble();
    }

    function cube(x as Double) as Double {
        return x * x * x;
    }
}
