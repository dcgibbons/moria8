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
    qualify_bar: int = 16  # of the 20 qualification seeds, how many must reach it (§7.2)
    ready_margin: int = 2  # character levels over the depth before going deeper (brain.ready_level)


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
    # M3 (§14.4).
    "reach_dl5": Goal(
        "reach_dl5", "Descend through DL1-4, levelling up and resupplying, and arrive on DL5.",
        lambda o: o.dlvl >= 5, step_budget=20_000, target_dlvl=5),
    "clvl5": Goal(
        "clvl5", "Reach character level 5. target_dlvl 4 caps depth; readiness (brain.ready_level) keeps it on DL1-2 until level 5.",
        lambda o: o.clvl >= 5, step_budget=30_000, target_dlvl=4, want_xp=True),
    # M4 (§15): frozen 2026-10-24 at these budgets (playtest/suites/).
    "clvl10": Goal(
        "clvl10", "Reach character level 10. target_dlvl 8 caps depth; readiness keeps it three levels over "
        "each depth (M4 round 84 A/B: 31/40 against 28/40 at two).",
        lambda o: o.clvl >= 10, step_budget=100_000, target_dlvl=8, want_xp=True, ready_margin=3),
    # reach_dl8 replaced reach_dl10 (maintainer direction 2026-10-24).
    "reach_dl8": Goal(
        "reach_dl8", "Descend, levelling up and resupplying, and arrive on DL8. Readiness keeps it two "
        "levels over each depth: diving at level = depth met Green Nagas at level 5 with the starting "
        "Dagger (maintainer direction 2026-10-23: build up first).",
        lambda o: o.dlvl >= 8, step_budget=100_000, target_dlvl=8),
}

# Fixed qualification seeds (§7.2): 20 seeds, first character only.
QUALIFICATION_SEEDS = list(range(1001, 1021))


def required(goal: Goal, seeds: int) -> int:
    """Seeds that must reach ``goal`` out of ``seeds`` run: its bar, scaled
    to the seed count and rounded up."""
    return -(-goal.qualify_bar * seeds // len(QUALIFICATION_SEEDS))
