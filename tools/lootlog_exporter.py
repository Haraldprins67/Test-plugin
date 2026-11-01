"""Copy Classic Loot Log exports into a game's Lootlogs folder without running Lua.

Run manually with Python 3.9+: lootlog_exporter.py --watch --game-dir PATH.
The addon can write sandboxed bridge files immediately, or queue an ASCII
payload in SavedVariables which becomes visible after /reload or logout.
"""

from __future__ import annotations

import argparse
import base64
import binascii
from dataclasses import dataclass, field
from datetime import datetime
import os
from pathlib import Path
import re
import sys
import time
from typing import Iterator, Optional


HEADER = "Classic Loot Log export"
FOOTER = "End Classic Loot Log export"
BRIDGE_PREFIX = "ClassicLootLog_"
QUEUE_PAYLOAD = re.compile(r"CLLEXPORT1:([A-Za-z0-9+/=]+)")
FILE_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_(.+)\.txt$")
INVALID_NAME = re.compile(r'[<>:"/\\|?*\x00-\x1f\x7f]')
RESERVED = {"CON", "PRN", "AUX", "NUL"}
RESERVED.update("COM" + str(number) for number in range(1, 10))
RESERVED.update("LPT" + str(number) for number in range(1, 10))


class UnsafePathError(ValueError):
    """A source or destination would escape the intended game directory."""


@dataclass
class ScanResult:
    written: list[Path] = field(default_factory=list)
    unchanged: int = 0
    invalid: int = 0


def game_directory(value: Path) -> Path:
    root = value.expanduser().resolve()
    if not (root / "Interface" / "AddOns").is_dir():
        raise ValueError("The game directory must contain Interface/AddOns.")
    return root


def find_game_directory(start: Optional[Path] = None) -> Path:
    starts = [start] if start is not None else [Path(__file__).parent, Path.cwd()]
    for location in starts:
        candidate = location.expanduser().resolve()
        if candidate.is_file():
            candidate = candidate.parent
        for root in (candidate, *candidate.parents):
            if (root / "Interface" / "AddOns").is_dir():
                return root
    raise ValueError("Game directory not found. Supply --game-dir with your OctoWoW folder.")


def safe_path(root: Path, path: Path) -> None:
    try:
        relative = path.relative_to(root)
    except ValueError as error:
        raise UnsafePathError("Path is outside the game directory.") from error
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise UnsafePathError("Symbolic links are not used for export paths.")
    try:
        path.resolve().relative_to(root)
    except ValueError as error:
        raise UnsafePathError("Resolved path is outside the game directory.") from error


def valid_filename(name: str) -> bool:
    if not name or len(name) > 220 or INVALID_NAME.search(name):
        return False
    if not name.isprintable() or name.endswith((" ", ".")):
        return False
    if name.split(".", 1)[0].upper() in RESERVED:
        return False
    matched = FILE_NAME.fullmatch(name)
    if not matched:
        return False
    try:
        datetime.strptime(matched.group(1), "%Y-%m-%d_%H-%M-%S")
    except ValueError:
        return False
    return bool(matched.group(2))


def complete_report(text: str) -> Optional[bytes]:
    text = text.lstrip("\ufeff").replace("\r\n", "\n")
    if not text.startswith(HEADER) or not text.rstrip().endswith(FOOTER):
        return None
    return text.encode("utf-8")


def read_source(root: Path, path: Path) -> str:
    safe_path(root, path)
    if not path.is_file():
        raise ValueError("Export source is not a regular file.")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(str(path), flags)
    with os.fdopen(descriptor, "rb") as source:
        return source.read().decode("utf-8-sig")


def quoted_value(text: str, start: int) -> tuple[Optional[str], int]:
    """Skip a Lua quoted string without interpreting escapes or Lua code."""
    quote = text[start]
    position = start + 1
    while position < len(text):
        if text[position] == "\\":
            position += 2
        elif text[position] == quote:
            return text[start + 1:position], position + 1
        else:
            position += 1
    return None, len(text)


def long_string_end(text: str, start: int) -> Optional[int]:
    opening = re.match(r"\[(=*)\[", text[start:])
    if not opening:
        return None
    closing = "]" + opening.group(1) + "]"
    end = text.find(closing, start + opening.end())
    return len(text) if end < 0 else end + len(closing)


def skip_space(text: str, position: int) -> int:
    while position < len(text) and text[position].isspace():
        position += 1
    return position


def skip_table(text: str, opening: int) -> int:
    depth, position = 1, opening + 1
    while position < len(text):
        if text[position] in "\"'":
            _, position = quoted_value(text, position)
            continue
        if text.startswith("--", position):
            position = long_string_end(text, position + 2) or text.find("\n", position)
            if position < 0:
                return len(text)
            continue
        end = long_string_end(text, position)
        if end is not None:
            position = end
            continue
        if text[position] == "{":
            depth += 1
        elif text[position] == "}":
            depth -= 1
            if depth == 0:
                return position + 1
        position += 1
    return len(text)


def queue_values(text: str, opening: int) -> Optional[list[str]]:
    """Accept only the addon's flat array of quoted ASCII export markers."""
    values = []
    position = skip_space(text, opening + 1)
    while position < len(text):
        if text[position] == "}":
            return values
        indexed = re.match(r"\[\s*[1-9][0-9]*\s*\]\s*=\s*", text[position:])
        if indexed:
            position += indexed.end()
        if position >= len(text) or text[position] not in "\"'":
            return None
        value, position = quoted_value(text, position)
        matched = QUEUE_PAYLOAD.fullmatch(value or "")
        if not matched:
            return None
        values.append(matched.group(1))
        position = skip_space(text, position)
        if position >= len(text):
            return None
        if text[position] == "}":
            return values
        if text[position] not in ",;":
            return None
        position = skip_space(text, position + 1)
    return None


def pending_payloads(text: str) -> Iterator[str]:
    """Read pendingFileExports tables only; chat strings cannot forge exports."""
    position = 0
    while position < len(text):
        if text.startswith("--", position):
            position = long_string_end(text, position + 2) or text.find("\n", position)
            if position < 0:
                return
            continue
        end = long_string_end(text, position)
        if end is not None:
            position = end
            continue
        value = None
        key_end = position
        if text[position] in "\"'":
            value, key_end = quoted_value(text, position)
            previous = position - 1
            while previous >= 0 and text[previous].isspace():
                previous -= 1
            if previous < 0 or text[previous] != "[":
                value = None
            following = skip_space(text, key_end)
            if following < len(text) and text[following] == "]":
                key_end = following + 1
            else:
                value = None
            position = max(position + 1, key_end)
        elif text[position].isalpha() or text[position] == "_":
            matched = re.match(r"[A-Za-z_][A-Za-z_0-9]*", text[position:])
            if matched:
                value = matched.group()
                position += matched.end()
                key_end = position
            else:
                position += 1
        else:
            position += 1
        if value != "pendingFileExports":
            continue
        following = skip_space(text, key_end)
        if following >= len(text) or text[following] != "=":
            continue
        opening = skip_space(text, following + 1)
        if opening >= len(text) or text[opening] != "{":
            continue
        values = queue_values(text, opening)
        position = skip_table(text, opening)
        if values is not None:
            yield from values


def native_sources(root: Path) -> Iterator[Path]:
    seen = set()
    for name in ("CustomData", "imports", "Imports"):
        folder = root / name
        if not folder.is_dir():
            continue
        safe_path(root, folder)
        identity = os.path.normcase(str(folder.resolve()))
        if identity in seen:
            continue
        seen.add(identity)
        for path in sorted(folder.iterdir()):
            if path.name.startswith(BRIDGE_PREFIX):
                yield path


def saved_variable_sources(root: Path) -> Iterator[Path]:
    accounts = root / "WTF" / "Account"
    if not accounts.is_dir():
        return
    safe_path(root, accounts)
    for name in ("ClassicLootLog.lua", "Test-plugin.lua"):
        for path in sorted(accounts.rglob(name)):
            if path.parent.name == "SavedVariables":
                yield path


def copy_report(root: Path, destination: Path, name: str, payload: bytes) -> Optional[Path]:
    if not valid_filename(name):
        raise ValueError("Invalid export filename.")
    stem = name[:-4]
    number = 1
    while True:
        suffix = "" if number == 1 else "_" + str(number).zfill(2)
        target = destination / (stem + suffix + ".txt")
        safe_path(root, target)
        if target.exists():
            if target.is_file() and target.read_bytes() == payload:
                return None
            number += 1
            continue
        try:
            # Exclusive creation prevents overwriting a changed existing log.
            with target.open("xb") as output:
                output.write(payload)
            return target
        except FileExistsError:
            continue


def scan_once(directory: Path) -> ScanResult:
    root = game_directory(directory)
    destination = root / "Lootlogs"
    safe_path(root, destination)
    destination.mkdir(exist_ok=True)
    if not destination.is_dir():
        raise ValueError("Lootlogs must be a directory.")
    result = ScanResult()

    def save(name: str, text: str) -> None:
        payload = complete_report(text)
        if payload is None or not valid_filename(name):
            result.invalid += 1
            return
        target = copy_report(root, destination, name, payload)
        if target is None:
            result.unchanged += 1
        else:
            result.written.append(target)

    try:
        candidates = list(native_sources(root))
    except (OSError, ValueError):
        candidates = []
        result.invalid += 1
    for path in candidates:
        try:
            name = path.name[len(BRIDGE_PREFIX):]
            if not name.endswith(".txt"):
                name += ".txt"
            save(name, read_source(root, path))
        except (OSError, UnicodeError, ValueError):
            result.invalid += 1

    try:
        saved_sources = list(saved_variable_sources(root))
    except (OSError, ValueError):
        saved_sources = []
        result.invalid += 1
    for path in saved_sources:
        try:
            contents = read_source(root, path)
        except (OSError, UnicodeError, ValueError):
            result.invalid += 1
            continue
        for encoded in pending_payloads(contents):
            try:
                decoded = base64.b64decode(encoded, validate=True).decode("utf-8")
                name, separator, report = decoded.partition("\n")
                if not separator:
                    raise ValueError("Incomplete queued export.")
                save(name, report)
            except (binascii.Error, UnicodeError, ValueError, OSError):
                result.invalid += 1
    return result


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, help="OctoWoW root containing Interface/AddOns")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--once", action="store_true", help="Process available exports once (default)")
    mode.add_argument("--watch", action="store_true", help="Check every second until stopped")
    args = parser.parse_args(argv)
    try:
        root = game_directory(args.game_dir) if args.game_dir else find_game_directory()
        if args.watch:
            print("Watching Classic Loot Log exports. Destination: " + str(root / "Lootlogs"), flush=True)
            print("Without a native file patch, use /reload or logout after clicking Save all logs.", flush=True)
        while True:
            result = scan_once(root)
            for path in result.written:
                print("Saved: " + str(path), flush=True)
            if not args.watch:
                print("Exported " + str(len(result.written)) + " log(s); unchanged "
                      + str(result.unchanged) + "; incomplete/invalid " + str(result.invalid) + ".")
                return 0
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nLootlog exporter stopped.")
        return 0
    except (OSError, ValueError) as error:
        print("Lootlog exporter: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
