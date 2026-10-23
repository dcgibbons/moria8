import dataclasses
import struct
import unittest

from moria_playtest import abi as abimod
from moria_playtest.auditor import Auditor
from moria_playtest.brain import Brain
from moria_playtest.game import KEY_SPACE, Mode, Observation
from moria_playtest.goals import GOALS
from moria_playtest.screen import decode_rows
from moria_playtest.view import DIRS, TYPE_TRAP, UNKNOWN, WALL, Creature, View

from test_game import ABI as BASE_ABI, screen_bytes

ABI = abimod.Abi(labels={**BASE_ABI.labels, "zp_view_x": 0x60, "zp_view_y": 0x61},
                 consts=BASE_ABI.consts, all_symbols={})
COLS, ROWS = 80, 48


def command_obs(pos=(10, 5), hp=21, mhp=21, sp=0xF2, view=(0, 0), rows=None,
                monsters=(), dlvl=0) -> Observation:
    zp = bytearray(256)
    zp[0x2B], zp[0x2C] = pos
    zp[0x2D:0x2F] = struct.pack("<h", hp)
    zp[0x2F:0x31] = struct.pack("<h", mhp)
    zp[0x33], zp[0x34] = 1, dlvl
    zp[0x60], zp[0x61] = view
    table = bytearray([0xFF] * 384)
    for slot, (mx, my) in enumerate(monsters):
        table[slot * 12:slot * 12 + 3] = bytes([mx, my, 1])
    screen_rows = {21: f"bot Half-Troll              LV:1  DL:{dlvl}",
                   23: f"HP:{hp}/{mhp}  MP:0/0   AC:4  AU:277   Full"}
    col, row = pos[0] - view[0] + 1, pos[1] - view[1] + 2
    screen_rows[row] = " " * col + "@"
    screen_rows.update(rows or {})
    screen = screen_bytes(screen_rows)
    obs = Observation(1, 0x10B9, sp, 0x36, 0x1181, 4, bytes(zp), bytes(111), bytes(table),
                      screen, decode_rows(screen), abi=ABI)
    obs.mode, obs.stage = Mode.COMMAND, "command"
    return obs


def floor_tiles(occupied=()) -> bytearray:
    tiles = bytearray([0x0C] * (COLS * ROWS))   # floor, lit + visited
    for x, y in occupied:
        tiles[y * COLS + x] |= 0x01
    return tiles


def town_view(pos, stairs, monsters=frozenset(), walls=(), dlvl=0, stairs_type=0x9) -> View:
    types = [0] * (COLS * ROWS)
    for x, y in walls:
        types[y * COLS + x] = WALL
    types[stairs[1] * COLS + stairs[0]] = stairs_type
    return View(COLS, ROWS, types, pos, dlvl, {m: Creature("k", 1) for m in monsters})


class ViewBrainTest(unittest.TestCase):
    def test_descends_when_on_stairs(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        decision = brain.decide(command_obs(), town_view((5, 5), (5, 5)))
        self.assertEqual((decision.key, decision.layer), (ord(">"), "descend"))

    def test_walks_toward_stairs_around_a_creature(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        decision = brain.decide(command_obs(), town_view((5, 5), (7, 5), monsters={(6, 5)}))
        self.assertIn(decision.key, (DIRS[(1, -1)], DIRS[(1, 1)]))

    def test_unknown_tiles_are_not_walkable(self) -> None:
        view = town_view((5, 5), (9, 5))
        view.types[5 * COLS + 6] = UNKNOWN
        self.assertFalse(view.passable(6, 5, avoid_monsters=True))

    def test_prompt_layer(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        for mode, key in ((Mode.DISMISS, 0x20), (Mode.UNKNOWN, 0x03), (Mode.DEATH, 0x20)):
            obs = dataclasses.replace(command_obs(), mode=mode, stage="")
            self.assertEqual(brain.decide(obs, None).key, key)


class BrainM2Test(unittest.TestCase):
    def obs(self, hp=21, mhp=21, msg="", dlvl=1, pos=(5, 5)):
        o = command_obs(hp=hp, mhp=mhp, dlvl=dlvl, pos=pos)
        o.rows[0] = msg.ljust(40)
        return o

    def test_frontier_and_search_spots(self) -> None:
        view = town_view((5, 5), (60, 40), dlvl=1)
        view.types = [UNKNOWN] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0          # a short corridor of floor
        view.types[5 * COLS + 8] = WALL               # wall, unknown beyond
        self.assertIn((3, 5), view.frontier())
        self.assertEqual(view.search_spots(set()) & {(7, 5)}, {(7, 5)})

    def test_known_trap_is_never_a_destination(self) -> None:
        view = town_view((5, 5), (60, 40), dlvl=1)
        view.types = [UNKNOWN] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 3] = TYPE_TRAP          # revealed trap at the corridor's open end
        view.types[5 * COLS + 8] = WALL
        view.types[4 * COLS + 3] = WALL
        self.assertNotIn((3, 5), view.frontier())
        self.assertNotIn((3, 5), view.search_spots(set()))

    def test_keep_clear_refuses_tiles_next_to_creatures(self) -> None:
        view = town_view((5, 5), (5, 9), dlvl=1, monsters={(6, 6)})
        step = view.step_toward({(5, 9)}, avoid_monsters=True, keep_clear=True)
        self.assertNotIn((5 + step[0], 5 + step[1]), {(5, 6), (6, 5), (6, 6), (6, 7), (5, 7), (7, 5)})

    def test_hurt_with_creature_in_view_runs_for_stairs(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 2), dlvl=1, monsters={(12, 12)}, stairs_type=0xA)
        decision = brain.decide(self.obs(hp=12), view)
        self.assertEqual((decision.layer, decision.key), ("retreat", DIRS[(0, -1)]))

    def test_first_strike_waits_for_contact(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(7, 5)})
        self.assertEqual(brain.decide(self.obs(), view).reason,
                         "wait for it to step into contact: first strike")

    def test_unseen_attacker_stops_resting(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 3), dlvl=1, stairs_type=0xA)
        decision = brain.decide(self.obs(hp=15, msg="the Kobold hits you."), view)
        self.assertEqual(decision.layer, "retreat")

    def test_no_fighting_in_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        decision = brain.decide(self.obs(dlvl=0), town_view((5, 5), (9, 5), monsters={(6, 5)}))
        self.assertNotEqual(decision.layer, "fight")

    def test_no_food_stops_eating_until_a_pickup(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)

        def hungry(msg: str) -> Observation:
            o = self.obs(msg=msg)
            o.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:277   Hungry"
            return o

        self.assertEqual(brain.decide(hungry(""), view).layer, "eat")
        self.assertNotEqual(brain.decide(hungry("You have no food."), view).layer, "eat")
        self.assertNotEqual(brain.decide(hungry(""), view).layer, "eat")
        self.assertEqual(brain.decide(hungry("You picked up a Ration of Food."), view).layer, "eat")

    def store_obs(self, stage: str, rows: dict[int, str]) -> Observation:
        o = self.obs(dlvl=0)
        o.rows = [" " * 40] * 25
        for row, text in rows.items():
            o.rows[row] = text.ljust(40)
        o.mode, o.stage = Mode.STORE, stage
        return o

    def test_store_buys_food_then_leaves(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        stock = {3: " a) Iron Spike                 1 GP", 5: " c) Ration of Food             3 GP",
                 7: " e) Ration of Food             3 GP", 18: " B)uy  S)ell  Q)uit"}
        keys = [brain.decide(self.store_obs("menu", stock), None).key,
                brain.decide(self.store_obs("buy_which", stock), None).key,
                brain.decide(self.store_obs("buy_confirm", stock), None).key]
        self.assertEqual(keys, [ord("B"), ord("C"), ord("Y")])
        sold = {**stock, 5: " c)"}
        self.assertEqual(brain.decide(self.store_obs("menu", sold), None).key, ord("B"))
        self.assertEqual(brain.decide(self.store_obs("buy_which", sold), None).key, ord("E"))
        self.assertEqual(brain.decide(self.store_obs("menu", {3: stock[3], 18: stock[18]}), None).key, ord("Q"))
        self.assertTrue(brain.shopped)

    def test_store_message_ends_shopping(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        rows = {5: " c) Ration of Food             3 GP", 18: " B)uy  S)ell  Q)uit"}
        self.assertEqual(brain.decide(self.store_obs("message", rows), None).key, KEY_SPACE)
        self.assertEqual(brain.decide(self.store_obs("menu", rows), None).key, ord("Q"))

    def test_town_walks_to_the_general_store_once(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        view = town_view((5, 8), (30, 8))
        view.stores = [(5, 6)]
        view.types[6 * COLS + 5] = 0x7                  # store entrance
        decision = brain.decide(self.obs(dlvl=0, pos=(5, 8)), view)
        self.assertEqual((decision.layer, decision.key), ("shop", DIRS[(0, -1)]))
        brain.shopped = True
        self.assertEqual(brain.decide(self.obs(dlvl=0, pos=(5, 8)), view).layer, "descend")

    def test_out_of_food_heads_for_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)
        o = self.obs(msg="You have no food.")
        o.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:277   Weak"
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.key), ("eat", DIRS[(0, -1)]))

    def test_paths_detour_around_a_known_trap_but_cross_it_if_needed(self) -> None:
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.types[5 * COLS + 6] = TYPE_TRAP
        self.assertNotEqual(view.step_toward({(7, 5)}, avoid_monsters=True), (1, 0))
        view.types = [WALL] * (COLS * ROWS)               # now a walled one-wide corridor
        for x in (5, 6, 7):
            view.types[5 * COLS + x] = TYPE_TRAP if x == 6 else 0x0
        self.assertEqual(view.step_toward({(7, 5)}, avoid_monsters=True), (1, 0))

    def test_explores_across_a_trap_only_when_nothing_else_is_left(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (60, 40), dlvl=1)
        view.types = [WALL] * (COLS * ROWS)
        for x in (4, 5):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 6] = TYPE_TRAP              # corridor end: unknown beyond the trap
        view.types[5 * COLS + 7] = UNKNOWN
        decision = brain.decide(self.obs(), view)
        self.assertEqual((decision.layer, decision.key), ("explore", DIRS[(1, 0)]))

    def test_xp_goal_never_scums_deeper(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 5), dlvl=1)          # standing on a down staircase
        brain.level.scum = True
        self.assertNotEqual(brain.decide(self.obs(), view).key, ord(">"))


class AuditorTest(unittest.TestCase):
    def kinds(self, auditor: Auditor, obs: Observation, tiles) -> list[str]:
        return [f.detail for f in auditor.check(obs, bytes(tiles))]

    def test_clean_command_stop(self) -> None:
        self.assertEqual(self.kinds(Auditor(), command_obs(), floor_tiles()), [])

    def test_stack_drift(self) -> None:
        auditor = Auditor()
        auditor.check(command_obs(sp=0xF2), bytes(floor_tiles()))
        found = auditor.check(command_obs(sp=0xF1), bytes(floor_tiles()))
        self.assertEqual([f.kind for f in found], ["stack"])

    def test_hp_over_max_and_status_mismatch(self) -> None:
        obs = command_obs(hp=30, mhp=21)
        obs.rows[23] = "HP:21/21  MP:0/0"
        details = self.kinds(Auditor(), obs, floor_tiles())
        self.assertIn("HP 30 exceeds max HP 21", details)
        self.assertIn("status hp=21 but memory has 30", details)

    def test_occupied_flag_must_match_monster_table(self) -> None:
        details = self.kinds(Auditor(), command_obs(monsters=[(11, 5)]), floor_tiles(occupied=[(11, 5)]))
        self.assertEqual(details, [])
        details = self.kinds(Auditor(), command_obs(), floor_tiles(occupied=[(11, 5)]))
        self.assertEqual(len(details), 1)
        self.assertIn("FLAG_OCCUPIED=1 at (11, 5)", details[0])

    def test_player_glyph_position(self) -> None:
        obs = command_obs()
        obs.rows[7] = " " * 40
        self.assertTrue(any("player glyph" in d for d in self.kinds(Auditor(), obs, floor_tiles())))

    def test_unknown_prompt_reported_once(self) -> None:
        auditor = Auditor()
        obs = dataclasses.replace(command_obs(), mode=Mode.UNKNOWN, stage="direction")
        self.assertEqual([f.cls for f in auditor.check(obs, None)], ["bot"])
        self.assertEqual(auditor.check(obs, None), [])


class RunSeedsTest(unittest.TestCase):
    """The process runner reports every seed: a character that raises or a
    worker that dies becomes an ``error`` result, never a missing one (review)."""

    def test_every_seed_gets_a_result_and_unique_findings(self) -> None:
        import os
        import tempfile
        from pathlib import Path
        from moria_playtest import session as sess
        from moria_playtest.recorder import SessionLog

        stops = Path(tempfile.mkdtemp()) / "stops"

        class FakeWorker:
            def __init__(self, *args, **kwargs) -> None:
                self.seed = None

            def stop(self) -> None:   # runs in the worker process: record it in a file
                with stops.open("a") as fh:
                    fh.write(f"stop {self.seed}\n")

        class FakeCharacter:
            def __init__(self, worker, goal, seed, log) -> None:
                self.seed, self.log = seed, log
                worker.seed = seed

            def play(self):
                self.log.finding({"kind": "k", "cls": "bot", "detail": str(self.seed),
                                  "seed": self.seed, "step": 0})
                if self.seed == 3:
                    raise RuntimeError("brain bug")
                if self.seed == 5:
                    os._exit(1)   # the worker process dies without reporting
                return sess.Result(self.seed, outcome="reached")

        saved = sess.Worker, sess.Character
        sess.Worker, sess.Character = FakeWorker, FakeCharacter
        try:
            with tempfile.TemporaryDirectory() as tmp:
                log = SessionLog(Path(tmp), {"mode": "qualify"})
                results = sess.run_seeds(GOALS["reach_dl2"], list(range(1, 9)), 3, log, None, False)
                ids = [p.name for p in (Path(tmp) / "findings").glob("F*.json")]
                characters = log.summary["characters"]
        finally:
            sess.Worker, sess.Character = saved
        self.assertEqual([r.seed for r in results], list(range(1, 9)))
        self.assertEqual({r.seed: r.outcome for r in results if r.outcome != "reached"},
                         {3: "error", 5: "error"})
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(ids), 8)
        self.assertEqual(len(characters), 8)
        # The worker that raised on seed 3 is replaced, so only the error path
        # can have stopped it.
        self.assertIn("stop 3", stops.read_text().splitlines())


class RunSeedsParentFailureTest(unittest.TestCase):
    """Review round 4: if the parent fails, every worker still stops its
    emulator (graceful wind-down, then SIGTERM, which unwinds like an error)."""

    def test_every_worker_stops_its_emulator(self) -> None:
        import tempfile
        import time
        from pathlib import Path
        from moria_playtest import session as sess
        from moria_playtest.recorder import SessionLog

        stops = Path(tempfile.mkdtemp()) / "stops"

        class FakeWorker:
            def __init__(self, *args, **kwargs) -> None:
                with stops.open("a") as fh:
                    fh.write("start\n")

            def stop(self) -> None:
                with stops.open("a") as fh:
                    fh.write("stop\n")

        class FakeCharacter:
            def __init__(self, worker, goal, seed, log) -> None:
                self.seed = seed

            def play(self):
                time.sleep(30 if self.seed > 1 else 0.1)   # most are mid-game: SIGTERM path
                return sess.Result(self.seed, outcome="reached")

        class FailingLog(SessionLog):
            def character(self, result) -> None:
                raise RuntimeError("parent failure")

        saved = sess.Worker, sess.Character, sess.WIND_DOWN_SECONDS
        sess.Worker, sess.Character, sess.WIND_DOWN_SECONDS = FakeWorker, FakeCharacter, 0.5
        try:
            with tempfile.TemporaryDirectory() as tmp:
                log = FailingLog(Path(tmp), {"mode": "qualify"})
                with self.assertRaises(RuntimeError):
                    sess.run_seeds(GOALS["reach_dl2"], [1, 2, 3], 3, log, None, False)
        finally:
            sess.Worker, sess.Character, sess.WIND_DOWN_SECONDS = saved
        lines = stops.read_text().splitlines()
        self.assertGreater(lines.count("start"), 0)
        self.assertEqual(lines.count("stop"), lines.count("start"))


class RecorderPathTest(unittest.TestCase):
    def test_same_seed_on_two_goals_keeps_both_traces_and_snapshots(self) -> None:
        import tempfile
        from pathlib import Path
        from types import SimpleNamespace

        from moria_playtest.recorder import SessionLog
        from moria_playtest.session import Character

        names: list[str] = []
        def snapshot(name: str, state: dict) -> SimpleNamespace:
            names.append(name)
            return SimpleNamespace(path=Path(name))

        worker = SimpleNamespace(worker_id=0, snapshot=snapshot)
        with tempfile.TemporaryDirectory() as tmp:
            log = SessionLog(Path(tmp), {"mode": "regress"})
            dirs = []
            for goal in ("enter_dungeon", "reach_dl2"):
                character = Character(worker, GOALS[goal], 1009, log)
                character.take_snapshot(command_obs())
                character.log.close()
                dirs.append(character.log.dir)
            self.assertNotEqual(dirs[0], dirs[1])
            self.assertTrue(all((d / "trace.jsonl.gz").exists() for d in dirs))
        self.assertEqual(len(set(names)), 2)


class PlateauTest(unittest.TestCase):
    def test_plateau_alert_fires_once_and_never_stops_the_session(self) -> None:
        import json
        import tempfile
        from pathlib import Path
        from unittest import mock

        from moria_playtest import session
        from moria_playtest.recorder import SessionLog

        batches = iter([[session.Result(seed=i, outcome="died")] for i in range(1, 13)]
                       + [[session.Result(seed=13, outcome="reached", max_dlvl=1)]])
        with tempfile.TemporaryDirectory() as tmp:
            log = SessionLog(Path(tmp), {"mode": "session"})
            with mock.patch.object(session, "run_seeds", lambda *a, **k: next(batches)):
                results = session.session_until_reached(GOALS["enter_dungeon"], 1, 1, log, None)
            events = [json.loads(line) for line in (Path(tmp) / "events.jsonl").read_text().splitlines()]
        self.assertEqual(results[-1].outcome, "reached")
        self.assertEqual([e["kind"] for e in events], ["plateau"])


if __name__ == "__main__":
    unittest.main()
