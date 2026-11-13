#!/usr/bin/env python3
"""Pack the Atari 8-bit cartridge build into an AtariMax 128 KB (.car type 41) ROM.

Descriptor and Bank 0 layout are shared with platforms/atari8/cartridge_{boot,copy}.s
and platforms/atari8/cartridge_contract.s.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import catalog_disk

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = catalog_disk.consts(ROOT / "platforms/atari8/cartridge_contract.s")
BANK_SIZE = CONTRACT["CART_ROM_BANK_SIZE"]
BANK_COUNT = CONTRACT["CART_ROM_BANK_COUNT"]
ROM_SIZE = BANK_COUNT * BANK_SIZE
WINDOW = CONTRACT["CART_WINDOW"]
WINDOW_END = CONTRACT["CART_WINDOW_END"]
CART_TYPE_ATARI_MAX_128KB = 41

OVERLAYS = (
    ("STARTUP", "STA"),
    ("TOWN", "TWN"),
    ("DEATH", "DTH"),
    ("DUNGEON_GEN", "GEN"),
    ("HELP", "HLP"),
    ("UI", "UI"),
    ("ITEMS", "ITM"),
    ("SPELL", "SPL"),
    ("MODAL_MISC", "MDL"),
    ("CHEST", "CHS"),
)


def prg(path: Path, minimum: int, maximum: int, exact_start: bool = True,
        allow_cart_window: bool = False) -> tuple[int, bytes]:
    raw = path.read_bytes()
    if len(raw) < 3:
        raise ValueError(f"Empty/truncated PRG: {path}")
    dest = int.from_bytes(raw[:2], "little")
    payload = raw[2:]
    end = dest + len(payload)
    if exact_start and dest != minimum:
        raise ValueError(f"Unexpected start address: {path}: ${dest:04x} != ${minimum:04x}")
    if dest < minimum or end > maximum:
        raise ValueError(f"Unexpected RAM span: {path}: ${dest:04x}..${end:04x} outside ${minimum:04x}..${maximum:04x}")
    if not allow_cart_window and not (end <= WINDOW or dest >= WINDOW_END):
        raise ValueError(f"Post-boot asset overlaps cartridge window $A000-$BFFF: {path}: ${dest:04x}..${end:04x}")
    return dest, payload


def pack(source: Path, output: Path) -> dict:
    rom = bytearray(b"\xff" * ROM_SIZE)
    boot = (source / "bank0.bin").read_bytes()
    if len(boot) != BANK_SIZE:
        raise ValueError(f"Unexpected Bank 0 size: {len(boot)} != {BANK_SIZE}")
    dir_rom_off = CONTRACT["CART_DIRECTORY"] - WINDOW
    dir_bytes = CONTRACT["CART_ASSET_COUNT"] * CONTRACT["CART_DESCRIPTOR_SIZE"]
    if any(b != 0xFF for b in boot[dir_rom_off:dir_rom_off + dir_bytes]):
        raise ValueError("Bank 0 boot stub overlaps CART_DIRECTORY window")
    if boot[-4] != 0x00 or boot[-3] != 0x04:
        raise ValueError(f"Unexpected Bank 0 Atari cartridge trailer flags: {boot[-6:].hex()}")
    rom[:BANK_SIZE] = boot

    inputs = {
        CONTRACT["CART_ASSET_RESIDENT"]: (
            "resident",
            *prg(source / "MORIA8.RES", CONTRACT["CART_ENTRY"], 0xC100, allow_cart_window=True),
        ),
        CONTRACT["CART_ASSET_RUNTIME"]: (
            "runtime",
            *prg(source / "ATARI.BNK", 0xF000, 0xFFFA),
        ),
        CONTRACT["CART_ASSET_TITLE"]: (
            "title",
            *prg(source / "TITLE.DAT", 0xC100, 0xD000),
        ),
        CONTRACT["CART_ASSET_CATALOG"]: (
            "catalog",
            0,
            b"".join(catalog_disk.records()),
        ),
        CONTRACT["CART_ASSET_LEGAL_UI"]: (
            "legalui",
            *prg(source / "legalui", 0xE000, 0xE600),
        ),
        CONTRACT["CART_ASSET_LEGAL_NOTICE"]: (
            "license",
            0,
            (ROOT / "data/LICENSE").read_bytes(),
        ),
        CONTRACT["CART_ASSET_LEGAL_OFFER"]: (
            "source-offer",
            0,
            (ROOT / "data/SOURCE-OFFER").read_bytes(),
        ),
    }
    inputs.update({
        CONTRACT["CART_ASSET_" + symbol]: (
            f"OVL.{ext}",
            *prg(source / f"OVL.{ext}", 0xE000, 0xF000),
        )
        for symbol, ext in OVERLAYS
    })

    for legal_id in (CONTRACT["CART_ASSET_LEGAL_NOTICE"], CONTRACT["CART_ASSET_LEGAL_OFFER"]):
        name, dest, data = inputs[legal_id]
        if not data or len(data) >= 0x8000 or b"\0" in data:
            raise ValueError(f"Legal ROM text must be nonempty, NUL-free and below 32 KB: {name}")
        inputs[legal_id] = (name, dest, data + b"\0" + bytes((-len(data) - 1) % 256))

    if sorted(inputs) != list(range(CONTRACT["CART_ASSET_COUNT"])):
        raise ValueError("Missing, duplicate or noncontiguous cartridge asset IDs")
    if dir_rom_off + dir_bytes > BANK_SIZE - 6:
        raise ValueError("Asset directory exceeds ROM bank zero")
    if len(inputs[CONTRACT["CART_ASSET_CATALOG"]][2]) > 0x6000:
        raise ValueError("Catalog offsets exceed the reader's 16-bit source range")

    manifest = {
        "format": "AtariMax-128KB",
        "car_type": CART_TYPE_ATARI_MAX_128KB,
        "flash_writes": False,
        "rom_size": ROM_SIZE,
        "assets": [],
    }

    offset = BANK_SIZE
    page_aligned_ids = {
        CONTRACT["CART_ASSET_RESIDENT"],
        CONTRACT["CART_ASSET_LEGAL_NOTICE"],
        CONTRACT["CART_ASSET_LEGAL_OFFER"],
    }
    for asset_id, (name, dest, data) in sorted(inputs.items()):
        if asset_id in page_aligned_ids and (offset & 0xFF):
            offset = (offset + 0xFF) & ~0xFF
        if not data or len(data) > 0xFFFF or offset + len(data) > ROM_SIZE:
            raise ValueError(f"Asset does not fit in 128 KB ROM: {name} (offset={offset}, len={len(data)})")
        bank, within = divmod(offset, BANK_SIZE)
        struct.pack_into(
            "<BHHHB",
            rom,
            dir_rom_off + asset_id * CONTRACT["CART_DESCRIPTOR_SIZE"],
            bank,
            WINDOW + within,
            dest,
            len(data),
            0,
        )
        rom[offset:offset + len(data)] = data
        manifest["assets"].append(dict(
            id=asset_id,
            name=name,
            bank=bank,
            source=WINDOW + within,
            rom_offset=offset,
            destination=dest,
            size=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
        ))
        offset += len(data)

    checksum = sum(rom) & 0xFFFFFFFF
    header = b"CART" + struct.pack(">III", CART_TYPE_ATARI_MAX_128KB, checksum, 0)
    car_bytes = header + rom

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(car_bytes)

    raw_bin = source / (output.stem + ".bin")
    raw_bin.write_bytes(rom)

    manifest.update(
        rom_bytes_used=offset,
        rom_bytes_free=ROM_SIZE - offset,
        rom_checksum=checksum,
        car_sha256=hashlib.sha256(car_bytes).hexdigest(),
        bin_sha256=hashlib.sha256(rom).hexdigest(),
    )
    (source / (output.stem + ".json")).write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = pack(args.source, args.output)
    print(
        f"{args.output}: {len(result['assets'])} assets, "
        f"{result['rom_bytes_used']}/{result['rom_size']} ROM bytes "
        f"({result['rom_bytes_free']} free)"
    )
