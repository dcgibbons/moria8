"""``make playtest-queue`` (§23.4): the continuous playtest queue.

A long-running service keeps every active platform's race/class items
cycling through the queue's goal, one character per run, on a fixed worker
budget, and runs subqueues (§23.5) beside them. Everything lives under
``var/playtest-queue/`` (outside ``build/``, which ``make clean`` removes,
because run records are kept for good):

- ``state-<goal>.json``: the main queue for that goal: each platform's order,
  every item's streak, struggling mark, best result and first success; the
  runs in flight; the build being played.
- ``runs.jsonl``: one compact record per finished run, kept for good.
- ``queue.db``: the same records in SQLite, for the dashboard's queries
  (``records.py``); rebuilt from ``runs.jsonl`` when behind it.
- ``runs/<id>/``: a run's ``job.json``, trace, snapshots, findings, live
  status and ``result.json``; deleted ``retention_days`` after it ends.
- ``builds/<id>/``: a snapshot of the sources (``git archive`` of a commit,
  or the working tree for a subqueue) with its own ``build/``. A run plays
  its build's game with its build's bot, so editing this tree never changes
  a run in flight or the main queue's build.
- ``subqueues/<name>.json``: a submitted subqueue, its items and results;
  ``<name>.cancel`` cancels it.
- ``state-balrog.json``: the Balrog queue (§23.9): every combination past
  the M7 bar, its turn order, runs, wins and best run.
- ``balrog/<run>/``: a Balrog start, an M7 success's DL30 snapshot with
  its whole brain.
- ``service.json``: the service's heartbeat and what it is doing.

The config is ``playtest/queue.json``, read every tick.
"""

from __future__ import annotations

import argparse
import dataclasses
import gzip
import hashlib
import json
import os
import random
import shutil
import statistics
import signal
import sqlite3
import subprocess
import sys
import tarfile
import time
import traceback
from pathlib import Path
from typing import Any

from . import records
from .goals import (CHARACTERS, GOALS, QUALIFICATION_SEEDS, apply_variant, for_character, for_port, parse_variant,
                    required)
from .launch import ROOT
from .ports import PORTS

HOME = ROOT / "var" / "playtest-queue"
CONFIG = ROOT / "playtest" / "queue.json"
SUITES = ROOT / "playtest" / "suites"
TICK_SECONDS = 5.0
PAUSE_POLL_STEPS = 20       # a run looks for its pause file this often
# Past the M7 goal's clvl 25 and DL30, for the Balrog queue's deep game.
CLVL_MILESTONES = (5, 10, 15, 20, 25, 30, 35, 40)
DLVL_MILESTONES = (5, 8, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100)
RECALL_TEXT = "yanked"      # "You feel yourself yanked away!" (Word of Recall)
COUNTED = ("reached", "died", "budget", "finding", "error")   # outcomes that move an item
DEFAULTS: dict[str, Any] = {
    "workers": 24, "min_per_platform": 1, "platforms": ["c64"], "goal": "deep", "retry_cap": 3,
    "start_budget": 2_000_000, "budget_factor": 3, "budget_floor": 750_000, "retention_days": 14, "fetch_every_s": 600,
    "remote": "origin", "branch": "main", "fetch_url": "", "paused": False, "epoch": "",
    "balrog_workers": 0, "balrog_budget": 3_000_000,
}


def now() -> float:
    return round(time.time(), 1)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + f".tmp{os.getpid()}")
    tmp.write_text(json.dumps(data, indent=1, default=str))
    tmp.replace(path)


def load_config(path: Path = CONFIG) -> dict[str, Any]:
    config = dict(DEFAULTS)
    config.update(read_json(path) or {})
    return config


def combos(platform: str) -> list[str]:
    """The race/class items of one platform, in race then class table order."""
    del platform   # every platform allows every combination (core/tables.s)
    return list(CHARACTERS)


# -- builds -----------------------------------------------------------------------

def git(*args: str, check: bool = True, timeout: float = 120) -> str:
    done = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if check and done.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {done.stderr.strip()}")
    return done.stdout.strip()


def tree_state() -> dict[str, Any]:
    """This working tree's commit and whether it differs from it."""
    return {"commit": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain"))}


def build_env() -> dict[str, str]:
    """The tree's Kick Assembler for a snapshot's make (downloads stay here)."""
    env = dict(os.environ)
    jar = ROOT / "tools" / "kickass" / "KickAss.jar"
    if "KICKASS" not in env and jar.exists():
        env["KICKASS"] = str(jar)
    return env


def snapshot_build(platforms: list[str], source: str = "commit", home: Path = HOME) -> str:
    """Snapshot the sources and build ``platforms`` there; returns the build id.

    ``commit`` takes HEAD's tracked files (``git archive``); ``tree`` takes
    the working tree as it stands, edits and new files included (a subqueue
    testing a change). A build that exists already is reused."""
    state = tree_state()
    if source == "commit":
        build_id = state["commit"][:12]
    else:
        files = git("ls-files", "-co", "--exclude-standard", "-z").split("\0")
        digest = hashlib.sha256()
        for name in sorted(f for f in files if f):
            path = ROOT / name
            if path.is_file():
                digest.update(name.encode() + b"\0" + path.read_bytes())
        build_id = f"{state['commit'][:12]}-tree-{digest.hexdigest()[:8]}"
    out = home / "builds" / build_id
    meta = read_json(out / "build.json") or {}
    if set(platforms) <= set(meta.get("platforms", [])):
        return build_id
    src = out.with_name(build_id + f".partial{os.getpid()}")
    if not meta:
        shutil.rmtree(src, ignore_errors=True)
        src.mkdir(parents=True)
        if source == "commit":
            archive = subprocess.run(["git", "archive", "--format=tar", state["commit"]], cwd=ROOT,
                                     capture_output=True, check=True, timeout=300).stdout
            tar_path = src.with_suffix(".tar")
            tar_path.write_bytes(archive)
            with tarfile.open(tar_path) as tar:
                tar.extractall(src, filter="data")
            tar_path.unlink()
        else:
            for name in (f for f in files if f):
                path = ROOT / name
                if path.is_file():
                    (src / name).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, src / name)
    else:
        src = out
    for platform in platforms:
        if platform in meta.get("platforms", []):
            continue
        target = PORTS[platform].disk_target
        made = subprocess.run(["make", "-s", target], cwd=src, env=build_env(), capture_output=True,
                              text=True, timeout=1800)
        if made.returncode:
            raise RuntimeError(f"make {target} failed in build {build_id}: "
                               f"{(made.stderr or made.stdout).strip()[-2000:]}")
    meta = {"id": build_id, "commit": state["commit"], "dirty": source == "tree" and state["dirty"],
            "source": source, "platforms": sorted(set(meta.get("platforms", [])) | set(platforms)),
            "built": meta.get("built") or now()}
    write_json(src / "build.json", meta)
    if src != out:
        src.replace(out)
    return build_id


def build_meta(build_id: str, home: Path = HOME) -> dict[str, Any]:
    return read_json(home / "builds" / build_id / "build.json") or {}


# -- one run ------------------------------------------------------------------------

def run_one(run_dir: Path) -> int:
    """Play one job (``job.json``) in this process, from the build snapshot
    whose code this is; write ``result.json``. Runs under tools/isolated.sh."""
    from .dashboard import death
    from .game import derive_rng
    from .launch import Build, StaleDisk, build_identity, check_disk
    from .recorder import SessionLog
    from .session import Character, Result, load_brain
    from .worker import Snapshot, Worker

    job = read_json(run_dir / "job.json")
    port = PORTS[job["platform"]]
    goal = dataclasses.replace(for_port(for_character(GOALS[job["goal"]], job["character"]), port),
                               step_budget=job["step_budget"])
    goal = apply_variant(goal, job.get("variant"))   # a subqueue arm's changes (§23.10)

    class QueueCharacter(Character):
        """Records milestones, counts a depth stood on earlier toward the
        goal, and holds while the service pauses it (§23.5)."""

        def __init__(self, *args, **kwargs) -> None:   # type: ignore[no-untyped-def]
            super().__init__(*args, **kwargs)
            self.milestones: dict[str, int] = {}

        def observe(self, obs) -> None:   # type: ignore[no-untyped-def]
            found = []
            for level in CLVL_MILESTONES:
                if obs.clvl >= level and f"clvl{level}" not in self.milestones:
                    found.append(f"clvl{level}")
            for level in DLVL_MILESTONES:
                if self.result.max_dlvl >= level and f"dl{level}" not in self.milestones:
                    found.append(f"dl{level}")
            if "recall" not in self.milestones and any(RECALL_TEXT in row for row in obs.rows[:2]):
                found.append("recall")
            for name in found:
                self.milestones[name] = self.result.steps
                self.session.event("milestone", seed=self.seed, step=self.result.steps, milestone=name)
            if found:
                write_json(run_dir / "progress.json", {"milestones": self.milestones,
                                                       "clvl": obs.clvl, "max_dlvl": self.result.max_dlvl,
                                                       "steps": self.result.steps, "t": now()})
            if self.result.steps % PAUSE_POLL_STEPS == 0 and (run_dir / "pause").exists():
                write_json(run_dir / "paused.json", {"since": now(), "steps": self.result.steps})
                while (run_dir / "pause").exists():
                    time.sleep(2)
                (run_dir / "paused.json").unlink(missing_ok=True)

        def reached(self, obs) -> bool:   # type: ignore[no-untyped-def]
            if self.goal.name == "deep":
                return obs.clvl >= 25 and self.result.max_dlvl >= 30
            return self.goal.reached(obs)

        def start(self):   # type: ignore[no-untyped-def]
            """A Balrog run with a start (§23.9) goes on from the graduate's
            snapshot, with its whole brain, and new dice: the game's RNG is
            reseeded from this run's seed, so each run goes its own way."""
            resume = job.get("resume")
            if not resume:
                return super().start()
            source = Path(resume["snapshot"])
            local = run_dir / "start" / source.name   # take_snapshot deletes it later: a copy
            local.parent.mkdir(parents=True, exist_ok=True)
            for side in source.parent.glob(f"{source.stem}.*"):
                shutil.copy2(side, local.parent / side.name)
            snapshot = Snapshot.load(local)
            obs = self.worker.restore(snapshot)
            game = self.worker.game
            assert game is not None
            game.seed = self.seed
            game.mon.mem_set(game.abi.zp_rng_0, derive_rng(self.seed, 1), game.ram)
            self.brain = load_brain(local, self.goal)
            self.auditor.command_sp = snapshot.brain.get("auditor_command_sp")
            self.result.steps = int(resume["step"])
            self.result.max_dlvl = int(resume["dlvl"])
            self.snapshot = snapshot
            self.session.event("character_start", seed=self.seed, worker=self.worker.worker_id,
                               goal=self.goal.name, resumed_from=resume["run"], step=resume["step"])
            return obs

    started = time.time()
    record: dict[str, Any] = {"id": job["id"], "queue": job["queue"], "platform": job["platform"],
                              "character": job["character"], "goal": job["goal"], "seed": job["seed"],
                              "step_budget": job["step_budget"], "build": job["build"],
                              "commit": job["commit"], "dirty": job["dirty"], "started": job["started"],
                              "epoch": job.get("epoch", "")}
    if job.get("variant") or job.get("arm"):
        record.update({"variant": job.get("variant") or "", "arm": job.get("arm"),
                       "tactics": sorted(goal.tactics)})
    if job.get("resume"):
        record["resumed_from"] = {k: job["resume"][k] for k in ("run", "step", "dlvl")}
    build = Build.shipping(port)
    try:
        check_disk(build)
    except (StaleDisk, OSError) as exc:
        write_json(run_dir / "result.json", {**record, "outcome": "stale", "detail": str(exc), "ended": now()})
        return 2
    session = SessionLog(run_dir, {"mode": "queue", "goal": goal.name, "character": job["character"],
                                   "port": port.name, "build": build_identity(build), "job": job,
                                   "started": time.strftime("%Y-%m-%dT%H:%M:%S")})
    character: QueueCharacter | None = None
    try:
        worker = Worker(run_dir, job.get("slot", 0), build=build)
        character = QueueCharacter(worker, goal, job["seed"], session)
        result = character.play()
    except Exception as exc:   # anything but a GameFault: a harness error
        session.event("worker_error", seed=job["seed"], error=repr(exc), traceback=traceback.format_exc())
        result = Result(job["seed"], outcome="error", findings=[f"error: {exc!r}"])
    session.character(result.__dict__)
    traces = sorted(run_dir.glob("w*/*/*/trace.jsonl.gz"))
    record.update({"outcome": result.outcome, "steps": result.steps, "clvl": result.clvl,
                   "dlvl": result.dlvl, "max_dlvl": result.max_dlvl, "restarts": result.restarts,
                   "findings": result.findings, "wall_s": round(time.time() - started, 1),
                   "milestones": character.milestones if character else {},
                   "features": {**(features(traces[0]) if traces else {}),
                                "casts": character.brain.magic.ledger if character else {},
                                "missiles": character.brain.missiles if character else {},
                                "kit": kit(character.brain) if character else {}},
                   "ended": now()})
    if result.outcome == "died" and traces:
        detail = death(traces[0])
        record["death"] = {k: detail.get(k) for k in ("cause", "killer", "clw", "oil", "mp", "mmp", "last")}
    session.summary["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    session.save_summary()
    write_json(run_dir / "result.json", record)
    return 0


def kit(brain: Any) -> dict[str, Any]:
    """What the character carried at the end, for the strategy heuristics
    (§23.7): weapon, armour, launcher, potions, oil, books, spells known."""
    return {"weapon": list(brain.weapon), "armour": dict(brain.armour), "launcher": brain.launcher,
            "ammo": brain.ammo, "clw": brain.clw, "strong": dict(brain.strong), "oil": brain.oil,
            "books": list(brain.magic.books or []), "spells": sorted(brain.magic.known)}


def features(trace: Path) -> dict[str, Any]:
    """Counts for the feature grid (§23.6) from a run's trace: decisions by
    brain layer, and the deepest level and highest level seen."""
    layers: dict[str, int] = {}
    try:
        with gzip.open(trace, "rt") as handle:
            for line in handle:
                try:
                    layer = json.loads(line).get("layer") or "?"
                except ValueError:
                    break
                layers[layer] = layers.get(layer, 0) + 1
    except (OSError, EOFError):
        pass
    return {"layers": layers}


# -- the queue's state ---------------------------------------------------------------

def new_item() -> dict[str, Any]:
    return {"runs": 0, "successes": 0, "streak": 0, "fails_in_row": 0, "struggling": False,
            "in_flight": None, "last": None, "best": None, "success": None}


def deepest(record: dict[str, Any]) -> str | None:
    """The deepest milestone a run reached, by order of the M7 goal."""
    order = [f"dl{d}" for d in DLVL_MILESTONES] + [f"clvl{c}" for c in CLVL_MILESTONES]
    reached = record.get("milestones") or {}
    best = None
    for kind in ("clvl", "dl"):
        names = [n for n in order if n.startswith(kind) and n in reached]
        if names:
            best = (best + " " if best else "") + names[-1]
    return best


def state_path(home: Path, goal: str, epoch: str = "") -> Path:
    """The main queue's state for ``goal`` in ``epoch`` (config "epoch"): a new
    epoch starts its items, streaks and successes afresh, the earlier state
    file kept beside it (maintainer, 2026-11-01: reset the statistics once
    the game fixes change what a run means; run records are never deleted)."""
    return home / (f"state-{goal}-{epoch}.json" if epoch else f"state-{goal}.json")


class Queue:
    """The main queue for one goal and epoch: each platform's order and every item."""

    def __init__(self, goal: str, home: Path = HOME, epoch: str = "") -> None:
        self.goal = goal
        self.epoch = epoch
        self.path = state_path(home, goal, epoch)
        self.state: dict[str, Any] = read_json(self.path) or {"goal": goal, "created": now(), "platforms": {},
                                                               "budget": None, "slowest_success": None}

    def save(self) -> None:
        write_json(self.path, self.state)

    def platform(self, name: str) -> dict[str, Any]:
        entry = self.state["platforms"].setdefault(name, {"order": [], "items": {}, "cycle": 1, "cycle_done": []})
        for combo in combos(name):
            if combo not in entry["items"]:
                entry["items"][combo] = new_item()
                entry["order"].append(combo)
        return entry

    def budget(self, config: dict[str, Any]) -> int:
        """2,000,000 steps until a success; then 3x the slowest success (§23.3),
        never below ``budget_floor`` (the maintainer, 2026-10-31: 3x the first
        success, 502,428, cut off slow characters still surviving on DL17-19)."""
        slowest = self.state.get("slowest_success")
        if not slowest:
            return int(config["start_budget"])
        return max(int(slowest * config["budget_factor"]), int(config["budget_floor"]))

    def head(self, platform: str) -> str | None:
        entry = self.platform(platform)
        return entry["order"][0] if entry["order"] else None

    def take(self, platform: str, run_id: str) -> str:
        entry = self.platform(platform)
        combo = entry["order"].pop(0)
        entry["items"][combo]["in_flight"] = run_id
        return combo

    def give_back(self, platform: str, combo: str) -> None:
        """A run that did not count (stale build, service restart, cancel):
        the item goes back to the head, its streak untouched."""
        entry = self.platform(platform)
        entry["items"][combo]["in_flight"] = None
        if combo not in entry["order"]:
            entry["order"].insert(0, combo)

    def finish(self, record: dict[str, Any], retry_cap: int) -> None:
        """Move an item by its run's outcome (§23.4): a success to the back; a
        failure to the head, up to ``retry_cap`` in a row, then to the back
        marked struggling."""
        platform, combo = record["platform"], record["character"]
        if record["outcome"] not in COUNTED:
            self.give_back(platform, combo)
            return
        entry = self.platform(platform)
        item = entry["items"][combo]
        item["in_flight"] = None
        item["runs"] += 1
        item["last"] = {k: record.get(k) for k in ("id", "outcome", "steps", "clvl", "max_dlvl", "ended",
                                                   "commit", "seed")}
        item["last"]["deepest"] = deepest(record)
        item["last"]["cause"] = (record.get("death") or {}).get("cause")
        progress = (record.get("max_dlvl", 0), record.get("clvl", 0))
        best = item["best"]
        if best is None or progress > (best.get("max_dlvl", 0), best.get("clvl", 0)):
            item["best"] = {"max_dlvl": progress[0], "clvl": progress[1], "run": record["id"],
                            "deepest": deepest(record), "commit": record.get("commit")}
        if record["outcome"] == "reached":
            item["successes"] += 1
            item["streak"] = max(item["streak"], 0) + 1
            item["fails_in_row"] = 0
            item["struggling"] = False
            if item["success"] is None:
                item["success"] = {"run": record["id"], "commit": record.get("commit"), "ended": record.get("ended"),
                                   "steps": record.get("steps")}
            slowest = self.state.get("slowest_success") or 0
            self.state["slowest_success"] = max(slowest, record.get("steps", 0))
            entry["order"].append(combo)
        else:
            item["streak"] = min(item["streak"], 0) - 1
            item["fails_in_row"] += 1
            if item["fails_in_row"] > retry_cap:
                item["struggling"] = True
                item["fails_in_row"] = 0
                entry["order"].append(combo)
            else:
                entry["order"].insert(0, combo)
        if combo not in entry["cycle_done"]:
            entry["cycle_done"].append(combo)
        if len(entry["cycle_done"]) >= len(entry["items"]):
            entry["cycle"] += 1
            entry["cycle_done"] = []


class Balrog:
    """The Balrog queue (M8, §23.9; maintainer 2026-11-01): a combination
    that meets the M7 bar joins it for good, whatever the epoch, and up to
    ``balrog_workers`` runs play the balrog goal, taking turns across the
    graduates with a new seed each run. It gathers data on the deep game; a
    win is unlikely until the bot is much better."""

    def __init__(self, home: Path = HOME) -> None:
        self.path = home / "state-balrog.json"
        self.state: dict[str, Any] = read_json(self.path) or {"created": now(), "items": {}, "order": []}

    def save(self) -> None:
        write_json(self.path, self.state)

    def graduate(self, platform: str, combo: str, success: dict[str, Any]) -> bool:
        """Add a combination; False if it is in already."""
        key = f"{platform}/{combo}"
        if key in self.state["items"]:
            return False
        self.state["items"][key] = {"platform": platform, "character": combo, "graduated": success,
                                    "runs": 0, "won": 0, "last": None, "best": None}
        self.state["order"].append(key)
        return True

    def set_start(self, record: dict[str, Any], start: dict[str, Any]) -> None:
        """An M7 success's snapshot becomes its combination's start, the
        newest replacing the one before (graduating it if need be)."""
        self.graduate(record["platform"], record["character"],
                      {"run": record["id"], "commit": record.get("commit"), "ended": record.get("ended"),
                       "steps": record.get("steps"), "epoch": record.get("epoch", "")})
        self.state["items"][f"{record['platform']}/{record['character']}"]["start"] = start

    def take(self) -> dict[str, Any]:
        """The next graduate, which goes to the back."""
        key = self.state["order"].pop(0)
        self.state["order"].append(key)
        return self.state["items"][key]

    def finish(self, record: dict[str, Any]) -> None:
        item = self.state["items"].get(f"{record['platform']}/{record['character']}")
        if item is None or record["outcome"] not in COUNTED:
            return
        item["runs"] += 1
        item["won"] += record["outcome"] == "reached"
        item["last"] = {k: record.get(k) for k in ("id", "outcome", "steps", "clvl", "max_dlvl", "ended", "seed")}
        item["last"].update(deepest=deepest(record), cause=(record.get("death") or {}).get("cause"))
        best = item["best"]
        progress = (record.get("max_dlvl") or 0, record.get("clvl") or 0)
        if best is None or progress > (best["max_dlvl"], best["clvl"]):
            item["best"] = {"max_dlvl": progress[0], "clvl": progress[1], "run": record["id"],
                            "deepest": deepest(record)}


# -- subqueues ---------------------------------------------------------------------

def parse_seeds(text: str) -> list[int]:
    seeds: list[int] = []
    for part in text.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            seeds += list(range(int(lo), int(hi) + 1))
        elif part:
            seeds.append(int(part))
    return seeds


def regress_items(platform: str, character: str | None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Every frozen suite of ``platform`` (one character's, if given) as items."""
    items, suites = [], {}
    for path in sorted(SUITES.glob("*.json")):
        suite = json.loads(path.read_text())
        who = suite.get("character", "half-troll-warrior")
        if suite.get("port", "c64") != platform or character not in (None, who):
            continue
        goal = for_character(GOALS[suite["goal"]], who)
        suites[path.stem] = {"required": suite.get("required", required(goal, len(suite["seeds"]))),
                             "seeds": len(suite["seeds"])}
        items += [{"suite": path.stem, "goal": suite["goal"], "character": who, "platform": platform,
                   "seed": seed, "step_budget": suite["step_budget"]} for seed in suite["seeds"]]
    return items, suites


def submit(name: str, items: list[dict[str, Any]], *, build: str, suites: dict[str, Any] | None = None,
           home: Path = HOME, note: str = "", **extra: Any) -> Path:
    """Write a subqueue; ``extra`` holds its ``variant`` or its A/B arms (``ab``)."""
    path = home / "subqueues" / f"{name}.json"
    if path.exists():
        raise FileExistsError(f"subqueue {name} exists: {path}")
    write_json(path, {"name": name, "created": now(), "build": build, "note": note, "items": items,
                      "next": 0, "results": [], "suites": suites or {}, "done": False, "cancelled": False,
                      **extra})
    return path


def group_key(item: dict[str, Any]) -> str:
    """A subqueue item's report group: its frozen suite, or goal, character
    and platform, and its A/B arm or variant (§23.10)."""
    key = item.get("suite") or f"{item['goal']} {item['character']} {item['platform']}"
    label = item.get("arm") or item.get("variant")
    return f"{key} [{label}]" if label else key


def subqueue_report(sub: dict[str, Any]) -> dict[str, Any]:
    """Per goal and character (or frozen suite, or arm): reached of finished, and the bar."""
    groups: dict[str, dict[str, Any]] = {}
    for item in sub["items"]:
        key = group_key(item)
        groups.setdefault(key, {"reached": 0, "done": 0, "total": 0})["total"] += 1
    for result in sub["results"]:
        key = group_key(result)
        group = groups.setdefault(key, {"reached": 0, "done": 0, "total": 0})
        group["done"] += 1
        group["reached"] += result["outcome"] == "reached"
    for key, group in groups.items():
        if key in sub.get("suites", {}):
            group["required"] = sub["suites"][key]["required"]
            group["passed"] = group["reached"] >= group["required"] if group["done"] == group["total"] else None
    return groups


ARMS = ("A", "B")


def ab_items(goal: str, characters: list[str], platforms: list[str], seeds: dict[tuple[str, str], list[int]],
             variants: dict[str, str], step_budget: int | None = None) -> list[dict[str, Any]]:
    """An A/B subqueue's items (§23.10): every character and platform on the
    same seeds under both arms, so each arm plays the same maps, interleaved
    seed by seed (A then B) so both arms progress together. ``seeds`` maps
    (platform, character) to that pair's seeds. A variant's ``step_budget``
    is its arm's budget; else ``step_budget``, else the goal's for the port."""
    items = []
    depth = max((len(s) for s in seeds.values()), default=0)
    for n in range(depth):
        for platform in platforms:
            for name in characters:
                pair = seeds[(platform, name)]
                if n >= len(pair):
                    continue
                for arm in ARMS:
                    played = apply_variant(for_port(for_character(GOALS[goal], name), PORTS[platform]),
                                           variants[arm])
                    own = any(field == "step_budget" for field, _ in parse_variant(variants[arm]))
                    budget = played.step_budget if own else step_budget or played.step_budget
                    items.append({"goal": goal, "character": name, "platform": platform, "seed": pair[n],
                                  "step_budget": budget, "arm": arm, "variant": variants[arm]})
    return items


def median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def ab_summary(results: list[dict[str, Any]], total: int) -> dict[str, Any]:
    deaths: dict[str, int] = {}
    for r in results:
        if r["outcome"] == "died":
            cause = r.get("cause") or "unknown"
            deaths[cause] = deaths.get(cause, 0) + 1
    outcomes: dict[str, int] = {}
    for r in results:
        outcomes[r["outcome"]] = outcomes.get(r["outcome"], 0) + 1
    return {"reached": sum(r["outcome"] == "reached" for r in results), "done": len(results), "total": total,
            "median_max_dlvl": median([r.get("max_dlvl") or 0 for r in results]),
            "median_clvl": median([r.get("clvl") or 0 for r in results]),
            "outcomes": dict(sorted(outcomes.items())),
            "deaths": dict(sorted(deaths.items(), key=lambda kv: (-kv[1], kv[0])))}


def ab_report(sub: dict[str, Any]) -> dict[str, Any]:
    """An A/B subqueue's comparison (§23.10): per arm and per character, the
    runs that reached the goal, median deepest level and character level,
    and deaths by cause; then the seeds both arms finished, paired: where
    only one reached the goal, and where one went deeper (deepest level,
    then character level)."""
    by_arm: dict[str, list[dict[str, Any]]] = {arm: [] for arm in ARMS}
    for r in sub["results"]:
        if r.get("arm") in by_arm:
            by_arm[r["arm"]].append(r)
    totals = {arm: sum(i.get("arm") == arm for i in sub["items"]) for arm in ARMS}
    arms = {arm: {"variant": (sub.get("ab") or {}).get(arm, ""), **ab_summary(by_arm[arm], totals[arm])}
            for arm in ARMS}
    characters: dict[str, dict[str, Any]] = {}
    for name in sorted({i["character"] for i in sub["items"]}):
        characters[name] = {}
        for arm in ARMS:
            mine = [r for r in by_arm[arm] if r["character"] == name]
            total = sum(i.get("arm") == arm and i["character"] == name for i in sub["items"])
            summary = ab_summary(mine, total)
            characters[name][arm] = {k: summary[k] for k in ("reached", "done", "total", "median_max_dlvl",
                                                             "median_clvl")}
    keyed = {arm: {(r["platform"], r["character"], r["seed"]): r for r in by_arm[arm]} for arm in ARMS}
    paired = {"pairs": 0, "only_a_reached": [], "only_b_reached": [], "a_deeper": [], "b_deeper": [],
              "same_depth": 0}
    for key in sorted(set(keyed["A"]) & set(keyed["B"])):
        a, b = keyed["A"][key], keyed["B"][key]
        label = f"{key[1]} {key[2]}" + (f" {key[0]}" if len({k[0] for k in keyed["A"]}) > 1 else "")
        paired["pairs"] += 1
        a_won, b_won = a["outcome"] == "reached", b["outcome"] == "reached"
        if a_won != b_won:
            paired["only_a_reached" if a_won else "only_b_reached"].append(label)
        depth_a = (a.get("max_dlvl") or 0, a.get("clvl") or 0)
        depth_b = (b.get("max_dlvl") or 0, b.get("clvl") or 0)
        if depth_a == depth_b:
            paired["same_depth"] += 1
        else:
            paired["a_deeper" if depth_a > depth_b else "b_deeper"].append(label)
    return {"arms": arms, "characters": characters, "paired": paired}


def format_ab(report: dict[str, Any]) -> str:
    """``ab_report`` as text for the terminal."""
    def num(value: float | None) -> str:
        return "-" if value is None else f"{value:g}"
    lines = []
    for arm, a in report["arms"].items():
        deaths = ", ".join(f"{cause} {n}" for cause, n in a["deaths"].items()) or "none"
        total = f" of {a['total']}" if a["total"] != a["done"] else ""
        lines.append(f"arm {arm} [{a['variant'] or 'as defined'}]: reached {a['reached']}/{a['done']}{total}"
                     f", median max DL {num(a['median_max_dlvl'])}, median clvl {num(a['median_clvl'])}; "
                     f"deaths: {deaths}")
    for name, arms in report["characters"].items():
        lines.append(f"  {name:22} " + "   ".join(
            f"{arm} {c['reached']}/{c['done']} DL {num(c['median_max_dlvl'])} clvl {num(c['median_clvl'])}"
            for arm, c in arms.items()))
    p = report["paired"]
    lines.append(f"paired seeds: {p['pairs']}; only A reached {len(p['only_a_reached'])}, only B reached "
                 f"{len(p['only_b_reached'])}; A deeper {len(p['a_deeper'])}, B deeper {len(p['b_deeper'])}, "
                 f"same {p['same_depth']}")
    for field, title in (("only_a_reached", "only A reached"), ("only_b_reached", "only B reached"),
                         ("a_deeper", "A deeper"), ("b_deeper", "B deeper")):
        if p[field]:
            lines.append(f"  {title}: {', '.join(p[field])}")
    return "\n".join(lines)


# -- the service --------------------------------------------------------------------

def proc_alive(pid: int, run_dir: str) -> bool:
    """``pid`` is still the run process for ``run_dir`` (not a reused pid)."""
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace")
    except OSError:
        return False
    return run_dir in cmdline


class Service:
    def __init__(self, home: Path = HOME, config_path: Path = CONFIG) -> None:
        self.home = home
        self.config_path = config_path
        self.config = load_config(config_path)
        self.running_path = home / "running.json"
        # Runs in flight, across service restarts: run id -> job (with pid).
        self.running: dict[str, dict[str, Any]] = read_json(self.running_path) or {}
        # The build played before a restart, kept: a restart while the tree is
        # mid-edit must not snapshot that edit (2026-10-31: a service restart
        # played another agent's unfinished game change for an hour).
        previous = (read_json(home / "service.json") or {}).get("build")
        self.build_id: str | None = previous if previous and build_meta(previous, home) else None
        self.build_state: dict[str, Any] = {}
        self.last_fetch = 0.0
        self.last_sweep = 0.0
        self.stopping = False
        self.log_lines: list[str] = []
        self.backoff: dict[str, float] = {}   # platform -> time a stale build may be retried
        self.balrog = Balrog(home)

    # -- bookkeeping

    def log(self, text: str) -> None:
        line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {text}"
        print(line, flush=True)
        self.log_lines = (self.log_lines + [line])[-40:]

    def save_running(self) -> None:
        write_json(self.running_path, self.running)

    def heartbeat(self) -> None:
        write_json(self.home / "service.json", {
            "pid": os.getpid(), "updated": now(), "config": self.config, "build": self.build_id,
            "build_state": self.build_state, "log": self.log_lines})

    # -- builds and origin

    def refresh_build(self, force: bool = False) -> None:
        """Fetch ``origin``; fast-forward and rebuild when the tree is clean and
        its commit is contained in ``origin/main`` (§23.4). Otherwise keep
        playing the current build and record that it is behind. A rebuild
        flag (``make playtest-queue-rebuild``) snapshots the tree as it stands."""
        if not force and time.time() - self.last_fetch < self.config["fetch_every_s"] \
                and not (self.home / "rebuild").exists():
            return
        self.last_fetch = time.time()
        remote, branch = self.config["remote"], self.config["branch"]
        upstream = f"{remote}/{branch}"
        state: dict[str, Any] = {"checked": now(), "upstream": upstream}
        try:
            # A URL fetches without the user's SSH agent (a systemd unit has none)
            # into the same remote-tracking branch.
            source = self.config["fetch_url"] or remote
            git("fetch", "--quiet", source, f"+refs/heads/{branch}:refs/remotes/{upstream}", timeout=300)
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            state["fetch_error"] = str(exc)
        try:
            tree = tree_state()
            contained = subprocess.run(["git", "merge-base", "--is-ancestor", "HEAD", upstream],
                                       cwd=ROOT).returncode == 0
            behind = int(git("rev-list", "--count", f"HEAD..{upstream}"))
            ahead = int(git("rev-list", "--count", f"{upstream}..HEAD"))
            state.update({"head": tree["commit"], "dirty": tree["dirty"], "contained": contained,
                          "behind": behind, "ahead": ahead})
            if behind and contained and not tree["dirty"]:
                git("merge", "--ff-only", "--quiet", upstream)
                self.log(f"fast-forwarded to {upstream} ({behind} commits)")
                state.update({"head": git("rev-parse", "HEAD"), "behind": 0})
                tree = tree_state()
            current = build_meta(self.build_id, self.home) if self.build_id else {}
            wanted = current.get("commit") != tree["commit"] or not set(self.config["platforms"]) <= set(
                current.get("platforms", []))
            rebuild = (self.home / "rebuild").exists()   # make playtest-queue-rebuild
            if self.build_id is None or rebuild or (wanted and contained and not tree["dirty"]):
                source = "tree" if tree["dirty"] or rebuild else "commit"
                (self.home / "rebuild").unlink(missing_ok=True)
                self.log(f"building {tree['commit'][:12]} ({source}) for {', '.join(self.config['platforms'])}")
                self.build_id = snapshot_build(self.config["platforms"], source, self.home)
                self.log(f"playing build {self.build_id}")
        except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
            state["error"] = str(exc)[-2000:]
            self.log(f"build check failed: {str(exc)[:300]}")
        meta = build_meta(self.build_id, self.home) if self.build_id else {}
        state["playing"] = meta
        state["stale_build"] = bool(meta) and meta.get("commit") != state.get("head")
        self.build_state = state

    # -- runs

    def free_slot(self) -> int:
        used = {job["slot"] for job in self.running.values()}
        return next(n for n in range(len(used) + 1) if n not in used)

    def start(self, job: dict[str, Any]) -> None:
        """Start one run as its own process from its build snapshot."""
        build = self.home / "builds" / job["build"]
        run_dir = self.home / "runs" / job["id"]
        run_dir.mkdir(parents=True, exist_ok=True)
        job["slot"] = self.free_slot()
        write_json(run_dir / "job.json", job)
        env = dict(os.environ, PYTHONPATH=str(build / "playtest"), PYTHONDONTWRITEBYTECODE="1")
        env.pop("MORIA8_ISOLATED", None)
        log = (run_dir / "run.log").open("a")
        proc = subprocess.Popen([str(build / "tools" / "isolated.sh"), sys.executable, "-m", "moria_playtest.queue",
                                 "run", str(run_dir)], cwd=build, env=env, stdout=log, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, start_new_session=True)
        log.close()
        job["pid"] = proc.pid
        job["paused"] = False
        self.running[job["id"]] = job
        self.save_running()
        self.log(f"start {job['id']} ({job['queue']}, slot {job['slot']}, budget {job['step_budget']})")

    def new_job(self, queue: str, platform: str, character: str, goal: str, seed: int, budget: int,
                build_id: str, **extra: Any) -> dict[str, Any]:
        meta = build_meta(build_id, self.home)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        # The arm too, and a suffix if still taken: an A/B pair shares its
        # character and seed, and both arms starting in the same second shared
        # one run directory and overwrote each other (ab1, 2026-11-01).
        arm = extra.get("arm")
        base = f"{stamp}-{queue}-{platform}-{character}-{seed}" + (f"-{arm}" if arm else "")
        run_id, n = base, 1
        while run_id in self.running or (self.home / "runs" / run_id).exists():
            n += 1
            run_id = f"{base}-{n}"
        return {"id": run_id, "queue": queue, "platform": platform, "character": character, "goal": goal,
                "seed": seed, "step_budget": budget, "build": build_id, "commit": meta.get("commit"),
                "dirty": meta.get("dirty", False), "started": now(), "epoch": self.config.get("epoch", ""), **extra}

    def reap(self, queue: Queue, subs: dict[str, dict[str, Any]], adopting: bool = False) -> None:
        """Collect finished runs. A run whose process is gone without a
        result died under the service (an error), or before this service
        started (abandoned: not counted)."""
        for run_id, job in list(self.running.items()):
            run_dir = self.home / "runs" / run_id
            record = read_json(run_dir / "result.json")
            if record is None:
                if proc_alive(job["pid"], str(run_dir)):
                    continue
                time.sleep(0.2)
                record = read_json(run_dir / "result.json")
            if record is None:
                outcome = "cancelled" if job.get("cancelled") else "abandoned" if adopting else "error"
                record = {**{k: job.get(k) for k in ("id", "queue", "platform", "character", "goal", "seed",
                                                     "step_budget", "build", "commit", "dirty", "started")},
                          "outcome": outcome, "findings": [f"error: run process exited without a result "
                                                           f"(see {run_dir.name}/run.log)"], "ended": now()}
                write_json(run_dir / "result.json", record)
            del self.running[run_id]
            self.save_running()
            if record["outcome"] == "stale":
                self.backoff[job["platform"]] = time.time() + 60
            if job.get("suite"):
                record["suite"] = job["suite"]
            with (self.home / "runs.jsonl").open("a") as fh:
                fh.write(json.dumps(record, default=str) + "\n")
            try:
                records.insert(record, self.home)
            except (sqlite3.Error, OSError) as exc:   # runs.jsonl has it; the next start imports it
                self.log(f"queue.db insert failed for {run_id}: {exc}")
            self.log(f"end {run_id}: {record['outcome']} clvl {record.get('clvl')} "
                     f"max DL {record.get('max_dlvl')} steps {record.get('steps')}")
            if job["queue"] == "main":
                if job["goal"] == queue.goal and job.get("epoch", "") == queue.epoch:
                    queue.finish(record, self.config["retry_cap"])
                    queue.save()
                if job["goal"] == "deep" and record["outcome"] == "reached":
                    self.balrog_start(record)
                continue
            if job["queue"] == "balrog":
                self.balrog.finish(record)
                self.balrog.save()
                continue
            sub = subs.get(job["queue"])
            if sub is None:
                continue
            if record["outcome"] in ("stale", "abandoned"):
                sub["requeue"] = sub.get("requeue", []) + [job["item"]]
            elif record["outcome"] != "cancelled":   # a cancelled run is no result
                sub["results"].append({**sub["items"][job["item"]],
                                       **{k: record.get(k) for k in ("id", "outcome", "steps", "clvl", "max_dlvl")},
                                       "cause": (record.get("death") or {}).get("cause")})
            self.save_sub(sub)

    def sync_records(self) -> None:
        """Import runs.jsonl into queue.db when the database is missing or
        behind it (a first start, a lost database, failed inserts)."""
        log = self.home / "runs.jsonl"
        try:
            with log.open() as fh:
                lines = sum(1 for _ in fh)
        except OSError:
            return
        try:
            if records.count(self.home) < lines:
                self.log(f"queue.db: imported {records.import_jsonl(log, self.home)} records from runs.jsonl")
        except (sqlite3.Error, OSError) as exc:
            self.log(f"queue.db import failed: {exc}")

    def pause(self, run_id: str, paused: bool) -> None:
        job = self.running[run_id]
        flag = self.home / "runs" / run_id / "pause"
        if paused:
            flag.touch()
        else:
            flag.unlink(missing_ok=True)
        job["paused"] = paused
        self.save_running()
        self.log(f"{'pause' if paused else 'resume'} {run_id}")

    def stop_run(self, run_id: str) -> None:
        """End a run now (a cancelled subqueue): its whole process group."""
        job = self.running[run_id]
        job["cancelled"] = True   # reap records "cancelled", not an error
        self.save_running()
        (self.home / "runs" / run_id / "pause").unlink(missing_ok=True)
        try:
            os.killpg(job["pid"], signal.SIGTERM)
        except OSError:
            pass

    # -- subqueues

    def load_subs(self) -> dict[str, dict[str, Any]]:
        subs = {}
        for path in sorted((self.home / "subqueues").glob("*.json")):
            sub = read_json(path)
            if not sub or sub.get("done"):
                continue
            if path.with_suffix(".cancel").exists() and not sub.get("cancelled"):
                sub["cancelled"] = True
                for run_id, job in self.running.items():
                    if job["queue"] == sub["name"]:
                        self.stop_run(run_id)
                self.log(f"cancel subqueue {sub['name']}")
            subs[sub["name"]] = sub
        return subs

    def save_sub(self, sub: dict[str, Any]) -> None:
        write_json(self.home / "subqueues" / f"{sub['name']}.json", sub)

    def sub_pending(self, sub: dict[str, Any]) -> int:
        if sub.get("cancelled"):
            return 0
        return len(sub["items"]) - sub["next"] + len(sub.get("requeue", []))

    def next_sub_item(self, sub: dict[str, Any]) -> int:
        if sub.get("requeue"):
            return sub["requeue"].pop(0)
        sub["next"] += 1
        return sub["next"] - 1

    def finish_subs(self, subs: dict[str, dict[str, Any]]) -> None:
        for sub in subs.values():
            in_flight = any(job["queue"] == sub["name"] for job in self.running.values())
            if not in_flight and (sub.get("cancelled") or self.sub_pending(sub) == 0):
                sub["done"] = True
                sub["finished"] = now()
                sub["report"] = subqueue_report(sub)
                if sub.get("ab"):
                    sub["ab_report"] = ab_report(sub)
                self.save_sub(sub)
                self.log(f"subqueue {sub['name']} {'cancelled' if sub.get('cancelled') else 'drained'}: "
                         f"{json.dumps(sub['report'])}")

    def balrog_start(self, record: dict[str, Any]) -> None:
        """Keep an M7 success's last snapshot, taken on DL30 with the whole
        brain beside it, as its combination's Balrog start (§23.9). Runs
        keep snapshots for ``retention_days``; a start is kept while used."""
        from .session import brain_pickle_path
        snaps = [p for p in (self.home / "runs" / record["id"]).glob("w*/snapshots/*.vsf")
                 if brain_pickle_path(p).exists()]
        if not snaps:
            return   # a build from before brains were saved: it plays from the start
        source = max(snaps, key=lambda p: p.stat().st_mtime)
        dest = self.home / "balrog" / record["id"]
        dest.mkdir(parents=True, exist_ok=True)
        for side in source.parent.glob(f"{source.stem}.*"):
            shutil.copy2(side, dest / side.name)
        saved = read_json(source.with_suffix(".brain.json")) or {}
        self.balrog.set_start(record, {"run": record["id"], "build": record["build"],
                                       "snapshot": str(dest / source.name), "step": saved.get("step", 0),
                                       "dlvl": saved.get("dlvl", 0), "set": now()})
        self.balrog.save()
        self.log(f"balrog queue: {record['character']} starts from {source.name} (run {record['id']})")

    def graduate(self, queue: Queue) -> None:
        """Every combination with an M7 success joins the Balrog queue."""
        if queue.goal != "deep":
            return
        for platform, entry in queue.state["platforms"].items():
            for combo, item in entry["items"].items():
                if item["success"] and self.balrog.graduate(platform, combo, {**item["success"],
                                                                              "epoch": queue.epoch}):
                    self.balrog.save()
                    self.log(f"balrog queue: {combo} on {platform} joins (M7 run {item['success']['run']})")

    # -- scheduling

    def schedule(self, queue: Queue, subs: dict[str, dict[str, Any]]) -> None:
        """Workers (§23.4, §23.5): subqueues borrow from the main queue's
        budget; the main queue shrinks toward one worker per active platform
        by pausing its newest runs, and resumes them as subqueues drain."""
        config = self.config
        platforms = list(config["platforms"])
        total = int(config["workers"])
        minimum = int(config["min_per_platform"]) * len(platforms)
        if config.get("paused"):
            for run_id, job in self.running.items():
                if not job["paused"]:
                    self.pause(run_id, True)
            return
        for run_id, job in list(self.running.items()):
            if job["queue"] != "main" and job["paused"]:
                self.pause(run_id, False)
        main = [r for r, j in self.running.items() if j["queue"] == "main"]
        main_active = [r for r in main if not self.running[r]["paused"]]
        main_paused = sorted((r for r in main if self.running[r]["paused"]),
                             key=lambda r: self.running[r]["started"])
        sub_running = sum(1 for j in self.running.values() if j["queue"] != "main")
        # The Balrog queue's workers come out of the total, as a subqueue's do.
        balrog_running = sum(1 for j in self.running.values() if j["queue"] == "balrog")
        balrog_pending = 0
        if self.balrog.state["order"] and self.build_id and max(self.backoff.values(), default=0) < time.time():
            balrog_pending = max(0, int(config["balrog_workers"]) - balrog_running)
        pending = sum(self.sub_pending(sub) for sub in subs.values()) + balrog_pending
        target = max(minimum, total - sub_running - pending)
        if len(main_active) > target:
            for run_id in sorted(main_active, key=lambda r: self.running[r]["started"])[target:]:
                self.pause(run_id, True)
            main_active = main_active[:target]
        while len(main_active) < target and main_paused:
            run_id = main_paused.pop(0)
            self.pause(run_id, False)
            main_active.append(run_id)
        active = sum(1 for j in self.running.values() if not j["paused"])
        while active < total:
            per_platform = {p: sum(1 for r in main_active if self.running[r]["platform"] == p) for p in platforms}
            ready = [p for p in platforms if queue.head(p) is not None and self.backoff.get(p, 0) < time.time()]
            ready.sort(key=lambda p: per_platform[p])
            if ready and len(main_active) < minimum and self.build_id:
                run_id = self.start_main(queue, ready[0])
            elif balrog_pending:
                self.start_balrog()
                balrog_pending -= 1
                pending -= 1
                active += 1
                continue
            elif pending:
                sub = next(s for s in subs.values() if self.sub_pending(s))
                index = self.next_sub_item(sub)
                item = sub["items"][index]
                job = self.new_job(sub["name"], item["platform"], item["character"], item["goal"], item["seed"],
                                   item["step_budget"], sub["build"], item=index, suite=item.get("suite"),
                                   **{k: item[k] for k in ("variant", "arm") if item.get(k) is not None})
                self.save_sub(sub)
                self.start(job)
                pending -= 1
                active += 1
                continue
            elif ready and len(main_active) < target and self.build_id:
                run_id = self.start_main(queue, ready[0])
            else:
                break
            main_active.append(run_id)
            active += 1

    def start_balrog(self) -> None:
        """A graduate with a start goes on from it, in the start's build (its
        brain loads only into the same bot code); one without plays from the
        title in the current build."""
        assert self.build_id is not None
        item = self.balrog.take()
        start = item.get("start")
        if start and not build_meta(start["build"], self.home):
            start = None
        seed = random.SystemRandom().randrange(1, 2**31)
        job = self.new_job("balrog", item["platform"], item["character"], "balrog", seed,
                           int(self.config["balrog_budget"]), start["build"] if start else self.build_id,
                           **({"resume": start} if start else {}))
        self.balrog.save()
        self.start(job)

    def start_main(self, queue: Queue, platform: str) -> str:
        assert self.build_id is not None
        combo = queue.head(platform)
        assert combo is not None
        seed = random.SystemRandom().randrange(1, 2**31)
        job = self.new_job("main", platform, combo, queue.goal, seed, queue.budget(self.config), self.build_id)
        queue.take(platform, job["id"])
        queue.save()
        self.start(job)
        return job["id"]

    # -- retention

    def sweep(self) -> None:
        """Delete run directories ``retention_days`` after they ended, and
        builds no kept run or the current build uses."""
        if time.time() - self.last_sweep < 3600:
            return
        self.last_sweep = time.time()
        cutoff = time.time() - float(self.config["retention_days"]) * 86400
        kept_builds = {self.build_id} | {job["build"] for job in self.running.values()}
        for run_dir in (self.home / "runs").glob("*"):
            if run_dir.name in self.running:
                continue
            result = read_json(run_dir / "result.json")
            ended = (result or {}).get("ended") or run_dir.stat().st_mtime
            if ended < cutoff:
                shutil.rmtree(run_dir, ignore_errors=True)
                self.log(f"retention: removed {run_dir.name}")
            elif result:
                kept_builds.add(result.get("build"))
        for sub in (self.home / "subqueues").glob("*.json"):
            data = read_json(sub) or {}
            if not data.get("done"):
                kept_builds.add(data.get("build"))
        starts = [item["start"] for item in self.balrog.state["items"].values() if item.get("start")]
        kept_builds |= {start["build"] for start in starts}
        kept_starts = {Path(start["snapshot"]).parent.name for start in starts} | {
            job["resume"]["run"] for job in self.running.values() if job.get("resume")}
        for start_dir in (self.home / "balrog").glob("*"):
            if start_dir.name not in kept_starts:
                shutil.rmtree(start_dir, ignore_errors=True)
                self.log(f"retention: removed Balrog start {start_dir.name}")
        for build in (self.home / "builds").glob("*"):
            if build.is_dir() and build.name not in kept_builds and ".partial" not in build.name:
                shutil.rmtree(build, ignore_errors=True)
                self.log(f"retention: removed build {build.name}")

    # -- main loop

    def tick(self, queue: Queue) -> Queue:
        config = load_config(self.config_path)
        if config != self.config:
            self.log(f"config: {json.dumps(config)}")
            self.config = config
            self.last_fetch = 0.0
        if config["goal"] != queue.goal or config.get("epoch", "") != queue.epoch:
            queue = Queue(config["goal"], self.home, config.get("epoch", ""))
        for platform in config["platforms"]:
            queue.platform(platform)
        subs = self.load_subs()
        self.reap(queue, subs)
        self.graduate(queue)
        self.refresh_build()
        self.finish_subs(subs)
        subs = {name: sub for name, sub in subs.items() if not sub.get("done")}
        if not self.stopping:
            self.schedule(queue, subs)
        self.sweep()
        queue.save()
        self.heartbeat()
        return queue

    def serve(self) -> int:
        (self.home / "runs").mkdir(parents=True, exist_ok=True)
        (self.home / "subqueues").mkdir(parents=True, exist_ok=True)
        signal.signal(signal.SIGTERM, lambda *_: setattr(self, "stopping", True))
        self.sync_records()
        queue = Queue(self.config["goal"], self.home, self.config.get("epoch", ""))
        # Runs from before a restart: keep those still playing, mark the rest.
        self.reap(queue, self.load_subs(), adopting=True)
        for job in self.running.values():
            if job["queue"] == "main" and job["goal"] == queue.goal and job.get("epoch", "") == queue.epoch:
                entry = queue.platform(job["platform"])
                entry["items"][job["character"]]["in_flight"] = job["id"]
                if job["character"] in entry["order"]:
                    entry["order"].remove(job["character"])
        # An item in flight with no run behind it goes back to the head.
        for name, entry in queue.state["platforms"].items():
            for combo, item in entry["items"].items():
                if item["in_flight"] and item["in_flight"] not in self.running:
                    queue.give_back(name, combo)
        queue.save()
        self.log(f"service up: {len(self.running)} runs in flight, goal {queue.goal}")
        self.refresh_build(force=True)
        while not self.stopping:
            try:
                queue = self.tick(queue)
            except Exception:   # the service outlives any one bad tick
                self.log(f"tick failed: {traceback.format_exc()[-1500:]}")
            time.sleep(TICK_SECONDS)
        # Runs keep playing (each in its own session): a restarted service adopts them.
        self.log(f"service stopping; {len(self.running)} runs left in flight")
        self.heartbeat()
        return 0


# -- command line ------------------------------------------------------------------

def add_subqueue_args(parser: argparse.ArgumentParser) -> None:
    """Options a plain subqueue and an A/B subqueue share."""
    parser.add_argument("--name", required=True)
    parser.add_argument("--characters", default="all", help="comma list of race-class names, or all")
    parser.add_argument("--platforms", default="c64")
    parser.add_argument("--seeds", help="e.g. 1001-1020 (default: the qualification seeds)")
    parser.add_argument("--random-seeds", type=int, help="this many new seeds per character instead")
    parser.add_argument("--step-budget", type=int, help="default: the goal's, scaled to the platform")
    parser.add_argument("--build", default="tree", choices=("tree", "commit", "main"),
                        help="tree: this working tree as it stands (default); commit: HEAD; main: the "
                             "main queue's current build")
    parser.add_argument("--note", default="")


def check_variant(parser: argparse.ArgumentParser, goal: str, spec: str) -> str:
    """``spec`` stripped, or a usage error if the goal cannot take it."""
    try:
        apply_variant(GOALS[goal], spec)
    except ValueError as exc:
        parser.error(str(exc))
    return spec.strip()


def draw_seeds(args: argparse.Namespace) -> list[int]:
    """One character's seeds: drawn now from the system's random source, or given."""
    if args.random_seeds:
        return [random.SystemRandom().randrange(1, 2**31) for _ in range(args.random_seeds)]
    return parse_seeds(args.seeds) if args.seeds else QUALIFICATION_SEEDS


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-queue")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("serve", help="run the queue service (the systemd unit's command)")
    run = sub.add_parser("run", help="internal: play one run")
    run.add_argument("run_dir", type=Path)
    add = sub.add_parser("submit", help="submit a subqueue (§23.5)")
    add_subqueue_args(add)
    add.add_argument("--goal", choices=sorted(GOALS))
    add.add_argument("--regress", action="store_true", help="the frozen suites (one character's with "
                                                            "--characters NAME)")
    add.add_argument("--variant", default="", help="goal fields changed for every run, e.g. "
                                                   "tactics=-dangerous,-summoner,ready_margin=2 (§23.10)")
    ab = sub.add_parser("ab", help="submit an A/B subqueue: the same seeds under two variants (§23.10)")
    add_subqueue_args(ab)
    ab.add_argument("--goal", default="deep", choices=sorted(GOALS))
    ab.add_argument("--variant-a", default="", help="arm A's variant (empty: the goal as defined)")
    ab.add_argument("--variant-b", default="", help="arm B's variant")
    cancel = sub.add_parser("cancel", help="cancel a subqueue")
    cancel.add_argument("--name", required=True)
    report = sub.add_parser("report", help="print a subqueue's report (an A/B subqueue's comparison)")
    report.add_argument("--name", required=True)
    sub.add_parser("status", help="print the main queue and subqueues")
    sub.add_parser("rebuild", help="play this working tree as it stands from the next run on")
    args = parser.parse_args(argv)

    if args.command == "serve":
        return Service().serve()
    if args.command == "run":
        return run_one(args.run_dir)
    if args.command == "cancel":
        path = HOME / "subqueues" / f"{args.name}.json"
        if not path.exists():
            parser.error(f"no subqueue {args.name}")
        path.with_suffix(".cancel").touch()
        print(f"cancelled {args.name}")
        return 0
    if args.command == "report":
        data = read_json(HOME / "subqueues" / f"{args.name}.json")
        if data is None:
            parser.error(f"no subqueue {args.name}")
        print(report_text(data))
        return 0
    if args.command == "status":
        return status()
    if args.command == "rebuild":
        HOME.mkdir(parents=True, exist_ok=True)
        (HOME / "rebuild").touch()
        print("the service snapshots this working tree on its next tick")
        return 0
    platforms = args.platforms.split(",")
    for platform in platforms:
        if platform not in PORTS:
            parser.error(f"unknown platform {platform}")
    extra: dict[str, Any] = {}
    variant = ""
    if args.command == "submit" and args.regress:
        if args.variant:
            parser.error("--regress plays the frozen suites as frozen: no --variant")
        if args.characters not in ("all", None) and args.characters not in CHARACTERS:
            parser.error("--regress takes one character or all")
        items, suites = [], {}
        for platform in platforms:
            more, more_suites = regress_items(platform, None if args.characters == "all" else args.characters)
            items += more
            suites.update(more_suites)
    else:
        if not args.goal:
            parser.error("--goal is required unless --regress")
        names = list(CHARACTERS) if args.characters == "all" else args.characters.split(",")
        for name in names:
            if name not in CHARACTERS:
                parser.error(f"unknown character {name}")
        items, suites = [], {}
        if args.command == "ab":
            variants = {"A": check_variant(parser, args.goal, args.variant_a),
                        "B": check_variant(parser, args.goal, args.variant_b)}
            # Drawn once per character and shared by both arms: the same maps.
            seeds = {(platform, name): draw_seeds(args) for platform in platforms for name in names}
            items = ab_items(args.goal, names, platforms, seeds, variants, args.step_budget)
            extra["ab"] = variants
            variant = " | ".join(f"{arm}: {spec or 'as defined'}" for arm, spec in variants.items())
        else:
            variant = check_variant(parser, args.goal, args.variant)
            for platform in platforms:
                for name in names:
                    goal = apply_variant(for_port(for_character(GOALS[args.goal], name), PORTS[platform]), variant)
                    own = any(field == "step_budget" for field, _ in parse_variant(variant))
                    items += [{"goal": args.goal, "character": name, "platform": platform, "seed": seed,
                               "step_budget": goal.step_budget if own else args.step_budget or goal.step_budget,
                               **({"variant": variant} if variant else {})} for seed in draw_seeds(args)]
            if variant:
                extra["variant"] = variant
    if not items:
        parser.error("no items")
    if args.build == "main":
        service = read_json(HOME / "service.json") or {}
        build_id = service.get("build")
        if not build_id:
            parser.error("the service has no build yet")
        goals_py = HOME / "builds" / build_id / "playtest" / "moria_playtest" / "goals.py"
        if variant and "def apply_variant" not in (goals_py.read_text(errors="replace") if goals_py.exists() else ""):
            parser.error(f"build {build_id} predates variants: its runs would ignore them")
    else:
        print(f"building {args.build} snapshot for {', '.join(platforms)} ...", flush=True)
        build_id = snapshot_build(platforms, args.build)
    path = submit(args.name, items, build=build_id, suites=suites, home=HOME, note=args.note, **extra)
    print(f"submitted {args.name}: {len(items)} runs on build {build_id} ({path})"
          f"{f'; variant {variant}' if variant else ''}")
    return 0


def report_text(sub: dict[str, Any]) -> str:
    """A subqueue's groups, and an A/B subqueue's comparison, as text."""
    state = "done" if sub.get("done") else "cancelled" if sub.get("cancelled") else "running"
    lines = [f"subqueue {sub.get('name')}: {state}, {len(sub.get('results', []))}/{len(sub.get('items', []))} run"
             + (f", variant {sub['variant']}" if sub.get("variant") else "")]
    for key, group in (sub.get("report") or subqueue_report(sub)).items():
        bar = f" (bar {group['required']})" if "required" in group else ""
        lines.append(f"  {key}: {group['reached']}/{group['done']} of {group['total']}{bar}")
    if sub.get("ab"):
        lines.append(format_ab(sub.get("ab_report") or ab_report(sub)))
    return "\n".join(lines)


def status() -> int:
    config = load_config()
    service = read_json(HOME / "service.json") or {}
    age = time.time() - service.get("updated", 0)
    print(f"service: {'up' if age < 60 else 'DOWN'} (heartbeat {age:.0f}s ago), build {service.get('build')}")
    queue = Queue(config["goal"], epoch=config.get("epoch", ""))
    for name, entry in queue.state["platforms"].items():
        items = entry["items"]
        done = sum(1 for i in items.values() if i["success"])
        print(f"{name}: goal {queue.goal}, cycle {entry['cycle']} ({len(entry['cycle_done'])}/{len(items)}), "
              f"{done}/{len(items)} succeeded, budget {queue.budget(config)}")
        for combo, item in sorted(items.items()):
            last = item["last"] or {}
            print(f"  {combo:22} runs {item['runs']:3} ok {item['successes']:2} streak {item['streak']:+3}"
                  f"{' STRUGGLING' if item['struggling'] else ''}{' (playing)' if item['in_flight'] else ''}"
                  f"  last {last.get('outcome', '-')} clvl {last.get('clvl', '-')} DL {last.get('max_dlvl', '-')}")
    for path in sorted((HOME / "subqueues").glob("*.json")):
        sub = read_json(path) or {}
        state = "done" if sub.get("done") else "cancelled" if sub.get("cancelled") else "running"
        print(f"subqueue {sub.get('name')}: {state}, {len(sub.get('results', []))}/{len(sub.get('items', []))}"
              f"{' ' + json.dumps(sub['report']) if sub.get('report') else ''}")
        if sub.get("variant"):
            print(f"  variant {sub['variant']}")
        if sub.get("ab"):
            print("  " + format_ab(sub.get("ab_report") or ab_report(sub)).replace("\n", "\n  "))
    return 0


if __name__ == "__main__":
    sys.exit(main())
