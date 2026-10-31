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
import multiprocessing.connection
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
from .goals import (CHARACTERS, DEFAULT_CHARACTER, GOALS, QUALIFICATION_SEEDS, Goal, for_character,
                    for_port, required)
from .launch import PLAYTEST_OUT, ROOT, Build, StaleDisk, build_identity, check_disk
from .ports import C64, PORTS
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
        self.cited: set[Path] = set()  # snapshots a finding cites: kept for replay
        self.reported: set[tuple[str, str]] = set()
        self.keep_worker = False   # leave the emulator running after play() (disk.py)
        self.load_retries: int | None = None   # asset_load_retries at the last level entry

    # -- snapshots and findings ------------------------------------------------

    def take_snapshot(self, obs: Observation) -> None:
        self.auditor.learn(obs)
        state = {"seed": self.seed, "step": self.result.steps, "dlvl": obs.dlvl,
                 "brain": self.brain.state(), "auditor_command_sp": self.auditor.command_sp}
        previous = self.snapshot
        snapshot = self.worker.snapshot(f"{self.goal.name}-{self.seed}-s{self.result.steps}-dl{obs.dlvl}", state)
        if snapshot is None:   # a port without snapshots (MAME, mame.py)
            self.session.event("level_entry", seed=self.seed, step=self.result.steps, dlvl=obs.dlvl,
                               snapshot=None)
            return
        self.snapshot = snapshot
        if previous is not None and previous.path not in self.cited:
            # Only the restart point and the snapshots findings cite are kept:
            # one per level entry filled the disk (M4 round 55: a stair-bouncing
            # bot wrote ~4,000 snapshots per character, 2.4 TB across rounds).
            previous.delete()
        self.keys = []
        self.session.event("level_entry", seed=self.seed, step=self.result.steps, dlvl=obs.dlvl,
                           snapshot=str(self.snapshot.path))

    def file_finding(self, kind: str, cls: str, detail: str, obs: Observation | None,
                     pc: int | None = None) -> None:
        if (kind, detail) in self.reported:
            return
        self.reported.add((kind, detail))
        self.result.findings.append(f"{kind}: {detail}")
        if self.snapshot is not None:
            self.cited.add(self.snapshot.path)
        self.session.finding({
            "kind": kind, "cls": cls, "detail": detail, "pc": pc, "seed": self.seed,
            "goal": self.goal.name, "step": self.result.steps, "build": self.worker.build.__dict__,
            "snapshot": str(self.snapshot.path) if self.snapshot else None,
            "keys": list(self.keys), "screen": obs.rows if obs else None,
            "observation": obs.summary() if obs else None})

    def check_load_retries(self, obs: Observation) -> None:
        """A repeated disk load (asset_load_retry) is a load the drive failed
        once: filed so it shows, without ending the character."""
        game = self.worker.game
        assert game is not None
        symbol = game.abi.all_symbols.get("asset_load_retries")
        if symbol is None:
            return
        count = game.mon.mem_get(symbol[0], 1, game.ram)[0]
        if self.load_retries is not None and count != self.load_retries:
            self.file_finding("load_retry", "game", f"a disk load was repeated by step {self.result.steps} "
                              f"(asset_load_retries {self.load_retries} -> {count})", obs)
        self.load_retries = count

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
                    self.check_load_retries(obs)
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
                # The brain's kit beside each decision: whether a death came
                # with potions or oil left (M5f).
                self.log.decision(obs, {**decision.as_dict(), "clw": self.brain.clw, "oil": self.brain.oil})
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
            if not self.keep_worker:
                self.worker.stop()
        self.result.wall_s = round(time.monotonic() - started, 2)
        self.session.event("character_end", seed=self.seed, outcome=self.result.outcome,
                           steps=self.result.steps, dlvl=self.result.dlvl)
        return self.result


# -- modes ------------------------------------------------------------------------

def _worker_process(worker_id: int, goal: Goal, session_dir: Path, build: Build,
                    pending: "multiprocessing.Queue[int]", done: "multiprocessing.connection.Connection",
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
            done.send(result.__dict__)
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
    pending, stop = context.Queue(), context.Event()
    count = min(workers, len(seeds))
    # One pipe per worker for results. A Queue's put hands the result to a
    # feeder thread, so a worker that died right after a put lost it; a
    # pipe's send is written before it returns.
    pipes = [context.Pipe(duplex=False) for _ in range(count)]
    procs = [context.Process(target=_worker_process, args=(worker_id, goal, session.dir, build,
                                                           pending, pipes[worker_id][1], stop,
                                                           stop_on_reach))
             for worker_id in range(count)]
    for proc in procs:   # fork before the queue's feeder thread starts
        proc.start()
    for _, writer in pipes:
        writer.close()   # only the workers write: a reader sees EOF once they have exited
    readers = [reader for reader, _ in pipes]
    results: list[Result] = []
    try:
        for seed in seeds:
            pending.put(seed)
        for _ in procs:
            pending.put(None)   # one sentinel per worker
        while readers:
            for reader in multiprocessing.connection.wait(readers):
                try:
                    result = Result(**reader.recv())
                except EOFError:
                    readers.remove(reader)
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
        for reader, _ in pipes:
            reader.close()
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


def suite_path(goal: str, character: str = DEFAULT_CHARACTER, port: str = C64.name) -> Path:
    """The Half-Troll Warrior's suites are named by goal alone (M0-M4); other
    characters' add the character (§16.4 item 1), and other ports' the port
    (§21.2)."""
    parts = [goal, *([character] if character != DEFAULT_CHARACTER else []),
             *([port] if port != C64.name else [])]
    return SUITES / f"{'-'.join(parts)}.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-session")
    parser.add_argument("--goal", default="enter_dungeon", choices=sorted(GOALS))
    parser.add_argument("--character", choices=sorted(CHARACTERS),
                        help=f"race and class (default {DEFAULT_CHARACTER}); with --regress, "
                             "only that character's suites")
    parser.add_argument("--seeds", help="e.g. 1001-1020 or 5,9,12 (default: qualification seeds)")
    parser.add_argument("--seed-start", type=int, default=1)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--qualify", action="store_true")
    parser.add_argument("--freeze", action="store_true")
    parser.add_argument("--regress", action="store_true")
    parser.add_argument("--port", default=C64.name, choices=sorted(PORTS),
                        help="the port to play (§21); with --regress, only that port's suites")
    parser.add_argument("--build-out", type=Path, help="alternate build OUT directory")
    parser.add_argument("--name", help="session directory name")
    parser.add_argument("--step-budget", type=int,
                        help="qualify only: cap each character at this many steps instead of "
                             "the goal's budget (quicker iteration rounds; not with --freeze)")
    args = parser.parse_args(argv)

    port = PORTS[args.port]
    build = Build.from_out(args.build_out, port) if args.build_out else Build.shipping(port)
    try:
        check_disk(build)   # once, before any worker: not one boot error per seed
    except StaleDisk as exc:
        print(f"playtest-session: {exc}", file=sys.stderr)
        return 2
    mode = "regress" if args.regress else "qualify" if args.qualify else "session"
    character = args.character or DEFAULT_CHARACTER
    tag = suite_path(args.goal, character, port.name).stem
    name = args.name or f"{time.strftime('%Y%m%d-%H%M%S')}-{mode}-{tag}"
    session = SessionLog(PLAYTEST_OUT / "sessions" / name,
                         {"mode": mode, "goal": args.goal, "character": character, "port": port.name,
                          "build": build_identity(build),
                          "started": time.strftime("%Y-%m-%dT%H:%M:%S")})
    print(f"session: {session.dir}", flush=True)

    ok = True
    if mode == "regress":
        suites = [path for path in sorted(SUITES.glob("*.json"))
                  for suite in (json.loads(path.read_text()),)
                  if args.character in (None, suite.get("character", DEFAULT_CHARACTER))
                  and suite.get("port", C64.name) == port.name]
        report = {}
        ok = bool(suites)   # no frozen suite is no evidence
        for path in suites:
            suite = json.loads(path.read_text())
            goal = dataclasses.replace(for_character(GOALS[suite["goal"]],
                                                     suite.get("character", DEFAULT_CHARACTER)),
                                       step_budget=suite["step_budget"])
            results = run_seeds(goal, suite["seeds"], args.workers, session, build, False)
            passed = sum(r.outcome == "reached" for r in results)
            report[path.stem] = f"{passed}/{len(suite['seeds'])}"
            ok &= passed >= suite.get("required", required(goal, len(suite["seeds"])))
        session.summary["regress"] = report
        print(json.dumps(report))
    elif mode == "qualify":
        goal = for_port(for_character(GOALS[args.goal], character), port)
        if args.step_budget:
            if args.freeze:
                parser.error("--step-budget is for iteration rounds; freeze with the goal's budget")
            goal = dataclasses.replace(goal, step_budget=args.step_budget)
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
            suite = {"goal": goal.name, "seeds": seeds, "required": need,
                     "step_budget": goal.step_budget}
            if character != DEFAULT_CHARACTER:
                suite["character"] = character
            if port is not C64:
                suite["port"] = port.name
            write_json(suite_path(goal.name, character, port.name), {**suite,
                                               "frozen": time.strftime("%Y-%m-%d"),
                                               "program_sha256": build_identity(build)["program_sha256"]})
            print(f"froze {suite_path(goal.name, character, port.name).relative_to(ROOT)}")
    else:
        results = session_until_reached(for_port(for_character(GOALS[args.goal], character), port),
                                        args.seed_start, args.workers, session, build)
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
