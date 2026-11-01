CLASSIC LOOT LOG - LOCAL FILE EXPORTER

Requires Python 3.9 or newer on your computer. The addon itself needs no Python.

1. Keep this tools folder inside your installed addon folder.
2. On Windows, double-click START-LOOTLOG-EXPORTER.cmd and leave its window open.
3. In WoW, open Export log and click Save all, or type /cll save.
4. If the addon says queued, use /reload or log out so WoW saves the report.
5. The helper prints Saved: followed by the final file in your game Lootlogs folder.

The small farming window is opened or closed with /sl.

Filename format: YYYY-MM-DD_HH-MM-SS_Player.txt
Repeated exports receive a suffix. Existing different files are not overwritten.

The helper supports native patch exports in CustomData/imports and queued exports
in this addon's SavedVariables. It never executes Lua, edits saved data, deletes
source files or sends logs over the network. Close its window or press Ctrl+C to stop.

Manual command:
python lootlog_exporter.py --watch --game-dir "C:/Games/Octowow"

Replace --watch with --once to process existing exports once.
