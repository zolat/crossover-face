# Config code

One string that carries the face's whole configuration: every setting plus the custom
theme. The web configurator produces it; the watch applies it from the `configCode` text
setting in Garmin Connect, or from a `.SET` file pushed over USB. The watch also writes its
own live configuration back into `configCode`, so the field in Garmin Connect always shows
what the watch is running and can be pasted back into the web.

It is a **transport, not a store**. The settings stay where they always were — numeric
`Application.Properties`, edited by the on-watch menu and by Garmin Connect's list
fields — and the custom theme lives in `Application.Storage`, which phone-side saves never
touch. The code is derived from those and applied onto them.

The format is also the payload a later background sync would carry, unchanged.

## v1

28 bytes, base64url without padding: **38 characters**.

    byte  field              stored as                      valid
    0     version            1                              1
    1     theme              persisted theme ID             0, 1, 7, 8, 99
    2     handBacking        list index                     0..2
    3     alwaysOnFill       list index                     0..1
    4     dotRotation        list index                     0..1
    5     showDate           list index                     0..1
    6     dateOutline        list index                     0..2
    7     ring1              Source.Kind                    0..15
    8     ring2              Source.Kind                    0..15
    9     ring3              Source.Kind                    0..15
    10    ring4              Source.Kind                    0..15
    11    tempAheadLow       degrees C + 20                 0..70
    12    tempAheadHigh      degrees C + 20                 0..70
    13    custom colour 1    R, G, B (outermost ring)       any
    16    custom colour 2    R, G, B                        any
    19    custom colour 3    R, G, B                        any
    22    custom colour 4    R, G, B (innermost ring)       any
    25    custom ramp        cold | mid << 2 | hot << 4     top two bits 0
    26    CRC-16             big-endian, over bytes 0..25

The CRC is CRC-16/CCITT-FALSE: polynomial `0x1021`, initial value `0xFFFF`, no reflection,
no final XOR. `"123456789"` checks to `0x29B1`.

Theme `99` is **Custom**: the rings take bytes 13–25. It sits outside the production ID
sequence on purpose — the next shipping theme is still `9`. The custom theme is carried
whichever theme is selected, so switching to a shipping theme and back never loses it.

A ramp stop is an index into the theme's four colours, exactly as `Palette.RAMP_STOPS` is.

## Decoding

- Strip whitespace. Accept either base64 alphabet (`-_` or `+/`) and optional `=` padding,
  because a code pasted through a phone's clipboard or an e-mail can come back either way.
- Reject — apply nothing — on a wrong length for the version, a bad CRC, an unknown
  version, or any field outside its range. A code is all-or-nothing: a half-applied one
  would leave the wearer with a face that matches neither what they had nor what they
  pasted.
- Ring sources are range-checked only. Which ring may carry which source, and the retired
  source reading as Off, stay `StatMap.load()`'s business, as they are for every other way
  a value arrives. That includes the two time styles, 14 and 15: a watch with drawn hands
  publishes one as `ring1`, because its outermost ring tells the time whatever `ring1`
  stores, and a watch with physical hands reads either as Off.
- A temperature pair is not normalised here either; `StatMap.loadTempAheadScale()` swaps
  and widens it like any other.

## Encoding

The watch encodes from `StatMap` *after* `load()`, so a code it writes is canonical:
retired and disallowed values are already mapped to what the face actually draws, and the
temperature pair is already ordered. Two configs that draw the same face encode the same.

## Who wins when both change

The watch remembers the last code it wrote, in `Application.Storage` as `lastCode`.

- `configCode` differs from `lastCode` and decodes: the wearer pasted it. It is applied —
  settings to Properties, the custom theme to Storage — and wins over any list field saved
  in the same moment.
- Otherwise the change came from a list field or the on-watch menu, and the code is
  regenerated from the settings.
- A code that does not decode is ignored and overwritten with the live configuration.
- Pasting the very code the field already shows is no change at all, so a list field
  saved alongside it wins. The comparison is against what the watch wrote, not against
  what the face draws.

This runs at start as well as on a phone-side change, because a `.SET` pushed over USB is
only read when the app starts.

## Versions

Later versions only append fields. A decoder that knows version *n* reads every version up
to *n*, filling the fields an older code lacks with their defaults; it refuses a version
newer than itself rather than guessing.

## Keeping the three codecs in step

The codec exists three times — TypeScript (`web/configurator/src/codec/`), Python
(`tools/simctl/configcode.py`), Monkey C (`source/settings/ConfigCode.mc`) — and all three
are held to `tools/testdata/config-codes.json`: the TypeScript and Python tests read it
directly, `MatrixTest` carries the same vectors as constants. A change to the format
changes that file first.
