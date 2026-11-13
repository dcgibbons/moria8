#!/usr/bin/env python3
"""Verify Commander X16 Cartridge (.crt, .bin, .json manifest, and compliance texts)."""

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
CART_DESCRIPTOR_SIZE = 8
CRT_HEADER_SIZE = 480
CRT_MAGIC = b"CX16 CARTRIDGE\r\n"
CRT_VERSION = b"01.00           "
CRT_BANK_NONE = 0
CRT_BANK_ROM = 1
EXPECTED_ASSET_COUNT = 20

EXPECTED_ASSET_LAYOUT: dict[str, tuple[int, int | None, int]] = {
    "MORIA8.PRG": (0, 0, 0x0801),
    "CX16.AUXDATA": (1, 3, 0xA000),
    "CX16.HUFFDATA": (2, 4, 0xA000),
    "OVL.START": (3, 9, 0xA000),
    "OVL.TOWN": (4, 10, 0xA000),
    "OVL.DEATH": (5, 11, 0xA000),
    "OVL.GEN": (6, 12, 0xA000),
    "OVL.HELP": (7, 13, 0xA000),
    "OVL.UI": (8, 14, 0xA000),
    "OVL.ITEMS": (9, 15, 0xA000),
    "OVL.SPELL": (10, 16, 0xA000),
    "OVL.MODAL": (11, 17, 0xA000),
    "OVL.CHEST": (12, 18, 0xA000),
    "OVL.STORAGE": (13, 19, 0xA000),
    "OVL.TITLE": (14, 20, 0xA000),
    "TITLE": (15, 21, 0xA000),
    "MONSTER.CAT": (16, 22, 0xA000),
    "LEGALUI": (17, 23, 0xA000),
    "LICENSE": (18, None, 0x0000),
    "SOURCE-OFFER": (19, None, 0x0000),
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_power_of_two(n: int) -> bool:
    return n > 0 and (n & (n - 1)) == 0


def validate_cartridge_bytes(
    crt_bytes: bytes,
    bin_bytes: bytes,
    manifest: dict,
    expected_assets: dict[str, bytes] | None = None,
    bootrom_bytes: bytes | None = None,
) -> list[str]:
    errors: list[str] = []

    if not is_power_of_two(len(bin_bytes)) or len(bin_bytes) != CART_IMAGE_SIZE:
        errors.append(f"raw .bin size must be power-of-two {CART_IMAGE_SIZE} B, got {len(bin_bytes)}")
    if len(crt_bytes) != CRT_HEADER_SIZE + len(bin_bytes):
        errors.append(
            f".crt size mismatch: expected {CRT_HEADER_SIZE + len(bin_bytes)}, got {len(crt_bytes)}"
        )
        return errors

    hdr = crt_bytes[:CRT_HEADER_SIZE]
    if hdr[0x000:0x010] != CRT_MAGIC:
        errors.append("bad .crt header magic")
    if hdr[0x010:0x020] != CRT_VERSION:
        errors.append("bad .crt header version")
    if hdr[0x0A0:0x100] != b"\x00" * 96:
        errors.append(".crt reserved bytes 0x0A0..0x0FF must be zero")
    for idx in range(224):
        expected_type = CRT_BANK_ROM if idx < CART_BANK_COUNT else CRT_BANK_NONE
        if hdr[0x100 + idx] != expected_type:
            errors.append(f".crt bank_info[{idx}] expected {expected_type}, got {hdr[0x100 + idx]}")
            break

    if crt_bytes[CRT_HEADER_SIZE:] != bin_bytes:
        errors.append(".crt bank payload does not match raw .bin")

    if bin_bytes[:4] != b"CX16":
        errors.append("Bank 32 $C000 missing 'CX16' autostart signature")

    if bootrom_bytes is not None:
        if len(bootrom_bytes) > CART_DIRECTORY_OFFSET:
            errors.append(f"bootrom.bin exceeds {CART_DIRECTORY_OFFSET} B")
        elif bin_bytes[: len(bootrom_bytes)] != bootrom_bytes:
            errors.append("Bank 32 $C000.. does not match bootrom.bin")

    if manifest.get("format") != "cx16-cartridge-v1":
        errors.append("manifest format mismatch")
    if manifest.get("crt_sha256") != sha256_bytes(crt_bytes):
        errors.append("manifest crt_sha256 mismatch")
    if manifest.get("bin_sha256") != sha256_bytes(bin_bytes):
        errors.append("manifest bin_sha256 mismatch")

    assets = manifest.get("assets", [])
    if len(assets) != EXPECTED_ASSET_COUNT:
        errors.append(f"expected {EXPECTED_ASSET_COUNT} manifest assets, got {len(assets)}")
        return errors

    seen_names: set[str] = set()
    for asset in assets:
        aid = asset["id"]
        name = asset["name"]
        seen_names.add(name)
        desc_off = CART_DIRECTORY_OFFSET + aid * CART_DESCRIPTOR_SIZE
        bank_num, rom_addr, dest_addr, ram_bank, size = struct.unpack_from("<BHHBH", bin_bytes, desc_off)

        if bank_num < CART_ROM_BANK_START or bank_num >= CART_ROM_BANK_START + CART_BANK_COUNT:
            errors.append(f"{name}: invalid bank {bank_num}")
            continue
        if rom_addr < CART_ROM_WINDOW_BASE or rom_addr >= 0x10000:
            errors.append(f"{name}: invalid rom_addr ${rom_addr:04X}")
            continue

        rom_off = (bank_num - CART_ROM_BANK_START) * CART_ROM_BANK_SIZE + (rom_addr - CART_ROM_WINDOW_BASE)
        if rom_off + size > len(bin_bytes):
            errors.append(f"{name}: descriptor range overflows ROM")
            continue

        actual_payload = bin_bytes[rom_off : rom_off + size]
        if asset["size"] != size or asset["rom_offset"] != rom_off or asset["rom_bank"] != bank_num:
            errors.append(f"{name}: manifest metadata disagrees with binary descriptor")
        if sha256_bytes(actual_payload) != asset["sha256"]:
            errors.append(f"{name}: ROM payload sha256 disagrees with manifest")

        if expected_assets is not None and name in expected_assets:
            if actual_payload != expected_assets[name]:
                errors.append(f"{name}: ROM payload disagrees with source artifact")

        exp_dest = int(asset["dest_addr"].lstrip("$"), 16)
        if dest_addr != exp_dest:
            errors.append(f"{name}: dest_addr mismatch")
        exp_ram = 0xFF if asset["ram_bank"] is None else asset["ram_bank"]
        if ram_bank != exp_ram:
            errors.append(f"{name}: ram_bank mismatch")
        if name not in EXPECTED_ASSET_LAYOUT:
            errors.append(f"unexpected asset {name}")
        else:
            want_id, want_ram, want_dest = EXPECTED_ASSET_LAYOUT[name]
            if aid != want_id or asset["ram_bank"] != want_ram or exp_dest != want_dest:
                errors.append(
                    f"{name}: layout mismatch (got id={aid} bank={asset['ram_bank']} dest=${exp_dest:04X}, "
                    f"expected id={want_id} bank={want_ram} dest=${want_dest:04X})"
                )

    for required in EXPECTED_ASSET_LAYOUT:
        if required not in seen_names:
            errors.append(f"missing required asset {required}")

    return errors


def run_selftest() -> int:
    rom = bytearray([0xFF] * CART_IMAGE_SIZE)
    bootrom = b"CX16\x78\xd8\xa2\xff\x9a"
    rom[: len(bootrom)] = bootrom

    expected: dict[str, bytes] = {}
    cursor = 0x0200
    records = []
    for name, (idx, want_ram, dest_addr) in EXPECTED_ASSET_LAYOUT.items():
        payload = f"PAY-{idx}-{name}".encode("ascii")
        expected[name] = payload
        bank_num = CART_ROM_BANK_START + (cursor // CART_ROM_BANK_SIZE)
        rom_addr = CART_ROM_WINDOW_BASE + (cursor % CART_ROM_BANK_SIZE)
        ram_bank = 0xFF if want_ram is None else want_ram
        rom[cursor : cursor + len(payload)] = payload
        desc = struct.pack("<BHHBH", bank_num, rom_addr, dest_addr, ram_bank, len(payload))
        rom[0x100 + idx * 8 : 0x100 + (idx + 1) * 8] = desc
        records.append(
            {
                "id": idx,
                "name": name,
                "rom_offset": cursor,
                "rom_bank": bank_num,
                "rom_addr": f"${rom_addr:04X}",
                "dest_addr": f"${dest_addr:04X}",
                "ram_bank": want_ram,
                "size": len(payload),
                "sha256": sha256_bytes(payload),
            }
        )
        cursor += len(payload)

    hdr = bytearray(CRT_HEADER_SIZE)
    hdr[0:16] = CRT_MAGIC
    hdr[16:32] = CRT_VERSION
    for i in range(CART_BANK_COUNT):
        hdr[0x100 + i] = CRT_BANK_ROM
    bin_bytes = bytes(rom)
    crt_bytes = bytes(hdr) + bin_bytes
    manifest = {
        "format": "cx16-cartridge-v1",
        "crt_sha256": sha256_bytes(crt_bytes),
        "bin_sha256": sha256_bytes(bin_bytes),
        "assets": records,
    }

    errs = validate_cartridge_bytes(crt_bytes, bin_bytes, manifest, expected, bootrom)
    assert not errs, f"selftest positive check failed: {errs}"

    # Negative checks
    bad_magic = b"NOPE" + crt_bytes[4:]
    assert validate_cartridge_bytes(bad_magic, bin_bytes, manifest, expected, bootrom)

    bad_sig = bytearray(bin_bytes)
    bad_sig[0] = 0x00
    assert validate_cartridge_bytes(bytes(hdr) + bytes(bad_sig), bytes(bad_sig), manifest, expected, bootrom)

    bad_power = bin_bytes + b"\xff"
    assert validate_cartridge_bytes(bytes(hdr) + bad_power, bad_power, manifest, expected, bootrom)

    bad_license = dict(expected)
    bad_license["LICENSE"] = b"tampered"
    assert validate_cartridge_bytes(crt_bytes, bin_bytes, manifest, bad_license, bootrom)

    print("check_cx16_cart.py --selftest: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Commander X16 Cartridge artifacts")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--crt", type=Path)
    parser.add_argument("--bin", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    if not (args.crt and args.bin and args.manifest and args.build_dir):
        parser.error("--crt, --bin, --manifest, and --build-dir are required unless --selftest")

    crt_bytes = args.crt.read_bytes()
    bin_bytes = args.bin.read_bytes()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    bootrom_bytes = (args.build_dir / "bootrom.bin").read_bytes()

    expected_assets: dict[str, bytes] = {}
    for asset in manifest["assets"]:
        name = asset["name"]
        src = (args.data_dir if asset.get("source") == "data" else args.build_dir) / name
        raw = src.read_bytes()
        expected_assets[name] = raw[2:] if asset.get("prg_header") else raw

    errors = validate_cartridge_bytes(crt_bytes, bin_bytes, manifest, expected_assets, bootrom_bytes)
    if errors:
        for err in errors:
            print(f"FAIL: {err}", file=sys.stderr)
        return 1

    print(f"check_cx16_cart.py: PASS ({args.crt}, {len(manifest['assets'])} assets verified)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
