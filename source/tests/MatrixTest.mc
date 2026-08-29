import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;
import Toybox.WatchUi;

//! Tests for the parts of the face that can be checked without a screen: the
//! lattice, the dot -> ring mapping, the burn-in drift and the always-on
//! luminance budget.
//!
//! The dot count is asserted against the figure the Python mockup produces
//! from the same constants (tools/mockup.py), so the two implementations
//! cannot drift apart silently — the mockups stay an honest preview.
module MatrixTest {

    const EXPECTED_DOTS = 1112;

    //! Garmin blanks an always-on face above this share of screen luminance.
    const BUDGET = 0.10;

    //! Lit pixels per dot. Dots are crosses: two DOT-long strokes sharing
    //! their centre pixel, so 2 * DOT - 1 — not DOT squared. Using the square
    //! figure here over-reported every luminance measurement by nearly 3x.
    const LIT_PIXELS_PER_DOT = (2 * DotGrid.DOT) - 1;

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
                total += relativeLuminance(palette[slot]) * LIT_PIXELS_PER_DOT;
            }
        }
        return total / (Math.PI * DotGrid.RADIUS * DotGrid.RADIUS);
    }

    //! build() fills three dots out of every four by mirroring a fourth across
    //! the axes, which means it writes to computed indices rather than to a
    //! running cursor. Get that arithmetic wrong and a slot is written twice
    //! while another is never written at all — and every consistency check
    //! still passes, because a mis-aimed write puts x, y, ring and position in
    //! the *same* wrong slot. Only counting the slots catches it.
    (:test)
    function cacheCoversEveryLatticeDotExactlyOnce(logger as Logger) as Boolean {
        for (var l = 0; l < ALL_LAYOUTS.size(); l++) {
            Properties.setValue(StatMap.PROPERTY_LAYOUT, ALL_LAYOUTS[l]);
            Config.reload();
            DotGrid.build();

            Test.assertEqualMessage(DotGrid.count, EXPECTED_DOTS,
                "the build counted a different lattice than the mockup");
            Test.assertEqualMessage(DotGrid.xs.size(), DotGrid.count,
                "the cache is not the size it claims");

            // One slot per grid cell, so a double write is visible as a 2.
            var seen = new [DotGrid.ROWS * DotGrid.COLS] as Array<Number>;
            for (var i = 0; i < seen.size(); i++) {
                seen[i] = 0;
            }
            for (var i = 0; i < DotGrid.count; i++) {
                var col = columnOf(DotGrid.xs[i]);
                var row = columnOf(DotGrid.ys[i]);
                Test.assertMessage(col >= 0 && col < DotGrid.COLS &&
                                   row >= 0 && row < DotGrid.ROWS,
                    "a cached dot sits outside the grid");
                seen[row * DotGrid.COLS + col] += 1;
            }

            var filled = 0;
            for (var row = 0; row < DotGrid.ROWS; row++) {
                for (var col = 0; col < DotGrid.COLS; col++) {
                    var times = seen[row * DotGrid.COLS + col];
                    var wanted = DotGrid.contains(DotGrid.offsetAt(col),
                                                  DotGrid.offsetAt(row)) ? 1 : 0;
                    Test.assertEqualMessage(times, wanted,
                        "grid cell " + col + "," + row + " was built " +
                        times + " times, wanted " + wanted);
                    filled += times;
                }
            }
            logger.debug("layout " + StatMap.layout + ": " + filled +
                         " dots, each built exactly once");
        }
        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        return true;
    }

    //! The face must never draw a half-built field. That was the bug the
    //! chunked build shipped: it filled 150 dots per frame, and in always-on
    //! a frame is a *minute*, so the face crawled into existence over eight of
    //! them. One build, complete before the first draw, is the contract — and
    //! a reload must mark the cache stale so a layout change is picked up.
    (:test)
    function theCacheIsWholeBeforeAnythingDrawsIt(logger as Logger) as Boolean {
        Config.reload();
        Test.assertMessage(DotGrid.stale,
            "reloading settings must mark the cache stale");

        DotGrid.ensureBuilt();          // what onLayout does, once
        Test.assertMessage(!DotGrid.stale, "one build must finish the cache");
        Test.assertEqualMessage(DotGrid.count, EXPECTED_DOTS,
            "the first build must produce the whole lattice");
        Test.assertEqualMessage(DotGrid.positionOf.size(), EXPECTED_DOTS,
            "every dot must have a position after a single build");

        // Every later frame finds it built and does no work. A rebuild would
        // recompute the same values, so comparing them proves nothing —
        // scribble on the cache and check the scribble survives.
        DotGrid.positionOf[EXPECTED_DOTS - 1] = -1.0;
        DotGrid.ensureBuilt();
        Test.assertEqualMessage(DotGrid.positionOf[EXPECTED_DOTS - 1], -1.0,
            "a built cache must not be rebuilt on the next frame");
        DotGrid.invalidate();
        DotGrid.ensureBuilt();
        Test.assertMessage(DotGrid.positionOf[EXPECTED_DOTS - 1] >= 0.0,
            "invalidating must make the next frame rebuild");
        logger.debug("cache complete in one build: " + DotGrid.count + " dots");
        return true;
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
        Test.assertMessage(DotGrid.contains(DotGrid.HUB + 5, 0),
            "just outside the hub must have dots");
        return true;
    }

    (:test)
    function cornersAreClipped(logger as Logger) as Boolean {
        Test.assertMessage(!DotGrid.contains(185, 185), "corner must be clipped");
        Test.assertMessage(DotGrid.contains(0, 185), "rim must have dots");
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

        Test.assertEqualMessage(Source.span(Source.SOURCE_OFF, true)[1], 0.0,
            "an off ring must have an empty span");

        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[ring], ring);
        }
        Config.reload();
        return true;
    }

    //! The temperature scale runs 0C to 60C, which puts one degree on every
    //! minute mark: 18C sits exactly where :18 does. That correspondence is
    //! the whole reason for the range, so it is worth asserting directly.
    (:test)
    function oneDegreeSitsOnEachMinuteMark(logger as Logger) as Boolean {
        Test.assertEqualMessage(WeatherData.fraction(0.0), 0.0,
            "0C must sit at twelve o'clock");
        // 60C wraps onto twelve exactly as minute 60 is minute 0.
        Test.assertMessage(WeatherData.fraction(60.0) < 0.001,
            "60C must land back at twelve o'clock");
        for (var degrees = 0; degrees < 60; degrees += 15) {
            var expected = degrees / 60.0;
            var actual = WeatherData.fraction(degrees.toFloat());
            Test.assertMessage((actual - expected).abs() < 0.001,
                "each degree must land on its own minute mark");
        }
        return true;
    }

    //! Sub-zero temperatures run anticlockwise past twelve, the same way
    //! minute 55 does. Clamping them to zero would fold every frost onto
    //! twelve o'clock and show a wrong reading rather than a missing one.
    (:test)
    function subZeroWrapsBackPastTwelve(logger as Logger) as Boolean {
        var minusFive = WeatherData.fraction(-5.0);
        logger.debug("-5C sits at " + minusFive);
        Test.assertMessage((minusFive - (55.0 / 60.0)).abs() < 0.001,
            "-5C must sit where :55 does");
        Test.assertMessage((WeatherData.fraction(-1.0) - (59.0 / 60.0)).abs() < 0.001,
            "-1C must sit where :59 does");
        Test.assertMessage(WeatherData.fraction(-60.0) < 0.001,
            "a whole turn below zero must land back at twelve");
        Test.assertMessage(WeatherData.fraction(65.0) - (5.0 / 60.0) < 0.001,
            "above the scale must wrap too");
        return true;
    }

    //! A frosty day spans twelve o'clock: its start is *after* its end.
    (:test)
    function spanWrappingPastTheOriginStaysLit(logger as Logger) as Boolean {
        // -5C to 3C — from :55 round through twelve to :03.
        var frosty = [WeatherData.fraction(-5.0), WeatherData.fraction(3.0)]
                     as Array<Float>;
        Test.assertMessage(frosty[0] > frosty[1],
            "this range must actually wrap, or the test proves nothing");

        Test.assertMessage(StatMap.isLit(56.0 / 60.0, frosty),
            "-4C is inside the range");
        Test.assertMessage(StatMap.isLit(0.0, frosty),
            "0C is inside the range");
        Test.assertMessage(StatMap.isLit(2.0 / 60.0, frosty),
            "2C is inside the range");
        Test.assertMessage(!StatMap.isLit(30.0 / 60.0, frosty),
            "30C is nowhere near a frosty day");
        Test.assertMessage(!StatMap.isLit(50.0 / 60.0, frosty),
            "50C is outside, just before the range starts");
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

    //! Holding the fills back in always-on works by handing the renderer a
    //! span nothing is inside, rather than branching ~1100 times a frame. That
    //! only holds if no dot in any layout ever falls in it — and the obvious
    //! wrong choice, (0, 0), lights any dot sitting exactly at the origin.
    (:test)
    function heldBackFillsLightNothingAnywhere(logger as Logger) as Boolean {
        var nothing = StatMap.noSpans();
        Test.assertMessage(!(StatMap.NEVER_LIT[0] > StatMap.NEVER_LIT[1]),
            "the empty span must not read as wrapping, or it lights everything");

        for (var l = 0; l < ALL_LAYOUTS.size(); l++) {
            StatMap.layout = ALL_LAYOUTS[l];
            var lit = 0;
            var checked = 0;
            for (var row = 0; row < DotGrid.ROWS; row++) {
                var dy = DotGrid.offsetAt(row);
                for (var col = 0; col < DotGrid.COLS; col++) {
                    var dx = DotGrid.offsetAt(col);
                    if (!DotGrid.contains(dx, dy)) {
                        continue;
                    }
                    if (StatMap.classify(col, dx, dy, nothing) % 2 == 1) {
                        lit++;
                    }
                    checked++;
                }
            }
            logger.debug("layout " + StatMap.layout + ": " + lit +
                         " of " + checked + " dots lit");
            Test.assertEqualMessage(lit, 0,
                "a dot is lit by the empty span in layout " + StatMap.layout);
        }
        StatMap.layout = StatMap.LAYOUT_BANDS_BOTTOM;
        return true;
    }

    //! The reason to want it is not only that it looks calmer: the filled dots
    //! are the brightest thing on the face and they barely move, which is
    //! exactly what burns an AMOLED in. Holding them back has to actually cut
    //! the light, or the option is cosmetic.
    (:test)
    function heldBackFillsCutAlwaysOnLuminance(logger as Logger) as Boolean {
        Config.reload();
        var busy = everySpan(0.0, 0.82);
        for (var l = 0; l < ALL_LAYOUTS.size(); l++) {
            StatMap.layout = ALL_LAYOUTS[l];
            var withFills = frameLuminance(busy, Palette.alwaysOn);
            var heldBack = frameLuminance(StatMap.noSpans(), Palette.alwaysOn);
            logger.debug("layout " + StatMap.layout + ": with fills " +
                         withFills + ", held back " + heldBack);
            Test.assertMessage(heldBack < withFills,
                "holding the fills back must lower always-on luminance");
            Test.assertMessage(heldBack < BUDGET,
                "and must still sit inside the burn-in budget");
        }
        StatMap.layout = StatMap.LAYOUT_BANDS_BOTTOM;
        return true;
    }

    (:test)
    function alwaysOnFillSettingIsClamped(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_ALWAYS_ON_FILL, 99);
        Config.reload();
        Test.assertEqualMessage(StatMap.alwaysOnFill,
            StatMap.ALWAYS_ON_FILL_SHOWN,
            "an out-of-range value must fall back to showing the data");

        Properties.setValue(StatMap.PROPERTY_ALWAYS_ON_FILL,
                            StatMap.ALWAYS_ON_FILL_HIDDEN);
        Config.reload();
        Test.assertEqualMessage(StatMap.alwaysOnFill,
            StatMap.ALWAYS_ON_FILL_HIDDEN, "a valid value must be honoured");

        // The menu reads its sub-label straight off the setting, so an
        // unhandled value would index past the end of the label table.
        var menu = new SettingsMenu();
        menu.onShow();

        Properties.setValue(StatMap.PROPERTY_ALWAYS_ON_FILL,
                            StatMap.ALWAYS_ON_FILL_SHOWN);
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

    //! The two modes draw the same filled colours and differ only in their
    //! unfilled tier. That is what "minimal change between modes" means here,
    //! and the budget test above is what keeps it affordable.
    (:test)
    function modesDifferOnlyInTheUnfilledTier(logger as Logger) as Boolean {
        Config.reload();
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(
                Palette.alwaysOn[ring * 2 + 1], Palette.active[ring * 2 + 1],
                "filled colours must match between modes");
            Test.assertMessage(
                Palette.alwaysOn[ring * 2] != Palette.active[ring * 2],
                "the unfilled tier must differ between modes");
        }
        var spans = everySpan(0.0, 0.7);
        var awake = frameLuminance(spans, Palette.active);
        var asleep = frameLuminance(spans, Palette.alwaysOn);
        logger.debug("active " + awake + " / always-on " + asleep);
        Test.assertMessage(asleep < BUDGET,
            "always-on exceeds the burn-in budget");
        return true;
    }

    //! The unfilled tier must stay visible while awake — the whole design
    //! rests on every dot carrying its ring's colour, lit or not.
    (:test)
    function unfilledTierIsBrighterAwake(logger as Logger) as Boolean {
        Config.reload();
        Test.assertMessage(Palette.WEAK_ACTIVE > Palette.WEAK_ALWAYS_ON,
            "awake should carry the brighter unfilled tier");
        var empty = everySpan(0.0, 0.0);
        var awake = frameLuminance(empty, Palette.active);
        logger.debug("all-unfilled awake luminance: " + awake);
        Test.assertMessage(awake > 0.0,
            "an entirely unfilled face must still show its dots");
        return true;
    }

    //! LIFT scales above 1.0, so a channel that overflowed would bleed into
    //! the next one's bits and change the hue outright.
    (:test)
    function scaleClampsInsteadOfBleeding(logger as Logger) as Boolean {
        Test.assertEqualMessage(Palette.scale(0xFFFFFF, 2.0), 0xFFFFFF,
            "white scaled up must stay white");
        Test.assertEqualMessage(Palette.scale(0x00FF00, 4.0), 0x00FF00,
            "an overflowing channel must not bleed into its neighbours");
        Test.assertEqualMessage(Palette.scale(0x804020, 0.0), 0x000000,
            "scaling to nothing must give black");
        return true;
    }

    //! The drift must never push a dot past the edge of the screen.
    (:test)
    function driftKeepsDotsOnScreen(logger as Logger) as Boolean {
        var furthest = DotGrid.offsetAt(DotGrid.COLS - 1);
        var reach = furthest + Drift.MAX_OFFSET + (DotGrid.DOT / 2);
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

    //! The claim drift makes is that no pixel is lit in more than one phase.
    //! Checking it needs neighbours in frame, not one dot in isolation: at
    //! this pitch a dot's own decorrelation is easy, and it is collisions with
    //! the *next dot along* that break the guarantee.
    (:test)
    function driftDutyCycleIsOnePhaseInFour(logger as Logger) as Boolean {
        var pitch = DotGrid.PITCH;
        var size = 3 * pitch;                  // a 3x3 block of dots
        var counts = new [size * size] as Array<Number>;
        for (var i = 0; i < counts.size(); i++) { counts[i] = 0; }

        var half = DotGrid.DOT / 2;
        for (var p = 0; p < Drift.PHASES.size(); p++) {
            var offset = Drift.offsetFor(p * Drift.PERIOD_MINUTES);
            for (var gy = 0; gy < 3; gy++) {
                for (var gx = 0; gx < 3; gx++) {
                    var cx = (gx * pitch) + (pitch / 2) + offset[0];
                    var cy = (gy * pitch) + (pitch / 2) + offset[1];
                    // A cross: one horizontal stroke, one vertical. The two
                    // meet at the centre, so the vertical skips k = 0 or the
                    // centre pixel would be counted twice within one phase.
                    for (var k = -half; k <= half; k++) {
                        mark(counts, size, cx + k, cy);
                        if (k != 0) {
                            mark(counts, size, cx, cy + k);
                        }
                    }
                }
            }
        }

        var worst = 0;
        for (var i = 0; i < counts.size(); i++) {
            if (counts[i] > worst) { worst = counts[i]; }
        }
        logger.debug("worst duty cycle: " + worst + " of " + Drift.PHASES.size());
        Test.assertEqualMessage(worst, 1,
            "a pixel is lit in more than one drift phase, so drift buys less than it claims");
        return true;
    }

    function mark(counts as Array<Number>, size as Number,
                  x as Number, y as Number) as Void {
        if (x < 0 || y < 0 || x >= size || y >= size) {
            return;     // outside the window; neighbours beyond it are mirrored
        }
        counts[y * size + x] += 1;
    }

    //! A menu's sub-labels are built from the settings at construction time,
    //! so they go stale the moment a sub-menu changes one. onShow() is where
    //! they get refreshed — without it the menu shows the previous value until
    //! you leave settings entirely and come back.
    //! getItem() is nullable and getSubLabel() returns a union, so reading a
    //! sub-label needs unwrapping before it can be compared.
    function subLabelOf(menu as WatchUi.Menu2, index as Number) as String {
        var item = menu.getItem(index);
        if (item == null) {
            return "";
        }
        var label = item.getSubLabel();
        return (label == null) ? "" : label.toString();
    }

    //! Every settings row that shows a value, by index. The rings row is not
    //! here: it opens a sub-menu and carries no value of its own.
    const MENU_VALUE_ROWS = [0, 1, 2, 4] as Array<Number>;

    (:test)
    function settingsMenuRefreshesItsSubLabels(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        var menu = new SettingsMenu();
        var before = subLabelOf(menu, 0);

        // What a sub-menu does when the user picks a different layout.
        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_RINGS);
        Config.reload();
        Test.assertEqualMessage(subLabelOf(menu, 0), before,
            "sub-label should still be stale before the menu is shown again");

        menu.onShow();
        logger.debug("was '" + before + "', now '" + subLabelOf(menu, 0) + "'");
        Test.assertMessage(!subLabelOf(menu, 0).equals(before),
            "onShow must refresh the sub-label to the new setting");

        // onShow refreshes rows by index, so inserting a row silently points
        // the refreshes at the wrong ones. Every row that carries a value must
        // still have one after a refresh.
        for (var i = 0; i < MENU_VALUE_ROWS.size(); i++) {
            var row = MENU_VALUE_ROWS[i];
            Test.assertMessage(menu.getItem(row) != null,
                "menu row " + row + " is missing");
            Test.assertMessage(subLabelOf(menu, row).length() > 0,
                "menu row " + row + " lost its sub-label — the indexes " +
                "onShow refreshes have drifted from the rows it adds");
        }

        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        return true;
    }

    //! Same staleness, same fix, for the ring assignment menu.
    (:test)
    function ringMenuRefreshesItsSubLabels(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_RINGS[0], Source.SOURCE_STEPS);
        Config.reload();
        var menu = new RingMenu();
        var before = subLabelOf(menu, 0);

        Properties.setValue(StatMap.PROPERTY_RINGS[0], Source.SOURCE_RAIN);
        Config.reload();
        menu.onShow();
        logger.debug("was '" + before + "', now '" + subLabelOf(menu, 0) + "'");
        Test.assertMessage(!subLabelOf(menu, 0).equals(before),
            "onShow must refresh the ring's sub-label");

        Properties.setValue(StatMap.PROPERTY_RINGS[0], Source.SOURCE_STEPS);
        Config.reload();
        return true;
    }

    //! Guards the shape of the arm table itself. Nothing previously asserted
    //! that ARMS was even populated, so a table that came back empty on the
    //! watch would draw a blank face with no test failing anywhere.
    (:test)
    function armTableIsWellFormed(logger as Logger) as Boolean {
        Test.assertEqualMessage(DotGrid.ARMS.size(),
            DotGrid.ORIENTATIONS * DotGrid.ARM_VALUES,
            "the arm table is not the size its constants claim");

        var half = DotGrid.DOT / 2;
        for (var o = 0; o < DotGrid.ORIENTATIONS; o++) {
            var i = o * DotGrid.ARM_VALUES;
            var ax = DotGrid.ARMS[i];
            var ay = DotGrid.ARMS[i + 1];
            var bx = DotGrid.ARMS[i + 2];
            var by = DotGrid.ARMS[i + 3];

            Test.assertEqualMessage(ax * bx + ay * by, 0,
                "a cross's two strokes must be at right angles");

            var extentA = (ax.abs() > ay.abs()) ? ax.abs() : ay.abs();
            var extentB = (bx.abs() > by.abs()) ? bx.abs() : by.abs();
            Test.assertEqualMessage(extentA, half,
                "every orientation must span the same width");
            Test.assertEqualMessage(extentB, half,
                "every orientation must span the same height");
        }
        return true;
    }

    //! Every dot must point at a real entry in that table. An out-of-range
    //! offset would read past the end of ARMS and take the face down.
    (:test)
    function everyDotHasAValidArmOffset(logger as Logger) as Boolean {
        var layouts = [StatMap.LAYOUT_BANDS_BOTTOM, StatMap.LAYOUT_RINGS]
                      as Array<Number>;
        for (var l = 0; l < layouts.size(); l++) {
            Properties.setValue(StatMap.PROPERTY_LAYOUT, layouts[l]);
            Config.reload();
            DotGrid.build();
            Test.assertEqualMessage(DotGrid.armOf.size(), DotGrid.count,
                "every dot needs an orientation");

            var distinct = 0;
            for (var i = 0; i < DotGrid.count; i++) {
                var offset = DotGrid.armOf[i];
                Test.assertMessage(offset >= 0 &&
                        offset + DotGrid.ARM_VALUES <= DotGrid.ARMS.size(),
                    "arm offset points outside the table");
                Test.assertEqualMessage(offset % DotGrid.ARM_VALUES, 0,
                    "arm offset must land on an entry boundary");
                distinct |= 1 << (offset / DotGrid.ARM_VALUES);
            }
            logger.debug("layout " + StatMap.layout + " orientations used: " + distinct);
            if (StatMap.layout == StatMap.LAYOUT_RINGS) {
                Test.assertEqualMessage(distinct,
                    (1 << DotGrid.ORIENTATIONS) - 1,
                    "the rings layout should use every orientation");
            } else {
                Test.assertEqualMessage(distinct, 1,
                    "the band layouts should leave every cross upright");
            }
        }
        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        return true;
    }

    //! DotGrid.build() inlines the ring, position and orientation maths for
    //! speed, because calling out per dot tripped the watchdog on the watch.
    //! That leaves two copies of the same maths, so this asserts they agree
    //! for every dot in every layout — the inlined one is fast, StatMap's and
    //! orientationFor's are the readable definitions, and neither may drift.
    (:test)
    function cacheAgreesWithTheReferenceMaths(logger as Logger) as Boolean {
        for (var l = 0; l < ALL_LAYOUTS.size(); l++) {
            Properties.setValue(StatMap.PROPERTY_LAYOUT, ALL_LAYOUTS[l]);
            Config.reload();
            DotGrid.build();

            var checked = 0;
            for (var i = 0; i < DotGrid.count; i++) {
                var dx = DotGrid.xs[i];
                var dy = DotGrid.ys[i];

                Test.assertEqualMessage(DotGrid.ringOf[i],
                    StatMap.ringFor(columnOf(dx), dx, dy),
                    "cached ring disagrees with StatMap.ringFor");

                var expected = StatMap.positionOf(dx, dy);
                Test.assertMessage((DotGrid.positionOf[i] - expected).abs() < 0.0001,
                    "cached position disagrees with StatMap.positionOf");

                // Three dots in four take their orientation by mirroring a
                // fourth, so the reflection rule needs checking per dot.
                var wantedArm = (StatMap.layout == StatMap.LAYOUT_RINGS)
                    ? DotGrid.orientationFor(dx, dy) : 0;
                Test.assertEqualMessage(DotGrid.armOf[i], wantedArm,
                    "cached orientation disagrees with orientationFor");
                checked++;
            }
            logger.debug("layout " + StatMap.layout + ": " + checked + " dots agree");
            Test.assertMessage(checked > 1000, "hardly any dots were checked");
        }
        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        return true;
    }

    //! The renderer walks the dots ring by ring, and every hoist it makes out
    //! of its inner loop assumes this: each ring's dots are contiguous, and
    //! within a ring they are still in the lattice's scan order. Scan order is
    //! not cosmetic — in the band layouts a dot's position depends only on its
    //! row, so scan order is fill order, and it is what makes each ring draw as
    //! two long runs of one colour instead of hundreds of short ones.
    (:test)
    function ringsAreContiguousAndInScanOrder(logger as Logger) as Boolean {
        for (var l = 0; l < ALL_LAYOUTS.size(); l++) {
            Properties.setValue(StatMap.PROPERTY_LAYOUT, ALL_LAYOUTS[l]);
            Config.reload();
            DotGrid.build();

            Test.assertEqualMessage(DotGrid.ringStart.size(), StatMap.RINGS + 1,
                "ringStart needs one entry per ring plus the total");
            Test.assertEqualMessage(DotGrid.ringStart[0], 0,
                "the first ring must start at the first dot");
            Test.assertEqualMessage(DotGrid.ringStart[StatMap.RINGS],
                DotGrid.count, "the ring blocks must account for every dot");

            var longestRun = 0;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                var from = DotGrid.ringStart[ring];
                var to = DotGrid.ringStart[ring + 1];
                Test.assertMessage(to > from, "ring " + ring + " has no dots");

                var previous = -1;
                for (var i = from; i < to; i++) {
                    Test.assertEqualMessage(DotGrid.ringOf[i], ring,
                        "a dot inside ring " + ring + "'s block belongs to " +
                        DotGrid.ringOf[i]);
                    // Scan order: row first, then column, strictly increasing.
                    var key = columnOf(DotGrid.ys[i]) * DotGrid.COLS +
                              columnOf(DotGrid.xs[i]);
                    Test.assertMessage(key > previous,
                        "ring " + ring + " is out of scan order at " + i);
                    previous = key;
                }
                var size = to - from;
                if (size > longestRun) { longestRun = size; }
            }
            logger.debug("layout " + StatMap.layout + ": rings contiguous, " +
                         "largest " + longestRun + " dots");
        }
        Properties.setValue(StatMap.PROPERTY_LAYOUT, StatMap.LAYOUT_BANDS_BOTTOM);
        Config.reload();
        return true;
    }

    //! MatrixRenderer inlines litBetween's two comparisons rather than calling
    //! isLit per dot. The boundaries are where a copied comparison drifts — an
    //! inline that used > instead of >= would light one dot fewer per ring and
    //! nothing else would ever notice.
    (:test)
    function litTestsAgreeAtTheBoundaries(logger as Logger) as Boolean {
        var spans = [
            [0.0, 0.0] as Array<Float>,     // empty
            [0.0, 1.0] as Array<Float>,     // full
            [0.25, 0.75] as Array<Float>,   // a plain range
            [0.75, 0.25] as Array<Float>,   // wrapping past the origin
            [0.5, 0.5] as Array<Float>      // a single point
        ] as Array<Array<Float> >;

        var checked = 0;
        for (var s = 0; s < spans.size(); s++) {
            var span = spans[s];
            var wraps = span[0] > span[1];
            // Every hundredth, plus the two ends and the pixels either side of
            // them, which is where the two forms can disagree.
            var probes = [span[0], span[1], span[0] - 0.0001, span[0] + 0.0001,
                          span[1] - 0.0001, span[1] + 0.0001] as Array<Float>;
            for (var i = 0; i <= 100; i++) {
                probes.add(i / 100.0);
            }
            for (var i = 0; i < probes.size(); i++) {
                var position = probes[i];
                Test.assertEqualMessage(
                    StatMap.litBetween(position, span[0], span[1], wraps),
                    StatMap.isLit(position, span),
                    "the inlined lit test disagrees with isLit at " + position +
                    " for span " + span[0] + ".." + span[1]);
                checked++;
            }
        }
        logger.debug("lit tests agree over " + checked + " probes");
        return true;
    }

    //! Recover a dot's column from its x offset — build() knows it, the cache
    //! does not store it, and ringFor needs it for the band layouts.
    function columnOf(dx as Number) as Number {
        return ((dx / (DotGrid.PITCH / 2)) + (DotGrid.COLS - 1)) / 2;
    }

    //! Awake, the system asks for a frame every second and almost all of them
    //! are the frame before it. Skipping those is the largest saving the face
    //! has left — but a skip shows whatever is already on screen, so the rules
    //! that bound it matter more than the saving.
    (:test)
    function unchangedFramesAreSkippedButNeverIndefinitely(logger as Logger) as Boolean {
        FrameGate.forget();
        FrameGate.drawn = 0;
        FrameGate.suppressed = 0;

        var still = [1.0, 2.0, 3.0] as Array<Float>;
        Test.assertMessage(FrameGate.shouldDraw(still),
            "the first frame after forgetting must always be drawn");
        Test.assertMessage(!FrameGate.shouldDraw([1.0, 2.0, 3.0] as Array<Float>),
            "an identical frame must be skipped");

        // A change of any kind must draw, including one only in the last slot.
        Test.assertMessage(FrameGate.shouldDraw([1.0, 2.0, 4.0] as Array<Float>),
            "a changed fingerprint must be drawn");
        Test.assertMessage(!FrameGate.shouldDraw([1.0, 2.0, 4.0] as Array<Float>),
            "and then settle back to skipping");

        // The cap: something drawn over the face from outside is only repaired
        // by a draw, so skips must not run on forever.
        var run = 0;
        for (var i = 0; i < 40; i++) {
            if (FrameGate.shouldDraw([1.0, 2.0, 4.0] as Array<Float>)) {
                Test.assertMessage(run <= FrameGate.MAX_SKIPS,
                    "went " + run + " frames without drawing, cap is " +
                    FrameGate.MAX_SKIPS);
                run = 0;
            } else {
                run++;
            }
        }
        Test.assertMessage(run <= FrameGate.MAX_SKIPS,
            "the gate must never skip more than the cap in a row");

        // forget() is what onShow and waking use; it must always draw next.
        FrameGate.forget();
        Test.assertMessage(FrameGate.shouldDraw([1.0, 2.0, 4.0] as Array<Float>),
            "forget() must force the next frame to be drawn");

        logger.debug("skipped " + FrameGate.skipPercent() + "% of frames");
        Test.assertMessage(FrameGate.skipPercent() > 50,
            "a still face should skip most of its frames, or this buys nothing");
        Test.assertMessage(FrameGate.skipPercent() < 100,
            "it must never skip all of them");

        FrameGate.forget();
        FrameGate.drawn = 0;
        FrameGate.suppressed = 0;
        return true;
    }

    //! The frame-cost readout is the only way to see what a frame costs on the
    //! watch, so it has to survive a long session without its average drifting
    //! into meaninglessness or its counters overflowing.
    (:test)
    function frameCostAveragesRecentFrames(logger as Logger) as Boolean {
        Diagnostics.frames = 0;
        Diagnostics.totalMs = 0;
        Diagnostics.worstMs = 0;
        Test.assertMessage(Diagnostics.summary().equals("no frames yet"),
            "with no frames recorded there is nothing to average");

        for (var i = 0; i < 40; i++) {
            Diagnostics.record(30);
        }
        Test.assertEqualMessage(Diagnostics.averageMs(), 30,
            "a steady 30ms frame must average 30ms");
        Diagnostics.record(90);
        Test.assertEqualMessage(Diagnostics.worstMs, 90,
            "the worst frame must be remembered");

        // A day's worth of frames must not swamp a change that just happened.
        for (var i = 0; i < 5000; i++) {
            Diagnostics.record(30);
        }
        Test.assertMessage(Diagnostics.frames <= Diagnostics.WINDOW,
            "the window must stay bounded, or the counters run away");
        for (var i = 0; i < Diagnostics.WINDOW; i++) {
            Diagnostics.record(10);
        }
        Test.assertMessage(Diagnostics.averageMs() < 20,
            "the average must follow a sustained change, not average it away");
        logger.debug("after the change: " + Diagnostics.summary());

        Diagnostics.frames = 0;
        Diagnostics.totalMs = 0;
        Diagnostics.worstMs = 0;
        return true;
    }

    //! The backing must land on the hands, and only on the hands.
    (:test)
    function handBackingFollowsTheHands(logger as Logger) as Boolean {
        // Both hands straight up.
        Test.assertMessage(HandBacking.covers(0, -100, 0.0, -1.0, 0.0, -1.0),
            "a dot on the hand axis must be covered");
        Test.assertMessage(!HandBacking.covers(100, 0, 0.0, -1.0, 0.0, -1.0),
            "a dot at right angles to the hand must not be covered");
        Test.assertMessage(!HandBacking.covers(0, -HandBacking.MINUTE_REACH - 40,
                0.0, -1.0, 0.0, -1.0),
            "a dot beyond the hand tip must not be covered");
        Test.assertMessage(HandBacking.covers(HandBacking.HALF_WIDTH - 1, -100,
                0.0, -1.0, 0.0, -1.0),
            "a dot within the hand's width must be covered");
        Test.assertMessage(!HandBacking.covers(HandBacking.HALF_WIDTH * 3, -100,
                0.0, -1.0, 0.0, -1.0),
            "a dot well outside the hand's width must not be covered");

        // The two hands are tested independently: a dot under the minute hand
        // alone must still be covered, and the hour hand's shorter reach must
        // not be lent to it. Collapsing three calls into one is exactly the
        // kind of change that could drop one hand's test silently.
        Test.assertMessage(HandBacking.covers(0, -100, 1.0, 0.0, 0.0, -1.0),
            "a dot under the minute hand alone must be covered");
        Test.assertMessage(HandBacking.covers(100, 0, 1.0, 0.0, 0.0, -1.0),
            "a dot under the hour hand alone must be covered");
        Test.assertMessage(
            !HandBacking.covers(0, -HandBacking.HOUR_REACH - 20,
                                0.0, -1.0, 1.0, 0.0),
            "the hour hand must not reach as far as the minute hand");
        Test.assertMessage(
            HandBacking.covers(0, -HandBacking.HOUR_REACH - 20,
                               1.0, 0.0, 0.0, -1.0),
            "the minute hand does reach that far");
        return true;
    }
}
