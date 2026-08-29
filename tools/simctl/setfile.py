"""Codec for the simulator's persisted-properties file (``<APPNAME>.SET``).

The simulator keeps an app's ``Application.Properties`` in a binary file inside its
simulated device filesystem. Editing it is the only way to change a setting without
driving the GUI (*File -> Edit Persistent Storage*), and the GUI is where this project
has repeatedly lost time.

The layout, recovered by decoding a real file and confirmed by re-serialising it to
identical bytes:

===========  ==================================================================
``abcdabcd`` magic
u32          byte length of the key table
key table    repeated ``u16 length`` + that many bytes of name, NUL terminated
``da7ada7a`` magic separating names from values
u32          byte length of the value section
value        ``u8`` container type, ``u32`` entry count, then that many entries of
section      ``u8 key type`` + ``u32 offset into the key table`` +
             ``u8 value type`` + ``i32 value``
===========  ==================================================================

Keys are referenced by *byte offset* into the table rather than by index, which is why
encoding has to lay the table out before it can write any entry.

Only whole-number properties are handled, because that is all a Connect IQ *list*
setting can be and all seven of this face's properties are lists. An unknown type code
raises rather than being skipped: a settings file that silently loses a key would be
worse than one that fails loudly, since the value it falls back to is invisible.
"""

from __future__ import annotations

import struct
from collections import OrderedDict

MAGIC_KEYS = b"\xab\xcd\xab\xcd"
MAGIC_VALUES = b"\xda\x7a\xda\x7a"

#: Monkey C container/value type codes as they appear in the file.
TYPE_NUMBER = 0x01
TYPE_STRING = 0x03
TYPE_DICTIONARY = 0x0B


class SetFileError(ValueError):
    """The bytes are not a settings file this codec understands."""


def _need(data: bytes, offset: int, count: int, what: str) -> None:
    if offset + count > len(data):
        raise SetFileError(
            f"truncated while reading {what}: wanted {count} bytes at {offset}, "
            f"file is {len(data)} bytes"
        )


def decode(data: bytes) -> "OrderedDict[str, int]":
    """Return the properties in file order, so re-encoding reproduces the bytes."""
    _need(data, 0, 8, "header")
    if data[:4] != MAGIC_KEYS:
        raise SetFileError(f"bad magic {data[:4].hex()}, expected {MAGIC_KEYS.hex()}")

    keys_length = struct.unpack_from(">I", data, 4)[0]
    _need(data, 8, keys_length, "key table")
    table = data[8 : 8 + keys_length]

    names: dict[int, str] = {}
    offset = 0
    while offset < keys_length:
        (length,) = struct.unpack_from(">H", table, offset)
        if length < 1:
            raise SetFileError(f"zero-length key at table offset {offset}")
        # The stored length counts the NUL terminator; the name itself excludes it.
        names[offset] = table[offset + 2 : offset + 2 + length - 1].decode("utf-8")
        offset += 2 + length

    cursor = 8 + keys_length
    _need(data, cursor, 9, "value section header")
    if data[cursor : cursor + 4] != MAGIC_VALUES:
        raise SetFileError(
            f"bad value magic {data[cursor:cursor + 4].hex()}, "
            f"expected {MAGIC_VALUES.hex()}"
        )

    container = data[cursor + 8]
    if container != TYPE_DICTIONARY:
        raise SetFileError(f"expected a dictionary (0x0b), found type 0x{container:02x}")
    (count,) = struct.unpack_from(">I", data, cursor + 9)

    values: "OrderedDict[str, int]" = OrderedDict()
    entry = cursor + 13
    for index in range(count):
        _need(data, entry, 10, f"entry {index}")
        key_type = data[entry]
        (key_offset,) = struct.unpack_from(">I", data, entry + 1)
        value_type = data[entry + 5]
        (value,) = struct.unpack_from(">i", data, entry + 6)
        if key_type != TYPE_STRING:
            raise SetFileError(f"entry {index} has key type 0x{key_type:02x}, expected 0x03")
        if value_type != TYPE_NUMBER:
            raise SetFileError(
                f"entry {index} ({names.get(key_offset, '?')}) has value type "
                f"0x{value_type:02x}; only whole numbers (0x01) are supported"
            )
        if key_offset not in names:
            raise SetFileError(f"entry {index} points at key offset {key_offset}, which is not a key")
        values[names[key_offset]] = value
        entry += 10

    return values


def encode(values: "OrderedDict[str, int] | dict[str, int]") -> bytes:
    """Serialise properties. Key order is preserved, so decode/encode is byte-exact."""
    table = b""
    offsets: dict[str, int] = {}
    for name in values:
        offsets[name] = len(table)
        encoded = name.encode("utf-8") + b"\0"
        table += struct.pack(">H", len(encoded)) + encoded

    body = bytes([TYPE_DICTIONARY]) + struct.pack(">I", len(values))
    for name, value in values.items():
        if not isinstance(value, int) or isinstance(value, bool):
            raise SetFileError(f"{name}={value!r}: only whole numbers can be stored")
        body += (
            bytes([TYPE_STRING])
            + struct.pack(">I", offsets[name])
            + bytes([TYPE_NUMBER])
            + struct.pack(">i", value)
        )

    return (
        MAGIC_KEYS
        + struct.pack(">I", len(table))
        + table
        + MAGIC_VALUES
        + struct.pack(">I", len(body))
        + body
    )
