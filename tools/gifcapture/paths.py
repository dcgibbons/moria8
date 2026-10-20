"""Shared locations for the gif capture tools."""
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ASSETS = ROOT / "docs" / "assets"
BUILD = ROOT / "build"
# Frame dumps and emulator scratch files go here (under build/, which is gitignored output).
WORK = Path(os.environ.get("GIFCAP_WORK", BUILD / "gifcapture"))
# Directory holding MAME's apple2ee.zip (Apple IIe ROMs are not redistributable).
A2ROMS = os.environ.get("A2ROMS", "")
