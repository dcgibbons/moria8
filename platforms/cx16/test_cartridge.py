#!/usr/bin/env python3
"""Headless verification suite for Commander X16 Cartridge (CX16_CARTRIDGE)."""

from __future__ import annotations

import argparse
import array
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import wave

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools"))

import harness_smoke  # noqa: E402
import make_cx16_cart  # noqa: E402

CART_IMAGE = ROOT / "build" / "moria8-cx16.crt"
CART_BUILD_DIR = ROOT / "build" / "cx16-cart"
CART_BIN = CART_BUILD_DIR / "moria8-cx16.bin"
CART_MANIFEST = CART_BUILD_DIR / "moria8-cx16.json"
DISK_BUILD_DIR = ROOT / "build" / "cx16"
DATA_DIR = ROOT / "data"
TEST_WORK_ROOT = ROOT / "build" / "test" / "cx16-cartridge"

PROGRAM_ARTIFACTS = {
    "MORIA8.PRG",
    "CX16.AUXDATA",
    "CX16.HUFFDATA",
    "MONSTER.CAT",
    "MONSTER.EXT",
    "ITEM.CAT",
    "TITLE",
    "LEGALUI",
    "LICENSE",
    "SOURCE-OFFER",
    "OVL.START",
    "OVL.TOWN",
    "OVL.ITEMS",
    "OVL.SPELL",
    "OVL.CHEST",
    "OVL.UI",
    "OVL.GEN",
    "OVL.HELP",
    "OVL.DEATH",
    "OVL.MODAL",
    "OVL.HOME",
    "OVL.STORAGE",
    "OVL.TITLE",
}


def fletcher16(data: bytes) -> tuple[int, int]:
    s1 = 0
    s2 = 0
    for b in data:
        s1 = (s1 + b) % 255
        s2 = (s2 + s1) % 255
    return s1, s2


def assert_fsroot_program_free(fsroot: Path) -> None:
    present = {p.name.upper() for p in fsroot.iterdir()}
    leaked = sorted(present & PROGRAM_ARTIFACTS)
    if leaked:
        raise AssertionError(f"temporary -fsroot must not contain program files, found: {leaked}")


def decode_gif_frames(raw: bytes) -> tuple[int, int, list[list[int]]]:
    """Minimal pure-Python GIF89a frame decoder returning (w, h, list_of_index_frames)."""
    if raw[:6] not in (b"GIF87a", b"GIF89a"):
        raise ValueError("not a GIF stream")
    w, h, packed, bg, _ = struct.unpack_from("<HHBBB", raw, 6)
    pos = 13
    if packed & 0x80:
        gct_entries = 1 << ((packed & 0x07) + 1)
        pos += 3 * gct_entries

    canvas = [bg] * (w * h)
    frames: list[list[int]] = []
    trans_idx: int | None = None

    def read_subblocks(p: int) -> tuple[bytes, int]:
        out = bytearray()
        while p < len(raw):
            sz = raw[p]
            p += 1
            if sz == 0:
                break
            out.extend(raw[p : p + sz])
            p += sz
        return bytes(out), p

    while pos < len(raw):
        intro = raw[pos]
        pos += 1
        if intro == 0x3B:
            break
        if intro == 0x21:
            if pos >= len(raw):
                break
            lbl = raw[pos]
            pos += 1
            ext_data, pos = read_subblocks(pos)
            if lbl == 0xF9 and len(ext_data) >= 4:
                trans_idx = ext_data[3] if (ext_data[0] & 0x01) else None
            continue
        if intro != 0x2C:
            break

        if pos + 9 > len(raw):
            break
        left, top, iw, ih, ipacked = struct.unpack_from("<HHHHB", raw, pos)
        pos += 9
        if ipacked & 0x80:
            lct_entries = 1 << ((ipacked & 0x07) + 1)
            pos += 3 * lct_entries
        if pos >= len(raw):
            break
        min_code_size = raw[pos]
        pos += 1
        compressed, pos = read_subblocks(pos)

        # LZW decode
        clear_code = 1 << min_code_size
        eoi_code = clear_code + 1
        next_code = eoi_code + 1
        code_size = min_code_size + 1
        dictionary: list[bytes] = [bytes([i]) for i in range(clear_code)] + [b"", b""]

        bit_buf = 0
        bit_cnt = 0
        byte_idx = 0
        prev_seq = b""
        pixels: list[int] = []

        while True:
            while bit_cnt < code_size:
                if byte_idx >= len(compressed):
                    break
                bit_buf |= compressed[byte_idx] << bit_cnt
                bit_cnt += 8
                byte_idx += 1
            if bit_cnt < code_size:
                break
            code = bit_buf & ((1 << code_size) - 1)
            bit_buf >>= code_size
            bit_cnt -= code_size

            if code == clear_code:
                dictionary = [bytes([i]) for i in range(clear_code)] + [b"", b""]
                code_size = min_code_size + 1
                next_code = eoi_code + 1
                prev_seq = b""
                continue
            if code == eoi_code:
                break

            if code < len(dictionary):
                seq = dictionary[code]
            elif code == next_code and prev_seq:
                seq = prev_seq + prev_seq[:1]
            else:
                break

            pixels.extend(seq)
            if prev_seq and next_code < 4096:
                dictionary.append(prev_seq + seq[:1])
                next_code += 1
                if next_code == (1 << code_size) and code_size < 12:
                    code_size += 1
            prev_seq = seq

        for dy in range(ih):
            y = top + dy
            if y >= h:
                break
            row_off = y * w
            src_off = dy * iw
            for dx in range(iw):
                x = left + dx
                if x >= w or src_off + dx >= len(pixels):
                    break
                px = pixels[src_off + dx]
                if trans_idx is None or px != trans_idx:
                    canvas[row_off + x] = px
        frames.append(canvas.copy())
        trans_idx = None

    return w, h, frames


def make_testbench_stub_prg() -> bytes:
    # PRG header $0801 + single RTS ($60)
    return bytes((0x01, 0x08, 0x60))


def make_testbench_crt_copy(src_crt: Path, dst_crt: Path) -> None:
    data = bytearray(src_crt.read_bytes())
    # Clear Bank 32 $C000 byte 0 so x16-rom enters BASIC -> -prg -> SYS65533 -> RDY;
    # CartBench then calls RUN C004 directly to exercise cartridge_boot.s.
    data[480] = 0x00
    dst_crt.write_bytes(data)


def make_testbench_bin_copy(src_bin: Path, dst_bin: Path) -> None:
    data = bytearray(src_bin.read_bytes())
    data[0] = 0x00
    dst_bin.write_bytes(data)


class CartBench(harness_smoke.X16Bench):
    """X16Bench driving moria8-cx16.crt or moria8-cx16.bin with an empty -fsroot."""

    def __init__(
        self,
        x16emu: Path,
        rom: Path | None,
        workdir: Path,
        syms: dict[str, int],
        mode: str,
        cart_path: Path,
        boot_syms: dict[str, int],
    ) -> None:
        super().__init__(x16emu, rom, workdir, syms)
        self.mode = mode
        self.cart_path = cart_path
        self.boot_syms = boot_syms

    def assert_line(self, name: str, ok: bool, detail: str = "") -> None:
        super().assert_line(name, ok, detail)
        line = self.output_lines[-1]
        print(line)
        if not ok:
            raise AssertionError(line)

    def read_status(self) -> int:
        self._send("RST")
        while True:
            line = self._readline()
            if line in ("RDY", "Testbench mode..."):
                continue
            return int(line, 16)

    def start(self, boot_to_title: bool = True) -> None:
        assert_fsroot_program_free(self.workdir)
        tb_dir = self.workdir.parent / f"{self.workdir.name}_tb_media"
        tb_dir.mkdir(parents=True, exist_ok=True)
        stub_prg = tb_dir / "tb_stub.prg"
        stub_prg.write_bytes(make_testbench_stub_prg())

        if self.mode == "crt":
            tb_media = tb_dir / "tb_cart.crt"
            make_testbench_crt_copy(self.cart_path, tb_media)
            cart_args = ["-cart", str(tb_media)]
        elif self.mode == "bin":
            tb_media = tb_dir / "tb_cart.bin"
            make_testbench_bin_copy(self.cart_path, tb_media)
            cart_args = ["-cartbin", str(tb_media)]
        else:
            raise ValueError(f"unknown mode {self.mode}")

        rom_path = harness_smoke.resolve_rom_path(self.x16emu, self.rom)
        cmd = [
            str(self.x16emu),
            "-testbench",
            "-warp",
            "-zeroram",
            "-rom",
            str(rom_path),
        ] + cart_args + ["-fsroot", str(self.workdir), "-prg", str(stub_prg)]

        env = os.environ.copy()
        env["SDL_VIDEODRIVER"] = "dummy"
        env["SDL_AUDIODRIVER"] = "dummy"
        self.proc = subprocess.Popen(
            cmd,
            cwd=str(self.workdir),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )
        self._wait_rdy()

        if self.mode == "bin":
            # Restore 'C' at Bank 32 $C000 in -cartbin writable ROM banks
            self.write_u8(0x0001, 32)
            self.write_u8(0xC000, 0x43)

        # Simulate keys buffered during x16-rom's 60-jiffy Shift window and its sei
        # handoff into boot_cold_start ($C004) with I=1.
        self.write_bank_u8(0, 0xA80A, 2)
        for i, b in enumerate(b"M8TB"):
            self.write_u8(0x07FC + i, b)
        cold_addr = self.boot_syms["boot_cold_start"]
        for i, b in enumerate((0x78, 0x4C, cold_addr & 0xFF, cold_addr >> 8)):
            self.write_u8(0x0700 + i, b)
        self.write_u8(0x0001, 32)
        self.run_addr(0x0700)

        p_status = self.read_status()
        kbdbuf_cnt = self.read_bank_u8(0, 0xA80A)
        rom_bank = self.read_u8(0x0001)
        self.assert_line(
            "cart_boot_handoff_irq_enabled",
            (p_status & 0x04) == 0,
            f"P={p_status:#04x} (I={1 if (p_status & 0x04) else 0}) after boot_cold_start",
        )
        self.assert_line(
            "cart_boot_flushes_kbdbuf",
            kbdbuf_cnt == 0,
            f"NDX ($A80A)={kbdbuf_cnt} after boot_cold_start, expected 0",
        )
        self.assert_line(
            "cart_boot_handoff_rom_bank0",
            rom_bank == 0,
            f"ROM bank ($01)={rom_bank} after boot_cold_start, expected 0",
        )

        if boot_to_title:
            self.verify_prg_copy_fletcher16()
            self.run_addr(self.syms["cx16_preload_banks"])
            check_preloaded_banks_fidelity(self)
            self.write_u8(self.syms["cx16_testbench_enabled"], 1)
            self.run_addr(self.syms["entry_bootstrap"])


def compute_ram_fletcher16(tb: harness_smoke.X16Bench, bank: int, start: int, length: int) -> tuple[int, int]:
    """Run a tiny 65C02 Fletcher-16 checksum routine at $0700 (params at $0760..$0766)."""
    # Params:
    #   $0760: bank
    #   $0761/$0762: remaining lo/hi
    #   $0763: sum1
    #   $0764: sum2
    # Stub ($0700..$074F):
    #   0700: A5 00       lda $00
    #   0702: 48          pha
    #   0703: AD 60 07    lda $0760
    #   0706: 85 00       sta $00
    #   0708: 9C 63 07    stz $0763
    #   070B: 9C 64 07    stz $0764
    # loop ($070E):
    #   070E: AD 61 07    lda $0761
    #   0711: 0D 62 07    ora $0762
    #   0714: F0 3B       beq done ($0751)
    #   0716: AD 63 07    lda $0763
    #   0719: 18          clc
    #   071A: 6D xx xx    adc $xxxx    ; $071B/$071C
    #   071D: 90 02       bcc +2
    #   071F: 69 00       adc #0
    #   0721: C9 FF       cmp #$ff
    #   0723: D0 02       bne +2
    #   0725: A9 00       lda #0
    #   0727: 8D 63 07    sta $0763
    #   072A: 18          clc
    #   072B: 6D 64 07    adc $0764
    #   072E: 90 02       bcc +2
    #   0730: 69 00       adc #0
    #   0732: C9 FF       cmp #$ff
    #   0734: D0 02       bne +2
    #   0736: A9 00       lda #0
    #   0738: 8D 64 07    sta $0764
    #   073B: EE 1B 07    inc $071B
    #   073E: D0 03       bne +3
    #   0740: EE 1C 07    inc $071C
    #   0743: AD 61 07    lda $0761
    #   0746: D0 03       bne +3
    #   0748: CE 62 07    dec $0762
    #   074B: CE 61 07    dec $0761
    #   074E: 4C 0E 07    jmp $070E
    # done ($0751):
    #   0751: 68          pla
    #   0752: 85 00       sta $00
    #   0754: 60          rts
    code = [
        0xA5, 0x00, 0x48,
        0xAD, 0x60, 0x07, 0x85, 0x00,
        0x9C, 0x63, 0x07, 0x9C, 0x64, 0x07,
        0xAD, 0x61, 0x07, 0x0D, 0x62, 0x07, 0xF0, 0x3B,
        0xAD, 0x63, 0x07, 0x18, 0x6D, start & 0xFF, (start >> 8) & 0xFF,
        0x90, 0x02, 0x69, 0x00, 0xC9, 0xFF, 0xD0, 0x02, 0xA9, 0x00, 0x8D, 0x63, 0x07,
        0x18, 0x6D, 0x64, 0x07,
        0x90, 0x02, 0x69, 0x00, 0xC9, 0xFF, 0xD0, 0x02, 0xA9, 0x00, 0x8D, 0x64, 0x07,
        0xEE, 0x1B, 0x07, 0xD0, 0x03, 0xEE, 0x1C, 0x07,
        0xAD, 0x61, 0x07, 0xD0, 0x03, 0xCE, 0x62, 0x07, 0xCE, 0x61, 0x07,
        0x4C, 0x0E, 0x07,
        0x68, 0x85, 0x00, 0x60,
    ]
    for i, b in enumerate(code):
        tb.write_u8(0x0700 + i, b)
    tb.write_u8(0x0760, bank)
    tb.write_u8(0x0761, length & 0xFF)
    tb.write_u8(0x0762, (length >> 8) & 0xFF)
    tb.run_addr(0x0700)
    return tb.read_u8(0x0763), tb.read_u8(0x0764)


def _attach_fletcher(self: CartBench) -> None:
    raw = (CART_BUILD_DIR / "MORIA8.PRG").read_bytes()[2:]
    exp = fletcher16(raw)
    got = compute_ram_fletcher16(self, 0, 0x0801, len(raw))
    self.assert_line(
        "boot_prg_copy_fletcher16",
        got == exp,
        f"copied MORIA8.PRG fletcher16 {got} != expected {exp}",
    )


CartBench.verify_prg_copy_fletcher16 = _attach_fletcher  # type: ignore[attr-defined]


def check_preloaded_banks_fidelity(tb: harness_smoke.X16Bench) -> None:
    manifest = json.loads(CART_MANIFEST.read_text(encoding="utf-8"))
    for asset in manifest["assets"]:
        ram_bank = asset["ram_bank"]
        if ram_bank is None or asset["name"] in ("MORIA8.PRG", "LEGALUI"):
            # MORIA8.PRG checked at boot; LEGALUI is loaded on demand into CX16_BANK_LEGAL
            continue
        payload = (CART_BUILD_DIR / asset["name"]).read_bytes()[2:]
        dest = int(asset["dest_addr"].lstrip("$"), 16)
        exp = fletcher16(payload)
        got = compute_ram_fletcher16(tb, ram_bank, dest, len(payload))
        tb.assert_line(
            f"preload_bank_{ram_bank}_{asset['name']}",
            got == exp,
            f"bank {ram_bank} ({asset['name']}) fletcher16 {got} != expected {exp}",
        )


def check_cart_read_edge_cases(tb: harness_smoke.X16Bench) -> None:
    syms = tb.syms
    cart_read_addr = syms["cart_read"]
    # Stub at $0700: jsr cart_read; php; sta $0778; pla; sta $0779; rts
    stub = [
        0x20, cart_read_addr & 0xFF, cart_read_addr >> 8,
        0x08, 0x8D, 0x78, 0x07, 0x68, 0x8D, 0x79, 0x07, 0x60,
    ]
    for i, b in enumerate(stub):
        tb.write_u8(0x0700 + i, b)

    def call_cart_read(aid: int, offset: int, dest: int, count: int, is_rec: int) -> tuple[int, int]:
        tb.write_u8(syms["cart_asset_id"], aid)
        tb.write_u8(syms["cart_offset_lo"], offset & 0xFF)
        tb.write_u8(syms["cart_offset_hi"], (offset >> 8) & 0xFF)
        tb.write_u8(syms["cart_dest_lo"], dest & 0xFF)
        tb.write_u8(syms["cart_dest_hi"], (dest >> 8) & 0xFF)
        tb.write_u8(syms["cart_count_lo"], count & 0xFF)
        tb.write_u8(syms["cart_count_hi"], (count >> 8) & 0xFF)
        tb.write_u8(syms["cart_is_record"], is_rec)
        tb.run_addr(0x0700)
        return tb.read_u8(0x0778), tb.read_u8(0x0779) & 0x01

    manifest = json.loads(CART_MANIFEST.read_text(encoding="utf-8"))
    license_aid = next(a["id"] for a in manifest["assets"] if a["name"] == "LICENSE")
    license_bytes = (DATA_DIR / "LICENSE").read_bytes()
    sentinel = 0xA5
    for i in range(16):
        tb.write_u8(0x0780 + i, sentinel)

    # 1. Zero-length read writes nothing and returns A=0, C=0
    a, c = call_cart_read(license_aid, 0, 0x0780, 0, 0)
    tb.assert_line("cart_read_zero_len", a == 0 and c == 0, f"A={a} C={c}")
    tb.assert_line("cart_read_zero_nowrite", tb.read_u8(0x0780) == sentinel, "zero-length read wrote buffer")

    # 2. Out-of-bounds raw read returns A=0, C=1 and writes nothing
    a, c = call_cart_read(license_aid, len(license_bytes), 0x0780, 8, 0)
    tb.assert_line("cart_read_oob_raw", a == 0 and c == 1, f"A={a} C={c}")
    tb.assert_line("cart_read_oob_nowrite", tb.read_u8(0x0780) == sentinel, "oob read wrote buffer")

    # 3. Legal chunk (is_record=2) clamps near EOF and preserves trailing sentinel
    tail = 9
    a, c = call_cart_read(license_aid, len(license_bytes) - tail, 0x0780, 128, 2)
    tb.assert_line("cart_read_legal_clamp", a == tail and c == 0, f"A={a} C={c}")
    got_tail = bytes(tb.read_u8(0x0780 + i) for i in range(tail))
    tb.assert_line("cart_read_legal_tail_bytes", got_tail == license_bytes[-tail:], f"got={got_tail!r}")
    tb.assert_line("cart_read_legal_sentinel", tb.read_u8(0x0780 + tail) == sentinel, "clamped read overwrote sentinel")

    # 4. Legal chunk at exact EOF returns A=0, C=1
    a, c = call_cart_read(license_aid, len(license_bytes), 0x0780, 128, 2)
    tb.assert_line("cart_read_legal_eof", a == 0 and c == 1, f"A={a} C={c}")


def _read_legal_doc_to_eof(tb: harness_smoke.X16Bench, doc_label: str) -> None:
    for _ in range(6):
        if tb.screen_has("End. R: restart  Q: back") or tb.screen_has("Document read failed"):
            break
        tb.press(" ")
    tb.assert_line(
        f"legal_{doc_label}_no_read_err",
        not tb.screen_has("Document read failed"),
        f"{doc_label} reported Document read failed",
    )
    tb.assert_line(
        f"legal_{doc_label}_eof_footer",
        tb.screen_has("End. R: restart  Q: back"),
        f"{doc_label} did not reach EOF footer",
    )
    if "legal_eof" in tb.syms:
        eof_val = tb.read_bank_u8(harness_smoke.CX16_BANK_LEGAL, tb.syms["legal_eof"])
        tb.assert_line(
            f"legal_{doc_label}_eof_flag",
            eof_val == 0x40,
            f"{doc_label} legal_eof={eof_val:#04x}, expected 0x40",
        )


def check_legal_viewer(tb: harness_smoke.X16Bench, from_gameplay: bool) -> None:
    if from_gameplay:
        tb.shift("/")
        tb.assert_line("help_open", tb.screen_has("Command Reference"), "'?' did not open Help")
        tb.press(" ")
        tb.assert_line("help_legal_entry", tb.screen_has("L License / Source"), "Help missing L entry")
        tb.press("L")
    else:
        tb.press("A")
    tb.assert_line("legal_menu", tb.screen_has("License & Source"), "did not open legal viewer")
    tb.press("1")
    tb.assert_line(
        "legal_license_text",
        tb.screen_has("MORIA8 LICENSE NOTICE") or tb.screen_has("COPYRIGHT"),
        "LICENSE text missing from screen",
    )
    _read_legal_doc_to_eof(tb, "license")
    tb.press("Q")
    tb.assert_line("legal_back_to_menu", tb.screen_has("License & Source"), "Q from LICENSE did not return to legal menu")
    tb.press("2")
    tb.assert_line(
        "legal_source_offer_text",
        tb.screen_has("MORIA8 SOURCE OFFER") or tb.screen_has("GNU GPL"),
        "SOURCE-OFFER text missing from screen",
    )
    _read_legal_doc_to_eof(tb, "source_offer")
    tb.press("Q")
    tb.assert_line("legal_back_from_offer", tb.screen_has("License & Source"), "Q from SOURCE-OFFER did not return to legal menu")
    tb.press("3")
    tb.assert_line(
        "legal_sysinfo_menu",
        tb.screen_has("Moria 8 - System Info")
        and tb.screen_has("Commander X16 (80-col VERA)")
        and tb.screen_has("ROM Cartridge")
        and (not from_gameplay or tb.screen_has("Turn ")),
        "key 3 did not show expected cartridge System Info",
    )
    tb.press("Q")
    tb.assert_line("legal_sysinfo_back", tb.screen_has("1 License"), "Q from System Info did not return to legal menu")
    tb.press("Q")
    if from_gameplay:
        tb.assert_line("legal_help_return", tb.screen_has("Command Reference"), "Help screen was not restored")
        tb.press("Q")
        tb.assert_line("legal_return_town", tb.in_town(), "did not return to town after gameplay legal viewer")
        tb.shift("V")
        tb.assert_line(
            "gameplay_sysinfo",
            tb.screen_has("Moria 8 - System Info")
            and tb.screen_has("ROM Cartridge")
            and tb.screen_has("RNG:"),
            "SHIFT+V did not open gameplay System Info on cartridge",
        )
        tb.press("Q")
        tb.assert_line("gameplay_sysinfo_close", tb.in_town(), "Q from gameplay System Info did not return to town")
    else:
        tb.assert_line("legal_return_title", tb.on_title(), "did not return to title after title legal viewer")


def save_character_from_town(tb: harness_smoke.X16Bench) -> None:
    tb.drain_more()
    tb.shift("S")
    tb.assert_line("save_slot_prompt", tb.screen_has("Select Slot 1-4"), "save slot prompt did not appear")
    tb.press("1")
    tb.assert_line("save_completed_to_title", harness_smoke._finish_save_to_title(tb), "save did not return to title")


def load_character_from_title(tb: harness_smoke.X16Bench) -> None:
    tb.assert_line("title_before_load", tb.on_title(), "expected title screen before L load")
    tb.press("L")
    tb.assert_line("load_slots", tb.screen_has("Save Slots:"), "load did not show slot list")
    tb.press("1")
    for _ in range(4):
        if tb.in_town():
            break
        if tb.screen_has("-more-") or tb.screen_has("Welcome"):
            tb.press(" ")
    tb.assert_line("loaded_in_town", tb.in_town(), "loaded character did not enter town")


def check_load_missing_save(tb: harness_smoke.X16Bench) -> None:
    tb.assert_line("title_before_missing_load", tb.on_title(), "expected title before missing-save L check")
    tb.press("L")
    tb.assert_line("missing_load_slots", tb.screen_has("Save Slots:"), "L did not show Save Slots on empty fsroot")
    tb.press("1")
    tb.assert_line(
        "missing_load_not_in_town",
        not tb.in_town(),
        "empty slot load unexpectedly entered town",
    )
    for _ in range(4):
        if tb.on_title():
            break
        tb.press(" ")
    tb.assert_line(
        "missing_load_returned_to_title",
        tb.on_title(),
        "failed empty-slot load did not recover cleanly to title screen",
    )


def run_cold_boot_gif_check(x16emu: Path, rom: Path | None, mode: str, media_path: Path, fsroot: Path) -> None:
    if fsroot.exists():
        shutil.rmtree(fsroot)
    fsroot.mkdir(parents=True, exist_ok=True)
    assert_fsroot_program_free(fsroot)

    gif_path = fsroot.parent / f"cold_{mode}.gif"
    if gif_path.exists():
        gif_path.unlink()

    rom_path = harness_smoke.resolve_rom_path(x16emu, rom)
    cmd = [
        str(x16emu),
        "-warp",
        "-gif",
        str(gif_path),
        "-fsroot",
        str(fsroot),
        "-rom",
        str(rom_path),
        "-cart" if mode == "crt" else "-cartbin",
        str(media_path),
    ]

    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "dummy"
    env["SDL_AUDIODRIVER"] = "dummy"

    proc = subprocess.Popen(
        cmd,
        cwd=str(fsroot),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
    )
    try:
        deadline = time.time() + 4.0
        while time.time() < deadline:
            if gif_path.is_file() and gif_path.stat().st_size > 16384:
                time.sleep(0.8)
                break
            if proc.poll() is not None:
                break
            time.sleep(0.1)
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=3)

    assert_fsroot_program_free(fsroot)
    if not gif_path.is_file() or gif_path.stat().st_size == 0:
        raise AssertionError(f"cold boot ({mode}) produced no GIF output at {gif_path}")

    w, h, frames = decode_gif_frames(gif_path.read_bytes())
    if len(frames) < 1 or w != 640 or h != 480:
        raise AssertionError(f"cold boot ({mode}) unexpected GIF geometry {w}x{h}, frames={len(frames)}")

    last = frames[-1]
    banner_lit = sum(1 for y in range(20, 140) for x in range(80, 560) if last[y * w + x] != 0)
    menu_lit = sum(1 for y in range(280, 400) for x in range(160, 480) if last[y * w + x] != 0)
    if banner_lit < 200 or menu_lit < 100:
        raise AssertionError(
            f"cold boot ({mode}) title screen missing expected pixels (banner={banner_lit}, menu={menu_lit})"
        )
    print(f"ASSERT cold_boot_{mode}_gif PASS (frames={len(frames)}, banner_px={banner_lit}, menu_px={menu_lit})")


def check_irq_and_keyhdl_state(tb: CartBench, label: str) -> None:
    p_status = tb.read_status()
    tb.assert_line(
        f"{label}_irq_enabled",
        (p_status & 0x04) == 0,
        f"{label}: P={p_status:#04x} (I={1 if (p_status & 0x04) else 0})",
    )
    rom_bank = tb.read_u8(0x0001)
    tb.assert_line(
        f"{label}_rom_bank0",
        rom_bank == 0,
        f"{label}: ROM bank ($01)={rom_bank}, expected 0",
    )
    keyhdl = tb.read_u8(0x032E) | (tb.read_u8(0x032F) << 8)
    expected_keyhdl = tb.syms["cx16_key_event"]
    keyhdl_next = tb.read_u8(tb.syms["cx16_keyhdl_next"]) | (tb.read_u8(tb.syms["cx16_keyhdl_next"] + 1) << 8)
    tb.assert_line(
        f"{label}_keyhdl_installed",
        keyhdl == expected_keyhdl and keyhdl_next != 0,
        f"{label}: KEYHDL=${keyhdl:04x} (expected ${expected_keyhdl:04x}), next=${keyhdl_next:04x}",
    )


def _decode_vram_text_rows(vram: bytes) -> list[str]:
    rows: list[str] = []
    for y in range(60):
        row_base = 0x1B000 + y * 256
        chars = [harness_smoke.vera_code_to_ascii(vram[row_base + x * 2]) for x in range(80)]
        rows.append("".join(chars).rstrip())
    return rows


def run_cold_boot_live_sound_irq_check(
    x16emu: Path,
    rom: Path | None,
    cart_syms: dict[str, int],
    fsroot: Path,
) -> None:
    """Boot an unmodified bootrom.bin under live 60 Hz IRQs/audio (no -testbench/-warp)."""
    if fsroot.exists():
        shutil.rmtree(fsroot)
    fsroot.mkdir(parents=True, exist_ok=True)
    assert_fsroot_program_free(fsroot)

    work_dir = fsroot.parent / "cold_live_work"
    if work_dir.exists():
        shutil.rmtree(work_dir)
    build_copy = work_dir / "build"
    build_copy.mkdir(parents=True, exist_ok=True)
    for src in CART_BUILD_DIR.iterdir():
        if src.is_file():
            shutil.copy2(src, build_copy / src.name)

    live_prg = CART_BUILD_DIR / "cartridge_test_live.prg"
    live_syms = harness_smoke._load_symbols(CART_BUILD_DIR / "cartridge_test_live.sym")
    live_raw = live_prg.read_bytes()
    if len(live_raw) < 3:
        raise AssertionError(f"invalid live test helper PRG: {live_prg}")
    helper_addr = struct.unpack_from("<H", live_raw, 0)[0]
    helper_body = live_raw[2:]

    prg_path = build_copy / "MORIA8.PRG"
    prg_raw = bytearray(prg_path.read_bytes())
    load_addr = struct.unpack_from("<H", prg_raw, 0)[0]
    if load_addr != 0x0801:
        raise AssertionError(f"unexpected MORIA8.PRG load header ${load_addr:04x}")
    prg_body = bytearray(prg_raw[2:])
    orig_end = load_addr + len(prg_body)
    if orig_end > helper_addr:
        raise AssertionError(f"MORIA8.PRG end ${orig_end:04x} overlaps helper ${helper_addr:04x}")

    poll_jsr_off = (cart_syms["input_get_key_poll"] + 2) - load_addr
    expected_snd = cart_syms["hal_sound_update"]
    if prg_body[poll_jsr_off] != 0x20 or struct.unpack_from("<H", prg_body, poll_jsr_off + 1)[0] != expected_snd:
        raise AssertionError(
            f"unexpected opcode at input_get_key_poll+2: {prg_body[poll_jsr_off:poll_jsr_off + 3].hex()}"
        )
    struct.pack_into("<H", prg_body, poll_jsr_off + 1, live_syms["live_test_entry"])

    prg_body.extend(b"\x00" * (helper_addr - orig_end))
    prg_body.extend(helper_body)
    prg_path.write_bytes(struct.pack("<H", load_addr) + bytes(prg_body))

    crt_bytes, _, _ = make_cx16_cart.build_cartridge_images(
        build_dir=build_copy,
        data_dir=DATA_DIR,
        version_str="0.0.0-test",
        description="Moria8 CX16 Live IRQ Probe",
        author="Moria8 Test",
        copyright_str="GPL-3.0-or-later",
    )
    temp_crt = work_dir / "live_probe.crt"
    temp_crt.write_bytes(crt_bytes)

    wav_path = work_dir / "cold_live.wav"
    dump_path = work_dir / "dump.bin"
    rom_path = harness_smoke.resolve_rom_path(x16emu, rom)
    cmd = [
        str(x16emu),
        "-dump",
        "CRV",
        "-wav",
        str(wav_path),
        "-fsroot",
        str(fsroot),
        "-rom",
        str(rom_path),
        "-cart",
        str(temp_crt),
    ]

    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "dummy"
    env["SDL_AUDIODRIVER"] = "dummy"

    proc = subprocess.Popen(
        cmd,
        cwd=str(work_dir),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    try:
        out, _ = proc.communicate(timeout=8.0)
    except subprocess.TimeoutExpired as exc:
        proc.kill()
        out_partial, _ = proc.communicate(timeout=3)
        raise AssertionError(
            f"cold_boot_live_sound_irq timed out after 8s (IRQ likely masked I=1). output={out_partial!r}"
        ) from exc

    if proc.returncode != 0:
        raise AssertionError(f"cold_boot_live_sound_irq exited rc={proc.returncode}: {out}")
    if not dump_path.is_file():
        raise AssertionError(f"cold_boot_live_sound_irq missing dump at {dump_path}: {out}")

    dump = dump_path.read_bytes()
    expected_dump_len = 7 + 0xA000 + 0x20000
    if len(dump) < expected_dump_len:
        raise AssertionError(f"unexpected dump.bin size {len(dump)} < {expected_dump_len}")
    ram = dump[7 : 7 + 0xA000]
    vram = dump[7 + 0xA000 : 7 + 0xA000 + 0x20000]

    stage = ram[live_syms["live_stage"]]
    init_seen = ram[live_syms["live_init_seen"]]
    saved_p = ram[live_syms["live_saved_p"]]
    keydown_sample = ram[live_syms["live_keydown_sample"]]
    keyup_sample = ram[live_syms["live_keyup_sample"]]
    saw_snd_timer = ram[live_syms["live_saw_snd_timer"]]
    end_snd_timer = ram[cart_syms["zp_snd_timer"]]
    psg_v0_vol = vram[0x1F9C2]
    screen_text = "\n".join(_decode_vram_text_rows(vram))

    if stage != 2:
        raise AssertionError(f"live probe stage={stage}, expected 2")
    if init_seen != 1 or (saved_p & 0x04) != 0:
        raise AssertionError(f"live probe saved_p={saved_p:#04x} (seen={init_seen}), expected I=0")
    if keydown_sample != 0x02 or keyup_sample != 0x00:
        raise AssertionError(f"KEYHDL matrix samples down={keydown_sample:#04x} up={keyup_sample:#04x}")
    if saw_snd_timer == 0 or end_snd_timer != 0:
        raise AssertionError(f"sound timer transition invalid: saw={saw_snd_timer}, end={end_snd_timer}")
    if psg_v0_vol != 0:
        raise AssertionError(f"VERA PSG voice 0 volume={psg_v0_vol:#04x}, expected 0")
    if "Roll Statistics" not in screen_text:
        raise AssertionError("VERA VRAM missing 'Roll Statistics' after live key input")

    if not wav_path.is_file() or wav_path.stat().st_size <= 44:
        raise AssertionError(f"missing or empty WAV recording at {wav_path}")
    with wave.open(str(wav_path), "rb") as wf:
        if wf.getsampwidth() != 2 or wf.getnframes() == 0:
            raise AssertionError(f"unexpected WAV format width={wf.getsampwidth()} frames={wf.getnframes()}")
        samples = array.array("h")
        samples.frombytes(wf.readframes(wf.getnframes()))
        peak = max((abs(s) for s in samples), default=0)
    if peak == 0:
        raise AssertionError("recorded WAV has zero PCM amplitude (PSG audio did not play)")

    assert_fsroot_program_free(fsroot)
    print(
        "ASSERT cold_boot_live_sound_irq PASS "
        f"(P={saved_p:#04x}, snd_timer={saw_snd_timer}->0, wav_peak={peak})"
    )


def run_cartridge_suite(x16emu: Path, rom: Path | None) -> int:
    if TEST_WORK_ROOT.exists():
        shutil.rmtree(TEST_WORK_ROOT)
    TEST_WORK_ROOT.mkdir(parents=True, exist_ok=True)

    cart_syms = harness_smoke._load_symbols(CART_BUILD_DIR / "main.sym")
    boot_syms = harness_smoke._load_symbols(CART_BUILD_DIR / "cartridge_boot.sym")
    disk_syms = harness_smoke._load_symbols(DISK_BUILD_DIR / "main.sym")

    # 1. Unmodified -cart and -cartbin autonomous cold-boot checks with empty -fsroot
    run_cold_boot_gif_check(x16emu, rom, "crt", CART_IMAGE, TEST_WORK_ROOT / "cold_crt")
    run_cold_boot_gif_check(x16emu, rom, "bin", CART_BIN, TEST_WORK_ROOT / "cold_bin")
    run_cold_boot_live_sound_irq_check(x16emu, rom, cart_syms, TEST_WORK_ROOT / "cold_live_fsroot")

    # 2. Full interactive -cart testbench suite with empty -fsroot
    save_fsroot = TEST_WORK_ROOT / "crt_save_fsroot"
    save_fsroot.mkdir(parents=True, exist_ok=True)
    tb = CartBench(x16emu, rom, save_fsroot, cart_syms, "crt", CART_IMAGE, boot_syms)
    try:
        tb.start(boot_to_title=True)
        tb.assert_line("cart_title_menu", tb.on_title(), "title screen missing after cartridge boot")
        check_irq_and_keyhdl_state(tb, "title")
        check_cart_read_edge_cases(tb)
        check_load_missing_save(tb)
        check_legal_viewer(tb, from_gameplay=False)
        tb.chargen("A")
        check_irq_and_keyhdl_state(tb, "town")
        check_legal_viewer(tb, from_gameplay=True)
        save_character_from_town(tb)
        assert_fsroot_program_free(save_fsroot)
        sav_files = [p.name for p in save_fsroot.iterdir() if p.name.upper().startswith("THE.GAME")]
        tb.assert_line("cart_saved_file", len(sav_files) >= 1, f"no THE.GAME created in {save_fsroot}")
        sav_hdr = (save_fsroot / sav_files[0]).read_bytes()[:8]
        tb.assert_line("cart_save_v2", sav_hdr == b"MORIA01\x22", f"save header={sav_hdr!r}")
    finally:
        tb.close()

    # 3. Negative Save V2 checks then reload cartridge save in a fresh -cart session + descend to DL16/DL50
    tb_reload = CartBench(x16emu, rom, save_fsroot, cart_syms, "crt", CART_IMAGE, boot_syms)
    try:
        tb_reload.start(boot_to_title=True)
        harness_smoke.verify_negative_save_cases(
            tb_reload,
            save_fsroot / sav_files[0],
            prefix="cart_neg",
            reload_valid=False,
        )
        load_character_from_title(tb_reload)
        name_bytes = bytes(tb_reload.read_u8(cart_syms["player_data"] + i) for i in range(4))
        tb_reload.assert_line("cart_reload_name", name_bytes == b"\x14\x05\x13\x14", f"reloaded name={name_bytes!r}")
        tb_reload.assert_line("cart_descend_dl1", harness_smoke._descend_to_dl1(tb_reload), "did not reach DL1")
        # Run DL16/DL50 monster catalog verification using CX16_BANK_CATALOG + Bank 4
        tb_reload.wizard_menu_open()
        tb_reload.press_until("DLVL", "L")
        tb_reload.press("1")
        tb_reload.press("6")
        tb_reload.press("\r")
        tb_reload.drain_more()
        tb_reload.assert_line("cart_cat_dl16", tb_reload.read_u8(cart_syms["zp_player_dlvl"]) == 16, "missed DL16")
        mt = cart_syms["monster_table"]
        live = [tb_reload.read_u8(mt + i * 12 + 2) for i in range(32)]
        live = [t for t in live if t != 0xFF]
        tb_reload.assert_line("cart_cat_population", len(live) >= 15, f"DL16 live={len(live)}")
        loaded = all(t < 32 and tb_reload.read_u8(cart_syms["cat_slot_id_hi"] + t) != 0xFF for t in live)
        tb_reload.assert_line(
            "cart_cat_slots",
            loaded,
            f"Bank {harness_smoke.CX16_BANK_CATALOG} catalog slot missing",
        )
        # Verify Bank 5 MONSTER.EXT preload & catalog_fetch_ext on cartridge
        ext_payload = (CART_BUILD_DIR / "MONSTER.EXT").read_bytes()[2:]
        fetch_addr = cart_syms["catalog_fetch_ext"]
        stub_cfe = [0x20, fetch_addr & 0xFF, fetch_addr >> 8, 0x60]
        for idx_s, op in enumerate(stub_cfe):
            tb_reload.write_u8(0x0700 + idx_s, op)
        saved_bank_reg = tb_reload.read_u8(0x0000)
        tb_reload.write_u8(0x0000, 9)
        cart_ext_ok = True
        cart_ext_detail = ""
        for cid in (0, 77, 255, 256, 278):
            tb_reload.write_u8(cart_syms["cat_id_lo"], cid & 0xFF)
            tb_reload.write_u8(cart_syms["cat_id_hi"], cid >> 8)
            tb_reload.run_addr(0x0700)
            got_rec = bytes(tb_reload.read_u8(cart_syms["cat_ext_record"] + k) for k in range(8))
            want_rec = ext_payload[cid * 8 : (cid + 1) * 8]
            if got_rec != want_rec or tb_reload.read_u8(0x0000) != 9 or tb_reload.read_u8(0x0001) != 0:
                cart_ext_ok = False
                cart_ext_detail = f"cid={cid} got={got_rec.hex()} want={want_rec.hex()} $00={tb_reload.read_u8(0x0000)} $01={tb_reload.read_u8(0x0001)}"
                break
        tb_reload.write_u8(0x0000, saved_bank_reg)
        tb_reload.assert_line("cart_catalog_fetch_ext", cart_ext_ok, cart_ext_detail)
        tb_reload.wizard_menu_open()
        tb_reload.press_until("DLVL", "L")
        tb_reload.press("5")
        tb_reload.press("0")
        tb_reload.press("\r")
        tb_reload.drain_more()
        tb_reload.assert_line("cart_cat_dl50", tb_reload.read_u8(cart_syms["zp_player_dlvl"]) == 50, "missed DL50")
        assert_fsroot_program_free(save_fsroot)
    finally:
        tb_reload.close()

    # 4. Bidirectional save interchange with disk MORIA8.PRG
    disk_fsroot = TEST_WORK_ROOT / "disk_interchange_fsroot"
    disk_fsroot.mkdir(parents=True, exist_ok=True)
    for fname in os.listdir(DISK_BUILD_DIR):
        src = DISK_BUILD_DIR / fname
        if src.is_file():
            shutil.copy2(src, disk_fsroot / fname)
    for p in save_fsroot.iterdir():
        if p.name.upper().startswith("THE.GAME"):
            shutil.copy2(p, disk_fsroot / p.name)

    tb_disk = harness_smoke.X16Bench(x16emu, rom, disk_fsroot, disk_syms)
    try:
        tb_disk.start(boot_to_title=True)
        load_character_from_title(tb_disk)
        name_bytes = bytes(tb_disk.read_u8(disk_syms["player_data"] + i) for i in range(4))
        tb_disk.assert_line("disk_loaded_cart_save", name_bytes == b"\x14\x05\x13\x14", f"disk loaded name={name_bytes!r}")
        # Mutate gold (PL_GOLD_0 = 43, PL_GOLD_1 = 44) and save from disk MORIA8.PRG, then reload in cartridge
        gold_addr = disk_syms["player_data"] + 43
        tb_disk.write_u8(gold_addr, 0x39)
        tb_disk.write_u8(gold_addr + 1, 0x05)  # 1337 gp
        tb_disk.write_u8(gold_addr + 2, 0x00)
        save_character_from_town(tb_disk)
    finally:
        tb_disk.close()
    for line in tb_disk.output_lines:
        print(line)
    if tb_disk.failures:
        raise AssertionError(f"disk interchange bench reported {tb_disk.failures} failure(s)")

    cart_interchange_fsroot = TEST_WORK_ROOT / "cart_interchange_fsroot"
    cart_interchange_fsroot.mkdir(parents=True, exist_ok=True)
    for p in disk_fsroot.iterdir():
        if p.name.upper().startswith("THE.GAME"):
            shutil.copy2(p, cart_interchange_fsroot / p.name)

    tb_from_disk = CartBench(
        x16emu, rom, cart_interchange_fsroot, cart_syms, "crt", CART_IMAGE, boot_syms
    )
    try:
        tb_from_disk.start(boot_to_title=True)
        load_character_from_title(tb_from_disk)
        cart_gold_addr = cart_syms["player_data"] + 43
        gold = tb_from_disk.read_u8(cart_gold_addr) | (tb_from_disk.read_u8(cart_gold_addr + 1) << 8)
        tb_from_disk.assert_line("cart_loaded_disk_save_gold", gold == 1337, f"expected 1337 gp, got {gold}")
        assert_fsroot_program_free(cart_interchange_fsroot)
    finally:
        tb_from_disk.close()

    # 5. Interactive -cartbin smoke check with empty -fsroot
    bin_fsroot = TEST_WORK_ROOT / "bin_fsroot"
    bin_fsroot.mkdir(parents=True, exist_ok=True)
    tb_bin = CartBench(x16emu, rom, bin_fsroot, cart_syms, "bin", CART_BIN, boot_syms)
    try:
        tb_bin.start(boot_to_title=True)
        tb_bin.assert_line("cartbin_title_menu", tb_bin.on_title(), "title screen missing for -cartbin")
        check_irq_and_keyhdl_state(tb_bin, "cartbin_title")
        check_legal_viewer(tb_bin, from_gameplay=False)
        tb_bin.chargen("A")
        assert_fsroot_program_free(bin_fsroot)
    finally:
        tb_bin.close()

    print("test_cartridge.py: ALL CX16 CARTRIDGE SCENARIOS PASSED")
    return 0


def run_selftest() -> int:
    # Minimal 1x1 GIF89a with 1 pixel of color 1
    gif = bytearray(b"GIF89a\x01\x00\x01\x00\x80\x00\x00")
    gif.extend(b"\x00\x00\x00\xff\xff\xff")  # 2-color GCT
    gif.extend(b"\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00")
    gif.append(2)  # LZW min code size
    gif.extend(b"\x02\x4c\x01\x00")  # LZW stream: clear(4), pix(1), eoi(5) -> 0x4C, 0x01
    gif.append(0x3B)
    w, h, frames = decode_gif_frames(bytes(gif))
    assert (w, h) == (1, 1) and len(frames) == 1 and frames[0] == [1], f"gif decode mismatch: {w}x{h} {frames}"

    assert fletcher16(b"CX16") == (sum(b"CX16") % 255, (4 * 67 + 3 * 88 + 2 * 49 + 54) % 255)
    assert make_testbench_stub_prg() == b"\x01\x08\x60"

    # Verify -fsroot program-artifact guard allows save files and catches leaked program artifacts
    selftest_dir = TEST_WORK_ROOT / "selftest_fsroot"
    if selftest_dir.exists():
        shutil.rmtree(selftest_dir)
    selftest_dir.mkdir(parents=True, exist_ok=True)
    try:
        assert_fsroot_program_free(selftest_dir)
        (selftest_dir / "THE.GAME").write_bytes(b"save")
        assert_fsroot_program_free(selftest_dir)
        for leak_name in ("LEGALUI", "MORIA8.PRG", "ITEM.CAT", "MONSTER.EXT"):
            leak_path = selftest_dir / leak_name
            leak_path.write_bytes(b"leak")
            raised = False
            try:
                assert_fsroot_program_free(selftest_dir)
            except AssertionError:
                raised = True
            assert raised, f"assert_fsroot_program_free failed to catch {leak_name}"
            leak_path.unlink()
        assert_fsroot_program_free(selftest_dir)
    finally:
        if selftest_dir.exists():
            shutil.rmtree(selftest_dir)
    with tempfile.TemporaryDirectory(prefix="cx16_cart_rom_selftest_") as rom_tmp:
        fake_emu = Path(rom_tmp) / "x16emu"
        fake_emu.write_bytes(b"")
        try:
            harness_smoke.resolve_rom_path(fake_emu, None)
        except RuntimeError:
            pass
        else:
            raise AssertionError("resolve_rom_path failed to reject missing X16ROM / adjacent rom.bin")
    print("test_cartridge.py --selftest: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--x16emu", default=os.environ.get("X16EMU", "x16emu"))
    parser.add_argument("--rom", default=os.environ.get("X16ROM", ""))
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    x16emu = Path(args.x16emu)
    try:
        rom = harness_smoke.resolve_rom_path(x16emu, Path(args.rom) if args.rom else None)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return run_cartridge_suite(x16emu, rom)


if __name__ == "__main__":
    sys.exit(main())
