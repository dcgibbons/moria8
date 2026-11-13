#!/usr/bin/env python3
"""Compatibility import for existing C128 harness callers."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from tools.vice_connector import *  # noqa: F401,F403,E402
