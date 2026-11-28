"""``make playtest-check``: static gate (no emulator), <=30 s.

Runs the symbol/offset table check against each port's current build and
sources, then the playtester unit tests.
"""

from __future__ import annotations

import concurrent.futures
import io
import os
import sys
import time
import unittest
from pathlib import Path

from . import abi
from .launch import Build
from .ports import PORTS


def _iter_cases(suite: unittest.TestSuite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from _iter_cases(item)
        else:
            yield item


def _init_worker(tests_dir: str) -> None:
    if tests_dir not in sys.path:
        sys.path.insert(0, tests_dir)


def _run_group(task: tuple[str, str]) -> tuple[int, int, int, int, str]:
    mod, cls_name = task
    suite = unittest.defaultTestLoader.loadTestsFromName(f"{mod}.{cls_name}")
    buf = io.StringIO()
    result = unittest.TextTestRunner(stream=buf, verbosity=1).run(suite)
    output = "" if result.wasSuccessful() else buf.getvalue()
    return (result.testsRun, len(result.failures), len(result.errors), len(result.skipped), output)


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

    tests_dir = Path(__file__).resolve().parents[1] / "tests"
    if str(tests_dir) not in sys.path:
        sys.path.insert(0, str(tests_dir))
    discovered = unittest.defaultTestLoader.discover(str(tests_dir))
    groups: dict[tuple[str, str], int] = {}
    import_failures: list[unittest.TestCase] = []
    for case in _iter_cases(discovered):
        cls = type(case)
        if cls.__module__ == "unittest.loader":
            import_failures.append(case)
        else:
            key = (cls.__module__, cls.__name__)
            groups[key] = groups.get(key, 0) + 1

    jobs = int(os.environ.get("PLAYTEST_CHECK_JOBS") or min(os.cpu_count() or 1, 16))
    if jobs <= 1 or (len(groups) <= 1 and not import_failures):
        result = unittest.TextTestRunner(verbosity=1).run(discovered)
        ok = not errors and result.wasSuccessful()
        print("playtest-check:", "PASS" if ok else "FAIL")
        return 0 if ok else 1

    started = time.monotonic()
    total_run = total_fail = total_err = total_skip = 0
    if import_failures:
        buf = io.StringIO()
        res = unittest.TextTestRunner(stream=buf, verbosity=1).run(unittest.TestSuite(import_failures))
        total_run += res.testsRun
        total_fail += len(res.failures)
        total_err += len(res.errors)
        if buf.getvalue():
            print(buf.getvalue(), end="")

    ordered = sorted(groups, key=lambda key: (-groups[key], key))
    with concurrent.futures.ProcessPoolExecutor(max_workers=jobs, initializer=_init_worker,
                                                initargs=(str(tests_dir),)) as pool:
        for ran, fail, err, skip, out in pool.map(_run_group, ordered):
            total_run += ran
            total_fail += fail
            total_err += err
            total_skip += skip
            if out:
                print(out, end="")

    elapsed = time.monotonic() - started
    tests_ok = (total_fail == 0 and total_err == 0)
    print(f"\nRan {total_run} tests in {elapsed:.3f}s ({jobs} workers)")
    if tests_ok:
        details = f"skipped={total_skip}" if total_skip else ""
        print(f"OK ({details})" if details else "OK")
    else:
        print(f"FAILED (failures={total_fail}, errors={total_err})")
    ok = not errors and tests_ok
    print("playtest-check:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
