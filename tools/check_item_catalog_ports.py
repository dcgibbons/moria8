#!/usr/bin/env python3
"""Cross-port 0..360 item catalog Name, Category, Hot-Table & Cold-Record verifier.

Verifies all 8 Moria8 disk ports (c64, plus4, c128, apple2, cx16, atari8,
bbcmaster, cpm) AND all 5 shipping cartridges (c64-cart, plus4-cart, c128-cart,
cx16-cart, atari8-cart): compiled hot tables and 'ITM2' ITEM.CAT payload
against item_catalog_spec.json across all 361 item IDs (0..360), 55 egos, and
174 flavours without emulating CPU instructions or port banking registers.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tools"))

import build_item_catalog as bic  # noqa: E402
import catalog_disk  # noqa: E402
import item_ids as IID  # noqa: E402

SPEC_PATH = REPO_ROOT / "platforms/shared/item_catalog/item_catalog_spec.json"
DEFAULT_BUILD_ROOT = REPO_ROOT / "build"

CANONICAL_PORTS = ("c64", "plus4", "c128", "apple2", "cx16", "atari8", "bbcmaster", "cpm")
CANONICAL_CARTS = ("c64-cart", "plus4-cart", "c128-cart", "cx16-cart", "atari8-cart")
ALL_TARGETS = CANONICAL_PORTS + CANONICAL_CARTS
CPM_COM_BASE = 0x0100

PORT_HOT_PRGS: dict[str, tuple[str, ...]] = {
    "c64": ("moria8.prg", "64.bank"),
    "plus4": ("moria4.prg", "4.bank"),
    "c128": ("128.play.prg", "128.item.prg", "moria128.prg", "128.bank.prg"),
    "apple2": ("a2.auxdata", "moria8a2.prg", "a2.play"),
    "cx16": ("CX16.AUXDATA", "MORIA8.PRG"),
    "atari8": ("MORIA8.RES", "ATARI.BNK"),
    "bbcmaster": ("beeb.auxdata", "beeb.play", "moria8.res.prg"),
    "cpm": ("MORIA8.COM",),
    "c64-cart": ("moria8.prg", "64.bank"),
    "plus4-cart": ("moria4.prg", "4.bank"),
    "c128-cart": ("128.play.prg", "128.item.prg", "moria128.prg", "128.bank.prg"),
    "cx16-cart": ("CX16.AUXDATA", "MORIA8.PRG"),
    "atari8-cart": ("MORIA8.RES", "ATARI.BNK"),
}

PORT_ICAT_PATH: dict[str, tuple[str, bool]] = {
    "c64": ("item.cat", True),
    "plus4": ("item.cat", True),
    "c128": ("item.cat", True),
    "apple2": ("bin/ITEM.CAT", False),
    "cx16": ("ITEM.CAT", True),
    "atari8": ("ITEM.CAT", False),
    "bbcmaster": ("bin/ITEM.CAT", False),
    "cpm": ("MORIA8.DAT", False),
}
CPM_DAT_ITEM_CAT_SLOT = 15
CPM_RECORD_SIZE = 128

CART_IMAGE_FILENAME: dict[str, str] = {
    "c64-cart": "moria8-c64.crt",
    "plus4-cart": "moria8-plus4.crt",
    "c128-cart": "moria8-c128.crt",
    "cx16-cart": "moria8-cx16.crt",
    "atari8-cart": "moria8-atari8.car",
}

SYM_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)=\$([0-9a-fA-F]+)")
SJASM_SYM_RE = re.compile(r"^([A-Za-z_@.][A-Za-z0-9_@.]*):\s*EQU\s+(?:0x|\$)([0-9a-fA-F]+)\s*$")
VS_RE = re.compile(r"^al\s+C:([0-9a-fA-F]+)\s+\.([A-Za-z_][A-Za-z0-9_]*)$")


def is_port_built(port: str, build_root: Path = DEFAULT_BUILD_ROOT) -> bool:
    bd = build_root / port
    has_syms = (bd / "main.sym").is_file() or (bd / "main.vs").is_file()
    has_hot = bd.is_dir() and has_syms and (bd / PORT_HOT_PRGS[port][0]).is_file()
    if not has_hot:
        return False
    if port in CART_IMAGE_FILENAME:
        return (build_root / CART_IMAGE_FILENAME[port]).is_file()
    icat_rel, _ = PORT_ICAT_PATH[port]
    return (bd / icat_rel).is_file()


def _load_prg(path: Path) -> tuple[int, bytes]:
    raw = path.read_bytes()
    if len(raw) < 2:
        raise ValueError(f"PRG too short: {path}")
    return raw[0] | (raw[1] << 8), raw[2:]


def _load_segment(port: str, path: Path) -> tuple[int, bytes]:
    if port == "cpm":
        return CPM_COM_BASE, path.read_bytes()
    return _load_prg(path)


def _ascii_code_to_char(code: int) -> str:
    if not (0x20 <= code <= 0x7E):
        raise ValueError(f"Invalid decoded ASCII byte: 0x{code:02x}")
    return chr(code)


def _text_to_ascii_codes(text: str) -> bytes:
    codes = text.encode("ascii")
    for code in codes:
        if not (0x20 <= code <= 0x7E):
            raise ValueError(f"ASCII byte 0x{code:02x} out of literal range for {text!r}")
    return codes


def _extract_vice_crt_rom(
    crt_path: Path,
    expected_sig: bytes,
    bank_count: int,
    bank_size: int,
    chip_addr: int = 0x8000,
) -> bytes:
    raw = crt_path.read_bytes()
    if len(raw) < 64 or raw[:16] != expected_sig:
        raise ValueError(f"Bad CRT signature in {crt_path.name}")
    hdr_len = struct.unpack_from(">I", raw, 0x10)[0]
    chips: dict[int, bytes] = {}
    pos = hdr_len
    while pos + 16 <= len(raw):
        magic, pkt_len, _ctype, bank, addr, size = struct.unpack_from(">4sIHHHH", raw, pos)
        if magic != b"CHIP" or pkt_len < 16 or pos + pkt_len > len(raw):
            raise ValueError(f"Corrupt CHIP packet in {crt_path.name} at {pos}")
        if addr == chip_addr:
            chips[bank] = raw[pos + 16 : pos + 16 + size]
        pos += pkt_len
    erased = b"\xff" * bank_size
    return b"".join(chips.get(b, erased) for b in range(bank_count))


def read_cart_item_cat(port: str, build_root: Path = DEFAULT_BUILD_ROOT) -> bytes:
    img_path = build_root / CART_IMAGE_FILENAME[port]
    if not img_path.is_file():
        raise FileNotFoundError(f"missing cartridge image: {img_path}")

    if port == "c64-cart":
        contract = catalog_disk.consts(REPO_ROOT / "platforms/commodore/c64/cartridge_contract.s")
        rom = _extract_vice_crt_rom(img_path, b"C64 CARTRIDGE   ", 64, 8192, 0x8000)
        desc_off = (contract["CART_DIRECTORY"] - 0x8000) + contract["CART_ASSET_ITEM_CATALOG"] * contract["CART_DESCRIPTOR_SIZE"]
        bank, addr, _dest, size, _res = struct.unpack_from("<BHHHB", rom, desc_off)
        start = bank * 8192 + (addr - 0x8000)
        return rom[start : start + size]

    if port == "plus4-cart":
        contract = catalog_disk.consts(REPO_ROOT / "platforms/commodore/plus4/cartridge_contract.s")
        bank_size = contract["CART_ROM_BANK_SIZE"]
        bank_count = contract["CART_BANK_COUNT"]
        rom = _extract_vice_crt_rom(img_path, b"PLUS4 CARTRIDGE ", bank_count, bank_size, 0x8000)
        desc_off = (contract["CART_DIRECTORY"] - 0x8000) + contract["CART_ASSET_ITEM_CATALOG"] * contract["CART_DESCRIPTOR_SIZE"]
        bank, addr, _dest, size, _res = struct.unpack_from("<BHHHB", rom, desc_off)
        start = bank * bank_size + (addr - 0x8000)
        return rom[start : start + size]

    if port == "c128-cart":
        contract = catalog_disk.consts(REPO_ROOT / "platforms/commodore/c128/cartridge_contract.s")
        bank_size = contract["CART_ROM_BANK_SIZE"]
        bank_count = contract["CART_BANK_COUNT"]
        rom = _extract_vice_crt_rom(img_path, b"C128 CARTRIDGE  ", bank_count, bank_size, 0x8000)
        desc_off = (contract["CART_DIRECTORY"] - 0x8000) + contract["CART_ASSET_ITEM_CATALOG"] * contract["CART_DESCRIPTOR_SIZE"]
        bank, addr, _dest, size, _flags = struct.unpack_from("<BHHHB", rom, desc_off)
        start = bank * bank_size + (addr - 0x8000)
        return rom[start : start + size]

    if port == "cx16-cart":
        raw = img_path.read_bytes()
        if len(raw) < 480 or raw[:16] != b"CX16 CARTRIDGE\r\n":
            raise ValueError(f"Bad CX16 CRT signature in {img_path.name}")
        rom = raw[480:]
        desc_off = 0x0100 + 18 * 8  # Asset 18 = ITEM.CAT
        bank_num, rom_addr, _dest, _ram_bank, size = struct.unpack_from("<BHHBH", rom, desc_off)
        start = (bank_num - 32) * 0x4000 + (rom_addr - 0xC000)
        rom_slice = rom[start : start + size]
        disk_icat = build_root / "cx16-cart" / "ITEM.CAT"
        if disk_icat.is_file():
            file_slice = _load_prg(disk_icat)[1]
            if file_slice != rom_slice:
                raise ValueError("cx16-cart/ITEM.CAT differs from moria8-cx16.crt asset #18")
        return rom_slice

    if port == "atari8-cart":
        contract = catalog_disk.consts(REPO_ROOT / "platforms/atari8/cartridge_contract.s")
        raw = img_path.read_bytes()
        if len(raw) < 16 or raw[:4] != b"CART":
            raise ValueError(f"Bad Atari CAR signature in {img_path.name}")
        rom = raw[16:]
        bank_size = contract["CART_WINDOW_END"] - contract["CART_WINDOW"]
        desc_off = (contract["CART_DIRECTORY"] - contract["CART_WINDOW"]) + contract["CART_ASSET_ITEM_CATALOG"] * contract["CART_DESCRIPTOR_SIZE"]
        bank, addr, _dest, size, _res = struct.unpack_from("<BHHHB", rom, desc_off)
        start = bank * bank_size + (addr - contract["CART_WINDOW"])
        return rom[start : start + size]

    raise ValueError(f"Unknown cartridge target: {port}")


def _read_cpm_dat_item_cat(dat_path: Path, build_dir: Path) -> bytes:
    raw = dat_path.read_bytes()
    if len(raw) < 256 or raw[:4] != b"M8CP" or raw[4] != 1:
        raise ValueError(f"Bad MORIA8.DAT header in {dat_path}")
    entry_count = raw[5]
    if entry_count <= CPM_DAT_ITEM_CAT_SLOT or entry_count > 41:
        raise ValueError(f"{dat_path.name}: entry_count={entry_count} lacks ITEM_CAT slot {CPM_DAT_ITEM_CAT_SLOT}")
    start_rec, rec_count, byte_len = struct.unpack_from("<HHH", raw, 6 + CPM_DAT_ITEM_CAT_SLOT * 6)
    if rec_count == 0 or byte_len == 0:
        raise ValueError(f"{dat_path.name}: ITEM_CAT slot {CPM_DAT_ITEM_CAT_SLOT} is empty")
    start_off = start_rec * CPM_RECORD_SIZE
    end_off = start_off + byte_len
    if start_rec < 2 or end_off > len(raw) or start_off + rec_count * CPM_RECORD_SIZE > len(raw):
        raise ValueError(f"{dat_path.name}: ITEM_CAT slot {CPM_DAT_ITEM_CAT_SLOT} extent out of bounds")
    dat_slice = raw[start_off:end_off]
    raw_icat = build_dir / "item_cat_ascii.bin"
    if raw_icat.is_file() and raw_icat.read_bytes() != dat_slice:
        raise ValueError("cpm/item_cat_ascii.bin differs from MORIA8.DAT slot 15 (DAT_ID_ITEM_CAT)")
    return dat_slice


def read_port_item_cat(port: str, build_root: Path = DEFAULT_BUILD_ROOT) -> bytes:
    if port in CART_IMAGE_FILENAME:
        return read_cart_item_cat(port, build_root)
    if port == "cpm":
        return _read_cpm_dat_item_cat(build_root / "cpm" / "MORIA8.DAT", build_root / "cpm")
    icat_rel, has_prg_hdr = PORT_ICAT_PATH[port]
    path = build_root / port / icat_rel
    return _load_prg(path)[1] if has_prg_hdr else path.read_bytes()


def _parse_symbols(bd: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    if (bd / "main.sym").is_file():
        for line in (bd / "main.sym").read_text(encoding="utf-8").splitlines():
            m = SYM_RE.match(line) or SJASM_SYM_RE.match(line.strip())
            if m:
                name = m.group(1).lstrip("@")
                if name not in syms:
                    syms[name] = int(m.group(2), 16)
    if (bd / "main.vs").is_file():
        for line in (bd / "main.vs").read_text(encoding="utf-8").splitlines():
            m = VS_RE.match(line)
            if m and m.group(2) not in syms:
                syms[m.group(2)] = int(m.group(1), 16)
    return syms


def _read_sym_slice(segments: list[tuple[int, bytes]], addr: int, size: int) -> bytes | None:
    for base, body in segments:
        if base <= addr and addr + size <= base + len(body):
            off = addr - base
            return body[off : off + size]
    return None


def verify_port(
    port: str,
    build_root: Path = DEFAULT_BUILD_ROOT,
    spec: dict | None = None,
    icat_override: bytes | None = None,
    max_errors: int = 20,
) -> list[str]:
    if spec is None:
        spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    bd = build_root / port
    errors: list[str] = []

    def fail(msg: str) -> bool:
        errors.append(f"{port}: {msg}")
        return len(errors) >= max_errors

    orig_s2c = bic.screencode_to_char
    try:
        if port == "cpm":
            bic.screencode_to_char = _ascii_code_to_char
        icat_blob = icat_override if icat_override is not None else read_port_item_cat(port, build_root)
        dec = bic.decode_item_cat(icat_blob)
    except Exception as exc:
        return [f"{port}: ITEM.CAT decode failed: {exc}"]
    finally:
        bic.screencode_to_char = orig_s2c

    items = spec["items"]
    if len(dec["items"]) != len(items):
        return [f"{port}: ITEM.CAT item count {len(dec['items'])} != {len(items)}"]

    cold_keys = (
        "id", "name", "cost", "is_depth_variant", "weight", "dice", "sides",
        "flags", "p1", "tohit", "todam", "toac", "vms_level", "missile_type",
    )
    for exp, got in zip(items, dec["items"]):
        for k in cold_keys:
            if got[k] != exp[k] and fail(f"item #{exp['id']} {k}: {got[k]!r} != {exp[k]!r}"):
                return errors
    for exp, got in zip(spec["egos"], dec["egos"]):
        for k in ("id", "name", "cost_delta", "flags", "p1", "tohit", "todam", "toac"):
            if got[k] != exp[k] and fail(f"ego #{exp['id']} {k}: {got[k]!r} != {exp[k]!r}"):
                return errors
    for exp, got in zip(spec["flavours"], dec["flavours"]):
        if got["name"] != exp["name"] and fail(f"flavour #{exp['id']}: {got['name']!r} != {exp['name']!r}"):
            return errors

    syms = _parse_symbols(bd)
    segments = [_load_segment(port, bd / fn) for fn in PORT_HOT_PRGS[port] if (bd / fn).is_file()]
    extra_ac = [it for it in items if it["base_ac"] >= 15]
    expected_tables = {
        "it_category": bytes(it["cat"] for it in items),
        "it_color_ac": bytes(((it["color"] & 0x0F) << 4) | min(it["base_ac"], 15) for it in items),
        "it_ac_extra_id_lo": bytes(it["id"] & 0xFF for it in extra_ac),
        "it_ac_extra_id_hi": bytes(it["id"] >> 8 for it in extra_ac),
        "it_ac_extra_val": bytes(it["base_ac"] for it in extra_ac),
        "it_unknown_idx": bytes(it["unknown_idx"] for it in items),
        "flavour_colors": bytes(fl["color"] for fl in spec["flavours"]),
    }
    for label, exp_bytes in expected_tables.items():
        if label not in syms:
            if fail(f"missing symbol {label} in {bd}"):
                return errors
            continue
        got_bytes = _read_sym_slice(segments, syms[label], len(exp_bytes))
        if got_bytes is None:
            if fail(f"symbol {label}=${syms[label]:04x} not covered by {PORT_HOT_PRGS[port]}"):
                return errors
            continue
        if got_bytes != exp_bytes:
            idx = next(i for i, (a, b) in enumerate(zip(got_bytes, exp_bytes)) if a != b)
            if fail(f"{label}[{idx}]: 0x{got_bytes[idx]:02x} != 0x{exp_bytes[idx]:02x}"):
                return errors

    return errors


class CheckItemCatalogPortsSelfTest(unittest.TestCase):
    def test_spec_and_synthetic_port_and_cart_roundtrip(self) -> None:
        spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        self.assertEqual(len(spec["items"]), IID.ITEM_TYPE_COUNT)
        self.assertEqual(len(ALL_TARGETS), 13)
        orig_t2s = bic.text_to_screencodes
        orig_s2c = bic.screencode_to_char
        try:
            bic.text_to_screencodes = _text_to_ascii_codes
            bic.screencode_to_char = _ascii_code_to_char
            ascii_blob, _ = bic.build_item_cat(spec)
        finally:
            bic.text_to_screencodes = orig_t2s
            bic.screencode_to_char = orig_s2c
        blob, _ = bic.build_item_cat(spec)
        items = spec["items"]
        extra_ac = [it for it in items if it["base_ac"] >= 15]
        hot_chunks = [
            ("it_category", bytes(it["cat"] for it in items)),
            ("it_color_ac", bytes(((it["color"] & 0x0F) << 4) | min(it["base_ac"], 15) for it in items)),
            ("it_ac_extra_id_lo", bytes(it["id"] & 0xFF for it in extra_ac)),
            ("it_ac_extra_id_hi", bytes(it["id"] >> 8 for it in extra_ac)),
            ("it_ac_extra_val", bytes(it["base_ac"] for it in extra_ac)),
            ("it_unknown_idx", bytes(it["unknown_idx"] for it in items)),
            ("flavour_colors", bytes(fl["color"] for fl in spec["flavours"])),
        ]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bd = root / "c64"
            bd.mkdir()
            sym_lines = []
            payload = bytearray()
            base = 0x4000
            for name, chunk in hot_chunks:
                sym_lines.append(f".label {name}=${base + len(payload):04x}")
                payload.extend(chunk)
            (bd / "main.sym").write_text("\n".join(sym_lines) + "\n", encoding="utf-8")
            (bd / "moria8.prg").write_bytes(b"\x00\x40" + bytes(payload))
            (bd / "item.cat").write_bytes(b"\x00\xe0" + blob)
            self.assertEqual(verify_port("c64", build_root=root, spec=spec), [])

            # Synthetic CX16 cartridge verification + mismatch detection
            cbd = root / "cx16-cart"
            cbd.mkdir()
            (cbd / "main.sym").write_text("\n".join(sym_lines) + "\n", encoding="utf-8")
            (cbd / "CX16.AUXDATA").write_bytes(b"\x00\x40" + bytes(payload))
            (cbd / "MORIA8.PRG").write_bytes(b"\x01\x08\x60")
            (cbd / "ITEM.CAT").write_bytes(b"\x00\xa0" + blob)
            rom = bytearray(8 * 0x4000)
            rom[0x4000 : 0x4000 + len(blob)] = blob
            struct.pack_into("<BHHBH", rom, 0x0100 + 18 * 8, 33, 0xC000, 0xA000, 6, len(blob))
            crt_hdr = bytearray(480)
            crt_hdr[:16] = b"CX16 CARTRIDGE\r\n"
            (root / "moria8-cx16.crt").write_bytes(bytes(crt_hdr) + bytes(rom))
            self.assertEqual(verify_port("cx16-cart", build_root=root, spec=spec), [])

            # Corrupt ITEM.CAT inside CRT -> fails verification
            rom[0x4000] ^= 0xFF
            (root / "moria8-cx16.crt").write_bytes(bytes(crt_hdr) + bytes(rom))
            self.assertTrue(verify_port("cx16-cart", build_root=root, spec=spec))

            bad_prg = bytearray((bd / "moria8.prg").read_bytes())
            bad_prg[2 + 10] ^= 0xFF
            (bd / "moria8.prg").write_bytes(bytes(bad_prg))
            self.assertIn("it_category[10]", verify_port("c64", build_root=root, spec=spec)[0])

            # Synthetic CP/M Z80 verification: sjasmplus EQU symbols, raw MORIA8.COM at 0x0100, MORIA8.DAT slot 15
            zbd = root / "cpm"
            zbd.mkdir()
            z_syms = []
            z_payload = bytearray(0x0200)  # code before hot tables at 0x0100..0x02FF
            z_base = CPM_COM_BASE
            for name, chunk in hot_chunks:
                z_syms.append(f"{name}: EQU 0x{z_base + len(z_payload):08X}")
                z_payload.extend(chunk)
            (zbd / "main.sym").write_text("\n".join(z_syms) + "\n", encoding="utf-8")
            (zbd / "MORIA8.COM").write_bytes(bytes(z_payload))
            (zbd / "item_cat_ascii.bin").write_bytes(ascii_blob)

            def _make_dat(slot15_bytes: bytes) -> bytes:
                recs = (len(slot15_bytes) + CPM_RECORD_SIZE - 1) // CPM_RECORD_SIZE
                hdr = bytearray(256)
                hdr[0:4] = b"M8CP"
                hdr[4] = 1
                hdr[5] = 20
                struct.pack_into("<HHH", hdr, 6 + CPM_DAT_ITEM_CAT_SLOT * 6, 2, recs, len(slot15_bytes))
                padded = slot15_bytes + b"\x00" * (recs * CPM_RECORD_SIZE - len(slot15_bytes))
                return bytes(hdr) + padded

            (zbd / "MORIA8.DAT").write_bytes(_make_dat(ascii_blob))
            self.assertTrue(is_port_built("cpm", build_root=root))
            self.assertEqual(verify_port("cpm", build_root=root, spec=spec), [])
            self.assertIs(bic.screencode_to_char, orig_s2c)

            # Corrupt MORIA8.COM hot table -> detected; bic.screencode_to_char still restored
            bad_com = bytearray(z_payload)
            bad_com[0x0200 + 5] ^= 0xFF
            (zbd / "MORIA8.COM").write_bytes(bytes(bad_com))
            self.assertIn("it_category[5]", verify_port("cpm", build_root=root, spec=spec)[0])
            self.assertIs(bic.screencode_to_char, orig_s2c)

            # Restore MORIA8.COM and corrupt MORIA8.DAT slot 15 -> detected; bic.screencode_to_char restored
            (zbd / "MORIA8.COM").write_bytes(bytes(z_payload))
            bad_ascii = bytearray(ascii_blob)
            bad_ascii[32 + 20 * 4] ^= 0xFF
            (zbd / "MORIA8.DAT").write_bytes(_make_dat(bytes(bad_ascii)))
            self.assertIn("slot 15", verify_port("cpm", build_root=root, spec=spec)[0])
            (zbd / "item_cat_ascii.bin").write_bytes(bytes(bad_ascii))
            self.assertTrue(verify_port("cpm", build_root=root, spec=spec))
            self.assertIs(bic.screencode_to_char, orig_s2c)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify 0..360 item names, categories, and tables across all 8 disk ports and 5 cartridges."
    )
    parser.add_argument("--selftest", action="store_true", help="Run offline unit self-tests")
    parser.add_argument("--port", action="append", choices=ALL_TARGETS, help="Specific port/cart target(s) to verify")
    parser.add_argument("--if-built", action="append", choices=ALL_TARGETS, help="Additional target(s) to verify if built")
    parser.add_argument("--all-built", action="store_true", help="Verify every port/cart whose artifacts exist")
    parser.add_argument("--build-root", type=Path, default=DEFAULT_BUILD_ROOT, help="Build root directory (default: build/)")
    args = parser.parse_args(argv)

    if args.selftest:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(CheckItemCatalogPortsSelfTest)
        return 0 if unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful() else 1

    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    ports: list[str] = list(args.port or [])
    for p in args.if_built or ():
        if p not in ports and is_port_built(p, args.build_root):
            ports.append(p)
    if args.all_built:
        for p in ALL_TARGETS:
            if p not in ports and is_port_built(p, args.build_root):
                ports.append(p)
    if not ports and not args.all_built and not args.if_built:
        ports = list(ALL_TARGETS)
    if not ports:
        print("check_item_catalog_ports: no built targets found to check", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for p in ports:
        errs = verify_port(p, build_root=args.build_root, spec=spec)
        if errs:
            all_errors.extend(errs)
        else:
            print(f"PASS check_item_catalog_ports [{p}]: all {len(spec['items'])} items (0..{len(spec['items']) - 1}) name + category + cold/hot tables verified")
    if all_errors:
        for e in all_errors[:40]:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
