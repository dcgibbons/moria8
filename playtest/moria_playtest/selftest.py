"""``make playtest-selftest``: the auditor must catch a deliberately broken build.

Builds the C64 disk with ``-define PLAYTEST_FAULT_STACK_LEAK`` (a test-only hook
at the top of ``main_loop`` that leaks one stack byte per pass), plays the
``enter_dungeon`` goal on it, and requires a ``stack`` finding that
``repro`` then reproduces from its snapshot and key log.
"""

from __future__ import annotations

import json
import subprocess
import sys

from . import session
from .launch import PLAYTEST_OUT, ROOT
from .repro import reproduce

BUILD_OUT = PLAYTEST_OUT / "selftest-build"
SESSION = "selftest-stack-leak"
KA_FLAGS64 = ("-showmem -vicesymbols -libdir ../../core -libdir common -afo -libdir c64 "
              "-define DEBUG_FEAT_DISK_TRACE=0 -define PLAYTEST_FAULT_STACK_LEAK")


def build_broken() -> None:
    BUILD_OUT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["make", "-s", "-B", "-C", str(ROOT / "platforms" / "commodore"),
                    f"OUT={BUILD_OUT}", f"KA_FLAGS64={KA_FLAGS64}",
                    str(BUILD_OUT / "moria8-c64.d64")], check=True, stdout=subprocess.DEVNULL)


def main() -> int:
    build_broken()
    session.main(["--qualify", "--seeds", "1001", "--workers", "1",
                  "--build-out", str(BUILD_OUT), "--name", SESSION])
    findings_dir = PLAYTEST_OUT / "sessions" / SESSION / "findings"
    stack = [p for p in sorted(findings_dir.glob("F*.json"))
             if json.loads(p.read_text())["kind"] == "stack"]
    if not stack:
        print("playtest-selftest: FAIL (no stack finding on the broken build)")
        return 1
    ok, detail = reproduce(stack[0])
    print(f"stack finding {stack[0].name}: {json.loads(stack[0].read_text())['detail']}")
    print(f"repro: {detail}")
    print("playtest-selftest:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
