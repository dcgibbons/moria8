"""Recorder (§6.8): everything a session writes under build/playtest/sessions/<id>/.

- ``summary.json``: goal, mode, seeds, per-character results.
- ``events.jsonl``: character start/end, level entry, findings, restarts, plateau.
- ``w<N>/<goal>/<seed>/trace.jsonl.gz``: every decision. The goal is in the
  path because regression plays the same seeds for every goal.
- ``w<N>/snapshots/<goal>-<seed>-s<step>-dl<N>.vsf`` + ``.brain.json``: level
  entries (written by Worker).
- ``findings/<id>.json``: kind, detail, snapshot, and the keys that replay it.
- ``status-w<N>.json``: live worker state for the dashboard.
"""

from __future__ import annotations

import gzip
import json
import threading
import time
from pathlib import Path
from typing import Any

from .game import Game, Observation

_LOCK = threading.Lock()


def write_json(path: Path, data: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=1, default=str))
    tmp.replace(path)


class SessionLog:
    """Session-wide files shared by all workers (thread safe)."""

    def __init__(self, session_dir: Path, summary: dict[str, Any]) -> None:
        self.dir = session_dir
        (session_dir / "findings").mkdir(parents=True, exist_ok=True)
        self.summary = summary
        self.summary.setdefault("characters", [])
        self.findings = 0
        self.save_summary()

    def event(self, kind: str, **data: Any) -> None:
        line = json.dumps({"t": round(time.time(), 2), "kind": kind, **data}, default=str)
        with _LOCK, (self.dir / "events.jsonl").open("a") as fh:
            fh.write(line + "\n")

    def character(self, result: dict[str, Any]) -> None:
        with _LOCK:
            self.summary["characters"].append(result)
            write_json(self.dir / "summary.json", self.summary)

    def save_summary(self) -> None:
        with _LOCK:
            write_json(self.dir / "summary.json", self.summary)

    def finding(self, record: dict[str, Any]) -> Path:
        with _LOCK:
            self.findings += 1
            record["id"] = f"F{self.findings:04d}"
            path = self.dir / "findings" / f"{record['id']}.json"
            write_json(path, record)
        self.event("finding", id=record["id"], finding_kind=record["kind"], cls=record["cls"],
                   detail=record["detail"], seed=record["seed"], step=record["step"])
        return path


class CharacterLog:
    """Per-character trace and live dashboard status for one worker."""

    STATUS_EVERY = 10

    def __init__(self, session: SessionLog, worker: int, seed: int, goal: str) -> None:
        self.session = session
        self.worker = worker
        self.seed = seed
        self.goal = goal
        self.dir = session.dir / f"w{worker}" / goal / str(seed)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.trace = gzip.open(self.dir / "trace.jsonl.gz", "wt")
        self.recent: list[dict[str, Any]] = []
        self.started = time.monotonic()

    def decision(self, obs: Observation, decision: dict[str, Any]) -> None:
        entry = {"step": obs.step, "mode": obs.mode.value, "stage": obs.stage, "dlvl": obs.dlvl,
                 "pos": list(obs.pos), "hp": obs.hp,
                 "msg": " | ".join(r.strip() for r in obs.rows[:2] if r.strip()), **decision}
        self.trace.write(json.dumps(entry) + "\n")
        self.recent = (self.recent + [entry])[-30:]

    def status(self, game: Game, obs: Observation, steps: int, extra: dict[str, Any]) -> None:
        colors = game.mon.mem_get(game.abi.COLOR_RAM, 1000, game.io)
        elapsed = time.monotonic() - self.started
        write_json(self.session.dir / f"status-w{self.worker}.json", {
            "worker": self.worker, "seed": self.seed, "goal": self.goal, "steps": steps,
            "steps_per_s": round(steps / elapsed, 1) if elapsed else 0, **obs.summary(), **extra,
            "rows": obs.rows, "colors": bytes(c & 0x0F for c in colors).hex(),
            "decisions": self.recent, "updated": round(time.time(), 1)})

    def close(self) -> None:
        self.trace.close()
