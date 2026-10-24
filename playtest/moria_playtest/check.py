"""``make playtest-check``: static gate (no emulator), <=30 s.

Runs the symbol/offset table check against the current C64 build and sources,
then the playtester unit tests.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

from . import abi


def main() -> int:
    if not abi.C64_VS.exists():
        print(f"playtest-check: {abi.C64_VS} missing; run `make build64` first")
        return 1
    errors = abi.check()
    for error in errors:
        print(f"playtest-check: {error}")
    tests = unittest.defaultTestLoader.discover(str(Path(__file__).resolve().parents[1] / "tests"))
    result = unittest.TextTestRunner(verbosity=1).run(tests)
    ok = not errors and result.wasSuccessful()
    print("playtest-check:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
