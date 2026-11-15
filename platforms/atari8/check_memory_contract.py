#!/usr/bin/env python3
"""Static memory-contract checker for the Atari 8-bit port (platforms/atari8/)."""

from __future__ import annotations

import argparse
import re
import struct
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUILD_DIR = ROOT / "build" / "atari8"

OS_PAGE2_DCB_BASE = 0x0200
OS_PAGE2_DCB_END = 0x031A
LOW_RESIDENT_START = 0x0C00
LOW_HELPERS_LIMIT = 0x4000
MAP_BASE = 0xC100
MAP_END = 0xCFFF
IO_HOLE_BASE = 0xD000
IO_HOLE_END = 0xD7FF
HIGH_RESIDENT_BASE = 0xD800
OVERLAY_BASE = 0xE000
OVERLAY_LIMIT = 0xF000
BANKED_BASE = 0xF000
BANKED_LIMIT = 0xFFFA

ALLOWED_MAP_SYMBOLS = {
    "MAP_BASE",
    "MAP_END",
    "CREATURE_BASE",
    "hiscore_table",
}

ALLOWED_IO_SYMBOLS = {
    "hal_entropy_timer0_lo",
    "hal_entropy_timer0_hi",
    "hal_entropy_timer1_lo",
    "hal_entropy_timer1_hi",
}

REQUIRED_HIGH_RESIDENT_SYMBOLS = {
    "fi_item_id": 0xDC00,
    "hd_decode_buf": 0xDD00,
    "zp_save_buf": 0xDD40,
    "msg_history": 0xDDCE,
}

REQUIRED_LOW_SYMBOLS = (
    "entry_main",
    "atari_font_init",
    "atari_nmi_handler",
    "atari_irq_handler",
    "exit_trampoline",
    "EnterSio",
    "ExitSio",
    "save_zp",
    "restore_zp",
    "sio_sector_buf",
    "xe_detect",
    "xe_cache_stash",
    "xe_cache_fetch",
    "xe_slot_populated",
    "xe_slot_portb",
    "xe_slot_win_hi",
    "xe_slot_ram_hi",
    "xe_slot_pages",
    "hal_asset_load_prg_header",
    "hal_asset_load_title",
    "hal_storage_probe_media",
    "atari_write_sio_sector",
    "hal_storage_open",
    "hal_storage_chrin",
    "hal_storage_chrout",
    "hal_storage_close",
    "hal_item_cat_read_byte",
    "low_helpers_end",
)

OVERLAY_FILES = (
    "OVL.STA",
    "OVL.TWN",
    "OVL.DTH",
    "OVL.MDL",
    "OVL.HLP",
    "OVL.UI",
    "OVL.ITM",
    "OVL.SPL",
    "OVL.CHS",
    "OVL.GEN",
    "OVL.HOM",
    "OVL.STO",
    "OVL.TTL",
    "legalui",
)

# The monster catalog's records (monster_catalog_a8.s): 125 data bytes per
# DOS 2.5 sector, staged through the 4 KB $E000 window 32 sectors at a time
# on a 130XE, so it fits five slots (10..13 full 16p + 15 tail).
CATALOG_FILE = "MONSTER.CAT"
CATALOG_MAX_SECTORS = 5 * 32
ITEM_CATALOG_FILE = "ITEM.CAT"
ITEM_CATALOG_MAX_BYTES = 7800

XE_SLOT_COUNT = 19
XE_WIN_BASE_HI = 0x40
XE_WIN_LIMIT_HI = 0x80
XE_BANK_PORTB_TO_ID = {
    0xE2: 0,
    0xE6: 1,
    0xEA: 2,
    0xEE: 3,
}
XE_OVERLAY_SLOT_FILES = {
    0: "OVL.STA",
    1: "OVL.TWN",
    2: "OVL.DTH",
    3: "OVL.GEN",
    4: "OVL.HLP",
    5: "OVL.UI",
    6: "OVL.ITM",
    7: "OVL.SPL",
    8: "OVL.MDL",
    9: "OVL.CHS",
    16: "OVL.HOM",
    17: "OVL.STO",
    18: "OVL.TTL",
}
XE_CATALOG_FULL_SLOTS = (10, 11, 12, 13)
XE_CATALOG_TAIL_SLOT = 15
XE_TITLE_SLOT = 14

LABEL_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$([0-9A-Fa-f]+)\b")


def parse_sym_file(sym_path: Path) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in sym_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = LABEL_RE.match(line.strip())
        if match:
            symbols[match.group(1)] = int(match.group(2), 16)
    return symbols


def prg_span(prg_path: Path) -> tuple[int, int]:
    data = prg_path.read_bytes()
    if len(data) < 3:
        raise ValueError(f"{prg_path.name}: PRG too short ({len(data)} bytes)")
    start = struct.unpack_from("<H", data, 0)[0]
    end_excl = start + (len(data) - 2)
    return start, end_excl


def page_ceil(byte_count: int) -> int:
    return (byte_count + 255) // 256


def validate_xe_slots(
    symbols: dict[str, int],
    res_bytes: bytes,
    res_start: int,
    overlay_spans: dict[str, tuple[int, int]],
    title_span: tuple[int, int] | None,
    cat_sectors: int | None,
) -> list[str]:
    errors: list[str] = []
    table_syms = ("xe_slot_portb", "xe_slot_win_hi", "xe_slot_ram_hi", "xe_slot_pages")
    if any(sym not in symbols for sym in table_syms):
        return errors

    portb_addr, win_addr, ram_addr, pages_addr = (symbols[s] for s in table_syms)
    if win_addr != portb_addr + XE_SLOT_COUNT or ram_addr != win_addr + XE_SLOT_COUNT or pages_addr != ram_addr + XE_SLOT_COUNT:
        errors.append(
            f"130XE slot tables (xe_slot_portb/win_hi/ram_hi/pages) are not contiguous {XE_SLOT_COUNT}-byte tables"
        )
        return errors

    tables: list[list[int]] = []
    for sym, addr in zip(table_syms, (portb_addr, win_addr, ram_addr, pages_addr)):
        off = addr - res_start
        if off < 0 or off + XE_SLOT_COUNT > len(res_bytes):
            errors.append(f"{sym} at ${addr:04X} falls outside MORIA8.RES payload")
            return errors
        tables.append(list(res_bytes[off : off + XE_SLOT_COUNT]))

    slot_portb, slot_win_hi, slot_ram_hi, slot_pages = tables
    by_bank: dict[int, list[tuple[int, int, int]]] = {0: [], 1: [], 2: [], 3: []}

    for slot in range(XE_SLOT_COUNT):
        portb = slot_portb[slot]
        win_hi = slot_win_hi[slot]
        pages = slot_pages[slot]

        if portb not in XE_BANK_PORTB_TO_ID:
            errors.append(f"130XE slot {slot} invalid PORTB ${portb:02X}")
            continue
        if pages < 1:
            errors.append(f"130XE slot {slot} invalid page count {pages}")
            continue
        end_hi = win_hi + pages
        if win_hi < XE_WIN_BASE_HI or end_hi > XE_WIN_LIMIT_HI:
            errors.append(
                f"130XE slot {slot} window ${win_hi:02X}00-${end_hi - 1:02X}FF crosses $4000-$7FFF bank bounds"
            )
            continue

        bank = XE_BANK_PORTB_TO_ID[portb]
        for prev_slot, prev_start, prev_end in by_bank[bank]:
            if max(win_hi, prev_start) < min(end_hi, prev_end):
                errors.append(
                    f"130XE Bank {bank} (${portb:02X}) overlap: slot {slot} (${win_hi:02X}00-${end_hi - 1:02X}FF) "
                    f"overlaps slot {prev_slot} (${prev_start:02X}00-${prev_end - 1:02X}FF)"
                )
        by_bank[bank].append((slot, win_hi, end_hi))

    ovl_ram_hi = OVERLAY_BASE >> 8
    ovl_limit_hi = OVERLAY_LIMIT >> 8
    for slot, fname in XE_OVERLAY_SLOT_FILES.items():
        ram_hi = slot_ram_hi[slot]
        pages = slot_pages[slot]
        if ram_hi != ovl_ram_hi:
            errors.append(f"130XE slot {slot} ({fname}) xe_slot_ram_hi=${ram_hi:02X} != ${ovl_ram_hi:02X}")
        elif ram_hi + pages > ovl_limit_hi:
            errors.append(f"130XE slot {slot} ({fname}) RAM span exceeds $E000-$EFFF ({pages} pages)")
        if fname in overlay_spans:
            payload_len, actual_pages = overlay_spans[fname]
            if actual_pages > pages:
                errors.append(
                    f"130XE slot {slot} ({fname}) overflow: payload {payload_len} B needs {actual_pages} pages "
                    f"> xe_slot_pages[{slot}]={pages}"
                )

    for slot in XE_CATALOG_FULL_SLOTS:
        if slot_ram_hi[slot] != ovl_ram_hi:
            errors.append(f"130XE slot {slot} ({CATALOG_FILE}) xe_slot_ram_hi=${slot_ram_hi[slot]:02X} != ${ovl_ram_hi:02X}")
        if slot_pages[slot] != 16:
            errors.append(f"130XE slot {slot} ({CATALOG_FILE}) xe_slot_pages={slot_pages[slot]} != 16")

    tail_ram_hi = slot_ram_hi[XE_CATALOG_TAIL_SLOT]
    tail_pages = slot_pages[XE_CATALOG_TAIL_SLOT]
    if tail_ram_hi != ovl_ram_hi:
        errors.append(f"130XE slot {XE_CATALOG_TAIL_SLOT} ({CATALOG_FILE} tail) xe_slot_ram_hi=${tail_ram_hi:02X} != ${ovl_ram_hi:02X}")
    elif tail_ram_hi + tail_pages > ovl_limit_hi:
        errors.append(f"130XE slot {XE_CATALOG_TAIL_SLOT} ({CATALOG_FILE} tail) staging exceeds $E000-$EFFF")
    if cat_sectors is not None:
        tail_sectors = max(0, cat_sectors - len(XE_CATALOG_FULL_SLOTS) * 32)
        actual_tail_pages = page_ceil(tail_sectors * 128)
        if actual_tail_pages > tail_pages:
            errors.append(
                f"130XE slot {XE_CATALOG_TAIL_SLOT} ({CATALOG_FILE} tail) overflow: {tail_sectors} sectors need "
                f"{actual_tail_pages} pages > xe_slot_pages[{XE_CATALOG_TAIL_SLOT}]={tail_pages}"
            )

    title_ram_hi = slot_ram_hi[XE_TITLE_SLOT]
    title_pages = slot_pages[XE_TITLE_SLOT]
    map_ram_hi = MAP_BASE >> 8
    io_ram_hi = IO_HOLE_BASE >> 8
    if title_ram_hi != map_ram_hi:
        errors.append(f"130XE slot {XE_TITLE_SLOT} (TITLE.DAT) xe_slot_ram_hi=${title_ram_hi:02X} != ${map_ram_hi:02X}")
    elif title_ram_hi + title_pages > io_ram_hi:
        errors.append(
            f"130XE slot {XE_TITLE_SLOT} (TITLE.DAT) RAM span ${title_ram_hi:02X}00+${title_pages:02X}00 crosses into $D000 I/O"
        )
    if title_span is not None:
        payload_len, actual_pages = title_span
        if actual_pages > title_pages:
            errors.append(
                f"130XE slot {XE_TITLE_SLOT} (TITLE.DAT) overflow: payload {payload_len} B needs {actual_pages} pages "
                f"> xe_slot_pages[{XE_TITLE_SLOT}]={title_pages}"
            )

    return errors


def validate_build(build_dir: Path) -> list[str]:
    errors: list[str] = []
    sym_path = build_dir / "main.sym"
    if not sym_path.exists():
        return [f"missing symbol file {sym_path}"]

    symbols = parse_sym_file(sym_path)

    for sym in REQUIRED_LOW_SYMBOLS:
        if sym not in symbols:
            errors.append(f"missing required low-resident symbol {sym}")
            continue
        addr = symbols[sym]
        limit = LOW_HELPERS_LIMIT if sym == "low_helpers_end" else LOW_HELPERS_LIMIT - 1
        if not (LOW_RESIDENT_START <= addr <= limit):
            errors.append(f"{sym} at ${addr:04X} violates < $4000 low-RAM contract")

    if "program_end" not in symbols:
        errors.append("missing symbol program_end")
    else:
        prog_end = symbols["program_end"]
        if not (LOW_RESIDENT_START <= prog_end <= MAP_BASE):
            errors.append(f"program_end at ${prog_end:04X} exceeds MAP_BASE (${MAP_BASE:04X})")

    if "banked_code_end" not in symbols:
        errors.append("missing symbol banked_code_end")
    else:
        bank_end = symbols["banked_code_end"]
        if not (BANKED_BASE <= bank_end <= BANKED_LIMIT):
            errors.append(f"banked_code_end at ${bank_end:04X} exceeds CPU vectors (${BANKED_LIMIT:04X})")

    # Check HighResident symbols ($D800-$DFFF)
    for sym, expected_addr in REQUIRED_HIGH_RESIDENT_SYMBOLS.items():
        if sym not in symbols:
            errors.append(f"missing required high-resident symbol {sym}")
        elif symbols[sym] != expected_addr:
            errors.append(f"{sym} at ${symbols[sym]:04X} != expected ${expected_addr:04X}")

    if "high_resident_end" not in symbols:
        errors.append("missing symbol high_resident_end")
    else:
        high_end = symbols["high_resident_end"]
        if not (HIGH_RESIDENT_BASE <= high_end <= OVERLAY_BASE):
            errors.append(f"high_resident_end at ${high_end:04X} exceeds ${OVERLAY_BASE:04X}")

    # Check symbol overlap with protected windows ($0200-$031A, $C100-$CFFF, $D000-$D7FF)
    for sym, addr in symbols.items():
        if OS_PAGE2_DCB_BASE <= addr <= OS_PAGE2_DCB_END:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps protected OS Page 2 / DCB (${OS_PAGE2_DCB_BASE:04X}-${OS_PAGE2_DCB_END:04X})"
            )
        elif MAP_BASE <= addr <= MAP_END and sym not in ALLOWED_MAP_SYMBOLS:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps MAP_BASE (${MAP_BASE:04X}-${MAP_END:04X})"
            )
        elif IO_HOLE_BASE <= addr <= IO_HOLE_END and sym not in ALLOWED_IO_SYMBOLS:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps Hardware I/O hole (${IO_HOLE_BASE:04X}-${IO_HOLE_END:04X})"
            )

    # Check MORIA8.RES PRG span
    res_prg = build_dir / "MORIA8.RES"
    res_bytes: bytes | None = None
    res_start = 0
    if not res_prg.exists():
        errors.append("missing MORIA8.RES")
    else:
        raw_res = res_prg.read_bytes()
        start, end_excl = prg_span(res_prg)
        res_start = start
        res_bytes = raw_res[2:]
        if start != LOW_RESIDENT_START:
            errors.append(f"MORIA8.RES load address ${start:04X} != ${LOW_RESIDENT_START:04X}")
        if end_excl > MAP_BASE:
            errors.append(f"MORIA8.RES end ${end_excl:04X} overlaps MAP_BASE (${MAP_BASE:04X})")

    # Check ATARI.BNK PRG span
    bnk_prg = build_dir / "ATARI.BNK"
    if not bnk_prg.exists():
        errors.append("missing ATARI.BNK")
    else:
        start, end_excl = prg_span(bnk_prg)
        if start != BANKED_BASE:
            errors.append(f"ATARI.BNK load address ${start:04X} != ${BANKED_BASE:04X}")
        if end_excl > BANKED_LIMIT:
            errors.append(f"ATARI.BNK end ${end_excl:04X} overlaps CPU vectors (${BANKED_LIMIT:04X})")

    # The monster catalog's records: within the 130XE slots that hold them
    cat_file = build_dir / CATALOG_FILE
    cat_sectors: int | None = None
    if not cat_file.exists():
        errors.append(f"missing {CATALOG_FILE}")
    else:
        cat_sectors = -(-cat_file.stat().st_size // 125)
        if cat_sectors > CATALOG_MAX_SECTORS:
            errors.append(f"{CATALOG_FILE} needs more than {CATALOG_MAX_SECTORS} sectors")

    # Packed 'ITM2' item catalog streamed from disk / MaxFlash cartridge by LowHelpers.
    icat_file = build_dir / ITEM_CATALOG_FILE
    if not icat_file.exists():
        errors.append(f"missing {ITEM_CATALOG_FILE}")
    else:
        icat_bytes = icat_file.read_bytes()
        if len(icat_bytes) < 6 or len(icat_bytes) > ITEM_CATALOG_MAX_BYTES:
            errors.append(
                f"{ITEM_CATALOG_FILE} size {len(icat_bytes)} B outside valid 6..{ITEM_CATALOG_MAX_BYTES} B range"
            )
        elif icat_bytes[:4] != b"ITM2":
            errors.append(f"{ITEM_CATALOG_FILE} missing ITM2 header")
        else:
            decl_size = struct.unpack_from("<H", icat_bytes, 4)[0]
            if decl_size != len(icat_bytes):
                errors.append(
                    f"{ITEM_CATALOG_FILE} declared size {decl_size} != file size {len(icat_bytes)}"
                )

    # Check overlays ($E000-$EFFF)
    overlay_spans: dict[str, tuple[int, int]] = {}
    for name in OVERLAY_FILES:
        p = build_dir / name
        if not p.exists():
            errors.append(f"missing {name}")
            continue
        start, end_excl = prg_span(p)
        payload_len = end_excl - start
        overlay_spans[name] = (payload_len, page_ceil(payload_len))
        if start != OVERLAY_BASE:
            errors.append(f"{name} load address ${start:04X} != ${OVERLAY_BASE:04X}")
        if end_excl > OVERLAY_LIMIT:
            errors.append(f"{name} end ${end_excl:04X} exceeds ${OVERLAY_LIMIT:04X}")

    # Check TITLE.DAT ($C100, <= 3 pages = 768 B)
    title_prg = build_dir / "TITLE.DAT"
    title_span: tuple[int, int] | None = None
    if not title_prg.exists():
        errors.append("missing TITLE.DAT")
    else:
        start, end_excl = prg_span(title_prg)
        payload_len = end_excl - start
        title_span = (payload_len, page_ceil(payload_len))
        if start != MAP_BASE:
            errors.append(f"TITLE.DAT load address ${start:04X} != ${MAP_BASE:04X}")
        if payload_len > 0x0300:
            errors.append(f"TITLE.DAT payload {payload_len} B exceeds 3-page (768 B) 130XE Slot 14 span")

    if res_bytes is not None:
        errors.extend(validate_xe_slots(symbols, res_bytes, res_start, overlay_spans, title_span, cat_sectors))

    # Check boot.prg ($0800, 384 B)
    boot_prg = build_dir / "boot.prg"
    if not boot_prg.exists():
        errors.append("missing boot.prg")
    else:
        start, end_excl = prg_span(boot_prg)
        if start != 0x0800 or (end_excl - start) != 384:
            errors.append(f"boot.prg span ${start:04X}-${end_excl:04X} must be $0800-$0980 (384 B)")

    return errors


def write_synthetic_prg(path: Path, start: int, length: int) -> None:
    path.write_bytes(struct.pack("<H", start) + (b"\xea" * length))


def patch_synthetic_xe_tables(
    res_path: Path,
    portb_addr: int,
    portb: list[int],
    win_hi: list[int],
    ram_hi: list[int],
    pages: list[int],
) -> None:
    buf = bytearray(res_path.read_bytes())
    off = 2 + (portb_addr - LOW_RESIDENT_START)
    buf[off : off + 4 * XE_SLOT_COUNT] = bytes(portb + win_hi + ram_hi + pages)
    res_path.write_bytes(bytes(buf))


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        bdir = Path(tmp)
        sym_addrs = {name: 0x0C00 + i * 0x20 for i, name in enumerate(REQUIRED_LOW_SYMBOLS)}
        table_base = 0x0C00 + len(REQUIRED_LOW_SYMBOLS) * 0x20
        sym_addrs["xe_slot_portb"] = table_base
        sym_addrs["xe_slot_win_hi"] = table_base + XE_SLOT_COUNT
        sym_addrs["xe_slot_ram_hi"] = table_base + 2 * XE_SLOT_COUNT
        sym_addrs["xe_slot_pages"] = table_base + 3 * XE_SLOT_COUNT
        sym_lines = [f".label {name}=${addr:04x}" for name, addr in sym_addrs.items()]
        sym_lines.append(".label program_end=$bd00")
        sym_lines.append(".label banked_code_end=$fe80")
        for sym, addr in REQUIRED_HIGH_RESIDENT_SYMBOLS.items():
            sym_lines.append(f".label {sym}=${addr:04x}")
        sym_lines.append(".label high_resident_end=$df0e")
        base_sym_text = "\n".join(sym_lines) + "\n"
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")

        base_portb = [
            0xE2, 0xE2, 0xEA, 0xEE,
            0xEA, 0xE2, 0xE2, 0xEA,
            0xEE, 0xEA, 0xE6, 0xE6,
            0xE6, 0xE6, 0xEA, 0xEA,
            0xEA, 0xEE, 0xEA,
        ]
        base_win_hi = [
            0x40, 0x50, 0x59, 0x4E,
            0x50, 0x60, 0x70, 0x40,
            0x40, 0x65, 0x40, 0x50,
            0x60, 0x70, 0x77, 0x71,
            0x7A, 0x5D, 0x7E,
        ]
        base_ram_hi = [0xE0] * 14 + [0xC1, 0xE0, 0xE0, 0xE0, 0xE0]
        base_pages = [16, 16, 12, 15, 9, 16, 16, 16, 14, 12, 16, 16, 16, 16, 3, 6, 4, 14, 2]

        res_path = bdir / "MORIA8.RES"
        write_synthetic_prg(res_path, 0x0C00, 0xB100)
        patch_synthetic_xe_tables(
            res_path, sym_addrs["xe_slot_portb"], base_portb, base_win_hi, base_ram_hi, base_pages
        )
        write_synthetic_prg(bdir / "ATARI.BNK", 0xF000, 0x0E80)
        write_synthetic_prg(bdir / "TITLE.DAT", 0xC100, 621)
        write_synthetic_prg(bdir / "boot.prg", 0x0800, 384)
        for slot, fname in XE_OVERLAY_SLOT_FILES.items():
            write_synthetic_prg(bdir / fname, 0xE000, base_pages[slot] * 256 - 2)
        write_synthetic_prg(bdir / "legalui", 0xE000, 0x03DD)
        (bdir / CATALOG_FILE).write_bytes(bytes(139 * 125 + 49))
        (bdir / ITEM_CATALOG_FILE).write_bytes(b"ITM2" + struct.pack("<H", 7573) + bytes(7573 - 6))

        errs = validate_build(bdir)
        if errs:
            print(f"FAIL: valid synthetic build rejected: {errs}", file=sys.stderr)
            return 1

        # Negative test 1: low helper above $4000 must fail
        enter_sio_str = f"EnterSio=${sym_addrs['EnterSio']:04x}"
        (bdir / "main.sym").write_text(base_sym_text.replace(enter_sio_str, "EnterSio=$4000"), encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch EnterSio >= $4000", file=sys.stderr)
            return 1

        # Negative test 2: program_end overlapping MAP_BASE ($C100) must fail
        (bdir / "main.sym").write_text(base_sym_text.replace("program_end=$bd00", "program_end=$c101"), encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch program_end > MAP_BASE", file=sys.stderr)
            return 1

        # Negative test 3: symbol in OS Page 2 / DCB ($0200-$031A) must fail
        (bdir / "main.sym").write_text(base_sym_text + ".label bad_os_sym=$0220\n", encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $0200-$031A", file=sys.stderr)
            return 1

        # Negative test 4: symbol in Hardware I/O hole ($D000-$D7FF) must fail
        (bdir / "main.sym").write_text(base_sym_text + ".label bad_io_sym=$d200\n", encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $D000-$D7FF", file=sys.stderr)
            return 1

        # Negative test 5: symbol in MAP_BASE ($C100-$CFFF) must fail
        (bdir / "main.sym").write_text(base_sym_text + ".label bad_map_sym=$c500\n", encoding="utf-8")
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $C100-$CFFF", file=sys.stderr)
            return 1
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")

        # Negative test 6: 130XE slot crossing $7FFF must fail
        bad_win = list(base_win_hi)
        bad_win[3] = 0x72  # +15 pages -> $81 > $80
        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], base_portb, bad_win, base_ram_hi, base_pages)
        if not validate_build(bdir):
            print("FAIL: failed to catch 130XE slot crossing $7FFF", file=sys.stderr)
            return 1

        # Negative test 7: 130XE slot overlap within the same bank must fail
        bad_win = list(base_win_hi)
        bad_win[3] = 0x45  # overlaps slot 8 ($40..$4D) in Bank 3
        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], base_portb, bad_win, base_ram_hi, base_pages)
        if not validate_build(bdir):
            print("FAIL: failed to catch 130XE bank overlap", file=sys.stderr)
            return 1

        # Negative test 8: invalid 130XE PORTB value must fail
        bad_portb = list(base_portb)
        bad_portb[0] = 0xFE
        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], bad_portb, base_win_hi, base_ram_hi, base_pages)
        if not validate_build(bdir):
            print("FAIL: failed to catch invalid 130XE PORTB value", file=sys.stderr)
            return 1

        # Negative test 9: TITLE.DAT crossing into $D000 via ram_hi/pages must fail
        bad_ram = list(base_ram_hi)
        bad_ram[14] = 0xCE
        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], base_portb, base_win_hi, bad_ram, base_pages)
        if not validate_build(bdir):
            print("FAIL: failed to catch 130XE TITLE.DAT crossing $D000", file=sys.stderr)
            return 1

        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], base_portb, base_win_hi, base_ram_hi, base_pages)

        # Negative test 10: overlay payload exceeding xe_slot_pages[slot] must fail
        write_synthetic_prg(bdir / "OVL.DTH", 0xE000, base_pages[2] * 256 + 1)
        if not validate_build(bdir):
            print("FAIL: failed to catch OVL.DTH exceeding xe_slot_pages[2]", file=sys.stderr)
            return 1
        write_synthetic_prg(bdir / "OVL.DTH", 0xE000, base_pages[2] * 256 - 2)

        # Negative test 11: MONSTER.CAT tail exceeding xe_slot_pages[15] must fail
        (bdir / CATALOG_FILE).write_bytes(bytes(140 * 125 + 1))
        if not validate_build(bdir):
            print("FAIL: failed to catch MONSTER.CAT tail exceeding xe_slot_pages[15]", file=sys.stderr)
            return 1
        (bdir / CATALOG_FILE).write_bytes(bytes(139 * 125 + 49))

        # Negative test 12: TITLE.DAT exceeding xe_slot_pages[14] must fail
        bad_pages = list(base_pages)
        bad_pages[14] = 2  # TITLE.DAT is 621 B -> needs 3 pages
        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], base_portb, base_win_hi, base_ram_hi, bad_pages)
        if not validate_build(bdir):
            print("FAIL: failed to catch TITLE.DAT exceeding xe_slot_pages[14]", file=sys.stderr)
            return 1
        patch_synthetic_xe_tables(res_path, sym_addrs["xe_slot_portb"], base_portb, base_win_hi, base_ram_hi, base_pages)

        # Negative test 13: OVL.STO exceeding xe_slot_pages[17] must fail
        write_synthetic_prg(bdir / "OVL.STO", 0xE000, base_pages[17] * 256 + 1)
        if not validate_build(bdir):
            print("FAIL: failed to catch OVL.STO exceeding xe_slot_pages[17]", file=sys.stderr)
            return 1
        write_synthetic_prg(bdir / "OVL.STO", 0xE000, base_pages[17] * 256 - 2)

        # Negative test 14: ITEM.CAT exceeding cap or corrupt header must fail
        (bdir / ITEM_CATALOG_FILE).write_bytes(b"ITM2" + struct.pack("<H", 7801) + bytes(7801 - 6))
        if not validate_build(bdir):
            print("FAIL: failed to catch ITEM.CAT exceeding 7800 B cap", file=sys.stderr)
            return 1
        (bdir / ITEM_CATALOG_FILE).write_bytes(b"BAD!" + struct.pack("<H", 7573) + bytes(7573 - 6))
        if not validate_build(bdir):
            print("FAIL: failed to catch ITEM.CAT bad header", file=sys.stderr)
            return 1

    print("Atari 8-bit memory contract self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run synthetic pass/fail self-tests.")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    errors = validate_build(args.build_dir)
    if errors:
        print("Atari 8-bit memory contract check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    print("Atari 8-bit memory contract check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
