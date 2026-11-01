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
        return service

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
        queue.write_json(service.home / "builds" / "b0" / "build.json", {"id": "b0"})
        return rec

    def test_an_m7_success_keeps_its_dl30_snapshot_as_the_start(self) -> None:
        service = self.service(4, 2)
        service.balrog_start(self.success_run(service))
        item = service.balrog.state["items"]["c64/elf-priest"]
        start = item["start"]
        self.assertEqual((start["run"], start["build"], start["step"], start["dlvl"]), ("m7", "b0", 125346, 30))
        kept = Path(start["snapshot"])
        self.assertEqual(kept.parent, service.home / "balrog" / "m7")
        self.assertTrue(kept.exists() and kept.with_suffix(".brain.pickle").exists())
        service.start_balrog()
        job = next(iter(service.running.values()))
        self.assertEqual((job["build"], job["resume"]["run"]), ("b0", "m7"))   # the start's build: its bot

    def test_a_success_without_a_saved_brain_plays_from_the_title(self) -> None:
        service = self.service(4, 2)
        service.balrog_start(self.success_run(service, with_brain=False))
        service.balrog.graduate("c64", "elf-priest", {})
        service.start_balrog()
        job = next(iter(service.running.values()))
        self.assertEqual(job["build"], "b1")
        self.assertNotIn("resume", job)

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

    def decide(self, goal: str, hp: int) -> str:
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
        view.creatures = {(6, 5): Creature("R", 12)}
        obs = command_obs(pos=(5, 5), dlvl=12, clvl=15, hp=hp, mhp=60,
                          rows={23: f"HP:{hp}/60  MP:20/20 AC:20  AU:100"})
        return brain.decide(obs, view).reason

    def test_hurt_beside_a_creature_the_heal_comes_first(self) -> None:
        self.assertIn("Cure Light Wounds", self.decide("deep", 25))
        self.assertIn("Neutralize Poison", self.decide("deep", 50))   # not hurt: cure the poison
        self.assertIn("Neutralize Poison", self.decide("clvl10", 25))   # the frozen goals keep their order


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
        from test_m1 import command_obs, town_view
        brain, ccw = self.brain()
        brain.strong[ccw] = 2
        view = town_view((5, 5), (12, 5), dlvl=11, stairs_type=0xA)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=11, clvl=14, hp=30, mhp=136), view)
        self.assertEqual(decision.reason, "HP 30/136: drink Cure Critical Wounds")

    def test_it_wants_them_from_level_ten_on_the_deep_goal_only(self) -> None:
        self.assertTrue(self.brain()[0].strong_wanted())
        self.assertFalse(self.brain("clvl10")[0].strong_wanted())


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
