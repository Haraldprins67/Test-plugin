"""Validate both the manual ZIP entry point and Octo launcher's repository entry point."""

from pathlib import Path

root = Path(__file__).resolve().parents[1]


def toc(path: Path) -> tuple[dict[str, str], list[Path]]:
    metadata = {}
    files = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            key, value = line[3:].split(":", 1)
            metadata[key] = value.strip()
        elif line and not line.startswith("#"):
            resolved = (path.parent / line.replace("\\", "/")).resolve()
            assert resolved.is_relative_to(root), "TOC path escapes repository"
            assert resolved.is_file(), f"Missing TOC target: {line}"
            files.append(resolved)
    return metadata, files


manual_metadata, manual_files = toc(root / "ClassicLootLog/ClassicLootLog.toc")
launcher_metadata, launcher_files = toc(root / "Test-plugin.toc")
assert launcher_metadata == manual_metadata
assert launcher_files == manual_files
assert [path.name for path in manual_files] == [
    "Compat.lua", "Core.lua", "Tracking.lua", "Value.lua", "GroupLoot.lua", "GroupEvents.lua", "LootReceipts.lua",
    "Finance.lua", "Money.lua", "Merchant.lua", "Mini.lua", "FileExport.lua", "SavedLogs.lua",
    "MinimapButton.lua", "LogsPanel.lua", "Main.lua"
]
assert manual_metadata["Interface"] == "11200"
assert manual_metadata["Version"] == "1.8.2"
assert "SellValue" in manual_metadata["OptionalDeps"].split(", ")
assert manual_metadata["SavedVariablesPerCharacter"] == "ClassicLootLogDB"
print("PASS launcher and manual entry points load the same version and addon files")
