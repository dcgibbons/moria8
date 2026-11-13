#!/usr/bin/env python3
"""Build Commander X16 Cartridge image (.crt, raw NOR-flash .bin, and .json manifest)."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

CART_ROM_BANK_SIZE = 0x4000
CART_ROM_WINDOW_BASE = 0xC000
CART_ROM_BANK_START = 32
CART_BANK_COUNT = 8
CART_IMAGE_SIZE = CART_BANK_COUNT * CART_ROM_BANK_SIZE
CART_DIRECTORY_OFFSET = 0x0100
CART_PAYLOAD_OFFSET = 0x0200
CART_DESCRIPTOR_SIZE = 8
CART_RAM_BANK_NONE = 0xFF
CRT_HEADER_SIZE = 480
CRT_MAGIC = b"CX16 CARTRIDGE\r\n"
CRT_VERSION = b"01.00           "
CRT_BANK_NONE = 0
CRT_BANK_ROM = 1

# (asset_id, name, source_kind, expected_prg_hdr, target_ram_bank, target_dest)
ASSETS: list[tuple[int, str, str, int | None, int, int]] = [
    (0, "MORIA8.PRG", "build", 0x0801, 0, 0x0801),
    (1, "CX16.AUXDATA", "build", 0x6000, 3, 0xA000),
    (2, "CX16.HUFFDATA", "build", 0x8000, 4, 0xA000),
    (3, "OVL.START", "build", 0xA000, 9, 0xA000),
    (4, "OVL.TOWN", "build", 0xA000, 10, 0xA000),
    (5, "OVL.DEATH", "build", 0xA000, 11, 0xA000),
    (6, "OVL.GEN", "build", 0xA000, 12, 0xA000),
    (7, "OVL.HELP", "build", 0xA000, 13, 0xA000),
    (8, "OVL.UI", "build", 0xA000, 14, 0xA000),
    (9, "OVL.ITEMS", "build", 0xA000, 15, 0xA000),
    (10, "OVL.SPELL", "build", 0xA000, 16, 0xA000),
    (11, "OVL.MODAL", "build", 0xA000, 17, 0xA000),
    (12, "OVL.CHEST", "build", 0xA000, 18, 0xA000),
    (13, "OVL.STORAGE", "build", 0xA000, 19, 0xA000),
    (14, "OVL.TITLE", "build", 0xA000, 20, 0xA000),
    (15, "TITLE", "build", 0xA000, 21, 0xA000),
    (16, "MONSTER.CAT", "build", 0xA000, 22, 0xA000),
    (17, "LEGALUI", "build", 0xA000, 23, 0xA000),
    (18, "LICENSE", "data", None, CART_RAM_BANK_NONE, 0x0000),
    (19, "SOURCE-OFFER", "data", None, CART_RAM_BANK_NONE, 0x0000),
]


def parse_sym_file(path: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    if not path.is_file():
        return syms
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line.startswith(".label "):
            continue
        rest = line[len(".label ") :]
        if "=" not in rest:
            continue
        name, val_str = rest.split("=", 1)
        val_str = val_str.split("{", 1)[0].split("//", 1)[0].strip()
        if val_str.startswith("$"):
            syms[name.strip()] = int(val_str[1:], 16)
        elif val_str.isdigit():
            syms[name.strip()] = int(val_str, 10)
    return syms


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pad_ascii_32(text: str) -> bytes:
    raw = text.encode("ascii", errors="replace")[:32]
    return raw.ljust(32, b" ")


def build_crt_header(
    bank_count: int,
    description: str,
    author: str,
    copyright_str: str,
    prg_version: str,
) -> bytes:
    if bank_count <= 0 or bank_count > 224:
        raise ValueError(f"invalid bank count: {bank_count}")
    header = bytearray(CRT_HEADER_SIZE)
    header[0x000:0x010] = CRT_MAGIC
    header[0x010:0x020] = CRT_VERSION
    header[0x020:0x040] = pad_ascii_32(description)
    header[0x040:0x060] = pad_ascii_32(author)
    header[0x060:0x080] = pad_ascii_32(copyright_str)
    header[0x080:0x0A0] = pad_ascii_32(prg_version)
    # 0x0A0..0x0FF reserved = 0x00
    for idx in range(bank_count):
        header[0x100 + idx] = CRT_BANK_ROM
    return bytes(header)


def strip_prg_header(raw: bytes, name: str, expected_hdr: int) -> bytes:
    if len(raw) < 2:
        raise ValueError(f"{name}: PRG shorter than 2 bytes")
    hdr = raw[0] | (raw[1] << 8)
    if hdr != expected_hdr:
        raise ValueError(f"{name}: expected PRG load header ${expected_hdr:04X}, got ${hdr:04X}")
    return raw[2:]


def build_cartridge_images(
    build_dir: Path,
    data_dir: Path,
    version_str: str,
    description: str,
    author: str,
    copyright_str: str,
) -> tuple[bytes, bytes, dict]:
    bootrom_path = build_dir / "bootrom.bin"
    bootrom = bootrom_path.read_bytes()
    if len(bootrom) > CART_DIRECTORY_OFFSET:
        raise ValueError(f"bootrom.bin ({len(bootrom)} B) exceeds $C100 limit ({CART_DIRECTORY_OFFSET} B)")
    if bootrom[:4] != b"CX16":
        raise ValueError("bootrom.bin missing CX16 signature at $C000")

    main_syms = parse_sym_file(build_dir / "main.sym")
    boot_syms = parse_sym_file(build_dir / "cartridge_boot.sym")
    if "entry_bootstrap" in main_syms and main_syms["entry_bootstrap"] != 0x080D:
        raise ValueError(f"entry_bootstrap moved from $080D to ${main_syms['entry_bootstrap']:04X}")
    if "program_end" in main_syms and main_syms["program_end"] > 0x9B00:
        raise ValueError(f"program_end ${main_syms['program_end']:04X} exceeds $9B00")

    rom = bytearray([0xFF] * CART_IMAGE_SIZE)
    rom[0 : len(bootrom)] = bootrom

    cursor = CART_PAYLOAD_OFFSET
    asset_records: list[dict] = []

    for asset_id, name, source_kind, expected_hdr, ram_bank, dest_addr in ASSETS:
        src_path = (build_dir if source_kind == "build" else data_dir) / name
        raw = src_path.read_bytes()
        if expected_hdr is not None:
            payload = strip_prg_header(raw, name, expected_hdr)
        else:
            payload = raw
        if len(payload) > 0xFFFF:
            raise ValueError(f"{name}: payload {len(payload)} exceeds 16-bit size")
        if cursor + len(payload) > CART_IMAGE_SIZE:
            raise ValueError(
                f"{name}: cartridge overflow at offset {cursor} + {len(payload)} > {CART_IMAGE_SIZE}"
            )

        bank_idx = cursor // CART_ROM_BANK_SIZE
        bank_num = CART_ROM_BANK_START + bank_idx
        rom_addr = CART_ROM_WINDOW_BASE + (cursor % CART_ROM_BANK_SIZE)

        rom[cursor : cursor + len(payload)] = payload

        desc = struct.pack(
            "<BHHBH",
            bank_num,
            rom_addr,
            dest_addr,
            ram_bank,
            len(payload),
        )
        assert len(desc) == CART_DESCRIPTOR_SIZE
        desc_off = CART_DIRECTORY_OFFSET + asset_id * CART_DESCRIPTOR_SIZE
        rom[desc_off : desc_off + CART_DESCRIPTOR_SIZE] = desc

        end_off = cursor + len(payload) - 1 if payload else cursor
        end_bank = CART_ROM_BANK_START + (end_off // CART_ROM_BANK_SIZE)
        asset_records.append(
            {
                "id": asset_id,
                "name": name,
                "source": source_kind,
                "prg_header": f"${expected_hdr:04X}" if expected_hdr is not None else None,
                "rom_offset": cursor,
                "rom_bank": bank_num,
                "rom_end_bank": end_bank,
                "rom_addr": f"${rom_addr:04X}",
                "dest_addr": f"${dest_addr:04X}",
                "ram_bank": None if ram_bank == CART_RAM_BANK_NONE else ram_bank,
                "size": len(payload),
                "sha256": sha256_bytes(payload),
            }
        )
        cursor += len(payload)

    crt_header = build_crt_header(
        bank_count=CART_BANK_COUNT,
        description=description,
        author=author,
        copyright_str=copyright_str,
        prg_version=version_str,
    )
    bin_bytes = bytes(rom)
    crt_bytes = crt_header + bin_bytes

    manifest = {
        "format": "cx16-cartridge-v1",
        "version": version_str,
        "bank_size": CART_ROM_BANK_SIZE,
        "bank_start": CART_ROM_BANK_START,
        "bank_count": CART_BANK_COUNT,
        "image_size": CART_IMAGE_SIZE,
        "payload_bytes_used": cursor,
        "free_bytes": CART_IMAGE_SIZE - cursor,
        "crt_size": len(crt_bytes),
        "crt_sha256": sha256_bytes(crt_bytes),
        "bin_sha256": sha256_bytes(bin_bytes),
        "bootrom_size": len(bootrom),
        "bootrom_sha256": sha256_bytes(bootrom),
        "symbols": {
            "entry_bootstrap": f"${main_syms['entry_bootstrap']:04X}" if "entry_bootstrap" in main_syms else None,
            "program_end": f"${main_syms['program_end']:04X}" if "program_end" in main_syms else None,
            "boot_cold_start": f"${boot_syms['boot_cold_start']:04X}" if "boot_cold_start" in boot_syms else None,
            "boot_copy_prepare": f"${boot_syms['boot_copy_prepare']:04X}" if "boot_copy_prepare" in boot_syms else None,
            "boot_copy_done": f"${boot_syms['boot_copy_done']:04X}" if "boot_copy_done" in boot_syms else None,
        },
        "assets": asset_records,
    }
    return crt_bytes, bin_bytes, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Commander X16 Cartridge (.crt, .bin, .json)")
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--out-crt", type=Path, required=True)
    parser.add_argument("--out-bin", type=Path, required=True)
    parser.add_argument("--out-manifest", type=Path, required=True)
    parser.add_argument("--version-file", type=Path, default=Path("VERSION"))
    parser.add_argument("--description", default="Moria8 for Commander X16")
    parser.add_argument("--author", default="Moria8 Contributors")
    parser.add_argument("--copyright", default="GPL-3.0-or-later")
    args = parser.parse_args()

    version_str = "0.0.0"
    if args.version_file.is_file():
        raw_ver = args.version_file.read_text(encoding="utf-8").strip()
        if args.version_file.suffix == ".json":
            ver_data = json.loads(raw_ver)
            version_str = str(ver_data.get("cx16", version_str))
        elif raw_ver:
            version_str = raw_ver

    crt_bytes, bin_bytes, manifest = build_cartridge_images(
        build_dir=args.build_dir,
        data_dir=args.data_dir,
        version_str=version_str,
        description=args.description,
        author=args.author,
        copyright_str=args.copyright,
    )

    for out_path in (args.out_crt, args.out_bin, args.out_manifest):
        out_path.parent.mkdir(parents=True, exist_ok=True)
    args.out_crt.write_bytes(crt_bytes)
    args.out_bin.write_bytes(bin_bytes)
    args.out_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(
        f"CX16 cartridge built: {args.out_crt} ({len(crt_bytes)} B), "
        f"{args.out_bin} ({len(bin_bytes)} B), "
        f"used {manifest['payload_bytes_used']}/{CART_IMAGE_SIZE} B "
        f"({manifest['free_bytes']} B free)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
