"""Read and write the face's settings without touching the simulator GUI.

A setting resolves to the first of these that exists: the value **persisted** in the
simulator's app data, the default **seeded** from ``resources/properties.xml``, then the
hard-coded fallback in ``StatMap.load()``. So a persisted value silently wins over an
edited ``properties.xml``, and every ``make test`` run leaves values behind because
several tests call ``Properties.setValue``. That is the trap this module exists to
remove: it reports which values are actually persisted, and writes them directly.

Values are validated against ``bin/<App>-settings.json``, the schema ``monkeyc`` emits
from ``resources/settings/settings.xml``. Using the generated schema rather than a local
copy means a new setting is picked up without editing anything here — one less place to
keep in step.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import OrderedDict
from pathlib import Path

if __package__ in (None, ""):  # allow `python3 simctl/settings.py`
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from simctl import paths, setfile

DEFAULT_PRG = "bin/CrossoverFace.prg"


class SettingsError(ValueError):
    """A setting was unknown, out of range, or the schema was unavailable."""


class Schema:
    """The settings the compiler says this app has, with their permitted values."""

    def __init__(self, entries: list[dict], strings: dict[str, str]):
        self._entries = {entry["key"]: entry for entry in entries}
        self._strings = strings

    @classmethod
    def load(cls, repo: Path | None = None, prg: str = DEFAULT_PRG) -> "Schema":
        repo = repo or paths.repo_root()
        schema_path = repo / "bin" / f"{Path(prg).stem}-settings.json"
        if not schema_path.exists():
            raise SettingsError(
                f"no settings schema at {schema_path} — it is build output, so run "
                f"`make build` first (values are not written unvalidated)"
            )
        entries = json.loads(schema_path.read_text())["settings"]
        return cls(entries, cls._read_strings(repo))

    @staticmethod
    def _read_strings(repo: Path) -> dict[str, str]:
        """Resource ids map to the human labels shown on the watch."""
        path = repo / "resources" / "strings" / "strings.xml"
        if not path.exists():
            return {}
        return dict(re.findall(r'<string id="([^"]+)">([^<]*)</string>', path.read_text()))

    @property
    def keys(self) -> list[str]:
        return list(self._entries)

    def default(self, key: str) -> int:
        return self._entries[key]["defaultValue"]

    def defaults(self) -> "OrderedDict[str, int]":
        return OrderedDict((key, self.default(key)) for key in self._entries)

    def validate(self, key: str, value: int) -> None:
        entry = self._entries.get(key)
        if entry is None:
            raise SettingsError(f"unknown setting {key!r}; known: {', '.join(self.keys)}")
        if entry["valueType"] != "number":
            raise SettingsError(
                f"{key} is a {entry['valueType']}; only whole-number settings are supported"
            )
        options = entry.get("configOptions")
        if options:
            allowed = [option["value"] for option in options]
            if value not in allowed:
                labels = ", ".join(
                    f"{option['value']}={self.label(key, option['value'])}" for option in options
                )
                raise SettingsError(f"{key}={value} is not one of: {labels}")
            return
        low, high = entry.get("configMin"), entry.get("configMax")
        if low is not None and value < low:
            raise SettingsError(f"{key}={value} is below the minimum {low}")
        if high is not None and value > high:
            raise SettingsError(f"{key}={value} is above the maximum {high}")

    def label(self, key: str, value: int) -> str:
        """The human label for a value, e.g. ``handBacking=1`` -> ``White``."""
        entry = self._entries.get(key)
        if entry is None:
            return str(value)
        for option in entry.get("configOptions") or []:
            if option["value"] == value:
                return self._strings.get(option["display"], option["display"])
        return str(value)

    def title(self, key: str) -> str:
        entry = self._entries.get(key, {})
        resource = entry.get("configTitle")
        return self._strings.get(resource, resource or key)


def read(root: Path, prg: str = DEFAULT_PRG) -> "OrderedDict[str, int]":
    """Whatever is actually persisted. Empty when the app has never stored anything."""
    path = paths.settings_file(root, prg)
    if not path.exists():
        return OrderedDict()
    return setfile.decode(path.read_bytes())


def describe(root: Path, schema: Schema, prg: str = DEFAULT_PRG) -> list[dict]:
    """Every setting, saying whether the value is persisted or falling back to a default.

    The distinction matters: a *persisted* value is the one that wins, and it is the one
    an edit to ``properties.xml`` cannot override.
    """
    stored = read(root, prg)
    rows = []
    for key in schema.keys:
        persisted = key in stored
        value = stored[key] if persisted else schema.default(key)
        rows.append(
            {
                "key": key,
                "title": schema.title(key),
                "value": value,
                "label": schema.label(key, value),
                "persisted": persisted,
            }
        )
    for key, value in stored.items():  # anything the schema no longer knows about
        if key not in schema.keys:
            rows.append(
                {"key": key, "title": key, "value": value, "label": str(value),
                 "persisted": True, "unknown": True}
            )
    return rows


def write(root: Path, updates: dict[str, int], schema: Schema,
          prg: str = DEFAULT_PRG) -> "OrderedDict[str, int]":
    """Validate and persist ``updates``, keeping every other stored value as it was.

    The caller must have stopped the app first: a running app can flush its in-memory
    properties back over this file when it terminates, silently reverting the write.
    """
    for key, value in updates.items():
        schema.validate(key, value)

    values = read(root, prg) or schema.defaults()
    values.update(updates)

    path = paths.settings_file(root, prg)
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    temporary = path.with_suffix(".SET.tmp")
    temporary.write_bytes(setfile.encode(values))
    os.chmod(temporary, mode)
    os.replace(temporary, path)  # atomic, so a reader never sees a half-written file
    return values


def reset(root: Path, prg: str = DEFAULT_PRG) -> bool:
    """Forget every persisted value — the scriptable *Reset All App Data* for settings."""
    path = paths.settings_file(root, prg)
    if not path.exists():
        return False
    path.unlink()
    return True


def _parse_assignment(text: str) -> tuple[str, int]:
    if "=" not in text:
        raise SettingsError(f"expected key=value, got {text!r}")
    key, _, raw = text.partition("=")
    try:
        return key.strip(), int(raw)
    except ValueError:
        raise SettingsError(f"{text!r}: value must be a whole number") from None


def main(argv: list[str] | None = None) -> int:
    # Shared as a parent so --tmpdir works either side of the subcommand.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--tmpdir", help="instance TMPDIR (default: the shared simulator)")
    common.add_argument("--prg", default=DEFAULT_PRG)
    common.add_argument("--json", action="store_true", help="machine-readable output")

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0], parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("get", help="show every setting and whether it is persisted",
                   parents=[common])
    setter = sub.add_parser("set", help="persist one or more key=value settings",
                            parents=[common])
    setter.add_argument("assignments", nargs="+")
    sub.add_parser("reset", help="delete the persisted settings file", parents=[common])

    args = parser.parse_args(argv)
    root = paths.root_for(args.tmpdir)

    try:
        if args.command == "reset":
            removed = reset(root, args.prg)
            print("cleared persisted settings" if removed else "nothing was persisted")
            return 0

        schema = Schema.load(prg=args.prg)
        if args.command == "set":
            updates = dict(_parse_assignment(text) for text in args.assignments)
            write(root, updates, schema, args.prg)

        rows = describe(root, schema, args.prg)
        if args.json:
            print(json.dumps(rows, indent=2))
        else:
            width = max(len(row["key"]) for row in rows)
            for row in rows:
                origin = "persisted" if row["persisted"] else "default"
                print(f"{row['key']:<{width}}  {row['value']}  {row['label']:<16} ({origin})")
        return 0
    except (SettingsError, setfile.SetFileError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
