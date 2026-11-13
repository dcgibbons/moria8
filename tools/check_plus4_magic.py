#!/usr/bin/env python3
"""Independently check a built Plus/4 c264 magic cart CRT, BIN, manifest and payloads."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import tempfile

import catalog_disk
import make_plus4_magic


def selftest() -> None:
    with tempfile.TemporaryDirectory(prefix="plus4-magic-selftest-") as tmp:
        root = Path(tmp)
        path = root / "invalid.prg"
        for raw in (b"", b"\x00\xe0", b"\x01\xe0\x00", b"\x00\xe0" + bytes(4097)):
            path.write_bytes(raw)
            try:
                make_plus4_magic.prg(path, 0xE000, 0xF000)
            except ValueError:
                pass
            else:
                raise AssertionError("Accepted empty, wrongly linked or oversize overlay PRG")
        for bad_dest, bad_len in ((0x7FFF, 2), (0x8000, 16), (0xBFFF, 1), (0xFC00, 1), (0xFBFF, 2)):
            try:
                make_plus4_magic.assert_runtime_destination_safe("bad", bad_dest, bad_len)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Accepted unsafe runtime destination ${bad_dest:04x}+{bad_len}")
        make_plus4_magic.assert_runtime_destination_safe("low", 0x4000, 49)
        make_plus4_magic.assert_runtime_destination_safe("map", 0xC800, 0x0F00)
        make_plus4_magic.assert_runtime_destination_safe("ovl", 0xE000, 0x1000)
        make_plus4_magic.assert_runtime_destination_safe("bank", 0xF000, 0x0C00)
    print("PASS selftest: PRG bounds and Plus/4 runtime destination safety guards verified")


def check(crt: Path, source: Path) -> None:
    image = crt.read_bytes()
    assert image[:16] == b"PLUS4 CARTRIDGE "
    assert struct.unpack_from(">IHHBB", image, 0x10) == (64, 0x0200, 1, 0, 0)

    contract = make_plus4_magic.CONTRACT
    bank_size = contract["CART_ROM_BANK_SIZE"]
    bank_count = contract["CART_BANK_COUNT"]
    chips: dict[int, bytes] = {}
    offset = 64
    while offset < len(image):
        magic, length, chip_type, bank, address, size = struct.unpack_from(">4sIHHHH", image, offset)
        assert (magic, length, chip_type, address, size) == (b"CHIP", bank_size + 16, 0, 0x8000, bank_size)
        assert bank < bank_count
        assert bank not in chips
        chips[bank] = image[offset + 16:offset + length]
        assert len(chips[bank]) == size
        offset += length
    assert offset == len(image) and len(chips) == bank_count

    rom = b"".join(chips[bank] for bank in range(bank_count))
    bin_bytes = (source / "moria8-plus4.bin").read_bytes()
    assert rom == bin_bytes, "Raw .bin does not match CRT CHIP payloads"

    # Autostart header at $8000-$8009: jmp cold, jmp cold, module >= 1, "CBM"
    assert rom[0] == 0x4C and rom[3] == 0x4C and rom[6] >= 1 and rom[7:10] == b"CBM"
    bootrom = (source / "bootrom.bin").read_bytes()
    assert rom[:len(bootrom)] == bootrom

    symbols = {
        name: int(value, 16)
        for name, value in re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", (source / "main.sym").read_text())
    }
    assert symbols["entry"] == contract["CART_ENTRY"]
    assert symbols["cart_reader_start"] >= 0x1001
    assert symbols["cart_reader_end"] <= 0x8000
    assert symbols["cat_record"] + 49 <= 0x8000
    assert symbols["exit_trampoline"] < 0x8000
    assert symbols["program_end"] <= 0xC800
    assert symbols["banked_code_end"] <= 0xFC00

    for dead in (
        "plus4_banked_fname",
        "legal_notice_filename",
        "legal_offer_filename",
        "ovl_reu_start_lo",
        "ovl_reu_start_hi",
        "hal_asset_close_channel",
        "asset_load_ask_for_disk",
    ):
        assert dead not in symbols, f"Dead disk-only symbol present: {dead}"

    shared = catalog_disk.consts(catalog_disk.ROOT / "platforms/commodore/common/overlay.s")
    assert len(make_plus4_magic.OVERLAYS) == contract["CART_OVERLAY_COUNT"]
    for symbol, _ in make_plus4_magic.OVERLAYS:
        assert contract["CART_ASSET_" + symbol] - contract["CART_ASSET_STARTUP"] + 1 == shared["OVL_" + symbol]

    names: dict[int, str | None] = {
        contract["CART_ASSET_RESIDENT"]: "moria4.prg",
        contract["CART_ASSET_RUNTIME"]: "4.bank",
        contract["CART_ASSET_INDEX"]: None,
        contract["CART_ASSET_TITLE"]: "title",
        contract["CART_ASSET_CATALOG"]: None,
        contract["CART_ASSET_LEGAL_UI"]: "legalui",
        contract["CART_ASSET_LEGAL_NOTICE"]: None,
        contract["CART_ASSET_LEGAL_OFFER"]: None,
    }
    names.update({
        contract["CART_ASSET_" + symbol]: f"ovl.{name}"
        for symbol, name in make_plus4_magic.OVERLAYS
    })

    manifest = json.loads((source / "moria8-plus4.json").read_text())
    assert manifest["crt_sha256"] == hashlib.sha256(image).hexdigest()
    assert manifest["bin_sha256"] == hashlib.sha256(bin_bytes).hexdigest()
    assert len(manifest["assets"]) == contract["CART_ASSET_COUNT"]

    previous_end = bank_size
    dir_base = contract["CART_DIRECTORY"] - 0x8000
    desc_size = contract["CART_DESCRIPTOR_SIZE"]
    for asset_id, name in sorted(names.items()):
        bank, address, destination, size, reserved = struct.unpack_from(
            "<BHHHB", rom, dir_base + asset_id * desc_size
        )
        assert reserved == 0 and bank < bank_count and 0x8000 <= address < 0xC000
        start = bank * bank_size + address - 0x8000
        assert start == previous_end and start + size <= len(rom)
        if asset_id == contract["CART_ASSET_RESIDENT"]:
            assert address == 0x8000, "Boot copier requires a page/bank-aligned resident source"
        else:
            make_plus4_magic.assert_runtime_destination_safe(f"asset-{asset_id}", destination, size)

        if asset_id == contract["CART_ASSET_INDEX"]:
            arrays = catalog_disk.byte_arrays((catalog_disk.CATALOG / "catalog_index.s").read_text())
            expected = (
                make_plus4_magic.CATALOG_IDX_LOAD.to_bytes(2, "little")
                + bytes(arrays["cat_level_raw"] + arrays["cat_level_playable"] + arrays["cat_available"])
            )
        elif asset_id == contract["CART_ASSET_CATALOG"]:
            expected = b"\0\0" + b"".join(catalog_disk.records())
        elif asset_id in (contract["CART_ASSET_LEGAL_NOTICE"], contract["CART_ASSET_LEGAL_OFFER"]):
            doc_name = "LICENSE" if asset_id == contract["CART_ASSET_LEGAL_NOTICE"] else "SOURCE-OFFER"
            doc = (make_plus4_magic.ROOT / "data" / doc_name).read_bytes()
            expected = b"\0\0" + doc + b"\0" + bytes((-len(doc) - 1) % 256)
        else:
            expected = (source / name).read_bytes()

        expected_dest = (
            make_plus4_magic.MAP_BASE
            if asset_id == contract["CART_ASSET_TITLE"]
            else int.from_bytes(expected[:2], "little")
        )
        assert destination == expected_dest, asset_id
        assert rom[start:start + size] == expected[2:], asset_id
        entry_meta = manifest["assets"][asset_id]
        assert entry_meta["id"] == asset_id
        assert entry_meta["destination"] == destination
        assert entry_meta["size"] == size
        assert entry_meta["sha256"] == hashlib.sha256(expected[2:]).hexdigest()
        previous_end = start + size

    selftest()
    print(f"PASS CRT: {bank_count} chips, autostart/header, 18 exact assets, compliance texts, raw .bin & manifest")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("crt", nargs="?", type=Path)
    parser.add_argument("source", nargs="?", type=Path)
    args = parser.parse_args()
    if args.selftest:
        selftest()
        if args.crt is None and args.source is None:
            sys.exit(0)
    if args.crt is None or args.source is None:
        parser.error("crt and source paths are required unless running --selftest alone")
    check(args.crt, args.source)
