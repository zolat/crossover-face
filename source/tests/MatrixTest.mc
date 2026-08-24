import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

//! Tests for the parts of the face that can be checked without a screen: the
//! lattice, the dot -> stat mapping, and the always-on luminance budget.
//!
//! The dot count is asserted against the figure the Python mockup produces from
//! the same constants (tools/mockup.py), so the two implementations cannot
//! drift apart silently — the mockups stay an honest preview of the face.
module MatrixTest {

    const EXPECTED_DOTS = 572;

    //! Garmin blanks an always-on face above this share of screen luminance.
    const BUDGET = 0.10;

    //! Rec. 709 luma coefficients, matching tools/luminance.py.
    const LUMA_R = 0.2126;
    const LUMA_G = 0.7152;
    const LUMA_B = 0.0722;

    function relativeLuminance(colour as Number) as Float {
        var r = (colour >> 16) & 0xFF;
        var g = (colour >> 8) & 0xFF;
        var b = colour & 0xFF;
        return (LUMA_R * r + LUMA_G * g + LUMA_B * b) / 255.0;
    }

    //! Mean luminance of a whole frame, as a fraction of full white over the
    //! round screen area — the quantity Garmin's rule is written against.
    function frameLuminance(values as Array<Float>, palette as Array<Number>) as Float {
        var total = 0.0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                var slot = StatMap.classify(col, dx, dy, values);
                total += relativeLuminance(palette[slot]) * DotGrid.DOT * DotGrid.DOT;
            }
        }
        var screen = Math.PI * DotGrid.RADIUS * DotGrid.RADIUS;
        return total / screen;
    }

    (:test)
    function latticeMatchesMockup(logger as Logger) as Boolean {
        var count = 0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            for (var col = 0; col < DotGrid.COLS; col++) {
                if (DotGrid.contains(DotGrid.offsetAt(col), DotGrid.offsetAt(row))) {
                    count++;
                }
            }
        }
        logger.debug("dots in lattice: " + count);
        Test.assertEqualMessage(count, EXPECTED_DOTS,
            "lattice drifted from the mockup model");
        return true;
    }

    (:test)
    function hubIsExcluded(logger as Logger) as Boolean {
        Test.assertMessage(!DotGrid.contains(0, 0), "centre must be empty");
        Test.assertMessage(!DotGrid.contains(DotGrid.HUB - 1, 0),
            "inside the hub must be empty");
        Test.assertMessage(DotGrid.contains(DotGrid.HUB + 7, 0),
            "just outside the hub must have dots");
        return true;
    }

    (:test)
    function cornersAreClipped(logger as Logger) as Boolean {
        Test.assertMessage(!DotGrid.contains(189, 189), "corner must be clipped");
        Test.assertMessage(DotGrid.contains(0, 189), "rim must have dots");
        return true;
    }

    //! Empty and full are the two states a gauge must get exactly right.
    (:test)
    function fillEndpoints(logger as Logger) as Boolean {
        var empty = [0.0, 0.0, 0.0, 0.0] as Array<Float>;
        var full = [1.0, 1.0, 1.0, 1.0] as Array<Float>;

        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                Test.assertMessage(StatMap.classify(col, dx, dy, empty) % 2 == 0,
                    "nothing may read as filled at 0%");
                Test.assertMessage(StatMap.classify(col, dx, dy, full) % 2 == 1,
                    "everything must read as filled at 100%");
            }
        }
        return true;
    }

    //! Every stat at 100% is the brightest frame the face can ever draw. If
    //! that fits the budget, no real reading can blank the screen.
    (:test)
    function alwaysOnWorstCaseFitsBudget(logger as Logger) as Boolean {
        Palette.build();
        var worst = frameLuminance([1.0, 1.0, 1.0, 1.0] as Array<Float>,
                                   Palette.alwaysOn);
        logger.debug("worst-case always-on luminance: " + worst);
        Test.assertMessage(worst < BUDGET,
            "always-on worst case exceeds the AMOLED burn-in budget");
        return true;
    }

    //! Always-on must be strictly dimmer than awake, or the dimming is a no-op.
    (:test)
    function alwaysOnIsDimmerThanActive(logger as Logger) as Boolean {
        Palette.build();
        var values = [0.68, 0.55, 0.82, 0.40] as Array<Float>;
        var awake = frameLuminance(values, Palette.active);
        var asleep = frameLuminance(values, Palette.alwaysOn);
        logger.debug("active " + awake + " / always-on " + asleep);
        Test.assertMessage(asleep < awake, "always-on is not dimmer than active");
        return true;
    }
}
