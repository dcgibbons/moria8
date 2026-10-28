"""Goals defined by the test system (§7).

A goal is a predicate over an observation at a ``COMMAND`` stop, plus the
character it applies to and a step budget. The budget is counted in agent
steps, so qualification is deterministic and can fail.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Callable

from .game import Observation

# Chargen keys for the scripted path (§6.4): race letter, class letter.
HALF_TROLL_WARRIOR = ("H", "A")

# Race menu letters, in race table order (core/player_create.s). The class
# menu lists only the classes a race allows (race_class_flags), so a class's
# letter depends on the race; Warrior, allowed to every race, is always A.
RACE_KEYS = {"human": "A", "half-elf": "B", "elf": "C", "halfling": "D", "gnome": "E",
             "dwarf": "F", "half-orc": "G", "half-troll": "H"}
DEFAULT_CHARACTER = "half-troll-warrior"
CLASSES = ("warrior", "mage", "priest", "rogue", "ranger", "paladin")   # class table order
# Classes each race allows, bit n = CLASSES[n] (core/tables.s race_class_flags).
RACE_CLASS_FLAGS = {"human": 0b111111, "half-elf": 0b111111, "elf": 0b011111, "halfling": 0b001011,
                    "gnome": 0b001111, "dwarf": 0b000101, "half-orc": 0b001101, "half-troll": 0b000101}


def class_key(race: str, klass: str) -> str:
    """The class menu lists only the classes the race allows, in table
    order (core/player_create.s), so a class's letter depends on the race."""
    allowed = [c for i, c in enumerate(CLASSES) if RACE_CLASS_FLAGS[race] >> i & 1]
    return chr(ord("A") + allowed.index(klass))


CHARACTERS: dict[str, tuple[str, str]] = {
    f"{race}-{klass}": (key, class_key(race, klass))
    for race, key in RACE_KEYS.items() for i, klass in enumerate(CLASSES) if RACE_CLASS_FLAGS[race] >> i & 1}

# Bars below 16/20 for combinations weak by design (maintainer decision
# 2026-10-24, §16.1): each is frozen at what it reliably reaches.
CHARACTER_BARS: dict[tuple[str, str], int] = {
    # M5a freeze run (2026-10-25): 15/20; 14-17 across rounds 4-10.
    ("halfling-warrior", "clvl10"): 15,
    # M5f (maintainer decision 2026-10-27, "freeze at their level"): the 6-9
    # HP casters, at what rounds 18 and 19 both reached (identical: fixed
    # seeds, the same brain); most of their losses come at level 1-2.
    ("gnome-mage", "clvl10"): 8,
    ("gnome-mage", "reach_dl8"): 7,
    ("halfling-mage", "clvl10"): 8,
    ("halfling-mage", "reach_dl8"): 5,
    ("gnome-priest", "reach_dl8"): 5,
    # M5 regression (maintainer decision 2026-10-27, "capture their low bars
    # and freeze"): frozen at 10/20, then 9/20 on both runs of the fixed
    # brain once the VMS trap change re-rolled every map.
    ("gnome-priest", "clvl10"): 9,
}
# Pure spell casters, every race and goal: 10/20, half the seeds
# (maintainer decision 2026-10-27, M5f: "it is OK to accept them as weaker
# and have a lower bar"; 15/20 from 2026-10-26, M5b). Suites frozen before
# keep the bar they were frozen at. A CHARACTER_BARS entry still decides its
# combination.
CLASS_BARS: dict[str, int] = {"mage": 10, "priest": 10}


@dataclass(frozen=True)
class Goal:
    name: str
    description: str
    reached: Callable[[Observation], bool]
    character: tuple[str, str] = HALF_TROLL_WARRIOR
    race: str = "half-troll"   # names for the brain's own estimates (melee skill)
    klass: str = "warrior"
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
        "clvl10", "Reach character level 10. target_dlvl 8 caps depth; readiness keeps it four levels over "
        "each depth (M4 round 84 A/B: 31/40 against 28/40 at two; three until M5b round 38: it hunts and "
        "fights at each depth, and without the removed maximum-HP bar Priests died at twice reach_dl8's rate).",
        lambda o: o.clvl >= 10, step_budget=100_000, target_dlvl=8, want_xp=True, ready_margin=4),
    # reach_dl8 replaced reach_dl10 (maintainer direction 2026-10-24).
    "reach_dl8": Goal(
        "reach_dl8", "Descend, levelling up and resupplying, and arrive on DL8. Readiness keeps it three "
        "levels over each depth, as clvl10: diving at level = depth met Green Nagas at level 5 with the "
        "starting Dagger (maintainer direction 2026-10-23: build up first); at two, Human Paladins met "
        "DL2 Novice Priests at level 3 that the same seeds survived under clvl10 (M5b round 20).",
        lambda o: o.dlvl >= 8, step_budget=100_000, target_dlvl=8, ready_margin=3),
}

# Fixed qualification seeds (§7.2): 20 seeds, first character only.
QUALIFICATION_SEEDS = list(range(1001, 1021))


def required(goal: Goal, seeds: int) -> int:
    """Seeds that must reach ``goal`` out of ``seeds`` run: its bar, scaled
    to the seed count and rounded up."""
    return -(-goal.qualify_bar * seeds // len(QUALIFICATION_SEEDS))


def for_character(goal: Goal, character: str) -> Goal:
    """``goal`` played by ``character`` (a CHARACTERS name), at its bar."""
    race, klass = character.rsplit("-", 1)
    return replace(goal, character=CHARACTERS[character], race=race, klass=klass,
                   qualify_bar=CHARACTER_BARS.get((character, goal.name),
                                                  CLASS_BARS.get(klass, goal.qualify_bar)))

