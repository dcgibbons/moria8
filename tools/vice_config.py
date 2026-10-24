#!/usr/bin/env python3
"""vice_config.py — the VICE config file the test runners and harnesses pass.

VICE reads the file given with ``-config`` instead of the user's vicerc;
``-default +saveres`` then start from defaults and save nothing back. An
empty file (/dev/null) made VICE pop up "No version tag found in config
file" on the desktop for every instance, so the file names the installed
VICE's version, the only thing VICE requires of it.

The file lives under the repository's build directory, one per VICE version:
build/vice/vicerc-<version>. Parallel runs share it; it is written once,
atomically.

Usage as a module: ``vice_config(exe)`` returns the path.
Usage from a shell: ``python3 tools/vice_config.py <exe>`` prints the path.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = REPO_ROOT / "build" / "vice"


@lru_cache(maxsize=None)
def vice_version(exe: str) -> str:
    """The installed VICE's version, as its config files must name it."""
    try:
        out = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    match = re.search(r"VICE (\d+(?:\.\d+)+)", out)
    return match.group(1) if match else ""


@lru_cache(maxsize=None)
def vice_config(exe: str) -> str:
    version = vice_version(exe) or "unknown"
    path = CONFIG_DIR / f"vicerc-{version}"
    text = f"[Version]\nConfigVersion={version}\n" if version != "unknown" else "[Version]\n"
    if not path.is_file() or path.read_text() != text:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
        tmp.write_text(text)
        os.replace(tmp, path)
    return str(path)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: vice_config.py <vice executable>")
    print(vice_config(sys.argv[1]))
