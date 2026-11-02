import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;
import Toybox.Test;

//! The config code and the custom theme it carries.
//!
//! The codec is held to the same vectors as the web's and the tooling's: the
//! block below is generated from tools/testdata/config-codes.json by
//! `python3 -m simctl.configcode vectors-mc`, and a simctl test fails when the
//! two disagree. Its own file because MatrixTest is the face's, and this is a
//! format.
module ConfigCodeTest {

    // --- generated from tools/testdata/config-codes.json: do not edit ---
    const VALID_CODES = [
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIA5bM6ALwM",
        "AmMCAQEAAgkKDQcARv___wAAABI0VqvN7wcA5bM6AIQ9",
        "AggAAAABAQwLBQRGAOh5-bjWS3_U__9rWzIA5bM6AJVG",
        "AgEAAAABAQABAgkUQeh5-bjWS3_U__9rWzIA5bM6ALyY",
        "AgcAAAABAQAIAgMgIOh5-bjWS3_U__9rWwAA5bM6ADN1",
        "AgABAAABAQ8IAgMUQeh5-bjWS3_U__9rWzIA5bM6AGHa",
        "AgAAAAABAQ4NAg8UQeh5-bjWS3_U__9rWzIA5bM6AO_0",
        "AmMAAAABAQAIAgMUQREiM0RVZneImaq7zAQHEjRWAaPZ",
        "AgAAAAABAQAIAgMUQQAAAAAAAAAAAAAAAAAP____B7jr"
    ] as Array<String>;
    //! ConfigCode.FIELDS numbers per code, in VALID_CODES order.
    const VALID_CONFIGS = [
        0, 0, 0, 0, 1, 1, 0, 8, 2, 3, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        99, 2, 1, 1, 0, 2, 9, 10, 13, 7, -20, 50, 16777215, 0, 1193046, 11259375, 3, 1, 0, 0, 15053626,
        8, 0, 0, 0, 1, 1, 12, 11, 5, 4, 50, -20, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        1, 0, 0, 0, 1, 1, 0, 1, 2, 9, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        7, 0, 0, 0, 1, 1, 0, 8, 2, 3, 12, 12, 15235577, 12113483, 8377599, 16739163, 0, 0, 0, 0, 15053626,
        0, 1, 0, 0, 1, 1, 15, 8, 2, 3, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        0, 0, 0, 0, 1, 1, 14, 13, 2, 15, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        99, 0, 0, 0, 1, 1, 0, 8, 2, 3, 0, 45, 1122867, 4478310, 7833753, 11189196, 4, 1, 0, 7, 1193046,
        0, 0, 0, 0, 1, 1, 0, 8, 2, 3, 0, 45, 0, 0, 0, 0, 4, 4, 4, 15, 16777215
    ] as Array<Number>;
    //! Version-1 codes, decode-only, and the ConfigCode.FIELDS numbers a
    //! version-2 decoder makes of each: ring 5 and colour 5 at their defaults.
    const V1_CODES = [
        "AQAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIEYw",
        "AWMCAQEAAgkKDQcARv___wAAABI0VqvN7wcDSQ",
        "AQgAAAABAQwLBQRGAOh5-bjWS3_U__9rWzKyZw",
        "AQEAAAABAQABAgkUQeh5-bjWS3_U__9rWzIRZQ",
        "AQcAAAABAQAIAgMgIOh5-bjWS3_U__9rWwBfYg",
        "AQABAAABAQ8IAgMUQeh5-bjWS3_U__9rWzKZQQ",
        "AQAAAAABAQ4NAg8UQeh5-bjWS3_U__9rWzLhnA"
    ] as Array<String>;
    const V1_CONFIGS = [
        0, 0, 0, 0, 1, 1, 0, 8, 2, 3, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        99, 2, 1, 1, 0, 2, 9, 10, 13, 7, -20, 50, 16777215, 0, 1193046, 11259375, 3, 1, 0, 0, 15053626,
        8, 0, 0, 0, 1, 1, 12, 11, 5, 4, 50, -20, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        1, 0, 0, 0, 1, 1, 0, 1, 2, 9, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        7, 0, 0, 0, 1, 1, 0, 8, 2, 3, 12, 12, 15235577, 12113483, 8377599, 16739163, 0, 0, 0, 0, 15053626,
        0, 1, 0, 0, 1, 1, 15, 8, 2, 3, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626,
        0, 0, 0, 0, 1, 1, 14, 13, 2, 15, 0, 45, 15235577, 12113483, 8377599, 16739163, 2, 0, 3, 0, 15053626
    ] as Array<Number>;
    const ALIAS_CODES = [
        "AmMCAQEAAgkKDQcARv///wAAABI0VqvN7wcA5bM6AIQ9",
        "  AmMCAQEAAgkKDQcARv_\n __wAAABI0VqvN7wcA5bM6AIQ9\t"
    ] as Array<String>;
    //! Which VALID_CODES entry each alias spells.
    const ALIAS_OF = [1, 1] as Array<Number>;
    const INVALID_CODES = [
        "AQAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIEYg",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzLg4Q",
        "AQAAAAABAQAIAgMUQeh5-bjWS38",
        "AQAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIEYwA",
        "AQUAAAABAQAIAgMUQeh5-bjWS3_U__9rWzJHJg",
        "AQADAAABAQAIAgMUQeh5-bjWS3_U__9rWzJdZg",
        "AQAAAAIBAQAIAgMUQeh5-bjWS3_U__9rWzLf0w",
        "AQAAAAABARAIAgMUQeh5-bjWS3_U__9rWzI0Pg",
        "AQAAAAABAQAIAgMUR-h5-bjWS3_U__9rWzIPBA",
        "AQAAAAABAQAIAgMUQeh5-bjWS3_U__9rW3JMpw",
        "",
        "this is not a code!",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIA5bM6ALwN",
        "AwAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIA5bM6ADIl",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzLg4Q",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIA5bM6AABqVw",
        "AQAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIA5bM6AD5W",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIQ5bM6ALhW",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWzIA5bM6CD0E",
        "AgAAAAABAQAIAgMUQeh5-bjWS3_U__9rWwEA5bM6AU1B"
    ] as Array<String>;
    const CRC_CHECK = 10673;
    // --- end of generated vectors ---

    function configAt(index as Number) as Array<Number> {
        return VALID_CONFIGS.slice(index * ConfigCode.FIELDS,
                                   (index + 1) * ConfigCode.FIELDS);
    }

    function sameConfig(a as Array<Number>?, b as Array<Number>) as Boolean {
        if (a == null || a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < b.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    //! Every setting the code writes, the custom theme and both code slots,
    //! so a test can put the shared app data back the way it found it — the
    //! face and the test build share one settings file.
    function snapshot() as Dictionary {
        var keys = ConfigCode.ENUM_KEYS.slice(0, null);
        keys.add(StatMap.PROPERTY_THEME);
        keys.add(StatMap.PROPERTY_RINGS[ConfigCode.CODE_RINGS]);
        keys.add(StatMap.PROPERTY_TEMP_AHEAD_LOW);
        keys.add(StatMap.PROPERTY_TEMP_AHEAD_HIGH);
        keys.add(ConfigCode.PROPERTY_CODE);
        var properties = {} as Dictionary;
        for (var i = 0; i < keys.size(); i++) {
            properties[keys[i]] = Properties.getValue(keys[i]);
        }
        return {
            :properties => properties,
            :custom => Storage.getValue(StatMap.STORAGE_CUSTOM_THEME),
            :last => Storage.getValue(ConfigCode.STORAGE_LAST_CODE)
        };
    }

    function restore(saved as Dictionary) as Void {
        var properties = saved[:properties] as Dictionary;
        var keys = properties.keys();
        for (var i = 0; i < keys.size(); i++) {
            var value = properties[keys[i]];
            if (value != null) {
                Properties.setValue(keys[i] as String,
                                    value as Application.Properties.ValueType);
            }
        }
        restoreStorage(StatMap.STORAGE_CUSTOM_THEME, saved[:custom] as Object?);
        restoreStorage(ConfigCode.STORAGE_LAST_CODE, saved[:last] as Object?);
        Config.reload();
    }

    function restoreStorage(key as String, value as Object?) as Void {
        if (value == null) {
            Storage.deleteValue(key);
        } else {
            Storage.setValue(key, value as Application.Storage.ValueType);
        }
    }

    function setCustom(colours as Array<Number>, ramp as Array<Number>) as Void {
        var stored = colours.slice(0, null);
        stored.addAll(ramp);
        Storage.setValue(StatMap.STORAGE_CUSTOM_THEME,
                         stored as Array<Application.Storage.ValueType>);
    }

    // --- the format ----------------------------------------------------------

    (:test)
    function theCrcIsCcittFalse(logger as Logger) as Boolean {
        var chars = "123456789".toCharArray();
        var bytes = new [chars.size()] as Array<Number>;
        for (var i = 0; i < chars.size(); i++) {
            bytes[i] = chars[i].toNumber();
        }
        Test.assertEqualMessage(ConfigCode.crc16(bytes, bytes.size()), CRC_CHECK,
            "the CRC must be CCITT-FALSE, or no other codec will agree with it");
        return true;
    }

    (:test)
    function everyVectorEncodesToItsCode(logger as Logger) as Boolean {
        for (var i = 0; i < VALID_CODES.size(); i++) {
            var code = ConfigCode.encode(configAt(i));
            Test.assertMessage(code.equals(VALID_CODES[i]),
                "vector " + i + " encodes to " + code + ", not " + VALID_CODES[i]);
            Test.assertEqualMessage(code.length(), 44,
                "a version-2 code is 44 characters");
        }
        return true;
    }

    (:test)
    function everyVectorDecodesToItsConfig(logger as Logger) as Boolean {
        for (var i = 0; i < VALID_CODES.size(); i++) {
            Test.assertMessage(
                sameConfig(ConfigCode.decode(VALID_CODES[i]), configAt(i)),
                "vector " + i + " does not decode to its config");
        }
        return true;
    }

    //! A version-1 code still applies, with ring 5 and colour 5 at their
    //! defaults: a newer decoder reads every older code.
    (:test)
    function aVersion1CodeDecodesWithTheNewFieldsDefaulted(logger as Logger)
            as Boolean {
        for (var i = 0; i < V1_CODES.size(); i++) {
            var expected = V1_CONFIGS.slice(i * ConfigCode.FIELDS,
                                            (i + 1) * ConfigCode.FIELDS);
            Test.assertMessage(
                sameConfig(ConfigCode.decode(V1_CODES[i]), expected),
                "version-1 vector " + i + " does not decode as version 2 reads it");
        }
        return true;
    }

    //! The standard alphabet with padding, and a code broken across lines —
    //! what a phone clipboard or an e-mail hands back.
    (:test)
    function otherSpellingsOfACodeDecodeTheSame(logger as Logger) as Boolean {
        for (var i = 0; i < ALIAS_CODES.size(); i++) {
            Test.assertMessage(
                sameConfig(ConfigCode.decode(ALIAS_CODES[i]),
                           configAt(ALIAS_OF[i])),
                "alias " + i + " does not decode like the code it spells");
        }
        return true;
    }

    (:test)
    function everyInvalidCodeIsRefusedWhole(logger as Logger) as Boolean {
        for (var i = 0; i < INVALID_CODES.size(); i++) {
            Test.assertMessage(ConfigCode.decode(INVALID_CODES[i]) == null,
                "invalid vector " + i + " (" + INVALID_CODES[i] +
                ") was accepted");
        }
        return true;
    }

    //! The codec names the settings by literal, for the on-device const-array
    //! reason; these are what keep the literals the settings' own.
    (:test)
    function configCodeKeysMatchTheSettings(logger as Logger) as Boolean {
        var keys = [StatMap.PROPERTY_BACKING, StatMap.PROPERTY_ALWAYS_ON_FILL,
                    StatMap.PROPERTY_ROTATION, StatMap.PROPERTY_DATE,
                    StatMap.PROPERTY_DATE_OUTLINE] as Array<String>;
        // Version 1 carries the first four rings; the 454's fifth is outside it.
        keys.addAll(StatMap.PROPERTY_RINGS.slice(0, ConfigCode.CODE_RINGS));
        var highs = [StatMap.BACKING_DARK, StatMap.ALWAYS_ON_FILL_HIDDEN,
                     StatMap.ROTATION_UPRIGHT, StatMap.DATE_ON,
                     StatMap.OUTLINE_80] as Array<Number>;
        for (var ring = 0; ring < ConfigCode.CODE_RINGS; ring++) {
            highs.add(Source.COUNT - 1);
        }
        Test.assertEqualMessage(ConfigCode.ENUM_KEYS.size(), keys.size(),
            "the code must carry every one-byte setting");
        for (var i = 0; i < keys.size(); i++) {
            Test.assertMessage(ConfigCode.ENUM_KEYS[i].equals(keys[i]),
                "code field " + i + " names " + ConfigCode.ENUM_KEYS[i] +
                ", not " + keys[i]);
            Test.assertEqualMessage(ConfigCode.ENUM_MAX[i], highs[i],
                keys[i] + " has a different top value in the code");
        }
        Test.assertEqualMessage(StatMap.CUSTOM_THEME_SIZE,
            Palette.THEME_COLOURS + Palette.RAMP_POINTS,
            "a custom theme is five colours and three ramp stops");
        Test.assertEqualMessage(ConfigCode.FIELDS,
            1 + ConfigCode.ENUM_KEYS.size() + 2 + ConfigCode.CODE_COLOURS +
                Palette.RAMP_POINTS + 2,
            "a config vector is theme, settings, temperatures, four custom " +
            "colours, the stops, then ring 5 and colour 5");
        Test.assertEqualMessage(StatMap.PROPERTY_RINGS[ConfigCode.CODE_RINGS],
            "ring5", "the appended ring is ring5");
        return true;
    }

    // --- the custom theme ----------------------------------------------------

    (:test)
    function aCustomThemeDrawsItsOwnColoursAndRamp(logger as Logger) as Boolean {
        var saved = snapshot();
        var colours = [0x123456, 0xABCDEF, 0x00FF00, 0xFF8000, 0x8000FF]
                      as Array<Number>;
        setCustom(colours, [3, 1, 0] as Array<Number>);
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_CUSTOM);
        Config.reload();

        Test.assertEqualMessage(StatMap.theme, StatMap.THEME_CUSTOM,
            "theme 99 must load as Custom, not fall back to Terrain");
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            Test.assertEqualMessage(Palette.active[ring * 2 + 1], colours[ring],
                "ring " + ring + " does not draw its custom colour");
        }
        Test.assertEqualMessage(Palette.rampActive[0], colours[3],
            "the custom ramp must start at its cold stop");
        Test.assertEqualMessage(
            Palette.rampActive[Palette.RAMP_STEPS - 1], colours[0],
            "the custom ramp must end at its hot stop");
        restore(saved);
        return true;
    }

    //! Choosing a shipping theme must not lose the custom one: the code carries
    //! it whichever theme is in force, so switching back restores it.
    (:test)
    function theCustomThemeIsCarriedWhicheverThemeIsSelected(
            logger as Logger) as Boolean {
        var saved = snapshot();
        var colours = [0x111111, 0x222222, 0x333333, 0x444444, 0x555555]
                      as Array<Number>;
        setCustom(colours, [0, 1, 2] as Array<Number>);
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_BEACON);
        Config.reload();

        var decoded = ConfigCode.decode(ConfigCode.encode(ConfigCode.current()));
        Test.assertMessage(decoded != null, "the live config must encode");
        var carried = decoded as Array<Number>;
        Test.assertEqualMessage(carried[0], StatMap.THEME_BEACON,
            "the code must say which theme is in force");
        for (var i = 0; i < ConfigCode.CODE_COLOURS; i++) {
            Test.assertEqualMessage(carried[ConfigCode.FIELD_COLOURS + i],
                colours[i], "custom colour " + i + " was dropped");
        }
        Test.assertEqualMessage(carried[ConfigCode.FIELD_COLOUR5], colours[4],
            "custom colour 5 was dropped");
        Test.assertEqualMessage(carried[ConfigCode.FIELD_TEMP_LOW],
            StatMap.tempAheadLow,
            "a fifth ring must not spill into the temperature field");
        Test.assertEqualMessage(Palette.active[1], 0x5CD9F0,
            "a stored custom theme must not leak into a shipping one");
        restore(saved);
        return true;
    }

    //! A custom theme stored before themes had five colours still loads, with
    //! the default fifth slotted in ahead of its stops; and a code carries the
    //! fifth colour and ring 5 there and back.
    (:test)
    function aFourColourCustomThemeGainsAFifth(logger as Logger) as Boolean {
        var saved = snapshot();
        Storage.setValue(StatMap.STORAGE_CUSTOM_THEME,
            [0x111111, 0x222222, 0x333333, 0x444444, 3, 1, 0]
                as Array<Application.Storage.ValueType>);
        Config.reload();
        var custom = StatMap.customTheme;
        Test.assertEqualMessage(custom.size(), StatMap.CUSTOM_THEME_SIZE,
            "a four-colour custom theme must load widened, not fall back");
        Test.assertEqualMessage(custom[3], 0x444444, "colour 4 moved");
        Test.assertEqualMessage(custom[4], StatMap.CUSTOM_FIFTH_DEFAULT,
            "the fifth colour must be the default");
        Test.assertEqualMessage(custom[5], 3, "the stops must follow the colours");

        setCustom([0x111111, 0x222222, 0x333333, 0x444444, 0x5A5A5A]
                      as Array<Number>, [0, 1, 2] as Array<Number>);
        Config.reload();
        var code = ConfigCode.current();
        code[ConfigCode.FIELD_COLOURS] = 0x777777;
        ConfigCode.apply(code);
        Config.reload();
        Test.assertEqualMessage(StatMap.customTheme[0], 0x777777,
            "the code's colours must apply");
        Test.assertEqualMessage(StatMap.customTheme[4], 0x5A5A5A,
            "the code must carry the fifth colour");

        // A stop on the fifth colour, and ring 5, survive a round trip.
        code = ConfigCode.current();
        code[ConfigCode.FIELD_RAMP] = 4;
        code[ConfigCode.FIELD_RING5] = Source.SOURCE_BATTERY;
        var again = ConfigCode.decode(ConfigCode.encode(code));
        Test.assertMessage(sameConfig(again, code),
            "a stop on colour 5 and ring 5 must round-trip");
        ConfigCode.apply(code);
        Config.reload();
        Test.assertEqualMessage(StatMap.customTheme[Palette.THEME_COLOURS], 4,
            "a stop may name the fifth colour");
        Test.assertEqualMessage(
            Properties.getValue(StatMap.PROPERTY_RINGS[ConfigCode.CODE_RINGS]),
            Source.SOURCE_BATTERY, "ring 5 must apply on every watch");
        if (StatMap.RINGS == 5) {
            Test.assertEqualMessage(StatMap.rings[4], Source.SOURCE_BATTERY,
                "and draw on the 454");
        }
        restore(saved);
        return true;
    }

    (:test)
    function aMalformedCustomThemeFallsBackWhole(logger as Logger) as Boolean {
        var saved = snapshot();
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_CUSTOM);
        var bad = [
            [0xFFFFFF, 0, 0] as Array<Application.Storage.ValueType>,
            [0, 0, 0, 0, 0, 0, 4] as Array<Application.Storage.ValueType>,
            [0x1000000, 0, 0, 0, 0, 0, 0] as Array<Application.Storage.ValueType>,
            [0, 0, 0, "red", 0, 0, 0] as Array<Application.Storage.ValueType>
        ] as Array<Array<Application.Storage.ValueType> >;
        for (var i = 0; i < bad.size(); i++) {
            Storage.setValue(StatMap.STORAGE_CUSTOM_THEME, bad[i]);
            Config.reload();
            for (var k = 0; k < StatMap.CUSTOM_THEME_SIZE; k++) {
                Test.assertEqualMessage(StatMap.customTheme[k],
                    StatMap.CUSTOM_DEFAULT[k],
                    "malformed custom theme " + i + " was partly used");
            }
        }
        restore(saved);
        return true;
    }

    //! No colours a wearer can pick cross the always-on budget, so the watch
    //! needs no clamp: every dot white is the brightest theme there is, and it
    //! still fits once the brightest mark and every sun dot are added — the
    //! same three terms theSunDotsFitTheAlwaysOnBudget prices. Measured at
    //! 8.99% on 390 and 416 and 9.10% on 454 before this was written.
    (:test)
    function anAllWhiteCustomThemeFitsTheAlwaysOnBudget(
            logger as Logger) as Boolean {
        var saved = snapshot();
        setCustom([0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF] as Array<Number>,
                  [0, 1, 2] as Array<Number>);
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_CUSTOM);
        Config.reload();

        var area = Math.PI * DotGrid.RADIUS * DotGrid.RADIUS;
        var solid = DotGrid.DOT * DotGrid.DOT;
        var lit = MatrixTest.LIT_PIXELS_PER_DOT;
        var dimmest = 1.0;
        var brightestMark = 0.0;
        var brightestSun = 0.0;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            var band = MatrixTest.relativeLuminance(Palette.alwaysOn[ring * 2 + 1]);
            if (band < dimmest) { dimmest = band; }
            var mark = MatrixTest.relativeLuminance(Palette.markerOf[ring]);
            if (mark > brightestMark) { brightestMark = mark; }
            var soft = MatrixTest.relativeLuminance(Palette.softMarkOf[ring]);
            if (soft > brightestMark) { brightestMark = soft; }
        }
        for (var k = 0; k < Palette.sunOf.size(); k++) {
            var sun = MatrixTest.relativeLuminance(Palette.sunOf[k]);
            if (sun > brightestSun) { brightestSun = sun; }
        }
        var full = MatrixTest.everySpan(0.0, 1.0);
        var field = MatrixTest.frameLuminance(full, Palette.alwaysOn);
        var marks = ((brightestMark * solid) - (dimmest * lit)) *
                    StatMap.RINGS / area;
        var suns = ((brightestSun * solid) - (dimmest * lit)) *
                   StatMap.RINGS * Source.SUN_VALUES / area;
        var hands = MatrixTest.frameLuminanceWithHands(full, Palette.alwaysOn,
                                                       StatMap.BACKING_WHITE);
        logger.debug("all white: field " + field + " + marks " + marks +
                     " + suns " + suns + "; with hands " + hands);
        Test.assertMessage(field + marks + suns < MatrixTest.BUDGET,
            "an all-white custom theme crosses the always-on budget");
        Test.assertMessage(hands < MatrixTest.BUDGET,
            "an all-white custom theme crosses the budget under the hands");
        restore(saved);
        return true;
    }

    // --- sync: who wins --------------------------------------------------------

    (:test)
    function aPastedCodeIsAppliedAndTheFieldRewritten(logger as Logger) as Boolean {
        var saved = snapshot();
        Config.reload();
        ConfigCode.publish();

        // The every-field vector, spelled the long way so the rewrite shows.
        Properties.setValue(ConfigCode.PROPERTY_CODE, ALIAS_CODES[0]);
        Config.reload();
        Test.assertMessage(ConfigCode.sync(), "a pasted code must be applied");

        var expected = configAt(ALIAS_OF[0]);
        Test.assertEqualMessage(StatMap.theme, StatMap.THEME_CUSTOM,
            "the pasted theme must be in force");
        Test.assertEqualMessage(Palette.active[1], expected[ConfigCode.FIELD_COLOURS],
            "the pasted custom colours must be drawn");
        var field = Properties.getValue(ConfigCode.PROPERTY_CODE) as String;
        Test.assertMessage(sameConfig(ConfigCode.decode(field), ConfigCode.current()),
            "the field must be rewritten to what the face now draws");
        Test.assertMessage(field.equals(Storage.getValue(ConfigCode.STORAGE_LAST_CODE)),
            "the rewritten code must be remembered as the watch's own");
        Test.assertMessage(!ConfigCode.sync(),
            "the watch's own code must not count as pasted next time");
        restore(saved);
        return true;
    }

    //! A list field saved in Garmin Connect leaves the code field as it was.
    //! The field change must win, and the code be regenerated around it.
    (:test)
    function aListFieldChangeIsKeptAndTheCodeRegenerated(
            logger as Logger) as Boolean {
        var saved = snapshot();
        Properties.setValue(StatMap.PROPERTY_DATE_OUTLINE, StatMap.OUTLINE_50);
        Config.reload();
        var before = ConfigCode.publish();

        Properties.setValue(StatMap.PROPERTY_DATE_OUTLINE, StatMap.OUTLINE_80);
        Config.reload();
        Test.assertMessage(!ConfigCode.sync(),
            "an unchanged code field must not be re-applied");
        Test.assertEqualMessage(StatMap.dateOutline, StatMap.OUTLINE_80,
            "the list field's change must survive");
        var after = Properties.getValue(ConfigCode.PROPERTY_CODE) as String;
        Test.assertMessage(!after.equals(before),
            "the code must be regenerated to carry the change");
        Test.assertEqualMessage(
            (ConfigCode.decode(after) as Array<Number>)[5], StatMap.OUTLINE_80,
            "the regenerated code must say what the field now says");
        restore(saved);
        return true;
    }

    (:test)
    function aCodeThatDoesNotDecodeChangesNothing(logger as Logger) as Boolean {
        var saved = snapshot();
        Properties.setValue(StatMap.PROPERTY_THEME, StatMap.THEME_PULSE);
        Config.reload();
        ConfigCode.publish();
        var live = ConfigCode.current();

        for (var i = 0; i < INVALID_CODES.size(); i++) {
            Properties.setValue(ConfigCode.PROPERTY_CODE, INVALID_CODES[i]);
            Test.assertMessage(!ConfigCode.sync(),
                "invalid vector " + i + " was applied");
            Test.assertMessage(sameConfig(ConfigCode.current(), live),
                "invalid vector " + i + " changed the configuration");
            var field = Properties.getValue(ConfigCode.PROPERTY_CODE) as String;
            Test.assertMessage(sameConfig(ConfigCode.decode(field), live),
                "a refused code must be replaced with the live one");
        }
        restore(saved);
        return true;
    }

    //! Garmin Connect saves every field at once. A wearer who pastes a code and
    //! also touched a list field meant the code: it is the whole configuration.
    (:test)
    function aPastedCodeWinsOverAListFieldSavedWithIt(logger as Logger) as Boolean {
        var saved = snapshot();
        // Start from a known configuration: if the watch were already running
        // vector 1, pasting it would rightly count as no change at all.
        ConfigCode.apply(configAt(0));
        Config.reload();
        ConfigCode.publish();

        // Vector 1 sets backing to Dark; the list field says White.
        Test.assertMessage(!VALID_CODES[1].equals(
                Storage.getValue(ConfigCode.STORAGE_LAST_CODE)),
            "the pasted code must differ from the watch's own to count as pasted");
        Properties.setValue(StatMap.PROPERTY_BACKING, StatMap.BACKING_WHITE);
        Properties.setValue(ConfigCode.PROPERTY_CODE, VALID_CODES[1]);
        Config.reload();
        ConfigCode.sync();
        Test.assertEqualMessage(StatMap.backing, configAt(1)[1],
            "the pasted code's backing must win over the list field's");
        restore(saved);
        return true;
    }
}
