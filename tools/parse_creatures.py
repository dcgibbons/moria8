#!/usr/bin/env python3
"""
Parse umoria creature data and generate C64 Moria creature roster.

Reads the umoria data_creatures.cpp source file, decodes all 279 creatures
and 215 attack types, maps to our SoA format, and outputs:
  1. Full roster summary
  2. Selected subset (~120 creatures for disk tiers)
  3. Tier assignments with overlapping level ranges

Usage:
  UMORIA_SRC=<path>/src/data_creatures.cpp \
      python3 tools/parse_creatures.py [--all | --selected | --tiers | --asm]

  --all       Show all 279 umoria creatures
  --selected  Show the ~120 selected creatures (default)
  --tiers     Show tier breakdown with creature counts
  --asm       Generate assembly data (for R3.5.2) and sync docs/monsters.html
  --sync-web  Sync docs/monsters.html directly from tier0.s..tier4.s (no UMORIA_SRC needed)
  --check-web Verify docs/monsters.html matches tier0.s..tier4.s byte-for-byte

UMORIA_SRC names Umoria's src/data_creatures.cpp at the pinned revision in
docs/BEHAVIOR_CHANGE_PROTOCOL.md (2a2a6b791f084cac97db85f5b78739e913dd3572);
there is no default. --asm rewrites platforms/commodore/c64/creature_data/;
regenerating at that revision reproduces the committed tier files.
"""

import re
import sys
import os

# ============================================================
# Umoria attack type mapping → our C64 attack types
# ============================================================
# Umoria attack types (from data_creatures.cpp comments):
#  1=Normal, 2=Poison STR, 3=Confusion, 4=Fear, 5=Fire,
#  6=Acid, 7=Cold, 8=Lightning, 9=Corrosion, 10=Blindness,
#  11=Paralysis, 12=Steal Money, 13=Steal Object, 14=Poison,
#  15=Lose DEX, 16=Lose CON, 17=Lose INT, 18=Lose WIS,
#  19=Lose XP, 20=Aggravation, 21=Disenchant, 22=Eat food,
#  23=Eat light, 24=Eat charges, 99=Blank

# Our C64 attack effect types — must match monster.s:21-29
ATK_NONE      = 0
ATK_NORMAL    = 1
ATK_CONFUSE   = 3
ATK_FEAR      = 4
ATK_ACID      = 6
ATK_CORRODE   = 9
ATK_PARALYZE  = 11
ATK_POISON    = 14
ATK_AGGRAVATE = 20

ATK_NAMES = {
    0: "NONE", 1: "NORMAL", 3: "CONFUSE", 4: "FEAR",
    6: "ACID", 9: "CORRODE", 11: "PARALYZE", 14: "POISON",
    20: "AGGRAVATE",
}

UMORIA_TO_C64_ATK = {
    1:  ATK_NORMAL,     # Normal
    2:  ATK_POISON,     # Poison STR
    3:  ATK_CONFUSE,    # Confusion
    4:  ATK_FEAR,       # Fear
    5:  ATK_NORMAL,     # Fire → normal (no C64 handler)
    6:  ATK_ACID,       # Acid
    7:  ATK_NORMAL,     # Cold → normal (no C64 handler)
    8:  ATK_NORMAL,     # Lightning → normal (no C64 handler)
    9:  ATK_CORRODE,    # Corrosion
    10: ATK_NORMAL,     # Blindness → normal (no C64 handler)
    11: ATK_PARALYZE,   # Paralysis
    12: ATK_NORMAL,     # Steal Money → 0d0 touch (no-HP; no handler)
    13: ATK_NORMAL,     # Steal Object → 0d0 touch (no-HP; no handler)
    14: ATK_POISON,     # Poison
    15: ATK_POISON,     # Lose DEX → poison (simplified)
    16: ATK_POISON,     # Lose CON → poison (simplified)
    17: ATK_NORMAL,     # Lose INT → normal (simplified)
    18: ATK_NORMAL,     # Lose WIS → normal (simplified)
    19: ATK_NORMAL,     # Lose experience → 0d0 touch (no-HP; no handler)
    20: ATK_AGGRAVATE,  # Aggravation (no-HP; dice dropped)
    21: ATK_NORMAL,     # Disenchant → 0d0 touch (no-HP; no handler)
    22: ATK_NORMAL,     # Eat food → 0d0 touch (no-HP; no handler)
    23: ATK_NORMAL,     # Eat light → 0d0 touch (no-HP; no handler)
    24: ATK_NORMAL,     # Eat charges → 0d0 touch (no-HP; no handler)
    99: ATK_NONE,       # Blank → no attack
}

# Upstream attack types that never deal HP damage: pinned VMS Moria
# creature.inc make_attack (cases 12, 13, 19-24 call no take_hit) and Umoria
# monster.cpp executeAttackOnPlayer (no playerTakesHit). Their dice measure
# something else (Lose experience: the experience drained, VMS lose_exp /
# Umoria spellLoseEXP), so the generator drops them to 0d0: Moria8 has no
# steal, drain-experience, disenchant or eat effects, and a 0d0 ATK_NORMAL
# keeps the to-hit roll as a touch with no damage. ATK_AGGRAVATE keeps its
# handler (its slot-0 path rolls no damage) and loses its dice too.
NO_HP_ATTACK_TYPES = {12, 13, 19, 20, 21, 22, 23, 24}

# Moria8 keeps two attack slots (cr_atk0_*, cr_atk1_*); upstream creatures
# have up to four (VMS values.inc c_list damage strings, Umoria
# data_creatures.cpp). A creature with three or four keeps the two that
# matter most, after the type mapping above and NO_HP_ATTACK_TYPES, ranked by:
#   1. a paralysis attack first: upstream it costs randint(level) + 3
#      helpless turns (VMS creature.inc make_attack case 11; Umoria
#      monster.cpp identical) in which the creature's other blows land
#      freely, so it outweighs any one blow (Iridescent Beetle: its 4d6
#      bite and paralysing gaze, not the 1d12);
#   2. then expected HP damage, dice * (sides + 1) / 2 (a 0d0 touch is 0);
#   3. then an attack with a Moria8 effect (fear, confusion, poison, acid,
#      corrode, aggravate) over a plain hit of equal damage;
#   4. then the earlier upstream slot.
# The two kept stay in their upstream order (slot 0 keeps its meaning, e.g.
# ATK_AGGRAVATE). A creature with two or fewer is unchanged. Before
# 2026-11-01 the first two were kept, which dropped the dragons' and trolls'
# bites, the Umber Hulk's 2d6 and the Ghost's 1d10 claw.
def select_attack_slots(atks):
    """Pick the two attack slots Moria8 keeps from up to four mapped ones."""
    live = [(i, a) for i, a in enumerate(atks) if a['type'] != ATK_NONE]
    if len(live) > 2:
        ranked = sorted(live, key=lambda ia: (
            ia[1]['type'] == ATK_PARALYZE,
            ia[1]['dice'] * (ia[1]['sides'] + 1),
            ia[1]['type'] != ATK_NORMAL,
            -ia[0]), reverse=True)
        live = sorted(ranked[:2])
    kept = [a for _, a in live]
    while len(kept) < 2:
        kept.append({'type': ATK_NONE, 'dice': 0, 'sides': 0})
    return kept

# ============================================================
# Umoria speed mapping → our C64 speed (0=slow, 1=normal, 2=fast)
# ============================================================
# Umoria: speed + 10. So 9=very slow, 10=slow, 11=normal, 12=fast, 13=very fast
def map_speed(umoria_speed):
    if umoria_speed <= 10:
        return 0  # slow (every other turn)
    elif umoria_speed == 11:
        return 1  # normal
    else:
        return 2  # fast

# Umoria CMOVE random-movement bits, kept in place in cr_speed bits 3-5 above
# the speed code (MON-013): CM_20_RANDOM 0x08, CM_40_RANDOM 0x10, CM_75_RANDOM
# 0x20. monster_ai.s rolls 75%, then 40%, then 20% before normal movement.
CM_RANDOM_MOVE = 0x38

SPEED_MASK = 0x03

# Umoria CDEFENSE CD_MAX_HP (VMS cdefense %X'4000'): the creature spawns with
# its full hit dice, N * S, not a roll (VMS misc.inc place_monster max_hp;
# Umoria monster_manager.cpp maxDiceRoll). Kept in cr_speed bit 7, which the
# speed (CR_SPEED_MASK) and random-move (CM_RANDOM_MOVE) readers mask out;
# monster_spawn_one (core/monster.s) tests it.
CD_MAX_HP = 0x4000
CR_MAX_HP = 0x80

# Umoria CMOVE treasure bits 24-30, shifted down to cr_treasure bits 0-6
# (MON-014): carry object, carry gold, 60%, 90%, 1d2, 2d2 and 4d2 drops (VMS
# bit 30 is 4d3). Bit 31 (CM_WIN) is not a drop.
CM_TREASURE = 0x7F

# ============================================================
# Color assignment based on creature name/type
# ============================================================
# C64 colors
COL_WHITE   = 1
COL_RED     = 2
COL_CYAN    = 3
COL_PURPLE  = 4
COL_GREEN   = 5
COL_BLUE    = 6
COL_YELLOW  = 7
COL_ORANGE  = 8
COL_BROWN   = 9
COL_LRED    = 10
COL_DGREY   = 11
COL_GREY    = 12
COL_LGREEN  = 13
COL_LBLUE   = 14
COL_LGREY   = 15

def assign_color(name):
    """Assign C64 color based on creature name keywords."""
    n = name.lower()
    # Color keywords
    if 'white' in n or 'clear' in n or 'silver' in n or 'frost' in n or 'ice' in n:
        return COL_WHITE
    if 'red' in n or 'fire' in n or 'crimson' in n:
        return COL_RED
    if 'blue' in n:
        return COL_BLUE
    if 'green' in n:
        return COL_GREEN
    if 'yellow' in n or 'gold' in n or 'copper' in n:
        return COL_YELLOW
    if 'black' in n or 'dark' in n or 'death' in n or 'nether' in n:
        return COL_DGREY
    if 'grey' in n or 'gray' in n:
        return COL_GREY
    if 'brown' in n or 'tan' in n or 'wooden' in n:
        return COL_BROWN
    if 'purple' in n or 'violet' in n:
        return COL_PURPLE
    if 'orange' in n or 'spotted' in n or 'mottled' in n:
        return COL_ORANGE
    if 'multi' in n or 'iridescent' in n or 'shimmering' in n:
        return COL_CYAN
    if 'ancient' in n:
        return COL_LRED
    if 'mature' in n:
        return COL_ORANGE
    if 'young' in n:
        return COL_LGREEN
    # Type-based defaults
    if 'skeleton' in n or 'zombie' in n or 'mummif' in n:
        return COL_LGREY
    if 'ghost' in n or 'spirit' in n or 'wraith' in n or 'wight' in n:
        return COL_LGREY
    if 'dragon' in n:
        return COL_RED
    if 'troll' in n or 'ogre' in n:
        return COL_GREEN
    if 'orc' in n:
        return COL_BROWN
    if 'lich' in n:
        return COL_PURPLE
    if 'golem' in n:
        return COL_GREY
    if 'jelly' in n or 'ooze' in n or 'mold' in n:
        return COL_LGREEN
    if 'bat' in n:
        return COL_BROWN
    if 'worm' in n:
        return COL_LGREY
    if 'scorpion' in n or 'tick' in n or 'beetle' in n:
        return COL_BROWN
    # Humanoids
    if any(x in n for x in ['warrior', 'priest', 'mage', 'rogue', 'knight',
                             'ninja', 'swordsman', 'bandit', 'brigand',
                             'berzerker', 'necromancer', 'sorcerer',
                             'mercenary', 'veteran']):
        return COL_CYAN
    # Townspeople
    if any(x in n for x in ['urchin', 'beggar', 'leper', 'drunk', 'wretch', 'idiot']):
        return COL_LGREY
    # Default
    return COL_WHITE

# ============================================================
# CMOVE flag analysis
# ============================================================
CF_ATTACK_ONLY = 0x01  # Our flag for stationary attackers
CF_UNDEAD      = 0x02  # Our undead flag
CF_EVIL        = 0x04  # Evil creature (ego slay)
CF_ANIMAL      = 0x08  # Animal creature (ego slay)
CF_DRAGON      = 0x10  # Dragon creature (future ego slay)
CF_BREEDER     = 0x40  # Multiplying creature (core/monster.s)
CF_INFRA      = 0x80  # Warm creature visible to infravision

# Umoria config.cpp flag bits (pinned revision 2a2a6b79).
CM_MOVE_NORMAL = 0x00000002
CM_MULTIPLY = 0x00200000
CD_DRAGON   = 0x0001
CD_ANIMAL   = 0x0002
CD_EVIL     = 0x0004
CD_UNDEAD   = 0x0008
CD_INFRA    = 0x2000

# Door capability (Umoria CMOVE 0x00020000) folds into cr_aaf bit 7:
# AAF values top out at 40, so bit 7 carries CD_OPEN_DOOR.
CD_OPEN_DOOR  = 0x80  # cr_aaf bit 7: opens/bashes doors

def map_doorflags(cmove):
    """Map umoria CMOVE door bit to the cr_aaf bit-7 flag."""
    if cmove & 0x00020000:  # CM_OPEN_DOOR
        return CD_OPEN_DOOR
    return 0

def map_mflags(cmove, cdefense, name):
    """Map umoria CMOVE/CDEFENSE flags to our cr_mflags byte."""
    flags = 0
    # Never moves: neither CM_MOVE_NORMAL (0x02) nor a random-move bit
    # (0x08/0x10/0x20). Pinned VMS creature.inc mon_move and Umoria
    # monster.cpp monsterMove move a creature only through those bits:
    # CM_ATTACK_ONLY (0x01) creatures attack an adjacent player in place, and
    # CM_ONLY_MAGIC (0x04, Quylthulg; VMS encodes Rotting Quylthulg as 0) or
    # no bits at all never move. Moria8's CF_ATTACK_ONLY keeps both in place.
    # Until 2026-11-01 only exactly 0x01 was recognised, so the Quylthulg
    # walked.
    if (cmove & (CM_MOVE_NORMAL | CM_RANDOM_MOVE)) == 0:
        flags |= CF_ATTACK_ONLY
    # Multiplies: Umoria CM_MULTIPLY (worm masses, lice, ...). Umoria has no
    # pack flag, so CF_GROUP stays unset, as upstream has no packs.
    if cmove & CM_MULTIPLY:
        flags |= CF_BREEDER
    # Slay classes, Umoria CD_* bits. Until 2026-10-25 animal was read from
    # 0x0010 (CD_FROST, hurt by frost) and dragon from 0x0002 (CD_ANIMAL).
    if cdefense & CD_UNDEAD:
        flags |= CF_UNDEAD
    if cdefense & CD_EVIL:
        flags |= CF_EVIL
    if cdefense & CD_ANIMAL:
        flags |= CF_ANIMAL
    if cdefense & CD_DRAGON:
        flags |= CF_DRAGON
    # Seen with infravision
    if cdefense & CD_INFRA:
        flags |= CF_INFRA
    return flags

# ============================================================
# Spell mapping
# ============================================================
# Our spell flags
MSF_WOUND_LIGHT   = 0x01
MSF_BREATH        = 0x02
MSF_SUMMON        = 0x04
MSF_TELEPORT      = 0x08
MSF_BLIND         = 0x10
MSF_CONFUSE       = 0x20
MSF_WOUND_SERIOUS = 0x40
MSF_FEAR          = 0x80

def map_spells(spell_word):
    """Map umoria spell flags to our spell_flags and spell_chance."""
    if spell_word == 0:
        return 0, 0  # No spells

    # Frequency: low 4 bits add up to give 1-in-X chance
    freq = spell_word & 0x0F
    if freq == 0:
        return 0, 0
    # Convert to percentage: 100/freq, cap at 100
    chance = min(100, int(100 / freq)) if freq > 0 else 0

    flags = 0
    # Map spell bits
    if spell_word & 0x000080:  # Cause light wound (3d8)
        flags |= MSF_WOUND_LIGHT
    if spell_word & 0x000100:  # Cause serious wound (8d8)
        flags |= MSF_WOUND_SERIOUS
    if spell_word & 0x000200:  # Hold person
        pass  # Not mapped to our flags
    if spell_word & 0x000400:  # Blindness
        flags |= MSF_BLIND
    if spell_word & 0x000800:  # Confusion
        flags |= MSF_CONFUSE
    if spell_word & 0x001000:  # Fear
        flags |= MSF_FEAR
    if spell_word & 0x002000:  # Summon monster
        flags |= MSF_SUMMON
    if spell_word & 0x004000:  # Summon undead
        flags |= MSF_SUMMON
    if spell_word & 0x000040:  # Teleport player to monster
        flags |= MSF_TELEPORT
    if spell_word & 0x010000:  # Drain mana
        pass  # Not mapped
    # Breath attacks
    breath_bits = (spell_word >> 19) & 0x1F
    if breath_bits:
        flags |= MSF_BREATH

    # None of the creature's spells exists in Moria8 (blink, teleport self,
    # hold person, slow, drain mana): no chance either, or monster_can_cast
    # would spend the turn on a pick with nothing to cast.
    if flags == 0:
        return 0, 0

    return chance, flags

# ============================================================
# Display character mapping (ASCII → C64 screen code)
# ============================================================
def char_to_screencode(ch):
    """Convert ASCII character to C64 screen code (lowercase/uppercase mode)."""
    if 'A' <= ch <= 'Z':
        return ord(ch) - ord('A') + 0x41  # Uppercase: $41-$5A
    if 'a' <= ch <= 'z':
        return ord(ch) - ord('a') + 0x01  # Lowercase: $01-$1A
    if ch == '$':
        return 0x24
    if ch == ',':
        return 0x2C
    if ch == '.':
        return 0x2E
    # Default: return the ASCII code (many overlap for printable chars)
    return ord(ch) & 0x3F

# ============================================================
# Parse the source file
# ============================================================
def parse_attacks(filepath):
    """Parse the monster_attacks array from the source file."""
    attacks = []
    with open(filepath, 'r') as f:
        content = f.read()

    # Find the monster_attacks array
    atk_match = re.search(r'MonsterAttack_t\s+monster_attacks.*?=\s*\{(.*?)\};', content, re.DOTALL)
    if not atk_match:
        print("ERROR: Could not find monster_attacks array", file=sys.stderr)
        return attacks

    atk_text = atk_match.group(1)
    # Parse each {type, desc, {dice, sides}} entry
    pattern = r'\{(\d+),\s*(\d+),\s*\{(\d+),\s*(\d+)\}\}'
    for m in re.finditer(pattern, atk_text):
        attacks.append({
            'type': int(m.group(1)),
            'desc': int(m.group(2)),
            'dice': int(m.group(3)),
            'sides': int(m.group(4)),
        })
    return attacks


def parse_creatures(filepath):
    """Parse the creatures_list array from the source file."""
    creatures = []
    with open(filepath, 'r') as f:
        content = f.read()

    # Find the creatures_list array
    cr_match = re.search(r'creatures_list\[.*?\]\s*=\s*\{(.*?)\n\};', content, re.DOTALL)
    if not cr_match:
        print("ERROR: Could not find creatures_list array", file=sys.stderr)
        return creatures

    cr_text = cr_match.group(1)
    # Parse each creature entry
    # Format: {"Name", 0xCMOVE, 0xSPELL, 0xCDEF, XP, SLEEP, AAF, AC, SPEED, 'CHAR', {HD_N, HD_S}, {A0, A1, A2, A3}, DLVL},
    pattern = (
        r'\{"([^"]+)"'           # name
        r',\s*(0x[0-9A-Fa-f]+)L' # cmove
        r',\s*(0x[0-9A-Fa-f]+)L' # spell
        r',\s*(0x[0-9A-Fa-f]+)'  # cdefense
        r',\s*(\d+)L?'           # xp (optional L suffix)
        r',\s*(\d+)'             # sleep
        r',\s*(\d+)'             # aaf
        r',\s*(\d+)'             # ac
        r',\s*(\d+)'             # speed
        r",\s*'(.)',"            # sprite char
        r'\s*\{\s*(\d+),\s*(\d+)\}' # hit die
        r',\s*\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\}' # damage[4]
        r',\s*(\d+)\}'          # dungeon level
    )

    for m in re.finditer(pattern, cr_text):
        creatures.append({
            'name': m.group(1),
            'cmove': int(m.group(2), 16),
            'spell': int(m.group(3), 16),
            'cdefense': int(m.group(4), 16),
            'xp': int(m.group(5)),
            'sleep': int(m.group(6)),
            'aaf': int(m.group(7)),
            'ac': int(m.group(8)),
            'speed': int(m.group(9)),
            'sprite': m.group(10),
            'hd_num': int(m.group(11)),
            'hd_sides': int(m.group(12)),
            'dmg': [int(m.group(13)), int(m.group(14)),
                    int(m.group(15)), int(m.group(16))],
            'dlvl': int(m.group(17)),
        })
    return creatures


# ============================================================
# Creature selection for ~120 disk-tier subset
# ============================================================
# Name-based selection (robust against index changes).
# At runtime, names are looked up against parsed creature list.
#
# Selection criteria:
# - 8 town creatures (all)
# - 3 per dungeon level for levels 1-40 (a few have 2)
# - Prefer unique/iconic over redundant color variants
# - Ensure all attack types are represented
# - Include winning creatures
# - Target: exactly 120 creatures

SELECTED_NAMES = [
    # === DL 0: Town (all 8) ===
    "Filthy Street Urchin",
    "Blubbering Idiot",
    "Pitiful-Looking Beggar",
    "Mangy-Looking Leper",
    "Squint-Eyed Rogue",
    "Singing, Happy Drunk",
    "Mean-Looking Mercenary",
    "Battle-Scarred Veteran",

    # === DL 1 (3) ===
    "Kobold",                     # classic humanoid
    "White Worm mass",            # slow, poison
    "Floating Eye",               # paralyze spells, stationary

    # === DL 2 (3) ===
    "Novice Priest",              # spellcaster
    "Novice Mage",                # spellcaster
    "Giant Black Ant",            # melee swarm

    # === DL 3 (3) ===
    "Poltergeist",                # ghost, fast, fear+spells
    "Black Naga",                 # strong early unique
    "Yellow Jelly",               # fast, poison+spells

    # === DL 4 (3) ===
    "Creeping Copper Coins",      # mimic, slow, poison
    "Blue Worm mass",             # slow, cold
    "Jackal",                     # melee

    # === DL 5 (3) ===
    "Green Naga",                 # acid attack
    "White Mushroom patch",       # paralysis spore
    "Skeleton Kobold",            # undead

    # === DL 6 (3) ===
    "Brown Mold",                 # confusion attack
    "Orc",                        # classic humanoid
    "Rattlesnake",                # poison

    # === DL 7 (3) ===
    "Bloodshot Eye",              # blind attack + spells
    "Zombie Kobold",              # undead
    "Lost Soul",                  # ghost, fear+spells

    # === DL 8 (3) ===
    "Green Mold",                 # fear attack
    "Skeleton Orc",               # undead
    "Bandit",                     # humanoid

    # === DL 9 (3) ===
    "Orc Shaman",                 # spellcaster
    "Giant Red Ant",              # poison
    "King Cobra",                 # blind + poison

    # === DL 10 (3) ===
    "Giant White Tick",           # slow, poison
    "Disenchanter Mold",          # spellcaster
    "Creeping Gold Coins",        # mimic, slow

    # === DL 11 (3) ===
    "Orc Zombie",                 # undead
    "Nasty Little Gnome",         # spellcaster
    "Hobgoblin",                  # strong melee

    # === DL 12 (3) ===
    "Black Mamba",                # fast, poison
    "Priest",                     # spellcaster
    "Skeleton Human",             # undead

    # === DL 13 (3) ===
    "Ogre",                       # classic, strong
    "Magic User",                 # major spellcaster
    "Black Orc",                  # strong melee

    # === DL 14 (3) ===
    "Giant White Dragon Fly",     # cold breath + spells
    "Hill Giant",                 # classic
    "Flesh Golem",                # golem type

    # === DL 15 (2) ===
    "Frost Giant",                # cold attack
    "Violet Mold",                # paralysis + spells

    # === DL 16 (3) ===
    "Umber Hulk",                 # iconic
    "Fire Giant",                 # fire attack
    "Quasit",                     # poison + spells

    # === DL 17 (3) ===
    "Troll",                      # classic
    "Giant Brown Scorpion",       # poison sting
    "Earth Spirit",               # elemental

    # === DL 18 (3) ===
    "Fire Spirit",                # fire, fast
    "Uruk-Hai Orc",               # strong orc
    "Stone Giant",                # strong melee

    # === DL 19 (2) ===
    "Stone Golem",                # slow, high AC
    "Killer Black Beetle",        # melee

    # === DL 20 (2) ===
    "Quylthulg",                  # summoner, no attacks
    "Cloud Giant",                # strong

    # === DL 21 (2) ===
    "Mummified Orc",              # undead
    "Killer Boring Beetle",       # melee

    # === DL 22 (3) ===
    "Killer Stag Beetle",         # multi-attack melee
    "Iron Golem",                 # slow, high AC
    "Giant Yellow Scorpion",      # poison

    # === DL 23 (2) ===
    "Warrior",                    # strong humanoid
    "Giant Silver Ant",           # corrode

    # === DL 24 (3) ===
    "Forest Wight",               # undead, drain, spells
    "Mummified Human",            # undead
    "Banshee",                    # ghost, drain, fast

    # === DL 25 (2) ===
    "Giant Troll",                # strong
    "Killer Red Beetle",          # poison

    # === DL 26 (3) ===
    "Giant Fire Tick",            # fire attack
    "White Wraith",               # undead, drain, spells
    "Giant Black Scorpion",       # poison

    # === DL 27 (3) ===
    "Killer Fire Beetle",         # fire
    "Vampire",                    # drain, spells
    "Shimmering Mold",            # high HP

    # === DL 28 (3) ===
    "Black Knight",               # humanoid, spells
    "Mage",                       # major spellcaster
    "Ice Troll",                  # cold variant

    # === DL 29 (3) ===
    "Giant Purple Worm",          # corrode, big
    "Young Blue Dragon",          # dragon, spells
    "Young Green Dragon",         # dragon, spells

    # === DL 30 (2) ===
    "Skeleton Troll",             # undead
    "Grave Wight",                # undead, drain, spells

    # === DL 31 (3) ===
    "Ghost",                      # fast, drain, spells
    "Death Watch Beetle",         # strong melee
    "Ogre Mage",                  # spellcaster

    # === DL 32 (3) ===
    "Two-Headed Troll",           # multi-attack
    "Invisible Stalker",          # fast, invisible
    "Ninja",                      # poison

    # === DL 33 (2) ===
    "Barrow Wight",               # undead, drain, spells
    "Fire Elemental",             # slow, fire

    # === DL 34 (3) ===
    "Lich",                       # major spellcaster, drain
    "Master Vampire",             # drain, spells
    "Earth Elemental",            # slow, strong

    # === DL 35 (3) ===
    "Young Red Dragon",           # fire breath, spells
    "Necromancer",                # major spellcaster
    "Mature White Dragon",        # cold breath, spells

    # === DL 36 (2) ===
    "Xorn",                       # wall pass
    "Grey Wraith",                # undead, drain, spells

    # === DL 37 (3) ===
    "Iridescent Beetle",          # strong melee
    "King Lich",                  # major spellcaster
    "Mature Red Dragon",          # fire breath, spells

    # === DL 38 (2) ===
    "Ancient White Dragon",       # fast, cold breath
    "Black Wraith",               # undead, drain, spells

    # === DL 39 (3) ===
    "Nether Wraith",              # undead, drain, spells
    "Sorcerer",                   # fast, major spellcaster
    "Ancient Blue Dragon",        # fast, spells

    # === DL 40 (3) ===
    "Ancient Red Dragon",         # fast, fire breath
    "Emperor Lich",               # fast, major spellcaster
    "Ancient Multi-Hued Dragon",  # fast, multi-breath

    # === Winning creatures ===
    "Evil Iggy",                  # boss (DL 50)
    "Balrog",                     # final boss (DL 100)
]

# Creatures added after the original 120 (maintainer, 2026-10-25): upstream's
# DL 1 is full of weak prey, and the 3-per-level selection above left Kobold,
# White Worm mass and Floating Eye as Moria8's only DL 1 creatures (found by
# the M5b playtest). Each tier lists them after its original members, in this
# order, so the tier-local indices that saves and tests use do not move.
ADDED_NAMES = [
    "Giant White Centipede",      # DL 1, bite 1d2, sting 1d2
    "Giant Yellow Centipede",     # DL 1, bite 1d3, sting 1d3
    "White Icky-Thing",           # DL 1, touch 1d2
    "Large White Snake",          # DL 1, bite 1d1, slow
    "Giant White Mouse",          # DL 1, bite 1d2, breeds
    # Second batch (maintainer, 2026-10-25: "add 25 more creatures to tier-1"):
    # DL 1-5 creatures upstream has and Moria8 lacked; no more breeders and
    # nothing invisible.
    "Large Brown Snake",          # DL 1
    "Grey Mushroom patch",        # DL 1, stationary, confusion spores
    "Blubbering Icky-Thing",      # DL 2, poison touch
    "Metallic Green Centipede",   # DL 2
    "Novice Warrior",             # DL 2
    "Novice Rogue",               # DL 2
    "Giant Green Frog",           # DL 2
    "Blue Yeek",                  # DL 2
    "Large Black Snake",          # DL 2
    "White Harpy",                # DL 2, erratic flyer
    "Yellow Mushroom patch",      # DL 2, stationary, fear spores
    "Metallic Blue Centipede",    # DL 3
    "Scruffy-Looking Hobbit",     # DL 3
    "Huge Brown Bat",             # DL 3, fast, erratic
    "Giant White Ant",            # DL 3
    "Metallic Red Centipede",     # DL 3
    "Large Green Snake",          # DL 3
    "Drooling Harpy",             # DL 3
    "Radiation Eye",              # DL 3, stationary, spells
    "Giant Black Centipede",      # DL 4
    "Giant Blue Centipede",       # DL 4
    "Large Grey Snake",           # DL 4
    "Black Yeek",                 # DL 5
    "Grey Icky-Thing",            # DL 5
    "Giant Black Frog",           # DL 5
]
ADDED_ORDER: list[int] = []       # their indices, resolved in main()


def tier_order(indices):
    """Selected creature indices in tier order: the original selection by
    Umoria index, then ADDED_NAMES in their listed order."""
    added = [i for i in ADDED_ORDER if i in indices]
    return [i for i in sorted(indices) if i not in ADDED_ORDER] + added


# ============================================================
# Tier assignment
# ============================================================
# Overlapping tiers for spawn window (dlvl-2 to dlvl+3)
TIERS = [
    {"name": "Tier 0 (Town)",   "min_dlvl": 0,  "max_dlvl": 0,  "resident": True},
    {"name": "Tier 1 (Shallow)","min_dlvl": 1,  "max_dlvl": 8,  "resident": False},
    {"name": "Tier 2 (Early)",  "min_dlvl": 5,  "max_dlvl": 15, "resident": False},
    {"name": "Tier 3 (Mid)",    "min_dlvl": 11, "max_dlvl": 25, "resident": False},
    {"name": "Tier 4 (Deep)",   "min_dlvl": 20, "max_dlvl": 100, "resident": False},
]

def get_tiers_for_creature(dlvl):
    """Return list of tier indices this creature belongs to."""
    tiers = []
    for i, t in enumerate(TIERS):
        if t["min_dlvl"] <= dlvl <= t["max_dlvl"]:
            tiers.append(i)
    return tiers


# ============================================================
# Main
# ============================================================
def main():
    mode = "selected"
    if len(sys.argv) > 1:
        mode = sys.argv[1].lstrip('-')

    if mode == "sync-web":
        sync_web(check_only=False)
        return
    if mode == "check-web":
        sync_web(check_only=True)
        return

    # Source file: supplied by the caller only (AGENTS.md rule 9).
    src_path = os.environ.get("UMORIA_SRC", "")
    if not src_path or not os.path.isfile(src_path):
        print("ERROR: set UMORIA_SRC to Umoria's src/data_creatures.cpp", file=sys.stderr)
        print("  (pinned revision: docs/BEHAVIOR_CHANGE_PROTOCOL.md)", file=sys.stderr)
        sys.exit(1)

    # Parse
    attacks = parse_attacks(src_path)
    creatures = parse_creatures(src_path)
    print(f"Parsed {len(creatures)} creatures, {len(attacks)} attack types", file=sys.stderr)

    # Decode attacks for each creature
    name_to_index = {}
    for i, cr in enumerate(creatures):
        decoded_atks = []
        for dmg_idx in cr['dmg']:
            if dmg_idx == 0 or dmg_idx >= len(attacks):
                decoded_atks.append({'type': 0, 'dice': 0, 'sides': 0})
            else:
                atk = attacks[dmg_idx]
                no_hp = atk['type'] in NO_HP_ATTACK_TYPES
                decoded_atks.append({
                    'type': UMORIA_TO_C64_ATK.get(atk['type'], ATK_NORMAL),
                    'dice': 0 if no_hp else atk['dice'],
                    'sides': 0 if no_hp else atk['sides'],
                })
        cr['attacks'] = select_attack_slots(decoded_atks)
        cr['c64_speed'] = (map_speed(cr['speed']) | (cr['cmove'] & CM_RANDOM_MOVE)
                           | (CR_MAX_HP if cr['cdefense'] & CD_MAX_HP else 0))
        cr['c64_color'] = assign_color(cr['name'])
        cr['c64_display'] = char_to_screencode(cr['sprite'])
        cr['c64_mflags'] = map_mflags(cr['cmove'], cr['cdefense'], cr['name'])
        cr['c64_aaf'] = min(127, cr['aaf']) | map_doorflags(cr['cmove'])
        spell_chance, spell_flags = map_spells(cr['spell'])
        cr['c64_spell_chance'] = spell_chance
        cr['c64_spell_flags'] = spell_flags
        cr['c64_treasure'] = (cr['cmove'] >> 24) & CM_TREASURE
        cr['c64_xp_lo'] = cr['xp'] & 0xFF
        cr['c64_xp_hi'] = (cr['xp'] >> 8) & 0xFF
        cr['tiers'] = get_tiers_for_creature(cr['dlvl'])
        name_to_index[cr['name']] = i

    # Resolve name-based selection to indices
    selected_indices = set()
    for name in SELECTED_NAMES:
        if name in name_to_index:
            selected_indices.add(name_to_index[name])
        else:
            print(f"WARNING: Selected creature not found: '{name}'", file=sys.stderr)
    for name in ADDED_NAMES:
        if name in name_to_index:
            selected_indices.add(name_to_index[name])
            ADDED_ORDER.append(name_to_index[name])
        else:
            print(f"WARNING: Added creature not found: '{name}'", file=sys.stderr)

    if mode == "all":
        print_all(creatures, selected_indices)
    elif mode == "selected":
        print_selected(creatures, selected_indices)
    elif mode == "tiers":
        print_tiers(creatures, selected_indices)
    elif mode == "stats":
        print_stats(creatures, selected_indices)
    elif mode == "asm":
        generate_asm(creatures, selected_indices)
    else:
        print(f"Unknown mode: {mode}")
        print("Usage: parse_creatures.py [--all | --selected | --tiers | --stats | --asm]")


def print_all(creatures, selected_indices):
    """Print all creatures in a table."""
    print(f"{'#':>3} {'DL':>2} {'Name':<30} {'Sym':>3} {'SPD':>3} {'HP':<6} {'AC':>3} "
          f"{'SLP':>4} {'AAF':>3} {'XP':>5} {'Atk1':<12} {'Atk2':<12} {'Spells':<10}")
    print("-" * 120)
    for i, cr in enumerate(creatures):
        a0 = cr['attacks'][0]
        a1 = cr['attacks'][1]
        atk0_str = f"{ATK_NAMES.get(a0['type'],'?')[:6]} {a0['dice']}d{a0['sides']}" if a0['dice'] > 0 else "-"
        atk1_str = f"{ATK_NAMES.get(a1['type'],'?')[:6]} {a1['dice']}d{a1['sides']}" if a1['dice'] > 0 else "-"
        sp = f"{cr['c64_spell_chance']}%" if cr['c64_spell_chance'] > 0 else "-"
        sel = "*" if i in selected_indices else " "
        print(f"{i:>3}{sel}{cr['dlvl']:>2} {cr['name']:<30} {cr['sprite']:>3} "
              f"{cr['c64_speed']:>3} {cr['hd_num']}d{cr['hd_sides']:<4} {cr['ac']:>3} "
              f"{cr['sleep']:>4} {cr['aaf']:>3} {cr['xp']:>5} {atk0_str:<12} {atk1_str:<12} {sp:<10}")


def print_selected(creatures, selected_indices):
    """Print selected creatures grouped by tier."""
    selected = [(i, creatures[i]) for i in sorted(selected_indices) if i < len(creatures)]
    print(f"Selected {len(selected)} creatures from {len(creatures)} total\n")

    # Group by dungeon level
    by_dlvl = {}
    for idx, cr in selected:
        dl = cr['dlvl']
        if dl not in by_dlvl:
            by_dlvl[dl] = []
        by_dlvl[dl].append((idx, cr))

    print(f"{'#':>3} {'DL':>2} {'Name':<30} {'Sym':>3} {'Col':>3} {'SPD':>3} {'Flg':>3} "
          f"{'HP':<6} {'AC':>3} {'SLP':>4} {'AAF':>3} {'XP':>5} {'Atk1':<12} {'Atk2':<12} "
          f"{'SP%':>3} {'SFlg':>4} {'Tiers':<10}")
    print("-" * 140)

    for dl in sorted(by_dlvl.keys()):
        for idx, cr in by_dlvl[dl]:
            a0 = cr['attacks'][0]
            a1 = cr['attacks'][1]
            atk0_str = f"{ATK_NAMES.get(a0['type'],'?')[:6]} {a0['dice']}d{a0['sides']}" if a0['dice'] > 0 else "-"
            atk1_str = f"{ATK_NAMES.get(a1['type'],'?')[:6]} {a1['dice']}d{a1['sides']}" if a1['dice'] > 0 else "-"
            tier_str = ",".join(str(t) for t in cr['tiers'])
            print(f"{idx:>3} {cr['dlvl']:>2} {cr['name']:<30} {cr['sprite']:>3} "
                  f"{cr['c64_color']:>3} {cr['c64_speed']:>3} ${cr['c64_mflags']:02X} "
                  f"{cr['hd_num']}d{cr['hd_sides']:<4} {cr['ac']:>3} "
                  f"{cr['sleep']:>4} {cr['aaf']:>3} {cr['xp']:>5} {atk0_str:<12} {atk1_str:<12} "
                  f"{cr['c64_spell_chance']:>3} ${cr['c64_spell_flags']:02X} {tier_str:<10}")


def print_tiers(creatures, selected_indices):
    """Print tier breakdown."""
    selected = {i: creatures[i] for i in selected_indices if i < len(creatures)}

    for tier_idx, tier in enumerate(TIERS):
        members = [(idx, cr) for idx, cr in selected.items()
                   if tier_idx in cr['tiers']]
        # Calculate data size
        soa_bytes = len(members) * TIER_BYTES_PER_CREATURE
        name_bytes = sum(len(cr['name']) + 1 for _, cr in members)  # +1 for null term
        total = soa_bytes + name_bytes

        print(f"\n{'='*60}")
        print(f"{tier['name']} (dlvl {tier['min_dlvl']}-{tier['max_dlvl']})")
        print(f"  Creatures: {len(members)}")
        print(f"  SoA data:  {soa_bytes} bytes")
        print(f"  Names:     {name_bytes} bytes")
        print(f"  Total:     {total} bytes")
        print(f"  {'Resident' if tier['resident'] else 'Loaded from disk/REU'}")
        print(f"{'='*60}")
        for idx, cr in sorted(members, key=lambda x: x[1]['dlvl']):
            print(f"  [{idx:>3}] DL{cr['dlvl']:>2} {cr['name']}")

    # Overall stats
    all_members = set()
    for tier_idx, tier in enumerate(TIERS):
        for idx, cr in selected.items():
            if tier_idx in cr['tiers']:
                all_members.add(idx)
    total_soa = len(all_members) * TIER_BYTES_PER_CREATURE
    total_names = sum(len(creatures[i]['name']) + 1 for i in all_members)
    print(f"\n{'='*60}")
    print(f"TOTAL: {len(all_members)} unique creatures")
    print(f"  SoA data:  {total_soa} bytes")
    print(f"  Names:     {total_names} bytes")
    print(f"  Combined:  {total_soa + total_names} bytes")
    print(f"{'='*60}")


def print_stats(creatures, selected_indices):
    """Print statistics about the selection."""
    selected = [(i, creatures[i]) for i in sorted(selected_indices) if i < len(creatures)]

    # Count by dungeon level
    by_dlvl = {}
    for idx, cr in selected:
        dl = cr['dlvl']
        by_dlvl[dl] = by_dlvl.get(dl, 0) + 1

    print("Creatures per dungeon level:")
    for dl in sorted(by_dlvl.keys()):
        bar = "#" * by_dlvl[dl]
        print(f"  DL {dl:>2}: {by_dlvl[dl]:>2} {bar}")

    # Attack type coverage
    atk_types = set()
    for idx, cr in selected:
        for a in cr['attacks']:
            if a['dice'] > 0:
                atk_types.add(a['type'])
    print(f"\nAttack types used: {sorted(atk_types)}")
    for t in sorted(atk_types):
        print(f"  {t}: {ATK_NAMES.get(t, '?')}")

    # Speed distribution
    speeds = {0: 0, 1: 0, 2: 0}
    for idx, cr in selected:
        speeds[cr['c64_speed'] & SPEED_MASK] += 1
    print(f"\nSpeed distribution: slow={speeds[0]}, normal={speeds[1]}, fast={speeds[2]}")

    # Flag distribution
    flag_counts = {'ATTACK_ONLY': 0, 'UNDEAD': 0, 'INFRA': 0}
    for idx, cr in selected:
        if cr['c64_mflags'] & CF_ATTACK_ONLY: flag_counts['ATTACK_ONLY'] += 1
        if cr['c64_mflags'] & CF_UNDEAD: flag_counts['UNDEAD'] += 1
        if cr['c64_mflags'] & CF_INFRA: flag_counts['INFRA'] += 1
    print(f"\nFlag counts: {flag_counts}")

    # Spellcaster count
    casters = sum(1 for _, cr in selected if cr['c64_spell_chance'] > 0)
    print(f"Spellcasters: {casters}")

    # Tier sizes summary
    print(f"\nTier data sizes:")
    for tier_idx, tier in enumerate(TIERS):
        members = [(idx, cr) for idx, cr in selected
                   if tier_idx in cr['tiers']]
        soa_bytes = len(members) * TIER_BYTES_PER_CREATURE
        name_bytes = sum(len(cr['name']) + 1 for _, cr in members)
        print(f"  {tier['name']}: {len(members)} creatures, "
              f"{soa_bytes + name_bytes} bytes "
              f"({'resident' if tier['resident'] else 'loadable'})")
    print(f"  Total unique: {len(selected)} creatures")


# ============================================================
# Assembly output — generate .s files per tier
# ============================================================

# SoA field definitions: (array_label, data_key, comment)
SOA_FIELDS = [
    ("cr_display",      "c64_display",      "Display character (screen code)"),
    ("cr_color",        "c64_color",        "Color code"),
    ("cr_speed",        "c64_speed",        "Speed (bits 0-1: 0=slow, 1=normal, 2=fast) | random-move bits 3-5 | max HP bit 7"),
    ("cr_mflags",       "c64_mflags",       "Monster flags"),
    ("cr_level",        "dlvl",             "Dungeon level"),
    ("cr_hd_num",       "hd_num",           "Hit dice count"),
    ("cr_hd_sides",     "hd_sides",         "Hit dice sides"),
    ("cr_ac",           "ac",               "Armor class"),
    ("cr_sleep",        "sleep",            "Sleep counter"),
    ("cr_aaf",          "c64_aaf",          "Area affect radius + door flag (bit7)"),
    ("cr_xp_lo",        "c64_xp_lo",        "XP low byte"),
    ("cr_xp_hi",        "c64_xp_hi",        "XP high byte"),
    ("cr_atk0_type",    None,               "Attack 0 type"),
    ("cr_atk0_dice",    None,               "Attack 0 dice count"),
    ("cr_atk0_sides",   None,               "Attack 0 dice sides"),
    ("cr_atk1_type",    None,               "Attack 1 type"),
    ("cr_atk1_dice",    None,               "Attack 1 dice count"),
    ("cr_atk1_sides",   None,               "Attack 1 dice sides"),
    ("cr_spell_chance", "c64_spell_chance",  "Spell chance (0-100)"),
    ("cr_spell_flags",  "c64_spell_flags",   "Spell flags bitmask"),
    ("cr_treasure",     "c64_treasure",      "Treasure flags: Umoria CMOVE bits 24-30 (carry obj/gold, 60%, 90%, 1d2, 2d2, 4d2/VMS 4d3)"),
]

# Bytes per creature in a tier file: the SoA arrays plus the name lo/hi tables.
TIER_BYTES_PER_CREATURE = len(SOA_FIELDS) + 2

def get_soa_value(cr, label, key):
    """Get the SoA byte value for a creature field."""
    if key is not None:
        return min(255, cr[key])
    # Attack fields need special handling
    if label == "cr_atk0_type":
        return cr['attacks'][0]['type']
    if label == "cr_atk0_dice":
        return cr['attacks'][0]['dice']
    if label == "cr_atk0_sides":
        return cr['attacks'][0]['sides']
    if label == "cr_atk1_type":
        return cr['attacks'][1]['type']
    if label == "cr_atk1_dice":
        return cr['attacks'][1]['dice']
    if label == "cr_atk1_sides":
        return cr['attacks'][1]['sides']
    return 0


def generate_asm_tier(tier_idx, tier, creatures, selected_indices, outdir):
    """Generate a .s file for one tier."""
    # Collect tier members sorted by dungeon level, then by umoria index
    members = []
    for idx in tier_order(selected_indices):
        cr = creatures[idx]
        if tier_idx in cr['tiers']:
            members.append((idx, cr))

    count = len(members)
    if count == 0:
        return

    tier_name = f"tier{tier_idx}"
    filename = os.path.join(outdir, f"{tier_name}.s")

    lines = []
    lines.append(f"// {tier['name']} — creature data")
    lines.append(f"// Generated by parse_creatures.py — DO NOT EDIT")
    lines.append(f"// {count} creatures, dlvl {tier['min_dlvl']}-{tier['max_dlvl']}")
    lines.append(f"//")
    lines.append(f"// Creature index map (tier-local → name):")
    for i, (idx, cr) in enumerate(members):
        lines.append(f"//   {i:>3}: [{idx:>3}] DL{cr['dlvl']:>2} {cr['name']}")
    lines.append("")

    # Header
    lines.append(f".const TIER_COUNT = {count}")
    lines.append(f".const TIER_MIN_DLVL = {tier['min_dlvl']}")
    lines.append(f".const TIER_MAX_DLVL = {tier['max_dlvl']}")
    lines.append("")

    # SoA arrays
    for label, key, comment in SOA_FIELDS:
        values = [get_soa_value(cr, label, key) for _, cr in members]
        lines.append(f"// {comment}")
        lines.append(f"{tier_name}_{label}:")
        # Format as .byte rows of 16
        for row_start in range(0, len(values), 16):
            row = values[row_start:row_start+16]
            hex_vals = ", ".join(f"${v:02x}" for v in row)
            lines.append(f"    .byte {hex_vals}")
        lines.append("")

    # Name pointer tables (lo/hi)
    lines.append("// Name string pointers")
    lines.append(f"{tier_name}_cr_name_lo:")
    for row_start in range(0, count, 8):
        row = [f"<{tier_name}_crn_{i}" for i in range(row_start, min(row_start+8, count))]
        lines.append(f"    .byte {', '.join(row)}")

    lines.append(f"{tier_name}_cr_name_hi:")
    for row_start in range(0, count, 8):
        row = [f">{tier_name}_crn_{i}" for i in range(row_start, min(row_start+8, count))]
        lines.append(f"    .byte {', '.join(row)}")
    lines.append("")

    # Name strings (screen codes, null-terminated)
    lines.append('.encoding "screencode_mixed"')
    lines.append("// Name strings (screen codes, null-terminated)")
    for i, (idx, cr) in enumerate(members):
        # Use original mixed-case name (e.g., "Kobold" not "KOBOLD")
        lines.append(f'{tier_name}_crn_{i}: .text "{cr["name"]}" ; .byte 0')
    lines.append("")

    # Size assertion
    lines.append(f"// End marker for size calculation")
    lines.append(f"{tier_name}_data_end:")
    lines.append(f".print \"{tier['name']}: \" + ({tier_name}_data_end - {tier_name}_cr_display) + \" bytes\"")
    lines.append("")

    with open(filename, 'w') as f:
        f.write('\n'.join(lines))

    return filename, count


def generate_asm(creatures, selected_indices):
    """Generate all tier .s files."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.join(script_dir, '..', 'platforms', 'commodore', 'c64', 'creature_data')
    os.makedirs(outdir, exist_ok=True)

    print(f"Generating assembly data in {os.path.abspath(outdir)}/\n")

    for tier_idx, tier in enumerate(TIERS):
        result = generate_asm_tier(tier_idx, tier, creatures, selected_indices, outdir)
        if result:
            filename, count = result
            print(f"  {os.path.basename(filename)}: {count} creatures")

    # Generate a summary include file
    summary_path = os.path.join(outdir, "creature_tiers.s")
    with open(summary_path, 'w') as f:
        f.write("// Creature tier configuration\n")
        f.write("// Generated by parse_creatures.py — DO NOT EDIT\n\n")
        f.write(f".const TOTAL_TIERS = {len(TIERS)}\n")
        for tier_idx, tier in enumerate(TIERS):
            members = [idx for idx in tier_order(selected_indices)
                       if tier_idx in creatures[idx]['tiers']]
            f.write(f".const TIER{tier_idx}_COUNT = {len(members)}\n")
            f.write(f".const TIER{tier_idx}_MIN_DLVL = {tier['min_dlvl']}\n")
            f.write(f".const TIER{tier_idx}_MAX_DLVL = {tier['max_dlvl']}\n")
            for local_idx, creature_idx in enumerate(members):
                if creatures[creature_idx]['name'] == "Balrog":
                    f.write(f".const CREATURE_BALROG = {local_idx}\n")
                    f.write(f".const CREATE_BALROG = {local_idx}\n")
                    f.write(f".const CREATURE_BALROG_TIER = {tier_idx}\n")
        f.write(f"\n// Tier file sizes (approximate, for REU allocation)\n")
        for tier_idx, tier in enumerate(TIERS):
            members = [(idx, creatures[idx]) for idx in tier_order(selected_indices)
                       if tier_idx in creatures[idx]['tiers']]
            soa = len(members) * TIER_BYTES_PER_CREATURE
            names = sum(len(cr['name']) + 1 for _, cr in members)
            f.write(f".const TIER{tier_idx}_SIZE = {soa + names}\n")

    print(f"  creature_tiers.s: tier configuration constants")
    sync_web(check_only=False)
    print(f"\nDone.")


WEB_TIER_LABELS = {
    0: "Tier 0 · Town (DL 0)",
    1: "Tier 1 · Shallow (DL 1–8)",
    2: "Tier 2 · Early (DL 5–15)",
    3: "Tier 3 · Mid (DL 11–25)",
    4: "Tier 4 · Deep (DL 20–100)",
}

WEB_SOA_KEYS = [
    ("cr_display",      "display"),
    ("cr_color",        "color"),
    ("cr_speed",        "speed"),
    ("cr_mflags",       "mflags"),
    ("cr_level",        "level"),
    ("cr_hd_num",       "hd_num"),
    ("cr_hd_sides",     "hd_sides"),
    ("cr_ac",           "ac"),
    ("cr_sleep",        "sleep"),
    ("cr_aaf",          "aaf"),
    ("cr_xp_lo",        "xp_lo"),
    ("cr_xp_hi",        "xp_hi"),
    ("cr_atk0_type",    "atk0_type"),
    ("cr_atk0_dice",    "atk0_dice"),
    ("cr_atk0_sides",   "atk0_sides"),
    ("cr_atk1_type",    "atk1_type"),
    ("cr_atk1_dice",    "atk1_dice"),
    ("cr_atk1_sides",   "atk1_sides"),
    ("cr_spell_chance", "spell_chance"),
    ("cr_spell_flags",  "spell_flags"),
    ("cr_treasure",     "treasure"),
]

WEB_BEGIN_MARKER = "// BEGIN GENERATED_CREATURE_DATA"
WEB_END_MARKER = "// END GENERATED_CREATURE_DATA"


def parse_asm_tier_file(filepath, tier_idx):
    """Parse a committed tier{N}.s file into its exact SoA arrays and metadata."""
    with open(filepath, "r", encoding="utf-8") as f:
        text = f.read()

    count_m = re.search(r"\.const\s+TIER_COUNT\s*=\s*(\d+)", text)
    if not count_m:
        raise ValueError(f"{filepath}: missing .const TIER_COUNT")
    count = int(count_m.group(1))

    # Extract Umoria IDs from header comments: //   0: [ 16] DL 1 Kobold
    ids = [int(m.group(2)) for m in re.finditer(r"^//\s+(\d+):\s+\[\s*(\d+)\]\s+DL\s*\d+\s+", text, re.MULTILINE)]
    if len(ids) != count:
        raise ValueError(f"{filepath}: expected {count} header index comments, found {len(ids)}")

    # Extract names from tierN_crn_<i>: .text "..."
    prefix = f"tier{tier_idx}"
    names = [m.group(2) for m in re.finditer(rf'^{prefix}_crn_(\d+):\s*\.text\s+"([^"]+)"', text, re.MULTILINE)]
    if len(names) != count:
        raise ValueError(f"{filepath}: expected {count} .text name entries, found {len(names)}")

    arrays = {}
    for asm_field, js_key in WEB_SOA_KEYS:
        label = f"{prefix}_{asm_field}:"
        pos = text.find(label)
        if pos < 0:
            raise ValueError(f"{filepath}: missing label {label}")
        rest = text[pos + len(label):]
        vals = []
        for line in rest.splitlines():
            s = line.strip()
            if not s:
                if vals:
                    break
                continue
            if s.startswith("//"):
                continue
            if not s.startswith(".byte"):
                break
            byte_part = s[len(".byte"):].split("//")[0]
            for tok in byte_part.split(","):
                tok = tok.strip()
                if not tok:
                    continue
                if tok.startswith("$"):
                    vals.append(int(tok[1:], 16))
                else:
                    vals.append(int(tok, 10))
        if len(vals) != count:
            raise ValueError(f"{filepath} {label}: expected {count} bytes, found {len(vals)}")
        arrays[js_key] = vals

    return {
        "tier": tier_idx,
        "label": WEB_TIER_LABELS[tier_idx],
        "ids": ids,
        "names": names,
        "arrays": arrays,
    }


def render_web_tiers_block(tier_dir):
    """Render the const TIERS_RAW = [...] JS block from tier0.s..tier4.s."""
    import json
    lines = [WEB_BEGIN_MARKER, "const TIERS_RAW = ["]
    for tier_idx in range(len(TIERS)):
        tier_path = os.path.join(tier_dir, f"tier{tier_idx}.s")
        t = parse_asm_tier_file(tier_path, tier_idx)
        lines.append("  {")
        lines.append(f'    tier: {t["tier"]}, label: {json.dumps(t["label"], ensure_ascii=False)},')
        lines.append(f'    ids: [{",".join(str(x) for x in t["ids"])}],')
        lines.append(f'    names: [{",".join(json.dumps(n, ensure_ascii=False) for n in t["names"])}],')
        for idx, (_, js_key) in enumerate(WEB_SOA_KEYS):
            vals = t["arrays"][js_key]
            formatted = ",".join(f"0x{v:02x}" for v in vals)
            comma = "," if idx + 1 < len(WEB_SOA_KEYS) else ""
            lines.append(f"    {js_key}: [{formatted}]{comma}")
        close = "  }," if tier_idx + 1 < len(TIERS) else "  }"
        lines.append(close)
    lines.append("];")
    lines.append(WEB_END_MARKER)
    return "\n".join(lines)


def sync_web(check_only=False):
    """Sync or verify docs/monsters.html against platforms/commodore/c64/creature_data/tier0.s..tier4.s."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, ".."))
    tier_dir = os.path.join(repo_root, "platforms", "commodore", "c64", "creature_data")
    html_path = os.path.join(repo_root, "docs", "monsters.html")

    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()

    start = html.find(WEB_BEGIN_MARKER)
    end = html.find(WEB_END_MARKER)
    if start < 0 or end < 0 or end < start:
        print(f"ERROR: {html_path} is missing {WEB_BEGIN_MARKER} / {WEB_END_MARKER} markers", file=sys.stderr)
        sys.exit(1)
    end += len(WEB_END_MARKER)

    rendered = render_web_tiers_block(tier_dir)
    current = html[start:end]

    if check_only:
        if current != rendered:
            print(
                "ERROR: docs/monsters.html creature data is out of sync with "
                "platforms/commodore/c64/creature_data/tier0.s..tier4.s.\n"
                "Run: python3 tools/parse_creatures.py --sync-web",
                file=sys.stderr,
            )
            sys.exit(1)
        return

    if current != rendered:
        new_html = html[:start] + rendered + html[end:]
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(new_html)
        print("Updated docs/monsters.html from tier0.s..tier4.s")


if __name__ == "__main__":
    main()
