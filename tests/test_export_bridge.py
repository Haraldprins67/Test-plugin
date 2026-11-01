"""Filesystem behavior of the optional local Lootlogs helper."""

import base64
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/lootlog_exporter.py"
SPEC = importlib.util.spec_from_file_location("lootlog_exporter", MODULE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = bridge
SPEC.loader.exec_module(bridge)

NAME = "2026-11-01_03-22-15_Testplayer.txt"
REPORT = "Classic Loot Log export\t1.5.0\nLoot\tAll recorded rows\nEnd Classic Loot Log export\n"


class ExportBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.game = Path(self.temporary.name) / "Octowow"
        (self.game / "Interface/AddOns").mkdir(parents=True)

    def source(self, folder="CustomData", name=NAME, report=REPORT, suffix=True):
        target = self.game / folder
        target.mkdir(exist_ok=True)
        actual = name if suffix else name[:-4]
        path = target / ("ClassicLootLog_" + actual)
        path.write_text(report, encoding="utf-8")
        return path

    def saved(self, payload, addon="ClassicLootLog"):
        directory = self.game / "WTF/Account/Example/Realm/Testplayer/SavedVariables"
        directory.mkdir(parents=True, exist_ok=True)
        encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
        path = directory / (addon + ".lua")
        path.write_text('ClassicLootLogDB = { ["pendingFileExports"] = { "CLLEXPORT1:'
                        + encoded + '" } }', encoding="utf-8")
        return path

    def test_native_customdata_and_imports_preserve_complete_logs(self):
        self.source(suffix=False)
        other_name = "2026-11-01_03-22-16_Mélïssa.txt"
        self.source("imports", other_name, REPORT.replace("All recorded", "More recorded"))
        result = bridge.scan_once(self.game)
        self.assertEqual(2, len(result.written))
        self.assertEqual(REPORT, (self.game / "Lootlogs" / NAME).read_text(encoding="utf-8"))
        self.assertTrue((self.game / "Lootlogs" / other_name).is_file())
        self.assertTrue((self.game / "CustomData" / ("ClassicLootLog_" + NAME[:-4])).is_file())

    def test_unchanged_reports_and_duplicate_provider_files_are_idempotent(self):
        self.source()
        self.source("Imports", report=REPORT.replace("\n", "\r\n"))
        first = bridge.scan_once(self.game)
        self.assertEqual(1, len(first.written))
        second = bridge.scan_once(self.game)
        self.assertEqual(0, len(second.written))
        self.assertEqual(2, second.unchanged)
        self.assertEqual([NAME], [p.name for p in (self.game / "Lootlogs").iterdir()])

    def test_existing_different_content_is_preserved_with_stable_collision_suffix(self):
        destination = self.game / "Lootlogs"
        destination.mkdir()
        original = destination / NAME
        original.write_text("Existing user log", encoding="utf-8")
        self.source()
        first = bridge.scan_once(self.game)
        self.assertEqual(NAME[:-4] + "_02.txt", first.written[0].name)
        self.assertEqual("Existing user log", original.read_text(encoding="utf-8"))
        self.assertEqual(0, len(bridge.scan_once(self.game).written))

    def test_queued_savedvariables_are_decoded_without_running_lua(self):
        saved = self.saved(NAME + "\n" + REPORT, "Test-plugin")
        untouched = Path(self.temporary.name) / "must-not-be-created"
        with saved.open("a", encoding="utf-8") as output:
            output.write('\nos.execute("create malicious file")\n')
        before = saved.read_bytes()
        result = bridge.scan_once(self.game)
        self.assertEqual(1, len(result.written))
        self.assertEqual(REPORT, result.written[0].read_text(encoding="utf-8"))
        self.assertFalse(untouched.exists())
        self.assertEqual(before, saved.read_bytes())
        self.assertEqual(0, len(bridge.scan_once(self.game).written))

    def test_other_addon_saved_files_are_never_read(self):
        saved = self.saved(NAME + "\n" + REPORT)
        saved.rename(saved.parent / "OtherAddon.lua")
        self.assertEqual(0, len(bridge.scan_once(self.game).written))

    def test_forged_chat_and_unrelated_table_markers_cannot_request_exports(self):
        saved = self.saved(NAME + "\n" + REPORT)
        token = 'CLLEXPORT1:' + base64.b64encode((NAME + "\n" + REPORT).encode()).decode()
        saved.write_text('ClassicLootLogDB = { ["chat"] = "' + token + '", '
                         + '["groupLoot"] = { ["raw"] = "pendingFileExports = { \\\"'
                         + token + '\\\" }" }, ["unrelated"] = { "' + token + '" }, '
                         + '["longChat"] = [[pendingFileExports = {"' + token + '"}]], '
                         + '-- pendingFileExports = { "' + token + '" }\n}', encoding="utf-8")
        self.assertEqual(0, len(bridge.scan_once(self.game).written))

    def test_malformed_pending_table_is_not_partially_exported(self):
        saved = self.saved(NAME + "\n" + REPORT)
        original = saved.read_text(encoding="utf-8")
        saved.write_text(original.replace('" } }', '", { nested = true } } }'), encoding="utf-8")
        self.assertEqual(0, len(bridge.scan_once(self.game).written))

    def test_indexed_serialized_pending_queue_is_supported(self):
        saved = self.saved(NAME + "\n" + REPORT)
        saved.write_text(saved.read_text(encoding="utf-8").replace('{ "CLLEXPORT1:', '{ [1] = "CLLEXPORT1:'), encoding="utf-8")
        self.assertEqual(1, len(bridge.scan_once(self.game).written))

    def test_incomplete_malformed_and_nonexport_sources_are_skipped(self):
        self.source(report=REPORT.replace("End Classic Loot Log export\n", ""))
        self.saved(NAME + "\n" + "Not a Classic Loot Log export")
        directory = self.game / "CustomData"
        (directory / "Unrelated.txt").write_text(REPORT, encoding="utf-8")
        (directory / ("ClassicLootLog_2026-11-01_03-22-16_Bad.txt")).write_bytes(b"\xff\xfe")
        result = bridge.scan_once(self.game)
        self.assertEqual(0, len(result.written))
        self.assertEqual(3, result.invalid)

    def test_traversal_absolute_and_windows_invalid_names_are_rejected(self):
        for name in ("../escape.txt", "/tmp/escape.txt", "C:\\escape.txt",
                     "2026-11-01_03:22:15_Player.txt", "2026-13-01_03-22-15_Player.txt",
                     "2026-11-01_03-22-15_Bad\x01name.txt", "2026-11-01_03-22-15_.txt"):
            self.assertFalse(bridge.valid_filename(name), name)
        self.saved("../escape.txt\n" + REPORT)
        result = bridge.scan_once(self.game)
        self.assertEqual(0, len(result.written))
        self.assertFalse((self.game / "escape.txt").exists())

    @unittest.skipUnless(hasattr(os, "symlink"), "Requires symlink support")
    def test_destination_symlink_cannot_escape_game_root(self):
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir()
        (self.game / "Lootlogs").symlink_to(outside, target_is_directory=True)
        self.source()
        with self.assertRaises(bridge.UnsafePathError):
            bridge.scan_once(self.game)
        self.assertEqual([], list(outside.iterdir()))

    @unittest.skipUnless(hasattr(os, "symlink"), "Requires symlink support")
    def test_source_and_existing_target_symlinks_are_not_followed(self):
        outside = Path(self.temporary.name) / "outside.txt"
        outside.write_text(REPORT, encoding="utf-8")
        source_dir = self.game / "CustomData"
        source_dir.mkdir()
        (source_dir / ("ClassicLootLog_" + NAME)).symlink_to(outside)
        self.assertEqual(0, len(bridge.scan_once(self.game).written))
        (source_dir / ("ClassicLootLog_" + NAME)).unlink()
        self.source()
        target = self.game / "Lootlogs" / NAME
        target.symlink_to(outside)
        self.assertEqual(0, len(bridge.scan_once(self.game).written))
        self.assertEqual(REPORT, outside.read_text(encoding="utf-8"))

    def test_game_directory_is_found_from_nested_manual_and_launcher_tools(self):
        for relative in ("ClassicLootLog/tools", "Test-plugin/tools", "Test-plugin/ClassicLootLog/tools"):
            tools = self.game / "Interface/AddOns" / relative
            tools.mkdir(parents=True)
            self.assertEqual(self.game, bridge.find_game_directory(tools))
        with self.assertRaises(ValueError):
            bridge.game_directory(self.game / "Interface/AddOns")

    def test_cli_once_reports_only_paths_and_counts(self):
        self.source()
        result = subprocess.run([sys.executable, str(MODULE_PATH), "--once", "--game-dir", str(self.game)],
                                capture_output=True, text=True, check=True)
        self.assertIn("Exported 1 log(s)", result.stdout)
        self.assertNotIn("All recorded rows", result.stdout)


if __name__ == "__main__":
    unittest.main()
