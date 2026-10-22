#!/usr/bin/env python3
"""Build a 130 KB Enhanced Density Atari DOS 2.5 compatible .atr disk image."""

from __future__ import annotations

import argparse
import struct
import sys
import tempfile
from pathlib import Path


SECTOR_SIZE = 128
DATA_BYTES_PER_SECTOR = 125
TOTAL_SECTORS = 1040
MAX_FILE_SECTOR = 1023
VTOC_SECTOR = 360
DIR_START_SECTOR = 361
DIR_END_SECTOR = 368
VTOC2_SECTOR = 1024
ATR_HEADER_SIZE = 16
ATR_IMAGE_SIZE = ATR_HEADER_SIZE + TOTAL_SECTORS * SECTOR_SIZE


def format_83(filename: str) -> bytes:
    upper = filename.upper()
    if "." in upper:
        stem, ext = upper.split(".", 1)
    else:
        stem, ext = upper, ""
    if len(stem) > 8 or len(ext) > 3:
        raise ValueError(f"Filename {filename!r} exceeds DOS 2.5 8.3 limit")
    return (stem.ljust(8) + ext.ljust(3)).encode("ascii")


def convert_lf_to_atascii(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\x9b")


class AtrBuilder:
    def __init__(self) -> None:
        self.sectors = [bytearray(SECTOR_SIZE) for _ in range(TOTAL_SECTORS + 1)]
        self.allocated = set(range(1, 4)) | set(range(VTOC_SECTOR, DIR_END_SECTOR + 1)) | {VTOC2_SECTOR}
        self.dir_entries: list[tuple[int, int, int, bytes]] = []

    def install_boot(self, boot_prg: bytes) -> None:
        # Strip 2-byte Kick Assembler PRG load address header ($00, $08) if present
        if len(boot_prg) == 386 and boot_prg[:2] == b"\x00\x08":
            payload = boot_prg[2:]
        elif len(boot_prg) <= 384:
            payload = boot_prg.ljust(384, b"\x00")
        else:
            raise ValueError(f"Boot payload must be <= 384 bytes (got {len(boot_prg)})")
        for i in range(3):
            self.sectors[1 + i][:] = payload[i * SECTOR_SIZE : (i + 1) * SECTOR_SIZE]

    def _alloc_sectors(self, count: int, contiguous: bool = False) -> list[int]:
        if count <= 0:
            raise ValueError("File must allocate at least 1 sector")
        if contiguous:
            run: list[int] = []
            for sec in range(DIR_END_SECTOR + 1, MAX_FILE_SECTOR + 1):
                if sec not in self.allocated:
                    run.append(sec)
                    if len(run) == count:
                        for s in run:
                            self.allocated.add(s)
                        return run
                else:
                    run.clear()
            raise RuntimeError(f"No contiguous run of {count} sectors available below {MAX_FILE_SECTOR + 1}")

        chosen: list[int] = []
        for sec in range(4, MAX_FILE_SECTOR + 1):
            if sec not in self.allocated:
                chosen.append(sec)
                if len(chosen) == count:
                    for s in chosen:
                        self.allocated.add(s)
                    return chosen
        raise RuntimeError(f"Disk full: needed {count} sectors below {MAX_FILE_SECTOR + 1}")

    def add_file(self, dos_name: str, payload: bytes, contiguous: bool = False) -> None:
        file_idx = len(self.dir_entries)
        if file_idx >= 64:
            raise RuntimeError("DOS 2.5 directory full (max 64 files)")
        name_83 = format_83(dos_name)
        if not payload:
            payload = b"\x00"
        num_sectors = (len(payload) + DATA_BYTES_PER_SECTOR - 1) // DATA_BYTES_PER_SECTOR
        sec_list = self._alloc_sectors(num_sectors, contiguous=contiguous)

        for idx, sec in enumerate(sec_list):
            chunk = payload[idx * DATA_BYTES_PER_SECTOR : (idx + 1) * DATA_BYTES_PER_SECTOR]
            next_sec = sec_list[idx + 1] if idx + 1 < len(sec_list) else 0
            buf = self.sectors[sec]
            buf[: len(chunk)] = chunk
            if len(chunk) < DATA_BYTES_PER_SECTOR:
                buf[len(chunk) : DATA_BYTES_PER_SECTOR] = b"\x00" * (DATA_BYTES_PER_SECTOR - len(chunk))
            buf[0x7D] = len(chunk)
            buf[0x7E] = ((file_idx & 0x3F) << 2) | ((next_sec >> 8) & 0x03)
            buf[0x7F] = next_sec & 0xFF

        uses_high = any(s >= 720 for s in sec_list)
        flags = 0x03 if uses_high else 0x42
        self.dir_entries.append((flags, num_sectors, sec_list[0], name_83))

    def add_preallocated_empty_slot(self, dos_name: str, num_sectors: int) -> None:
        file_idx = len(self.dir_entries)
        if file_idx >= 64:
            raise RuntimeError("DOS 2.5 directory full (max 64 files)")
        name_83 = format_83(dos_name)
        sec_list = self._alloc_sectors(num_sectors, contiguous=True)

        for idx, sec in enumerate(sec_list):
            next_sec = 0 if idx == 0 else (sec_list[idx + 1] if idx + 1 < len(sec_list) else 0)
            buf = self.sectors[sec]
            buf[:DATA_BYTES_PER_SECTOR] = b"\x00" * DATA_BYTES_PER_SECTOR
            # Sector 0 has $7D == 0 (empty slot marker) and 10-bit next_sec == 0
            buf[0x7D] = 0
            buf[0x7E] = ((file_idx & 0x3F) << 2) | ((next_sec >> 8) & 0x03)
            buf[0x7F] = next_sec & 0xFF

        uses_high = any(s >= 720 for s in sec_list)
        flags = 0x03 if uses_high else 0x42
        self.dir_entries.append((flags, num_sectors, sec_list[0], name_83))

    def _finalize_vtoc_and_dir(self) -> None:
        # Write directory entries into Sectors 361..368
        for idx, (flags, count, start_sec, name_83) in enumerate(self.dir_entries):
            dir_sec = DIR_START_SECTOR + (idx // 8)
            offset = (idx % 8) * 16
            entry = struct.pack("<BHH11s", flags, count, start_sec, name_83)
            self.sectors[dir_sec][offset : offset + 16] = entry

        # VTOC (Sector 360): sectors 0..719 bitmap at offsets 10..99
        vtoc = self.sectors[VTOC_SECTOR]
        vtoc[0] = 0x02
        total_low = 707
        free_low = sum(1 for s in range(4, 720) if s not in self.allocated)
        struct.pack_into("<HH", vtoc, 1, total_low, free_low)
        for sec in range(0, 720):
            byte_off = 10 + (sec // 8)
            bit_mask = 0x80 >> (sec % 8)
            if sec != 0 and sec not in self.allocated:
                vtoc[byte_off] |= bit_mask

        # VTOC2 (Sector 1024): sectors 48..1023 bitmap at offsets 0..121
        vtoc2 = self.sectors[VTOC2_SECTOR]
        for sec in range(48, 1024):
            byte_off = (sec - 48) // 8
            bit_mask = 0x80 >> ((sec - 48) % 8)
            if sec not in self.allocated:
                vtoc2[byte_off] |= bit_mask
        free_high = sum(1 for s in range(720, 1024) if s not in self.allocated)
        struct.pack_into("<H", vtoc2, 122, free_high)

    def to_bytes(self) -> bytes:
        self._finalize_vtoc_and_dir()
        paragraphs = (TOTAL_SECTORS * SECTOR_SIZE) // 16
        header = struct.pack("<HHHHBBH4x", 0x0296, paragraphs & 0xFFFF, SECTOR_SIZE, (paragraphs >> 16) & 0xFFFF, 0, 0, 0)
        body = b"".join(bytes(self.sectors[s]) for s in range(1, TOTAL_SECTORS + 1))
        image = header + body
        assert len(image) == ATR_IMAGE_SIZE
        return image


def build_release_atr(build_dir: Path, root_dir: Path, out_atr: Path) -> None:
    builder = AtrBuilder()
    builder.install_boot((build_dir / "boot.prg").read_bytes())

    # Rule 7 compliance files (LF -> $9B ATASCII EOL)
    builder.add_file("LICENSE.TXT", convert_lf_to_atascii((root_dir / "data" / "LICENSE").read_bytes()))
    builder.add_file("SRCOFFER.TXT", convert_lf_to_atascii((root_dir / "data" / "SOURCE-OFFER").read_bytes()))

    # Resident, RuntimeBanked, Overlays, Tiers, and Title Art
    # (Program disk never carries MORIA8.ID or save slots; saves require a
    # separate Save Disk initialized via Disk Setup.)
    asset_files = [
        ("MORIA8.RES", build_dir / "MORIA8.RES"),
        ("ATARI.BNK", build_dir / "ATARI.BNK"),
        ("OVL.STA", build_dir / "OVL.STA"),
        ("OVL.TWN", build_dir / "OVL.TWN"),
        ("OVL.DTH", build_dir / "OVL.DTH"),
        ("OVL.MDL", build_dir / "OVL.MDL"),
        ("OVL.HLP", build_dir / "OVL.HLP"),
        ("OVL.UI", build_dir / "OVL.UI"),
        ("OVL.ITM", build_dir / "OVL.ITM"),
        ("OVL.SPL", build_dir / "OVL.SPL"),
        ("OVL.CHS", build_dir / "OVL.CHS"),
        ("OVL.GEN", build_dir / "OVL.GEN"),
        ("MONSTER.DB1", build_dir / "MONSTER.DB1"),
        ("MONSTER.DB2", build_dir / "MONSTER.DB2"),
        ("MONSTER.DB3", build_dir / "MONSTER.DB3"),
        ("MONSTER.DB4", build_dir / "MONSTER.DB4"),
        ("TITLE.DAT", build_dir / "TITLE.DAT"),
    ]
    for dos_name, path in asset_files:
        builder.add_file(dos_name, path.read_bytes())

    out_atr.parent.mkdir(parents=True, exist_ok=True)
    out_atr.write_bytes(builder.to_bytes())


def build_blank_atr(out_atr: Path) -> None:
    builder = AtrBuilder()
    out_atr.parent.mkdir(parents=True, exist_ok=True)
    out_atr.write_bytes(builder.to_bytes())


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        builder = AtrBuilder()
        boot_stub = b"\x00\x08\x00\x03\x00\x08\x06\x08" + b"\xea" * 378
        builder.install_boot(boot_stub)
        builder.add_file("LICENSE.TXT", convert_lf_to_atascii(b"LINE1\nLINE2\n"))
        builder.add_file("SRCOFFER.TXT", convert_lf_to_atascii(b"OFFER\n"))
        builder.add_file("MORIA8.ID", b"M8SAVE")
        builder.add_file("MORIA8.RES", b"\x00\x0c" + bytes(range(256)) * 175)
        builder.add_preallocated_empty_slot("HISCORE.DAT", 2)
        for slot in range(4):
            builder.add_preallocated_empty_slot(f"SAVE{slot}.SAV", 56)

        atr_bytes = builder.to_bytes()
        if len(atr_bytes) != ATR_IMAGE_SIZE:
            print(f"FAIL: expected ATR size {ATR_IMAGE_SIZE}, got {len(atr_bytes)}", file=sys.stderr)
            return 1
        if atr_bytes[:2] != b"\x96\x02":
            print("FAIL: invalid ATR magic header", file=sys.stderr)
            return 1
        if any(s > MAX_FILE_SECTOR and s != VTOC2_SECTOR for s in builder.allocated):
            print("FAIL: allocated sector >= 1024", file=sys.stderr)
            return 1

        # Verify directory entries and SAVE0..3.SAV contiguous pre-allocation
        dir_names: dict[str, tuple[int, int, int, int]] = {}
        for idx in range(64):
            dir_sec = DIR_START_SECTOR + (idx // 8)
            sec_off = ATR_HEADER_SIZE + (dir_sec - 1) * SECTOR_SIZE + (idx % 8) * 16
            flags, count, start_sec, raw_name = struct.unpack_from("<BHH11s", atr_bytes, sec_off)
            if flags == 0:
                break
            dir_names[raw_name.decode("ascii")] = (idx, flags, count, start_sec)

        for slot in range(4):
            key = f"SAVE{slot}   SAV"
            if key not in dir_names:
                print(f"FAIL: missing {key} in directory", file=sys.stderr)
                return 1
            file_idx, _flags, count, start_sec = dir_names[key]
            if count != 56:
                print(f"FAIL: {key} count={count}, expected 56", file=sys.stderr)
                return 1
            if start_sec + count - 1 > MAX_FILE_SECTOR:
                print(f"FAIL: {key} crosses sector 1023", file=sys.stderr)
                return 1
            sec0_off = ATR_HEADER_SIZE + (start_sec - 1) * SECTOR_SIZE
            if atr_bytes[sec0_off + 0x7D] != 0:
                print(f"FAIL: {key} sector0[$7D] must be 0 for empty slot", file=sys.stderr)
                return 1
            if (atr_bytes[sec0_off + 0x7E] >> 2) != file_idx:
                print(f"FAIL: {key} sector0[$7E] file_idx mismatch", file=sys.stderr)
                return 1
            sec0_link = ((atr_bytes[sec0_off + 0x7E] & 0x03) << 8) | atr_bytes[sec0_off + 0x7F]
            if sec0_link != 0:
                print(f"FAIL: {key} empty sector0 10-bit link must be 0, got {sec0_link}", file=sys.stderr)
                return 1

        # Verify LICENSE.TXT ATASCII $9B conversion
        lic_idx, _lic_flags, _lic_cnt, lic_sec = dir_names["LICENSE TXT"]
        lic_off = ATR_HEADER_SIZE + (lic_sec - 1) * SECTOR_SIZE
        lic_len = atr_bytes[lic_off + 0x7D]
        if atr_bytes[lic_off : lic_off + lic_len] != b"LINE1\x9bLINE2\x9b":
            print("FAIL: LICENSE.TXT LF -> $9B conversion failed", file=sys.stderr)
            return 1

    print("make_atr.py self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run internal ATR builder self-test.")
    parser.add_argument("--blank-disk", action="store_true", help="Write an uninitialized blank DOS 2.5 .atr image.")
    parser.add_argument("--build-dir", type=Path, help="Directory containing built Atari 8-bit payloads.")
    parser.add_argument("--root-dir", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("-o", "--output", type=Path, help="Output .atr path.")
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    if args.blank_disk:
        if not args.output:
            parser.error("--output is required with --blank-disk")
        build_blank_atr(args.output)
        return 0

    if not args.build_dir or not args.output:
        parser.error("--build-dir and --output are required unless --selftest or --blank-disk is specified")

    build_release_atr(args.build_dir, args.root_dir, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
