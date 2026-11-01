# Classic Loot Log — OctoWoW

**Version 1.3.0** targets **OctoWoW's WoW 1.12.1 / Lua 5.0 client** (`Interface: 11200`). It provides an English interface using the original WoW dialog background, decorative border, gold headings and standard buttons.

**[Download ClassicLootLog-1.3.0-OctoWoW.zip](downloads/ClassicLootLog-1.3.0-OctoWoW.zip?raw=true)**

## Install or update

1. Exit WoW completely.
2. Extract the download into your **OctoWoW game folder's `Interface/AddOns/`** directory.
3. Check that the final path is `Interface/AddOns/ClassicLootLog/ClassicLootLog.toc`. Avoid an extra nested addon folder.
4. When updating, replace the previous `ClassicLootLog` addon folder. Do not delete your `WTF` folder; that is where your saved data lives.
5. Enable **Classic Loot Log** in the character-selection AddOns menu, enter the game and type `/cll`.

If you download the entire repository through **Code → Download ZIP**, copy only its `ClassicLootLog` folder to `Interface/AddOns`.

## Install through Octo Launcher for automatic updates

A manual ZIP install has no Git remote, so it cannot by itself supply the launcher's **Addon is up to date** check. That status compares the installed Git checkout with its remote branch; it is separate from the `Version` line in the TOC.

Use **OctoLauncher → Addons → Install Addon** and paste:

```text
https://github.com/Haraldprins67/Test-plugin
```

The repository now includes the root `Test-plugin.toc` expected for the `Test-plugin` folder that this Git URL produces. It loads the same addon sources as the manual ZIP and retains the displayed title **Classic Loot Log**. Leave the launcher's `.git` data intact and avoid editing its tracked files if you want automatic update checks. Actual launcher status still depends on your installed launcher and its network access.

**Switching from a manual install:** exit WoW first. Keep a backup of your existing addon and saved data. Disable the old `ClassicLootLog` addon in the game AddOns list and use only the launcher-installed `Test-plugin` copy. Because WoW names saved-data files after the addon folder, the launcher copy saves to `Test-plugin.lua` instead of `ClassicLootLog.lua`. To preserve your previous history, while WoW is closed, copy your character's `SavedVariables/ClassicLootLog.lua` to `SavedVariables/Test-plugin.lua`. Keep the original as a backup; do not overwrite an existing `Test-plugin.lua` with its own history without preserving that file first. Manual ZIP updates continue to use `ClassicLootLog.lua` and need no data-file rename.

This package targets OctoWoW, rather than the official modern Classic Era client. Optional newer API paths remain regression-tested, but the packaged interface version is deliberately `11200`.

## Compatibility fix

The earlier 1.1.0 package targeted Blizzard's modern Classic Era API and Lua 5.1. It could fail immediately on OctoWoW with:

```text
Core.lua:1: unexpected symbol near '...'
```

Version 1.2.1 removes the unsupported `SetObeyStepOnDrag` slider call entirely. Legacy client detection also checks the available loot APIs, so a custom/newer display version or a GUID backport does not select incompatible functions. This fixes the reported `Main.lua:286` startup error on modified OctoWoW clients.

Version 1.2.1 uses Lua 5.0 syntax throughout the addon files, a shared namespace that does not rely on chunk arguments, old-style event globals, legacy loot APIs, and a frame-based timer fallback. OctoWoW's optional GUID return from `UnitExists(unit)` is used when available; no Nampower installation is required by this addon.

## Controls

| Control | Action |
| --- | --- |
| **Reset** | Asks for confirmation, then clears loot, mob counts, disenchant marks and elapsed time. A running stopwatch restarts at zero. |
| **Export log** | Shows copyable TSV text. Choose **Loot entries** or **Statistics**, copy with Ctrl+A and Ctrl+C, and save outside WoW as `.txt` or `.tsv`. |
| **Timer: ON / OFF** | Starts, pauses or resumes the stopwatch. Paused and offline time are excluded. |
| **Lower-right corner grip** | Drag to resize the main window. Column widths and the number of visible rows adapt to the available space. |
| **Auto text: ON / OFF** | Scale the interface text with the window width, or keep the normal font size while the layout reflows. |
| **Size: LOCKED / UNLOCKED** | Lock or unlock mouse resizing. Window size and both preferences are saved per character. |
| **Item shares / Loot list** | Switches between individual loot entries and totals grouped by item ID. Disenchant materials appear separately. |
| **Disenchanted +1** | Select an original loot entry, then mark one unit as disenchanted. |
| **Undo DE -1** | Removes one disenchant mark from the selected entry. |

The list records loot while the window is hidden and while the timer is paused. Hover over an item to view its tooltip; Shift-click inserts its link into chat. Scroll to see older records.

| Command | Action |
| --- | --- |
| `/cll` or `/lootlog` | Toggle the window |
| `/cll show` / `/cll hide` | Show / hide the window |
| `/cll stats` | Show item shares |
| `/cll reset` | Open reset confirmation |
| `/cll log` | Open the export window |
| `/cll timer` | Toggle the stopwatch |
| `/cll timer on` / `/cll timer off` | Start/resume or pause the stopwatch |
| `/cll scale on` / `/cll scale off` | Enable/disable automatic text scaling |
| `/cll lock on` / `/cll lock off` | Lock/unlock resizing |
| `/cll price 2589 13` | Set item 2589's vendor price to 13 copper per unit (example manual value) |
| `/cll price 2589 clear` | Remove that cached/manual price and resume automatic lookup |
| `/cll epic on` / `/cll epic off` | Enable/disable purple epic-drop alerts |
| `/cll sound on` / `/cll sound off` | Enable/disable the optional alert sound |

## Resizing and automatic text

Drag the small lower-right grip while **Size: UNLOCKED** is selected. The main window supports widths from 680 to 1280 and heights from 430 to 900 UI units. The layout shows more rows in taller windows and rearranges the column widths; these are genuine layout changes rather than stretching the entire frame.

With **Auto text: ON**, text scales from 80% to 130% of its original size based on the window width. **Auto text: OFF** preserves the original font size while columns and rows continue to adapt. Locking size hides the drag grip. Reset clears the farming session but preserves window preferences, price overrides and notification settings. The separate copy/export dialog retains its fixed size.

## Vendor value

The **Vendor** column estimates the remaining vendor value of each observed item entry. A known zero price displays `0c`; an unavailable price displays **Unknown**. Money and currencies display `-`. Values use gold/silver/copper, and the log export includes unit copper price, remaining copper value and remaining quantity. The Statistics export includes a known-value total and the number of remaining units whose price is unknown.

Vanilla's standard `GetItemInfo` does not normally supply a sell price. Automatic prices are used only if the client supplies the sell-price return or an installed price library exposes `GetSellValue(itemID)`. There is no mandatory price-addon dependency and no guessed price table. A merchant's purchase price is never substituted for the amount you receive by selling.

For a missing price, set a known value with `/cll price <item ID> <copper per unit>`. Item IDs are present in exported item-link data. For example, `/cll price 15210 500` sets your chosen price for item 15210 to 5 silver; this is a command example, not a verified database price. Clear an override with `/cll price 15210 clear`. Prices are cached per character.

A disenchanted original contributes only its undestroyed units; the resulting materials contribute separately. Historical item-share percentages continue to use original quantities. Vendor figures are estimates for the observed loot history, **not current bag contents**: selling, trading or discarding items outside the tracked DE process does not reduce this estimate.

## Purple epic-drop alerts

New original drops of **epic quality (purple, quality 4)** produce a purple on-screen **EPIC LOOT** notice and a chat message. The alert includes the item link and quantity. The optional sound starts disabled; use `/cll sound on` to enable it. Toggle notifications with `/cll epic on` or `/cll epic off`.

Reopening the same recorded loot, loading saved history, and disenchant materials do not replay epic-drop alerts. Rare blue items and legendary orange items are outside this purple-only setting. An alert means the item was newly observed in your loot window; you do not have to take it first.

## What is recorded?

Loot is recorded when your own loot window opens, whether or not you take the item. Items, money and currencies exposed by the client are kept in the log. Unopened corpses and loot visible only to other players are not available to the addon. This is not an inventory tracker or a record of which party member received each item.

When loot-source GUIDs or OctoWoW's targeted-corpse GUID are available, reopening or partially looting the same corpse is deduplicated. Without a stable source ID, deduplication is limited to the current loot window; reopening may add another entry. Resetting intentionally clears this history.

Incomplete item data is retried up to five times while the loot window remains open. Auto-loot can remove an item before its data arrives, and incomplete snapshots of identical stacks can undercount. Removed data cannot be reconstructed afterwards.

## Mob counter and mobs per hour

The counter includes your kills, pet kills and group/raid kills that your client observes. It does not count every nearby death.

On OctoWoW, legacy combat messages are matched against the client's damage/death templates and your party/raid names. Observed participation is followed by a death message, or a personal/group kill message directly identifies the kill. Optional target GUIDs improve identification and deduplication. Pets and group targets are included when their names or GUIDs are available.

Old combat messages do not provide the same structured identifiers as modern WoW. Without a GUID, simultaneous mobs with the same name can be ambiguous, some group kills can be missed, and a PvP target absent from the available unit tokens cannot always be distinguished by name alone. Combat-log range also limits what can be observed. The counter should therefore be treated as an observed-session statistic, not a guaranteed server-wide count. Participation expires after 30 minutes, and tracking of surviving mobs restarts after `/reload`.

**Mobs/hour = kills recorded with the timer ON × 3600 / active stopwatch seconds.** The total counter still increases while paused, but paused kills and paused time do not enter the hourly rate. Zero measured time produces zero. This is an average for the session, not a rolling last-hour statistic.

## Item shares

**Item share = units of that item / all original dropped item units × 100.** For example, 10 cloth and 5 swords means 66.7% cloth and 33.3% swords. Stack quantities count; the number of log rows does not. Link variations with the same item ID are grouped together.

Money, currencies and disenchant results are excluded from the original-drop denominator. A sword remains an original sword drop after disenchanting, so destroying it does not change the historical drop percentages. These percentages are not drop chance per mob, current inventory proportions or gold value.

Disenchant materials appear separately. The Statistics export also reports the distribution within those materials.

## Disenchanting

Your own **Disenchant** casts are tracked through the client-specific spell events. On the old English client, this uses the spell name, cast duration, completion/interruption messages and bag changes. Materials in the associated loot window are labelled **DE material** and do not inflate original-drop percentages. Failed or interrupted casts do not mark an original item.

A before/after bag comparison attempts to identify the consumed original. Exactly one removed item can mark the newest eligible logged entry with that item ID. The original row and quantity remain intact; **DE: 1** means one unit was disenchanted. Materials can still be recorded when the original was never in the log.

If bag data is missing, more than one item disappears, or the cast start was missed, the addon does not guess the original. Select the relevant loot entry and use **Disenchanted +1** or **Undo DE -1**. Multiple identical originals can require manual correction because an item ID does not uniquely identify its earlier drop source.

Disenchanting by another player is not automatically linked to your recorded originals. You can mark the original manually; automatic material classification requires your own observed cast and its loot window. The addon never performs disenchant actions.

## Log files and saved data

Standard WoW addon APIs cannot write an arbitrary text file. Use **Export log** to copy the text into an external editor. Loot entries include date/time, session time, type, item, quantity, quality, source, item-link data, origin (`drop` or `disenchant`) and disenchant count. Export order is oldest first; embedded tabs and line breaks are escaped.

On logout or `/reload`, WoW writes the per-character database to:

```text
WTF/Account/<account>/<realm>/<character>/SavedVariables/ClassicLootLog.lua
```

Loot, mob counts, timer state and DE marks survive between sessions. Edit saved files only while WoW is closed. A crash can lose changes made since the last save. Existing version 1.x records are preserved during migration.

There is no fixed history limit. Export and reset periodically during long sessions to keep memory and file size manageable. Money uses the text reported by the loot window; its quantity column is not guaranteed to represent copper.

## Development and validation

WoW loads `Compat.lua`, `Core.lua`, `Tracking.lua`, `Value.lua` and `Main.lua` in that order. The manual and launcher TOCs reference the same files. No build or runtime dependencies are needed by the addon. Use the existing checkout in cloud tasks; they are already isolated and do not need extra Git worktrees.

The Python test runner uses Lupa for Lua 5.1 regression tests:

```sh
cd Test-plugin
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
.venv/bin/python tests/run.py
```

For OctoWoW compatibility, additionally run with an actual **Lua 5.0** interpreter:

```sh
.venv/bin/python tests/run.py --lua50 /path/to/lua5.0
```

That command parses every addon file with Lua 5.0 and executes the compatible core, adapter, legacy tracking and strict Vanilla UI suites. The Vanilla mocks deliberately omit modern APIs and pass event arguments through `this`, `event` and `arg1` globals. They exercise both addon folder identities, resizing, text scaling, price lookup and epic notices. A distribution check validates both TOC entry points. Tests cover the reported startup error, fourth-return loot quality, English labels, classic frame style, timer fallback, item shares, kill tracking, DE and export. These checks do not replace validation inside the real OctoWoW client.

A minimal package can be created with:

```sh
mkdir -p dist
python3 -m zipfile -c dist/ClassicLootLog.zip ClassicLootLog
```

In-game checks: open `/cll`, loot items and coins, reopen a partial corpse, pause/resume the timer, observe personal/pet/group kills, check item shares, disenchant a logged item, cancel another cast, correct a DE mark, export both views, test tooltips/Shift-click, reload to check persistence, and confirm/cancel reset.

Also test resizing small/large, locking the grip, toggling Auto text, retaining preferences after reload, known/unknown/zero vendor prices, a manual price override, a new purple drop and reopening that same loot without a repeated notice.
