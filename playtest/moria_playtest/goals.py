"""Goals defined by the test system (§7).

A goal is a predicate over an observation at a ``COMMAND`` stop, plus the
character it applies to and a step budget. The budget is counted in agent
steps, so qualification is deterministic and can fail.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .game import Observation

# Chargen keys for the scripted path (§6.4): race letter, class letter.
HALF_TROLL_WARRIOR = ("H", "A")


@dataclass(frozen=True)
class Goal:
    name: str
    description: str
    reached: Callable[[Observation], bool]
    character: tuple[str, str] = HALF_TROLL_WARRIOR
    step_budget: int = 2_000
    target_dlvl: int = 0   # the brain walks down until this depth
    want_xp: bool = False  # M2: seek monsters for XP


GOALS: dict[str, Goal] = {
    "enter_dungeon": Goal(
        "enter_dungeon", "Leave town by the down staircase and arrive on DL1.",
        lambda o: o.dlvl >= 1, step_budget=2_000, target_dlvl=1),
    "reach_dl2": Goal(
        "reach_dl2", "Explore DL1, find a down staircase, and arrive on DL2.",
        lambda o: o.dlvl >= 2, step_budget=20_000, target_dlvl=2),
    "reach_clvl2": Goal(
        "reach_clvl2", "Earn enough experience in the dungeon to reach character level 2.",
        lambda o: o.clvl >= 2, step_budget=20_000, target_dlvl=1, want_xp=True),
}

# Fixed qualification seeds (§7.2): 20 seeds, first character only.
QUALIFICATION_SEEDS = list(range(1001, 1021))
