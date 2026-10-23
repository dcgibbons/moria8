#!/usr/bin/env python3
"""make_ssd.py — Build an 80-track single-sided Acorn DFS (.ssd) disk image.

Acorn DFS 80-track single-sided geometry:
  - 80 tracks x 10 sectors/track x 256 bytes/sector = 800 sectors (204,800 bytes)
  - Sector 0 ($0000-$00FF): title[0:8] + up to 31 x 8-byte filename/directory entries
  - Sector 1 ($0100-$01FF): title[8:12], cycle, count*8, opt/sectors_hi, sectors_lo
                            + up to 31 x 8-byte address/length/start-sector entries
  - Catalogue entries are stored in descending start-sector order (highest sector
    at index 0, sector 2 at index N-1), matching native Acorn 1770 DFS layout.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

SECTOR_SIZE = 256
TOTAL_SECTORS = 800
IMAGE_SIZE = TOTAL_SECTORS * SECTOR_SIZE
MAX_FILES = 31


@dataclass(frozen=True)
class DfsFileSpec:
    name: str
    directory: str
    locked: bool
    load_addr: int
    exec_addr: int
    data: bytes


def parse_file_spec(spec: str) -> DfsFileSpec:
    # Format: [DIR.]NAME=PATH[:LOAD_HEX[:EXEC_HEX]]
    if "=" not in spec:
        raise ValueError(f"invalid file spec {spec!r} (expected NAME=PATH[:LOAD[:EXEC]])")
    lhs, rhs = spec.split("=", 1)
    parts = rhs.split(":")
    host_path = Path(parts[0])
    load_addr = int(parts[1], 16) if len(parts) >= 2 and parts[1] else 0xFFFF0E00
    exec_addr = int(parts[2], 16) if len(parts) >= 3 and parts[2] else load_addr

    if "." in lhs:
        directory, name = lhs.split(".", 1)
    else:
        directory, name = "$", lhs

    if len(directory) != 1:
        raise ValueError(f"DFS directory must be 1 char: {lhs!r}")
    if not (1 <= len(name) <= 7):
        raise ValueError(f"DFS filename must be 1..7 chars: {name!r}")

    data = host_path.read_bytes()
    return DfsFileSpec(
        name=name.upper(),
        directory=directory,
        locked=False,
        load_addr=load_addr,
        exec_addr=exec_addr,
        data=data,
    )


def build_ssd_image(
    files: list[DfsFileSpec],
    *,
    title: str = "MORIA8",
    boot_opt: int = 3,
    cycle: int = 0,
) -> bytes:
    if len(files) > MAX_FILES:
        raise ValueError(f"DFS catalogue supports at most {MAX_FILES} files (got {len(files)})")
    if not (0 <= boot_opt <= 3):
        raise ValueError(f"boot_opt must be 0..3 (got {boot_opt})")

    image = bytearray(IMAGE_SIZE)

    # Allocate sectors sequentially starting at sector 2
    placed: list[tuple[DfsFileSpec, int]] = []
    next_sector = 2
    for f in files:
        length = len(f.data)
        sectors_needed = (length + SECTOR_SIZE - 1) // SECTOR_SIZE if length > 0 else 1
        if next_sector + sectors_needed > TOTAL_SECTORS:
            raise ValueError(
                f"disk full placing {f.name}: needs {sectors_needed} sectors at {next_sector}/{TOTAL_SECTORS}"
            )
        start_offset = next_sector * SECTOR_SIZE
        image[start_offset : start_offset + length] = f.data
        placed.append((f, next_sector))
        next_sector += sectors_needed

    # Acorn DFS stores catalogue entries in descending start-sector order
    placed.reverse()

    # Sector 0 & 1 header: 12-byte title (8 bytes in sector 0, 4 bytes in sector 1)
    title_bytes = title.encode("ascii", errors="replace")[:12].ljust(12, b"\x00")
    image[0x000:0x008] = title_bytes[:8]
    image[0x100:0x104] = title_bytes[8:12]
    image[0x104] = cycle & 0xFF
    image[0x105] = len(placed) * 8
    image[0x106] = ((boot_opt & 0x03) << 4) | ((TOTAL_SECTORS >> 8) & 0x03)
    image[0x107] = TOTAL_SECTORS & 0xFF

    for idx, (f, start_sector) in enumerate(placed):
        cat0 = 8 + idx * 8
        cat1 = 0x100 + 8 + idx * 8

        padded_name = f.name.encode("ascii").ljust(7, b" ")
        image[cat0 : cat0 + 7] = padded_name
        dir_byte = ord(f.directory[0]) & 0x7F
        if f.locked:
            dir_byte |= 0x80
        image[cat0 + 7] = dir_byte

        length = len(f.data)
        load_lo = f.load_addr & 0xFFFF
        exec_lo = f.exec_addr & 0xFFFF
        len_lo = length & 0xFFFF

        # Host processor addresses ($FFFFxxxx or 16-bit <= $FFFF) set high bits to 0 or 3;
        # standard Acorn DFS sets bits 16..17 to 3 when >= 0xFFFF0000 else 0.
        load_hi = 0x03 if (f.load_addr & 0xFFFF0000) == 0xFFFF0000 else ((f.load_addr >> 16) & 0x03)
        exec_hi = 0x03 if (f.exec_addr & 0xFFFF0000) == 0xFFFF0000 else ((f.exec_addr >> 16) & 0x03)
        len_hi = (length >> 16) & 0x03
        sec_hi = (start_sector >> 8) & 0x03

        image[cat1 + 0] = load_lo & 0xFF
        image[cat1 + 1] = (load_lo >> 8) & 0xFF
        image[cat1 + 2] = exec_lo & 0xFF
        image[cat1 + 3] = (exec_lo >> 8) & 0xFF
        image[cat1 + 4] = len_lo & 0xFF
        image[cat1 + 5] = (len_lo >> 8) & 0xFF
        image[cat1 + 6] = (exec_hi << 6) | (len_hi << 4) | (load_hi << 2) | sec_hi
        image[cat1 + 7] = start_sector & 0xFF

    return bytes(image)


def build_blank_ssd(output_path: Path, *, title: str = "M8SAVE") -> None:
    img = build_ssd_image([], title=title, boot_opt=0)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(img)


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tdir = Path(tmp)
        f1 = tdir / "boot.txt"
        f2 = tdir / "moria8.bin"
        f1.write_bytes(b"*EXEC !BOOT\r")
        f2.write_bytes(b"\xa9\x00\x60" * 100)

        specs = [
            parse_file_spec(f"!BOOT={f1}:FFFF0000:FFFFFFFF"),
            parse_file_spec(f"MORIA8={f2}:FFFF1900:FFFF1900"),
        ]
        ssd = build_ssd_image(specs, title="MORIA8", boot_opt=3)
        if len(ssd) != IMAGE_SIZE:
            print(f"FAIL: expected {IMAGE_SIZE} bytes, got {len(ssd)}", file=sys.stderr)
            return 1
        if ssd[0x105] != 16:
            print(f"FAIL: expected 2 entries (16), got {ssd[0x105]}", file=sys.stderr)
            return 1
        if ssd[0x106] != 0x33 or ssd[0x107] != 0x20:
            print(f"FAIL: bad sector count/opt bytes: {ssd[0x106]:02X} {ssd[0x107]:02X}", file=sys.stderr)
            return 1
        # Entry 0 is MORIA8 (start sector 3), Entry 1 is !BOOT (start sector 2)
        if ssd[0x008:0x00F] != b"MORIA8 " or ssd[0x108 + 7] != 3:
            print("FAIL: entry 0 mismatch", file=sys.stderr)
            return 1
        if ssd[0x010:0x017] != b"!BOOT  " or ssd[0x110 + 7] != 2:
            print("FAIL: entry 1 mismatch", file=sys.stderr)
            return 1

        blank = build_ssd_image([], title="M8SAVE", boot_opt=0)
        if len(blank) != IMAGE_SIZE or blank[0x105] != 0 or blank[0x106] != 0x03:
            print("FAIL: blank disk header mismatch", file=sys.stderr)
            return 1

    print("make_ssd.py self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run synthetic self-test.")
    parser.add_argument("--blank-disk", type=Path, help="Write a blank formatted 80-track DFS .ssd image.")
    parser.add_argument("--title", default="MORIA8", help="12-char DFS disk title.")
    parser.add_argument("--opt", type=int, default=3, help="DFS *OPT 4 boot option (0..3, default 3 = *EXEC !BOOT).")
    parser.add_argument("output", nargs="?", type=Path, help="Output .ssd file path.")
    parser.add_argument("specs", nargs="*", help="File specs: NAME=PATH[:LOAD_HEX[:EXEC_HEX]]")
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    if args.blank_disk is not None:
        img = build_ssd_image([], title=args.title, boot_opt=0)
        args.blank_disk.parent.mkdir(parents=True, exist_ok=True)
        args.blank_disk.write_bytes(img)
        return 0

    if args.output is None:
        parser.error("output .ssd path is required")

    specs = [parse_file_spec(s) for s in args.specs]
    img = build_ssd_image(specs, title=args.title, boot_opt=args.opt)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(img)
    used_sectors = 2 + sum(
        (len(s.data) + SECTOR_SIZE - 1) // SECTOR_SIZE if len(s.data) > 0 else 1 for s in specs
    )
    print(f"{args.output}: {len(specs)}/{MAX_FILES} files, {used_sectors}/{TOTAL_SECTORS} sectors used")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
