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
        // Off is the picker's last entry. That used to be assertable as
        // SOURCE_OFF == COUNT - 1, and it held only for as long as nothing had
        // been added after Off — which is exactly what a new source now must
        // do, because appending below Off would renumber it on every watch
        // already carrying a setting. The claim was always about OFFERED's
        // order rather than the enum's, so it is now made against OFFERED.
        Test.assertEqualMessage(Source.OFFERED[Source.OFFERED.size() - 1],
            Source.SOURCE_OFF,
            "Off must be the picker's last entry — a claim about OFFERED " +
            "order, not about the enum index, since sources are appended " +
            "after Off so that stored indices never move");

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

    //! Weather is sampled once a minute, and all of it from one call.
    //!
    //! The watch syncs weather from the phone on the order of tens of minutes,
    //! so asking every second asked a question whose answer could not have
    //! changed. A minute is what always-on already gets.
    //!
    //! The sharper half is that the three readings now come from **one** call.
    //! They used to take a getCurrentConditions() each, so on a temperature
    //! ring the band and the mark drawn inside it could come from different
    //! samples — a disagreement no test could have caught, because the
    //! simulator reports no weather at all and every reading is null.
    (:test)
    function weatherIsSampledOnceAMinute(logger as Logger) as Boolean {
        // A fresh sample is taken when there is none.
        WeatherData.forget();
        Test.assertMessage(!WeatherData.sampled,
            "forget() must drop the sample");
        WeatherData.dayRange();
        Test.assertMessage(WeatherData.sampled,
            "reading must take a sample when there is none");

        // Within the minute the stored sample answers — including the null one
        // the simulator gives, which is cached like any other answer rather
        // than re-asked every frame.
        var taken = WeatherData.takenAt;
        WeatherData.dayRange();
        WeatherData.currentFraction();
        WeatherData.rainChance();
        Test.assertEqualMessage(WeatherData.takenAt, taken,
            "three reads inside the minute must share one sample — a band and " +
            "the mark inside it cannot come from different ones");

        // Past the minute, the watch is asked again.
        WeatherData.takenAt = System.getTimer() - Sample.INTERVAL_MS - 1;
        var stale = WeatherData.takenAt;
        WeatherData.dayRange();
        Test.assertMessage(WeatherData.takenAt != stale,
            "a sample older than REFRESH_MS must be replaced");
        logger.debug("sample refreshed after " + Sample.INTERVAL_MS + "ms");

        // getTimer wraps about every 25 days. A sample that looks like it was
        // taken in the future is that wrap, not a fresh reading — treating it
        // as fresh would freeze the weather until the counter caught up.
        WeatherData.takenAt = System.getTimer() + 1000000;
        var future = WeatherData.takenAt;
        WeatherData.dayRange();
        Test.assertMessage(WeatherData.takenAt != future,
            "a sample from the future is a wrapped timer and must be retaken, " +
            "or the weather freezes until the counter catches up");

        // The arithmetic is untouched by any of this: fraction() is pure, and
        // is what the scale tests above pin.
        Test.assertEqualMessage(WeatherData.fraction(30.0), 0.5,
            "caching must not have reached the scale");

        WeatherData.forget();
        return true;
    }

    //! Retiring a source must not renumber the ones after it.
    //!
    //! Stored settings are list indices. Heart rate came off the face, and the
    //! tempting change — delete the enum entry — would not have removed a
    //! source, it would have silently renamed every source above it: a watch
    //! with Battery on ring 3 would come back showing Body Battery, with
    //! nothing to say it had happened. So the slot stays and the picker skips
    //! it, and this is what holds that line.
    (:test)
    function retiringASourceLeavesEveryOtherIndexAlone(logger as Logger) as Boolean {
        // The numbering below the gap, pinned outright. If any of these move,
        // every watch in the field re-reads its rings as something else.
        Test.assertEqualMessage(Source.SOURCE_STEPS, 0, "steps must stay 0");
        Test.assertEqualMessage(Source.SOURCE_RETIRED, 1, "the gap must stay 1");
        Test.assertEqualMessage(Source.SOURCE_BATTERY, 2, "battery must stay 2");
        Test.assertEqualMessage(Source.SOURCE_BODY_BATTERY, 3,
            "body battery must stay 3");
        Test.assertEqualMessage(Source.SOURCE_TEMPERATURE, 4,
            "temperature must stay 4");
        Test.assertEqualMessage(Source.SOURCE_RAIN, 5, "rain must stay 5");
        Test.assertEqualMessage(Source.SOURCE_INTENSITY_MINUTES, 6,
            "intensity minutes must stay 6");
        Test.assertEqualMessage(Source.SOURCE_SECONDS, 7, "seconds must stay 7");
        Test.assertEqualMessage(Source.SOURCE_OFF, 8, "off must stay 8");
        // Above the gap, and above Off. A source added after Off looks wrong
        // and is the only safe place to put one: anywhere below would renumber
        // Off and everything under it, on every watch already carrying a
        // setting, with nothing to report that it had happened.
        Test.assertEqualMessage(Source.SOURCE_RAIN_HOURS, 9,
            "rain next 12h must stay 9");
        Test.assertEqualMessage(Source.SOURCE_UV_HOURS, 10,
            "UV next 12h must stay 10");
        Test.assertEqualMessage(Source.SOURCE_BODY_BATTERY_HOURS, 11,
            "Body Battery last 12h must stay 11");
        Test.assertEqualMessage(Source.COUNT, 12,
            "COUNT counts slots, not offers — the tables are indexed by it");

        // The retired slot is never offered.
        Test.assertEqualMessage(Source.OFFERED.size(), Source.COUNT - 1,
            "the picker must offer every source but the retired one");
        for (var i = 0; i < Source.OFFERED.size(); i++) {
            Test.assertMessage(Source.OFFERED[i] != Source.SOURCE_RETIRED,
                "the picker must not offer the retired source");
            Test.assertMessage(Source.OFFERED[i] >= 0 &&
                               Source.OFFERED[i] < Source.COUNT,
                "every offered source must be a real one");
        }

        // It lights nothing if something does hold it.
        var span = Source.span(Source.SOURCE_RETIRED, true);
        Test.assertEqualMessage(span.size(), 2,
            "even a retired source must report a span shape");
        Test.assertMessage(span[0] == span[1],
            "a retired source must light nothing");

        // And a ring still set to it reads as Off, which the menu can name.
        Properties.setValue(StatMap.PROPERTY_RINGS[1], Source.SOURCE_RETIRED);
        Config.reload();
        Test.assertEqualMessage(StatMap.rings[1], Source.SOURCE_OFF,
            "a ring left on the retired source must read as Off, not as a " +
            "band the menu has no name for");
        logger.debug("retired slot " + Source.SOURCE_RETIRED +
                     " reads back as Off (" + Source.SOURCE_OFF + ")");

        Properties.setValue(StatMap.PROPERTY_RINGS[1],
                            Source.SOURCE_INTENSITY_MINUTES);
        Config.reload();
        return true;
    }

    //! The watch's own readings are sampled once a minute, from one pass.
    //!
    //! None of them move faster than that in a way the face can show — a step
    //! ring resolves about 36 steps to a dot — and the duplicate this removes
    //! was a correctness problem as much as a cost: Source asks for steps
    //! twice a frame, once for the span and once for the over flag, and each
    //! ask used to be its own getInfo(). A step landing between them put the
    //! span and its flag one reading apart, which is exactly the pair whose
    //! disagreement draws a lap of 0.05 as a fill of 0.05.
    (:test)
    function theWatchIsSampledOnceAMinute(logger as Logger) as Boolean {
        WatchData.forget();
        Test.assertMessage(!WatchData.sampled, "forget() must drop the sample");
        WatchData.steps();
        Test.assertMessage(WatchData.sampled,
            "reading must take a sample when there is none");

        // Every reading inside the minute comes from that one sample.
        var taken = WatchData.takenAt;
        WatchData.steps();
        WatchData.intensityMinutes();
        WatchData.battery();
        Test.assertEqualMessage(WatchData.takenAt, taken,
            "three reads inside the minute must share one sample");

        // The span and the over flag must be the same reading, always.
        var steps = WatchData.steps();
        Test.assertEqualMessage(WatchData.steps(), steps,
            "a span and its over flag ask separately and must not be able " +
            "to disagree");

        // Past the minute, the watch is asked again.
        WatchData.takenAt = System.getTimer() - Sample.INTERVAL_MS - 1;
        var stale = WatchData.takenAt;
        WatchData.steps();
        Test.assertMessage(WatchData.takenAt != stale,
            "a sample older than the interval must be replaced");

        // Seconds is the one thing that must never be sampled: a second hand
        // read once a minute is a stopped one.
        var first = ClockData.fraction(10);
        var second = ClockData.fraction(40);
        Test.assertMessage(first != second,
            "ClockData must stay live — it is the one source a minute would " +
            "ruin");
        logger.debug("sample interval " + Sample.INTERVAL_MS + "ms, seconds live");

        WatchData.forget();
        return true;
    }

    //! Body Battery owns a separate cache because current and history share an
    //! iterator, but it keeps the same once-a-minute contract as the other data.
    (:test)
    function bodyBatteryCurrentIsSampledOnceAMinute(logger as Logger)
            as Boolean {
        BodyBatteryData.forget();
        BodyBatteryData.current();
        Test.assertMessage(BodyBatteryData.currentSampled,
            "the first current Body Battery read must take a sample");
        var taken = BodyBatteryData.currentTakenAt;
        BodyBatteryData.current();
        Test.assertEqualMessage(BodyBatteryData.currentTakenAt, taken,
            "a current Body Battery sample must be reused within its minute");

        var stale = System.getTimer() - Sample.INTERVAL_MS - 1;
        BodyBatteryData.currentTakenAt = stale;
        BodyBatteryData.current();
        Test.assertMessage(BodyBatteryData.currentTakenAt != stale,
            "an expired current Body Battery sample must be replaced");
        BodyBatteryData.forget();
        logger.debug("Body Battery current sample cached for one minute");
        return true;
    }

    //! The wrap is why Sample.due is a function and not a subtraction.
    (:test)
    function aWrappedTimerDoesNotFreezeTheData(logger as Logger) as Boolean {
        Test.assertMessage(Sample.due(0, false),
            "with no sample taken, one is always due");
        Test.assertMessage(!Sample.due(System.getTimer(), true),
            "a sample just taken is not due");
        Test.assertMessage(
            Sample.due(System.getTimer() - Sample.INTERVAL_MS - 1, true),
            "a sample past the interval is due");

        // getTimer wraps about every 25 days. A stamp in the future is that
        // wrap, and calling it fresh would freeze every reading the face has
        // until the counter caught up — up to 25 days of a still face.
        Test.assertMessage(Sample.due(System.getTimer() + 1000000, true),
            "a sample stamped in the future is a wrapped counter and must be " +
            "retaken, not trusted");
        logger.debug("wrap handled; interval " + Sample.INTERVAL_MS + "ms");
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

        // Every value the enum names, including the newest — the clamp is
        // written against the top of the enum and a value added without
        // raising it is simply unreachable, with no other symptom.
        var valid = [StatMap.ROTATION_UPRIGHT, StatMap.ROTATION_UPRIGHT_DATE]
                    as Array<Number>;
        for (var i = 0; i < valid.size(); i++) {
            Properties.setValue(StatMap.PROPERTY_ROTATION, valid[i]);
            Config.reload();
            Test.assertEqualMessage(StatMap.rotation, valid[i],
                "rotation " + valid[i] + " must be honoured");

            // The menu reads its sub-label straight off the setting, so an
            // unhandled value would index past the end of the label table.
            var menu = new SettingsMenu();
            menu.onShow();
        }

        Properties.setValue(StatMap.PROPERTY_ROTATION,
                            StatMap.ROTATION_UPRIGHT_DATE + 1);
        Config.reload();
        Test.assertEqualMessage(StatMap.rotation, StatMap.ROTATION_RADIAL,
            "one past the top of the enum must still fall back");

        Properties.setValue(StatMap.PROPERTY_ROTATION,
                            StatMap.ROTATION_RADIAL);
        Config.reload();
        return true;
    }

    //! Same contract for the theme setting.
    (:test)
    function themeSettingIsClamped(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_THEME, 99);
        Config.reload();
        Test.assertEqualMessage(StatMap.theme, StatMap.THEME_TERRAIN,
            "an out-of-range value must fall back to Terrain");

        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_ACTIVITY);
        Config.reload();
        Test.assertEqualMessage(StatMap.theme, StatMap.THEME_ACTIVITY,
            "a valid value must be honoured");

        // The menu reads its sub-label straight off the setting, so an
        // unhandled value would index past the end of the label table.
        var menu = new SettingsMenu();
        menu.onShow();

        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }

    //! Adding a theme means touching four places at once: the colours, the
    //! ramp stops that pick three of them, the range StatMap clamps to, and
    //! the menu's labels. Miss the clamp and the new theme is unreachable;
    //! miss the labels and choosing it indexes past the end of the table.
    (:test)
    function themeTablesCoverEveryTheme(logger as Logger) as Boolean {
        Test.assertEqualMessage(Palette.THEMES.size(),
            Palette.THEME_COUNT * Palette.THEME_COLOURS,
            "THEMES must hold exactly THEME_COLOURS entries per theme");
        Test.assertEqualMessage(Palette.RAMP_STOPS.size(),
            Palette.THEME_COUNT * Palette.RAMP_POINTS,
            "every theme needs a cold, a mid and a hot ramp stop");
        Test.assertEqualMessage(THEME_LABELS.size(), Palette.THEME_COUNT,
            "every theme needs a name in the settings menu");

        // Cold and hot must name a real colour. The mid slot may also be
        // RAMP_LINEAR, which a two-hue theme uses to say it has no third
        // colour to turn through — but only the mid slot: a sentinel at
        // either end would leave the ramp with no colour at all.
        for (var i = 0; i < Palette.RAMP_STOPS.size(); i++) {
            var stop = Palette.RAMP_STOPS[i];
            var isMid = (i % Palette.RAMP_POINTS) == 1;
            if (isMid && stop == Palette.RAMP_LINEAR) {
                continue;
            }
            Test.assertMessage(stop >= 0 && stop < Palette.THEME_COLOURS,
                "ramp stop " + i + " points outside its theme");
        }

        // A linear ramp still has to be a ramp: its two ends must differ, or
        // every temperature draws one colour.
        for (var theme = 0; theme < Palette.THEME_COUNT; theme++) {
            var stops = theme * Palette.RAMP_POINTS;
            if (Palette.RAMP_STOPS[stops + 1] != Palette.RAMP_LINEAR) {
                continue;
            }
            var base = theme * Palette.THEME_COLOURS;
            Test.assertMessage(
                Palette.THEMES[base + Palette.RAMP_STOPS[stops]] !=
                Palette.THEMES[base + Palette.RAMP_STOPS[stops + 2]],
                "theme " + theme + " ramps linearly between two colours " +
                "that are the same, so temperature reads as one flat band");
        }

        // The clamp is the piece with no other symptom: a theme present in
        // THEMES but outside StatMap's range simply never draws.
        var last = Palette.THEME_COUNT - 1;
        Properties.setValue(StatMap.PROPERTY_THEME, last);
        Config.reload();
        Test.assertEqualMessage(StatMap.theme, last,
            "the last theme is unreachable — StatMap's clamp has not been " +
            "widened to match Palette.THEME_COUNT");

        Properties.setValue(StatMap.PROPERTY_THEME, Palette.THEME_COUNT);
        Config.reload();
        Test.assertEqualMessage(StatMap.theme, StatMap.THEME_TERRAIN,
            "one past the last theme must still fall back");

        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }

    //! The theme has to actually reach the drawn colours. The menu writes a
    //! property and trusts Config.reload() to do the rest, so a build() that
    //! read the wrong index — or never read the setting at all — would leave
    //! the face looking identical and nothing else here would notice.
    (:test)
    function changingTheThemeChangesTheColours(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        var bands = new [StatMap.RINGS] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            bands[ring] = Palette.active[ring * 2 + 1];
        }
        var coldest = Palette.rampActive[0];
        var hottest = Palette.rampActive[Palette.RAMP_STEPS - 1];

        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_ACTIVITY);
        Config.reload();
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(Palette.active[ring * 2 + 1] != bands[ring],
                "ring " + ring + " kept its colour across a theme change");
        }
        Test.assertMessage(Palette.rampActive[0] != coldest,
            "the temperature ramp's cold end did not follow the theme");
        Test.assertMessage(
            Palette.rampActive[Palette.RAMP_STEPS - 1] != hottest,
            "the temperature ramp's hot end did not follow the theme");
        logger.debug("ramp " + coldest + "->" + hottest + " became " +
            Palette.rampActive[0] + "->" +
            Palette.rampActive[Palette.RAMP_STEPS - 1]);

        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }

    //! Making the theme selectable re-indexed every colour lookup in build().
    //! That is a refactor, so the shipping face must come out of it unmoved —
    //! and the ramp stops, which used to be the literals 2, 0 and 3, must
    //! still resolve to ice, orchid and rust for Terrain.
    (:test)
    function terrainIsUnchangedByTheThemeSeam(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();

        var terrain = [0xE879F9, 0xB8D64B, 0x7FD4FF, 0xFF6B5B]
                      as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(Palette.active[ring * 2 + 1], terrain[ring],
                "ring " + ring + " no longer draws its Terrain colour");
        }

        var stops = StatMap.THEME_TERRAIN * Palette.RAMP_POINTS;
        Test.assertEqualMessage(
            Palette.themeColour(Palette.RAMP_STOPS[stops]), 0x7FD4FF,
            "Terrain's ramp must still start at ice");
        Test.assertEqualMessage(
            Palette.themeColour(Palette.RAMP_STOPS[stops + 1]), 0xE879F9,
            "Terrain's ramp must still pass through orchid");
        Test.assertEqualMessage(
            Palette.themeColour(Palette.RAMP_STOPS[stops + 2]), 0xFF6B5B,
            "Terrain's ramp must still end at rust");

        Test.assertEqualMessage(Palette.rampActive[0], 0x7FD4FF,
            "the built ramp no longer starts at ice");
        Test.assertEqualMessage(
            Palette.rampActive[Palette.RAMP_STEPS - 1], 0xFF6B5B,
            "the built ramp no longer ends at rust");
        return true;
    }

    //! Every luminance test here measures whichever theme happens to be
    //! persisted, so a second theme would ship unmeasured. This walks them all
    //! through the worst frame the face can draw.
    (:test)
    function everyThemeFitsTheAlwaysOnBudget(logger as Logger) as Boolean {
        var full = everySpan(0.0, 1.0);
        for (var theme = 0; theme < Palette.THEME_COUNT; theme++) {
            Properties.setValue(StatMap.PROPERTY_THEME, theme);
            Config.reload();
            var worst = frameLuminance(full, Palette.alwaysOn);
            logger.debug("theme " + theme + " worst-case always-on: " + worst);
            Test.assertMessage(worst < BUDGET,
                "theme " + theme + " exceeds the AMOLED burn-in budget");
        }
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }

    //! The tiers a ring draws have to stay in order in every theme: unfilled
    //! below the band, a second lap above it, and the mark above that.
    //! theOverTierReadsBrighterThanTheBand pins that for the persisted theme,
    //! so a colour dark enough to invert an ordering would slip past it in
    //! any other. The per-ring tables must also stay distinguishable between
    //! rings that touch, or they earn nothing over the single constants they
    //! replaced — see the loop below for why touching is the right test and
    //! every-pair is not.
    (:test)
    function everyThemeKeepsTheTierOrder(logger as Logger) as Boolean {
        for (var theme = 0; theme < Palette.THEME_COUNT; theme++) {
            Properties.setValue(StatMap.PROPERTY_THEME, theme);
            Config.reload();

            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                var weak = relativeLuminance(Palette.active[ring * 2]);
                var band = relativeLuminance(Palette.active[ring * 2 + 1]);
                var over = relativeLuminance(Palette.overOf[ring]);
                var mark = relativeLuminance(Palette.markerOf[ring]);
                var dim = relativeLuminance(Palette.dimOf[ring]);
                var where = "theme " + theme + " ring " + ring;
                Test.assertMessage(dim < weak,
                    where + ": an hour with no forecast must read darker " +
                    "than one the forecast called dry, or the two say the " +
                    "same thing");
                Test.assertMessage(weak < band,
                    where + ": the unfilled tier must sit below the band");
                Test.assertMessage(band < over,
                    where + ": a second lap must read brighter than the band");
                Test.assertMessage(over < mark,
                    where + ": the mark must outshine the lap it lands on");
            }

            // Neighbours only, not every pair. A duotone repeats its two
            // hues on purpose, and rings 1 and 3 never touch — a shared
            // colour is only a defect between rings that sit against each
            // other, which is the same reason the ring order is chosen on
            // neighbour distance rather than on the set average.
            for (var a = 0; a + 1 < StatMap.RINGS; a++) {
                var b = a + 1;
                var pair = "theme " + theme + ": rings " + a + " and " + b;
                Test.assertMessage(
                    Palette.active[a * 2 + 1] != Palette.active[b * 2 + 1],
                    pair + " sit against each other and share a colour");
                Test.assertMessage(
                    Palette.markerOf[a] != Palette.markerOf[b],
                    pair + " sit against each other and share a mark colour");
                Test.assertMessage(
                    Palette.overOf[a] != Palette.overOf[b],
                    pair + " sit against each other and share a second-lap " +
                    "colour");
                Test.assertMessage(
                    Palette.dimOf[a] != Palette.dimOf[b],
                    pair + " sit against each other and share an " +
                    "unknown-hour colour");
            }
        }
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
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
    const MENU_VALUE_ROWS = [0, 1, 2, 3, 5] as Array<Number>;

    // --- the date watermark --------------------------------------------------

    //! The day the tests draw. Two digits with no repeated one, so a glyph
    //! written into the wrong half of the window cannot pass by symmetry.
    const GLYPH_DAY = 15;

    //! How many pixels a set bit of the font is worth: SCALE cells each way,
    //! one dot apiece.
    const GLYPH_CELLS_PER_BIT = DateGlyph.SCALE * DateGlyph.SCALE;

    function bitsSet(value as Number) as Number {
        var n = 0;
        for (var b = 0; b < DateGlyph.FONT_BITS; b++) {
            if (((value >> b) & 1) == 1) {
                n++;
            }
        }
        return n;
    }

    //! The window has to sit where every one of its cells holds a dot.
    //!
    //! It does not have to — a hole would simply draw a gap in the numeral —
    //! but a hole is invisible to every other test here and obvious on the
    //! wrist, and the placement was chosen on the promise of 140 out of 140.
    //! Nudge ORIGIN_ROW two rows further down and this is what says so.
    (:test)
    function everyWatermarkCellHoldsADot(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        DateGlyph.buildCells();

        Test.assertEqualMessage(DateGlyph.cells, DateGlyph.CELLS,
            "the watermark window has cells with no dot in them — it has been " +
            "moved onto the rim or over the hand pivot");

        var seen = new [DateGlyph.CELLS] as Array<Boolean>;
        for (var i = 0; i < DateGlyph.CELLS; i++) {
            seen[i] = false;
        }
        for (var k = 0; k < DateGlyph.cells; k++) {
            var at = DateGlyph.cellAt[k];
            Test.assertMessage(at >= 0 && at < DateGlyph.CELLS,
                "cell " + at + " is outside the window");
            Test.assertMessage(!seen[at], "cell " + at + " claimed twice");
            seen[at] = true;
        }
        logger.debug("watermark window: " + DateGlyph.cells + " of " +
                     DateGlyph.CELLS + " cells hold a dot");
        return true;
    }

    //! The struck dots arrive in the order the renderer walks them, and each
    //! ring's slice of them is where firstFor says it is.
    //!
    //! Both halves matter and they fail differently. Out of order, the
    //! renderer's cursor stops matching and the numeral loses dots from
    //! wherever the order first breaks. A wrong slice boundary draws one ring's
    //! share of the watermark while another ring is being redrawn, which is a
    //! numeral that appears in pieces as the rings tick.
    (:test)
    function theWatermarkIndexIsSortedAndRingGrouped(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        DateGlyph.ensure(GLYPH_DAY);

        Test.assertMessage(DateGlyph.lit > 0,
            "the watermark struck no dots at all");
        for (var i = 1; i < DateGlyph.lit; i++) {
            Test.assertMessage(DateGlyph.index[i] > DateGlyph.index[i - 1],
                "the struck dots are not in ascending index order at " + i);
        }

        Test.assertEqualMessage(DateGlyph.firstFor[0], 0,
            "the first ring's slice must start at the beginning");
        Test.assertEqualMessage(DateGlyph.firstFor[StatMap.RINGS],
            DateGlyph.lit, "the last slice must end at the total");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            for (var k = DateGlyph.firstFor[ring];
                     k < DateGlyph.firstFor[ring + 1]; k++) {
                var dot = DateGlyph.index[k];
                Test.assertMessage(dot >= DotGrid.ringStart[ring] &&
                                   dot < DotGrid.ringStart[ring + 1],
                    "dot " + dot + " is in ring " + ring + "'s slice but not " +
                    "in ring " + ring);
            }
            logger.debug("ring " + ring + " strikes " +
                (DateGlyph.firstFor[ring + 1] - DateGlyph.firstFor[ring]) +
                " dots");
        }
        return true;
    }

    //! The cursor walk and the readable definition agree on every dot.
    //!
    //! The renderer does not ask DateGlyph whether a dot is struck: it walks a
    //! sorted list with a cursor, which is one integer comparison per dot
    //! against a call and a division. That is the same trade
    //! StatMap.litBetween() gets, and it carries the same obligation — the
    //! readable definition stays, and this holds the fast path to it.
    (:test)
    function theWatermarkMatchesItsReadableDefinition(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        DateGlyph.ensure(GLYPH_DAY);

        var struck = new [DotGrid.count] as Array<Boolean>;
        for (var i = 0; i < DotGrid.count; i++) {
            struck[i] = false;
        }
        for (var k = 0; k < DateGlyph.lit; k++) {
            struck[DateGlyph.index[k]] = true;
        }
        for (var i = 0; i < DotGrid.count; i++) {
            Test.assertEqualMessage(struck[i], DateGlyph.isGlyphDot(i),
                "dot " + i + " at (" + DotGrid.xs[i] + ", " + DotGrid.ys[i] +
                ") disagrees: the list says " + struck[i] +
                ", isGlyphDot says " + DateGlyph.isGlyphDot(i));
        }
        return true;
    }

    //! The renderer strikes exactly the watermark's dots, ring by ring.
    //!
    //! Per ring rather than only in total, because the cursor is re-seeded from
    //! firstFor at the top of every ring and carrying it on from the ring
    //! before would still add up to the right number overall while drawing the
    //! numeral in the wrong rings.
    (:test)
    function theRendererStrikesExactlyTheWatermarkDots(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();

        var bitmap = Graphics.createBufferedBitmap(
            {:width => 64, :height => 64}).get();
        if (!(bitmap instanceof Graphics.BufferedBitmap)) {
            logger.debug("no buffered bitmap available; draw not exercised");
            return true;
        }
        var dc = bitmap.getDc();
        var spans = everySpan(0.0, 0.5);
        var overs = allOvers();
        var turning = StatMap.rotation;

        StatMap.rotation = StatMap.ROTATION_UPRIGHT_DATE;
        DateGlyph.ensure(GLYPH_DAY);
        MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(),
                            Palette.active, Palette.rampActive, null,
                            FrameGate.everything(), true);
        Test.assertEqualMessage(MatrixRenderer.struck, DateGlyph.lit,
            "a full redraw must strike every dot the watermark names");

        // A clear rules the delta out, which is what makes the count below a
        // statement about the cursor rather than about which dots moved.
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(),
                                Palette.active, Palette.rampActive, null,
                                onlyRingDirty(ring), true);
            var expected = DateGlyph.firstFor[ring + 1] -
                           DateGlyph.firstFor[ring];
            Test.assertEqualMessage(MatrixRenderer.struck, expected,
                "ring " + ring + " alone must strike its own slice");
        }

        // And neither of the other two rotations strikes anything, whatever
        // DateGlyph happens to be holding.
        var quiet = [StatMap.ROTATION_RADIAL, StatMap.ROTATION_UPRIGHT]
                    as Array<Number>;
        for (var r = 0; r < quiet.size(); r++) {
            StatMap.rotation = quiet[r];
            MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(),
                                Palette.active, Palette.rampActive, null,
                                FrameGate.everything(), true);
            Test.assertEqualMessage(MatrixRenderer.struck, 0,
                "rotation " + quiet[r] + " must draw the plain field");
        }

        StatMap.rotation = turning;
        return true;
    }

    //! A block ring draws the watermark too.
    //!
    //! Its dots are walked in a second loop that the span loop's changes do not
    //! reach, and the first version of the forecast ring was drawn as an empty
    //! span in three places for exactly that kind of reason. A ring on the
    //! twelve-hour forecast with the watermark under it is one line of the
    //! numeral simply missing.
    (:test)
    function aBlockRingStrikesItsShareOfTheWatermark(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();

        var bitmap = Graphics.createBufferedBitmap(
            {:width => 64, :height => 64}).get();
        if (!(bitmap instanceof Graphics.BufferedBitmap)) {
            logger.debug("no buffered bitmap available; draw not exercised");
            return true;
        }
        var dc = bitmap.getDc();
        var turning = StatMap.rotation;
        var was = StatMap.rings[0];
        StatMap.rotation = StatMap.ROTATION_UPRIGHT_DATE;
        StatMap.rings[0] = Source.SOURCE_RAIN_HOURS;
        DateGlyph.ensure(GLYPH_DAY);

        MatrixRenderer.draw(dc, everySpan(0.0, 0.5), noMarks(), allOvers(),
                            emptyBlocks(), Palette.active, Palette.rampActive,
                            null, onlyRingDirty(0), true);
        Test.assertEqualMessage(MatrixRenderer.struck,
            DateGlyph.firstFor[1] - DateGlyph.firstFor[0],
            "the block loop must strike the same dots the span loop would");

        StatMap.rings[0] = was;
        StatMap.rotation = turning;
        return true;
    }

    //! Rolling the date does not rebuild the lattice.
    //!
    //! The same claim rotationDoesNotReachTheCache makes, and it matters more
    //! here: the watermark changes on its own, once a day, on whatever frame
    //! happens to be next. A rebuild there is ~1100 dots of work inside an
    //! onUpdate, which is the budget the face has already tripped once.
    (:test)
    function theDateDoesNotReachTheCache(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        DateGlyph.ensure(1);

        var generation = DotGrid.generation;
        var arms = new [DotGrid.count] as Array<Number>;
        for (var i = 0; i < DotGrid.count; i++) {
            arms[i] = DotGrid.armOf[i];
        }

        for (var day = 2; day <= 31; day++) {
            DateGlyph.ensure(day);
            Test.assertEqualMessage(DotGrid.generation, generation,
                "day " + day + " rebuilt the dot cache");
        }
        for (var i = 0; i < DotGrid.count; i++) {
            Test.assertEqualMessage(DotGrid.armOf[i], arms[i],
                "dot " + i + " changed orientation with the date");
        }
        return true;
    }

    //! A rebuilt lattice invalidates the cells the watermark cached.
    //!
    //! build() reuses its arrays when the lattice has not changed size, which
    //! is every rebuild there is — so nothing about the arrays themselves says
    //! they have been rewritten, and a cache of dot *indices* into them cannot
    //! notice. DotGrid.generation is the only thing that can, and this is what
    //! holds DateGlyph to reading it.
    (:test)
    function aRebuiltLatticeRefreshesTheWatermark(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        DateGlyph.ensure(GLYPH_DAY);
        var before = DateGlyph.builtFor;

        DotGrid.build();
        Test.assertMessage(DotGrid.generation != before,
            "build() must move the generation counter");
        DateGlyph.ensure(GLYPH_DAY);
        Test.assertEqualMessage(DateGlyph.builtFor, DotGrid.generation,
            "the watermark kept cells from before the rebuild");
        return true;
    }

    //! Midnight clears the screen.
    //!
    //! A dot that was struck yesterday and is not today has four pixels on
    //! screen that a repaint will not remove: the repaint draws the cross's
    //! other stroke, which is exactly the four. Only a clear takes them off,
    //! and the day being in the *field* print is what asks for one.
    (:test)
    function aDateChangeClearsTheField(logger as Logger) as Boolean {
        FrameGate.forget();
        var rings = stillRings();
        var field = stillField();
        field[4] = 15.0;
        for (var i = 0; i < FrameGate.HOLD; i++) {
            FrameGate.plan(field, rings);
        }
        Test.assertMessage(!FrameGate.plan(field, rings),
            "an unchanged frame must skip before the date is moved");

        var tomorrow = stillField();
        tomorrow[4] = 16.0;
        Test.assertMessage(FrameGate.plan(tomorrow, rings),
            "the frame the date changes on must be drawn");
        Test.assertMessage(FrameGate.clears,
            "and drawn from black — a repaint leaves yesterday's strokes");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(FrameGate.dirty[ring],
                "ring " + ring + " must be redrawn: the watermark crosses all " +
                "four");
        }
        return true;
    }

    //! Striking a dot can only take light away, so nothing needs re-measuring.
    //!
    //! Every other thing the face draws had to be weighed against the 10%
    //! always-on budget. This one does not, and the reason is arithmetic rather
    //! than a measurement: a struck dot draws one of the two strokes it drew
    //! before, so its lit pixels are a strict subset of what they were and the
    //! frame's total can only fall. That argument holds only while a strike
    //! really is one stroke of a cross the field already draws — this is what
    //! says so.
    (:test)
    function strikingADotOnlyRemovesLight(logger as Logger) as Boolean {
        Test.assertMessage(DateGlyph.STROKE_PIXELS < LIT_PIXELS_PER_DOT,
            "a struck dot must light fewer pixels than a whole cross: " +
            DateGlyph.STROKE_PIXELS + " against " + LIT_PIXELS_PER_DOT);
        Test.assertEqualMessage(DateGlyph.STROKE_PIXELS, DotGrid.DOT,
            "a stroke is DOT pixels long");
        Test.assertMessage(
            DateGlyph.ARM >= 0 &&
            DateGlyph.ARM + 1 < DotGrid.ARMS.size(),
            "the struck stroke must come out of DotGrid.ARMS");
        Test.assertMessage(DateGlyph.ARM % DotGrid.ARM_VALUES == 0,
            "and must be the first arm of an orientation, not the middle of one");
        logger.debug("a struck dot lights " + DateGlyph.STROKE_PIXELS +
                     " pixels against " + LIT_PIXELS_PER_DOT);
        return true;
    }

    //! The two implementations of the watermark agree.
    //!
    //! tools/mockup.py mirrors DateGlyph by hand, the way it mirrors the
    //! lattice and the palette, and it is what the placement and the marking
    //! were chosen on. The figures below come from that mockup — the same role
    //! EXPECTED_DOTS plays for the lattice — so a constant moved on one side
    //! and not the other stops the mockups being an honest preview and says so
    //! here rather than in a render nobody looked at closely.
    (:test)
    function theWatermarkMatchesTheMockup(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();

        Test.assertEqualMessage(DateGlyph.SCALE, 2, "mockup.py: SCALE = 2");
        Test.assertEqualMessage(DateGlyph.COLS, 14,
            "mockup.py: GLYPH_COLS = 14");
        Test.assertEqualMessage(DateGlyph.ROWS, 10,
            "mockup.py: GLYPH_ROWS = 10");
        Test.assertEqualMessage(DateGlyph.ORIGIN_COL, 12,
            "mockup.py: GLYPH_ORIGIN = (12, 23)");
        Test.assertEqualMessage(DateGlyph.ORIGIN_ROW, 23,
            "mockup.py: GLYPH_ORIGIN = (12, 23)");

        // Dots struck, per day, straight out of tools/mockup.py.
        var days = [5, 15, 28, 31] as Array<Number>;
        var counts = [92, 76, 96, 76] as Array<Number>;
        for (var i = 0; i < days.size(); i++) {
            DateGlyph.ensure(days[i]);
            Test.assertEqualMessage(DateGlyph.lit, counts[i],
                "day " + days[i] + " strikes " + DateGlyph.lit +
                " dots here and " + counts[i] + " in the mockup");
        }
        return true;
    }

    //! Ten digits, fifteen bits each, none of them blank.
    (:test)
    function theWatermarkFontCoversTenDigits(logger as Logger) as Boolean {
        Test.assertEqualMessage(DateGlyph.DIGITS.size(), 10,
            "the font must have a glyph for every digit");
        var full = 1 << DateGlyph.FONT_BITS;
        for (var d = 0; d < DateGlyph.DIGITS.size(); d++) {
            var bits = DateGlyph.DIGITS[d];
            Test.assertMessage(bits > 0 && bits < full,
                "digit " + d + " is not a " + DateGlyph.FONT_BITS + "-bit glyph");
            for (var e = d + 1; e < DateGlyph.DIGITS.size(); e++) {
                Test.assertMessage(bits != DateGlyph.DIGITS[e],
                    "digits " + d + " and " + e + " draw the same shape");
            }
        }
        return true;
    }

    //! Every day of the month draws both its digits, leading zero included.
    //!
    //! The count is derived from the font's own bit counts rather than from
    //! cellLit, so it is a check on the scaling and the gutter and not a
    //! restatement of the filter. A day under ten that dropped its leading zero
    //! would come out short here by however many bits a `0` sets.
    (:test)
    function everyDayDrawsBothOfItsDigits(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        for (var day = 1; day <= 31; day++) {
            DateGlyph.ensure(day);
            var expected = (bitsSet(DateGlyph.DIGITS[day / 10]) +
                            bitsSet(DateGlyph.DIGITS[day % 10])) *
                           GLYPH_CELLS_PER_BIT;
            Test.assertEqualMessage(DateGlyph.lit, expected,
                "day " + day + " struck " + DateGlyph.lit + " dots, not " +
                expected);
        }
        logger.debug("days 1-31 all draw two digits");
        return true;
    }

    //! The row the staleness test below drives. Named rather than written as a
    //! bare index because the two have to move together: the test changes the
    //! backing setting and then asserts that *this* row followed it, so a row
    //! inserted above backing turns the test into a check on somebody else's
    //! sub-label, which passes for the wrong reason or fails for no reason.
    const MENU_BACKING_ROW = 1;

    (:test)
    function settingsMenuRefreshesItsSubLabels(logger as Logger) as Boolean {
        Properties.setValue(StatMap.PROPERTY_BACKING, StatMap.BACKING_OFF);
        Config.reload();
        var menu = new SettingsMenu();
        var before = subLabelOf(menu, MENU_BACKING_ROW);

        // What a sub-menu does when the user picks a different value.
        Properties.setValue(StatMap.PROPERTY_BACKING, StatMap.BACKING_WHITE);
        Config.reload();
        Test.assertEqualMessage(subLabelOf(menu, MENU_BACKING_ROW), before,
            "sub-label should still be stale before the menu is shown again");

        menu.onShow();
        logger.debug("was '" + before + "', now '" +
                     subLabelOf(menu, MENU_BACKING_ROW) + "'");
        Test.assertMessage(!subLabelOf(menu, MENU_BACKING_ROW).equals(before),
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
        var before = copyOf(view.ringPrint(spans, at12, none, emptyBlocks()));
        var after = copyOf(view.ringPrint(spans, at18, none, emptyBlocks()));
        logger.debug("the ring print is " + before.size() + " values");
        Test.assertMessage(!FrameGate.same(before, after),
            "a mark that moved must change the ring print");
        Test.assertMessage(
            FrameGate.same(before, view.ringPrint(spans, at12, none, emptyBlocks())),
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

        var under = copyOf(view.ringPrint(spans, marks, noOvers(), emptyBlocks()));
        var over = copyOf(view.ringPrint(spans, marks, allOvers(), emptyBlocks()));
        logger.debug("the ring print is " + under.size() + " values");
        Test.assertMessage(!FrameGate.same(under, over),
            "crossing the goal must change the ring print — the span alone " +
            "cannot tell a lap of 0.05 from a fill of 0.05");
        Test.assertMessage(
            FrameGate.same(under, view.ringPrint(spans, marks, noOvers(), emptyBlocks())),
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
        var rotations = [StatMap.ROTATION_RADIAL, StatMap.ROTATION_UPRIGHT,
                         StatMap.ROTATION_UPRIGHT_DATE] as Array<Number>;
        for (var r = 0; r < rotations.size(); r++) {
            StatMap.rotation = rotations[r];
            DateGlyph.ensure(15);
            MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                                Palette.rampActive, null,
                                FrameGate.everything(), true);
            MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                                Palette.rampActive, Palette.BACKING_WHITE,
                                FrameGate.everything(), true);
            // And again drawing one ring into what is already there, which is
            // the path a moved span actually takes.
            MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
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
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null,
                            FrameGate.everything(), true);
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(MatrixRenderer.walked[ring],
                "a cleared frame must redraw every ring, including " + ring);
        }

        // Now one ring only. The other three must not be touched at all.
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
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
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(1), false);
        var first = DotGrid.markedDotFor(1, 0.25);
        Test.assertMessage(first >= 0, "0.25 must mark a dot on ring 1");
        Test.assertEqualMessage(MatrixRenderer.drawnMark[1], first,
            "the renderer must remember the mark it drew");

        // The mark moves. The cell it left must be rubbed out, or 16 pixels of
        // it survive under the cross that replaces it.
        marks[1] = 0.75;
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
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
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
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
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null,
                            onlyRingDirty(3), false);
        Test.assertEqualMessage(MatrixRenderer.drawnMark[1], standing,
            "a ring left alone still has its mark on screen, so the renderer " +
            "must not lose track of where it is");

        // And a clear wipes the slate: nothing is on screen to rub out.
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
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
        // Five values, matching CrossoverView.fieldPrint(): drift x and y, the
        // backing colour, the minute the hands are at, and the day the
        // watermark is drawing. Zero here is the watermark switched off.
        return [0.0, 0.0, -1.0, 0.0, 0.0] as Array<Float>;
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

    //! The sweep is the minute expressed as a level, counting the second in
    //! progress: 1/60 at :00, one stop a tick, and exactly 1.0 at :59. It never
    //! goes *past* 1.0 — a span end above a full turn would not simply saturate,
    //! it would light a ring's dots in the wrong order — so both the ceiling and
    //! the rollover are asserted rather than assumed.
    (:test)
    function theSweepFillsItsMinuteAndResets(logger as Logger) as Boolean {
        var stopSize = 1.0 / 60.0;
        Test.assertMessage((ClockData.fraction(0) - stopSize).abs() < 0.001,
            ":00 must light the first stop, not sit dark on the origin");
        for (var second = 0; second < 60; second += 15) {
            var expected = (second + 1) / 60.0;
            Test.assertMessage((ClockData.fraction(second) - expected).abs() < 0.001,
                "each second must land on its own stop around the ring");
        }
        Test.assertEqualMessage(ClockData.fraction(59), 1.0,
            "the last second of the minute must complete the turn — a sweep " +
            "that stops at 59/60 leaves the stop before twelve permanently dark");
        Test.assertMessage((ClockData.fraction(60) - stopSize).abs() < 0.001,
            "the minute rolling over must put the sweep back on the first stop");

        // Whatever the clock says right now, the reading is a level pinned to
        // the origin and landing on one of the sixty stops.
        var live = Source.span(Source.SOURCE_SECONDS, true);
        Test.assertEqualMessage(live[0], 0.0,
            "seconds is a level, so its span must start at the origin");
        var stop = live[1] * 60.0;
        logger.debug("the sweep is at " + live[1] + ", stop " + stop);
        Test.assertMessage((stop - (stop + 0.5).toNumber()).abs() < 0.001,
            "the sweep must sit on a whole second, not between two");
        Test.assertMessage(live[1] > 0.0 && live[1] <= 1.0,
            "the sweep must stay inside the ring");
        return true;
    }

    //! How many dots of each ring a span leaves dark. The seconds ring is the
    //! only source whose fill is expected to close, so the count is what the
    //! test below reads rather than a lit/dark pair.
    function darkPerRing(span as Array<Float>) as Array<Number> {
        var spans = new [StatMap.RINGS] as Array<Array<Float> >;
        var dark = new [StatMap.RINGS] as Array<Number>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            spans[i] = span;
            dark[i] = 0;
        }
        for (var row = 0; row < DotGrid.ROWS; row++) {
            var dy = DotGrid.offsetAt(row);
            for (var col = 0; col < DotGrid.COLS; col++) {
                var dx = DotGrid.offsetAt(col);
                if (!DotGrid.contains(dx, dy)) {
                    continue;
                }
                var slot = StatMap.classify(dx, dy, spans);
                if (slot % 2 == 0) {
                    dark[slot / 2] += 1;
                }
            }
        }
        return dark;
    }

    //! The reported bug: the sweep climbed all minute and never actually got
    //! there. A span end of 59/60 stops short of the outermost dots, which sit
    //! as far round as 0.9958 — so eight dots on ring 0 and one on ring 3 stayed
    //! dark at every second of every minute, and the leading edge jumped back
    //! from just before twelve rather than closing on it.
    //!
    //! spanEndpoints already proves a hard-coded [0.0, 1.0] lights everything.
    //! What was missing is that the seconds *source* produces such a span, which
    //! is the half that regressed. :58 is asserted alongside so this cannot pass
    //! against a sweep that is simply always full.
    (:test)
    function theSweepClosesOnTheLastSecond(logger as Logger) as Boolean {
        var last = [0.0, ClockData.fraction(59)] as Array<Float>;
        var dark = darkPerRing(last);
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(dark[ring], 0,
                "ring " + ring + " left " + dark[ring] + " dots dark at :59 — " +
                "the sweep must close its turn on the last second");
        }

        var almost = darkPerRing([0.0, ClockData.fraction(58)] as Array<Float>);
        var short = 0;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            short += almost[ring];
        }
        logger.debug("at :58 the sweep still leaves " + short + " dots dark");
        Test.assertMessage(short > 0,
            "the second before last must still be short of a full turn, or " +
            "this test would pass against a sweep that never moves");
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

    // ------------------------------------------------------------------
    // Delta redraw
    // ------------------------------------------------------------------

    //! A 64x64 off-screen Dc, or null when the device has no buffered bitmap.
    //! Full-screen is ~304KB and takes the runner out; size does not matter to
    //! what these cover, because the renderer still walks every dot and the
    //! drawing clips.
    function probeDc(logger as Logger) as Graphics.Dc? {
        var bitmap = Graphics.createBufferedBitmap(
            {:width => 64, :height => 64}).get();
        if (!(bitmap instanceof Graphics.BufferedBitmap)) {
            logger.debug("no buffered bitmap available; draw not exercised");
            return null;
        }
        return bitmap.getDc();
    }

    function ringSize(ring as Number) as Number {
        return DotGrid.ringStart[ring + 1] - DotGrid.ringStart[ring];
    }

    //! Every ring's block channel empty, which is exactly what
    //! StatMap.blocks() reports for a ring assigned to anything else. The
    //! neutral input for every test that is not about the block ring.
    function emptyBlocks() as Array<Number> {
        var out = new [StatMap.RINGS * StatMap.BLOCK_VALUES] as Array<Number>;
        for (var i = 0; i < out.size(); i++) {
            out[i] = 0;
        }
        return out;
    }

    function noMarks() as Array<Float> {
        var marks = new [StatMap.RINGS] as Array<Float>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            marks[i] = Source.NO_MARKER;
        }
        return marks;
    }

    //! Two cleared frames, so the renderer has this ring in both buffers and
    //! the draw after them is delta-eligible. Anything testing the delta has
    //! to get here first, because the first two draws of any state are full
    //! ones by design.
    function settleBuffers(dc as Graphics.Dc, spans as Array<Array<Float> >,
                           overs as Array<Boolean>, backing as Number?) as Void {
        var marks = noMarks();
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, backing,
                            FrameGate.everything(), true);
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, backing,
                            FrameGate.everything(), true);
    }

    //! How many of a ring's dots read differently between two spans.
    function differing(ring as Number, a as Array<Float>,
                       b as Array<Float>) as Number {
        var count = 0;
        for (var i = DotGrid.ringStart[ring]; i < DotGrid.ringStart[ring + 1];
                i++) {
            var at = DotGrid.positionOf[i];
            if (StatMap.isLit(at, a) != StatMap.isLit(at, b)) {
                count++;
            }
        }
        return count;
    }

    //! A span that moved a little must repaint a little.
    //!
    //! The measurement this change is built on: the two drawLine calls per dot
    //! are ~55% of a drawn frame, and a seconds ring moves its edge about five
    //! dots between draws. So the ring is still walked — that part is cheap —
    //! and the dots that did not change tier are left where they are.
    //!
    //! Asserted as a fraction of the ring rather than an exact count, because
    //! the exact count is a property of the lattice and this is a claim about
    //! the renderer.
    (:test)
    function aMovedSpanRepaintsOnlyItsEdge(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var overs = noOvers();
        var spans = everySpan(0.0, 0.50);
        settleBuffers(dc, spans, overs, null);

        var moved = everySpan(0.0, 0.55);
        MatrixRenderer.draw(dc, moved, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);

        var whole = ringSize(2);
        var expected = differing(2, spans[2], moved[2]);
        logger.debug("ring 2: painted " + MatrixRenderer.painted + " of " +
                     whole + ", " + expected + " dots changed tier");
        Test.assertMessage(MatrixRenderer.painted > 0,
            "the span moved, so something must have been drawn");
        Test.assertEqualMessage(MatrixRenderer.painted, expected,
            "a delta must draw exactly the dots that changed tier");
        Test.assertMessage(MatrixRenderer.painted * 4 < whole,
            "a 5% span move repainted " + MatrixRenderer.painted + " of " +
            whole + " dots — that is not a delta, it is a full ring");
        return true;
    }

    //! A delta never skips a struck dot, and the watermark survives one.
    //!
    //! **This is the invariant the render loop's shape rests on.** The cursor
    //! that finds the struck dots advances inside the branch that draws one,
    //! not at the top of the loop — which is what leaves an ordinary dot a
    //! single comparison rather than a test and a local. The price is that a
    //! dot the delta skips never reaches the branch, so a skipped struck dot
    //! would leave the cursor a step behind and shift the rest of the numeral
    //! along the ring. `i != glyphNext` in the delta's condition is what stops
    //! that, and it is exactly the term someone tidying the condition would
    //! take out: it looks redundant, since a struck dot's *lit-ness* reads the
    //! same as any other dot's.
    //!
    //! Every other watermark test clears the screen, which rules the delta out
    //! — so without this one the whole interaction is untested.
    (:test)
    function aDeltaNeverSkipsAStruckDot(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var turning = StatMap.rotation;
        StatMap.rotation = StatMap.ROTATION_UPRIGHT_DATE;
        DateGlyph.ensure(GLYPH_DAY);

        var overs = noOvers();
        var spans = everySpan(0.0, 0.50);
        // Two full draws put this ring in both buffers, which is what makes the
        // next one delta-eligible.
        settleBuffers(dc, spans, overs, null);

        var ring = 2;
        var mine = DateGlyph.firstFor[ring + 1] - DateGlyph.firstFor[ring];
        Test.assertMessage(mine > 0,
            "ring " + ring + " carries none of the watermark, so this test " +
            "would pass vacuously — pick a ring the window crosses");

        var moved = everySpan(0.0, 0.55);
        MatrixRenderer.draw(dc, moved, noMarks(), overs, emptyBlocks(),
                            Palette.active, Palette.rampActive, null,
                            onlyRingDirty(ring), false);

        var whole = ringSize(ring);
        logger.debug("ring " + ring + ": painted " + MatrixRenderer.painted +
                     " of " + whole + ", struck " + MatrixRenderer.struck +
                     " of " + mine);
        // The delta really engaged. Without this the two below would pass on a
        // full repaint, which is the failure mode they exist to rule out.
        Test.assertMessage(MatrixRenderer.painted * 2 < whole,
            "the delta did not engage: " + MatrixRenderer.painted + " of " +
            whole + " dots is a full ring, so what follows proves nothing");
        Test.assertEqualMessage(MatrixRenderer.struck, mine,
            "a delta redraw must still strike every one of this ring's " +
            "watermark dots — one skipped leaves the cursor behind and shifts " +
            "the rest of the numeral round the ring");

        // And the dots it changed tier on are still all drawn: forcing the
        // struck ones in must not cost the delta its own job.
        var expected = differing(ring, spans[ring], moved[ring]);
        Test.assertMessage(MatrixRenderer.painted >= expected,
            "the delta dropped a dot that changed tier");

        StatMap.rotation = turning;
        return true;
    }

    //! The delta must cover **both** buffers, not just the last draw.
    //!
    //! This is the one that would rot silently. A partial draw is only correct
    //! in the buffer it lands in, and on a double-buffered device that buffer
    //! was written two draws ago — which is why FrameGate repeats a change into
    //! HOLD draws. A delta measured against the previous span alone looks right
    //! on screen and leaves every other frame a step behind, which reads as a
    //! ring that stutters rather than as anything broken.
    (:test)
    function theDeltaCoversBothBuffersNotJustTheLastDraw(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var overs = noOvers();
        var first = everySpan(0.0, 0.30);
        settleBuffers(dc, first, overs, null);

        // Two moves in a row, the way a seconds ring actually advances.
        var second = everySpan(0.0, 0.40);
        MatrixRenderer.draw(dc, second, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);
        var third = everySpan(0.0, 0.50);
        MatrixRenderer.draw(dc, third, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);

        // The buffer this third draw lands in was last written with `first`,
        // so the dots owed a repaint are those differing from either.
        var union = differing(2, third[2], first[2]);
        var justTheLast = differing(2, third[2], second[2]);
        logger.debug("painted " + MatrixRenderer.painted + ", union " + union +
                     ", against the last draw alone " + justTheLast);
        Test.assertMessage(union > justTheLast,
            "this test proves nothing unless the two-draw span is wider");
        Test.assertEqualMessage(MatrixRenderer.painted, union,
            "the delta must cover the span drawn two draws ago as well — " +
            "it painted " + MatrixRenderer.painted + " where the buffer this " +
            "draw lands in is " + union + " dots stale");
        return true;
    }

    //! Anything but the span repaints the ring, twice.
    //!
    //! A delta may only differ by span. Both colours, the over flag, the ramp
    //! and the backing repaint the ring wholesale, and a delta across one of
    //! them would leave every unchanged dot showing a tier that no longer
    //! exists. Twice, because both buffers hold the old colours.
    (:test)
    function aChangedTierForcesTwoFullRings(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var spans = everySpan(0.0, 0.50);
        var overs = noOvers();
        settleBuffers(dc, spans, overs, null);

        var whole = ringSize(2);
        // Same span, but the ring has gone past its goal — which swaps both
        // tiers underneath the loop.
        overs[2] = true;
        MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);
        Test.assertEqualMessage(MatrixRenderer.painted, whole,
            "the over flag swapped both tiers and the ring was not fully " +
            "repainted — every unchanged dot is showing a colour that is gone");
        MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);
        Test.assertEqualMessage(MatrixRenderer.painted, whole,
            "the second buffer still holds the old tiers, so the repeat draw " +
            "must be full as well — this is what HOLD is for");
        // And only then does the delta come back.
        MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);
        Test.assertMessage(MatrixRenderer.painted < whole,
            "with both buffers holding the new tiers the ring may delta again");
        logger.debug("over flip: full, full, then " + MatrixRenderer.painted +
                     " of " + whole);
        return true;
    }

    //! A cleared frame is never a delta.
    (:test)
    function aClearedFrameRedrawsEveryDot(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var spans = everySpan(0.0, 0.50);
        var overs = noOvers();
        settleBuffers(dc, spans, overs, null);
        MatrixRenderer.draw(dc, spans, noMarks(), overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null,
                            FrameGate.everything(), true);
        Test.assertEqualMessage(MatrixRenderer.painted, DotGrid.count,
            "the screen was blacked, so every dot is owed a cross — " +
            "a delta here leaves the field mostly black");
        return true;
    }

    //! A mark the erase rubbed out gets its dot back.
    //!
    //! The one place the delta and the mark interact. Rubbing a mark out blacks
    //! a DOT-square cell, which is the whole of that dot; the full repaint used
    //! to put the cross back as a matter of course. A delta will not, because
    //! that dot's tier did not change — so it has to be forced, or a moved mark
    //! leaves a black hole exactly where the reading used to be.
    (:test)
    function anErasedMarkCellGetsItsDotBack(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var spans = everySpan(0.0, 0.50);
        var overs = noOvers();
        settleBuffers(dc, spans, overs, null);

        var marks = noMarks();
        marks[2] = 0.20;
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);
        // The mark moves, on a span that did not. Nothing changed tier, so the
        // only dots owed a cross are the cells the erase blacked.
        marks[2] = 0.80;
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(2), false);
        logger.debug("mark move: erased " + MatrixRenderer.erased +
                     ", painted " + MatrixRenderer.painted);
        Test.assertMessage(MatrixRenderer.erased > 0,
            "the mark moved, so its old cell must have been rubbed out");
        Test.assertMessage(MatrixRenderer.painted >= MatrixRenderer.erased,
            "every cell the erase blacked is owed its dot back — " +
            MatrixRenderer.erased + " rubbed out against " +
            MatrixRenderer.painted + " drawn leaves a hole in the field");
        Test.assertMessage(MatrixRenderer.painted * 4 < ringSize(2),
            "only the mark moved, so this must still be a delta");
        return true;
    }

    // ------------------------------------------------------------------
    // Twelve-hour block sources
    // ------------------------------------------------------------------

    //! The worst (block, sub-band) a ring may hold and still be offered a
    //! block source. Measured on this lattice at a 22.5-degree block: rings 0
    //! and 1 floor at 8 and 6 dots, rings 2 and 3 at 4 and 2. Six is what
    //! separates them, and onlyTheOuterTwoRingsResolveTwelveHoursInThreeBands
    //! is what holds Source.BLOCKS_TOP_RING to that measurement rather than to
    //! taste.
    const MIN_BAND_DOTS = 6;

    //! Twelve levels packed the way a block source packs them:
    //! [levels low, levels high, known]. A level of HourBands.UNKNOWN leaves
    //! that block's known bit clear.
    function packBlocks(levels as Array<Number>) as Array<Number> {
        var words = [0, 0] as Array<Number>;
        var known = 0;
        for (var b = 0; b < HourBands.HOURS; b++) {
            if (levels[b] != HourBands.UNKNOWN) {
                HourBands.raise(words, b, levels[b]);
                known = known | (1 << b);
            }
        }
        return [words[0], words[1], known] as Array<Number>;
    }

    function everyBlockAt(level as Number) as Array<Number> {
        var out = new [HourBands.HOURS] as Array<Number>;
        for (var b = 0; b < HourBands.HOURS; b++) {
            out[b] = level;
        }
        return out;
    }

    //! The block channel with one ring carrying these twelve levels.
    function blocksFor(ring as Number,
                       levels as Array<Number>) as Array<Number> {
        var packed = packBlocks(levels);
        var out = emptyBlocks();
        out[ring * StatMap.BLOCK_VALUES] = packed[0];
        out[ring * StatMap.BLOCK_VALUES + 1] = packed[1];
        out[ring * StatMap.BLOCK_VALUES + 2] = packed[2];
        return out;
    }

    //! The four per-block tables MatrixRenderer resolves before its dot loop,
    //! rebuilt here by the same rules.
    //!
    //! A class rather than four returned arrays because two of them are
    //! Numbers and two are Floats, which do not travel together in one array
    //! under strict typing — and because more than one table has to exist at
    //! once: the sub-band measurements below compare a level against the one
    //! below it. The geometry tests read the field through this and
    //! HourBands.litAt(), which is the definition the renderer inlines.
    class BlockTables {
        var full as Array<Number>;
        var part as Array<Number>;
        var lo as Array<Float>;
        var hi as Array<Float>;

        function initialize(ring as Number, levels as Array<Number>) {
            // These read the cache directly rather than through the renderer,
            // which is what usually builds it.
            DotGrid.ensureBuilt();
            var packed = packBlocks(levels);
            var slots = HourBands.HOURS + 1;
            full = new [slots] as Array<Number>;
            part = new [slots] as Array<Number>;
            lo = new [slots] as Array<Float>;
            hi = new [slots] as Array<Float>;
            var base = ring * HourBands.BANDS;
            for (var b = 0; b < HourBands.HOURS; b++) {
                var level = HourBands.levelAt(packed[0], packed[1], packed[2],
                                              b);
                if (level == HourBands.UNKNOWN) {
                    full[b] = 0;
                    part[b] = 0;
                    lo[b] = 0.0;
                    hi[b] = 0.0;
                    continue;
                }
                var bands = HourBands.fullBandsFor(level);
                var window = HourBands.partialHalfFor(level);
                full[b] = (bands == 0) ? 0 : DotGrid.bandEdge[base + bands - 1];
                part[b] = (window > 0.0) ? DotGrid.bandEdge[base + bands] : 0;
                lo[b] = HourBands.BLOCK_CENTRE - window;
                hi[b] = HourBands.BLOCK_CENTRE + window;
            }
            full[HourBands.HOURS] = full[0];
            part[HourBands.HOURS] = part[0];
            lo[HourBands.HOURS] = lo[0];
            hi[HourBands.HOURS] = hi[0];
        }

        function lit(position as Float, radiusSq as Number) as Boolean {
            return HourBands.litAt(position, radiusSq, full, part, lo, hi);
        }

        //! How many of this ring's dots the tables light.
        function litDots(ring as Number) as Number {
            var n = 0;
            for (var i = DotGrid.ringStart[ring];
                    i < DotGrid.ringStart[ring + 1]; i++) {
                var dx = DotGrid.xs[i];
                var dy = DotGrid.ys[i];
                if (lit(DotGrid.positionOf[i], dx * dx + dy * dy)) {
                    n++;
                }
            }
            return n;
        }

        //! How many dots each block lights, twelve entries.
        function litPerBlock(ring as Number) as Array<Number> {
            var out = new [HourBands.HOURS] as Array<Number>;
            for (var b = 0; b < HourBands.HOURS; b++) {
                out[b] = 0;
            }
            for (var i = DotGrid.ringStart[ring];
                    i < DotGrid.ringStart[ring + 1]; i++) {
                var position = DotGrid.positionOf[i];
                var dx = DotGrid.xs[i];
                var dy = DotGrid.ys[i];
                if (lit(position, dx * dx + dy * dy)) {
                    out[HourBands.blockOf(position)]++;
                }
            }
            return out;
        }
    }

    //! Every block at one level, on one ring.
    function tablesAt(ring as Number, level as Number) as BlockTables {
        return new BlockTables(ring, everyBlockAt(level));
    }

    //! The anchoring claim, asserted directly and without a clock.
    //!
    //! The hour hand at local hour H points at clock position H mod 12, so the
    //! forecast N hours out has to sit at (H + N) mod 12 — which is that
    //! forecast hour's own hour-of-day, mod 12. That identity is why nothing
    //! rotates. If this ever fails, something has started treating the block
    //! index as an offset from now rather than as an hour of the day.
    (:test)
    function hoursAheadLandWhereTheHourHandWillPoint(logger as Logger)
            as Boolean {
        var anchors = [0, 11, 12, 13, 23] as Array<Number>;
        var epoch = 1700000000;
        for (var a = 0; a < anchors.size(); a++) {
            var anchor = anchors[a];
            for (var ahead = 0; ahead < HourBands.HOURS; ahead++) {
                var block = HourlyWeatherData.blockFor(
                    anchor, epoch, epoch + ahead * 3600);
                Test.assertEqualMessage(block,
                    (anchor + ahead) % HourBands.HOURS,
                    "at hour " + anchor + ", " + ahead + " hours ahead must " +
                    "land where the hour hand will be");
            }
        }
        // Half past the hour still belongs to that hour's block: the bucket is
        // an hour wide, not a boundary.
        Test.assertEqualMessage(
            HourlyWeatherData.blockFor(9, epoch, epoch + 3600 + 1799), 10,
            "a reading part-way through an hour belongs to that hour");
        logger.debug("anchoring holds for every hour of the day");
        return true;
    }

    //! Outside the twelve hours the ring covers, nothing is bucketed.
    //!
    //! The lower bound is the one that matters. Monkey C truncates toward zero,
    //! so an entry an hour in the past divides to 0 and would land on the
    //! current hour — yesterday's weather shown as now, with nothing to say it.
    (:test)
    function theTwelveHourWindowExcludesAnythingOutsideIt(logger as Logger)
            as Boolean {
        var epoch = 1700000000;
        Test.assertEqualMessage(
            HourlyWeatherData.blockFor(6, epoch, epoch - 1), -1,
            "a reading before this hour must not fold onto it");
        Test.assertEqualMessage(
            HourlyWeatherData.blockFor(6, epoch, epoch - 3600), -1,
            "an hour in the past must be dropped, not truncated to now");
        Test.assertEqualMessage(
            HourlyWeatherData.blockFor(
                6, epoch, epoch + HourlyWeatherData.WINDOW_S), -1,
            "twelve hours out has wrapped onto now and must be dropped");
        Test.assertEqualMessage(
            HourlyWeatherData.blockFor(
                6, epoch, epoch + HourlyWeatherData.WINDOW_S - 1),
            5, "the last second inside the window is still the last block");
        return true;
    }

    //! The scale runs the whole way to a certainty, in sixteen steps.
    //!
    //! The sub-bands used to *be* the scale, so a chance had four readings and
    //! anything at or above 75% drew the same full ring. Now the bands are the
    //! coarse axis and the width of the partial band is the fine one, so the
    //! top of the scale means what it says: a full block is 100%, one whole
    //! sub-band is a third, and 10% is a level rather than nothing.
    (:test)
    function aPercentageChanceLandsOnTheRightLevel(logger as Logger)
            as Boolean {
        Test.assertEqualMessage(HourlyWeatherData.rainLevelFor(0), 0,
            "0% is dry");
        Test.assertEqualMessage(HourlyWeatherData.rainLevelFor(6), 0,
            "below one step of the scale still reads dry, or a day of " +
            "two-percent hours draws a ring of pips");
        Test.assertEqualMessage(HourlyWeatherData.rainLevelFor(10), 1,
            "10% is the reading this scale exists for: a level, not nothing");
        Test.assertEqualMessage(HourlyWeatherData.rainLevelFor(50),
            HourBands.LEVELS / 2, "half a chance is half the scale");
        Test.assertEqualMessage(HourlyWeatherData.rainLevelFor(100),
            HourBands.LEVELS,
            "a certainty must reach the top of the scale, not overflow it");
        Test.assertEqualMessage(HourlyWeatherData.rainLevelFor(-5), 0,
            "a nonsense reading must not index below the scale");

        // Monotonic the whole way up, and every level reachable — a scale with
        // a rung nothing maps to is a rung the face can never draw.
        var seen = new [HourBands.LEVELS + 1] as Array<Boolean>;
        for (var i = 0; i <= HourBands.LEVELS; i++) {
            seen[i] = false;
        }
        var previous = 0;
        for (var percent = 0; percent <= 100; percent++) {
            var level = HourlyWeatherData.rainLevelFor(percent);
            Test.assertMessage(level >= previous,
                percent + "% read lower than " + (percent - 1) + "%");
            Test.assertMessage(level >= 0 && level <= HourBands.LEVELS,
                percent + "% left the scale entirely at " + level);
            seen[level] = true;
            previous = level;
        }
        for (var i = 0; i <= HourBands.LEVELS; i++) {
            Test.assertMessage(seen[i],
                "no percentage reaches level " + i + ", so the face can " +
                "never draw it");
        }

        // The band edges land on levels rather than between them, which is
        // what lets a test say "exactly one sub-band" without a magic number.
        Test.assertEqualMessage(
            HourBands.LEVELS_PER_BAND * HourBands.BANDS, HourBands.LEVELS,
            "BANDS must divide LEVELS, or no level fills a whole band");
        for (var band = 0; band <= HourBands.BANDS; band++) {
            var level = band * HourBands.LEVELS_PER_BAND;
            Test.assertEqualMessage(HourBands.fullBandsFor(level), band,
                "level " + level + " must fill exactly " + band + " bands");
            Test.assertEqualMessage(HourBands.partialHalfFor(level), 0.0,
                "level " + level + " lands on a band edge, so it must have " +
                "no partial band at all");
        }
        return true;
    }

    //! UV uses Garmin's bounded 0–10 index, and missing UV must not borrow
    //! rain's known bit merely because both fields came from one forecast row.
    (:test)
    function uvUsesItsWholeScaleAndItsOwnKnownBits(logger as Logger)
            as Boolean {
        Test.assertEqualMessage(HourlyWeatherData.uvLevelFor(0.0), 0,
            "zero UV must be empty");
        Test.assertEqualMessage(HourlyWeatherData.uvLevelFor(5.0),
            HourBands.LEVELS / 2, "UV 5 must sit halfway up the scale");
        Test.assertEqualMessage(HourlyWeatherData.uvLevelFor(10.0),
            HourBands.LEVELS, "UV 10 must fill the block");
        Test.assertEqualMessage(HourlyWeatherData.uvLevelFor(12.0),
            HourBands.LEVELS, "UV above the documented range must clamp");
        Test.assertEqualMessage(HourlyWeatherData.uvLevelFor(-1.0), 0,
            "negative UV must not index below the scale");

        HourlyWeatherData.clear();
        HourBands.raise(HourlyWeatherData.rainLevels, 4, 9);
        HourlyWeatherData.rainKnown = 1 << 4;
        HourBands.raise(HourlyWeatherData.uvLevels, 5, 8);
        HourlyWeatherData.uvKnown = 1 << 5;
        Test.assertEqualMessage(
            HourBands.levelAt(HourlyWeatherData.uvLevels[0],
                              HourlyWeatherData.uvLevels[1],
                              HourlyWeatherData.uvKnown, 4),
            HourBands.UNKNOWN,
            "known rain must not turn missing UV into zero UV");
        Test.assertEqualMessage(
            HourBands.levelAt(HourlyWeatherData.rainLevels[0],
                              HourlyWeatherData.rainLevels[1],
                              HourlyWeatherData.rainKnown, 5),
            HourBands.UNKNOWN,
            "known UV must not turn missing rain into dry weather");
        HourlyWeatherData.forget();
        HourlyWeatherData.clear();
        logger.debug("UV 0–10 reaches the whole block scale");
        return true;
    }

    //! Rain and UV are two views of one cached Weather.getHourlyForecast().
    (:test)
    function hourlyWeatherSourcesShareOneMinuteSample(logger as Logger)
            as Boolean {
        HourlyWeatherData.forget();
        var rain = [0, 0, 0] as Array<Number>;
        var uv = [0, 0, 0] as Array<Number>;
        HourlyWeatherData.fillRain(rain, 0);
        Test.assertMessage(HourlyWeatherData.sampled,
            "the first hourly weather source must take a sample");
        var taken = HourlyWeatherData.takenAt;
        HourlyWeatherData.fillUv(uv, 0);
        Test.assertEqualMessage(HourlyWeatherData.takenAt, taken,
            "UV must reuse rain's hourly-weather sample inside the minute");
        HourlyWeatherData.forget();
        return true;
    }

    //! All three packed words have to survive the frame print's float round
    //! trip.
    //!
    //! FrameGate compares prints element by element as floats, so a bit lost
    //! here is a forecast change the gate cannot see — the ring would simply
    //! stop updating, which looks like nothing going wrong at all. Four bits a
    //! block is what forces two levels words: twelve blocks at four bits is 48,
    //! and nothing here round-trips that.
    (:test)
    function theHourlyMasksSurviveTheFramePrint(logger as Logger) as Boolean {
        var levels = new [HourBands.HOURS] as Array<Number>;
        for (var b = 0; b < HourBands.HOURS; b++) {
            levels[b] = b % (HourBands.LEVELS + 1);
        }
        var packed = packBlocks(levels);
        for (var i = 0; i < packed.size(); i++) {
            var through = packed[i].toFloat().toNumber();
            Test.assertEqualMessage(through, packed[i],
                "word " + i + " lost a bit through the print: " + packed[i] +
                " came back as " + through);
        }

        // And the worst case, which is what bounds the claim: every block at
        // the top of the scale, every block known.
        var full = packBlocks(everyBlockAt(HourBands.LEVELS));
        for (var i = 0; i < HourBands.LEVEL_WORDS; i++) {
            Test.assertEqualMessage(full[i], 0xFFFFFF,
                "every block at the top level is what fills a levels word");
            Test.assertEqualMessage(full[i].toFloat().toNumber(), full[i],
                "a full levels word must round-trip exactly");
        }
        Test.assertEqualMessage(full[HourBands.LEVEL_WORDS],
            HourBands.ALL_KNOWN,
            "twelve known hours is what ALL_KNOWN means");
        Test.assertEqualMessage(
            full[HourBands.LEVEL_WORDS].toFloat().toNumber(),
            full[HourBands.LEVEL_WORDS],
            "a full known word must round-trip exactly");

        // Unpacking returns what went in.
        for (var b = 0; b < HourBands.HOURS; b++) {
            Test.assertEqualMessage(
                HourBands.levelAt(packed[0], packed[1], packed[2], b),
                levels[b], "block " + b + " did not survive packing");
        }
        // And the print carries a slot for each of them.
        Test.assertEqualMessage(FrameGate.PER_RING,
            4 + StatMap.BLOCK_VALUES,
            "the ring print must carry every block word beside the span, " +
            "the mark and the over flag");
        logger.debug("levels " + packed[0] + "/" + packed[1] + ", known " +
                     packed[2]);
        return true;
    }

    //! An hour with no forecast is not an hour forecast dry.
    (:test)
    function anHourWithNoForecastReadsAsUnknownRatherThanDry(logger as Logger)
            as Boolean {
        var levels = everyBlockAt(0);
        levels[4] = HourBands.UNKNOWN;
        var packed = packBlocks(levels);

        Test.assertEqualMessage(
            HourBands.levelAt(packed[0], packed[1], packed[2], 4),
            HourBands.UNKNOWN, "an hour with no forecast must read as unknown");
        Test.assertEqualMessage(
            HourBands.levelAt(packed[0], packed[1], packed[2], 3), 0,
            "an hour forecast dry must read as dry, which is a real answer");
        Test.assertMessage(HourBands.UNKNOWN != 0,
            "unknown must not be the same value as dry");

        // And the two must draw differently, or the distinction is invisible.
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(Palette.dimOf[ring] != Palette.active[ring * 2],
                "ring " + ring + " draws an unknown hour exactly as it draws " +
                "a dry one");
        }
        return true;
    }

    //! The sample is bucketed against an hour, so the hour rolling over expires
    //! it however recently it was taken.
    (:test)
    function theForecastIsResampledWhenTheHourRollsOver(logger as Logger)
            as Boolean {
        HourlyWeatherData.refresh();
        var hour = System.getClockTime().hour;
        Test.assertEqualMessage(HourlyWeatherData.anchorHour, hour,
            "a fresh sample is bucketed against the current hour");

        // A sample taken this very moment, but against the wrong hour. The
        // minute timer says it is fresh; the hour says it is not.
        HourlyWeatherData.takenAt = Sample.now();
        HourlyWeatherData.anchorHour = (hour + 1) % 24;
        Test.assertMessage(!Sample.due(HourlyWeatherData.takenAt,
                                       HourlyWeatherData.sampled),
            "this sample must look fresh to the minute timer, or the test " +
            "is not testing the hour");
        HourlyWeatherData.refresh();
        Test.assertEqualMessage(HourlyWeatherData.anchorHour, hour,
            "the hour rolling over must expire the sample on its own");

        // The ordinary minute expiry still works.
        HourlyWeatherData.takenAt = Sample.now() - Sample.INTERVAL_MS - 1;
        var stale = HourlyWeatherData.takenAt;
        HourlyWeatherData.refresh();
        Test.assertMessage(HourlyWeatherData.takenAt != stale,
            "a sample past its minute must still be retaken");
        return true;
    }

    //! Two entries in one hour take the higher reading, whichever order they
    //! arrive in.
    (:test)
    function aBusyHourTakesTheHigherChance(logger as Logger) as Boolean {
        var rising = [0, 0] as Array<Number>;
        HourBands.raise(rising, 5, 4);
        HourBands.raise(rising, 5, 13);
        var falling = [0, 0] as Array<Number>;
        HourBands.raise(falling, 5, 13);
        HourBands.raise(falling, 5, 4);
        Test.assertEqualMessage(
            HourBands.levelAt(rising[0], rising[1], 0xFFF, 5), 13,
            "the higher reading must win when it arrives second");
        Test.assertEqualMessage(rising[0], falling[0],
            "the merge must not depend on the order the forecast arrives in");
        Test.assertEqualMessage(rising[1], falling[1],
            "the merge must not depend on the order the forecast arrives in");

        // And it touches nothing else — including the other word, which is the
        // half of this that only exists because a block's level is four bits.
        var packed = packBlocks(everyBlockAt(1));
        var words = [packed[0], packed[1]] as Array<Number>;
        HourBands.raise(words, 7, HourBands.LEVELS);
        for (var b = 0; b < HourBands.HOURS; b++) {
            Test.assertEqualMessage(
                HourBands.levelAt(words[0], words[1], 0xFFF, b),
                (b == 7) ? HourBands.LEVELS : 1,
                "writing block 7 disturbed block " + b);
        }

        // A block in the *high* word, so neither word is written by luck.
        var high = [0, 0] as Array<Number>;
        HourBands.raise(high, 11, 9);
        Test.assertEqualMessage(high[0], 0,
            "block 11 lives in the high word and must not touch the low one");
        Test.assertEqualMessage(
            HourBands.levelAt(high[0], high[1], 0xFFF, 11), 9,
            "block 11 did not land in the high word");
        return true;
    }

    //! A sampled state is allowed to fall. Forecasts merge upward through
    //! raise(), while exact state replacement uses setLevel().
    (:test)
    function anExactBlockWriteCanLowerWithoutTouchingItsNeighbours(
            logger as Logger) as Boolean {
        var words = [0, 0] as Array<Number>;
        HourBands.setLevel(words, 4, 13);
        HourBands.setLevel(words, 5, 8);
        HourBands.setLevel(words, 4, 3);
        Test.assertEqualMessage(
            HourBands.levelAt(words[0], words[1], HourBands.ALL_KNOWN, 4), 3,
            "an exact write must be able to lower Body Battery");
        Test.assertEqualMessage(
            HourBands.levelAt(words[0], words[1], HourBands.ALL_KNOWN, 5), 8,
            "lowering block 4 disturbed block 5");

        HourBands.setLevel(words, 11, HourBands.LEVELS + 5);
        Test.assertEqualMessage(
            HourBands.levelAt(words[0], words[1], HourBands.ALL_KNOWN, 11),
            HourBands.LEVELS, "an exact write must clamp above the scale");
        HourBands.setLevel(words, 11, -4);
        Test.assertEqualMessage(
            HourBands.levelAt(words[0], words[1], HourBands.ALL_KNOWN, 11), 0,
            "an exact write must clamp below the scale");
        logger.debug("exact block write lowers one nibble in place");
        return true;
    }

    //! Past clock hours walk counter-clockwise from the hand with no renderer
    //! rotation: their own local hour modulo twelve is already that position.
    (:test)
    function bodyBatteryHistoryRunsCounterClockwiseFromTheHand(
            logger as Logger) as Boolean {
        var anchors = [0, 1, 11, 12, 23] as Array<Number>;
        for (var a = 0; a < anchors.size(); a++) {
            var anchor = anchors[a];
            for (var ago = 0; ago < HourBands.HOURS; ago++) {
                var sampleHour = (anchor + 24 - ago) % 24;
                var expected = (anchor + HourBands.HOURS - ago) %
                               HourBands.HOURS;
                Test.assertEqualMessage(
                    BodyBatteryData.blockForHour(sampleHour), expected,
                    ago + " hours before " + anchor +
                    " did not move counter-clockwise");
            }
        }
        return true;
    }

    //! Completed hours are averaged in raw units, while the current block is
    //! the newest value and may move down during the hour.
    (:test)
    function bodyBatteryAveragesPastHoursButKeepsCurrentLive(
            logger as Logger) as Boolean {
        BodyBatteryData.resetHistory();
        BodyBatteryData.anchorHour = 9;

        // 6% and 8% quantise to levels 0 and 1 separately. Their raw 7% mean
        // reaches level 1, proving quantisation happens after the average.
        BodyBatteryData.addPast(8, 6.0);
        BodyBatteryData.addPast(8, 8.0);
        BodyBatteryData.addPast(7, 0.0);
        // Anything accidentally accumulated for current must be ignored.
        BodyBatteryData.addPast(9, 95.0);
        BodyBatteryData.finishPast(9);

        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 8),
            HourBands.levelFromFraction(0.07),
            "past samples were not averaged before quantisation");
        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 7), 0,
            "a measured zero is known and empty");
        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 6), HourBands.UNKNOWN,
            "an hour with no samples must remain unknown");
        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 9), HourBands.UNKNOWN,
            "the current hour must not use its historical average");

        BodyBatteryData.currentKnown = true;
        BodyBatteryData.currentValue = 0.80;
        BodyBatteryData.writeCurrent();
        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 9), 12,
            "the current block must use the newest value");
        BodyBatteryData.currentValue = 0.20;
        BodyBatteryData.writeCurrent();
        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 9), 3,
            "the live current block must be able to drain");
        Test.assertEqualMessage(
            HourBands.levelAt(BodyBatteryData.levels[0],
                              BodyBatteryData.levels[1],
                              BodyBatteryData.known, 8),
            HourBands.levelFromFraction(0.07),
            "updating current disturbed the previous hour's average");

        Test.assertEqualMessage(BodyBatteryData.fraction(-5), 0.0,
            "Body Battery below zero must clamp");
        Test.assertEqualMessage(BodyBatteryData.fraction(105), 1.0,
            "Body Battery above 100 must clamp");
        BodyBatteryData.forget();
        logger.debug("past averaged, current live and replaceable");
        return true;
    }

    //! Every hour block leaves a dark gutter on **both** sides of it, so the
    //! hours stay countable rather than merging into one arc — and so the hour
    //! marks themselves sit in the middle of those gutters.
    //!
    //! Written against HOUR_BLOCK_DEGREES rather than against 22.5: widening
    //! the block to a full 30 is a legitimate design choice, and this must then
    //! say so rather than fail.
    (:test)
    function everyHourBlockLeavesADarkGutter(logger as Logger) as Boolean {
        var edges = tablesAt(0, HourBands.LEVELS);
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var tables = tablesAt(ring, HourBands.LEVELS);
            var gutter = 0;
            for (var i = DotGrid.ringStart[ring];
                    i < DotGrid.ringStart[ring + 1]; i++) {
                var position = DotGrid.positionOf[i];
                var dx = DotGrid.xs[i];
                var dy = DotGrid.ys[i];
                var lit = tables.lit(position, dx * dx + dy * dy);
                // Every block is at the top of the scale, so inside a block is
                // lit and outside one is not. Nothing else can decide it.
                Test.assertEqualMessage(lit, HourBands.insideBlock(position),
                    "ring " + ring + " dot " + i + " at " + position +
                    " disagrees with its own block test");
                if (!lit) {
                    gutter++;
                }
            }
            if (HourBands.FILL < 1.0) {
                Test.assertMessage(gutter > 0,
                    "ring " + ring + " left no gutter at all, so the hours " +
                    "cannot be counted");
                logger.debug("ring " + ring + ": " + gutter +
                             " dots in the gutters");
                // And the gutter straddles the hour mark rather than sitting
                // wholly on one side of it, which is what centring the block
                // means. Positions either side of a mark, both dark.
                for (var b = 0; b < HourBands.HOURS; b++) {
                    var mark = b.toFloat() / HourBands.HOURS;
                    var step = 0.0001;
                    Test.assertMessage(
                        !HourBands.insideBlock(mark + step),
                        "hour mark " + b + " must sit in a gutter, but the " +
                        "position just after it is inside a block");
                    var before = (b == 0) ? (1.0 - step) : (mark - step);
                    Test.assertMessage(!HourBands.insideBlock(before),
                        "hour mark " + b + " must sit in a gutter, but the " +
                        "position just before it is inside a block");
                }
            }
        }
        // Every table's spare thirteenth entry mirrors the first, or a
        // position that rounds to 12 reads someone else's forecast.
        Test.assertEqualMessage(edges.full[HourBands.HOURS], edges.full[0],
            "the spare block's full edge does not mirror the first");
        Test.assertEqualMessage(edges.part[HourBands.HOURS], edges.part[0],
            "the spare block's partial edge does not mirror the first");
        Test.assertEqualMessage(edges.lo[HourBands.HOURS], edges.lo[0],
            "the spare block's window does not mirror the first");
        Test.assertEqualMessage(edges.hi[HourBands.HOURS], edges.hi[0],
            "the spare block's window does not mirror the first");
        return true;
    }

    //! Each sub-band lights its own share of the ring, and the top of the
    //! scale lights every dot the blocks cover.
    (:test)
    function eachSubBandLightsItsShareOfTheRing(logger as Logger) as Boolean {
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var dry = tablesAt(ring, 0).litDots(ring);
            Test.assertEqualMessage(dry, 0,
                "a dry forecast must light nothing on ring " + ring);

            var previous = 0;
            for (var band = 1; band <= HourBands.BANDS; band++) {
                var lit = tablesAt(ring, band * HourBands.LEVELS_PER_BAND)
                    .litDots(ring);
                Test.assertMessage(lit > previous,
                    "ring " + ring + " band " + band + " lit " + lit +
                    " dots against band " + (band - 1) + "'s " + previous +
                    " — each sub-band must add to the one below it");
                previous = lit;
            }

            // The top of the scale is the whole block, edge to edge: no dead
            // rim inside the ring, which is why bandEdges() forces the
            // outermost edge to the ring's own rather than stacking three
            // steps. It is also the luminance argument — the widened scale
            // draws nothing the old top tier could not.
            var inside = 0;
            for (var i = DotGrid.ringStart[ring];
                    i < DotGrid.ringStart[ring + 1]; i++) {
                if (HourBands.insideBlock(DotGrid.positionOf[i])) {
                    inside++;
                }
            }
            Test.assertEqualMessage(previous, inside,
                "ring " + ring + ": the top level must light every dot its " +
                "blocks cover, but lit " + previous + " of " + inside);
            logger.debug("ring " + ring + ": " + inside + " dots under the " +
                         "blocks, of " + ringSize(ring));

            var unknown = tablesAt(ring, HourBands.UNKNOWN).litDots(ring);
            Test.assertEqualMessage(unknown, 0,
                "an unknown hour must light nothing on ring " + ring);
        }
        return true;
    }

    //! **The alignment, asserted.** A block sits centred in its hour slot.
    //!
    //! It did not used to. The block sat at the *leading* edge of its wedge,
    //! starting exactly on hour mark H with the whole 7.5-degree gutter bunched
    //! before mark H+1 — putting every block's centre 3.75 degrees anticlockwise
    //! of its slot's centre, about 12px of arc on the outer ring. That is small
    //! enough to survive every test the face had and large enough to be obvious
    //! on the wrist against the printed dial, which is exactly the kind of thing
    //! a measurement has to hold from now on.
    //!
    //! Written against the *symmetry* rather than against 3.75 degrees, so
    //! widening HOUR_BLOCK_DEGREES stays a free choice and this keeps meaning
    //! what it says.
    (:test)
    function everyBlockIsCentredInItsHourSlot(logger as Logger) as Boolean {
        // The definition: the lit arc answers the same either side of the
        // slot's midpoint, at every distance out to and past its edge.
        var wedge = 1.0 / HourBands.HOURS;
        for (var b = 0; b < HourBands.HOURS; b++) {
            var centre = (b + HourBands.BLOCK_CENTRE) * wedge;
            for (var step = 0; step <= 60; step++) {
                var out = (step * 0.008) * wedge;
                var before = centre - out;
                var after = centre + out;
                if (before < 0.0 || after >= 1.0) {
                    continue;
                }
                Test.assertEqualMessage(
                    HourBands.insideBlock(before),
                    HourBands.insideBlock(after),
                    "block " + b + " is lopsided " + out + " either side of " +
                    "its slot centre, so it does not sit between its hours");
            }
        }

        // BLOCK_CENTRE is the wedge's own centre, and that is not a coincidence
        // to be re-derived: LEAD is half of what FILL leaves over, so
        // LEAD + FILL/2 is half a wedge for any block width at all.
        Test.assertEqualMessage(HourBands.BLOCK_CENTRE, 0.5,
            "a centred block puts its middle at the middle of its wedge");
        Test.assertEqualMessage(
            HourBands.LEAD, 1.0 - HourBands.TRAIL,
            "the gutter must be split evenly, or the block is not centred");

        // And the dots agree with the definition: the lit arc's centre of mass
        // lands on the slot's midpoint rather than short of it.
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var tables = tablesAt(ring, HourBands.LEVELS);
            var sum = 0.0;
            var lit = 0;
            for (var i = DotGrid.ringStart[ring];
                    i < DotGrid.ringStart[ring + 1]; i++) {
                var position = DotGrid.positionOf[i];
                var dx = DotGrid.xs[i];
                var dy = DotGrid.ys[i];
                if (!tables.lit(position, dx * dx + dy * dy)) {
                    continue;
                }
                var at = position * HourBands.HOURS;
                sum += at - at.toNumber();
                lit++;
            }
            var centroid = sum / lit;
            var drift = (centroid - HourBands.BLOCK_CENTRE).abs();
            logger.debug("ring " + ring + ": lit centroid at " +
                         (centroid * HourBands.WEDGE_DEGREES) +
                         " degrees into a " + HourBands.WEDGE_DEGREES +
                         " degree slot, over " + lit + " dots");
            // A tenth of a degree. The lattice is not perfectly even round a
            // ring, so this cannot be exact — but the bug it replaces was
            // 3.75 degrees, nearly forty times this.
            Test.assertMessage(
                drift * HourBands.WEDGE_DEGREES < 0.1,
                "ring " + ring + "'s lit dots sit " +
                (drift * HourBands.WEDGE_DEGREES) +
                " degrees off the middle of their hour slots");
        }
        return true;
    }

    //! **The feature, asserted.** Every level above dry lights at least one dot
    //! in every block on every ring the source is offered on.
    //!
    //! The bottom of the scale is a window a fifth of one sub-band wide, and
    //! dots on a square lattice are not evenly spaced along a ring — so the
    //! failure this guards against is the whole point going quiet: a 10% hour
    //! that draws exactly nothing, which is indistinguishable from the dry
    //! hour the old four-step scale drew for it. On this lattice the geometry
    //! delivers it with no minimum window at all; if that ever stops being
    //! true, a floor sized off DotGrid.markerHalf is the fix rather than a
    //! coarser scale.
    (:test)
    function everyNonZeroLevelLightsAtLeastOneDot(logger as Logger) as Boolean {
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var worst = -1;
            for (var level = 1; level <= HourBands.LEVELS; level++) {
                var perBlock = tablesAt(ring, level).litPerBlock(ring);
                for (var b = 0; b < HourBands.HOURS; b++) {
                    Test.assertMessage(perBlock[b] > 0,
                        "ring " + ring + " block " + b + " at level " + level +
                        " lights nothing, so the bottom of the scale is " +
                        "invisible there");
                    if (worst < 0 || perBlock[b] < worst) {
                        worst = perBlock[b];
                    }
                }
            }
            logger.debug("ring " + ring + ": thinnest lit block holds " +
                         worst + " dots");
        }

        // The sibling invariant, and the one a minimum window would break: an
        // hour known and dry lights nothing at all. A scale whose floor leaked
        // a pip onto a dry hour would be worse than the one it replaced.
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var perBlock = tablesAt(ring, 0).litPerBlock(ring);
            for (var b = 0; b < HourBands.HOURS; b++) {
                Test.assertEqualMessage(perBlock[b], 0,
                    "ring " + ring + " block " + b + " lit a dot for a dry " +
                    "hour");
            }
        }
        return true;
    }

    //! More is never less: raising a level cannot unlight a dot in any block.
    //!
    //! The partial band grows out from the middle of its block while the full
    //! bands grow outward from the ring's inner edge, so the shape a level
    //! draws changes on two axes at once. Monotonic per *block* rather than in
    //! total, because a total can hide one block going backwards behind
    //! another going forwards — and a block is what a wearer reads.
    (:test)
    function aLevelIsMonotonicInDotsLit(logger as Logger) as Boolean {
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var previous = tablesAt(ring, 0).litPerBlock(ring);
            for (var level = 1; level <= HourBands.LEVELS; level++) {
                var current = tablesAt(ring, level).litPerBlock(ring);
                for (var b = 0; b < HourBands.HOURS; b++) {
                    Test.assertMessage(current[b] >= previous[b],
                        "ring " + ring + " block " + b + " fell from " +
                        previous[b] + " dots at level " + (level - 1) +
                        " to " + current[b] + " at level " + level);
                }
                previous = current;
            }
        }
        return true;
    }

    //! Why the forecast is offered on the outer two rings only.
    //!
    //! The restriction is a claim about the lattice, so it is asserted against
    //! the lattice rather than left in a comment: every block of every
    //! sub-band on a permitted ring holds at least MIN_BAND_DOTS dots, and the
    //! rings below the cut do not. If the lattice ever changes, this says
    //! whether Source.BLOCKS_TOP_RING still means what it claims to.
    (:test)
    function onlyTheOuterTwoRingsResolveTwelveHoursInThreeBands(
            logger as Logger) as Boolean {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var worst = -1;
            for (var band = 1; band <= HourBands.BANDS; band++) {
                // The dots this band adds over the one inside it.
                var inner = tablesAt(ring,
                    (band - 1) * HourBands.LEVELS_PER_BAND);
                var outer = tablesAt(ring, band * HourBands.LEVELS_PER_BAND);
                var perBlock = new [HourBands.HOURS] as Array<Number>;
                for (var b = 0; b < HourBands.HOURS; b++) {
                    perBlock[b] = 0;
                }
                for (var i = DotGrid.ringStart[ring];
                        i < DotGrid.ringStart[ring + 1]; i++) {
                    var position = DotGrid.positionOf[i];
                    var dx = DotGrid.xs[i];
                    var dy = DotGrid.ys[i];
                    var radiusSq = dx * dx + dy * dy;
                    if (outer.lit(position, radiusSq) &&
                            !inner.lit(position, radiusSq)) {
                        perBlock[HourBands.blockOf(position)]++;
                    }
                }
                for (var b = 0; b < HourBands.HOURS; b++) {
                    if (worst < 0 || perBlock[b] < worst) {
                        worst = perBlock[b];
                    }
                }
            }
            logger.debug("ring " + ring + ": worst sub-band holds " + worst +
                         " dots");
            if (ring <= Source.BLOCKS_TOP_RING) {
                Test.assertMessage(worst >= MIN_BAND_DOTS,
                    "ring " + ring + " is offered the forecast but its " +
                    "thinnest sub-band holds only " + worst + " dots");
            } else {
                Test.assertMessage(worst < MIN_BAND_DOTS,
                    "ring " + ring + " holds " + worst + " dots in its " +
                    "thinnest sub-band, so it could carry the forecast — " +
                    "Source.BLOCKS_TOP_RING is now costing a ring for nothing");

                // And what the widened scale adds to the same claim, on the
                // ring where it bites hardest: on the innermost ring sixteen
                // (block, level) pairs light no dot at all, so the scale would
                // not merely be cramped down there, part of it would be
                // invisible. Ring 2 draws every rung — its exclusion still
                // rests on the sub-band measurement above and on nothing else,
                // which is worth knowing before anyone relaxes the cut.
                var blind = 0;
                for (var level = 1; level <= HourBands.LEVELS; level++) {
                    var perBlock = tablesAt(ring, level).litPerBlock(ring);
                    for (var b = 0; b < HourBands.HOURS; b++) {
                        if (perBlock[b] == 0) {
                            blind++;
                        }
                    }
                }
                logger.debug("ring " + ring + ": " + blind +
                             " (block, level) pairs light nothing");
                if (ring == StatMap.RINGS - 1) {
                    Test.assertMessage(blind > 0,
                        "the innermost ring now draws every rung of the " +
                        "scale, so the sub-band measurement above is the " +
                        "only thing keeping any ring out");
                }
            }
        }
        return true;
    }

    //! HourBands.litAt() is what MatrixRenderer inlines, so it has to agree
    //! with the parts it is assembled from — at the block edge, at the gutter
    //! edge, at every sub-band edge and at both sides of the partial band's
    //! window, which is where a copied comparison drifts. The direct analogue
    //! of litTestsAgreeAtTheBoundaries.
    (:test)
    function theHourlyLitTestAgreesWithTheRenderer(logger as Logger)
            as Boolean {
        var levels = new [HourBands.HOURS] as Array<Number>;
        for (var b = 0; b < HourBands.HOURS; b++) {
            levels[b] = b % (HourBands.LEVELS + 1);
        }
        var ring = 0;
        var tables = new BlockTables(ring, levels);
        var probes = 0;
        for (var b = 0; b < HourBands.HOURS; b++) {
            var base = b.toFloat() / HourBands.HOURS;
            // Straddling every edge that decides an answer: the block's two
            // ends, the gutter, and — the new ones — both sides of the window
            // the partial band is drawn through.
            var wedge = 1.0 / HourBands.HOURS;
            var offsets = [
                0.0, 0.0001,
                (HourBands.LEAD - 0.0001) * wedge,
                HourBands.LEAD * wedge,
                (HourBands.LEAD + 0.0001) * wedge,
                (tables.lo[b] - 0.0001) * wedge, (tables.lo[b] + 0.0001) * wedge,
                HourBands.BLOCK_CENTRE * wedge,
                (tables.hi[b] - 0.0001) * wedge, (tables.hi[b] + 0.0001) * wedge,
                (HourBands.TRAIL - 0.0001) * wedge,
                HourBands.TRAIL * wedge,
                (HourBands.TRAIL + 0.0001) * wedge,
                0.9999 * wedge] as Array<Float>;
            for (var o = 0; o < offsets.size(); o++) {
                var position = base + offsets[o];
                if (position >= 1.0 || position < base) {
                    continue;
                }
                Test.assertEqualMessage(HourBands.blockOf(position), b,
                    "position " + position + " left its own block");
                var into = position * HourBands.HOURS - b;
                for (var band = 0; band < HourBands.BANDS; band++) {
                    var edge = DotGrid.bandEdge[ring * HourBands.BANDS + band];
                    var inside = HourBands.insideBlock(position) &&
                        (edge <= tables.full[b] ||
                         (edge <= tables.part[b] && into > tables.lo[b] &&
                          into < tables.hi[b]));
                    Test.assertEqualMessage(
                        tables.lit(position, edge), inside,
                        "litAt disagrees with its own parts at block " + b +
                        " band " + band + ", position " + position);
                    probes++;
                }
            }
        }
        logger.debug(probes + " boundary probes agree");
        return true;
    }

    //! An hourly frame cannot outshine a ring filled end to end.
    //!
    //! Its dots take one of exactly three colours: the band, which is what a
    //! full ring draws everywhere; the unfilled tier, which is what an empty
    //! one draws; and the unknown tier, which is darker than both. So the
    //! frame is bounded above by everySpan(0.0, 1.0), which the budget tests
    //! already measure — and this is what lets frameLuminance's two-tier model
    //! stand unchanged rather than needing a third slot.
    (:test)
    function theHourlyRingCannotOutshineAFullOne(logger as Logger) as Boolean {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var weak = relativeLuminance(Palette.active[ring * 2]);
            var band = relativeLuminance(Palette.active[ring * 2 + 1]);
            var dim = relativeLuminance(Palette.dimOf[ring]);
            Test.assertMessage(dim < weak,
                "ring " + ring + ": the unknown tier must be darker than " +
                "the unfilled one, or an unforecast hour costs luminance");
            Test.assertMessage(weak < band,
                "ring " + ring + ": the unfilled tier must be darker than " +
                "the band");
        }
        // And the gutters are never lit, so even at the top of the scale a
        // block ring lights strictly fewer dots than a full one.
        for (var ring = 0; ring <= Source.BLOCKS_TOP_RING; ring++) {
            var lit = tablesAt(ring, HourBands.LEVELS).litDots(ring);
            if (HourBands.FILL < 1.0) {
                Test.assertMessage(lit < ringSize(ring),
                    "ring " + ring + " lit all " + lit + " of its dots, so " +
                    "the gutter has gone");
            }
            logger.debug("ring " + ring + " worst case: " + lit + " of " +
                         ringSize(ring) + " lit");
        }
        return true;
    }

    //! A forecast change has to reach the gate, or the ring never redraws.
    //!
    //! This is the one test that fails if the two words are left out of the
    //! ring print — and the symptom it guards against is silence: an hourly
    //! ring whose span, mark and over flag never move is a ring the gate is
    //! certain has nothing to say.
    (:test)
    function aChangedHourlyMaskForcesARedraw(logger as Logger) as Boolean {
        var view = new CrossoverView();
        var spans = everySpan(0.0, 0.0);
        var marks = noMarks();
        var overs = noOvers();

        var dry = copyOf(view.ringPrint(spans, marks, overs,
                                        blocksFor(0, everyBlockAt(0))));
        var wet = copyOf(view.ringPrint(spans, marks, overs,
                                        blocksFor(0, everyBlockAt(2))));
        Test.assertMessage(!FrameGate.same(dry, wet),
            "the forecast changed and the ring print did not");
        Test.assertMessage(FrameGate.ringMoved(dry, wet, 0),
            "ring 0's own slice must be what moved");
        for (var ring = 1; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(!FrameGate.ringMoved(dry, wet, ring),
                "only ring 0 carried the forecast, so ring " + ring +
                " must not have moved");
        }

        // An hour going from dry to unknown is also a change, and the one a
        // print of levels alone would miss: the levels word is 0 either way.
        var unknown = copyOf(view.ringPrint(spans, marks, overs,
            blocksFor(0, everyBlockAt(HourBands.UNKNOWN))));
        Test.assertMessage(FrameGate.ringMoved(dry, unknown, 0),
            "dry and unknown share a levels word, so the known word is the " +
            "only thing that can tell the gate they differ");

        // And a change confined to the *high* levels word, which is the half
        // of the print that only exists because a level is four bits. A print
        // carrying one word would call this ring unchanged.
        var lateLevels = everyBlockAt(0);
        lateLevels[HourBands.HOURS - 1] = HourBands.LEVELS;
        var late = copyOf(view.ringPrint(spans, marks, overs,
                                         blocksFor(0, lateLevels)));
        Test.assertMessage(FrameGate.ringMoved(dry, late, 0),
            "a change in the last block lives in the high levels word alone, " +
            "and the gate must still see it");
        return true;
    }

    //! Held back in always-on, the forecast shows nothing — and the trap is
    //! that the obvious way to say so shows everything.
    //!
    //! All zeroes means every hour *unknown*, which draws the dim tier right
    //! round the ring. That is data, in the one mode whose whole purpose is to
    //! carry none. Known-and-dry is the reading that draws a plain field.
    (:test)
    function heldBackAlwaysOnShowsNoHourlyBands(logger as Logger) as Boolean {
        var held = StatMap.noBlocks();
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var lo = held[ring * StatMap.BLOCK_VALUES];
            var hi = held[ring * StatMap.BLOCK_VALUES + 1];
            var known = held[ring * StatMap.BLOCK_VALUES + 2];
            Test.assertEqualMessage(lo, 0,
                "held back, no hour may be lit on ring " + ring);
            Test.assertEqualMessage(hi, 0,
                "held back, no hour may be lit on ring " + ring);
            Test.assertEqualMessage(known, HourBands.ALL_KNOWN,
                "held back, every hour must read as known — all zeroes here " +
                "would draw the unknown tier right round the ring");
            for (var b = 0; b < HourBands.HOURS; b++) {
                Test.assertEqualMessage(HourBands.levelAt(lo, hi, known, b), 0,
                    "held back, block " + b + " must read as empty rather than " +
                    "unknown");
            }
        }
        Test.assertEqualMessage(tablesAt(0, 0).litDots(0), 0,
            "the held-back field must light nothing at all");
        return true;
    }

    //! An hourly ring is always repainted in full — it opts out of the delta,
    //! and that is a decision rather than an accident.
    //!
    //! The complement of aMovedSpanRepaintsOnlyItsEdge. A delta would have to
    //! evaluate a second block index, table lookup and radius test per dot,
    //! every frame the ring is walked, to save draws on a once-an-hour event.
    (:test)
    function theHourlyRingIsAlwaysRepaintedInFull(logger as Logger) as Boolean {
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var saved = StatMap.rings[0];
        StatMap.rings[0] = Source.SOURCE_RAIN_HOURS;

        var spans = everySpan(0.0, 0.0);
        var marks = noMarks();
        var overs = noOvers();
        var hours = blocksFor(0, everyBlockAt(2));

        // Two cleared draws first, so a delta would be eligible by now on any
        // ordinary source.
        for (var i = 0; i < 2; i++) {
            MatrixRenderer.draw(dc, spans, marks, overs, hours, Palette.active,
                                Palette.rampActive, null,
                                FrameGate.everything(), true);
        }
        // Nothing has changed at all, which is the strongest case for a delta.
        MatrixRenderer.draw(dc, spans, marks, overs, hours, Palette.active,
                            Palette.rampActive, null, onlyRingDirty(0), false);
        logger.debug("hourly repaint: " + MatrixRenderer.painted + " of " +
                     ringSize(0));
        Test.assertEqualMessage(MatrixRenderer.painted, ringSize(0),
            "an hourly ring must be repainted whole, but drew " +
            MatrixRenderer.painted + " of " + ringSize(0));

        StatMap.rings[0] = saved;
        Config.reload();
        return true;
    }

    //! Switching a ring into or out of the forecast repaints it twice.
    //!
    //! Both directions, because only one of them is obvious. Into the forecast
    //! is safe by accident — the hourly loop paints everything anyway. **Out**
    //! of it is the dangerous one: the buffers hold blocks, gutters and dim
    //! dots while the remembered spans describe the EMPTY span an hourly ring
    //! reports, so a delta would skip every dot that is unlit under both and
    //! leave the old forecast standing. The palette is keyed by ring rather
    //! than by source, so nothing else in the delta's key moves.
    (:test)
    function switchingARingToTheForecastRepaintsItTwice(logger as Logger)
            as Boolean {
        var dc = probeDc(logger);
        if (dc == null) {
            return true;
        }
        var saved = StatMap.rings[0];
        var marks = noMarks();
        var overs = noOvers();
        var hours = blocksFor(0, everyBlockAt(2));
        var spans = everySpan(0.0, 0.5);

        // An ordinary source, settled into both buffers so a delta is live.
        StatMap.rings[0] = Source.SOURCE_BATTERY;
        settleBuffers(dc, spans, overs, null);
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(0), false);
        Test.assertMessage(MatrixRenderer.painted < ringSize(0),
            "the ordinary source must be deltaing by now, or this test " +
            "cannot show that switching stops it");

        // Into the forecast.
        StatMap.rings[0] = Source.SOURCE_RAIN_HOURS;
        MatrixRenderer.draw(dc, spans, marks, overs, hours, Palette.active,
                            Palette.rampActive, null, onlyRingDirty(0), false);
        Test.assertEqualMessage(MatrixRenderer.painted, ringSize(0),
            "switching into the forecast must repaint the ring whole");
        MatrixRenderer.draw(dc, spans, marks, overs, hours, Palette.active,
                            Palette.rampActive, null, onlyRingDirty(0), false);
        Test.assertEqualMessage(MatrixRenderer.painted, ringSize(0),
            "and again, so both buffers hold the forecast");

        // Back out of it. This is the direction that would rot.
        StatMap.rings[0] = Source.SOURCE_BATTERY;
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(0), false);
        Test.assertEqualMessage(MatrixRenderer.painted, ringSize(0),
            "leaving the forecast must repaint the ring whole, or the old " +
            "blocks stay in a buffer");
        MatrixRenderer.draw(dc, spans, marks, overs, emptyBlocks(), Palette.active,
                            Palette.rampActive, null, onlyRingDirty(0), false);
        Test.assertEqualMessage(MatrixRenderer.painted, ringSize(0),
            "and again, because both buffers held the forecast");

        StatMap.rings[0] = saved;
        Config.reload();
        return true;
    }

    //! The picker offers every block source on the outer two rings only, and
    //! its labels and values stay in step.
    (:test)
    function blockSourcesAreOnlyOfferedOnTheOuterTwoRings(logger as Logger)
            as Boolean {
        var blockSources = [Source.SOURCE_RAIN_HOURS,
                            Source.SOURCE_UV_HOURS,
                            Source.SOURCE_BODY_BATTERY_HOURS] as Array<Number>;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var offered = Source.offeredFor(ring);
            var labels = offeredLabelsFor(ring);
            Test.assertEqualMessage(labels.size(), offered.size(),
                "ring " + ring + "'s picker labels and values disagree, so " +
                "it would store the wrong source with no symptom");

            var carried = 0;
            for (var i = 0; i < offered.size(); i++) {
                Test.assertMessage(offered[i] >= 0 &&
                                   offered[i] < Source.COUNT,
                    "every offered source must be a real one");
                Test.assertMessage(offered[i] != Source.SOURCE_RETIRED,
                    "the picker must never offer the retired source");
                if (Source.usesBlocks(offered[i])) {
                    carried++;
                }
            }
            var expected = (ring <= Source.BLOCKS_TOP_RING)
                ? blockSources.size() : 0;
            Test.assertEqualMessage(carried, expected,
                "ring " + ring + " carries " + carried + " block sources, " +
                "expected " + expected);

            // Nothing else is filtered, so the two lists differ by exactly the
            // number of block sources on an inner ring.
            Test.assertEqualMessage(offered.size(),
                Source.OFFERED.size() -
                    ((ring <= Source.BLOCKS_TOP_RING) ? 0
                                                     : blockSources.size()),
                "ring " + ring + "'s picker lost something other than the " +
                "block sources");
        }
        return true;
    }

    //! A stored setting pointing any block source at an inner ring reads as Off.
    //!
    //! The same answer the retired slot gets, and for the same reason: the
    //! ring has nothing it can draw, and saying so is better than a band the
    //! menu cannot name. Falling back to the ring's default instead would
    //! quietly resurrect a source the wearer never chose.
    (:test)
    function aStoredBlockSourceOnAnInnerRingReadsAsOff(logger as Logger)
            as Boolean {
        var saved = new [StatMap.RINGS] as Array<Number>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            saved[i] = StatMap.rings[i];
        }

        var blockSources = [Source.SOURCE_RAIN_HOURS,
                            Source.SOURCE_UV_HOURS,
                            Source.SOURCE_BODY_BATTERY_HOURS] as Array<Number>;
        for (var s = 0; s < blockSources.size(); s++) {
            var source = blockSources[s];
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                Properties.setValue(StatMap.PROPERTY_RINGS[ring], source);
            }
            Config.reload();
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                var expected = (ring <= Source.BLOCKS_TOP_RING)
                    ? source : Source.SOURCE_OFF;
                Test.assertEqualMessage(StatMap.rings[ring], expected,
                    "ring " + ring + " stored as block source " + source +
                    " read back as " + StatMap.rings[ring]);
            }
        }

        for (var i = 0; i < StatMap.RINGS; i++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[i], saved[i]);
        }
        Config.reload();
        for (var i = 0; i < StatMap.RINGS; i++) {
            Test.assertEqualMessage(StatMap.rings[i], saved[i],
                "the test must leave the rings as it found them");
        }
        return true;
    }
}
