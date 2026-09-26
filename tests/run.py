"""Run the unmodified Lua suite with a local Lua 5.2 runtime (pip install lupa)."""
from pathlib import Path
import os
from lupa.lua52 import LuaRuntime

os.chdir(Path(__file__).resolve().parent.parent)
LuaRuntime().execute(Path('tests/run.lua').read_text())
