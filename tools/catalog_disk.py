#!/usr/bin/env python3
"""The monster catalog's disk files for the C64, Plus/4 and Atari 8-bit.

records OUTDIR IDX_LOAD_ADDRESS
    Write MONSTER.CAT1-4 (PRG files) from the committed catalog sources
    (platforms/shared/catalog: fields, names, index), in the record layout of
    platforms/commodore/common/catalog_records.s.

    It also writes MONSTER.IDX with an empty sector table, for images that
    `fix` completes.

index D64 OUTFILE LOAD_ADDRESS
    Read where MONSTER.CAT1-4 landed on the D64 image and write MONSTER.IDX
    (a PRG loading at LOAD_ADDRESS): the level index, then the track and the
    sector of every record sector, in record order. Run after the record
    files are written and before anything that could move them.

fix D64
    On an image holding MONSTER.CAT1-4 and MONSTER.IDX, rewrite MONSTER.IDX's
    sector table in place for where the records landed on it (the test
    runners' images). An image without them is left alone.

atari OUTFILE
    Write MONSTER.CAT for the Atari 8-bit: the same records,
    A8_CATALOG_RECORDS_PER_SECTOR to each DOS 2.5 sector's data
    (platforms/atari8/monster_catalog_a8.s), no load header. tools/make_atr.py
    writes it contiguous, so record n is in file sector n / 2.

item-raw OUTDIR
    Write headerless ITEM.CAT ('ITM2', <= 7,800 B) from
    platforms/shared/item_catalog/item_cat_data.s into OUTDIR/ITEM.CAT.

item-atari OUTFILE
    Write headerless Atari DOS 2.5 ITEM.CAT payload to OUTFILE.

item-records OUTDIR PRG_LOAD_ADDRESS IDX_LOAD_ADDRESS
    Write Commodore PRG item.cat and empty item.idx into OUTDIR.

item-index D64 OUTFILE LOAD_ADDRESS
    Write item.idx from where item.cat landed on D64.

item-fix D64
    Rewrite item.idx's sector table in place on a D64 carrying item.cat and item.idx.

item-selftest
    Run offline self-tests on ITEM.CAT extraction and disk packing shapes.

docs/MONSTER_CATALOG_DESIGN.md, "C64 and Plus/4" and "Atari 8-bit".
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import huff_encoder as huff  # noqa: E402

CATALOG = ROOT / "platforms/shared/catalog"
ITEM_CATALOG = ROOT / "platforms/shared/item_catalog"
LAYOUT = ROOT / "platforms/commodore/common/catalog_records.s"
ATARI_LAYOUT = ROOT / "platforms/atari8/monster_catalog_a8.s"
FILES = [f"monster.cat{i}" for i in range(1, 5)]
INDEX_FILE = "monster.idx"
ITEM_FILE = "item.cat"
ITEM_INDEX_FILE = "item.idx"
SECTORS_PER_TRACK = [0, *([21] * 17), *([19] * 7), *([18] * 6), *([17] * 5)]


def consts(path: Path) -> dict[str, int]:
    out = {}
    for m in re.finditer(r"^\.const\s+(\w+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)", path.read_text(), re.M):
        v = m.group(2)
        out[m.group(1)] = int(v[1:], 16) if v.startswith("$") else int(v)
    return out


def byte_arrays(text: str) -> dict[str, list[int]]:
    """label -> the .byte values after it, up to the next label."""
    out: dict[str, list[int]] = {}
    label = None
    for line in text.splitlines():
        m = re.match(r"^(\w+):", line)
        if m:
            label = m.group(1)
            out[label] = []
            line = line[m.end():]
        if label and re.match(r"^\s*\.byte\b", line):
            out[label] += [int(v, 16) for v in re.findall(r"\$([0-9A-Fa-f]{2})", line.split("//")[0])]
    return out


def layout() -> dict[str, int]:
    c = consts(LAYOUT)
    idx = consts(CATALOG / "catalog_index.s")
    size = 2 + idx["CATALOG_SOA_FIELDS"] + idx["CATALOG_NAME_MAX"] + 1
    assert c["CATALOG_RECORD_SIZE"] == size, (c["CATALOG_RECORD_SIZE"], size)
    assert c["CATALOG_RECORD_NAME"] == 2 + idx["CATALOG_SOA_FIELDS"]
    per = c["CATALOG_RECORDS_PER_SECTOR"]
    assert c["CATALOG_SECTOR_HEADER"] + per * size <= 254, "records cross a sector"
    sectors = -(-idx["CATALOG_COUNT"] // per)
    assert c["CATALOG_RECORD_SECTORS"] == sectors, (c["CATALOG_RECORD_SECTORS"], sectors)
    assert c["CATALOG_RECORD_FILES"] == len(FILES) == -(-sectors // c["CATALOG_FILE_SECTORS"])
    assert (c["CATALOG_FILE_SECTORS"] * 254) <= 0x1000, "a record file outgrows its 4 KB window"
    return {**c, **idx}


def records() -> list[bytes]:
    lay = layout()
    fields = byte_arrays((CATALOG / "catalog_fields.s").read_text())
    names = re.findall(r"^catn_\d+:.*// (.+?)\s*$", (CATALOG / "catalog_names.s").read_text(), re.M)
    labels = [k for k in fields if k.startswith("cat_cr_")]
    count = lay["CATALOG_COUNT"]
    assert len(labels) == lay["CATALOG_SOA_FIELDS"] and len(names) == count
    out = []
    for n in range(count):
        name = [huff.ascii_to_screencode(ch) for ch in names[n]]
        rec = bytes([n & 0xFF, n >> 8] + [fields[label][n] for label in labels] + name)
        out.append(rec + bytes(lay["CATALOG_RECORD_SIZE"] - len(rec)))
    return out


def write_records(outdir: Path, idx_load: int) -> None:
    lay = layout()
    per, size = lay["CATALOG_RECORDS_PER_SECTOR"], lay["CATALOG_RECORD_SIZE"]
    recs = records()
    sectors = []
    for s in range(lay["CATALOG_RECORD_SECTORS"]):
        body = b"".join(recs[s * per:(s + 1) * per])
        sectors.append(bytes(lay["CATALOG_SECTOR_HEADER"]) + body + bytes(252 - len(body)))
    outdir.mkdir(parents=True, exist_ok=True)
    load = lay["CATALOG_RECORDS_LOAD"]
    for i, name in enumerate(FILES):
        chunk = sectors[i * lay["CATALOG_FILE_SECTORS"]:(i + 1) * lay["CATALOG_FILE_SECTORS"]]
        data = bytearray(b"".join(chunk))
        data[0:2] = bytes([load & 0xFF, load >> 8])   # the first header is the load address
        (outdir / name).write_bytes(bytes(data))
    (outdir / INDEX_FILE).write_bytes(index_bytes(None, idx_load))


def atari_records() -> bytes:
    """MONSTER.CAT's data for the Atari: per DOS 2.5 sector (its data bytes),
    the records in turn, then padding; the last sector holds what is left."""
    a8 = consts(ATARI_LAYOUT)
    per, data = a8["A8_CATALOG_RECORDS_PER_SECTOR"], a8["A8_CATALOG_SECTOR_DATA"]
    recs = records()
    sectors = -(-len(recs) // per)
    assert sectors == a8["A8_CATALOG_SECTORS"], (sectors, a8["A8_CATALOG_SECTORS"])
    out = bytearray()
    for s in range(sectors):
        body = b"".join(recs[s * per:(s + 1) * per])
        out += body + bytes(data - len(body)) if s < sectors - 1 else body
    return bytes(out)


def index_bytes(image: bytes | None, load: int) -> bytes:
    """MONSTER.IDX: the load address, the level index and the sector table of
    the records on ``image`` (zeros without one)."""
    lay = layout()
    index = byte_arrays((CATALOG / "catalog_index.s").read_text())
    data = index["cat_level_raw"] + index["cat_level_playable"] + index["cat_available"]
    count = lay["CATALOG_RECORD_SECTORS"]
    sectors = record_sectors(image) if image is not None else [(0, 0)] * count
    data += [t for t, _ in sectors] + [s for _, s in sectors]
    return bytes([load & 0xFF, load >> 8] + data)


def record_sectors(image: bytes) -> list[tuple[int, int]]:
    lay = layout()
    dirs = directory(image)
    sectors: list[tuple[int, int]] = []
    for name in FILES:
        if name not in dirs:
            raise SystemExit(f"no {name} on the image")
        sectors += chain(image, *dirs[name])
    assert len(sectors) == lay["CATALOG_RECORD_SECTORS"], len(sectors)
    # Each record sector starts with the first record id it holds: a check that
    # the files on this image are the ones the table names.
    per = lay["CATALOG_RECORDS_PER_SECTOR"]
    for s, (t, sec) in enumerate(sectors):
        off = sector_offset(t, sec) + 2 + lay["CATALOG_SECTOR_HEADER"]
        assert image[off] | image[off + 1] << 8 == s * per, (s, t, sec)
    return sectors


def sector_offset(track: int, sector: int) -> int:
    return (sum(SECTORS_PER_TRACK[1:track]) + sector) * 256


def chain(image: bytes, track: int, sector: int) -> list[tuple[int, int]]:
    out = []
    while track:
        out.append((track, sector))
        assert len(out) < 700, "sector chain loops"
        off = sector_offset(track, sector)
        track, sector = image[off], image[off + 1]
    return out


def directory(image: bytes) -> dict[str, tuple[int, int]]:
    out = {}
    for track, sector in chain(image, 18, 1):
        off = sector_offset(track, sector)
        for e in range(8):
            entry = image[off + e * 32: off + e * 32 + 32]
            if entry[2] & 0x07:
                name = bytes(entry[5:21]).rstrip(b"\xa0").decode("latin-1").lower()
                out[name] = (entry[3], entry[4])
    return out


def write_index(d64: Path, out: Path, load: int) -> None:
    out.write_bytes(index_bytes(d64.read_bytes(), load))


def fix_index(d64: Path) -> None:
    image = bytearray(d64.read_bytes())
    dirs = directory(bytes(image))
    if INDEX_FILE not in dirs or not all(name in dirs for name in FILES):
        return
    blocks = chain(bytes(image), *dirs[INDEX_FILE])
    assert len(blocks) == 1, f"{INDEX_FILE} spans {len(blocks)} blocks"
    off = sector_offset(*blocks[0])
    old = image[off + 2: off + 4]
    data = index_bytes(bytes(image), old[0] | old[1] << 8)
    assert image[off] == 0 and image[off + 1] == len(data) + 1, "MONSTER.IDX is not the expected size"
    image[off + 2: off + 2 + len(data)] = data
    d64.write_bytes(bytes(image))


def item_catalog_bytes() -> bytes:
    """Return packed 'ITM2' ITEM.CAT bytes from platforms/shared/item_catalog/item_cat_data.s."""
    lay = consts(ITEM_CATALOG / "item_cat_layout.s")
    arrays = byte_arrays((ITEM_CATALOG / "item_cat_data.s").read_text())
    data = bytes(arrays["item_cat_data"])
    assert data[:4] == b"ITM2", "item_cat_data.s must begin with 'ITM2' magic"
    assert len(data) == lay["ITMCAT_TOTAL_SIZE"] <= lay["ITMCAT_SIZE_CAP"], (
        len(data),
        lay["ITMCAT_TOTAL_SIZE"],
        lay["ITMCAT_SIZE_CAP"],
    )
    return data


def write_item_raw(outdir: Path) -> Path:
    """Write headerless binary ITEM.CAT into outdir (e.g. build/)."""
    outdir.mkdir(parents=True, exist_ok=True)
    out = outdir / "ITEM.CAT"
    out.write_bytes(item_catalog_bytes())
    return out


def item_atari_bytes() -> bytes:
    """Return Atari DOS 2.5 contiguous ITEM.CAT payload (125 bytes/sector, no PRG header)."""
    return item_catalog_bytes()


def item_sectors(image: bytes, expected_len: int) -> list[tuple[int, int]]:
    """Locate the D64 track/sector chain for item.cat and verify its 'ITM2' header."""
    dirs = directory(image)
    if ITEM_FILE not in dirs:
        raise SystemExit(f"no {ITEM_FILE} on the image")
    sectors = chain(image, *dirs[ITEM_FILE])
    expected_sectors = -(-(expected_len + 2) // 254)
    assert len(sectors) == expected_sectors, (len(sectors), expected_sectors)
    off = sector_offset(*sectors[0]) + 4  # skip T/S link (2B) + PRG load address (2B)
    assert image[off:off + 4] == b"ITM2", "item.cat on image missing 'ITM2' header"
    return sectors


def item_index_bytes(image: bytes | None, load: int) -> bytes:
    """item.idx PRG: [load_lo, load_hi, size_lo, size_hi, sector_count, T..., S...]."""
    blob = item_catalog_bytes()
    sector_count = -(-(len(blob) + 2) // 254)
    sectors = item_sectors(image, len(blob)) if image is not None else [(0, 0)] * sector_count
    header = [load & 0xFF, load >> 8, len(blob) & 0xFF, len(blob) >> 8, sector_count]
    data = header + [t for t, _ in sectors] + [s for _, s in sectors]
    assert len(data) - 2 <= 254, "item.idx exceeds one 1541 sector"
    return bytes(data)


def write_item_records(outdir: Path, prg_load: int, idx_load: int) -> None:
    """Write Commodore PRG item.cat and empty item.idx into outdir (e.g. build/)."""
    outdir.mkdir(parents=True, exist_ok=True)
    blob = item_catalog_bytes()
    (outdir / ITEM_FILE).write_bytes(bytes([prg_load & 0xFF, prg_load >> 8]) + blob)
    (outdir / ITEM_INDEX_FILE).write_bytes(item_index_bytes(None, idx_load))


def write_item_index(d64: Path, out: Path, load: int) -> None:
    """Write item.idx from where item.cat landed on D64."""
    out.write_bytes(item_index_bytes(d64.read_bytes(), load))


def fix_item_index(d64: Path) -> None:
    """Rewrite item.idx's sector table in place on a D64 carrying item.cat and item.idx."""
    image = bytearray(d64.read_bytes())
    dirs = directory(bytes(image))
    if ITEM_INDEX_FILE not in dirs or ITEM_FILE not in dirs:
        return
    blocks = chain(bytes(image), *dirs[ITEM_INDEX_FILE])
    assert len(blocks) == 1, f"{ITEM_INDEX_FILE} spans {len(blocks)} blocks"
    off = sector_offset(*blocks[0])
    old = image[off + 2: off + 4]
    data = item_index_bytes(bytes(image), old[0] | old[1] << 8)
    assert image[off] == 0 and image[off + 1] == len(data) + 1, "item.idx is not the expected size"
    image[off + 2: off + 2 + len(data)] = data
    d64.write_bytes(bytes(image))


def item_selftest() -> None:
    """Verify ITEM.CAT byte extraction, D64 index table shape, and Atari payload offline."""
    blob = item_catalog_bytes()
    assert blob[:4] == b"ITM2" and len(blob) <= 7800
    assert item_atari_bytes() == blob
    idx = item_index_bytes(None, 0xCF00)
    expected_secs = -(-(len(blob) + 2) // 254)
    assert idx[0:2] == bytes([0x00, 0xCF])
    assert (idx[2] | (idx[3] << 8)) == len(blob)
    assert idx[4] == expected_secs
    assert len(idx) == 5 + 2 * expected_secs
    print(f"catalog_disk item selftest PASSED: ITEM.CAT={len(blob)} B, D64={expected_secs} sectors, idx={len(idx)} B")


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "records":
        write_records(Path(sys.argv[2]), int(sys.argv[3], 0))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "fix":
        fix_index(Path(sys.argv[2]))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "atari":
        Path(sys.argv[2]).write_bytes(atari_records())
        return 0
    if len(sys.argv) == 5 and sys.argv[1] == "index":
        write_index(Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4], 0))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "item-raw":
        write_item_raw(Path(sys.argv[2]))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "item-atari":
        Path(sys.argv[2]).parent.mkdir(parents=True, exist_ok=True)
        Path(sys.argv[2]).write_bytes(item_atari_bytes())
        return 0
    if len(sys.argv) == 5 and sys.argv[1] == "item-records":
        write_item_records(Path(sys.argv[2]), int(sys.argv[3], 0), int(sys.argv[4], 0))
        return 0
    if len(sys.argv) == 5 and sys.argv[1] == "item-index":
        write_item_index(Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4], 0))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "item-fix":
        fix_item_index(Path(sys.argv[2]))
        return 0
    if len(sys.argv) == 2 and sys.argv[1] == "item-selftest":
        item_selftest()
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
