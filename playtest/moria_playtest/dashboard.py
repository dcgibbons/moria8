"""``make playtest-dashboard`` (§6.9): stdlib HTTP server on 127.0.0.1:8064.

Serves playtest/dashboard/index.html and a read-only JSON API over the session
directories. It only reads files, so it can never affect a running session.

A round is the set of sessions named ``<round>-<goal>-<character>`` (for
example ``m5b-r36b-clvl10-human-priest``); the page shows one round's suites
side by side, every worker's live screen, depth over steps, causes of death,
and the scores of earlier rounds of the same project.

- ``/api/overview[?round=R]``: the round (default: the newest), its suites,
  the round list and the project's history.
- ``/api/worker?session=S&worker=N``: one worker's status with its decisions.
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

from .goals import CHARACTERS, GOALS, QUALIFICATION_SEEDS, for_character, required
from .launch import PLAYTEST_OUT, ROOT

INDEX = ROOT / "playtest" / "dashboard" / "index.html"
SESSIONS = PLAYTEST_OUT / "sessions"
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


def sessions() -> list[tuple[Path, str, str, str]]:
    found = []
    for path in SESSIONS.glob("*"):
        parts = split_name(path.name) if path.is_dir() else None
        if parts and (path / "summary.json").exists():
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


def suite(path: Path, goal: str, character: str) -> dict[str, Any]:
    summary = read_json(path / "summary.json") or {}
    characters = summary.get("characters", [])
    for char in characters:
        if char.get("outcome") == "died":
            traces = list(path.glob(f"w*/*/{char['seed']}/trace.jsonl.gz"))
            char["killer"] = cached(traces[0], killer) if traces else ""
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
    path = SESSIONS / Path(session).name / f"status-w{number}.json"
    return read_json(path)


def make_handler() -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - http.server API
            url = urlparse(self.path)
            query = {k: v[-1] for k, v in parse_qs(url.query).items()}
            if url.path == "/api/overview":
                body = json.dumps(overview(query.get("round")), default=str).encode()
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
