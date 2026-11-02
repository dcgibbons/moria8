#!/usr/bin/env python3
"""Build the monster catalog (docs/MONSTER_CATALOG_DESIGN.md) from VMS Moria.

Reads VMS Moria 4.8's c_list (source/include/values.inc), the source of
truth, and writes:

- catalog.s: Kick Assembler data: one fixed-length record per creature in
  VMS order (sorted by level), the shared attack table, the Huffman-coded
  name block (its own tree, the game's decoder format), the level index
  (available creatures per level) and the availability bitmap;
- catalog.json: the report: field ranges, sizes, availability and why each
  unavailable creature waits, and the Umoria cross-check.

Usage:
  VMS_SRC=<vms-moria>/source [UMORIA_SRC=<umoria>/src/data_creatures.cpp] \
      python3 tools/build_catalog.py --out build/catalog
"""

import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import huff_encoder as huff  # noqa: E402
import parse_creatures as pc  # noqa: E402

# VMS constants (source/include/constants.inc).
MAX_MONS_LEVEL = 40
WIN_MON_TOT = 2

# What the engine implements exactly (not degraded). Implementing an ability
# means adding it here; every creature waiting only on it becomes available.
SUPPORTED_ATTACKS = {1, 3, 4, 6, 9, 11, 14, 20, 99}       # VMS/Umoria attack types
SUPPORTED_SPELLS = (0x0000000F                              # cast frequency
                    | 0x00000040                            # teleport to
                    | 0x00000080 | 0x00000100               # cause light, serious wounds
                    | 0x00000400 | 0x00000800 | 0x00001000  # blindness, confusion, fear
                    | 0x00002000 | 0x00004000               # summon monster, undead
                    | 0x00800000)                           # fire breath
SUPPORTED_CMOVE = (0x00000001 | 0x00000002 | 0x00000004     # attack only, normal move, only magic
                   | 0x00000038                             # 20/40/75% random move
                   | 0x00020000 | 0x00200000                # open doors, multiply
                   | 0x7F000000 | 0x80000000)               # treasure, win creature
SUPPORTED_CDEFENSE = 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x2000 | 0x4000   # dragon, animal, evil, undead, infra, max HP

ENTRY = re.compile(r"\(\s*'((?:[^']|'')*)'\s*,\s*%X'([0-9A-Fa-f]+)'\s*,\s*%X'([0-9A-Fa-f]+)'\s*,\s*%X'([0-9A-Fa-f]+)'"
                   r"\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*'(.)'\s*,\s*'\s*(\d+)d(\d+)\s*'\s*,"
                   r"\s*'([^']*)'\s*,\s*(\d+)\s*\)", re.S)


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
        creatures.append(dict(
            name=m.group(1).replace("''", "'"), cmove=int(m.group(2), 16), spells=int(m.group(3), 16),
            cdefense=int(m.group(4), 16), sleep=int(m.group(5)), mexp=int(m.group(6)), aaf=int(m.group(7)),
            ac=int(m.group(8)), speed=int(m.group(9)), glyph=m.group(10), hd=(int(m.group(11)), int(m.group(12))),
            attacks=attacks, level=int(m.group(14))))
        if len(creatures) > 1 and text[m.end():m.end() + 40].lstrip().startswith(");"):
            break
    return creatures


def bits(value: int) -> list[str]:
    return [f"0x{1 << b:x}" for b in range(32) if value >> b & 1]


MOVE_BITS = 0x0000003F       # how it moves (attack only, normal, only magic, random): one ability
NOT_ABILITIES = (0xFF800000  # treasure drops (small objects, carries objects or gold, amounts) and the win bit
                 | 0x000000C0)  # bits 6-7: no meaning upstream (Umoria config.cpp CM_*; VMS sets 0x80 on one mold)


def abilities(c: dict) -> list[tuple[str, bool]]:
    """What the creature itself does: each attack type, each spell, its way of
    moving and each other movement behaviour, with whether the engine
    implements it. Its reactions to the player's attacks (cdefense) are a
    player-side feature, not counted (maintainer, 2026-11-02)."""
    out = [(f"attack {k}", k in SUPPORTED_ATTACKS) for k in sorted({a[0] for a in c["attacks"]} - {0, 99})]   # 0, 99: no attack
    out += [(f"spell {b}", int(b, 16) & SUPPORTED_SPELLS != 0) for b in bits(c["spells"] & ~0x0F)]
    if c["cmove"] & MOVE_BITS:
        out.append(("movement", True))
    out += [(f"cmove {b}", int(b, 16) & SUPPORTED_CMOVE != 0) for b in bits(c["cmove"] & ~MOVE_BITS & ~NOT_ABILITIES)]
    return out


def missing(c: dict) -> list[str]:
    return [name for name, ok in abilities(c) if not ok]


# In today's roster with most abilities missing: kept, degraded (maintainer,
# 2026-11-02: "keep all"). A creature added to the roster later is asked about.
KEPT = {"Blubbering Icky-Thing", "Poltergeist", "Radiation Eye", "Bloodshot Eye", "Lost Soul", "Disenchanter Mold",
        "Giant White Dragon Fly", "Quythulg", "Banshee", "Ghost", "Lich", "King Lich", "Emperor Lich", "Evil Iggy",
        "Balrog"}


def mostly_missing(c: dict) -> bool:
    """More than half its abilities not implemented yet: not added (asked
    about if it is in today's roster). Otherwise it plays, the missing ones
    degraded, and they go to the backlog (maintainer, 2026-11-02)."""
    have = abilities(c)
    return bool(have) and 2 * len(missing(c)) > len(have)


# VMS spellings of creatures Umoria (and so Moria8's tiers) name otherwise.
ALIASES = {"Giant White Lice": "Giant White Louse", "Giant Black Lice": "Giant Black Louse",
           "Large Grey Snake": "Large Green Snake", "Urik-Hai Orc": "Uruk-Hai Orc",
           "Quythulg": "Quylthulg", "Ogre Magi": "Ogre Mage"}


def norm(name: str) -> str:
    """Names across VMS, Umoria and Moria8 spellings (aliases, case, hyphens, a plural)."""
    key = re.sub(r"[^a-z]", "", ALIASES.get(name, name).lower())
    return key[:-1] if key.endswith("s") else key


def todays_roster(root: Path) -> set[str]:
    names = set()
    for tier in sorted((root / "platforms/commodore/c64/creature_data").glob("tier[0-4].s")):
        names |= {norm(n) for n in re.findall(r'tier\d_crn_\d+: \.text "([^"]+)"', tier.read_text())}
    return names


def width(values: list[int]) -> int:
    lo, hi = min(values), max(values)
    if lo >= 0:
        return 1 if hi < 0x100 else 2 if hi < 0x10000 else 4
    return 1 if -0x80 <= lo and hi < 0x80 else 2


def main() -> int:
    parser = argparse.ArgumentParser(prog="build_catalog")
    parser.add_argument("--out", type=Path, default=Path("build/catalog"))
    args = parser.parse_args()
    source = Path(os.environ.get("VMS_SRC", ""))
    if not (source / "include" / "values.inc").is_file():
        print("ERROR: set VMS_SRC to the VMS Moria source directory (holding include/values.inc)", file=sys.stderr)
        return 1
    creatures = parse_vms(source)
    assert len(creatures) == 279, f"VMS max_creatures is 279, parsed {len(creatures)}"
    levels = [c["level"] for c in creatures]
    assert levels == sorted(levels), "VMS c_list must be sorted by level (m_level assumes it)"
    normal = creatures[:-WIN_MON_TOT]
    assert max(c["level"] for c in normal) <= MAX_MONS_LEVEL, "a normal creature is deeper than max_mons_level"

    # The shared attack table: distinct (type, verb, dice, sides), 1-based (0 = none).
    table = sorted({a for c in creatures for a in c["attacks"]})
    index_of = {a: i + 1 for i, a in enumerate(table)}
    assert len(table) < 256 and max(len(c["attacks"]) for c in creatures) <= 4

    # Names: their own Huffman tree, in the game decoder's format.
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

    # Availability and the level index (available creatures per level).
    today = todays_roster(Path(__file__).resolve().parent.parent)
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
    counts = [sum(1 for i, c in enumerate(creatures) if c["level"] == lvl and avail[i] and i not in win)
              for lvl in range(MAX_MONS_LEVEL + 1)]
    bitmap = [0] * ((len(creatures) + 7) // 8)
    for i, ok in enumerate(avail):
        if ok:
            bitmap[i // 8] |= 1 << (i % 8)

    # Record layout: field widths from the data.
    fields = [("glyph", 1), ("colour", 1), ("level", 1), ("hd_num", width([c["hd"][0] for c in creatures])),
              ("hd_sides", width([c["hd"][1] for c in creatures])), ("ac", 1),
              ("sleep", width([c["sleep"] for c in creatures])), ("aaf", 1), ("speed", width([c["speed"] for c in creatures])),
              ("mexp", width([c["mexp"] for c in creatures])), ("cmove", 4), ("spells", 4),
              ("cdefense", 2), ("attacks", 4), ("name", 2)]
    for name, key in (("level", "level"), ("ac", "ac"), ("aaf", "aaf")):
        assert width([c[key] for c in creatures]) == 1, f"{name} needs more than a byte"
    assert max(c["hd"][0] * c["hd"][1] for c in creatures) < 0x10000, "HP must fit 16 bits"
    record = sum(w for _, w in fields)

    def le(value: int, n: int) -> list[int]:
        return [(value >> (8 * k)) & 0xFF for k in range(n)]

    rows = []
    for i, c in enumerate(creatures):
        atk = [index_of[a] for a in c["attacks"]] + [0] * (4 - len(c["attacks"]))
        values = dict(glyph=pc.char_to_screencode(c["glyph"]), colour=pc.assign_color(c["name"]), level=c["level"],
                      hd_num=c["hd"][0], hd_sides=c["hd"][1], ac=c["ac"], sleep=c["sleep"], aaf=c["aaf"],
                      speed=c["speed"] & 0xFF, mexp=c["mexp"], cmove=c["cmove"], spells=c["spells"],
                      cdefense=c["cdefense"], name=name_offsets[i])
        row = []
        for name, w in fields:
            row += atk if name == "attacks" else le(values[name], w)
        assert len(row) == record
        rows.append(row)

    args.out.mkdir(parents=True, exist_ok=True)
    out = ["// Generated by tools/build_catalog.py from VMS Moria 4.8 c_list. Do not edit.",
           f".const CATALOG_COUNT = {len(creatures)}", f".const CATALOG_RECORD_SIZE = {record}",
           f".const CATALOG_MAX_MONS_LEVEL = {MAX_MONS_LEVEL}", f".const CATALOG_WIN_MON_TOT = {WIN_MON_TOT}"]
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
        out.append("    .byte " + ", ".join(f"${b:02x}" for b in name_bytes[k:k + 16]))
    out.append("catalog_level_counts:   // available normal creatures per level 0-40")
    out.append("    .byte " + ", ".join(str(n) for n in counts))
    out.append("catalog_available:      // bit i%8 of byte i/8: creature i spawns")
    out.append("    .byte " + ", ".join(f"${b:02x}" for b in bitmap))
    (args.out / "catalog.s").write_text("\n".join(out) + "\n")

    sizes = {"records": record * len(creatures), "attack_table": 4 * (len(table) + 1),
             "name_tree": len(left) + len(right), "names": len(name_bytes),
             "level_counts": len(counts), "availability_bitmap": len(bitmap)}
    sizes["catalog_total"] = sizes["records"] + sizes["attack_table"] + sizes["name_tree"] + sizes["names"]
    sizes["resident_index"] = sizes["level_counts"] + sizes["availability_bitmap"]
    by_band = {}
    for lo, hi in ((0, 0), (1, 5), (6, 10), (11, 20), (21, 30), (31, 40), (41, 100)):
        idx = [i for i, c in enumerate(creatures) if lo <= c["level"] <= hi]
        by_band[f"{lo}-{hi}"] = f"{sum(avail[i] for i in idx)} of {len(idx)}"
    need = collections.Counter(w for why in degraded.values() for w in why)
    report = {
        "creatures": len(creatures), "record_size": record, "fields": fields, "sizes": sizes,
        "ranges": {**{k: [min(c[k] for c in creatures), max(c[k] for c in creatures)]
                      for k in ("sleep", "mexp", "speed", "ac", "aaf", "level")},
                   "hd_num": [min(c["hd"][0] for c in creatures), max(c["hd"][0] for c in creatures)],
                   "hd_sides": [min(c["hd"][1] for c in creatures), max(c["hd"][1] for c in creatures)]},
        "attack_table_entries": len(table),
        "available": sum(avail), "available_by_level": by_band,
        "backlog_abilities": need.most_common(), "degraded": degraded,
        "ask_maintainer": ask, "skipped_not_in_todays_roster": skipped,
        "player_side_defence_gaps": collections.Counter(
            b for c in creatures for b in bits(c["cdefense"] & ~SUPPORTED_CDEFENSE)).most_common(),
        "win_creatures": [{"name": creatures[i]["name"], "level": creatures[i]["level"], "available": avail[i],
                           "missing": missing(creatures[i])} for i in sorted(win)],
    }
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
            for mine, their in (("level", "dlvl"), ("mexp", "xp"), ("ac", "ac"), ("aaf", "aaf"),
                                ("cmove", "cmove"), ("spells", "spell"), ("cdefense", "cdefense")):
                if a[mine] != b[their]:
                    diffs.append(f"{i} {a['name']}: {mine} VMS {a[mine]} vs Umoria {b[their]}")
            if a["hd"] != (b["hd_num"], b["hd_sides"]):
                diffs.append(f"{i} {a['name']}: hd VMS {a['hd']} vs Umoria {(b['hd_num'], b['hd_sides'])}")
        report["umoria_check"] = {"count": [len(creatures), len(theirs)], "differences": len(diffs),
                                  "first": diffs[:60]}
    (args.out / "catalog.json").write_text(json.dumps(report, indent=1))
    print(f"catalog: {len(creatures)} creatures, {record}-byte records, {len(table)} attacks, "
          f"{sizes['catalog_total']} bytes far + {sizes['resident_index']} resident; "
          f"{sum(avail)} available ({len(degraded)} with degraded abilities), {len(ask)} to ask about, "
          f"{len(skipped)} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
