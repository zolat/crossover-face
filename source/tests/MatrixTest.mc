import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
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

    //! Ceiling for what the dot cache may cost, in bytes. Deliberately loose:
    //! it is here to catch a new per-dot array, which would move the figure by
    //! thousands, not to hold the current number to the byte.
    const CACHE_CEILING = 56000;

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

            // Which ring the cache put this dot in is now said by where it
            // sits, not by a parallel array — and checking the placement
            // against the mapping is a stronger claim than the array was. The
            // array was written by the same pass that laid out the blocks, so
            // a grouping bug could be mirrored into it and agree with itself.
            Test.assertEqualMessage(ringHolding(i), StatMap.ringFor(dx, dy),
                "the block a dot was placed in disagrees with StatMap.ringFor");

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
    //! not cosmetic — it is what lets the renderer hold its pen, since a ring
    //! arrives as whole rows and a run of dots on the same side of the fill's
    //! leading edge shares a colour.
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
                // Against the mapping itself, not against a cached copy of it:
                // this is the claim the grouping actually has to make good on,
                // since the renderer reads a dot's ring from which block it is
                // walking and nothing else.
                Test.assertEqualMessage(
                    StatMap.ringFor(DotGrid.xs[i], DotGrid.ys[i]), ring,
                    "a dot inside ring " + ring + "'s block maps to ring " +
                    StatMap.ringFor(DotGrid.xs[i], DotGrid.ys[i]));
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
    //! times coarser on the innermost ring than on the outermost — and
    //! markedDot can pick a dot out at the ring's edge, where a single white
    //! dot reads as a stray lit one rather than a marker.
    //!
    //! Every ring carries a full turn, so there is no stretch of position it
    //! cannot represent. Each is still probed across the range its own dots
    //! actually span, and that range is logged, so a regression that narrows
    //! it shows up.
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

    //! The mark is remembered between frames, and never past a rebuild.
    //!
    //! Placing a mark walks the whole ring, so a marked ring used to be walked
    //! twice on every drawn frame. The mark moves with the current temperature
    //! — hourly at best — while a seconds ring draws sixty times a minute, so
    //! almost every one of those walks re-derived the answer it had just given.
    //!
    //! Two things have to hold for the memo to be safe, and both are asserted
    //! here rather than argued: it agrees with the direct search at every
    //! position, and it forgets on a rebuild. The second is the sharp one — a
    //! cached mark is an *index* into arrays that build() rewrites, so a stale
    //! one is not a stale answer but a wrong dot, possibly on the wrong ring.
    (:test)
    function theMarkedDotIsRememberedButNotPastARebuild(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();

        // The memo must agree with the search it replaces, everywhere.
        var checked = 0;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            for (var step = 0; step < 40; step++) {
                var mark = step / 40.0;
                var direct = DotGrid.markedDot(
                    ring, StatMap.windowAround(mark, DotGrid.markerHalf[ring]));
                Test.assertEqualMessage(DotGrid.markedDotFor(ring, mark), direct,
                    "the remembered mark disagrees with the search on ring " +
                    ring + " at " + mark);
                // And again, now that it is cached, which is the path that
                // actually runs on all but the first frame.
                Test.assertEqualMessage(DotGrid.markedDotFor(ring, mark), direct,
                    "the second ask must give the same answer as the first");
                checked++;
            }
        }
        logger.debug("agreed with the direct search on " + checked + " positions");

        // An unmarked ring caches its nothing, rather than rediscovering it.
        Test.assertEqualMessage(
            DotGrid.markedDotFor(0, Source.NO_MARKER), -1,
            "a ring with no mark must land on no dot");
        Test.assertEqualMessage(
            DotGrid.markedDotFor(0, Source.NO_MARKER), -1,
            "and must still land on no dot when the answer is remembered");

        // The empty key has to sit outside NO_MARKER, which is a real answer.
        Test.assertMessage(DotGrid.NO_MARK_KEY < Source.NO_MARKER,
            "the empty cache key must be a position no source can ever report");

        // A rebuild rewrites the arrays a cached index points into, so the
        // memo must not survive one.
        var at = DotGrid.markedDotFor(1, 0.25);
        Test.assertMessage(at >= 0, "0.25 must mark some dot on ring 1");
        DotGrid.invalidate();
        DotGrid.ensureBuilt();
        Test.assertEqualMessage(DotGrid.markedFor[1], DotGrid.NO_MARK_KEY,
            "a rebuild must forget every cached mark");
        Test.assertEqualMessage(DotGrid.markedDotFor(1, 0.25), at,
            "and then find the same dot again from scratch");
        return true;
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

        var none = noOvers();
        // The view refills one buffer every frame, so a copy has to be taken
        // before asking for the next print — exactly as FrameGate does.
        var before = copyOf(view.ringPrint(spans, at12, none));
        var after = copyOf(view.ringPrint(spans, at18, none));
        logger.debug("the ring print is " + before.size() + " values");
        Test.assertMessage(!FrameGate.same(before, after),
            "a mark that moved must change the ring print");
        Test.assertMessage(
            FrameGate.same(before, view.ringPrint(spans, at12, none)),
            "an unchanged mark must leave the ring print alone");

        // And it must move *that ring's* slice, not merely the frame: a mark
        // on ring 0 that dirtied ring 3 as well would give back the saving.
        Test.assertMessage(FrameGate.ringMoved(before, after, 0),
            "the ring carrying the mark must read as moved");
        for (var ring = 1; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(!FrameGate.ringMoved(before, after, ring),
                "ring " + ring + " must not be dirtied by ring 0's mark");
        }
        return true;
    }

    //! A copy, so two prints can be held at once.
    function copyOf(values as Array<Float>) as Array<Float> {
        var out = new [values.size()] as Array<Float>;
        for (var i = 0; i < values.size(); i++) {
            out[i] = values[i];
        }
        return out;
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

    //! Every ring inside its goal, and every ring past it.
    function noOvers() as Array<Boolean> {
        return everyOver(false);
    }

    function allOvers() as Array<Boolean> {
        return everyOver(true);
    }

    function everyOver(value as Boolean) as Array<Boolean> {
        var out = new [StatMap.RINGS] as Array<Boolean>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            out[i] = value;
        }
        return out;
    }

    //! Past the goal the span stops describing the fill and describes the
    //! second lap, so 100% and 250% no longer draw the same band.
    //!
    //! The cap is the interesting end. At twice the goal the lap is full, and
    //! carrying on round would report "only just started" at the exact moment
    //! of doing double — the reading would run backwards as the day went on.
    (:test)
    function overGoalRunsASecondLap(logger as Logger) as Boolean {
        var readings = [0.0, 0.34, 1.0, 1.05, 1.34, 1.99, 2.0, 3.5]
                       as Array<Float>;
        var laps = [0.0, 0.34, 1.0, 0.05, 0.34, 0.99, 1.0, 1.0]
                   as Array<Float>;
        for (var i = 0; i < readings.size(); i++) {
            var span = Source.goal(readings[i], true);
            logger.debug(readings[i] + " -> [" + span[0] + ", " + span[1] + "]");
            Test.assertEqualMessage(span[0], 0.0,
                "a goal always fills from the origin");
            Test.assertMessage((span[1] - laps[i]).abs() < 0.001,
                "a reading of " + readings[i] + " should span to " + laps[i] +
                " but spanned to " + span[1]);
        }
        return true;
    }

    //! Exactly the goal is not over it. The test is strictly greater, and at
    //! `>=` a ring hitting 100% would report a zero-length lap and drop a mark
    //! on the origin at the very moment the goal was met.
    (:test)
    function exactlyTheGoalIsNotOver(logger as Logger) as Boolean {
        Test.assertMessage(!Source.isOver(1.0, true),
            "exactly the goal must read as full, not as a lap of nothing");
        Test.assertMessage(Source.isOver(1.001, true),
            "a step past the goal must start the second lap");

        var atGoal = Source.goal(1.0, true);
        Test.assertMessage((atGoal[1] - 1.0).abs() < 0.001,
            "a met goal must still fill its ring end to end");
        return true;
    }

    //! The invariant the whole feature rests on: the span is a lap exactly when
    //! the flag says it is. If the two could ever disagree, the renderer would
    //! draw a 105% ring's lap span without swapping its tiers — and a ring that
    //! had just beaten its goal would read as 5% of the way to it.
    (:test)
    function theLapAndTheOverFlagAgree(logger as Logger) as Boolean {
        for (var mode = 0; mode < 2; mode++) {
            var awake = (mode == 1);
            for (var step = 0; step <= 250; step++) {
                var value = step / 100.0;
                var over = Source.isOver(value, awake);
                var span = Source.goal(value, awake);
                var capped = (value > 1.0) ? 1.0 : value;
                var lap = (value >= 2.0) ? 1.0 : value - 1.0;
                var expected = over ? lap : capped;
                Test.assertMessage((span[1] - expected).abs() < 0.001,
                    "awake " + awake + " at " + value + ": flag says over=" +
                    over + " but the span ends at " + span[1] +
                    ", not " + expected);
            }
        }
        // And asleep nothing is ever over, however far past the goal it is.
        Test.assertMessage(!Source.isOver(2.5, false),
            "always-on must not report an overflow");
        var asleep = Source.goal(2.5, false);
        Test.assertMessage((asleep[1] - 1.0).abs() < 0.001,
            "asleep, a beaten goal still reads as simply full");
        return true;
    }

    //! Always-on shows a beaten goal as a plain full band: no brighter tier and
    //! no white dot, the way it already carries no mark and no hand backing.
    //! This is the mode measured against the burn-in budget, and the mode
    //! nobody is reading closely.
    (:test)
    function alwaysOnCarriesNoOverflow(logger as Logger) as Boolean {
        Config.reload();
        var none = StatMap.overs(false);
        Test.assertEqualMessage(none.size(), StatMap.RINGS,
            "every ring needs an entry, or the renderer reads past the end");
        for (var i = 0; i < StatMap.RINGS; i++) {
            Test.assertMessage(!none[i],
                "ring " + i + " reports an overflow in always-on");
        }
        // Whatever the watch happens to read, no source is over while asleep.
        for (var kind = 0; kind < Source.COUNT; kind++) {
            Test.assertMessage(!Source.over(kind, false),
                "source " + kind + " overflows in always-on");
        }
        return true;
    }

    //! Only a goal can be beaten. Everything else is bounded by what it
    //! measures, cyclic, or a range whose wrap is the design — so an overflow
    //! there would be meaningless rather than merely unused.
    (:test)
    function onlyGoalSourcesOverflow(logger as Logger) as Boolean {
        for (var kind = 0; kind < Source.COUNT; kind++) {
            if (kind == Source.SOURCE_STEPS ||
                kind == Source.SOURCE_INTENSITY_MINUTES) {
                continue;
            }
            Test.assertMessage(!Source.over(kind, true),
                "source " + kind + " has no goal but reports overflowing one");
        }
        // The two that do are wired to the shared predicate rather than
        // testing for themselves — asserted against the reading rather than a
        // fixed answer, since the simulator's own step count decides it.
        Test.assertEqualMessage(
            Source.over(Source.SOURCE_STEPS, true),
            Source.isOver(WatchData.steps(), true),
            "steps must decide over-ness the same way its span does");
        Test.assertEqualMessage(
            Source.over(Source.SOURCE_INTENSITY_MINUTES, true),
            Source.isOver(WatchData.intensityMinutes(), true),
            "intensity minutes must decide over-ness the same way its span does");
        return true;
    }

    //! Where the over tier sits, and why it is a mix rather than a brightening.
    //!
    //! Scaling the colour up is not available — that is the whole reason LIFT
    //! is 1.0 — so "stronger" is the band mixed toward white. It has to clear
    //! the band it replaces, or beating the goal changes nothing; and it has to
    //! stay under the mark, because the waterline dot lands *on* this tier and
    //! is the only thing saying how far the lap has run.
    (:test)
    function theOverTierReadsBrighterThanTheBand(logger as Logger) as Boolean {
        Config.reload();
        Test.assertEqualMessage(Palette.overOf.size(), StatMap.RINGS,
            "every ring needs an over colour");
        Test.assertMessage(
            Palette.OVER_TINT > Palette.MARKER_TINT && Palette.OVER_TINT < 1.0,
            "the over tier must sit between the mark's tint and the band");

        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var weak = relativeLuminance(Palette.active[ring * 2]);
            var band = relativeLuminance(Palette.active[ring * 2 + 1]);
            var over = relativeLuminance(Palette.overOf[ring]);
            var mark = relativeLuminance(Palette.markerOf[ring]);
            logger.debug("ring " + ring + ": weak " + weak + " band " + band +
                         " over " + over + " mark " + mark);
            Test.assertMessage(weak < band,
                "ring " + ring + ": the unfilled tier must stay under the band");
            Test.assertMessage(band < over,
                "ring " + ring + ": beating the goal must read stronger than " +
                "merely meeting it");
            Test.assertMessage(over < mark,
                "ring " + ring + ": the waterline dot must outshine the lap " +
                "it sits on, or nothing says how far the lap has run");

            // "Tinted toward white" means exactly that: between the two.
            for (var shift = 0; shift <= 16; shift += 8) {
                var o = (Palette.overOf[ring] >> shift) & 0xFF;
                var b = (Palette.active[ring * 2 + 1] >> shift) & 0xFF;
                var w = (Palette.MARKER >> shift) & 0xFF;
                var low = (b < w) ? b : w;
                var high = (b < w) ? w : b;
                Test.assertMessage(o >= low && o <= high,
                    "ring " + ring + " channel " + shift + " landed outside " +
                    "the band and white it is mixed from");
            }
        }

        for (var a = 0; a < StatMap.RINGS; a++) {
            for (var b = a + 1; b < StatMap.RINGS; b++) {
                Test.assertMessage(Palette.overOf[a] != Palette.overOf[b],
                    "rings " + a + " and " + b + " share an over colour, so " +
                    "the per-ring table is doing nothing");
            }
        }
        return true;
    }

    //! The waterline is the end of the lap, taken from the span rather than
    //! read from the source a second time — so the dot cannot drift from the
    //! arc it terminates. A ring that is not over keeps its own source's mark.
    (:test)
    function theWaterlineMarksTheEndOfTheLap(logger as Logger) as Boolean {
        Config.reload();
        var spans = everySpan(0.0, 0.34);
        var marks = StatMap.markers(spans, allOvers());
        for (var i = 0; i < StatMap.RINGS; i++) {
            Test.assertMessage((marks[i] - 0.34).abs() < 0.001,
                "ring " + i + " marked " + marks[i] + " rather than the end " +
                "of its lap");
        }

        var unchanged = StatMap.markers(spans, noOvers());
        for (var i = 0; i < StatMap.RINGS; i++) {
            Test.assertEqualMessage(unchanged[i],
                Source.marker(StatMap.rings[i]),
                "ring " + i + " is not over, so its own source decides the mark");
        }
        return true;
    }

    //! A lap that reached its end marks nothing. Its waterline is the ring's
    //! own edge, so there is no boundary left to point at — and a window
    //! centred on 1.0 wraps past the origin, which would let markedDot choose
    //! between dots at both ends of the ring and land the dot at the wrong one.
    (:test)
    function aFullLapHasNoWaterline(logger as Logger) as Boolean {
        Config.reload();
        var marks = StatMap.markers(everySpan(0.0, 1.0), allOvers());
        for (var i = 0; i < StatMap.RINGS; i++) {
            Test.assertEqualMessage(marks[i], Source.NO_MARKER,
                "ring " + i + " marked a completed lap at " + marks[i]);
        }
        // Just short of the end still marks, so this is the cap and not an
        // off-by-one that quietly swallowed the top of the lap.
        var nearly = StatMap.markers(everySpan(0.0, 0.99), allOvers());
        Test.assertMessage(nearly[0] > 0.0,
            "a lap one step short of full must still carry its waterline");
        return true;
    }

    //! Every ring past its goal is the brightest field the face can draw, since
    //! the whole ring is lit and part of it in the raised tier. Awake carries no
    //! burn-in budget, but the frame is worth pricing against it anyway — the
    //! same reasoning as the mark's own luminance test.
    (:test)
    function overGoalCostsLittleLuminance(logger as Logger) as Boolean {
        Config.reload();
        // What an over ring hands the dot loop: unfilled becomes the band,
        // filled becomes the over tier. Every dot at the over tier is the worst
        // it can reach, so the whole ring is spanned.
        var swapped = new [StatMap.RINGS * 2] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            swapped[ring * 2] = Palette.active[ring * 2 + 1];
            swapped[ring * 2 + 1] = Palette.overOf[ring];
        }
        var full = everySpan(0.0, 1.0);
        var met = frameLuminance(full, Palette.active);
        var over = frameLuminance(full, swapped);
        logger.debug("goal met " + met + ", every ring over " + over);
        Test.assertMessage(over > met,
            "beating every goal must actually raise the field");
        Test.assertMessage(over < BUDGET,
            "every ring over goal exceeds the luminance budget");
        return true;
    }

    //! Crossing the goal is the one change the frame gate cannot see in the
    //! spans: a fill of 0.05 and a lap of 0.05 are the same two numbers, and
    //! the frame the ring changes colour on is one the gate would skip.
    //!
    //! The marks are held identical here on purpose. The waterline moves at the
    //! same moment and would mask this today, so testing through it would only
    //! prove the dot exists — not that the flags are in the fingerprint.
    (:test)
    function overFlagsForceARedraw(logger as Logger) as Boolean {
        var view = new CrossoverView();
        var spans = everySpan(0.0, 0.05);
        var marks = new [StatMap.RINGS] as Array<Float>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            marks[i] = Source.NO_MARKER;
        }

        var under = copyOf(view.ringPrint(spans, marks, noOvers()));
        var over = copyOf(view.ringPrint(spans, marks, allOvers()));
        logger.debug("the ring print is " + under.size() + " values");
        Test.assertMessage(!FrameGate.same(under, over),
            "crossing the goal must change the ring print — the span alone " +
            "cannot tell a lap of 0.05 from a fill of 0.05");
        Test.assertMessage(
            FrameGate.same(under, view.ringPrint(spans, marks, noOvers())),
            "an unchanged flag must leave the ring print alone");
        return true;
    }

    //! Drive the real renderer, into a real Dc, with a ring past its goal.
    //!
    //! Everything above tests the decisions; this tests that the draw actually
    //! runs. The over path adds an array the renderer indexes per ring and a
    //! palette table it indexes the same way, and a mistake in either is an
    //! out-of-bounds that no amount of checking the inputs would catch — it
    //! only shows up when something walks the rings and draws.
    //!
    //! Every ring is driven over at once, and one of them is temperature, so
    //! the ramp and the swap are exercised together. The marks land on the
    //! waterline, which is the case that draws a marked dot on top of the
    //! raised tier rather than on the plain band.
    //!
    //! Both rotations are drawn, because that is the one branch left inside the
    //! dot loop, and both with and without the hand backing, because backing is
    //! the only other thing that can win a dot away from the tiers.
    (:test)
    function theRendererDrawsAnOverGoalRing(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();

        // A real Dc, off screen, and a *small* one. A full 390x390 buffer is
        // ~304KB against a 128KB budget — it is why the face cannot cache its
        // field, and asking for one here takes the test runner out with it.
        // Size does not matter to what this covers: the renderer still walks
        // every dot and picks every colour, and the drawing clips.
        var bitmap = Graphics.createBufferedBitmap(
            {:width => 64, :height => 64}).get();
        if (!(bitmap instanceof Graphics.BufferedBitmap)) {
            logger.debug("no buffered bitmap available; draw not exercised");
            return true;
        }
        var dc = bitmap.getDc();

        var spans = everySpan(0.0, 0.34);
        var overs = allOvers();
        var marks = StatMap.markers(spans, overs);
        // One ring on the ramp, so the ramp and the swap are drawn together.
        var was = StatMap.rings[1];
        StatMap.rings[1] = Source.SOURCE_TEMPERATURE;

        var turning = StatMap.rotation;
        var rotations = [StatMap.ROTATION_RADIAL, StatMap.ROTATION_UPRIGHT]
                        as Array<Number>;
        for (var r = 0; r < rotations.size(); r++) {
            StatMap.rotation = rotations[r];
            MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                                Palette.rampActive, null,
                                FrameGate.everything(), true);
            MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                                Palette.rampActive, Palette.BACKING_WHITE,
                                FrameGate.everything(), true);
            // And again drawing one ring into what is already there, which is
            // the path a moved span actually takes.
            MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                                Palette.rampActive, null,
                                onlyRingDirty(1), false);
            logger.debug("rotation " + StatMap.rotation + " drew an over field");
        }

        StatMap.rings[1] = was;
        StatMap.rotation = turning;
        return true;
    }

    //! A clean ring is not walked, and a moved mark leaves no ghost.
    //!
    //! This is the claim the whole per-ring gate rests on, driven through the
    //! real renderer into a real Dc rather than argued about. The screen cannot
    //! be read back — Dc has no getPixel — so the renderer reports which rings
    //! it walked and how many stale marks it rubbed out, and this holds it to
    //! the dirty set it was handed.
    //!
    //! The erase is the subtle half. A mark is a solid block and a dot is a
    //! cross, so repainting a ring covers 9 of the 25 pixels a mark occupies.
    //! Without rubbing the cell out first, the other 16 survive as a ghost of
    //! the previous reading — and on the temperature ring, which is the only
    //! one that marks, that ghost would sit there until the next full clear.
    (:test)
    function aCleanRingIsNotWalkedAndAMovedMarkLeavesNoGhost(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        // Same 64x64 buffer theRendererDrawsAnOverGoalRing uses, and for the
        // same reason: a full-screen one is ~304KB and takes the runner out.
        var bitmap = Graphics.createBufferedBitmap(
            {:width => 64, :height => 64}).get();
        if (!(bitmap instanceof Graphics.BufferedBitmap)) {
            logger.debug("no buffered bitmap available; draw not exercised");
            return true;
        }
        var dc = bitmap.getDc();

        var spans = everySpan(0.0, 0.5);
        var overs = noOvers();
        var marks = new [StatMap.RINGS] as Array<Float>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            marks[i] = Source.NO_MARKER;
        }

        // A full frame first, so there is something on screen to preserve.
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            FrameGate.everything(), true);
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(MatrixRenderer.walked[ring],
                "a cleared frame must redraw every ring, including " + ring);
        }

        // Now one ring only. The other three must not be touched at all.
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(2), false);
        Test.assertMessage(MatrixRenderer.walked[2],
            "the dirty ring must be drawn");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (ring != 2) {
                Test.assertMessage(!MatrixRenderer.walked[ring],
                    "ring " + ring + " was clean and must not have been " +
                    "walked — walking it is exactly the cost this removes");
            }
        }

        // A mark appears on ring 1. Nothing was there before, so nothing to rub out.
        marks[1] = 0.25;
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(1), false);
        var first = DotGrid.markedDotFor(1, 0.25);
        Test.assertMessage(first >= 0, "0.25 must mark a dot on ring 1");
        Test.assertEqualMessage(MatrixRenderer.drawnMark[1], first,
            "the renderer must remember the mark it drew");

        // The mark moves. The cell it left must be rubbed out, or 16 pixels of
        // it survive under the cross that replaces it.
        marks[1] = 0.75;
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(1), false);
        Test.assertMessage(MatrixRenderer.erased >= 1,
            "the mark moved and its old cell was never rubbed out — it would " +
            "stay on screen as a ghost of the last reading");
        Test.assertMessage(MatrixRenderer.drawnMark[1] != first,
            "the remembered mark must follow the reading");
        Test.assertEqualMessage(MatrixRenderer.previousMark[1], first,
            "the cell the mark left must still be owed an erase");
        logger.debug("moved a mark, rubbed out " + MatrixRenderer.erased +
                     " stale cell(s)");

        // The second of the HOLD draws is the one that used to be wrong. It is
        // for the *other* buffer, which still shows the mark at its old cell —
        // so it has to rub out that cell too, not just the current one. With a
        // single slot it would rub out the new cell twice and leave sixteen
        // stray pixels of the old mark under a nine-pixel cross.
        var moved = DotGrid.markedDotFor(1, 0.75);
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(1), false);
        Test.assertMessage(MatrixRenderer.erased >= 2,
            "the repeat draw must rub out both the cell the mark is in and " +
            "the one it came from — the other buffer still shows the old one");
        Test.assertEqualMessage(MatrixRenderer.drawnMark[1], moved,
            "and the mark itself must not move on the repeat");

        // A ring that is not redrawn keeps the mark it has on screen: nothing
        // rubbed it out, so the renderer must not forget it either.
        var standing = MatrixRenderer.drawnMark[1];
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(3), false);
        Test.assertEqualMessage(MatrixRenderer.drawnMark[1], standing,
            "a ring left alone still has its mark on screen, so the renderer " +
            "must not lose track of where it is");

        // And a clear wipes the slate: nothing is on screen to rub out.
        MatrixRenderer.draw(dc, spans, marks, overs, Palette.active,
                            Palette.rampActive, null,
                            FrameGate.everything(), true);
        Test.assertEqualMessage(MatrixRenderer.erased, 0,
            "a frame that starts from black has nothing to rub out");
        return true;
    }

    //! What the dot cache costs, in bytes, measured rather than reasoned about.
    //!
    //! The cache is the face's dominant runtime consumer — several parallel
    //! arrays of one entry per dot, against a 131,072-byte watch-face budget —
    //! and nothing measured it until now. This is the memory counterpart of
    //! alwaysOnWorstCaseFitsBudget: it prices the thing, logs the figure, and
    //! fails if a sixth per-dot array appears.
    //!
    //! **Dropping the references first is the whole test.** invalidate() plus
    //! ensureBuilt() is a rebuild in place: each new array is assigned over its
    //! predecessor, Monkey C reference-counts, so the old one is freed at the
    //! moment the new one lands and the net delta is roughly nothing. Measured
    //! that way this passes no matter how big the cache is. Assigning the empty
    //! array drops the last reference and frees it there and then, so the
    //! sample below is taken with the cache genuinely absent.
    (:test)
    function theDotCacheFitsItsShareOfMemory(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dots = DotGrid.count;

        // Cold: let go of every per-dot array, then see what comes back.
        DotGrid.xs = [] as Array<Number>;
        DotGrid.ys = [] as Array<Number>;
        DotGrid.positionOf = [] as Array<Float>;
        DotGrid.armOf = [] as Array<Number>;
        DotGrid.invalidate();

        var before = System.getSystemStats().freeMemory;
        DotGrid.ensureBuilt();
        var after = System.getSystemStats().freeMemory;
        var cost = before - after;

        Test.assertEqualMessage(DotGrid.count, EXPECTED_DOTS,
            "the rebuild must produce the whole lattice again");
        // Only the delta means anything. The absolute free figure here is the
        // test harness's allowance, which is megabytes — a test build is not
        // held to the 131,072 a watch face gets, so measuring against it would
        // be measuring the wrong budget.
        logger.debug("dot cache: " + cost + " bytes for " + dots + " dots, " +
                     (cost / dots) + " per dot");

        // Generous, because this is a ceiling rather than a target: it exists to
        // catch a new per-dot array, which would move the figure by thousands.
        Test.assertMessage(cost < CACHE_CEILING,
            "the dot cache costs " + cost + " bytes, over the " +
            CACHE_CEILING + " this test allows — did a per-dot array appear?");
        Test.assertMessage(cost > 0,
            "the cache must cost something, or this is measuring nothing");
        return true;
    }

    //! Which ring's block a cache index falls in.
    //!
    //! The cache stores dots grouped by ring, so ringStart is the whole answer
    //! and no per-dot array is needed to say it — which is why there is no
    //! longer a DotGrid.ringOf for the checks above to read.
    function ringHolding(index as Number) as Number {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (index >= DotGrid.ringStart[ring] &&
                index < DotGrid.ringStart[ring + 1]) {
                return ring;
            }
        }
        return -1;
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

        var field = stillField();
        var still = stillRings();

        // forget() asks for HOLD full draws, not one: on a double-buffered
        // device the first lands in only one of the two buffers.
        for (var i = 0; i < FrameGate.HOLD; i++) {
            Test.assertMessage(FrameGate.plan(field, still),
                "the frames after forgetting must all be drawn");
            Test.assertMessage(FrameGate.clears,
                "and drawn from black, since nothing vouches for the screen");
        }
        Test.assertMessage(!FrameGate.plan(field, still),
            "an identical frame must then be skipped");

        // A change of any kind must draw, including one only in the last slot.
        var moved = stillRings();
        moved[moved.size() - 1] = 1.0;
        Test.assertMessage(FrameGate.plan(field, moved),
            "a changed ring must be drawn");
        settle(field, moved);
        Test.assertMessage(!FrameGate.plan(field, moved),
            "and then settle back to skipping");

        // The cap: something drawn over the face from outside is only repaired
        // by a draw, so skips must not run on forever — and the repair has to
        // start from black, or damage outside every ring's dots would survive.
        var run = 0;
        var repaired = 0;
        for (var i = 0; i < 40; i++) {
            if (FrameGate.plan(field, moved)) {
                Test.assertMessage(run <= FrameGate.MAX_SKIPS,
                    "went " + run + " frames without drawing, cap is " +
                    FrameGate.MAX_SKIPS);
                if (FrameGate.clears) {
                    repaired++;
                }
                run = 0;
            } else {
                run++;
            }
        }
        Test.assertMessage(run <= FrameGate.MAX_SKIPS,
            "the gate must never skip more than the cap in a row");
        Test.assertMessage(repaired > 0,
            "the periodic repair must clear the screen, or damage outside the " +
            "dots is never rubbed out");

        // forget() is what onShow and waking use; it must always draw next.
        FrameGate.forget();
        Test.assertMessage(FrameGate.plan(field, moved),
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

    //! A field print with nothing happening: no drift, no backing.
    function stillField() as Array<Float> {
        return [0.0, 0.0, -1.0, 0.0] as Array<Float>;
    }

    //! A ring print with every ring empty and unmarked.
    function stillRings() as Array<Float> {
        var out = new [StatMap.RINGS * FrameGate.PER_RING] as Array<Float>;
        for (var i = 0; i < out.size(); i++) {
            out[i] = 0.0;
        }
        return out;
    }

    //! Draw the same frame until every hold has run out, so what follows is
    //! testing the gate rather than the repeat a change is owed.
    function settle(field as Array<Float>, rings as Array<Float>) as Void {
        for (var i = 0; i < FrameGate.HOLD; i++) {
            FrameGate.plan(field, rings);
        }
    }

    //! Only this ring dirty, for driving the renderer down its partial path.
    function onlyRingDirty(ring as Number) as Array<Boolean> {
        var out = new [StatMap.RINGS] as Array<Boolean>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            out[i] = (i == ring);
        }
        return out;
    }

    //! One ring moving must draw that ring and leave the others alone.
    //!
    //! This is the whole of Phase 3 in one assertion. A seconds ring moves its
    //! span every tick, so the old whole-frame gate opened every second and
    //! redrew all four rings because one of them had moved — which this
    //! module's own comment used to accept as the price of a second hand.
    //!
    //! Three things have to hold, and the third is the one that bites: a moved
    //! ring is dirty, an unmoved one is not, and a change is repeated into
    //! HOLD consecutive *draws* rather than one. That last is what makes the
    //! partial redraw safe if the device hands onUpdate an alternating buffer,
    //! where the Dc being drawn into is the one from two draws ago.
    (:test)
    function onlyTheRingThatMovedIsDrawn(logger as Logger) as Boolean {
        FrameGate.forget();
        var field = stillField();
        var rings = stillRings();
        settle(field, rings);
        Test.assertMessage(!FrameGate.plan(field, rings),
            "a still face must skip");

        // Move ring 2's span end and nothing else.
        var moved = stillRings();
        moved[2 * FrameGate.PER_RING + 1] = 0.5;

        Test.assertMessage(FrameGate.plan(field, moved),
            "a ring that moved must open the gate");
        Test.assertMessage(!FrameGate.clears,
            "one ring moving must not clear the whole screen — clearing it " +
            "and redrawing three unchanged rings is what this replaces");
        Test.assertMessage(FrameGate.dirty[2], "the moved ring must be drawn");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            if (ring != 2) {
                Test.assertMessage(!FrameGate.dirty[ring],
                    "ring " + ring + " did not move and must not be drawn");
            }
        }

        // The hold: the same change is drawn again, still only that ring.
        Test.assertMessage(FrameGate.plan(field, moved),
            "a change must be repeated into HOLD consecutive draws, for a " +
            "device whose buffers alternate");
        Test.assertMessage(FrameGate.dirty[2],
            "and the repeat must be of the ring that moved");
        Test.assertMessage(!FrameGate.dirty[0],
            "the repeat must not spread to rings that never moved");

        // And then it settles.
        Test.assertMessage(!FrameGate.plan(field, moved),
            "once the hold is spent an unmoved face skips again");
        logger.debug("one ring moved, " + FrameGate.HOLD + " draws, no clear");

        // The field is different in kind: drift moves every dot, so there is
        // nothing on screen worth keeping.
        var drifted = stillField();
        drifted[0] = 3.0;
        Test.assertMessage(FrameGate.plan(drifted, moved),
            "a drift step must draw");
        Test.assertMessage(FrameGate.clears,
            "drift moves the whole lattice, so the frame starts from black");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(FrameGate.dirty[ring],
                "a cleared screen leaves every ring to redraw, including " +
                ring);
        }

        FrameGate.forget();
        return true;
    }

    //! The frame-cost readout is the only way to see what a frame costs on the
    //! watch, so it has to survive a long session without its average drifting
    //! into meaninglessness or its counters overflowing.
    (:test)
    function frameCostAveragesRecentFrames(logger as Logger) as Boolean {
        resetDiagnostics();
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

        resetDiagnostics();
        return true;
    }

    //! Both counters back to nothing. Skipped frames have their own totals, so
    //! clearing only the drawn ones leaves summary() reporting a session that
    //! was supposed to have been wiped.
    function resetDiagnostics() as Void {
        Diagnostics.frames = 0;
        Diagnostics.totalMs = 0;
        Diagnostics.worstMs = 0;
        Diagnostics.skips = 0;
        Diagnostics.skipTotalMs = 0;
        Diagnostics.skipWorstMs = 0;
    }

    //! What the face pays to decide it has nothing to draw.
    //!
    //! Awake, the gate skips most frames, so this preamble — four sources read,
    //! their spans and marks built, a fingerprint compared — is the face's
    //! most-executed code. It went unmeasured until now because the skip path
    //! returns before Diagnostics.record() is ever reached, which meant the
    //! readout described 17% of frames and stayed silent about the other 83%.
    //!
    //! Kept as its own average rather than folded in: a 3ms skip averaged
    //! against a 27ms draw reports neither number, and the drawn figure is the
    //! one the watchdog is judged against.
    (:test)
    function theSkippedFrameIsCostedSeparately(logger as Logger) as Boolean {
        resetDiagnostics();

        for (var i = 0; i < 10; i++) {
            Diagnostics.record(30);
        }
        for (var i = 0; i < 90; i++) {
            Diagnostics.recordSkip(3);
        }

        Test.assertEqualMessage(Diagnostics.averageMs(), 30,
            "a skipped frame must not drag the drawn average down");
        Test.assertEqualMessage(Diagnostics.skipAverageMs(), 3,
            "the skipped frames must average their own cost");
        Test.assertEqualMessage(Diagnostics.worstMs, 30,
            "the worst drawn frame must not be a skipped one");
        Test.assertEqualMessage(Diagnostics.skipWorstMs, 3,
            "the worst skipped frame is tracked on its own");
        logger.debug("both costs: " + Diagnostics.summary());

        // The skip totals must window the same way the drawn ones do, or a long
        // session's counters run away.
        for (var i = 0; i < 5000; i++) {
            Diagnostics.recordSkip(3);
        }
        Test.assertMessage(Diagnostics.skips <= Diagnostics.WINDOW,
            "the skip window must stay bounded, or the counters run away");
        for (var i = 0; i < Diagnostics.WINDOW; i++) {
            Diagnostics.recordSkip(1);
        }
        Test.assertMessage(Diagnostics.skipAverageMs() < 3,
            "the skip average must follow a sustained change too");

        // Recording only skips must still read as a session with something in it.
        resetDiagnostics();
        Diagnostics.recordSkip(2);
        Test.assertMessage(!Diagnostics.summary().equals("no frames yet"),
            "a session that has only ever skipped has still done something");

        resetDiagnostics();
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

    //! The ring print at a given second, laid out as CrossoverView lays it:
    //! four values per ring — its two span ends, its mark and its over flag.
    //! Only the first ring's sweep moves here.
    function ringPrintAtSecond(second as Number) as Array<Float> {
        var out = stillRings();
        out[1] = ClockData.fraction(second);        //! ring 1's span end
        return out;
    }

    //! A seconds ring must move its own ring every tick, and only its own.
    //!
    //! The sweep would visibly stall if a tick did not open the gate, so this
    //! asserts all sixty do. What it now also asserts is the point of the
    //! per-ring split: a tick draws **one** ring. The old whole-frame gate
    //! opened on all sixty too, and redrew four rings each time — this module
    //! used to call that the unavoidable cost of asking for a second hand.
    (:test)
    function everySecondDrawsOnlyTheSweepingRing(logger as Logger) as Boolean {
        var drawn = FrameGate.drawn;
        var suppressed = FrameGate.suppressed;
        FrameGate.forget();
        FrameGate.drawn = 0;
        FrameGate.suppressed = 0;

        var field = stillField();
        // Settle first, so the holds forget() asked for are spent and what
        // follows is the sweep's own doing.
        settle(field, ringPrintAtSecond(0));

        var opened = 0;
        var wholeFrames = 0;
        var otherRings = 0;
        for (var second = 1; second < 60; second++) {
            if (FrameGate.plan(field, ringPrintAtSecond(second))) {
                opened++;
                if (FrameGate.clears) {
                    wholeFrames++;
                } else {
                    // On a frame that is not the periodic repair, the sweep
                    // must cost its own ring and nothing else.
                    for (var ring = 1; ring < StatMap.RINGS; ring++) {
                        if (FrameGate.dirty[ring]) {
                            otherRings++;
                        }
                    }
                }
                Test.assertMessage(FrameGate.dirty[0],
                    "the sweeping ring must be drawn on tick " + second);
            }
        }
        logger.debug("the gate opened on " + opened + " of 59 ticks, cleared " +
                     wholeFrames + ", drew an unmoved ring outside the repair " +
                     otherRings + " times");
        Test.assertEqualMessage(opened, 59,
            "a moving sweep must never be skipped — it stalled on " +
            (59 - opened) + " ticks");

        // The point of the whole split: a tick draws one ring.
        Test.assertEqualMessage(otherRings, 0,
            "a second tick redrew a ring that had not moved " + otherRings +
            " times — that is the cost this split exists to remove");

        // The periodic repair still runs, and is still the minority. It has to
        // exist: a face that only ever redraws one ring would never rub out
        // damage lying between the dots, or on the three rings it is not
        // drawing. It must not be most of the minute either, or the saving is
        // spent on repairs.
        Test.assertMessage(wholeFrames > 0,
            "the screen must still be cleared periodically, or a notification " +
            "drawn over the face would stay there");
        Test.assertMessage(wholeFrames * 2 < opened,
            "most ticks must draw one ring, but " + wholeFrames + " of " +
            opened + " cleared and redrew all four");

        // And the gate is still a gate: a tick that does not move it is still
        // skipped, so this is the print changing rather than the gate having
        // been loosened.
        FrameGate.forget();
        settle(field, ringPrintAtSecond(7));
        Test.assertMessage(!FrameGate.plan(field, ringPrintAtSecond(7)),
            "an unmoved print must still be skipped");

        FrameGate.forget();
        FrameGate.drawn = drawn;
        FrameGate.suppressed = suppressed;
        return true;
    }
}
