"""``make playtest-strategy-evidence`` (§23.7): the evidence behind the
strategy guide, from the queue's run records.

For each race and class on the main queue's goal: runs, successes, how deep
and how far they get, what kills them at each stage, and what the successes
carried. Written as Markdown to ``docs/STRATEGY_EVIDENCE.md`` for the
design doc's summary and the guide's author; it reads files only.
"""

from __future__ import annotations

import argparse
import collections
import statistics
import sys
import time
from pathlib import Path
from typing import Any

from . import records
from .goals import CHARACTERS
from .launch import ROOT
from .queue import COUNTED, HOME, load_config

OUT = ROOT / "docs" / "STRATEGY_EVIDENCE.md"
STAGES = ((1, 5, "DL1-5"), (6, 14, "DL6-14"), (15, 24, "DL15-24"), (25, 99, "DL25+"))


def stage(dlvl: int) -> str:
    return next(name for lo, hi, name in STAGES if lo <= max(dlvl, 1) <= hi)


def summary(runs: list[dict[str, Any]]) -> dict[str, Any]:
    """One combination's evidence."""
    deaths = [r for r in runs if r["outcome"] == "died"]
    by_stage: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    for r in deaths:
        by_stage[stage(r.get("max_dlvl") or 0)][(r.get("death") or {}).get("cause") or "unknown"] += 1
    wins = [r for r in runs if r["outcome"] == "reached"]
    kits = [((r.get("features") or {}).get("kit") or {}) for r in wins]
    return {
        "runs": len(runs), "reached": len(wins),
        "median_dl": statistics.median(r.get("max_dlvl") or 0 for r in runs) if runs else 0,
        "median_clvl": statistics.median(r.get("clvl") or 0 for r in runs) if runs else 0,
        "best": max(((r.get("max_dlvl") or 0, r.get("clvl") or 0) for r in runs), default=(0, 0)),
        "early": sum((r.get("max_dlvl") or 0) <= 5 for r in deaths),
        "stages": {name: c.most_common(3) for name, c in by_stage.items()},
        "win_steps": sorted(r["steps"] for r in wins),
        "win_weapons": collections.Counter(k["weapon"][0] for k in kits if k.get("weapon")).most_common(2),
    }


def render(goal: str, rows: dict[str, dict[str, Any]], total: int) -> str:
    lines = [f"# Strategy evidence ({goal})", "",
             f"Generated {time.strftime('%Y-%m-%d %H:%M')} by `make playtest-strategy-evidence` from "
             f"{total} counted main-queue runs (`var/playtest-queue/queue.db`). Raw evidence for the "
             "strategy guide (docs/AI_PLAYTEST_DESIGN.md §23.7), not the guide.", "",
             "| Combination | Runs | Reached | Median DL / clvl | Best DL / clvl | Died by DL5 |",
             "| --- | --- | --- | --- | --- | --- |"]
    for name in sorted(rows, key=lambda n: (-rows[n]["reached"], -rows[n]["best"][0], n)):
        s = rows[name]
        lines.append(f"| {name} | {s['runs']} | {s['reached']} | {s['median_dl']:g} / {s['median_clvl']:g} "
                     f"| {s['best'][0]} / {s['best'][1]} | {s['early']} |")
    lines += ["", "## What kills them, by depth", ""]
    for name in sorted(rows):
        s = rows[name]
        parts = [f"{stage_name}: " + ", ".join(f"{cause} {n}" for cause, n in s["stages"][stage_name])
                 for _, _, stage_name in STAGES if stage_name in s["stages"]]
        win = (f" Successes: {len(s['win_steps'])}, in {', '.join(f'{n:,}' for n in s['win_steps'])} steps"
               + (f", wielding {', '.join(w for w, _ in s['win_weapons'])}" if s["win_weapons"] else "") + "."
               if s["win_steps"] else "")
        lines.append(f"- **{name}**: " + ("; ".join(parts) or "no deaths yet") + "." + win)
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-strategy-evidence")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args(argv)
    config = load_config()
    goal, epoch = config["goal"], config.get("epoch", "")
    db = records.open_ro(HOME)
    if db is None:
        print("no queue.db yet", file=sys.stderr)
        return 1
    runs = [r for r in records.records(db, "queue = 'main' AND goal = ?", (goal,))
            if r["outcome"] in COUNTED and r.get("epoch", "") == epoch]   # the current epoch only
    by_combo: dict[str, list[dict[str, Any]]] = {name: [] for name in CHARACTERS}
    for r in runs:
        by_combo.setdefault(r["character"], []).append(r)
    args.out.write_text(render(goal + (f", epoch {epoch}" if epoch else ""),
                               {n: summary(rs) for n, rs in by_combo.items()}, len(runs)))
    print(f"wrote {args.out} ({len(runs)} runs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
