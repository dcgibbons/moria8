"""Goals defined by the test system (§7).

A goal is a predicate over an observation at a ``COMMAND`` stop, plus the
character it applies to and a step budget. The budget is counted in agent
steps, so qualification is deterministic and can fail.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, replace
from typing import Callable

from .abi import CONSTS
from .game import Observation
from .ports import Port

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


# The deep goal's tactics (M7 queue, 2026-10-31), one name per behaviour a
# subqueue can play with or without (§23.10). Every other goal has none, so
# the frozen suites play as they were frozen.
TACTICS: dict[str, str] = {
    "group_casters": "leave_caster adds up every caster in view, not only the strongest",
    "heal_first": "a heal comes before a poison cure while a creature beside is hitting",
    "fight_fast": "a fast creature close is fought, not run from, on the turns it does not strike too",
    "strong_potions": "count, buy (from level 10, five) and drink Cure Serious and Critical Wounds",
    "restock": "a town trip when out of strong potions or Phase Door with the gold for more "
               "(needs strong_potions)",
    "dangerous": "below DL10, a creature the lore says wins counts as dangerous: the level is left on sight, "
                 "it is fled and phased from at any HP",
    "drain": "rests that lose HP with nothing attacking mean poison: Word of Recall, or Cure Critical Wounds",
    "summoner": "\"summons help!\" marks the level summoned: leave it, by Word of Recall with no stairs known",
    "ghost": "a ghost's strike marks the level summoned, as a summoner does",
    "swat_yield": "badly hurt with potions, swatting a fragile creature beside yields to drinking",
    "summon_phase": "just after a summoning (summoner or ghost), anything in contact means Phase Door",
    "class_books": "Rogues and Rangers buy the Mage books their spells are in (magic.CASTER_BOOK_LEVELS)",
}


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
    ready_taper: tuple[int, int, int] | None = None   # brain.ready_level past a knee (M7)
    exercise: bool = False  # cast every spell known until its effect is seen (M7 criterion 2)
    # Classes that buy a launcher and shoot (brain.missile_pick): the best bow
    # skills (core/tables.s class_properties BOW: Ranger 72, Rogue 66).
    missile_classes: tuple[str, ...] = ("rogue", "ranger")
    # M7 tactics the brain plays (TACTICS names); a subqueue's variant can
    # turn each off or on (apply_variant, §23.10).
    tactics: frozenset[str] = frozenset()


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
    # M7 (§23.3): one game per seed. The queue's character also counts a
    # depth stood on earlier (queue.QueueCharacter); the budget is the
    # queue's (playtest/queue.json), 2,000,000 steps until successes set it.
    "deep": Goal(
        "deep", "Reach character level 25 and stand on DL30 in the same game. Readiness keeps it three "
        "levels over each depth to DL12, then tapers to level 25 on DL30.",
        lambda o: o.clvl >= 25 and o.dlvl >= 30, step_budget=2_000_000, target_dlvl=30, want_xp=True,
        ready_margin=3, ready_taper=(12, 30, 25), exercise=True,
        # §23.7, by bow skill: the Warrior's 55 rises 4 a level as the
        # Rogue's and Ranger's do; Paladin 40, Priest 35 and Mage 20 do not.
        missile_classes=("rogue", "ranger", "warrior"), tactics=frozenset(TACTICS)),
    # M8 (§23.9): the Balrog queue plays every combination that has met the
    # M7 bar (queue.Balrog). The game sets GAME_FLAG_WINNER on the kill
    # (core/combat.s); the Balrog appears from DL100. Played as deep, the
    # readiness taper carried on past DL30 (brain.ready_level caps it at 40).
    "balrog": Goal(
        "balrog", "Kill the Balrog and win the game. Plays as deep to DL30, then on down to DL100, where the "
        "Balrog appears.",
        lambda o: bool(o.game_flags & CONSTS["GAME_FLAG_WINNER"][1]), step_budget=3_000_000, target_dlvl=100,
        want_xp=True, ready_margin=3, ready_taper=(12, 30, 25), exercise=True,
        missile_classes=("rogue", "ranger", "warrior"), tactics=frozenset(TACTICS)),
}

# Fixed qualification seeds (§7.2): 20 seeds, first character only.
QUALIFICATION_SEEDS = list(range(1001, 1021))


def required(goal: Goal, seeds: int) -> int:
    """Seeds that must reach ``goal`` out of ``seeds`` run: its bar, scaled
    to the seed count and rounded up."""
    return -(-goal.qualify_bar * seeds // len(QUALIFICATION_SEEDS))


def for_port(goal: Goal, port: Port) -> Goal:
    """``goal`` on ``port``: its step budget grows with the level's area, so a
    bigger map is the same test, not a shorter one (maintainer, 2026-10-27:
    "they can be different"). A frozen suite records the budget it ran."""
    return replace(goal, step_budget=round(goal.step_budget * port.map_scale))


def for_character(goal: Goal, character: str) -> Goal:
    """``goal`` played by ``character`` (a CHARACTERS name), at its bar."""
    race, klass = character.rsplit("-", 1)
    return replace(goal, character=CHARACTERS[character], race=race, klass=klass,
                   qualify_bar=CHARACTER_BARS.get((character, goal.name),
                                                  CLASS_BARS.get(klass, goal.qualify_bar)))



# Goal fields a variant may set (§23.10), by kind.
VARIANT_INTS = ("ready_margin", "step_budget", "target_dlvl")
VARIANT_BOOLS = ("exercise", "want_xp")
VARIANT_SETS = {"tactics": tuple(TACTICS), "missile_classes": CLASSES}
VARIANT_FIELDS = (*VARIANT_INTS, *VARIANT_BOOLS, *VARIANT_SETS, "ready_taper")
BOOLS = {"true": True, "yes": True, "on": True, "1": True, "false": False, "no": False, "off": False, "0": False}


def parse_variant(spec: str | None) -> list[tuple[str, list[str]]]:
    """A variant spec as (field, values) terms. Terms are ``field=value``,
    separated by commas, semicolons or spaces; a bare word after a term is
    another value of it: ``tactics=-dangerous,-summoner,ready_margin=2``."""
    terms: list[tuple[str, list[str]]] = []
    for token in re.split(r"[,;\s]+", (spec or "").strip()):
        if not token:
            continue
        if "=" in token:
            field, value = token.split("=", 1)
            if field not in VARIANT_FIELDS:
                raise ValueError(f"variant: {field!r} is not one of {', '.join(VARIANT_FIELDS)}")
            terms.append((field, [value] if value else []))
        elif terms:
            terms[-1][1].append(token)
        else:
            raise ValueError(f"variant: {token!r} is not field=value")
    return terms


def variant_set(field: str, values: list[str], current: frozenset[str] | tuple[str, ...]) -> set[str]:
    """``+name`` adds, ``-name`` removes, ``all`` and ``none`` set every or
    no name; bare names are the whole set."""
    names = VARIANT_SETS[field]
    out, bare = set(current), False
    for value in values:
        if value in ("all", "none"):
            out = set(names) if value == "all" else set()
            continue
        sign, name = (value[0], value[1:]) if value[0] in "+-" else ("", value)
        if name not in names:
            raise ValueError(f"variant: {field} has no {name!r} (one of {', '.join(names)})")
        if sign == "-":
            out.discard(name)
        else:
            if not sign and not bare:
                out, bare = set(), True
            out.add(name)
    return out


def apply_variant(goal: Goal, spec: str | None) -> Goal:
    """``goal`` with a subqueue arm's changes (§23.10); raises ValueError on
    a bad spec. An empty spec is the goal as defined."""
    changes: dict[str, object] = {}
    for field, values in parse_variant(spec):
        current = changes.get(field, getattr(goal, field))
        if field in VARIANT_SETS:
            chosen = variant_set(field, values, current)   # type: ignore[arg-type]
            changes[field] = frozenset(chosen) if field == "tactics" else tuple(
                n for n in VARIANT_SETS[field] if n in chosen)
            continue
        if len(values) != 1:
            raise ValueError(f"variant: {field} takes one value, not {values}")
        value = values[0]
        if field in VARIANT_BOOLS:
            if value.lower() not in BOOLS:
                raise ValueError(f"variant: {field}={value} is not true or false")
            changes[field] = BOOLS[value.lower()]
        elif field in VARIANT_INTS:
            try:
                changes[field] = int(value.replace("_", ""))
            except ValueError:
                raise ValueError(f"variant: {field}={value} is not a number") from None
        else:   # ready_taper: none, or knee depth/depth/level, e.g. 12/30/25
            parts = value.split("/")
            if value == "none":
                changes[field] = None
            elif len(parts) == 3 and all(p.isdigit() for p in parts):
                changes[field] = tuple(int(p) for p in parts)
            else:
                raise ValueError(f"variant: ready_taper={value} is not none or DEPTH/DEPTH/LEVEL")
    return replace(goal, **changes)   # type: ignore[arg-type]
