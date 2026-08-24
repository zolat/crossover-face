import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

//! Tests for the parts of the face that can be checked without a screen: the
//! lattice, the dot -> ring mapping, the burn-in drift and the always-on
//! luminance budget.
//!
//! The dot count is asserted against the figure the Python mockup produces
//! from the same constants (tools/mockup.py), so the two implementations
//! cannot drift apart silently — the mockups stay an honest preview.
module MatrixTest {

    const EXPECTED_DOTS = 572;

    //! Garmin blanks an always-on face above this share of screen luminance.
    const BUDGET = 0.10;

    //! Rec. 709 luma coefficients, matching tools/luminance.py.
    const LUMA_R = 0.2126;
    const LUMA_G = 0.7152;
    const LUMA_B = 0.0722;

    const ALL_LAYOUTS = [
        StatMap.LAYOUT_BANDS_BOTTOM,
        StatMap.LAYOUT_BANDS_CENTRE,
        StatMap.LAYOUT_RINGS
    ] as Array<Number>;

    function everySpan(start as Float, end as Float) as Array<Array<Float> > {
        var out = new [StatMap.RINGS] as Array<Array<Float> >;
        for (var i = 0; i < StatMap.RINGS; i++) {
            out[i] = [start, end] as Array<Float>;
        }
        return out;
    }

    function relativeLuminance(colour as Number) as Float {
        var r = (colour >> 16) & 0xFF;
        var g = (colour >> 8) & 0xFF;
        var b = colour & 0xFF;
        return (LUMA_R * r + LUMA_G * g + LUMA_B * b) / 255.0;
    }

    //! Mean luminance of a whole frame as a fraction of full white over the
    //! round screen — the quantity Garmin's rule is written against.
    function frameLuminance(spans as Array<Array<Float> >,
                            palette as Array<Number>) as Float {
        var total = 0.0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                var slot = StatMap.classify(col, dx, dy, spans);
                total += relativeLuminance(palette[slot]) * DotGrid.DOT * DotGrid.DOT;
            }
        }
        return total / (Math.PI * DotGrid.RADIUS * DotGrid.RADIUS);
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

    //! Empty and full are the two states every layout must get exactly right,
    //! and the two a gauge is most likely to get wrong.
    (:test)
    function spanEndpoints(logger as Logger) as Boolean {
        var empty = everySpan(0.0, 0.0);
        var full = everySpan(0.0, 1.0);
        for (var i = 0; i < ALL_LAYOUTS.size(); i++) {
            StatMap.layout = ALL_LAYOUTS[i];
            logger.debug("layout " + StatMap.layout);
            for (var row = 0; row < DotGrid.ROWS; row++) {
                var dy = DotGrid.offsetAt(row);
                for (var col = 0; col < DotGrid.COLS; col++) {
                    var dx = DotGrid.offsetAt(col);
                    if (!DotGrid.contains(dx, dy)) {
                        continue;
                    }
                    Test.assertMessage(StatMap.classify(col, dx, dy, empty) % 2 == 0,
                        "nothing may read as lit at 0%");
                    Test.assertMessage(StatMap.classify(col, dx, dy, full) % 2 == 1,
                        "everything must read as lit at 100%");
                }
            }
        }
        StatMap.layout = StatMap.LAYOUT_BANDS_BOTTOM;
        return true;
    }

    //! A range source must light only between its ends — that is the whole
    //! point of spans, and what lets temperature share the layouts with levels.
    (:test)
    function rangeLightsOnlyBetweenItsEnds(logger as Logger) as Boolean {
        var band = everySpan(0.4, 0.6);
        var below = 0;
        var inside = 0;
        var above = 0;
        StatMap.layout = StatMap.LAYOUT_BANDS_BOTTOM;

        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                var position = StatMap.positionOf(dx, dy);
                var lit = (StatMap.classify(col, dx, dy, band) % 2) == 1;
                if (position < 0.4) {
                    below++;
                    Test.assertMessage(!lit, "below the range must stay unlit");
                } else if (position > 0.6) {
                    above++;
                    Test.assertMessage(!lit, "above the range must stay unlit");
                } else {
                    inside++;
                    Test.assertMessage(lit, "inside the range must be lit");
                }
            }
        }
        logger.debug("below " + below + " inside " + inside + " above " + above);
        Test.assertMessage(below > 0 && inside > 0 && above > 0,
            "the test range must actually straddle the field");
        return true;
    }

    //! Every ring can be assigned any source, and an unassigned ring is dark.
    (:test)
    function ringsAreIndependentlyAssignable(logger as Logger) as Boolean {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[ring],
                                Source.SOURCE_TEMPERATURE);
        }
        Config.reload();
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(StatMap.rings[ring], Source.SOURCE_TEMPERATURE,
                "ring assignment did not survive a reload");
        }

        Properties.setValue(StatMap.PROPERTY_RINGS[0], 99);
        Config.reload();
        Test.assertEqualMessage(StatMap.rings[0], Source.SOURCE_STEPS,
            "an out-of-range source must fall back to the default");

        Test.assertEqualMessage(Source.span(Source.SOURCE_OFF)[1], 0.0,
            "an off ring must have an empty span");

        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[ring], ring);
        }
        Config.reload();
        return true;
    }

    //! The temperature scale: 0C at the ring's origin, 45C at its end.
    (:test)
    function temperatureScaleSpansZeroToFortyFive(logger as Logger) as Boolean {
        Test.assertEqualMessage(WeatherData.fraction(0.0), 0.0,
            "0C must sit at the start of the scale");
        Test.assertEqualMessage(WeatherData.fraction(45.0), 1.0,
            "45C must sit at the end of the scale");
        var middle = WeatherData.fraction(22.5);
        Test.assertMessage(middle > 0.49 && middle < 0.51,
            "22.5C must sit halfway");
        Test.assertEqualMessage(WeatherData.fraction(-10.0), 0.0,
            "below the scale must clamp, not wrap");
        Test.assertEqualMessage(WeatherData.fraction(60.0), 1.0,
            "above the scale must clamp, not wrap");
        return true;
    }

    (:test)
    function layoutSettingIsClamped(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_LAYOUT, 99);
        Config.reload();
        Test.assertEqualMessage(StatMap.layout, StatMap.LAYOUT_BANDS_BOTTOM,
            "out-of-range layout must fall back to the default");

        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_RINGS);
        Config.reload();
        Test.assertEqualMessage(StatMap.layout, StatMap.LAYOUT_RINGS,
            "a valid layout must be honoured");

        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        return true;
    }

    //! Every ring full is the brightest frame the face can draw. If that fits
    //! the budget, no real reading can blank the screen.
    (:test)
    function alwaysOnWorstCaseFitsBudget(logger as Logger) as Boolean {
        Config.reload();
        var full = everySpan(0.0, 1.0);
        for (var i = 0; i < ALL_LAYOUTS.size(); i++) {
            StatMap.layout = ALL_LAYOUTS[i];
            var worst = frameLuminance(full, Palette.alwaysOn);
            logger.debug("layout " + StatMap.layout + " worst-case always-on: " + worst);
            Test.assertMessage(worst < BUDGET,
                "always-on worst case exceeds the AMOLED burn-in budget");
        }
        StatMap.layout = StatMap.LAYOUT_BANDS_BOTTOM;
        return true;
    }

    (:test)
    function alwaysOnIsDimmerThanActive(logger as Logger) as Boolean {
        Config.reload();
        var spans = everySpan(0.0, 0.7);
        var awake = frameLuminance(spans, Palette.active);
        var asleep = frameLuminance(spans, Palette.alwaysOn);
        logger.debug("active " + awake + " / always-on " + asleep);
        Test.assertMessage(asleep < awake, "always-on is not dimmer than active");
        return true;
    }

    //! The drift must never push a dot past the edge of the screen. This is
    //! the constraint that pins Drift.AMPLITUDE — the outermost dots sit 189px
    //! out on a screen whose half-width is 195.
    (:test)
    function driftKeepsDotsOnScreen(logger as Logger) as Boolean {
        var furthest = DotGrid.offsetAt(DotGrid.COLS - 1);
        var reach = furthest + Drift.AMPLITUDE + (DotGrid.DOT / 2);
        logger.debug("furthest lit pixel from centre: " + reach);
        Test.assertMessage(reach <= 194, "drift pushes dots off the 390px screen");
        return true;
    }

    //! Consecutive phases must not share pixels, or the drift buys nothing.
    (:test)
    function driftPhasesAreDecorrelated(logger as Logger) as Boolean {
        for (var minute = 0; minute < 60; minute++) {
            var here = Drift.offsetFor(minute);
            var next = Drift.offsetFor(minute + Drift.PERIOD_MINUTES);
            if (here[0] == next[0] && here[1] == next[1]) {
                continue;
            }
            var moved = (here[0] - next[0]).abs();
            var movedY = (here[1] - next[1]).abs();
            if (movedY > moved) { moved = movedY; }
            Test.assertMessage(moved >= DotGrid.DOT,
                "consecutive drift phases overlap, so pixels stay lit");
        }
        return true;
    }

    (:test)
    function driftVisitsEveryPhase(logger as Logger) as Boolean {
        var seen = 0;
        for (var minute = 0; minute < 60; minute++) {
            seen |= 1 << Drift.phaseFor(minute);
        }
        Test.assertEqualMessage(seen, (1 << Drift.PHASES.size()) - 1,
            "drift does not visit every phase within an hour");
        return true;
    }

    //! The backing must land on the hands, and only on the hands.
    (:test)
    function handBackingFollowsTheHands(logger as Logger) as Boolean {
        var up = [0.0, -1.0, 0.0, -1.0] as Array<Float>;
        Test.assertMessage(HandBacking.covers(0, -100, up),
            "a dot on the hand axis must be covered");
        Test.assertMessage(!HandBacking.covers(100, 0, up),
            "a dot at right angles to the hand must not be covered");
        Test.assertMessage(!HandBacking.covers(0, -HandBacking.MINUTE_REACH - 40, up),
            "a dot beyond the hand tip must not be covered");
        Test.assertMessage(HandBacking.covers(HandBacking.HALF_WIDTH - 1, -100, up),
            "a dot within the hand's width must be covered");
        Test.assertMessage(!HandBacking.covers(HandBacking.HALF_WIDTH * 3, -100, up),
            "a dot well outside the hand's width must not be covered");
        return true;
    }
}
