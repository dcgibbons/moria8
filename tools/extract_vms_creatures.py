#!/usr/bin/env python3
"""Extract the authoritative 279-species VMS Moria 4.8 creature spec.

Reads VMS Moria 4.8's c_list (from an explicit --vms-values CLI path to
values.inc; no default external path) and writes deterministic JSON to
platforms/shared/catalog/monster_catalog_spec.json in exact Moria8 catalog
index order (0..278, matching platforms/shared/catalog/catalog_fields.s).

Usage:
  python3 -B tools/extract_vms_creatures.py --vms-values <path-to-values.inc> [--audit]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_creatures as pc  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SPEC_OUT = REPO_ROOT / "platforms" / "shared" / "catalog" / "monster_catalog_spec.json"
DEFAULT_CATALOG_FIELDS = REPO_ROOT / "platforms" / "shared" / "catalog" / "catalog_fields.s"
DEFAULT_CATALOG_INDEX = REPO_ROOT / "platforms" / "shared" / "catalog" / "catalog_index.s"
DEFAULT_CATALOG_NAMES = REPO_ROOT / "platforms" / "shared" / "catalog" / "catalog_names.s"

PINNED_VMS_COMMIT = "adce6c8898ea280181f1277b47f104e2b1f387a8"
CREATURE_COUNT = 279
TOWN_CREATURE_COUNT = 8
MAX_MONS_LEVEL = 40
WIN_MON_TOT = 2
MAX_ATTACKS = 4
MAX_ATTACK_SIDES = 14
MAX_ATTACK_ADESC = 19

VALID_ADTYPES = frozenset({0, 99} | set(range(1, 25)))

# VMS spellings mapped by tools/build_catalog.py for Moria8 display names.
ALIASES = {
    "Giant White Lice": "Giant White Louse",
    "Giant Black Lice": "Giant Black Louse",
    "Large Grey Snake": "Large Green Snake",
    "Urik-Hai Orc": "Uruk-Hai Orc",
    "Quythulg": "Quylthulg",
    "Ogre Magi": "Ogre Mage",
}

# Raw VMS spell word bit masks (source/include/creature.inc cast_spell).
VMS_SPELL_FREQ_MASK = 0x0000000F
VMS_SPELL_TELE_SHORT = 0x00000010     # 5: Teleport short (blink)
VMS_SPELL_TELE_LONG = 0x00000020      # 6: Teleport long
VMS_SPELL_TELE_TO = 0x00000040        # 7: Teleport player to monster
VMS_SPELL_LIGHT_WOUND = 0x00000080    # 8: Cause light wound
VMS_SPELL_SERIOUS_WOUND = 0x00000100  # 9: Cause serious wound
VMS_SPELL_HOLD_PERSON = 0x00000200    # 10: Hold person
VMS_SPELL_BLIND = 0x00000400          # 11: Cause blindness
VMS_SPELL_CONFUSE = 0x00000800        # 12: Cause confusion
VMS_SPELL_FEAR = 0x00001000           # 13: Cause fear
VMS_SPELL_SUMMON_MON = 0x00002000     # 14: Summon monster
VMS_SPELL_SUMMON_UND = 0x00004000     # 15: Summon undead
VMS_SPELL_SLOW_PERSON = 0x00008000    # 16: Slow person
VMS_SPELL_DRAIN_MANA = 0x00010000     # 17: Drain mana
VMS_SPELL_BREATH_LIGHT = 0x00080000   # 20: Breath lightning
VMS_SPELL_BREATH_GAS = 0x00100000     # 21: Breath poison gas
VMS_SPELL_BREATH_ACID = 0x00200000    # 22: Breath acid
VMS_SPELL_BREATH_FROST = 0x00400000   # 23: Breath frost
VMS_SPELL_BREATH_FIRE = 0x00800000    # 24: Breath fire
VMS_SPELL_BREATH_MASK = 0x00F80000
VMS_SPELL_KNOWN_MASK = (
    VMS_SPELL_FREQ_MASK
    | VMS_SPELL_TELE_SHORT
    | VMS_SPELL_TELE_LONG
    | VMS_SPELL_TELE_TO
    | VMS_SPELL_LIGHT_WOUND
    | VMS_SPELL_SERIOUS_WOUND
    | VMS_SPELL_HOLD_PERSON
    | VMS_SPELL_BLIND
    | VMS_SPELL_CONFUSE
    | VMS_SPELL_FEAR
    | VMS_SPELL_SUMMON_MON
    | VMS_SPELL_SUMMON_UND
    | VMS_SPELL_SLOW_PERSON
    | VMS_SPELL_DRAIN_MANA
    | VMS_SPELL_BREATH_MASK
)

# Phase 5 cr_spell_flags2 bit layout (#360 / #368):
#   bits 0..4: extended monster spells
#   bits 5..7: extended cmove flags
MSF2_BLINK = 0x01
MSF2_TELE_SELF = 0x02
MSF2_SUMMON_UNDEAD = 0x04
MSF2_SLOW = 0x08
MSF2_DRAIN_MANA = 0x10
MSF2_CM_PHASE = 0x20
MSF2_CM_EATS_OTHER = 0x40
MSF2_CM_PICKS_UP = 0x80

# Raw VMS cmove bit masks (source/include/creature.inc).
VMS_CM_ATTACK_ONLY = 0x00000001
VMS_CM_MOVE_NORMAL = 0x00000002
VMS_CM_ONLY_MAGIC = 0x00000004
VMS_CM_RANDOM_MASK = 0x00000038
VMS_CM_20_RANDOM = 0x00000008
VMS_CM_40_RANDOM = 0x00000010
VMS_CM_75_RANDOM = 0x00000020
VMS_CM_UNUSED_80 = 0x00000080  # Set on #183 Black Mold & #211 Shimmering Mold upstream; unused by VMS AI
VMS_CM_INVISIBLE = 0x00010000
VMS_CM_OPEN_DOOR = 0x00020000
VMS_CM_PHASE = 0x00040000
VMS_CM_EATS_OTHER = 0x00080000
VMS_CM_PICKS_UP = 0x00100000
VMS_CM_MULTIPLY = 0x00200000
VMS_CM_CARRY_OBJ = 0x01000000
VMS_CM_CARRY_GOLD = 0x02000000
VMS_CM_TREASURE_MASK = 0x7F000000
VMS_CM_WIN = 0x80000000
VMS_CM_KNOWN_MASK = (
    VMS_CM_ATTACK_ONLY
    | VMS_CM_MOVE_NORMAL
    | VMS_CM_ONLY_MAGIC
    | VMS_CM_RANDOM_MASK
    | VMS_CM_UNUSED_80
    | VMS_CM_INVISIBLE
    | VMS_CM_OPEN_DOOR
    | VMS_CM_PHASE
    | VMS_CM_EATS_OTHER
    | VMS_CM_PICKS_UP
    | VMS_CM_MULTIPLY
    | VMS_CM_TREASURE_MASK
    | VMS_CM_WIN
)

# Raw VMS cdefense bit masks (source/include/constants.inc / spells.inc).
VMS_CD_DRAGON = 0x0001
VMS_CD_ANIMAL = 0x0002
VMS_CD_EVIL = 0x0004
VMS_CD_UNDEAD = 0x0008
VMS_CD_FROST = 0x0010
VMS_CD_FIRE = 0x0020
VMS_CD_POISON = 0x0040
VMS_CD_ACID = 0x0080
VMS_CD_LIGHT = 0x0100
VMS_CD_STONE = 0x0200
VMS_CD_NO_SLEEP = 0x1000
VMS_CD_INFRA = 0x2000
VMS_CD_MAX_HP = 0x4000
VMS_CD_KNOWN_MASK = (
    VMS_CD_DRAGON
    | VMS_CD_ANIMAL
    | VMS_CD_EVIL
    | VMS_CD_UNDEAD
    | VMS_CD_FROST
    | VMS_CD_FIRE
    | VMS_CD_POISON
    | VMS_CD_ACID
    | VMS_CD_LIGHT
    | VMS_CD_STONE
    | VMS_CD_NO_SLEEP
    | VMS_CD_INFRA
    | VMS_CD_MAX_HP
)

# Phase 5 cr_cdefense 7-bit resistance/vulnerability mask (#360 / #368).
CDEF7_FROST = 0x01
CDEF7_FIRE = 0x02
CDEF7_POISON = 0x04
CDEF7_ACID = 0x08
CDEF7_LIGHT = 0x10
CDEF7_STONE = 0x20
CDEF7_NO_SLEEP = 0x40
CDEF_CM_INVISIBLE = 0x80  # Bit 7 spare in cr_cdefense (note: CF_UNDEAD owns $02 in cr_mflags)

ENTRY_RE = re.compile(
    r"\(\s*'((?:[^']|'')*)'\s*,"
    r"\s*%X'([0-9A-Fa-f]+)'\s*,"
    r"\s*%X'([0-9A-Fa-f]+)'\s*,"
    r"\s*%X'([0-9A-Fa-f]+)'\s*,"
    r"\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,"
    r"\s*'(.)'\s*,\s*'\s*(\d+)d(\d+)\s*'\s*,"
    r"\s*'([^']*)'\s*,\s*(\d+)\s*\)",
    re.S,
)


def pack_attack(adtype: int, adesc: int, dice: int, sides: int) -> tuple[int, int, int]:
    """Pack one VMS attack (adtype, adesc, dice, sides) into 3 Phase 5 bytes (#360).

    - type_byte: bits 0..6 = adtype (0..24 or 99), bit 7 = adesc[0]
    - dice_byte: bits 0..7 = dice (0..255)
    - sides_verb_byte: bits 0..3 = sides (0..14), bits 4..7 = adesc[4:1] (0..9)
    """
    if adtype not in VALID_ADTYPES:
        raise ValueError(f"Invalid adtype: {adtype}")
    if not (0 <= adesc <= MAX_ATTACK_ADESC):
        raise ValueError(f"Invalid adesc: {adesc}")
    if not (0 <= dice <= 255):
        raise ValueError(f"Invalid dice: {dice}")
    if not (0 <= sides <= MAX_ATTACK_SIDES):
        raise ValueError(f"Invalid sides: {sides} (exceeds {MAX_ATTACK_SIDES})")
    if adtype in (0, 99) and (adesc != 0 or dice != 0 or sides != 0):
        raise ValueError(f"Non-zero fields on blank attack: {(adtype, adesc, dice, sides)}")
    type_byte = (adtype & 0x7F) | ((adesc & 0x01) << 7)
    dice_byte = dice & 0xFF
    sides_verb_byte = (sides & 0x0F) | (((adesc >> 1) & 0x0F) << 4)
    return (type_byte, dice_byte, sides_verb_byte)


def unpack_attack(type_byte: int, dice_byte: int, sides_verb_byte: int) -> tuple[int, int, int, int]:
    """Unpack 3 Phase 5 attack bytes back to (adtype, adesc, dice, sides)."""
    adtype = type_byte & 0x7F
    adesc = ((type_byte >> 7) & 0x01) | (((sides_verb_byte >> 4) & 0x0F) << 1)
    dice = dice_byte & 0xFF
    sides = sides_verb_byte & 0x0F
    return (adtype, adesc, dice, sides)


def pack_spells_and_cmove_ext(spells: int, cmove: int) -> tuple[int, int, int]:
    """Pack raw VMS 32-bit spells + extended cmove bits into (spell_chance, spell_flags, spell_flags2)."""
    if spells & ~VMS_SPELL_KNOWN_MASK:
        raise ValueError(f"Unknown VMS spell bits in 0x{spells:08X}")
    if cmove & ~VMS_CM_KNOWN_MASK:
        raise ValueError(f"Unknown VMS cmove bits in 0x{cmove:08X}")

    freq = spells & VMS_SPELL_FREQ_MASK
    bkind = pc.breath_kind(spells)
    spell_chance = freq | (bkind << pc.MS_BREATH_SHIFT) | (pc.MS_HOLD if (spells & VMS_SPELL_HOLD_PERSON) else 0)

    spell_flags = 0
    if spells & VMS_SPELL_LIGHT_WOUND:
        spell_flags |= pc.MSF_WOUND_LIGHT
    if spells & VMS_SPELL_BREATH_MASK:
        spell_flags |= pc.MSF_BREATH
    if spells & VMS_SPELL_SUMMON_MON:
        spell_flags |= pc.MSF_SUMMON
    if spells & VMS_SPELL_TELE_TO:
        spell_flags |= pc.MSF_TELEPORT
    if spells & VMS_SPELL_BLIND:
        spell_flags |= pc.MSF_BLIND
    if spells & VMS_SPELL_CONFUSE:
        spell_flags |= pc.MSF_CONFUSE
    if spells & VMS_SPELL_SERIOUS_WOUND:
        spell_flags |= pc.MSF_WOUND_SERIOUS
    if spells & VMS_SPELL_FEAR:
        spell_flags |= pc.MSF_FEAR

    spell_flags2 = 0
    if spells & VMS_SPELL_TELE_SHORT:
        spell_flags2 |= MSF2_BLINK
    if spells & VMS_SPELL_TELE_LONG:
        spell_flags2 |= MSF2_TELE_SELF
    if spells & VMS_SPELL_SUMMON_UND:
        spell_flags2 |= MSF2_SUMMON_UNDEAD
    if spells & VMS_SPELL_SLOW_PERSON:
        spell_flags2 |= MSF2_SLOW
    if spells & VMS_SPELL_DRAIN_MANA:
        spell_flags2 |= MSF2_DRAIN_MANA
    if cmove & VMS_CM_PHASE:
        spell_flags2 |= MSF2_CM_PHASE
    if cmove & VMS_CM_EATS_OTHER:
        spell_flags2 |= MSF2_CM_EATS_OTHER
    if cmove & VMS_CM_PICKS_UP:
        spell_flags2 |= MSF2_CM_PICKS_UP

    return (spell_chance, spell_flags, spell_flags2)


def unpack_spells_and_cmove_ext(spell_chance: int, spell_flags: int, spell_flags2: int) -> tuple[int, int]:
    """Unpack (spell_chance, spell_flags, spell_flags2) back to (vms_spells, cmove_ext_bits)."""
    spells = spell_chance & VMS_SPELL_FREQ_MASK
    if spell_chance & pc.MS_HOLD:
        spells |= VMS_SPELL_HOLD_PERSON

    bkind = (spell_chance >> pc.MS_BREATH_SHIFT) & 0x07
    has_breath_flag = bool(spell_flags & pc.MSF_BREATH)
    if has_breath_flag != (bkind != 0):
        raise ValueError(f"Inconsistent breath flags: spell_chance=0x{spell_chance:02X}, spell_flags=0x{spell_flags:02X}")
    if bkind == pc.MS_BREATH_ALL:
        spells |= VMS_SPELL_BREATH_MASK
    elif 1 <= bkind <= 5:
        spells |= dict((k, bit) for bit, k in pc.BREATH_KINDS)[bkind]
    elif bkind != 0:
        raise ValueError(f"Invalid breath kind: {bkind}")

    if spell_flags & pc.MSF_WOUND_LIGHT:
        spells |= VMS_SPELL_LIGHT_WOUND
    if spell_flags & pc.MSF_SUMMON:
        spells |= VMS_SPELL_SUMMON_MON
    if spell_flags & pc.MSF_TELEPORT:
        spells |= VMS_SPELL_TELE_TO
    if spell_flags & pc.MSF_BLIND:
        spells |= VMS_SPELL_BLIND
    if spell_flags & pc.MSF_CONFUSE:
        spells |= VMS_SPELL_CONFUSE
    if spell_flags & pc.MSF_WOUND_SERIOUS:
        spells |= VMS_SPELL_SERIOUS_WOUND
    if spell_flags & pc.MSF_FEAR:
        spells |= VMS_SPELL_FEAR

    if spell_flags2 & MSF2_BLINK:
        spells |= VMS_SPELL_TELE_SHORT
    if spell_flags2 & MSF2_TELE_SELF:
        spells |= VMS_SPELL_TELE_LONG
    if spell_flags2 & MSF2_SUMMON_UNDEAD:
        spells |= VMS_SPELL_SUMMON_UND
    if spell_flags2 & MSF2_SLOW:
        spells |= VMS_SPELL_SLOW_PERSON
    if spell_flags2 & MSF2_DRAIN_MANA:
        spells |= VMS_SPELL_DRAIN_MANA

    cmove_ext = 0
    if spell_flags2 & MSF2_CM_PHASE:
        cmove_ext |= VMS_CM_PHASE
    if spell_flags2 & MSF2_CM_EATS_OTHER:
        cmove_ext |= VMS_CM_EATS_OTHER
    if spell_flags2 & MSF2_CM_PICKS_UP:
        cmove_ext |= VMS_CM_PICKS_UP

    return (spells, cmove_ext)


def pack_cdefense7(cdefense: int) -> int:
    """Pack the 7 extended VMS cdefense vulnerability/immunity bits into bits 0..6."""
    if cdefense & ~VMS_CD_KNOWN_MASK:
        raise ValueError(f"Unknown VMS cdefense bits in 0x{cdefense:04X}")
    out = 0
    if cdefense & VMS_CD_FROST:
        out |= CDEF7_FROST
    if cdefense & VMS_CD_FIRE:
        out |= CDEF7_FIRE
    if cdefense & VMS_CD_POISON:
        out |= CDEF7_POISON
    if cdefense & VMS_CD_ACID:
        out |= CDEF7_ACID
    if cdefense & VMS_CD_LIGHT:
        out |= CDEF7_LIGHT
    if cdefense & VMS_CD_STONE:
        out |= CDEF7_STONE
    if cdefense & VMS_CD_NO_SLEEP:
        out |= CDEF7_NO_SLEEP
    return out


def unpack_cdefense(cdefense7: int, mflags: int, speed_byte: int) -> int:
    """Reconstruct raw 16-bit VMS cdefense from (cdefense7, mflags, speed_byte)."""
    cdef = 0
    if mflags & pc.CF_DRAGON:
        cdef |= VMS_CD_DRAGON
    if mflags & pc.CF_ANIMAL:
        cdef |= VMS_CD_ANIMAL
    if mflags & pc.CF_EVIL:
        cdef |= VMS_CD_EVIL
    if mflags & pc.CF_UNDEAD:
        cdef |= VMS_CD_UNDEAD
    if mflags & pc.CF_INFRA:
        cdef |= VMS_CD_INFRA
    if speed_byte & pc.CR_MAX_HP:
        cdef |= VMS_CD_MAX_HP

    if cdefense7 & CDEF7_FROST:
        cdef |= VMS_CD_FROST
    if cdefense7 & CDEF7_FIRE:
        cdef |= VMS_CD_FIRE
    if cdefense7 & CDEF7_POISON:
        cdef |= VMS_CD_POISON
    if cdefense7 & CDEF7_ACID:
        cdef |= VMS_CD_ACID
    if cdefense7 & CDEF7_LIGHT:
        cdef |= VMS_CD_LIGHT
    if cdefense7 & CDEF7_STONE:
        cdef |= VMS_CD_STONE
    if cdefense7 & CDEF7_NO_SLEEP:
        cdef |= VMS_CD_NO_SLEEP
    return cdef


def scale_hit_dice(hd_count: int, hd_sides: int) -> tuple[int, int]:
    """Scale (hd_count, hd_sides) into 8-bit (hd_num, hd_sides_scaled) preserving max HP."""
    k = next(
        factor
        for factor in range(1, 256)
        if hd_count % factor == 0 and (hd_count // factor) < 256 and (hd_sides * factor) < 256
    )
    return (hd_count // k, hd_sides * k)


def parse_vms_values(values_inc_path: Path) -> list[dict]:
    """Parse all 279 VMS Moria 4.8 c_list records from values.inc."""
    text = values_inc_path.read_text(encoding="utf-8", errors="replace")
    try:
        start = text.index("c_list  :=")
    except ValueError as exc:
        raise ValueError("Could not locate 'c_list  :=' in values.inc") from exc

    records: list[dict] = []
    for m in ENTRY_RE.finditer(text, start):
        idx = len(records)
        name = m.group(1).replace("''", "'")
        cmove = int(m.group(2), 16)
        spells = int(m.group(3), 16)
        cdefense = int(m.group(4), 16)
        sleep = int(m.group(5))
        mexp = int(m.group(6))
        aaf = int(m.group(7))
        ac = int(m.group(8))
        speed = int(m.group(9))
        cchar = m.group(10)
        hd_count = int(m.group(11))
        hd_sides = int(m.group(12))
        damage_str = m.group(13)
        level = int(m.group(14))

        parsed_atks: list[dict] = []
        for part in filter(None, (p.strip() for p in damage_str.split("|"))):
            tokens = part.split()
            if len(tokens) != 3 or "d" not in tokens[2]:
                raise ValueError(f"Malformed attack clause {part!r} on #{idx} {name}")
            adtype = int(tokens[0])
            adesc = int(tokens[1])
            dice_s, sides_s = tokens[2].split("d", 1)
            dice = int(dice_s)
            sides = int(sides_s)
            parsed_atks.append(
                {
                    "adtype": adtype,
                    "adesc": adesc,
                    "dice": dice,
                    "sides": sides,
                }
            )

        if len(parsed_atks) > MAX_ATTACKS:
            raise ValueError(f"Creature #{idx} {name} has {len(parsed_atks)} > {MAX_ATTACKS} attacks")
        while len(parsed_atks) < MAX_ATTACKS:
            parsed_atks.append({"adtype": 0, "adesc": 0, "dice": 0, "sides": 0})

        packed_attacks = [
            list(pack_attack(a["adtype"], a["adesc"], a["dice"], a["sides"]))
            for a in parsed_atks
        ]

        moria8_name = ALIASES.get(name, name)
        display_byte = pc.char_to_screencode(cchar)
        color_byte = pc.assign_color(moria8_name)
        speed_byte = (
            pc.map_speed(speed + 10)
            | (cmove & pc.CM_RANDOM_MOVE)
            | (pc.CR_MAX_HP if (cdefense & VMS_CD_MAX_HP) else 0)
        )
        mflags = pc.map_mflags(cmove, cdefense, name)
        hd_num_byte, hd_sides_byte = scale_hit_dice(hd_count, hd_sides)
        sleep_byte = min(255, sleep // 10)
        aaf_byte = min(127, aaf) | pc.map_doorflags(cmove)
        xp_lo = mexp & 0xFF
        xp_hi = (mexp >> 8) & 0xFF
        treasure = (cmove >> 24) & pc.CM_TREASURE
        spell_chance, spell_flags, spell_flags2 = pack_spells_and_cmove_ext(spells, cmove)
        cdefense7 = pack_cdefense7(cdefense)
        cm_invisible = bool(cmove & VMS_CM_INVISIBLE)
        cdefense_byte = cdefense7 | (CDEF_CM_INVISIBLE if cm_invisible else 0)

        records.append(
            {
                "index": idx,
                "name": name,
                "moria8_name": moria8_name,
                "cchar": cchar,
                "hd_count": hd_count,
                "hd_sides": hd_sides,
                "ac": ac,
                "sleep": sleep,
                "aaf": aaf,
                "speed": speed,
                "mexp": mexp,
                "level": level,
                "cmove": cmove,
                "cmove_hex": f"0x{cmove:08X}",
                "spells": spells,
                "spells_hex": f"0x{spells:08X}",
                "cdefense": cdefense,
                "cdefense_hex": f"0x{cdefense:04X}",
                "damage_str": damage_str,
                "attacks": parsed_atks,
                "display": display_byte,
                "color": color_byte,
                "speed_byte": speed_byte,
                "mflags": mflags,
                "hd_num": hd_num_byte,
                "hd_sides_scaled": hd_sides_byte,
                "sleep_byte": sleep_byte,
                "aaf_byte": aaf_byte,
                "xp_lo": xp_lo,
                "xp_hi": xp_hi,
                "spell_chance": spell_chance,
                "spell_flags": spell_flags,
                "spell_flags2": spell_flags2,
                "cdefense7": cdefense7,
                "cm_invisible": cm_invisible,
                "cdefense_byte": cdefense_byte,
                "treasure": treasure,
                "packed_attacks": packed_attacks,
            }
        )

        if len(records) > 1 and text[m.end():m.end() + 40].lstrip().startswith(");"):
            break

    if len(records) != CREATURE_COUNT:
        raise ValueError(f"Expected {CREATURE_COUNT} creatures in values.inc, parsed {len(records)}")

    levels = [r["level"] for r in records]
    if levels != sorted(levels):
        raise ValueError("VMS c_list records are not in non-decreasing level order")
    if max(r["level"] for r in records[:-WIN_MON_TOT]) > MAX_MONS_LEVEL:
        raise ValueError("Normal creature exceeds MAX_MONS_LEVEL")

    return records


def build_spec_document(creatures: list[dict]) -> dict:
    """Build the top-level JSON document for monster_catalog_spec.json."""
    return {
        "schema_version": 1,
        "source": {
            "upstream": "VMS Moria 4.8",
            "upstream_file": "source/include/values.inc",
            "pinned_commit": PINNED_VMS_COMMIT,
        },
        "constants": {
            "CREATURE_COUNT": CREATURE_COUNT,
            "TOWN_CREATURE_COUNT": TOWN_CREATURE_COUNT,
            "MAX_MONS_LEVEL": MAX_MONS_LEVEL,
            "WIN_MON_TOT": WIN_MON_TOT,
            "IGGY_INDEX": 277,
            "BALROG_INDEX": 278,
            "MAX_ATTACKS": MAX_ATTACKS,
            "MAX_ATTACK_SIDES": MAX_ATTACK_SIDES,
            "MAX_ATTACK_ADESC": MAX_ATTACK_ADESC,
            "SOA_CORE_FIELDS": 21,
            "SOA_EXT_FIELDS": 8,
            "SOA_TOTAL_FIELDS": 29,
        },
        "creatures": creatures,
    }


def parse_catalog_fields_asm(path: Path = DEFAULT_CATALOG_FIELDS) -> dict[str, list[int]]:
    """Parse platforms/shared/catalog/catalog_fields.s into {field_label: [279 ints]}."""
    arrays: dict[str, list[int]] = {}
    current: str | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("//", 1)[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            label = line[:-1].strip()
            if label.startswith("cat_cr_"):
                current = label[len("cat_"):]
                arrays[current] = []
            else:
                current = None
        elif line.startswith(".byte") and current is not None:
            payload = line[len(".byte"):].strip()
            for tok in payload.split(","):
                tok = tok.strip()
                if tok.startswith("$"):
                    arrays[current].append(int(tok[1:], 16))
                else:
                    arrays[current].append(int(tok, 10))
    return arrays


def parse_catalog_names_comments(path: Path = DEFAULT_CATALOG_NAMES) -> list[str]:
    """Extract the 279 comment names from platforms/shared/catalog/catalog_names.s."""
    names: list[str] = []
    pat = re.compile(r"^catn_(\d+):\s*\.byte\s+.*?//\s*(.+)$")
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        m = pat.match(raw_line.strip())
        if m:
            idx = int(m.group(1))
            if idx != len(names):
                raise ValueError(f"Out-of-order catn_{idx} in catalog_names.s")
            names.append(m.group(2).strip())
    return names


def legacy_catalog_row_from_spec(c: dict) -> dict[str, int]:
    """Recompute the pre-Phase-5 21-field catalog_fields.s row from a spec creature."""
    mapped_atks = []
    for a in c["attacks"]:
        kind = a["adtype"]
        if kind in (0, 99):
            mapped_atks.append({"type": 0, "dice": 0, "sides": 0})
            continue
        no_hp = kind in pc.NO_HP_ATTACK_TYPES
        mapped_atks.append(
            {
                "type": pc.UMORIA_TO_C64_ATK.get(kind, pc.ATK_NORMAL),
                "dice": 0 if no_hp else a["dice"],
                "sides": 0 if no_hp else a["sides"],
            }
        )
    kept = pc.select_attack_slots(mapped_atks)
    legacy_chance, legacy_flags = pc.map_spells(c["spells"])
    return {
        "cr_display": c["display"],
        "cr_color": c["color"],
        "cr_speed": c["speed_byte"],
        "cr_mflags": c["mflags"],
        "cr_level": c["level"],
        "cr_hd_num": c["hd_num"],
        "cr_hd_sides": c["hd_sides_scaled"],
        "cr_ac": c["ac"],
        "cr_sleep": c["sleep_byte"],
        "cr_aaf": c["aaf_byte"],
        "cr_xp_lo": c["xp_lo"],
        "cr_xp_hi": c["xp_hi"],
        "cr_atk0_type": kept[0]["type"],
        "cr_atk0_dice": kept[0]["dice"],
        "cr_atk0_sides": kept[0]["sides"],
        "cr_atk1_type": kept[1]["type"],
        "cr_atk1_dice": kept[1]["dice"],
        "cr_atk1_sides": kept[1]["sides"],
        "cr_spell_chance": legacy_chance,
        "cr_spell_flags": legacy_flags,
        "cr_treasure": c["treasure"],
    }


def phase5_catalog_row_from_spec(c: dict) -> dict[str, int]:
    """Recompute the Phase 5 21-field catalog_fields.s row from a spec creature."""
    atk0 = c["packed_attacks"][0]
    atk1 = c["packed_attacks"][1]
    return {
        "cr_display": c["display"],
        "cr_color": c["color"],
        "cr_speed": c["speed_byte"],
        "cr_mflags": c["mflags"],
        "cr_level": c["level"],
        "cr_hd_num": c["hd_num"],
        "cr_hd_sides": c["hd_sides_scaled"],
        "cr_ac": c["ac"],
        "cr_sleep": c["sleep_byte"],
        "cr_aaf": c["aaf_byte"],
        "cr_xp_lo": c["xp_lo"],
        "cr_xp_hi": c["xp_hi"],
        "cr_atk0_type": atk0[0],
        "cr_atk0_dice": atk0[1],
        "cr_atk0_sides": atk0[2],
        "cr_atk1_type": atk1[0],
        "cr_atk1_dice": atk1[1],
        "cr_atk1_sides": atk1[2],
        "cr_spell_chance": c["spell_chance"],
        "cr_spell_flags": c["spell_flags"],
        "cr_treasure": c["treasure"],
    }


def audit_against_catalog_fields(
    creatures: list[dict],
    fields_path: Path = DEFAULT_CATALOG_FIELDS,
    names_path: Path = DEFAULT_CATALOG_NAMES,
) -> dict:
    """Cross-check all 279 VMS spec creatures against committed catalog_fields.s."""
    committed = parse_catalog_fields_asm(fields_path)
    cat_names = parse_catalog_names_comments(names_path)

    invariant_mismatches: list[str] = []
    legacy_repro_mismatches: list[str] = []
    phase5_repro_mismatches: list[str] = []
    hd_scaled: list[tuple[int, str, str, str]] = []
    sleep_div_zeroed: list[tuple[int, str, int]] = []
    sleep_clamped: list[tuple[int, str, int, int]] = []
    speed_collapsed_very_slow: list[tuple[int, str, int]] = []
    speed_collapsed_very_fast: list[tuple[int, str, int]] = []
    three_or_four_attacks: list[tuple[int, str, int]] = []
    remapped_or_zeroed_atks: list[tuple[int, str]] = []
    spell_chance_newly_active: list[tuple[int, str, str, int, int]] = []
    spell_flags_summon_undead_split: list[tuple[int, str, int, int, int]] = []
    quylthulg_zero_freq: list[tuple[int, str, str]] = []
    cm_invisible_species: list[tuple[int, str]] = []
    cm_phase_species: list[tuple[int, str]] = []
    cm_eats_other_species: list[tuple[int, str]] = []
    cm_picks_up_species: list[tuple[int, str]] = []
    cm_unused_bit_species: list[tuple[int, str, str]] = []
    random_only_movers: list[tuple[int, str, str]] = []
    duplicate_alias_names: list[tuple[str, list[int]]] = []

    invariant_keys = (
        "cr_display",
        "cr_color",
        "cr_speed",
        "cr_mflags",
        "cr_level",
        "cr_hd_num",
        "cr_hd_sides",
        "cr_ac",
        "cr_sleep",
        "cr_aaf",
        "cr_xp_lo",
        "cr_xp_hi",
        "cr_treasure",
    )

    by_moria8_name: dict[str, list[int]] = {}
    for c in creatures:
        idx = c["index"]
        by_moria8_name.setdefault(c["moria8_name"], []).append(idx)
        if cat_names[idx] != c["moria8_name"]:
            invariant_mismatches.append(
                f"#{idx}: catalog_names.s={cat_names[idx]!r} != moria8_name={c['moria8_name']!r}"
            )

        legacy = legacy_catalog_row_from_spec(c)
        phase5 = phase5_catalog_row_from_spec(c)
        for key in invariant_keys:
            if committed[key][idx] != legacy[key]:
                invariant_mismatches.append(
                    f"#{idx} {c['name']} {key}: catalog_fields.s=0x{committed[key][idx]:02X} != spec=0x{legacy[key]:02X}"
                )
        for key, arr in committed.items():
            if arr[idx] != legacy[key]:
                legacy_repro_mismatches.append(
                    f"#{idx} {c['name']} {key}: catalog_fields.s=0x{arr[idx]:02X} != legacy=0x{legacy[key]:02X}"
                )
            if arr[idx] != phase5[key]:
                phase5_repro_mismatches.append(
                    f"#{idx} {c['name']} {key}: catalog_fields.s=0x{arr[idx]:02X} != phase5=0x{phase5[key]:02X}"
                )

        if (c["hd_num"], c["hd_sides_scaled"]) != (c["hd_count"], c["hd_sides"]):
            hd_scaled.append(
                (idx, c["name"], f"{c['hd_count']}d{c['hd_sides']}", f"{c['hd_num']}d{c['hd_sides_scaled']}")
            )
        if 0 < c["sleep"] < 10 and c["sleep_byte"] == 0:
            sleep_div_zeroed.append((idx, c["name"], c["sleep"]))
        if c["sleep"] // 10 > 255:
            sleep_clamped.append((idx, c["name"], c["sleep"], c["sleep_byte"]))
        if c["speed"] < 0:
            speed_collapsed_very_slow.append((idx, c["name"], c["speed"]))
        if c["speed"] > 2:
            speed_collapsed_very_fast.append((idx, c["name"], c["speed"]))

        live_atks = [a for a in c["attacks"] if a["adtype"] not in (0, 99)]
        if len(live_atks) > 2:
            three_or_four_attacks.append((idx, c["name"], len(live_atks)))
        if any(
            a["adtype"] in pc.NO_HP_ATTACK_TYPES or pc.UMORIA_TO_C64_ATK.get(a["adtype"]) != a["adtype"]
            for a in live_atks
        ):
            remapped_or_zeroed_atks.append((idx, c["name"]))

        if legacy["cr_spell_chance"] != c["spell_chance"]:
            spell_chance_newly_active.append(
                (idx, c["name"], c["spells_hex"], legacy["cr_spell_chance"], c["spell_chance"])
            )
        if legacy["cr_spell_flags"] != c["spell_flags"]:
            spell_flags_summon_undead_split.append(
                (idx, c["name"], legacy["cr_spell_flags"], c["spell_flags"], c["spell_flags2"])
            )
        if c["spells"] != 0 and (c["spells"] & VMS_SPELL_FREQ_MASK) == 0:
            quylthulg_zero_freq.append((idx, c["name"], c["spells_hex"]))

        if c["cm_invisible"]:
            cm_invisible_species.append((idx, c["name"]))
        if c["cmove"] & VMS_CM_PHASE:
            cm_phase_species.append((idx, c["name"]))
        if c["cmove"] & VMS_CM_EATS_OTHER:
            cm_eats_other_species.append((idx, c["name"]))
        if c["cmove"] & VMS_CM_PICKS_UP:
            cm_picks_up_species.append((idx, c["name"]))
        if c["cmove"] & VMS_CM_UNUSED_80:
            cm_unused_bit_species.append((idx, c["name"], c["cmove_hex"]))
        if (c["cmove"] & VMS_CM_MOVE_NORMAL) == 0 and (c["cmove"] & VMS_CM_RANDOM_MASK) != 0:
            random_only_movers.append((idx, c["name"], c["cmove_hex"]))

    for mname, indices in by_moria8_name.items():
        if len(indices) > 1:
            duplicate_alias_names.append((mname, indices))

    return {
        "invariant_mismatches": invariant_mismatches,
        "legacy_repro_mismatches": legacy_repro_mismatches,
        "phase5_repro_mismatches": phase5_repro_mismatches,
        "hd_scaled": hd_scaled,
        "sleep_div_zeroed": sleep_div_zeroed,
        "sleep_clamped": sleep_clamped,
        "speed_collapsed_very_slow": speed_collapsed_very_slow,
        "speed_collapsed_very_fast": speed_collapsed_very_fast,
        "three_or_four_attacks": three_or_four_attacks,
        "remapped_or_zeroed_atks": remapped_or_zeroed_atks,
        "spell_chance_newly_active": spell_chance_newly_active,
        "spell_flags_summon_undead_split": spell_flags_summon_undead_split,
        "quylthulg_zero_freq": quylthulg_zero_freq,
        "cm_invisible_species": cm_invisible_species,
        "cm_phase_species": cm_phase_species,
        "cm_eats_other_species": cm_eats_other_species,
        "cm_picks_up_species": cm_picks_up_species,
        "cm_unused_bit_species": cm_unused_bit_species,
        "random_only_movers": random_only_movers,
        "duplicate_alias_names": duplicate_alias_names,
    }


def format_audit_report(creatures: list[dict], audit: dict) -> str:
    """Format a concise human-readable VMS vs catalog_fields.s audit summary."""
    distinct_sides = sorted({a["sides"] for c in creatures for a in c["attacks"]})
    distinct_adesc = sorted({a["adesc"] for c in creatures for a in c["attacks"]})
    distinct_adtype = sorted({a["adtype"] for c in creatures for a in c["attacks"]})
    max_dice = max(a["dice"] for c in creatures for a in c["attacks"])
    cdef7_nonzero = sum(1 for c in creatures if c["cdefense7"] != 0)
    sf2_nonzero = sum(1 for c in creatures if c["spell_flags2"] != 0)

    lines = [
        "=== VMS Moria 4.8 (279 species) vs catalog_fields.s Audit ===",
        f"Species count: {len(creatures)} (indices 0..{len(creatures) - 1})",
        f"Invariant 13-field byte-for-byte mismatches: {len(audit['invariant_mismatches'])}",
        f"Legacy 21-field build_catalog reproduction mismatches: {len(audit['legacy_repro_mismatches'])}",
        f"Attack sides set: {distinct_sides} (max={max(distinct_sides)} <= {MAX_ATTACK_SIDES})",
        f"Attack adesc range: {min(distinct_adesc)}..{max(distinct_adesc)} (count={len(distinct_adesc)})",
        f"Attack adtype set: {distinct_adtype} (max_dice={max_dice})",
        f"Non-zero cdefense7 species: {cdef7_nonzero}/279; non-zero spell_flags2 species: {sf2_nonzero}/279",
        "",
        "Intentional Pre-Phase-5 vs Phase-5 Differences & Audit Findings:",
        f"  1. HD >255 factor-scaled (max HP preserved): {len(audit['hd_scaled'])} species -> {audit['hd_scaled']}",
        f"  2. 3-or-4 attack species truncated to 2 in catalog_fields.s: {len(audit['three_or_four_attacks'])} species",
        f"  3. Missing adtype / NO_HP_ATTACK_TYPES remapped or 0d0-zeroed in catalog_fields.s: {len(audit['remapped_or_zeroed_atks'])} species",
        f"  4. Extended-only casters whose spell_chance was 0 in catalog_fields.s: {len(audit['spell_chance_newly_active'])} species",
        f"  5. Summon-Undead (0x4000) split from MSF_SUMMON ($04) to MSF2_SUMMON_UNDEAD ($04) + freq=0 Quylthulgs: {audit['spell_flags_summon_undead_split']}",
        f"  6. Raw VMS freq=0 spell words (upstream RAK quirk): {audit['quylthulg_zero_freq']}",
        f"  7. VMS sleep=1 truncated to $00 by sleep//10 (wakes/spawns 0-sleep instead of csleep=1): {len(audit['sleep_div_zeroed'])} species -> {[x[:2] for x in audit['sleep_div_zeroed']]}",
        f"  8. VMS sleep clamped at $FF (25000 -> 255): {audit['sleep_clamped']}",
        f"  9. VMS 5-rate speed (-1..+3) collapsed to 3 rates: speed=-1 ({len(audit['speed_collapsed_very_slow'])}): {audit['speed_collapsed_very_slow']}; speed=+3 ({len(audit['speed_collapsed_very_fast'])})",
        f" 10. Random-only movers (cmove has random bits without CM_MOVE_NORMAL 0x02, so CF_ATTACK_ONLY=0 lets Moria8 pathfind on non-random rolls): {audit['random_only_movers']}",
        f" 11. Duplicate moria8_name via ALIASES['Large Grey Snake']: {audit['duplicate_alias_names']} (#46 DL3 & #57 DL4 both named 'Large Green Snake' in catalog_names.s)",
        f" 12. CM_INVISIBLE (0x10000): {len(audit['cm_invisible_species'])} species; NOTE cr_mflags $02 is CF_UNDEAD in core/6502/monster.s:147, whereas cr_cdefense bit 7 ($80) is unused!",
        f" 13. Extended cmove counts: CM_PHASE={len(audit['cm_phase_species'])}, CM_EATS_OTHER={len(audit['cm_eats_other_species'])}, CM_PICKS_UP={len(audit['cm_picks_up_species'])}, unused_0x80={audit['cm_unused_bit_species']}",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="extract_vms_creatures.py",
        description="Extract VMS Moria 4.8 c_list (279 species) into monster_catalog_spec.json.",
    )
    parser.add_argument(
        "--vms-values",
        type=str,
        default="",
        required=True,
        help="Path to VMS Moria 4.8 source/include/values.inc (required; no hardcoded default).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_SPEC_OUT,
        help="Destination path for monster_catalog_spec.json.",
    )
    parser.add_argument(
        "--audit",
        action="store_true",
        help="Cross-check extracted creatures against platforms/shared/catalog/catalog_fields.s.",
    )
    args = parser.parse_args(argv)

    if not args.vms_values:
        print("ERROR: --vms-values <path> must be non-empty", file=sys.stderr)
        return 1
    values_path = Path(args.vms_values)
    if not values_path.is_file():
        print(f"ERROR: values.inc file not found: {values_path}", file=sys.stderr)
        return 1

    creatures = parse_vms_values(values_path)
    audit = audit_against_catalog_fields(creatures)
    repro_errs = (
        audit["phase5_repro_mismatches"]
        if audit["legacy_repro_mismatches"]
        else audit["legacy_repro_mismatches"]
    )
    if audit["invariant_mismatches"] or repro_errs:
        for msg in audit["invariant_mismatches"] + repro_errs:
            print(f"MISMATCH: {msg}", file=sys.stderr)
        return 1

    doc = build_spec_document(creatures)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")

    if args.audit:
        print(format_audit_report(creatures, audit))
    else:
        print(f"Wrote {len(creatures)} creatures to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
