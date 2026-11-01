import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

//! Tests for the time ring: the outermost ring of a watch with no hands, the
//! hour filling its inner sub-band and the minute its outer two. Kept out of
//! MatrixTest, whose shared helpers it borrows rather than copies.
module TimeRingTest {

    //! Lit dots on ring 0 at 10:29, and how many of those are the hour's, as
    //! tools/mockup.py counts them (`time_colour`), keyed by the lattice's
    //! column count. The two implementations are written separately; this is
    //! what stops them drifting.
    //!
    //! **10:29 because no dot sits near either end.** `positionOf` is
    //! `Angle`'s approximation and the mockup's is exact `atan2`, so a dot
    //! within `Angle.MAX_TURN_ERROR` of an end can land either side of it.
    //! 10:09 had one 0.00025 of a turn from an end and failed on two screens;
    //! every ring-0 dot clears 10:29's ends by 0.0013 on all three lattices.
    const MOCKUP_HOUR = 10;
    const MOCKUP_MINUTE = 29;
    const MOCKUP_COLS = [38, 40, 42] as Array<Number>;
    const MOCKUP_LIT = [261, 299, 336] as Array<Number>;
    const MOCKUP_HOUR_LIT = [115, 129, 150] as Array<Number>;

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

    //! A watch with no hands always tells the time on its outer ring, whatever
    //! that ring stores — including the Steps a watch that wore this face
    //! before will have saved. A watch with hands never does, and a stored
    //! time, which no menu can write, reads as Off on any ring.
    (:test)
    function aHandsFreeWatchAlwaysTellsTheTime(logger as Logger) as Boolean {
        var stored = [Source.SOURCE_STEPS, Source.SOURCE_OFF,
                      Source.SOURCE_RAIN_HOURS] as Array<Number>;
        for (var k = 0; k < stored.size(); k++) {
            Properties.setValue(StatMap.PROPERTY_RINGS[0], stored[k]);
            Config.reload();
            var expected = HandStyle.TIME_RING ? Source.SOURCE_TIME : stored[k];
            Test.assertEqualMessage(StatMap.rings[StatMap.TIME_RING], expected,
                "ring 1 stored as " + stored[k] + " loaded as " +
                StatMap.rings[0]);
        }
        Properties.setValue(StatMap.PROPERTY_RINGS[2], Source.SOURCE_TIME);
        Config.reload();
        Test.assertEqualMessage(StatMap.rings[2], Source.SOURCE_OFF,
            "a stored time is not a choice anyone made and must read as Off");
        for (var i = 0; i < Source.OFFERED.size(); i++) {
            Test.assertMessage(!Source.isTime(Source.OFFERED[i]),
                "the time is placed by the watch and must never be offered");
        }
        Properties.setValue(StatMap.PROPERTY_RINGS[0], Source.SOURCE_STEPS);
        Properties.setValue(StatMap.PROPERTY_RINGS[2], Source.SOURCE_BATTERY);
        Config.reload();
        return true;
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
        StatMap.rings[0] = Source.SOURCE_TIME;
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
        logger.debug("time ring repaint: " + MatrixRenderer.painted + " of " +
                     whole + ", recorded " + MatrixRenderer.recorded + " of " +
                     mine + " numeral dots");
        Test.assertEqualMessage(MatrixRenderer.painted, whole,
            "a minute's move must repaint the time ring whole");
        Test.assertEqualMessage(MatrixRenderer.recorded, mine,
            "the time ring must record every numeral dot it carries");

        DateGlyph.active = false;
        StatMap.rings[0] = saved;
        Config.reload();
        return true;
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
    //! time: the ring all white at 11:59-and-a-bit, every other ring full.
    (:test)
    function theTimeRingFitsTheAlwaysOnBudget(logger as Logger) as Boolean {
        DotGrid.ensureBuilt();
        for (var t = 0; t < StatMap.THEME_IDS.size(); t++) {
            Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_IDS[t]);
            Config.reload();
            var total = 0.0;
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                var colour = (ring == 0) ? Palette.TIME_LIT
                                         : Palette.alwaysOn[ring * 2 + 1];
                var each = MatrixTest.relativeLuminance(colour) *
                           MatrixTest.LIT_PIXELS_PER_DOT;
                total += each * MatrixTest.ringSize(ring);
            }
            var worst = total / (Math.PI * DotGrid.RADIUS * DotGrid.RADIUS);
            logger.debug("theme " + StatMap.THEME_IDS[t] +
                         " worst always-on with the time: " + worst);
            Test.assertMessage(worst < MatrixTest.BUDGET,
                "theme " + StatMap.THEME_IDS[t] + " with the time ring full " +
                "exceeds the always-on budget: " + worst);
        }
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        Config.reload();
        return true;
    }
}
