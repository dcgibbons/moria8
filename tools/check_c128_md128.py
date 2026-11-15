#!/usr/bin/env python3
"""Independently verify the C128 Magic Desk 128 CRT, BIN, manifest, and symbols."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import tempfile

import catalog_disk
import make_c128_md128


def parse_symbols(path: Path) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", path.read_text())
    }


def check(crt: Path, source: Path) -> None:
    image = crt.read_bytes()
    assert image[:16] == b"C128 CARTRIDGE  ", "Bad CRT signature"
    assert struct.unpack_from(">IHHBB", image, 0x10) == (64, 0x0200, 4, 0, 0), "Bad C128 MD128 header"

    chips: dict[int, bytes] = {}
    offset = 64
    while offset < len(image):
        magic, length, chip_type, bank, address, size = struct.unpack_from(">4sIHHHH", image, offset)
        assert (magic, length, chip_type, address, size) == (
            b"CHIP",
            make_c128_md128.BANK_SIZE + 16,
            0,
            0x8000,
            make_c128_md128.BANK_SIZE,
        ), f"Bad CHIP header at {offset}"
        assert bank < make_c128_md128.BANK_COUNT and bank not in chips
        chips[bank] = image[offset + 16:offset + length]
        assert len(chips[bank]) == make_c128_md128.BANK_SIZE
        offset += length
    assert offset == len(image) and len(chips) == make_c128_md128.BANK_COUNT

    rom = b"".join(chips[b] for b in range(make_c128_md128.BANK_COUNT))
    bin_path = source / "moria8-c128.bin"
    assert bin_path.read_bytes() == rom, "moria8-c128.bin diverges from CRT CHIPs"

    assert rom[6:10] == b"\x01CBM", "Missing C128 autostart CBM header"
    assert rom[:len((source / "rom0.bin").read_bytes())] == (source / "rom0.bin").read_bytes()

    contract = make_c128_md128.CONTRACT
    syms = parse_symbols(source / "main.sym")
    assert syms["entry"] == contract["CART_ENTRY"]
    assert syms["program_end"] <= 0xAF00, f"program_end=${syms['program_end']:04x} > $AF00"
    assert syms["cart_read"] < 0x8000, f"cart_read=${syms['cart_read']:04x} >= $8000"
    assert syms["hal_item_cat_cart_read_byte"] < 0x8000, (
        f"hal_item_cat_cart_read_byte=${syms['hal_item_cat_cart_read_byte']:04x} >= $8000"
    )
    assert syms["cart_desc_buf"] + contract["CART_DESCRIPTOR_SIZE"] <= 0x8000
    assert syms["cart_reader_end"] <= 0x8000, f"cart_reader_end=${syms['cart_reader_end']:04x} > $8000"
    moria_prg = (source / "moria128.prg").read_bytes()
    assert 0x1C01 + len(moria_prg) - 2 == syms["program_end"], (
        f"moria128.prg ends at ${0x1C01 + len(moria_prg) - 2:04x}, expected program_end=${syms['program_end']:04x}"
    )
    assert syms["mmu_common_helpers_blob_end"] - syms["mmu_common_helpers_blob"] <= 0x1FF
    helpers_base = catalog_disk.consts(
        catalog_disk.ROOT / "platforms/commodore/c128/memory128.s"
    )["MMU_COMMON_HELPERS_BASE"]
    helpers_end = helpers_base + (
        syms["mmu_common_helpers_blob_end"] - syms["mmu_common_helpers_blob"]
    )
    assert helpers_end <= syms["runtime_common_data_start"], (
        f"MMU helpers end ${helpers_end:04x} overlaps RuntimeCommonData ${syms['runtime_common_data_start']:04x}"
    )
    assert syms["runtime_common_data_end"] <= syms["mmu_common_cart_copy_chunk"]
    assert syms["mmu_common_cart_copy_end"] <= 0x1000

    for dead in (
        "c128_load_runtime_prg",
        "c128_load_resident_item_names_prg",
        "c128_load_resident_diskio_prg",
        "c128_load_resident_world_prg",
        "c128_load_resident_items_prg",
        "c128_load_resident_select_prg",
        "legal_notice_filename",
        "legal_offer_filename",
    ):
        assert dead not in syms, f"Dead disk symbol still emitted: {dead}"

    overlay_consts = catalog_disk.consts(catalog_disk.ROOT / "platforms/commodore/common/overlay.s")
    assert len(make_c128_md128.OVERLAYS) == contract["CART_OVERLAY_COUNT"]
    for symbol, _ in make_c128_md128.OVERLAYS:
        assert contract["CART_ASSET_" + symbol] - contract["CART_ASSET_STARTUP"] + 1 == overlay_consts["OVL_" + symbol]

    inputs = make_c128_md128.build_inputs(source)
    manifest = json.loads((source / "moria8-c128.json").read_text())
    assert manifest["format"] == "Magic Desk 128"
    assert manifest["crt_type"] == 4
    assert manifest["rom_size"] == make_c128_md128.ROM_SIZE
    assert len(manifest["assets"]) == contract["CART_ASSET_COUNT"]

    prev_end = make_c128_md128.BANK_SIZE
    for asset_id, (name, fname, dest, expected_data, expected_flags) in sorted(inputs.items()):
        desc_off = (contract["CART_DIRECTORY"] - 0x8000) + asset_id * contract["CART_DESCRIPTOR_SIZE"]
        bank, src_addr, dst_addr, size, flags = struct.unpack_from("<BHHHB", rom, desc_off)
        assert bank < make_c128_md128.BANK_COUNT
        assert 0x8000 <= src_addr < 0xC000
        start = bank * make_c128_md128.BANK_SIZE + (src_addr - 0x8000)
        assert start == prev_end and start + size <= len(rom), f"Non-contiguous asset {name}"
        assert dst_addr == dest and size == len(expected_data) and flags == expected_flags
        assert rom[start:start + size] == expected_data, f"ROM mismatch on {name}"

        entry = manifest["assets"][asset_id]
        assert entry["id"] == asset_id
        assert entry["bank"] == bank
        assert entry["source"] == src_addr
        assert entry["destination"] == dst_addr
        assert entry["flags"] == flags
        assert entry["size"] == size
        assert entry["sha256"] == hashlib.sha256(expected_data).hexdigest()
        prev_end = start + size

    print(f"PASS C128 MD128: 16 banks, {len(inputs)} verified assets, common/Bank0 bounds safe")


def selftest() -> None:
    build_test = make_c128_md128.ROOT / "build/test"
    build_test.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=build_test, prefix="md128-selftest-") as tmp:
        path = Path(tmp) / "bad.prg"
        for raw in (b"", b"\x00\xe0", b"\x01\xe0\x00", b"\x00\xe0" + bytes(4097)):
            path.write_bytes(raw)
            try:
                make_c128_md128.prg(path, 0xE000, 0xF000)
            except ValueError:
                pass
            else:
                raise AssertionError("Accepted invalid PRG span")
    print("PASS check_c128_md128.py --selftest")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("crt", nargs="?", type=Path)
    parser.add_argument("source", nargs="?", type=Path)
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if args.crt is None or args.source is None:
        parser.error("crt and source are required unless --selftest is specified")
    check(args.crt, args.source)


if __name__ == "__main__":
    main()
