"""Game knowledge a player brings to the game (§6.5): creature names and levels.

Read from the generated creature tier data the build ships, never from game
memory. The brain uses it the way a player uses experience: to tell whether
"You see a …" names a creature or an item, and who is attacking.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache

from .launch import ROOT
from .screen import screen_code_to_char

TIER_DIR = ROOT / "platforms/commodore/c64/creature_data"
TIER_LINE = re.compile(r"^//\s+\d+: \[\s*\d+\] DL\s*(\d+) (.+?)\s*$")
TIER_TABLE = re.compile(r"^tier\d+_cr_(\w+):\n((?:[ \t]*\.byte[^\n]*\n)+)", re.M)
CF_ATTACK_ONLY = 0x01   # cr_mflags: moves only to attack (tools/parse_creatures.py)
SPEED_FAST = 2          # cr_speed: 0 slow, 1 normal, 2 fast (tools/parse_creatures.py)
SPEED_SLOW = 0
SPEED_NORMAL = 1
SPEED_MASK = 0x03         # cr_speed bits 3-5 hold random-move flags (MON-013)
RANDOM_MASK = 0x38


@lru_cache(maxsize=1)
def creature_levels() -> dict[str, int]:
    """Creature name -> native dungeon level, for every shipped creature."""
    levels: dict[str, int] = {}
    for path in sorted(TIER_DIR.glob("tier[0-9].s")):
        for line in path.read_text().splitlines():
            match = TIER_LINE.match(line)
            if match:
                levels.setdefault(match.group(2), int(match.group(1)))
    return levels


@lru_cache(maxsize=1)
def _tiers() -> list[tuple[list[str], dict[str, list[int]]]]:
    """(creature names, byte tables by label) for each shipped tier file."""
    tiers = []
    for path in sorted(TIER_DIR.glob("tier[0-9].s")):
        text = path.read_text()
        names = [m.group(2) for m in map(TIER_LINE.match, text.splitlines()) if m]
        tables = {label: [int(v, 16) for v in re.findall(r"\$([0-9a-fA-F]{2})", body)]
                  for label, body in TIER_TABLE.findall(text)}
        tiers.append((names, tables))
    return tiers


@lru_cache(maxsize=1)
def _creatures() -> list[tuple[str, str, int, int]]:
    """(name, screen glyph, speed code, movement flags) for every shipped creature."""
    return [(name, screen_code_to_char(code), speed & SPEED_MASK, flags) for names, tables in _tiers()
            for name, code, speed, flags in zip(names, tables["display"], tables["speed"], tables["mflags"])]


@lru_cache(maxsize=1)
def strength() -> dict[tuple[str, int], tuple[float, int]]:
    """(screen glyph, creature level) -> (average HP, AC), the strongest
    shipped creature drawn that way at that level: what a player knows from
    the monster lore."""
    out: dict[tuple[str, int], tuple[float, int]] = {}
    for _, tables in _tiers():
        for code, level, num, sides, ac in zip(tables["display"], tables["level"], tables["hd_num"],
                                               tables["hd_sides"], tables["ac"]):
            key = (screen_code_to_char(code), level)
            hp = num * (sides + 1) / 2
            old = out.get(key, (0.0, 0))
            out[key] = (max(old[0], hp), max(old[1], ac))
    return out


@lru_cache(maxsize=1)
def ranged_kinds() -> frozenset[tuple[str, int]]:
    """(screen glyph, creature level) of every shipped creature that casts
    spells or breathes: running from one gives it free shots (§14.3 round
    28), from anything else it does not (M4 round 34). By kind, not glyph:
    one Orc Shaman made every Orc a caster, and the bot stood and fought
    whole Orc packs (M4 round 71)."""
    return frozenset((screen_code_to_char(code), level) for _, tables in _tiers()
                     for code, level, chance in zip(tables["display"], tables["level"], tables["spell_chance"])
                     if chance)


def casts(glyph: str, level: int) -> bool:
    return (glyph, level) in ranged_kinds()


@lru_cache(maxsize=1)
def stationary_glyphs() -> frozenset[str]:
    """Screen glyphs whose every shipped creature never moves (jellies,
    molds, …): a player learns to walk around them rather than fight."""
    by_glyph: dict[str, list[bool]] = {}
    for _, glyph, _, flags in _creatures():
        by_glyph.setdefault(glyph, []).append(bool(flags & CF_ATTACK_ONLY))
    return frozenset(glyph for glyph, still in by_glyph.items() if all(still))


@lru_cache(maxsize=1)
def glyphs_of() -> dict[str, frozenset[str]]:
    """Creature name -> the screen glyphs it is drawn with."""
    glyphs: dict[str, set[str]] = {}
    for name, glyph, _, _ in _creatures():
        glyphs.setdefault(name, set()).add(glyph)
    return {name: frozenset(g) for name, g in glyphs.items()}


@lru_cache(maxsize=1)
def creature_glyphs() -> frozenset[str]:
    """Every screen glyph some shipped creature uses: anything else on the
    map is an item or terrain (§14.3 round 20)."""
    return frozenset(glyph for _, glyph, _, _ in _creatures())


@lru_cache(maxsize=1)
def fast_creatures() -> frozenset[str]:
    """Creatures that move faster than the player: running from them on foot
    only gives them free hits (§14.3 round 14)."""
    return frozenset(name for name, _, speed, flags in _creatures()
                     if speed >= SPEED_FAST and not flags & CF_ATTACK_ONLY)


@lru_cache(maxsize=1)
def fragile_glyphs() -> frozenset[str]:
    """Screen glyphs whose every shipped creature has at most 4 hit points
    (mushroom patches, 1d1): one blow, where walking past one means being
    paralysed again at every step (M4 round 36)."""
    by_glyph: dict[str, list[bool]] = {}
    for _, tables in _tiers():
        for code, dice, sides in zip(tables["display"], tables["hd_num"], tables["hd_sides"]):
            by_glyph.setdefault(screen_code_to_char(code), []).append(dice * sides <= 4)
    return frozenset(glyph for glyph, weak in by_glyph.items() if all(weak))


@lru_cache(maxsize=1)
def slow_glyphs() -> frozenset[str]:
    """Screen glyphs whose every shipped creature moves slower than the player
    (creeping coins, worm masses): one can simply walk away (M4 round 35)."""
    by_glyph: dict[str, list[bool]] = {}
    for _, glyph, speed, flags in _creatures():
        by_glyph.setdefault(glyph, []).append(speed == SPEED_SLOW and not flags & CF_ATTACK_ONLY)
    return frozenset(glyph for glyph, slow in by_glyph.items() if all(slow))


@lru_cache(maxsize=1)
def outpaced_glyphs() -> frozenset[str]:
    """Screen glyphs whose every shipped creature a walking player outpaces:
    slower than the player, or as fast but moving at random some of the time
    (MON-013: nagas 20%)."""
    by_glyph: dict[str, list[bool]] = {}
    for _, tables in _tiers():
        for code, speed, flags in zip(tables["display"], tables["speed"], tables["mflags"]):
            base = speed & SPEED_MASK
            by_glyph.setdefault(screen_code_to_char(code), []).append(
                not flags & CF_ATTACK_ONLY and (
                    base == SPEED_SLOW or (base == SPEED_NORMAL and bool(speed & RANDOM_MASK))))
    return frozenset(glyph for glyph, outpaced in by_glyph.items() if all(outpaced))


ITEM_TABLES = ROOT / "core/item_tables.s"
ITEM_NAME = re.compile(r"^itn_(\d+):(.*)$", re.M)
ITEM_TOKEN = re.compile(r'^(itok_\w+):\s*\.text "([^"]*)"', re.M)
ITEM_CATEGORY = re.compile(r"^\s*\.byte (ICAT_\w+)\s*// (\d+):", re.M)


def _table_bytes(text: str, label: str) -> list[int]:
    """The values of a ``.byte``/``.fill`` table from its label to the next label."""
    body = text.split(f"\n{label}:\n", 1)[1]
    values: list[int] = []
    for line in body.splitlines():
        code = line.split("//", 1)[0].strip()
        if re.match(r"^\w+:", code):
            break
        if code.startswith(".byte"):
            values += [int(v[1:], 16) if v.startswith("$") else int(v)
                       for v in re.findall(r"\$[0-9a-fA-F]+|\b\d+\b", code[5:])]
        elif code.startswith(".fill"):
            count, value = (int(v) for v in re.findall(r"\d+", code))
            values += [value] * count
    return values


MISSILE_IDS = range(49, 55)   # bows, ammunition (IT_MISSILE_BASE, core/item_tables.s): one blow in melee


@dataclass(frozen=True)
class ItemKind:
    id: int
    name: str
    category: str     # ICAT_* name
    dice: int
    sides: int
    weight: int       # tenths of a pound

    @property
    def melee(self) -> bool:
        return self.category == "ICAT_WEAPON" and self.id not in MISSILE_IDS and self.dice > 0


@lru_cache(maxsize=1)
def item_kinds() -> dict[str, ItemKind]:
    """Item name -> kind, from the shipped item tables: what a player knows
    of weapon dice and weights from the manual."""
    text = ITEM_TABLES.read_text()
    tokens = {label.upper(): words for label, words in ITEM_TOKEN.findall(text)}

    def expand(stream: str) -> str:   # .text parts and .byte ITOK_* tokens, in order
        return "".join(m.group(1) if m.group(1) is not None else tokens.get(m.group(2), "")
                       for m in re.finditer(r'\.text "([^"]*)"|\.byte (ITOK_\w+)', stream))
    names = {int(i): expand(stream) for i, stream in ITEM_NAME.findall(text)}
    categories = {int(i): cat for cat, i in ITEM_CATEGORY.findall(text)}
    weights, dice = _table_bytes(text, "it_weight"), _table_bytes(text, "it_dmg_packed")
    return {name: ItemKind(i, name, categories.get(i, ""), dice[i] >> 4, dice[i] & 0x0F, weights[i])
            for i, name in names.items() if i < len(weights) and i < len(dice)}


def blows(strength: int, dexterity: int, weight: int) -> int:
    """Melee blows a turn, as ``combat_calc_blows`` (Umoria's table)."""
    dex = sum(dexterity >= t for t in (10, 19, 68, 108, 118))
    if strength * 15 < weight:
        return 1
    adj = strength * 10 // weight
    row = sum(adj >= t for t in (2, 3, 4, 5, 7, 9))
    return (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 2, 2, 3, 1, 1, 2, 2, 3, 3,
            1, 2, 2, 3, 3, 4, 1, 2, 2, 3, 4, 4, 2, 2, 3, 3, 4, 4)[row * 6 + dex]


@lru_cache(maxsize=1)
def _attack_pattern() -> re.Pattern[str]:
    names = sorted(creature_levels(), key=len, reverse=True)
    alternatives = "|".join(re.escape(name) for name in names)
    return re.compile(rf"[Tt]he ({alternatives}) (?:\w+ you\b|casts a spell|breathes)")


def attacker(messages: str) -> str | None:
    """The creature named in an attack or spell message, if any."""
    match = _attack_pattern().search(messages)
    return match.group(1) if match else None
