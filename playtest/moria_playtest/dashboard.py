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
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from .goals import CHARACTERS, CLASSES, GOALS, QUALIFICATION_SEEDS, RACE_KEYS, for_character, required
from .launch import PLAYTEST_OUT, ROOT

INDEX = ROOT / "playtest" / "dashboard" / "index.html"
SESSIONS = PLAYTEST_OUT / "sessions"
SUITES = ROOT / "playtest" / "suites"
MILESTONE_GOALS = ("clvl10", "reach_dl8")   # M4 and M5 (§16)
DEFAULT_CHARACTER = "half-troll-warrior"     # suites named by goal alone (session.suite_path)
TIMELINE = 400                               # steps of HP and mana the focus view draws
STATUS = re.compile(r"HP:\s*(-?\d+)/(\d+)\s+MP:\s*(\d+)/(\d+)")
KILLER = re.compile(r"[Tt]he ([A-Z][a-z]+(?: [A-Z][a-z]+)*?) "
                    r"(?:hits|bites|touches|stings|claws|crushes|kicks|casts|breathes|gazes|spits|butts|crawls)")
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
    if "falling rock" in text or "Rocks fall" in text:
        cause = "trap: falling rock"
    elif "pit" in text:
        cause = "trap: pit"
    elif "arrow" in text.lower():
        cause = "trap: arrow"
    elif "casts a spell" in text:
        cause = "caster's spell"
    elif any("poison" in (r.get("msg") or "").lower() for r in rows) and \
            all(r.get("layer") in ("rest", "search-mode", "explore", "look") for r in commands[-3:]):
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
    return {"session": path.name, "goal": goal, "character": character, "bar": bar(goal, character),
            "seeds": len(QUALIFICATION_SEEDS), "started": summary.get("started"),
            "updated": mtime(path), "characters": characters, "workers": workers,
            "depth": cached(path / "events.jsonl", depth_series) or {}, "findings": findings}


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
    if round_name not in by_round:
        round_name = max(latest, key=latest.get)
    project = round_name.split("-")[0]
    members = sorted(by_round[round_name], key=lambda item: (item[3], item[2]))
    return {"round": round_name,
            "rounds": sorted(by_round, key=latest.get, reverse=True)[:40],
            "suites": [suite(path, goal, character) for path, _, goal, character in members],
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


def suite_file(goal: str, character: str) -> Path:
    return SUITES / (f"{goal}.json" if character == DEFAULT_CHARACTER else f"{goal}-{character}.json")


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
            "characters": sorted(CHARACTERS), "cells": cells}


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
