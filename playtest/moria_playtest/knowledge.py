"""Game knowledge a player brings to the game (§6.5): creature names and levels.

Read from the generated creature tier data the build ships, never from game
memory. The brain uses it the way a player uses experience: to tell whether
"You see a …" names a creature or an item, and who is attacking.
"""

from __future__ import annotations

import re
from functools import lru_cache

from .launch import ROOT
from .screen import screen_code_to_char

TIER_DIR = ROOT / "platforms/commodore/c64/creature_data"
TIER_LINE = re.compile(r"^//\s+\d+: \[\s*\d+\] DL\s*(\d+) (.+?)\s*$")
TIER_TABLE = re.compile(r"^tier\d+_cr_(\w+):\n((?:[ \t]*\.byte[^\n]*\n)+)", re.M)
CF_ATTACK_ONLY = 0x01   # cr_mflags: moves only to attack (tools/parse_creatures.py)
SPEED_FAST = 2          # cr_speed: 0 slow, 1 normal, 2 fast (tools/parse_creatures.py)


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
def _creatures() -> list[tuple[str, str, int, int]]:
    """(name, screen glyph, speed code, movement flags) for every shipped creature."""
    creatures = []
    for path in sorted(TIER_DIR.glob("tier[0-9].s")):
        text = path.read_text()
        names = [m.group(2) for m in map(TIER_LINE.match, text.splitlines()) if m]
        tables = {label: [int(v, 16) for v in re.findall(r"\$([0-9a-fA-F]{2})", body)]
                  for label, body in TIER_TABLE.findall(text)}
        creatures += [(name, screen_code_to_char(code), speed, flags) for name, code, speed, flags
                      in zip(names, tables["display"], tables["speed"], tables["mflags"])]
    return creatures


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
def _attack_pattern() -> re.Pattern[str]:
    names = sorted(creature_levels(), key=len, reverse=True)
    alternatives = "|".join(re.escape(name) for name in names)
    return re.compile(rf"[Tt]he ({alternatives}) (?:\w+ you\b|casts a spell|breathes)")


def attacker(messages: str) -> str | None:
    """The creature named in an attack or spell message, if any."""
    match = _attack_pattern().search(messages)
    return match.group(1) if match else None
