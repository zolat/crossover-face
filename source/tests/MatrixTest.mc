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
                var slot = StatMap.classify(dx, dy, spans);
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
        logger.debug(filled + " dots, each built exactly once");
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

    //! Empty and full are the two states the mapping must get exactly right,
    //! and the two a gauge is most likely to get wrong.
    (:test)
    function spanEndpoints(logger as Logger) as Boolean {
        var empty = everySpan(0.0, 0.0);
        var full = everySpan(0.0, 1.0);
        var checked = 0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                Test.assertMessage(StatMap.classify(dx, dy, empty) % 2 == 0,
                    "nothing may read as lit at 0%");
                Test.assertMessage(StatMap.classify(dx, dy, full) % 2 == 1,
                    "everything must read as lit at 100%");
                checked++;
            }
        }
        logger.debug(checked + " dots checked empty and full");
        return true;
    }

    //! A range source must light only between its ends — that is the whole
    //! point of spans, and what lets temperature share the rings with levels.
    (:test)
    function rangeLightsOnlyBetweenItsEnds(logger as Logger) as Boolean {
        var band = everySpan(0.4, 0.6);
        var below = 0;
        var inside = 0;
        var above = 0;

        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                var position = StatMap.positionOf(dx, dy);
                var lit = (StatMap.classify(dx, dy, band) % 2) == 1;
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

    //! Every table indexed by Source.Kind covers every kind.
    //!
    //! Adding a source means touching four places that store or show a list
    //! index — the enum, the hue table, the on-device labels, and the two XML
    //! resource files. Nothing pinned the first three together, so a kind added
    //! to the enum alone would leave a ring reading off the end of a table or,
    //! worse, silently taking its neighbour's entry. The XML is out of reach
    //! from here; COUNT is the number those files have to match.
    (:test)
    function sourceTablesCoverEveryKind(logger as Logger) as Boolean {
        Test.assertEqualMessage(Source.HUES.size(), Source.COUNT,
            "the hue table has drifted from Source.Kind");
        Test.assertEqualMessage(SOURCE_LABELS.size(), Source.COUNT,
            "the settings labels have drifted from Source.Kind");
        Test.assertEqualMessage(Source.SOURCE_OFF, Source.COUNT - 1,
            "Off is the picker's last entry, so it must be the last index");

        // Every kind must answer in both power modes without throwing, and
        // answer inside the ring. Off, and anything unavailable, report EMPTY;
        // seconds reports EMPTY asleep, which is the reason for the two passes.
        for (var kind = 0; kind < Source.COUNT; kind++) {
            for (var mode = 0; mode < 2; mode++) {
                var span = Source.span(kind, mode == 0);
                Test.assertEqualMessage(span.size(), 2,
                    "source " + kind + " did not report a span");
                Test.assertMessage(span[0] >= 0.0 && span[0] <= 1.0 &&
                                   span[1] >= 0.0 && span[1] <= 1.0,
                    "source " + kind + " reported a span outside 0-1");
            }
        }

        // Intensity minutes is a level, so it fills from the origin whatever
        // the week's activity happens to be.
        var minutes = Source.span(Source.SOURCE_INTENSITY_MINUTES, true);
        Test.assertEqualMessage(minutes[0], 0.0,
            "a level must start at the origin");
        logger.debug("intensity minutes span " + minutes[0] + " to " + minutes[1]);

        Test.assertEqualMessage(Source.span(Source.SOURCE_OFF, true)[1], 0.0,
            "Off must still be empty after the renumbering");
        logger.debug(Source.COUNT + " sources, all reporting in both modes");
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

    //! Holding the fills back in always-on works by handing the renderer a
    //! span nothing is inside, rather than branching ~1100 times a frame. That
    //! only holds if no dot in any layout ever falls in it — and the obvious
    //! wrong choice, (0, 0), lights any dot sitting exactly at the origin.
    (:test)
    function heldBackFillsLightNothingAnywhere(logger as Logger) as Boolean {
        var nothing = StatMap.noSpans();
        Test.assertMessage(!(StatMap.NEVER_LIT[0] > StatMap.NEVER_LIT[1]),
            "the empty span must not read as wrapping, or it lights everything");

        var lit = 0;
        var checked = 0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                if (StatMap.classify(dx, dy, nothing) % 2 == 1) {
                    lit++;
                }
                checked++;
            }
        }
        logger.debug(lit + " of " + checked + " dots lit");
        Test.assertEqualMessage(lit, 0,
            "a dot is lit by the empty span");
        return true;
    }

    //! The reason to want it is not only that it looks calmer: the filled dots
    //! are the brightest thing on the face and they barely move, which is
    //! exactly what burns an AMOLED in. Holding them back has to actually cut
    //! the light, or the option is cosmetic.
    //!
    //! This is now measured against the *lifted* held-back table, which is the
    //! bound on how bright that tier may go: the saving is what the option is
    //! for, so the mode has to stay clearly darker than showing the data no
    //! matter how far the field is lifted to make it readable.
    (:test)
    function heldBackFillsCutAlwaysOnLuminance(logger as Logger) as Boolean {
        Config.reload();
        var busy = everySpan(0.0, 0.82);
        var withFills = frameLuminance(busy, Palette.alwaysOn);
        var heldBack = frameLuminance(StatMap.noSpans(), Palette.heldBack);
        logger.debug("with fills " + withFills + ", held back " + heldBack);
        Test.assertMessage(heldBack < withFills,
            "holding the fills back must lower always-on luminance");
        Test.assertMessage(heldBack < BUDGET,
            "and must still sit inside the burn-in budget");
        return true;
    }

    //! What the lifted tier is for. Held back, the unfilled dots are not a
    //! backdrop to the data — they are the whole image — so the field has to
    //! read on its own. It must also be brighter than the tier it replaced, or
    //! the lift is a no-op and nothing here would notice.
    (:test)
    function theHeldBackFieldIsBrighterThanPlainAlwaysOn(logger as Logger) as Boolean {
        Config.reload();
        Test.assertMessage(Palette.WEAK_HELD_BACK > Palette.WEAK_ALWAYS_ON,
            "the held-back tier must be brighter than the ordinary always-on one");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(
                Palette.heldBack[ring * 2] != Palette.alwaysOn[ring * 2],
                "ring " + ring + " was not actually lifted");
        }

        var nothing = StatMap.noSpans();
        var before = frameLuminance(nothing, Palette.alwaysOn);
        var lifted = frameLuminance(nothing, Palette.heldBack);
        logger.debug(before + " -> " + lifted);
        Test.assertMessage(lifted > before,
            "the held-back field must be brighter than it was");
        Test.assertMessage(lifted < BUDGET,
            "and must still sit inside the burn-in budget");
        return true;
    }

    //! How far it was lifted, and why that number. The held-back field matches
    //! the awake one exactly, so the background does not change brightness when
    //! the wrist comes up — a raise purely adds the filled dots, with nothing
    //! shifting underneath them.
    //!
    //! The constant is asserted as well as the colours, because writing it as a
    //! bare 0.55 would pass every check here today and silently stop tracking
    //! the awake tier the moment that one is retuned.
    (:test)
    function theHeldBackFieldMatchesTheAwakeField(logger as Logger) as Boolean {
        Config.reload();
        Test.assertEqualMessage(Palette.WEAK_HELD_BACK, Palette.WEAK_ACTIVE,
            "the held-back tier must be defined as the awake one, not as a value");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(
                Palette.heldBack[ring * 2], Palette.active[ring * 2],
                "ring " + ring + " changes brightness on a raise");
        }

        // A span of zero length lights nothing — spanEndpoints pins that —
        // so this measures the unfilled tier and nothing else.
        var empty = everySpan(0.0, 0.0);
        var held = frameLuminance(empty, Palette.heldBack);
        var awake = frameLuminance(empty, Palette.active);
        logger.debug("held back " + held + " / awake " + awake);
        Test.assertEqualMessage(held, awake,
            "the held-back and awake fields must measure the same");
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

    //! Same contract for the rotation setting.
    (:test)
    function rotationSettingIsClamped(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_ROTATION, 99);
        Config.reload();
        Test.assertEqualMessage(StatMap.rotation, StatMap.ROTATION_RADIAL,
            "an out-of-range value must fall back to following the rings");

        Properties.setValue(StatMap.PROPERTY_ROTATION,
                            StatMap.ROTATION_UPRIGHT);
        Config.reload();
        Test.assertEqualMessage(StatMap.rotation, StatMap.ROTATION_UPRIGHT,
            "a valid value must be honoured");

        // The menu reads its sub-label straight off the setting, so an
        // unhandled value would index past the end of the label table.
        var menu = new SettingsMenu();
        menu.onShow();

        Properties.setValue(StatMap.PROPERTY_ROTATION,
                            StatMap.ROTATION_RADIAL);
        Config.reload();
        return true;
    }

    //! Every ring full is the brightest frame the face can draw. If that fits
    //! the budget, no real reading can blank the screen.
    (:test)
    function alwaysOnWorstCaseFitsBudget(logger as Logger) as Boolean {
        Config.reload();
        var full = everySpan(0.0, 1.0);
        var worst = frameLuminance(full, Palette.alwaysOn);
        logger.debug("worst-case always-on: " + worst);
        Test.assertMessage(worst < BUDGET,
            "always-on worst case exceeds the AMOLED burn-in budget");
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
        Properties.setValue(StatMap.PROPERTY_BACKING, StatMap.BACKING_OFF);
        Config.reload();
        var menu = new SettingsMenu();
        var before = subLabelOf(menu, 0);

        // What a sub-menu does when the user picks a different value.
        Properties.setValue(StatMap.PROPERTY_BACKING, StatMap.BACKING_WHITE);
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

        Properties.setValue(StatMap.PROPERTY_BACKING, StatMap.BACKING_OFF);
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
        logger.debug("orientations used: " + distinct);
        Test.assertEqualMessage(distinct, (1 << DotGrid.ORIENTATIONS) - 1,
            "the field should carry every orientation");
        return true;
    }

    //! Turning the crosses upright is a *drawing* decision, not a geometric
    //! one: which way a cross would point is pure geometry, so it stays cached
    //! either way and the renderer simply stops reading it. Wiring the setting
    //! into build() instead would work, and would quietly cost a full rebuild
    //! of ~1100 dots every time the setting changed — and worse, would tempt
    //! someone to make the *ring* mapping conditional next. This pins the
    //! cache as independent of the setting.
    (:test)
    function rotationDoesNotReachTheCache(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_ROTATION, StatMap.ROTATION_RADIAL);
        Config.reload();
        DotGrid.build();
        var turned = new [DotGrid.count] as Array<Number>;
        for (var i = 0; i < DotGrid.count; i++) {
            turned[i] = DotGrid.armOf[i];
        }

        Properties.setValue(StatMap.PROPERTY_ROTATION, StatMap.ROTATION_UPRIGHT);
        Config.reload();
        DotGrid.build();
        Test.assertEqualMessage(DotGrid.armOf.size(), turned.size(),
            "the cache changed size with the rotation setting");
        for (var i = 0; i < turned.size(); i++) {
            Test.assertEqualMessage(DotGrid.armOf[i], turned[i],
                "dot " + i + " changed orientation with the setting — the " +
                "cache must not depend on it");
        }
        logger.debug(turned.size() + " orientations unchanged by the setting");

        Properties.setValue(StatMap.PROPERTY_ROTATION, StatMap.ROTATION_RADIAL);
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
        Config.reload();
        DotGrid.build();

        var checked = 0;
        for (var i = 0; i < DotGrid.count; i++) {
            var dx = DotGrid.xs[i];
            var dy = DotGrid.ys[i];

            Test.assertEqualMessage(DotGrid.ringOf[i],
                StatMap.ringFor(dx, dy),
                "cached ring disagrees with StatMap.ringFor");

            var expected = StatMap.positionOf(dx, dy);
            Test.assertMessage((DotGrid.positionOf[i] - expected).abs() < 0.0001,
                "cached position disagrees with StatMap.positionOf");

            // Three dots in four take their orientation by mirroring a
            // fourth, so the reflection rule needs checking per dot.
            Test.assertEqualMessage(DotGrid.armOf[i],
                DotGrid.orientationFor(dx, dy),
                "cached orientation disagrees with orientationFor");
            checked++;
        }
        logger.debug(checked + " dots agree");
        Test.assertMessage(checked > 1000, "hardly any dots were checked");
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
        logger.debug("rings contiguous, largest " + longestRun + " dots");
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

    //! The mark's window is centred on the position it marks, and wraps.
    (:test)
    function markWindowSurroundsItsPosition(logger as Logger) as Boolean {
        var centres = [0.0, 0.001, 0.25, 0.5, 0.75, 0.999] as Array<Float>;
        var half = 0.02;
        for (var i = 0; i < centres.size(); i++) {
            var centre = centres[i];
            var window = StatMap.windowAround(centre, half);
            Test.assertMessage(StatMap.isLit(centre, window),
                "the window must contain the position it marks, at " + centre);
            // Normalised, because a probe past 1.0 is not a position at all
            // and a wrapping window would happily contain it.
            var past = centre + half + 0.01;
            if (past >= 1.0) { past -= 1.0; }
            Test.assertMessage(!StatMap.isLit(past, window),
                "and must not reach past its half-width, at " + centre);
            Test.assertMessage(window[0] >= 0.0 && window[0] < 1.0 &&
                               window[1] >= 0.0 && window[1] <= 1.0,
                "the window must be normalised onto the ring, at " + centre);
        }

        // Either end crossing the origin turns it into a wrapping span, which
        // is the same shape a sub-zero day range already takes.
        var low = StatMap.windowAround(0.005, 0.02);
        Test.assertMessage(low[0] > low[1], "a window over twelve must wrap");
        Test.assertMessage(StatMap.isLit(0.995, low),
            "and must light the dots before twelve");

        // A half-width wider than the ring cannot be allowed to wrap onto
        // itself and light nothing.
        var huge = StatMap.windowAround(0.5, 0.9);
        Test.assertEqualMessage(huge[0], 0.0, "an oversized window must open");
        Test.assertEqualMessage(huge[1], 1.0, "an oversized window must fill");
        return true;
    }

    //! The mark must land on exactly one real dot, near the middle of its ring.
    //!
    //! Two failures hide here. The window can fall clean between dots — the
    //! reason it is sized per ring, since the same position units are three
    //! times coarser on the inner rings than in a band — and markedDot can
    //! pick a dot out at the ring's edge, where a single white dot reads as a
    //! stray lit one rather than a marker.
    //!
    //! The bands cannot represent every position on every ring: the leftmost
    //! band does not reach the bottom of a round screen, so its lowest few
    //! degrees have no dots and neither does the fill. Each ring is therefore
    //! probed across the range it can represent, and that range is logged so a
    //! regression that narrows it shows up.
    (:test)
    function markLandsOnOneCentralDot(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();

        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var from = DotGrid.ringStart[ring];
            var to = DotGrid.ringStart[ring + 1];
            var half = DotGrid.markerHalf[ring];

            var lowest = 1.0;
            var highest = 0.0;
            for (var i = from; i < to; i++) {
                var p = DotGrid.positionOf[i];
                if (p < lowest) { lowest = p; }
                if (p > highest) { highest = p; }
            }

            var worstOff = 0;
            for (var step = 0; step <= 20; step++) {
                var mark = lowest + (highest - lowest) * step / 20.0;
                var window = StatMap.windowAround(mark, half);
                var at = DotGrid.markedDot(ring, window);

                Test.assertMessage(at >= 0,
                    "ring " + ring + ": the mark at " + mark +
                    " found no dot");
                Test.assertMessage(at >= from && at < to,
                    "the marked dot must belong to the ring it marks");
                Test.assertMessage(
                    StatMap.isLit(DotGrid.positionOf[at], window),
                    "the marked dot must sit inside the mark's window");

                // Nothing else in the window may be nearer the middle.
                var middle = DotGrid.markMiddle[ring];
                var chosen = offFromMiddle(at, middle);
                for (var i = from; i < to; i++) {
                    if (StatMap.isLit(DotGrid.positionOf[i], window)) {
                        Test.assertMessage(
                            offFromMiddle(i, middle) >= chosen,
                            "ring " + ring + ": dot " + i + " sits nearer " +
                            "the middle than the one the mark chose");
                    }
                }
                if (chosen > worstOff) { worstOff = chosen; }
            }
            logger.debug("ring " + ring + ": positions " + lowest + ".." +
                         highest + ", worst offset from middle " + worstOff);
        }
        Config.reload();
        return true;
    }

    //! How far a dot sits from the middle of its ring, in markedDot's terms.
    function offFromMiddle(i as Number, middle as Number) as Number {
        var dx = DotGrid.xs[i];
        var dy = DotGrid.ys[i];
        return (dx * dx + dy * dy - middle).abs();
    }

    //! An unmarked ring must not quietly mark dot zero.
    (:test)
    function anUnmarkedRingMarksNothing(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        // NEVER_LIT is the span nothing falls in; as a window it must find no
        // dot at all, which is what -1 means to the renderer.
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(
                DotGrid.markedDot(ring, StatMap.NEVER_LIT), -1,
                "ring " + ring + " marked a dot with nothing to mark");
        }
        return true;
    }

    //! The current temperature moves while today's low and high sit still, so
    //! a fingerprint built from the spans alone calls that frame identical and
    //! the mark freezes on screen until the skip cap fires seconds later.
    //! Nothing else would report that: the face just stops telling the truth.
    (:test)
    function markMovesForceARedraw(logger as Logger) as Boolean {
        var view = new CrossoverView();
        var spans = everySpan(0.2, 0.8);

        var at12 = new [StatMap.RINGS] as Array<Float>;
        var at18 = new [StatMap.RINGS] as Array<Float>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            at12[i] = Source.NO_MARKER;
            at18[i] = Source.NO_MARKER;
        }
        at12[0] = 12.0 / 60.0;
        at18[0] = 18.0 / 60.0;

        var before = view.fingerprint(spans, at12, null);
        var after = view.fingerprint(spans, at18, null);
        logger.debug("fingerprint is " + before.size() + " values");
        Test.assertMessage(!FrameGate.same(before, after),
            "a mark that moved must change the fingerprint");
        Test.assertMessage(
            FrameGate.same(before, view.fingerprint(spans, at12, null)),
            "an unchanged mark must leave the fingerprint alone");
        return true;
    }

    //! Always-on never marks. White is the most luminous thing the face can
    //! draw and always-on is the mode measured against the burn-in budget, so
    //! the mark is awake-only the way the hand backing already is.
    (:test)
    function alwaysOnCarriesNoMark(logger as Logger) as Boolean {
        var none = StatMap.noMarkers();
        Test.assertEqualMessage(none.size(), StatMap.RINGS,
            "every ring needs an entry, or the renderer reads past the end");
        for (var i = 0; i < StatMap.RINGS; i++) {
            Test.assertEqualMessage(none[i], Source.NO_MARKER,
                "ring " + i + " still carries a mark");
        }
        // The renderer's test is `mark >= 0.0`, and positions never are.
        Test.assertMessage(Source.NO_MARKER < 0.0,
            "the empty marker must sit outside every position, or it draws");

        // Nothing but temperature marks anything at all.
        for (var kind = 0; kind < Source.COUNT; kind++) {
            if (kind == Source.SOURCE_TEMPERATURE) {
                continue;
            }
            Test.assertEqualMessage(Source.marker(kind), Source.NO_MARKER,
                "source " + kind + " marks a position it should not");
        }
        return true;
    }

    //! The mark trades a ring-coloured dot for a white one, which is the
    //! largest luminance step a single dot can make. Awake has no budget, but
    //! the fattest mark measured above is worth pricing anyway.
    (:test)
    function markCostsLittleLuminance(logger as Logger) as Boolean {
        Config.reload();
        var full = everySpan(0.0, 1.0);
        var base = frameLuminance(full, Palette.active);
        var area = Math.PI * DotGrid.RADIUS * DotGrid.RADIUS;
        // One dot per ring is the most the mark can ever cost, every one of
        // them swapped from the dimmest theme colour to the brightest mark.
        // The mark is tinted per ring now, so this prices the brightest of
        // them rather than the pure white it used to be.
        var dimmest = 1.0;
        var brightestMark = 0.0;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var lum = relativeLuminance(Palette.active[ring * 2 + 1]);
            if (lum < dimmest) { dimmest = lum; }
            var mark = relativeLuminance(Palette.markerOf[ring]);
            if (mark > brightestMark) { brightestMark = mark; }
        }
        // A marked dot is filled rather than a cross, so it lights DOT squared
        // pixels where an ordinary dot lights 2*DOT-1.
        var step = (brightestMark - dimmest) *
                   DotGrid.DOT * DotGrid.DOT * StatMap.RINGS / area;
        logger.debug("awake full field " + base + " plus at most " + step);
        Test.assertMessage(base + step < BUDGET,
            "even awake, the mark must not push the field past the budget");
        return true;
    }

    //! The mark carries a touch of the band it sits on, which is what stopped
    //! it reading as a hole punched through the field rather than a point on
    //! it. Three things keep that a tint rather than a repaint.
    //!
    //! It has to stay clearly brighter than the filled band, because once it
    //! is not, only the solid-versus-cross shape is left carrying it. It has to
    //! sit *between* white and the band on every channel — that is what "tinted
    //! toward" means, and a mix that overshot would land outside them. And it
    //! has to differ from ring to ring, or the per-ring table earns nothing
    //! over the single constant it replaced.
    (:test)
    function theMarkCarriesATouchOfItsBand(logger as Logger) as Boolean {
        Config.reload();
        Test.assertEqualMessage(Palette.markerOf.size(), StatMap.RINGS,
            "every ring needs a mark colour");
        Test.assertMessage(
            Palette.MARKER_TINT > 0.0 && Palette.MARKER_TINT < 1.0,
            "a tint of 0 is the pure white this replaced, and 1 is the band");

        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var mark = Palette.markerOf[ring];
            var band = Palette.active[ring * 2 + 1];
            Test.assertMessage(mark != Palette.MARKER,
                "ring " + ring + " kept the untinted white");
            Test.assertMessage(
                relativeLuminance(mark) > relativeLuminance(band),
                "the mark on ring " + ring + " must outshine its own band");

            for (var shift = 0; shift <= 16; shift += 8) {
                var m = (mark >> shift) & 0xFF;
                var b = (band >> shift) & 0xFF;
                var w = (Palette.MARKER >> shift) & 0xFF;
                var low = (b < w) ? b : w;
                var high = (b < w) ? w : b;
                Test.assertMessage(m >= low && m <= high,
                    "ring " + ring + " channel " + shift + " landed outside " +
                    "the band and white it is mixed from");
            }
            logger.debug("ring " + ring + " mark " + mark + " band " + band);
        }

        for (var a = 0; a < StatMap.RINGS; a++) {
            for (var b = a + 1; b < StatMap.RINGS; b++) {
                Test.assertMessage(Palette.markerOf[a] != Palette.markerOf[b],
                    "rings " + a + " and " + b + " share a mark colour, so " +
                    "the per-ring table is doing nothing");
            }
        }
        return true;
    }

    //! Recover a dot's column from its x offset — build() knows it and the
    //! cache does not store it, so the checks that walk the lattice by grid
    //! cell have to work it back out.
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

    // --- the seconds source --------------------------------------------------

    //! The sweep is the minute expressed as a level: 0.0 at :00, climbing to
    //! 59/60, and back to zero on the next minute rather than past 1.0. A span
    //! end above 1.0 would not simply saturate — it would light a ring's dots
    //! in the wrong order — so the reset is asserted, not assumed.
    (:test)
    function theSweepFillsItsMinuteAndResets(logger as Logger) as Boolean {
        Test.assertEqualMessage(ClockData.fraction(0), 0.0,
            ":00 must sit at the ring's origin");
        for (var second = 0; second < 60; second += 15) {
            var expected = second / 60.0;
            Test.assertMessage((ClockData.fraction(second) - expected).abs() < 0.001,
                "each second must land on its own stop around the ring");
        }
        Test.assertMessage(ClockData.fraction(59) < 1.0,
            "the sweep must never reach a full turn, or it would wrap");
        Test.assertEqualMessage(ClockData.fraction(60), 0.0,
            "the minute rolling over must put the sweep back at the origin");

        // Whatever the clock says right now, the reading is a level pinned to
        // the origin and landing on one of the sixty stops.
        var live = Source.span(Source.SOURCE_SECONDS, true);
        Test.assertEqualMessage(live[0], 0.0,
            "seconds is a level, so its span must start at the origin");
        var stop = live[1] * 60.0;
        logger.debug("the sweep is at " + live[1] + ", stop " + stop);
        Test.assertMessage((stop - (stop + 0.5).toNumber()).abs() < 0.001,
            "the sweep must sit on a whole second, not between two");
        Test.assertMessage(live[1] >= 0.0 && live[1] < 1.0,
            "the sweep must stay inside the ring");
        return true;
    }

    //! Always-on is asked for one frame a minute, so a per-second reading could
    //! only ever be stale there — and it is the mode the burn-in and luminance
    //! rules are written against. Asleep the ring must be genuinely dark, not
    //! dark-looking: this walks every dot of every layout to say so.
    (:test)
    function secondsGoDarkInAlwaysOn(logger as Logger) as Boolean {
        var asleep = Source.span(Source.SOURCE_SECONDS, false);
        Test.assertEqualMessage(asleep[0], asleep[1],
            "an asleep seconds ring must report a span of no length");

        var spans = new [StatMap.RINGS] as Array<Array<Float> >;
        for (var i = 0; i < StatMap.RINGS; i++) {
            spans[i] = asleep;
        }

        var checked = 0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                checked++;
                Test.assertMessage(
                    StatMap.classify(dx, dy, spans) % 2 == 0,
                    "an asleep seconds ring lit a dot");
            }
        }
        logger.debug("checked " + checked + " dots");
        Test.assertMessage(checked > 0, "the walk must actually visit dots");
        return true;
    }

    //! Awake, the same source must not be inert — otherwise the test above
    //! would pass just as well against a source that never reports anything.
    (:test)
    function secondsAreLiveWhileAwake(logger as Logger) as Boolean {
        // Half past the minute, chosen rather than read, so this cannot pass
        // or fail depending on when the suite happens to run.
        var half = [0.0, ClockData.fraction(30)] as Array<Float>;
        var lit = 0;
        var dark = 0;
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                if (StatMap.isLit(StatMap.positionOf(dx, dy), half)) {
                    lit++;
                } else {
                    dark++;
                }
            }
        }
        logger.debug("at :30 the sweep lights " + lit + " dots, " +
                     dark + " still dark");
        Test.assertMessage(lit > 0, "the sweep must light something at :30");
        Test.assertMessage(dark > 0, "and must not have filled the ring yet");
        return true;
    }

    //! The view's fingerprint, laid out as CrossoverView.fingerprint() lays it:
    //! the drift pair, the backing and its minute, then every ring's two ends.
    //! Only the first ring's sweep moves here.
    function fingerprintAtSecond(second as Number) as Array<Float> {
        var out = new [4 + (StatMap.RINGS * 2)] as Array<Float>;
        for (var i = 0; i < out.size(); i++) {
            out[i] = 0.0;
        }
        out[2] = -1.0;                              //! no backing
        out[5] = ClockData.fraction(second);        //! ring 1's span end
        return out;
    }

    //! The gate skips any frame whose fingerprint matches the last one drawn,
    //! and caps that at MAX_SKIPS. A seconds ring has to move the fingerprint
    //! every tick or the sweep would visibly stall for seconds at a time.
    //! Nothing in the gate was changed to allow this — the span end is already
    //! part of the fingerprint — so this test is what says so out loud.
    (:test)
    function everySecondOpensTheFrameGate(logger as Logger) as Boolean {
        var drawn = FrameGate.drawn;
        var suppressed = FrameGate.suppressed;
        FrameGate.forget();
        FrameGate.drawn = 0;
        FrameGate.suppressed = 0;

        var opened = 0;
        for (var second = 0; second < 60; second++) {
            if (FrameGate.shouldDraw(fingerprintAtSecond(second))) {
                opened++;
            }
        }
        logger.debug("the gate opened on " + opened + " of 60 ticks");
        Test.assertEqualMessage(opened, 60,
            "a moving sweep must never be skipped — it stalled on " +
            (60 - opened) + " ticks");

        // And the gate is still a gate: a tick that does not move it is still
        // skipped, so this is the fingerprint changing rather than the gate
        // having been loosened.
        FrameGate.forget();
        Test.assertMessage(FrameGate.shouldDraw(fingerprintAtSecond(7)),
            "the first frame after forgetting is always drawn");
        Test.assertMessage(!FrameGate.shouldDraw(fingerprintAtSecond(7)),
            "an unmoved fingerprint must still be skipped");

        FrameGate.forget();
        FrameGate.drawn = drawn;
        FrameGate.suppressed = suppressed;
        return true;
    }
}
