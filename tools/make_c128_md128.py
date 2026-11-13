#!/usr/bin/env python3
"""Pack the C128 cartridge build into a native Magic Desk 128 CRT and BIN."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import catalog_disk

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = catalog_disk.consts(ROOT / "platforms/commodore/c128/cartridge_contract.s")
BANK_SIZE = CONTRACT["CART_ROM_BANK_SIZE"]
BANK_COUNT = CONTRACT["CART_BANK_COUNT"]
ROM_SIZE = BANK_COUNT * BANK_SIZE
OVERLAYS = (
    ("STARTUP", "start"),
    ("TOWN", "town"),
    ("DEATH", "death"),
    ("DUNGEON_GEN", "gen"),
    ("HELP", "help"),
    ("UI", "ui"),
    ("ITEMS", "items"),
    ("SPELL", "disarm"),
    ("MODAL_MISC", "modal"),
    ("CHEST", "chest"),
)


def prg(path: Path, minimum: int, maximum: int) -> tuple[int, bytes]:
    raw = path.read_bytes()
    if len(raw) < 3:
        raise ValueError(f"Empty/truncated PRG: {path}")
    dest = int.from_bytes(raw[:2], "little")
    if dest != minimum or dest + len(raw) - 2 > maximum:
        raise ValueError(f"Unexpected RAM span: {path}: ${dest:04x} + {len(raw) - 2}")
    return dest, raw[2:]


def build_inputs(source: Path) -> dict[int, tuple[str, str, int, bytes, int]]:
    d_b0 = CONTRACT["CART_DEST_BANK0"]
    d_b1 = CONTRACT["CART_DEST_BANK1"]
    d_b1_top = CONTRACT["CART_DEST_BANK1_TOP_OFF"]

    inputs: dict[int, tuple[str, str, int, bytes, int]] = {
        CONTRACT["CART_ASSET_RESIDENT"]: ("resident", "moria128.prg", *prg(source / "moria128.prg", 0x1C01, 0x6000), d_b0),
        CONTRACT["CART_ASSET_RUNTIME_LOW"]: ("runtime_low", "128.runtime.prg", *prg(source / "128.runtime.prg", 0x1000, 0x4000), d_b0),
        CONTRACT["CART_ASSET_RUNTIME_INPUT"]: ("runtime_input", "128.input.prg", *prg(source / "128.input.prg", 0x0B00, 0x0C00), d_b0),
        CONTRACT["CART_ASSET_RUNTIME_PROJ"]: ("runtime_proj", "128.proj.prg", *prg(source / "128.proj.prg", 0x0A80, 0x0B00), d_b0),
        CONTRACT["CART_ASSET_RUNTIME_COMMON"]: ("runtime_common", "128.fdisk.prg", *prg(source / "128.fdisk.prg", 0x0D60, 0x0FB0), d_b0),
        CONTRACT["CART_ASSET_DISKIO"]: ("diskio", "128.diskio.prg", *prg(source / "128.diskio.prg", 0xAB00, 0xAF00), d_b0),
        CONTRACT["CART_ASSET_BANKED"]: ("banked", "128.bank.prg", *prg(source / "128.bank.prg", 0xF000, 0xFF00), d_b0),
        CONTRACT["CART_ASSET_WORLD"]: ("world", "128.world.prg", *prg(source / "128.world.prg", 0x6000, 0x8C50), d_b0),
        CONTRACT["CART_ASSET_RES_ITEMS"]: ("res_items", "128.item.prg", *prg(source / "128.item.prg", 0x8C50, 0xA800), d_b0),
        CONTRACT["CART_ASSET_NAMES"]: ("names", "128.names.prg", *prg(source / "128.names.prg", 0x7400, 0x7A60), d_b1),
        CONTRACT["CART_ASSET_HVEC"]: ("hvec", "128.hvec.prg", *prg(source / "128.hvec.prg", 0xFFFA, 0xFFFC), d_b1_top),
        CONTRACT["CART_ASSET_HUFF"]: ("huff", "128.huff.prg", *prg(source / "128.huff.prg", 0xF000, 0xFF00), d_b1_top),
        CONTRACT["CART_ASSET_CAT"]: ("cat", "128.cat.prg", *prg(source / "128.cat.prg", 0x7E60, 0x9568), d_b1),
        CONTRACT["CART_ASSET_CNM"]: ("cnm", "128.cnm.prg", *prg(source / "128.cnm.prg", 0xA000, 0xB000), d_b1),
        CONTRACT["CART_ASSET_SELECT"]: ("select", "128.select.prg", *prg(source / "128.select.prg", 0xA800, 0xAB00), d_b0),
        CONTRACT["CART_ASSET_PERSIST"]: ("persist", "128.persist.prg", *prg(source / "128.persist.prg", 0xAF00, 0xD000), d_b0),
        CONTRACT["CART_ASSET_PLAY"]: ("play", "128.play.prg", *prg(source / "128.play.prg", 0xAF00, 0xD000), d_b0),
        CONTRACT["CART_ASSET_TITLE"]: ("title", "title", *prg(source / "title", 0x4000, 0x4300), d_b1),
        CONTRACT["CART_ASSET_LEGAL_UI"]: ("legalui", "legalui", *prg(source / "legalui", 0xE000, 0xE600), d_b0),
        CONTRACT["CART_ASSET_LEGAL_NOTICE"]: ("license", "LICENSE", 0, (ROOT / "data/LICENSE").read_bytes(), d_b0),
        CONTRACT["CART_ASSET_LEGAL_OFFER"]: ("source-offer", "SOURCE-OFFER", 0, (ROOT / "data/SOURCE-OFFER").read_bytes(), d_b0),
    }
    inputs.update({
        CONTRACT["CART_ASSET_" + symbol]: (f"ovl.{name}", f"ovl.{name}", *prg(source / f"ovl.{name}", 0xE000, 0xF000), d_b0)
        for symbol, name in OVERLAYS
    })
    for legal_id in (CONTRACT["CART_ASSET_LEGAL_NOTICE"], CONTRACT["CART_ASSET_LEGAL_OFFER"]):
        name, fname, dest, data, flags = inputs[legal_id]
        if not data or len(data) >= 0x8000 or b"\0" in data:
            raise ValueError("Legal ROM text must be nonempty, NUL-free and below 32 KB")
        inputs[legal_id] = (name, fname, dest, data + b"\0" + bytes((-len(data) - 1) % 256), flags)
    return inputs


def pack(source: Path, output: Path) -> dict:
    rom = bytearray(b"\xff" * ROM_SIZE)
    boot = (source / "rom0.bin").read_bytes()
    if len(boot) > 0x100:
        raise ValueError("Boot ROM overlaps directory at $8100")
    rom[:len(boot)] = boot

    inputs = build_inputs(source)
    if sorted(inputs) != list(range(CONTRACT["CART_ASSET_COUNT"])):
        raise ValueError("Missing, duplicate or noncontiguous cartridge asset IDs")
    if len(inputs) * CONTRACT["CART_DESCRIPTOR_SIZE"] > 0x0100:
        raise ValueError("Asset directory exceeds Bank 0 $8100 page")

    manifest = {
        "format": "Magic Desk 128",
        "crt_type": 4,
        "crt_version": 0x0200,
        "bank_count": BANK_COUNT,
        "bank_size": BANK_SIZE,
        "rom_size": ROM_SIZE,
        "assets": [],
    }

    offset = BANK_SIZE
    for asset_id, (name, fname, dest, data, flags) in sorted(inputs.items()):
        if not data or len(data) > 0xFFFF or offset + len(data) > ROM_SIZE:
            raise ValueError(f"Asset does not fit: {name}")
        bank, within = divmod(offset, BANK_SIZE)
        desc_off = (CONTRACT["CART_DIRECTORY"] - 0x8000) + asset_id * CONTRACT["CART_DESCRIPTOR_SIZE"]
        rom[desc_off:desc_off + CONTRACT["CART_DESCRIPTOR_SIZE"]] = struct.pack(
            "<BHHHB", bank, 0x8000 + within, dest, len(data), flags
        )
        rom[offset:offset + len(data)] = data
        manifest["assets"].append({
            "id": asset_id,
            "name": name,
            "file": fname,
            "bank": bank,
            "source": 0x8000 + within,
            "rom_offset": offset,
            "destination": dest,
            "flags": flags,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })
        offset += len(data)

    header = bytearray(0x40)
    header[:16] = b"C128 CARTRIDGE  "
    struct.pack_into(">IHHBB", header, 0x10, 0x40, 0x0200, 4, 0, 0)
    title = b"MORIA8 MAGIC DESK 128"
    header[0x20:0x20 + len(title)] = title

    image = bytearray(header)
    for bank in range(BANK_COUNT):
        bank_data = rom[bank * BANK_SIZE:(bank + 1) * BANK_SIZE]
        image += struct.pack(">4sIHHHH", b"CHIP", BANK_SIZE + 16, 0, bank, 0x8000, BANK_SIZE)
        image += bank_data

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    (source / "moria8-c128.bin").write_bytes(rom)
    (source / "moria8-c128.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = pack(args.source, args.output)
    used = sum(a["size"] for a in manifest["assets"]) + BANK_SIZE
    print(f"Packed {args.output} ({len(manifest['assets'])} assets, {used}/{ROM_SIZE} ROM bytes)")


if __name__ == "__main__":
    main()
