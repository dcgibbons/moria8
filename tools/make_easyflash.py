#!/usr/bin/env python3
"""Pack the C64 cartridge build into a native, read-only EasyFlash CRT.

Descriptor and ROML layout are shared with c64/cartridge_{boot,copy}.s.
The manifest records exact ROM and RAM spans for independent verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import catalog_disk

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = catalog_disk.consts(ROOT / "platforms/commodore/c64/cartridge_contract.s")
BANK_SIZE = CONTRACT["CART_ROM_BANK_SIZE"]
ROM_SIZE = 64 * BANK_SIZE
OVERLAYS = (("STARTUP", "start"), ("TOWN", "town"), ("DEATH", "death"),
            ("DUNGEON_GEN", "gen"), ("HELP", "help"), ("UI", "ui"),
            ("ITEMS", "items"), ("SPELL", "spell"), ("MODAL_MISC", "modal"),
            ("CHEST", "chest"))


def index_bytes():
    # ROM records need the level/availability index, without disk sector maps.
    raw = catalog_disk.index_bytes(None, 0xCE00)[2:]
    return raw[:-2 * catalog_disk.layout()["CATALOG_RECORD_SECTORS"]]


def prg(path: Path, minimum: int, maximum: int) -> tuple[int, bytes]:
    raw = path.read_bytes()
    if len(raw) < 3:
        raise ValueError(f"Empty/truncated PRG: {path}")
    dest = int.from_bytes(raw[:2], "little")
    if dest != minimum or dest + len(raw) - 2 > maximum:
        raise ValueError(f"Unexpected RAM span: {path}: ${dest:04x} + {len(raw)-2}")
    return dest, raw[2:]


def pack(source: Path, output: Path) -> dict:
    roml = bytearray(b"\xff" * ROM_SIZE)
    boot = (source / "roml.bin").read_bytes()
    romh_boot = (source / "romh.bin").read_bytes()
    if len(boot) > 0x100 or len(romh_boot) != BANK_SIZE:
        raise ValueError("Boot ROM overlaps directory or lacks reset vectors")
    roml[:len(boot)] = boot
    inputs = {
        CONTRACT["CART_ASSET_RESIDENT"]: ("resident", *prg(source / "moria8.prg", 0x0801, 0xCE00)),
        CONTRACT["CART_ASSET_RUNTIME"]: ("runtime", *prg(source / "64.bank", 0xF000, 0xFFFA)),
        CONTRACT["CART_ASSET_INDEX"]: ("index", 0xCE00, index_bytes()),
        CONTRACT["CART_ASSET_TITLE"]: ("title", *prg(source / "title", 0xC000, 0xCF00)),
        CONTRACT["CART_ASSET_CATALOG"]: ("catalog", 0, b"".join(catalog_disk.records())),
        CONTRACT["CART_ASSET_LEGAL_UI"]: ("legalui", *prg(source / "legalui", 0xE000, 0xE600)),
        CONTRACT["CART_ASSET_LEGAL_NOTICE"]: ("license", 0, (ROOT / "data/LICENSE").read_bytes()),
        CONTRACT["CART_ASSET_LEGAL_OFFER"]: ("source-offer", 0, (ROOT / "data/SOURCE-OFFER").read_bytes()),
    }
    inputs.update({CONTRACT["CART_ASSET_" + symbol]:
                   (f"ovl.{name}", *prg(source / f"ovl.{name}", 0xE000, 0xF000))
                   for symbol, name in OVERLAYS})
    for legal_id in (CONTRACT["CART_ASSET_LEGAL_NOTICE"], CONTRACT["CART_ASSET_LEGAL_OFFER"]):
        name, dest, data = inputs[legal_id]
        if not data or len(data) >= 0x8000 or b"\0" in data:
            raise ValueError("Legal ROM text must be nonempty, NUL-free and below 32 KB")
        inputs[legal_id] = (name, dest, data + b"\0" + bytes((-len(data) - 1) % 256))
    if sorted(inputs) != list(range(CONTRACT["CART_ASSET_COUNT"])):
        raise ValueError("Missing, duplicate or noncontiguous cartridge asset IDs")
    if 0x100 + len(inputs) * CONTRACT["CART_DESCRIPTOR_SIZE"] > BANK_SIZE:
        raise ValueError("Asset directory exceeds ROM bank zero")
    if len(inputs[CONTRACT["CART_ASSET_CATALOG"]][2]) > 0x6000:
        raise ValueError("Catalog offsets exceed the reader's source-address range")
    manifest = {"format": "EasyFlash", "crt_type": 32, "subtype": 0,
                "flash_writes": False, "assets": []}
    offset = BANK_SIZE
    for asset_id, (name, dest, data) in sorted(inputs.items()):
        if not data or len(data) > 0xFFFF or offset + len(data) > ROM_SIZE:
            raise ValueError(f"Asset does not fit: {name}")
        bank, within = divmod(offset, BANK_SIZE)
        roml[CONTRACT["CART_DIRECTORY"] - 0x8000 + asset_id * CONTRACT["CART_DESCRIPTOR_SIZE"]:
             CONTRACT["CART_DIRECTORY"] - 0x8000 + (asset_id + 1) * CONTRACT["CART_DESCRIPTOR_SIZE"]] = struct.pack(
            "<BHHHB", bank, 0x8000 + within, dest, len(data), 0)
        roml[offset:offset + len(data)] = data
        manifest["assets"].append(dict(id=asset_id, name=name, bank=bank,
            source=0x8000 + within, rom_offset=offset, destination=dest,
            size=len(data), sha256=hashlib.sha256(data).hexdigest()))
        offset += len(data)
    header = bytearray(0x40)
    header[:16] = b"C64 CARTRIDGE   "
    struct.pack_into(">IHHBB", header, 0x10, 0x40, 0x0100, 32, 1, 0)
    header[0x1A] = 0  # Standard EasyFlash; no dependence on Ultimate extensions.
    header[0x20:0x20+len(b"MORIA8 EASYFLASH EXPERIMENT")] = b"MORIA8 EASYFLASH EXPERIMENT"
    image = bytearray(header)
    # Supply both chips for all banks; empty ROMH banks are erased flash.
    for bank in range(64):
        for address, data in ((0x8000, roml[bank*BANK_SIZE:(bank+1)*BANK_SIZE]),
                              (0xA000, romh_boot if bank == 0 else b"\xff" * BANK_SIZE)):
            image += struct.pack(">4sIHHHH", b"CHIP", BANK_SIZE + 16, 2, bank, address, BANK_SIZE)
            image += data
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    manifest.update(roml_bytes_used=offset, crt_sha256=hashlib.sha256(image).hexdigest())
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = pack(args.source, args.output)
    print(f"{args.output}: {len(result['assets'])} assets, {result['roml_bytes_used']} ROML bytes")
