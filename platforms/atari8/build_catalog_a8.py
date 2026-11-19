#!/usr/bin/env python3
"""Build Wave 5.3 57-byte Atari 8-bit MONSTER.CAT records and DOS 2.5 sector stream.

Layout per 57-byte record (A8_CATALOG_RECORD_SIZE = 57):
  - 0..1  (2 B):  catalog ID (little-endian lo, hi)
  - 2..22 (21 B): legacy SoA fields (platforms/shared/catalog/catalog_fields.s)
  - 23..48 (26 B): NUL-padded screen-code name (CATALOG_RECORD_NAME = 23 preserved)
  - 49..56 (8 B): Phase 5 extended SoA fields (platforms/shared/catalog/catalog_ext_fields.s)

Two 57-byte records (114 B) fit inside each 125-byte DOS 2.5 sector with 0 straddles,
keeping MONSTER.CAT at exactly 140 sectors (139 * 125 + 57 = 17,432 B, +0 .atr sectors
and 0 130XE catalog slot changes). Contains zero external host paths.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.dont_write_bytecode = True

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent.parent
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

import catalog_disk  # noqa: E402

ATARI_MEMORY_ASM = SCRIPT_DIR / "memory.s"
ATARI_CATALOG_ASM = SCRIPT_DIR / "monster_catalog_a8.s"
BASE_RECORD_SIZE = 49
EXT_RECORD_SIZE = 8
A8_RECORD_SIZE = BASE_RECORD_SIZE + EXT_RECORD_SIZE  # 57 B


def _atari_consts() -> dict[str, int]:
    return catalog_disk.consts(ATARI_MEMORY_ASM) | catalog_disk.consts(ATARI_CATALOG_ASM)


def records_57() -> list[bytes]:
    """Return all 279 57-byte Atari monster catalog records."""
    a8 = _atari_consts()
    assert a8["A8_CATALOG_RECORD_SIZE"] == A8_RECORD_SIZE, (
        a8["A8_CATALOG_RECORD_SIZE"],
        A8_RECORD_SIZE,
    )
    base_recs = catalog_disk.records(phase5=False)
    ext_recs = catalog_disk.ext_records()
    assert len(base_recs) == len(ext_recs) == 279, (len(base_recs), len(ext_recs))
    out: list[bytes] = []
    for idx, (base, ext) in enumerate(zip(base_recs, ext_recs)):
        assert len(base) == BASE_RECORD_SIZE, (idx, len(base))
        assert len(ext) == EXT_RECORD_SIZE, (idx, len(ext))
        assert (base[0] | (base[1] << 8)) == idx, idx
        out.append(base + ext)
    return out


def atari_sector_bytes() -> bytes:
    """Return headerless 140-sector DOS 2.5 MONSTER.CAT payload (17,432 B)."""
    a8 = _atari_consts()
    per = a8["A8_CATALOG_RECORDS_PER_SECTOR"]
    sec_data = a8["A8_CATALOG_SECTOR_DATA"]
    expected_sectors = a8["A8_CATALOG_SECTORS"]
    recs = records_57()
    sectors = -(-len(recs) // per)
    assert sectors == expected_sectors == 140, (sectors, expected_sectors)
    out = bytearray()
    for sec in range(sectors):
        body = b"".join(recs[sec * per : (sec + 1) * per])
        assert len(body) <= sec_data, (sec, len(body), sec_data)
        if sec < sectors - 1:
            out += body + bytes(sec_data - len(body))
        else:
            out += body
    return bytes(out)


def selftest() -> int:
    recs = records_57()
    assert len(recs) == 279
    assert all(len(r) == 57 for r in recs)
    raw = b"".join(recs)
    assert len(raw) == 279 * 57 == 15903
    sec_blob = atari_sector_bytes()
    assert len(sec_blob) == 139 * 125 + 57 == 17432
    assert -(-len(sec_blob) // 125) == 140
    # Spot-check record 0 and record 278 (Balrog) IDs + non-zero ext slices
    assert recs[0][:2] == b"\x00\x00"
    assert recs[278][:2] == (278).to_bytes(2, "little")
    assert any(b != 0 for r in recs for b in r[49:57]), "extended catalog slice is all zero"
    print("Atari 8-bit 57B MONSTER.CAT builder self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path, help="Output MONSTER.CAT path")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    if args.output is None:
        parser.error("output path is required unless --selftest is passed")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(atari_sector_bytes())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
