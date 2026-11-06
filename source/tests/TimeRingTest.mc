import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

//! Tests for the time ring: the outermost ring of a watch with no hands, the
//! hour filling its inner sub-band and the minute its outer two. Kept out of
//! MatrixTest, whose shared helpers it borrows rather than copies.
(:test)
module TimeRingTest {

    //! Lit dots on ring 0 at 10:27, and how many of those are the hour's, as
    //! tools/mockup.py counts them (`time_colour`), keyed by the lattice's
    //! column count, on the watches that carry a time ring — so 38 columns is
    //! the 42mm Epix, whose rings are measured from the centre. The two
    //! implementations are written separately; this is what stops them
    //! drifting.
    //!
    //! **10:27 because no dot sits near either end.** `positionOf` is
    //! `Angle`'s approximation and the mockup's is exact `atan2`, so a dot
    //! within `Angle.MAX_TURN_ERROR` of an end can land either side of it.
    //! 10:09 had one 0.00025 of a turn from an end; so did 10:29 once the
    //! rings were measured from the centre. Every ring-0 dot clears 10:27's
    //! and 4:27's ends by 0.0012 on all three lattices.
    const MOCKUP_HOUR = 10;
    const MOCKUP_MINUTE = 27;
    const MOCKUP_COLS = [38, 40, 42] as Array<Number>;
    const MOCKUP_LIT = [280, 323, 301] as Array<Number>;
    const MOCKUP_HOUR_LIT = [129, 150, 143] as Array<Number>;

    //! The overlapping style on ring 0, as tools/mockup.py counts it: dots in
    //! each slot at 10:27, where the hour is ahead, and at 4:27, where the
    //! minute is. Per row: hour-only, minute-only, both, neither.
    const OVERLAP_AHEAD_HOUR = [205, 0, 217, 62,
                                235, 0, 250, 71,
                                217, 0, 233, 66] as Array<Number>;
    const OVERLAP_AHEAD_MINUTE = [0, 37, 180, 267,
                                  0, 43, 207, 306,
                                  0, 41, 192, 283] as Array<Number>;

    function fractions(hour as Number, minute as Number) as Array<Float> {
        var out = [0.0, 0.0] as Array<Float>;
        ClockData.timeFractions(hour, minute, out);
        return out;
    }

    function near(a as Float, b as Float) as Boolean {
        return (a - b).abs() < 0.0001;
    }

    //! The two ends read like hands: the minute empty on the hour and a
    //! quarter at :15, the hour moving on with the minutes rather than jumping,
    //! and a 24-hour clock folded onto the twelve-hour dial.
    (:test)
    function theTimeReadsLikeHands(logger as Logger) as Boolean {
        var noon = fractions(12, 0);
        Test.assertMessage(near(noon[0], 0.0) && near(noon[1], 0.0),
            "twelve o'clock must leave both halves empty");
        var quarter = fractions(3, 15);
        Test.assertMessage(near(quarter[1], 0.25),
            "the minute at :15 must be a quarter, not " + quarter[1]);
        Test.assertMessage(near(quarter[0], (3 + 0.25) / 12.0),
            "the hour at 3:15 must sit a quarter of the way to four, not " +
            quarter[0]);
        var evening = fractions(21, 45);
        Test.assertMessage(near(evening[0], (9 + 0.75) / 12.0),
            "21:45 must fold onto the dial as 9:45, not " + evening[0]);
        var late = fractions(23, 59);
        Test.assertMessage(late[0] < 1.0 && late[1] < 1.0,
            "11:59 must stay inside the ring: " + late[0] + ", " + late[1]);
        return true;
    }

    //! Between the two ends, the inner and outer sub-bands disagree — which is
    //! the whole reading. At 3:15 the hour is just past the minute, so a dot at
    //! 0.26 of the way round is lit inside and dark outside; at 12:40 the
    //! minute has run far ahead, so a dot at 0.3 is dark inside and lit
    //! outside.
    (:test)
    function theTimeRingSplitsHourInsideMinuteOutside(logger as Logger)
            as Boolean {
        DotGrid.ensureBuilt();
        var cases = [
            [3, 15, 0.255, 0.270, true],    // hour past minute: inside only
            [12, 40, 0.10, 0.60, false],    // minute past hour: outside only
            [9, 45, 0.76, 0.81, true]
        ] as Array<Array>;
        var split = DotGrid.bandEdge[0];
        for (var c = 0; c < cases.size(); c++) {
            var hour = cases[c][0] as Number;
            var minute = cases[c][1] as Number;
            var at = fractions(hour, minute);
            var lo = cases[c][2] as Float;
            var hi = cases[c][3] as Float;
            var insideLit = cases[c][4] as Boolean;
            var inner = 0;
            var outer = 0;
            for (var i = DotGrid.ringStart[0]; i < DotGrid.ringStart[1]; i++) {
                var position = DotGrid.positionOf[i];
                if (position <= lo || position >= hi) {
                    continue;
                }
                var dx = DotGrid.xs[i];
                var dy = DotGrid.ys[i];
                var isInner = (dx * dx + dy * dy <= split);
                var lit = TimeRing.isLit(0, dx, dy, position, at[0], at[1]);
                Test.assertEqualMessage(lit, isInner == insideLit,
                    "at " + hour + ":" + minute + " a dot at " +
                    position + (isInner ? " inside" : " outside") +
                    " drew wrong");
                if (isInner) { inner++; } else { outer++; }
            }
            logger.debug(hour + ":" + minute + " between the ends: " +
                         inner + " inner, " + outer + " outer");
            Test.assertMessage(inner > 0 && outer > 0,
                "no dot of one band falls between the ends, so this proves " +
                "nothing — widen the window");
        }
        return true;
    }

    //! The Monkey C and the mockup light the same dots at a pinned time.
    (:test)
    function theTimeRingMatchesTheMockup(logger as Logger) as Boolean {
        // Pinned on the watches that draw a time ring; the Crossover never
        // does, and its rings are measured from the hub, not the centre.
        if (!HandStyle.TIME_RING) {
            return true;
        }
        DotGrid.ensureBuilt();
        var at = fractions(MOCKUP_HOUR, MOCKUP_MINUTE);
        var split = DotGrid.bandEdge[0];
        var lit = 0;
        var hourLit = 0;
        for (var i = DotGrid.ringStart[0]; i < DotGrid.ringStart[1]; i++) {
            var dx = DotGrid.xs[i];
            var dy = DotGrid.ys[i];
            if (TimeRing.isLit(0, dx, dy, DotGrid.positionOf[i], at[0], at[1])) {
                lit++;
                if (dx * dx + dy * dy <= split) {
                    hourLit++;
                }
            }
        }
        var row = MOCKUP_COLS.indexOf(DotGrid.COLS);
        logger.debug(MOCKUP_HOUR.format("%d") + ":" + MOCKUP_MINUTE.format("%02d") +
                     " on " + DotGrid.COLS + " columns: " + lit +
                     " lit, " + hourLit + " of them the hour");
        Test.assertMessage(row >= 0,
            "no mockup pin for a " + DotGrid.COLS + "-column lattice");
        Test.assertEqualMessage(lit, MOCKUP_LIT[row],
            "the time ring has drifted from tools/mockup.py");
        Test.assertEqualMessage(hourLit, MOCKUP_HOUR_LIT[row],
            "the hour's half has drifted from tools/mockup.py");
        return true;
    }

    //! A watch with no hands always tells the time on its outer ring. A
    //! stored time style is kept — the ring's picker wrote it — and anything
    //! else, including the Steps a watch that wore this face before will have
    //! saved, takes the default style. A watch with hands never tells the time
    //! in a ring, and a stored time style reads as Off on any ring.
    (:test)
    function aHandsFreeWatchAlwaysTellsTheTime(logger as Logger) as Boolean {
        var stored = [Source.SOURCE_STEPS, Source.SOURCE_OFF,
                      Source.SOURCE_RAIN_HOURS, Source.SOURCE_TIME,
                      Source.SOURCE_TIME_OVERLAP, 99] as Array<Number>;
        for (var k = 0; k < stored.size(); k++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[0], stored[k]);
            Config.reload();
            var expected = stored[k];
            if (HandStyle.TIME_RING) {
                expected = Source.isTime(stored[k]) ? stored[k]
                                                    : Source.TIME_DEFAULT;
            } else if (Source.isTime(stored[k])) {
                expected = Source.SOURCE_OFF;
            } else if (stored[k] == 99) {
                expected = Source.SOURCE_STEPS;
            }
            Test.assertEqualMessage(StatMap.rings[StatMap.TIME_RING], expected,
                "ring 1 stored as " + stored[k] + " loaded as " +
                StatMap.rings[0]);
        }
        for (var k = 0; k < Source.TIME_STYLES.size(); k++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[2],
                                Source.TIME_STYLES[k]);
            Config.reload();
            Test.assertEqualMessage(StatMap.rings[2], Source.SOURCE_OFF,
                "a time style off the time ring must read as Off");
        }
        for (var i = 0; i < Source.OFFERED.size(); i++) {
            Test.assertMessage(!Source.isTime(Source.OFFERED[i]),
                "the time styles must never be in the general picker");
        }
        Properties.setValue(StatMap.PROPERTY_RINGS[0], Source.SOURCE_STEPS);
        Properties.setValue(StatMap.PROPERTY_RINGS[2], Source.SOURCE_BATTERY);
        Config.reload();
        Test.assertEqualMessage(Source.TIME_DEFAULT,
            Source.SOURCE_TIME_OVERLAP, "a hands-free watch starts overlapping");
        return true;
    }

    //! The time ring's picker offers the two styles and nothing else, so the
    //! face can be restyled but never left without the time — and no other
    //! ring's picker offers a style. On the Crossover no picker offers one.
    (:test)
    function onlyTheTimeRingOffersTheTimeStyles(logger as Logger) as Boolean {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var offered = Source.offeredFor(ring);
            var styles = 0;
            for (var i = 0; i < offered.size(); i++) {
                if (Source.isTime(offered[i])) {
                    styles++;
                }
            }
            var timeRing = HandStyle.TIME_RING && ring == StatMap.TIME_RING;
            Test.assertEqualMessage(styles,
                timeRing ? Source.TIME_STYLES.size() : 0,
                "ring " + ring + " offers " + styles + " time styles");
            if (timeRing) {
                Test.assertEqualMessage(offered.size(), styles,
                    "the time ring must offer nothing but the time styles");
                Test.assertEqualMessage(offeredLabelsFor(ring).size(), styles,
                    "the time ring's labels and values disagree");
            }
        }
        return true;
    }

    //! Overlapping, each fill covers the whole thickness: the slot a dot is in
    //! depends on its position alone, and the counts match the mockup.
    (:test)
    function theOverlapPaintsEachFillWholeAndTheirMeetingPurple(
            logger as Logger) as Boolean {
        // Pinned on the watches that draw a time ring; the Crossover never
        // does, and its rings are measured from the hub, not the centre.
        if (!HandStyle.TIME_RING) {
            return true;
        }
        DotGrid.ensureBuilt();
        var row = MOCKUP_COLS.indexOf(DotGrid.COLS);
        Test.assertMessage(row >= 0,
            "no mockup pin for a " + DotGrid.COLS + "-column lattice");
        var times = [[10, 27], [4, 27]] as Array<Array<Number> >;
        var pins = [OVERLAP_AHEAD_HOUR, OVERLAP_AHEAD_MINUTE]
                   as Array<Array<Number> >;
        for (var t = 0; t < times.size(); t++) {
            var at = fractions(times[t][0], times[t][1]);
            var counts = [0, 0, 0, 0] as Array<Number>;
            for (var i = DotGrid.ringStart[0]; i < DotGrid.ringStart[1]; i++) {
                var position = DotGrid.positionOf[i];
                var slot = TimeRing.slotOf(0, DotGrid.xs[i], DotGrid.ys[i],
                    position, at[0], at[1], Source.SOURCE_TIME_OVERLAP);
                var expected = TimeRing.NEITHER;
                if (position < at[0]) {
                    expected += TimeRing.HOUR;
                }
                if (position < at[1]) {
                    expected += TimeRing.MINUTE;
                }
                Test.assertEqualMessage(slot, expected,
                    "a dot at " + position + " is in the wrong slot at " +
                    times[t][0] + ":" + times[t][1] + " — radius must not " +
                    "matter when overlapping");
                counts[slot]++;
            }
            logger.debug(times[t][0] + ":" + times[t][1] + " overlapping on " +
                         DotGrid.COLS + " columns: hour " + counts[1] +
                         ", minute " + counts[2] + ", both " + counts[3] +
                         ", neither " + counts[0]);
            for (var k = 0; k < 4; k++) {
                // Pins are hour, minute, both, neither; slots are neither,
                // hour, minute, both.
                Test.assertEqualMessage(counts[(k + 1) % 4], pins[t][row * 4 + k],
                    "the overlapping ring has drifted from tools/mockup.py");
            }
        }
        return true;
    }

    //! The overlapping ring's hour and minute for each shipping theme, in
    //! StatMap.THEME_IDS order, as tools/mockup.py's hue_split() gives them:
    //! the outer ring's colour turned 60 degrees back and on in OKLCH.
    const SPLIT_PINS = [
        0x80ACFF, 0xFF8281,     // Terrain: orchid -> light blue, salmon
        0xD456DB, 0xB98C00,     // Activity: red -> magenta, mustard
        0x8BDBA0, 0xB1C3FF,     // Beacon: cyan -> mint, lavender
        0xD456DB, 0xB98C00      // Pulse: red -> magenta, mustard
    ] as Array<Number>;

    function near255(a as Number, b as Number) as Boolean {
        for (var shift = 0; shift <= 16; shift += 8) {
            if ((((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs() > 1) {
                return false;
            }
        }
        return true;
    }

    //! Overlapping, the ring's own theme colour is "both", and the hour and
    //! minute are its hue split either way — on every theme, matching the
    //! mockup to a unit per channel, distinct from each other and from both.
    (:test)
    function theOverlapTakesItsColoursFromTheTheme(logger as Logger)
            as Boolean {
        for (var t = 0; t < StatMap.THEME_IDS.size(); t++) {
            Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_IDS[t]);
            Config.reload();
            var colours = TimeRing.coloursFor(Source.SOURCE_TIME_OVERLAP, 0);
            var ring = Palette.themeColour(StatMap.TIME_RING);
            logger.debug("theme " + StatMap.THEME_IDS[t] + ": hour " +
                         colours[TimeRing.HOUR].format("%06X") + ", minute " +
                         colours[TimeRing.MINUTE].format("%06X") + ", both " +
                         colours[TimeRing.BOTH].format("%06X"));
            Test.assertEqualMessage(colours[TimeRing.BOTH], ring,
                "where both have passed must be the ring's own colour");
            Test.assertEqualMessage(colours[TimeRing.NEITHER],
                Palette.TIME_UNLIT, "unfilled must be the neutral grey");
            Test.assertMessage(near255(colours[TimeRing.HOUR], SPLIT_PINS[t * 2]),
                "the hour has drifted from tools/mockup.py");
            Test.assertMessage(
                near255(colours[TimeRing.MINUTE], SPLIT_PINS[t * 2 + 1]),
                "the minute has drifted from tools/mockup.py");
            Test.assertMessage(colours[TimeRing.HOUR] != colours[TimeRing.MINUTE] &&
                               colours[TimeRing.HOUR] != ring &&
                               colours[TimeRing.MINUTE] != ring,
                "hour, minute and both must be three colours");
        }
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }

    //! A grey has no hue to turn; the chroma floor still splits it into two
    //! colours rather than two greys.
    (:test)
    function aPaleRingStillSplitsIntoTwoColours(logger as Logger) as Boolean {
        var grey = 0x9AA8C0;
        var pair = HueSplit.pair(grey, Palette.TIME_SPLIT_DEGREES,
                                 Palette.TIME_SPLIT_CHROMA);
        logger.debug("pale " + grey.format("%06X") + " -> " +
                     pair[0].format("%06X") + ", " + pair[1].format("%06X"));
        Test.assertMessage(near255(pair[0], 0x65B7BC) && near255(pair[1], 0xBF97C6),
            "the pale split has drifted from tools/mockup.py");
        var flat = HueSplit.pair(0x808080, Palette.TIME_SPLIT_DEGREES,
                                 Palette.TIME_SPLIT_CHROMA);
        Test.assertMessage(near255(flat[0], 0xAB6E64) && near255(flat[1], 0x5D8E67),
            "even a pure grey must split into two colours, as the mockup does");
        return true;
    }

    //! Whichever colour either time style draws is brightest, on the theme in
    //! force.
    function brightestTimeColour() as Number {
        var overlap = Palette.timeOverlap;
        var all = [Palette.TIME_LIT, overlap[0], overlap[1], overlap[2],
                   overlap[3]] as Array<Number>;
        var best = all[0];
        for (var i = 1; i < all.size(); i++) {
            if (MatrixTest.relativeLuminance(all[i]) >
                    MatrixTest.relativeLuminance(best)) {
                best = all[i];
            }
        }
        return best;
    }

    //! Holding the fills back hides the data and keeps the time.
    (:test)
    function heldBackKeepsTheTime(logger as Logger) as Boolean {
        var saved = StatMap.rings[0];
        StatMap.rings[0] = Source.SOURCE_TIME;
        var spans = StatMap.noSpans();
        var now = Source.span(Source.SOURCE_TIME, false);
        Test.assertMessage(near(spans[0][0], now[0]) &&
                           near(spans[0][1], now[1]),
            "the held-back mode must keep the time, not blank it");
        for (var ring = 1; ring < StatMap.RINGS; ring++) {
            if (Source.isTime(StatMap.rings[ring])) {
                continue;
            }
            Test.assertEqualMessage(spans[ring][0], StatMap.NEVER_LIT[0],
                "ring " + ring + " is data and must still be held back");
        }
        StatMap.rings[0] = saved;
        Config.reload();
        return true;
    }

    //! The time ring is repainted whole whenever it is drawn, never by delta,
    //! and still records every numeral dot it carries.
    (:test)
    function theTimeRingIsAlwaysRepaintedInFull(logger as Logger) as Boolean {
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = MatrixTest.probeDc(logger);
        if (dc == null) {
            return true;
        }
        var saved = StatMap.rings[0];
        for (var s = 0; s < Source.TIME_STYLES.size(); s++) {
            repaintsInFull(logger, dc, Source.TIME_STYLES[s]);
        }
        StatMap.rings[0] = saved;
        Config.reload();
        return true;
    }

    function repaintsInFull(logger as Logger, dc as Graphics.Dc,
                            style as Number) as Void {
        StatMap.rings[0] = style;
        DateGlyph.ensure(MatrixTest.GLYPH_DAY);
        DateGlyph.active = true;

        var spans = MatrixTest.everySpan(0.0, 0.5);
        spans[0] = fractions(10, 9);
        var marks = MatrixTest.noMarks();
        var overs = MatrixTest.noOvers();
        var blocks = MatrixTest.emptyBlocks();
        for (var i = 0; i < 2; i++) {
            MatrixRenderer.draw(dc, spans, marks, overs, blocks, Palette.active,
                                Palette.rampActive, null,
                                FrameGate.everything(), true);
        }
        spans[0] = fractions(10, 10);
        MatrixRenderer.draw(dc, spans, marks, overs, blocks, Palette.active,
                            Palette.rampActive, null,
                            MatrixTest.onlyRingDirty(0), false);
        var whole = MatrixTest.ringSize(0);
        var mine = DateGlyph.firstFor[1] - DateGlyph.firstFor[0];
        logger.debug("style " + style + " repaint: " +
                     MatrixRenderer.painted + " of " +
                     whole + ", recorded " + MatrixRenderer.recorded + " of " +
                     mine + " numeral dots");
        Test.assertEqualMessage(MatrixRenderer.painted, whole,
            "a minute's move must repaint the time ring whole");
        Test.assertEqualMessage(MatrixRenderer.recorded, mine,
            "the time ring must record every numeral dot it carries");

        DateGlyph.active = false;
    }

    //! A minute's move dirties the time ring and nothing else.
    (:test)
    function aMinuteMovesOnlyTheTimeRingsPrint(logger as Logger) as Boolean {
        var view = new CrossoverView();
        var spans = MatrixTest.everySpan(0.0, 0.3);
        spans[0] = fractions(10, 9);
        var marks = MatrixTest.noMarks();
        var suns = MatrixTest.copyOf(MatrixRenderer.NO_SUNS);
        var before = MatrixTest.copyOf(view.ringPrint(spans, marks,
            MatrixTest.noOvers(), MatrixTest.emptyBlocks(), suns));
        spans[0] = fractions(10, 10);
        var after = MatrixTest.copyOf(view.ringPrint(spans, marks,
            MatrixTest.noOvers(), MatrixTest.emptyBlocks(), suns));
        Test.assertMessage(FrameGate.ringMoved(before, after, 0),
            "a minute must move the time ring's print");
        for (var ring = 1; ring < StatMap.RINGS; ring++) {
            Test.assertMessage(!FrameGate.ringMoved(before, after, ring),
                "ring " + ring + " does not carry the time and must not move");
        }
        return true;
    }

    //! Every theme stays under the always-on budget at its brightest with the
    //! time: the ring all in the brightest colour either style draws, its
    //! twelve hour marks in white, every other ring full. White at 11:59 is the split's worst; the overlap's
    //! every colour is darker, which `brightestTimeColour` makes the test
    //! rather than an assumption.
    (:test)
    function theTimeRingFitsTheAlwaysOnBudget(logger as Logger) as Boolean {
        DotGrid.ensureBuilt();
        for (var t = 0; t < StatMap.THEME_IDS.size(); t++) {
            Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_IDS[t]);
            Config.reload();
            var total = 0.0;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                var colour = (ring == 0) ? brightestTimeColour()
                                         : Palette.alwaysOn[ring * 2 + 1];
                var each = MatrixTest.relativeLuminance(colour) *
                           MatrixTest.LIT_PIXELS_PER_DOT;
                total += each * MatrixTest.ringSize(ring);
            }
            // The twelve hour marks, which draw in always-on too: each a
            // solid cell where a cross was, priced in white — brighter than
            // anything a mark is painted, the lifted current hour included.
            total += TimeRing.HOURS * MatrixTest.relativeLuminance(0xFFFFFF) *
                     (DotGrid.DOT * DotGrid.DOT - MatrixTest.LIT_PIXELS_PER_DOT);
            var worst = total / (Math.PI * DotGrid.RADIUS * DotGrid.RADIUS);
            logger.debug("theme " + StatMap.THEME_IDS[t] +
                         " worst always-on with the time and hour marks: " +
                         worst);
            Test.assertMessage(worst < MatrixTest.BUDGET,
                "theme " + StatMap.THEME_IDS[t] + " with the time ring full " +
                "exceeds the always-on budget: " + worst);
        }
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }

    // --- hour marks and the seconds dot -----------------------------------

    //! How far apart two positions are round the ring, the short way.
    function turnsApart(a as Float, b as Float) as Float {
        var d = (a - b).abs();
        return (d > 0.5) ? 1.0 - d : d;
    }

    function radiusSqOf(at as Number) as Number {
        return DotGrid.xs[at] * DotGrid.xs[at] + DotGrid.ys[at] * DotGrid.ys[at];
    }

    //! The ring's middle, squared: a mark on the outer edge sits beyond it and
    //! the seconds dot inside it.
    function middleSq(ring as Number) as Number {
        var outer = (ring == 0) ? DotGrid.RADIUS.toFloat()
                                : Math.sqrt(DotGrid.ringEdge[ring - 1]).toFloat();
        var middle = (outer + DotGrid.ringInner[ring]) / 2.0;
        return (middle * middle).toNumber();
    }

    function inRing(ring as Number, at as Number) as Boolean {
        return at >= DotGrid.ringStart[ring] && at < DotGrid.ringStart[ring + 1];
    }

    //! Twelve marks, one per hour, each a different dot of the time ring, on
    //! its outer half and within a lattice pitch of arc of its hour.
    (:test)
    function theHourMarksSitOnTheOuterEdge(logger as Logger) as Boolean {
        DotGrid.ensureBuilt();
        var ring = StatMap.TIME_RING;
        var dots = TimeRing.hourDotsFor(ring);
        Test.assertEqualMessage(dots.size(), TimeRing.HOURS, "twelve hour marks");
        var middle = middleSq(ring);
        for (var h = 0; h < TimeRing.HOURS; h++) {
            var at = dots[h];
            Test.assertMessage(at >= 0 && inRing(ring, at),
                "hour " + h + " has no dot on the time ring: " + at);
            Test.assertMessage(radiusSqOf(at) > middle,
                "hour " + h + "'s mark is not on the ring's outer half");
            var off = turnsApart(DotGrid.positionOf[at], h.toFloat() / TimeRing.HOURS);
            Test.assertMessage(off <= DotGrid.markerHalf[ring] + Angle.MAX_TURN_ERROR,
                "hour " + h + "'s mark is " + off + " of a turn from its hour");
            for (var k = 0; k < h; k++) {
                Test.assertMessage(dots[k] != at,
                    "hours " + k + " and " + h + " share a dot");
            }
        }
        return true;
    }

    //! For every second of the minute the dot sits on the time ring's inner
    //! half, near where a second hand would point — and never on an hour mark,
    //! which is what lets a tick repaint a plain cross and nothing else.
    (:test)
    function theSecondsDotNeverLandsOnAnHourMark(logger as Logger) as Boolean {
        DotGrid.ensureBuilt();
        var ring = StatMap.TIME_RING;
        var marks = TimeRing.hourDotsFor(ring);
        var middle = middleSq(ring);
        var last = -1;
        for (var second = 0; second < 60; second++) {
            var position = ClockData.secondFraction(second);
            var at = TimeRing.secondDotFor(ring, position);
            Test.assertMessage(at >= 0 && inRing(ring, at),
                "second " + second + " has no dot on the time ring");
            Test.assertMessage(radiusSqOf(at) < middle,
                "second " + second + "'s dot is not on the ring's inner half");
            var off = turnsApart(DotGrid.positionOf[at], position);
            Test.assertMessage(off <= DotGrid.markerHalf[ring] + Angle.MAX_TURN_ERROR,
                "second " + second + "'s dot is " + off + " of a turn away");
            Test.assertMessage(marks.indexOf(at) < 0,
                "second " + second + " lands on an hour mark");
            Test.assertMessage(at != last,
                "seconds " + (second - 1) + " and " + second + " share a dot");
            last = at;
        }
        Test.assertEqualMessage(TimeRing.secondDotFor(ring, Source.NO_MARKER), -1,
            "no second, no dot");
        return true;
    }

    //! The seconds dot is a position, like the minute: empty on the minute and
    //! a quarter at :15, never reaching 1.0.
    (:test)
    function theSecondReadsLikeAHand(logger as Logger) as Boolean {
        Test.assertMessage(near(ClockData.secondFraction(0), 0.0), "0 at :00");
        Test.assertMessage(near(ClockData.secondFraction(15), 0.25), "0.25 at :15");
        Test.assertMessage(ClockData.secondFraction(59) < 1.0, "below 1.0 at :59");
        Test.assertMessage(near(ClockData.secondFraction(60), 0.0),
            "a leap second folds back onto the dial");
        return true;
    }

    //! The current hour is the one the hour's fill last passed — on the hour
    //! itself too, where floating point puts 10/12 a hair short of ten.
    (:test)
    function theCurrentHourIsTheLastTheFillPassed(logger as Logger) as Boolean {
        var cases = [[10, 0, 10], [10, 59, 10], [11, 0, 11], [0, 0, 0],
                     [12, 0, 0], [23, 59, 11], [6, 30, 6]] as Array<Array<Number> >;
        for (var i = 0; i < cases.size(); i++) {
            var c = cases[i];
            var hour = TimeRing.currentHour(fractions(c[0], c[1])[0]);
            Test.assertEqualMessage(hour, c[2],
                c[0] + ":" + c[1] + " must light hour " + c[2] + "'s mark, not " + hour);
        }
        return true;
    }

    //! Only awake, only with the setting on, only on a watch with a time ring,
    //! and only in the time ring's own slot.
    (:test)
    function theSecondsDotIsAwakeOnly(logger as Logger) as Boolean {
        var saved = StatMap.seconds;
        Properties.setValue(StatMap.PROPERTY_SECONDS, StatMap.TIME_EXTRA_ON);
        Config.reload();
        var marks = MatrixTest.noMarks();
        StatMap.fillSecondMark(marks, false);
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(marks[ring], Source.NO_MARKER,
                "always-on must carry no seconds dot");
        }
        StatMap.fillSecondMark(marks, true);
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var expected = HandStyle.TIME_RING && ring == StatMap.TIME_RING;
            Test.assertEqualMessage(marks[ring] >= 0.0, expected,
                "ring " + ring + (expected ? " must" : " must not") +
                " carry the seconds dot awake");
        }
        Properties.setValue(StatMap.PROPERTY_SECONDS, StatMap.TIME_EXTRA_OFF);
        Config.reload();
        marks = MatrixTest.noMarks();
        StatMap.fillSecondMark(marks, true);
        Test.assertEqualMessage(marks[StatMap.TIME_RING], Source.NO_MARKER,
            "with the setting off there is no seconds dot");
        Properties.setValue(StatMap.PROPERTY_SECONDS, saved);
        Config.reload();
        return true;
    }

    //! A second that moves nothing else repaints one dot and rubs out one
    //! cell, not the ring — in both styles, with the hour marks on.
    (:test)
    function aSecondsTickRepaintsOneDot(logger as Logger) as Boolean {
        var saved = StatMap.hourMarks;
        Properties.setValue(StatMap.PROPERTY_HOUR_MARKS, StatMap.TIME_EXTRA_ON);
        Config.reload();
        DotGrid.ensureBuilt();
        var dc = MatrixTest.probeDc(logger);
        if (dc != null) {
            var style = StatMap.rings[0];
            for (var s = 0; s < Source.TIME_STYLES.size(); s++) {
                StatMap.rings[0] = Source.TIME_STYLES[s];
                ticksOneDot(logger, dc);
            }
            StatMap.rings[0] = style;
        }
        Properties.setValue(StatMap.PROPERTY_HOUR_MARKS, saved);
        Config.reload();
        return true;
    }

    function ticksOneDot(logger as Logger, dc as Graphics.Dc) as Void {
        DateGlyph.active = false;
        var spans = MatrixTest.everySpan(0.0, 0.5);
        spans[0] = fractions(10, 27);
        var marks = MatrixTest.noMarks();
        marks[0] = ClockData.secondFraction(14);
        var overs = MatrixTest.noOvers();
        var blocks = MatrixTest.emptyBlocks();
        MatrixRenderer.draw(dc, spans, marks, overs, blocks, Palette.active,
                            Palette.rampActive, null, FrameGate.everything(), true);
        marks[0] = ClockData.secondFraction(15);
        MatrixRenderer.draw(dc, spans, marks, overs, blocks, Palette.active,
                            Palette.rampActive, null,
                            MatrixTest.onlyRingDirty(0), false);
        logger.debug("style " + StatMap.rings[0] + " tick: painted " +
                     MatrixRenderer.painted + ", erased " + MatrixRenderer.erased);
        Test.assertEqualMessage(MatrixRenderer.painted, 1,
            "a seconds tick must repaint the one dot the second left");
        Test.assertEqualMessage(MatrixRenderer.erased, 1,
            "a seconds tick must rub out the one cell the second left");

        // And a minute is still the whole ring, seconds dot or not.
        spans[0] = fractions(10, 28);
        marks[0] = ClockData.secondFraction(0);
        MatrixRenderer.draw(dc, spans, marks, overs, blocks, Palette.active,
                            Palette.rampActive, null,
                            MatrixTest.onlyRingDirty(0), false);
        Test.assertEqualMessage(MatrixRenderer.painted, MatrixTest.ringSize(0),
            "a minute must still repaint the time ring whole");
    }

    //! The two rows exist exactly where the time ring does, and each opens on
    //! the value in use.
    (:test)
    function theTimeRingRowsAreOnlyWhereThereIsATimeRing(logger as Logger)
            as Boolean {
        var menu = new SettingsMenu();
        var ids = [:hourMarks, :seconds] as Array<Symbol>;
        for (var i = 0; i < ids.size(); i++) {
            var row = menu.findItemById(ids[i]);
            Test.assertEqualMessage(row >= 0, HandStyle.TIME_RING,
                "row " + i + (HandStyle.TIME_RING ? " is missing" :
                              " must not exist on a watch with hands"));
        }
        Test.assertEqualMessage(EXTRA_LABELS.size(), StatMap.TIME_EXTRA_ON + 1,
            "every extra value needs a label");
        return true;
    }
}
