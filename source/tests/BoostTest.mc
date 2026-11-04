import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

//! The always-on boost: always-on drawn from a lighter copy of the theme, to
//! make up for the watch turning its screen down there. Off leaves every table
//! exactly as it was; on, every always-on table lightens and the awake ones do
//! not move.
module BoostTest {

    //! tools/mockup.py's lighten() at Bright and Brightest, each shipping
    //! theme's five colours in THEME_IDS order — Bright's five, then
    //! Brightest's. The web configurator's boost.test.ts holds the same table.
    const LIGHTEN_PINS = [
        0xF4AAFF, 0xCBEA61, 0xB0E3FF, 0xFFA699, 0xFDCB56,   // Terrain
        0xFAD2FF, 0xDCFB73, 0xD6F0FF, 0xFFD1CA, 0xFFE4AB,
        0xFF968D, 0x8AE36D, 0x7DB9FF, 0xFFB951, 0xB2ACFF,   // Activity
        0xFFC9C3, 0xA2FD86, 0xBBDAFF, 0xFFDBAC, 0xD4D3FF,
        0x86EBFF, 0xFF968D, 0xB2ACFF, 0xFFB951, 0xCBEA61,   // Beacon
        0xC3F5FF, 0xFFC9C3, 0xD4D3FF, 0xFFDBAC, 0xDCFB73,
        0xFF968D, 0x52F0DC, 0xF4AAFF, 0xCBEA61, 0xB0E3FF,   // Pulse
        0xFFC9C3, 0x92FFEE, 0xFAD2FF, 0xDCFB73, 0xD6F0FF
    ] as Array<Number>;

    function setBoost(level as Number) as Void {
        Properties.setValue(StatMap.PROPERTY_BOOST, level);
        Config.reload();
    }

    //! Back to what every other test expects: Terrain, no boost, awake tables.
    function reset() as Void {
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_TERRAIN);
        setBoost(StatMap.BOOST_OFF);
        Palette.useMode(false);
    }

    function near255(a as Number, b as Number) as Boolean {
        for (var shift = 0; shift <= 16; shift += 8) {
            if ((((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs() > 1) {
                return false;
            }
        }
        return true;
    }

    function sameNumbers(a as Array<Number>, b as Array<Number>) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    (:test)
    function boostSettingIsClamped(logger as Logger) as Boolean {
        setBoost(99);
        Test.assertEqualMessage(StatMap.boost, StatMap.BOOST_OFF,
            "an out-of-range boost must fall back to Off");
        setBoost(StatMap.BOOST_BRIGHTEST);
        Test.assertEqualMessage(StatMap.boost, StatMap.BOOST_BRIGHTEST,
            "a valid boost must be honoured");
        reset();
        return true;
    }

    //! Off is what every watch had before the setting: the same filled colours
    //! awake and asleep, and one set of shared tables for both modes.
    (:test)
    function offLeavesEveryTableAsItWas(logger as Logger) as Boolean {
        reset();
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(Palette.alwaysOn[ring * 2 + 1],
                Palette.active[ring * 2 + 1], "filled colours must match between modes");
            Test.assertEqualMessage(Palette.alwaysOn[ring * 2],
                Palette.scale(Palette.themeColour(ring), Palette.WEAK_ALWAYS_ON),
                "the always-on unfilled tier must be the theme's at 0.45");
        }
        Test.assertMessage(Palette.dimAsleep == Palette.dimAwake &&
                           Palette.softAsleep == Palette.softAwake &&
                           Palette.sunAsleep == Palette.sunAwake &&
                           Palette.timeAsleep == Palette.timeAwake,
            "with the boost off both modes share one set of tables");
        Test.assertMessage(sameNumbers(Palette.rampAlwaysOn, Palette.rampActive),
            "with the boost off the ramp is the same in both modes");
        return true;
    }

    (:test)
    function lightenMatchesTheMockup(logger as Logger) as Boolean {
        for (var t = 0; t < StatMap.THEME_IDS.size(); t++) {
            for (var level = 1; level <= 2; level++) {
                for (var i = 0; i < Palette.THEME_COLOURS; i++) {
                    var colour = Palette.THEMES[t * Palette.THEME_COLOURS + i];
                    var got = HueSplit.lighten(colour, Palette.BOOST_AMOUNTS[level]);
                    var pin = LIGHTEN_PINS[(t * 2 + level - 1) * Palette.THEME_COLOURS + i];
                    Test.assertMessage(near255(got, pin),
                        "theme " + StatMap.THEME_IDS[t] + " colour " + i + " at " +
                        level + ": " + got.format("%06X") + ", mockup " +
                        pin.format("%06X"));
                }
            }
        }
        return true;
    }

    //! Lighter in OKLCH, never a different hue: the theme stays itself.
    (:test)
    function lightenRaisesLightnessAndKeepsTheHue(logger as Logger) as Boolean {
        for (var i = 0; i < Palette.THEMES.size(); i++) {
            var colour = Palette.THEMES[i];
            var before = HueSplit.toOklch(colour);
            var previous = before[0];
            for (var level = 1; level <= 2; level++) {
                var after = HueSplit.toOklch(
                    HueSplit.lighten(colour, Palette.BOOST_AMOUNTS[level]));
                Test.assertMessage(after[0] > previous,
                    colour.format("%06X") + " must lighten at level " + level);
                var turn = (after[2] - before[2]).abs();
                if (turn > 180.0d) {
                    turn = 360.0d - turn;
                }
                Test.assertMessage(turn < 2.0d,
                    colour.format("%06X") + " turned " + turn + " degrees");
                previous = after[0];
            }
        }
        return true;
    }

    //! On, every always-on table lightens and the awake ones stay exactly as
    //! they were: the boost is for always-on alone.
    (:test)
    function boostLightensAlwaysOnAndNothingAwake(logger as Logger) as Boolean {
        reset();
        var awake = Palette.active.slice(0, null);
        var dim = Palette.dimAwake.slice(0, null);
        var soft = Palette.softAwake.slice(0, null);
        var suns = Palette.sunAwake.slice(0, null);
        var ramp = Palette.rampActive.slice(0, null);
        var plain = Palette.alwaysOn.slice(0, null);
        setBoost(StatMap.BOOST_BRIGHT);
        Test.assertMessage(sameNumbers(Palette.active, awake) &&
                           sameNumbers(Palette.dimAwake, dim) &&
                           sameNumbers(Palette.softAwake, soft) &&
                           sameNumbers(Palette.sunAwake, suns) &&
                           sameNumbers(Palette.rampActive, ramp),
            "the boost must not move a single awake colour");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            for (var lit = 0; lit < 2; lit++) {
                Test.assertMessage(
                    MatrixTest.relativeLuminance(Palette.alwaysOn[ring * 2 + lit]) > MatrixTest.relativeLuminance(plain[ring * 2 + lit]),
                    "ring " + ring + " tier " + lit + " must be brighter boosted");
            }
            Test.assertMessage(MatrixTest.relativeLuminance(Palette.dimAsleep[ring]) > MatrixTest.relativeLuminance(dim[ring]),
                "ring " + ring + ": unknown hours must lighten with the rest");
            Test.assertMessage(MatrixTest.relativeLuminance(Palette.softAsleep[ring]) > MatrixTest.relativeLuminance(soft[ring]),
                "ring " + ring + ": the mark must lighten with its band");
        }
        Test.assertMessage(!sameNumbers(Palette.rampAlwaysOn, Palette.rampActive),
            "the always-on ramp must lighten too");
        reset();
        return true;
    }

    //! useMode() is what the view calls before a frame: it is the only thing
    //! that puts the boosted shared tables in front of the renderer.
    (:test)
    function useModePointsTheSharedTablesAtTheMode(logger as Logger) as Boolean {
        setBoost(StatMap.BOOST_BRIGHTEST);
        Palette.useMode(true);
        Test.assertMessage(Palette.dimOf == Palette.dimAsleep &&
                           Palette.softMarkOf == Palette.softAsleep &&
                           Palette.sunOf == Palette.sunAsleep &&
                           Palette.timeOverlap == Palette.timeAsleep,
            "always-on must read the boosted tables");
        Test.assertMessage(Palette.timeAsleep[TimeRing.BOTH] ==
                           Palette.bright[StatMap.TIME_RING],
            "the time ring's own colour is the boosted ring colour");
        Palette.useMode(false);
        Test.assertMessage(Palette.dimOf == Palette.dimAwake &&
                           Palette.softMarkOf == Palette.softAwake &&
                           Palette.sunOf == Palette.sunAwake &&
                           Palette.timeOverlap == Palette.timeAwake,
            "awake must read the theme's own tables");
        reset();
        return true;
    }

    //! everyThemeFitsTheAlwaysOnBudget, at every boost level. Safe by
    //! construction — all-white fits — and measured anyway, since this is the
    //! one setting whose whole purpose is to spend that budget.
    (:test)
    function everyThemeFitsTheBudgetAtEveryBoost(logger as Logger) as Boolean {
        var full = MatrixTest.everySpan(0.0, 1.0);
        for (var t = 0; t < StatMap.THEME_IDS.size(); t++) {
            Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_IDS[t]);
            var previous = 0.0;
            for (var level = StatMap.BOOST_OFF; level <= StatMap.BOOST_BRIGHTEST; level++) {
                setBoost(level);
                var worst = MatrixTest.frameLuminance(full, Palette.alwaysOn);
                logger.debug("theme " + StatMap.THEME_IDS[t] + " boost " + level +
                             ": " + worst);
                Test.assertMessage(worst < MatrixTest.BUDGET,
                    "theme " + StatMap.THEME_IDS[t] + " at boost " + level +
                    " exceeds the always-on budget");
                Test.assertMessage(worst > previous,
                    "each boost level must be brighter than the last");
                previous = worst;
            }
        }
        reset();
        return true;
    }

    //! The tiers stay in order boosted: unknown below unfilled below filled.
    (:test)
    function boostedTiersKeepTheirOrder(logger as Logger) as Boolean {
        for (var t = 0; t < StatMap.THEME_IDS.size(); t++) {
            Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_IDS[t]);
            setBoost(StatMap.BOOST_BRIGHTEST);
            for (var ring = 0; ring < StatMap.RINGS; ring++) {
                var dim = MatrixTest.relativeLuminance(Palette.dimAsleep[ring]);
                var weak = MatrixTest.relativeLuminance(Palette.alwaysOn[ring * 2]);
                var band = MatrixTest.relativeLuminance(Palette.alwaysOn[ring * 2 + 1]);
                Test.assertMessage(dim < weak && weak < band,
                    "theme " + StatMap.THEME_IDS[t] + " ring " + ring +
                    ": boosted tiers out of order");
            }
        }
        reset();
        return true;
    }
}
