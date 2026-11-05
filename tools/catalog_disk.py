#!/usr/bin/env python3
"""The monster catalog's disk files for the C64 and Plus/4.

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

docs/MONSTER_CATALOG_DESIGN.md, "C64 and Plus/4".
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import huff_encoder as huff  # noqa: E402

CATALOG = ROOT / "platforms/shared/catalog"
LAYOUT = ROOT / "platforms/commodore/common/catalog_records.s"
FILES = [f"monster.cat{i}" for i in range(1, 5)]
INDEX_FILE = "monster.idx"
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


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "records":
        write_records(Path(sys.argv[2]), int(sys.argv[3], 0))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "fix":
        fix_index(Path(sys.argv[2]))
        return 0
    if len(sys.argv) == 5 and sys.argv[1] == "index":
        write_index(Path(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4], 0))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
