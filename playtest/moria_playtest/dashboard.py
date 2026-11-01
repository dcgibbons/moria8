"""``make playtest-dashboard`` (§6.9): stdlib HTTP server on 127.0.0.1:8064.

Serves playtest/dashboard/index.html and a read-only JSON API over the session
directories. It only reads files, so it can never affect a running session.

A round is the set of sessions named ``<round>-<goal>-<character>`` (for
example ``m5b-r36b-clvl10-human-priest``); the page shows one round's suites
side by side, every worker's live screen, depth over steps, causes of death,
and the scores of earlier rounds of the same project.

- ``/api/overview[?round=R]``: the round (default: the newest), its suites,
  the round list and the project's history.
- ``/api/worker?session=S&worker=N``: one worker's status with its decisions,
  and the HP and mana of its last ``TIMELINE`` steps.
- ``/api/milestone``: every race and class on the M5 goals: frozen or not,
  its bar, and the latest full result.
- ``/api/ports``: M6's coverage map (§21.4): the primary characters on each
  port's goals, frozen or not, the latest full result and when it ran.
- ``/api/disk``: the disk scenarios (§22, ``make playtest-disk``): each
  port's latest run, scenario by scenario, live while it runs.
- ``/api/queue``: the continuous queue (§23.6): the service and the build it
  plays, each platform's cycle grid, live runs, subqueues, the feature
  counts and difficulty ratings from every run's record.
- ``/api/queue_run?id=R``: one live queue run's focus view.
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
import time
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from . import records as run_records
from .goals import (CHARACTER_BARS, CHARACTERS, CLASS_BARS, CLASSES, GOALS, QUALIFICATION_SEEDS, RACE_KEYS,
                    for_character, required)
from .launch import PLAYTEST_OUT, ROOT
from .ports import C64, PORTS

INDEX = ROOT / "playtest" / "dashboard" / "index.html"
SESSIONS = PLAYTEST_OUT / "sessions"
DISK_RUNS = PLAYTEST_OUT / "disk"            # make playtest-disk: <time>-<port>/summary.json
LIVE_SECONDS = 300   # a round that wrote within this is running
SUITES = ROOT / "playtest" / "suites"
MILESTONE_GOALS = ("clvl10", "reach_dl8")   # M4 and M5 (§16)
PORT_GOALS = ("clvl5", "reach_dl5")          # M6 (§21.2)
PORT_CHARACTERS = ("half-troll-warrior", "human-warrior", "human-priest", "human-mage", "human-rogue")
DEFAULT_CHARACTER = "half-troll-warrior"     # suites named by goal alone (session.suite_path)
TIMELINE = 400                               # steps of HP and mana the focus view draws
NOW = PLAYTEST_OUT / "now.json"              # {"text": ...}: what the current runs are for
STATUS = re.compile(r"HP:\s*(-?\d+)/(\d+)\s+MP:\s*(\d+)/(\d+)")
# Names may hold lowercase words ("White Worm mass"), never "the" (a name
# clipped at the line end, "the Ko | the Kobold hits you").
KILLER = re.compile(r"[Tt]he ([A-Z][\w'-]*(?:,? (?!the\b)[\w'-]+)*?) "
                    r"(?:hits|bites|touches|stings|claws|crushes|kicks|casts|breathes|gazes|spits|butts|crawls"
                    r"|poisons|confuses|paralyzes|frightens)")
_cache: dict[tuple[str, float], Any] = {}


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def cached(path: Path, build):
    """``build(path)``, remembered until the file changes."""
    try:
        key = (str(path), path.stat().st_mtime)
    except OSError:
        return None
    if key not in _cache:
        # One entry per file: every change used to add one, and the publisher,
        # which runs for days, grew to 7.8 GB (2026-10-31).
        for stale in [k for k in _cache if k[0] == key[0]]:
            del _cache[stale]
        _cache[key] = build(path)
    return _cache[key]


def split_name(name: str) -> tuple[str, str, str] | None:
    """``(round, goal, character)`` of a session directory name."""
    for goal in sorted(GOALS, key=len, reverse=True):
        marker = f"-{goal}"
        at = name.find(marker + "-")
        if at > 0:
            return name[:at], goal, name[at + len(marker) + 1:]
        if name.endswith(marker):
            return name[:-len(marker)], goal, "half-troll-warrior"
    return None


def bar(goal: str, character: str) -> int:
    if goal not in GOALS or character not in CHARACTERS:
        return 16
    return required(for_character(GOALS[goal], character), len(QUALIFICATION_SEEDS))


def session_parts(path: Path) -> tuple[str, str, str] | None:
    """``(round, goal, character)``: the goal and character the session
    recorded in its summary, the round its name less those; a summary
    without them falls back to the name (``split_name``). Names put the
    character before the goal or after it, or leave it out (M5d and M5e
    sessions showed as Half-Troll Warriors, 2026-10-26)."""
    summary = read_json(path / "summary.json") or {}
    goal, character = summary.get("goal"), summary.get("character")
    if goal not in GOALS or character not in CHARACTERS:
        return split_name(path.name)
    round_name = path.name
    for token in (character, goal):
        round_name = re.sub(rf"(^|-){re.escape(token)}(?=-|$)", "", round_name)
    return round_name, goal, character


def sessions() -> list[tuple[Path, str, str, str]]:
    found = []
    for path in SESSIONS.glob("*"):
        if not path.is_dir() or not (path / "summary.json").exists():
            continue
        parts = session_parts(path)
        if parts:
            found.append((path, *parts))
    return found


def mtime(path: Path) -> float:
    newest = (path / "summary.json").stat().st_mtime
    for status in path.glob("status-w*.json"):
        newest = max(newest, status.stat().st_mtime)
    return newest


def depth_series(events: Path) -> dict[str, list[list[int]]]:
    """Per seed, [step, dlvl] at each level entry where the depth changed."""
    series: dict[str, list[list[int]]] = {}
    try:
        lines = events.read_text().splitlines()
    except OSError:
        return series
    for line in lines:
        if '"level_entry"' not in line:
            continue
        event = json.loads(line)
        points = series.setdefault(str(event["seed"]), [])
        if not points or points[-1][1] != event["dlvl"]:
            points.append([event["step"], event["dlvl"]])
    return series


def killer(trace: Path) -> str:
    try:
        with gzip.open(trace, "rt") as handle:
            lines = handle.read().splitlines()[-15:]
    except (OSError, EOFError):
        return ""
    found = KILLER.findall(" ".join(json.loads(line).get("msg") or "" for line in lines))
    return found[-1] if found else ""


def trace_tail(trace: Path, count: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        with gzip.open(trace, "rt") as handle:
            for line in handle:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    break   # still being written
                del rows[:-count]
    except (OSError, EOFError):
        pass
    return rows


def death(trace: Path) -> dict[str, Any]:
    """How a character died, from its trace's end: the cause in groups (a
    trap, poison, a caster's spell, or the creature that hit it), the kit it
    still held, and its mana (the M5f questions: what kills them, and did
    they die holding potions?)."""
    rows = trace_tail(trace, 60)
    if not rows:
        return {}
    text = " | ".join(r.get("msg") or "" for r in rows[-6:])
    commands = [r for r in rows if r.get("mode") == "COMMAND"]
    last = commands[-1] if commands else rows[-1]
    found = KILLER.findall(" ".join(r.get("msg") or "" for r in rows[-15:]))
    slain = next((r for r in reversed(rows) if "have been slain" in (r.get("msg") or "")), {})
    before = next((r.get("hp") for r in reversed(rows[:rows.index(slain)]) if r.get("hp") is not None), 0) \
        if slain else 0
    if "falling rock" in text or "Rocks fall" in text:
        cause = "trap: falling rock"
    elif re.search(r"\bpit\b", text):   # not "the Green Naga spits acid" (M7 queue)
        cause = "trap: pit"
    elif "arrow" in text.lower():
        cause = "trap: arrow"
    elif "casts a spell" in text:
        cause = "caster's spell"
    elif any("poison" in (r.get("msg") or "").lower() for r in rows) and (
            all(r.get("layer") in ("rest", "search-mode", "explore", "look") for r in commands[-3:])
            or (slain.get("hp") == 0 and 0 < before <= 4 and not KILLER.search(slain.get("msg") or ""))):
        # The poison tick (at most 4 HP) stops at 0 HP; a killing blow usually
        # leaves HP below 0 and prints no "hits you" (M7 queue).
        cause = "poison"
    else:
        cause = found[-1] if found else "unknown"
    status = STATUS.search(last.get("status") or "")
    return {"cause": cause, "killer": found[-1] if found else "", "clw": last.get("clw"),
            "oil": last.get("oil"), "mp": int(status.group(3)) if status else None,
            "mmp": int(status.group(4)) if status else None, "last": last.get("reason") or ""}


def suite(path: Path, goal: str, character: str) -> dict[str, Any]:
    summary = read_json(path / "summary.json") or {}
    characters = summary.get("characters", [])
    for char in characters:
        if char.get("outcome") == "died":
            traces = list(path.glob(f"w*/*/{char['seed']}/trace.jsonl.gz"))
            detail = cached(traces[0], death) if traces else {}
            char.update(detail or {})
            char.setdefault("killer", "")
    workers = []
    for status_path in sorted(path.glob("status-w*.json")):
        status = read_json(status_path)
        if status:
            status.pop("decisions", None)
            workers.append(status)
    findings: dict[str, int] = {}
    for finding in path.glob("findings/*.json"):
        kind = (read_json(finding) or {}).get("kind", "?")
        findings[kind] = findings.get(kind, 0) + 1
    return {"session": path.name, "goal": goal, "character": character, "port": summary.get("port", C64.name),
            "bar": bar(goal, character),
            "seeds": len(QUALIFICATION_SEEDS), "started": summary.get("started"),
            "updated": mtime(path), "characters": characters, "workers": workers,
            "depth": cached(path / "events.jsonl", depth_series) or {}, "findings": findings}


def regress_suites(path: Path, character: str) -> list[dict[str, Any]]:
    """A ``--regress`` session runs each of its character's frozen suites in
    turn and records no goal of its own: one entry per suite, each with the
    characters that played it and the bar it was frozen at. A finished
    character's goal is its start's: each end is paired with the earliest
    unfinished start of the same seed (the suites run one after another)."""
    summary = read_json(path / "summary.json") or {}
    finished = summary.get("characters", [])
    starts: dict[int, list[str]] = {}
    goals_done: list[str] = []
    try:
        lines = (path / "events.jsonl").read_text().splitlines()
    except OSError:
        lines = []
    for line in lines:
        if '"character_start"' in line or '"character_end"' in line:
            event = json.loads(line)
            if event["kind"] == "character_start":
                starts.setdefault(event["seed"], []).append(event.get("goal", ""))
            elif starts.get(event["seed"]):
                goals_done.append(starts[event["seed"]].pop(0))
    by_goal: dict[str, list[dict[str, Any]]] = {}
    for char, goal in zip(finished, goals_done):
        by_goal.setdefault(goal, []).append(char)
    statuses = [status for status_path in sorted(path.glob("status-w*.json"))
                if (status := read_json(status_path))]
    for status in statuses:
        status.pop("decisions", None)
    entries = []
    for goal in GOALS:
        frozen = read_json(suite_file(goal, character, summary.get("port", C64.name)))
        if not frozen:
            continue
        chars = by_goal.get(goal, [])
        for char in chars:
            if char.get("outcome") == "died":
                traces = [t for t in path.glob(f"w*/{goal}/{char['seed']}/trace.jsonl.gz")]
                char.update((cached(traces[0], death) if traces else {}) or {})
                char.setdefault("killer", "")
        live = [w for w in statuses if w.get("goal") == goal and not w.get("outcome")
                and len(chars) < len(frozen.get("seeds", []))]
        entries.append({"session": path.name, "goal": goal, "character": character,
                        "port": summary.get("port", C64.name),
                        "bar": frozen.get("required", bar(goal, character)), "seeds": len(frozen.get("seeds", [])),
                        "started": summary.get("started"), "updated": mtime(path), "characters": chars,
                        "workers": live, "depth": {}, "findings": {}, "regress": True})
    return entries


def history(project: str, all_sessions) -> list[dict[str, Any]]:
    rounds: dict[str, dict[str, Any]] = {}
    for path, round_name, goal, character in all_sessions:
        if not round_name.startswith(project + "-"):
            continue
        summary = cached(path / "summary.json", read_json) or {}
        chars = summary.get("characters", [])
        entry = rounds.setdefault(round_name, {"round": round_name, "started": summary.get("started") or "",
                                               "suites": {}})
        entry["started"] = min(entry["started"] or "~", summary.get("started") or "~")
        entry["suites"][f"{goal} {character}"] = {
            "reached": sum(c.get("outcome") == "reached" for c in chars), "done": len(chars),
            "bar": bar(goal, character)}
    return sorted(rounds.values(), key=lambda r: r["started"])


def overview(round_name: str | None) -> dict[str, Any]:
    all_sessions = sessions()
    if not all_sessions:
        return {"round": None, "rounds": [], "suites": [], "history": [], "now": time.time()}
    by_round: dict[str, list] = {}
    for item in all_sessions:
        by_round.setdefault(item[1], []).append(item)
    latest = {name: max(mtime(p) for p, *_ in items) for name, items in by_round.items()}
    rounds = sorted(by_round, key=latest.get, reverse=True)[:40]
    if round_name in by_round:
        names = [round_name]
    else:
        # Every round running now, not only the last to write: ports and
        # regressions run side by side, and the view flipped between them
        # (M6, 2026-10-28). With none running, the latest.
        names = [name for name in rounds if time.time() - latest[name] < LIVE_SECONDS] or rounds[:1]
        round_name = " + ".join(names)
        if len(names) > 1:
            rounds.insert(0, round_name)
    project = names[0].split("-")[0]
    members = sorted((item for name in names for item in by_round[name]),
                     key=lambda item: (item[3], item[2], item[1]))
    suites = []
    for path, _, goal, character in members:
        if (cached(path / "summary.json", read_json) or {}).get("mode") == "regress":
            suites += regress_suites(path, character)
        else:
            suites.append(suite(path, goal, character))
    return {"round": round_name, "now_text": (read_json(NOW) or {}).get("text", ""),
            "rounds": rounds,
            "suites": suites,
            "history": history(project, all_sessions),
            "now": time.time()}


def worker(session: str, number: int) -> dict[str, Any] | None:
    base = SESSIONS / Path(session).name
    status = read_json(base / f"status-w{number}.json")
    if not status:
        return status
    traces = sorted(base.glob(f"w{number}/*/{status.get('seed')}/trace.jsonl.gz"))
    timeline = []
    for row in trace_tail(traces[0], TIMELINE * 2) if traces else []:
        match = STATUS.search(row.get("status") or "")
        if row.get("mode") == "COMMAND" and match:
            timeline.append([row["step"], int(match.group(1)), int(match.group(2)),
                             int(match.group(3)), int(match.group(4)), row.get("layer") or ""])
    status["timeline"] = timeline[-TIMELINE:]
    if timeline:
        last = traces and trace_tail(traces[0], 1)
        status["kit"] = {"clw": last[0].get("clw"), "oil": last[0].get("oil")} if last else {}
    return status


def suite_file(goal: str, character: str, port: str = C64.name) -> Path:
    """session.suite_path: the goal, then the character and port unless defaults."""
    parts = [goal, *([character] if character != DEFAULT_CHARACTER else []),
             *([port] if port != C64.name else [])]
    return SUITES / f"{'-'.join(parts)}.json"


def milestone() -> dict[str, Any]:
    """Every allowed race and class on the M5 goals: its bar, whether its
    suite is frozen (and at what), and its latest finished result."""
    latest: dict[tuple[str, str], tuple[float, int, int]] = {}
    for path, _, goal, character in sessions():
        if goal not in MILESTONE_GOALS:
            continue
        summary = cached(path / "summary.json", read_json) or {}
        chars = summary.get("characters", [])
        if len(chars) < len(QUALIFICATION_SEEDS):
            continue
        when = mtime(path)
        if when > latest.get((goal, character), (0.0, 0, 0))[0]:
            latest[(goal, character)] = (when, sum(c.get("outcome") == "reached" for c in chars), len(chars))
    cells = {}
    for character in CHARACTERS:
        for goal in MILESTONE_GOALS:
            frozen = read_json(suite_file(goal, character))
            result = latest.get((goal, character))
            cells[f"{character} {goal}"] = {
                "bar": bar(goal, character), "frozen": bool(frozen),
                "frozen_bar": (frozen or {}).get("required"), "frozen_on": (frozen or {}).get("frozen"),
                "latest": result[1] if result else None}
    return {"races": list(RACE_KEYS), "classes": list(CLASSES), "goals": list(MILESTONE_GOALS),
            "characters": sorted(CHARACTERS), "cells": cells, "legend": legend()}


def ports() -> dict[str, Any]:
    """M6's coverage map (§21.4): each primary character on each port's
    goals, its bar, whether its suite is frozen, and the latest finished
    qualification with the day it ran."""
    latest: dict[tuple[str, str, str], tuple[float, int, int, str]] = {}
    for path, _, goal, character in sessions():
        if goal not in PORT_GOALS or character not in PORT_CHARACTERS:
            continue
        summary = cached(path / "summary.json", read_json) or {}
        chars = summary.get("characters", [])
        if summary.get("mode") != "qualify" or len(chars) < len(QUALIFICATION_SEEDS):
            continue
        key = (summary.get("port", C64.name), goal, character)
        when = mtime(path)
        if when > latest.get(key, (0.0,))[0]:
            latest[key] = (when, sum(c.get("outcome") == "reached" for c in chars), len(chars),
                           (summary.get("started") or "")[:10])
    cells, frozen_count = {}, {}
    for port in PORTS:
        frozen_count[port] = 0
        for character in PORT_CHARACTERS:
            for goal in PORT_GOALS:
                frozen = read_json(suite_file(goal, character, port))
                result = latest.get((port, goal, character))
                frozen_count[port] += bool(frozen)
                cells[f"{port} {character} {goal}"] = {
                    "bar": (frozen or {}).get("required", bar(goal, character)), "frozen": bool(frozen),
                    "frozen_on": (frozen or {}).get("frozen"),
                    "latest": result[1] if result else None, "ran": result[3] if result else None}
    return {"ports": list(PORTS), "characters": list(PORT_CHARACTERS), "goals": list(PORT_GOALS),
            "cells": cells, "frozen": frozen_count, "suites": len(PORT_CHARACTERS) * len(PORT_GOALS)}


def disk() -> dict[str, Any]:
    """Each port's disk-scenario run to show: one running now, else the
    newest with the most scenarios (a SCENARIOS= rerun of a few does not
    hide the last full run); and the recent runs."""
    runs = []
    for path in sorted(DISK_RUNS.glob("*/summary.json"), key=lambda p: mtime(p.parent), reverse=True)[:60]:
        summary = cached(path, read_json)
        if not summary or not summary.get("scenarios"):
            continue
        rows = summary["scenarios"]
        runs.append({"run": path.parent.name, "port": summary.get("port"), "started": summary.get("started"),
                     "finished": summary.get("finished"), "scenarios": rows,
                     "live": not summary.get("finished") and time.time() - mtime(path.parent) < LIVE_SECONDS,
                     "expected": sum(r["outcome"] in ("pass", "xfail") for r in rows), "total": len(rows)})
    latest: dict[str, dict[str, Any]] = {}
    for port in {run["port"] for run in runs}:
        port_runs = [run for run in runs if run["port"] == port]   # newest first
        live = [run for run in port_runs if run["live"]]
        most = max(run["total"] for run in port_runs)
        latest[port] = live[0] if live else next(run for run in port_runs if run["total"] == most)
    names: list[str] = []
    for run in latest.values():
        names += [r["name"] for r in run["scenarios"] if r["name"] not in names]
    return {"ports": [p for p in PORTS if p in latest], "latest": latest, "scenarios": names,
            "runs": [{k: r[k] for k in ("run", "port", "started", "finished", "live", "expected", "total")}
                     for r in runs[:20]], "now": time.time()}


# -- the continuous queue (§23.6) ------------------------------------------------

RATINGS = ("Easy", "Medium", "Hard", "Very Hard")
RATING_MIN_RUNS = 5   # counted runs before a combination is rated
SPELL_COVERAGE_LEVEL = 25   # criterion 2: the spells a class learns by this level


def rate(value: float, bounds: tuple[float, float, float], higher_is_easier: bool = True) -> str:
    """``value`` against three bounds, Easy to Very Hard."""
    for rating, bound in zip(RATINGS, bounds):
        if (value >= bound) if higher_is_easier else (value <= bound):
            return rating
    return RATINGS[-1]


def queue_records(path: Path) -> list[dict[str, Any]]:
    records = []
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return records
    for line in lines:
        try:
            records.append(json.loads(line))
        except ValueError:
            continue
    return records


def queue_runs(home: Path, goal: str, counted: tuple[str, ...], epoch: str = "") -> dict[str, Any]:
    """The run records' part of /api/queue: ratings and feature counts over
    the main queue's counted runs on ``goal``, the number of runs and the
    newest 30. From queue.db, the derived counts remembered until a row is
    written (the database file's mtime lags its WAL); from runs.jsonl before
    the service has made the database."""
    db = run_records.open_ro(home)
    if db is None:
        records = cached(home / "runs.jsonl", queue_records) or []
        main = [r for r in records if r.get("queue") == "main" and r.get("goal") == goal and r["outcome"] in counted
                and r.get("epoch", "") == epoch]
        return {"ratings": ratings(main), "features": queue_features(main), "runs": len(records),
                "recent": records[-30:][::-1]}
    with closing(db):
        # Every insert takes a new rowid, so the count and the last rowid change with each.
        version = db.execute("SELECT count(*), max(rowid) FROM runs").fetchone()
        key = (f"{run_records.path(home)}:{goal}:{epoch}", version)
        if key not in _cache:
            for stale in [k for k in _cache if k[0] == key[0]]:
                del _cache[stale]
            main = run_records.records(db, f"queue = 'main' AND goal = ? AND outcome IN "
                                           f"({', '.join('?' * len(counted))})", (goal, *counted))
            main = [r for r in main if r.get("epoch", "") == epoch]   # the current epoch's runs only
            _cache[key] = {"ratings": ratings(main), "features": queue_features(main)}
        return {**_cache[key], "runs": version[0], "recent": run_records.records(db, newest=30)}


def ratings(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Per combination (§23.7): survival (runs not ended by death), the
    median character level at death, and the share of deaths at level 5 or
    below, each rated Easy to Very Hard once it has RATING_MIN_RUNS runs."""
    by_combo: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        by_combo.setdefault(record["character"], []).append(record)
    out = {}
    for combo, runs in by_combo.items():
        deaths = sorted(r.get("clvl") or 0 for r in runs if r["outcome"] == "died")
        survival = 1 - len(deaths) / len(runs)
        median = deaths[len(deaths) // 2] if deaths else None
        early = sum(level <= 5 for level in deaths) / len(runs)
        entry: dict[str, Any] = {"runs": len(runs), "survival": round(survival, 2), "median_death_clvl": median,
                                 "early_deaths": round(early, 2)}
        if len(runs) >= RATING_MIN_RUNS:
            entry["ratings"] = {"survival": rate(survival, (0.75, 0.5, 0.25)),
                                "median_death_clvl": rate(median, (20, 12, 6)) if median is not None else "Easy",
                                "early_deaths": rate(early, (0.1, 0.25, 0.5), higher_is_easier=False)}
        out[combo] = entry
    return out


def queue_features(records: list[dict[str, Any]]) -> dict[str, Any]:
    """The feature grid's counts (§23.6), per class: decisions by brain
    layer, milestones reached, recall trips and causes of death."""
    from . import knowledge
    classes: dict[str, dict[str, Any]] = {}
    for record in records:
        klass = record["character"].rsplit("-", 1)[1]
        entry = classes.get(klass)
        if entry is None:
            # Criterion 2 (§23.2): every spell or prayer the class learns by
            # level 25, with how often it was cast and its effect seen.
            entry = classes[klass] = {"runs": 0, "layers": {}, "milestones": {}, "causes": {}, "spells": {
                name: {"level": level, "cast": 0, "effect": 0, "evidence": ""}
                for name, level in knowledge.spells(klass).items() if level <= SPELL_COVERAGE_LEVEL}}
        entry["runs"] += 1
        for key, count in ((record.get("features") or {}).get("missiles") or {}).items():
            entry.setdefault("missiles", {"shots": 0, "kills": 0})[key] += count
        for name, cast in ((record.get("features") or {}).get("casts") or {}).items():
            spell = entry["spells"].setdefault(name, {"level": None, "cast": 0, "effect": 0, "evidence": ""})
            spell["cast"] += cast.get("cast", 0)
            spell["effect"] += cast.get("effect", 0)
            spell["evidence"] = spell["evidence"] or cast.get("evidence", "")
        for layer, count in ((record.get("features") or {}).get("layers") or {}).items():
            entry["layers"][layer] = entry["layers"].get(layer, 0) + count
        for name in record.get("milestones") or {}:
            entry["milestones"][name] = entry["milestones"].get(name, 0) + 1
        cause = (record.get("death") or {}).get("cause")
        if cause:
            entry["causes"][cause] = entry["causes"].get(cause, 0) + 1
    return classes


def queue_live(home: Path, run_id: str, job: dict[str, Any], full: bool = False) -> dict[str, Any]:
    run_dir = home / "runs" / run_id
    status = next((read_json(p) for p in sorted(run_dir.glob("status-w*.json"))), None) or {}
    if not full:
        status.pop("decisions", None)
    progress = read_json(run_dir / "progress.json") or {}
    return {"id": run_id, **{k: job.get(k) for k in ("queue", "platform", "character", "goal", "seed", "step_budget",
                                                     "paused", "started", "commit", "dirty", "build")},
            "milestones": progress.get("milestones", {}), "status": status}


def queue() -> dict[str, Any]:
    from . import queue as q
    home = q.HOME
    config = q.load_config()
    service = read_json(home / "service.json") or {}
    state = read_json(q.state_path(home, config["goal"], config.get("epoch", ""))) or {}
    running = read_json(home / "running.json") or {}
    runs = queue_runs(home, config["goal"], q.COUNTED, config.get("epoch", ""))
    subs = []
    for path in sorted((home / "subqueues").glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)[:12]:
        sub = cached(path, read_json) or {}
        subs.append({k: sub.get(k) for k in ("name", "created", "finished", "build", "note", "done", "cancelled",
                                              "report", "variant", "ab")} |
                    {"items": len(sub.get("items", [])), "results": len(sub.get("results", [])),
                     "reached": sum(r["outcome"] == "reached" for r in sub.get("results", [])),
                     "progress": q.subqueue_report(sub) if not sub.get("done") and sub.get("items") else None,
                     "ab_report": (sub.get("ab_report") or q.ab_report(sub)) if sub.get("ab") else None})
    return {"now": time.time(), "service": {"up": time.time() - service.get("updated", 0) < 60,
                                            "updated": service.get("updated"), "build": service.get("build"),
                                            "build_state": service.get("build_state", {}), "log": service.get("log", [])[-12:]},
            "config": config, "races": list(RACE_KEYS), "classes": list(CLASSES), "characters": sorted(CHARACTERS),
            "goal": {"name": config["goal"], "what": GOALS[config["goal"]].description.split(". ")[0].rstrip(".") + "."
                     if config["goal"] in GOALS else ""},
            "slowest_success": state.get("slowest_success"),
            "budget": max(int(state["slowest_success"] * config["budget_factor"]), int(config["budget_floor"]))
            if state.get("slowest_success") else config["start_budget"],
            "platforms": state.get("platforms", {}),
            "live": [queue_live(home, run_id, job) for run_id, job in running.items()],
            "subqueues": subs, "balrog": read_json(home / "state-balrog.json") or {"items": {}, "order": []},
            "ratings": runs["ratings"], "features": runs["features"],
            "runs": runs["runs"], "recent": [{k: r.get(k) for k in ("id", "queue", "character", "platform", "outcome",
                                                                    "clvl", "max_dlvl", "steps", "ended")}
                                             | {"cause": (r.get("death") or {}).get("cause")}
                                             for r in runs["recent"]]}


def queue_run(run_id: str) -> dict[str, Any] | None:
    from . import queue as q
    running = read_json(q.HOME / "running.json") or {}
    job = running.get(Path(run_id).name)
    if job is None:
        return None
    live = queue_live(q.HOME, Path(run_id).name, job, full=True)
    status = live["status"]
    traces = sorted((q.HOME / "runs" / live["id"]).glob("w*/*/*/trace.jsonl.gz"))
    timeline = []
    for row in trace_tail(traces[0], TIMELINE * 2) if traces else []:
        match = STATUS.search(row.get("status") or "")
        if row.get("mode") == "COMMAND" and match:
            timeline.append([row["step"], int(match.group(1)), int(match.group(2)),
                             int(match.group(3)), int(match.group(4)), row.get("layer") or ""])
    status["timeline"] = timeline[-TIMELINE:]
    if traces:
        last = trace_tail(traces[0], 1)
        status["kit"] = {"clw": last[0].get("clw"), "oil": last[0].get("oil")} if last else {}
    return {**status, "run": live}


def legend() -> dict[str, Any]:
    """What the page's bars and goals mean, from the code that sets them
    (goals.py), so the explanation cannot drift from the numbers."""
    default = next(iter(GOALS.values())).__class__.__dataclass_fields__["qualify_bar"].default
    return {"seeds": len(QUALIFICATION_SEEDS), "default_bar": default, "class_bars": CLASS_BARS,
            "character_bars": [{"character": c, "goal": g, "bar": b} for (c, g), b in sorted(CHARACTER_BARS.items())],
            "goals": [{"name": g.name, "what": g.description.split(". ")[0].rstrip(".") + ".",
                       "steps": g.step_budget} for g in GOALS.values()]}


def make_handler() -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - http.server API
            url = urlparse(self.path)
            query = {k: v[-1] for k, v in parse_qs(url.query).items()}
            if url.path == "/api/overview":
                body = json.dumps(overview(query.get("round")), default=str).encode()
                kind = "application/json"
            elif url.path == "/api/milestone":
                body = json.dumps(milestone(), default=str).encode()
                kind = "application/json"
            elif url.path == "/api/ports":
                body = json.dumps(ports(), default=str).encode()
                kind = "application/json"
            elif url.path == "/api/queue":
                body = json.dumps(queue(), default=str).encode()
                kind = "application/json"
            elif url.path == "/api/queue_run":
                body = json.dumps(queue_run(query.get("id", "")), default=str).encode()
                kind = "application/json"
            elif url.path == "/api/disk":
                body = json.dumps(disk(), default=str).encode()
                kind = "application/json"
            elif url.path == "/api/worker":
                body = json.dumps(worker(query.get("session", ""), int(query.get("worker", "0"))),
                                  default=str).encode()
                kind = "application/json"
            elif url.path in ("/", "/index.html"):
                body, kind = INDEX.read_bytes(), "text/html; charset=utf-8"
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args: object) -> None:
            pass

    return Handler


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-dashboard")
    parser.add_argument("--port", type=int, default=8064)
    args = parser.parse_args(argv)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler())
    print(f"playtest dashboard: http://127.0.0.1:{args.port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
