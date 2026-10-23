"""``make playtest-session``: play a goal (§7).

Modes:
- default: keep starting characters on successive seeds until one reaches the
  goal (no time limit; plateau alerts never stop it);
- ``--qualify``: the goal's fixed seeds, first character each, within the
  step budget; ``--freeze`` writes the passing seeds as the goal's regression
  suite under playtest/suites/;
- ``--regress``: every frozen suite must still pass.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import multiprocessing
import queue
import signal
import sys
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import nav
from .auditor import Auditor
from .brain import Brain
from .game import EmulatorUnresponsive, GameFault, Mode, Observation
from .goals import GOALS, QUALIFICATION_SEEDS, Goal, required
from .launch import PLAYTEST_OUT, ROOT, SHIPPING, Build, build_identity
from .recorder import CharacterLog, SessionLog, write_json
from .vice import ViceError
from .view import build_view
from .worker import Snapshot, Worker

SUITES = ROOT / "playtest" / "suites"
PLATEAU_CHARACTERS = 10
WIND_DOWN_SECONDS = 5   # a failed run waits this long per worker before SIGTERM
MAX_RESTARTS_PER_STEP = 2


@dataclass
class Result:
    seed: int
    outcome: str = "budget"   # reached | died | budget | finding | error
    steps: int = 0
    dlvl: int = 0
    clvl: int = 0
    max_dlvl: int = 0
    findings: list[str] = field(default_factory=list)
    restarts: int = 0
    wall_s: float = 0.0
    max_resume_wall_s: float = 0.0   # longest single resume-to-input-stop wait


class Character:
    """One character played by one worker toward one goal."""

    def __init__(self, worker: Worker, goal: Goal, seed: int, session: SessionLog) -> None:
        self.worker = worker
        self.goal = goal
        self.seed = seed
        self.session = session
        self.log = CharacterLog(session, worker.worker_id, seed, goal.name)
        self.brain = Brain(goal)
        self.auditor = Auditor()
        self.result = Result(seed)
        self.snapshot: Snapshot | None = None
        self.keys: list[int] = []      # keys fed since self.snapshot
        self.reported: set[tuple[str, str]] = set()

    # -- snapshots and findings ------------------------------------------------

    def take_snapshot(self, obs: Observation) -> None:
        self.auditor.learn(obs)
        state = {"seed": self.seed, "step": self.result.steps, "dlvl": obs.dlvl,
                 "brain": self.brain.state(), "auditor_command_sp": self.auditor.command_sp}
        self.snapshot = self.worker.snapshot(f"{self.goal.name}-{self.seed}-s{self.result.steps}-dl{obs.dlvl}", state)
        self.keys = []
        self.session.event("level_entry", seed=self.seed, step=self.result.steps, dlvl=obs.dlvl,
                           snapshot=str(self.snapshot.path))

    def file_finding(self, kind: str, cls: str, detail: str, obs: Observation | None,
                     pc: int | None = None) -> None:
        if (kind, detail) in self.reported:
            return
        self.reported.add((kind, detail))
        self.result.findings.append(f"{kind}: {detail}")
        self.session.finding({
            "kind": kind, "cls": cls, "detail": detail, "pc": pc, "seed": self.seed,
            "goal": self.goal.name, "step": self.result.steps, "build": self.worker.build.__dict__,
            "snapshot": str(self.snapshot.path) if self.snapshot else None,
            "keys": list(self.keys), "screen": obs.rows if obs else None,
            "observation": obs.summary() if obs else None})

    def audit(self, obs: Observation, tiles: bytes | None) -> None:
        """File the auditor's findings for this observation (a game finding
        ends the character) and any item prompt the brain did not ask for."""
        for finding in self.auditor.check(obs, tiles):
            self.file_finding(finding.kind, finding.cls, finding.detail, obs)
            if finding.cls == "game":
                self.result.outcome = "finding"
        if obs.mode == Mode.ITEM and not self.brain.expects_item_prompt():
            # Mode.ITEM is only "known" when the brain asked for it.
            self.file_finding("unknown_prompt", "bot", obs.rows[0].strip()[:40] or obs.stage, obs)

    # -- play -------------------------------------------------------------------

    def start(self) -> Observation:
        obs = self.worker.start_at_title()
        game = self.worker.game
        assert game is not None
        game.seed_title(self.seed)
        self.session.event("character_start", seed=self.seed, worker=self.worker.worker_id,
                           goal=self.goal.name)
        return obs

    def press(self, key: int) -> Observation:
        """Feed one key; on an unresponsive emulator, restart from the snapshot and replay."""
        for attempt in range(MAX_RESTARTS_PER_STEP + 1):
            try:
                game = self.worker.game
                assert game is not None
                obs = game.press(key)
                self.keys.append(key)
                return obs
            except (EmulatorUnresponsive, ViceError) as exc:
                self.result.restarts += 1
                self.session.event("emulator_restart", seed=self.seed, step=self.result.steps,
                                   attempt=attempt, error=str(exc))
                if self.snapshot is None or attempt == MAX_RESTARTS_PER_STEP:
                    raise GameFault("hang", f"emulator unresponsive at the same step after "
                                    f"{attempt + 1} attempts: {exc}") from exc
                self.worker.restore(self.snapshot)
                assert self.worker.game is not None
                for replay_key in self.keys:
                    self.worker.game.press(replay_key)
        raise AssertionError("unreachable")

    def play(self) -> Result:
        started = time.monotonic()
        try:
            obs = self.start()
            dlvl_seen: int | None = None
            while self.result.steps < self.goal.step_budget:
                game = self.worker.game
                assert game is not None
                tiles = nav.read_map(game) if obs.mode == Mode.COMMAND else None
                if obs.mode == Mode.COMMAND and obs.dlvl != dlvl_seen:
                    dlvl_seen = obs.dlvl
                    self.result.max_dlvl = max(self.result.max_dlvl, obs.dlvl)
                    self.take_snapshot(obs)
                self.audit(obs, tiles)
                if self.result.outcome == "finding":
                    break
                if obs.mode == Mode.COMMAND and self.goal.reached(obs):
                    self.result.outcome = "reached"
                    break
                if obs.mode == Mode.DEATH:
                    self.result.outcome = "died"
                    break
                view = None
                if tiles is not None:
                    levels = game.mon.mem_get(game.abi.cr_level, game.abi.MAX_DUNGEON_CREATURES
                                              + game.abi.MAX_TOWN_CREATURES, game.ram)
                    view = build_view(game, obs, tiles, levels)
                decision = self.brain.decide(obs, view)
                for event in self.brain.events:
                    self.file_finding("stall", "bot", event, obs)
                self.brain.events.clear()
                self.log.decision(obs, decision.as_dict())
                if self.result.steps % CharacterLog.STATUS_EVERY == 0:
                    self.log.status(game, obs, self.result.steps, {"character_seed": self.seed})
                obs = self.press(decision.key)
                self.result.steps += 1
            self.result.dlvl, self.result.clvl = obs.dlvl, obs.clvl
            if self.worker.game is not None:
                self.result.max_resume_wall_s = round(self.worker.game.stats["max_resume_wall"], 3)
                self.log.status(self.worker.game, obs, self.result.steps,
                                {"outcome": self.result.outcome})
        except GameFault as fault:
            self.result.outcome = "finding"
            self.file_finding(fault.kind, "game", fault.detail, None, fault.pc)
        finally:
            self.log.close()
            self.worker.stop()
        self.result.wall_s = round(time.monotonic() - started, 2)
        self.session.event("character_end", seed=self.seed, outcome=self.result.outcome,
                           steps=self.result.steps, dlvl=self.result.dlvl)
        return self.result


# -- modes ------------------------------------------------------------------------

def _worker_process(worker_id: int, goal: Goal, session_dir: Path, build: Build,
                    pending: "multiprocessing.Queue[int]", done: "multiprocessing.Queue[dict[str, Any]]",
                    stop: Any, stop_on_reach: bool) -> None:
    """One worker in its own process: the brain and the emulator protocol are
    CPU-bound Python, so threads would share one core under the GIL."""
    # SIGTERM (the parent winding down) unwinds like an exception, so the
    # emulator is stopped: VICE runs in its own session and outlives us.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(1))
    session = SessionLog.attach(session_dir)
    worker: Worker | None = None
    try:
        while True:
            seed = pending.get()
            if seed is None or stop.is_set():
                return
            try:
                worker = worker or Worker(session_dir, worker_id, build=build)
                result = Character(worker, goal, seed, session).play()
            except Exception as exc:   # anything but a GameFault: record it, never drop the seed
                session.event("worker_error", seed=seed, worker=worker_id, error=repr(exc),
                              traceback=traceback.format_exc())
                result = Result(seed, outcome="error", findings=[f"error: {exc!r}"])
                if worker is not None:
                    worker.stop()   # no emulator left holding the worker's port
                worker = None   # a fresh worker for the next seed
            done.put(result.__dict__)
            if result.outcome == "reached" and stop_on_reach:
                stop.set()
    finally:
        if worker is not None:
            worker.stop()


def run_seeds(goal: Goal, seeds: list[int], workers: int, session: SessionLog, build: Build,
              stop_on_reach: bool) -> list[Result]:
    """Play one character per seed on ``workers`` parallel worker processes.

    Every seed gets a result: a character that raised, or whose worker
    process died, is recorded as ``error`` (unless an earlier character
    reached the goal and ``stop_on_reach`` ended the batch).
    """
    context = multiprocessing.get_context("fork")   # inherits goals registered by callers
    pending, done, stop = context.Queue(), context.Queue(), context.Event()
    count = min(workers, len(seeds))
    procs = [context.Process(target=_worker_process, args=(worker_id, goal, session.dir, build,
                                                           pending, done, stop, stop_on_reach))
             for worker_id in range(count)]
    for proc in procs:   # fork before the queue's feeder thread starts
        proc.start()
    results: list[Result] = []
    try:
        for seed in seeds:
            pending.put(seed)
        for _ in procs:
            pending.put(None)   # one sentinel per worker
        while any(proc.is_alive() for proc in procs) or not done.empty():
            try:
                result = Result(**done.get(timeout=1))
            except queue.Empty:
                continue
            session.character(result.__dict__)
            results.append(result)
    except BaseException:
        stop.set()   # the parent failed: no worker keeps playing on its own
        for proc in procs:
            proc.join(timeout=WIND_DOWN_SECONDS)   # finish the current character
        for proc in procs:
            if proc.is_alive():
                proc.terminate()   # SIGTERM: the worker stops its emulator, then exits
        raise
    finally:
        for proc in procs:
            proc.join()
    if not stop.is_set():
        played = {r.seed for r in results}
        dead = [p.exitcode for p in procs if p.exitcode]
        for seed in seeds:
            if seed not in played:   # its worker died without reporting
                result = Result(seed, outcome="error", findings=[f"error: worker exit codes {dead}"])
                session.character(result.__dict__)
                results.append(result)
    return sorted(results, key=lambda r: r.seed)


def session_until_reached(goal: Goal, seed_start: int, workers: int, session: SessionLog,
                          build: Build) -> list[Result]:
    """Unbounded: new characters until one reaches the goal; plateau alerts only notify."""
    results: list[Result] = []
    best, since_best, seed = -1, 0, seed_start
    while True:
        batch = run_seeds(goal, list(range(seed, seed + workers)), workers, session, build, True)
        seed += workers
        results += batch
        for result in batch:
            progress = result.max_dlvl * 100 + result.clvl
            if progress > best:
                best, since_best = progress, 0
            else:
                since_best += 1
                if since_best == PLATEAU_CHARACTERS:
                    session.event("plateau", characters=since_best, best_progress=best)
        if any(r.outcome == "reached" for r in batch):
            return results


def suite_path(goal: str) -> Path:
    return SUITES / f"{goal}.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-session")
    parser.add_argument("--goal", default="enter_dungeon", choices=sorted(GOALS))
    parser.add_argument("--seeds", help="e.g. 1001-1020 or 5,9,12 (default: qualification seeds)")
    parser.add_argument("--seed-start", type=int, default=1)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--qualify", action="store_true")
    parser.add_argument("--freeze", action="store_true")
    parser.add_argument("--regress", action="store_true")
    parser.add_argument("--build-out", type=Path, help="alternate build OUT directory")
    parser.add_argument("--name", help="session directory name")
    args = parser.parse_args(argv)

    build = Build.from_out(args.build_out) if args.build_out else SHIPPING
    mode = "regress" if args.regress else "qualify" if args.qualify else "session"
    name = args.name or f"{time.strftime('%Y%m%d-%H%M%S')}-{mode}-{args.goal}"
    session = SessionLog(PLAYTEST_OUT / "sessions" / name,
                         {"mode": mode, "goal": args.goal, "build": build_identity(build),
                          "started": time.strftime("%Y-%m-%dT%H:%M:%S")})
    print(f"session: {session.dir}", flush=True)

    ok = True
    if mode == "regress":
        suites = sorted(SUITES.glob("*.json"))
        report = {}
        ok = bool(suites)   # no frozen suite is no evidence
        for path in suites:
            suite = json.loads(path.read_text())
            goal = dataclasses.replace(GOALS[suite["goal"]], step_budget=suite["step_budget"])
            results = run_seeds(goal, suite["seeds"], args.workers, session, build, False)
            passed = sum(r.outcome == "reached" for r in results)
            report[goal.name] = f"{passed}/{len(suite['seeds'])}"
            ok &= passed >= suite.get("required", required(goal, len(suite["seeds"])))
        session.summary["regress"] = report
        print(json.dumps(report))
    elif mode == "qualify":
        goal = GOALS[args.goal]
        seeds = parse_seeds(args.seeds) if args.seeds else QUALIFICATION_SEEDS
        results = run_seeds(goal, seeds, args.workers, session, build, False)
        passed = [r.seed for r in results if r.outcome == "reached"]
        need = required(goal, len(seeds))
        ok = len(passed) >= need
        session.summary["qualification"] = {"passed": f"{len(passed)}/{len(seeds)}", "required": need,
                                            "works": ok,
                                            "failed": [r.__dict__ for r in results
                                                       if r.outcome != "reached"]}
        print(f"qualification {goal.name}: {len(passed)}/{len(seeds)} (needs {need})", flush=True)
        if ok and args.freeze and seeds != QUALIFICATION_SEEDS:
            print("not frozen: a suite is the goal's full qualification seed list", flush=True)
        elif ok and args.freeze:
            SUITES.mkdir(parents=True, exist_ok=True)
            write_json(suite_path(goal.name), {"goal": goal.name, "seeds": seeds, "required": need,
                                               "step_budget": goal.step_budget,
                                               "frozen": time.strftime("%Y-%m-%d"),
                                               "program_sha256": build_identity(build)["program_sha256"]})
            print(f"froze {suite_path(goal.name).relative_to(ROOT)}")
    else:
        results = session_until_reached(GOALS[args.goal], args.seed_start, args.workers, session, build)
        reached = [r.seed for r in results if r.outcome == "reached"]
        print(f"goal {args.goal} reached by seed {reached[0]} after {len(results)} characters")
    session.summary["findings"] = session.findings
    session.summary["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    session.save_summary()
    print(f"findings: {session.findings} (see {session.dir / 'findings'})")
    return 0 if ok else 1


def parse_seeds(text: str) -> list[int]:
    seeds: list[int] = []
    for part in text.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            seeds += list(range(int(lo), int(hi) + 1))
        elif part:
            seeds.append(int(part))
    return seeds


if __name__ == "__main__":
    sys.exit(main())
