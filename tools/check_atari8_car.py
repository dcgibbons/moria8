#!/usr/bin/env python3
"""Independently verify a built Atari 8-bit .car ROM, descriptors, symbols, and payloads."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import struct
import sys
import tempfile

import catalog_disk
import make_atari8_car


def parse_symbols(sym_path: Path) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(r"\.label\s+(\w+)=\$([0-9a-fA-F]+)", sym_path.read_text())
    }


def check(car: Path, source: Path) -> None:
    image = car.read_bytes()
    contract = make_atari8_car.CONTRACT
    rom_size = make_atari8_car.ROM_SIZE
    assert len(image) == 16 + rom_size, f"Unexpected CAR size: {len(image)}"

    magic = image[:4]
    car_type, checksum, unused = struct.unpack_from(">III", image, 4)
    assert magic == b"CART", magic
    assert car_type == make_atari8_car.CART_TYPE_ATARI_MAX_128KB, car_type
    assert unused == 0, unused
    rom = image[16:]
    assert (sum(rom) & 0xFFFFFFFF) == checksum, "CAR header checksum mismatch"

    raw_bin = source / (car.stem + ".bin")
    assert raw_bin.read_bytes() == rom, "Raw .bin does not match .car ROM payload"

    bank0 = (source / "bank0.bin").read_bytes()
    assert len(bank0) == make_atari8_car.BANK_SIZE
    dir_off = contract["CART_DIRECTORY"] - contract["CART_WINDOW"]
    dir_end = dir_off + contract["CART_ASSET_COUNT"] * contract["CART_DESCRIPTOR_SIZE"]
    assert rom[:dir_off] == bank0[:dir_off]
    assert rom[dir_end:make_atari8_car.BANK_SIZE] == bank0[dir_end:make_atari8_car.BANK_SIZE]

    cart_start, cart_present, cart_flags, cart_init = struct.unpack_from("<HBBH", rom, 0x1FFA)
    assert cart_present == 0x00 and cart_flags == 0x04
    assert 0xA000 <= cart_start < contract["CART_DIRECTORY"]
    assert 0xA000 <= cart_init < contract["CART_DIRECTORY"]
    assert rom[cart_init - 0xA000] == 0x60, "cart_init must execute RTS"

    symbols = parse_symbols(source / "main.sym")
    assert symbols["entry_main"] == contract["CART_ENTRY"]
    assert symbols["cart_read"] < 0x4000
    assert symbols["cart_load_prg"] < 0x4000
    assert symbols["catalog_fetch_record"] < 0x4000
    assert symbols["cat_record"] + 49 <= 0x4000
    assert symbols["low_helpers_end"] <= 0x4000
    assert symbols["program_end"] <= 0xC100
    assert symbols["banked_code_end"] <= 0xFFFA

    for dead in (
        "xe_detect",
        "xe_cache_stash",
        "xe_cache_fetch",
        "xe_slot_populated",
        "a8_cat_find",
        "a8_cat_read",
        "atari_legal_filename",
        "asset_load_ask_for_disk",
        "dsm_show_swap_prompt",
    ):
        assert dead not in symbols, f"Dead disk/130XE symbol present in cartridge build: {dead}"

    names = {
        contract["CART_ASSET_RESIDENT"]: "MORIA8.RES",
        contract["CART_ASSET_RUNTIME"]: "ATARI.BNK",
        contract["CART_ASSET_TITLE"]: "TITLE.DAT",
        contract["CART_ASSET_CATALOG"]: None,
        contract["CART_ASSET_ITEM_CATALOG"]: None,
        contract["CART_ASSET_LEGAL_UI"]: "legalui",
        contract["CART_ASSET_LEGAL_NOTICE"]: None,
        contract["CART_ASSET_LEGAL_OFFER"]: None,
    }
    names.update({
        contract["CART_ASSET_" + symbol]: f"OVL.{ext}"
        for symbol, ext in make_atari8_car.OVERLAYS
    })

    page_aligned_ids = {
        contract["CART_ASSET_RESIDENT"],
        contract["CART_ASSET_LEGAL_NOTICE"],
        contract["CART_ASSET_LEGAL_OFFER"],
    }
    previous_end = make_atari8_car.BANK_SIZE
    for asset_id, name in sorted(names.items()):
        bank, address, destination, size, reserved = struct.unpack_from(
            "<BHHHB", rom, dir_off + asset_id * contract["CART_DESCRIPTOR_SIZE"]
        )
        assert reserved == 0
        assert 1 <= bank < make_atari8_car.BANK_COUNT
        assert contract["CART_WINDOW"] <= address < contract["CART_WINDOW_END"]
        start = bank * make_atari8_car.BANK_SIZE + address - contract["CART_WINDOW"]
        expected_start = (previous_end + 255) & ~255 if asset_id in page_aligned_ids else previous_end
        assert start == expected_start, (asset_id, start, expected_start)
        assert all(b == 0xFF for b in rom[previous_end:start]), asset_id
        assert start + size <= len(rom), (asset_id, start, size)

        if asset_id == contract["CART_ASSET_RESIDENT"]:
            assert address == contract["CART_WINDOW"], "Boot copier requires page-aligned resident source"
        else:
            assert destination == 0 or (destination + size <= 0xA000 or destination >= 0xC000), (
                f"Post-boot asset overlaps cartridge window: {asset_id} ${destination:04x}+${size:x}"
            )

        if asset_id == contract["CART_ASSET_CATALOG"]:
            expected = b"\0\0" + b"".join(catalog_disk.records())
        elif asset_id == contract["CART_ASSET_ITEM_CATALOG"]:
            expected = b"\0\0" + catalog_disk.item_atari_bytes()
        elif asset_id in (contract["CART_ASSET_LEGAL_NOTICE"], contract["CART_ASSET_LEGAL_OFFER"]):
            doc_name = "LICENSE" if asset_id == contract["CART_ASSET_LEGAL_NOTICE"] else "SOURCE-OFFER"
            doc = (make_atari8_car.ROOT / "data" / doc_name).read_bytes()
            expected = b"\0\0" + doc + b"\0" + bytes((-len(doc) - 1) % 256)
        else:
            expected = (source / name).read_bytes()

        assert destination == int.from_bytes(expected[:2], "little"), asset_id
        assert rom[start:start + size] == expected[2:], asset_id
        previous_end = start + size

    assert all(b == 0xFF for b in rom[previous_end:]), "Trailing ROM bytes must stay erased ($FF)"
    print(
        f"PASS CAR: type 41, checksum ${checksum:08x}, {len(names)} exact assets, "
        f"{previous_end}/{rom_size} bytes used, zero $A000-$BFFF post-boot overlaps"
    )


def selftest() -> None:
    with tempfile.TemporaryDirectory(prefix="atari8-car-selftest-") as tmp:
        tmp_path = Path(tmp)
        bad = tmp_path / "invalid.prg"
        cases = (
            (b"", (0xE000, 0xF000, True, False)),
            (b"\x00\xe0", (0xE000, 0xF000, True, False)),
            (b"\x01\xe0\x00", (0xE000, 0xF000, True, False)),
            (b"\x00\xe0" + bytes(4097), (0xE000, 0xF000, True, False)),
            (b"\x00\xa0\x00", (0x0C00, 0xC100, False, False)),
            (b"\xff\x9f\x01\x02", (0x0C00, 0xC100, False, False)),
        )
        for raw, params in cases:
            bad.write_bytes(raw)
            try:
                make_atari8_car.prg(bad, *params)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Packer accepted invalid PRG case: len={len(raw)}")
    print("PASS CAR selftest: invalid/oversize/$A000-overlapping PRGs rejected")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("car", nargs="?", type=Path)
    parser.add_argument("source", nargs="?", type=Path)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        if args.car is None:
            sys.exit(0)
    if args.car is None or args.source is None:
        parser.error("car and source paths are required unless --selftest is run standalone")
    check(args.car, args.source)
