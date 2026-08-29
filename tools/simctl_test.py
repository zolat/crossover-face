"""Tests for the simulator control modules.

The settings codec is the piece worth pinning hardest: it writes a file the simulator
reads, so a mistake here shows up as the face rendering the wrong thing, which looks
like a rendering bug rather than a tooling one. ``tools/testdata/CROSSOVERFACE.SET`` is
a real file taken from the simulator, and the round-trip test asserts *byte* equality
rather than value equality — that is what proves nothing in the format is being guessed.
"""

import importlib
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from collections import OrderedDict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from simctl import instance as instances
from simctl import paths, setfile
from simctl import lock as simctl_lock
from simctl.runner import Runner, parse_tests, read_crash
from simctl.settings import Schema, SettingsError, describe, read, reset, write

FIXTURE = Path(__file__).resolve().parent / "testdata" / "CROSSOVERFACE.SET"

# A stand-in for bin/CrossoverFace-settings.json, so these tests do not need a build.
SCHEMA_ENTRIES = [
    {
        "key": "handBacking", "valueType": "number", "defaultValue": 0,
        "configTitle": "BackingTitle", "configType": "list",
        "configOptions": [
            {"display": "BackingOff", "value": 0},
            {"display": "BackingWhite", "value": 1},
        ],
        "configMin": None, "configMax": None,
    },
    {
        "key": "ring1", "valueType": "number", "defaultValue": 0,
        "configTitle": "RingTitle", "configType": "number",
        "configOptions": None, "configMin": 0, "configMax": 7,
    },
]
SCHEMA_STRINGS = {"BackingOff": "Off", "BackingWhite": "White", "BackingTitle": "Behind hands"}


def schema() -> Schema:
    return Schema(SCHEMA_ENTRIES, SCHEMA_STRINGS)


class SetFileCodec(unittest.TestCase):
    def test_round_trips_a_real_file_byte_for_byte(self):
        original = FIXTURE.read_bytes()
        self.assertEqual(setfile.encode(setfile.decode(original)), original)

    def test_decodes_the_faces_seven_properties(self):
        values = setfile.decode(FIXTURE.read_bytes())
        self.assertEqual(
            set(values),
            {"ring1", "ring2", "ring3", "ring4", "alwaysOnFill", "dotRotation", "handBacking"},
        )
        self.assertTrue(all(isinstance(value, int) for value in values.values()))

    def test_key_order_survives_so_encoding_is_deterministic(self):
        values = OrderedDict([("bravo", 2), ("alpha", 1)])
        self.assertEqual(list(setfile.decode(setfile.encode(values))), ["bravo", "alpha"])

    def test_offsets_are_recomputed_for_differing_name_lengths(self):
        # Keys are referenced by byte offset, so a long name must not shift a later one.
        values = OrderedDict([("a", 1), ("averyverylongname", 2), ("b", 3)])
        self.assertEqual(setfile.decode(setfile.encode(values)), values)

    def test_rejects_a_file_that_is_not_a_settings_file(self):
        with self.assertRaises(setfile.SetFileError):
            setfile.decode(b"not a settings file at all")

    def test_rejects_truncation_rather_than_returning_partial_values(self):
        data = FIXTURE.read_bytes()
        with self.assertRaises(setfile.SetFileError):
            setfile.decode(data[: len(data) - 4])

    def test_rejects_an_unsupported_value_type_instead_of_dropping_the_key(self):
        data = bytearray(FIXTURE.read_bytes())
        keys_length = struct.unpack_from(">I", data, 4)[0]
        first_entry = 8 + keys_length + 13
        data[first_entry + 5] = 0x02  # some type this codec does not handle
        with self.assertRaises(setfile.SetFileError):
            setfile.decode(bytes(data))

    def test_refuses_to_store_a_boolean_as_a_number(self):
        with self.assertRaises(setfile.SetFileError):
            setfile.encode(OrderedDict([("handBacking", True)]))


class SchemaValidation(unittest.TestCase):
    def test_rejects_a_value_outside_the_list(self):
        with self.assertRaises(SettingsError):
            schema().validate("handBacking", 9)

    def test_rejects_an_unknown_key(self):
        with self.assertRaises(SettingsError):
            schema().validate("noSuchSetting", 0)

    def test_enforces_numeric_bounds_when_there_is_no_list(self):
        schema().validate("ring1", 7)
        with self.assertRaises(SettingsError):
            schema().validate("ring1", 8)

    def test_resolves_labels_through_the_string_resources(self):
        self.assertEqual(schema().label("handBacking", 1), "White")
        self.assertEqual(schema().title("handBacking"), "Behind hands")

    def test_missing_schema_is_an_error_naming_the_fix(self):
        with self.assertRaises(SettingsError) as caught:
            Schema.load(repo=Path(tempfile.gettempdir()) / "definitely-not-a-checkout")
        self.assertIn("make build", str(caught.exception))


class SettingsOnDisk(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = paths.root_for(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def test_write_then_read_returns_the_value(self):
        write(self.root, {"handBacking": 1}, schema())
        self.assertEqual(read(self.root)["handBacking"], 1)

    def test_writing_one_setting_leaves_the_others_alone(self):
        write(self.root, {"handBacking": 1, "ring1": 5}, schema())
        write(self.root, {"handBacking": 0}, schema())
        self.assertEqual(read(self.root)["ring1"], 5)

    def test_an_invalid_value_writes_nothing_at_all(self):
        write(self.root, {"handBacking": 1}, schema())
        with self.assertRaises(SettingsError):
            write(self.root, {"handBacking": 0, "ring1": 99}, schema())
        # The valid half of the batch must not have landed either.
        self.assertEqual(read(self.root)["handBacking"], 1)

    def test_reset_removes_the_file_and_is_safe_to_repeat(self):
        write(self.root, {"handBacking": 1}, schema())
        self.assertTrue(reset(self.root))
        self.assertFalse(reset(self.root))
        self.assertEqual(read(self.root), {})

    def test_describe_distinguishes_persisted_from_default(self):
        write(self.root, {"handBacking": 1}, schema())
        rows = {row["key"]: row for row in describe(self.root, schema())}
        self.assertTrue(rows["handBacking"]["persisted"])
        self.assertEqual(rows["handBacking"]["label"], "White")

    def test_describe_reports_defaults_when_nothing_is_persisted(self):
        rows = {row["key"]: row for row in describe(self.root, schema())}
        self.assertFalse(rows["handBacking"]["persisted"])
        self.assertEqual(rows["handBacking"]["value"], 0)


class TestOutputParsing(unittest.TestCase):
    """monkeydo's exit status is not a verdict, so the summary line has to be."""

    PASSING = (
        "RESULTS\nTest:                Status:\n"
        "MatrixTest.alpha     PASS\nMatrixTest.beta      PASS\n"
        "Ran 2 tests\n\nPASSED (passed=2, failed=0, errors=0)\n"
    )

    def test_reads_the_counts_and_the_verdict(self):
        report = parse_tests(self.PASSING)
        self.assertEqual((report.ran, report.passed, report.failures), (2, True, 0))
        self.assertTrue(report.ok)

    def test_lists_the_individual_tests(self):
        self.assertEqual([t["name"] for t in parse_tests(self.PASSING).tests],
                         ["MatrixTest.alpha", "MatrixTest.beta"])

    def test_accepts_both_summary_shapes_seen_across_sdk_versions(self):
        old = parse_tests("Ran 3 tests\nPASSED (failures=0, errors=0)")
        new = parse_tests("Ran 3 tests\nPASSED (passed=3, failed=0, errors=0)")
        self.assertTrue(old.passed and new.passed)

    def test_counts_failures(self):
        report = parse_tests("Ran 3 tests\nFAILED (passed=1, failed=2, errors=0)")
        self.assertEqual((report.passed, report.failures), (False, 2))
        self.assertFalse(report.ok)

    def test_no_ran_line_is_contention_not_a_failing_test(self):
        # The trap this exists for: a killed run prints nothing and reads as a failure.
        report = parse_tests("TESTS FAILED")
        self.assertTrue(report.contention)
        self.assertFalse(report.ok)

    def test_a_completed_failing_run_is_not_called_contention(self):
        self.assertFalse(parse_tests("Ran 3 tests\nFAILED (passed=2, failed=1, errors=0)").contention)


class CrashLog(unittest.TestCase):
    LOG = ("Error: Watchdog Tripped\n"
           "Time: 2026-08-29\n"
           "Stack: \n"
           "  - pc: 0x10002bb0\n"
           "    File: 'MatrixRenderer'\n"
           "    Line: 118\n"
           "    Function: draw\n")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = paths.root_for(self.temporary.name)
        self.log = paths.crash_log(self.root)
        self.log.parent.mkdir(parents=True, exist_ok=True)
        self.log.write_text(self.LOG)

    def test_reads_the_error_and_stack(self):
        crash = read_crash(self.root)
        self.assertEqual(crash["error"], "Watchdog Tripped")
        self.assertEqual(crash["stack"][0],
                         {"file": "MatrixRenderer", "line": 118, "function": "draw"})

    def test_ignores_a_crash_older_than_the_run(self):
        # The log survives between runs, so a stale crash must not be blamed on new code.
        future = self.log.stat().st_mtime + 60
        self.assertIsNone(read_crash(self.root, newer_than=future))

    def test_reports_a_crash_from_this_run(self):
        self.assertIsNotNone(read_crash(self.root, newer_than=self.log.stat().st_mtime - 60))

    def test_no_log_is_not_a_crash(self):
        self.log.unlink()
        self.assertIsNone(read_crash(self.root))


class LockReentrancy(unittest.TestCase):
    """A long-lived server must be able to hold the lock across several operations."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.previous = os.environ.get("CROSSOVER_SIM_LOCK")
        os.environ["CROSSOVER_SIM_LOCK"] = str(Path(self.temporary.name) / "lock")
        importlib.reload(simctl_lock)
        self.addCleanup(self._restore)

    def _restore(self):
        if self.previous is None:
            os.environ.pop("CROSSOVER_SIM_LOCK", None)
        else:
            os.environ["CROSSOVER_SIM_LOCK"] = self.previous
        importlib.reload(simctl_lock)

    def test_acquiring_twice_does_not_block_on_ourselves(self):
        lock = simctl_lock.SimulatorLock()
        self.assertTrue(lock.acquire(timeout=3))
        self.assertTrue(lock.held_by_us())
        # Without the re-entrancy check this waits out the full timeout and fails.
        self.assertTrue(lock.acquire(timeout=3))
        lock.release()
        self.assertIsNone(lock.holder())

    def test_release_is_safe_when_we_never_held_it(self):
        simctl_lock.SimulatorLock().release()

    def test_a_foreign_holder_is_not_ours(self):
        lock = simctl_lock.SimulatorLock()
        lock.acquire(timeout=3)
        other = simctl_lock.SimulatorLock(owner=lock.owner + 1)
        self.assertFalse(other.held_by_us())
        lock.release()


class InstanceNaming(unittest.TestCase):
    def test_each_checkout_gets_its_own_deterministic_port(self):
        first = instances.isolated("alpha").port
        self.assertEqual(first, instances.isolated("alpha").port)  # stable
        self.assertNotEqual(first, instances.isolated("bravo").port)

    def test_ports_avoid_the_sdk_scan_range(self):
        # monkeydo probes 1234-1238 and takes the first answer, so an isolated instance
        # inside that range could be found by a session that knows nothing about it.
        for name in ("alpha", "bravo", "charlie", "delta"):
            self.assertGreater(instances.isolated(name).port, 1238)

    def test_shared_is_not_isolated_and_uses_the_default_port(self):
        shared = instances.shared()
        self.assertFalse(shared.isolated)
        self.assertEqual(shared.port, instances.SHARED_PORT)

    def test_resolve_selects_shared_by_name(self):
        self.assertFalse(instances.resolve("shared").isolated)
        self.assertTrue(instances.resolve(None).isolated)

    def test_isolated_instances_have_separate_device_filesystems(self):
        self.assertNotEqual(instances.isolated("alpha").root, instances.isolated("bravo").root)


class SharedModeLocking(unittest.TestCase):
    """The shared simulator is driven through make, which takes the lock itself.

    A long-lived server that already holds the lock must tell the recipe not to take it
    again. Without that, `sim_load` followed by `sim_test` has the recipe wait on a lock
    held by its own caller — a full-timeout stall that then parses as contention, i.e.
    blamed on another session.
    """

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.lock_dir = Path(self.temporary.name) / "lock"
        self.previous = os.environ.get("CROSSOVER_SIM_LOCK")
        os.environ["CROSSOVER_SIM_LOCK"] = str(self.lock_dir)
        self.addCleanup(self._restore)
        self.runner = Runner(instances.shared())
        self.runner.lock.lock_dir = self.lock_dir

    def _restore(self):
        if self.runner.lock.held_by_us():
            self.runner.lock.release()
        if self.previous is None:
            os.environ.pop("CROSSOVER_SIM_LOCK", None)
        else:
            os.environ["CROSSOVER_SIM_LOCK"] = self.previous

    def test_a_lock_we_hold_would_block_the_make_recipe(self):
        # The failure being designed around, proved rather than assumed.
        self.assertTrue(self.runner.lock.acquire(timeout=3))
        result = subprocess.run(
            [str(self.runner.lock.script), "acquire", "999999"],
            capture_output=True, text=True,
            env={**os.environ, "CROSSOVER_SIM_LOCK_WAIT": "2"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("still holds", result.stderr)

    def test_holding_the_lock_tells_make_not_to_take_it(self):
        self.assertEqual(self.runner._make_overrides(), [])
        self.runner.lock.acquire(timeout=3)
        self.assertIn("SIM_LOCK=true", self.runner._make_overrides())

    def test_an_isolated_run_never_touches_the_shared_lock(self):
        overrides = Runner(instances.isolated("alpha"))._make_overrides()
        self.assertIn("SIM_LOCK=true", overrides)
        self.assertIsNone(Runner(instances.isolated("alpha")).lock)

    def test_shared_mode_has_a_lock_and_isolated_does_not(self):
        self.assertIsNotNone(Runner(instances.shared()).lock)
        self.assertIsNone(Runner(instances.isolated("bravo")).lock)


if __name__ == "__main__":
    unittest.main(verbosity=2)
