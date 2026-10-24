"""Keystroke fuzz for M0 (§8, §9 items 8-9).

Random keys at every stop exercise the prompt surface. A guided share of
command-mode steps walks toward the nearest down staircase with the privileged
BFS (``nav``), so generation, tier loads, and deeper prompts are reached.
Excluded keys: SHIFT+Q (quit), SHIFT+S (save and quit), CTRL+W (wizard mode).
"""

from __future__ import annotations

import random
import time
from collections import Counter
from dataclasses import dataclass, field

from . import nav
from .game import KEY_RETURN, KEY_RUNSTOP, KEY_SPACE, GameFault, Mode, Observation
from .worker import Worker

EXCLUDED = {0xD1, 0xD3, 0x17}
# PETSCII command keys from core/input_tables.s, plus selection and cancel keys.
COMMAND_KEYS = [k for k in (
    0x4B, 0x4A, 0x48, 0x4C, 0x59, 0x55, 0x42, 0x4E, 0x91, 0x11, 0x9D, 0x1D,
    0x38, 0x32, 0x34, 0x36, 0x37, 0x39, 0x31, 0x33, 0x35,
    0x3E, 0x3C, 0x2E, 0x53, 0x4F, 0x43, 0x47, 0x2C, 0x44, 0x49, 0x45, 0x57, 0x54, 0x51,
    0x52, 0x41, 0x5A, 0x4D, 0x50, 0x3F, 0x58, 0x46, 0x66,
    0xC3, 0xD1, 0xC5, 0xD3, 0xC6, 0xD4, 0xD2, 0xC4, 0x02, 0x04, 0x12, 0x23, 0x2B, 0x2F, 0x17,
    0xCB, 0xCA, 0xC8, 0xCC, 0xD9, 0xD5, 0xC2, 0xCE,
) if k not in EXCLUDED]
PROMPT_KEYS = ([ord(c) for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"]
               + [KEY_RETURN, KEY_SPACE, KEY_RUNSTOP, 0x1B, 0x59, 0x4E])


@dataclass
class FuzzReport:
    steps: int = 0
    wall_s: float = 0.0
    modes: Counter = field(default_factory=Counter)
    stages: Counter = field(default_factory=Counter)
    unknown_screens: Counter = field(default_factory=Counter)
    unknown_samples: dict[str, dict[str, object]] = field(default_factory=dict)
    findings: list[dict[str, object]] = field(default_factory=list)
    characters: int = 0
    deaths: int = 0
    max_dlvl: int = 0
    max_clvl: int = 0
    max_span_wall: float = 0.0
    max_span_jiffies: int = 0
    max_span_context: str = ""
    spans_over_1s: int = 0

    def as_dict(self) -> dict[str, object]:
        return {
            "steps": self.steps, "wall_s": round(self.wall_s, 1),
            "steps_per_s": round(self.steps / self.wall_s, 1) if self.wall_s else 0,
            "modes": dict(self.modes), "stages": dict(self.stages),
            "unknown_screens": dict(self.unknown_screens.most_common(40)),
            "unknown_screen_kinds": len(self.unknown_screens),
            "unknown_samples": self.unknown_samples,
            "findings": self.findings, "characters": self.characters, "deaths": self.deaths,
            "max_dlvl": self.max_dlvl, "max_clvl": self.max_clvl,
            "max_span_wall_s": round(self.max_span_wall, 3),
            "max_span_jiffies": self.max_span_jiffies,
            "max_span_context": self.max_span_context, "spans_over_1s": self.spans_over_1s,
        }


def unknown_key(obs: Observation) -> str:
    return " | ".join(row.strip() for row in obs.rows[:2] if row.strip())[:80] or "(blank rows 0-1)"


class Fuzzer:
    def __init__(self, worker: Worker, seed: int, guided: float = 0.35) -> None:
        self.worker = worker
        self.rand = random.Random(seed)
        self.seed = seed
        self.guided = guided
        self.report = FuzzReport()
        self.pending_dir: int | None = None
        self.same_unknown = 0
        self.death_steps = 0

    DEATH_STEPS = 10  # random keys spent in the death flow before ending the character

    def new_character(self) -> Observation:
        obs = self.worker.start_at_title()
        assert self.worker.game is not None
        self.worker.game.seed_title(self.seed * 1000 + self.report.characters)
        self.report.characters += 1
        return obs

    def choose(self, obs: Observation) -> int:
        game = self.worker.game
        assert game is not None
        if obs.mode == Mode.CHARGEN:
            return game.chargen_key(obs)
        if obs.mode == Mode.DEATH:
            return self.rand.choice(PROMPT_KEYS)  # explore the death flow briefly
        if obs.mode == Mode.DISMISS:
            return KEY_SPACE if self.rand.random() < 0.9 else KEY_RETURN
        if obs.mode in (Mode.UNKNOWN, Mode.DIRECTION, Mode.ITEM):
            if self.pending_dir is not None:
                key, self.pending_dir = self.pending_dir, None
                return key
            self.same_unknown += 1
            if self.same_unknown > 8:
                return (KEY_RUNSTOP, 0x1B, KEY_RETURN, KEY_SPACE)[self.same_unknown % 4]
            return self.rand.choice(PROMPT_KEYS) if self.rand.random() < 0.5 else KEY_RUNSTOP
        self.same_unknown = 0
        self.pending_dir = None
        if self.rand.random() < self.guided:
            key = self.guided_key(obs)
            if key is not None:
                return key
        return self.rand.choice(COMMAND_KEYS)

    def guided_key(self, obs: Observation) -> int | None:
        game = self.worker.game
        assert game is not None
        abi = game.abi
        cols, rows = abi.hal_layout_map_cols, abi.hal_layout_map_rows
        tiles = nav.read_map(game)
        stairs = set(nav.find_tiles(tiles, cols, abi.TILE_STAIRS_DN >> 4))
        if not stairs:
            return None
        step = nav.first_step(tiles, cols, rows, obs.pos, stairs, in_town=obs.dlvl == 0)
        if step is None:
            return None
        if step == (0, 0):
            return ord(">")
        target = (obs.pos[0] + step[0], obs.pos[1] + step[1])
        if tiles[target[1] * cols + target[0]] >> 4 == nav.TYPE_DOOR_CLOSED:
            self.pending_dir = nav.DIRECTION_KEYS[step]
            return ord("O")
        return nav.DIRECTION_KEYS[step]

    def run(self, steps: int) -> FuzzReport:
        report = self.report
        start = time.monotonic()
        obs = self.new_character()
        while report.steps < steps:
            game = self.worker.game
            assert game is not None
            key = self.choose(obs)
            before = obs
            wall0 = time.monotonic()
            try:
                obs = game.press(key)
            except GameFault as fault:
                report.findings.append({"kind": fault.kind, "detail": fault.detail,
                                        "pc": fault.pc, "step": report.steps, "key": key,
                                        "before": before.summary(), "screen": before.rows})
                obs = self.new_character()
                continue
            span = time.monotonic() - wall0
            jiffies = (obs.jiffies - before.jiffies) % (1 << 24)
            report.steps += 1
            report.modes[obs.mode.value] += 1
            if obs.stage:
                report.stages[obs.stage] += 1
            if obs.mode == Mode.UNKNOWN:
                kind = unknown_key(obs)
                report.unknown_screens[kind] += 1
                if kind not in report.unknown_samples:
                    report.unknown_samples[kind] = {
                        "step": report.steps, "key": key, "ret": f"${obs.ret:04X}",
                        "overlay": obs.overlay, "sp": obs.sp, "dlvl": obs.dlvl,
                        "screen": [row.rstrip() for row in obs.rows]}
            if obs.mode == Mode.DEATH:
                if before.mode != Mode.DEATH:
                    report.deaths += 1
                    self.death_steps = 0
                self.death_steps += 1
                if self.death_steps > self.DEATH_STEPS:
                    obs = self.new_character()  # DEATH ends the character (§6.4)
            if obs.mode == Mode.CHARGEN and obs.stage == "title" and before.stage != "title":
                obs = self.new_character()
            report.max_dlvl = max(report.max_dlvl, obs.dlvl if obs.mode == Mode.COMMAND else 0)
            report.max_clvl = max(report.max_clvl, obs.clvl if obs.mode == Mode.COMMAND else 0)
            if span > 1.0:
                report.spans_over_1s += 1
            if span > report.max_span_wall:
                report.max_span_wall = span
                report.max_span_context = (f"key=${key:02X} from {before.mode.value}:{before.stage} "
                                           f"DL{before.dlvl} -> {obs.mode.value}:{obs.stage} DL{obs.dlvl}")
            report.max_span_jiffies = max(report.max_span_jiffies, jiffies)
        report.wall_s = time.monotonic() - start
        return report
