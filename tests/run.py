"""Run the addon's Lua 5.1 tests outside WoW using the pinned Lupa runtime."""

from pathlib import Path
import os
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    sys.exit("Install test dependencies first: python3 -m pip install -r tests/requirements.txt")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    for suite in ("tests/core_spec.lua", "tests/stats_spec.lua", "tests/tracking_spec.lua",
                  "tests/wow_stub_spec.lua"):
        print(f"Running {suite} with Lua 5.1", flush=True)
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.execute(Path(suite).read_text(encoding="utf-8"), name=suite)


if __name__ == "__main__":
    main()
