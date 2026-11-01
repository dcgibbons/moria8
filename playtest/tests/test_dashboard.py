import json
import tempfile
import unittest
from pathlib import Path

from moria_playtest import dashboard


class SessionPartsTest(unittest.TestCase):
    """The dashboard takes a session's goal and character from its summary,
    whatever order its name gives them in (M5d and M5e sessions showed as
    Half-Troll Warriors, 2026-10-26)."""

    def parts(self, name: str, summary: dict) -> tuple[str, str, str] | None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / name
            path.mkdir()
            (path / "summary.json").write_text(json.dumps(summary))
            return dashboard.session_parts(path)

    def test_character_from_the_summary(self) -> None:
        self.assertEqual(self.parts("m5e-base-clvl10", {"goal": "clvl10", "character": "human-mage"}),
                         ("m5e-base", "clvl10", "human-mage"))
        self.assertEqual(self.parts("m5d-r1-human-rogue-clvl10", {"goal": "clvl10", "character": "human-rogue"}),
                         ("m5d-r1", "clvl10", "human-rogue"))
        self.assertEqual(self.parts("m5b-r55-reach_dl8-dwarf-priest",
                                    {"goal": "reach_dl8", "character": "dwarf-priest"}),
                         ("m5b-r55", "reach_dl8", "dwarf-priest"))

    def test_an_old_summary_falls_back_to_the_name(self) -> None:
        self.assertEqual(self.parts("m4-r3-clvl10", {"goal": "clvl10"}), ("m4-r3", "clvl10", "half-troll-warrior"))



class PublishTest(unittest.TestCase):
    """The published dashboard is public (maintainer, 2026-10-27): no host
    paths leave the machine."""

    def test_scrub_cuts_host_paths_to_their_last_part(self) -> None:
        from moria_playtest.publish import scrub
        data = {"session": "/home/someone/Projects/x/build/playtest/sessions/m5f-r1-clvl10-elf-mage",
                "nested": ["see /tmp/foo/bar.vsf here", {"p": "/backup/a/b.bin"}], "n": 3, "rel": "data/w.json"}
        self.assertEqual(scrub(data), {"session": "m5f-r1-clvl10-elf-mage",
                                       "nested": ["see bar.vsf here", {"p": "b.bin"}], "n": 3, "rel": "data/w.json"})

    def test_the_page_is_marked_static(self) -> None:
        from unittest import mock
        from moria_playtest import publish
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(publish.dashboard, "overview", return_value={"round": "r1", "rounds": ["r1", "r0"], "suites": []}), \
                mock.patch.object(publish.dashboard, "milestone", return_value={"cells": {}}), \
                mock.patch.object(publish.dashboard, "queue", return_value={"live": []}):
            counts = publish.snapshot(Path(tmp))
            page = (Path(tmp) / "index.html").read_text()
            self.assertIn(publish.STATIC_META, page)
            self.assertEqual(json.loads((Path(tmp) / "data" / "overview.json").read_text())["rounds"], ["r1"])
            self.assertEqual(counts, {"suites": 0, "workers": 0})


class RegressSuitesTest(unittest.TestCase):
    """A --regress session runs its character's frozen suites in turn and
    records no goal of its own (summary goal enter_dungeon): the dashboard
    shows one row per suite, at the bar it was frozen at."""

    def test_characters_go_to_the_suite_they_played(self) -> None:
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suites, path = root / "suites", root / "m5-regress-elf-mage"
            suites.mkdir()
            path.mkdir()
            (suites / "clvl10-elf-mage.json").write_text(json.dumps({"seeds": [1001, 1002], "required": 1}))
            (suites / "reach_dl8-elf-mage.json").write_text(json.dumps({"seeds": [1001, 1002], "required": 2}))
            events = [{"kind": "character_start", "seed": 1001, "goal": "clvl10"},
                      {"kind": "character_start", "seed": 1002, "goal": "clvl10"},
                      {"kind": "character_end", "seed": 1002, "outcome": "reached"},
                      {"kind": "character_end", "seed": 1001, "outcome": "reached"},
                      {"kind": "character_start", "seed": 1001, "goal": "reach_dl8"},
                      {"kind": "character_end", "seed": 1001, "outcome": "budget"}]
            (path / "events.jsonl").write_text("\n".join(json.dumps(e) for e in events))
            (path / "summary.json").write_text(json.dumps({
                "mode": "regress", "goal": "enter_dungeon", "character": "elf-mage",
                "characters": [{"seed": 1002, "outcome": "reached"}, {"seed": 1001, "outcome": "reached"},
                               {"seed": 1001, "outcome": "budget"}]}))
            with mock.patch.object(dashboard, "SUITES", suites):
                rows = {r["goal"]: r for r in dashboard.regress_suites(path, "elf-mage")}
        self.assertEqual(set(rows), {"clvl10", "reach_dl8"})
        self.assertEqual([c["seed"] for c in rows["clvl10"]["characters"]], [1002, 1001])
        self.assertEqual([c["outcome"] for c in rows["reach_dl8"]["characters"]], ["budget"])
        self.assertEqual((rows["clvl10"]["bar"], rows["reach_dl8"]["bar"]), (1, 2))


class PortsTest(unittest.TestCase):
    """M6's coverage map (§21.4): each primary character on each port."""

    def test_frozen_suites_and_latest_results_per_port(self) -> None:
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suites, sessions = root / "suites", root / "sessions"
            suites.mkdir()
            (suites / "clvl5-human-mage-plus4.json").write_text(json.dumps({"required": 10, "frozen": "2026-10-27"}))
            (suites / "clvl5.json").write_text(json.dumps({"required": 16}))
            path = sessions / "m6b-c128-reach_dl5-human-rogue"
            path.mkdir(parents=True)
            (path / "summary.json").write_text(json.dumps({
                "mode": "qualify", "goal": "reach_dl5", "character": "human-rogue", "port": "c128",
                "started": "2026-10-27T21:00:00",
                "characters": [{"seed": s, "outcome": "reached" if s < 1013 else "died"} for s in range(1001, 1021)]}))
            with mock.patch.object(dashboard, "SUITES", suites), mock.patch.object(dashboard, "SESSIONS", sessions):
                cover = dashboard.ports()
        self.assertEqual(cover["ports"][:3], ["c64", "plus4", "c128"])
        self.assertEqual((cover["frozen"]["plus4"], cover["frozen"]["c64"], cover["frozen"]["c128"]), (1, 1, 0))
        mage = cover["cells"]["plus4 human-mage clvl5"]
        self.assertEqual((mage["frozen"], mage["bar"], mage["frozen_on"]), (True, 10, "2026-10-27"))
        rogue = cover["cells"]["c128 human-rogue reach_dl5"]
        self.assertEqual((rogue["frozen"], rogue["latest"], rogue["bar"], rogue["ran"]), (False, 12, 16, "2026-10-27"))
        self.assertIsNone(cover["cells"]["c64 human-rogue reach_dl5"]["latest"])


class LiveRoundsTest(unittest.TestCase):
    """The default view shows every round running now: a BBC qualification
    and C64 and X16 regressions ran side by side, and the view flipped to
    whichever wrote last (M6, 2026-10-28)."""

    def test_every_running_round_and_not_a_finished_one(self) -> None:
        import os
        import time
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            sessions = Path(tmp)
            for name, port, age in (("m6k-bbcmaster-clvl5-human-mage", "bbcmaster", 10),
                                    ("m6i-c128-clvl5-human-mage", "c128", 20),
                                    ("m6a-c64-clvl5-human-mage", "c64", 3600)):
                path = sessions / name
                path.mkdir()
                (path / "summary.json").write_text(json.dumps({
                    "mode": "qualify", "goal": "clvl5", "character": "human-mage", "port": port,
                    "started": "2026-10-28T12:00:00", "characters": []}))
                stamp = time.time() - age
                os.utime(path / "summary.json", (stamp, stamp))
            with mock.patch.object(dashboard, "SESSIONS", sessions):
                view = dashboard.overview(None)
                alone = dashboard.overview("m6a-c64")
        self.assertEqual(sorted(s["port"] for s in view["suites"]), ["bbcmaster", "c128"])
        self.assertEqual(view["round"], "m6k-bbcmaster + m6i-c128")
        self.assertEqual(view["rounds"][0], view["round"])
        self.assertEqual([s["port"] for s in alone["suites"]], ["c64"])


class DiskRunsTest(unittest.TestCase):
    """The disk panel (§22) shows each port's run: one running now, else the
    newest with the most scenarios, so a SCENARIOS= rerun of one does not
    hide the last full run."""

    def run_dir(self, root: Path, name: str, port: str, names: list[str], age: float, finished: bool) -> None:
        import os
        import time
        path = root / name
        path.mkdir()
        (path / "summary.json").write_text(json.dumps({
            "port": port, "started": "2026-10-30T12:00:00",
            "finished": "2026-10-30T12:05:00" if finished else None,
            "scenarios": [{"name": n, "doc": "", "outcome": "pass", "seconds": 1.0, "detail": "", "known": ""}
                          for n in names]}))
        stamp = time.time() - age
        os.utime(path / "summary.json", (stamp, stamp))

    def test_a_full_run_over_a_newer_partial_and_a_live_one_first(self) -> None:
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.run_dir(root, "20261030-1200-c64", "c64", ["save_resume", "full_disk"], 600, True)
            self.run_dir(root, "20261030-1300-c64", "c64", ["full_disk"], 300, True)
            self.run_dir(root, "20261030-1200-plus4", "plus4", ["save_resume", "full_disk"], 600, True)
            self.run_dir(root, "20261030-1310-plus4", "plus4", ["save_resume"], 5, False)
            with mock.patch.object(dashboard, "DISK_RUNS", root):
                view = dashboard.disk()
        self.assertEqual(view["ports"], ["c64", "plus4"])
        self.assertEqual(view["latest"]["c64"]["run"], "20261030-1200-c64")
        self.assertEqual(view["latest"]["plus4"]["run"], "20261030-1310-plus4")
        self.assertTrue(view["latest"]["plus4"]["live"])
        self.assertEqual(view["scenarios"], ["save_resume", "full_disk"])


if __name__ == "__main__":
    unittest.main()


class DeathCauseTest(unittest.TestCase):
    """M7 queue: a Warrior slain beside a Green Naga that "spits acid" was
    recorded as killed by a pit trap."""

    def cause(self, *messages: str, hp: int = 0, before: int = 2) -> str:
        """The cause for a trace of these messages, the last at `hp` and the
        others at `before`."""
        import gzip
        with tempfile.TemporaryDirectory() as tmp:
            trace = Path(tmp) / "trace.jsonl.gz"
            with gzip.open(trace, "wt") as fh:
                for i, msg in enumerate(messages):
                    fh.write(json.dumps({"step": i, "mode": "COMMAND", "msg": msg, "status": "",
                                         "hp": hp if i == len(messages) - 1 else before}) + "\n")
            return dashboard.death(trace)["cause"]

    def test_spits_is_not_a_pit(self) -> None:
        self.assertEqual(self.cause("the Green Naga spits acid on you.", "You have been slain."), "Green Naga")
        self.assertEqual(self.cause("You fall into a pit!", "You have been slain."), "trap: pit")

    def test_lowercase_name_words_and_poison_tick(self) -> None:
        """M7 queue: a Human Ranger poisoned by a White Worm mass died to the
        poison tick and was recorded as "unknown"."""
        self.assertEqual(self.cause("the White Worm mass hits you. | You have been slain."), "White Worm mass")
        self.assertEqual(self.cause("the White Worm mass poisons you. | the White Worm mass hits you.",
                                    "You have been slain. | -more-"), "poison")
        self.assertEqual(self.cause("the White Worm mass poisons you.",
                                    "the Kobold hits you. | You have been slain."), "Kobold")
        # The killing blow prints no "hits you": HP below 0 is that blow.
        self.assertEqual(self.cause("the Black Mamba poisons you.", "the Black Mamba hits you.",
                                    "You hit the Black Mamba. | You have been slain.", hp=-7), "Black Mamba")
        # From 9 HP to 0 is a blow, not a poison tick.
        self.assertEqual(self.cause("the Black Mamba poisons you.", "You hit the Black Mamba.",
                                    "You have been slain.", hp=0, before=9), "Black Mamba")
        self.assertEqual(self.cause("the Flask of Oil hits the Ko", "the Kobold hits you.",
                                    "You have been slain.", hp=-2), "Kobold")
