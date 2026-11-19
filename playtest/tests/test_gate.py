"""make playtest-gate (moria_playtest/gate.py): what fails it."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from moria_playtest import gate
from moria_playtest.ports import APPLE2, C64


def run(root: Path, outcome: str, findings: list[dict] | None = None, lines: list[str] | None = None) -> Path:
    run_dir = root / outcome
    (run_dir / "findings").mkdir(parents=True)
    (run_dir / "result.json").write_text(json.dumps({"outcome": outcome, "steps": 812, "clvl": 3, "max_dlvl": 2,
                                                     "findings": lines or []}))
    for n, finding in enumerate(findings or [], 1):
        (run_dir / "findings" / f"F{n:04d}.json").write_text(json.dumps(finding))
    return run_dir


class GateVerdictTest(unittest.TestCase):
    def test_the_bot_s_own_findings_and_a_death_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ok, line = gate.verdict(run(Path(tmp), "died", [{"kind": "stall", "cls": "bot", "detail": "x"}]))
            self.assertTrue(ok, line)

    def test_a_game_finding_fails(self) -> None:
        # 2026-11-15: the BBC's first store buy panicked ("P43"), a hang.
        with tempfile.TemporaryDirectory() as tmp:
            ok, line = gate.verdict(run(Path(tmp), "finding", [
                {"kind": "stall", "cls": "bot", "detail": "x"},
                {"kind": "hang", "cls": "game", "detail": "no key wait for 300+ emulated seconds"}]))
            self.assertFalse(ok)
            self.assertIn("hang: no key wait", line)

    def test_a_run_error_fails(self) -> None:
        # 2026-11-15: no Apple IIe run saw a key wait (the playtest port's window).
        with tempfile.TemporaryDirectory() as tmp:
            ok, line = gate.verdict(run(Path(tmp), "error",
                                        lines=["error: EmulatorUnresponsive('no key wait within 60s wall')"]))
            self.assertFalse(ok)
            self.assertIn("EmulatorUnresponsive", line)

    def test_a_run_without_a_result_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "r").mkdir()
            self.assertFalse(gate.verdict(Path(tmp) / "r")[0])

    def test_a_failed_tour_step_fails(self) -> None:
        # 2026-11-15: the Atari's second-book '?' list hung only there.
        with tempfile.TemporaryDirectory() as tmp:
            tour = Path(tmp) / "atari8-tour"
            tour.mkdir()
            (tour / "tour.json").write_text(json.dumps({"passed": False, "steps": ["chargen reaches the town"],
                                                        "failure": "hang: no key wait for 300+ emulated seconds"}))
            ok, line = gate.verdict(tour)
            self.assertFalse(ok)
            self.assertIn("hang", line)
            (tour / "tour.json").write_text(json.dumps({"passed": True, "steps": ["a", "b"]}))
            self.assertTrue(gate.verdict(tour)[0])
            (tour / "tour.json").unlink()
            self.assertFalse(gate.verdict(tour)[0])   # no result: the tour died

    def test_a_skipped_target_fails_the_gate_unless_allowed(self) -> None:
        """2026-11-16: "55 passed, 0 failed" without the Plus/4's ROMs, over a
        build whose every Plus/4 disk game hung at its first store."""
        skipped = {"plus4": "skipped: PLAYTEST_PLUS4_KERNAL not set"}
        self.assertEqual(gate.exit_code([], {}, False), 0)
        self.assertEqual(gate.exit_code([], skipped, False), 1)
        self.assertEqual(gate.exit_code([], skipped, True), 0)
        self.assertEqual(gate.exit_code(["c64-tour"], skipped, True), 1)   # a failure fails all the same

    def test_a_port_without_its_roms_is_skipped(self) -> None:
        from unittest import mock
        with mock.patch.dict(gate.os.environ, {}, clear=True):
            self.assertEqual(gate.missing_roms(APPLE2), ["A2ROMS"])
            self.assertEqual(gate.missing_roms(C64), [])

    def test_its_jobs_play_the_tree_for_the_gate_s_steps(self) -> None:
        job = gate.job_for("bbcmaster", "elf-mage", 1002, "abc", False)
        self.assertEqual((job["platform"], job["character"], job["seed"], job["step_budget"], job["build"]),
                         ("bbcmaster", "elf-mage", 1002, gate.GATE_STEPS, "tree"))

    def test_tour_legal_streams_license_and_source_offer_then_returns_to_command(self) -> None:
        from types import SimpleNamespace
        from moria_playtest.game import Mode
        from moria_playtest.tour import Tour, TourFailed

        def fake_obs(row0: str, mode: Mode = Mode.UNKNOWN) -> SimpleNamespace:
            rows = [row0] + [""] * 24
            return SimpleNamespace(rows=rows, mode=mode)

        pressed: list[str] = []
        screens = [
            fake_obs("+--- Command Reference [L:License] ---+"),
            fake_obs(" License & Source"),
            fake_obs(" MORIA8 LICENSE NOTICE"),
            fake_obs(" License & Source"),
            fake_obs(" MORIA8 SOURCE OFFER"),
            fake_obs(" License & Source"),
            fake_obs("+--- Command Reference [L:License] ---+"),
            fake_obs("", mode=Mode.COMMAND),
        ]

        class FakeGame:
            abi = SimpleNamespace(all_symbols={})

            def press(self, key: int) -> SimpleNamespace:
                pressed.append(chr(key))
                return screens.pop(0)

        worker = SimpleNamespace(game=FakeGame())
        trip = Tour(worker, fake_obs("", mode=Mode.COMMAND))   # type: ignore[arg-type]
        trip.legal()
        self.assertEqual("".join(pressed), "?L1Q2QQQ")
        self.assertEqual(trip.steps[-1], "back at the command prompt after Help")

        bad_screens = [
            fake_obs("+--- Command Reference [L:License] ---+"),
            fake_obs(" License & Source"),
            fake_obs(" Document read failed. Press any key."),
        ]
        worker_bad = SimpleNamespace(game=SimpleNamespace(
            abi=SimpleNamespace(all_symbols={}),
            press=lambda key: bad_screens.pop(0),
        ))
        trip_bad = Tour(worker_bad, fake_obs("", mode=Mode.COMMAND))   # type: ignore[arg-type]
        with self.assertRaisesRegex(TourFailed, "the streamed LICENSE notice"):
            trip_bad.legal()


if __name__ == "__main__":
    unittest.main()
