import contextlib
import dataclasses
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from moria_playtest import queue
from moria_playtest.brain import ready_level


def record(combo: str, outcome: str, steps: int = 1000, **extra) -> dict:
    return {"id": f"r-{combo}-{outcome}", "platform": "c64", "character": combo, "outcome": outcome,
            "steps": steps, "clvl": extra.pop("clvl", 5), "max_dlvl": extra.pop("max_dlvl", 3), **extra}


class QueueOrderTest(unittest.TestCase):
    """§23.4: a success goes to the back; a failure to the head, up to the
    retry cap in a row, then to the back marked struggling."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.queue = queue.Queue("deep", Path(self.tmp.name))
        self.entry = self.queue.platform("c64")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def play(self, outcome: str, **extra) -> str:
        combo = self.queue.take("c64", "run")
        self.queue.finish(record(combo, outcome, **extra), retry_cap=3)
        return combo

    def test_every_combination_is_an_item(self) -> None:
        self.assertEqual(len(self.entry["items"]), 31)
        self.assertEqual(len(self.entry["order"]), 31)

    def test_success_goes_to_the_back(self) -> None:
        first = self.play("reached")
        self.assertEqual(self.entry["order"][-1], first)
        self.assertNotEqual(self.queue.head("c64"), first)
        self.assertEqual(self.entry["items"][first]["success"]["run"], f"r-{first}-reached")

    def test_failures_retry_at_the_head_then_struggle(self) -> None:
        first = self.queue.head("c64")
        for _ in range(3):
            self.assertEqual(self.play("died"), first)
            self.assertEqual(self.queue.head("c64"), first)
        self.assertEqual(self.play("died"), first)   # the fourth failure in a row
        item = self.entry["items"][first]
        self.assertTrue(item["struggling"])
        self.assertEqual(self.entry["order"][-1], first)
        self.assertEqual(item["streak"], -4)

    def test_a_struggling_item_waits_ahead_of_the_successes(self) -> None:
        succeeded = self.play("reached")                 # now last
        first = self.queue.head("c64")
        for _ in range(4):
            self.play("died")
        order = self.entry["order"]
        self.assertTrue(self.entry["items"][first]["struggling"])
        self.assertEqual(order.index(first), order.index(succeeded) - 1)

    def test_open_items_get_parallel_runs_once_the_head_has_succeeded(self) -> None:
        import collections
        items = self.entry["items"]
        for combo in list(items)[:-1]:                   # all but one have succeeded
            items[combo]["success"] = {"run": "r"}
        open_ = list(items)[-1]
        self.entry["order"] = [c for c in self.entry["order"] if c != open_]
        self.queue.take("c64", "primary") if self.queue.head("c64") == open_ else None
        playing = collections.Counter({open_: 1})
        self.assertEqual(self.queue.parallel_pick("c64", playing, 3), open_)
        self.assertIsNone(self.queue.parallel_pick("c64", collections.Counter({open_: 3}), 3))   # the cap
        items[open_]["in_flight"] = "primary"
        order = list(self.entry["order"])
        self.queue.finish(record(open_, "reached"), retry_cap=3, parallel=True)
        self.assertEqual((items[open_]["runs"], items[open_]["in_flight"]), (1, "primary"))
        self.assertIsNotNone(items[open_]["success"])
        self.assertEqual(self.entry["order"], order)      # its place is its own run's

    def test_no_parallel_run_while_an_open_item_waits(self) -> None:
        import collections
        self.assertIsNone(self.queue.parallel_pick("c64", collections.Counter(), 3))

    def test_a_success_clears_struggling(self) -> None:
        first = self.queue.head("c64")
        for _ in range(4):
            self.play("budget")
        self.entry["order"].remove(first)
        self.entry["order"].insert(0, first)
        self.play("reached")
        self.assertFalse(self.entry["items"][first]["struggling"])
        self.assertEqual(self.entry["items"][first]["streak"], 1)

    def test_uncounted_outcomes_go_back_to_the_head_unchanged(self) -> None:
        first = self.queue.head("c64")
        for outcome in ("stale", "abandoned", "cancelled"):
            self.assertEqual(self.play(outcome), first)
            self.assertEqual(self.queue.head("c64"), first)
        self.assertEqual(self.entry["items"][first]["runs"], 0)

    def test_budget_is_three_times_the_slowest_success(self) -> None:
        config = dict(queue.DEFAULTS)
        self.assertEqual(self.queue.budget(config), 2_000_000)
        self.play("reached", steps=400_000)
        self.play("reached", steps=250_000)
        self.assertEqual(self.queue.budget(config), 1_200_000)

    def test_budget_has_a_floor(self) -> None:
        config = dict(queue.DEFAULTS)
        self.play("reached", steps=167_476)
        self.assertEqual(self.queue.budget(config), 750_000)   # not 502,428

    def test_the_cycle_counts_every_item_once(self) -> None:
        for _ in range(31):
            self.play("reached")
        self.assertEqual(self.entry["cycle"], 2)
        self.assertEqual(self.entry["cycle_done"], [])

    def test_best_keeps_the_deepest_run(self) -> None:
        first = self.queue.head("c64")
        self.play("died", max_dlvl=12, clvl=14, milestones={"dl5": 1, "dl10": 2, "clvl10": 3})
        self.play("died", max_dlvl=6, clvl=20)
        best = self.entry["items"][first]["best"]
        self.assertEqual((best["max_dlvl"], best["clvl"]), (12, 14))
        self.assertEqual(best["deepest"], "clvl10 dl10")


class ScheduleTest(unittest.TestCase):
    """§23.5: subqueues borrow workers; the main queue keeps its minimum,
    pausing its newest runs rather than losing them."""

    def service(self, workers: int) -> queue.Service:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name)
        config = home / "queue.json"
        config.write_text(json.dumps({"workers": workers}))
        service = queue.Service(home, config)
        service.build_id = "b1"
        started = []

        def start(job):
            job["slot"], job["pid"], job["paused"] = len(service.running), 0, False
            job["started"] = len(started)
            started.append(job)
            service.running[job["id"]] = job

        service.start = start   # type: ignore[method-assign]
        service.pause = lambda run_id, paused: service.running[run_id].update(paused=paused)   # type: ignore[method-assign]
        return service

    def test_main_characters_limit_the_main_queue(self) -> None:
        """2026-11-05: after M7 the main queue plays only the combinations
        the Balrog queue has no start for, one run each."""
        service = self.service(4)
        service.config["main_characters"] = ["human-warrior", "elf-warrior"]
        q = queue.Queue("deep", service.home)
        entry = q.platform("c64")
        for combo in entry["items"]:
            entry["items"][combo]["success"] = {"run": "m7"}   # M7 met: no parallel runs
        service.schedule(q, {})
        self.assertEqual(sorted(j["character"] for j in service.running.values()), ["elf-warrior", "human-warrior"])
        self.assertEqual(entry["order"], [c for c in queue.combos("c64")
                                          if c not in ("human-warrior", "elf-warrior")])   # the others keep their places

    def test_the_build_queue_plays_one_run_per_port(self) -> None:
        """2026-11-05: one run per port in build_platforms, of the build
        queue's own build, out of the total; the main queue keeps the rest."""
        service = self.service(6)
        service.config.update(build_platforms=["c64", "atari8", "apple2"], build_goal="clvl10")
        service.ci_build = "head1"
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.schedule(q, {})
        build = [j for j in service.running.values() if j["queue"] == "build"]
        self.assertEqual(sorted(j["platform"] for j in build), ["apple2", "atari8", "c64"])
        self.assertTrue(all(j["build"] == "head1" and j["goal"] == "clvl10" for j in build))
        self.assertEqual({j["character"] for j in build}, {queue.combos("c64")[0]})
        by_port = {j["platform"]: j["step_budget"] for j in build}
        self.assertEqual(by_port["c64"], 100_000)
        self.assertEqual(by_port["apple2"], round(100_000 * queue.PORTS["apple2"].map_scale))   # 80-column map
        self.assertEqual(sum(j["queue"] == "main" for j in service.running.values()), 3)
        service.schedule(q, {})   # one each: nothing more starts
        self.assertEqual(sum(j["queue"] == "build" for j in service.running.values()), 3)

    def test_no_build_queue_run_without_its_build(self) -> None:
        service = self.service(3)
        service.config["build_platforms"] = ["c64"]
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.schedule(q, {})
        self.assertFalse(any(j["queue"] == "build" for j in service.running.values()))

    def sub(self, count: int) -> dict:
        items = [{"goal": "clvl5", "character": "human-mage", "platform": "c64", "seed": n, "step_budget": 10}
                 for n in range(count)]
        return {"name": "ab", "build": "b1", "items": items, "next": 0, "results": []}

    def test_the_main_queue_fills_every_worker(self) -> None:
        service = self.service(4)
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.schedule(q, {})
        self.assertEqual(len(service.running), 4)
        self.assertEqual(len({j["character"] for j in service.running.values()}), 4)

    def test_a_subqueue_pauses_main_runs_down_to_the_minimum(self) -> None:
        service = self.service(4)
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.schedule(q, {})
        subs = {"ab": self.sub(10)}
        service.schedule(q, subs)
        main = [j for j in service.running.values() if j["queue"] == "main"]
        self.assertEqual(sum(not j["paused"] for j in main), 1)
        self.assertEqual(len(main), 4)   # paused, not stopped
        self.assertEqual(sum(j["queue"] == "ab" for j in service.running.values()), 3)
        # The subqueue drains: the paused runs resume before new ones start.
        for run_id in [r for r, j in service.running.items() if j["queue"] == "ab"]:
            del service.running[run_id]
        subs["ab"]["next"] = 10
        service.schedule(q, subs)
        self.assertEqual(sum(not j["paused"] for j in service.running.values()), 4)
        self.assertEqual(len(service.running), 4)

    def test_paused_config_pauses_everything(self) -> None:
        service = self.service(2)
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.schedule(q, {})
        service.config["paused"] = True
        service.schedule(q, {})
        self.assertTrue(all(j["paused"] for j in service.running.values()))


class BuildQueueTest(unittest.TestCase):
    """The build queue cycles every combination in table order whatever
    the outcome; a run that did not count plays again first."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.buildq = queue.BuildQueue(self.home)

    def test_cycles_in_table_order(self) -> None:
        order = queue.combos("bbcmaster")
        taken = [self.buildq.take("bbcmaster") for _ in range(len(order) + 2)]
        self.assertEqual(taken, order + order[:2])
        self.assertEqual(self.buildq.platform("bbcmaster")["cycle"], 2)

    def test_a_death_moves_on_and_an_abandoned_run_plays_again(self) -> None:
        first = self.buildq.take("c64")
        self.buildq.finish({**record(first, "died", clvl=7), "commit": "abc"})
        second = self.buildq.take("c64")
        self.assertNotEqual(second, first)
        self.buildq.finish(record(second, "abandoned"))
        self.assertEqual(self.buildq.take("c64"), second)
        item = self.buildq.platform("c64")["items"][first]
        self.assertEqual((item["runs"], item["reached"], item["best"]["clvl"], item["last"]["commit"]),
                         (1, 0, 7, "abc"))
        self.assertEqual(self.buildq.platform("c64")["items"][second]["runs"], 0)

    def test_its_runs_move_nothing_in_the_main_queue(self) -> None:
        service = queue.Service(self.home, self.home / "queue.json")
        q = queue.Queue("deep", self.home)
        q.platform("c64")
        before = json.dumps(q.state, sort_keys=True)
        combo = service.buildq.take("c64")
        run_dir = self.home / "runs" / "b1"
        queue.write_json(run_dir / "result.json", {**record(combo, "reached", clvl=10), "id": "b1", "queue": "build",
                                                    "goal": "deep"})
        service.running["b1"] = {"id": "b1", "queue": "build", "platform": "c64", "character": combo,
                                 "goal": "deep", "pid": 0, "started": 0}
        service.reap(q, {})
        self.assertEqual(json.dumps(q.state, sort_keys=True), before)
        self.assertEqual(queue.BuildQueue(self.home).platform("c64")["items"][combo]["reached"], 1)
        self.assertEqual(queue.Balrog(self.home).state["items"], {})


class SubqueueReportTest(unittest.TestCase):
    def test_suites_pass_at_their_bar(self) -> None:
        sub = {"items": [{"suite": "clvl5", "goal": "clvl5", "character": "x", "platform": "c64"}] * 3,
               "results": [{"suite": "clvl5", "goal": "clvl5", "character": "x", "platform": "c64",
                            "outcome": o} for o in ("reached", "reached", "died")],
               "suites": {"clvl5": {"required": 2, "seeds": 3}}}
        self.assertEqual(queue.subqueue_report(sub)["clvl5"],
                         {"reached": 2, "done": 3, "total": 3, "required": 2, "passed": True})

    def test_regress_items_cover_every_frozen_suite(self) -> None:
        items, suites = queue.regress_items("c64", None)
        self.assertEqual(len(suites), len([p for p in queue.SUITES.glob("*.json")
                                           if json.loads(p.read_text()).get("port", "c64") == "c64"]))
        self.assertEqual(len(items), sum(s["seeds"] for s in suites.values()))


class DeepGoalTest(unittest.TestCase):
    def test_readiness_tapers_to_level_25_on_dl30(self) -> None:
        taper = (12, 30, 25)
        self.assertEqual(ready_level(10, 3, taper), ready_level(10, 3))
        self.assertEqual(ready_level(30, 3, taper), 25)
        levels = [ready_level(d, 3, taper) for d in range(1, 31)]
        self.assertEqual(levels, sorted(levels))

    def test_deepest_names_the_furthest_milestones(self) -> None:
        self.assertEqual(queue.deepest({"milestones": {"dl5": 1, "clvl5": 2, "clvl10": 3}}), "clvl10 dl5")
        self.assertIsNone(queue.deepest({}))


class BalrogQueueTest(unittest.TestCase):
    """§23.9: a combination past the M7 bar joins the Balrog queue for good;
    its runs take up to balrog_workers of the total, turn about."""

    def service(self, workers: int, balrog_workers: int) -> queue.Service:
        service = ScheduleTest.service(self, workers)   # type: ignore[arg-type]
        service.config.update(balrog_workers=balrog_workers)
        service.build_id = "b0"
        self.make_build(service, "b0")
        return service

    @staticmethod
    def make_build(service: queue.Service, build: str, built: float = 1.0) -> Path:
        root = service.home / "builds" / build
        queue.write_json(root / "build.json", {"id": build, "platforms": sorted(queue.PORTS), "built": built})
        return root

    def test_an_m7_success_joins_once_and_stays_across_epochs(self) -> None:
        service = self.service(4, 2)
        q = queue.Queue("deep", service.home, "e1")
        combo = q.take("c64", "r1")
        q.finish(record(combo, "reached"), retry_cap=3)
        service.graduate(q)
        service.graduate(q)
        self.assertEqual(service.balrog.state["order"], [f"c64/{combo}"])
        self.assertEqual(service.balrog.state["items"][f"c64/{combo}"]["graduated"]["epoch"], "e1")
        service.graduate(queue.Queue("deep", service.home, "e2"))   # a new epoch, no successes yet
        self.assertEqual(queue.Balrog(service.home).state["order"], [f"c64/{combo}"])

    def test_its_workers_come_out_of_the_total(self) -> None:
        service = self.service(4, 2)
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.schedule(q, {})
        self.assertEqual(len(service.running), 4)
        self.assertFalse(any(j["queue"] == "balrog" for j in service.running.values()))   # no graduates
        service.balrog.graduate("c64", "elf-priest", {"run": "r"})
        service.schedule(q, {})
        balrog = [j for j in service.running.values() if j["queue"] == "balrog"]
        self.assertEqual([(j["character"], j["goal"], j["step_budget"]) for j in balrog],
                         [("elf-priest", "balrog", 3_000_000)] * 2)   # one graduate: two seeds of it
        self.assertEqual(len({j["seed"] for j in balrog}), 2)
        self.assertEqual(sum(not j["paused"] for j in service.running.values()), 4)
        self.assertEqual(sum(j["paused"] for j in service.running.values() if j["queue"] == "main"), 2)

    def balrog(self) -> queue.Balrog:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return queue.Balrog(Path(tmp.name))

    def test_graduates_take_turns(self) -> None:
        balrog = self.balrog()
        for combo in ("elf-priest", "human-priest"):
            balrog.graduate("c64", combo, {})
        self.assertEqual([balrog.take()["character"] for _ in range(3)], ["elf-priest", "human-priest", "elf-priest"])

    def test_a_finished_run_counts_for_its_graduate(self) -> None:
        balrog = self.balrog()
        balrog.graduate("c64", "elf-priest", {})
        balrog.finish(record("elf-priest", "died", max_dlvl=41, clvl=31, milestones={"dl40": 1, "clvl30": 2}))
        balrog.finish(record("elf-priest", "stale"))
        balrog.finish(record("elf-priest", "reached", max_dlvl=100, clvl=40))
        item = balrog.state["items"]["c64/elf-priest"]
        self.assertEqual((item["runs"], item["won"]), (2, 1))
        self.assertEqual((item["best"]["max_dlvl"], item["best"]["clvl"]), (100, 40))

    def success_run(self, service: queue.Service, with_brain: bool = True) -> dict:
        """An M7 success whose run kept a DL30 snapshot (with its brain)."""
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from moria_playtest.session import save_brain
        rec = record("elf-priest", "reached", id="m7", build="b0", goal="deep", clvl=25, max_dlvl=30)
        snaps = service.home / "runs" / "m7" / "w3" / "snapshots"
        snaps.mkdir(parents=True)
        vsf = snaps / "deep-9-s125346-dl30.vsf"
        vsf.write_bytes(b"VICE")
        queue.write_json(vsf.with_suffix(".brain.json"), {"seed": 9, "step": 125346, "dlvl": 30})
        if with_brain:
            save_brain(Brain(for_character(GOALS["deep"], "elf-priest")), vsf)
        self.make_build(service, "b0")
        return rec

    def test_an_m7_success_keeps_its_dl30_snapshot_as_the_start(self) -> None:
        service = self.service(4, 2)
        service.balrog_start({**self.success_run(service), "platform": "plus4"})   # a snapshot port
        item = service.balrog.state["items"]["plus4/elf-priest"]
        start = item["start"]
        self.assertEqual((start["run"], start["build"], start["step"], start["dlvl"]), ("m7", "b0", 125346, 30))
        kept = Path(start["snapshot"])
        self.assertEqual(kept.parent, service.home / "balrog" / "m7")
        self.assertTrue(kept.exists() and kept.with_suffix(".brain.pickle").exists())
        service.start_balrog()
        job = next(iter(service.running.values()))
        self.assertEqual((job["build"], job["resume"]["run"]), ("b0", "m7"))   # the start's build: its bot

    def test_a_start_plays_the_current_bot_when_its_brain_loads_there(self) -> None:
        """Maintainer, 2026-11-02: graduates of the build before the level-40
        Balrog goal still dove to DL30. A saved brain names only classes in
        brain.py, magic.py and view.py (the goal is not in it): a build with
        the same game and no attribute the saved brain lacks plays the
        start, with its own goals and bot."""
        service = self.service(4, 2)
        service.balrog_start({**self.success_run(service), "platform": "plus4"})   # a snapshot port
        same = "class Brain:\n    def __init__(self):\n        self.food = 0\n"
        same += "class Creature:\n    def __init__(self):\n        self.glyph = ''\n"
        reworded = same + "    def eat(self):\n        return self.food - 1\n"   # new code, no new state
        reworded = reworded.replace("self.food = 0", "self.food = 0\n        self.restock_wait = 0")   # filled on load
        grown = same.replace("self.glyph = ''", "self.glyph = ''\n        self.level = 0")   # not filled
        for n, (build, goals, brain) in enumerate((("b0", "old", same), ("b1", "new", reworded), ("b2", "new", grown))):
            root = self.make_build(service, build, built=n)
            (root / "build").mkdir(parents=True)
            (root / "build" / "moria8-c64.d64").write_bytes(b"disk")
            bot = root / "playtest" / "moria_playtest"
            bot.mkdir(parents=True)
            (bot / "goals.py").write_text(goals)
            (bot / "brain.py").write_text(brain)
            (bot / "magic.py").write_text("")
            (bot / "view.py").write_text("")
        self.assertTrue(queue.same_game_and_brain("b0", "b1", service.home))
        self.assertFalse(queue.same_game_and_brain("b0", "b2", service.home))
        service.build_id = "b1"
        service.start_balrog()
        job = next(iter(service.running.values()))
        self.assertEqual((job["build"], job["resume"]["run"]), ("b1", "m7"))
        service.running.clear()
        service.build_id = "b2"   # an attribute the old brain lacks: a new character, in the newest build
        service.start_balrog()
        job = next(iter(service.running.values()))
        self.assertEqual(job["build"], "b2")
        self.assertNotIn("resume", job)
        item = service.balrog.state["items"]["plus4/elf-priest"]
        self.assertIsNone(item["start"])
        self.assertEqual([s["run"] for s in item["retired_starts"]], ["m7"])

    def test_a_success_without_a_saved_brain_plays_from_the_title(self) -> None:
        service = self.service(4, 2)
        service.balrog_start(self.success_run(service, with_brain=False))
        service.balrog.graduate("c64", "elf-priest", {})
        service.start_balrog()
        job = next(iter(service.running.values()))
        self.assertEqual(job["build"], "b0")
        self.assertNotIn("resume", job)

    def c128_saved_game(self, service: queue.Service, rec: dict) -> None:
        """The run's graduate/ directory: a save disk and the brain (graduate.py)."""
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from moria_playtest.session import save_brain
        grad = service.home / "runs" / rec["id"] / "graduate"
        grad.mkdir(parents=True)
        (grad / "save.d64").write_bytes(b"D64")
        queue.write_json(grad / "graduate.brain.json", {"seed": 9, "step": 270563, "dlvl": 28})
        save_brain(Brain(for_character(GOALS["deep"], "elf-priest")), grad / "graduate.vsf")

    def test_a_c128_success_starts_the_balrog_queue_from_its_saved_game(self) -> None:
        """VICE's C128 snapshot leaves out the VDC: a restore stalled past the
        60 s limit, so a C128 graduate saves its game instead (2026-11-02)."""
        service = self.service(4, 2)
        rec = {**self.success_run(service), "platform": "c128"}   # a snapshot too: the saved game wins
        self.c128_saved_game(service, rec)
        service.balrog_start(rec)
        start = service.balrog.state["items"]["c128/elf-priest"]["start"]
        self.assertEqual((start["save"], start["step"], start["dlvl"]), (str(service.home / "balrog" / "m7"), 270563, 28))
        self.assertNotIn("snapshot", start)
        self.assertTrue((Path(start["save"]) / "save.d64").exists())
        self.assertTrue(service.start_balrog())
        job = next(iter(service.running.values()))
        self.assertEqual((job["build"], job["resume"]["save"]), ("b0", start["save"]))

    def test_a_c128_success_without_a_saved_game_gets_no_start(self) -> None:
        service = self.service(4, 2)
        service.balrog_start({**self.success_run(service), "platform": "c128"})
        service.balrog.graduate("c128", "elf-priest", {})
        self.assertIsNone(service.balrog.state["items"]["c128/elf-priest"].get("start"))
        self.assertTrue(service.start_balrog())   # no start: a new character from level 1
        self.assertNotIn("resume", next(iter(service.running.values())))

    def test_a_c128_snapshot_start_is_retired_for_a_new_character(self) -> None:
        """VICE's C128 snapshot leaves out the VDC: only a saved game goes on
        there, so a snapshot start retires and the combination plays from
        level 1 (maintainer, 2026-11-06)."""
        service = self.service(4, 2)
        service.balrog.graduate("c128", "elf-priest", {"run": "r"})
        item = service.balrog.state["items"]["c128/elf-priest"]
        item["start"] = {"run": "r", "build": "b0", "snapshot": "deep.vsf"}
        self.assertTrue(service.start_balrog())
        self.assertNotIn("resume", next(iter(service.running.values())))
        self.assertIsNone(item["start"])
        self.assertEqual([s["run"] for s in item["retired_starts"]], ["r"])

    def policy_build(self, service: queue.Service, build: str, oldest: int, current: int, built: float) -> None:
        """A build whose C128 loader takes saves ``oldest``..``current``, with a bot."""
        root = self.make_build(service, build, built)
        policy = root / "platforms" / "commodore" / "c128" / "hal" / "storage_policy.s"
        policy.parent.mkdir(parents=True)
        policy.write_text(f"#if HAL_PLATFORM_MONSTER_CATALOG\n.const hal_storage_save_v1_version = ${oldest:02X}\n"
                          f".const hal_storage_save_version = ${current:02X}\n#else\n"
                          f".const hal_storage_save_v1_version = $10\n.const hal_storage_save_version = $18\n#endif\n")
        bot = root / "playtest" / "moria_playtest"
        bot.mkdir(parents=True)
        for name in queue.BRAIN_MODULES:
            (bot / name).write_text("class Brain:\n    def __init__(self):\n        self.food = 0\n")

    def test_a_saved_game_goes_on_in_the_newest_build_that_loads_it(self) -> None:
        """Maintainer, 2026-11-06: the newest build always; a start whose
        save that build's loader takes goes on there, else a new character."""
        service = self.service(4, 2)
        self.policy_build(service, "old", 0x19, 0x19, 1)
        self.policy_build(service, "mid", 0x1A, 0x1A, 2)
        self.policy_build(service, "new", 0x1A, 0x1A, 3)
        self.assertEqual(queue.save_versions("old", "c128", service.home), (0x19, 0x19))
        service.build_id, service.ci_build = "mid", "new"
        self.assertEqual(service.newest_build("c128"), "new")
        for combo, build in (("elf-priest", "mid"), ("human-priest", "old")):
            service.balrog.graduate("c128", combo, {"run": combo})
            service.balrog.state["items"][f"c128/{combo}"]["start"] = {"run": combo, "build": build, "save": "s"}
        self.assertTrue(service.start_balrog())
        self.assertTrue(service.start_balrog())
        jobs = {j["character"]: j for j in service.running.values()}
        self.assertEqual({c: j["build"] for c, j in jobs.items()}, {"elf-priest": "new", "human-priest": "new"})
        self.assertEqual(jobs["elf-priest"]["resume"]["run"], "elf-priest")   # $1A loads in $1A
        self.assertNotIn("resume", jobs["human-priest"])                     # $19 does not
        self.assertIsNone(service.balrog.state["items"]["c128/human-priest"]["start"])

    def test_balrog_platforms_join_from_level_1_and_take_no_other_port(self) -> None:
        """Maintainer, 2026-11-06: the Balrog queue on the C64, every
        combination from level 1; the C128's M7 successes do not join."""
        service = self.service(4, 2)
        service.config["balrog_platforms"] = ["c64"]
        q = queue.Queue("deep", service.home)
        entry = q.platform("c128")
        entry["items"]["elf-priest"]["success"] = {"run": "m7"}
        service.graduate(q)
        items = service.balrog.state["items"]
        self.assertEqual(sorted(items), sorted(f"c64/{c}" for c in queue.combos("c64")))
        service.graduate(q)   # joined once
        self.assertEqual(len(service.balrog.state["order"]), len(queue.combos("c64")))
        service.balrog_start({**self.success_run(service), "platform": "c128"})
        self.assertNotIn("c128/elf-priest", items)
        self.assertTrue(service.start_balrog())
        job = next(iter(service.running.values()))
        self.assertEqual((job["platform"], job["build"]), ("c64", "b0"))
        self.assertNotIn("resume", job)

    def test_an_m7_success_leads_a_chain_still_below_its_level(self) -> None:
        balrog = self.balrog()
        balrog.graduate("c128", "elf-priest", {})
        item = balrog.state["items"]["c128/elf-priest"]
        item["start"] = {"run": "r1-clvl12", "clvl": 12, "checkpoint": True, "save": "balrog/r1-clvl12"}
        balrog.set_start(self.balrog_record("m7", "reached"), {"run": "m7", "save": "balrog/m7"})
        self.assertEqual(item["start"]["run"], "m7")
        self.assertEqual([s["run"] for s in item["start_history"]], ["r1-clvl12"])

    def test_a_saved_brain_loads_with_the_balrog_goal(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from moria_playtest.session import load_brain, save_brain
        with tempfile.TemporaryDirectory() as tmp:
            snap = Path(tmp) / "s.vsf"
            brain = Brain(for_character(GOALS["deep"], "elf-priest"))
            brain.clw, brain.oil = 5, 10
            self.assertTrue(save_brain(brain, snap))
            balrog = for_character(GOALS["balrog"], "elf-priest")
            loaded = load_brain(snap, balrog)
        self.assertIs(loaded.goal, balrog)
        self.assertEqual((loaded.clw, loaded.oil), (5, 10))

    # -- checkpoints (maintainer, 2026-11-05: a save at each new character
    # level, so a death goes on from the latest; a win through them counts)

    def checkpoint_run(self, service: queue.Service, run_id: str, clvl: int, step: int,
                       snapshot: bool = False) -> None:
        """A Balrog run's checkpoint directory, as run_one's QueueCharacter keeps it."""
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from moria_playtest.session import save_brain
        ckpt = service.home / "runs" / run_id / queue.CHECKPOINTS / f"clvl{clvl:02d}"
        ckpt.mkdir(parents=True)
        state: dict = {"clvl": clvl, "step": step, "dlvl": 20}
        if snapshot:
            brain_file = ckpt / "balrog-1-s1-dl20.vsf"
            brain_file.write_bytes(b"VICE")
            state["snapshot"] = brain_file.name
        else:
            brain_file = ckpt / "graduate.vsf"
            (ckpt / "save.d64").write_bytes(b"D64")
        save_brain(Brain(for_character(GOALS["deep"], "elf-priest")), brain_file)
        queue.write_json(ckpt / "checkpoint.json", state)

    def c128_graduate(self, service: queue.Service) -> dict:
        rec = {**self.success_run(service), "platform": "c128"}
        self.c128_saved_game(service, rec)
        service.balrog_start(rec)
        return service.balrog.state["items"]["c128/elf-priest"]

    def balrog_record(self, run_id: str, outcome: str = "died", **extra) -> dict:
        return {**record("elf-priest", outcome, id=run_id, **extra), "platform": "c128"}

    def test_a_balrog_run_goes_on_from_its_highest_checkpoint(self) -> None:
        service = self.service(4, 2)
        item = self.c128_graduate(service)
        job = {"id": "b1", "build": "b0", "resume": item["start"]}
        self.checkpoint_run(service, "b1", 26, 300_000)
        self.checkpoint_run(service, "b1", 27, 350_000)
        self.assertTrue(service.balrog_checkpoint(self.balrog_record("b1", clvl=27), job))
        start = item["start"]
        self.assertEqual((start["run"], start["clvl"], start["step"], start["build"], start["graduate"], start["restores"]),
                         ("b1-clvl27", 27, 350_000, "b0", "m7", 1))
        self.assertTrue((Path(start["save"]) / "save.d64").exists())
        self.assertEqual([s["run"] for s in item["start_history"]], ["m7"])
        self.assertTrue(service.start_balrog())
        run = next(iter(service.running.values()))
        self.assertEqual((run["resume"]["run"], run["step_budget"]), ("b1-clvl27", 3_000_000 + 350_000))

    def test_a_snapshot_port_checkpoint_is_its_level_entry_snapshot(self) -> None:
        service = self.service(4, 2)
        service.balrog_start({**self.success_run(service), "platform": "plus4"})
        item = service.balrog.state["items"]["plus4/elf-priest"]
        self.checkpoint_run(service, "b1", 26, 300_000, snapshot=True)
        rec = {**self.balrog_record("b1"), "platform": "plus4"}
        self.assertTrue(service.balrog_checkpoint(rec, {"build": "b0", "resume": item["start"]}))
        self.assertEqual(Path(item["start"]["snapshot"]), service.home / "balrog" / "b1-clvl26" / "balrog-1-s1-dl20.vsf")
        self.assertTrue(Path(item["start"]["snapshot"]).exists())

    def test_a_checkpoint_no_higher_than_the_start_is_not_taken(self) -> None:
        """Two runs from one start: the second's lower level does not undo the first's."""
        service = self.service(4, 2)
        item = self.c128_graduate(service)
        graduate_start = dict(item["start"])
        self.checkpoint_run(service, "b1", 27, 350_000)
        self.checkpoint_run(service, "b2", 26, 320_000)
        self.assertTrue(service.balrog_checkpoint(self.balrog_record("b1"), {"build": "b0", "resume": graduate_start}))
        self.assertFalse(service.balrog_checkpoint(self.balrog_record("b2"), {"build": "b0", "resume": graduate_start}))
        self.assertEqual(item["start"]["run"], "b1-clvl27")
        self.assertFalse(service.balrog.fell_short(self.balrog_record("b2"), {"resume": graduate_start}))   # not the start now
        self.assertNotIn("fails", item["start"])

    def test_a_dead_end_checkpoint_steps_back(self) -> None:
        balrog = self.balrog()
        balrog.graduate("c128", "elf-priest", {})
        item = balrog.state["items"]["c128/elf-priest"]
        base = {"run": "m7", "save": "balrog/m7", "step": 1, "dlvl": 20}
        item["start"] = base
        self.assertTrue(balrog.checkpoint(self.balrog_record("r1"), {"resume": base},
                                          {"run": "r1-clvl28", "clvl": 28, "save": "balrog/r1-clvl28"}))
        checkpoint = item["start"]
        steps = [balrog.fell_short(self.balrog_record(f"f{n}"), {"resume": checkpoint})
                 for n in range(queue.CHECKPOINT_RETRIES)]
        self.assertEqual(steps, [False] * (queue.CHECKPOINT_RETRIES - 1) + [True])
        self.assertEqual(item["start"]["run"], "m7")
        self.assertEqual(item["start"]["restores"], 1 + queue.CHECKPOINT_RETRIES)
        self.assertEqual(item["start_history"], [])
        self.assertFalse(balrog.fell_short(self.balrog_record("w", "reached"), {"resume": item["start"]}))   # a win
        for n in range(queue.CHECKPOINT_RETRIES):   # the graduate's own start never steps back
            self.assertFalse(balrog.fell_short(self.balrog_record(f"g{n}"), {"resume": item["start"]}))

    def test_a_win_through_checkpoints_counts(self) -> None:
        balrog = self.balrog()
        balrog.graduate("c128", "elf-priest", {})
        balrog.finish(self.balrog_record("w", "reached", clvl=40, max_dlvl=50,
                                         resumed_from={"run": "r1-clvl39", "restores": 7}))
        item = balrog.state["items"]["c128/elf-priest"]
        self.assertEqual(item["won"], 1)
        self.assertEqual([(w["id"], w["restores"]) for w in item["wins"]], [("w", 7)])

    def test_a_newer_graduate_keeps_the_chain(self) -> None:
        service = self.service(4, 2)
        item = self.c128_graduate(service)
        self.checkpoint_run(service, "b1", 27, 350_000)
        service.balrog_checkpoint(self.balrog_record("b1"), {"build": "b0", "resume": item["start"]})
        service.balrog.set_start({**self.balrog_record("m7b", "reached"), "id": "m7b"}, {"run": "m7b", "save": "x"})
        self.assertEqual(item["start"]["run"], "b1-clvl27")
        self.assertEqual([s["run"] for s in item["start_history"]], ["m7b"])   # the base a step back reaches

    def test_retention_keeps_the_chains_starts(self) -> None:
        service = self.service(4, 2)
        item = self.c128_graduate(service)
        self.checkpoint_run(service, "b1", 27, 350_000)
        service.balrog_checkpoint(self.balrog_record("b1"), {"build": "b0", "resume": item["start"]})
        (service.home / "balrog" / "gone").mkdir()
        service.last_sweep = 0.0
        service.sweep()
        self.assertEqual(sorted(p.name for p in (service.home / "balrog").iterdir()), ["b1-clvl27", "m7"])

    def test_level_40_before_the_balrog(self) -> None:
        """Maintainer, 2026-11-02: character level 38-40 (really 40), then
        the Balrog. A graduate at level 25 does not go below DL22."""
        from moria_playtest.brain import ready_level
        from moria_playtest.goals import GOALS
        goal = GOALS["balrog"]
        def ready(dlvl: int) -> int:
            return ready_level(dlvl, goal.ready_margin, goal.ready_taper)
        self.assertEqual(max(d for d in range(1, 101) if ready(d) <= 25), 22)
        self.assertEqual(max(d for d in range(1, 101) if ready(d) <= 39), 36)
        self.assertEqual(ready(50), 40)

    def test_a_saved_brain_gains_the_attributes_newer_code_adds(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from moria_playtest.session import load_brain, save_brain
        with tempfile.TemporaryDirectory() as tmp:
            snap = Path(tmp) / "s.vsf"
            brain = Brain(for_character(GOALS["deep"], "elf-priest"))
            del brain.restock_wait, brain.magic.known, brain.level.bumped   # as an older bot saved it
            brain.clw = 5
            self.assertTrue(save_brain(brain, snap))
            loaded = load_brain(snap, for_character(GOALS["balrog"], "elf-priest"))
        self.assertEqual(loaded.clw, 5)
        self.assertEqual((loaded.restock_wait, loaded.magic.known, loaded.level.bumped),
                         (Brain(GOALS["deep"]).restock_wait, {}, {}))

    def test_a_game_without_a_level_for_level_steps_ends(self) -> None:
        from moria_playtest.goals import GOALS
        from moria_playtest.session import LevelWatch
        watch = LevelWatch()
        self.assertIsNone(watch.note(0, 18, 2, 150_000))
        self.assertIsNone(watch.note(149_999, 18, 2, 150_000))
        self.assertIsNone(watch.note(149_999, 19, 2, 150_000))          # a level restarts the count
        self.assertIsNone(watch.note(299_998, 19, 2, 150_000))
        self.assertIn("clvl 19 on DL2", watch.note(299_999, 19, 2, 150_000))
        self.assertIsNone(LevelWatch().note(10**7, 18, 2, 0))           # 0: never
        self.assertEqual(GOALS["deep"].level_steps, 150_000)
        self.assertEqual(GOALS["balrog"].level_steps, 0)

    def test_a_loop_is_named_once_a_stay(self) -> None:
        """Maintainer, 2026-11-03: loops should be obvious. One square entered
        LOOP_RECENT times within LOOP_WINDOW steps is named once a stay on a
        level, with the decisions that kept coming back; exploring is not."""
        from moria_playtest.session import LOOP_RECENT, LoopWatch
        watch = LoopWatch()
        named = [watch.note(step, 2, (5, 5) if step % 2 else (6, 5), "rest", "hurt: back away")
                 for step in range(1, 2 * LOOP_RECENT + 10)]
        found = [n for n in named if n]
        self.assertEqual(len(found), 1)
        self.assertIn("on DL2: rest: hurt: back away", found[0])
        walk = LoopWatch()
        self.assertFalse(any(walk.note(step, 3, (step, 5), "explore", "edge") for step in range(5000)))
        self.assertIsNotNone(next(n for n in (watch.note(9000 + k, 3, (5, 5) if k % 2 else (6, 5), "rest", "x")
                                              for k in range(2 * LOOP_RECENT + 10)) if n))   # a new stay: named again

    def test_a_restored_game_goes_on_counting_its_steps(self) -> None:
        """M8, 2026-11-02: a new emulator counted game steps from 0, so the
        brain's town-trip timers, set at the graduate's steps, were hundreds
        of thousands of steps away."""
        from moria_playtest.worker import Snapshot, Worker

        class Fake:
            step = 0
            seed = 0

            def undump(self, path: Path) -> str:
                return f"step {self.step}"
        worker = Worker.__new__(Worker)
        worker.restarts, game = 0, Fake()
        worker._spawn = lambda autostart: game   # type: ignore[method-assign]
        obs = worker.restore(Snapshot(Path("s.vsf"), {"seed": 7, "step": 251110}))
        self.assertEqual((obs, game.step, game.seed), ("step 251110", 251110, 7))

    def test_the_goal_is_the_winner_flag(self) -> None:
        from moria_playtest.goals import GOALS
        goal = GOALS["balrog"]
        self.assertTrue(goal.reached(mock.Mock(game_flags=0x04)))
        self.assertFalse(goal.reached(mock.Mock(game_flags=0x01)))
        self.assertEqual(goal.target_dlvl, 100)

    def test_readiness_tops_out_at_level_40(self) -> None:
        taper = (12, 30, 25)
        levels = [ready_level(d, 3, taper) for d in range(1, 101)]
        self.assertEqual(levels, sorted(levels))
        self.assertEqual(ready_level(30, 3, taper), 25)   # the deep goal's curve is unchanged
        self.assertEqual(max(levels), 40)


class ProcAliveTest(unittest.TestCase):
    def test_a_run_is_known_by_its_id_wherever_home_lives(self) -> None:
        """A run started before HOME moved (var/playtest-queue to var/moria8)
        is still alive; a suffixed id is another run."""
        import subprocess
        import sys
        proc = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)",
                                 "/x/var/playtest-queue/runs/20261101-1-main-c64-elf-priest-5"])
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        cmdline = Path(f"/proc/{proc.pid}/cmdline")
        for _ in range(500):   # until the child has exec'd (until then it shows the parent's)
            if b"time.sleep" in cmdline.read_bytes():
                break
            queue.time.sleep(0.01)
        self.assertTrue(queue.proc_alive(proc.pid, "/x/var/moria8/runs/20261101-1-main-c64-elf-priest-5"))
        self.assertFalse(queue.proc_alive(proc.pid, "/x/var/moria8/runs/20261101-1-main-c64-elf-priest-5-2"))
        self.assertFalse(queue.proc_alive(proc.pid, "/x/var/moria8/runs/20261101-1-main-c64-elf-priest"))


class AdoptTest(unittest.TestCase):
    def test_a_run_gone_before_the_service_started_is_not_counted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            q = queue.Queue("deep", home)
            combo = q.take("c64", "r1")
            q.save()
            job = {"id": "r1", "queue": "main", "platform": "c64", "character": combo, "goal": "deep",
                   "seed": 5, "pid": 999_999_999, "slot": 0, "paused": False, "started": 1, "build": "b"}
            queue.write_json(home / "running.json", {"r1": job})
            service = queue.Service(home, home / "queue.json")
            with mock.patch.object(queue.time, "sleep"):
                service.reap(q, {}, adopting=True)
            self.assertEqual(q.head("c64"), combo)
            self.assertEqual(q.platform("c64")["items"][combo]["runs"], 0)
            self.assertIn('"abandoned"', (home / "runs.jsonl").read_text())


if __name__ == "__main__":
    unittest.main()


class CastLedgerTest(unittest.TestCase):
    """M7 criterion 2: each cast is recorded, and its effect only when
    something came of it (a message of its own, a move, a heal)."""

    def cast(self, name: str, after: str, moved: bool = False, hp: int = 10, signature=None) -> dict:
        import dataclasses
        from moria_playtest.game import Mode
        from moria_playtest.magic import Magic, Prayer
        from test_m1 import command_obs
        magic = Magic("mage")
        magic.signature = (0, 0, 0)
        magic.known[name] = Prayer("a", 1, 1, "Beginners-Magick")
        magic.wanted, magic.current = name, "Beginners-Magick"
        magic.listed_books.add("Beginners-Magick")
        which = dataclasses.replace(command_obs(hp=10, mhp=20), mode=Mode.SPELL, stage="which")
        which.rows[0] = "Cast which? (a-a, ESC)".ljust(40)
        magic.prompt(which)
        done = command_obs(hp=hp, mhp=20, pos=(11, 5) if moved else (10, 5))
        done.rows[0] = after.ljust(40)
        magic.watch_cast(done, signature or (0, 0, 0))
        return magic.ledger[name]

    def test_a_message_is_the_effect(self) -> None:
        entry = self.cast("Light Area", "The area fills with light.")
        self.assertEqual((entry["cast"], entry["effect"], entry["failed"]), (1, 1, 0))
        self.assertEqual(entry["evidence"], "The area fills with light.")

    def test_a_failed_or_fizzled_cast_is_not(self) -> None:
        self.assertEqual(self.cast("Light Area", "Your spell fails.")["failed"], 1)
        self.assertEqual(self.cast("Magic Missile", "Your spell fizzles out.")["effect"], 0)

    def test_a_move_or_a_heal_without_a_message(self) -> None:
        self.assertEqual(self.cast("Phase Door", "", moved=True)["evidence"], "moved")
        self.assertEqual(self.cast("Cure Light Wounds", "", hp=15)["evidence"], "healed")
        self.assertEqual(self.cast("Detect Monsters", "")["effect"], 0)
        self.assertEqual(self.cast("Find Traps", "", signature=(2, 0, 0))["evidence"], "traps shown")

    def test_a_hit_below_the_direction_prompt(self) -> None:
        import dataclasses
        from moria_playtest.game import Mode
        from moria_playtest.magic import Magic, Prayer
        from test_m1 import command_obs
        magic = Magic("mage")
        magic.signature = (0, 0, 0)
        magic.known["Magic Missile"] = Prayer("a", 1, 1, "Beginners-Magick")
        magic.wanted, magic.current = "Magic Missile", "Beginners-Magick"
        magic.listed_books.add("Beginners-Magick")
        which = dataclasses.replace(command_obs(), mode=Mode.SPELL, stage="which")
        magic.prompt(which)
        more = dataclasses.replace(command_obs(), mode=Mode.DISMISS, stage="more")
        more.rows[0] = "Direction?                        -more-"
        more.rows[1] = "Your spell hits the Giant White Centipede."
        magic.watch_cast(more)
        magic.watch_cast(command_obs(), (0, 0, 0))
        self.assertEqual(magic.ledger["Magic Missile"]["evidence"], "Your spell hits the Giant White Centipede.")

    def test_a_creatures_doing_is_not_the_spells(self) -> None:
        self.assertEqual(self.cast("Magic Missile", "The White Icky-Thing hits you.")["effect"], 0)
        self.assertEqual(self.cast("Magic Missile", "The Kobold dies. The Jackal bites you.")["evidence"],
                         "The Kobold dies.")

    def test_every_class_spell_list_comes_from_the_sources(self) -> None:
        from moria_playtest import knowledge
        counts = {c: sum(level <= 25 for level in knowledge.spells(c).values())
                  for c in ("mage", "priest", "rogue", "ranger", "paladin")}
        self.assertEqual(counts, {"mage": 28, "priest": 29, "rogue": 11, "ranger": 24, "paladin": 24})


class GroupCasterTest(unittest.TestCase):
    """M7 queue (tactic group_casters): three Orc Shamans, each alone too weak to worry about, took
    a 56-HP level-13 Elf Mage from 24 HP to dead in two turns. On the deep
    goal ``leave_caster`` adds up every caster in view."""

    def decide(self, goal: str, shamans: int) -> str:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        brain = Brain(GOALS[goal])
        brain.food = 3
        view = town_view((5, 5), (12, 5), dlvl=10, stairs_type=0xA)   # within RETREAT_RANGE
        view.creatures = {(5 + 8, 13 + i): Creature("o", 9) for i in range(shamans)}
        return brain.decide(command_obs(pos=(5, 5), dlvl=10, clvl=13, hp=60, mhp=60), view).layer

    def test_a_pack_of_casters_is_left(self) -> None:
        self.assertNotEqual(self.decide("deep", 1), "leave-caster")   # two casts (48) cannot kill 60 HP
        self.assertEqual(self.decide("deep", 3), "leave-caster")

    def test_other_goals_keep_their_frozen_rule(self) -> None:
        self.assertNotEqual(self.decide("clvl10", 3), "leave-caster")


class HealBeforeCureTest(unittest.TestCase):
    """M7 queue (tactic heal_first): a Gnome Priest prayed Neutralize Poison twice
    beside a Black Mamba from 29 HP and died; the heal comes first."""

    def decide(self, goal: str, hp: int, creature: tuple[str, int] = ("R", 9)) -> str:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.magic import Prayer
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        brain = Brain(dataclasses.replace(GOALS[goal], klass="priest"))
        brain.food = 3
        brain.magic.known = {"Cure Light Wounds": Prayer("b", 1, 1), "Neutralize Poison": Prayer("a", 6, 1)}
        brain.magic.study_due, brain.magic.listed = False, True
        brain.poisoned = True
        view = town_view((5, 5), (12, 5), dlvl=12, stairs_type=0xA)
        view.creatures = {(6, 5): Creature(*creature)}
        obs = command_obs(pos=(5, 5), dlvl=12, clvl=15, hp=hp, mhp=60,
                          rows={23: f"HP:{hp}/60  MP:20/20 AC:20  AU:100"})
        return brain.decide(obs, view).reason

    def test_hurt_beside_a_creature_the_heal_comes_first(self) -> None:
        # A King Cobra (normal speed; VMS: 1d2 spit, 3d4 poison bite, against
        # AC 20 about 4 a turn) is one the heal outruns.
        self.assertIn("Cure Light Wounds", self.decide("deep", 25))
        self.assertIn("Neutralize Poison", self.decide("deep", 50))   # not hurt: cure the poison
        self.assertIn("Neutralize Poison", self.decide("clvl10", 25))   # the frozen goals keep their order

    def test_no_heal_that_a_black_mamba_outruns(self) -> None:
        """M7 queue, 2026-11-02: a Black Mamba bites twice a turn (fast),
        more than Cure Light Wounds (3d3) heals; 45 characters healed beside
        one until they died. Fighting on at least hurts it."""
        self.assertEqual(self.decide("deep", 25, ("R", 12)), "attack adjacent 'R'")


class FastCreatureTest(unittest.TestCase):
    """M7 queue (tactic fight_fast): a Gnome Rogue ran from a Black Mamba on the
    turns it missed and died with its potions drunk; it fights instead."""

    def test_a_fast_creature_close_is_not_run_from(self) -> None:
        from moria_playtest import knowledge
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        mamba = knowledge.kinds_by_name()["Black Mamba"]
        layers = {}
        for goal in ("deep", "clvl10"):
            brain = Brain(GOALS[goal])
            brain.food = 3
            view = town_view((5, 5), (12, 5), dlvl=13, stairs_type=0xA)
            view.creatures = {(6, 6): Creature(*mamba)}
            layers[goal] = brain.decide(command_obs(pos=(5, 5), dlvl=13, clvl=16, hp=40, mhp=103), view).layer
        self.assertNotEqual(layers["deep"], "retreat")
        self.assertEqual(layers["clvl10"], "retreat")


class SlowKindTest(unittest.TestCase):
    """M8, 2026-11-02: a level-25 Halfling fought an Iron Golem (slow, 80d8,
    AC 99) to the death with no stairs known: walking away judged 'g' by
    glyph, and a Ghoul drawn the same is not slow."""

    def test_walks_away_from_a_slow_kind_whose_glyph_is_shared(self) -> None:
        from moria_playtest import knowledge
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        golem = knowledge.kinds_by_name()["Iron Golem"]
        self.assertIn(golem, knowledge.slow_kinds())
        self.assertNotIn("g", knowledge.slow_glyphs())
        brain = Brain(for_character(GOALS["balrog"], "halfling-warrior"))
        brain.food = 20
        view = town_view((10, 10), (40, 40), dlvl=22)   # no stairs known
        view.creatures = {(11, 10): Creature(*golem)}
        obs = command_obs(pos=(10, 10), dlvl=22, clvl=25, hp=100, mhp=207,
                          rows={23: "HP:100/207  MP:0/0  AC:40  AU:100"})
        brain.track(obs, view)
        decision = brain.decide(obs, view)
        self.assertEqual((decision.layer, decision.reason), ("retreat", "walk away from a slower creature"))


class CautionReadinessTest(unittest.TestCase):
    """The danger, caution, readiness and memory rules (maintainer,
    2026-11-03). Expected values come from the rules as decided, not from
    the bot's code."""

    def setUp(self) -> None:
        from moria_playtest import knowledge
        from moria_playtest.view import Creature
        self.kobold = Creature("k", 1)                                  # VMS Kobold: 1d6 bite, normal speed
        self.mamba = Creature(*knowledge.kinds_by_name()["Black Mamba"])   # fast, 4d4 bite

    def brain(self, character: str = "human-warrior"):  # type: ignore[no-untyped-def]
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        brain = Brain(for_character(GOALS["deep"], character))
        brain.food = 10
        return brain

    def test_with_no_way_out_a_potion_that_outlasts_the_turn_is_drunk(self) -> None:
        # 2026-11-04: Mages at clvl 17-22 spent their mana, then fought to the
        # death holding five Cure Light Wounds.
        from test_m1 import command_obs, town_view
        mage = self.brain("elf-mage")
        mage.clw, mage.phase = 5, 0
        view = town_view((5, 5), (30, 30), dlvl=15)
        view.creatures = {(6, 5): self.mamba}                           # danger 32: 8 heals under a third
        mage.adjacent = [self.mamba]
        hurt = command_obs(pos=(5, 5), dlvl=15, clvl=20, hp=30, mhp=90, rows={23: "HP:30/90  MP:0/30 AU:100"})
        self.assertEqual(mage.quaff(hurt, view).layer, "quaff")
        mage.phase = 1                                                   # a way out: phase, not this potion
        self.assertIsNone(mage.quaff(hurt, view))

    def test_early_and_out_of_potions_goes_back_to_town(self) -> None:
        # 2026-11-04: eleven of twelve Kobold deaths at level 1-4 had drunk
        # their Cure Light Wounds and explored on.
        from test_m1 import command_obs
        priest = self.brain("elf-priest")
        broke = command_obs(dlvl=1, clvl=2, rows={23: "HP:10/10  MP:2/2 AC:10 AU:30"})
        rich = command_obs(dlvl=1, clvl=2, rows={23: "HP:10/10  MP:2/2 AC:10 AU:100"})
        self.assertFalse(priest.out_of_cures(broke))                       # not the gold for two
        self.assertTrue(priest.out_of_cures(rich))
        self.assertTrue(priest.needs_resupply(rich))
        priest.end_visit(rich)                                             # town had none: not straight back
        self.assertFalse(priest.needs_resupply(rich))
        priest.clw = 1
        self.assertFalse(priest.out_of_cures(rich))
        self.assertFalse(priest.out_of_cures(command_obs(dlvl=1, clvl=5, rows={23: "AU:100"})))

    def test_an_early_caster_keeps_potion_gold_before_word_of_recall(self) -> None:
        # 2026-11-04: Elf Priests paid 160 of 238 gold for Word of Recall at
        # level 1 and died at level 1-4 holding no potions.
        from moria_playtest.brain import CLW_GOLD, CLW_RESERVE
        from test_m1 import command_obs
        priest, warrior = self.brain("elf-priest"), self.brain("human-warrior")
        early, later = command_obs(dlvl=0, clvl=1), command_obs(dlvl=0, clvl=5)
        self.assertEqual(priest.early_potion_gold(early), CLW_RESERVE * CLW_GOLD)
        self.assertEqual(priest.early_potion_gold(later), 0)
        self.assertEqual(warrior.early_potion_gold(early), 0)
        priest.clw = CLW_RESERVE
        self.assertEqual(priest.early_potion_gold(early), 0)

    def test_after_a_phase_the_bot_makes_for_the_stairs(self) -> None:
        # 2026-11-04: a level-4 Elf Priest phased from an Orc at 5 HP, saw
        # nothing and explored straight back to it.
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        priest = self.brain("elf-priest")
        priest.phase = 1
        orc = Creature("o", 3)
        view = town_view((5, 5), (20, 5), dlvl=2, stairs_type=0xA)
        view.creatures = {(6, 5): orc}
        priest.adjacent = [orc]
        hurt = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=5, mhp=25)
        self.assertEqual(priest.phase_door(hurt, view).layer, "phase")
        after = town_view((12, 5), (20, 5), dlvl=2, stairs_type=0xA)   # landed, nothing in view
        priest.adjacent = []
        decision = priest.retreat(command_obs(pos=(12, 5), dlvl=2, clvl=4, hp=6, mhp=25), after)
        self.assertEqual((decision.layer, priest.level.retreat_to), ("retreat", (20, 5)))

    def test_danger_counts_reach_speed_and_breeders(self) -> None:
        from moria_playtest.brain import Brain
        from test_m1 import command_obs, town_view
        obs = command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=40, mhp=40)
        view = town_view((5, 5), (40, 40), dlvl=3)
        view.creatures = {(6, 5): self.kobold}
        self.assertEqual(Brain.danger((5, 5), view, obs), 6)          # beside: 1d6 at its most
        self.assertEqual(Brain.danger((4, 5), view, obs), 0)          # two off, normal speed: cannot reach
        view.creatures = {(7, 5): self.mamba}
        self.assertEqual(Brain.danger((5, 5), view, obs), 16)         # two off, fast: steps in, strikes once
        view.creatures = {(6, 5): self.mamba}
        self.assertEqual(Brain.danger((5, 5), view, obs), 32)         # beside: strikes twice

    def test_back_away_only_from_a_slower_creature(self) -> None:
        """2026-11-03: backing away from a Kobold (as fast as the player) gave
        up every attack while it followed and bit; half the early deaths of a
        run without the leash had done so. Only a slower creature is backed
        away from, to a square out of its reach."""
        from moria_playtest.brain import Brain
        from moria_playtest.view import DIRS, Creature
        from test_m1 import command_obs, town_view
        brain = self.brain()
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(6, 5): self.kobold}
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=12, mhp=30)        # danger 6 > 0.4 x 12
        self.assertIsNone(brain.caution(obs, view))                         # as fast: no backing away
        snake = Creature("R", 2)                                            # Large Black Snake: slow
        view.creatures = {(6, 5): snake}
        hp = int(Brain.danger((5, 5), view, obs) / 0.4) - 1                 # just over CAUTION_BACK
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=hp, mhp=30)
        decision = brain.caution(obs, view)
        self.assertEqual(decision.layer, "caution")
        step = next(d for d, k in DIRS.items() if k == decision.key)
        self.assertGreater(abs((5 + step[0]) - 6), 1)                       # out of its reach

    def test_readiness_wants_hp_and_supplies_by_class(self) -> None:
        from test_m1 import command_obs
        mage, warrior = self.brain("human-mage"), self.brain("human-warrior")
        for b in (mage, warrior):
            b.clw, b.recall = 2, 1
        self.assertFalse(warrior.prepared(command_obs(dlvl=1, clvl=2, hp=20, mhp=20), 2))   # DL2: 30 HP
        self.assertTrue(warrior.prepared(command_obs(dlvl=2, clvl=4, hp=50, mhp=50), 3))
        self.assertFalse(mage.prepared(command_obs(dlvl=2, clvl=4, hp=50, mhp=50), 3))      # Mage: clvl 11
        self.assertTrue(mage.prepared(command_obs(dlvl=2, clvl=11, hp=40, mhp=40), 3))
        self.assertTrue(mage.prepared(command_obs(dlvl=4, clvl=18, hp=57, mhp=57), 5))      # no HP floor past DL2
        self.assertFalse(mage.prepared(command_obs(dlvl=13, clvl=18, hp=90, mhp=90), 14))   # a Mage: five over from DL10
        self.assertTrue(mage.prepared(command_obs(dlvl=13, clvl=19, hp=90, mhp=90), 14))
        self.assertTrue(warrior.prepared(command_obs(dlvl=13, clvl=17, hp=150, mhp=150), 14))   # others: three
        warrior.clw = 1
        self.assertFalse(warrior.prepared(command_obs(dlvl=2, clvl=4, hp=50, mhp=50), 3))   # two cure potions
        warrior.clw, warrior.recall = 2, 0
        self.assertFalse(warrior.prepared(command_obs(dlvl=4, clvl=6, hp=60, mhp=60), 5))   # Word of Recall

    def test_a_weak_character_leaves_a_breeding_level_and_never_rests_near_one(self) -> None:
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        brain = self.brain()
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=20, mhp=40)
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(20, 20): Creature("w", 1)}                  # a White Worm mass, far off
        brain.decide(obs, view)
        self.assertFalse(brain.level.scum)
        brain.level.breeders_seen.update({(21, 20): obs.step, (22, 20): obs.step})
        brain.decide(obs, view)
        self.assertTrue(brain.level.scum)                              # three seen below clvl 15
        near = town_view((5, 5), (40, 40), dlvl=2)
        brain.level.breeders_seen = {(12, 5): obs.step}                # 7 squares off, out of sight
        self.assertIsNone(brain.rest(obs, near))

    def test_a_mage_walks_to_melee_nothing(self) -> None:
        from test_m1 import command_obs, town_view
        obs = command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=30, mhp=30)
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.types[5 * 80 + 2] = 0xA
        view.creatures = {(8, 5): self.kobold}
        self.assertIsNone(self.brain("human-mage").hunt(obs, view))
        self.assertIsNotNone(self.brain("human-warrior").hunt(obs, view))

    def test_paths_go_round_squares_a_creature_could_hurt_badly(self) -> None:
        from test_m1 import command_obs, town_view
        brain = self.brain()
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=10, mhp=30)
        view = town_view((5, 5), (9, 5), dlvl=2)
        view.creatures = {(7, 4): self.kobold}                         # 6 at most beside it: over 0.3 x 10
        brain.decide(obs, view)
        self.assertIn((6, 5), view.perilous)
        step = view.step_toward({(9, 5)}, avoid_monsters=True)
        self.assertGreater(chebyshev_from((5 + step[0], 5 + step[1]), (7, 4)), 1)

    def test_no_progress_for_long_forgets_what_was_remembered(self) -> None:
        from moria_playtest.brain import FORGET_STEPS
        from test_m1 import command_obs, town_view
        brain = self.brain()
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=40, mhp=40)
        brain.track(obs, town_view((5, 5), (40, 40), dlvl=2))
        brain.level.slow_seen[(20, 20)] = obs.step
        brain.level.loop_blocks[(6, 5)] = 3
        brain.level.bumped[(6, 5)] = obs.step + 100
        brain.level.since_progress = FORGET_STEPS - 1                  # this step makes 500
        brain.decide(obs, town_view((5, 5), (40, 40), dlvl=2))
        self.assertEqual((brain.level.slow_seen, brain.level.bumped), ({}, {}))
        self.assertEqual(brain.level.loop_blocks, {(6, 5): 3})          # a loop that returns is blocked longer
        # Once per 500 steps, not every step after: a block set now holds.
        brain.level.bumped[(7, 5)] = obs.step + 100
        brain.decide(obs, town_view((5, 5), (40, 40), dlvl=2))
        self.assertIn((7, 5), brain.level.bumped)

    def test_a_walk_up_keeps_its_staircase(self) -> None:
        from test_m1 import command_obs, town_view
        brain = self.brain()
        brain.food = 0.5                                               # short of food: heads up
        view = town_view((10, 5), (2, 5), dlvl=2, stairs_type=0xA)
        view.types[5 * 80 + 20] = 0xA                                   # a second up staircase, east
        obs = command_obs(pos=(10, 5), dlvl=2, clvl=5, hp=40, mhp=40)
        brain.level.up_target = (20, 5)                                # committed east earlier
        decision = brain.resupply(obs, view)
        self.assertEqual(decision.key, __import__("moria_playtest.view", fromlist=["DIRS"]).DIRS[(1, 0)])


def chebyshev_from(a: tuple[int, int], b: tuple[int, int]) -> int:
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


class WandTest(unittest.TestCase):
    """Wands and staffs (maintainer, 2026-11-04: "this is a big gap"): kept,
    bought, aimed, and the Staff of Teleportation as the far escape."""

    def brain(self, character: str):  # type: ignore[no-untyped-def]
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        brain = Brain(for_character(GOALS["deep"], character))
        brain.food = 10
        return brain

    def test_charges_are_counted_from_buying_picking_up_and_the_pack(self) -> None:
        from moria_playtest.game import Mode
        from test_m1 import command_obs, town_view
        brain = self.brain("human-mage")
        brain.credit("Wand of Frost (7 charges)", 1)
        self.assertEqual(brain.wands, {"Wand of Frost": 7})
        brain.track_light("You picked up a Wand of Lightning (5 charges).")
        self.assertEqual(brain.wands["Wand of Lightning"], 5)
        brain.track_light("You picked up a Wand of Cold Balls (magik).")   # sensed: charges not shown
        self.assertEqual(brain.wands["Wand of Cold Balls"], 1)
        brain.picking, brain.listed = "Wand of Frost", True
        pick = command_obs(dlvl=3, clvl=12, rows={0: "Aim which wand (a-b)?", 2: " a) Wand of Lightning (5 charges)",
                                                  3: " b) Wand of Frost (4 charges)"})
        pick.mode = Mode.ITEM
        self.assertEqual(brain.pick_item(pick).key, ord("B"))
        self.assertEqual(brain.wands["Wand of Frost"], 3)                 # the pack's count, less this one
        brain.last_aimed = "Wand of Lightning"
        brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=12, rows={0: "No charges left."}),
                     town_view((5, 5), (30, 30), dlvl=3))
        self.assertEqual(brain.wands["Wand of Lightning"], 0)

    def test_a_wand_is_aimed_when_spells_or_melee_will_not_do(self) -> None:
        from moria_playtest.brain import KEY_AIM
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        mage = self.brain("human-mage")
        mage.wands = {"Wand of Frost": 5, "Wand of Stinking Cloud": 5}
        view = town_view((5, 5), (30, 30), dlvl=10)
        view.creatures = {(9, 5): Creature("k", 1)}                     # in line, four east
        out = command_obs(pos=(5, 5), dlvl=10, clvl=15, hp=60, mhp=60, rows={23: "HP:60/60  MP:0/30 AU:100"})
        decision = mage.aim(out, view)
        self.assertEqual((decision.key, decision.reason), (KEY_AIM, "aim the Wand of Stinking Cloud at 'k'"))
        warrior = self.brain("human-warrior")
        warrior.wands = {"Wand of Frost": 5}
        well = command_obs(pos=(5, 5), dlvl=10, clvl=15, hp=150, mhp=150)
        self.assertIsNone(warrior.aim(well, view))                      # a Kobold at full HP: melee
        hurt = command_obs(pos=(5, 5), dlvl=10, clvl=15, hp=50, mhp=150)
        self.assertEqual(warrior.aim(hurt, view).reason, "aim the Wand of Frost at 'k'")
        from moria_playtest import knowledge
        worm = Creature(*sorted(knowledge.breeder_kinds())[0])
        view.creatures = {(9, 5): worm}
        self.assertIsNone(warrior.aim(hurt, view))                       # a bolt is not worth a breeder
        warrior.wands["Wand of Stinking Cloud"] = 5
        self.assertIsNone(warrior.aim(hurt, view))                       # nor a ball on one alone
        view.creatures = {(9, 5): worm, (10, 5): worm, (9, 6): worm}
        self.assertEqual(warrior.aim(hurt, view).reason, f"aim the Wand of Stinking Cloud at 3 '{worm.glyph}'")

    def test_the_staff_of_teleportation_is_the_far_escape(self) -> None:
        from moria_playtest.brain import KEY_USE, TELEPORT_STAFF
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        mage = self.brain("human-mage")
        mage.wands = {TELEPORT_STAFF: 4}
        kobold = Creature("k", 1)
        view = town_view((5, 5), (30, 30), dlvl=10)
        view.creatures, mage.adjacent = {(6, 5): kobold}, [kobold]
        dying = command_obs(pos=(5, 5), dlvl=10, clvl=15, hp=10, mhp=60)
        self.assertTrue(mage.can_phase(dying))
        decision = mage.phase_door(dying, view)
        self.assertEqual((decision.key, decision.layer), (KEY_USE, "phase"))

    def test_the_magic_shop_sells_the_wands_and_staff_wanted(self) -> None:
        from moria_playtest.brain import TELEPORT_STAFF, WAND_BUYS
        brain = self.brain("human-warrior")
        self.assertEqual(brain.wands_wanted(), [*WAND_BUYS, TELEPORT_STAFF])
        brain.wands = {"Wand of Lightning": 6}
        self.assertEqual(brain.wands_wanted(), [TELEPORT_STAFF])
        brain.wands[TELEPORT_STAFF] = 3
        self.assertEqual(brain.wands_wanted(), [])


class UnknownItemTest(unittest.TestCase):
    """Identification (maintainer, 2026-11-04): found potions and scrolls are
    kept and tried when safe; unknown wands and staffs are identified."""

    def brain(self, character: str):  # type: ignore[no-untyped-def]
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        brain = Brain(for_character(GOALS["deep"], character))
        brain.food = 10
        return brain

    def test_flavours_are_told_from_known_names(self) -> None:
        from moria_playtest.brain import unknown_kind
        self.assertEqual([unknown_kind(n) for n in ("Blue Potion", "an Azure Potion", "White Scroll", "Scroll of Lumen",
                                                    "Iron Wand", "Birch Staff", "Bronze Ring")],
                         ["potion", "potion", "scroll", "scroll", "wand", "staff", "ring"])
        self.assertEqual({unknown_kind(n) for n in ("Potion of Cure Light Wounds", "Scroll of Light", "Wand of Frost",
                                                    "Ration of Food", "Spellbook Magick I")}, {None})

    def test_found_items_are_counted_and_unknown_ones_kept(self) -> None:
        brain = self.brain("human-warrior")
        brain.track_light("You picked up a Potion of Cure Light Wounds.")
        brain.track_light("You picked up a Blue Potion.")
        self.assertEqual((brain.clw, brain.unknown["Blue Potion"]), (1, 1))

    def test_an_unknown_potion_is_tried_only_when_safe(self) -> None:
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        brain = self.brain("human-warrior")
        brain.unknown["Blue Potion"] = 1
        view = town_view((5, 5), (30, 30), dlvl=3)
        hurt = command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=20, mhp=40)
        self.assertIsNone(brain.try_unknown(hurt, view))
        view.creatures = {(9, 5): Creature("k", 1)}
        well = command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=40, mhp=40)
        self.assertIsNone(brain.try_unknown(well, view))                 # something in view
        view.creatures = {}
        decision = brain.try_unknown(well, view)
        self.assertEqual((decision.key, decision.layer, brain.picking), (ord("Q"), "try", "Blue Potion"))

    def test_the_pack_lists_a_flavour_with_its_article(self) -> None:
        # 2026-11-04: "try the Blue Potion" found "a Blue Potion" in the list
        # and cancelled ("item to pick not listed").
        from moria_playtest.game import Mode
        from test_m1 import command_obs
        brain = self.brain("human-warrior")
        brain.picking, brain.listed = "Blue Potion", True
        pick = command_obs(dlvl=3, rows={0: "Quaff which potion (a-b)?", 2: " a) Potion of Cure Light Wounds",
                                         3: " b) a Blue Potion"})
        pick.mode = Mode.ITEM
        self.assertEqual(brain.pick_item(pick).key, ord("B"))

    def test_an_unknown_wand_is_identified_then_counted(self) -> None:
        from test_m1 import command_obs, town_view
        brain = self.brain("human-warrior")
        brain.unknown["Iron Wand"] = 1
        brain.identify_scrolls = 1
        decision = brain.identify_items(command_obs(pos=(5, 5), dlvl=3, clvl=8), town_view((5, 5), (30, 30), dlvl=3))
        self.assertEqual((decision.key, brain.picking, brain.picking_next), (ord("R"), "Scroll of Identify", "Iron Wand"))
        brain.track_light("This is a Wand of Frost (6 charges).")
        self.assertEqual((brain.wands.get("Wand of Frost"), brain.unknown["Iron Wand"]), (6, 0))

    def test_an_identify_scroll_not_listed_is_not_asked_for_again(self) -> None:
        """2026-11-06: a count above the pack's read Identify, found none on
        the list, cancelled and asked again for 30,000 steps."""
        from moria_playtest.game import Mode
        from test_m1 import command_obs, town_view
        brain = self.brain("human-warrior")
        brain.unknown["Silver Wand"] = 1
        brain.identify_scrolls = 1
        brain.identify_items(command_obs(pos=(5, 5), dlvl=1, clvl=14), town_view((5, 5), (30, 30), dlvl=1))
        brain.listed = True
        listing = command_obs(dlvl=1, rows={0: "Read which scroll (a-a)?", 2: " a) Scroll of Light"})
        listing.mode = Mode.ITEM
        self.assertEqual(brain.pick_item(listing).reason, "item to pick not listed: cancel")
        self.assertEqual((brain.identify_scrolls, brain.picking, brain.picking_next), (0, None, None))
        self.assertIsNone(brain.identify_items(command_obs(pos=(5, 5), dlvl=1, clvl=14),
                                               town_view((5, 5), (30, 30), dlvl=1)))


class StrongPotionTest(unittest.TestCase):
    """M7 queue (tactic strong_potions): a level-14 Warrior with 136 HP drank five Cure
    Light Wounds beside three creatures and died holding 17,000 gold."""

    def brain(self, goal: str = "deep"):
        from moria_playtest.brain import Brain, CCW
        from moria_playtest.goals import GOALS
        brain = Brain(GOALS[goal])
        brain.food, brain.clw, brain.clvl = 3, 2, 14
        return brain, CCW

    def test_badly_hurt_it_drinks_the_strongest_carried(self) -> None:
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        brain, ccw = self.brain()
        brain.strong[ccw] = 2
        view = town_view((5, 5), (12, 5), dlvl=11, stairs_type=0xA)
        view.creatures = {(6, 5): Creature("k", 1)}                  # something that can hurt it
        obs = command_obs(pos=(5, 5), dlvl=11, clvl=14, hp=30, mhp=136)
        self.assertEqual(brain.quaff(obs, view).reason, "HP 30/136: drink Cure Critical Wounds")
        view.creatures = {}                                           # nothing: rest instead
        self.assertIsNone(brain.quaff(obs, view))

    def test_no_potion_that_the_creatures_beside_outrun(self) -> None:
        """M8, 2026-11-02: a level-25 Half-Troll drank seven beside a
        Swordsman and a Stone Giant that took more back each turn, and died
        with none left."""
        from moria_playtest import knowledge
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        mamba = Creature(*knowledge.kinds_by_name()["Black Mamba"])
        self.assertEqual(knowledge.moves()[(mamba.glyph, mamba.level)], 2.0)   # fast: two moves a turn
        reasons = {}
        for beside in ((), (mamba,), (mamba,) * 3):
            brain, ccw = self.brain()
            brain.strong[ccw] = 2
            brain.adjacent = list(beside)
            view = town_view((5, 5), (12, 5), dlvl=11, stairs_type=0xA)
            view.creatures = dict(zip(((6, 5), (6, 6), (6, 4)), beside))
            obs = command_obs(pos=(5, 5), dlvl=11, clvl=14, hp=30, mhp=136,
                              rows={23: "HP:30/136  MP:0/0   AC:20  AU:100"})
            decision = brain.quaff(obs, view)
            reasons[len(beside)] = decision.reason if decision else None
        self.assertIsNone(reasons[0])                                           # nothing can hurt it: rest
        self.assertEqual(reasons[1], "HP 30/136: drink Cure Critical Wounds")   # 32 at most: survives, 24 > 32/3
        self.assertIsNone(reasons[3])                                           # 96 at most: drinking cannot save it

    def test_it_wants_them_from_level_ten_on_the_deep_goal_only(self) -> None:
        self.assertTrue(self.brain()[0].strong_wanted())
        self.assertFalse(self.brain("clvl10")[0].strong_wanted())

    def test_neutralize_poison_is_bought_and_drunk_out_of_the_fight(self) -> None:
        """2026-11-05: Gnome Mages at 1 mana drained to death from a Black
        Mamba's stacked poison, Cure Poison known but no mana to cast it."""
        from moria_playtest.brain import NEUTRALIZE
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        brain, _ = self.brain()
        self.assertIn(NEUTRALIZE, brain.shopping_list(10_000))
        self.assertNotIn(NEUTRALIZE, self.brain("clvl10")[0].shopping_list(10_000))
        brain.credit(NEUTRALIZE + " Poison", 2)
        self.assertNotIn(NEUTRALIZE, brain.shopping_list(10_000))
        brain.poisoned = True
        view = town_view((5, 5), (12, 5), dlvl=13, stairs_type=0xA)
        obs = command_obs(pos=(5, 5), dlvl=13, clvl=19, hp=30, mhp=61, rows={23: "HP:30/61  MP:1/29  AC:20  AU:100"})
        self.assertEqual(brain.quaff(obs, view).reason, "HP 30/61 poisoned: drink Neutralize Poison")
        mamba = Creature("R", 12)
        brain.adjacent, view.creatures = [mamba], {(6, 5): mamba}
        decision = brain.quaff(obs, view)
        self.assertNotIn("Neutralize", decision.reason if decision else "")   # beside it: the next bite poisons again


class DangerousTest(unittest.TestCase):
    """M7 queue (tactic dangerous): giants at walking speed killed nine characters
    on DL15-20; below DL10 a creature that wins by the lore marks the level
    for leaving, fast or not."""

    def test_a_giant_marks_the_level_for_leaving(self) -> None:
        from moria_playtest import knowledge
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        giant = knowledge.kinds_by_name()["Fire Giant"]
        scum = {}
        for goal, dlvl in (("deep", 17), ("deep", 8), ("clvl10", 17)):
            brain = Brain(GOALS[goal])
            brain.food = 3
            view = town_view((5, 5), (40, 5), dlvl=dlvl, stairs_type=0xA)
            view.creatures = {(5, 15): Creature(*giant)}
            obs = command_obs(pos=(5, 5), dlvl=dlvl, clvl=16, hp=140, mhp=140)
            self.assertGreater(brain.fight_odds(Creature(*giant), obs), 1.0)
            brain.decide(obs, view)
            scum[(goal, dlvl)] = brain.level.scum
        self.assertEqual(scum, {("deep", 17): True, ("deep", 8): False, ("clvl10", 17): False})


class DrainTest(unittest.TestCase):
    """M7 queue (tactic drain): two level-15 characters rested from 14 HP to
    death a point a turn, poisoned with no message shown."""

    def test_rests_that_lose_hp_mean_poison_and_a_recall(self) -> None:
        from moria_playtest.brain import Brain, DRAIN_RESTS
        from moria_playtest.goals import GOALS
        from test_m1 import command_obs, town_view
        brain = Brain(GOALS["deep"])
        brain.food, brain.recall = 3, 2
        view = town_view((5, 5), (40, 5), dlvl=13, stairs_type=0xA)
        layers = []
        # Supplied: no town trip of its own (resupply is not under test).
        with mock.patch.object(Brain, "needs_resupply", return_value=False):
            for i, hp in enumerate(range(70, 70 - DRAIN_RESTS - 2, -1)):
                obs = command_obs(pos=(5, 5), dlvl=13, clvl=16, hp=hp, mhp=136)
                obs.step = i
                layers.append(brain.decide(obs, view).layer)
        self.assertEqual(layers[0], "rest")
        self.assertTrue(brain.poisoned)
        self.assertEqual(layers[-1], "recall")


class RestockTest(unittest.TestCase):
    """M7 queue (tactic restock): characters drank all five strong potions and
    never went back for more."""

    def test_out_of_strong_potions_with_gold_it_goes_back(self) -> None:
        from moria_playtest.brain import Brain, CSW
        from moria_playtest.goals import GOALS
        from test_m1 import command_obs
        obs = command_obs(pos=(5, 5), dlvl=13, clvl=16, hp=100, mhp=136,
                          rows={23: "HP:100/136 MP:0/0 AC:20 AU:5000"})
        other = ("light_low", "food_low", "wants_recall", "wants_gear", "wants_book_trip")
        with contextlib.ExitStack() as stack:
            for name in other:   # only the restock under test
                stack.enter_context(mock.patch.object(Brain, name, return_value=False))
            brain = Brain(GOALS["deep"])
            brain.clvl = 16
            self.assertTrue(brain.needs_resupply(obs))
            brain.strong[CSW] = 1
            self.assertTrue(brain.needs_resupply(obs))    # no Phase Door either
            brain.phase = 2
            self.assertFalse(brain.needs_resupply(obs))
            frozen = Brain(GOALS["clvl10"])
            frozen.clvl = 16
            self.assertFalse(frozen.needs_resupply(obs))


class SummonerTest(unittest.TestCase):
    """M7 queue (tactic summoner, ghost): deaths beside a Magic User summoning again and
    again; the level is left, by Word of Recall when no stairs are known."""

    def test_a_summoner_with_no_stairs_known_sends_it_home(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import View
        from test_m1 import COLS, ROWS, command_obs
        layers = {}
        with mock.patch.object(Brain, "needs_resupply", return_value=False):
            for heard in ("the Magic User summons help!", ""):
                brain = Brain(GOALS["deep"])
                brain.food, brain.recall = 3, 2
                view = View(COLS, ROWS, [0] * (COLS * ROWS), (5, 5), 20, {})
                obs = command_obs(pos=(5, 5), dlvl=20, clvl=22, hp=180, mhp=184, rows={0: heard})
                layers[heard] = (brain.decide(obs, view).layer, brain.level.summoned)
        self.assertEqual(layers["the Magic User summons help!"], ("recall", obs.step))
        self.assertIsNone(layers[""][1])   # nothing heard: no summoner marked

    def test_a_ghost_strikes_from_the_walls(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import View
        from test_m1 import COLS, ROWS, command_obs
        brain = Brain(GOALS["deep"])
        brain.food, brain.recall = 3, 2
        view = View(COLS, ROWS, [0] * (COLS * ROWS), (5, 5), 24, {})
        obs = command_obs(pos=(5, 5), dlvl=24, clvl=22, hp=180, mhp=184, rows={0: "the Banshee touches you."})
        brain.decide(obs, view)
        self.assertEqual(brain.level.summoned, obs.step)
        self.assertTrue(brain.level.scum)


class SwatYieldsTest(unittest.TestCase):
    """M7 queue (tactic swat_yield): a Half-Elf Mage swatted a Bloodshot Eye from
    56 HP to death holding fifteen potions."""

    def test_badly_hurt_beside_an_eye_it_drinks(self) -> None:
        from moria_playtest import knowledge
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        eye = next(kind for name, kind in knowledge.kinds_by_name().items() if name == "Bloodshot Eye")
        layers = {}
        for goal in ("deep", "clvl10"):
            brain = Brain(GOALS[goal])
            brain.food, brain.clw = 3, 5
            view = town_view((5, 5), (40, 5), dlvl=13, stairs_type=0xA)
            view.creatures = {(6, 5): Creature(*eye)}
            layers[goal] = brain.decide(command_obs(pos=(5, 5), dlvl=13, clvl=15, hp=12, mhp=65), view).layer
        self.assertEqual(layers["deep"], "quaff")
        self.assertEqual(layers["clvl10"], "fight")   # the frozen goals keep their order


class CancelTest(unittest.TestCase):
    """Runs a subqueue cancel stops are recorded as cancelled and left out of
    its report (m7-regress-1, 2026-10-31: 23 killed runs scored as errors)."""

    def test_a_cancelled_run_is_no_result(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            item = {"goal": "clvl10", "character": "elf-rogue", "platform": "c64", "seed": 1, "step_budget": 10}
            sub = {"name": "s", "build": "b", "items": [item], "next": 1, "results": [], "suites": {}}
            queue.write_json(home / "subqueues" / "s.json", sub)
            job = {"id": "r1", "queue": "s", "platform": "c64", "character": "elf-rogue", "goal": "clvl10",
                   "seed": 1, "pid": 999_999_999, "slot": 0, "paused": False, "started": 1, "build": "b",
                   "item": 0, "cancelled": True}
            queue.write_json(home / "running.json", {"r1": job})
            service = queue.Service(home, home / "queue.json")
            subs = {"s": queue.read_json(home / "subqueues" / "s.json")}
            with mock.patch.object(queue.time, "sleep"):
                service.reap(queue.Queue("deep", home), subs)
            self.assertEqual(queue.read_json(home / "runs" / "r1" / "result.json")["outcome"], "cancelled")
            self.assertEqual(subs["s"]["results"], [])

    def test_a_partial_cancel_stops_and_skips_only_its_characters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            items = [{"goal": "deep", "character": c, "platform": "c128", "seed": s, "step_budget": 10}
                     for s in (1, 2) for c in ("human-mage", "human-warrior")]
            queue.write_json(home / "subqueues" / "s.json",
                             {"name": "s", "build": "b", "items": items, "next": 2, "results": [], "suites": {}})
            queue.write_json(home / "subqueues" / "s.cancel", ["human-warrior"])
            job = {"id": "r1", "queue": "s", "platform": "c128", "character": "human-warrior", "goal": "deep",
                   "seed": 1, "pid": 999_999_999, "slot": 0, "paused": False, "started": 1, "build": "b", "item": 1}
            queue.write_json(home / "running.json", {"r1": job})
            service = queue.Service(home, home / "queue.json")
            sub = service.load_subs()["s"]
            self.assertTrue(service.running["r1"]["cancelled"])
            self.assertFalse(sub.get("cancelled"))
            self.assertFalse((home / "subqueues" / "s.cancel").exists())
            self.assertEqual(service.sub_pending(sub), 1)            # only seed 2's mage is left
            self.assertEqual(service.next_sub_item(sub), 2)
            self.assertEqual(service.sub_pending(sub), 0)


class RestartBuildTest(unittest.TestCase):
    """A restarted service keeps playing the build it played."""

    def test_the_previous_build_is_kept(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            queue.write_json(home / "builds" / "b7" / "build.json", {"id": "b7", "commit": "c", "platforms": ["c64"]})
            queue.write_json(home / "service.json", {"build": "b7"})
            self.assertEqual(queue.Service(home, home / "q.json").build_id, "b7")
            queue.write_json(home / "service.json", {"build": "gone"})
            self.assertIsNone(queue.Service(home, home / "q.json").build_id)

    def test_the_build_queue_build_is_kept(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            queue.write_json(home / "builds" / "h1" / "build.json", {"id": "h1", "commit": "c", "platforms": ["c64"]})
            queue.write_json(home / "service.json", {"build_queue_build": "h1"})
            self.assertEqual(queue.Service(home, home / "q.json").ci_build, "h1")

    def test_a_snapshot_finds_the_trees_kick_assembler(self) -> None:
        """Every port's Makefile finds it at its default path (2026-11-05:
        KICKASS set to the jar sent the Atari build to download it)."""
        with tempfile.TemporaryDirectory() as tmp:
            queue.link_kickass(Path(tmp))
            jar = Path(tmp) / "tools" / "kickass" / "KickAss.jar"
            self.assertEqual(jar.exists(), (queue.ROOT / "tools" / "kickass" / "KickAss.jar").exists())


class SummonPhaseTest(unittest.TestCase):
    """M7 queue (tactic summon_phase): beside a Quylthulg's Banshee, 146 HP to dead
    in three turns; after a summoning anything in contact is phased from."""

    def test_after_a_summoning_contact_means_phase_door(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from moria_playtest.view import Creature
        from test_m1 import command_obs
        obs = command_obs(pos=(5, 5), dlvl=26, clvl=23, hp=140, mhp=146)
        for goal, expected in (("deep", True), ("clvl10", False)):
            brain = Brain(GOALS[goal])
            brain.phase = 2
            brain.adjacent = [Creature("G", 24)]
            brain.level.summoned = obs.step
            self.assertEqual(brain.phase_due(obs), expected)


@contextlib.contextmanager
def scratch_home():
    """``queue.main`` against a temporary home: never the live queue's
    (a submit there is scheduled by the running service)."""
    real_submit = queue.submit
    with tempfile.TemporaryDirectory() as tmp, \
            mock.patch.object(queue, "HOME", Path(tmp)), \
            mock.patch.object(queue, "snapshot_build", return_value="b1"), \
            mock.patch.object(queue, "submit", lambda *a, **k: real_submit(*a, **{**k, "home": Path(tmp)})), \
            contextlib.redirect_stdout(None):
        yield Path(tmp)


class TacticsTest(unittest.TestCase):
    """§23.10: the deep goal's tactics are named, so an A/B subqueue can play
    without one; every other goal has none (the frozen suites)."""

    def test_the_deep_goal_has_every_tactic_and_the_others_none(self) -> None:
        from moria_playtest.goals import GOALS, TACTICS
        for name in ("deep", "balrog"):   # the Balrog goal plays as deep (§23.9)
            self.assertEqual(GOALS[name].tactics, frozenset(TACTICS), name)
        for name, goal in GOALS.items():
            if name not in ("deep", "balrog"):
                self.assertEqual(goal.tactics, frozenset(), name)

    def test_every_tactic_the_brain_checks_is_named(self) -> None:
        import re
        from moria_playtest import brain
        from moria_playtest.goals import TACTICS
        source = Path(brain.__file__).read_text()
        self.assertNotIn("deep_tactics", source)
        checked = set(re.findall(r'"(\w+)" (?:not )?in (?:self\.goal\.)?tactics', source))
        self.assertEqual(checked, set(TACTICS))

    def test_a_tactic_turned_off_plays_as_the_frozen_goals(self) -> None:
        """The behaviour tests above, on the deep goal without their tactic."""
        from moria_playtest import knowledge
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, apply_variant
        from moria_playtest.view import Creature
        from test_m1 import command_obs, town_view
        deep = GOALS["deep"]
        with mock.patch.dict(GOALS, {"deep_without": apply_variant(deep, "tactics=-group_casters")}):
            self.assertEqual(GroupCasterTest().decide("deep", 3), "leave-caster")
            self.assertNotEqual(GroupCasterTest().decide("deep_without", 3), "leave-caster")
        brain = Brain(apply_variant(deep, "tactics=-strong_potions"))
        brain.clvl = 14
        self.assertFalse(brain.strong_wanted())
        giant = knowledge.kinds_by_name()["Fire Giant"]
        obs = command_obs(pos=(5, 5), dlvl=17, clvl=16, hp=140, mhp=140)
        self.assertTrue(Brain(deep).dangerous(Creature(*giant), obs))
        self.assertFalse(Brain(apply_variant(deep, "tactics=-dangerous")).dangerous(Creature(*giant), obs))
        mamba = knowledge.kinds_by_name()["Black Mamba"]
        for spec, retreats in (("", False), ("tactics=-fight_fast", True)):
            brain = Brain(apply_variant(deep, spec))
            brain.food = 3
            view = town_view((5, 5), (12, 5), dlvl=13, stairs_type=0xA)
            view.creatures = {(6, 6): Creature(*mamba)}
            layer = brain.decide(command_obs(pos=(5, 5), dlvl=13, clvl=16, hp=40, mhp=103), view).layer
            self.assertEqual(layer == "retreat", retreats, spec)
        obs = command_obs(pos=(5, 5), dlvl=26, clvl=23, hp=140, mhp=146)
        # A ghost beside is dangerous on DL26 too: both off to see summon_phase alone.
        for spec, expected in (("", True), ("tactics=-dangerous", True), ("tactics=-summon_phase,-dangerous", False)):
            brain = Brain(apply_variant(deep, spec))
            brain.phase, brain.adjacent, brain.level.summoned = 2, [Creature("G", 24)], obs.step
            self.assertEqual(brain.phase_due(obs), expected, spec)

    def test_summoner_and_ghost_are_separate(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, apply_variant
        from moria_playtest.view import View
        from test_m1 import COLS, ROWS, command_obs
        marked = {}
        for spec in ("", "tactics=-summoner", "tactics=-ghost"):
            for heard in ("the Magic User summons help!", "the Banshee touches you."):
                brain = Brain(apply_variant(GOALS["deep"], spec))
                brain.food, brain.recall = 3, 2
                view = View(COLS, ROWS, [0] * (COLS * ROWS), (5, 5), 24, {})
                obs = command_obs(pos=(5, 5), dlvl=24, clvl=22, hp=180, mhp=184, rows={0: heard})
                with mock.patch.object(Brain, "needs_resupply", return_value=False):
                    brain.decide(obs, view)
                marked[(spec, heard.split()[1])] = brain.level.summoned is not None
        self.assertEqual(marked, {("", "Magic"): True, ("", "Banshee"): True,
                                  ("tactics=-summoner", "Magic"): False, ("tactics=-summoner", "Banshee"): True,
                                  ("tactics=-ghost", "Magic"): True, ("tactics=-ghost", "Banshee"): False})


class VariantTest(unittest.TestCase):
    """§23.10: a subqueue's variant changes goal fields for its runs."""

    def test_tactics_are_added_removed_or_set(self) -> None:
        from moria_playtest.goals import GOALS, TACTICS, apply_variant
        deep, clvl10 = GOALS["deep"], GOALS["clvl10"]
        self.assertEqual(apply_variant(deep, "tactics=-dangerous,-summoner").tactics,
                         frozenset(TACTICS) - {"dangerous", "summoner"})
        self.assertEqual(apply_variant(clvl10, "tactics=+drain").tactics, {"drain"})
        self.assertEqual(apply_variant(deep, "tactics=drain,ghost").tactics, {"drain", "ghost"})
        self.assertEqual(apply_variant(deep, "tactics=none").tactics, frozenset())
        self.assertEqual(apply_variant(clvl10, "tactics=all,-restock").tactics, frozenset(TACTICS) - {"restock"})
        self.assertEqual(apply_variant(deep, ""), deep)

    def test_scalar_fields(self) -> None:
        from moria_playtest.goals import GOALS, apply_variant
        goal = apply_variant(GOALS["deep"], "ready_margin=2; exercise=false step_budget=500_000 ready_taper=10/30/24")
        self.assertEqual((goal.ready_margin, goal.exercise, goal.step_budget, goal.ready_taper),
                         (2, False, 500_000, (10, 30, 24)))
        self.assertIsNone(apply_variant(GOALS["deep"], "ready_taper=none").ready_taper)
        self.assertEqual(apply_variant(GOALS["deep"], "missile_classes=-warrior").missile_classes, ("rogue", "ranger"))
        # Several terms on one field apply in order.
        self.assertEqual(apply_variant(GOALS["deep"], "tactics=-drain,tactics=+drain").tactics, GOALS["deep"].tactics)

    def test_bad_specs_are_refused(self) -> None:
        from moria_playtest.goals import GOALS, apply_variant
        for spec in ("tactics=-nonsense", "colour=red", "dangerous", "exercise=maybe", "ready_margin=two",
                     "ready_margin=1,2", "ready_taper=12/30", "missile_classes=+bard"):
            with self.assertRaises(ValueError, msg=spec):
                apply_variant(GOALS["deep"], spec)

    def test_a_submitted_variant_reaches_every_item(self) -> None:
        with scratch_home() as tmp:
            queue.main(["submit", "--name", "v", "--goal", "clvl10", "--characters", "elf-rogue",
                        "--seeds", "1-3", "--variant", "tactics=+dangerous,ready_margin=2"])
            sub = queue.read_json(tmp / "subqueues" / "v.json")
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(None):
                queue.main(["submit", "--name", "w", "--goal", "deep", "--variant", "tactics=-bogus"])
            self.assertFalse((tmp / "subqueues" / "w.json").exists())
        self.assertEqual(sub["variant"], "tactics=+dangerous,ready_margin=2")
        self.assertEqual({i["variant"] for i in sub["items"]}, {"tactics=+dangerous,ready_margin=2"})
        self.assertEqual(list(queue.subqueue_report(sub)), ["clvl10 elf-rogue c64 [tactics=+dangerous,ready_margin=2]"])

    def test_the_job_carries_its_items_arm_and_variant(self) -> None:
        service = ScheduleTest.service(self, 1)   # type: ignore[arg-type]
        q = queue.Queue("deep", service.home)
        q.platform("c64")
        service.config["min_per_platform"] = 0
        item = {"goal": "deep", "character": "elf-rogue", "platform": "c64", "seed": 7, "step_budget": 10,
                "arm": "B", "variant": "tactics=-drain"}
        sub = {"name": "ab", "build": "b1", "items": [item], "next": 0, "results": []}
        service.save_sub = lambda sub: None   # type: ignore[method-assign]
        service.schedule(q, {"ab": sub})
        job = next(j for j in service.running.values() if j["queue"] == "ab")
        self.assertEqual((job["arm"], job["variant"]), ("B", "tactics=-drain"))


class AbTest(unittest.TestCase):
    """§23.10: an A/B subqueue plays the same seeds under both arms."""

    def test_items_pair_the_seeds_and_interleave_the_arms(self) -> None:
        seeds = {("c64", "elf-rogue"): [11, 12], ("c64", "dwarf-priest"): [21, 22]}
        items = queue.ab_items("deep", ["elf-rogue", "dwarf-priest"], ["c64"], seeds,
                               {"A": "", "B": "tactics=-dangerous"}, step_budget=1000)
        self.assertEqual([(i["character"], i["seed"], i["arm"]) for i in items], [
            ("elf-rogue", 11, "A"), ("elf-rogue", 11, "B"), ("dwarf-priest", 21, "A"), ("dwarf-priest", 21, "B"),
            ("elf-rogue", 12, "A"), ("elf-rogue", 12, "B"), ("dwarf-priest", 22, "A"), ("dwarf-priest", 22, "B")])
        self.assertEqual({i["step_budget"] for i in items}, {1000})
        self.assertEqual({i["variant"] for i in items if i["arm"] == "B"}, {"tactics=-dangerous"})
        own = queue.ab_items("deep", ["elf-rogue"], ["c64"], {("c64", "elf-rogue"): [1]},
                             {"A": "", "B": "step_budget=5000"}, step_budget=1000)
        self.assertEqual([i["step_budget"] for i in own], [1000, 5000])

    def test_random_seeds_are_drawn_once_for_both_arms(self) -> None:
        with scratch_home() as tmp:
            queue.main(["ab", "--name", "ab1", "--characters", "elf-rogue,human-mage", "--random-seeds", "3",
                        "--variant-b", "tactics=-summoner,-ghost"])
            sub = queue.read_json(tmp / "subqueues" / "ab1.json")
        self.assertEqual(sub["ab"], {"A": "", "B": "tactics=-summoner,-ghost"})
        self.assertEqual(len(sub["items"]), 12)
        for name in ("elf-rogue", "human-mage"):
            arms = {arm: [i["seed"] for i in sub["items"] if i["character"] == name and i["arm"] == arm]
                    for arm in ("A", "B")}
            self.assertEqual(arms["A"], arms["B"])
            self.assertEqual(len(set(arms["A"])), 3)

    def test_the_report(self) -> None:
        seeds = {("c64", "elf-rogue"): [1, 2, 3], ("c64", "human-mage"): [4]}
        items = queue.ab_items("deep", ["elf-rogue", "human-mage"], ["c64"], seeds, {"A": "", "B": "tactics=none"})
        played = {   # (arm, seed): outcome, max_dlvl, clvl, cause
            ("A", 1): ("reached", 30, 25, None), ("B", 1): ("died", 20, 22, "Stone Giant"),
            ("A", 2): ("died", 12, 15, "Black Mamba"), ("B", 2): ("died", 14, 15, "Stone Giant"),
            ("A", 3): ("budget", 18, 20, None), ("B", 3): ("budget", 18, 20, None),
            ("A", 4): ("died", 5, 8, "Orc Shaman")}   # B 4 still playing: no pair
        results = [{**i, "outcome": o, "max_dlvl": d, "clvl": c, "cause": cause}
                   for i in items if (key := (i["arm"], i["seed"])) in played
                   for o, d, c, cause in [played[key]]]
        sub = {"name": "ab", "items": items, "results": results, "ab": {"A": "", "B": "tactics=none"}}
        report = queue.ab_report(sub)
        a, b = report["arms"]["A"], report["arms"]["B"]
        self.assertEqual((a["reached"], a["done"], a["total"], a["median_max_dlvl"], a["median_clvl"]),
                         (1, 4, 4, 15, 17.5))
        self.assertEqual((b["reached"], b["done"], b["total"], b["median_max_dlvl"], b["median_clvl"]),
                         (0, 3, 4, 18, 20))
        self.assertEqual(a["deaths"], {"Black Mamba": 1, "Orc Shaman": 1})
        self.assertEqual(b["deaths"], {"Stone Giant": 2})
        self.assertEqual(b["variant"], "tactics=none")
        self.assertEqual(report["characters"]["elf-rogue"]["A"],
                         {"reached": 1, "done": 3, "total": 3, "median_max_dlvl": 18, "median_clvl": 20})
        self.assertEqual(report["characters"]["human-mage"]["B"]["done"], 0)
        self.assertEqual(report["paired"], {"pairs": 3, "only_a_reached": ["elf-rogue 1"], "only_b_reached": [],
                                            "a_deeper": ["elf-rogue 1"], "b_deeper": ["elf-rogue 2"],
                                            "same_depth": 1})
        self.assertEqual(sorted(queue.subqueue_report(sub)), ["deep elf-rogue c64 [A]", "deep elf-rogue c64 [B]",
                                                              "deep human-mage c64 [A]", "deep human-mage c64 [B]"])
        text = queue.report_text(sub)
        self.assertIn("only A reached 1, only B reached 0; A deeper 1, B deeper 1, same 1", text)
        self.assertIn("arm B [tactics=none]: reached 0/3 of 4", text)

    def test_a_result_keeps_its_arm_and_cause(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "queue.json").write_text("{}")
            item = {"goal": "deep", "character": "elf-rogue", "platform": "c64", "seed": 1, "step_budget": 10,
                    "arm": "B", "variant": "tactics=-drain"}
            sub = {"name": "s", "build": "b", "items": [item], "next": 1, "results": [], "suites": {}}
            queue.write_json(home / "subqueues" / "s.json", sub)
            job = {"id": "r1", "queue": "s", "platform": "c64", "character": "elf-rogue", "goal": "deep",
                   "seed": 1, "pid": 999_999_999, "slot": 0, "paused": False, "started": 1, "build": "b",
                   "item": 0, "arm": "B", "variant": "tactics=-drain"}
            queue.write_json(home / "running.json", {"r1": job})
            queue.write_json(home / "runs" / "r1" / "result.json",
                             {**job, "outcome": "died", "clvl": 9, "max_dlvl": 7, "steps": 5,
                              "death": {"cause": "Cave Bear"}})
            service = queue.Service(home, home / "queue.json")
            subs = {"s": queue.read_json(home / "subqueues" / "s.json")}
            service.reap(queue.Queue("deep", home), subs)
            [result] = subs["s"]["results"]
            self.assertEqual((result["arm"], result["variant"], result["cause"]), ("B", "tactics=-drain", "Cave Bear"))


class BlindReadTest(unittest.TestCase):
    """M7 queue, 2026-11-01: blind characters re-read Word of Recall for 1.9M
    steps; the refusal takes no turn, so the blindness never ran down."""

    def test_a_refused_read_is_not_retried_while_blind(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS
        from test_m1 import command_obs, town_view
        for clw, layer in ((0, None), (2, "quaff")):
            brain = Brain(GOALS["clvl10"])   # every goal: this is a stall, not a tactic
            brain.food, brain.recall, brain.clw = 3, 2, clw
            view = town_view((5, 5), (40, 5), dlvl=17, stairs_type=0xA)
            with mock.patch.object(Brain, "needs_resupply", return_value=True):
                obs = command_obs(pos=(5, 5), dlvl=17, clvl=19, hp=150, mhp=150,
                                  rows={0: "You can't see to read!"})
                decision = brain.decide(obs, view)
            self.assertNotEqual(decision.layer, "recall")
            if layer:
                self.assertEqual(decision.reason, "blind: drink Cure Light Wounds")


class RunIdTest(unittest.TestCase):
    """ab1, 2026-11-01: both arms of an A/B pair started in the same second
    under one run id and overwrote each other."""

    def test_paired_jobs_get_distinct_ids(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            service = queue.Service(home, home / "q.json")
            a = service.new_job("ab", "c64", "human-mage", "deep", 7, 10, "b", arm="A")
            service.running[a["id"]] = a
            b = service.new_job("ab", "c64", "human-mage", "deep", 7, 10, "b", arm="B")
            service.running[b["id"]] = b
            again = service.new_job("ab", "c64", "human-mage", "deep", 7, 10, "b", arm="B")
            self.assertEqual(len({a["id"], b["id"], again["id"]}), 3)


class ClassBooksTest(unittest.TestCase):
    """M7 queue, 2026-11-01: Rogues and Rangers never bought past
    Beginners-Magick (5 of 11 and 7 of 24 spells seen)."""

    def test_a_ranger_wants_magick_i_at_level_seven(self) -> None:
        from moria_playtest.brain import Brain
        from moria_playtest.goals import GOALS, for_character
        from test_m1 import command_obs
        obs = command_obs(pos=(5, 5), dlvl=0, clvl=7, hp=50, mhp=50)
        self.assertEqual(Brain(for_character(GOALS["deep"], "human-ranger")).book_wanted(obs), "Magick I")
        self.assertIsNone(Brain(for_character(GOALS["clvl10"], "human-ranger")).book_wanted(obs))
        rogue = Brain(for_character(GOALS["deep"], "human-rogue"))
        self.assertIsNone(rogue.book_wanted(obs))   # Magick I from level 15
        self.assertEqual(rogue.book_wanted(command_obs(pos=(5, 5), dlvl=0, clvl=15, hp=50, mhp=50)), "Magick I")




class StrategyEvidenceTest(unittest.TestCase):
    def test_deaths_are_grouped_by_depth(self) -> None:
        from moria_playtest import strategy
        runs = [{"outcome": "died", "max_dlvl": 2, "clvl": 3, "death": {"cause": "Kobold"}, "steps": 900},
                {"outcome": "died", "max_dlvl": 18, "clvl": 19, "death": {"cause": "Stone Giant"}, "steps": 9e4},
                {"outcome": "reached", "max_dlvl": 30, "clvl": 25, "steps": 167476,
                 "features": {"kit": {"weapon": ["Mace", 2]}}}]
        s = strategy.summary(runs)
        self.assertEqual((s["runs"], s["reached"], s["early"], s["best"]), (3, 1, 1, (30, 25)))
        self.assertEqual(s["stages"], {"DL1-5": [("Kobold", 1)], "DL15-24": [("Stone Giant", 1)]})
        self.assertIn("in 167,476 steps, wielding Mace", strategy.render("deep", {"x-priest": s}, 3))


class EpochTest(unittest.TestCase):
    """Maintainer, 2026-11-01: reset the statistics for a new epoch; records
    are kept and tagged, the old state file stays."""

    def test_an_epoch_has_its_own_state_and_tags_its_runs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            old = queue.Queue("deep", home)
            old.state["slowest_success"] = 100
            old.save()
            new = queue.Queue("deep", home, "e2")
            self.assertIsNone(new.state["slowest_success"])
            self.assertEqual(new.path.name, "state-deep-e2.json")
            self.assertTrue((home / "state-deep.json").exists())
            (home / "q.json").write_text(json.dumps({"epoch": "e2"}))
            service = queue.Service(home, home / "q.json")
            self.assertEqual(service.new_job("main", "c64", "human-mage", "deep", 1, 10, "b")["epoch"], "e2")

    def test_the_dashboard_counts_the_current_epoch_only(self) -> None:
        from moria_playtest import dashboard
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            lines = [{"id": f"r{i}", "queue": "main", "goal": "deep", "character": "human-mage", "platform": "c64",
                      "outcome": "died", "clvl": 3, "max_dlvl": 2, "steps": 10, "epoch": e}
                     for i, e in enumerate(["", "", "e2"])]
            (home / "runs.jsonl").write_text("".join(json.dumps(l) + "\n" for l in lines))
            self.assertEqual(dashboard.queue_runs(home, "deep", queue.COUNTED, "e2")["ratings"]["human-mage"]["runs"], 1)
            self.assertEqual(dashboard.queue_runs(home, "deep", queue.COUNTED, "")["ratings"]["human-mage"]["runs"], 2)


class GraduateSaveTest(unittest.TestCase):
    """graduate.save follows the screens: a first save through Disk Setup,
    and a loaded game's, which overwrites slot 1 (a Balrog checkpoint,
    2026-11-05; screens from a C128 probe of a Balrog start)."""

    class Game:
        def __init__(self, screens: list[tuple[str, str]]) -> None:
            self.screens = screens   # (the key it expects, the screen after it)
            self.keys: list[str] = []

        def press(self, key: int):   # type: ignore[no-untyped-def]
            want, screen = self.screens.pop(0)
            self.keys.append(chr(key) if key < 0x80 else "S+")
            assert self.keys[-1] == want, (self.keys, want)
            return mock.Mock(rows=screen.split("\n"))

    def save(self, screens: list[tuple[str, str]]) -> list[str]:
        from moria_playtest import graduate
        game = self.Game(screens)
        text = mock.Mock(command=mock.Mock(return_value=""))
        graduate.save(game, text, Path("save.d64"))
        text.command.assert_called_once_with('attach "save.d64" 9')
        self.assertEqual(game.screens, [])
        return game.keys

    def test_a_first_save(self) -> None:
        slots = "Save Slots:\n1)  Empty\nSelect Slot 1-4"
        self.assertEqual(self.save([("S+", "Disk Setup\n3) Done"), ("3", "Insert a Save Disk"),
                                    (" ", "Initialize this disk? Y/N"), ("Y", slots), ("1", "N)ew  L)oad")]),
                         ["S+", "3", " ", "Y", "1"])

    def test_a_loaded_games_save_overwrites_slot_1(self) -> None:
        slots = "Save Slots:\n1) *bot\n2)  Empty\nSelect Slot 1-4"
        self.assertEqual(self.save([("S+", slots), ("1", "Overwrite? Y/N"),
                                    ("Y", "Overwrite? Y/N\nSaving game... -more-"), (" ", "N)ew  L)oad")]),
                         ["S+", "1", "Y", " "])

    def test_an_unknown_screen_fails(self) -> None:
        from moria_playtest import graduate
        with self.assertRaises(graduate.GraduateError):
            self.save([("S+", "Disk error")])
