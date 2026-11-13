#!/usr/bin/env python3
"""Independently check a built CRT's chips, descriptors and source payloads."""
from __future__ import annotations

import argparse
from pathlib import Path
import struct
import tempfile
import re

import catalog_disk
import make_easyflash


def check(crt: Path, source: Path) -> None:
    image = crt.read_bytes()
    assert image[:16] == b"C64 CARTRIDGE   "
    assert struct.unpack_from(">IHHBB", image, 0x10) == (64, 0x100, 32, 1, 0)
    assert image[0x1A] == 0
    chips = {}
    offset = 64
    while offset < len(image):
        magic, length, chip_type, bank, address, size = struct.unpack_from(">4sIHHHH", image, offset)
        assert (magic, length, chip_type, size) == (b"CHIP", 8208, 2, 8192)
        assert bank < 64 and address in (0x8000, 0xA000)
        assert (bank, address) not in chips
        chips[bank, address] = image[offset + 16:offset + length]
        assert len(chips[bank, address]) == size
        offset += length
    assert offset == len(image) and len(chips) == 128
    rom = b"".join(chips[bank, 0x8000] for bank in range(64))
    assert rom[4:9] == b"\xc3\xc2\xcd80"
    assert chips[0, 0xA000] == (source / "romh.bin").read_bytes()
    reset = int.from_bytes(chips[0, 0xA000][-4:-2], "little")
    assert 0xE000 <= reset < 0xFFFA
    contract = make_easyflash.CONTRACT
    symbols = {name: int(value, 16) for name, value in
               re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", (source / "main.sym").read_text())}
    assert symbols["entry"] == contract["CART_ENTRY"]
    boot = {name: int(value, 16) for name, value in
            re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", (source / "cartridge_boot.sym").read_text())}
    bridge = boot["bridge"] - 0xE000
    assert chips[0, 0xA000][bridge:bridge+8] == b"\xa9\x07\x8d\x02\xde\x6c\xfc\xff"
    assert bytes([0x4C]) + symbols["entry"].to_bytes(2, "little") in rom[:0x100]
    for dead in ("reu_detect", "reu_stash_overlays", "reu_show_status_banked",
                 "ultimate_detect",
                 "c64_banked_fname", "asset_load_ask_for_disk",
                 "exit_trampoline", "save_zp", "restore_zp", "zp_save_buf"):
        assert dead not in symbols, dead
    assert symbols["c64u_turbo_fast"] < symbols["c64u_turbo_end"] <= symbols["program_end"] <= 0xC000
    assert symbols["program_end"] <= symbols["c64u_turbo_detect"] < symbols["c64u_turbo_detect_end"]
    shared = catalog_disk.consts(catalog_disk.ROOT / "platforms/commodore/common/overlay.s")
    assert len(make_easyflash.OVERLAYS) == contract["CART_OVERLAY_COUNT"]
    for symbol, _ in make_easyflash.OVERLAYS:
        assert contract["CART_ASSET_" + symbol] - contract["CART_ASSET_STARTUP"] + 1 == shared["OVL_" + symbol]
    names = {contract["CART_ASSET_RESIDENT"]: "moria8.prg",
             contract["CART_ASSET_RUNTIME"]: "64.bank",
             contract["CART_ASSET_INDEX"]: None,
             contract["CART_ASSET_TITLE"]: "title",
             contract["CART_ASSET_CATALOG"]: None,
             contract["CART_ASSET_LEGAL_UI"]: "legalui",
             contract["CART_ASSET_LEGAL_NOTICE"]: None,
             contract["CART_ASSET_LEGAL_OFFER"]: None}
    names.update({contract["CART_ASSET_" + symbol]: f"ovl.{name}"
                  for symbol, name in make_easyflash.OVERLAYS})
    previous_end = 8192
    for asset_id, name in sorted(names.items()):
        bank, address, destination, size, reserved = struct.unpack_from("<BHHHB", rom, contract["CART_DIRECTORY"] - 0x8000 + asset_id * contract["CART_DESCRIPTOR_SIZE"])
        assert reserved == 0 and bank < 64 and 0x8000 <= address < 0xA000
        start = bank*8192 + address - 0x8000
        assert start == previous_end and start + size <= len(rom)
        if asset_id == contract["CART_ASSET_RESIDENT"]:
            assert address == 0x8000, "Boot copier requires an aligned resident source"
        if asset_id == contract["CART_ASSET_INDEX"]:
            arrays = catalog_disk.byte_arrays((catalog_disk.CATALOG / "catalog_index.s").read_text())
            expected = b"\x00\xce" + bytes(arrays["cat_level_raw"] + arrays["cat_level_playable"] + arrays["cat_available"])
        elif asset_id == contract["CART_ASSET_CATALOG"]:
            expected = b"\0\0" + b"".join(catalog_disk.records())
        elif asset_id in (contract["CART_ASSET_LEGAL_NOTICE"], contract["CART_ASSET_LEGAL_OFFER"]):
            name = "LICENSE" if asset_id == contract["CART_ASSET_LEGAL_NOTICE"] else "SOURCE-OFFER"
            doc = (make_easyflash.ROOT / "data" / name).read_bytes()
            expected = b"\0\0" + doc + b"\0" + bytes((-len(doc) - 1) % 256)
        else:
            expected = (source / name).read_bytes()
        assert destination == int.from_bytes(expected[:2], "little"), asset_id
        assert rom[start:start + size] == expected[2:], asset_id
        previous_end = start + size
    # Boundary rejection is checked without changing built inputs.
    with tempfile.TemporaryDirectory(dir=source, prefix="packer-test-") as temp:
        path = Path(temp) / "invalid.prg"
        for raw in (b"", b"\x00\xe0", b"\x01\xe0\x00", b"\x00\xe0" + bytes(4097)):
            path.write_bytes(raw)
            try:
                make_easyflash.prg(path, 0xE000, 0xF000)
            except ValueError:
                pass
            else:
                raise AssertionError("Accepted empty, wrongly linked or oversize overlay")
    print("PASS CRT: 128 chips, reset/header, 18 exact assets, compliance texts, rejected invalid PRGs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("crt", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    check(args.crt, args.source)
