"""``make playtest-check``: static gate (no emulator), <=30 s.

Runs the symbol/offset table check against each port's current build and
sources, then the playtester unit tests.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

from . import abi
from .launch import Build
from .ports import PORTS


def main() -> int:
    errors = []
    for port in PORTS.values():
        vs = Build.shipping(port).vs
        if not vs.exists():
            print(f"playtest-check: {vs} missing; run `make build` first")
            return 1
        errors += [f"{port.name}: {error}" for error in abi.check(vs, port=port)]
    for error in errors:
        print(f"playtest-check: {error}")
    tests = unittest.defaultTestLoader.discover(str(Path(__file__).resolve().parents[1] / "tests"))
    result = unittest.TextTestRunner(verbosity=1).run(tests)
    ok = not errors and result.wasSuccessful()
    print("playtest-check:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
