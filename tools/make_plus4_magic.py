#!/usr/bin/env python3
"""Pack the Plus/4 cartridge build into a c264 magic cart CRT and raw BIN.

Descriptor and C1LO layout are shared with plus4/cartridge_{boot,copy,contract}.s.
The manifest records exact ROM and RAM spans for independent verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import build_catalog
import catalog_disk

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = catalog_disk.consts(ROOT / "platforms/commodore/plus4/cartridge_contract.s")
BANK_SIZE = CONTRACT["CART_ROM_BANK_SIZE"]
BANK_COUNT = CONTRACT["CART_BANK_COUNT"]
ROM_SIZE = BANK_COUNT * BANK_SIZE
MAP_BASE = 0xC800
MAP_END_EXCL = 0xD700
CATALOG_IDX_LOAD = 0xD600
OVERLAYS = (
    ("STARTUP", "start"),
    ("TOWN", "town"),
    ("DEATH", "death"),
    ("DUNGEON_GEN", "gen"),
    ("HELP", "help"),
    ("UI", "ui"),
    ("ITEMS", "items"),
    ("SPELL", "spell"),
    ("MODAL_MISC", "modal"),
    ("CHEST", "chest"),
    ("HOME", "home"),
    ("STORAGE", "storage"),
    ("TITLE", "title"),
)


def index_bytes() -> bytes:
    # ROM records need the level/availability index, without disk sector maps.
    raw = catalog_disk.index_bytes(None, CATALOG_IDX_LOAD)[2:]
    return raw[:-2 * catalog_disk.layout()["CATALOG_RECORD_SECTORS"]]


def prg(path: Path, minimum: int, maximum: int) -> tuple[int, bytes]:
    raw = path.read_bytes()
    if len(raw) < 3:
        raise ValueError(f"Empty/truncated PRG: {path}")
    dest = int.from_bytes(raw[:2], "little")
    if dest != minimum or dest + len(raw) - 2 > maximum:
        raise ValueError(f"Unexpected RAM span: {path}: ${dest:04x} + {len(raw) - 2}")
    return dest, raw[2:]


def assert_runtime_destination_safe(name: str, dest: int, size: int) -> None:
    if dest == 0:
        return
    end = dest + size
    if dest < 0xC000 and end > 0x8000:
        raise ValueError(
            f"Runtime asset {name} (${dest:04x}-${end - 1:04x}) overlaps C1LO $8000-$BFFF"
        )
    if end > 0xFC00:
        raise ValueError(
            f"Runtime asset {name} (${dest:04x}-${end - 1:04x}) overlaps >= $FC00"
        )


def pack(source: Path, output: Path) -> dict:
    rom = bytearray(b"\xff" * ROM_SIZE)
    boot = (source / "bootrom.bin").read_bytes()
    if len(boot) > CONTRACT["CART_DIRECTORY"] - CONTRACT["CART_ROM_WINDOW_BASE"]:
        raise ValueError("Boot ROM overlaps asset directory at $8100")
    rom[:len(boot)] = boot

    _, title_data = prg(source / "title", 0xC000, 0xD000)
    if MAP_BASE + len(title_data) > MAP_END_EXCL:
        raise ValueError("Title data exceeds MAP_BASE..MAP_END")

    inputs: dict[int, tuple[str, int, bytes]] = {
        CONTRACT["CART_ASSET_RESIDENT"]: ("resident", *prg(source / "moria4.prg", 0x1001, CATALOG_IDX_LOAD)),
        CONTRACT["CART_ASSET_RUNTIME"]: ("runtime", *prg(source / "4.bank", 0xF000, 0xFC00)),
        CONTRACT["CART_ASSET_INDEX"]: ("index", CATALOG_IDX_LOAD, index_bytes()),
        CONTRACT["CART_ASSET_TITLE_ART"]: ("title", MAP_BASE, title_data),
        CONTRACT["CART_ASSET_CATALOG"]: ("catalog", 0, b"".join(catalog_disk.records())),
        CONTRACT["CART_ASSET_LEGAL_UI"]: ("legalui", *prg(source / "legalui", 0xE000, 0xE600)),
        CONTRACT["CART_ASSET_LEGAL_NOTICE"]: ("license", 0, (ROOT / "data/LICENSE").read_bytes()),
        CONTRACT["CART_ASSET_LEGAL_OFFER"]: ("source-offer", 0, (ROOT / "data/SOURCE-OFFER").read_bytes()),
        CONTRACT["CART_ASSET_ITEM_CATALOG"]: ("item.cat", 0, catalog_disk.item_catalog_bytes()),
        CONTRACT["CART_ASSET_CATALOG_EXT"]: (
            "monster.ext",
            0,
            build_catalog.ext_row_major_bytes(build_catalog.load_spec()["creatures"]),
        ),
    }
    inputs.update({
        CONTRACT["CART_ASSET_" + symbol]:
            (f"ovl.{name}", *prg(source / f"ovl.{name}", 0xE000, 0xF000))
        for symbol, name in OVERLAYS
    })
    for legal_id in (CONTRACT["CART_ASSET_LEGAL_NOTICE"], CONTRACT["CART_ASSET_LEGAL_OFFER"]):
        name, dest, data = inputs[legal_id]
        if not data or len(data) >= 0x4000 or b"\0" in data:
            raise ValueError("Legal ROM text must be nonempty, NUL-free and below 16 KB")
        inputs[legal_id] = (name, dest, data + b"\0" + bytes((-len(data) - 1) % 256))
    if sorted(inputs) != list(range(CONTRACT["CART_ASSET_COUNT"])):
        raise ValueError("Missing, duplicate or noncontiguous cartridge asset IDs")
    if 0x100 + len(inputs) * CONTRACT["CART_DESCRIPTOR_SIZE"] > BANK_SIZE:
        raise ValueError("Asset directory exceeds ROM bank zero")
    if len(inputs[CONTRACT["CART_ASSET_CATALOG"]][2]) > 0x4000:
        raise ValueError("Catalog offsets exceed the reader's 16 KB source-address range")
    if len(inputs[CONTRACT["CART_ASSET_ITEM_CATALOG"]][2]) > 0x4000:
        raise ValueError("Item catalog offsets exceed the reader's 16 KB source-address range")
    if len(inputs[CONTRACT["CART_ASSET_CATALOG_EXT"]][2]) > 0x4000:
        raise ValueError("Extended catalog offsets exceed the reader's 16 KB source-address range")

    manifest: dict = {
        "format": "c264 magic cart",
        "crt_type": 1,
        "crt_version": "2.0",
        "bank_size": BANK_SIZE,
        "bank_count": BANK_COUNT,
        "assets": [],
    }
    offset = BANK_SIZE
    dir_offset_base = CONTRACT["CART_DIRECTORY"] - CONTRACT["CART_ROM_WINDOW_BASE"]
    desc_size = CONTRACT["CART_DESCRIPTOR_SIZE"]

    for asset_id, (name, dest, data) in sorted(inputs.items()):
        if asset_id != CONTRACT["CART_ASSET_RESIDENT"]:
            assert_runtime_destination_safe(name, dest, len(data))
        if not data or len(data) > 0xFFFF or offset + len(data) > ROM_SIZE:
            raise ValueError(f"Asset does not fit: {name}")
        bank, within = divmod(offset, BANK_SIZE)
        if asset_id == CONTRACT["CART_ASSET_RESIDENT"] and within != 0:
            raise ValueError("Resident image must start on a ROM bank boundary")
        struct.pack_into(
            "<BHHHB",
            rom,
            dir_offset_base + asset_id * desc_size,
            bank,
            CONTRACT["CART_ROM_WINDOW_BASE"] + within,
            dest,
            len(data),
            0,
        )
        rom[offset:offset + len(data)] = data
        manifest["assets"].append(dict(
            id=asset_id,
            name=name,
            bank=bank,
            source=CONTRACT["CART_ROM_WINDOW_BASE"] + within,
            rom_offset=offset,
            destination=dest,
            size=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
        ))
        offset += len(data)

    bin_path = source / "moria8-plus4.bin"
    raw_bytes = bytes(rom)
    bin_path.write_bytes(raw_bytes)

    header = bytearray(0x40)
    header[:16] = b"PLUS4 CARTRIDGE "
    struct.pack_into(">IHHBB", header, 0x10, 0x40, 0x0200, 1, 0, 0)
    title_label = b"MORIA8 PLUS/4 MAGIC CART"
    header[0x20:0x20 + len(title_label)] = title_label

    image = bytearray(header)
    for bank in range(BANK_COUNT):
        image += struct.pack(
            ">4sIHHHH",
            b"CHIP",
            BANK_SIZE + 16,
            0,
            bank,
            CONTRACT["CART_ROM_WINDOW_BASE"],
            BANK_SIZE,
        )
        image += raw_bytes[bank * BANK_SIZE:(bank + 1) * BANK_SIZE]

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    manifest.update(
        rom_bytes_used=offset,
        rom_bytes_total=ROM_SIZE,
        bin_sha256=hashlib.sha256(raw_bytes).hexdigest(),
        crt_sha256=hashlib.sha256(image).hexdigest(),
    )
    (source / "moria8-plus4.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = pack(args.source, args.output)
    print(f"{args.output}: {len(result['assets'])} assets, {result['rom_bytes_used']} / {result['rom_bytes_total']} ROM bytes")
