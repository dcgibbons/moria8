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


if __name__ == "__main__":
    unittest.main()


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
                mock.patch.object(publish.dashboard, "milestone", return_value={"cells": {}}):
            counts = publish.snapshot(Path(tmp))
            page = (Path(tmp) / "index.html").read_text()
            self.assertIn(publish.STATIC_META, page)
            self.assertEqual(json.loads((Path(tmp) / "data" / "overview.json").read_text())["rounds"], ["r1"])
            self.assertEqual(counts, {"suites": 0, "workers": 0})
