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
