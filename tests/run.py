"""Exercise current and Vanilla WoW APIs, with an optional genuine Lua 5.0 run."""

from pathlib import Path
import argparse
import os
import subprocess
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    sys.exit("Install test dependencies first: python3 -m pip install -r tests/requirements.txt")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua50", help="Path to a genuine Lua 5.0 interpreter")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    subprocess.run([sys.executable, "tests/distribution_spec.py"], check=True)
    for suite in ("tests/core_spec.lua", "tests/stats_spec.lua", "tests/tracking_spec.lua",
                  "tests/wow_stub_spec.lua"):
        print(f"Running {suite} with Lua 5.1", flush=True)
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.execute(Path(suite).read_text(encoding="utf-8"), name=suite)

    legacy_suites = (
        "tests/lua50_core_spec.lua",
        "tests/compat_spec.lua",
        "tests/legacy_tracking_spec.lua",
        "tests/loot_receipts_spec.lua",
        "tests/legacy_ui_spec.lua",
        "tests/value_spec.lua",
        "tests/finance_spec.lua",
        "tests/money_spec.lua",
        "tests/merchant_spec.lua",
        "tests/group_loot_spec.lua",
        "tests/group_events_spec.lua",
        "tests/mini_spec.lua",
        "tests/file_export_spec.lua",
        "tests/saved_logs_spec.lua",
        "tests/minimap_spec.lua",
        "tests/logs_panel_spec.lua",
    )
    for suite in legacy_suites:
        print(f"Running {suite} with Lua 5.1", flush=True)
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.execute(Path(suite).read_text(encoding="utf-8"), name=suite)

    if options.lua50:
        subprocess.run(
            [options.lua50, "-e", "assert(string.find(_VERSION, '^Lua 5%.0'), _VERSION)"],
            check=True,
        )
        for source in sorted(Path("ClassicLootLog").glob("*.lua")):
            print(f"Checking Lua 5.0 syntax: {source}", flush=True)
            subprocess.run(
                [options.lua50, "-e", f'assert(loadfile("{source.as_posix()}"))'],
                check=True,
            )
        for suite in legacy_suites:
            print(f"Running {suite} with Lua 5.0", flush=True)
            subprocess.run([options.lua50, suite], check=True)


if __name__ == "__main__":
    main()
