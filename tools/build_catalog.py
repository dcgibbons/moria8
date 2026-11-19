#!/usr/bin/env python3
"""Build Moria8 monster catalog assembly & binary payloads from monster_catalog_spec.json.

Reads the in-repo authoritative 279-species VMS Moria 4.8 specification at
`platforms/shared/catalog/monster_catalog_spec.json` (zero hardcoded external
paths; optional `VMS_SRC` / `UMORIA_SRC` env vars remain supported for legacy
report cross-checks) and emits:

1. Extended 8-column SoA assembly (`ext-asm`):
   `platforms/shared/catalog/catalog_ext_fields.s` (`8 × 279 = 2,232 B`:
   `cat_atk2_type`, `cat_atk2_dice`, `cat_atk2_sides`,
   `cat_atk3_type`, `cat_atk3_dice`, `cat_atk3_sides`,
   `cat_spell_flags2`, `cat_cdefense`, where
   `cat_cdefense = cdefense7 | ($80 if cm_invisible else 0)`).

2. Extended binary payloads:
   - `ext-soa`: Raw `2,232 B` (`8 × 279` column-major SoA), or `2,234 B` with
     `--prg-addr <addr>` 2-byte little-endian load header, for C128 (`128.cex`),
     CX16 (`MONSTER.EXT`), and EasyFlash / MD128 / Plus4 / CX16 cartridges.
   - `ext-rows`: Row-major `279 × 8 B = 2,232 B` (or `2,234 B` with
     `--prg-addr <addr>`), for Apple IIe (`A2.CATEXT`), BBC Master (`MONEXT`),
     and C64 REU (`monster.ext` PRG).
   - `ext-1541`: 1541 sector-packed `MONSTER.EXT` (`31 × 8 B = 248 <= 252 B`
     per sector + `2 B` sector header + `4 B` pad = `254 B/sector × 9 sectors`
     = `2,286 B`, `0` cross-sector straddles) for C64 / Plus/4 `.d64`.

3. Fixed-record & Atari `MONSTER.CAT` payloads (`records`):
   - Legacy `49 B`/record (`2 B` id + `21 B` fields + `26 B` name = `13,671 B`
     raw, or `140` DOS 2.5 sectors = `17,424 B` with `--atari-sectors`).
   - `--phase5-records`: Phase 5 `57 B`/record (`2 B` id `[lo, hi]` + `29 B`
     Phase 5 fields + `26 B` NUL-padded screen-code name = `15,903 B` raw;
     `2 × 57 = 114 <= 125 B` DOS 2.5 sector = `140` sectors / `17,432 B` with
     `--atari-sectors`, `0` cross-sector straddles).

4. Wave 5.4 atomic assembly flip (`--phase5-asm` / `phase5-asm`):
   Flips `catalog_fields.s` (Phase 5 `atk0/atk1` `verb+sides` packing + split
   `Summon Undead`), `catalog_ext_fields.s`, `catalog_index.s` (`cat_undead[35]`
   replacing all-`$FF` `cat_available[35]`), and `catalog_names.s` in one command.

5. PackBits RLE encoder/decoder (`packbits` subcommand or `--packbits` flag)
   for Apple IIe (`A2.AUXDATA`, `A2.CATALOG`, `A2.CATEXT`) and Atari `.car`
   (`MONSTER.CAT`).

6502 PackBits Unpack Specification
----------------------------------
Stream consists of packets terminated by an explicit `$80` (`128`) EOF byte:
  - Header byte `n` in `0..127` (`$00..$7F`):
      Copy the next `n + 1` (`1..128`) literal bytes from source to destination.
  - Header byte `n` in `129..255` (`$81..$FF`):
      Read the next single byte and repeat it `257 - n` (`2..128`) times to
      destination. On 6502, `257 - n` is `(n ^ $FF) + 2` (`eor #$ff ; clc ; adc #2`,
      yielding `2..128` with carry clear).
  - Header byte `n == 128` (`$80`):
      End of stream (EOF); stop immediately without reading any payload byte.

Reference 6502 unpack loop (`zp_ptr0` = src, `zp_ptr1` = dst, `Y = 0`):
    !pb_pkt:
        jsr next_src_byte       // A = header n
        cmp #$80
        beq !pb_done+           // $80 -> EOF
        bcs !pb_run+            // $81..$FF -> repeat 257 - n times
        tax                     // $00..$7F -> copy X+1 literal bytes
    !pb_lit:
        jsr next_src_byte
        jsr put_dst_byte
        dex
        bpl !pb_lit-
        bmi !pb_pkt-
    !pb_run:
        eor #$ff
        adc #1                  // C=1 on entry from bcs -> A = (255 - n) + 2 = 257 - n
        tax
        jsr next_src_byte       // A = repeated byte
    !pb_fill:
        jsr put_dst_byte
        dex
        bne !pb_fill-
        beq !pb_pkt-
    !pb_done:
        rts
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
import extract_vms_creatures as evc  # noqa: E402
import huff_encoder as huff  # noqa: E402
import parse_creatures as pc  # noqa: E402

DEFAULT_SPEC_PATH = REPO_ROOT / "platforms" / "shared" / "catalog" / "monster_catalog_spec.json"
DEFAULT_SHARED_CATALOG_DIR = REPO_ROOT / "platforms" / "shared" / "catalog"

# VMS constants (source/include/constants.inc).
CREATURE_COUNT = 279
MAX_MONS_LEVEL = 40
WIN_MON_TOT = 2
CATALOG_NAME_MAX = 25
LEGACY_RECORD_SIZE = 49
PHASE5_RECORD_SIZE = 57
EXT_SOA_FIELD_COUNT = 8
EXT_TOTAL_BYTES = CREATURE_COUNT * EXT_SOA_FIELD_COUNT  # 2,232 B
EXT_1541_PER_SECTOR = 31                                # 31 * 8 = 248 <= 252 B
EXT_1541_SECTORS = 9                                    # 9 * 31 = 279 (0 remainder, 0 straddles)
EXT_1541_SECTOR_HEADER = 2
EXT_1541_SECTOR_BYTES = 254
ATARI_RECORDS_PER_SECTOR = 2
ATARI_SECTOR_DATA = 125
ATARI_SECTORS = 140

EXT_FIELD_LABELS: tuple[str, ...] = (
    "cat_atk2_type",
    "cat_atk2_dice",
    "cat_atk2_sides",
    "cat_atk3_type",
    "cat_atk3_dice",
    "cat_atk3_sides",
    "cat_spell_flags2",
    "cat_cdefense",
)

CORE_FIELD_KEYS: tuple[str, ...] = tuple(label for label, _key, _comment in pc.SOA_FIELDS)

# Pre-Phase-5 engine support masks used when reproducing the legacy 21-field catalog.
SUPPORTED_ATTACKS = {1, 3, 4, 5, 6, 7, 8, 9, 11, 14, 20, 99}
SUPPORTED_SPELLS = (
    0x0000000F
    | 0x00000040
    | 0x00000080
    | 0x00000100
    | 0x00000400
    | 0x00000800
    | 0x00001000
    | 0x00002000
    | 0x00004000
    | 0x00000200
    | 0x00F80000
)
SUPPORTED_CMOVE = (
    0x00000001
    | 0x00000002
    | 0x00000004
    | 0x00000038
    | 0x00020000
    | 0x00200000
    | 0x7F000000
    | 0x80000000
)
SUPPORTED_CDEFENSE = 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x2000 | 0x4000

ENTRY = re.compile(
    r"\(\s*'((?:[^']|'')*)'\s*,\s*%X'([0-9A-Fa-f]+)'\s*,\s*%X'([0-9A-Fa-f]+)'\s*,\s*%X'([0-9A-Fa-f]+)'"
    r"\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*'(.)'\s*,\s*'\s*(\d+)d(\d+)\s*'\s*,"
    r"\s*'([^']*)'\s*,\s*(\d+)\s*\)",
    re.S,
)

ALIASES = dict(evc.ALIASES)

KEPT = {
    "Blubbering Icky-Thing",
    "Poltergeist",
    "Radiation Eye",
    "Bloodshot Eye",
    "Lost Soul",
    "Disenchanter Mold",
    "Giant White Dragon Fly",
    "Quythulg",
    "Banshee",
    "Ghost",
    "Lich",
    "King Lich",
    "Emperor Lich",
    "Evil Iggy",
    "Balrog",
}

MOVE_BITS = 0x0000003F
NOT_ABILITIES = 0xFF800000 | 0x000000C0


def parse_int_auto(val: str) -> int:
    s = val.strip()
    if s.startswith("$"):
        return int(s[1:], 16)
    return int(s, 0)


def load_spec(spec_path: Path = DEFAULT_SPEC_PATH) -> dict:
    """Load and validate in-repo monster_catalog_spec.json."""
    doc = json.loads(spec_path.read_text(encoding="utf-8"))
    assert doc.get("schema_version") == 1, f"Unsupported schema_version: {doc.get('schema_version')}"
    creatures = doc["creatures"]
    assert len(creatures) == CREATURE_COUNT, f"Expected {CREATURE_COUNT} creatures, got {len(creatures)}"
    levels = [c["level"] for c in creatures]
    assert levels == sorted(levels), "Spec creatures must be sorted by level"
    assert max(c["level"] for c in creatures[:-WIN_MON_TOT]) <= MAX_MONS_LEVEL
    for idx, c in enumerate(creatures):
        assert c["index"] == idx
        expected_cdef_byte = c["cdefense7"] | (0x80 if c["cm_invisible"] else 0)
        assert c["cdefense_byte"] == expected_cdef_byte, (idx, c["cdefense_byte"], expected_cdef_byte)
        assert len(c["packed_attacks"]) == 4
        for slot, atk in enumerate(c["attacks"]):
            repacked = list(evc.pack_attack(atk["adtype"], atk["adesc"], atk["dice"], atk["sides"]))
            assert c["packed_attacks"][slot] == repacked, (idx, slot, c["packed_attacks"][slot], repacked)
    return doc


def spec_to_legacy_vms_entry(c: dict) -> dict:
    """Convert a monster_catalog_spec.json entry to legacy parse_vms() dict shape."""
    atks = [
        (a["adtype"], a["adesc"], a["dice"], a["sides"])
        for a in c["attacks"]
        if not (a["adtype"] == 0 and a["adesc"] == 0 and a["dice"] == 0 and a["sides"] == 0)
    ]
    return {
        "name": c["name"],
        "cmove": c["cmove"],
        "spells": c["spells"],
        "cdefense": c["cdefense"],
        "sleep": c["sleep"],
        "mexp": c["mexp"],
        "aaf": c["aaf"],
        "ac": c["ac"],
        "speed": c["speed"],
        "glyph": c["cchar"],
        "hd": (c["hd_count"], c["hd_sides"]),
        "attacks": atks,
        "level": c["level"],
    }


def parse_vms(source: Path) -> list[dict]:
    text = (source / "include" / "values.inc").read_text(errors="replace")
    start = text.index("c_list  :=")
    creatures = []
    for m in ENTRY.finditer(text, start):
        attacks = []
        for part in filter(None, (p.strip() for p in m.group(13).split("|"))):
            kind, verb, dice = part.split()
            n, s = dice.split("d")
            attacks.append((int(kind), int(verb), int(n), int(s)))
        creatures.append(
            dict(
                name=m.group(1).replace("''", "'"),
                cmove=int(m.group(2), 16),
                spells=int(m.group(3), 16),
                cdefense=int(m.group(4), 16),
                sleep=int(m.group(5)),
                mexp=int(m.group(6)),
                aaf=int(m.group(7)),
                ac=int(m.group(8)),
                speed=int(m.group(9)),
                glyph=m.group(10),
                hd=(int(m.group(11)), int(m.group(12))),
                attacks=attacks,
                level=int(m.group(14)),
            )
        )
        if len(creatures) > 1 and text[m.end() : m.end() + 40].lstrip().startswith(");"):
            break
    return creatures


def bits(value: int) -> list[str]:
    return [f"0x{1 << b:x}" for b in range(32) if value >> b & 1]


def abilities(c: dict) -> list[tuple[str, bool]]:
    out = [(f"attack {k}", k in SUPPORTED_ATTACKS) for k in sorted({a[0] for a in c["attacks"]} - {0, 99})]
    out += [(f"spell {b}", int(b, 16) & SUPPORTED_SPELLS != 0) for b in bits(c["spells"] & ~0x0F)]
    if c["cmove"] & MOVE_BITS:
        out.append(("movement", True))
    out += [(f"cmove {b}", int(b, 16) & SUPPORTED_CMOVE != 0) for b in bits(c["cmove"] & ~MOVE_BITS & ~NOT_ABILITIES)]
    return out


def missing(c: dict) -> list[str]:
    return [name for name, ok in abilities(c) if not ok]


def mostly_missing(c: dict) -> bool:
    have = abilities(c)
    return bool(have) and 2 * len(missing(c)) > len(have)


def norm(name: str) -> str:
    key = re.sub(r"[^a-z]", "", ALIASES.get(name, name).lower())
    return key[:-1] if key.endswith("s") else key


def todays_roster(root: Path) -> set[str]:
    names = set()
    for tier in sorted((root / "platforms/commodore/c64/creature_data").glob("tier[0-4].s")):
        names |= {norm(n) for n in re.findall(r'tier\d_crn_\d+: \.text "([^"]+)"', tier.read_text())}
    return names


def engine_row(c: dict) -> dict:
    """Legacy 21-field engine row (pre-Phase-5 attack ranking and spell mapping)."""
    attacks = []
    for kind, _verb, dice, sides in c["attacks"]:
        if kind in (0, 99):
            attacks.append({"type": 0, "dice": 0, "sides": 0})
            continue
        no_hp = kind in pc.NO_HP_ATTACK_TYPES
        attacks.append(
            {
                "type": pc.UMORIA_TO_C64_ATK.get(kind, pc.ATK_NORMAL),
                "dice": 0 if no_hp else dice,
                "sides": 0 if no_hp else sides,
            }
        )
    kept = pc.select_attack_slots(attacks)
    n, sides = c["hd"]
    k = next(k for k in range(1, 256) if n % k == 0 and n // k < 256 and sides * k < 256)
    chance, flags = pc.map_spells(c["spells"])
    return {
        "cr_display": pc.char_to_screencode(c["glyph"]),
        "cr_color": pc.assign_color(ALIASES.get(c["name"], c["name"])),
        "cr_speed": (
            pc.map_speed(c["speed"] + 10)
            | (c["cmove"] & pc.CM_RANDOM_MOVE)
            | (pc.CR_MAX_HP if c["cdefense"] & pc.CD_MAX_HP else 0)
        ),
        "cr_mflags": pc.map_mflags(c["cmove"], c["cdefense"], c["name"]),
        "cr_level": c["level"],
        "cr_hd_num": n // k,
        "cr_hd_sides": sides * k,
        "cr_ac": c["ac"],
        "cr_sleep": min(255, c["sleep"] // 10),
        "cr_aaf": min(127, c["aaf"]) | pc.map_doorflags(c["cmove"]),
        "cr_xp_lo": c["mexp"] & 0xFF,
        "cr_xp_hi": c["mexp"] >> 8,
        "cr_atk0_type": kept[0]["type"],
        "cr_atk0_dice": kept[0]["dice"],
        "cr_atk0_sides": kept[0]["sides"],
        "cr_atk1_type": kept[1]["type"],
        "cr_atk1_dice": kept[1]["dice"],
        "cr_atk1_sides": kept[1]["sides"],
        "cr_spell_chance": chance,
        "cr_spell_flags": flags,
        "cr_treasure": (c["cmove"] >> 24) & pc.CM_TREASURE,
    }


def phase5_core_row(spec_creature: dict) -> dict[str, int]:
    """Phase 5 21-field core row with lossless verb+sides atk0/atk1 and split spells."""
    atk0 = spec_creature["packed_attacks"][0]
    atk1 = spec_creature["packed_attacks"][1]
    return {
        "cr_display": spec_creature["display"],
        "cr_color": spec_creature["color"],
        "cr_speed": spec_creature["speed_byte"],
        "cr_mflags": spec_creature["mflags"],
        "cr_level": spec_creature["level"],
        "cr_hd_num": spec_creature["hd_num"],
        "cr_hd_sides": spec_creature["hd_sides_scaled"],
        "cr_ac": spec_creature["ac"],
        "cr_sleep": spec_creature["sleep_byte"],
        "cr_aaf": spec_creature["aaf_byte"],
        "cr_xp_lo": spec_creature["xp_lo"],
        "cr_xp_hi": spec_creature["xp_hi"],
        "cr_atk0_type": atk0[0],
        "cr_atk0_dice": atk0[1],
        "cr_atk0_sides": atk0[2],
        "cr_atk1_type": atk1[0],
        "cr_atk1_dice": atk1[1],
        "cr_atk1_sides": atk1[2],
        "cr_spell_chance": spec_creature["spell_chance"],
        "cr_spell_flags": spec_creature["spell_flags"],
        "cr_treasure": spec_creature["treasure"],
    }


def phase5_ext_row(spec_creature: dict) -> list[int]:
    """Return the 8 extended Phase 5 bytes for one species in canonical order."""
    atk2 = spec_creature["packed_attacks"][2]
    atk3 = spec_creature["packed_attacks"][3]
    cdef_byte = spec_creature["cdefense7"] | (0x80 if spec_creature["cm_invisible"] else 0)
    assert cdef_byte == spec_creature["cdefense_byte"]
    row = [
        atk2[0],
        atk2[1],
        atk2[2],
        atk3[0],
        atk3[1],
        atk3[2],
        spec_creature["spell_flags2"],
        cdef_byte,
    ]
    assert len(row) == EXT_SOA_FIELD_COUNT and all(0 <= b < 256 for b in row)
    return row


def ext_soa_columns(spec_creatures: list[dict]) -> dict[str, list[int]]:
    """Build {column_label: [279 bytes]} for the 8 extended Phase 5 SoA columns."""
    assert len(spec_creatures) == CREATURE_COUNT
    rows = [phase5_ext_row(c) for c in spec_creatures]
    return {
        label: [rows[i][col_idx] for i in range(CREATURE_COUNT)]
        for col_idx, label in enumerate(EXT_FIELD_LABELS)
    }


def format_ext_fields_asm(spec_creatures: list[dict]) -> str:
    """Render platforms/shared/catalog/catalog_ext_fields.s (8 x 279 = 2,232 B)."""
    cols = ext_soa_columns(spec_creatures)
    hexrow = lambda vals: "    .byte " + ", ".join(f"${v:02x}" for v in vals)
    lines = [
        "// Generated by tools/build_catalog.py from monster_catalog_spec.json. Do not edit.",
        "// Phase 5 extended monster catalog SoA columns (8 fields x 279 species = 2,232 bytes).",
        f".const CATALOG_EXT_SOA_FIELDS = {EXT_SOA_FIELD_COUNT}",
        f".const CATALOG_EXT_BYTES = {EXT_TOTAL_BYTES}",
        "catalog_ext_fields:",
    ]
    for label in EXT_FIELD_LABELS:
        lines.append(f"{label}:")
        vals = cols[label]
        lines += [hexrow(vals[k : k + 16]) for k in range(0, len(vals), 16)]
    lines.append("catalog_ext_fields_end:")
    for label in EXT_FIELD_LABELS:
        short = label[len("cat_") :]
        lines.append(f".label cat_cr_{short} = {label}")
    return "\n".join(lines) + "\n"


def write_ext_fields_asm(out_file: Path, spec_creatures: list[dict]) -> None:
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(format_ext_fields_asm(spec_creatures), encoding="utf-8")


def ext_soa_bytes(spec_creatures: list[dict], prg_addr: int | None = None) -> bytes:
    """Return 2,232 B column-major SoA (8 x 279), optionally prefixed by 2 B PRG load addr."""
    cols = ext_soa_columns(spec_creatures)
    payload = bytes(b for label in EXT_FIELD_LABELS for b in cols[label])
    assert len(payload) == EXT_TOTAL_BYTES
    if prg_addr is not None:
        assert 0 <= prg_addr <= 0xFFFF
        return bytes([prg_addr & 0xFF, (prg_addr >> 8) & 0xFF]) + payload
    return payload


def ext_row_major_bytes(spec_creatures: list[dict], prg_addr: int | None = None) -> bytes:
    """Return 2,232 B row-major (279 x 8 B), optionally prefixed by 2 B PRG load addr."""
    assert len(spec_creatures) == CREATURE_COUNT
    payload = bytes(b for c in spec_creatures for b in phase5_ext_row(c))
    assert len(payload) == EXT_TOTAL_BYTES
    if prg_addr is not None:
        assert 0 <= prg_addr <= 0xFFFF
        return bytes([prg_addr & 0xFF, (prg_addr >> 8) & 0xFF]) + payload
    return payload


def ext_1541_sector_bytes(spec_creatures: list[dict], load_addr: int = 0xE000) -> bytes:
    """Return 1541 sector-packed MONSTER.EXT PRG (9 sectors x 254 B = 2,286 B, 31 rows/sec, 0 straddles)."""
    assert 0 <= load_addr <= 0xFFFF
    assert len(spec_creatures) == CREATURE_COUNT
    rows = [bytes(phase5_ext_row(c)) for c in spec_creatures]
    sectors: list[bytes] = []
    for s in range(EXT_1541_SECTORS):
        chunk = rows[s * EXT_1541_PER_SECTOR : (s + 1) * EXT_1541_PER_SECTOR]
        body = b"".join(chunk)
        assert len(body) <= EXT_1541_SECTOR_BYTES - EXT_1541_SECTOR_HEADER
        first_id = s * EXT_1541_PER_SECTOR
        hdr = (
            bytes([load_addr & 0xFF, (load_addr >> 8) & 0xFF])
            if s == 0
            else bytes([first_id & 0xFF, (first_id >> 8) & 0xFF])
        )
        pad = bytes((EXT_1541_SECTOR_BYTES - EXT_1541_SECTOR_HEADER) - len(body))
        sec_bytes = hdr + body + pad
        assert len(sec_bytes) == EXT_1541_SECTOR_BYTES
        sectors.append(sec_bytes)
    out = b"".join(sectors)
    assert len(out) == EXT_1541_SECTORS * EXT_1541_SECTOR_BYTES
    return out


def undead_bitmap(spec_creatures: list[dict]) -> list[int]:
    """Build 35-byte cat_undead bitmap (bit i%8 of byte i//8 set iff species i has CD_UNDEAD)."""
    assert len(spec_creatures) == CREATURE_COUNT
    bitmap = [0] * ((CREATURE_COUNT + 7) // 8)
    for i, c in enumerate(spec_creatures):
        is_undead = bool(c["cdefense"] & evc.VMS_CD_UNDEAD)
        assert is_undead == bool(c["mflags"] & pc.CF_UNDEAD), (i, c["name"])
        if is_undead:
            bitmap[i // 8] |= 1 << (i % 8)
    assert len(bitmap) == 35
    return bitmap


def fixed_records(spec_creatures: list[dict], phase5: bool = False) -> list[bytes]:
    """Build fixed-width catalog records: 49 B legacy or 57 B Phase 5 (--phase5-records).

    Record layout:
      - [0..1] (2 B): catalog id [id & $FF, id >> 8] (checked by cfr_check / a8_cat_check)
      - [2..2+F-1] (21 B legacy or 29 B Phase 5): engine fields in SoA order
      - [2+F..rec_size-1] (26 B): moria8_name in screen codes, NUL-terminated & 0-padded
    """
    assert len(spec_creatures) == CREATURE_COUNT
    rec_size = PHASE5_RECORD_SIZE if phase5 else LEGACY_RECORD_SIZE
    out: list[bytes] = []
    for n, sc in enumerate(spec_creatures):
        assert sc["index"] == n
        if phase5:
            core = phase5_core_row(sc)
            field_bytes = [core[k] for k in CORE_FIELD_KEYS] + phase5_ext_row(sc)
            assert len(field_bytes) == 29
        else:
            legacy = engine_row(spec_to_legacy_vms_entry(sc))
            field_bytes = [legacy[k] for k in CORE_FIELD_KEYS]
            assert len(field_bytes) == 21
        name_sc = [huff.ascii_to_screencode(ch) for ch in sc["moria8_name"]]
        assert len(name_sc) <= CATALOG_NAME_MAX
        rec = bytes([n & 0xFF, (n >> 8) & 0xFF] + field_bytes + name_sc)
        assert len(rec) < rec_size, (n, len(rec), rec_size)
        out.append(rec + bytes(rec_size - len(rec)))
    return out


def atari_monster_cat_bytes(spec_creatures: list[dict], phase5: bool = False) -> bytes:
    """Pack fixed records (49 B or 57 B) at 2 records per 125 B Atari DOS 2.5 sector (140 sectors)."""
    recs = fixed_records(spec_creatures, phase5=phase5)
    sectors = -(-len(recs) // ATARI_RECORDS_PER_SECTOR)
    assert sectors == ATARI_SECTORS
    out = bytearray()
    for s in range(sectors):
        body = b"".join(recs[s * ATARI_RECORDS_PER_SECTOR : (s + 1) * ATARI_RECORDS_PER_SECTOR])
        assert len(body) <= ATARI_SECTOR_DATA, (s, len(body), ATARI_SECTOR_DATA)
        out += body + bytes(ATARI_SECTOR_DATA - len(body)) if s < sectors - 1 else body
    return bytes(out)


def packbits_encode(data: bytes) -> bytes:
    """Optimal Moria8 PackBits encoder with explicit $80 (128) EOF marker.

    Packet headers:
      - 0..127 ($00..$7F): copy next (n + 1) literal bytes (1..128 bytes)
      - 129..255 ($81..$FF): repeat next 1 byte (257 - n) times (2..128 bytes)
      - 128 ($80): EOF sentinel
    Uses dynamic programming to produce the minimum valid byte length.
    """
    n = len(data)
    if n == 0:
        return b"\x80"

    run_len = [1] * n
    for i in range(n - 2, -1, -1):
        if data[i] == data[i + 1]:
            run_len[i] = run_len[i + 1] + 1

    inf = n * 2 + 16
    dp = [inf] * (n + 1)
    choice: list[tuple[int, int]] = [(0, 0)] * n  # (kind: 0=lit, 1=run, length)
    dp[n] = 1  # $80 EOF byte

    for i in range(n - 1, -1, -1):
        best_cost = inf
        best_choice = (0, 1)

        # Candidate repeat runs: check maximal capped run (and max_r - 1 for boundary splits).
        if run_len[i] >= 2:
            max_r = min(128, run_len[i])
            candidates = (max_r, max_r - 1) if max_r > 2 else (2,)
            for r in candidates:
                cost = 2 + dp[i + r]
                if cost < best_cost:
                    best_cost = cost
                    best_choice = (1, r)

        # Candidate literal runs: 1..min(128, n - i). Stop extending once a >=3 repeat starts,
        # because splitting a >=3 run out of a literal never increases byte count.
        max_lit = min(128, n - i)
        for lit in range(1, max_lit + 1):
            cost = 1 + lit + dp[i + lit]
            if cost < best_cost:
                best_cost = cost
                best_choice = (0, lit)
            if lit >= 1 and (i + lit) < n and run_len[i + lit] >= 3:
                break

        dp[i] = best_cost
        choice[i] = best_choice

    out = bytearray()
    pos = 0
    while pos < n:
        kind, length = choice[pos]
        if kind == 0:
            assert 1 <= length <= 128
            out.append(length - 1)
            out.extend(data[pos : pos + length])
        else:
            assert 2 <= length <= 128
            out.append(257 - length)
            out.append(data[pos])
        pos += length
    out.append(0x80)
    return bytes(out)


def packbits_decode(encoded: bytes) -> bytes:
    """Decode a Moria8 PackBits stream terminated by $80 (128) EOF."""
    out = bytearray()
    pos = 0
    n = len(encoded)
    while pos < n:
        hdr = encoded[pos]
        pos += 1
        if hdr == 0x80:
            if pos != n:
                raise ValueError(f"Trailing {n - pos} byte(s) after $80 EOF at offset {pos - 1}")
            return bytes(out)
        if hdr <= 127:
            count = hdr + 1
            if pos + count > n:
                raise ValueError(f"Truncated literal packet at {pos - 1}: need {count} bytes")
            out.extend(encoded[pos : pos + count])
            pos += count
        else:
            count = 257 - hdr
            if pos >= n:
                raise ValueError(f"Truncated repeat packet at {pos - 1}")
            out.extend([encoded[pos]] * count)
            pos += 1
    raise ValueError("Missing $80 EOF marker in PackBits stream")


def write_engine_catalog(
    out: Path,
    creatures: list[dict],
    avail: list[bool],
    win: set[int],
    *,
    phase5_asm: bool = False,
    spec_creatures: list[dict] | None = None,
) -> None:
    """Write catalog_fields.s, catalog_index.s, catalog_names.s (and catalog_ext_fields.s when phase5_asm)."""
    if phase5_asm:
        assert spec_creatures is not None and len(spec_creatures) == len(creatures)
        rows = [phase5_core_row(sc) for sc in spec_creatures]
        avail = [True] * len(creatures)
    else:
        rows = [engine_row(c) for c in creatures]

    fields = [label for label, _key, _comment in pc.SOA_FIELDS]
    for row in rows:
        assert all(0 <= row[f] < 256 for f in fields), row
    raw = [
        sum(1 for i, c in enumerate(creatures) if c["level"] == lvl and i not in win)
        for lvl in range(MAX_MONS_LEVEL + 1)
    ]
    playable = [
        sum(1 for i, c in enumerate(creatures) if c["level"] == lvl and avail[i] and i not in win)
        for lvl in range(MAX_MONS_LEVEL + 1)
    ]
    hexrow = lambda vals: "    .byte " + ", ".join(f"${v:02x}" for v in vals)
    head = "// Generated by tools/build_catalog.py from VMS Moria 4.8 c_list. Do not edit."

    lines = [head, "// The monster catalog in the engine's row encoding, one array per field.", "catalog_fields:"]
    for f in fields:
        lines.append(f"cat_{f}:")
        vals = [row[f] for row in rows]
        lines += [hexrow(vals[k : k + 16]) for k in range(0, len(vals), 16)]
    lines.append("catalog_fields_end:")
    (out / "catalog_fields.s").write_text("\n".join(lines) + "\n", encoding="utf-8")

    if phase5_asm:
        assert spec_creatures is not None
        write_ext_fields_asm(out / "catalog_ext_fields.s", spec_creatures)
        bitmap = undead_bitmap(spec_creatures)
        bitmap_lines = [
            "cat_undead:         // bit i%8 of byte i/8: creature i has CD_UNDEAD",
            hexrow(bitmap),
            "catalog_index_end:",
        ]
    else:
        bitmap = [0] * ((len(creatures) + 7) // 8)
        for i, ok in enumerate(avail):
            if ok:
                bitmap[i // 8] |= 1 << (i % 8)
        bitmap_lines = [
            "cat_available:      // bit i%8 of byte i/8: creature i spawns",
            hexrow(bitmap),
            "catalog_index_end:",
        ]

    index = [
        head,
        "// The catalog's constants and the index the creature picker reads.",
        f".const CATALOG_COUNT = {len(creatures)}",
        f".const CATALOG_SOA_FIELDS = {len(fields)}",
        f".const CATALOG_TOWN_COUNT = {raw[0]}",
        f".const CATALOG_WIN_FIRST = {min(win)}",
        f".const CATALOG_IGGY_ID = {next(i for i in win if creatures[i]['name'] == 'Evil Iggy')}",
        f".const CATALOG_BALROG_ID = {next(i for i in win if creatures[i]['name'] == 'Balrog')}",
        f".const CATALOG_MAX_MONS_LEVEL = {MAX_MONS_LEVEL}",
        f".const CATALOG_NAME_MAX = {max(len(ALIASES.get(c['name'], c['name'])) for c in creatures)}",
        "cat_level_raw:      // creatures per level 0-40, win creatures excluded (VMS m_level before summing)",
        hexrow(raw),
        "cat_level_playable: // the same, playable creatures only",
        hexrow(playable),
        *bitmap_lines,
    ]
    (out / "catalog_index.s").write_text("\n".join(index) + "\n", encoding="utf-8")

    shown = [ALIASES.get(c["name"], c["name"]) for c in creatures]
    codes_of = [[huff.ascii_to_screencode(ch) for ch in name] for name in shown]
    freq = collections.Counter(sc for codes in codes_of for sc in codes)
    freq[0x00] += len(codes_of)
    tree = huff.build_tree(freq)
    codes = huff.build_codes(tree)
    left, right = huff.flatten_tree(tree)
    assert len(left) < 0x7F and all(0 < sc < 0x80 for sc in freq if sc), "tree outside the decoder's format"
    names = [
        head,
        "// Catalog names by catalog id: Huffman-coded with their own tree (huff_encoder format;",
        "// leaves $80 | screen code), decoded by core/huffman.s with this tree swapped in.",
        "catn_tree_left:",
    ]
    names += [hexrow(left[k : k + 16]) for k in range(0, len(left), 16)]
    names.append("catn_tree_right:")
    names += [hexrow(right[k : k + 16]) for k in range(0, len(right), 16)]
    labels = [f"catn_{i}" for i in range(len(creatures))]
    names.append("cat_name_lo:")
    names += ["    .byte " + ", ".join(f"<{l}" for l in labels[k : k + 8]) for k in range(0, len(labels), 8)]
    names.append("cat_name_hi:")
    names += ["    .byte " + ", ".join(f">{l}" for l in labels[k : k + 8]) for k in range(0, len(labels), 8)]
    for label, name, sc in zip(labels, shown, codes_of):
        packed, _ = huff.compress_string(sc, codes)
        names.append(f"{label}: .byte " + ", ".join(f"${v:02x}" for v in packed) + f"  // {name}")
    names.append("catalog_names_end:")
    (out / "catalog_names.s").write_text("\n".join(names) + "\n", encoding="utf-8")


def width(values: list[int]) -> int:
    lo, hi = min(values), max(values)
    if lo >= 0:
        return 1 if hi < 0x100 else 2 if hi < 0x10000 else 4
    return 1 if -0x80 <= lo and hi < 0x80 else 2


def maybe_packbits_write(out_path: Path, payload: bytes, use_packbits: bool, label: str) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if use_packbits:
        compressed = packbits_encode(payload)
        assert packbits_decode(compressed) == payload
        out_path.write_bytes(compressed)
        saved = len(payload) - len(compressed)
        pct = (100.0 * len(compressed) / len(payload)) if payload else 100.0
        print(f"packbits [{label}]: {len(payload)} -> {len(compressed)} B (saved {saved} B, {pct:.1f}%)")
    else:
        out_path.write_bytes(payload)


def run_legacy_report_mode(args: argparse.Namespace) -> int:
    vms_env = os.environ.get("VMS_SRC", "")
    spec_doc: dict | None = None
    if vms_env and (Path(vms_env) / "include" / "values.inc").is_file():
        creatures = parse_vms(Path(vms_env))
        if args.spec.is_file():
            spec_doc = load_spec(args.spec)
    elif args.spec.is_file():
        spec_doc = load_spec(args.spec)
        creatures = [spec_to_legacy_vms_entry(c) for c in spec_doc["creatures"]]
    else:
        print(
            "ERROR: monster_catalog_spec.json not found and VMS_SRC is not set",
            file=sys.stderr,
        )
        return 1

    assert len(creatures) == CREATURE_COUNT, f"VMS max_creatures is 279, parsed {len(creatures)}"
    levels = [c["level"] for c in creatures]
    assert levels == sorted(levels), "VMS c_list must be sorted by level (m_level assumes it)"
    normal = creatures[:-WIN_MON_TOT]
    assert max(c["level"] for c in normal) <= MAX_MONS_LEVEL, "a normal creature is deeper than max_mons_level"

    table = sorted({a for c in creatures for a in c["attacks"]})
    index_of = {a: i + 1 for i, a in enumerate(table)}
    assert len(table) < 256 and max(len(c["attacks"]) for c in creatures) <= 4

    codes_of = [[huff.ascii_to_screencode(ch) for ch in c["name"]] for c in creatures]
    freq = collections.Counter(sc for codes in codes_of for sc in codes)
    freq[0x00] += len(codes_of)
    tree = huff.build_tree(freq)
    codes = huff.build_codes(tree)
    left, right = huff.flatten_tree(tree)
    name_bytes, name_offsets = [], []
    for sc in codes_of:
        name_offsets.append(len(name_bytes))
        packed, _ = huff.compress_string(sc, codes)
        name_bytes += packed

    today = todays_roster(REPO_ROOT)
    avail, degraded, ask, skipped = [], {}, {}, {}
    for c in creatures:
        gone = missing(c)
        ok = not mostly_missing(c) or c["name"] in KEPT
        avail.append(ok)
        if ok and gone:
            degraded[c["name"]] = gone
        elif not ok:
            (ask if norm(c["name"]) in today else skipped)[c["name"]] = gone
    win = set(range(len(creatures) - WIN_MON_TOT, len(creatures)))
    counts = [
        sum(1 for i, c in enumerate(creatures) if c["level"] == lvl and avail[i] and i not in win)
        for lvl in range(MAX_MONS_LEVEL + 1)
    ]
    bitmap = [0] * ((len(creatures) + 7) // 8)
    for i, ok in enumerate(avail):
        if ok:
            bitmap[i // 8] |= 1 << (i % 8)

    fields = [
        ("glyph", 1),
        ("colour", 1),
        ("level", 1),
        ("hd_num", width([c["hd"][0] for c in creatures])),
        ("hd_sides", width([c["hd"][1] for c in creatures])),
        ("ac", 1),
        ("sleep", width([c["sleep"] for c in creatures])),
        ("aaf", 1),
        ("speed", width([c["speed"] for c in creatures])),
        ("mexp", width([c["mexp"] for c in creatures])),
        ("cmove", 4),
        ("spells", 4),
        ("cdefense", 2),
        ("attacks", 4),
        ("name", 2),
    ]
    for name, key in (("level", "level"), ("ac", "ac"), ("aaf", "aaf")):
        assert width([c[key] for c in creatures]) == 1, f"{name} needs more than a byte"
    assert max(c["hd"][0] * c["hd"][1] for c in creatures) < 0x10000, "HP must fit 16 bits"
    record = sum(w for _, w in fields)

    def le(value: int, n: int) -> list[int]:
        return [(value >> (8 * k)) & 0xFF for k in range(n)]

    rows = []
    for i, c in enumerate(creatures):
        atk = [index_of[a] for a in c["attacks"]] + [0] * (4 - len(c["attacks"]))
        values = dict(
            glyph=pc.char_to_screencode(c["glyph"]),
            colour=pc.assign_color(c["name"]),
            level=c["level"],
            hd_num=c["hd"][0],
            hd_sides=c["hd"][1],
            ac=c["ac"],
            sleep=c["sleep"],
            aaf=c["aaf"],
            speed=c["speed"] & 0xFF,
            mexp=c["mexp"],
            cmove=c["cmove"],
            spells=c["spells"],
            cdefense=c["cdefense"],
            name=name_offsets[i],
        )
        row = []
        for name, w in fields:
            row += atk if name == "attacks" else le(values[name], w)
        assert len(row) == record
        rows.append(row)

    args.out.mkdir(parents=True, exist_ok=True)
    out = [
        "// Generated by tools/build_catalog.py from VMS Moria 4.8 c_list. Do not edit.",
        f".const CATALOG_COUNT = {len(creatures)}",
        f".const CATALOG_RECORD_SIZE = {record}",
        f".const CATALOG_MAX_MONS_LEVEL = {MAX_MONS_LEVEL}",
        f".const CATALOG_WIN_MON_TOT = {WIN_MON_TOT}",
    ]
    offset = 0
    for name, w in fields:
        out.append(f".const CAT_{name.upper()} = {offset}   // {w} byte{'s' if w > 1 else ''}")
        offset += w
    out.append("catalog_records:")
    for c, row in zip(creatures, rows):
        out.append(f"    .byte {', '.join(f'${b:02x}' for b in row)}   // {c['name']} (L{c['level']})")
    out.append("catalog_attacks:   // type, verb, dice, sides; entry 0 is none")
    out.append("    .byte 0, 0, 0, 0")
    for a in table:
        out.append(f"    .byte {a[0]}, {a[1]}, {a[2]}, {a[3]}")
    out.append("catalog_name_tree_left:")
    out.append("    .byte " + ", ".join(f"${b:02x}" for b in left))
    out.append("catalog_name_tree_right:")
    out.append("    .byte " + ", ".join(f"${b:02x}" for b in right))
    out.append("catalog_names:")
    for k in range(0, len(name_bytes), 16):
        out.append("    .byte " + ", ".join(f"${b:02x}" for b in name_bytes[k : k + 16]))
    out.append("catalog_level_counts:   // available normal creatures per level 0-40")
    out.append("    .byte " + ", ".join(str(n) for n in counts))
    out.append("catalog_available:      // bit i%8 of byte i/8: creature i spawns")
    out.append("    .byte " + ", ".join(f"${b:02x}" for b in bitmap))
    (args.out / "catalog.s").write_text("\n".join(out) + "\n", encoding="utf-8")

    sizes = {
        "records": record * len(creatures),
        "attack_table": 4 * (len(table) + 1),
        "name_tree": len(left) + len(right),
        "names": len(name_bytes),
        "level_counts": len(counts),
        "availability_bitmap": len(bitmap),
    }
    sizes["catalog_total"] = sizes["records"] + sizes["attack_table"] + sizes["name_tree"] + sizes["names"]
    sizes["resident_index"] = sizes["level_counts"] + sizes["availability_bitmap"]
    by_band = {}
    for lo, hi in ((0, 0), (1, 5), (6, 10), (11, 20), (21, 30), (31, 40), (41, 100)):
        idx = [i for i, c in enumerate(creatures) if lo <= c["level"] <= hi]
        by_band[f"{lo}-{hi}"] = f"{sum(avail[i] for i in idx)} of {len(idx)}"
    need = collections.Counter(w for why in degraded.values() for w in why)
    report = {
        "creatures": len(creatures),
        "record_size": record,
        "fields": fields,
        "sizes": sizes,
        "ranges": {
            **{
                k: [min(c[k] for c in creatures), max(c[k] for c in creatures)]
                for k in ("sleep", "mexp", "speed", "ac", "aaf", "level")
            },
            "hd_num": [min(c["hd"][0] for c in creatures), max(c["hd"][0] for c in creatures)],
            "hd_sides": [min(c["hd"][1] for c in creatures), max(c["hd"][1] for c in creatures)],
        },
        "attack_table_entries": len(table),
        "available": sum(avail),
        "available_by_level": by_band,
        "backlog_abilities": need.most_common(),
        "degraded": degraded,
        "ask_maintainer": ask,
        "skipped_not_in_todays_roster": skipped,
        "player_side_defence_gaps": collections.Counter(
            b for c in creatures for b in bits(c["cdefense"] & ~SUPPORTED_CDEFENSE)
        ).most_common(),
        "win_creatures": [
            {
                "name": creatures[i]["name"],
                "level": creatures[i]["level"],
                "available": avail[i],
                "missing": missing(creatures[i]),
            }
            for i in sorted(win)
        ],
    }
    if args.engine_out:
        args.engine_out.mkdir(parents=True, exist_ok=True)
        if args.phase5_asm and spec_doc is None:
            spec_doc = load_spec(args.spec)
        write_engine_catalog(
            args.engine_out,
            creatures,
            avail,
            win,
            phase5_asm=args.phase5_asm,
            spec_creatures=spec_doc["creatures"] if spec_doc is not None else None,
        )
    if args.ext_asm_out:
        if spec_doc is None:
            spec_doc = load_spec(args.spec)
        write_ext_fields_asm(args.ext_asm_out, spec_doc["creatures"])
    umoria = os.environ.get("UMORIA_SRC")
    if umoria and Path(umoria).is_file():
        theirs = pc.parse_creatures(umoria)
        by_name = {norm(b["name"]): (j, b) for j, b in enumerate(theirs)}
        diffs = []
        for i, a in enumerate(creatures):
            j, b = by_name.get(norm(a["name"]), (None, None))
            if b is None:
                diffs.append(f"{i} {a['name']}: not in Umoria")
                continue
            if i != j:
                diffs.append(f"{i} {a['name']}: Umoria position {j}")
            for mine, their in (
                ("level", "dlvl"),
                ("mexp", "xp"),
                ("ac", "ac"),
                ("aaf", "aaf"),
                ("cmove", "cmove"),
                ("spells", "spell"),
                ("cdefense", "cdefense"),
            ):
                if a[mine] != b[their]:
                    diffs.append(f"{i} {a['name']}: {mine} VMS {a[mine]} vs Umoria {b[their]}")
            if a["hd"] != (b["hd_num"], b["hd_sides"]):
                diffs.append(f"{i} {a['name']}: hd VMS {a['hd']} vs Umoria {(b['hd_num'], b['hd_sides'])}")
        report["umoria_check"] = {"count": [len(creatures), len(theirs)], "differences": len(diffs), "first": diffs[:60]}
    (args.out / "catalog.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(
        f"catalog: {len(creatures)} creatures, {record}-byte records, {len(table)} attacks, "
        f"{sizes['catalog_total']} bytes far + {sizes['resident_index']} resident; "
        f"{sum(avail)} available ({len(degraded)} with degraded abilities), {len(ask)} to ask about, "
        f"{len(skipped)} skipped"
    )
    return 0


def build_subcommand_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="build_catalog")
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC_PATH, help="Path to monster_catalog_spec.json")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_ext_asm = sub.add_parser("ext-asm", help="Generate catalog_ext_fields.s (8 x 279 = 2,232 B SoA)")
    p_ext_asm.add_argument("--out", type=Path, default=DEFAULT_SHARED_CATALOG_DIR / "catalog_ext_fields.s")

    p_ext_soa = sub.add_parser("ext-soa", help="Write 2,232 B SoA binary (or 2,234 B PRG with --prg-addr)")
    p_ext_soa.add_argument("--out", type=Path, required=True)
    p_ext_soa.add_argument("--prg-addr", type=parse_int_auto, default=None, help="Optional 16-bit PRG load header")
    p_ext_soa.add_argument("--packbits", action="store_true", help="PackBits-compress the output")

    p_ext_rows = sub.add_parser("ext-rows", help="Write 279 x 8 B = 2,232 B row-major binary (A2.CATEXT / MONEXT / REU)")
    p_ext_rows.add_argument("--out", type=Path, required=True)
    p_ext_rows.add_argument("--prg-addr", type=parse_int_auto, default=None, help="Optional 16-bit PRG load header")
    p_ext_rows.add_argument("--packbits", action="store_true", help="PackBits-compress the output")

    p_ext_1541 = sub.add_parser("ext-1541", help="Write 1541 9-sector MONSTER.EXT PRG (31 x 8 B/sec = 2,286 B)")
    p_ext_1541.add_argument("--out", type=Path, required=True)
    p_ext_1541.add_argument("--load-addr", type=parse_int_auto, default=0xE000, help="PRG load address (default $E000)")

    p_records = sub.add_parser("records", help="Write fixed-record MONSTER.CAT binary (49 B or --phase5-records 57 B)")
    p_records.add_argument("--out", type=Path, required=True)
    p_records.add_argument("--phase5-records", action="store_true", help="Emit 57 B Phase 5 records (29 fields)")
    p_records.add_argument("--atari-sectors", action="store_true", help="Pad 2 records per 125 B DOS 2.5 sector (140 sectors)")
    p_records.add_argument("--packbits", action="store_true", help="PackBits-compress the output (e.g. Atari .car)")

    p_pb = sub.add_parser("packbits", help="PackBits-compress (or --decode) a binary file with $80 EOF")
    p_pb.add_argument("--in", dest="infile", type=Path, required=True)
    p_pb.add_argument("--out", type=Path, required=True)
    p_pb.add_argument("--decode", action="store_true", help="Decode PackBits input back to raw bytes")
    p_pb.add_argument("--strip-prg", action="store_true", help="Strip 2-byte PRG load header before encoding")

    p_p5_asm = sub.add_parser("phase5-asm", help="Wave 5.4 atomic flip of catalog_fields.s + catalog_ext_fields.s + cat_undead[35]")
    p_p5_asm.add_argument("--out-dir", type=Path, default=DEFAULT_SHARED_CATALOG_DIR)

    return parser


SUBCOMMANDS = frozenset({"ext-asm", "ext-soa", "ext-rows", "ext-1541", "records", "packbits", "phase5-asm"})


def main(argv: list[str] | None = None) -> int:
    args_list = list(sys.argv[1:] if argv is None else argv)

    # Dispatch subcommand mode when a subcommand token is present; otherwise run backwards-compatible flag mode.
    first_positional = next((tok for tok in args_list if not tok.startswith("-")), None)
    if first_positional in SUBCOMMANDS:
        parser = build_subcommand_parser()
        args = parser.parse_args(args_list)
        if args.cmd == "packbits":
            raw = args.infile.read_bytes()
            if args.decode:
                decoded = packbits_decode(raw)
                args.out.parent.mkdir(parents=True, exist_ok=True)
                args.out.write_bytes(decoded)
                print(f"packbits decode [{args.infile.name}]: {len(raw)} -> {len(decoded)} B")
            else:
                if args.strip_prg:
                    assert len(raw) >= 2, "Input file shorter than 2-byte PRG header"
                    raw = raw[2:]
                maybe_packbits_write(args.out, raw, True, args.infile.name)
            return 0

        spec_doc = load_spec(args.spec)
        spec_creatures = spec_doc["creatures"]

        if args.cmd == "ext-asm":
            write_ext_fields_asm(args.out, spec_creatures)
            print(f"ext-asm: wrote {args.out} ({EXT_SOA_FIELD_COUNT} x {CREATURE_COUNT} = {EXT_TOTAL_BYTES} B)")
            return 0

        if args.cmd == "ext-soa":
            payload = ext_soa_bytes(spec_creatures, prg_addr=args.prg_addr)
            maybe_packbits_write(args.out, payload, args.packbits, args.out.name)
            return 0

        if args.cmd == "ext-rows":
            payload = ext_row_major_bytes(spec_creatures, prg_addr=args.prg_addr)
            maybe_packbits_write(args.out, payload, args.packbits, args.out.name)
            return 0

        if args.cmd == "ext-1541":
            payload = ext_1541_sector_bytes(spec_creatures, load_addr=args.load_addr)
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_bytes(payload)
            return 0

        if args.cmd == "records":
            if args.atari_sectors:
                payload = atari_monster_cat_bytes(spec_creatures, phase5=args.phase5_records)
            else:
                payload = b"".join(fixed_records(spec_creatures, phase5=args.phase5_records))
            maybe_packbits_write(args.out, payload, args.packbits, args.out.name)
            return 0

        if args.cmd == "phase5-asm":
            args.out_dir.mkdir(parents=True, exist_ok=True)
            legacy_creatures = [spec_to_legacy_vms_entry(c) for c in spec_creatures]
            win = set(range(len(spec_creatures) - WIN_MON_TOT, len(spec_creatures)))
            write_engine_catalog(
                args.out_dir,
                legacy_creatures,
                [True] * len(spec_creatures),
                win,
                phase5_asm=True,
                spec_creatures=spec_creatures,
            )
            print(f"phase5-asm: wrote Phase 5 catalog_fields.s, catalog_ext_fields.s, catalog_index.s (cat_undead), catalog_names.s -> {args.out_dir}")
            return 0

    legacy_parser = argparse.ArgumentParser(prog="build_catalog")
    legacy_parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC_PATH)
    legacy_parser.add_argument("--out", type=Path, default=Path("build/catalog"))
    legacy_parser.add_argument(
        "--engine-out",
        type=Path,
        help="also write catalog_fields.s, catalog_index.s and catalog_names.s here (platforms/shared/catalog)",
    )
    legacy_parser.add_argument(
        "--phase5-asm",
        action="store_true",
        help="with --engine-out, emit Phase 5 atk0/atk1 verb+sides packing, catalog_ext_fields.s, and cat_undead[35]",
    )
    legacy_parser.add_argument(
        "--ext-asm-out",
        type=Path,
        help="write extended 8-column SoA assembly file (platforms/shared/catalog/catalog_ext_fields.s)",
    )
    legacy_args = legacy_parser.parse_args(args_list)
    return run_legacy_report_mode(legacy_args)


if __name__ == "__main__":
    sys.exit(main())
