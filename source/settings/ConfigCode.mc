import Toybox.Application;
import Toybox.Lang;
import Toybox.StringUtil;

//! The face's whole configuration as one pasteable string: every setting plus
//! the custom theme. docs/config-code.md is the specification, and
//! tools/testdata/config-codes.json holds this codec to the same vectors as the
//! web's and the tooling's.
//!
//! A code is a **transport, not a store**. Settings stay in Properties, where
//! the menu and Garmin Connect's list fields edit them, and the custom theme in
//! Storage. sync() applies a code the wearer pasted onto those, then writes the
//! live configuration back into the same field — so the field in Garmin Connect
//! always shows what the watch is running.
//!
//! Nothing here runs per frame: only at start, on a phone-side change and after
//! a menu choice.
module ConfigCode {

    const VERSION = 1;
    //! Bytes in a version-1 code: 26 of payload and a 16-bit CRC.
    const LENGTH = 28;
    const PAYLOAD = 26;
    const TEMP_OFFSET = 20;

    const PROPERTY_CODE = "configCode";
    //! The last code this watch wrote. A field that differs from it was pasted.
    const STORAGE_LAST_CODE = "lastCode";

    //! A config vector — what pack() takes and unpack() returns — is these
    //! nineteen numbers, in code order and in the units the settings store:
    //! theme, the nine one-byte settings, both temperature ends in °C, the four
    //! custom colours and the three custom ramp stops.
    const FIELDS = 19;
    const FIELD_TEMP_LOW = 10;
    const FIELD_COLOURS = 12;
    const FIELD_RAMP = 16;

    //! The nine one-byte settings after the theme, and how high each may go.
    //! Literal, for the on-device const-array reason StatMap.THEME_IDS gives;
    //! configCodeKeysMatchTheSettings pins them to StatMap's own names.
    const ENUM_KEYS = ["handBacking", "alwaysOnFill", "dotRotation", "showDate",
                       "dateOutline", "ring1", "ring2", "ring3", "ring4"]
                      as Array<String>;
    const ENUM_MAX = [2, 1, 1, 1, 2, 15, 15, 15, 15] as Array<Number>;

    const ALPHABET =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    // --- the format --------------------------------------------------------

    //! CRC-16/CCITT-FALSE over the first `count` bytes.
    function crc16(bytes as Array<Number>, count as Number) as Number {
        var crc = 0xFFFF;
        for (var i = 0; i < count; i++) {
            crc = crc ^ (bytes[i] << 8);
            for (var bit = 0; bit < 8; bit++) {
                crc = ((crc & 0x8000) != 0)
                    ? ((crc << 1) ^ 0x1021) & 0xFFFF
                    : (crc << 1) & 0xFFFF;
            }
        }
        return crc;
    }

    //! A config vector as the 28 bytes of a sealed code. Trusts its input:
    //! only decode() is handed anything a wearer typed.
    function pack(config as Array<Number>) as Array<Number> {
        var bytes = new [LENGTH] as Array<Number>;
        bytes[0] = VERSION;
        for (var i = 0; i < FIELD_TEMP_LOW; i++) {
            bytes[1 + i] = config[i];
        }
        bytes[11] = config[FIELD_TEMP_LOW] + TEMP_OFFSET;
        bytes[12] = config[FIELD_TEMP_LOW + 1] + TEMP_OFFSET;
        for (var c = 0; c < Palette.THEME_COLOURS; c++) {
            var colour = config[FIELD_COLOURS + c];
            bytes[13 + c * 3] = (colour >> 16) & 0xFF;
            bytes[14 + c * 3] = (colour >> 8) & 0xFF;
            bytes[15 + c * 3] = colour & 0xFF;
        }
        bytes[25] = config[FIELD_RAMP] | (config[FIELD_RAMP + 1] << 2) |
                    (config[FIELD_RAMP + 2] << 4);
        var crc = crc16(bytes, PAYLOAD);
        bytes[26] = (crc >> 8) & 0xFF;
        bytes[27] = crc & 0xFF;
        return bytes;
    }

    //! The config vector a sealed code carries, or null when the code is
    //! anything but a well-formed version-1 code with every field in range.
    function unpack(bytes as Array<Number>) as Array<Number>? {
        if (bytes.size() != LENGTH || bytes[0] != VERSION) {
            return null;
        }
        if (crc16(bytes, PAYLOAD) != ((bytes[26] << 8) | bytes[27])) {
            return null;
        }
        var theme = bytes[1];
        if (theme != StatMap.THEME_CUSTOM &&
            StatMap.THEME_IDS.indexOf(theme) < 0) {
            return null;
        }
        var config = new [FIELDS] as Array<Number>;
        config[0] = theme;
        for (var i = 0; i < ENUM_MAX.size(); i++) {
            var value = bytes[2 + i];
            if (value > ENUM_MAX[i]) {
                return null;
            }
            config[1 + i] = value;
        }
        for (var i = 0; i < 2; i++) {
            var celsius = bytes[11 + i] - TEMP_OFFSET;
            if (celsius < StatMap.TEMP_AHEAD_MIN_C ||
                celsius > StatMap.TEMP_AHEAD_MAX_C) {
                return null;
            }
            config[FIELD_TEMP_LOW + i] = celsius;
        }
        for (var c = 0; c < Palette.THEME_COLOURS; c++) {
            config[FIELD_COLOURS + c] = (bytes[13 + c * 3] << 16) |
                                        (bytes[14 + c * 3] << 8) |
                                         bytes[15 + c * 3];
        }
        var ramp = bytes[25];
        if ((ramp >> 6) != 0) {
            return null;
        }
        config[FIELD_RAMP] = ramp & 3;
        config[FIELD_RAMP + 1] = (ramp >> 2) & 3;
        config[FIELD_RAMP + 2] = (ramp >> 4) & 3;
        return config;
    }

    //! base64url, unpadded: the canonical spelling.
    function toText(bytes as Array<Number>) as String {
        var alphabet = ALPHABET.toCharArray();
        var out = [] as Array<Char>;
        var count = bytes.size();
        for (var i = 0; i < count; i += 3) {
            var b1 = (i + 1 < count) ? bytes[i + 1] : 0;
            var b2 = (i + 2 < count) ? bytes[i + 2] : 0;
            var triple = (bytes[i] << 16) | (b1 << 8) | b2;
            out.add(alphabet[(triple >> 18) & 63]);
            out.add(alphabet[(triple >> 12) & 63]);
            if (i + 1 < count) {
                out.add(alphabet[(triple >> 6) & 63]);
            }
            if (i + 2 < count) {
                out.add(alphabet[triple & 63]);
            }
        }
        return StringUtil.charArrayToString(out);
    }

    //! Either base64 alphabet, padded or not, whitespace ignored — a code that
    //! went through a phone's clipboard or an e-mail can come back any of
    //! those ways. Anything else is refused rather than skipped.
    function fromText(text as String) as Array<Number>? {
        var values = [] as Array<Number>;
        var padded = false;
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var code = chars[i].toNumber();
            if (code == 32 || code == 9 || code == 10 || code == 13) {
                continue;
            }
            if (code == 61) {               // '=' may only trail
                padded = true;
                continue;
            }
            var value = sextet(code);
            if (value < 0 || padded) {
                return null;
            }
            values.add(value);
        }
        var count = values.size();
        if (count % 4 == 1) {
            return null;
        }
        var bytes = [] as Array<Number>;
        for (var i = 0; i < count; i += 4) {
            var group = (count - i < 4) ? count - i : 4;
            var acc = 0;
            for (var k = 0; k < 4; k++) {
                acc = (acc << 6) | ((k < group) ? values[i + k] : 0);
            }
            bytes.add((acc >> 16) & 0xFF);
            if (group > 2) {
                bytes.add((acc >> 8) & 0xFF);
            }
            if (group > 3) {
                bytes.add(acc & 0xFF);
            }
        }
        return bytes;
    }

    function sextet(code as Number) as Number {
        if (code >= 65 && code <= 90) { return code - 65; }     // A-Z
        if (code >= 97 && code <= 122) { return code - 71; }    // a-z
        if (code >= 48 && code <= 57) { return code + 4; }      // 0-9
        if (code == 45 || code == 43) { return 62; }            // - or +
        if (code == 95 || code == 47) { return 63; }            // _ or /
        return -1;
    }

    function encode(config as Array<Number>) as String {
        return toText(pack(config));
    }

    function decode(text as String) as Array<Number>? {
        var bytes = fromText(text);
        return (bytes == null) ? null : unpack(bytes);
    }

    // --- the watch's side ----------------------------------------------------

    //! The configuration the face is drawing, after StatMap.load() has mapped
    //! retired and disallowed values — so a code written from it is canonical.
    function current() as Array<Number> {
        var config = new [FIELDS] as Array<Number>;
        config[0] = StatMap.theme;
        config[1] = StatMap.backing;
        config[2] = StatMap.alwaysOnFill;
        config[3] = StatMap.rotation;
        config[4] = StatMap.date;
        config[5] = StatMap.dateOutline;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            config[6 + ring] = StatMap.rings[ring];
        }
        config[FIELD_TEMP_LOW] = StatMap.tempAheadLow;
        config[FIELD_TEMP_LOW + 1] = StatMap.tempAheadHigh;
        var custom = StatMap.customTheme;
        for (var i = 0; i < StatMap.CUSTOM_THEME_SIZE; i++) {
            config[FIELD_COLOURS + i] = custom[i];
        }
        return config;
    }

    //! Write a decoded config onto the stores it describes. The caller reloads.
    function apply(config as Array<Number>) as Void {
        Properties.setValue(StatMap.PROPERTY_THEME, config[0]);
        for (var i = 0; i < ENUM_KEYS.size(); i++) {
            Properties.setValue(ENUM_KEYS[i], config[1 + i]);
        }
        Properties.setValue(StatMap.PROPERTY_TEMP_AHEAD_LOW,
                            config[FIELD_TEMP_LOW]);
        Properties.setValue(StatMap.PROPERTY_TEMP_AHEAD_HIGH,
                            config[FIELD_TEMP_LOW + 1]);
        Storage.setValue(StatMap.STORAGE_CUSTOM_THEME,
                         config.slice(FIELD_COLOURS, FIELDS)
                             as Array<Application.Storage.ValueType>);
    }

    //! Put the live configuration in the code field, and remember it as ours.
    function publish() as String {
        var code = encode(current());
        Properties.setValue(PROPERTY_CODE, code);
        Storage.setValue(STORAGE_LAST_CODE, code);
        return code;
    }

    //! Apply a pasted code if there is one, then publish. True when a code was
    //! applied. Call after Config.reload(), so publish() reads current state.
    //!
    //! "Pasted" means the field differs from the last code this watch wrote:
    //! a list field saved in Garmin Connect leaves the code field as it was, so
    //! that change is kept and the code regenerated around it. A code that does
    //! not decode is simply overwritten — the field then shows what the face is
    //! actually running, which is the most useful thing a refusal can say.
    function sync() as Boolean {
        var applied = false;
        var field = null;
        var last = null;
        try {
            field = Properties.getValue(PROPERTY_CODE);
            last = Storage.getValue(STORAGE_LAST_CODE);
        } catch (ex) {
            field = null;
        }
        if (field instanceof String && field.length() > 0 &&
            !field.equals(last)) {
            var config = decode(field);
            if (config != null) {
                apply(config);
                Config.reload();
                applied = true;
            }
        }
        publish();
        return applied;
    }
}
