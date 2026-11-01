"""The config code: the face's whole configuration as one pasteable string.

``docs/config-code.md`` is the specification; this is one of three codecs held to it,
beside the TypeScript one in ``web/configurator`` and ``source/settings/ConfigCode.mc``.
All three are pinned by ``tools/testdata/config-codes.json``.

Here it serves the tooling: ``make push-config`` validates a code before writing it into a
``.SET``, and the vectors file is generated and checked from this module.

Usage::

    python3 -m simctl.configcode decode <code>     # the settings it carries, as JSON
    python3 -m simctl.configcode encode <json>     # a settings dict back to a code
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

VERSION = 1
LENGTH = 28  # bytes, v1

THEME_CUSTOM = 99
THEME_IDS = (0, 1, 7, 8, THEME_CUSTOM)
TEMP_OFFSET = 20
TEMP_MIN, TEMP_MAX = -20, 50
SOURCE_MAX = 13

#: The single-byte settings, in byte order, with their inclusive upper bound. Byte 1
#: (theme) and the two temperatures are checked separately.
ENUM_FIELDS = (
    ("handBacking", 2),
    ("alwaysOnFill", 1),
    ("dotRotation", 1),
    ("showDate", 1),
    ("dateOutline", 2),
    ("ring1", SOURCE_MAX),
    ("ring2", SOURCE_MAX),
    ("ring3", SOURCE_MAX),
    ("ring4", SOURCE_MAX),
)

#: Terrain, so a face that never had a custom theme carries a sensible one.
DEFAULT_CUSTOM_COLOURS = (0xE879F9, 0xB8D64B, 0x7FD4FF, 0xFF6B5B)
DEFAULT_CUSTOM_RAMP = (2, 0, 3)

DEFAULTS = OrderedDict(
    theme=0,
    handBacking=0,
    alwaysOnFill=0,
    dotRotation=0,
    showDate=1,
    dateOutline=1,
    ring1=0,
    # properties.xml seeds ring2 with 1, the retired source, which StatMap.load()
    # reads as Off - so Off is what a fresh face draws and what it would encode.
    ring2=8,
    ring3=2,
    ring4=3,
    tempAheadLow=0,
    tempAheadHigh=45,
    customColours=list(DEFAULT_CUSTOM_COLOURS),
    customRamp=list(DEFAULT_CUSTOM_RAMP),
)

#: The numeric Properties a code sets; the rest of a decoded config goes to Storage.
PROPERTY_KEYS = tuple(key for key in DEFAULTS if not key.startswith("custom"))


class ConfigCodeError(ValueError):
    """Not a config code this version understands. Nothing from it may be applied."""


def crc16(data: bytes) -> int:
    """CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, unreflected, no final XOR."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def _check(config: dict) -> None:
    missing = [key for key in DEFAULTS if key not in config]
    if missing:
        raise ConfigCodeError(f"missing {', '.join(missing)}")
    if config["theme"] not in THEME_IDS:
        raise ConfigCodeError(f"theme={config['theme']} is not one of {THEME_IDS}")
    for key, high in ENUM_FIELDS:
        value = config[key]
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= high:
            raise ConfigCodeError(f"{key}={value!r} is outside 0..{high}")
    for key in ("tempAheadLow", "tempAheadHigh"):
        if not TEMP_MIN <= config[key] <= TEMP_MAX:
            raise ConfigCodeError(f"{key}={config[key]} is outside {TEMP_MIN}..{TEMP_MAX}")
    colours, ramp = config["customColours"], config["customRamp"]
    if len(colours) != 4 or any(not 0 <= c <= 0xFFFFFF for c in colours):
        raise ConfigCodeError(f"customColours={colours!r} must be four 0xRRGGBB values")
    if len(ramp) != 3 or any(not 0 <= stop <= 3 for stop in ramp):
        raise ConfigCodeError(f"customRamp={ramp!r} must be three indices 0..3")


def to_bytes(config: dict) -> bytes:
    _check(config)
    body = bytearray([VERSION, config["theme"]])
    body += bytes(config[key] for key, _ in ENUM_FIELDS)
    body += bytes([config["tempAheadLow"] + TEMP_OFFSET, config["tempAheadHigh"] + TEMP_OFFSET])
    for colour in config["customColours"]:
        body += colour.to_bytes(3, "big")
    cold, mid, hot = config["customRamp"]
    body.append(cold | (mid << 2) | (hot << 4))
    body += crc16(bytes(body)).to_bytes(2, "big")
    assert len(body) == LENGTH
    return bytes(body)


def encode(config: dict) -> str:
    """The canonical text form: base64url, no padding."""
    return base64.urlsafe_b64encode(to_bytes(config)).decode("ascii").rstrip("=")


_ALPHABET = re.compile(r"[A-Za-z0-9_-]*")


def _unwrap(code: str) -> bytes:
    text = "".join(code.split()).rstrip("=").replace("+", "-").replace("/", "_")
    # Explicit, because the stdlib decoder drops characters outside its alphabet
    # rather than refusing them - a mangled paste would decode to something.
    if not _ALPHABET.fullmatch(text):
        raise ConfigCodeError("not base64: contains characters outside the alphabet")
    if len(text) % 4 == 1:
        raise ConfigCodeError("not base64: impossible length")
    try:
        return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    except (binascii.Error, ValueError) as error:
        raise ConfigCodeError(f"not base64: {error}") from None


def decode(code: str) -> "OrderedDict[str, object]":
    """Every field, or :class:`ConfigCodeError`. A code is all-or-nothing."""
    data = _unwrap(code)
    if not data:
        raise ConfigCodeError("empty")
    if data[0] != VERSION:
        raise ConfigCodeError(f"version {data[0]} is not one this decoder reads (1)")
    if len(data) != LENGTH:
        raise ConfigCodeError(f"{len(data)} bytes, a version-1 code is {LENGTH}")
    if crc16(data[:-2]) != int.from_bytes(data[-2:], "big"):
        raise ConfigCodeError("checksum does not match: the code is damaged or mistyped")

    config: "OrderedDict[str, object]" = OrderedDict(theme=data[1])
    for index, (key, _) in enumerate(ENUM_FIELDS):
        config[key] = data[2 + index]
    config["tempAheadLow"] = data[11] - TEMP_OFFSET
    config["tempAheadHigh"] = data[12] - TEMP_OFFSET
    config["customColours"] = [int.from_bytes(data[13 + 3 * i : 16 + 3 * i], "big")
                               for i in range(4)]
    ramp = data[25]
    if ramp >> 6:
        raise ConfigCodeError(f"ramp byte 0x{ramp:02x} sets its reserved top bits")
    config["customRamp"] = [ramp & 3, (ramp >> 2) & 3, (ramp >> 4) & 3]
    _check(config)
    return config


# --- the Monkey C copy of the vectors ---------------------------------------
#
# Monkey C tests cannot read a JSON file, so ConfigCodeTest.mc carries the vectors
# as constants between two marker lines. This writes that block; ``vectors-mc --check``
# (and a simctl test) fails when the file and the JSON disagree.

VECTORS = Path(__file__).resolve().parent.parent / "testdata" / "config-codes.json"
MONKEYC_TEST = Path(__file__).resolve().parents[2] / "source" / "tests" / "ConfigCodeTest.mc"
BLOCK_START = "    // --- generated from tools/testdata/config-codes.json: do not edit ---"
BLOCK_END = "    // --- end of generated vectors ---"


def config_vector(config: dict) -> list[int]:
    """A config in ConfigCode.mc's nineteen-number order."""
    return ([config["theme"]] + [config[key] for key, _ in ENUM_FIELDS]
            + [config["tempAheadLow"], config["tempAheadHigh"]]
            + list(config["customColours"]) + list(config["customRamp"]))


def monkeyc_block(vectors: dict) -> str:
    def strings(items):
        return ",\n".join(f'        "{item}"' for item in items)

    def numbers(rows):
        return ",\n".join("        " + ", ".join(str(n) for n in row) for row in rows)

    valid, aliases, invalid = vectors["valid"], vectors["aliases"], vectors["invalid"]
    names = [vector["name"] for vector in valid]
    return "\n".join([
        BLOCK_START,
        "    const VALID_CODES = [",
        strings(vector["code"] for vector in valid),
        "    ] as Array<String>;",
        "    //! ConfigCode.FIELDS numbers per code, in VALID_CODES order.",
        "    const VALID_CONFIGS = [",
        numbers(config_vector(vector["config"]) for vector in valid),
        "    ] as Array<Number>;",
        "    const ALIAS_CODES = [",
        strings(json.dumps(alias["code"])[1:-1] for alias in aliases),
        "    ] as Array<String>;",
        "    //! Which VALID_CODES entry each alias spells.",
        "    const ALIAS_OF = [" + ", ".join(str(names.index(a["same_as"])) for a in aliases)
        + "] as Array<Number>;",
        "    const INVALID_CODES = [",
        strings(json.dumps(vector["code"])[1:-1] for vector in invalid),
        "    ] as Array<String>;",
        f"    const CRC_CHECK = {vectors['crc_check']['crc']};",
        BLOCK_END,
    ])


def sync_monkeyc(check: bool = False) -> bool:
    """Rewrite the generated block, or with ``check`` report whether it is current."""
    text = MONKEYC_TEST.read_text()
    start, end = text.index(BLOCK_START), text.index(BLOCK_END) + len(BLOCK_END)
    wanted = monkeyc_block(json.loads(VECTORS.read_text()))
    if text[start:end] == wanted:
        return True
    if not check:
        MONKEYC_TEST.write_text(text[:start] + wanted + text[end:])
    return False


# --- pushing a code to a simulator --------------------------------------------


def push(code: str, instance: str | None, device: str) -> dict:
    """Put a code in a simulator's ``configCode`` and restart the face to apply it.

    Only the code is written, not the settings it carries: the face applies it at start
    through ConfigCode.sync(), so this exercises the same path a code pasted into Garmin
    Connect does. The canonical spelling is written, after it has decoded here.
    """
    from simctl import instance as instances
    from simctl import settings as settings_module
    from simctl.runner import Runner

    canonical = encode(decode(code))
    runner = Runner(instances.resolve(instance), device=device)
    schema = settings_module.Schema.load(prg=runner.prg)
    written = runner.write_settings({"configCode": canonical}, schema)
    if not written["ok"]:
        return written
    loaded = runner.load(build=False)
    return {"ok": loaded.get("ok", False), "code": canonical, "load": loaded}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("decode").add_argument("code")
    sub.add_parser("encode").add_argument("config", help="JSON object, or - for stdin")
    pusher = sub.add_parser("push", help="apply a code on a simulator (build first), or a watch")
    pusher.add_argument("code")
    pusher.add_argument("--watch", action="store_true",
                        help="write it to the watch on the cable instead; unplug to apply")
    pusher.add_argument("--instance", default="shared",
                        help="'shared' (default, takes the simulator lock) or a private name")
    pusher.add_argument("--device", default="instinctcrossoveramoled")
    mc = sub.add_parser("vectors-mc", help="write the vectors into ConfigCodeTest.mc")
    mc.add_argument("--check", action="store_true", help="only report whether it is current")
    args = parser.parse_args(argv)
    if args.command == "vectors-mc":
        current = sync_monkeyc(check=args.check)
        if args.check and not current:
            print("ConfigCodeTest.mc is out of date: run `python3 -m simctl.configcode "
                  "vectors-mc`", file=sys.stderr)
            return 1
        return 0
    try:
        if args.command == "push" and args.watch:
            # Checked here, under this module's own ConfigCodeError: run as a script this
            # module is __main__, and simctl.watch imports a second copy of it.
            decode(args.code)
            from simctl import watch
            try:
                result = watch.push(args.code)
            except watch.WatchError as error:
                print(f"error: {error}", file=sys.stderr)
                return 1
            print(f"wrote {result['code']} to {result['file']}")
            print(f"the watch's previous file is saved at {result['backup']}")
            print("Unplug the watch: the face applies the code as the cable comes out.")
            return 0
        if args.command == "push":
            result = push(args.code, args.instance, args.device)
            print(json.dumps(result, indent=2, default=str))
            return 0 if result.get("ok") else 1
        if args.command == "decode":
            print(json.dumps(decode(args.code), indent=2))
        else:
            raw = sys.stdin.read() if args.config == "-" else args.config
            config = OrderedDict(DEFAULTS)
            config.update(json.loads(raw))
            print(encode(config))
    except ConfigCodeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
