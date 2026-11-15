"""``make playtest-gate``: the bot plays every port before a product commit.

Each target (every port and cartridge whose ROMs are set) plays
GATE_CHARACTERS from fixed seeds for GATE_STEPS steps, each run as the build
queue plays one (``queue.run_one``) from this tree's build, and takes the
scripted tour of the actions the bot reaches late or by chance (``tour.py``),
``--workers`` at a time. A failed tour step fails the gate too. A game finding (``cls`` "game": a hang, crash, stack fault,
state invariant, disk load) or a run error fails the gate; deaths, stalls and
the bot's other findings are the bot's and do not. 2026-11-15: every unit and
harness suite passed a build whose first store buy panicked every BBC and
Apple IIe game, and whose Apple IIe playtest port could not see a key wait;
the build queue found both within a minute of play.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from .launch import PLAYTEST_OUT, ROOT
from .ports import PORTS, Port

# Casters for the books; a Ranger for the launcher and its ammunition (2026-11-15:
# the C64's ego arrows jammed it, and no gate character ever shot).
GATE_CHARACTERS = (("human-warrior", 1001), ("elf-mage", 1002), ("dwarf-priest", 1003), ("half-elf-ranger", 1005))
GATE_STEPS = 3000      # past chargen, the first shopping and into the dungeon on every port
GATE_GOAL = "clvl10"
RUN_WALL_SECONDS = 1800.0   # a run's own emulator timeouts end a stuck one long before this


def missing_roms(port: Port) -> list[str]:
    return [name for name in port.required_roms if not os.environ.get(name)]


def job_for(target: str, character: str, seed: int, commit: str, dirty: bool) -> dict[str, Any]:
    return {"id": f"gate-{target}-{character}-{seed}", "queue": "gate", "platform": target,
            "character": character, "goal": GATE_GOAL, "seed": seed, "step_budget": GATE_STEPS,
            "build": "tree", "commit": commit, "dirty": dirty, "started": time.time(), "epoch": ""}


def verdict(run_dir: Path) -> tuple[bool, str]:
    """(passed, one line): a run error, any game finding or a failed tour step fails."""
    if (run_dir / "tour.json").exists() or run_dir.name.endswith("-tour"):
        tour = json.loads((run_dir / "tour.json").read_text()) if (run_dir / "tour.json").exists() else None
        if tour is None:
            return False, "no tour result (the tour died)"
        done = f"tour, {len(tour['steps'])} steps"
        return (True, done) if tour["passed"] else (False, f"{done}: {tour.get('failure')}")
    result = json.loads((run_dir / "result.json").read_text()) if (run_dir / "result.json").exists() else None
    if result is None:
        return False, "no result (the run died)"
    line = f"{result['outcome']}, step {result['steps']}, clvl {result['clvl']}, DL{result['max_dlvl']}"
    if result["outcome"] == "error":
        return False, f"{line}: {'; '.join(result['findings'])[:200]}"
    for path in sorted((run_dir / "findings").glob("F*.json")):
        finding = json.loads(path.read_text())
        if finding.get("cls") == "game":
            return False, f"{line}: {finding['kind']}: {finding['detail']} ({path})"
    return True, line


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-gate")
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--targets", default="", help="comma-separated (default: every port and cartridge)")
    args = parser.parse_args(argv)
    targets = [t for t in args.targets.split(",") if t] or list(PORTS)
    out = PLAYTEST_OUT / "gate" / time.strftime("%Y%m%d-%H%M%S")
    commit, dirty = git("rev-parse", "HEAD"), bool(git("status", "--porcelain", "--untracked-files=no"))
    env = dict(os.environ, PYTHONPATH=str(ROOT / "playtest"), PYTHONDONTWRITEBYTECODE="1")
    env.pop("MORIA8_ISOLATED", None)   # each run in its own namespace, as the queue's

    pending: list[tuple[Path, list[str]]] = []
    play = [sys.executable, "-m", "moria_playtest.queue", "run"]
    skipped: dict[str, str] = {}
    for target in targets:
        roms = missing_roms(PORTS[target])
        if roms:
            skipped[target] = f"skipped: {', '.join(roms)} not set"
            continue
        tour_dir = out / f"{target}-tour"
        tour_dir.mkdir(parents=True)
        pending.append((tour_dir, [sys.executable, "-m", "moria_playtest.tour", target, str(tour_dir)]))
        for character, seed in GATE_CHARACTERS:
            run_dir = out / f"{target}-{character}"
            run_dir.mkdir(parents=True)
            (run_dir / "job.json").write_text(json.dumps(job_for(target, character, seed, commit, dirty), indent=1))
            pending.append((run_dir, play + [str(run_dir)]))
    print(f"playtest gate: {len(pending)} tours and runs of {GATE_STEPS} steps, {args.workers} at a time ({out})",
          flush=True)

    running: dict[Path, tuple[subprocess.Popen[bytes], float]] = {}
    results: dict[Path, tuple[bool, str]] = {}
    while pending or running:
        while pending and len(running) < args.workers:
            run_dir, command = pending.pop(0)
            with (run_dir / "run.log").open("w") as log:
                proc = subprocess.Popen([str(ROOT / "tools" / "isolated.sh"), *command], cwd=ROOT, env=env,
                                        stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
            running[run_dir] = (proc, time.monotonic())
        time.sleep(1.0)
        for run_dir, (proc, began) in list(running.items()):
            if proc.poll() is None and time.monotonic() - began < RUN_WALL_SECONDS:
                continue
            if proc.poll() is None:
                proc.kill()
                proc.wait()
                results[run_dir] = (False, f"no result in {RUN_WALL_SECONDS:.0f} s (killed)")
            else:
                results[run_dir] = verdict(run_dir)
            del running[run_dir]
            ok, line = results[run_dir]
            print(f"  {'PASS' if ok else 'FAIL'} {run_dir.name}: {line}", flush=True)

    failed = sorted(run_dir.name for run_dir, (ok, _) in results.items() if not ok)
    for target, why in skipped.items():
        print(f"  SKIP {target}: {why}")
    print(f"playtest gate: {len(results) - len(failed)} passed, {len(failed)} failed, "
          f"{len(skipped)} targets skipped")
    if failed:
        print("replay a failure: make playtest-repro FINDING=<the finding's path>")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
