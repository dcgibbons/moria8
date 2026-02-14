#!/usr/bin/env python3
"""
Parse umoria creature data and generate C64 Moria creature roster.

Reads the umoria data_creatures.cpp source file, decodes all 279 creatures
and 215 attack types, maps to our SoA format, and outputs:
  1. Full roster summary
  2. Selected subset (~120 creatures for disk tiers)
  3. Tier assignments with overlapping level ranges

Usage:
  python3 tools/parse_creatures.py [--all | --selected | --tiers | --asm]

  --all       Show all 279 umoria creatures
  --selected  Show the ~120 selected creatures (default)
  --tiers     Show tier breakdown with creature counts
  --asm       Generate assembly data (for R3.5.2)
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

# Our C64 attack effect types
ATK_NORMAL    = 0
ATK_POISON    = 1
ATK_PARALYZE  = 2
ATK_FEAR      = 3
ATK_CONFUSE   = 4
ATK_CORRODE   = 5
ATK_AGGRAVATE = 6
ATK_BLIND     = 7
ATK_STEAL_GOLD= 8
ATK_DRAIN_XP  = 9
ATK_FIRE      = 10
ATK_COLD      = 11

ATK_NAMES = {
    0: "NORMAL", 1: "POISON", 2: "PARALYZE", 3: "FEAR",
    4: "CONFUSE", 5: "CORRODE", 6: "AGGRAVATE", 7: "BLIND",
    8: "STEAL_GOLD", 9: "DRAIN_XP", 10: "FIRE", 11: "COLD",
}

UMORIA_TO_C64_ATK = {
    1:  ATK_NORMAL,     # Normal
    2:  ATK_POISON,     # Poison STR
    3:  ATK_CONFUSE,    # Confusion
    4:  ATK_FEAR,       # Fear
    5:  ATK_FIRE,       # Fire
    6:  ATK_CORRODE,    # Acid
    7:  ATK_COLD,       # Cold
    8:  ATK_NORMAL,     # Lightning → normal (simplified)
    9:  ATK_CORRODE,    # Corrosion
    10: ATK_BLIND,      # Blindness
    11: ATK_PARALYZE,   # Paralysis
    12: ATK_STEAL_GOLD, # Steal Money
    13: ATK_NORMAL,     # Steal Object → normal (simplified)
    14: ATK_POISON,     # Poison
    15: ATK_POISON,     # Lose DEX → poison (simplified)
    16: ATK_POISON,     # Lose CON → poison (simplified)
    17: ATK_NORMAL,     # Lose INT → normal (simplified)
    18: ATK_NORMAL,     # Lose WIS → normal (simplified)
    19: ATK_DRAIN_XP,   # Lose experience
    20: ATK_AGGRAVATE,  # Aggravation
    21: ATK_NORMAL,     # Disenchant → normal (simplified)
    22: ATK_NORMAL,     # Eat food → normal (simplified)
    23: ATK_NORMAL,     # Eat light → normal (simplified)
    24: ATK_NORMAL,     # Eat charges → normal (simplified)
    99: ATK_NORMAL,     # Blank
}

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
CF_INVISIBLE   = 0x04  # Invisible
CF_PASS_WALL   = 0x08  # Can pass through walls

def map_mflags(cmove, cdefense, name):
    """Map umoria CMOVE/CDEFENSE flags to our cr_mflags byte."""
    flags = 0
    # Attack only = CMOVE bit 0 set (0x01) and bit 1 clear (0x02)
    move_bits = cmove & 0x3F
    if move_bits == 0x01:  # Move only to attack (stationary)
        flags |= CF_ATTACK_ONLY
    # Undead check: CDEFENSE bit 3 (0x0008) = hurt by slay undead
    if cdefense & 0x0008:
        flags |= CF_UNDEAD
    # Invisible: CMOVE bit 16 (0x10000)
    if cmove & 0x00010000:
        flags |= CF_INVISIBLE
    return flags

# ============================================================
# Spell mapping
# ============================================================
# Our spell flags
MSF_BOLT    = 0x01
MSF_BREATH  = 0x02
MSF_SUMMON  = 0x04
MSF_TELEPORT= 0x08
MSF_BLIND   = 0x10
MSF_CONFUSE = 0x20
MSF_HEAL    = 0x40
MSF_FEAR    = 0x80  # Future expansion

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
    if spell_word & 0x000080:  # Cause light wound
        flags |= MSF_BOLT
    if spell_word & 0x000100:  # Cause serious wound
        flags |= MSF_BOLT
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
    # Heal: not explicitly in umoria spell flags for most creatures
    # But some creatures have it via special logic — we'll add manually

    return chance, flags

# ============================================================
# Display character mapping (ASCII → C64 screen code)
# ============================================================
def char_to_screencode(ch):
    """Convert ASCII character to C64 screen code (uppercase mode)."""
    if 'A' <= ch <= 'Z':
        return ord(ch) - ord('A') + 1
    if 'a' <= ch <= 'z':
        return ord(ch) - ord('a') + 1  # Same as uppercase in screen codes
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

    # Find source file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    src_path = os.path.join(script_dir, '..', 'umoria_creatures.cpp')
    if not os.path.exists(src_path):
        src_path = '/tmp/umoria_creatures.cpp'
    if not os.path.exists(src_path):
        print(f"ERROR: Cannot find umoria_creatures.cpp", file=sys.stderr)
        print(f"  Copy from: https://raw.githubusercontent.com/dungeons-of-moria/umoria/master/src/data_creatures.cpp", file=sys.stderr)
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
                decoded_atks.append({
                    'type': UMORIA_TO_C64_ATK.get(atk['type'], ATK_NORMAL),
                    'dice': atk['dice'],
                    'sides': atk['sides'],
                })
        cr['attacks'] = decoded_atks
        cr['c64_speed'] = map_speed(cr['speed'])
        cr['c64_color'] = assign_color(cr['name'])
        cr['c64_display'] = char_to_screencode(cr['sprite'])
        cr['c64_mflags'] = map_mflags(cr['cmove'], cr['cdefense'], cr['name'])
        spell_chance, spell_flags = map_spells(cr['spell'])
        cr['c64_spell_chance'] = spell_chance
        cr['c64_spell_flags'] = spell_flags
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

    if mode == "all":
        print_all(creatures, selected_indices)
    elif mode == "selected":
        print_selected(creatures, selected_indices)
    elif mode == "tiers":
        print_tiers(creatures, selected_indices)
    elif mode == "stats":
        print_stats(creatures, selected_indices)
    else:
        print(f"Unknown mode: {mode}")
        print("Usage: parse_creatures.py [--all | --selected | --tiers | --stats]")


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
        soa_bytes = len(members) * 22  # 22 SoA arrays per creature
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
    total_soa = len(all_members) * 22
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
        speeds[cr['c64_speed']] += 1
    print(f"\nSpeed distribution: slow={speeds[0]}, normal={speeds[1]}, fast={speeds[2]}")

    # Flag distribution
    flag_counts = {'ATTACK_ONLY': 0, 'UNDEAD': 0, 'INVISIBLE': 0}
    for idx, cr in selected:
        if cr['c64_mflags'] & CF_ATTACK_ONLY: flag_counts['ATTACK_ONLY'] += 1
        if cr['c64_mflags'] & CF_UNDEAD: flag_counts['UNDEAD'] += 1
        if cr['c64_mflags'] & CF_INVISIBLE: flag_counts['INVISIBLE'] += 1
    print(f"\nFlag counts: {flag_counts}")

    # Spellcaster count
    casters = sum(1 for _, cr in selected if cr['c64_spell_chance'] > 0)
    print(f"Spellcasters: {casters}")

    # Tier sizes summary
    print(f"\nTier data sizes:")
    for tier_idx, tier in enumerate(TIERS):
        members = [(idx, cr) for idx, cr in selected
                   if tier_idx in cr['tiers']]
        soa_bytes = len(members) * 22
        name_bytes = sum(len(cr['name']) + 1 for _, cr in members)
        print(f"  {tier['name']}: {len(members)} creatures, "
              f"{soa_bytes + name_bytes} bytes "
              f"({'resident' if tier['resident'] else 'loadable'})")
    print(f"  Total unique: {len(selected)} creatures")


if __name__ == "__main__":
    main()
