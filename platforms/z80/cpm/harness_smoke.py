#!/usr/bin/env python3
"""CP/M 2.2 Z80 M5 smoke harness for Moria8 (docs/CPM_MEMORY_CONTRACT.md).

Drives headless build/cpm/cpm_runner in JSON-lines --control mode (with strict
CP/M 2.2 BDOS hazard checking enabled) and exercises real tools/runcpm/RunCPM
on a POSIX PTY.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
from contextlib import contextmanager
import json
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Iterator


CPM_SRC_DIR = Path(__file__).resolve().parent
ROOT = CPM_SRC_DIR.parents[2]
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))
import item_ids  # noqa: E402
import version_info  # noqa: E402
DEFAULT_BUILD_DIR = ROOT / "build" / "cpm"
DEFAULT_RUNNER = DEFAULT_BUILD_DIR / "cpm_runner"
DEFAULT_RUNCPM = ROOT / "tools" / "runcpm" / "RunCPM"
DEFAULT_SJASMPLUS = ROOT / "tools" / "sjasmplus" / "sjasmplus"
HUFFMAN_TXT = ROOT / "data" / "huffman_strings.txt"
LICENSE_TXT = ROOT / "data" / "LICENSE"
SOURCE_OFFER_TXT = ROOT / "data" / "SOURCE-OFFER"
VERSION_JSON = ROOT / "version.json"

# Authoritative 52 KB TPA ABI addresses (platforms/z80/cpm/memory.inc)
Z80_STATE_BASE = 0x6A00
Z80_STATE_SIZE = 64
STACK_CANARY_ADDR = 0x8C00
STACK_CANARY_BYTES = b"M8SK"
CPM_CHAR_SHADOW_BASE = 0x8E00
CPM_COLOR_SHADOW_BASE = 0x9580

OVL_NONE = 0
OVL_START = 1
OVL_TOWN = 2
OVL_DEATH = 3
OVL_GEN = 4
OVL_HELP = 5
OVL_UI = 6
OVL_ITEMS = 7
OVL_SPELL = 8
OVL_MODAL = 9
OVL_CHEST = 10
OVL_HOME = 11
OVL_STORAGE = 12
OVL_TITLE = 13
OVL_LEGAL = 14
OVL_ITEMS_EFF = 15
OVL_SPELL_EFF = 16
OVL_ACTIONS = 17
OVL_MON_EXT = 18
OVL_ITEM_MGT = 19

MAP_BASE_ADDR = 0x9D00
MAP_SIZE_BYTES = 13068
SAVE_VERSION_BYTE = 0x22
SAVE_STREAM_BYTES = 17164
SAVE_SLOT_RECORDS = 135
SAVE_RECORD_BYTES = 128

SGR_RE = re.compile(r"\x1b\[([0-9;]*)m")
ANSI_SEQ_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z~]")

SCENARIOS: tuple[str, ...] = (
    "tpa_guard_reject",
    "boot_title_adm3a",
    "boot_title_color",
    "boot_title_mono",
    "cli_tail_and_missing_overlay",
    "legal_viewer_nested_trampoline",
    "huffman_and_rng_entropy",
    "core_hal_unit_probe",
    "chargen_and_town_render",
    "town_store_buy_sell",
    "town_home_deposit_withdraw",
    "save_v2_roundtrip_and_checksum",
    "multi_drive_save_setup",
    "hiscore_io_roundtrip",
    "dungeon_gen_topology_soak",
    "los_stairs_and_exploration",
    "features_doors_traps_chests",
    "turn_regen_poison_repeat",
    "ui_help_wizard_death_hiscore",
    "monster_catalog_spawn_and_visibility",
    "monster_ai_combat_and_drops",
    "monster_attacks_and_magic",
    "item_mgt_ranged_throw_and_egos",
    "items_potions_scrolls_wands_staves",
    "spells_prayers_and_detect_lifecycle",
    "recall_and_balrog_victory",
    "runcpm_pty_smoke",
)


def _resolve_tool(explicit: Path | None, env_name: str, default_path: Path) -> Path:
    if explicit is not None:
        return explicit
    val = os.environ.get(env_name, "").strip()
    if not val:
        return default_path
    p = Path(val)
    if "/" in val or os.sep in val:
        return p.resolve()
    found = shutil.which(val)
    return Path(found) if found else p


def _load_expected_version() -> str:
    return version_info.resolve_port_version(VERSION_JSON, "cpm").display


def _load_huffman_corpus() -> list[str]:
    texts: list[str] = []
    for raw in HUFFMAN_TXT.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip("\r\n")
        if not line.strip() or line.strip().startswith("#"):
            continue
        trimmed = line.lstrip()
        if trimmed.startswith("@"):
            trimmed = trimmed[trimmed.index(" ") + 1 :]
        if trimmed.endswith(" ~"):
            trimmed = trimmed[:-1]
        texts.append(trimmed)
    return texts


def _extract_sgr_codes(raw_ansi: str) -> list[int]:
    codes: list[int] = []
    for m in SGR_RE.finditer(raw_ansi):
        params = m.group(1)
        if not params:
            codes.append(0)
            continue
        for part in params.split(";"):
            codes.append(int(part) if part else 0)
    return codes


def _is_fg_color_sgr(code: int) -> bool:
    return (30 <= code <= 37) or (90 <= code <= 97)


def _is_any_color_sgr(code: int) -> bool:
    return (
        (30 <= code <= 37)
        or (40 <= code <= 47)
        or (90 <= code <= 97)
        or (100 <= code <= 107)
    )


class ControlClient:
    """JSON-lines controller for headless build/cpm/cpm_runner."""

    def __init__(self, args: list[str]) -> None:
        self.proc = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert self.proc.stdin is not None
        assert self.proc.stdout is not None
        self._closed = False

    def call(self, obj: dict) -> dict:
        assert self.proc.stdin is not None and self.proc.stdout is not None
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            stderr = self.proc.stderr.read() if self.proc.stderr else ""
            raise RuntimeError(f"cpm_runner closed stdout unexpectedly; stderr={stderr!r}")
        resp = json.loads(line)
        if not resp.get("ok"):
            raise AssertionError(f"cpm_runner command {obj} failed: {resp}")
        return resp

    def run_idle(self, max_steps: int = 5_000_000, idle_polls: int = 512) -> dict:
        res = self.call({"cmd": "run_idle", "max_steps": max_steps, "idle_polls": idle_polls})
        assert res["reason"] == "idle", f"expected idle, got {res}"
        return res

    def run_until_exit(self, max_steps: int = 5_000_000) -> dict:
        res = self.call({"cmd": "run", "max_steps": max_steps})
        assert res["reason"] == "exited", f"expected exited, got {res}"
        return res

    def send_keys(self, text: str) -> None:
        self.call({"cmd": "send_keys", "text": text})

    def read_mem(self, addr: int, length: int) -> bytes:
        res = self.call({"cmd": "read_mem", "addr": addr, "len": length})
        return bytes.fromhex(res["hex"])

    def write_mem(self, addr: int, data: bytes) -> None:
        self.call({"cmd": "write_mem", "addr": addr, "hex": data.hex()})

    def read_z80_state(self) -> dict[str, object]:
        raw = self.read_mem(Z80_STATE_BASE, Z80_STATE_SIZE)
        rng_seed, entropy_poll, turn = struct.unpack_from("<IIH", raw, 0x08)
        hp, mhp = struct.unpack_from("<HH", raw, 0x17)
        return {
            "raw": raw,
            "magic": raw[0x00:0x04],
            "version": raw[0x04],
            "monochrome": raw[0x05],
            "current_overlay": raw[0x06],
            "overlay_depth": raw[0x07],
            "rng_seed": rng_seed,
            "entropy_poll": entropy_poll,
            "turn": turn,
            "game_flags": raw[0x12],
            "player_x": raw[0x13],
            "player_y": raw[0x14],
            "player_dlvl": raw[0x15],
            "player_lvl": raw[0x16],
            "hp": hp,
            "mhp": mhp,
            "mp": raw[0x1B],
            "mmp": raw[0x1C],
            "mon_count": raw[0x1E],
            "item_count": raw[0x1F],
            "view_x": raw[0x20],
            "view_y": raw[0x21],
            "light_rad": raw[0x22],
            "save_drive": raw[0x24],
            "program_drive": raw[0x25],
            "last_bdos_err": raw[0x26],
            "esc_pending": raw[0x27],
            "term_mode": raw[0x28],
        }

    def read_stack_canary(self) -> bytes:
        return self.read_mem(STACK_CANARY_ADDR, len(STACK_CANARY_BYTES))

    def screen_lines(self, include_attrs: bool = False) -> tuple[list[str], dict]:
        scr = self.call({"cmd": "screen", "include_attrs": include_attrs})
        assert scr["rows"] == 24 and scr["cols"] == 80
        return scr["lines"], scr

    def console_out(self, since: int = 0) -> tuple[str, int]:
        out = self.call({"cmd": "console_out", "since": since})
        return out["text"], int(out["total_len"])

    def close(self) -> int:
        if self._closed:
            return 0
        self._closed = True
        try:
            if self.proc.poll() is None:
                self.call({"cmd": "quit"})
        except Exception:
            pass
        rc = self.proc.wait(timeout=5)
        stderr = self.proc.stderr.read() if self.proc.stderr else ""
        if stderr:
            raise AssertionError(f"unexpected stderr in control mode: {stderr!r}")
        return rc

    def force_cleanup(self) -> None:
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait(timeout=5)


@contextmanager
def _staged_runner(
    runner: Path,
    build_dir: Path,
    extra_args: list[str] | None = None,
) -> Iterator[ControlClient]:
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    if not com_src.is_file():
        raise FileNotFoundError(f"Missing MORIA8.COM at {com_src}")
    if not dat_src.is_file():
        raise FileNotFoundError(f"Missing MORIA8.DAT at {dat_src}")

    with tempfile.TemporaryDirectory() as td:
        workdir = Path(td)
        com_dst = workdir / "MORIA8.COM"
        dat_dst = workdir / "MORIA8.DAT"
        shutil.copy2(com_src, com_dst)
        shutil.copy2(dat_src, dat_dst)

        cmd = [str(runner), "--control", "--workdir", str(workdir)]
        if extra_args:
            cmd.extend(extra_args)
        cmd.append(str(com_dst))
        cli = ControlClient(cmd)
        try:
            yield cli
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def scenario_tpa_guard_reject(runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path) -> None:
    with _staged_runner(runner, build_dir, extra_args=["--tpa-top", "0xC000"]) as cli:
        res = cli.run_until_exit()
        assert res["exit_code"] == 0, f"expected clean exit code 0, got {res}"
        assert res["exit_reason"] == "bdos_0", f"expected bdos_0 exit, got {res}"
        out_text, _ = cli.console_out()
        assert "Insufficient TPA" in out_text, f"missing TPA error message in {out_text!r}"
        assert cli.read_mem(Z80_STATE_BASE, 4) == b"\x00\x00\x00\x00", (
            "TPA guard must exit before initializing z80_state"
        )
        assert cli.read_stack_canary() == b"\x00\x00\x00\x00", (
            "TPA guard must exit before writing stack_canary"
        )


def scenario_boot_title_adm3a(runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path) -> None:
    expected_ver = _load_expected_version()

    with _staged_runner(runner, build_dir) as cli:
        cli.run_idle()
        lines, scr = cli.screen_lines(include_attrs=True)
        screen_blob = "\n".join(lines)
        assert "#   #" in screen_blob and "The Dungeons of Moria" in screen_blob, (
            f"missing title banner on screen:\n{screen_blob}"
        )
        assert "N)ew  L)oad  D)isk Setup  A)bout" in screen_blob, (
            f"missing title menu on screen:\n{screen_blob}"
        )
        assert expected_ver in screen_blob, f"missing {expected_ver} on title screen:\n{screen_blob}"
        assert "[ADM-3A]" in screen_blob, f"missing [ADM-3A] badge on default title screen:\n{screen_blob}"
        assert "Free Software" not in screen_blob and "GPL" not in screen_blob, screen_blob
        assert "Welcome back" not in screen_blob and "[H] High Scores" not in screen_blob, screen_blob

        raw_out, out_cursor = cli.console_out()
        assert "\x1a" in raw_out, f"expected ADM-3A 0x1A clear on default boot, got {raw_out[:64]!r}"
        assert "\x1b=" in raw_out, f"expected ADM-3A ESC= positioning on default boot, got {raw_out[:64]!r}"
        assert "\x1b[" not in raw_out, f"default ADM-3A boot must not emit ANSI CSI escapes: {raw_out!r}"

        st = cli.read_z80_state()
        assert st["magic"] == b"M8Z0", f"bad z80_state magic: {st['magic']!r}"
        assert st["version"] == 1, f"bad z80_state version: {st['version']}"
        assert st["term_mode"] == 0, f"expected default term_mode=0 (ADM-3A), got {st['term_mode']}"
        assert st["monochrome"] == 1, f"expected default monochrome=1 (ADM-3A), got {st['monochrome']}"
        assert st["current_overlay"] == OVL_TITLE, (
            f"expected current_overlay={OVL_TITLE}, got {st['current_overlay']}"
        )
        assert st["overlay_depth"] == 1, f"expected overlay_depth=1 in Title, got {st['overlay_depth']}"
        assert cli.read_stack_canary() == STACK_CANARY_BYTES

        cli.send_keys("Q")
        fin = cli.run_until_exit()
        assert fin["exit_code"] == 0 and fin["exit_reason"] in ("bdos_0", "warm_boot"), fin
        exit_out, _ = cli.console_out(since=out_cursor)
        assert "\x1b=7 " in exit_out, f"expected ADM-3A row-23 exit park ESC=7 , got {exit_out!r}"
        assert "\x1b[" not in exit_out, f"ADM-3A exit must not emit ANSI CSI escapes: {exit_out!r}"
        assert cli.read_stack_canary() == STACK_CANARY_BYTES


def scenario_boot_title_color(runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path) -> None:
    expected_ver = _load_expected_version()

    with _staged_runner(runner, build_dir, extra_args=["--tail", "/V"]) as cli:
        cli.run_idle()
        lines, scr = cli.screen_lines(include_attrs=True)
        screen_blob = "\n".join(lines)
        assert "#   #" in screen_blob and "The Dungeons of Moria" in screen_blob, (
            f"missing title banner on screen:\n{screen_blob}"
        )
        assert "N)ew  L)oad  D)isk Setup  A)bout" in screen_blob, (
            f"missing title menu on screen:\n{screen_blob}"
        )
        assert expected_ver in screen_blob, f"missing {expected_ver} on title screen:\n{screen_blob}"
        assert "[Color]" in screen_blob, f"missing [Color] badge on title screen:\n{screen_blob}"
        assert "Free Software" not in screen_blob and "GPL" not in screen_blob, screen_blob
        assert "Welcome back" not in screen_blob and "[H] High Scores" not in screen_blob, screen_blob

        raw_out, _ = cli.console_out()
        sgr_codes = _extract_sgr_codes(raw_out)
        assert any(_is_fg_color_sgr(c) for c in sgr_codes), (
            f"expected ANSI color foreground SGR codes in /V color boot, got {sgr_codes}"
        )

        st = cli.read_z80_state()
        assert st["magic"] == b"M8Z0", f"bad z80_state magic: {st['magic']!r}"
        assert st["version"] == 1, f"bad z80_state version: {st['version']}"
        assert st["term_mode"] == 1, f"expected /V term_mode=1 (ANSI), got {st['term_mode']}"
        assert st["monochrome"] == 0, f"expected color monochrome=0, got {st['monochrome']}"
        assert st["current_overlay"] == OVL_TITLE, (
            f"expected current_overlay={OVL_TITLE}, got {st['current_overlay']}"
        )
        assert st["overlay_depth"] == 1, f"expected overlay_depth=1 in Title, got {st['overlay_depth']}"
        assert cli.read_stack_canary() == STACK_CANARY_BYTES

        cli.send_keys("Q")
        fin = cli.run_until_exit()
        assert fin["exit_code"] == 0 and fin["exit_reason"] in ("bdos_0", "warm_boot"), fin
        assert cli.read_stack_canary() == STACK_CANARY_BYTES


def scenario_boot_title_mono(runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path) -> None:
    expected_ver = _load_expected_version()

    with _staged_runner(runner, build_dir, extra_args=["--tail", "/M"]) as cli:
        cli.run_idle()
        st = cli.read_z80_state()
        assert st["magic"] == b"M8Z0"
        assert st["term_mode"] == 1, f"expected abi_term_mode=1 for /M, got {st['term_mode']}"
        assert st["monochrome"] == 1, f"expected abi_monochrome=1 for /M, got {st['monochrome']}"
        assert st["current_overlay"] == OVL_TITLE

        lines, scr = cli.screen_lines(include_attrs=True)
        screen_blob = "\n".join(lines)
        assert "N)ew  L)oad  D)isk Setup  A)bout" in screen_blob
        assert "[Mono]" in screen_blob, f"missing [Mono] badge in mono mode:\n{screen_blob}"
        assert expected_ver in screen_blob

        mono_out, out_cursor = cli.console_out()
        mono_sgr = _extract_sgr_codes(mono_out)
        bad_colors = [c for c in mono_sgr if _is_any_color_sgr(c)]
        assert not bad_colors, f"monochrome /M emitted color SGR codes {bad_colors}: {mono_out!r}"
        has_reverse = ("\x1b[7m" in mono_out) or any(
            (attr & 0x08) != 0 for row in scr["attr"] for attr in row
        )
        assert has_reverse, "monochrome mode must preserve reverse-video highlight (ESC[7m)"

        # Runtime toggle: ANSI Mono (1,1) -> ADM-3A (0,1)
        cli.send_keys("M")
        cli.run_idle()
        st_adm = cli.read_z80_state()
        assert st_adm["term_mode"] == 0 and st_adm["monochrome"] == 1, (
            f"expected first 'M' toggle from Mono to ADM-3A (0,1), got ({st_adm['term_mode']},{st_adm['monochrome']})"
        )
        adm_out, out_cursor = cli.console_out(since=out_cursor)
        assert "\x1a" in adm_out and "\x1b[" not in adm_out, (
            f"runtime toggle to ADM-3A must emit 0x1A and zero CSI sequences: {adm_out!r}"
        )
        assert "[ADM-3A]" in "\n".join(cli.screen_lines()[0])

        # Runtime toggle: ADM-3A (0,1) -> ANSI Color (1,0)
        cli.send_keys("M")
        cli.run_idle()
        st_color = cli.read_z80_state()
        assert st_color["term_mode"] == 1 and st_color["monochrome"] == 0, (
            f"expected second 'M' toggle from ADM-3A to Color (1,0), got ({st_color['term_mode']},{st_color['monochrome']})"
        )
        color_out, out_cursor = cli.console_out(since=out_cursor)
        color_sgr = _extract_sgr_codes(color_out)
        assert any(_is_fg_color_sgr(c) for c in color_sgr), (
            f"runtime toggle to color did not emit color SGR codes: {color_sgr}"
        )
        assert "[Color]" in "\n".join(cli.screen_lines()[0])

        # Runtime toggle: ANSI Color (1,0) -> ANSI Mono (1,1)
        cli.send_keys("M")
        cli.run_idle()
        st_mono2 = cli.read_z80_state()
        assert st_mono2["term_mode"] == 1 and st_mono2["monochrome"] == 1, (
            f"expected third 'M' toggle from Color to Mono (1,1), got ({st_mono2['term_mode']},{st_mono2['monochrome']})"
        )
        mono2_out, _ = cli.console_out(since=out_cursor)
        mono2_sgr = _extract_sgr_codes(mono2_out)
        bad_colors2 = [c for c in mono2_sgr if _is_any_color_sgr(c)]
        assert not bad_colors2, (
            f"runtime toggle back to mono emitted color SGR codes {bad_colors2}: {mono2_out!r}"
        )
        assert "[Mono]" in "\n".join(cli.screen_lines()[0])

        cli.send_keys("Q")
        fin = cli.run_until_exit()
        assert fin["exit_code"] == 0
        assert cli.read_stack_canary() == STACK_CANARY_BYTES


def scenario_cli_tail_and_missing_overlay(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Verify parse_cli_tail edge cases, B: drive override, and OVL_LEGAL CF=1 error handling."""
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    if not com_src.is_file() or not dat_src.is_file():
        raise FileNotFoundError(f"Missing MORIA8.COM or MORIA8.DAT in {build_dir}")

    # 1. All parse_cli_tail edge cases on drive A: (/A, /V, /M, /MON, /VT, //M, /V/, Q:)
    cases: tuple[tuple[str, int, int, int], ...] = (
        ("", 0, 1, 0),
        (" /", 0, 1, 0),
        (" /A", 0, 1, 0),
        (" /a", 0, 1, 0),
        (" /V", 1, 0, 0),
        (" /v", 1, 0, 0),
        (" /V/", 1, 0, 0),
        (" /VT", 0, 1, 0),
        (" /M/", 1, 1, 0),
        (" //", 0, 1, 0),
        (" //M", 1, 1, 0),
        (" foo/", 0, 1, 0),
        (" /m", 1, 1, 0),
        (" /MON", 0, 1, 0),
        (" Q:", 0, 1, 0),
    )
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        drv_a = tmp / "drv_a"
        drv_b = tmp / "drv_b"
        drv_a.mkdir()
        drv_b.mkdir()
        shutil.copy2(com_src, tmp / "MORIA8.COM")
        shutil.copy2(dat_src, drv_a / "MORIA8.DAT")

        for tail_str, exp_term, exp_mono, exp_drv in cases:
            cli = ControlClient([
                str(runner),
                "--control",
                "--drive", f"A={drv_a}",
                "--drive", f"B={drv_b}",
                "--strict-drives",
                "--raw-tail",
                "--tail", tail_str,
                str(tmp / "MORIA8.COM"),
            ])
            try:
                cli.run_idle()
                st = cli.read_z80_state()
                assert st["magic"] == b"M8Z0", f"bad magic for tail {tail_str!r}"
                assert st["term_mode"] == exp_term, (
                    f"tail {tail_str!r}: expected term_mode={exp_term}, got {st['term_mode']}"
                )
                assert st["monochrome"] == exp_mono, (
                    f"tail {tail_str!r}: expected monochrome={exp_mono}, got {st['monochrome']}"
                )
                assert st["program_drive"] == exp_drv, (
                    f"tail {tail_str!r}: expected program_drive={exp_drv}, got {st['program_drive']}"
                )
                cli.send_keys("Q")
                fin = cli.run_until_exit()
                assert fin["exit_code"] == 0
                assert cli.read_stack_canary() == STACK_CANARY_BYTES
                assert cli.close() == 0
            finally:
                cli.force_cleanup()

        # 2. B:/, B: /m, and B:/V with MORIA8.DAT ONLY on drive B: (A: empty!)
        (drv_a / "MORIA8.DAT").unlink()
        shutil.copy2(dat_src, drv_b / "MORIA8.DAT")

        for tail_str, exp_term, exp_mono in ((" B:/", 0, 1), (" B: /m", 1, 1), (" B:/V", 1, 0)):
            cli = ControlClient([
                str(runner),
                "--control",
                "--drive", f"A={drv_a}",
                "--drive", f"B={drv_b}",
                "--strict-drives",
                "--raw-tail",
                "--tail", tail_str,
                str(tmp / "MORIA8.COM"),
            ])
            try:
                cli.run_idle()
                st = cli.read_z80_state()
                assert st["program_drive"] == 1, (
                    f"tail {tail_str!r}: expected abi_program_drive=1 (B:), got {st['program_drive']}"
                )
                assert st["save_drive"] == 1, (
                    f"tail {tail_str!r}: expected abi_save_drive=1 (B:), got {st['save_drive']}"
                )
                assert st["term_mode"] == exp_term, (
                    f"tail {tail_str!r}: expected term_mode={exp_term}, got {st['term_mode']}"
                )
                assert st["monochrome"] == exp_mono, (
                    f"tail {tail_str!r}: expected monochrome={exp_mono}, got {st['monochrome']}"
                )
                assert st["current_overlay"] == OVL_TITLE
                blob = "\n".join(cli.screen_lines()[0])
                assert "N)ew  L)oad  D)isk Setup  A)bout" in blob, (
                    f"tail {tail_str!r}: Drive B: title failed to render:\n{blob}"
                )
                cli.send_keys("Q")
                fin = cli.run_until_exit()
                assert fin["exit_code"] == 0
                assert cli.read_stack_canary() == STACK_CANARY_BYTES
                assert cli.close() == 0
            finally:
                cli.force_cleanup()

        # 3. Missing OVL_LEGAL slot 13 in MORIA8.DAT -> Title 'A' returns CF=1 error without flicker
        corrupt_dat = bytearray(dat_src.read_bytes())
        struct.pack_into("<HHH", corrupt_dat, 6 + 13 * 6, 0, 0, 0)
        (drv_a / "MORIA8.DAT").write_bytes(bytes(corrupt_dat))
        cli = ControlClient([
            str(runner),
            "--control",
            "--drive", f"A={drv_a}",
            "--strict-drives",
            str(tmp / "MORIA8.COM"),
        ])
        try:
            cli.run_idle()
            _, out_before_a = cli.console_out()
            cli.send_keys("A")
            cli.run_idle()
            st_err = cli.read_z80_state()
            assert st_err["current_overlay"] == OVL_TITLE, (
                f"expected OVL_TITLE restored after missing OVL_LEGAL, got {st_err['current_overlay']}"
            )
            assert st_err["overlay_depth"] == 1, (
                f"expected overlay_depth=1 restored after load_failed, got {st_err['overlay_depth']}"
            )
            lines_err, _ = cli.screen_lines()
            assert "Unable to load Legal Viewer." in lines_err[20], (
                f"expected error on INPUT_ROW 20, got row20={lines_err[20]!r}"
            )
            assert "N)ew  L)oad  D)isk Setup  A)bout" in "\n".join(lines_err)
            delta_out, _ = cli.console_out(since=out_before_a)
            assert "\x1b[2J" not in delta_out and "\x1a" not in delta_out, (
                f"missing OVL_LEGAL error path must not hard-clear/flicker: {delta_out!r}"
            )
            cli.send_keys("Q")
            fin = cli.run_until_exit()
            assert fin["exit_code"] == 0
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def scenario_legal_viewer_nested_trampoline(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    with _staged_runner(runner, build_dir, extra_args=["--tpa-top", "0xD100"]) as cli:
        cli.run_idle()
        st0 = cli.read_z80_state()
        assert st0["current_overlay"] == OVL_TITLE and st0["overlay_depth"] == 1

        # Enter Legal Viewer from Title ('A') -> nested overlay OVL_LEGAL (depth 2)
        cli.send_keys("A")
        cli.run_idle()
        st1 = cli.read_z80_state()
        assert st1["current_overlay"] == OVL_LEGAL, (
            f"expected OVL_LEGAL ({OVL_LEGAL}), got {st1['current_overlay']}"
        )
        assert st1["overlay_depth"] == 2, f"expected overlay_depth=2 in Legal, got {st1['overlay_depth']}"
        legal_lines, _ = cli.screen_lines()
        legal_blob = "\n".join(legal_lines)
        assert "License & Source" in legal_blob
        assert "1 License  2 Source  3 Info  Q Back" in legal_blob

        # Open 1: License -> check data/LICENSE text, Space page, and ESC return
        cli.send_keys("1")
        cli.run_idle()
        lic_lines, _ = cli.screen_lines()
        lic_blob = "\n".join(lic_lines)
        assert "GNU GENERAL PUBLIC LICENSE" in lic_blob, (
            f"missing license text on page:\n{lic_blob}"
        )
        cli.send_keys(" ")
        cli.run_idle()
        back1, _ = cli.screen_lines()
        assert "1 License  2 Source  3 Info  Q Back" in "\n".join(back1)
        cli.send_keys("1\x1b")
        cli.run_idle()
        back1b, _ = cli.screen_lines()
        assert "1 License  2 Source  3 Info  Q Back" in "\n".join(back1b)

        # Open 2: Source Offer (22 lines -> tests Space, R restart, EOF Space exit, & Q)
        cli.send_keys("2")
        cli.run_idle()
        src_p1, _ = cli.screen_lines()
        src_p1_blob = "\n".join(src_p1)
        assert "MORIA8 SOURCE OFFER" in src_p1_blob and "Space: next" in src_p1_blob, (
            f"missing paginated SOURCE-OFFER page 1:\n{src_p1_blob}"
        )
        assert "CHARGE." not in src_p1_blob

        # Space -> page 2 (advances past line 20 to EOF)
        cli.send_keys(" ")
        cli.run_idle()
        src_space_blob = "\n".join(cli.screen_lines()[0])
        assert "CHARGE." in src_space_blob and "End. R: restart" in src_space_blob, (
            f"Space failed to advance SOURCE-OFFER to page 2:\n{src_space_blob}"
        )
        assert "MORIA8 SOURCE OFFER" not in src_space_blob

        # 'R' restart -> page 1 -> 'Q' back to Legal menu
        cli.send_keys("R")
        cli.run_idle()
        src_restart_blob = "\n".join(cli.screen_lines()[0])
        assert "MORIA8 SOURCE OFFER" in src_restart_blob and "Space: next" in src_restart_blob, (
            f"'R' failed to restart SOURCE-OFFER:\n{src_restart_blob}"
        )
        cli.send_keys("Q")
        cli.run_idle()

        # Open 3 & 'V' alias: System Info -> verify TPA $D100, drive, mode, TOC count 25
        for sys_key in ("3", "V"):
            cli.send_keys(sys_key)
            cli.run_idle()
            info_blob = "\n".join(cli.screen_lines()[0])
            assert "TPA $D100" in info_blob, f"missing TPA $D100 in SysInfo ({sys_key}):\n{info_blob}"
            assert "Program A:" in info_blob and "(ADM-3A)" in info_blob, (
                f"missing drive/terminal mode in SysInfo ({sys_key}):\n{info_blob}"
            )
            assert "MORIA8.DAT v1 (25 TOC slots)" in info_blob, (
                f"missing TOC count 25 in SysInfo ({sys_key}):\n{info_blob}"
            )
            cli.send_keys("Q")
            cli.run_idle()
            assert "1 License  2 Source  3 Info  Q Back" in "\n".join(cli.screen_lines()[0])

        # Exit Legal menu -> verify OVL_TITLE reloaded cleanly at depth 1
        cli.send_keys("Q")
        cli.run_idle()
        st2 = cli.read_z80_state()
        assert st2["current_overlay"] == OVL_TITLE, (
            f"expected OVL_TITLE ({OVL_TITLE}) restored, got {st2['current_overlay']}"
        )
        assert st2["overlay_depth"] == 1, f"expected overlay_depth=1 in Title, got {st2['overlay_depth']}"
        title_lines, _ = cli.screen_lines()
        assert "N)ew  L)oad  D)isk Setup  A)bout" in "\n".join(title_lines)

        cli.send_keys("Q")
        fin = cli.run_until_exit()
        assert fin["exit_code"] == 0
        assert cli.read_stack_canary() == STACK_CANARY_BYTES


def scenario_huffman_and_rng_entropy(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    corpus = _load_huffman_corpus()

    with _staged_runner(runner, build_dir) as cli:
        cli.run_idle()
        lines, _ = cli.screen_lines()
        assert "N)ew  L)oad  D)isk Setup  A)bout" in "\n".join(lines)

        # Verify real Huffman decoding via Load -> empty slot message from corpus
        cli.send_keys("L1")
        cli.run_idle()
        load_blob = "\n".join(cli.screen_lines()[0])
        assert any(s in load_blob for s in corpus), (
            f"Huffman string missing from Moria8 corpus on Load prompt:\n{load_blob}"
        )
        cli.send_keys(" \x1b")
        cli.run_idle()
        assert cli.read_z80_state()["current_overlay"] == OVL_TITLE

        st0 = cli.read_z80_state()
        ent0 = st0["entropy_poll"]
        rng0 = st0["rng_seed"]

        # 1. Idle polling advances entropy_poll; CSI arrow (\x1b[A) mixes RNG without leaving garbage
        cli.run_idle(idle_polls=600)
        st_poll = cli.read_z80_state()
        assert st_poll["entropy_poll"] > ent0, (
            f"expected abi_entropy_poll to advance ({ent0} -> {st_poll['entropy_poll']})"
        )

        cli.send_keys("\x1b[A")
        cli.run_idle()
        st_arrow = cli.read_z80_state()
        assert st_arrow["current_overlay"] == OVL_TITLE, (
            "CSI Up arrow leaked 'A' or switched away from Title"
        )
        assert st_arrow["esc_pending"] == 0
        assert st_arrow["rng_seed"] != rng0, (
            f"expected abi_rng_seed to advance across key poll ({rng0:#x} -> {st_arrow['rng_seed']:#x})"
        )

        # 2. Enter Legal ('A') -> bare ESC returns cleanly to Title after 255-poll timeout
        cli.send_keys("A")
        cli.run_idle()
        assert cli.read_z80_state()["current_overlay"] == OVL_LEGAL

        cli.send_keys("\x1b")
        cli.run_idle()
        st_esc = cli.read_z80_state()
        assert st_esc["current_overlay"] == OVL_TITLE, (
            f"bare ESC failed to return from Legal to Title: {st_esc}"
        )
        assert st_esc["esc_pending"] == 0

        # 3. Rapid ESC + 'N' (\x1bN) inside Legal: ESC backs out to Title AND 'N' enters OVL_START chargen
        cli.send_keys("A")
        cli.run_idle()
        assert cli.read_z80_state()["current_overlay"] == OVL_LEGAL

        cli.send_keys("\x1bN")
        cli.run_idle()
        st_pushback = cli.read_z80_state()
        assert st_pushback["current_overlay"] == OVL_START, (
            f"expected queued 'N' after ESC to enter OVL_START ({OVL_START}), got {st_pushback}"
        )
        assert st_pushback["esc_pending"] == 0
        lines_pb, _ = cli.screen_lines()
        assert "Choose your race" in "\n".join(lines_pb), (
            f"expected queued 'N' after ESC to display Race selection:\n" + "\n".join(lines_pb)
        )

        # Chargen does not allow ESC cancel (6502 parity): finish creation & Quit back to Title
        cli.send_keys("a\raTest\ra QY")
        cli.run_idle()
        st_back = cli.read_z80_state()
        assert st_back["current_overlay"] == OVL_TITLE

        cli.send_keys("Q")
        fin = cli.run_until_exit()
        assert fin["exit_code"] == 0
        assert cli.read_stack_canary() == STACK_CANARY_BYTES


class _PtyAnsiScreen:
    """Minimal 80x24 ANSI/VT100 + ADM-3A screen model for RunCPM PTY verification."""

    def __init__(self, rows: int = 24, cols: int = 80) -> None:
        self.rows = rows
        self.cols = cols
        self.cells = [[" "] * cols for _ in range(rows)]
        self.cur_row = 0
        self.cur_col = 0
        self._state = "normal"
        self._csi_buf = ""
        self._adm_row = 0

    def feed(self, data: bytes) -> None:
        for b in data:
            ch = chr(b)
            if self._state == "esc":
                if ch == "[":
                    self._state = "csi"
                    self._csi_buf = ""
                elif ch == "=":
                    self._state = "adm_row"
                else:
                    self._state = "normal"
                continue
            if self._state == "adm_row":
                self._adm_row = max(0, min(self.rows - 1, b - 0x20))
                self._state = "adm_col"
                continue
            if self._state == "adm_col":
                self.cur_row = self._adm_row
                self.cur_col = max(0, min(self.cols - 1, b - 0x20))
                self._state = "normal"
                continue
            if self._state == "csi":
                if "\x40" <= ch <= "\x7e":
                    self._dispatch_csi(self._csi_buf, ch)
                    self._state = "normal"
                elif ch == "\x1b":
                    self._state = "esc"
                else:
                    self._csi_buf += ch
                continue

            if b == 0x1B:
                self._state = "esc"
            elif b == 0x1A:
                self.cells = [[" "] * self.cols for _ in range(self.rows)]
                self.cur_row = 0
                self.cur_col = 0
            elif b == 0x1E:
                self.cur_row = 0
                self.cur_col = 0
            elif ch == "\r":
                self.cur_col = 0
            elif ch == "\n":
                self.cur_row += 1
                if self.cur_row >= self.rows:
                    self.cells.pop(0)
                    self.cells.append([" "] * self.cols)
                    self.cur_row = self.rows - 1
            elif ch == "\b":
                if self.cur_col > 0:
                    self.cur_col -= 1
            elif 0x20 <= b <= 0x7E:
                self.cells[self.cur_row][self.cur_col] = ch
                if self.cur_col + 1 < self.cols:
                    self.cur_col += 1

    def _dispatch_csi(self, params_str: str, final_ch: str) -> None:
        if params_str.startswith("?"):
            return
        parts = [int(p) if p.isdigit() else 0 for p in params_str.split(";")] if params_str else []
        if final_ch in ("H", "f"):
            r = (parts[0] if len(parts) >= 1 and parts[0] > 0 else 1) - 1
            c = (parts[1] if len(parts) >= 2 and parts[1] > 0 else 1) - 1
            self.cur_row = max(0, min(self.rows - 1, r))
            self.cur_col = max(0, min(self.cols - 1, c))
        elif final_ch == "J":
            mode = parts[0] if parts else 0
            if mode in (2, 3):
                self.cells = [[" "] * self.cols for _ in range(self.rows)]

    def text(self) -> str:
        return "\n".join("".join(row) for row in self.cells)


def _parse_sym_addrs(sym_path: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    for line in sym_path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Za-z_@.][A-Za-z0-9_@.]*):\s*EQU\s+0x([0-9A-Fa-f]+)\s*$", line.strip())
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    return syms


def scenario_core_hal_unit_probe(
    runner: Path, _runcpm: Path, sjasmplus: Path, build_dir: Path
) -> None:
    """Exercise resident M1 math, numeric format, RNG, sound, Huffman LRU, & BDOS 13 recovery."""
    if not sjasmplus.is_file():
        raise FileNotFoundError(f"sjasmplus binary not found at {sjasmplus}")
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    exp_src = build_dir / "main_exp.inc"
    huff_inc = build_dir / "huff_ascii.inc"
    huff_stream = (build_dir / "huff_stream.bin").read_bytes()
    for req in (com_src, dat_src, exp_src, huff_inc):
        if not req.is_file():
            raise FileNotFoundError(f"Missing required build artifact {req}")

    corpus = _load_huffman_corpus()

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        drv_a = tmp / "drive_a"
        drv_b = tmp / "drive_b"
        drv_a.mkdir()
        drv_b.mkdir()
        shutil.copy2(dat_src, drv_a / "MORIA8.DAT")

        probe_asm = tmp / "unit_probe.asm"
        probe_com = tmp / "PROBE.COM"
        probe_sym = tmp / "probe.sym"
        probe_asm.write_text(
            f"""    DEVICE NOSLOT64K
    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    DEFINE HUFF_CONSTS_ONLY 1
    INCLUDE "huff_ascii.inc"
    UNDEFINE HUFF_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  RESIDENT_BASE
    INCBIN "{com_src.resolve()}"
    ASSERT $ <= OVL_WINDOW_BASE
    DS   OVL_WINDOW_BASE - $, 0

    ORG  OVL_WINDOW_BASE
probe_start:
    LD   SP, STACK_TOP
    LD   HL, canary_bytes
    LD   DE, STACK_CANARY_ADDR
    LD   BC, STACK_CANARY_LEN
    LDIR

    LD   HL, BSS_BASE
    LD   DE, BSS_BASE + 1
    LD   BC, bss_end - BSS_BASE - 1
    LD   (HL), 0
    LDIR

    LD   HL, magic_bytes
    LD   DE, z80_state
    LD   BC, 4
    LDIR
    LD   A, Z80_ABI_VERSION_NUM
    LD   (z80_state + Z80_ABI_VERSION), A
    XOR  A
    LD   (abi_program_drive), A
    LD   (abi_save_drive), A

    CALL bdos_reset_dma_default
    CALL dat_init
    JP   C, probe_fail
    CALL rng_init_boot
    CALL sound_init
    CALL huff_lru_init

    ; 1. Math: mul_hl_a, mul_de_a, mul_de_bc, div_hl_c (incl C>=128 and C==0)
    LD   HL, 0x0123
    LD   A, 5
    CALL mul_hl_a
    LD   (res_mul_hl), HL

    LD   DE, 0x0080
    LD   A, 12
    CALL mul_de_a
    LD   (res_mul_de), HL

    LD   DE, 300
    LD   C, 200
    CALL mul_de_bc
    LD   (res_mul_bc), HL

    LD   HL, 60000
    LD   C, 200
    CALL div_hl_c
    JP   C, probe_fail
    LD   (res_div1_q), HL
    LD   (res_div1_r), A

    LD   HL, 65535
    LD   C, 200                 ; C >= 128 overflow path
    CALL div_hl_c
    JP   C, probe_fail
    LD   (res_div2_q), HL
    LD   (res_div2_r), A

    LD   HL, 12345
    LD   C, 0                   ; div-by-zero -> HL=0xFFFF, CF=1
    CALL div_hl_c
    JP   NC, probe_fail
    LD   (res_div0_q), HL

    ; 2. Numeric formatting: fmt_u16_dec(17164), fmt_u16_dec(65535), fmt_u8_dec(205)
    LD   HL, 17164
    LD   DE, buf_dec_17164
    CALL fmt_u16_dec
    LD   A, B
    LD   (len_dec_17164), A

    LD   HL, 65535
    LD   DE, buf_dec_65535
    CALL fmt_u16_dec
    LD   A, B
    LD   (len_dec_65535), A

    LD   A, 205
    LD   DE, buf_dec_205
    CALL fmt_u8_dec
    LD   A, B
    LD   (len_dec_205), A

    ; 3. RNG: rng_next_u8 & rng_range
    CALL rng_next_u8
    LD   (res_rng_u8), A
    LD   A, 1
    CALL rng_range
    LD   (res_rng_1), A
    XOR  A
    CALL rng_range
    LD   (res_rng_0), A

    LD   B, 32
    LD   HL, buf_rng_10
.rng10_loop:
    LD   A, 10
    CALL rng_range
    LD   (HL), A
    INC  HL
    DJNZ .rng10_loop

    ; 4. Sound: bell on -> toggle off -> bell muted -> toggle on -> bell on (expect 07, 07)
    CALL sound_bell
    CALL sound_toggle
    LD   (res_snd_off), A
    CALL sound_bell
    CALL sound_toggle
    LD   (res_snd_on), A
    CALL sound_bell

    ; 5. Huffman 2-record LRU + 128 B boundary crossing + eviction (rec 0, 1, 1->2, 24, 0)
    LD   A, 0
    LD   DE, buf_huff_0a
    CALL huff_decode_string
    JP   C, probe_fail
    LD   A, 8
    LD   DE, buf_huff_8
    CALL huff_decode_string
    JP   C, probe_fail
    LD   A, 19                  ; crosses 0x0100 (rec 1 -> rec 2)
    LD   DE, buf_huff_19
    CALL huff_decode_string
    JP   C, probe_fail
    LD   A, 240                 ; rec 24 (>= 20), evicts LRU slot
    LD   DE, buf_huff_240
    CALL huff_decode_string
    JP   C, probe_fail
    LD   A, 0                   ; evicted from rec 0 -> re-fetch cleanly
    LD   DE, buf_huff_0b
    CALL huff_decode_string
    JP   C, probe_fail

    ; 6. bdos_reset_disk_recover: switch to B:, BDOS 13 recover -> preserve B:, DMA=0xD080, fcb_dat=A:
    LD   C, BDOS_SELDSK
    LD   E, 1
    CALL bdos_call
    OR   A
    JP   NZ, probe_fail

    LD   IX, 0x1357
    LD   IY, 0x2468
    LD   A, 1
    CALL bdos_reset_disk_recover
    JP   C, probe_fail
    LD   (res_ix_post), IX
    LD   (res_iy_post), IY

    LD   C, BDOS_CURDSK
    LD   DE, 0
    CALL bdos_call
    LD   (res_curdsk), A

    LD   A, DAT_ID_HUFF_STREAM
    LD   DE, 2
    LD   HL, buf_rec2
    CALL dat_read_slot_record
    JP   C, probe_fail

    ; 7. Direct zero-LDIR 0xD080 path, 0xD081 non-overlap path, and .rsr_bad_rec
    LD   A, DAT_ID_HUFF_STREAM
    LD   DE, 1
    LD   HL, CPM_DMA_BUF_BASE
    CALL dat_read_slot_record
    JP   C, probe_fail
    LD   HL, CPM_DMA_BUF_BASE
    LD   DE, buf_dma_rec1
    LD   BC, 128
    LDIR

    LD   A, DAT_ID_HUFF_STREAM
    LD   DE, 3
    LD   HL, CPM_DMA_BUF_BASE + 1
    CALL dat_read_slot_record
    JP   C, probe_fail
    LD   HL, CPM_DMA_BUF_BASE + 1
    LD   DE, buf_dma_rec3
    LD   BC, 128
    LDIR

    LD   A, DAT_ID_HUFF_STREAM
    LD   DE, 250                ; out of range -> CF=1, A=0xFF, abi_last_bdos_err=0xFF
    LD   HL, buf_rec2
    CALL dat_read_slot_record
    JP   NC, probe_fail
    LD   (res_bad_rec_a), A
    LD   A, (abi_last_bdos_err)
    LD   (res_bad_rec_err), A

    LD   A, 0xAA
    LD   (res_ok), A
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL bdos_call

probe_fail:
    LD   A, 0xEE
    LD   (res_ok), A
    HALT

canary_bytes:
    DB   STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3
magic_bytes:
    DB   "M8Z0"

res_ok:         DB 0
res_mul_hl:     DW 0
res_mul_de:     DW 0
res_mul_bc:     DW 0
res_div1_q:     DW 0
res_div1_r:     DB 0
res_div2_q:     DW 0
res_div2_r:     DB 0
res_div0_q:     DW 0
len_dec_17164:  DB 0
len_dec_65535:  DB 0
len_dec_205:    DB 0
res_rng_u8:     DB 0
res_rng_1:      DB 0
res_rng_0:      DB 0
res_snd_off:    DB 0
res_snd_on:     DB 0
res_ix_post:    DW 0
res_iy_post:    DW 0
res_curdsk:     DB 0
res_bad_rec_a:  DB 0
res_bad_rec_err: DB 0
buf_dec_17164:  DS 8, 0
buf_dec_65535:  DS 8, 0
buf_dec_205:    DS 8, 0
buf_rng_10:     DS 32, 0
buf_huff_0a:    DS 82, 0
buf_huff_8:     DS 82, 0
buf_huff_19:    DS 82, 0
buf_huff_240:   DS 82, 0
buf_huff_0b:    DS 82, 0
buf_rec2:       DS 128, 0
buf_dma_rec1:   DS 128, 0
buf_dma_rec3:   DS 128, 0

    SAVEBIN "{probe_com}", RESIDENT_BASE, $ - RESIDENT_BASE
""",
            encoding="utf-8",
        )

        sproc = subprocess.run(
            [
                str(sjasmplus),
                "--nologo",
                f"-I{CPM_SRC_DIR}",
                f"-I{ROOT / 'core' / 'z80'}",
                f"-I{build_dir}",
                f"--sym={probe_sym}",
                str(probe_asm),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert sproc.returncode == 0, f"unit probe assembly failed:\n{sproc.stderr}"
        syms = _parse_sym_addrs(probe_sym)

        cli = ControlClient([
            str(runner),
            "--control",
            "--drive", f"A={drv_a}",
            "--drive", f"B={drv_b}",
            "--strict-drives",
            str(probe_com),
        ])
        try:
            cli.call({"cmd": "set_regs", "pc": syms["probe_start"], "sp": 0x8E00})
            res = cli.run_until_exit()
            assert res["exit_code"] == 0, f"unit probe failed exit: {res}"
            assert cli.read_mem(syms["res_ok"], 1) == b"\xAA", "probe reached probe_fail!"

            # Verify math
            assert struct.unpack("<H", cli.read_mem(syms["res_mul_hl"], 2))[0] == (0x0123 * 5)
            assert struct.unpack("<H", cli.read_mem(syms["res_mul_de"], 2))[0] == (0x0080 * 12)
            assert struct.unpack("<H", cli.read_mem(syms["res_mul_bc"], 2))[0] == (300 * 200)
            assert struct.unpack("<H", cli.read_mem(syms["res_div1_q"], 2))[0] == 300
            assert cli.read_mem(syms["res_div1_r"], 1)[0] == 0
            assert struct.unpack("<H", cli.read_mem(syms["res_div2_q"], 2))[0] == 327
            assert cli.read_mem(syms["res_div2_r"], 1)[0] == 135
            assert struct.unpack("<H", cli.read_mem(syms["res_div0_q"], 2))[0] == 0xFFFF

            # Verify numeric formatting
            assert cli.read_mem(syms["len_dec_17164"], 1)[0] == 5
            assert cli.read_mem(syms["buf_dec_17164"], 6) == b"17164\x00"
            assert cli.read_mem(syms["len_dec_65535"], 1)[0] == 5
            assert cli.read_mem(syms["buf_dec_65535"], 6) == b"65535\x00"
            assert cli.read_mem(syms["len_dec_205"], 1)[0] == 3
            assert cli.read_mem(syms["buf_dec_205"], 4) == b"205\x00"

            # Verify RNG
            assert cli.read_mem(syms["res_rng_1"], 1)[0] == 0
            assert cli.read_mem(syms["res_rng_0"], 1)[0] == 0
            rng10_vals = list(cli.read_mem(syms["buf_rng_10"], 32))
            assert all(0 <= v < 10 for v in rng10_vals), f"rng_range(10) out of bounds: {rng10_vals}"

            # Verify sound toggle & bell output (strictly two 0x07 bytes)
            assert cli.read_mem(syms["res_snd_off"], 1)[0] == 0
            assert cli.read_mem(syms["res_snd_on"], 1)[0] == 1
            out_info = cli.call({"cmd": "console_out"})
            assert out_info["hex"] == "0707", f"expected exactly two BEL bytes (0707), got {out_info['hex']}"

            # Verify Huffman boundary crossing + LRU eviction
            for sym_name, str_id in (
                ("buf_huff_0a", 0),
                ("buf_huff_8", 8),
                ("buf_huff_19", 19),
                ("buf_huff_240", 240),
                ("buf_huff_0b", 0),
            ):
                raw_s = cli.read_mem(syms[sym_name], 82)
                got_s = raw_s.split(b"\x00", 1)[0].decode("ascii")
                assert got_s == corpus[str_id], (
                    f"huffman[{str_id}] ({sym_name}) mismatch: {got_s!r} != {corpus[str_id]!r}"
                )

            # Verify bdos_reset_disk_recover (IX/IY preserved, B: preserved, DMA restored to 0xD080, A:MORIA8.DAT readable)
            assert struct.unpack("<H", cli.read_mem(syms["res_ix_post"], 2))[0] == 0x1357
            assert struct.unpack("<H", cli.read_mem(syms["res_iy_post"], 2))[0] == 0x2468
            assert cli.read_mem(syms["res_curdsk"], 1)[0] == 1
            assert cli.call({"cmd": "info"})["dma_addr"] == 0xD080
            assert cli.read_mem(syms["buf_rec2"], 128) == huff_stream[256:384]
            assert cli.read_mem(syms["buf_dma_rec1"], 128) == huff_stream[128:256]
            assert cli.read_mem(syms["buf_dma_rec3"], 128) == huff_stream[384:512]
            assert cli.read_mem(syms["res_bad_rec_a"], 1)[0] == 0xFF
            assert cli.read_mem(syms["res_bad_rec_err"], 1)[0] == 0xFF
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def _load_main_syms(build_dir: Path) -> dict[str, int]:
    sym_path = build_dir / "main.sym"
    if not sym_path.is_file():
        raise FileNotFoundError(f"Missing main.sym at {sym_path}")
    return _parse_sym_addrs(sym_path)


def _read_u24_player_gold(cli: ControlClient, syms: dict[str, int]) -> int:
    raw = cli.read_mem(syms["player_data"] + 43, 3)  # PL_GOLD_0..2
    return raw[0] | (raw[1] << 8) | (raw[2] << 16)


def _read_u16_sym(cli: ControlClient, syms: dict[str, int], name: str) -> int:
    return struct.unpack("<H", cli.read_mem(syms[name], 2))[0]


def _create_human_warrior(
    cli: ControlClient,
    name: str = "Hero",
    reroll: bool = False,
    female: bool = False,
    class_key: str = "a",
) -> None:
    cli.run_idle()
    cli.send_keys("N")
    cli.run_idle()
    assert cli.read_z80_state()["current_overlay"] == OVL_START

    # 1. Race: Human ('a')
    cli.send_keys("a")
    cli.run_idle()
    # 2. Roll stats (optional reroll) then Enter to accept
    if reroll:
        cli.send_keys("r")
        cli.run_idle()
    cli.send_keys("\r")
    cli.run_idle()
    # 3. Class
    cli.send_keys(class_key)
    cli.run_idle()
    # 4. Name
    cli.send_keys(name + "\r")
    cli.run_idle()
    # 5. Sex
    cli.send_keys("b" if female else "a")
    cli.run_idle()
    # 6. Character Info summary -> Space enters Town & game loop
    lines_info, _ = cli.screen_lines()
    assert "Character Info" in "\n".join(lines_info), (
        f"expected Character Info summary:\n" + "\n".join(lines_info)
    )
    cli.send_keys(" ")
    cli.run_idle()


def _assert_status_bar(lines: list[str], name: str, dlvl: int = 0, lvl: int = 1) -> None:
    """Assert rows 21..23 contain non-blank, accurate status bar fields."""
    assert name in lines[21] and f"LV:{lvl}" in lines[21] and f"DL:{dlvl}" in lines[21], (
        f"row 21 status bar bad/blank ({name!r}, LV:{lvl}, DL:{dlvl}):\n" + "\n".join(lines[20:24])
    )
    for stat_tok in ("ST:", "IN:", "WI:", "DX:", "CO:", "CH:"):
        assert stat_tok in lines[22], (
            f"row 22 missing {stat_tok!r}:\n" + "\n".join(lines[20:24])
        )
    for vit_tok in ("HP:", "MP:", "AC:", "AU:"):
        assert vit_tok in lines[23], (
            f"row 23 missing {vit_tok!r}:\n" + "\n".join(lines[20:24])
        )
    assert "EXP:" not in lines[23], f"unexpected EXP: in row 23:\n{lines[23]}"


def _walk_steps(cli: ControlClient, steps: str) -> None:
    for ch in steps:
        cli.send_keys(ch)
        cli.run_idle()


def _dismiss_more(cli: ControlClient, limit: int = 50) -> None:
    for _ in range(limit):
        if "-more-" not in "\n".join(cli.screen_lines()[0][:2]):
            return
        cli.send_keys(" ")
        cli.run_idle()


def _assert_valid_floor_items(
    cli: ControlClient,
    syms: dict[str, int],
    *,
    require_nonempty: bool = False,
    check_tile_flag: bool = False,
    label: str = "floor items",
) -> list[tuple[int, int, int, int]]:
    fi_ids = cli.read_mem(syms["fi_item_id"], 42)
    fi_xs = cli.read_mem(syms["fi_x"], 42)
    fi_ys = cli.read_mem(syms["fi_y"], 42)
    fi_his = cli.read_mem(syms["fi_meta_hi"], 42)
    items = [
        (idx, fi_xs[idx], fi_ys[idx], fi_ids[idx] + (255 if (fi_his[idx] & 0x40) else 0))
        for idx in range(42)
        if fi_ids[idx] != 0xFF
    ]
    if require_nonempty:
        assert items, f"{label}: expected at least one floor item"
    bad = [row for row in items if not (0 <= row[3] < 361)]
    assert not bad, f"{label}: out-of-range logical_id (>=361): {bad}"
    if check_tile_flag:
        bad_tiles = [row for row in items if (_get_map_tile(cli, row[1], row[2]) & 0x02) == 0]
        assert not bad_tiles, f"{label}: missing FLAG_HAS_ITEM on map tile for {bad_tiles}"
    return items


def _quit_game_and_title(cli: ControlClient) -> None:
    st_town = cli.read_z80_state()
    assert st_town["current_overlay"] == OVL_NONE and st_town["overlay_depth"] == 0, (
        f"expected unpinned Town (OVL_NONE, depth 0), got {st_town}"
    )
    cli.send_keys("QY")
    cli.run_idle()
    st_title = cli.read_z80_state()
    assert st_title["current_overlay"] == OVL_TITLE and st_title["overlay_depth"] == 1, (
        f"expected OVL_TITLE at depth 1, got {st_title}"
    )
    cli.send_keys("Q")
    fin = cli.run_until_exit()
    assert fin["exit_code"] == 0
    assert cli.read_stack_canary() == STACK_CANARY_BYTES


def _parse_store_listings(lines: list[str]) -> list[tuple[str, int, str]]:
    """Parse rows 3..18 in OVL_TOWN for (slot_letter, price_gp, line_text)."""
    items: list[tuple[str, int, str]] = []
    for row in lines[3:19]:
        m = re.match(r"^\s*([A-Pa-p])\)\s+.+?\s+(\d+)\s*(?:GP)?\s*$", row)
        if m:
            items.append((m.group(1).lower(), int(m.group(2)), row.strip()))
    return items


def _complete_store_haggle(cli: ControlClient, initial_price: int, target_msg: str) -> None:
    """Finish a store buy/sell either via Y/N prompt or asking/countering exact shopkeeper price."""
    for _ in range(10):
        lines, _ = cli.screen_lines()
        blob = "\n".join(lines)
        if target_msg in blob:
            return
        if "Buy? (Y/N)" in blob or "Sell? (Y/N)" in blob:
            cli.send_keys("y")
            cli.run_idle()
            continue
        m_num = (
            re.search(r"Final offer:\s*(\d+)\s*gp", blob)
            or re.search(r"How about\s+(\d+)\s*gp", blob)
            or re.search(r"(?:Asks|Offers)\s+(\d+)\s*gp", blob)
        )
        offer = int(m_num.group(1)) if m_num else initial_price
        cli.send_keys(f"{offer}\r")
        cli.run_idle()
    final_lines, _ = cli.screen_lines()
    raise AssertionError(f"failed to reach {target_msg!r} in store:\n" + "\n".join(final_lines))


def _kick_store_by_insults(cli: ControlClient, slot_letter: str) -> None:
    """Enter buy haggle on slot_letter and issue 1 gp insulting offers until kicked."""
    cli.send_keys("b" + slot_letter)
    cli.run_idle()
    kicked = False
    for _ in range(6):
        cli.send_keys("1\r")
        cli.run_idle()
        lines, _ = cli.screen_lines()
        blob = "\n".join(lines)
        if "Get out of my store!" in blob:
            cli.send_keys(" ")
            cli.run_idle()
            kicked = True
            break
        # Dismiss insult prompt before next 1 gp offer
        cli.send_keys(" ")
        cli.run_idle()
    assert kicked, "expected 'Get out of my store!' after 3 insulting offers"
    cli.send_keys("b" + slot_letter)
    cli.run_idle()
    rechk_lines, _ = cli.screen_lines()
    assert "Get out of my store!" in "\n".join(rechk_lines)
    cli.send_keys(" q")
    cli.run_idle()


def scenario_chargen_and_town_render(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Create Human Warrior in OVL_START, render 198x66 Town, verify buildings, depth=0 & hard-clear status bars."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Conan", reroll=True)

        st = cli.read_z80_state()
        assert st["current_overlay"] == OVL_NONE and st["overlay_depth"] == 0, (
            f"expected Town at OVL_NONE / depth 0, got {st}"
        )
        assert st["player_dlvl"] == 0, f"expected Town dlvl=0, got {st}"
        assert st["player_lvl"] == 1
        assert st["hp"] == st["mhp"] and st["hp"] > 0
        assert st["program_drive"] == 0
        assert st["save_drive"] == 0
        assert st["player_x"] == 31 and st["player_y"] == 18

        lines, _ = cli.screen_lines()
        blob = "\n".join(lines)
        _assert_status_bar(lines, "Conan")
        for bld in ("1", "2", "3", "4", "5", "6", "7", "8"):
            assert bld in blob, f"missing Town building '{bld}' on screen:\n{blob}"
        assert ">" in blob and "@" in blob, f"missing '>' stairs or '@' player:\n{blob}"

        # Check full 66x22 Town slice in MAP_BASE (upper-left inside 198x66 MAP_BASE)
        town_cells = bytearray()
        for row_idx in range(22):
            off = MAP_BASE_ADDR + row_idx * 198
            town_cells.extend(cli.read_mem(off, 66))
        # Verify stairs_dn tile (nibble 0x90) at (32, 18)
        stairs_tile = town_cells[18 * 66 + 32]
        assert (stairs_tile & 0xF0) == 0x90, f"expected TILE_STAIRS_DN (0x90) at (32,18), got {stairs_tile:#x}"
        # Verify player background in BSS is populated
        bg = cli.read_mem(syms["player_background"], 160).split(b"\x00", 1)[0]
        assert len(bg) > 0, "expected generated player_background text"

        # Verify status bar survives '=' 3-state cycle & 'v' Legal Viewer hard clears in Town
        cli.send_keys("=")
        cli.run_idle()
        st_col = cli.read_z80_state()
        assert st_col["term_mode"] == 1 and st_col["monochrome"] == 0
        col_lines, _ = cli.screen_lines()
        assert "Color mode." in col_lines[0]
        _assert_status_bar(col_lines, "Conan")

        cli.send_keys("=")
        cli.run_idle()
        st_mono = cli.read_z80_state()
        assert st_mono["term_mode"] == 1 and st_mono["monochrome"] == 1
        mono_lines, _ = cli.screen_lines()
        assert "Monochrome mode." in mono_lines[0]
        _assert_status_bar(mono_lines, "Conan")

        cli.send_keys("=")
        cli.run_idle()
        st_adm = cli.read_z80_state()
        assert st_adm["term_mode"] == 0 and st_adm["monochrome"] == 1
        adm_lines, _ = cli.screen_lines()
        assert "ADM-3A mode." in adm_lines[0]
        _assert_status_bar(adm_lines, "Conan")

        cli.send_keys("v")
        cli.run_idle()
        st_leg = cli.read_z80_state()
        assert st_leg["current_overlay"] == OVL_LEGAL and st_leg["overlay_depth"] == 1
        sys_town_blob = "\n".join(cli.screen_lines()[0])
        assert "Turn " in sys_town_blob and re.search(r"\$[0-9A-Fa-f]{8}", sys_town_blob), (
            f"SysInfo in Town missing session/RNG telemetry:\n{sys_town_blob}"
        )
        cli.send_keys("Q")
        cli.run_idle()
        leg_back_lines, _ = cli.screen_lines()
        _assert_status_bar(leg_back_lines, "Conan")

        _quit_game_and_title(cli)


def _probe_town_overlay_math(runner: Path, sjasmplus: Path, build_dir: Path) -> None:
    """Directly exercise ovl_town_mul24x8_in >= 65536/saturation and ovl_town_load_base_tool error fallback."""
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    ovl_town_bin = build_dir / "ovl_town.ovl"
    town_syms = _parse_sym_addrs(build_dir / "ovl_town.sym")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        drv_a = tmp / "drive_a"
        drv_a.mkdir()
        shutil.copy2(dat_src, drv_a / "MORIA8.DAT")

        probe_asm = tmp / "town_probe.asm"
        probe_com = tmp / "TOWNPRB.COM"
        probe_sym = tmp / "townprb.sym"
        probe_asm.write_text(
            f"""    DEVICE NOSLOT64K
    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    INCLUDE "main_exp.inc"

    ORG  RESIDENT_BASE
    INCBIN "{com_src.resolve()}"
    ASSERT $ <= OVL_WINDOW_BASE
    DS   OVL_WINDOW_BASE - $, 0
    ORG  OVL_WINDOW_BASE
    INCBIN "{ovl_town_bin.resolve()}"
    ASSERT $ <= 0x6A00
    DS   MAP_BASE - $, 0

    ORG  MAP_BASE
town_probe_start:
    LD   SP, STACK_TOP
    LD   HL, tp_canary
    LD   DE, STACK_CANARY_ADDR
    LD   BC, STACK_CANARY_LEN
    LDIR

    LD   HL, BSS_BASE
    LD   DE, BSS_BASE + 1
    LD   BC, bss_end - BSS_BASE - 1
    LD   (HL), 0
    LDIR

    LD   HL, tp_magic
    LD   DE, z80_state
    LD   BC, 4
    LDIR
    LD   A, Z80_ABI_VERSION_NUM
    LD   (z80_state + Z80_ABI_VERSION), A
    XOR  A
    LD   (abi_program_drive), A

    CALL bdos_reset_dma_default
    CALL dat_init
    JP   C, tp_fail
    CALL icat_init

    ; 1. ovl_town_mul24x8_in: 0x010000 * 3 -> 0x030000
    LD   B, 0x01
    LD   HL, 0x0000
    LD   A, 3
    CALL 0x{town_syms["ovl_town_mul24x8_in"]:04X}
    LD   (res_mul1_hl), HL
    LD   A, E
    LD   (res_mul1_e), A

    ; 2. ovl_town_mul24x8_in: 0x0186A0 * 10 -> 0x0F4240 (1,000,000)
    LD   B, 0x01
    LD   HL, 0x86A0
    LD   A, 10
    CALL 0x{town_syms["ovl_town_mul24x8_in"]:04X}
    LD   (res_mul2_hl), HL
    LD   A, E
    LD   (res_mul2_e), A

    ; 3. ovl_town_mul24x8_in saturation (H != 0): 0x400000 * 10 -> 0xFFFFFF
    LD   B, 0x40
    LD   HL, 0x0000
    LD   A, 10
    CALL 0x{town_syms["ovl_town_mul24x8_in"]:04X}
    LD   (res_mul3_hl), HL
    LD   A, E
    LD   (res_mul3_e), A

    ; 4. ovl_town_mul24x8_in saturation (ADD A, L carry): 0x19A000 * 10 -> 0xFFFFFF
    LD   B, 0x19
    LD   HL, 0xA000
    LD   A, 10
    CALL 0x{town_syms["ovl_town_mul24x8_in"]:04X}
    LD   (res_mul4_hl), HL
    LD   A, E
    LD   (res_mul4_e), A

    ; 5. ovl_town_load_base_tool baseline (Dagger, ego=0, flags=0)
    LD   A, ITEM_SLOT_DAGGER
    LD   (0x{town_syms["ovl_town_item_id"]:04X}), A
    LD   A, ITEM_PAGE_DAGGER
    LD   (0x{town_syms["ovl_town_item_ego"]:04X}), A
    XOR  A
    LD   (0x{town_syms["ovl_town_item_flags"]:04X}), A
    CALL 0x{town_syms["ovl_town_load_base_tool"]:04X}
    LD   HL, 0x{town_syms["ovl_town_base24"]:04X}
    LD   DE, res_base_plain
    LD   BC, 3
    LDIR

    ; 6. ovl_town_load_base_tool error fallback: identified ego 2 (1 <= 2 < EGO_TYPE_COUNT)
    ;    with uncached ITMCAT_OFF_EGOS faulted (FCB_DAT_ADDR = 16 = unmounted P:) -> icat_get_ego
    ;    leaves E != 0 (LOW(ITMCAT_OFF_EGOS) = 0x47) and returns CF=1, so ovl_town_load_base_tool
    ;    must reset base24+2 to 0.
    LD   A, 16
    LD   (FCB_DAT_ADDR), A
    LD   A, 2
    CALL icat_get_ego
    JR   NC, .ego_probe_done
    LD   A, E
    OR   A
    JR   Z, .ego_probe_done
    LD   A, 1
    LD   (res_ego_err_cf), A
.ego_probe_done:
    LD   A, ITEM_PAGE_DAGGER | 2
    LD   (0x{town_syms["ovl_town_item_ego"]:04X}), A
    LD   A, IF_IDENTIFIED
    LD   (0x{town_syms["ovl_town_item_flags"]:04X}), A
    CALL 0x{town_syms["ovl_town_load_base_tool"]:04X}
    LD   HL, 0x{town_syms["ovl_town_base24"]:04X}
    LD   DE, res_base_err
    LD   BC, 3
    LDIR
    LD   A, (abi_program_drive)
    INC  A
    LD   (FCB_DAT_ADDR), A

    ; 7. ovl_town_load_base_tool unidentified ego fallback: ego=1, flags=0, must clear base24+2
    LD   A, ITEM_PAGE_DAGGER | 1
    LD   (0x{town_syms["ovl_town_item_ego"]:04X}), A
    XOR  A
    LD   (0x{town_syms["ovl_town_item_flags"]:04X}), A
    LD   DE, 0xAA55
    CALL 0x{town_syms["ovl_town_load_base_tool"]:04X}
    LD   HL, 0x{town_syms["ovl_town_base24"]:04X}
    LD   DE, res_base_unid
    LD   BC, 3
    LDIR

    LD   A, 0xAA
    LD   (res_tp_ok), A
    JR   tp_exit

tp_fail:
    LD   A, 0xEE
    LD   (res_tp_ok), A
tp_exit:
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL bdos_call
    JP   CPM_WARM_BOOT

tp_canary:      DB STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3
tp_magic:       DB "M8Z0"
res_tp_ok:      DB 0
res_mul1_hl:    DW 0
res_mul1_e:     DB 0
res_mul2_hl:    DW 0
res_mul2_e:     DB 0
res_mul3_hl:    DW 0
res_mul3_e:     DB 0
res_mul4_hl:    DW 0
res_mul4_e:     DB 0
res_base_plain: DS 3, 0xFF
res_base_err:   DS 3, 0xFF
res_base_unid:  DS 3, 0xFF
res_ego_err_cf: DB 0
    ASSERT $ <= 0xD000

    SAVEBIN "{probe_com}", RESIDENT_BASE, $ - RESIDENT_BASE
""",
            encoding="utf-8",
        )
        sproc = subprocess.run(
            [
                str(sjasmplus), "--nologo",
                f"-I{CPM_SRC_DIR}", f"-I{ROOT / 'core' / 'z80'}", f"-I{build_dir}",
                f"--sym={probe_sym}", str(probe_asm),
            ],
            capture_output=True, text=True, check=False,
        )
        assert sproc.returncode == 0, f"town_probe assembly failed:\n{sproc.stderr}"
        psyms = _parse_sym_addrs(probe_sym)

        cli = ControlClient([
            str(runner), "--control",
            "--drive", f"A={drv_a}", "--strict-drives",
            str(probe_com),
        ])
        try:
            cli.call({"cmd": "set_regs", "pc": psyms["town_probe_start"], "sp": 0x8E00})
            assert cli.run_until_exit()["exit_code"] == 0
            assert cli.read_mem(psyms["res_tp_ok"], 1) == b"\xAA", "town probe failed!"

            def _u24(hl_name: str, e_name: str) -> int:
                lo = struct.unpack("<H", cli.read_mem(psyms[hl_name], 2))[0]
                hi = cli.read_mem(psyms[e_name], 1)[0]
                return lo | (hi << 16)

            assert _u24("res_mul1_hl", "res_mul1_e") == 0x030000
            assert _u24("res_mul2_hl", "res_mul2_e") == 0x0F4240
            assert _u24("res_mul3_hl", "res_mul3_e") == 0xFFFFFF
            assert _u24("res_mul4_hl", "res_mul4_e") == 0xFFFFFF

            base_plain = cli.read_mem(psyms["res_base_plain"], 3)
            base_err = cli.read_mem(psyms["res_base_err"], 3)
            base_unid = cli.read_mem(psyms["res_base_unid"], 3)
            ego_err_cf = cli.read_mem(psyms["res_ego_err_cf"], 1)[0]
            assert ego_err_cf == 1, f"expected real icat_get_ego(2) CF=1 with E!=0 under faulted FCB_DAT, got {ego_err_cf}"
            assert base_plain[2] == 0 and base_plain[:2] != b"\x00\x00"
            assert base_err == base_plain, f"icat_get_ego CF=1 leaked E: {base_err!r} != {base_plain!r}"
            assert base_unid == base_plain, f"unidentified ego leaked E: {base_unid!r} != {base_plain!r}"
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def scenario_town_store_buy_sell(
    runner: Path, _runcpm: Path, sjasmplus: Path, build_dir: Path
) -> None:
    """Test General Store buy/sell, no-redraw invalid/empty bell, ovl_town 24-bit/ego math, Armory cmp24/category/3-insult kick, Black Market & Ctrl-P."""
    _probe_town_overlay_math(runner, sjasmplus, build_dir)
    syms = _load_main_syms(build_dir)
    town_syms = _parse_sym_addrs(build_dir / "ovl_town.sym")
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Trader")
        _clear_all_monsters(cli, syms)
        gold0 = _read_u24_player_gold(cli, syms)
        wt0 = _read_u16_sym(cli, syms, "inven_weight_lo")

        # Walk from (31, 18) east onto open aisle x=32, up to y=10 avenue, west to x=15, north to '1' at (15, 6)
        _walk_steps(cli, "l" + "k" * 8 + "h" * 17 + "k" * 4)
        st = cli.read_z80_state()
        assert st["current_overlay"] == OVL_TOWN and st["overlay_depth"] == 1, (
            f"expected OVL_TOWN ({OVL_TOWN}, depth 1) at (15,6), got {st}"
        )

        store_lines, _ = cli.screen_lines()
        assert "General Store" in "\n".join(store_lines), (
            f"expected General Store at (15,6):\n" + "\n".join(store_lines)
        )

        # Invalid key in store is silently ignored without changing screen
        cli.send_keys("z")
        cli.run_idle()
        assert cli.screen_lines()[0] == store_lines

        # Buy ('b') prompt: invalid key ('z') & empty slot cancel cleanly back to store menu
        gen_si = list(cli.read_mem(syms["si_item_id"], 16))
        cli.send_keys("b")
        cli.run_idle()
        buy_prompt_lines, _ = cli.screen_lines()
        assert "Buy which item? (a-p)" in "\n".join(buy_prompt_lines)
        cli.send_keys("z")
        cli.run_idle()
        assert cli.screen_lines()[0] == store_lines
        tested_empty_buy = False
        if 0xFF in gen_si:
            empty_buy_key = chr(ord("a") + gen_si.index(0xFF))
            cli.send_keys("b" + empty_buy_key)
            cli.run_idle()
            assert cli.screen_lines()[0] == store_lines
            tested_empty_buy = True

        # Sell ('s') prompt: opens "Sell Items", invalid key ('z') & empty slot ('v') cancel cleanly
        assert cli.read_mem(syms["inv_item_id"] + 21, 1)[0] == 0xFF
        cli.send_keys("s")
        cli.run_idle()
        sell_prompt_lines, _ = cli.screen_lines()
        assert "Sell which item? (a-v)" in "\n".join(sell_prompt_lines)
        cli.send_keys("z")
        cli.run_idle()
        assert cli.screen_lines()[0] == store_lines
        cli.send_keys("sv")
        cli.run_idle()
        assert cli.screen_lines()[0] == store_lines

        listings = _parse_store_listings(store_lines)
        assert listings, f"General Store has no item listings:\n" + "\n".join(store_lines)
        listings.sort(key=lambda item: item[1])
        pick_letter, pick_price, _ = listings[0]
        assert pick_price <= gold0, f"cheapest store item {pick_price} gp > gold {gold0} gp"

        inv_before = list(cli.read_mem(syms["inv_qty"], 22))
        total_qty_before = sum(inv_before[i] for i in range(22) if cli.read_mem(syms["inv_item_id"] + i, 1)[0] != 0xFF)

        cli.send_keys("b" + pick_letter)
        cli.run_idle()
        _complete_store_haggle(cli, pick_price, "Bought!")

        gold_after_buy = _read_u24_player_gold(cli, syms)
        wt_after_buy = _read_u16_sym(cli, syms, "inven_weight_lo")
        inv_after = list(cli.read_mem(syms["inv_qty"], 22))
        total_qty_after = sum(inv_after[i] for i in range(22) if cli.read_mem(syms["inv_item_id"] + i, 1)[0] != 0xFF)
        assert gold_after_buy < gold0, f"gold did not decrease on buy: {gold0} -> {gold_after_buy}"
        assert total_qty_after > total_qty_before, f"inventory qty did not grow: {total_qty_before} -> {total_qty_after}"
        assert wt_after_buy > wt0, f"inventory weight did not increase: {wt0} -> {wt_after_buy}"

        # Sell starting Food Ration (slot 'a') back to General Store ("Sold!" waits for keypress)
        cli.send_keys("sa")
        cli.run_idle()
        _complete_store_haggle(cli, 3, "Sold!")
        cli.send_keys(" ")
        cli.run_idle()
        assert _read_u24_player_gold(cli, syms) > gold_after_buy

        # Exit General Store -> verify status bar & depth=0
        cli.send_keys("q")
        cli.run_idle()
        town_after_gen, _ = cli.screen_lines()
        _assert_status_bar(town_after_gen, "Trader")

        # Give player an identified Plate Mail (ID=232, base cost >= 256 gp) in first empty slot
        inv_ids = list(cli.read_mem(syms["inv_item_id"], 22))
        pm_idx = inv_ids.index(0xFF)
        pm_letter = chr(ord("a") + pm_idx)
        cli.write_mem(syms["inv_item_id"] + pm_idx, b"\xE8")  # ITEM_SLOT_PLATE_MAIL (232)
        cli.write_mem(syms["inv_qty"] + pm_idx, b"\x01")
        cli.write_mem(syms["inv_to_ac"] + pm_idx, b"\x05")    # +5 AC raises offer cleanly >= 256 gp
        cli.write_mem(syms["inv_flags"] + pm_idx, b"\x02")    # IF_IDENTIFIED

        # Walk from (15, 6) -> (15, 7) -> (27, 7) -> (27, 6) into Armory '2'
        _walk_steps(cli, "j" + "l" * 12 + "k")
        assert cli.read_z80_state()["current_overlay"] == OVL_TOWN
        arm_lines, _ = cli.screen_lines()
        assert "Armory" in "\n".join(arm_lines), f"expected Armory at (27,6):\n" + "\n".join(arm_lines)

        if not tested_empty_buy:
            arm_si = list(cli.read_mem(syms["si_item_id"] + 16, 16))
            assert 0xFF in arm_si, "expected at least one empty store slot in General Store or Armory"
            cli.send_keys("b" + chr(ord("a") + arm_si.index(0xFF)))
            cli.run_idle()
            assert cli.screen_lines()[0] == arm_lines
            tested_empty_buy = True

        # Wrong-category sell guard: Food Ration ('a') rejected by Armory
        cli.send_keys("sa")
        cli.run_idle()
        arm_cat_lines, _ = cli.screen_lines()
        assert "We don't buy that." in "\n".join(arm_cat_lines)
        cli.send_keys(" ")
        cli.run_idle()

        # >=256 gp sell offering 50 gp (ovl_town_cmp24 OR B check) + 5-digit <=65535 live clamp (70000 -> 7000)
        gold_pre_cmp = _read_u24_player_gold(cli, syms)
        cli.send_keys("s" + pm_letter)
        cli.run_idle()
        pm_sell_lines, _ = cli.screen_lines()
        m_pm_off = re.search(r"Offers\s+(\d+)\s+gp", "\n".join(pm_sell_lines))
        assert m_pm_off and int(m_pm_off.group(1)) >= 256, (
            f"expected >=256 gp Armory offer for Plate Mail:\n" + "\n".join(pm_sell_lines)
        )
        armory_pm_offer = int(m_pm_off.group(1))
        cli.send_keys("50\r")
        cli.run_idle()
        cmp_sell_lines, _ = cli.screen_lines()
        assert "WHAT WAS THAT?" in "\n".join(cmp_sell_lines), (
            f"expected 50 gp counter on >=256 gp offer to reject:\n" + "\n".join(cmp_sell_lines)
        )
        assert _read_u24_player_gold(cli, syms) == gold_pre_cmp
        # Dismiss retry -> enter 70000 gp offer -> live <=65535 check rejects final '0' -> 7000, triggers insult
        cli.send_keys(" ")
        cli.run_idle()
        cli.send_keys("70000\r")
        cli.run_idle()
        hg_raw = cli.read_mem(town_syms["ovl_town_hg_input"], 3)
        hg_val = hg_raw[0] | (hg_raw[1] << 8) | (hg_raw[2] << 16)
        assert hg_val == 7000, f"expected <=65535 live clamp 70000 -> 7000, got {hg_val} (0x{hg_val:06X})"
        cmp_7d_lines, _ = cli.screen_lines()
        assert cmp_7d_lines[23].strip(), f"expected insult line on row 23:\n" + "\n".join(cmp_7d_lines)
        assert _read_u24_player_gold(cli, syms) == gold_pre_cmp
        cli.send_keys(" Q")
        cli.run_idle()

        # <256 gp buy offering 300 gp & 70000->7000 gp (ovl_town_cmp24 OR B check + <=65535 clamp) + 3-insult kick
        arm_listings = _parse_store_listings(arm_lines)
        sub256 = [it for it in arm_listings if 11 <= it[1] < 256]
        if sub256:
            lt_sub, pr_sub, _ = sub256[0]
            cli.send_keys("b" + lt_sub)
            cli.run_idle()
            cli.send_keys("300\r")
            cli.run_idle()
            cmp_buy_lines, _ = cli.screen_lines()
            assert "WHAT WAS THAT?" in "\n".join(cmp_buy_lines), (
                f"expected 300 gp offer on {pr_sub} gp item to reject:\n" + "\n".join(cmp_buy_lines)
            )
            cli.send_keys(" ")
            cli.run_idle()
            cli.send_keys("70000\r")
            cli.run_idle()
            hg_buy_raw = cli.read_mem(town_syms["ovl_town_hg_input"], 3)
            hg_buy_val = hg_buy_raw[0] | (hg_buy_raw[1] << 8) | (hg_buy_raw[2] << 16)
            assert hg_buy_val == 7000, (
                f"expected <=65535 live clamp 70000 -> 7000, got {hg_buy_val} (0x{hg_buy_val:06X})"
            )
            cmp_buy7_lines, _ = cli.screen_lines()
            assert "WHAT WAS THAT?" in "\n".join(cmp_buy7_lines)
            assert _read_u24_player_gold(cli, syms) == gold_pre_cmp
            cli.send_keys(" Q")
            cli.run_idle()

        # Insult Armory keeper 3 times -> "Get out of my store!" + hg_kicked[1] > 0 -> exit back to Town
        gt10 = [it for it in arm_listings if it[1] > 10]
        _kick_store_by_insults(cli, gt10[0][0])
        assert cli.read_z80_state()["current_overlay"] == OVL_NONE
        assert cli.read_mem(syms["hg_kicked"] + 1, 1)[0] > 0
        town_after_kick, _ = cli.screen_lines()
        _assert_status_bar(town_after_kick, "Trader")

        # Reset Plate Mail +AC to 0 before Black Market so exact base/10 == 105 gp applies
        cli.write_mem(syms["inv_to_ac"] + pm_idx, b"\x00")

        # Walk from (27, 6) -> (27, 7) -> (32, 7) -> (32, 17) -> (39, 17) -> (39, 16) into Black Market '7'
        # Clear any MON-039 ambient wanderer spawned during earlier store haggling before blind _walk_steps.
        _clear_all_monsters(cli, syms)
        # Also verify 24-bit carry across 65,536 GP in ovl_town_add_p1_bonus on Black Market slot 0
        bm_slot0 = 6 * 16
        cli.write_mem(syms["si_item_id"] + bm_slot0, bytes([93]))      # Amulet of the Magi (Page 1)
        cli.write_mem(syms["si_qty"] + bm_slot0, b"\x01")
        cli.write_mem(syms["si_p1"] + bm_slot0, bytes([127]))
        cli.write_mem(syms["si_meta"] + bm_slot0, b"\x02")
        cli.write_mem(syms["si_to_hit"] + bm_slot0, bytes([127]))
        cli.write_mem(syms["si_to_dam"] + bm_slot0, bytes([127]))
        cli.write_mem(syms["si_to_ac"] + bm_slot0, bytes([127]))
        cli.write_mem(syms["si_meta_hi"] + bm_slot0, b"\x40")    # Page 1 -> base*3 + 50800 > 65535
        _walk_steps(cli, "j" + "l" * 5 + "j" * 10 + "l" * 7 + "k")
        assert cli.read_z80_state()["current_overlay"] == OVL_TOWN
        bm_lines, _ = cli.screen_lines()
        assert "Black Market" in "\n".join(bm_lines), (
            f"expected Black Market at (39,16):\n" + "\n".join(bm_lines)
        )
        bm_listings = _parse_store_listings(bm_lines)
        assert any(it[0] == "a" and it[1] > 65535 for it in bm_listings), (
            f"ovl_town_add_p1_bonus dropped >65535 GP carry on Black Market slot 'a': {bm_listings}"
        )
        # Black Market /10 sell check: Plate Mail [25,+0] (base 1050) must offer 105 gp (<= 1/4 of Armory)
        cli.send_keys("s" + pm_letter)
        cli.run_idle()
        bm_sell_lines, _ = cli.screen_lines()
        m_bm = re.search(r"(?:Offers|Offer:)\s*(\d+)\s*gp", "\n".join(bm_sell_lines))
        assert m_bm and int(m_bm.group(1)) == 105 and int(m_bm.group(1)) < armory_pm_offer, (
            f"expected Black Market base/10 (105 gp) offer vs Armory {armory_pm_offer}:\n" + "\n".join(bm_sell_lines)
        )
        if "Sell? (Y/N)" in "\n".join(bm_sell_lines):
            cli.send_keys("z")
        else:
            cli.send_keys("Q")
        cli.run_idle()

        # Exit Black Market -> test status bar + '>' + msg_history ring buffer
        cli.send_keys("q")
        cli.run_idle()
        town_after_bm, _ = cli.screen_lines()
        _assert_status_bar(town_after_bm, "Trader")
        cli.send_keys(">")
        cli.run_idle()
        hist_mem = cli.read_mem(syms["msg_history"], 8 * 80)
        assert b"You see no stairs here." in hist_mem, (
            f"expected stairs message in msg_history ring buffer: {hist_mem!r}"
        )

        # Verify Weaponsmith (store 2) & Magic Shop (store 5) generate diverse category stock (ovl_town_check_cat preserves DE)
        # Black Market at (39, 16) -> Magic Shop at (27, 16) -> Weaponsmith at (39, 6)
        _clear_all_monsters(cli, syms)
        _walk_steps(cli, "j" + "h" * 12 + "k")
        assert cli.read_z80_state()["current_overlay"] == OVL_TOWN
        mag_lines, _ = cli.screen_lines()
        mag_blob = "\n".join(mag_lines)
        assert "Magic Shop" in mag_blob, f"expected Magic Shop at (27,16):\n{mag_blob}"
        mag_listings = _parse_store_listings(mag_lines)
        mag_si = list(cli.read_mem(syms["si_item_id"] + 5 * 16, 16))
        mag_ego = list(cli.read_mem(syms["si_meta_hi"] + 5 * 16, 16))
        mag_distinct = {(mag_si[i], mag_ego[i]) for i in range(16) if mag_si[i] != 0xFF}
        assert len(mag_distinct) >= 3 and "Leather Gloves" not in mag_blob and mag_listings, (
            f"Magic Shop generated degenerate stock (DE clobbered?): distinct={mag_distinct}\n{mag_blob}"
        )
        cli.send_keys("q")
        cli.run_idle()

        _clear_all_monsters(cli, syms)
        _walk_steps(cli, "j" + "l" * 5 + "k" * 10 + "l" * 7 + "k")
        assert cli.read_z80_state()["current_overlay"] == OVL_TOWN
        wep_lines, _ = cli.screen_lines()
        wep_blob = "\n".join(wep_lines)
        assert "Weaponsmith" in wep_blob, f"expected Weaponsmith at (39,6):\n{wep_blob}"
        wep_listings = _parse_store_listings(wep_lines)
        wep_si = list(cli.read_mem(syms["si_item_id"] + 2 * 16, 16))
        wep_ego = list(cli.read_mem(syms["si_meta_hi"] + 2 * 16, 16))
        wep_distinct = {(wep_si[i], wep_ego[i]) for i in range(16) if wep_si[i] != 0xFF}
        assert len(wep_distinct) >= 3 and "Leather Gloves" not in wep_blob and wep_listings, (
            f"Weaponsmith generated degenerate stock (DE clobbered?): distinct={wep_distinct}\n{wep_blob}"
        )
        cli.send_keys("q")
        cli.run_idle()

        _quit_game_and_title(cli)


def scenario_town_home_deposit_withdraw(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Walk to Home '8', deposit pack slot 'a', exit & re-enter Home, withdraw back, verify status bar."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Keeper")
        _clear_all_monsters(cli, syms)
        orig_id = cli.read_mem(syms["inv_item_id"], 1)[0]
        orig_qty = cli.read_mem(syms["inv_qty"], 1)[0]
        assert orig_id != 0xFF and orig_qty >= 1

        # Walk from (31, 18) -> (51, 18) -> (51, 16) into Home '8'
        _walk_steps(cli, "l" * 20 + "k" * 2)
        st_h = cli.read_z80_state()
        assert st_h["current_overlay"] == OVL_HOME and st_h["overlay_depth"] == 1
        home0, _ = cli.screen_lines()
        assert "Home" in "\n".join(home0)

        # Deposit slot 'a'
        cli.send_keys("da")
        cli.run_idle()
        home1, _ = cli.screen_lines()
        assert "Deposited!" in "\n".join(home1), f"deposit failed:\n" + "\n".join(home1)

        home_base_slot = 7 * 16
        assert cli.read_mem(syms["si_item_id"] + home_base_slot, 1)[0] == orig_id
        assert cli.read_mem(syms["si_qty"] + home_base_slot, 1)[0] == orig_qty

        # Exit Home -> verify depth 0 + status bar -> re-enter Home to verify persistence
        cli.send_keys("q")
        cli.run_idle()
        town_h1, _ = cli.screen_lines()
        _assert_status_bar(town_h1, "Keeper")
        _walk_steps(cli, "jk")
        assert cli.read_z80_state()["current_overlay"] == OVL_HOME
        home2, _ = cli.screen_lines()
        assert "a)" in "\n".join(home2)

        # Withdraw slot 'a' back cleanly
        cli.send_keys("ra")
        cli.run_idle()
        home3, _ = cli.screen_lines()
        home3_blob = "\n".join(home3)
        assert "Retrieved!" in home3_blob, f"withdraw failed:\n{home3_blob}"
        assert cli.read_mem(syms["si_item_id"] + home_base_slot, 1)[0] == 0xFF

        cli.send_keys("q")
        cli.run_idle()
        town_h2, _ = cli.screen_lines()
        _assert_status_bar(town_h2, "Keeper")
        _quit_game_and_title(cli)


def scenario_save_v2_roundtrip_and_checksum(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Verify atomic Save V2 stream, .TMP abort preservation, corrupt reject, same-session & cold reload."""
    syms = _load_main_syms(build_dir)
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"

    with tempfile.TemporaryDirectory() as td:
        workdir = Path(td)
        shutil.copy2(com_src, workdir / "MORIA8.COM")
        shutil.copy2(dat_src, workdir / "MORIA8.DAT")

        # 1. Start Character A ("Saver"), move, save SAVE0.SAV, test atomic fail & same-session Load
        cli1 = ControlClient([
            str(runner), "--control", "--workdir", str(workdir), str(workdir / "MORIA8.COM"),
        ])
        try:
            _create_human_warrior(cli1, name="Saver")
            _walk_steps(cli1, "k5")
            pre_st = cli1.read_z80_state()
            pre_gold = _read_u24_player_gold(cli1, syms)
            pre_wt = _read_u16_sym(cli1, syms, "inven_weight_lo")
            pre_wield_wt = _read_u16_sym(cli1, syms, "wield_weight_lo")
            assert pre_wt > 0 and pre_wield_wt > 0, (
                f"expected initialized inven/wield weights on New Game: wt={pre_wt}, wield_wt={pre_wield_wt}"
            )
            pre_inv = cli1.read_mem(syms["inv_item_id"], 272)
            pre_stores = cli1.read_mem(syms["si_item_id"], 1024)
            pre_map = cli1.read_mem(MAP_BASE_ADDR, MAP_SIZE_BYTES)
            pre_pbg = cli1.read_mem(syms["player_background"], 160)

            # S -> select slot 1 -> SAVE0.SAV (Save & Quit returns to Title)
            cli1.send_keys("S")
            cli1.run_idle()
            st_sv = cli1.read_z80_state()
            assert st_sv["current_overlay"] == OVL_STORAGE and st_sv["overlay_depth"] == 1
            cli1.send_keys("1")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE, (
                f"expected S save-and-quit to return to Title: {cli1.read_z80_state()}"
            )
            assert list(workdir.glob("*.TMP")) == [], "stale .TMP files remain after save"

            # Verify on-disk SAVE0.SAV binary format & trailing 16-bit additive checksum
            save_path = workdir / "SAVE0.SAV"
            assert save_path.is_file(), "SAVE0.SAV was not created"
            valid_raw = save_path.read_bytes()
            assert len(valid_raw) == SAVE_SLOT_RECORDS * SAVE_RECORD_BYTES, (
                f"expected {SAVE_SLOT_RECORDS * SAVE_RECORD_BYTES} B (135 CP/M recs), got {len(valid_raw)}"
            )
            payload = valid_raw[:SAVE_STREAM_BYTES]
            assert len(payload) == SAVE_STREAM_BYTES
            assert valid_raw[SAVE_STREAM_BYTES:] == b"\x00" * (
                SAVE_SLOT_RECORDS * SAVE_RECORD_BYTES - SAVE_STREAM_BYTES
            ), "expected clean zero-padding in final CP/M record"
            assert payload[:7] == b"MORIA01" and payload[7] == SAVE_VERSION_BYTE
            expected_cksum = sum(payload[: SAVE_STREAM_BYTES - 2]) & 0xFFFF
            stored_cksum = struct.unpack_from("<H", payload, SAVE_STREAM_BYTES - 2)[0]
            assert stored_cksum == expected_cksum, (
                f"Save V2 checksum mismatch: stored={stored_cksum:#06x} != calc={expected_cksum:#06x}"
            )

            # Reload slot 1 from Title to test atomic failure guard inside gameplay
            cli1.send_keys("L1")
            cli1.run_idle()
            _assert_status_bar(cli1.screen_lines()[0], "Saver")

            # Atomic failure guard: blocking directory SAVE0.TMP fails BDOS 22 -> SAVE0.SAV intact!
            tmp_blocker = workdir / "SAVE0.TMP"
            tmp_blocker.mkdir()
            cli1.send_keys("S1y")
            cli1.run_idle()
            err_save_lines, _ = cli1.screen_lines()
            assert "Disk is full." in "\n".join(err_save_lines), (
                f"expected atomic write error prompt:\n" + "\n".join(err_save_lines)
            )
            cli1.send_keys(" ")
            cli1.run_idle()
            _assert_status_bar(cli1.screen_lines()[0], "Saver")
            assert save_path.read_bytes() == valid_raw, "failed save corrupted prior SAVE0.SAV!"
            tmp_blocker.rmdir()

            # Save slot 2 (SAVE1.SAV) with PLF_SEARCHING (0x10), zp_search_count=5, and zp_run_dir = 2 to verify load normalization
            cur_plf = cli1.read_mem(syms["player_data"] + 54, 1)[0]
            cli1.write_mem(syms["player_data"] + 54, bytes([cur_plf | 0x10]))
            _write_mem(cli1, syms["zp_search_count"], [5])
            cli1.write_mem(syms["zp_run_dir"], b"\x02")
            cli1.send_keys("S2")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE
            assert cli1.read_mem(syms["zp_search_count"], 1)[0] == 0, "zp_search_count not cleared on save"
            assert list(workdir.glob("*.TMP")) == []

            # Reload slot 2, then save slot 3 (SAVE2.SAV) at 118 STR cap + Ring of Strength +5
            cli1.send_keys("L2")
            cli1.run_idle()
            cli1.write_mem(syms["player_data"] + 54, bytes([cur_plf]))
            _write_mem(cli1, syms["player_data"] + 21, [118])
            _write_mem(cli1, syms["player_data"] + 27, [118])
            _set_inv_item(cli1, syms, 29, 54, qty=1, p1=5, flags=0x02, ego=0x40)
            cli1.send_keys("S3")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE
            assert list(workdir.glob("*.TMP")) == []

            # Reload slot 2, then save slot 4 (SAVE3.SAV) at base=3 + cursed Ring of Weakness (-2) -> res=0xFE (-2)
            cli1.send_keys("L2")
            cli1.run_idle()
            cli1.write_mem(syms["player_data"] + 54, bytes([cur_plf]))
            _write_mem(cli1, syms["player_data"] + 21, [3])
            _write_mem(cli1, syms["player_data"] + 27, [3])
            _write_mem(cli1, syms["player_stat_res"], [0])
            _set_inv_item(cli1, syms, 29, 67, qty=1, p1=(-2) & 0xFF, flags=0x02, ego=0x40)
            cli1.send_keys("S4")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE
            assert list(workdir.glob("*.TMP")) == []

            # Already at Title -> create Char B ("Other", Mage) at same LV:1 DL:0 -> kick Armory -> same-session Load Char A
            _create_human_warrior(cli1, name="Other", class_key="b")
            _clear_all_monsters(cli1, syms)
            char_b_lines, _ = cli1.screen_lines()
            _assert_status_bar(char_b_lines, "Other")

            # Walk Char B to Armory '2' (27, 6) and kick it via 3 insults (hg_kicked[1] != 0)
            _walk_steps(cli1, "l" + "k" * 8 + "h" * 5 + "k" * 4)
            assert cli1.read_z80_state()["current_overlay"] == OVL_TOWN
            arm_b_lines, _ = cli1.screen_lines()
            gt10_b = [it for it in _parse_store_listings(arm_b_lines) if it[1] > 10]
            _kick_store_by_insults(cli1, gt10_b[0][0])
            assert cli1.read_mem(syms["hg_kicked"] + 1, 1)[0] > 0

            # Quit Char B -> taint player_pflags -> same-session Title 'L'oad SAVE0.SAV -> verify full status bar, recalc & hg_kicked cleared
            cli1.send_keys("QY")
            cli1.run_idle()
            _write_mem(cli1, syms["player_pflags"], [0xFF])
            cli1.send_keys("L1")
            cli1.run_idle()
            same_load_lines, _ = cli1.screen_lines()
            assert "Welcome back to Moria8!" in "\n".join(same_load_lines)
            _assert_status_bar(same_load_lines, "Saver")
            assert "Other" not in same_load_lines[21]
            assert cli1.read_mem(syms["hg_kicked"], 8) == b"\x00" * 8, "hg_kicked[0..7] not cleared on load"
            assert cli1.read_mem(syms["player_pflags"], 1)[0] == 0, "player_pflags leaked across same-session load"
            assert _read_u16_sym(cli1, syms, "wield_weight_lo") == pre_wield_wt, "wield_weight_lo stale on same-session load"

            # Verify Armory '2' is accessible again after load (Saver at (31,17))
            _clear_all_monsters(cli1, syms)
            _walk_steps(cli1, "l" + "k" * 7 + "h" * 5 + "k" * 4)
            assert cli1.read_z80_state()["current_overlay"] == OVL_TOWN
            cli1.send_keys("q")
            cli1.run_idle()

            # Flip 1 bit in a corrupted copy on disk -> return to Title -> Load must reject cleanly
            corrupt = bytearray(valid_raw)
            corrupt[100] ^= 0x01
            save_path.write_bytes(bytes(corrupt))

            cli1.send_keys("QY")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE

            cli1.send_keys("L")
            cli1.run_idle()
            slot_menu_lines, _ = cli1.screen_lines()
            assert "Saver" in "\n".join(slot_menu_lines), (
                f"slot menu peek failed:\n" + "\n".join(slot_menu_lines)
            )
            cli1.send_keys("1")
            cli1.run_idle()
            err_lines, _ = cli1.screen_lines()
            assert "Save file corrupt!" in "\n".join(err_lines), (
                f"expected corrupt-save rejection:\n" + "\n".join(err_lines)
            )
            cli1.send_keys(" ")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE

            # Craft valid-checksum save with door_state_count=17 (> MAX_DOOR_STATES=16): Pass-1 must reject before touching RAM
            bad_doors = bytearray(valid_raw)
            bad_doors[2403] = 17
            new_ck = sum(bad_doors[: SAVE_STREAM_BYTES - 2]) & 0xFFFF
            struct.pack_into("<H", bad_doors, SAVE_STREAM_BYTES - 2, new_ck)
            save_path.write_bytes(bytes(bad_doors))
            _write_mem(cli1, syms["door_state_count"], [3])
            cli1.send_keys("L1")
            cli1.run_idle()
            err_doors, _ = cli1.screen_lines()
            assert "Save file corrupt!" in "\n".join(err_doors), (
                f"expected Pass-1 door_state_count overflow rejection:\n" + "\n".join(err_doors)
            )
            assert cli1.read_mem(syms["door_state_count"], 1)[0] == 3, (
                "Pass-1 rejection leaked into live door_state_count RAM"
            )
            cli1.send_keys(" ")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE
            cli1.send_keys("Q")
            assert cli1.run_until_exit()["exit_code"] == 0
            assert cli1.read_stack_canary() == STACK_CANARY_BYTES
        finally:
            cli1.force_cleanup()

        # 2. Restore valid SAVE0.SAV, cold-boot a fresh VM, Load slot 1 & slot 2, verify parity & normalization
        (workdir / "SAVE0.SAV").write_bytes(valid_raw)
        cli2 = ControlClient([
            str(runner), "--control", "--workdir", str(workdir), str(workdir / "MORIA8.COM"),
        ])
        try:
            cli2.run_idle()
            assert cli2.read_mem(syms["game_loaded_flag"], 1)[0] == 0, "fresh boot should have game_loaded_flag == 0"
            cli2.send_keys("L1")
            cli2.run_idle()
            assert cli2.read_mem(syms["game_loaded_flag"], 1)[0] == 0, "game_loop must consume/clear game_loaded_flag"
            assert cli2.read_mem(syms["zp_search_count"], 1)[0] == 0, "zp_search_count not zeroed on load"
            load_lines, _ = cli2.screen_lines()
            assert "Welcome back to Moria8!" in "\n".join(load_lines), (
                f"expected resumed greeting:\n" + "\n".join(load_lines)
            )
            _assert_status_bar(load_lines, "Saver")
            post_st = cli2.read_z80_state()
            assert post_st["current_overlay"] == OVL_NONE and post_st["overlay_depth"] == 0
            assert post_st["player_x"] == pre_st["player_x"]
            assert post_st["player_y"] == pre_st["player_y"]
            assert post_st["player_dlvl"] == pre_st["player_dlvl"]
            assert post_st["player_lvl"] == pre_st["player_lvl"]
            assert post_st["hp"] == pre_st["hp"] and post_st["mhp"] == pre_st["mhp"]
            assert post_st["turn"] == pre_st["turn"] and post_st["turn"] >= 2
            assert _read_u24_player_gold(cli2, syms) == pre_gold
            post_wt = _read_u16_sym(cli2, syms, "inven_weight_lo")
            post_wield_wt = _read_u16_sym(cli2, syms, "wield_weight_lo")
            assert post_wt > 0 and post_wt == pre_wt, f"weight mismatch after cold load: {post_wt} != {pre_wt}"
            assert post_wield_wt == pre_wield_wt, f"wield_weight_lo mismatch after cold load: {post_wield_wt} != {pre_wield_wt}"
            assert cli2.read_mem(syms["player_pflags"], 1)[0] == 0
            assert cli2.read_mem(syms["inv_item_id"], 272) == pre_inv
            assert cli2.read_mem(syms["si_item_id"], 1024) == pre_stores
            assert cli2.read_mem(MAP_BASE_ADDR, MAP_SIZE_BYTES) == pre_map
            assert cli2.read_mem(syms["player_background"], 160) == pre_pbg

            # Load slot 2 (SAVE1.SAV) -> verify PLF_SEARCHING & zp_run_dir normalized on load
            cli2.send_keys("QY")
            cli2.run_idle()
            cli2.send_keys("L2")
            cli2.run_idle()
            assert (cli2.read_mem(syms["player_data"] + 54, 1)[0] & 0x30) == 0, "PLF_SEARCHING|RESTING not cleared"
            assert cli2.read_mem(syms["zp_run_dir"], 1)[0] == 0xFF, "zp_run_dir not reset to 0xFF"

            # Load slot 3 (SAVE2.SAV) -> verify 118-cap +50 MON-044 residual reconstructed so removing Ring keeps STR=118
            cli2.send_keys("QY")
            cli2.run_idle()
            cli2.send_keys("L3")
            cli2.run_idle()
            assert cli2.read_mem(syms["player_stat_res"], 1)[0] == 50, (
                f"Save V2 load failed to reconstruct STR +50 MON-044 residual: res={cli2.read_mem(syms['player_stat_res'], 1)[0]}"
            )
            eq_ids = cli2.read_mem(syms["inv_item_id"] + 22, 11)
            ring_ord = sum(1 for i in range(7) if eq_ids[i] != 0xFF)
            cli2.send_keys("t" + chr(ord("a") + ring_ord))
            cli2.run_idle()
            _dismiss_more(cli2)
            assert cli2.read_mem(syms["player_data"] + 27, 1)[0] == 118, (
                "Removing +5 STR ring at 118 cap dropped PL_STR_CUR below 118"
            )
            assert cli2.read_mem(syms["player_stat_res"], 1)[0] == 0, (
                f"Removing +5 STR ring left non-zero residual: {cli2.read_mem(syms['player_stat_res'], 1)[0]}"
            )

            # Load slot 4 (SAVE3.SAV) -> verify floor-3 cursed Ring (-2) reconstructs res=0xFE and takeoff clears to (3, 0)
            cli2.send_keys("QY")
            cli2.run_idle()
            cli2.send_keys("L4")
            cli2.run_idle()
            assert cli2.read_mem(syms["player_data"] + 27, 1)[0] == 3, (
                f"Save V2 load corrupted floor-3 PL_STR_CUR: {cli2.read_mem(syms['player_data'] + 27, 1)[0]}"
            )
            assert cli2.read_mem(syms["player_stat_res"], 1)[0] == 0xFE, (
                f"Save V2 load failed to reconstruct floor-3 -2 MON-044 residual: res={cli2.read_mem(syms['player_stat_res'], 1)[0]}"
            )
            eq_ids = cli2.read_mem(syms["inv_item_id"] + 22, 11)
            ring_ord = sum(1 for i in range(7) if eq_ids[i] != 0xFF)
            cli2.send_keys("t" + chr(ord("a") + ring_ord))
            cli2.run_idle()
            _dismiss_more(cli2)
            assert cli2.read_mem(syms["player_data"] + 27, 1)[0] == 3, (
                "Removing cursed -2 STR ring at floor 3 altered PL_STR_CUR"
            )
            assert cli2.read_mem(syms["player_stat_res"], 1)[0] == 0, (
                f"Removing cursed -2 STR ring left non-zero residual: {cli2.read_mem(syms['player_stat_res'], 1)[0]}"
            )

            _quit_game_and_title(cli2)
        finally:
            cli2.force_cleanup()


def scenario_multi_drive_save_setup(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Configure Save Drive B: via Disk Setup while keeping MORIA8.DAT pinned on A:."""
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        drv_a = root / "drv_a"
        drv_b = root / "drv_b"
        drv_a.mkdir()
        drv_b.mkdir()
        shutil.copy2(com_src, drv_a / "MORIA8.COM")
        shutil.copy2(dat_src, drv_a / "MORIA8.DAT")

        # 1. Boot on A:, switch Save Drive -> B: via 'D', verify Title & chargen/save on B:
        cli1 = ControlClient([
            str(runner), "--control",
            "--drive", f"A={drv_a}",
            "--drive", f"B={drv_b}",
            "--strict-drives",
            str(drv_a / "MORIA8.COM"),
        ])
        try:
            cli1.run_idle()
            cli1.send_keys("D")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_STORAGE
            dlines0, _ = cli1.screen_lines()
            assert "Disk Setup" in "\n".join(dlines0) and "Program: A:" in "\n".join(dlines0) and "Save:    A:" in "\n".join(dlines0)

            # Probe unmounted drive C: first via '2' (Pick save drive) -> reject gracefully & keep A:MORIA8.DAT
            cli1.send_keys("2C")
            cli1.run_idle()
            dlines_bad, _ = cli1.screen_lines()
            assert "Drive is not ready." in "\n".join(dlines_bad)
            assert cli1.read_z80_state()["save_drive"] == 0
            cli1.send_keys(" ")
            cli1.run_idle()

            # Select valid drive B: via '2'
            cli1.send_keys("2B")
            cli1.run_idle()
            dlines1, _ = cli1.screen_lines()
            assert "Save:    B:" in "\n".join(dlines1)
            st_drv = cli1.read_z80_state()
            assert st_drv["save_drive"] == 1 and st_drv["program_drive"] == 0

            cli1.send_keys("3")
            cli1.run_idle()
            title_lines, _ = cli1.screen_lines()
            assert "[Save: B:]" in "\n".join(title_lines)

            # Create character (loads OVL_START, OVL_GEN, OVL_TOWN from A:!) & save to B:SAVE0.SAV
            _create_human_warrior(cli1, name="DrvHero")
            cli1.send_keys("5S")
            cli1.run_idle()
            slines, _ = cli1.screen_lines()
            assert "Save Slots:" in "\n".join(slines) and "Select Slot 1-4" in "\n".join(slines)
            cli1.send_keys("1")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE
            assert (drv_b / "SAVE0.SAV").is_file(), "expected SAVE0.SAV on drive B:"
            assert not (drv_a / "SAVE0.SAV").exists(), "SAVE0.SAV must NOT be written on drive A:"

            cli1.send_keys("Q")
            assert cli1.run_until_exit()["exit_code"] == 0
        finally:
            cli1.force_cleanup()

        # 2. Fresh boot -> Disk Setup B: -> Load from B:SAVE0.SAV while loading overlays from A:
        cli2 = ControlClient([
            str(runner), "--control",
            "--drive", f"A={drv_a}",
            "--drive", f"B={drv_b}",
            "--strict-drives",
            str(drv_a / "MORIA8.COM"),
        ])
        try:
            cli2.run_idle()
            cli2.send_keys("D2B3L1")
            cli2.run_idle()
            loaded, _ = cli2.screen_lines()
            assert "Welcome back to Moria8!" in "\n".join(loaded) and "DrvHero" in "\n".join(loaded)
            _quit_game_and_title(cli2)
        finally:
            cli2.force_cleanup()


def scenario_hiscore_io_roundtrip(
    runner: Path, _runcpm: Path, sjasmplus: Path, build_dir: Path
) -> None:
    """Test HISCORE.DAT load-missing, write on B:, read-back parity, & corrupt rejection."""
    if not sjasmplus.is_file():
        raise FileNotFoundError(f"sjasmplus binary not found at {sjasmplus}")
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        drv_a = tmp / "drive_a"
        drv_b = tmp / "drive_b"
        drv_a.mkdir()
        drv_b.mkdir()
        shutil.copy2(dat_src, drv_a / "MORIA8.DAT")

        probe_asm = tmp / "hs_probe.asm"
        probe_com = tmp / "HSPROBE.COM"
        probe_sym = tmp / "hsprobe.sym"
        probe_asm.write_text(
            f"""    DEVICE NOSLOT64K
    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "item_ids_z80.inc"
    INCLUDE "main_exp.inc"

    ORG  RESIDENT_BASE
    INCBIN "{com_src.resolve()}"
    ASSERT $ <= OVL_WINDOW_BASE
    DS   0xD100 - $, 0

    ORG  0xD100
hs_probe_start:
    LD   SP, STACK_TOP
    LD   HL, hs_canary
    LD   DE, STACK_CANARY_ADDR
    LD   BC, STACK_CANARY_LEN
    LDIR

    LD   HL, BSS_BASE
    LD   DE, BSS_BASE + 1
    LD   BC, bss_end - BSS_BASE - 1
    LD   (HL), 0
    LDIR

    LD   HL, hs_magic
    LD   DE, z80_state
    LD   BC, 4
    LDIR
    LD   A, Z80_ABI_VERSION_NUM
    LD   (z80_state + Z80_ABI_VERSION), A
    XOR  A
    LD   (abi_program_drive), A
    LD   A, 1                   ; Save HISCORE.DAT on drive B:
    LD   (abi_save_drive), A

    CALL bdos_reset_dma_default
    CALL dat_init
    JP   C, hs_fail

    ; 1. Missing HISCORE.DAT -> CF=0, count=0
    LD   A, 99
    LD   (hiscore_count), A
    CALL tramp_hiscore_load
    JP   C, hs_fail
    LD   A, (hiscore_count)
    LD   (res_miss_cnt), A

    ; 2. Populate 2 entries x 23 B = 46 B and write B:HISCORE.DAT
    LD   A, 2
    LD   (hiscore_count), A
    LD   HL, hs_seed_entries
    LD   DE, hiscore_table
    LD   BC, 46
    LDIR
    CALL tramp_hiscore_save
    JP   C, hs_fail

    ; 3. Clear table + count, reload from B:HISCORE.DAT
    XOR  A
    LD   (hiscore_count), A
    LD   HL, hiscore_table
    LD   DE, hiscore_table + 1
    LD   BC, HISCORE_TABLE_SIZE - 1
    LD   (HL), 0
    LDIR
    CALL tramp_hiscore_load
    JP   C, hs_fail

    LD   A, (hiscore_count)
    LD   (res_load_cnt), A
    LD   HL, hiscore_table
    LD   DE, res_loaded_entries
    LD   BC, 46
    LDIR

    ; 4. Populate all 10 entries x 23 B = 230 B and write 2-record (256 B) B:HISCORE.DAT
    LD   A, 10
    LD   (hiscore_count), A
    LD   HL, hs_seed_10_entries
    LD   DE, hiscore_table
    LD   BC, 230
    LDIR
    CALL tramp_hiscore_save
    JP   C, hs_fail

    ; 5. Clear table + count, reload all 10 entries from B:HISCORE.DAT
    XOR  A
    LD   (hiscore_count), A
    LD   HL, hiscore_table
    LD   DE, hiscore_table + 1
    LD   BC, HISCORE_TABLE_SIZE - 1
    LD   (HL), 0
    LDIR
    CALL tramp_hiscore_load
    JP   C, hs_fail
    LD   A, (hiscore_count)
    LD   (res_load10_cnt), A
    LD   HL, hiscore_table
    LD   DE, res_loaded10_entries
    LD   BC, 230
    LDIR

    ; 6. Ensure MORIA8.DAT on A: still works after hiscore I/O on B:
    CALL tramp_gen_dungeon
    JP   C, hs_fail

    LD   A, 0x55
    LD   (res_hs_ok), A
    JR   hs_exit

hs_fail:
    LD   A, 0xEE
    LD   (res_hs_ok), A
hs_exit:
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL bdos_call
    JP   CPM_WARM_BOOT

hs_canary: DB STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3
hs_magic:  DB "M8Z0"
hs_seed_entries:
    DB "Alice           ", 10, 0x34, 0x12, 0x00, 0x05, 0x01, 0x02
    DB "Bob             ",  7, 0x80, 0x02, 0x00, 0x03, 0x02, 0x01
hs_seed_10_entries:
    DB "Hero01          ", 20, 0xE8, 0x03, 0x00, 0x0A, 0x00, 0x00
    DB "Hero02          ", 18, 0x84, 0x03, 0x00, 0x09, 0x01, 0x01
    DB "Hero03          ", 16, 0x20, 0x03, 0x00, 0x08, 0x02, 0x02
    DB "Hero04          ", 14, 0xBC, 0x02, 0x00, 0x07, 0x03, 0x03
    DB "Hero05          ", 12, 0x58, 0x02, 0x00, 0x06, 0x04, 0x04
    DB "Hero06          ", 10, 0xF4, 0x01, 0x00, 0x05, 0x05, 0x05
    DB "Hero07          ",  8, 0x90, 0x01, 0x00, 0x04, 0x06, 0x00
    DB "Hero08          ",  6, 0x2C, 0x01, 0x00, 0x03, 0x07, 0x01
    DB "Hero09          ",  4, 0xC8, 0x00, 0x00, 0x02, 0x00, 0x02
    DB "Hero10          ",  2, 0x64, 0x00, 0x00, 0x01, 0x01, 0x03
res_hs_ok:            DB 0
res_miss_cnt:         DB 0xFF
res_load_cnt:         DB 0xFF
res_load10_cnt:       DB 0xFF
res_loaded_entries:   DS 46, 0
res_loaded10_entries: DS 230, 0

    SAVEBIN "{probe_com}", RESIDENT_BASE, $ - RESIDENT_BASE
""",
            encoding="utf-8",
        )
        sproc = subprocess.run(
            [
                str(sjasmplus), "--nologo",
                f"-I{CPM_SRC_DIR}", f"-I{ROOT / 'core' / 'z80'}", f"-I{build_dir}",
                f"--sym={probe_sym}", str(probe_asm),
            ],
            capture_output=True, text=True, check=False,
        )
        assert sproc.returncode == 0, f"hs_probe assembly failed:\n{sproc.stderr}"
        syms = _parse_sym_addrs(probe_sym)

        cli = ControlClient([
            str(runner), "--control",
            "--drive", f"A={drv_a}", "--drive", f"B={drv_b}", "--strict-drives",
            str(probe_com),
        ])
        try:
            cli.call({"cmd": "set_regs", "pc": syms["hs_probe_start"], "sp": 0x8E00})
            assert cli.run_until_exit()["exit_code"] == 0
            assert cli.read_mem(syms["res_hs_ok"], 1) == b"\x55", "hiscore probe hit hs_fail!"
            assert cli.read_mem(syms["res_miss_cnt"], 1)[0] == 0
            assert cli.read_mem(syms["res_load_cnt"], 1)[0] == 2
            assert cli.read_mem(syms["res_load10_cnt"], 1)[0] == 10
            hs_disk = (drv_b / "HISCORE.DAT").read_bytes()
            assert len(hs_disk) == 256, f"expected 256 B (2 CP/M records) for 10 entries, got {len(hs_disk)}"
            assert hs_disk[:4] == b"MH\x01\x0a", f"bad HISCORE.DAT 10-entry header: {hs_disk[:8]!r}"
            loaded2 = cli.read_mem(syms["res_loaded_entries"], 46)
            loaded10 = cli.read_mem(syms["res_loaded10_entries"], 230)
            assert loaded10 == hs_disk[4:234], "loaded 10 high-score entries != HISCORE.DAT body"
            assert loaded2[:16] == b"Alice           "
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def _write_mem(cli: ControlClient, addr: int, data: list[int] | bytes) -> None:
    cli.call({"cmd": "write_mem", "addr": addr, "bytes": list(data)})


def _set_map_tile(cli: ControlClient, x: int, y: int, val: int) -> None:
    _write_mem(cli, MAP_BASE_ADDR + y * 198 + x, [val & 0xFF])


def _get_map_tile(cli: ControlClient, x: int, y: int) -> int:
    return cli.read_mem(MAP_BASE_ADDR + y * 198 + x, 1)[0]


def _clear_all_monsters(cli: ControlClient, syms: dict[str, int]) -> None:
    """Clear active monsters & tile occupancy bits for deterministic non-combat scenarios."""
    grid = bytearray(cli.read_mem(MAP_BASE_ADDR, MAP_SIZE_BYTES))
    for i in range(len(grid)):
        grid[i] &= ~0x01
    cli.write_mem(MAP_BASE_ADDR, bytes(grid))
    empty_row = bytes([0, 0, 0xFF] + [0] * 9)
    cli.write_mem(syms["monster_table"], empty_row * 32)
    _write_mem(cli, syms["zp_mon_count"], [0])
    _write_mem(cli, syms["abi_mon_count"], [0])


def scenario_dungeon_gen_topology_soak(
    runner: Path, _runcpm: Path, sjasmplus: Path, build_dir: Path
) -> None:
    """Multi-seed RAM audit of OVL_GEN 198x66 dungeon topology, BFS reachability, stairs, doors & traps."""
    if not sjasmplus.is_file():
        raise FileNotFoundError(f"sjasmplus binary not found at {sjasmplus}")
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    cases: tuple[tuple[int, int, int], ...] = (
        (0x12345678, 1, 0),
        (0xDEADBEEF, 1, 1),
        (0xCAFEBABE, 5, 0),
        (0x01020304, 5, 1),
        (0x87654321, 10, 0),
        (0xA5A55A5A, 10, 1),
        (0x11223344, 20, 0),
        (0x99887766, 20, 1),
        (0x13579BDF, 2, 0),
        (0x2468ACE0, 3, 1),
        (0xFEEDFACE, 8, 0),
        (0x0F1E2D3C, 12, 1),
        (0x77777777, 15, 0),
        (0x42424242, 18, 1),
        (0xB16B00B5, 25, 0),
        (0x00C0FFEE, 30, 1),
    )
    rows_asm = "\n".join(
        f"    DB 0x{s & 0xFF:02X}, 0x{(s >> 8) & 0xFF:02X}, 0x{(s >> 16) & 0xFF:02X}, 0x{(s >> 24) & 0xFF:02X}, {d}, {dr}"
        for s, d, dr in cases
    )
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        shutil.copy2(dat_src, tmp / "MORIA8.DAT")
        probe_asm = tmp / "dg_probe.asm"
        probe_com = tmp / "DGPROBE.COM"
        probe_sym = tmp / "dgprobe.sym"
        probe_asm.write_text(
            f"""    DEVICE NOSLOT64K
    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "main_exp.inc"

    ORG  RESIDENT_BASE
    INCBIN "{com_src.resolve()}"
    ASSERT $ <= OVL_WINDOW_BASE
    DS   0xD100 - $, 0

    ORG  0xD100
dg_probe_start:
    LD   SP, STACK_TOP
    LD   HL, dg_canary
    LD   DE, STACK_CANARY_ADDR
    LD   BC, STACK_CANARY_LEN
    LDIR
    LD   HL, BSS_BASE
    LD   DE, BSS_BASE + 1
    LD   BC, bss_end - BSS_BASE - 1
    LD   (HL), 0
    LDIR
    LD   HL, dg_magic
    LD   DE, z80_state
    LD   BC, 4
    LDIR
    LD   A, Z80_ABI_VERSION_NUM
    LD   (z80_state + Z80_ABI_VERSION), A
    CALL bdos_reset_dma_default
    CALL dat_init
    JP   C, dg_fail

    LD   B, {len(cases)}
    LD   HL, dg_cases
dg_case_lp:
    PUSH BC
    PUSH HL
    LD   DE, abi_rng_seed
    LD   BC, 4
    LDIR
    LD   A, (HL)
    INC  HL
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
    LD   A, (HL)
    INC  HL
    LD   (level_entry_dir), A
    EX   (SP), HL                ; stack top = next case ptr
    POP  HL
    PUSH HL
    LD   IX, 0xCAFE
    LD   IY, 0xBEEF
    CALL tramp_gen_dungeon
    JP   C, dg_fail
    LD   DE, 0xCAFE
    PUSH IX
    POP  HL
    OR   A
    SBC  HL, DE
    JP   NZ, dg_fail
    LD   DE, 0xBEEF
    PUSH IY
    POP  HL
    OR   A
    SBC  HL, DE
    JP   NZ, dg_fail
dg_case_brk:
    NOP
    POP  HL
    POP  BC
    DEC  B
    JR   NZ, dg_case_lp

    LD   A, 0x55
    LD   (dg_res_ok), A
    JR   dg_exit
dg_fail:
    LD   A, 0xEE
    LD   (dg_res_ok), A
dg_exit:
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL bdos_call
    JP   CPM_WARM_BOOT

dg_canary: DB STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3
dg_magic:  DB "M8Z0"
dg_cases:
{rows_asm}
dg_res_ok: DB 0

    SAVEBIN "{probe_com}", RESIDENT_BASE, $ - RESIDENT_BASE
""",
            encoding="utf-8",
        )
        sproc = subprocess.run(
            [
                str(sjasmplus), "--nologo",
                f"-I{CPM_SRC_DIR}", f"-I{ROOT / 'core' / 'z80'}", f"-I{build_dir}",
                f"--sym={probe_sym}", str(probe_asm),
            ],
            capture_output=True, text=True, check=False,
        )
        assert sproc.returncode == 0, f"dg_probe assembly failed:\n{sproc.stderr}"
        syms = _parse_sym_addrs(probe_sym)

        cli = ControlClient([str(runner), "--control", "--workdir", str(tmp), str(probe_com)])
        try:
            cli.call({"cmd": "set_regs", "pc": syms["dg_probe_start"], "sp": 0x8E00})
            cli.call({"cmd": "add_breakpoint", "addr": syms["dg_case_brk"]})
            seen_traps: set[int] = set()
            seen_room_types: set[int] = set()
            for idx, (seed, dlvl, ed) in enumerate(cases):
                res = cli.call({"cmd": "run", "max_steps": 3000000})
                assert res["reason"] == "breakpoint" and res["pc"] == syms["dg_case_brk"], (
                    f"case {idx} (seed={seed:#x}, dlvl={dlvl}) stopped abnormally: {res}"
                )
                assert cli.read_mem(CPM_CHAR_SHADOW_BASE, 1920) == b" " * 1920, "char shadow dirty after OVL_GEN"
                assert all((b & 0x80) == 0 for b in cli.read_mem(CPM_COLOR_SHADOW_BASE, 1920)), (
                    "color shadow dirty bit set after OVL_GEN"
                )
                grid = cli.read_mem(MAP_BASE_ADDR, MAP_SIZE_BYTES)
                st = cli.read_z80_state()
                px, py = st["player_x"], st["player_y"]
                rc = cli.read_mem(syms["room_count"], 1)[0]
                assert 1 <= rc <= 21, f"case {idx}: bad room_count={rc}"
                rx = cli.read_mem(syms["room_x"], rc)
                ry = cli.read_mem(syms["room_y"], rc)
                rw = cli.read_mem(syms["room_w"], rc)
                rh = cli.read_mem(syms["room_h"], rc)
                rt = cli.read_mem(syms["room_type"], rc)
                seen_room_types.update(rt)

                st_dn = sum(1 for b in grid if (b & 0xF0) == 0x90)
                st_up = sum(1 for b in grid if (b & 0xF0) == 0xA0)
                assert 1 <= st_up <= 2, f"case {idx}: bad up stairs count={st_up}"
                assert 3 <= st_dn <= 4, f"case {idx}: bad down stairs count={st_dn}"
                sx_u, sy_u = cli.read_mem(syms["stairs_up_x"], 1)[0], cli.read_mem(syms["stairs_up_y"], 1)[0]
                sx_d, sy_d = cli.read_mem(syms["stairs_dn1_x"], 1)[0], cli.read_mem(syms["stairs_dn1_y"], 1)[0]
                if ed == 0:
                    assert (px, py) == (sx_u, sy_u), f"dir=0 player {(px, py)} != up stairs {(sx_u, sy_u)}"
                else:
                    assert (px, py) == (sx_d, sy_d), f"dir=1 player {(px, py)} != dn1 stairs {(sx_d, sy_d)}"

                # Verify straight 2-sided door jambs (DGN-008/017)
                wall_nibs = {0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0xC0, 0xD0}
                for y in range(1, 65):
                    row_off = y * 198
                    for x in range(1, 197):
                        nib = grid[row_off + x] & 0xF0
                        if nib in (0x70, 0x80, 0xF0):
                            n_w = (grid[(y - 1) * 198 + x] & 0xF0) in wall_nibs
                            s_w = (grid[(y + 1) * 198 + x] & 0xF0) in wall_nibs
                            w_w = (grid[row_off + x - 1] & 0xF0) in wall_nibs
                            e_w = (grid[row_off + x + 1] & 0xF0) in wall_nibs
                            ok_h = n_w and s_w and (not w_w) and (not e_w)
                            ok_v = w_w and e_w and (not n_w) and (not s_w)
                            assert ok_h or ok_v, f"case {idx}: malformed door jamb at ({x},{y}) nib={nib:#x}"

                # Verify door states (DGN-015) and traps (DGN-019)
                dc = cli.read_mem(syms["door_state_count"], 1)[0]
                assert dc <= 16, f"case {idx}: door_state_count={dc} > 16"
                dx_a = cli.read_mem(syms["door_state_x"], dc)
                dy_a = cli.read_mem(syms["door_state_y"], dc)
                for di in range(dc):
                    assert (grid[dy_a[di] * 198 + dx_a[di]] & 0xF0) in (0x80, 0xF0), (
                        f"case {idx}: door_state at non-door {(dx_a[di], dy_a[di])}"
                    )
                tc = cli.read_mem(syms["trap_count"], 1)[0]
                assert tc <= 16, f"case {idx}: trap_count={tc} > 16"
                tx_a = cli.read_mem(syms["trap_x"], tc)
                ty_a = cli.read_mem(syms["trap_y"], tc)
                tt_a = cli.read_mem(syms["trap_type"], tc)
                for ti in range(tc):
                    assert tt_a[ti] < 18, f"case {idx}: bad trap_type={tt_a[ti]}"
                    assert (grid[ty_a[ti] * 198 + tx_a[ti]] & 0xF0) == 0x00, (
                        f"case {idx}: trap not on TILE_FLOOR"
                    )
                    seen_traps.add(tt_a[ti])

                # Full BFS reachability from player spawn across walkable/doors/rubble
                pass_nibs = {0x00, 0x70, 0x80, 0x90, 0xA0, 0xB0, 0xE0, 0xF0}
                visited = bytearray(MAP_SIZE_BYTES)
                q = [(px, py)]
                visited[py * 198 + px] = 1
                head = 0
                while head < len(q):
                    cx, cy = q[head]
                    head += 1
                    for ddx, ddy in ((0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)):
                        nx, ny = cx + ddx, cy + ddy
                        if 0 <= nx < 198 and 0 <= ny < 66:
                            p = ny * 198 + nx
                            if not visited[p] and (grid[p] & 0xF0) in pass_nibs:
                                visited[p] = 1
                                q.append((nx, ny))
                for ri in range(rc):
                    assert 1 <= rx[ri] and rx[ri] + rw[ri] < 198
                    assert 1 <= ry[ri] and ry[ri] + rh[ri] < 66
                    if rt[ri] == 2:  # RT_VAULT may remain sealed
                        continue
                    for yy in range(ry[ri], ry[ri] + rh[ri]):
                        for xx in range(rx[ri], rx[ri] + rw[ri]):
                            if (grid[yy * 198 + xx] & 0xF0) in pass_nibs:
                                assert visited[yy * 198 + xx], (
                                    f"case {idx}: unreachable non-vault room {ri} tile ({xx},{yy})"
                                )

            assert len(seen_traps) >= 12, f"expected broad trap distribution across 16 seeds, saw {sorted(seen_traps)}"
            assert 0 in seen_room_types and (3 in seen_room_types or 2 in seen_room_types), (
                f"expected special room types, saw {sorted(seen_room_types)}"
            )
            fin = cli.run_until_exit()
            assert fin["exit_code"] == 0 and cli.read_mem(syms["dg_res_ok"], 1) == b"\x55"
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def scenario_los_stairs_and_exploration(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test Town -> DL1 -> LOS room reveal & wall occlusion -> '<' Town, '5' rest vs '.' cancel."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Explorer")
        st0 = cli.read_z80_state()
        t0 = st0["turn"]

        # '5' rests 1 turn in place; '. ' cancels run cleanly without turn cost
        cli.send_keys("5")
        cli.run_idle()
        assert cli.read_z80_state()["turn"] == t0 + 1
        assert (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]) == (31, 18)

        cli.send_keys(". ")
        cli.run_idle()
        assert cli.read_z80_state()["turn"] == t0 + 1

        # Descend Town '>' at (32, 18) to DL1
        _walk_steps(cli, "l>")
        st_d1 = cli.read_z80_state()
        assert st_d1["player_dlvl"] == 1
        px, py = st_d1["player_x"], st_d1["player_y"]
        assert (_get_map_tile(cli, px, py) & 0xF0) == 0xA0, "expected TILE_STAIRS_UP under player on DL1"
        assert (_get_map_tile(cli, px, py) & 0x04) != 0, "player spawn tile must be FLAG_VISITED"
        _assert_valid_floor_items(cli, syms, require_nonempty=True, label="DL1 spawned floor items")

        # Verify wall occlusion around an unexplored dark neighbor cell beyond an adjacent wall
        grid = cli.read_mem(MAP_BASE_ADDR, MAP_SIZE_BYTES)
        wall_nibs = {0x10, 0x20, 0x30, 0x40, 0x50, 0x60}
        occluded_ok = False
        for ddx, ddy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
            wx, wy = px + ddx, py + ddy
            bx, by = px + 2 * ddx, py + 2 * ddy
            if 1 <= bx < 197 and 1 <= by < 65:
                wt = grid[wy * 198 + wx]
                bt = grid[by * 198 + bx]
                if (wt & 0xF0) in wall_nibs and (bt & 0x0C) == 0:
                    occluded_ok = True
                    break
        assert occluded_ok or sum(1 for b in grid if (b & 0x04) != 0) < 2000

        # Synthetic wall occlusion + dynamic LOS reveal verification (unlit tile so room-light skips)
        sx_dir = 1 if px < 194 else -1
        step_dir = "l" if sx_dir == 1 else "h"
        back_dir = "h" if sx_dir == 1 else "l"
        _set_map_tile(cli, px, py, _get_map_tile(cli, px, py) & ~0x08)
        _set_map_tile(cli, px + sx_dir, py, 0x20 | 0x04)      # visited vertical wall
        _set_map_tile(cli, px + 2 * sx_dir, py, 0x00)         # unvisited dark floor behind wall
        cli.send_keys("5")  # advance turn -> calls los_update_visibility
        cli.run_idle()
        assert (_get_map_tile(cli, px + 2 * sx_dir, py) & 0x04) == 0, "cell behind wall must remain unvisited"

        # Clear synthetic wall -> move 1 step toward it -> LOS reveals cell beyond
        _set_map_tile(cli, px + sx_dir, py, 0x00)
        cli.send_keys(step_dir)
        cli.run_idle()
        assert (_get_map_tile(cli, px + 2 * sx_dir, py) & 0x04) != 0, "LOS must reveal floor once wall removed"

        # Step back onto '<' stairs and ascend to Town (32, 18)
        _walk_steps(cli, back_dir + "<")
        st_t2 = cli.read_z80_state()
        assert st_t2["player_dlvl"] == 0 and (st_t2["player_x"], st_t2["player_y"]) == (32, 18)
        lines, _ = cli.screen_lines()
        _assert_status_bar(lines, "Explorer", dlvl=0)
        _quit_game_and_title(cli)


def scenario_features_doors_traps_chests(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test 'o'/'c'/^D/^B doors, 's' secret/trap reveal + zp_disturb, 'D' disarm, '+' tunnel, chests, and hidden traps."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        # Rogue has high search/disarm; boost DEX/STR for deterministic bash/pick/disarm
        _create_human_warrior(cli, name="Tink", class_key="d")
        _clear_all_monsters(cli, syms)
        _walk_steps(cli, "l>")
        _clear_all_monsters(cli, syms)
        st = cli.read_z80_state()
        assert st["player_dlvl"] == 1
        px, py = st["player_x"], st["player_y"]

        # Center player away from map borders if needed so arena [-1..+3, -1..+1] stays interior
        pl_addr = syms["player_data"]
        if px < 2 or px >= 190 or py < 2 or py >= 64:
            px, py = 100, 30
            _write_mem(cli, syms["abi_player_x"], [px])
            _write_mem(cli, syms["abi_player_y"], [py])
            _write_mem(cli, pl_addr + 49, [px, py])
            _set_map_tile(cli, px, py, 0x00 | 0x08 | 0x04)

        # Boost HP, STR, DEX, level, and equip an iron pick + carried iron spike
        _write_mem(cli, pl_addr + 19, [15])       # PL_LEVEL
        _write_mem(cli, pl_addr + 21, [18, 18, 18, 18, 18, 18])
        _write_mem(cli, pl_addr + 27, [18, 18, 18, 18, 18, 18])
        _write_mem(cli, pl_addr + 33, [200, 0, 200, 0])
        # Clear floor hazards around player and stage test arena in RAM
        _write_mem(cli, syms["door_state_count"], [0])
        _write_mem(cli, syms["trap_count"], [0])
        for dx, dy in ((1, 0), (2, 0), (3, 0), (-1, 0), (0, -1), (0, 1)):
            _set_map_tile(cli, px + dx, py + dy, 0x00 | 0x08 | 0x04)

        # Put Iron Pick (198) in EQUIP_WEAPON (22) and Iron Spike (197) qty=2 in inv slot 0
        _write_mem(cli, syms["inv_item_id"] + 22, [198])
        _write_mem(cli, syms["inv_qty"] + 22, [1])
        _write_mem(cli, syms["inv_p1"] + 22, [3])
        _write_mem(cli, syms["inv_flags"] + 22, [0])
        _write_mem(cli, syms["inv_ego"] + 22, [0])
        _write_mem(cli, syms["inv_item_id"], [197])
        _write_mem(cli, syms["inv_qty"], [2])

        # 1. Door East (px+1, py): 'o' open -> 'c' close -> ^D jam -> 'o' stuck -> ^B bash open/broken
        _set_map_tile(cli, px + 1, py, 0x80 | 0x08 | 0x04)
        cli.send_keys("ol")
        cli.run_idle()
        assert (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x70, "expected open door after 'o' l"
        cli.send_keys("cl")
        cli.run_idle()
        assert (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x80, "expected closed door after 'c' l"
        cli.send_keys("\x04l")
        cli.run_idle()
        assert cli.read_mem(syms["inv_qty"], 1)[0] == 1, "^D jam must consume 1 spike"
        assert cli.read_mem(syms["door_state_count"], 1)[0] >= 1
        assert (cli.read_mem(syms["door_state_val"], 1)[0] & 0x80) != 0, "expected jammed door high bit"
        cli.send_keys("ol")
        cli.run_idle()
        assert (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x80, "jammed door must resist 'o'"
        for _ in range(40):
            if (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x70:
                break
            while cli.read_mem(syms["zp_eff_paralyze"], 1)[0] > 0:
                cli.send_keys("5")
                cli.run_idle()
                _dismiss_more(cli)
            cli.send_keys("\x02l")
            cli.run_idle()
            _dismiss_more(cli)
        _dismiss_more(cli)
        for _ in range(5):
            if cli.read_mem(syms["zp_eff_paralyze"], 1)[0] == 0:
                break
            cli.send_keys("5")
            cli.run_idle()
            _dismiss_more(cli)
        assert (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x70, "^B bash did not force jammed door"
        st_bash = cli.read_z80_state()
        assert (st_bash["player_x"], st_bash["player_y"]) == (px + 1, py), (
            f"^B bash must step into doorway (px+1, py): got {st_bash}"
        )
        # Regression (6502 bash.s:228): bash runs passive FOS search only when PLF_SEARCHING is OFF
        orig_race = cli.read_mem(syms["player_data"] + 17, 1)[0]
        orig_class = cli.read_mem(syms["player_data"] + 18, 1)[0]
        orig_light = cli.read_mem(syms["player_data"] + 55, 1)[0]
        orig_str_base = cli.read_mem(syms["player_data"] + 21, 1)[0]
        orig_str_cur = cli.read_mem(syms["player_data"] + 27, 1)[0]
        pl_flags = cli.read_mem(syms["player_data"] + 54, 1)[0]
        _write_mem(cli, syms["player_data"] + 54, [pl_flags & ~0x10])
        _write_mem(cli, syms["player_data"] + 17, [3])   # RACE_HALFLING
        _write_mem(cli, syms["player_data"] + 18, [3])   # CLASS_ROGUE (search=44%, fos=11)
        _write_mem(cli, syms["player_data"] + 55, [2])   # PL_LIGHT_RAD
        _write_mem(cli, syms["player_data"] + 21, [100])  # max STR for clean door bash
        _write_mem(cli, syms["player_data"] + 27, [100])
        _write_mem(cli, syms["abi_rng_seed"], [0x01, 0x00, 0x00, 0x00])
        _set_map_tile(cli, px + 2, py, 0xF0 | 0x08)  # secret door East of doorway (px+1, py)
        for _ in range(160):
            _write_mem(cli, syms["abi_player_x"], [px])
            _write_mem(cli, syms["player_data"] + 49, [px])
            _write_mem(cli, syms["abi_player_y"], [py])
            _write_mem(cli, syms["player_data"] + 50, [py])
            _write_mem(cli, syms["zp_eff_paralyze"], [0])
            _write_mem(cli, syms["door_state_count"], [0])
            _set_map_tile(cli, px + 1, py, 0x80 | 0x08)  # closed door at (px+1, py)
            cli.send_keys("\x02l")
            cli.run_idle()
            _dismiss_more(cli)
            if (_get_map_tile(cli, px + 2, py) & 0xF0) == 0x80:
                break
        assert (_get_map_tile(cli, px + 2, py) & 0xF0) == 0x80, (
            "Door bash with PLF_SEARCHING OFF failed to run passive FOS search"
        )
        _write_mem(cli, syms["player_data"] + 17, [orig_race])
        _write_mem(cli, syms["player_data"] + 18, [orig_class])
        _write_mem(cli, syms["player_data"] + 21, [orig_str_base])
        _write_mem(cli, syms["player_data"] + 27, [orig_str_cur])
        _write_mem(cli, syms["player_data"] + 55, [orig_light])
        _write_mem(cli, syms["zp_eff_paralyze"], [0])
        _write_mem(cli, syms["abi_player_x"], [px])
        _write_mem(cli, syms["player_data"] + 49, [px])
        _write_mem(cli, syms["abi_player_y"], [py])
        _write_mem(cli, syms["player_data"] + 50, [py])

        # 2. Tunnel South rubble (px, py+1): '+' 'j' -> TILE_FLOOR
        _set_map_tile(cli, px, py + 1, 0xB0 | 0x08 | 0x04)
        for _ in range(8):
            if (_get_map_tile(cli, px, py + 1) & 0xF0) == 0x00:
                break
            cli.send_keys("+j")
            cli.run_idle()
        assert (_get_map_tile(cli, px, py + 1) & 0xF0) == 0x00, "'+' j must clear rubble to floor"

        # 3. Search ('s') secret door West (px-1, py) + hidden TRAP_ARROW North (px, py-1) + adjacent chest at (px+1, py-1)
        _set_map_tile(cli, px - 1, py, 0xF0 | 0x08)       # secret door West
        _set_map_tile(cli, px, py - 1, 0x00 | 0x08)       # hidden TRAP_ARROW North (on floor!)
        _write_mem(cli, syms["trap_count"], [1])
        _write_mem(cli, syms["trap_x"], [px])
        _write_mem(cli, syms["trap_y"], [py - 1])
        _write_mem(cli, syms["trap_type"], [1])  # TRAP_ARROW
        # Chest adjacent NE (px+1, py-1) locked + poison trap unfound
        _write_mem(cli, syms["fi_item_id"], [204, 0xFF])
        _write_mem(cli, syms["fi_x"], [px + 1])
        _write_mem(cli, syms["fi_y"], [py - 1])
        _write_mem(cli, syms["fi_qty"], [1])
        _write_mem(cli, syms["fi_p1"], [0x01 | 0x04])  # LOCKED | TRAP_POISON
        _write_mem(cli, syms["fi_to_hit"], [0])
        _set_map_tile(cli, px + 1, py - 1, 0x00 | 0x08 | 0x04 | 0x02)

        for _ in range(60):
            w_t = _get_map_tile(cli, px - 1, py) & 0xF0
            n_t = _get_map_tile(cli, px, py - 1) & 0xF0
            c_p1 = cli.read_mem(syms["fi_p1"], 1)[0]
            if w_t == 0x80 and n_t == 0xE0 and (c_p1 & 0x40):
                assert cli.read_mem(syms["zp_disturb"], 1)[0] > 0, "'s' discovery must set zp_disturb"
                break
            cli.send_keys("s")
            cli.run_idle()
            _dismiss_more(cli)
        _dismiss_more(cli)
        assert (_get_map_tile(cli, px - 1, py) & 0xF0) == 0x80, "'s' must reveal secret door -> closed door"
        assert (_get_map_tile(cli, px, py - 1) & 0xF0) == 0xE0, "'s' must reveal hidden trap -> TILE_TRAP"
        assert (cli.read_mem(syms["fi_p1"], 1)[0] & 0x40) != 0, "'s' must reveal CHEST_P1_TRAP_FOUND"

        # 4. Disarm floor trap North ('D' 'k') -> TILE_FLOOR, trap_count==0, player steps onto (px, py-1); step 'j' back
        cli.send_keys("Dk")
        cli.run_idle()
        assert (_get_map_tile(cli, px, py - 1) & 0xF0) == 0x00, "'D' k must disarm arrow trap to floor"
        assert cli.read_mem(syms["trap_count"], 1)[0] == 0
        st_dis = cli.read_z80_state()
        assert (st_dis["player_x"], st_dis["player_y"]) == (px, py - 1), (
            f"'D' k floor trap disarm must move player onto (px, py-1): got {st_dis}"
        )
        cli.send_keys("j")
        cli.run_idle()

        # 5. Move chest to cleared West tile (px-1, py) -> Disarm ('Dh') & open/loot ('oh')
        _set_map_tile(cli, px + 1, py - 1, 0x00 | 0x08 | 0x04)
        _set_map_tile(cli, px - 1, py, 0x00 | 0x08 | 0x04 | 0x02)
        _write_mem(cli, syms["fi_x"], [px - 1])
        _write_mem(cli, syms["fi_y"], [py])
        _write_mem(cli, syms["fi_p1"], [0x01 | 0x04 | 0x40])
        cli.send_keys("Dh")
        cli.run_idle()
        assert (cli.read_mem(syms["fi_p1"], 1)[0] & 0x3E) == 0, "expected chest traps disarmed"
        cli.send_keys("oh")
        cli.run_idle()
        assert (
            (cli.read_mem(syms["fi_p1"], 1)[0] & 0x80) != 0
            or cli.read_mem(syms["fi_item_id"], 1)[0] == item_ids.ITEM_SLOT_RUINED_CHEST
        ), "expected chest opened / ruined"

        # 5b. Chest in slot 1 (>0) at (px-1, py) with CHEST_P1_TRAP_STR (reloads OVL_CHEST via tramp_modal_recalc_equipment):
        # keep filler item in slot 0 at (px+1, py-1) and verify slot 0 stays untouched while slot 1 is marked OPENED, STR drains & 1d4 dmg fires
        _write_mem(
            cli,
            syms["fi_item_id"],
            [item_ids.ITEM_SLOT_GOLD_RUBIES, item_ids.ITEM_SLOT_SMALL_WOODEN_CHEST, 0xFF],
        )  # slot 0 = gold (GOLD_RUBIES), slot 1 = chest (SMALL_WOODEN_CHEST)
        _write_mem(cli, syms["fi_x"], [px + 1, px - 1])
        _write_mem(cli, syms["fi_y"], [py - 1, py])
        _write_mem(cli, syms["fi_qty"], [1, 1])
        _write_mem(cli, syms["fi_p1"], [50, 0x02 | 0x40])  # CHEST_P1_TRAP_STR | FOUND
        _write_mem(cli, syms["fi_meta_hi"], [0, 52])
        _write_mem(cli, syms["zp_item_count"], [2])
        _write_mem(cli, syms["abi_item_count"], [2])
        _write_mem(cli, pl_addr + 21, [16, 16, 16, 16, 16, 16])
        _write_mem(cli, pl_addr + 27, [16, 16, 16, 16, 16, 16])
        _write_mem(cli, pl_addr + 33, [50, 0])  # HP=50 (< MHP ~127 so recalc_equipment clamp preserves 50)
        _write_mem(cli, syms["abi_player_hp"], [50, 0])
        _write_mem(cli, syms["player_sust_mask"], [0])
        _set_map_tile(cli, px + 1, py - 1, 0x00 | 0x08 | 0x04 | 0x02)
        _set_map_tile(cli, px - 1, py, 0x00 | 0x08 | 0x04 | 0x02)
        pre_ch_hp = cli.read_z80_state()["hp"]
        cli.send_keys("oh")
        cli.run_idle()
        _dismiss_more(cli)
        assert (
            cli.read_mem(syms["fi_item_id"], 1)[0] == item_ids.ITEM_SLOT_GOLD_RUBIES
            and cli.read_mem(syms["fi_p1"], 1)[0] == 50
        ), (
            "slot 0 corrupted after OVL_CHEST reload!"
        )
        assert (cli.read_mem(syms["fi_p1"] + 1, 1)[0] & 0x80) != 0, "chest slot 1 not marked CHEST_P1_OPENED"
        assert cli.read_mem(pl_addr + 21, 1)[0] == 16, "CHEST_P1_TRAP_STR must preserve PL_STR_BASE"
        assert cli.read_mem(pl_addr + 27, 1)[0] == 15, "CHEST_P1_TRAP_STR must drain PL_STR_CUR 16->15"
        assert pre_ch_hp - 4 <= cli.read_z80_state()["hp"] < pre_ch_hp, (
            f"CHEST_P1_TRAP_STR must deal 1d4 dmg: before={pre_ch_hp}, after={cli.read_z80_state()['hp']}"
        )
        assert cli.read_mem(syms["zp_item_count"], 1)[0] >= 2 and (
            cli.read_mem(syms["zp_item_count"], 1)[0] == cli.read_mem(syms["abi_item_count"], 1)[0]
        ), "chest loot must sync zp_item_count & abi_item_count"
        dropped_cnt = cli.read_mem(syms["zp_item_count"], 1)[0]
        if dropped_cnt > 2:
            dropped_ids = cli.read_mem(syms["fi_item_id"] + 2, dropped_cnt - 2)
            dropped_his = cli.read_mem(syms["fi_meta_hi"] + 2, dropped_cnt - 2)
            dropped_lids = [iid + (255 if (mhi & 0x40) else 0) for iid, mhi in zip(dropped_ids, dropped_his)]
            assert all(iid != 0xFF and 0 <= lid < 361 for iid, lid in zip(dropped_ids, dropped_lids)), (
                f"chest 361-item drop wrote empty/out-of-range item: ids={list(dropped_ids)} lids={dropped_lids}"
            )
        _set_map_tile(cli, px + 1, py - 1, 0x00 | 0x08 | 0x04)
        _set_map_tile(cli, px - 1, py, 0x00 | 0x08 | 0x04)
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])

        # 5c. Tunnel dungeon TILE_CORNER_TL | FLAG_VISITED (0x34, ASCII '4') & locked door state removal (LD A, E fix)
        _write_mem(cli, pl_addr + 27, [118])      # PL_STR_CUR = 18/100 + Dwarven Pick -> reliable granite dig
        _write_mem(cli, syms["inv_ego"] + 22, [2])
        _set_map_tile(cli, px, py + 1, 0x30 | 0x08 | 0x04)  # 0x3C; also test 0x34 ('4')!
        _set_map_tile(cli, px, py + 1, 0x34)
        for _ in range(40):
            if (_get_map_tile(cli, px, py + 1) & 0xF0) == 0x00:
                break
            cli.send_keys("+j")
            cli.run_idle()
        assert (_get_map_tile(cli, px, py + 1) & 0xF0) == 0x00, "'+' must dig dungeon 0x34 TILE_CORNER_TL"
        _set_map_tile(cli, px, py + 1, 0x80 | 0x08 | 0x04)
        _write_mem(cli, syms["door_state_count"], [1])
        _write_mem(cli, syms["door_state_x"], [px])
        _write_mem(cli, syms["door_state_y"], [py + 1])
        _write_mem(cli, syms["door_state_val"], [15])  # locked difficulty 15
        for _ in range(40):
            if (_get_map_tile(cli, px, py + 1) & 0xF0) == 0x00:
                break
            cli.send_keys("+j")
            cli.run_idle()
        assert (_get_map_tile(cli, px, py + 1) & 0xF0) == 0x00
        assert cli.read_mem(syms["door_state_count"], 1)[0] == 0, "tunneling locked door must remove door_state[0]"

        # 6. Step onto hidden floor traps: COVERED_PIT -> OPEN_PIT, ROCKFALL -> RUBBLE, then 'D' bad-fail TRAP_TRAP_DOOR -> dlvl 2
        _set_map_tile(cli, px, py, _get_map_tile(cli, px, py) & ~0x02)
        _set_map_tile(cli, px + 1, py, 0x00 | 0x08)
        _set_map_tile(cli, px + 2, py, 0x00 | 0x08)
        _write_mem(cli, syms["trap_count"], [2])
        _write_mem(cli, syms["trap_x"], [px + 1, px + 2])
        _write_mem(cli, syms["trap_y"], [py, py])
        _write_mem(cli, syms["trap_type"], [6, 5])  # COVERED_PIT, ROCKFALL

        cli.send_keys("l")
        cli.run_idle()
        lines_pit, _ = cli.screen_lines()
        assert "You fell into a pit!" in "\n".join(lines_pit), (
            f"expected covered pit trigger message:\n" + "\n".join(lines_pit[:3])
        )
        assert (_get_map_tile(cli, px + 1, py) & 0xF0) == 0xE0, "covered pit must reveal as TILE_TRAP"
        assert cli.read_mem(syms["trap_type"], 1)[0] == 0, "TRAP_COVERED_PIT must mutate to TRAP_OPEN_PIT (0)"
        _dismiss_more(cli)

        cli.send_keys("l")
        cli.run_idle()
        _dismiss_more(cli)
        assert (_get_map_tile(cli, px + 2, py) & 0xF0) == 0xB0, "TRAP_ROCKFALL must turn tile to TILE_RUBBLE"

        # Test 'D' bad-fail on visible TRAP_TRAP_DOOR (8) East -> drops to DL2 & regenerates level cleanly
        _write_mem(cli, pl_addr + 19, [1])
        _write_mem(cli, syms["abi_player_lvl"], [1])
        _write_mem(cli, pl_addr + 46, [0, 0, 0])  # clear accumulated PL_XP_0..2
        _write_mem(cli, pl_addr + 21, [16, 3, 3, 3, 18, 10])
        _write_mem(cli, pl_addr + 27, [16, 3, 3, 3, 18, 10])
        _write_mem(cli, syms["zp_eff_confuse"], [20])
        _write_mem(cli, syms["zp_eff_blind"], [20])
        for _ in range(15):
            st_mid = cli.read_z80_state()
            if st_mid["player_dlvl"] == 2:
                break
            mx, my = st_mid["player_x"], st_mid["player_y"]
            _write_mem(cli, pl_addr + 33, [200, 0, 200, 0])
            _set_map_tile(cli, mx + 1, my, 0xE0 | 0x08 | 0x04)
            _write_mem(cli, syms["trap_count"], [1])
            _write_mem(cli, syms["trap_x"], [mx + 1])
            _write_mem(cli, syms["trap_y"], [my])
            _write_mem(cli, syms["trap_type"], [8])  # TRAP_TRAP_DOOR
            cli.send_keys("Dl")
            cli.run_idle()
        _write_mem(cli, syms["zp_eff_confuse"], [0])
        _write_mem(cli, syms["zp_eff_blind"], [0])
        st_d2 = cli.read_z80_state()
        assert st_d2["player_dlvl"] == 2, f"'D' bad-fail TRAP_TRAP_DOOR should drop & gen DL2, got {st_d2}"
        lines_d2, _ = cli.screen_lines()
        _assert_status_bar(lines_d2, "Tink", dlvl=2, lvl=st_d2["player_lvl"])

        # 7. Regression: Trap 9 corrodes EQUIP_CLOAK via tramp_mon_ext_acid_armour & respects base_ac + to_ac <= 0 guard
        _clear_all_monsters(cli, syms)
        _write_mem(cli, pl_addr + 33, [200, 0, 200, 0])
        _write_mem(cli, syms["abi_player_hp"], [200, 0])
        px2, py2 = st_d2["player_x"], st_d2["player_y"]
        if px2 >= 190:
            px2 = 100
            _write_mem(cli, syms["abi_player_x"], [px2])
            _write_mem(cli, pl_addr + 49, [px2])
        _set_map_tile(cli, px2, py2, 0x0C)
        _set_map_tile(cli, px2 + 1, py2, 0xE0 | 0x08 | 0x04)
        _write_mem(cli, syms["trap_count"], [1])
        _write_mem(cli, syms["trap_x"], [px2 + 1])
        _write_mem(cli, syms["trap_y"], [py2])
        _write_mem(cli, syms["trap_type"], [9])  # TRAP_CORRODE
        cli.write_mem(syms["inv_item_id"] + 23, bytes([0xFF] * 10))
        _set_inv_item(cli, syms, 32, 211, qty=1, to_ac=1, flags=0x02, ego=0)  # Cloak base_ac=1, to_ac=+1
        _write_mem(cli, syms["player_pflags"], [0])
        cli.send_keys("l")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_to_ac"] + 32, 1)[0] == 0, "Trap 9 failed to corrode EQUIP_CLOAK +1->0"
        _write_mem(cli, pl_addr + 33, [200, 0, 200, 0])
        _write_mem(cli, syms["abi_player_hp"], [200, 0])
        cli.send_keys("hl")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_to_ac"] + 32, 1)[0] == 0xFF, "Trap 9 failed to corrode EQUIP_CLOAK 0->-1"
        _write_mem(cli, pl_addr + 33, [200, 0, 200, 0])
        _write_mem(cli, syms["abi_player_hp"], [200, 0])
        cli.send_keys("hl")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_to_ac"] + 32, 1)[0] == 0xFF, "Trap 9 corroded Cloak past worn-out (base_ac+to_ac<=0)"

        _quit_game_and_title(cli)


def scenario_turn_regen_poison_repeat(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test TRN-009 exact 24-bit regen, TRN-010 poison, TRN-011 paralyze, TRN-014 ^R auto-rest, CJS run, '#' & 'X'."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Timer")
        _clear_all_monsters(cli, syms)
        pl = syms["player_data"]

        # 0. Turn-1 hunger threshold parity (START_FOOD=2000 must stay FULL, not Hungry < 2000!)
        cli.send_keys("5")
        cli.run_idle()
        assert cli.read_mem(pl + 53, 1)[0] == 0, "turn-1 hunger must remain FULL (threshold=150, not 2000)"
        assert "Hungry" not in "\n".join(cli.screen_lines()[0])

        # 1. TRN-009 exact 24-bit regen check (MHP=300, HP=200, HUNGER=FULL):
        # 300 * 197 + 1442 = 60542 (0xEC7E) -> tick 1: HP=200 frac=0xEC7E; tick 2: HP=201 frac=0xD8FC
        _write_mem(cli, pl + 33, [200, 0, 44, 1])  # HP=200, MHP=300
        _write_mem(cli, pl + 51, [0x88, 0x13, 0])  # FOOD=5000, FULL
        _write_mem(cli, syms["regen_frac_lo"], [0])
        _write_mem(cli, syms["zp_regen_frac"], [0])
        _write_mem(cli, syms["zp_eff_poison"], [0])

        cli.send_keys("5")
        cli.run_idle()
        assert cli.read_z80_state()["hp"] == 200
        assert cli.read_mem(syms["regen_frac_lo"], 1)[0] == 0x7E
        assert cli.read_mem(syms["zp_regen_frac"], 1)[0] == 0xEC

        cli.send_keys("5")
        cli.run_idle()
        assert cli.read_z80_state()["hp"] == 201, "TRN-009 24-bit regen multiply must heal 200 -> 201 on turn 2"
        assert cli.read_mem(syms["regen_frac_lo"], 1)[0] == 0xFC
        assert cli.read_mem(syms["zp_regen_frac"], 1)[0] == 0xD8

        # Trigger exact HUNGER=1 threshold (150 -> 149): silent message row + status bar indicator
        _write_mem(cli, pl + 51, [150, 0, 0])
        cli.send_keys("5")
        cli.run_idle()
        hng_lines, _ = cli.screen_lines()
        assert cli.read_mem(pl + 53, 1)[0] == 1
        assert "Hungry" in hng_lines[21] and "getting hungry" not in hng_lines[0].lower(), (
            f"unexpected hunger HUD/msg on 150->149:\n{hng_lines[0]!r}\n{hng_lines[21]!r}"
        )
        _write_mem(cli, pl + 51, [0x88, 0x13, 0])

        # 2. TRN-010 CON-scaled poison & expiry (CON=12 -> adj=0 -> idx 4 -> 1 dmg/turn, 0 on 1->0 expiry!)
        _write_mem(cli, pl + 31, [12])            # PL_CON_CUR = 12
        _write_mem(cli, pl + 33, [100, 0])        # HP = 100
        _write_mem(cli, syms["zp_eff_poison"], [3])
        _walk_steps(cli, "555")
        lines_p, _ = cli.screen_lines()
        assert cli.read_mem(syms["zp_eff_poison"], 1)[0] == 0
        assert cli.read_z80_state()["hp"] == 98, f"TRN-010 expected 2 poison dmg (100->98), got {cli.read_z80_state()['hp']}"
        assert "You feel better." in "\n".join(lines_p)

        # HP=1, zp_eff_poison=1 must survive expiry turn unharmed
        _write_mem(cli, pl + 33, [1, 0])
        _write_mem(cli, syms["zp_eff_poison"], [1])
        cli.send_keys("5")
        cli.run_idle()
        st_surv = cli.read_z80_state()
        assert st_surv["hp"] == 1 and (st_surv["game_flags"] & 0x01) == 0, f"died on poison expiry turn: {st_surv}"
        assert "You feel better." in cli.screen_lines()[0][0]
        _write_mem(cli, pl + 33, [42, 1])

        # 3. TRN-011 paralysis expiry -> "You can move again." + next '5' advances turn by 1
        _write_mem(cli, syms["zp_eff_paralyze"], [3])
        t_before_par = cli.read_z80_state()["turn"]
        cli.send_keys("5")  # turn 1: ticks 3->2; auto-skip turn 2: ticks 2->1 -> wakes & clears 1->0
        cli.run_idle()
        st_par = cli.read_z80_state()
        assert st_par["turn"] == t_before_par + 2, (
            f"expected 1 active + 1 paralyzed turn ({t_before_par + 2}), got {st_par['turn']}"
        )
        assert cli.read_mem(syms["zp_eff_paralyze"], 1)[0] == 0
        assert "You can move again." in cli.screen_lines()[0][0]
        cli.send_keys("5")
        cli.run_idle()
        assert cli.read_z80_state()["turn"] == t_before_par + 3, "command after paralysis expiry must consume 1 turn"

        # 4. TRN-014 ^R Auto-Rest -> completes when HP == MHP
        _write_mem(cli, pl + 33, [42, 1])         # HP=298, MHP=300
        cli.send_keys("\x12")
        cli.run_idle()
        st_rest = cli.read_z80_state()
        assert st_rest["hp"] == 300, f"^R auto-rest must heal to MHP=300, got {st_rest['hp']}"
        assert cli.read_mem(syms["auto_rest_active"], 1)[0] == 0

        # 5. TRN-006 CJS Auto-Run in Town (West from (31,18) along open row y=18) + rendered '@' check!
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["zp_mon_count"], [26])  # >= MAX_MONSTERS - CAT_GEN_RESERVE: prevent 1-in-160 MON-039 wanderer interrupting deterministic auto-run
        _write_mem(cli, syms["abi_rng_seed"], [0x11, 0x22, 0x33, 0x44])
        st_r0 = cli.read_z80_state()
        t_r0 = st_r0["turn"]
        scr_r0, _ = cli.screen_lines()
        at_col0 = next(r.index("@") for r in scr_r0[2:20] if "@" in r)
        cli.send_keys("H")
        cli.run_idle()
        st_r1 = cli.read_z80_state()
        scr_r1, _ = cli.screen_lines()
        at_col1 = next(r.index("@") for r in scr_r1[2:20] if "@" in r)
        assert st_r1["player_x"] < st_r0["player_x"] - 2 and st_r1["turn"] >= t_r0 + 2, (
            f"shifted 'H' run should move >=3 tiles West: before={st_r0}, after={st_r1}"
        )
        assert at_col1 < at_col0 - 2, f"auto-run must visually move '@' on screen: {at_col0} -> {at_col1}"

        # 5b. TRN-006 Round 2 regressions: cardinal 45-deg side stop, diagonal NE flank break, & blind run
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["zp_mon_count"], [26])  # >= MAX_MONSTERS - CAT_GEN_RESERVE: prevent 1-in-160 MON-039 wanderer interrupting deterministic auto-run
        _write_mem(cli, syms["abi_rng_seed"], [0x11, 0x22, 0x33, 0x44])
        # (a) Cardinal corridor at y=18 flanked by walls at y=17,19 with North side opening at (7,17): must stop at (6,18)
        for rx in range(2, 12):
            _set_map_tile(cli, rx, 17, 0x00 | 0x08 | 0x04 if rx == 7 else 0x10 | 0x08 | 0x04)
            _set_map_tile(cli, rx, 18, 0x00 | 0x08 | 0x04)
            _set_map_tile(cli, rx, 19, 0x10 | 0x08 | 0x04)
        _write_mem(cli, syms["abi_player_x"], [2, 18])
        _write_mem(cli, pl + 49, [2, 18])
        cli.send_keys("L")
        cli.run_idle()
        assert (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]) == (6, 18), (
            f"cardinal East run must stop at (6,18) before 45-deg opening (7,17): got {cli.read_z80_state()}"
        )
        # (b) Blind run (zp_eff_blind=10) ignores unvisited adjacent item & stops only on wall at (11,18)
        _set_map_tile(cli, 8, 17, 0x00 | 0x02)  # unvisited item beside path
        _set_map_tile(cli, 11, 18, 0x20)        # opaque blocking wall East at x=11
        _write_mem(cli, syms["zp_eff_blind"], [10])
        _write_mem(cli, syms["abi_player_x"], [2, 18])
        _write_mem(cli, pl + 49, [2, 18])
        cli.send_keys("L")
        cli.run_idle()
        assert (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]) == (10, 18), (
            f"blind East run must ignore unvisited flank/item and stop at wall (10,18): got {cli.read_z80_state()}"
        )
        _write_mem(cli, syms["zp_eff_blind"], [0])
        # (c) Diagonal NE open-area run from (4,19): N walls at (4,18)&(5,17), NW open at (4,17) must stop at exact (5,18) via -2 flank
        for ry in range(15, 21):
            for rx in range(2, 14):
                _set_map_tile(cli, rx, ry, 0x00 | 0x08 | 0x04)
        _set_map_tile(cli, 4, 18, 0x10 | 0x08 | 0x04)
        _set_map_tile(cli, 5, 17, 0x10 | 0x08 | 0x04)
        _write_mem(cli, syms["abi_player_x"], [4, 19])
        _write_mem(cli, pl + 49, [4, 19])
        cli.send_keys("U")
        cli.run_idle()
        assert (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]) == (5, 18), (
            f"diagonal NE open run must stop at exact (5,18) on -2 NW flank break: {cli.read_z80_state()}"
        )
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["zp_mon_count"], [26])  # >= MAX_MONSTERS - CAT_GEN_RESERVE: prevent 1-in-160 MON-039 wanderer interrupting NE auto-run
        # Adding (4,17) wall extends NE run cleanly to (6,17) where NW=(5,16)/N=(6,16) open
        _set_map_tile(cli, 4, 17, 0x10 | 0x08 | 0x04)
        _write_mem(cli, syms["abi_player_x"], [4, 19])
        _write_mem(cli, pl + 49, [4, 19])
        cli.send_keys("U")
        cli.run_idle()
        assert (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]) == (6, 17), (
            f"diagonal NE open run with (4,17) wall must stop at exact (6,17): {cli.read_z80_state()}"
        )
        # Restore player at (20, 18) on clean floor for TRN-002 & 'X' swap checks
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["zp_mon_count"], [26])  # >= MAX_MONSTERS - CAT_GEN_RESERVE: prevent 1-in-160 MON-039 wanderer interrupting search mode
        _write_mem(cli, syms["abi_rng_seed"], [0x11, 0x22, 0x33, 0x44])
        _write_mem(cli, syms["abi_player_x"], [20, 18])
        _write_mem(cli, pl + 49, [20, 18])

        # 6. TRN-002 '#' search mode doubles action turn cost ('l' AND 's'), plus 'X' weapon swap & curse refusal
        cli.send_keys("#")
        cli.run_idle()
        assert (cli.read_mem(pl + 54, 1)[0] & 0x10) != 0, "'#' must set PLF_SEARCHING"
        t_s0 = cli.read_z80_state()["turn"]
        cli.send_keys("l")
        cli.run_idle()
        assert cli.read_z80_state()["turn"] == t_s0 + 2, "search-mode move must advance 2 turns"
        cli.send_keys("s")
        cli.run_idle()
        assert cli.read_z80_state()["turn"] == t_s0 + 4, "search-mode 's' must advance 2 turns"
        cli.send_keys("#")
        cli.run_idle()
        assert (cli.read_mem(pl + 54, 1)[0] & 0x10) == 0

        # Natural blindness expiry refreshes visibility cleanly (6502 turn.s + los.asm parity)
        _write_mem(cli, syms["zp_eff_blind"], [1])
        _write_mem(cli, syms["vis_room_revealed"], [0])
        cli.send_keys("5")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["zp_eff_blind"], 1)[0] == 0, "blindness did not expire"
        assert cli.read_mem(syms["vis_room_revealed"], 1)[0] == 0, "game_loop must consume vis_room_revealed"
        assert "@" in "\n".join(cli.screen_lines()[0][2:20]), "blindness expiry failed to redraw viewport"

        # Put Secondary item (Zweihander) in EQUIP_SECONDARY (33) and Cursed Rapier in EQUIP_WEAPON (22)
        _write_mem(cli, syms["inv_item_id"] + 22, [item_ids.ITEM_SLOT_RAPIER])
        _write_mem(cli, syms["inv_ego"] + 22, [item_ids.ITEM_PAGE_RAPIER])
        _write_mem(cli, syms["inv_flags"] + 22, [0x01])  # IF_CURSED
        _write_mem(cli, syms["inv_item_id"] + 33, [item_ids.ITEM_SLOT_TWO_HANDED_SWORD_ZWEIHANDER])
        _write_mem(cli, syms["inv_qty"] + 33, [1])
        _write_mem(cli, syms["inv_flags"] + 33, [0])
        _write_mem(cli, syms["inv_ego"] + 33, [item_ids.ITEM_PAGE_TWO_HANDED_SWORD_ZWEIHANDER])
        cli.send_keys("X")
        cli.run_idle()
        assert cli.read_mem(syms["inv_item_id"] + 22, 1)[0] == item_ids.ITEM_SLOT_RAPIER, "'X' must refuse cursed EQUIP_WEAPON"

        _write_mem(cli, syms["inv_flags"] + 22, [0x08])  # IF_SENSED, uncursed
        cli.send_keys("X")
        cli.run_idle()
        ex_rows = "\n".join(cli.screen_lines()[0][:2])
        _dismiss_more(cli)
        assert "magik" not in ex_rows, f"'X' exchange printed (magik) on sensed weapon: {ex_rows!r}"
        assert cli.read_mem(syms["inv_item_id"] + 22, 1)[0] == item_ids.ITEM_SLOT_TWO_HANDED_SWORD_ZWEIHANDER, (
            "'X' must swap EQUIP_WEAPON <-> EQUIP_SECONDARY"
        )
        assert cli.read_mem(syms["inv_item_id"] + 33, 1)[0] == item_ids.ITEM_SLOT_RAPIER
        _quit_game_and_title(cli)


def scenario_ui_help_wizard_death_hiscore(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test 'C'/'i'/'e'/'x'/'/', nested '?' -> 'L' Help page preservation, ^W Wizard, Tombstone & HISCORE.DAT."""
    syms = _load_main_syms(build_dir)
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    with tempfile.TemporaryDirectory() as td:
        workdir = Path(td)
        shutil.copy2(com_src, workdir / "MORIA8.COM")
        shutil.copy2(dat_src, workdir / "MORIA8.DAT")

        # 1. Session 1: Title 'H', UI screens, nested Help -> Legal -> Help Pg2, Wizard non-recording death
        cli1 = ControlClient([str(runner), "--control", "--workdir", str(workdir), str(workdir / "MORIA8.COM")])
        try:
            cli1.run_idle()
            # Title 'H' Hall of Heroes shortcut removed (6502 parity) -> stays in OVL_TITLE
            cli1.send_keys("H")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE

            _create_human_warrior(cli1, name="WizTest")
            _clear_all_monsters(cli1, syms)
            # Character Info 'C' displays 18/xx (18/50 and 18/00 for 118) while row-22 status line caps to 18
            _write_mem(cli1, syms["player_data"] + 27, [68])   # STR = 18/50
            _write_mem(cli1, syms["player_data"] + 30, [118])  # DEX = 18/00
            _write_mem(cli1, syms["zp_ui_dirty"], [0x81])
            # UI screens C, i, e, x, /@, /D
            for key, expect in (("C", "18/50"), ("C", "18/00"), ("i", "Inventory"), ("e", "Equipment")):
                cli1.send_keys(key)
                cli1.run_idle()
                assert cli1.read_z80_state()["current_overlay"] == OVL_UI
                scr_u, _ = cli1.screen_lines()
                assert expect in "\n".join(scr_u), f"UI key {key!r} missing {expect!r}:\n" + "\n".join(scr_u)
                cli1.send_keys("Q")
                cli1.run_idle()
                assert cli1.read_z80_state()["overlay_depth"] == 0
            assert "18/" not in cli1.screen_lines()[0][22], (
                f"Status line row 22 leaked 18/xx instead of capping to 18: {cli1.screen_lines()[0][22]!r}"
            )
            # Wizard first-time enable returns CF=0 ("WIZARD ON", map intact); menu [W] returns CF=1 with line_buf msg
            cli1.send_keys("\x17y")
            cli1.run_idle()
            assert (cli1.read_z80_state()["game_flags"] & 0x02) != 0, "^W y did not set GAME_FLAG_WIZARD"
            assert "WIZARD ON" in cli1.screen_lines()[0][1], f"^W y missed WIZARD ON on row 1: {cli1.screen_lines()[0][:2]!r}"
            assert "@" in "\n".join(cli1.screen_lines()[0][2:20]), "^W y wiped map on first enable"
            cli1.send_keys("\x17w")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0
            assert "WALL ON" in cli1.screen_lines()[0][0], f"Wizard [W] menu exit missed line_buf msg: {cli1.screen_lines()[0][0]!r}"
            assert "@" in "\n".join(cli1.screen_lines()[0][2:20]), "Wizard menu exit did not redraw map"
            cli1.send_keys("\x17w")
            cli1.run_idle()
            # Wizard [G] Item by id cancel must exit silently without printing "FAIL"
            cli1.send_keys("\x17g\x1b")
            cli1.run_idle()
            assert "FAIL" not in cli1.screen_lines()[0][0], (
                f"Wizard [G] cancel printed FAIL: {cli1.screen_lines()[0][0]!r}"
            )
            # Wizard [G] Item 196 (Flask of Oil) must spawn with p1 = 250 (LANTERN_MAX_CHARGES)
            cli1.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
            cli1.send_keys("\x17g196\r")
            cli1.run_idle()
            assert cli1.read_mem(syms["inv_item_id"], 1)[0] == item_ids.ITEM_SLOT_FLASK_OF_OIL, "Wizard [G] 196 failed to create Flask of Oil"
            assert cli1.read_mem(syms["inv_p1"], 1)[0] == 250, (
                f"Dungeon Flask of Oil spawned with p1={cli1.read_mem(syms['inv_p1'], 1)[0]} instead of 250"
            )
            # Wizard [L] bad value prints "BAD" & clears input; unrecognized key exits Wizard menu
            cli1.send_keys("\x17l999\r")
            cli1.run_idle()
            assert "BAD" in cli1.screen_lines()[0][0], (
                f"Wizard [L] out-of-range missed BAD message: {cli1.screen_lines()[0][0]!r}"
            )
            cli1.send_keys("\x1b")
            cli1.run_idle()
            cli1.send_keys("\x17z")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0, "Unrecognized key did not exit Wizard menu"
            cli1.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
            _write_mem(cli1, syms["abi_game_flags"], [0])
            _write_mem(cli1, syms["zp_game_flags"], [0])

            t_look0 = cli1.read_z80_state()["turn"]
            cli1.send_keys("x\x1b")
            cli1.run_idle()
            st_cancel = cli1.read_z80_state()
            assert st_cancel["overlay_depth"] == 0 and st_cancel["turn"] == t_look0

            # Look ('x') on monster_table[0] with MX_TYPE=32 (Urchin) vs MX_HP_HI=37 (Drunk) -> must read +2, not +4
            st_lk = cli1.read_z80_state()
            lx, ly = st_lk["player_x"] + 1, st_lk["player_y"]
            lx2 = lx + 1
            old_lt = _get_map_tile(cli1, lx, ly)
            old_lt2 = _get_map_tile(cli1, lx2, ly)
            old_rad = cli1.read_mem(syms["abi_light_rad"], 1)[0]

            _set_map_tile(cli1, lx, ly, (old_lt & 0x0C) | 0x01)
            # monster_table[0]: x, y, type=32, hp_lo=0, hp_hi=37, flags=0x18 (VISIBLE|DETECTED)
            _write_mem(cli1, syms["monster_table"], [lx, ly, 32, 0, 37, 0x18, 0, 0, 0, 0, 0, 0])
            cli1.send_keys("xl")
            cli1.run_idle()
            st_after_adj = cli1.read_z80_state()
            look_mon_line = cli1.screen_lines()[0][0]
            assert st_after_adj["overlay_depth"] == 0 and st_after_adj["turn"] == t_look0
            assert "You see a Filthy Street Urchin." in look_mon_line, (
                f"Look monster read wrong offset (expected Filthy Street Urchin, got {look_mon_line!r})"
            )

            # Ray scan skips empty visible floor at (lx, ly) and stops on visible monster at (lx2, ly)
            _set_map_tile(cli1, lx, ly, 0x0C)
            _set_map_tile(cli1, lx2, ly, 0x0C | 0x01)
            _write_mem(cli1, syms["monster_table"], [lx2, ly, 32, 0, 0, 0x08, 0, 0, 0, 0, 0, 0])
            cli1.send_keys("xl")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0
            assert "You see a Filthy Street Urchin." in cli1.screen_lines()[0][0], (
                f"Look ray scan failed: {cli1.screen_lines()[0][0]!r}"
            )

            # TRN-001 / MON-001: MF_DETECTED monster on unlit tile is still described (perception precedes light)
            _write_mem(cli1, syms["abi_light_rad"], [0])
            _set_map_tile(cli1, lx2, ly, 0x00)
            _set_map_tile(cli1, lx, ly, 0x01)
            _write_mem(cli1, syms["monster_table"], [lx, ly, 32, 0, 0, 0x10, 0, 0, 0, 0, 0, 0])
            cli1.send_keys("xl")
            cli1.run_idle()
            assert "You see a Filthy Street Urchin." in cli1.screen_lines()[0][0], (
                f"Detected-only Look failed: {cli1.screen_lines()[0][0]!r}"
            )

            # Unseen wall outside light reports "You see nothing special."
            _clear_all_monsters(cli1, syms)
            _set_map_tile(cli1, lx, ly, 0x10)
            cli1.send_keys("xl")
            cli1.run_idle()
            assert "You see nothing special." in cli1.screen_lines()[0][0], (
                f"Unseen wall Look failed: {cli1.screen_lines()[0][0]!r}"
            )

            # Visible wall blocks LOS to monster beyond it and reports "You see a wall."
            _write_mem(cli1, syms["abi_light_rad"], [old_rad])
            _set_map_tile(cli1, lx, ly, 0x1C)
            _set_map_tile(cli1, lx2, ly, 0x0C | 0x01)
            _write_mem(cli1, syms["monster_table"], [lx2, ly, 32, 0, 0, 0x08, 0, 0, 0, 0, 0, 0])
            cli1.send_keys("xl")
            cli1.run_idle()
            assert "You see a wall." in cli1.screen_lines()[0][0], (
                f"Blocked LOS Look failed: {cli1.screen_lines()[0][0]!r}"
            )
            _clear_all_monsters(cli1, syms)

            # Floor chest along ray shows locked suffix (armed unfound trap stays hidden) then trapped when found
            _set_map_tile(cli1, lx, ly, 0x0C)
            _set_map_tile(cli1, lx2, ly, 0x0E)
            _write_mem(cli1, syms["fi_item_id"], [204])
            _write_mem(cli1, syms["fi_x"], [lx2])
            _write_mem(cli1, syms["fi_y"], [ly])
            _write_mem(cli1, syms["fi_qty"], [1])
            _write_mem(cli1, syms["fi_p1"], [0x05])
            _write_mem(cli1, syms["fi_meta"], [0])
            _write_mem(cli1, syms["fi_meta_hi"], [0])
            cli1.send_keys("xl")
            cli1.run_idle()
            chest_line = cli1.screen_lines()[0][0]
            assert "Small Wooden Chest (locked)." in chest_line, f"Chest look failed: {chest_line!r}"
            _write_mem(cli1, syms["fi_p1"], [0x45])
            cli1.send_keys("xl")
            cli1.run_idle()
            chest_trap_line = cli1.screen_lines()[0][0]
            assert "Small Wooden Chest (trapped)." in chest_trap_line, f"Trapped chest look failed: {chest_trap_line!r}"
            assert cli1.read_z80_state()["turn"] == t_look0
            # Singular floor-item Look articles: "a <consonant>" vs "an <vowel>" (6502 parity)
            _write_mem(cli1, syms["fi_item_id"], [234, 0xFF])  # Short Bow
            _write_mem(cli1, syms["fi_qty"], [1])
            _write_mem(cli1, syms["fi_p1"], [0])
            _write_mem(cli1, syms["fi_meta"], [0])
            _write_mem(cli1, syms["fi_meta_hi"], [0])
            cli1.send_keys("xl")
            cli1.run_idle()
            assert "You see a Short Bow." in cli1.screen_lines()[0][0], (
                f"Consonant singular floor item article failed: {cli1.screen_lines()[0][0]!r}"
            )
            _write_mem(cli1, syms["fi_item_id"], [240, 0xFF])  # Arrow
            cli1.send_keys("xl")
            cli1.run_idle()
            assert "You see a Arrow." in cli1.screen_lines()[0][0], (
                f"Floor item Look failed 6502 'You see a ' parity: {cli1.screen_lines()[0][0]!r}"
            )
            # Floor Look never spoils ego/identified bonuses and chest suffix uses fi_p1 even if fi_meta_hi set
            _write_mem(cli1, syms["fi_item_id"], [234, 0xFF])
            _write_mem(cli1, syms["fi_meta"], [0x02])
            _write_mem(cli1, syms["fi_meta_hi"], [2])
            cli1.send_keys("xl")
            cli1.run_idle()
            bow_line = cli1.screen_lines()[0][0]
            assert "You see a Short Bow." in bow_line and "(Slay Evil)" not in bow_line, (
                f"Floor Look leaked ego/identified bonuses: {bow_line!r}"
            )
            _write_mem(cli1, syms["fi_item_id"], [item_ids.ITEM_SLOT_SMALL_WOODEN_CHEST, 0xFF])
            _write_mem(cli1, syms["fi_p1"], [0x80])       # CHEST_P1_OPENED
            _write_mem(cli1, syms["fi_meta"], [0])
            _write_mem(cli1, syms["fi_meta_hi"], [53])    # EGO_CHEST_DISARMED
            cli1.send_keys("xl")
            cli1.run_idle()
            assert "You see a Small Wooden Chest (empty)." in cli1.screen_lines()[0][0], (
                f"Floor Look failed opened chest fi_p1 suffix with fi_meta_hi set: {cli1.screen_lines()[0][0]!r}"
            )
            _write_mem(cli1, syms["fi_item_id"], [0xFF])

            _write_mem(cli1, syms["abi_light_rad"], [old_rad])
            _set_map_tile(cli1, lx, ly, old_lt)
            _set_map_tile(cli1, lx2, ly, old_lt2)

            # Border permanent-rock protection (6502 tunnel.s): '+' against border row 0 at (31,0) says permanent rock
            _write_mem(cli1, syms["inv_item_id"] + 22, [198])
            _write_mem(cli1, syms["inv_qty"] + 22, [1])
            _write_mem(cli1, syms["inv_p1"] + 22, [3])
            _write_mem(cli1, syms["inv_flags"] + 22, [0])
            _write_mem(cli1, syms["inv_ego"] + 22, [0])
            old_y = cli1.read_mem(syms["abi_player_y"], 1)[0]
            _write_mem(cli1, syms["abi_player_y"], [1])
            _write_mem(cli1, syms["player_data"] + 50, [1])
            pre_tw = _get_map_tile(cli1, 31, 0)
            cli1.send_keys("+k")
            cli1.run_idle()
            assert "permanent rock" in cli1.screen_lines()[0][0].lower(), (
                f"Border wall tunnel should say permanent rock: {cli1.screen_lines()[0][0]!r}"
            )
            assert _get_map_tile(cli1, 31, 0) == pre_tw
            _write_mem(cli1, syms["abi_player_y"], [old_y])
            _write_mem(cli1, syms["player_data"] + 50, [old_y])

            # '/' is Monster Recall only (non-letter or unencountered stays on map cleanly)
            cli1.send_keys("/@")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0
            cli1.send_keys("/D")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0
            # '/' Recall cancel must clear "Recall which?" from Row 0
            cli1.send_keys("/\x1b")
            cli1.run_idle()
            assert "Recall" not in cli1.screen_lines()[0][0], (
                f"'/' Recall cancel left prompt on Row 0: {cli1.screen_lines()[0][0]!r}"
            )

            # Help Pg1 -> Pg2 -> 'L' Legal -> 'Q' Legal -> must return to Help Pg2! -> 'Q' Town
            cli1.send_keys("?")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_HELP
            pg1_blob = "\n".join(cli1.screen_lines()[0])
            assert (
                "Command Reference [L:License]" in pg1_blob
                and "Movement" in pg1_blob
                and "Actions" in pg1_blob
                and "Items" in pg1_blob
                and "Combat" in pg1_blob
                and "Z Use Staff" in pg1_blob
            ), f"Help Page 1 layout unexpected:\n{pg1_blob}"
            cli1.send_keys(" ")
            cli1.run_idle()
            pg2_blob = "\n".join(cli1.screen_lines()[0])
            assert "Magic" in pg2_blob and "CTRL+W" in pg2_blob, (
                f"Help Page 2 layout unexpected:\n{pg2_blob}"
            )
            cli1.send_keys("L")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_LEGAL and cli1.read_z80_state()["overlay_depth"] == 2
            cli1.send_keys("Q")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_HELP and cli1.read_z80_state()["overlay_depth"] == 1
            assert "CTRL+W" in "\n".join(cli1.screen_lines()[0]), "Help Page 2 not preserved across nested Legal!"
            cli1.send_keys("Q")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0
            _assert_status_bar(cli1.screen_lines()[0], "WizTest")

            # ^W Wizard decline -> enable ("WIZARD ON") -> 9-command menu A/H/X/L 3
            cli1.send_keys("\x17n")
            cli1.run_idle()
            assert (cli1.read_z80_state()["game_flags"] & 0x02) == 0
            cli1.send_keys("\x17y")
            cli1.run_idle()
            assert cli1.read_z80_state()["overlay_depth"] == 0
            assert (cli1.read_z80_state()["game_flags"] & 0x02) != 0
            cli1.send_keys("\x17a\x17h\x17x\x17l3\r")
            cli1.run_idle()
            st_wiz = cli1.read_z80_state()
            assert st_wiz["player_dlvl"] == 3 and st_wiz["overlay_depth"] == 0 and st_wiz["player_lvl"] > 1
            _assert_status_bar(cli1.screen_lines()[0], "WizTest", dlvl=3, lvl=st_wiz["player_lvl"])

            # Force fatal poison in Wizard mode -> must NOT record HISCORE.DAT
            _write_mem(cli1, syms["player_data"] + 33, [1, 0])
            _write_mem(cli1, syms["zp_eff_poison"], [10])
            for _ in range(5):
                cli1.send_keys("5")
                cli1.run_idle()
                if "You have been slain." in cli1.screen_lines()[0][0]:
                    break
            assert "You have been slain." in cli1.screen_lines()[0][0]
            _dismiss_more(cli1)
            score_w = "\n".join(cli1.screen_lines()[0])
            assert "* You have died *" in score_w
            assert "WIZARD RUN - NO RANK" in score_w
            assert "-------- High Scores --------" in score_w
            assert not (workdir / "HISCORE.DAT").exists(), "Wizard death must not write HISCORE.DAT!"
            cli1.send_keys(" ")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE

            # 2. Non-wizard character "Martyr" dies from poison -> writes HISCORE.DAT & shows single-screen score
            _create_human_warrior(cli1, name="Martyr")
            _walk_steps(cli1, "l>")
            _write_mem(cli1, syms["player_data"] + 33, [1, 0])
            _write_mem(cli1, syms["zp_eff_poison"], [10])
            for _ in range(5):
                cli1.send_keys("5")
                cli1.run_idle()
                if "You have been slain." in cli1.screen_lines()[0][0]:
                    break
            assert "You have been slain." in cli1.screen_lines()[0][0]
            _dismiss_more(cli1)
            score_m = "\n".join(cli1.screen_lines()[0])
            assert "* You have died *" in score_m and "Martyr" in score_m
            assert "-------- High Scores --------" in score_m
            assert (workdir / "HISCORE.DAT").is_file()
            cli1.send_keys(" ")
            cli1.run_idle()
            assert cli1.read_z80_state()["current_overlay"] == OVL_TITLE
            cli1.send_keys("Q")
            assert cli1.run_until_exit()["exit_code"] == 0
            assert cli1.read_stack_canary() == STACK_CANARY_BYTES
            assert cli1.close() == 0
        finally:
            cli1.force_cleanup()

        # 3. Cold-boot Session 2: verify Martyr persisted in HISCORE.DAT on disk
        hs_bytes = (workdir / "HISCORE.DAT").read_bytes()
        assert b"Martyr" in hs_bytes, "Martyr missing from persisted HISCORE.DAT"


def _pty_pump_until(
    master_fd: int,
    buf: bytearray,
    pty_screen: _PtyAnsiScreen,
    predicate,
    desc: str,
    timeout_s: float = 10.0,
) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if predicate():
            return
        rem = max(0.05, min(0.25, deadline - time.monotonic()))
        r, _, _ = select.select([master_fd], [], [], rem)
        if r:
            try:
                chunk = os.read(master_fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf.extend(chunk)
            pty_screen.feed(chunk)
    raise AssertionError(
        f"RunCPM PTY timed out waiting for {desc}; screen=\n{pty_screen.text()}\ntail={bytes(buf[-400:])!r}"
    )


def scenario_runcpm_pty_smoke(
    _runner: Path, runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    if not runcpm.is_file():
        raise FileNotFoundError(f"RunCPM binary not found at {runcpm}")
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    if not com_src.is_file() or not dat_src.is_file():
        raise FileNotFoundError(f"Missing MORIA8.COM or MORIA8.DAT in {build_dir}")

    with tempfile.TemporaryDirectory() as td:
        drive_root = Path(td)
        a0 = drive_root / "A" / "0"
        a0.mkdir(parents=True)
        shutil.copy2(com_src, a0 / "MORIA8.COM")
        shutil.copy2(dat_src, a0 / "MORIA8.DAT")

        master_fd, slave_fd = pty.openpty()
        proc = subprocess.Popen(
            [str(runcpm.resolve())],
            cwd=str(drive_root),
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
        )
        os.close(slave_fd)
        buf = bytearray()
        pty_screen = _PtyAnsiScreen()
        try:
            _pty_pump_until(master_fd, buf, pty_screen, lambda: b"A0>" in buf, "initial A0> prompt")
            os.write(master_fd, b"MORIA8\r")

            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "N)ew  L)oad  D)isk Setup  A)bout" in pty_screen.text(),
                "Title menu",
            )
            os.write(master_fd, b"A")

            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "1 License  2 Source  3 Info  Q Back" in pty_screen.text(),
                "Legal menu",
            )
            os.write(master_fd, b"1")

            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "GNU GENERAL PUBLIC LICENSE" in pty_screen.text(),
                "License viewer",
            )
            os.write(master_fd, b"Q")

            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "1 License  2 Source  3 Info  Q Back" in pty_screen.text(),
                "Legal menu after Q",
            )
            os.write(master_fd, b"Q")

            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "N)ew  L)oad  D)isk Setup  A)bout" in pty_screen.text(),
                "Title menu after Legal",
            )

            # Verify unmounted B: probe under real RunCPM returns "Drive is not ready." without Bdos Err crash
            os.write(master_fd, b"D")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "Disk Setup" in pty_screen.text(),
                "Disk Setup under RunCPM",
            )
            os.write(master_fd, b"2B")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "Drive is not ready." in pty_screen.text(),
                "Drive is not ready under RunCPM",
            )
            assert b"Bdos Err" not in buf, f"RunCPM hit BDOS Select trap on unmounted B:: {buf[-300:]!r}"
            os.write(master_fd, b" \x1b")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "N)ew  L)oad  D)isk Setup  A)bout" in pty_screen.text(),
                "Title menu after Disk Setup ESC",
            )

            # Quick M2 chargen + Town render test under genuine RunCPM PTY
            os.write(master_fd, b"N")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "Choose your race" in pty_screen.text(),
                "Chargen race menu",
            )
            os.write(master_fd, b"a\raHero\ra")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "Character Info" in pty_screen.text(),
                "Character Info summary",
            )
            os.write(master_fd, b" ")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "LV:1" in pty_screen.text() and "DL:0" in pty_screen.text() and "@" in pty_screen.text(),
                "Town screen under RunCPM",
            )
            os.write(master_fd, b"l>")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "DL:1" in pty_screen.text() and "@" in pty_screen.text(),
                "DL1 dungeon descend under RunCPM",
            )
            os.write(master_fd, b"QY")
            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: "N)ew  L)oad  D)isk Setup  A)bout" in pty_screen.text(),
                "Title menu after Town Quit",
            )

            quit_pos = len(buf)
            os.write(master_fd, b"Q")

            _pty_pump_until(
                master_fd,
                buf,
                pty_screen,
                lambda: b"A0>" in buf[quit_pos:],
                "warm-boot A0> prompt",
            )
            os.write(master_fd, b"EXIT\r")
            rc = proc.wait(timeout=5)
            assert rc == 0, f"RunCPM exited with {rc}"
        finally:
            try:
                os.close(master_fd)
            except OSError:
                pass
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)


def _set_inv_item(
    cli: ControlClient,
    syms: dict[str, int],
    slot: int,
    item_id: int,
    qty: int = 1,
    p1: int = 0,
    to_hit: int = 0,
    to_dam: int = 0,
    to_ac: int = 0,
    flags: int = 0,
    ego: int = 0,
) -> None:
    _write_mem(cli, syms["inv_item_id"] + slot, [item_id & 0xFF])
    _write_mem(cli, syms["inv_qty"] + slot, [qty & 0xFF])
    _write_mem(cli, syms["inv_p1"] + slot, [p1 & 0xFF])
    _write_mem(cli, syms["inv_to_hit"] + slot, [to_hit & 0xFF])
    _write_mem(cli, syms["inv_to_dam"] + slot, [to_dam & 0xFF])
    _write_mem(cli, syms["inv_to_ac"] + slot, [to_ac & 0xFF])
    _write_mem(cli, syms["inv_flags"] + slot, [flags & 0xFF])
    _write_mem(cli, syms["inv_ego"] + slot, [ego & 0xFF])


def _read_monster_slots(cli: ControlClient, syms: dict[str, int]) -> list[tuple[int, int, int, int, int, int]]:
    raw = cli.read_mem(syms["monster_table"], 32 * 12)
    out = []
    for i in range(32):
        off = i * 12
        mx, my, mtype, hp_lo, hp_hi, mflags = raw[off], raw[off + 1], raw[off + 2], raw[off + 3], raw[off + 4], raw[off + 5]
        out.append((i, mx, my, mtype, hp_lo | (hp_hi << 8), mflags))
    return out


def scenario_monster_catalog_spawn_and_visibility(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test MON-001/002/006/016/021/040: Town creature names, MONSTER.CAT paging, DL1 spawn & blind LOS."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Scout")
        st_t = cli.read_z80_state()
        assert st_t["player_dlvl"] == 0 and 4 <= st_t["mon_count"] <= 7, f"expected 4..7 townspeople, got {st_t}"

        # All 8 town names must be populated in town_name_pool from MONSTER.CAT records 0..7
        pool_raw = cli.read_mem(syms["town_name_pool"], 8 * 26)
        town_names = [pool_raw[i * 26 : (i + 1) * 26].split(b"\x00", 1)[0].decode("ascii") for i in range(8)]
        assert town_names[0] == "Filthy Street Urchin" and "Veteran" in town_names[7], (
            f"town_name_pool malformed: {town_names}"
        )

        # Verify unused monster slots use EMPTY_SLOT (0xFF), never 0
        rows = _read_monster_slots(cli, syms)
        active = [r for r in rows if r[3] != 0xFF]
        assert 4 <= len(active) <= 7 and all(32 <= r[3] <= 39 for r in active), f"bad town slots: {rows}"

        # Place slot 0 adjacent East (marked visible) -> 'x' Look identifies it cleanly
        _clear_all_monsters(cli, syms)
        px, py = st_t["player_x"], st_t["player_y"]
        _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"], [px + 1, py, 32, 5, 0, 0x18, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        cli.send_keys("xl")
        cli.run_idle()
        assert cli.read_z80_state()["overlay_depth"] == 0
        assert "Filthy Street Urchin" in cli.screen_lines()[0][0], (
            f"Town creature Look failed: {cli.screen_lines()[0][0]!r}"
        )

        # Descend to DL1 -> MON-002 dungeon monsters populate tier_name_pool & cat_slot_id
        _clear_all_monsters(cli, syms)
        _set_map_tile(cli, px + 1, py, 0x9C)  # TILE_STAIRS_DN | LIT | VISITED
        _walk_steps(cli, "l>")
        st_d = cli.read_z80_state()
        assert st_d["player_dlvl"] == 1 and st_d["mon_count"] >= 1, f"DL1 spawn failed: {st_d}"
        assert cli.read_mem(syms["active_dungeon_count"], 1)[0] >= 1
        drows = _read_monster_slots(cli, syms)
        dactive = [r for r in drows if r[3] != 0xFF]
        assert len(dactive) == st_d["mon_count"] and all(r[4] > 0 for r in dactive), f"bad DL1 HP/slots: {dactive}"
        id_hi = cli.read_mem(syms["cat_slot_id_hi"], 32)
        assert any((b & 0x80) == 0 for b in id_hi), "cat_slot_id_hi had no loaded dungeon slots"

        # MON-001 visibility: place active slot dactive[0] adjacent East -> '5' sets MF_VISIBLE; blind clears it
        sidx, _, _, cr_t, mhp, _ = dactive[0]
        dpx, dpy = st_d["player_x"], st_d["player_y"]
        old_occ_x, old_occ_y = dactive[0][1], dactive[0][2]
        _set_map_tile(cli, old_occ_x, old_occ_y, _get_map_tile(cli, old_occ_x, old_occ_y) & ~0x01)
        _set_map_tile(cli, dpx + 1, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["cr_cdefense"] + cr_t, [cli.read_mem(syms["cr_cdefense"] + cr_t, 1)[0] & 0x7F])
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 1, dpy, cr_t, mhp & 0xFF, mhp >> 8, 0, 0, 0, 0, 0, 0, 0])
        cli.send_keys("5")
        cli.run_idle()
        fl_vis = cli.read_mem(syms["monster_table"] + sidx * 12 + 5, 1)[0]
        assert (fl_vis & 0x08) != 0, f"adjacent monster missing MF_VISIBLE: {fl_vis:#x}"
        _write_mem(cli, syms["zp_eff_blind"], [2])
        cli.send_keys("5")
        cli.run_idle()
        fl_blind = cli.read_mem(syms["monster_table"] + sidx * 12 + 5, 1)[0]
        assert (fl_blind & 0x08) == 0, f"blind player must clear MF_VISIBLE: {fl_blind:#x}"

        # Regression: MON-017 awake awareness gate (awake, non-visible monster beyond cr_aaf must NOT move)
        _write_mem(cli, syms["zp_eff_blind"], [0])
        _set_map_tile(cli, dpx + 1, dpy, _get_map_tile(cli, dpx + 1, dpy) & ~0x01)
        far_x = dpx + 25 if dpx + 26 < 197 else dpx - 25
        _set_map_tile(cli, far_x, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["cr_aaf"] + cr_t, [10])
        _write_mem(cli, syms["cr_speed"] + cr_t, [1])
        _write_mem(cli, syms["cr_spell_chance"] + cr_t, [0])
        _write_mem(cli, syms["monster_table"] + sidx * 12, [far_x, dpy, cr_t, mhp & 0xFF, mhp >> 8, 0x01, 0, 0, 0, 0, 0, 0])
        cli.send_keys("5")
        cli.run_idle()
        mon_far = cli.read_mem(syms["monster_table"] + sidx * 12, 6)
        assert (mon_far[0], mon_far[1]) == (far_x, dpy), (
            f"MON-017: awake out-of-AAF monster moved from {(far_x, dpy)} to {(mon_far[0], mon_far[1])}"
        )
        _set_map_tile(cli, far_x, dpy, _get_map_tile(cli, far_x, dpy) & ~0x01)

        # Regression: floor_item_add must preserve Page-1 ego/meta/to_* fields and NOT corrupt recall_data
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])
        _write_mem(cli, syms["recall_data"], [0xA5, 0x5A, 0x3C, 0xC3])
        _set_inv_item(cli, syms, 0, 25, qty=1, p1=0, to_hit=3, to_dam=2, to_ac=1, flags=0x02, ego=0x45)
        cli.send_keys("da")
        cli.run_idle()
        assert cli.read_mem(syms["fi_to_hit"], 1)[0] == 3, "floor_item_add dropped fi_to_hit"
        assert cli.read_mem(syms["fi_to_dam"], 1)[0] == 2, "floor_item_add dropped fi_to_dam"
        assert cli.read_mem(syms["fi_to_ac"], 1)[0] == 1, "floor_item_add dropped fi_to_ac"
        assert cli.read_mem(syms["fi_meta_hi"], 1)[0] == 0x45, "floor_item_add dropped fi_meta_hi page+ego"
        assert list(cli.read_mem(syms["recall_data"], 4)) == [0xA5, 0x5A, 0x3C, 0xC3], (
            "floor_item_add overflowed into recall_data"
        )
        _write_mem(cli, syms["recall_data"], [0, 0, 0, 0])
        _quit_game_and_title(cli)


def scenario_monster_ai_combat_and_drops(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test MON-010/014/015, TRN-005 disturbance, fixed directional _gl_try_move bump melee, & AI step."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Slayer")
        # Regression: ovl_chest pick_item_tables must assemble inside OVL_WINDOW_BASE (0x5600+),
        # so Town monster object drops produce valid items (<361) with real Look text and 'g' pickup.
        chest_syms = _parse_sym_addrs(build_dir / "ovl_chest.sym")
        assert chest_syms["pit_sorted_lo"] >= 0x5600 and chest_syms["pit_level_bounds_lo"] >= 0x5600, (
            f"ovl_chest pick_item_tables assembled before 0x5600: {chest_syms['pit_sorted_lo']:#x}"
        )
        _clear_all_monsters(cli, syms)
        st = cli.read_z80_state()
        tpx, tpy = st["player_x"], st["player_y"]
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])
        _set_map_tile(cli, tpx - 1, tpy, 0x0C | 0x01)
        _write_mem(cli, syms["cr_ac"] + 32, [0])
        _write_mem(cli, syms["cr_treasure"] + 32, [0x11])  # guarantee 1..2 object drops at dlvl=0
        _write_mem(cli, syms["monster_table"], [tpx - 1, tpy, 32, 1, 0, 0x0A, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        for _ in range(8):
            cli.send_keys("h")
            cli.run_idle()
            _dismiss_more(cli)
            if cli.read_mem(syms["monster_table"] + 2, 1)[0] == 0xFF:
                break
        assert cli.read_mem(syms["monster_table"] + 2, 1)[0] == 0xFF, "Town test creature survived melee"
        fi_ids = cli.read_mem(syms["fi_item_id"], 42)
        fi_xs = cli.read_mem(syms["fi_x"], 42)
        fi_ys = cli.read_mem(syms["fi_y"], 42)
        fi_his = cli.read_mem(syms["fi_meta_hi"], 42)
        dropped = [
            (idx, fi_xs[idx], fi_ys[idx], fi_ids[idx] + (255 if (fi_his[idx] & 0x40) else 0))
            for idx in range(42)
            if fi_ids[idx] != 0xFF
        ]
        assert dropped, "Town monster kill with object drop bit produced no floor items"
        assert all(0 <= lid < 361 for _, _, _, lid in dropped), (
            f"Out-of-range Town drop logical_id (>=361): {dropped}"
        )
        dslot, fx, fy, _ = dropped[0]
        _set_map_tile(cli, fx - 1, fy, 0x0C)
        _write_mem(cli, syms["abi_player_x"], [fx - 1, fy])
        _write_mem(cli, syms["player_data"] + 49, [fx - 1, fy])
        cli.send_keys("xl")
        cli.run_idle()
        look_msg = cli.screen_lines()[0][0].strip()
        _dismiss_more(cli)
        assert look_msg.startswith("You see a ") and look_msg != "You see a .", (
            f"Town drop Look produced empty/corrupt name: {look_msg!r}"
        )
        inv_qty_before = sum(
            q for i, q in zip(cli.read_mem(syms["inv_item_id"], 22), cli.read_mem(syms["inv_qty"], 22)) if i != 0xFF
        )
        _walk_steps(cli, "lg")
        assert cli.read_mem(syms["fi_item_id"] + dslot, 1)[0] == 0xFF, "Town drop still on floor after 'g'"
        inv_qty_after = sum(
            q for i, q in zip(cli.read_mem(syms["inv_item_id"], 22), cli.read_mem(syms["inv_qty"], 22)) if i != 0xFF
        )
        assert inv_qty_after > inv_qty_before, "Picked-up Town drop did not enter inventory"
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])
        _write_mem(cli, syms["abi_player_x"], [tpx, tpy])
        _write_mem(cli, syms["player_data"] + 49, [tpx, tpy])

        _clear_all_monsters(cli, syms)
        st = cli.read_z80_state()
        _set_map_tile(cli, st["player_x"] + 1, st["player_y"], 0x9C)
        _walk_steps(cli, "l>")
        _assert_valid_floor_items(cli, syms, require_nonempty=True, label="DL1 spawned floor items")

        # Enable Wizard temporarily to spawn a real catalog monster, then exit Wizard & test live bump melee
        _clear_all_monsters(cli, syms)
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])
        cli.send_keys("\x17y\x17S")
        cli.run_idle()
        # Clear Wizard flag to ensure normal game flags, relocate spawned monster East (px+1, py) with HP=1
        _write_mem(cli, syms["abi_game_flags"], [0])
        _write_mem(cli, syms["zp_game_flags"], [0])
        st_d = cli.read_z80_state()
        px, py = st_d["player_x"], st_d["player_y"]
        rows = [r for r in _read_monster_slots(cli, syms) if r[3] != 0xFF]
        assert rows, "Wizard 'S' did not spawn any monster"
        sidx, mx0, my0, cr_t, _, mfl = rows[0]
        cat_id = (
            cli.read_mem(syms["cat_slot_id_lo"] + cr_t, 1)[0]
            | (cli.read_mem(syms["cat_slot_id_hi"] + cr_t, 1)[0] << 8)
        )
        _set_map_tile(cli, mx0, my0, _get_map_tile(cli, mx0, my0) & ~0x01)
        _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
        # Guarantee treasure drop (cr_treasure[cr_t]=0x13: mixed gold/obj + 1..2 drops) & high player to-hit/dam, HP=1
        _write_mem(cli, syms["cr_treasure"] + cr_t, [0x13])
        _write_mem(cli, syms["monster_table"] + sidx * 12, [px + 1, py, cr_t, 1, 0, mfl | 0x0A, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["inv_to_hit"] + 22, [30])
        _write_mem(cli, syms["inv_to_dam"] + 22, [15])
        xp0 = int.from_bytes(cli.read_mem(syms["player_data"] + 46, 3), "little")

        # Bump East ('l'): tests fixed _gl_try_move direction + ovl_modal_player_attack + kill + MON-014 drop fulfill (retry on 5% nat-1)
        for _ in range(4):
            cli.send_keys("l")
            cli.run_idle()
            _dismiss_more(cli)
            if cli.read_mem(syms["monster_table"] + sidx * 12 + 2, 1)[0] == 0xFF:
                break
        st_after = cli.read_z80_state()
        assert (st_after["player_x"], st_after["player_y"]) == (px, py), (
            f"Bump melee East moved onto monster instead of attacking: before={(px, py)}, after={st_after}"
        )
        assert cli.read_mem(syms["monster_table"] + sidx * 12 + 2, 1)[0] == 0xFF, "1-HP monster survived bump melee"
        assert (_get_map_tile(cli, px + 1, py) & 0x01) == 0, "Kill left stale FLAG_OCCUPIED"
        assert cli.read_mem(syms["md_queue_count"], 1)[0] == 0, "md_queue_count not drained by turn_post_action"
        _assert_valid_floor_items(
            cli,
            syms,
            require_nonempty=True,
            check_tile_flag=True,
            label="MON-014 DL1 treasure drop",
        )
        xp1 = int.from_bytes(cli.read_mem(syms["player_data"] + 46, 3), "little")
        assert xp1 > xp0, f"Monster kill did not award XP: {xp0} -> {xp1}"
        kills = cli.read_mem(syms["recall_data"] + cat_id * 4, 1)[0]
        assert kills >= 1, f"recall kills not incremented for cat_id={cat_id}"

        # Awake AI movement + TRN-005 disturbance: place awake (0x09 = VISIBLE|AWAKE) movable monster at (px+3, py)
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["abi_rng_seed"], [0x11, 0x22, 0x33, 0x44])
        for fx in range(px + 1, px + 4):
            _set_map_tile(cli, fx, py, 0x0C)
        _set_map_tile(cli, px + 3, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"], [px + 3, py, cr_t, 50, 0, 0x09, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["cr_speed"] + cr_t, [1])
        _write_mem(cli, syms["cr_cdefense"] + cr_t, [0])
        _write_mem(cli, syms["cr_mflags"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_flags"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_chance"] + cr_t, [0])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        cli.send_keys("5")
        cli.run_idle()
        m_after = _read_monster_slots(cli, syms)[0]
        assert m_after[1] < px + 3 or m_after[2] != py, f"Awake monster did not step toward player: {m_after}"
        assert (_get_map_tile(cli, m_after[1], m_after[2]) & 0x01) != 0, "Monster AI failed to set new FLAG_OCCUPIED"

        # Regression (MON-043): low-HP monster (HP=1) with non-zero reserved bytes 10..11 must NOT flee, and must melee player
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["abi_rng_seed"], [0x11, 0x22, 0x33, 0x44])
        _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
        _write_mem(cli, syms["cr_speed"] + cr_t, [1])
        _write_mem(cli, syms["cr_mflags"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_flags"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_chance"] + cr_t, [0])
        _write_mem(cli, syms["cr_atk0_type"] + cr_t, [1])
        _write_mem(cli, syms["cr_atk0_dice"] + cr_t, [2])
        _write_mem(cli, syms["cr_atk0_sides"] + cr_t, [6])
        _write_mem(cli, syms["cr_atk1_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_atk2_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_atk3_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_level"] + cr_t, [60])
        _write_mem(cli, syms["eff_invuln_timer"], [0])
        _write_mem(cli, syms["zp_eff_poison"], [0])
        _write_mem(cli, syms["player_data"] + 33, [200, 0, 200, 0])
        _write_mem(cli, syms["abi_player_hp"], [200, 0, 200, 0])
        _write_mem(cli, syms["monster_table"], [px + 1, py, cr_t, 1, 0, 0x09, 0, 0, 0, 0, 0xFF, 0x7F])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        for _ in range(8):
            cli.send_keys("5")
            cli.run_idle()
            _dismiss_more(cli)
            m_low = _read_monster_slots(cli, syms)[0]
            assert (m_low[1], m_low[2]) == (px + 1, py), (
                f"MON-043 low-HP monster fled instead of holding ground: {m_low}"
            )
            if cli.read_z80_state()["hp"] < 200:
                break
        assert cli.read_z80_state()["hp"] < 200, "MON-043 adjacent low-HP monster failed to melee player"

        # Regression: CF_GROUP (0x20) wake preserves BC across _mc_cheb_dist_hl_de & wakes nearby groupmate
        _clear_all_monsters(cli, syms)
        _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
        _set_map_tile(cli, px + 3, py, 0x0C | 0x01)
        _write_mem(cli, syms["cr_mflags"] + cr_t, [0x20])  # CF_GROUP
        _write_mem(cli, syms["monster_table"], [px + 1, py, cr_t, 50, 0, 0x08, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["monster_table"] + 12, [px + 3, py, cr_t, 50, 0, 0x08, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [2])
        _write_mem(cli, syms["abi_mon_count"], [2])
        cli.send_keys("l")  # melee/bump monster 0 -> wakes slot 0 + groupmate slot 1 cleanly
        cli.run_idle()
        _dismiss_more(cli)
        _write_mem(cli, syms["cr_mflags"] + cr_t, [0])

        # Regression: Flame Tongue (EGO_FLAME_TONGUE=4) deals 1.5x+2d4 (>=3) on 1d1 Broken Dagger vs CD_FIRE
        _clear_all_monsters(cli, syms)
        _set_inv_item(cli, syms, 22, 12, qty=1, to_hit=120, to_dam=0, flags=0x02, ego=0x40 | 4)
        _write_mem(cli, syms["player_data"] + 27, [10, 10, 10, 10, 10, 10])  # STR/DEX=10 -> 0 dmg adj, 1 blow
        _write_mem(cli, syms["player_data"] + 40, [120, 0, 1])  # PL_TOHIT=120, PL_TODMG=0, PL_BLOWS=1
        _write_mem(cli, syms["pcc_eq_todam"], [0])
        _write_mem(cli, syms["cr_cdefense"] + cr_t, [0x02])  # CD_FIRE
        _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"], [px + 1, py, cr_t, 100, 0, 0x09, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        cli.send_keys("l")
        cli.run_idle()
        _dismiss_more(cli)
        hp_left = _read_monster_slots(cli, syms)[0][4]
        assert hp_left <= 97, f"Flame Tongue failed 1.5x+2d4 vs CD_FIRE (hp_left={hp_left})"

        # Regression: eff_invuln_timer blocks monster melee damage and resets on New Game
        _write_mem(cli, syms["zp_eff_poison"], [0])
        _write_mem(cli, syms["eff_invuln_timer"], [5])
        _write_mem(cli, syms["player_data"] + 33, [200, 0, 200, 0])
        _write_mem(cli, syms["abi_player_hp"], [200, 0, 200, 0])
        # Let adjacent monster swing & step onto poison dart / wait: use high-damage adjacent monster attack
        _write_mem(cli, syms["cr_atk0_type"] + cr_t, [1])
        _write_mem(cli, syms["cr_atk0_dice"] + cr_t, [5])
        _write_mem(cli, syms["cr_atk0_sides"] + cr_t, [10])
        _write_mem(cli, syms["cr_atk1_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_atk2_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_atk3_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_level"] + cr_t, [40])
        cli.send_keys("5")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["hp"] == 200, "eff_invuln_timer failed to block monster melee"
        # Poison DoT must STILL deal damage while eff_invuln_timer > 0 blocks monster attack
        _write_mem(cli, syms["zp_eff_poison"], [5])
        cli.send_keys("5")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["hp"] < 200, "eff_invuln_timer improperly blocked poison DoT"
        _write_mem(cli, syms["zp_eff_poison"], [0])

        cli.send_keys("QY")
        cli.run_idle()
        _create_human_warrior(cli, name="Clean")
        assert cli.read_mem(syms["eff_invuln_timer"], 1)[0] == 0, "New Game leaked eff_invuln_timer"
        _quit_game_and_title(cli)


def scenario_monster_attacks_and_magic(
    runner: Path, _runcpm: Path, sjasmplus: Path, build_dir: Path
) -> None:
    """Test OVL_MON_EXT (MON-007/008/009/028..031): monster multi-attack, dragon breath, resist, recall bits, & player death."""
    com_src = build_dir / "MORIA8.COM"
    dat_src = build_dir / "MORIA8.DAT"
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        drv_a = tmp / "drive_a"
        drv_a.mkdir()
        shutil.copy2(dat_src, drv_a / "MORIA8.DAT")

        probe_asm = tmp / "mon_ext_probe.asm"
        probe_com = tmp / "MEPROBE.COM"
        probe_sym = tmp / "meprobe.sym"
        probe_asm.write_text(
            f"""    DEVICE NOSLOT64K
    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    DEFINE MONSTER_IDX_CONSTS_ONLY 1
    INCLUDE "monster_idx_z80.inc"
    UNDEFINE MONSTER_IDX_CONSTS_ONLY
    INCLUDE "main_exp.inc"

    ORG  RESIDENT_BASE
    INCBIN "{com_src.resolve()}"
    ASSERT $ <= OVL_WINDOW_BASE
    DS   0xD100 - $, 0

    ORG  0xD100
me_probe_start:
    LD   SP, STACK_TOP
    LD   HL, me_canary
    LD   DE, STACK_CANARY_ADDR
    LD   BC, STACK_CANARY_LEN
    LDIR
    LD   HL, BSS_BASE
    LD   DE, BSS_BASE + 1
    LD   BC, bss_end - BSS_BASE - 1
    LD   (HL), 0
    LDIR
    LD   HL, me_magic
    LD   DE, z80_state
    LD   BC, 4
    LDIR
    LD   A, Z80_ABI_VERSION_NUM
    LD   (z80_state + Z80_ABI_VERSION), A

    CALL bdos_reset_dma_default
    CALL dat_init
    JP   C, me_fail
    CALL player_init
    CALL inv_init
    CALL catalog_reset_slots
    LD   HL, monster_table + MX_TYPE
    LD   DE, MONSTER_ENTRY_SIZE
    LD   B, MAX_MONSTERS
.init_m:
    LD   (HL), EMPTY_SLOT
    ADD  HL, DE
    DJNZ .init_m

    ; Set up open arena around player (10,10), DL 40, Warrior Lvl 30 HP=500 AC=0
    LD   HL, 0x0A0A
    LD   (abi_player_x), HL
    LD   (player_data + PL_MAP_X), HL
    LD   A, 40
    LD   (abi_player_dlvl), A
    LD   (player_data + PL_DLEVEL), A
    LD   A, 30
    LD   (abi_player_lvl), A
    LD   (player_data + PL_LEVEL), A
    LD   HL, 500
    LD   (player_data + PL_HP_LO), HL
    LD   (player_data + PL_MHP_LO), HL
    LD   (abi_player_hp), HL
    LD   (abi_player_mhp), HL

    ; Write open floor around (8..12, 8..12)
    LD   E, 8
.fy:
    LD   D, 8
.fx:
    LD   B, E
    LD   C, D
    LD   A, 0x0C
    CALL map_set_tile
    INC  D
    LD   A, D
    CP   13
    JR   C, .fx
    INC  E
    LD   A, E
    CP   13
    JR   C, .fy

    ; 1. Load Ancient Multi-Hued Dragon (cat 276) in slot 0 and spawn at (11, 10)
    LD   DE, 276
    CALL catalog_slot_for_id
    LD   (zp_mon_type), A
    LD   B, 10
    LD   C, 11
    CALL monster_spawn_awake
    JP   NC, me_fail
    LD   (zp_mon_idx), A
    LD   A, B                   ; B already clobbered by spawn, store x/y
    LD   A, 11
    LD   (zp_mon_x), A
    LD   A, 10
    LD   (zp_mon_y), A
    LD   A, 0x1A
    LD   (zp_mon_flags), A

    ; Test tramp_mon_ext_attack (IX/IY preservation + damage + recall_mark_atk_slot)
    LD   IX, 0x1234
    LD   IY, 0x5678
    CALL tramp_mon_ext_attack
    PUSH IX
    POP  HL
    LD   DE, 0x1234
    OR   A
    SBC  HL, DE
    JP   NZ, me_fail
    PUSH IY
    POP  HL
    LD   DE, 0x5678
    OR   A
    SBC  HL, DE
    JP   NZ, me_fail

    ; 2. Test tramp_mon_ext_cast (Dragon breath / spell + recall_mark_spell_slot)
    CALL msg_clear
    CALL tramp_mon_ext_cast
    LD   HL, (abi_player_hp)
    LD   DE, 500
    OR   A
    SBC  HL, DE
    JR   C, .cast_damaged
    ; Even if RNG missed melee/spell roll, re-invoke once more to verify spell recall bit
    CALL msg_clear
    CALL tramp_mon_ext_cast
.cast_damaged:
    CALL msg_clear
    LD   A, (recall_data + 276 * 4 + 3)
    LD   (res_spell_recall), A

    ; 3. Test tramp_mon_ext_acid_armour on worn Soft Leather Ring Mail (id 218, to_ac=3)
    LD   A, 218
    LD   (inv_item_id + EQUIP_BODY), A
    LD   A, 1
    LD   (inv_qty + EQUIP_BODY), A
    LD   A, 3
    LD   (inv_to_ac + EQUIP_BODY), A
    XOR  A
    LD   (player_pflags), A
    LD   (zp_eff_resist), A
    CALL tramp_mon_ext_acid_armour
    CALL msg_clear
    LD   A, (inv_to_ac + EQUIP_BODY)
    LD   (res_acid_ac), A

    ; 3b. Stat drain preserves PL_STR_BASE & restore brings PL_STR_CUR back to base
    LD   A, 16
    LD   (player_data + PL_STR_BASE), A
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_eq_stat_mod), A
    LD   (player_stat_res), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_BASE)
    LD   (res_drain_base), A
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_drain_cur), A
    LD   A, STAT_STR
    CALL player_restore_stat_a
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_rest_cur), A

    ; 3c. XP drain below threshold triggers level-down via tramp_modal_award_xp(0)
    LD   A, 5
    LD   (player_data + PL_LEVEL), A
    LD   (abi_player_lvl), A
    LD   A, 100
    LD   (player_data + PL_EXPFACT), A
    LD   HL, 5
    LD   (player_data + PL_XP_0), HL
    XOR  A
    LD   (player_data + PL_XP_2), A
    LD   HL, 0
    CALL tramp_modal_award_xp
    LD   A, (abi_player_lvl)
    LD   (res_lvldown), A
    LD   A, 30
    LD   (player_data + PL_LEVEL), A
    LD   (abi_player_lvl), A

    ; 3d. MSF2_SLOW immunity via PFLAG_FREE_ACT and MON-038 disturb on visible MSF2_BLINK
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_spell_flags
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, cr_spell_flags2
    ADD  HL, DE
    LD   (HL), MSF2_SLOW
    LD   HL, cr_spell_chance
    ADD  HL, DE
    LD   (HL), 1
    LD   A, PFLAG_FREE_ACT
    LD   (player_pflags), A
    XOR  A
    LD   (zp_eff_speed), A
    CALL tramp_mon_ext_cast
    CALL msg_clear
    LD   A, (zp_eff_speed)
    LD   (res_free_slow), A

    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_spell_flags2
    ADD  HL, DE
    LD   (HL), MSF2_BLINK
    LD   A, 0x09
    LD   (zp_mon_flags), A
    XOR  A
    LD   (zp_disturb), A
    CALL tramp_mon_ext_cast
    CALL msg_clear
    LD   A, (zp_disturb)
    LD   (res_blink_disturb), A

    ; 3e. ATK_LOSE_EXP (19) deals 0 HP damage while draining XP & triggering level-down
    LD   HL, 10
    LD   (player_data + PL_HP_LO), HL
    LD   (abi_player_hp), HL
    LD   HL, 100
    LD   (player_data + PL_MHP_LO), HL
    LD   (abi_player_mhp), HL
    LD   A, 5
    LD   (player_data + PL_LEVEL), A
    LD   (abi_player_lvl), A
    LD   A, 100
    LD   (player_data + PL_EXPFACT), A
    LD   HL, 25
    LD   (player_data + PL_XP_0), HL
    XOR  A
    LD   (player_data + PL_XP_2), A
    LD   (player_data + PL_AC), A
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   (HL), 60
    LD   HL, cr_atk0_type
    ADD  HL, DE
    LD   (HL), ATK_LOSE_EXP
    LD   HL, cr_atk0_dice
    ADD  HL, DE
    LD   (HL), 5
    LD   HL, cr_atk0_sides
    ADD  HL, DE
    LD   (HL), 8
    LD   HL, cr_atk1_type
    ADD  HL, DE
    LD   (HL), 0
    LD   B, 4
.lexp_lp:
    PUSH BC
    CALL tramp_mon_ext_attack
    CALL msg_clear
    POP  BC
    LD   A, (abi_player_lvl)
    CP   5
    JR   C, .lexp_dn
    DJNZ .lexp_lp
.lexp_dn:
    LD   HL, (abi_player_hp)
    LD   (res_lexp_hp), HL
    LD   HL, (abi_player_mhp)
    LD   (res_lexp_mhp), HL
    LD   HL, (player_data + PL_XP_0)
    LD   (res_lexp_xp), HL
    LD   A, (abi_player_lvl)
    LD   (res_lexp_lvl), A

    ; 3f. ATK_AGGRAVATE (20) always hits even at cr_level=1 vs PL_AC=60, waking slot 1
    LD   A, 60
    LD   (player_data + PL_AC), A
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   (HL), 1
    LD   HL, cr_atk0_type
    ADD  HL, DE
    LD   (HL), ATK_AGGRAVATE
    LD   HL, cr_atk0_dice
    ADD  HL, DE
    LD   (HL), 1
    LD   HL, cr_atk0_sides
    ADD  HL, DE
    LD   (HL), 1
    LD   HL, cr_atk1_type
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, monster_table + MONSTER_ENTRY_SIZE
    LD   (HL), 9                 ; MX_X
    INC  HL
    LD   (HL), 9                 ; MX_Y
    INC  HL
    LD   A, (zp_mon_type)
    LD   (HL), A                 ; MX_TYPE
    LD   HL, monster_table + MONSTER_ENTRY_SIZE + MX_FLAGS
    LD   (HL), 0x00              ; sleeping
    CALL tramp_mon_ext_attack
    CALL msg_clear
    LD   A, (monster_table + MONSTER_ENTRY_SIZE + MX_FLAGS)
    AND  0x01
    LD   (res_aggr_awake), A
    LD   A, EMPTY_SLOT
    LD   (monster_table + MONSTER_ENTRY_SIZE + MX_TYPE), A
    XOR  A
    LD   (player_data + PL_AC), A
    LD   A, 30
    LD   (player_data + PL_LEVEL), A
    LD   (abi_player_lvl), A

    ; 3g. CR_MAX_HP uses cr_speed bit 7 (0x80), NOT cr_mflags bit 7 (CF_INFRA)
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   (HL), 0x80             ; CF_INFRA without CR_MAX_HP
    LD   HL, cr_speed
    ADD  HL, DE
    LD   (HL), 0x01
    LD   HL, cr_hd_num
    ADD  HL, DE
    LD   (HL), 10
    LD   HL, cr_hd_sides
    ADD  HL, DE
    LD   (HL), 10
    LD   A, EMPTY_SLOT
    LD   (monster_table + MONSTER_ENTRY_SIZE + MX_TYPE), A
    LD   B, 9
    LD   C, 9
    LD   A, (zp_mon_type)
    CALL monster_spawn_one
    JP   NC, me_fail
    LD   A, 1
    CALL monster_get_ptr
    LD   DE, MX_HP_LO
    ADD  HL, DE
    LD   A, (HL)
    LD   (res_infra_hp), A
    LD   A, 1
    CALL monster_remove
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_mflags
    ADD  HL, DE
    LD   (HL), 0
    LD   HL, cr_speed
    ADD  HL, DE
    LD   (HL), 0x81             ; CR_MAX_HP set -> exact 10*10 = 100
    LD   B, 9
    LD   C, 9
    CALL monster_spawn_one
    JP   NC, me_fail
    LD   A, 1
    CALL monster_get_ptr
    LD   DE, MX_HP_LO
    ADD  HL, DE
    LD   A, (HL)
    LD   (res_maxhp_hp), A
    LD   A, 1
    CALL monster_remove

    ; 3h. ATK_DISENCHANT (21) deals 0 HP damage & lowers positive hit/dam/ac
    LD   HL, 50
    LD   (player_data + PL_HP_LO), HL
    LD   (abi_player_hp), HL
    LD   B, 6
    LD   HL, inv_item_id + EQUIP_WEAPON
.dis_setup:
    LD   (HL), 211              ; EQUIP_WEAPON..EQUIP_FEET + EQUIP_CLOAK (7 slots)
    INC  HL
    DJNZ .dis_setup
    LD   A, 211
    LD   (inv_item_id + EQUIP_CLOAK), A
    LD   A, 5
    LD   (inv_to_ac + EQUIP_WEAPON), A
    LD   (inv_to_ac + EQUIP_BODY), A
    LD   (inv_to_ac + EQUIP_SHIELD), A
    LD   (inv_to_ac + EQUIP_HEAD), A
    LD   (inv_to_ac + EQUIP_HANDS), A
    LD   (inv_to_ac + EQUIP_FEET), A
    LD   (inv_to_ac + EQUIP_CLOAK), A
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_level
    ADD  HL, DE
    LD   (HL), 60
    LD   HL, cr_atk0_type
    ADD  HL, DE
    LD   (HL), ATK_DISENCHANT
    LD   HL, cr_atk0_dice
    ADD  HL, DE
    LD   (HL), 5
    LD   HL, cr_atk0_sides
    ADD  HL, DE
    LD   (HL), 8
    LD   HL, cr_atk1_type
    ADD  HL, DE
    LD   (HL), 0
    XOR  A
    LD   (player_data + PL_AC), A
    CALL tramp_mon_ext_attack
    LD   A, (me_any_hit)
    LD   (res_dis_any_hit), A
    CALL msg_clear
    LD   HL, (abi_player_hp)
    LD   (res_dis_hp), HL
    LD   HL, inv_to_ac + EQUIP_WEAPON
    LD   A, (HL)
    CP   5
    JR   C, .dis_y
    LD   HL, inv_to_ac + EQUIP_BODY
    LD   B, 5
.dis_chk:
    LD   A, (HL)
    CP   5
    JR   C, .dis_y
    INC  HL
    DJNZ .dis_chk
    LD   A, (inv_to_ac + EQUIP_CLOAK)
    CP   5
    JR   C, .dis_y
    XOR  A
    JR   .dis_st
.dis_y:
    LD   A, 1
.dis_st:
    LD   (res_dis_ok), A
    ; Clean disenchant test items out of equipped slots
    LD   B, 11
    LD   HL, inv_item_id + EQUIP_WEAPON
.dis_clr:
    LD   (HL), EMPTY_SLOT
    INC  HL
    DJNZ .dis_clr

    ; 3i. ADESC_INSULTS (19) formats "insults you." & recall_data+2 increments once/round
    XOR  A
    LD   (recall_data + 276 * 4 + 2), A
    LD   A, (zp_mon_type)
    LD   E, A
    LD   D, 0
    LD   HL, cr_atk0_type
    ADD  HL, DE
    LD   (HL), 0x80 | ATK_NORMAL ; bit 7 = ADESC bit 0 (19 is odd)
    LD   HL, cr_atk0_dice
    ADD  HL, DE
    LD   (HL), 1
    LD   HL, cr_atk0_sides
    ADD  HL, DE
    LD   (HL), ((19 >> 1) << 4) | 4
    LD   B, 8
.ins_lp:
    PUSH BC
    LD   HL, 250
    LD   (player_data + PL_HP_LO), HL
    LD   (abi_player_hp), HL
    CALL tramp_mon_ext_attack
    POP  BC
    LD   HL, (abi_player_hp)
    LD   DE, 250
    OR   A
    SBC  HL, DE
    JR   C, .ins_hit
    CALL msg_clear
    DJNZ .ins_lp
.ins_hit:
    LD   HL, line_buf
    LD   DE, res_insult_msg
    LD   BC, 48
    LDIR
    CALL msg_clear
    LD   A, (recall_data + 276 * 4 + 2)
    LD   (res_atk_recall), A

    ; 3j. _im_re_armour preserves ICAT_CLOAK across div_hl_c & rolls EGO_STEALTH
    LD   A, 60
    LD   (abi_player_dlvl), A
    LD   HL, 0x0001
    LD   (abi_rng_seed), HL
    LD   (abi_rng_seed + 2), HL
    LD   B, 48
    XOR  A
    LD   (res_cloak_stealth), A
.clk_lp:
    PUSH BC
    LD   A, 211
    LD   (fi_add_id), A
    XOR  A
    LD   (fi_add_ego), A
    LD   (fi_add_p1), A
    LD   (fi_add_to_ac), A
    LD   (fi_add_flags), A
    LD   (item_cur_page), A
    CALL tramp_item_mgt_roll_enchant
    POP  BC
    LD   A, (fi_add_ego)
    AND  0x3F
    CP   EGO_STEALTH
    JR   Z, .clk_ok
    DJNZ .clk_lp
    JR   .clk_done
.clk_ok:
    LD   A, 1
    LD   (res_cloak_stealth), A
.clk_done:

    ; Reload clean Dragon from catalog into slot 0 at (11,10) for fatal check #4
    LD   A, EMPTY_SLOT
    LD   (monster_table + MX_TYPE), A
    CALL catalog_reset_slots
    LD   DE, 276
    CALL catalog_slot_for_id
    LD   (zp_mon_type), A
    LD   B, 10
    LD   C, 11
    CALL monster_spawn_awake
    LD   (zp_mon_idx), A
    LD   A, 11
    LD   (zp_mon_x), A
    LD   A, 10
    LD   (zp_mon_y), A
    LD   A, 0x1A
    LD   (zp_mon_flags), A

    ; 4. Fatal hit check (MON-008): HP=1, attack/cast loop (up to 12 rounds) -> GAME_FLAG_OVER + death_cause_buf populated
    LD   HL, 1
    LD   (player_data + PL_HP_LO), HL
    LD   (abi_player_hp), HL
    LD   B, 12
.fat_lp:
    PUSH BC
    LD   A, 11
    LD   (zp_mon_x), A
    LD   A, 10
    LD   (zp_mon_y), A
    CALL tramp_mon_ext_cast
    CALL msg_clear
    LD   A, (abi_game_flags)
    RRA
    JR   C, .fat_hit
    CALL tramp_mon_ext_attack
    LD   A, (me_any_hit)
    LD   (res_dis_any_hit), A
    CALL msg_clear
    POP  BC
    LD   A, (abi_game_flags)
    RRA
    JR   C, .fat_done
    DJNZ .fat_lp
    JR   .fat_done
.fat_hit:
    POP  BC
.fat_done:
    LD   A, (abi_game_flags)
    LD   (res_fatal_flags), A

    ; 3k. _mc_race_prop/_mc_class_prop preserve B & catalog_slot_for_id preserves slot 0 when 32 slots full
    LD   A, RACE_HALFLING
    LD   (player_data + PL_RACE), A
    LD   A, CLASS_WARRIOR
    LD   (player_data + PL_CLASS), A
    XOR  A
    LD   (player_pflags2), A
    CALL player_search_get_fos
    LD   (res_halfling_war_fos), A
    CALL player_get_stealth
    LD   (res_halfling_war_stl), A
    ; Fill all 32 monster_table slots with species 0..31 so catalog_slot_for_id must not clobber slot 0
    LD   B, CAT_SLOTS
    LD   C, 0
    LD   HL, monster_table
    LD   DE, cat_slot_id_lo
.full32_lp:
    LD   (HL), 1
    INC  HL
    LD   (HL), 1
    INC  HL
    LD   (HL), C
    LD   A, C
    ADD  A, 10
    LD   (DE), A
    INC  DE
    PUSH HL
    LD   HL, cat_slot_id_hi
    LD   E, C
    LD   D, 0
    ADD  HL, DE
    LD   (HL), 0
    POP  HL
    LD   DE, MONSTER_ENTRY_SIZE - 2
    ADD  HL, DE
    INC  C
    DJNZ .full32_lp
    LD   DE, 276
    CALL catalog_slot_for_id
    LD   A, (cat_slot_id_lo)
    LD   (res_cat_full_id0), A

    ; 3l. MON-044 VMS 18/xx equipment stepping, restore with gear, and de_statp drain bands
    ; Case 1: 17 +3 -> 38 (18/20), -3 -> 17
    LD   A, 17
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   C, STAT_STR
    LD   A, 3
    CALL player_step_equip_stat_c
    LD   (res_m44_17p3), A
    LD   A, (-3) & 0xFF
    CALL player_step_equip_stat_c
    LD   (res_m44_38m3), A

    ; Case 2: 23 (18/05) - 1 -> 18 (19..27 -> 18 rule)
    LD   A, 23
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   A, (-1) & 0xFF
    CALL player_step_equip_stat_c
    LD   (res_m44_23m1), A

    ; Case 3: cap 118 +3 -> (118, res=30), -3 -> (118, res=0), +15 -> (118, res=127 sat)
    LD   A, 118
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   A, 3
    CALL player_step_equip_stat_c
    LD   A, (player_stat_res)
    LD   (res_m44_cap_p3_res), A
    LD   A, (-3) & 0xFF
    CALL player_step_equip_stat_c
    LD   (res_m44_cap_m3_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_cap_m3_res), A
    LD   A, 15
    CALL player_step_equip_stat_c
    LD   (res_m44_cap_sat_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_cap_sat_res), A

    ; Case 3b: floor 3 res=-127 + (-5) saturates at 0x80 (-128)
    LD   A, 3
    LD   (player_data + PL_STR_CUR), A
    LD   A, 0x81
    LD   (player_stat_res), A
    LD   A, (-5) & 0xFF
    CALL player_step_equip_stat_c
    LD   (res_m44_min_sat_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_min_sat_res), A

    ; Case 4: restore with equipped +3 mod: base 18 -> (48, 0), base 118 -> (118, 30)
    LD   A, 18
    LD   (player_data + PL_STR_BASE), A
    LD   A, 15
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   A, 3
    LD   (player_eq_stat_mod), A
    LD   A, STAT_STR
    CALL player_restore_stat_a
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_m44_rst18_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_rst18_res), A

    LD   A, 118
    LD   (player_data + PL_STR_BASE), A
    LD   A, 116
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   A, STAT_STR
    CALL player_restore_stat_a
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_m44_rst118_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_rst118_res), A
    XOR  A
    LD   (player_eq_stat_mod), A

    ; Case 5: de_statp cur==3 -> CF=0 unchanged; cur==18 -> cur=17 CF=1
    LD   A, 3
    LD   (player_data + PL_STR_CUR), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    RLA
    AND  1
    LD   (res_m44_d3_cf), A
    LD   A, 18
    LD   (player_data + PL_STR_CUR), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_m44_d18_cur), A

    ; Case 6: de_statp 19..108 -> 4 trials at cur=100 (85..94) and cur=20 -> 18 floor
    LD   B, 4
    LD   HL, res_m44_d100
.d100_lp:
    PUSH BC
    PUSH HL
    LD   A, 100
    LD   (player_data + PL_STR_CUR), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    POP  HL
    LD   (HL), A
    INC  HL
    POP  BC
    DJNZ .d100_lp

    LD   A, 20
    LD   (player_data + PL_STR_CUR), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_m44_d20_cur), A

    ; Case 7: de_statp 109..118 (res=0) -> 4 trials at cur=115 (112..114) and cur=118 (115..117)
    LD   B, 4
    LD   HL, res_m44_d115
.d115_lp:
    PUSH BC
    PUSH HL
    LD   A, 115
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    POP  HL
    LD   (HL), A
    INC  HL
    POP  BC
    DJNZ .d115_lp

    LD   B, 4
    LD   HL, res_m44_d118z
.d118z_lp:
    PUSH BC
    PUSH HL
    LD   A, 118
    LD   (player_data + PL_STR_CUR), A
    XOR  A
    LD   (player_stat_res), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    POP  HL
    LD   (HL), A
    INC  HL
    POP  BC
    DJNZ .d118z_lp

    ; Case 8: de_statp at cur=118, res=10 -> stays 118, res in 7..9
    LD   A, 118
    LD   (player_data + PL_STR_CUR), A
    LD   A, 10
    LD   (player_stat_res), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    LD   (res_m44_r10_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_r10_res), A

    ; Case 9: de_statp at cur=118, res=1 -> loop up to 16 attempts until roll > 1 spills to 116..117, res=0
    LD   B, 16
.r1_lp:
    PUSH BC
    LD   A, 118
    LD   (player_data + PL_STR_CUR), A
    LD   A, 1
    LD   (player_stat_res), A
    LD   A, STAT_STR
    CALL player_drain_stat_a
    LD   A, (player_data + PL_STR_CUR)
    CP   118
    JR   C, .r1_spilled
    POP  BC
    DJNZ .r1_lp
    XOR  A
    LD   (res_m44_r1_cur), A
    JR   .r1_done
.r1_spilled:
    POP  BC
    LD   (res_m44_r1_cur), A
    LD   A, (player_stat_res)
    LD   (res_m44_r1_res), A
.r1_done:

    LD   A, 0xAA
    LD   (res_me_ok), A
    JR   me_exit

me_fail:
    LD   A, 0xEE
    LD   (res_me_ok), A
me_exit:
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL bdos_call
    JP   CPM_WARM_BOOT

me_canary: DB STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3
me_magic:  DB "M8Z0"
res_me_ok:        DB 0
res_spell_recall: DB 0
res_acid_ac:      DB 0
res_drain_base:   DB 0
res_drain_cur:    DB 0
res_rest_cur:     DB 0
res_lvldown:      DB 0
res_free_slow:    DB 0
res_blink_disturb: DB 0
res_lexp_hp:      DW 0
res_lexp_mhp:     DW 0
res_lexp_xp:      DW 0
res_lexp_lvl:     DB 0
res_aggr_awake:   DB 0
res_infra_hp:     DB 0
res_maxhp_hp:     DB 0
res_dis_hp:       DW 0
res_dis_ok:       DB 0
res_dis_any_hit:  DB 0
res_atk_recall:   DB 0
res_insult_msg:   DS 48, 0
res_cloak_stealth: DB 0
res_fatal_flags:  DB 0
res_halfling_war_fos: DB 0
res_halfling_war_stl: DB 0
res_cat_full_id0: DB 0
res_m44_17p3:     DB 0
res_m44_38m3:     DB 0
res_m44_23m1:     DB 0
res_m44_cap_p3_res: DB 0
res_m44_cap_m3_cur: DB 0
res_m44_cap_m3_res: DB 0
res_m44_cap_sat_cur: DB 0
res_m44_cap_sat_res: DB 0
res_m44_min_sat_cur: DB 0
res_m44_min_sat_res: DB 0
res_m44_rst18_cur: DB 0
res_m44_rst18_res: DB 0
res_m44_rst118_cur: DB 0
res_m44_rst118_res: DB 0
res_m44_d3_cf:    DB 0
res_m44_d18_cur:  DB 0
res_m44_d100:     DS 4, 0
res_m44_d20_cur:  DB 0
res_m44_d115:     DS 4, 0
res_m44_d118z:    DS 4, 0
res_m44_r10_cur:  DB 0
res_m44_r10_res:  DB 0
res_m44_r1_cur:   DB 0
res_m44_r1_res:   DB 0

    SAVEBIN "{probe_com}", RESIDENT_BASE, $ - RESIDENT_BASE
""",
            encoding="utf-8",
        )
        sproc = subprocess.run(
            [
                str(sjasmplus), "--nologo",
                f"-I{CPM_SRC_DIR}", f"-I{ROOT / 'core' / 'z80'}", f"-I{build_dir}",
                f"--sym={probe_sym}", str(probe_asm),
            ],
            capture_output=True, text=True, check=False,
        )
        assert sproc.returncode == 0, f"mon_ext_probe failed:\n{sproc.stderr}"
        psyms = _parse_sym_addrs(probe_sym)
        cli = ControlClient([str(runner), "--control", "--drive", f"A={drv_a}", "--strict-drives", str(probe_com)])
        try:
            cli.call({"cmd": "set_regs", "pc": psyms["me_probe_start"], "sp": 0x8E00})
            cli.send_keys("          ")
            assert cli.run_until_exit()["exit_code"] == 0
            assert cli.read_mem(psyms["res_me_ok"], 1) == b"\xAA", "ovl_mon_ext probe failed"
            assert cli.read_mem(psyms["res_spell_recall"], 1)[0] != 0, "Dragon spell recall bits stayed 0"
            assert cli.read_mem(psyms["res_acid_ac"], 1)[0] == 2, "Acid armour failed to corrode to_ac 3->2"
            assert cli.read_mem(psyms["res_drain_base"], 1)[0] == 16, "player_drain_stat_a mutated PL_STR_BASE"
            assert cli.read_mem(psyms["res_drain_cur"], 1)[0] == 15, "player_drain_stat_a failed to drain PL_STR_CUR"
            assert cli.read_mem(psyms["res_rest_cur"], 1)[0] == 16, "player_restore_stat_a failed to restore PL_STR_CUR"
            assert cli.read_mem(psyms["res_lvldown"], 1)[0] < 5, "tramp_modal_award_xp(0) failed level-down"
            assert cli.read_mem(psyms["res_free_slow"], 1)[0] == 0, "PFLAG_FREE_ACT failed to resist MSF2_SLOW"
            assert cli.read_mem(psyms["res_blink_disturb"], 1)[0] >= 1, "MON-038 visible MSF2_BLINK failed to disturb"
            assert _read_u16_sym(cli, psyms, "res_lexp_hp") == 10, "ATK_LOSE_EXP dealt HP damage instead of 0"
            assert _read_u16_sym(cli, psyms, "res_lexp_mhp") < 100, "ATK_LOSE_EXP level-down failed to call player_calc_hp"
            assert _read_u16_sym(cli, psyms, "res_lexp_xp") < 25, "ATK_LOSE_EXP failed to drain XP"
            assert cli.read_mem(psyms["res_lexp_lvl"], 1)[0] < 5, "ATK_LOSE_EXP failed level-down"
            assert cli.read_mem(psyms["res_aggr_awake"], 1)[0] != 0, "ATK_AGGRAVATE missed at PL_AC=60"
            assert cli.read_mem(psyms["res_infra_hp"], 1)[0] < 100, "CF_INFRA triggered CR_MAX_HP max HP"
            assert cli.read_mem(psyms["res_maxhp_hp"], 1)[0] == 100, "CR_MAX_HP (cr_speed bit 7) did not set exact 10*10 HP"
            assert _read_u16_sym(cli, psyms, "res_dis_hp") == 50, "ATK_DISENCHANT dealt HP damage instead of 0"
            assert cli.read_mem(psyms["res_dis_ok"], 1)[0] == 1, "ATK_DISENCHANT failed to lower worn equipment to_ac"
            assert cli.read_mem(psyms["res_dis_any_hit"], 1)[0] >= 1, "me_any_hit wiped across OVL_MODAL reload in ATK_DISENCHANT"
            assert cli.read_mem(psyms["res_halfling_war_fos"], 1)[0] == 33, (
                f"Halfling Warrior FOS expected 33 (38-5), got {cli.read_mem(psyms['res_halfling_war_fos'], 1)[0]}"
            )
            assert cli.read_mem(psyms["res_halfling_war_stl"], 1)[0] == 5, (
                f"Halfling Warrior stealth expected 5 (1+4), got {cli.read_mem(psyms['res_halfling_war_stl'], 1)[0]}"
            )
            assert cli.read_mem(psyms["res_cat_full_id0"], 1)[0] == 10, (
                "catalog_slot_for_id overwrote live species slot 0 when 32 slots full"
            )
            assert cli.read_mem(psyms["res_atk_recall"], 1)[0] >= 1, "recall_mark_atk_slot failed to increment attack count"
            ins_txt = cli.read_mem(psyms["res_insult_msg"], 48).split(b"\x00", 1)[0].decode("ascii", "replace")
            assert "insults you." in ins_txt, f"Expected 6502 ADESC_INSULTS 'insults you.', got {ins_txt!r}"
            assert cli.read_mem(psyms["res_cloak_stealth"], 1)[0] == 1, "_im_re_armour failed to roll EGO_STEALTH on Cloak (div_hl_c clobbered B?)"
            assert (cli.read_mem(psyms["res_fatal_flags"], 1)[0] & 0x01) != 0, "1-HP player survived Dragon breath"
            cause = cli.read_mem(psyms["death_cause_buf"], 32).split(b"\x00", 1)[0].decode("ascii", "replace")
            assert "Dragon" in cause, f"Expected Dragon in death_cause_buf, got {cause!r}"
            # MON-044 Z80 assertions
            assert cli.read_mem(psyms["res_m44_17p3"], 1)[0] == 38, "MON-044 17+3 expected 38 (18/20)"
            assert cli.read_mem(psyms["res_m44_38m3"], 1)[0] == 17, "MON-044 38-3 expected 17"
            assert cli.read_mem(psyms["res_m44_23m1"], 1)[0] == 18, "MON-044 18/05 (23)-1 expected 18 (19..27 rule)"
            assert cli.read_mem(psyms["res_m44_cap_p3_res"], 1)[0] == 30, "MON-044 cap 118+3 expected res=30"
            assert cli.read_mem(psyms["res_m44_cap_m3_cur"], 1)[0] == 118 and cli.read_mem(psyms["res_m44_cap_m3_res"], 1)[0] == 0
            assert cli.read_mem(psyms["res_m44_cap_sat_cur"], 1)[0] == 118 and cli.read_mem(psyms["res_m44_cap_sat_res"], 1)[0] == 127
            assert cli.read_mem(psyms["res_m44_min_sat_cur"], 1)[0] == 3 and cli.read_mem(psyms["res_m44_min_sat_res"], 1)[0] == 0x80
            assert cli.read_mem(psyms["res_m44_rst18_cur"], 1)[0] == 48 and cli.read_mem(psyms["res_m44_rst18_res"], 1)[0] == 0
            assert cli.read_mem(psyms["res_m44_rst118_cur"], 1)[0] == 118 and cli.read_mem(psyms["res_m44_rst118_res"], 1)[0] == 30
            assert cli.read_mem(psyms["res_m44_d3_cf"], 1)[0] == 0, "de_statp at cur=3 must return CF=0"
            assert cli.read_mem(psyms["res_m44_d18_cur"], 1)[0] == 17, "de_statp at cur=18 expected 17"
            d100 = list(cli.read_mem(psyms["res_m44_d100"], 4))
            assert all(85 <= v <= 94 for v in d100), f"de_statp at 100 out of [85..94]: {d100}"
            assert cli.read_mem(psyms["res_m44_d20_cur"], 1)[0] == 18, "de_statp at cur=20 must floor at 18"
            d115 = list(cli.read_mem(psyms["res_m44_d115"], 4))
            assert all(112 <= v <= 114 for v in d115), f"de_statp at 115 out of [112..114]: {d115}"
            d118z = list(cli.read_mem(psyms["res_m44_d118z"], 4))
            assert all(115 <= v <= 117 for v in d118z), f"de_statp at 118 (res=0) out of [115..117]: {d118z}"
            assert cli.read_mem(psyms["res_m44_r10_cur"], 1)[0] == 118 and 7 <= cli.read_mem(psyms["res_m44_r10_res"], 1)[0] <= 9
            r1_cur = cli.read_mem(psyms["res_m44_r1_cur"], 1)[0]
            assert r1_cur in (116, 117) and cli.read_mem(psyms["res_m44_r1_res"], 1)[0] == 0, f"de_statp res=1 spill bad: cur={r1_cur}"
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


def scenario_item_mgt_ranged_throw_and_egos(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test OVL_ITEM_MGT: g/d/w/t/E/R, ranged 'F' bow+arrow, 'T' throw, & ego generation/naming."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Archer")
        _clear_all_monsters(cli, syms)
        st = cli.read_z80_state()
        px, py = st["player_x"], st["player_y"]

        # 1. Floor pickup ('g') -> drop ('da') -> verify fi_item_id & FLAG_ITEM roundtrip
        _set_map_tile(cli, px, py, _get_map_tile(cli, px, py) | 0x02)
        _write_mem(cli, syms["fi_item_id"], [41] + [0xFF] * 41)  # slot 0 = Ration of Food (41)
        _write_mem(cli, syms["fi_x"], [px])
        _write_mem(cli, syms["fi_y"], [py])
        _write_mem(cli, syms["fi_qty"], [1])
        _write_mem(cli, syms["zp_item_count"], [1])
        _write_mem(cli, syms["abi_item_count"], [1])
        cli.send_keys("g")
        cli.run_idle()
        assert cli.read_mem(syms["zp_item_count"], 1)[0] == 0, "Pickup 'g' left floor item"
        assert (_get_map_tile(cli, px, py) & 0x02) == 0, "Pickup 'g' left FLAG_ITEM"

        # 2. Eat ('E') food ration (lower PL_FOOD_LO first so we verify gain)
        _write_mem(cli, syms["player_data"] + 51, [100, 0])
        # Find ration (id 41) slot in pack 0..21
        pack_ids = cli.read_mem(syms["inv_item_id"], 22)
        ration_slot = pack_ids.index(41)
        cli.send_keys("E")
        cli.run_idle()
        food_after = struct.unpack("<H", cli.read_mem(syms["player_data"] + 51, 2))[0]
        assert food_after > 100, f"Eat 'E' failed to increase food: {food_after}"

        # 3. Takeoff ('t') body armor (b -> EQUIP_BODY) -> wear ('w') back
        arm_id = cli.read_mem(syms["inv_item_id"] + 23, 1)[0]
        pre_ac = cli.read_mem(syms["player_data"] + 39, 1)[0]
        cli.send_keys("tb")
        cli.run_idle()
        assert cli.read_mem(syms["inv_item_id"] + 23, 1)[0] == 0xFF, "Takeoff 'tb' failed to clear EQUIP_BODY"
        assert cli.read_mem(syms["player_data"] + 39, 1)[0] < pre_ac, "Takeoff failed to lower PL_AC"
        # Wear back the removed body armor in pack
        pack_ids = cli.read_mem(syms["inv_item_id"], 22)
        arm_slot = pack_ids.index(arm_id)
        cli.send_keys("w")
        cli.run_idle()
        vis_cnt = cli.read_mem(syms["piw_visible_count"], 1)[0]
        vis_slots = list(cli.read_mem(syms["piw_visible_slots"], vis_cnt))
        cli.send_keys(chr(ord("a") + vis_slots.index(arm_slot)))
        cli.run_idle()
        assert cli.read_mem(syms["inv_item_id"] + 23, 1)[0] == arm_id, "Wear 'w' failed to equip body armor"

        # 3b. Regression: _im_wear wearing from pack slot >= 1 preserves slot 0 (piw_slot not clobbered by _im_inv_to_fi_add)
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _write_mem(cli, syms["inv_item_id"] + 28, [0xFF])  # clear EQUIP_LIGHT
        _set_inv_item(cli, syms, 0, 41, qty=1, flags=0x02)  # Ration at slot 0
        _set_inv_item(cli, syms, 2, 195, qty=1, p1=100, flags=0x02)  # Torch at slot 2
        cli.send_keys("w")
        cli.run_idle()
        vis_cnt_w = cli.read_mem(syms["piw_visible_count"], 1)[0]
        vis_slots_w = list(cli.read_mem(syms["piw_visible_slots"], vis_cnt_w))
        cli.send_keys(chr(ord("a") + vis_slots_w.index(2)))
        cli.run_idle()
        assert cli.read_mem(syms["inv_item_id"] + 28, 1)[0] == item_ids.ITEM_SLOT_WOODEN_TORCH, "Wear Torch from slot 2 failed"
        assert cli.read_mem(syms["inv_item_id"] + 0, 1)[0] == item_ids.ITEM_SLOT_RATION_OF_FOOD, "_im_wear clobbered slot 0 instead of removing piw_slot 2"
        assert cli.read_mem(syms["inv_item_id"] + 2, 1)[0] == 0xFF, "_im_wear failed to remove piw_slot 2"

        # 4. Refuel ('R') Brass Lantern (194, p1=50) with Flask of Oil (196, p1=100)
        _set_inv_item(cli, syms, 28, 194, qty=1, p1=50)  # EQUIP_LIGHT
        _set_inv_item(cli, syms, 5, 196, qty=1, p1=100, flags=0)  # Flask of Oil in pack
        cli.send_keys("R")
        cli.run_idle()
        assert cli.read_mem(syms["inv_p1"] + 28, 1)[0] == 150, (
            f"Refuel 'R' failed exact 50+100=150 (inv_consume_one clobbered C?): {cli.read_mem(syms['inv_p1'] + 28, 1)[0]}"
        )
        assert cli.read_mem(syms["inv_item_id"] + 5, 1)[0] == 0xFF, "Refuel 'R' did not consume flask"

        # 4b. Regression: _im_wear torch-stack swap when BOTH pack (22/22) and floor (42/42) are full aborts without losing torch or lantern
        cli.write_mem(syms["inv_item_id"], bytes([41] * 22))
        cli.write_mem(syms["inv_qty"], bytes([1] * 22))
        _set_inv_item(cli, syms, 21, 195, qty=2, p1=100, flags=0x02)  # Wooden Torch stack (slot 'v')
        _set_inv_item(cli, syms, 28, 194, qty=1, p1=150, flags=0x02)  # Brass Lantern equipped
        cli.write_mem(syms["fi_item_id"], bytes([65] * 42))
        _write_mem(cli, syms["zp_item_count"], [42])
        _write_mem(cli, syms["abi_item_count"], [42])
        cli.send_keys("w")
        cli.run_idle()
        vis_cnt_f = cli.read_mem(syms["piw_visible_count"], 1)[0]
        vis_slots_f = list(cli.read_mem(syms["piw_visible_slots"], vis_cnt_f))
        cli.send_keys(chr(ord("a") + vis_slots_f.index(21)))
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_item_id"] + 28, 1)[0] == item_ids.ITEM_SLOT_BRASS_LANTERN, "Full torch swap clobbered EQUIP_LIGHT"
        assert cli.read_mem(syms["inv_qty"] + 21, 1)[0] == 2, "Full torch swap consumed torch before overflow abort"
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))

        # 5. Descend to DL1 -> Test ranged 'F' (Short Bow 234 + Arrow 240) and 'T' throw onto monster + Ego naming
        _set_map_tile(cli, px + 1, py, 0x9C)
        _walk_steps(cli, "l>")
        _clear_all_monsters(cli, syms)
        st_d = cli.read_z80_state()
        dpx, dpy = st_d["player_x"], st_d["player_y"]
        for dx in range(1, 5):
            _set_map_tile(cli, dpx + dx, dpy, 0x0C)
        # Put 1 monster at (dpx+3, dpy) via slot 0 with valid loaded cr_type=0 (cat 25)
        cli.send_keys("\x17y\x17s")
        cli.run_idle()
        _write_mem(cli, syms["abi_game_flags"], [0])
        _write_mem(cli, syms["zp_game_flags"], [0])
        rows = [r for r in _read_monster_slots(cli, syms) if r[3] != 0xFF]
        sidx, mx0, my0, cr_t, _, _ = rows[0]
        _set_map_tile(cli, mx0, my0, _get_map_tile(cli, mx0, my0) & ~0x01)
        _set_map_tile(cli, dpx + 3, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 3, dpy, cr_t, 80, 0, 0x1A, 0, 0, 0, 0, 0, 0])

        # Equip Short Bow (234) + give Slay-Evil ego Long Sword in slot 3 (test 'i' ego naming!) + 5 Arrows (240) in slot 2
        _set_inv_item(cli, syms, 22, 234, qty=1, to_hit=20, to_dam=5, flags=0x02, ego=0)  # Short Bow
        _set_inv_item(cli, syms, 0, 240, qty=5, to_hit=20, to_dam=5, flags=0x02, ego=0)  # Arrows at pack 'a'
        _set_inv_item(cli, syms, 1, 25, qty=1, flags=0x02, ego=0x40 | 2)  # Long Sword of Slay Evil (id=25, page=0x40, ego=EGO_SLAY_EVIL)
        cli.send_keys("i")
        cli.run_idle()
        inv_text = "\n".join(cli.screen_lines()[0])
        assert "Slay Evil" in inv_text, f"Ego name missing from 'i' inventory:\n{inv_text}"
        cli.send_keys("Q")
        cli.run_idle()

        # Verify 22-item full pack renders 'v)' cleanly without footer overwrite on both 'i' and 'd ?'
        for s_full in range(22):
            _set_inv_item(cli, syms, s_full, 41, qty=1, flags=0x02, ego=0)
        cli.send_keys("i")
        cli.run_idle()
        full_i_rows = cli.screen_lines()[0]
        assert any("v)" in r and "Press any key" not in r for r in full_i_rows), (
            f"Full 22-item 'i' missing/overwrote 'v)':\n" + "\n".join(full_i_rows)
        )
        cli.send_keys("Q")
        cli.run_idle()
        cli.send_keys("d?")
        cli.run_idle()
        assert cli.read_mem(syms["piw_visible_count"], 1)[0] == 22, "Full 22-item 'd ?' piw_visible_count != 22"
        full_d_rows = cli.screen_lines()[0]
        assert any("v)" in r and "Select item" not in r for r in full_d_rows), (
            f"Full 22-item 'd ?' missing/overwrote 'v)':\n" + "\n".join(full_d_rows)
        )
        cli.send_keys("\x1b")
        cli.run_idle()
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 240, qty=5, to_hit=20, to_dam=5, flags=0x02, ego=0)
        _set_inv_item(cli, syms, 1, 25, qty=1, flags=0x02, ego=0x40 | 2)

        # Verify 'd ?' (Drop) and 't ?' (Takeoff) filter exact non-empty slots without DE clobber phantom rows
        occ_pack = sum(1 for v in cli.read_mem(syms["inv_item_id"], 22) if v != 0xFF)
        cli.send_keys("d?")
        cli.run_idle()
        assert cli.read_mem(syms["piw_visible_count"], 1)[0] == occ_pack, (
            f"'d ?' piw_visible_count {cli.read_mem(syms['piw_visible_count'], 1)[0]} != {occ_pack}"
        )
        cli.send_keys("\x1b")
        cli.run_idle()

        occ_equip = sum(1 for v in cli.read_mem(syms["inv_item_id"] + 22, 11) if v != 0xFF)
        cli.send_keys("t?")
        cli.run_idle()
        assert cli.read_mem(syms["piw_visible_count"], 1)[0] == occ_equip, (
            f"'t ?' piw_visible_count {cli.read_mem(syms['piw_visible_count'], 1)[0]} != {occ_equip}"
        )
        t_modal_blob = "\n".join(cli.screen_lines()[0])
        assert "Equipment" in t_modal_blob and "Weapon:" in t_modal_blob and "(none)" in t_modal_blob, (
            f"'t ?' selector missing 6502 slot labels/(none):\n{t_modal_blob}"
        )
        cli.send_keys("\x1b")
        cli.run_idle()

        # Regression (6502 player_item_commands.s): wear single-item swap keeps old equip in same pack slot in-place
        cli.send_keys("wb")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_item_id"] + 22, 1)[0] == item_ids.ITEM_SLOT_LONG_SWORD, "Wear swap failed to equip Long Sword from slot 1"
        assert cli.read_mem(syms["inv_item_id"] + 1, 1)[0] == item_ids.ITEM_SLOT_SHORT_BOW, (
            f"Single-item wear swap failed to place old Short Bow in-place at slot 1: got {cli.read_mem(syms['inv_item_id'] + 1, 1)[0]}"
        )
        assert cli.read_mem(syms["inv_item_id"] + 0, 1)[0] == item_ids.ITEM_SLOT_ARROW, "Wear swap shifted unrelated slot 0"
        assert cli.read_mem(syms["inv_item_id"] + 2, 1)[0] == 0xFF, "Wear swap appended to slot 2 instead of swapping in-place"
        # Swap Short Bow back into EQUIP_WEAPON and put Arrows back in slot 0, Long Sword in slot 1 for Ranged/Throw
        _set_inv_item(cli, syms, 22, 234, qty=1, to_hit=20, to_dam=5, flags=0x02, ego=0)
        _set_inv_item(cli, syms, 0, 240, qty=5, to_hit=20, to_dam=5, flags=0x02, ego=0)
        _set_inv_item(cli, syms, 1, 25, qty=1, flags=0x02, ego=0x40 | 2)
        # Ensure monster in slot sidx is asleep & unprovoked (flags=0x08 MF_VISIBLE, sleep=10) to verify ranged does NOT set MF_PROVOKED
        cur_pre_f = _read_monster_slots(cli, syms)[sidx]
        if cur_pre_f[3] != 0xFF:
            _set_map_tile(cli, cur_pre_f[1], cur_pre_f[2], _get_map_tile(cli, cur_pre_f[1], cur_pre_f[2]) & ~0x01)
        _set_map_tile(cli, dpx + 3, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 3, dpy, cr_t, 80, 0, 0x08, 0, 10, 0, 0, 0, 0])

        # Fire arrow 'Fl' at monster before throwing Long Sword ('Tbl').
        # Equip Chain Mail (223) + Cloak (211) so inv_calc_weight caches 0d0 Cloak -> proves icat_select_id reloads Arrow 1d4!
        _set_inv_item(cli, syms, 23, 223, qty=1, flags=0x02, ego=0)
        _set_inv_item(cli, syms, 32, 211, qty=1, flags=0x02, ego=0)
        _write_mem(cli, syms["cr_ac"] + cr_t, [0])
        _write_mem(cli, syms["player_data"] + 30, [118])  # PL_DEX_CUR max
        _write_mem(cli, syms["player_data"] + 27, [118])  # PL_STR_CUR max (tests 'T' STR dmg load!)
        _write_mem(cli, syms["abi_rng_seed"], [0x12, 0x34, 0x56, 0x78])
        hp_mon0 = _read_monster_slots(cli, syms)[sidx][4]
        shots = 0
        msg_f = ""
        hp_mon1 = hp_mon0
        for _ in range(4):
            prev_f = _read_monster_slots(cli, syms)[sidx][4]
            cli.send_keys("Fl")
            cli.run_idle()
            msg_f = cli.screen_lines()[0][0]
            _dismiss_more(cli)
            shots += 1
            hp_mon1 = _read_monster_slots(cli, syms)[sidx][4]
            if hp_mon1 < prev_f:
                hp_mon0 = prev_f
                break
        assert hp_mon1 < hp_mon0 and (hp_mon0 - hp_mon1) >= 22, (
            f"Ranged 'F' failed Arrow 1d4 dmg with worn Cloak: {hp_mon0} -> {hp_mon1} ({msg_f!r})"
        )
        assert "(+20,+5)" not in msg_f, f"Ranged 'F' leaked identified stats (6502 item_append_name parity): {msg_f!r}"
        assert cli.read_mem(syms["inv_qty"] + 0, 1)[0] == 5 - shots, "Ranged 'F' did not consume fired Arrows"
        assert (cli.read_mem(syms["monster_table"] + sidx * 12 + 5, 1)[0] & 0x04) == 0, (
            "Ranged 'F' must not set MF_PROVOKED (6502 parity)"
        )
        assert cli.read_mem(syms["monster_table"] + sidx * 12 + 7, 1)[0] == 0, (
            "Ranged 'F' survive failed to wake monster"
        )

        # Ranged 'F' fatal blow must print "You have slain the <name>."
        _set_inv_item(cli, syms, 0, 240, qty=5, to_hit=20, to_dam=5, flags=0x02, ego=0)
        cur_mon = _read_monster_slots(cli, syms)[sidx]
        if cur_mon[3] != 0xFF:
            _set_map_tile(cli, cur_mon[1], cur_mon[2], _get_map_tile(cli, cur_mon[1], cur_mon[2]) & ~0x01)
        _set_map_tile(cli, dpx + 3, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 3, dpy, cr_t, 1, 0, 0x1A, 0, 0, 0, 0, 0, 0])
        slay_msg_f = ""
        for _ in range(4):
            cli.send_keys("Fl")
            cli.run_idle()
            slay_msg_f = cli.screen_lines()[0][0]
            _dismiss_more(cli)
            if _read_monster_slots(cli, syms)[sidx][3] == 0xFF:
                break
        assert "You have slain the" in slay_msg_f, f"Ranged 'F' kill missed slay msg: {slay_msg_f!r}"
        _set_map_tile(cli, dpx + 3, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 3, dpy, cr_t, 50, 0, 0x1A, 0, 0, 0, 0, 0, 0])
        hp_mon1 = 50

        # Throw Long Sword ('Tbl') at monster (retry on 5% nat-1) and verify damage + single-item removal!
        msg_t = ""
        hp_mon2 = hp_mon1
        for _ in range(3):
            _set_inv_item(cli, syms, 1, 25, qty=1, flags=0x02, ego=0x40 | 2)
            cli.send_keys("Tbl")
            cli.run_idle()
            msg_t = cli.screen_lines()[0][0]
            _dismiss_more(cli)
            hp_mon2 = _read_monster_slots(cli, syms)[sidx][4]
            if hp_mon2 < hp_mon1:
                break
        assert hp_mon2 < hp_mon1, f"Throw 'T' failed to hit monster: {hp_mon1} -> {hp_mon2} ({msg_t!r})"
        assert ("hits the" in msg_f) or ("hits the" in msg_t), (
            f"_im_print_ammo_vs_mon overwrote verb: msg_f={msg_f!r}, msg_t={msg_t!r}"
        )
        assert cli.read_mem(syms["inv_item_id"] + 1, 1)[0] == 0xFF, "Throw 'T' did not remove Long Sword from pack"

        # Throw 'T' fatal blow must print "You have slain the <name>."
        cur_mon = _read_monster_slots(cli, syms)[sidx]
        if cur_mon[3] != 0xFF:
            _set_map_tile(cli, cur_mon[1], cur_mon[2], _get_map_tile(cli, cur_mon[1], cur_mon[2]) & ~0x01)
        _set_map_tile(cli, dpx + 3, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 3, dpy, cr_t, 1, 0, 0x1A, 0, 0, 0, 0, 0, 0])
        slay_msg_t = ""
        for _ in range(4):
            _set_inv_item(cli, syms, 1, 25, qty=1, to_hit=20, to_dam=5, flags=0x02, ego=0x40 | 2)
            cli.send_keys("Tbl")
            cli.run_idle()
            slay_msg_t = cli.screen_lines()[0][0]
            _dismiss_more(cli)
            if _read_monster_slots(cli, syms)[sidx][3] == 0xFF:
                break
        assert "You have slain the" in slay_msg_t, f"Throw 'T' kill missed slay msg: {slay_msg_t!r}"

        # Regression: negative throw tohit clamps to 0 BEFORE mul_hl_a * 3 / 4 (with clamped 0 vs AC 5, only 5% nat-20 hits; wrapped 255 hits ~95%)
        _set_map_tile(cli, dpx + 3, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["cr_ac"] + cr_t, [5])
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 3, dpy, cr_t, 200, 0, 0x08, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["player_data"] + 19, [1])
        _write_mem(cli, syms["abi_player_lvl"], [1])
        _write_mem(cli, syms["player_data"] + 30, [3])  # min DEX
        _set_inv_item(cli, syms, 1, 12, qty=5, to_hit=(-50) & 0xFF, flags=0x02, ego=0)  # Broken Dagger -50
        neg_hits = 0
        for _ in range(5):
            prev_n = _read_monster_slots(cli, syms)[sidx][4]
            cli.send_keys("Tbl")
            cli.run_idle()
            _dismiss_more(cli)
            cur_n = _read_monster_slots(cli, syms)[sidx][4]
            if cur_n < prev_n:
                neg_hits += 1
        assert neg_hits <= 2, f"Negative throw tohit wrapped to 255 ({neg_hits}/5 hits vs AC 5)"
        # Regression: throwing an unidentified light omits "(N turns)" and "(magik)"
        _set_inv_item(cli, syms, 1, item_ids.ITEM_SLOT_WOODEN_TORCH, qty=1, p1=50, flags=0x08, ego=0)
        cli.send_keys("Tbl")
        cli.run_idle()
        torch_msg = cli.screen_lines()[0][0]
        _dismiss_more(cli)
        assert "Wooden Torch" in torch_msg and "turns)" not in torch_msg and "magik" not in torch_msg, (
            f"Thrown unidentified Wooden Torch printed unexpected suffix: {torch_msg!r}"
        )
        cli.write_mem(syms["inv_item_id"] + 1, b"\xFF")
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])

        # Regression: ovl_actions_bash_monster loads EQUIP_SHIELD dice via icat_select_id even with worn Cloak cached
        _set_map_tile(cli, dpx + 3, dpy, 0x0C)
        _set_map_tile(cli, dpx + 1, dpy, 0x0C | 0x01)
        _write_mem(cli, syms["cr_ac"] + cr_t, [0])
        _write_mem(cli, syms["monster_table"] + sidx * 12, [dpx + 1, dpy, cr_t, 50, 0, 0x08, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["player_data"] + 19, [20])
        _write_mem(cli, syms["abi_player_lvl"], [20])
        _write_mem(cli, syms["player_data"] + 27, [118])
        _write_mem(cli, syms["player_data"] + 30, [118])
        _write_mem(cli, syms["zp_eff_paralyze"], [0])
        _set_inv_item(cli, syms, 24, 2, qty=1, to_ac=1, flags=0x02, ego=0x40)  # Small Shield (id 2, Page 1)
        _set_inv_item(cli, syms, 32, 211, qty=1, flags=0x02, ego=0)          # Cloak
        mhp_b = 50
        for _ in range(5):
            _write_mem(cli, syms["zp_eff_paralyze"], [0])
            cli.send_keys("\x02l")
            cli.run_idle()
            _dismiss_more(cli)
            mhp_b = _read_monster_slots(cli, syms)[sidx][4]
            if mhp_b < 50 or _read_monster_slots(cli, syms)[sidx][3] == 0xFF:
                break
        assert mhp_b < 50 or _read_monster_slots(cli, syms)[sidx][3] == 0xFF, "Shield bash failed to damage monster"

        # Regression: occupied-slot wear swap preserves 9th byte fi_add_ego (0x40|ego)
        _set_inv_item(cli, syms, 22, 25, qty=1, flags=0x02, ego=0x40 | 2)
        _set_inv_item(cli, syms, 1, 25, qty=1, flags=0x02, ego=0x40 | 4)
        cli.send_keys("wb")
        cli.run_idle()
        _dismiss_more(cli)
        _clear_all_monsters(cli, syms)
        assert cli.read_mem(syms["inv_ego"] + 22, 1)[0] == (0x40 | 4), "Wear swap lost new ego"
        assert (0x40 | 2) in cli.read_mem(syms["inv_ego"], 22), "Wear swap stripped 0x40|ego on swapped-out weapon"

        # Regression: Torch (195) radius == 1, Lantern (194) radius == 1 (6502 parity)
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _write_mem(cli, syms["inv_item_id"] + 28, [0xFF])
        _write_mem(cli, syms["player_data"] + 55, [0])
        _write_mem(cli, syms["abi_light_rad"], [0])
        _set_inv_item(cli, syms, 0, 195, qty=1, p1=100, flags=0x02, ego=0)  # Wooden Torch at 'a'
        cli.send_keys("wa")
        cli.run_idle()
        assert cli.read_z80_state()["light_rad"] == 1, "Equipped Wooden Torch must set light_rad == 1"
        _set_inv_item(cli, syms, 0, 194, qty=1, p1=100, flags=0x02, ego=0)  # Brass Lantern at 'a'
        cli.send_keys("wa")
        cli.run_idle()
        assert cli.read_z80_state()["light_rad"] == 1, "Equipped Brass Lantern must set light_rad == 1"

        # MON-044 live production wear/takeoff test via OVL_ITEM_MGT -> OVL_MODAL -> player_step_equip_stat_c:
        # Clear rings, verify STR 17 +3 -> 38 (18/20), CON 18 +8 -> 98 (18/80) crossing con_adj>=94 (+MHP),
        # takeoff back to (17, 18) lowering MHP, and floor 3 -2 -> (cur=3, res=0xFE) -> takeoff (cur=3, res=0).
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _write_mem(cli, syms["inv_item_id"] + 29, [0xFF])
        _write_mem(cli, syms["inv_item_id"] + 31, [0xFF])
        _write_mem(cli, syms["player_eq_stat_mod"], [0] * 6)
        _write_mem(cli, syms["player_stat_res"], [0] * 6)
        _write_mem(cli, syms["player_data"] + 21, [17, 12, 12, 12, 18, 12])  # BASE: STR=17, CON=18
        _write_mem(cli, syms["player_data"] + 27, [17, 12, 12, 12, 18, 12])  # CUR:  STR=17, CON=18
        _set_inv_item(cli, syms, 0, 54, qty=1, p1=3, flags=0x02, ego=0x40)   # Ring of Strength (+3) at 'a'
        _set_inv_item(cli, syms, 1, 56, qty=1, p1=8, flags=0x02, ego=0x40)   # Ring of Gain CON (+8) at 'b'
        _set_inv_item(cli, syms, 2, 67, qty=1, p1=((-2) & 0xFF), flags=0x02, ego=0x40)  # Ring of Weakness (-2)
        cli.send_keys("wa")  # wear Ring of Strength (+3) -> recalcs MHP at CON=18, STR 17 -> 38
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_data"] + 27, 1)[0] == 38, "MON-044 live wear Ring+3 from STR 17 expected 38"
        mhp_con18 = cli.read_z80_state()["mhp"]
        cli.send_keys("wa")  # wear Ring of Gain CON (+8) -> CON 18 -> 98 (con_adj 2->3) & MHP rises
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_data"] + 31, 1)[0] == 98, "MON-044 live wear Ring+8 from CON 18 expected 98"
        mhp_con98 = cli.read_z80_state()["mhp"]
        assert mhp_con98 > mhp_con18, f"MON-044 live CON 18->98 did not raise MHP: {mhp_con18} -> {mhp_con98}"
        # Take off both rings
        eq_now = cli.read_mem(syms["inv_item_id"] + 22, 11)
        r2_ord = sum(1 for i in range(9) if eq_now[i] != 0xFF)
        r1_ord = sum(1 for i in range(7) if eq_now[i] != 0xFF)
        cli.send_keys("t" + chr(ord("a") + r2_ord))
        cli.run_idle()
        _dismiss_more(cli)
        cli.send_keys("t" + chr(ord("a") + r1_ord))
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_data"] + 27, 1)[0] == 17 and cli.read_mem(syms["player_stat_res"], 1)[0] == 0
        assert (
            cli.read_mem(syms["player_data"] + 31, 1)[0] == 18
            and cli.read_mem(syms["player_stat_res"] + 4, 1)[0] == 0
            and mhp_con98 - cli.read_z80_state()["mhp"] == 19
        )
        # Floor 3 -2 -> (3, 0xFE) -> takeoff -> (3, 0)
        _write_mem(cli, syms["player_data"] + 21, [3])
        _write_mem(cli, syms["player_data"] + 27, [3])
        _write_mem(cli, syms["player_stat_res"], [0])
        cli.send_keys("wa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_data"] + 27, 1)[0] == 3 and cli.read_mem(syms["player_stat_res"], 1)[0] == 0xFE
        cli.send_keys("t" + chr(ord("a") + sum(1 for i in range(7) if cli.read_mem(syms["inv_item_id"] + 22, 11)[i] != 0xFF)))
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_data"] + 27, 1)[0] == 3 and cli.read_mem(syms["player_stat_res"], 1)[0] == 0

        # Regression (ovl_modal JP PO overflow recovery): old_mod == -128 (0x80) at base=118 -> cur=3, res=-103;
        # equipping +5 STR ring makes new - old overflow signed 8-bit, undoing -128 in two +64 steps + 5 -> (118, 50)
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 54, qty=1, p1=5, flags=0x02, ego=0x40)  # Ring of Strength (+5) at 'a'
        _write_mem(cli, syms["player_data"] + 21, [118])
        _write_mem(cli, syms["player_data"] + 27, [3])
        _write_mem(cli, syms["player_stat_res"], [0x99])     # -103 residual from -128 stepping off 118
        _write_mem(cli, syms["player_eq_stat_mod"], [0x80])  # -128
        cli.send_keys("wa")
        cli.run_idle()
        _dismiss_more(cli)
        assert (
            cli.read_mem(syms["player_data"] + 27, 1)[0] == 118
            and cli.read_mem(syms["player_stat_res"], 1)[0] == 50
            and cli.read_mem(syms["player_eq_stat_mod"], 1)[0] == 5
        ), (
            "ovl_modal JP PO old_mod=-128 overflow recovery failed: "
            f"cur={cli.read_mem(syms['player_data'] + 27, 1)[0]} res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        _write_mem(cli, syms["inv_item_id"] + 29, [0xFF])
        _write_mem(cli, syms["player_eq_stat_mod"], [0] * 6)
        _write_mem(cli, syms["player_stat_res"], [0] * 6)

        # Stage Arrow (240) at slot 0 and test 'd' drop ('da')
        _set_inv_item(cli, syms, 0, 240, qty=2, flags=0x02, ego=0)
        cli.send_keys("da")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["zp_item_count"], 1)[0] >= 1, "Drop 'd' did not place item on floor"
        _quit_game_and_title(cli)


def scenario_items_potions_scrolls_wands_staves(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test OVL_ITEMS + OVL_ITEMS_EFF: 'q' quaff, 'r' read, 'a' aim wand, 'z' use staff, flavor propagation."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        _create_human_warrior(cli, name="Alch")
        _clear_all_monsters(cli, syms)
        st = cli.read_z80_state()
        _set_map_tile(cli, st["player_x"] + 1, st["player_y"], 0x9C)
        _walk_steps(cli, "l>")
        _clear_all_monsters(cli, syms)

        # Spawn a monster at (px+2, py) for wand & detect evil staff
        cli.send_keys("\x17y\x17s")
        cli.run_idle()
        _write_mem(cli, syms["abi_game_flags"], [0])
        _write_mem(cli, syms["zp_game_flags"], [0])
        st_d = cli.read_z80_state()
        px, py = st_d["player_x"], st_d["player_y"]
        rows = [r for r in _read_monster_slots(cli, syms) if r[3] != 0xFF]
        sidx, mx0, my0, cr_t, _, _ = rows[0]
        _set_map_tile(cli, mx0, my0, _get_map_tile(cli, mx0, my0) & ~0x01)
        _set_map_tile(cli, px + 1, py, 0x0C)
        _set_map_tile(cli, px + 2, py, 0x0C | 0x01)
        # Set CF_EVIL (0x04) on cr_mflags[cr_t] so Detect Evil triggers cleanly; HP=15 so wand damages cleanly
        _write_mem(cli, syms["cr_mflags"] + cr_t, [cli.read_mem(syms["cr_mflags"] + cr_t, 1)[0] | 0x04])
        _write_mem(cli, syms["monster_table"] + sidx * 12, [px + 2, py, cr_t, 15, 0, 0x08, 0, 0, 0, 0, 0, 0])

        # Stage clean pack slots:
        # 0: Potion of Healing (65) qty=2, flags=0 (unidentified) -> quaff 1st learns flavor!
        # 1: Scroll of Phase Door (102) qty=1
        # 2: Wand of Magic Missile (150) qty=1, p1=3 charges
        # 3: Staff of Detect Evil (181) qty=1, p1=4 charges
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 65, qty=2, p1=200, flags=0, ego=0)
        _set_inv_item(cli, syms, 1, 102, qty=1, p1=0, flags=0, ego=0)
        _set_inv_item(cli, syms, 2, 150, qty=1, p1=3, flags=2, ego=0)
        _set_inv_item(cli, syms, 3, 181, qty=1, p1=4, flags=2, ego=0)

        # 1. Quaff ('qa') at HP=5 -> heals & marks Potion of Healing known
        _write_mem(cli, syms["player_data"] + 33, [5, 0])
        _write_mem(cli, syms["abi_player_hp"], [5, 0])
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["hp"] > 5, "Potion of Healing failed to heal"
        assert cli.read_mem(syms["inv_qty"] + 0, 1)[0] == 1, "Potion qty did not decrement"
        cli.send_keys("i")
        cli.run_idle()
        assert "Healing" in "\n".join(cli.screen_lines()[0]), "Flavor knowledge did not propagate for Healing"
        cli.send_keys("Q")
        cli.run_idle()

        # 2. Aim Wand of Magic Missile ('aal' — filtered to wands -> 'a' picks slot 2, dir 'l' East)
        mhp_mm0 = _read_monster_slots(cli, syms)[sidx][4]
        cli.send_keys("aal")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_p1"] + 2, 1)[0] == 2, "Wand of Magic Missile failed to decrement p1 3->2"
        assert _read_monster_slots(cli, syms)[sidx][4] < mhp_mm0, "Wand of Magic Missile failed to damage monster"

        # 2b. Regression (6502 item_actions_overlay.s:381): cancelling wand direction still spends charge + consumes turn
        t_wand0 = cli.read_z80_state()["turn"]
        cli.send_keys("aa\x1b")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_p1"] + 2, 1)[0] == 1, "Wand cancel failed to spend charge"
        assert cli.read_z80_state()["turn"] > t_wand0, "Wand cancel failed to consume turn"

        # 3. Use Staff of Detect Evil ('za' — filtered to staves -> 'a' picks slot 3)
        cli.send_keys("za")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["inv_p1"] + 3, 1)[0] == 3, "Staff of Detect Evil failed to decrement p1 4->3"

        # 4. Read Scroll of Phase Door ('ra' — filtered to scrolls -> 'a' picks slot 1)
        # Ensure open floor within range <= 10 so Phase Door stays local (dist <= 10)
        for dy_p in range(-2, 3):
            for dx_p in range(-2, 3):
                if (dx_p, dy_p) != (0, 0):
                    _set_map_tile(cli, px + dx_p, py + dy_p, 0x0C)
        pos0 = (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"])
        cli.send_keys("ra")
        cli.run_idle()
        _dismiss_more(cli)
        assert 102 not in cli.read_mem(syms["inv_item_id"], 22), "Scroll of Phase Door not consumed"
        pos1 = (cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"])
        phase_dist = max(abs(pos1[0] - pos0[0]), abs(pos1[1] - pos0[1]))
        assert 1 <= phase_dist <= 10, f"Phase Door teleported out of [1..10] range: {pos0}->{pos1} (dist={phase_dist})"

        # 5. Regression: Heroism raises PL_MHP +10 and expiry restores exact pre-Heroism MHP
        st_h = cli.read_z80_state()
        mhp0 = st_h["mhp"]
        _set_inv_item(cli, syms, 0, 84, qty=1, flags=0x02)  # Potion of Heroism
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["mhp"] == mhp0 + 10, "Heroism failed to raise PL_MHP by +10"
        _write_mem(cli, syms["zp_eff_hero"], [1])
        cli.send_keys("5")
        cli.run_idle()
        assert cli.read_z80_state()["mhp"] == mhp0, "Heroism expiry failed to restore exact base MHP"

        # 6. Regression: Wand of Light lights player room (6502 eff_light_and_report); Wand of Disarm removes trap & disarms chest
        px, py = cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]
        _write_mem(cli, syms["room_count"], [1])
        _write_mem(cli, syms["room_x"], [px])
        _write_mem(cli, syms["room_y"], [py])
        _write_mem(cli, syms["room_w"], [2])
        _write_mem(cli, syms["room_h"], [2])
        _write_mem(cli, syms["room_lit"], [0])
        _set_map_tile(cli, px + 1, py, 0x00 | 0x02)  # chest at (px+1, py), unlit
        _set_map_tile(cli, px + 2, py, 0xE0)         # TILE_TRAP unlit
        _set_map_tile(cli, px + 3, py, 0x00 | 0x02)  # floor with non-chest potion
        _write_mem(cli, syms["trap_count"], [1])
        _write_mem(cli, syms["trap_x"], [px + 2])
        _write_mem(cli, syms["trap_y"], [py])
        _write_mem(cli, syms["trap_type"], [1])
        _write_mem(cli, syms["fi_item_id"], [65, 204, 0xFF])  # slot 0 = Potion of Healing, slot 1 = Chest
        _write_mem(cli, syms["fi_x"], [px + 3, px + 1])
        _write_mem(cli, syms["fi_y"], [py, py])
        _write_mem(cli, syms["fi_qty"], [1, 1])
        _write_mem(cli, syms["fi_p1"], [200, 0x45])           # chest LOCKED | TRAP_POISON | TRAP_FOUND
        _write_mem(cli, syms["fi_meta_hi"], [0, 48])          # EGO_CHEST_POISON (48)
        _write_mem(cli, syms["zp_item_count"], [2])
        _write_mem(cli, syms["abi_item_count"], [2])
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 137, qty=1, p1=3, flags=2)  # Wand of Light
        _set_inv_item(cli, syms, 1, 154, qty=1, p1=3, flags=2)  # Wand of Disarming
        _set_inv_item(cli, syms, 2, 144, qty=1, p1=3, flags=2)  # Wand of Haste Monster
        _set_inv_item(cli, syms, 3, 173, qty=1, p1=3, flags=2)  # Staff of Slow Monsters
        cli.send_keys("aa")
        cli.run_idle()
        assert cli.read_z80_state()["player_x"] == px, "Wand of Light unexpectedly prompted or moved player"
        assert "-more-" not in cli.screen_lines()[0][0], (
            f"Wand of Light double-printed message: {cli.screen_lines()[0][0]!r}"
        )
        _dismiss_more(cli)
        assert (_get_map_tile(cli, px + 1, py) & 0x08) != 0, "Wand of Light failed to set FLAG_LIT in player room"
        assert cli.read_mem(syms["room_lit"], 1)[0] == 1, "Wand of Light failed to set room_lit[0]"
        cli.send_keys("abl")
        cli.run_idle()
        assert (_get_map_tile(cli, px + 2, py) & 0xF0) == 0x00, "Wand of Disarm failed to clear TILE_TRAP"
        assert cli.read_mem(syms["trap_count"], 1)[0] == 0, "Wand of Disarm failed to remove trap_x/y entry"
        assert cli.read_mem(syms["fi_p1"], 1)[0] == 200, "Wand of Disarm clobbered non-chest fi_p1"
        assert cli.read_mem(syms["fi_p1"] + 1, 1)[0] == 0x40, "Wand of Disarm dropped CHEST_P1_TRAP_FOUND"
        assert (cli.read_mem(syms["fi_meta_hi"] + 1, 1)[0] & 0x3F) == 48, "Wand of Disarm altered fi_meta_hi ego"

        # 7. Regression: Wand of Haste Monster & Staff of Slow Monsters set MX_SPEED_CNT properly
        _write_mem(cli, syms["cr_cdefense"] + cr_t, [0])
        _write_mem(cli, syms["cr_atk0_type"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_chance"] + cr_t, [0])
        _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"], [px + 1, py, cr_t, 50, 0, 0x00, 0, 5, 0, 0, 0, 0])
        _write_mem(cli, syms["monster_table"] + 12, [px + 4, py, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        cli.send_keys("acl")
        cli.run_idle()
        _dismiss_more(cli)
        slot0 = cli.read_mem(syms["monster_table"], 12)
        slot1 = cli.read_mem(syms["monster_table"] + 12, 12)
        assert slot0[6] == 1, f"Wand Haste failed MX_SPEED_CNT: {slot0}"
        assert slot1[0] == px + 4, f"Wand Haste corrupted slot+1.MX_X: {slot1}"
        cli.send_keys("za")
        cli.run_idle()
        _dismiss_more(cli)
        slot0_s = cli.read_mem(syms["monster_table"], 12)
        assert slot0_s[6] == 0 and slot0_s[8] == 0, f"Staff Slow failed to decrement MX_SPEED_CNT cleanly: {slot0_s}"
        cli.send_keys("za")
        cli.run_idle()
        _dismiss_more(cli)
        slot0_s2 = cli.read_mem(syms["monster_table"], 12)
        assert slot0_s2[6] == 0xFF and slot0_s2[8] == 0, f"Staff Slow wrote wrong field on MX_SPEED_CNT 0->-1: {slot0_s2}"

        # 8. Regression: Mushrooms 31 (restore CON) / 35 (restore all), Potion 81 (Lose Memories lvldown), Scroll 104 from Town
        _clear_all_monsters(cli, syms)
        pl_it = syms["player_data"]
        _write_mem(cli, pl_it + 21, [16, 16, 16, 16, 16, 16])
        _write_mem(cli, pl_it + 27, [12, 12, 16, 16, 11, 16])
        _write_mem(cli, syms["player_eq_stat_mod"], [0] * 6)
        _write_mem(cli, syms["player_stat_res"], [0] * 6)
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)   # Potion of Gain Strength
        _write_mem(cli, pl_it + 21, [118])  # PL_STR_BASE = 118
        _write_mem(cli, pl_it + 27, [118])  # PL_STR_CUR = 118
        _write_mem(cli, syms["player_stat_res"], [2])
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_stat_res"], 1)[0] == 2, "Gain Strength altered clamped res when base unchanged"
        _write_mem(cli, pl_it + 21, [110])  # base 110, cur clamped 118 -> base gains + step into res!
        _write_mem(cli, pl_it + 27, [118])
        _write_mem(cli, syms["player_stat_res"], [2])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["player_stat_res"], 1)[0] > 2, "Gain Strength ignored player_stat_res residual"
        _write_mem(cli, pl_it + 21, [100])
        _write_mem(cli, pl_it + 27, [118])
        _write_mem(cli, syms["player_stat_res"], [126])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_it + 27, 1)[0] == 118 and cli.read_mem(syms["player_stat_res"], 1)[0] == 127, (
            f"Gain Strength wrapped instead of saturating at +127: res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        # Resident player_restore_stat_a via Potion of Restore Strength (52) on residual-only drain at cur=118 (res 10 -> 50)
        _set_inv_item(cli, syms, 29, 54, qty=1, p1=5, flags=0x02, ego=0x40)  # worn Ring of Strength (+5)
        _write_mem(cli, syms["player_eq_stat_mod"], [5, 0, 0, 0, 0, 0])
        _write_mem(cli, pl_it + 21, [118])
        _write_mem(cli, pl_it + 27, [118])
        _write_mem(cli, syms["player_stat_res"], [10])
        _set_inv_item(cli, syms, 0, 52, qty=1, flags=0x02)  # Potion of Restore Strength
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_it + 27, 1)[0] == 118 and cli.read_mem(syms["player_stat_res"], 1)[0] == 50, (
            f"Resident Restore Strength failed 118 residual restore: res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        # MON-044 Gain Strength (50) with worn stat-modifying equipment (5 cases)
        def _mon044_healthy(base: int, eq_mod: int) -> tuple[int, int]:
            c = max(3, min(118, base))
            r = 0
            if eq_mod > 0:
                for _ in range(eq_mod):
                    if c == 3 and r < 0:
                        r += 1
                    elif c < 18:
                        c += 1
                    elif c < 118:
                        c += 10
                        if c > 118:
                            r = c - 118
                            c = 118
                    else:
                        r = min(127, r + 10)
            elif eq_mod < 0:
                for _ in range(-eq_mod):
                    if c == 118:
                        if r >= 10:
                            r -= 10
                        else:
                            c = 108 + r
                            r = 0
                    elif c >= 28:
                        c -= 10
                    elif c >= 19:
                        c = 18
                    elif c >= 4:
                        c -= 1
                    else:
                        if r > -128:
                            r -= 1
            return c, r

        # Case A: base=16 + Ring (+3) [healthy 28] -> Gain STR -> base=17 -> cur=38 (18/20), res=0
        _set_inv_item(cli, syms, 29, 54, qty=1, p1=3, flags=0x02, ego=0x40)
        _write_mem(cli, syms["player_eq_stat_mod"], [3, 0, 0, 0, 0, 0])
        _write_mem(cli, pl_it + 21, [16])
        _write_mem(cli, pl_it + 27, [28])
        _write_mem(cli, syms["player_stat_res"], [0])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_it + 21, 1)[0] == 17 and cli.read_mem(pl_it + 27, 1)[0] == 38 and cli.read_mem(syms["player_stat_res"], 1)[0] == 0, (
            f"Gain STR base 16 +3 ring mismatch: base={cli.read_mem(pl_it + 21, 1)[0]} cur={cli.read_mem(pl_it + 27, 1)[0]} res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        # Case B: base=17 + Ring (+12) [healthy 118 + res 10] -> Gain STR -> base=18 -> cur=118, res=20
        _set_inv_item(cli, syms, 29, 54, qty=1, p1=12, flags=0x02, ego=0x40)
        _write_mem(cli, syms["player_eq_stat_mod"], [12, 0, 0, 0, 0, 0])
        _write_mem(cli, pl_it + 21, [17])
        _write_mem(cli, pl_it + 27, [118])
        _write_mem(cli, syms["player_stat_res"], [10])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_it + 21, 1)[0] == 18 and cli.read_mem(pl_it + 27, 1)[0] == 118 and cli.read_mem(syms["player_stat_res"], 1)[0] == 20, (
            f"Gain STR base 17 +12 ring mismatch: base={cli.read_mem(pl_it + 21, 1)[0]} cur={cli.read_mem(pl_it + 27, 1)[0]} res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        # Case C: drained base=16 + Ring (+3) [healthy 28, cur 22] -> Gain STR -> base=17 -> cur=32 (drain -6 kept)
        _set_inv_item(cli, syms, 29, 54, qty=1, p1=3, flags=0x02, ego=0x40)
        _write_mem(cli, syms["player_eq_stat_mod"], [3, 0, 0, 0, 0, 0])
        _write_mem(cli, pl_it + 21, [16])
        _write_mem(cli, pl_it + 27, [22])
        _write_mem(cli, syms["player_stat_res"], [0])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_it + 21, 1)[0] == 17 and cli.read_mem(pl_it + 27, 1)[0] == 32 and cli.read_mem(syms["player_stat_res"], 1)[0] == 0, (
            f"Gain STR drained base 16 +3 ring mismatch: base={cli.read_mem(pl_it + 21, 1)[0]} cur={cli.read_mem(pl_it + 27, 1)[0]} res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        # Case D: base=18 + cursed Ring (-2) [healthy 16] -> Gain STR -> matches _mon044_healthy(new_base, -2)
        _set_inv_item(cli, syms, 29, 67, qty=1, p1=(-2) & 0xFF, flags=0x02, ego=0x40)
        _write_mem(cli, syms["player_eq_stat_mod"], [(-2) & 0xFF, 0, 0, 0, 0, 0])
        _write_mem(cli, pl_it + 21, [18])
        _write_mem(cli, pl_it + 27, [16])
        _write_mem(cli, syms["player_stat_res"], [0])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        new_base_d = cli.read_mem(pl_it + 21, 1)[0]
        exp_cur_d, exp_res_d = _mon044_healthy(new_base_d, -2)
        assert new_base_d > 18 and cli.read_mem(pl_it + 27, 1)[0] == exp_cur_d and cli.read_mem(syms["player_stat_res"], 1)[0] == (exp_res_d & 0xFF), (
            f"Gain STR base 18 -2 ring mismatch: new_base={new_base_d} cur={cli.read_mem(pl_it + 27, 1)[0]} res={cli.read_mem(syms['player_stat_res'], 1)[0]} exp=({exp_cur_d}, {exp_res_d})"
        )
        # Case E: saturated gear (+17 STR: two +6 rings + +5 HA), base=100, drained cur=90, res=0 -> must apply full (new_base - 100) delta
        _set_inv_item(cli, syms, 29, 54, qty=1, p1=6, flags=0x02, ego=0x40)
        _set_inv_item(cli, syms, 31, 54, qty=1, p1=6, flags=0x02, ego=0x40)
        _set_inv_item(cli, syms, 22, 6, qty=1, p1=5, flags=0x02, ego=0x07)  # weapon Holy Avenger (+5)
        _write_mem(cli, syms["player_eq_stat_mod"], [17, 0, 0, 0, 0, 0])
        _write_mem(cli, pl_it + 21, [100])
        _write_mem(cli, pl_it + 27, [90])
        _write_mem(cli, syms["player_stat_res"], [0])
        _set_inv_item(cli, syms, 0, 50, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        new_base_e = cli.read_mem(pl_it + 21, 1)[0]
        assert 100 < new_base_e <= 110 and cli.read_mem(pl_it + 27, 1)[0] == 90 + (new_base_e - 100) and cli.read_mem(syms["player_stat_res"], 1)[0] == 0, (
            f"Gain STR saturated +17 gear mismatch: new_base={new_base_e} cur={cli.read_mem(pl_it + 27, 1)[0]} res={cli.read_mem(syms['player_stat_res'], 1)[0]}"
        )
        _write_mem(cli, syms["inv_item_id"] + 22, [0xFF])
        _write_mem(cli, syms["inv_item_id"] + 31, [0xFF])
        _write_mem(cli, syms["inv_item_id"] + 29, [0xFF])
        _write_mem(cli, syms["player_eq_stat_mod"], [0] * 6)
        _write_mem(cli, syms["player_stat_res"], [0] * 6)
        _set_inv_item(cli, syms, 0, 82, qty=1, flags=0x02)   # Potion of Salt Water
        _write_mem(cli, syms["zp_eff_poison"], [10])
        cli.send_keys("qa")
        cli.run_idle()
        salt_msg = cli.screen_lines()[0][0]
        _dismiss_more(cli)
        assert cli.read_mem(syms["zp_eff_poison"], 1)[0] == 0, "Salt Water failed to clear zp_eff_poison immediately"
        assert "better" not in salt_msg, f"Salt Water printed poison-end msg instead of immediate cure: {salt_msg!r}"
        _write_mem(cli, syms["zp_eff_paralyze"], [0])

        _write_mem(cli, pl_it + 21, [16, 16, 16, 16, 16, 16])
        _write_mem(cli, pl_it + 27, [12, 12, 16, 16, 11, 16])
        _write_mem(cli, syms["player_stat_res"], [0] * 6)
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 31, qty=1, flags=0x02)   # Mushroom of Restore CON
        _set_inv_item(cli, syms, 1, 35, qty=1, flags=0x02)   # Mushroom of Restoring
        _set_inv_item(cli, syms, 2, 81, qty=1, flags=0x02)   # Potion of Lose Memories
        cli.send_keys("Ea")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_it + 31, 1)[0] == 16, "Mushroom 31 failed to restore CON"
        cli.send_keys("Ea")
        cli.run_idle()
        _dismiss_more(cli)
        assert list(cli.read_mem(pl_it + 27, 2)) == [16, 16], "Mushroom 35 failed to restore STR/INT"

        _write_mem(cli, pl_it + 19, [5])
        _write_mem(cli, syms["abi_player_lvl"], [5])
        _write_mem(cli, pl_it + 46, [30, 0, 0])
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["player_lvl"] < 5, "Potion of Lose Memories failed to trigger level-down"

        # Potion of Restore Life Levels (87): multi-level loop restores full PL_MAX_XP in 1 drink
        _write_mem(cli, pl_it + 19, [1])
        _write_mem(cli, syms["abi_player_lvl"], [1])
        _write_mem(cli, pl_it + 46, [0, 0, 0])         # PL_XP = 0
        _write_mem(cli, pl_it + 111, [0x50, 0xC3, 0])   # PL_MAX_XP = 50000
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 87, qty=1, flags=0x02)
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        got_xp = int.from_bytes(cli.read_mem(pl_it + 46, 3), "little")
        assert got_xp == 50000 and cli.read_z80_state()["player_lvl"] > 1, (
            f"Restore Life Levels failed multi-level loop: lvl={cli.read_z80_state()['player_lvl']}, xp={got_xp}"
        )

        # Scroll of Recharging (121) omits "(N charges)" on identified wand
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 121, qty=1, flags=0x02)
        _set_inv_item(cli, syms, 1, 150, qty=1, p1=3, flags=0x02)  # identified Wand of Magic Missile
        cli.send_keys("raa")
        cli.run_idle()
        rech_msg = cli.screen_lines()[0][0]
        _dismiss_more(cli)
        assert "glows briefly." in rech_msg and "charges)" not in rech_msg, (
            f"Scroll of Recharging printed unexpected charge suffix: {rech_msg!r}"
        )

        # Scroll of Identify (98) on a 5-arrow stack omits stack quantity ("This is a Arrow.")
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 98, qty=1, flags=0x02)
        _set_inv_item(cli, syms, 1, item_ids.ITEM_SLOT_ARROW, qty=5, flags=0x00)
        cli.send_keys("raa")
        cli.run_idle()
        id_msg = cli.screen_lines()[0][0]
        _dismiss_more(cli)
        assert "This is a Arrow." in id_msg and "5 " not in id_msg, (
            f"Identify on stacked arrows printed unexpected quantity: {id_msg!r}"
        )

        # Scroll of Teleport Level (104) from Town (dlvl=0) -> dlvl=1, and dlvl=1->1 skips extra turn_post_action
        for start_dlvl, expected_dlvls in ((0, {1}), (1, {1, 2})):
            for seed in ([0x01, 0x00, 0x00, 0x00], [0x02, 0x00, 0x00, 0x00], [0x03, 0x00, 0x00, 0x00], [0x04, 0x00, 0x00, 0x00]):
                cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
                _set_inv_item(cli, syms, 0, 104, qty=1, flags=0x02)
                _write_mem(cli, syms["abi_player_dlvl"], [start_dlvl])
                _write_mem(cli, pl_it + 20, [start_dlvl])
                _write_mem(cli, syms["abi_rng_seed"], seed)
                turn_before = cli.read_z80_state()["turn"]
                cli.send_keys("ra")
                cli.run_idle()
                _dismiss_more(cli)
                st_tl = cli.read_z80_state()
                assert st_tl["player_dlvl"] in expected_dlvls, (
                    f"Teleport Level from dlvl={start_dlvl} failed (seed={seed}): got dlvl={st_tl['player_dlvl']}"
                )
                assert st_tl["turn"] == turn_before, (
                    f"Teleport Level from dlvl={start_dlvl} ticked extra turn: {turn_before} -> {st_tl['turn']}"
                )
                if start_dlvl == 0:
                    assert cli.read_mem(syms["level_entry_dir"], 1)[0] == 0, "Town->DL1 Teleport Level must set level_entry_dir=0"
                _clear_all_monsters(cli, syms)

        # 9. Regression: _st_speed signed overflow when slowed (-50), Magic Mapping floorplan+secret+msg, Genocide spares Balrog
        _clear_all_monsters(cli, syms)
        px_mm, py_mm = cli.read_z80_state()["player_x"], cli.read_z80_state()["player_y"]
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 177, qty=1, p1=3, flags=0x02)  # Staff of Speed
        _write_mem(cli, syms["zp_eff_speed"], [0xCE])              # -50 signed
        cli.send_keys("za")
        cli.run_idle()
        _dismiss_more(cli)
        spd_raw = cli.read_mem(syms["zp_eff_speed"], 1)[0]
        spd_s = spd_raw - 256 if spd_raw >= 128 else spd_raw
        assert -34 <= spd_s <= -5, f"Staff of Speed while slowed (-50) clamped wrong: {spd_s}"

        # Scroll of Magic Mapping (106): reveal distant unlit floor + secret door + "You feel your map grow clearer."
        mm_dx_flr, mm_dx_sec = (-5, -6) if px_mm + 6 >= 197 else (5, 6)
        _set_map_tile(cli, px_mm + mm_dx_flr, py_mm, 0x00)          # TILE_FLOOR unvisited unlit
        _set_map_tile(cli, px_mm + mm_dx_sec, py_mm, 0xF0)          # TILE_SECRET
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 106, qty=1, flags=0x02)
        cli.send_keys("ra")
        cli.run_idle()
        mm_msg = cli.screen_lines()[0][0]
        _dismiss_more(cli)
        assert "You feel your map grow clearer." in mm_msg, f"Magic Mapping msg mismatch: {mm_msg!r}"
        assert (_get_map_tile(cli, px_mm + mm_dx_flr, py_mm) & 0x04) != 0, "Magic Mapping missed floor tile"
        assert _get_map_tile(cli, px_mm + mm_dx_sec, py_mm) == 0x84, (
            f"Magic Mapping failed secret->door+visited: {_get_map_tile(cli, px_mm + mm_dx_sec, py_mm):#x}"
        )
        assert "+" in "\n".join(cli.screen_lines()[0][1:19]), (
            "Magic Mapping failed to bump zp_dirty_count for immediate viewport redraw"
        )

        # Scroll of Genocide (122): deletes matching display char while sparing Balrog (cat_slot_id == 278)
        _clear_all_monsters(cli, syms)
        _set_map_tile(cli, px_mm + 1, py_mm, 0x0C | 0x01)
        _set_map_tile(cli, px_mm + 2, py_mm, 0x0C | 0x01)
        _write_mem(cli, syms["cat_slot_id_lo"], [1, 22])            # slot 0 = id 1, slot 1 = id 278 (0x0116)
        _write_mem(cli, syms["cat_slot_id_hi"], [0, 1])
        _write_mem(cli, syms["cr_display"], [ord("o"), ord("o")])
        _write_mem(cli, syms["monster_table"], [px_mm + 1, py_mm, 0, 50, 0, 0x08, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["monster_table"] + 12, [px_mm + 2, py_mm, 1, 50, 0, 0x08, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [2])
        _write_mem(cli, syms["abi_mon_count"], [2])
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 122, qty=1, flags=0x02)
        cli.send_keys("rao")
        cli.run_idle()
        _dismiss_more(cli)
        slots_g = _read_monster_slots(cli, syms)
        assert slots_g[0][3] == 0xFF, f"Genocide failed to delete non-Balrog slot 0: {slots_g[0]}"
        assert slots_g[1][3] == 1, f"Genocide deleted Balrog slot 1: {slots_g[1]}"

        # Wand of Trap/Door Destruction (149): 20-tile directional beam, preserves trap_type on swap-delete, updates chest ego
        _clear_all_monsters(cli, syms)
        dx_w, dir_w = (-1, "h") if px_mm + 3 >= 197 else (1, "l")
        _set_map_tile(cli, px_mm + dx_w, py_mm, 0xE2)         # TILE_TRAP | FLAG_HAS_ITEM
        _set_map_tile(cli, px_mm + 2 * dx_w, py_mm, 0x80)     # TILE_DOOR_CLOSED
        _set_map_tile(cli, px_mm + 3 * dx_w, py_mm, 0x00)     # clear floor
        _write_mem(cli, syms["trap_count"], [2])
        _write_mem(cli, syms["trap_x"], [px_mm + dx_w, px_mm + dx_w])
        _write_mem(cli, syms["trap_y"], [py_mm, py_mm + (-2 if py_mm >= 64 else 2)])
        _write_mem(cli, syms["trap_type"], [0, 17])           # slot 0 removed, slot 1 (TRAP_AGGRAVATE=17) must survive
        _write_mem(cli, syms["fi_item_id"], [204] + [0xFF] * 41)
        _write_mem(cli, syms["fi_x"], [px_mm + dx_w])
        _write_mem(cli, syms["fi_y"], [py_mm])
        _write_mem(cli, syms["fi_p1"], [0x45])                # CHEST_P1_TRAP_FOUND | TRAP_POISON | LOCKED
        _write_mem(cli, syms["fi_meta_hi"], [48])             # EGO_CHEST_POISON
        _write_mem(cli, syms["zp_item_count"], [1])
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 149, qty=1, p1=3, flags=0x02)
        cli.send_keys("aa" + dir_w)
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["trap_count"], 1)[0] == 1, "Wand Trap/Door Destr failed to remove beam trap"
        assert cli.read_mem(syms["trap_type"], 1)[0] == 17, "Swap-delete corrupted remaining trap_type"
        assert (_get_map_tile(cli, px_mm + 2 * dx_w, py_mm) & 0xF0) == 0x00, "Wand Trap/Door Destr failed to break closed door"
        assert cli.read_mem(syms["fi_p1"], 1)[0] == 0x40, "Wand Trap/Door Destr failed to disarm chest"
        assert (cli.read_mem(syms["fi_meta_hi"], 1)[0] & 0x3F) == 48, "Wand Trap/Door Destr altered fi_meta_hi ego"

        # Scroll of Trap Creation (118): uses rng_range(TRAP_TYPE_COUNT) instead of trap_count index
        _write_mem(cli, syms["trap_count"], [0])
        for dy_t in (-1, 0, 1):
            for dx_t in (-1, 0, 1):
                _set_map_tile(cli, px_mm + dx_t, py_mm + dy_t, 0x00)
        _write_mem(cli, syms["abi_rng_seed"], [0x12, 0x34, 0x56, 0x78])
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 118, qty=1, flags=0x02)
        cli.send_keys("ra")
        cli.run_idle()
        _dismiss_more(cli)
        tc_c = cli.read_mem(syms["trap_count"], 1)[0]
        assert tc_c >= 1 and any(
            t != i for i, t in enumerate(cli.read_mem(syms["trap_type"], tc_c))
        ), f"Trap Creation wrote deterministic trap_count index: {list(cli.read_mem(syms['trap_type'], tc_c))}"

        _quit_game_and_title(cli)


def scenario_spells_prayers_and_detect_lifecycle(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test OVL_SPELL + OVL_SPELL_EFF: Mage P/G/m/?/overcast/TRN-008/detect timer, and Priest G/p."""
    syms = _load_main_syms(build_dir)
    with _staged_runner(runner, build_dir) as cli:
        # 1. Mage ('b')
        _create_human_warrior(cli, name="Gandalf", class_key="b")
        _clear_all_monsters(cli, syms)
        st = cli.read_z80_state()
        _set_map_tile(cli, st["player_x"] + 1, st["player_y"], 0x9C)
        _walk_steps(cli, "l>")
        _clear_all_monsters(cli, syms)

        st_d = cli.read_z80_state()
        px, py = st_d["player_x"], st_d["player_y"]
        for dx in range(1, 5):
            _set_map_tile(cli, px + dx, py, 0x0C)
        cli.send_keys("\x17y\x17s")
        cli.run_idle()
        _write_mem(cli, syms["abi_game_flags"], [0])
        _write_mem(cli, syms["zp_game_flags"], [0])
        rows = [r for r in _read_monster_slots(cli, syms) if r[3] != 0xFF]
        sidx, mx0, my0, cr_t, _, _ = rows[0]
        _set_map_tile(cli, mx0, my0, _get_map_tile(cli, mx0, my0) & ~0x01)
        _set_map_tile(cli, px + 2, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [px + 2, py, cr_t, 5, 0, 0x08, 0, 0, 0, 0, 0, 0])

        # Stage Beginners-Magick (186) in pack slot 0; lvl=3, INT=16, mana=20, new_spells=2, worked=0
        pl = syms["player_data"]
        _set_inv_item(cli, syms, 0, 186, qty=1, flags=0x02)
        _write_mem(cli, pl + 19, [3])
        _write_mem(cli, syms["abi_player_lvl"], [3])
        _write_mem(cli, pl + 22, [16])
        _write_mem(cli, pl + 28, [16])
        _write_mem(cli, pl + 37, [20, 20])
        _write_mem(cli, syms["abi_player_mp"], [20, 20])
        _write_mem(cli, pl + 61, [0] * 8)  # clear learnt/worked
        _write_mem(cli, pl + 73, [2])      # PL_NEW_SPELLS = 2

        # 'P' Peruse/Browse removed (6502 uses 'm' '?'/'*' and 'f' Study): verify 'P' is a no-op
        cli.send_keys("P")
        cli.run_idle()
        assert cli.read_z80_state()["overlay_depth"] == 0

        # 'f' Gain/Study spell -> book 'a' -> spell 'a' (Magic Missile)
        cli.send_keys("faa")
        cli.run_idle()
        assert (cli.read_mem(pl + 61, 1)[0] & 0x01) != 0, "Gain failed to set PL_SPELLS_LEARNT_0 bit 0"
        assert cli.read_mem(pl + 73, 1)[0] == 1, "Gain failed to decrement PL_NEW_SPELLS"

        # 'm' Cast Magic Missile via '?' spell list modal -> pick 'a' -> dir 'l' East!
        xp0 = int.from_bytes(cli.read_mem(pl + 46, 3), "little")
        _write_mem(cli, pl + 19, [10])
        _write_mem(cli, syms["abi_player_lvl"], [10])
        _write_mem(cli, pl + 28, [18])
        for seed in ([0x12, 0x34, 0x56, 0x78], [0x99, 0x11, 0x22, 0x33], [0xAA, 0xBB, 0xCC, 0xDD]):
            if (cli.read_mem(pl + 65, 1)[0] & 0x01) != 0:
                break
            _write_mem(cli, syms["abi_turn"], [1, 0])  # odd turn avoids immediate even-turn +1 mana regen
            _write_mem(cli, syms["zp_turn_lo"], [1, 0])
            _write_mem(cli, syms["abi_rng_seed"], seed)
            cli.send_keys("ma?al")
            cli.run_idle()
            _dismiss_more(cli)
        assert cli.read_z80_state()["mp"] < 20, "Cast Magic Missile did not spend mana"
        assert (cli.read_mem(pl + 65, 1)[0] & 0x01) != 0, "First cast did not mark PL_SPELLS_WORKED_0 bit 0"
        xp1 = int.from_bytes(cli.read_mem(pl + 46, 3), "little")
        assert xp1 == xp0, f"6502 parity: first-time spell cast must not award XP (xp0={xp0}, xp1={xp1})"

        # Regression: 6502 bolt max range = 19 (dist 20 out of range; dist 19 hits)
        _clear_all_monsters(cli, syms)
        if px < 22:
            _set_map_tile(cli, px, py, 0x0C)
            px = 40
            _write_mem(cli, syms["abi_player_x"], [px])
            _write_mem(cli, pl + 49, [px])
            _set_map_tile(cli, px, py, 0x0C)
        for dx_r in range(1, 22):
            _set_map_tile(cli, px - dx_r, py, 0x0C)
        _set_map_tile(cli, px - 20, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [px - 20, py, cr_t, 200, 0, 0x08, 0, 0, 0, 0, 0, 0])
        for _ in range(3):
            _write_mem(cli, pl + 37, [20, 20])
            _write_mem(cli, syms["abi_player_mp"], [20, 20])
            cli.send_keys("maa")
            cli.run_idle()
            if "Dir" in cli.screen_lines()[0][0]:
                cli.send_keys("h")
                cli.run_idle()
            _dismiss_more(cli)
        assert _read_monster_slots(cli, syms)[sidx][4] == 200, "Magic Missile exceeded max range 19 (hit at dist 20)"
        _set_map_tile(cli, px - 20, py, 0x0C)
        _set_map_tile(cli, px - 19, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [px - 19, py, cr_t, 200, 0, 0x08, 0, 0, 0, 0, 0, 0])
        for _ in range(5):
            _write_mem(cli, pl + 37, [20, 20])
            _write_mem(cli, syms["abi_player_mp"], [20, 20])
            cli.send_keys("maa")
            cli.run_idle()
            if "Dir" in cli.screen_lines()[0][0]:
                cli.send_keys("h")
                cli.run_idle()
            _dismiss_more(cli)
            if _read_monster_slots(cli, syms)[sidx][4] < 200:
                break
        assert _read_monster_slots(cli, syms)[sidx][4] < 200, "Magic Missile failed to hit within max range 19 (dist 19)"

        # Verify 'm' -> '?' -> ESC redraws map cleanly via hal_layout_visibility_force_redraw
        cli.send_keys("m")
        cli.run_idle()
        prompt_m = cli.screen_lines()[0][0].rstrip()
        assert prompt_m == "Spell book (a-b)?", (
            f"Unexpected spell book prompt: {prompt_m!r}"
        )
        cli.send_keys("a?\x1b")
        cli.run_idle()
        scr_after_esc = "\n".join(cli.screen_lines()[0][2:20])
        assert "@" in scr_after_esc, f"'m'->'?'->ESC failed to redraw dungeon map:\n{scr_after_esc}"

        # Regression: Light Area in corridor does not permanently light corridor tiles; inside a room lights the room
        _set_map_tile(cli, 1, 1, 0x00)
        for dy_c in (-1, 0, 1):
            for dx_c in (-1, 0, 1):
                _set_map_tile(cli, px + dx_c, py + dy_c, 0x10 if dy_c != 0 else 0x00)
        _write_mem(cli, pl + 61, [0x0F])  # first 4 mage spells learnt
        _write_mem(cli, pl + 74, [0, 1, 2, 3])
        _write_mem(cli, syms["room_count"], [0])
        for _ in range(5):
            _write_mem(cli, pl + 37, [20, 20])
            _write_mem(cli, syms["abi_player_mp"], [20, 20])
            cli.send_keys("mad")  # Light Area in corridor
            cli.run_idle()
            la_msg = cli.screen_lines()[0][0]
            _dismiss_more(cli)
            if "fails" not in la_msg.lower():
                break
        assert "fails" not in la_msg.lower(), f"Light Area in corridor kept failing: {la_msg!r}"
        assert (_get_map_tile(cli, px - 1, py - 1) & 0x08) == 0, "Light Area improperly set FLAG_LIT in corridor"
        assert (_get_map_tile(cli, 1, 1) & 0x08) == 0, "Light Area bugged onto (0..2, 0..2)"
        _write_mem(cli, syms["room_count"], [1])
        _write_mem(cli, syms["room_x"], [px])
        _write_mem(cli, syms["room_y"], [py])
        _write_mem(cli, syms["room_w"], [1])
        _write_mem(cli, syms["room_h"], [1])
        _write_mem(cli, syms["room_lit"], [0])
        for _ in range(5):
            _write_mem(cli, pl + 37, [20, 20])
            _write_mem(cli, syms["abi_player_mp"], [20, 20])
            cli.send_keys("mad")  # Light Area inside room
            cli.run_idle()
            la_msg = cli.screen_lines()[0][0]
            _dismiss_more(cli)
            if "fails" not in la_msg.lower():
                break
        assert "fails" not in la_msg.lower(), f"Light Area in room kept failing: {la_msg!r}"
        assert cli.read_mem(syms["room_lit"], 1)[0] == 1, "Light Area failed to set room_lit[0]"
        assert (_get_map_tile(cli, px - 1, py - 1) & 0x08) != 0, "Light Area failed to light player room perimeter"
        assert (_get_map_tile(cli, 1, 1) & 0x08) == 0, "Light Area bugged onto (0..2, 0..2)"

        # TRN-013 Overcast check (mana=0 -> cast spell -> bounded 1..5 paralyze turns + turn ends cleanly)
        _write_mem(cli, pl + 37, [0])
        _write_mem(cli, syms["abi_player_mp"], [0])
        _write_mem(cli, syms["abi_rng_seed"], [0x55, 0x66, 0x77, 0x88])
        cli.send_keys("maa")
        cli.run_idle()
        if "Dir" in cli.screen_lines()[0][0]:
            cli.send_keys("l")
            cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["overlay_depth"] == 0
        assert cli.read_mem(syms["zp_eff_paralyze"], 1)[0] == 0, "Overcast paralyze failed to expire cleanly"

        # TRN-008 Level-up magic pending recalculation
        _write_mem(cli, pl + 19, [12])
        _write_mem(cli, syms["abi_player_lvl"], [12])
        _write_mem(cli, pl + 38, [0])  # max mana = 0 before recalc
        _write_mem(cli, syms["levelup_magic_pending"], [1])
        cli.send_keys("5")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["levelup_magic_pending"], 1)[0] == 0, "TRN-008 failed to clear pending flag"
        assert cli.read_mem(pl + 38, 1)[0] > 0, "TRN-008 failed to recalculate PL_MAX_MANA"

        # eff_detect_timer lifecycle (Detect Monsters marks MF_DETECTED then clears on expiry)
        _set_map_tile(cli, px + 4, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"], [px + 4, py, cr_t, 10, 0, 0x00, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["eff_detect_timer"], [2])
        cli.send_keys("5")  # 2->1 -> sets MF_DETECTED
        cli.run_idle()
        assert (cli.read_mem(syms["monster_table"] + 5, 1)[0] & 0x10) != 0, "eff_detect_timer failed to set MF_DETECTED"
        cli.send_keys("5")  # 1->0 -> clears MF_DETECTED
        cli.run_idle()
        assert (cli.read_mem(syms["monster_table"] + 5, 1)[0] & 0x10) == 0, "eff_detect_timer expiry failed to clear MF_DETECTED"

        # Regression: Wall to Mud on FLAG_HAS_ITEM mineral vein spawns ITEM_SLOT_GOLD_LARGE OR clears ghost FLAG_HAS_ITEM when full
        _clear_all_monsters(cli, syms)
        st_wm = cli.read_z80_state()
        px, py = st_wm["player_x"], st_wm["player_y"]
        _set_inv_item(cli, syms, 1, 187, qty=1, flags=0x02)  # Magick I
        _write_mem(cli, pl + 19, [25])
        _write_mem(cli, syms["abi_player_lvl"], [25])
        _write_mem(cli, pl + 28, [118])
        _write_mem(cli, pl + 37, [50, 50])
        _write_mem(cli, syms["abi_player_mp"], [50, 50])
        _write_mem(cli, pl + 61, [0x00, 0x80, 0x00, 0x00])  # ONLY spell 15 (Wall to Mud) learnt
        _write_mem(cli, pl + 65, [0xFF, 0xFF, 0xFF, 0xFF])
        _write_mem(cli, pl + 74, [15])
        _set_map_tile(cli, px + 1, py, 0xD6)  # TILE_QUARTZ | FLAG_VISITED | FLAG_HAS_ITEM
        cli.write_mem(syms["fi_item_id"], bytes([0xFF] * 42))
        cli.write_mem(syms["fi_add_qty_hi"], b"\x55" * 7)
        _write_mem(cli, syms["zp_item_count"], [0])
        _write_mem(cli, syms["abi_item_count"], [0])
        for _ in range(5):
            cli.send_keys("mbal")
            cli.run_idle()
            _dismiss_more(cli)
            if (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x00:
                break
        assert (_get_map_tile(cli, px + 1, py) & 0xF2) == 0x02, "Wall to Mud on quartz+item failed to leave floor+FLAG_HAS_ITEM"
        assert cli.read_mem(syms["fi_item_id"], 1)[0] in (
            item_ids.ITEM_SLOT_GOLD_SMALL,
            item_ids.ITEM_SLOT_GOLD_LARGE,
        ), "Wall to Mud on quartz+item failed to spawn gold"
        gold_qty = cli.read_mem(syms["fi_qty"], 1)[0]
        dlvl_wm = cli.read_z80_state()["player_dlvl"]
        max_gold = (min(255, 5 + dlvl_wm * 3) - 1) * 2 + 1
        assert 1 <= gold_qty <= max_gold and (gold_qty & 1) == 1, (
            f"Wall to Mud gold qty {gold_qty} out of 6502 odd range 1..{max_gold}"
        )
        assert cli.read_mem(syms["fi_add_qty_hi"], 1)[0] == 0, "Wall to Mud failed to clear fi_add_qty_hi"
        assert cli.read_mem(syms["fi_p1"], 1)[0] == 0, "Wall to Mud left non-zero fi_p1 on gold"
        assert cli.read_mem(syms["zp_item_count"], 1)[0] == 1, "Wall to Mud double-incremented zp_item_count"
        assert cli.read_mem(syms["abi_item_count"], 1)[0] == 1, "Wall to Mud double-incremented abi_item_count"
        # Full floor-item array (42/42): ghost FLAG_HAS_ITEM must be cleared
        _set_map_tile(cli, px + 1, py, 0xD6)
        cli.write_mem(syms["fi_item_id"], bytes([1] * 42))
        for _ in range(5):
            cli.send_keys("mbal")
            cli.run_idle()
            _dismiss_more(cli)
            if (_get_map_tile(cli, px + 1, py) & 0xF0) == 0x00:
                break
        assert (_get_map_tile(cli, px + 1, py) & 0xF2) == 0x00, "Wall to Mud left ghost FLAG_HAS_ITEM when fi_* full"

        # Regression: directional non-bolt ray (ovl_spell_eff_trace_mon) reaches dist 20; M9 keeps player-tile trap; Mass Genocide caps at dist 20
        if px < 22:
            _set_map_tile(cli, px, py, 0x0C)
            px = 40
            _write_mem(cli, syms["abi_player_x"], [px])
            _write_mem(cli, pl + 49, [px])
            _set_map_tile(cli, px, py, 0x0C)
        _clear_all_monsters(cli, syms)
        _write_mem(cli, syms["cr_mflags"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_flags"] + cr_t, [0])
        _write_mem(cli, syms["cr_spell_chance"] + cr_t, [0])
        _write_mem(cli, syms["cr_cdefense"] + cr_t, [0])
        for dx_r in range(1, 22):
            _set_map_tile(cli, px - dx_r, py, 0x0C)
        _set_map_tile(cli, px - 20, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"] + sidx * 12, [px - 20, py, cr_t, 50, 0, 0x00, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [1])
        _write_mem(cli, syms["abi_mon_count"], [1])
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 145, qty=1, p1=3, flags=2)  # Wand of Slow Monster -> ovl_spell_eff_trace_mon
        cli.send_keys("aah")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(syms["monster_table"] + sidx * 12 + 6, 1)[0] == 0xFF, (
            "ovl_spell_eff_trace_mon failed to reach dist 20"
        )
        # Scroll of Mass Genocide (115): hits dist 20, spares dist 21 (20-tile cap)
        _clear_all_monsters(cli, syms)
        _set_map_tile(cli, px - 20, py, 0x0C | 0x01)
        _set_map_tile(cli, px - 21, py, 0x0C | 0x01)
        _write_mem(cli, syms["monster_table"], [px - 20, py, cr_t, 50, 0, 0x00, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["monster_table"] + 12, [px - 21, py, cr_t, 50, 0, 0x00, 0, 0, 0, 0, 0, 0])
        _write_mem(cli, syms["zp_mon_count"], [2])
        _write_mem(cli, syms["abi_mon_count"], [2])
        _set_inv_item(cli, syms, 1, 115, qty=1, flags=2)
        cli.send_keys("ra")
        cli.run_idle()
        _dismiss_more(cli)
        mg_slots = _read_monster_slots(cli, syms)
        assert mg_slots[0][3] == 0xFF and mg_slots[1][3] != 0xFF, (
            f"Mass Genocide violated 20-tile LOS cap: dist20={mg_slots[0]}, dist21={mg_slots[1]}"
        )
        _clear_all_monsters(cli, syms)
        # M9 Trap/Door Destruction (spell 9 = index 9) keeps trap on player's own tile (px, py) while removing adjacent
        _set_map_tile(cli, px, py, 0xE4)
        _set_map_tile(cli, px + 1, py, 0xE0)
        _write_mem(cli, syms["trap_count"], [2])
        _write_mem(cli, syms["trap_x"], [px, px + 1])
        _write_mem(cli, syms["trap_y"], [py, py])
        _write_mem(cli, syms["trap_type"], [0, 1])
        _set_inv_item(cli, syms, 0, 187, qty=1, flags=0x02)  # Magick I
        _write_mem(cli, pl + 19, [25])
        _write_mem(cli, syms["abi_player_lvl"], [25])
        _write_mem(cli, pl + 28, [118])
        _write_mem(cli, pl + 37, [50, 50])
        _write_mem(cli, syms["abi_player_mp"], [50, 50])
        _write_mem(cli, pl + 61, [0x00, 0x02, 0x00, 0x00])  # ONLY spell 9 (Destroy Traps/Doors) learnt
        _write_mem(cli, pl + 65, [0xFF, 0xFF, 0xFF, 0xFF])
        _write_mem(cli, pl + 74, [9])
        for _ in range(5):
            cli.send_keys("maa")
            cli.run_idle()
            _dismiss_more(cli)
            if cli.read_mem(syms["trap_count"], 1)[0] < 2:
                break
        assert cli.read_mem(syms["trap_count"], 1)[0] == 1 and cli.read_mem(syms["trap_x"], 1)[0] == px, (
            f"M9 Trap Destruction deleted player-tile trap: count={cli.read_mem(syms['trap_count'], 1)[0]}"
        )
        _write_mem(cli, syms["trap_count"], [0])
        _set_map_tile(cli, px, py, 0x0C)

        cli.send_keys("QY")
        cli.run_idle()

        # 2. Priest ('c'): Gain ('G') + Pray ('p')
        _create_human_warrior(cli, name="Friar", class_key="c")
        _clear_all_monsters(cli, syms)
        pl_p = syms["player_data"]
        _set_inv_item(cli, syms, 0, 190, qty=1, flags=0x02)  # Holy Book of Prayers
        _write_mem(cli, pl_p + 19, [5])
        _write_mem(cli, syms["abi_player_lvl"], [5])
        _write_mem(cli, pl_p + 29, [18])  # high WIS
        _write_mem(cli, pl_p + 37, [20, 20])
        _write_mem(cli, syms["abi_player_mp"], [20, 20])
        _write_mem(cli, pl_p + 73, [1])
        cli.send_keys("faa")
        cli.run_idle()
        assert (cli.read_mem(pl_p + 61, 1)[0] & 0x01) != 0, "Priest gain failed"
        _write_mem(cli, syms["abi_turn"], [1, 0])
        _write_mem(cli, syms["zp_turn_lo"], [1, 0])
        cli.send_keys("paa")
        cli.run_idle()
        assert cli.read_z80_state()["mp"] < 20, "Priest pray failed to cast & spend mana"
        # Regression: _p_gain_stat Gain WIS preserves C=STAT_WIS across msg_print_huff and calls tramp_spell_recalc_levelup
        _write_mem(cli, pl_p + 23, [15])  # PL_WIS_BASE
        _write_mem(cli, pl_p + 29, [15])  # PL_WIS_CUR
        _write_mem(cli, pl_p + 73, [0])   # PL_NEW_SPELLS = 0
        cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
        _set_inv_item(cli, syms, 0, 56, qty=1, flags=0x02)  # Potion of Gain Wisdom
        cli.send_keys("qa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_mem(pl_p + 29, 1)[0] == 16, "Potion of Gain Wisdom failed to raise WIS"
        assert cli.read_mem(pl_p + 73, 1)[0] >= 1, "_p_gain_stat failed to invoke tramp_spell_recalc_levelup on WIS gain"
        # Regression: level transition preserves levelup_magic_pending, clears PLF_RESTING on Recall, & P30 Holy Word keeps Heroism +10 MHP
        _write_mem(cli, pl_p + 19, [40])
        _write_mem(cli, syms["abi_player_lvl"], [40])
        _write_mem(cli, pl_p + 29, [118])
        _write_mem(cli, pl_p + 37, [50, 50])
        _write_mem(cli, syms["abi_player_mp"], [50, 50])
        _write_mem(cli, pl_p + 61, [0, 0, 0, 0x20])  # ONLY P30 Holy Word (bit 29 = byte 3 bit 5)
        _write_mem(cli, pl_p + 65, [0xFF, 0xFF, 0xFF, 0xFF])
        _write_mem(cli, pl_p + 74, [29])
        _set_inv_item(cli, syms, 0, 193, qty=1, flags=0x02)  # Exorcism book
        # First verify P30 Holy Word preserves active Heroism (+10 MHP) when CON is undrained
        _write_mem(cli, syms["zp_eff_hero"], [10])
        base_mhp_hw = cli.read_z80_state()["mhp"]
        _write_mem(cli, pl_p + 35, list((base_mhp_hw + 10).to_bytes(2, "little")))
        _write_mem(cli, syms["abi_player_mhp"], list((base_mhp_hw + 10).to_bytes(2, "little")))
        cli.send_keys("paa")
        cli.run_idle()
        _dismiss_more(cli)
        assert cli.read_z80_state()["mhp"] == base_mhp_hw + 10, (
            f"Holy Word stripped Heroism +10 MHP: expected {base_mhp_hw + 10}, got {cli.read_z80_state()['mhp']}"
        )
        # Next verify level transition keeps levelup_magic_pending, clears PLF_RESTING (0x20), & keeps HSTR_RECALL_ARRIVE visible
        _write_mem(cli, syms["abi_player_dlvl"], [2])
        _write_mem(cli, pl_p + 20, [2])   # PL_DLEVEL = 2 (in dungeon so Recall triggers -> Town)
        _write_mem(cli, pl_p + 56, [2])   # PL_MAX_DLVL = 2
        _write_mem(cli, pl_p + 33, [1, 0])
        _write_mem(cli, syms["abi_player_hp"], [1, 0])  # HP < MHP so _gl_stop_rest wouldn't mask _gl_clr_level_latches
        _write_mem(cli, pl_p + 73, [0, 0])  # clear PL_NEW_SPELLS & learnt count so recalc_levelup visibly grants spells
        _write_mem(cli, syms["zp_eff_word_recall"], [1])
        _write_mem(cli, syms["auto_rest_active"], [1])
        _write_mem(cli, pl_p + 54, [cli.read_mem(pl_p + 54, 1)[0] | 0x20])
        _write_mem(cli, syms["levelup_magic_pending"], [1])
        cli.send_keys("5")
        cli.run_idle()
        recall_msg = cli.screen_lines()[0][0]
        _dismiss_more(cli)
        assert cli.read_z80_state()["player_dlvl"] == 0, "Word of Recall failed to return Priest from DL2 to Town"
        assert "You feel yourself yanked away!" in recall_msg, (
            f"Word of Recall arrival message wiped or missing on row 0: {recall_msg!r}"
        )
        assert (cli.read_mem(pl_p + 54, 1)[0] & 0x20) == 0, "Word of Recall during Auto-Rest stranded PLF_RESTING"
        assert cli.read_mem(syms["levelup_magic_pending"], 1)[0] == 0, "Level transition dropped or skipped levelup_magic_pending"
        assert cli.read_mem(pl_p + 73, 1)[0] > 0, "Level transition dropped levelup_magic_pending before tramp_spell_recalc_levelup ran"
        _quit_game_and_title(cli)


def scenario_recall_and_balrog_victory(
    runner: Path, _runcpm: Path, _sjasmplus: Path, build_dir: Path
) -> None:
    """Test '/' Monster Recall viewer, Wizard [B] Balrog spawn, non-wizard Balrog kill -> Royal Winner Crown & HOF."""
    syms = _load_main_syms(build_dir)
    with tempfile.TemporaryDirectory() as td:
        workdir = Path(td)
        shutil.copy2(build_dir / "MORIA8.COM", workdir / "MORIA8.COM")
        shutil.copy2(build_dir / "MORIA8.DAT", workdir / "MORIA8.DAT")

        cli = ControlClient([str(runner), "--control", "--workdir", str(workdir), str(workdir / "MORIA8.COM")])
        try:
            # 1. Wizard mode: S at dlvl 100 forces Balrog; '/' recall still requires encounter count > 0 even in Wizard Mode!
            _create_human_warrior(cli, name="Bane")
            _clear_all_monsters(cli, syms)
            cli.write_mem(syms["recall_data"], bytes(279 * 4))
            cli.send_keys("\x17y/B")
            cli.run_idle()
            unseen_b = "\n".join(cli.screen_lines()[0])
            assert "Balrog" not in unseen_b and cli.read_z80_state()["overlay_depth"] == 0, (
                f"Wizard '/' leaked unencountered Balrog recall:\n{unseen_b}"
            )
            # Wizard S at dlvl=100 must force Balrog (278)
            _write_mem(cli, syms["abi_player_dlvl"], [100])
            _write_mem(cli, syms["player_data"] + 20, [100])
            cli.send_keys("\x17s")
            cli.run_idle()
            rows = [r for r in _read_monster_slots(cli, syms) if r[3] != 0xFF]
            assert rows, "Wizard S) Summon failed to spawn creature"
            cat0 = cli.read_mem(syms["cat_slot_id_lo"] + rows[0][3], 1)[0] | (
                cli.read_mem(syms["cat_slot_id_hi"] + rows[0][3], 1)[0] << 8
            )
            assert cat0 == 278, f"Wizard S at dlvl 100 spawned cat {cat0} instead of Balrog 278"
            _write_mem(cli, syms["abi_player_dlvl"], [0])
            _write_mem(cli, syms["player_data"] + 20, [0])

            # Seed recall_data for Balrog (278 -> cdef=0xC0 -> Hurt: None) & Brown Mold (74 -> cdef=0x4A -> Hurt: FIR ACD)
            _write_mem(cli, syms["recall_data"] + 278 * 4, [1, 0, 0, 0])
            _write_mem(cli, syms["recall_data"] + 74 * 4, [1, 0, 0, 0])
            cli.send_keys("/B")
            cli.run_idle()
            rcl_txt = "\n".join(cli.screen_lines()[0])
            assert "Recall" in rcl_txt and "Balrog" in rcl_txt, f"Monster Recall failed:\n{rcl_txt}"
            assert "Hurt: None" in rcl_txt, f"Balrog Recall Hurt: unexpected tags:\n{rcl_txt}"
            cli.send_keys(" ")
            cli.run_idle()
            assert cli.read_z80_state()["overlay_depth"] == 0
            cli.send_keys("/m")
            cli.run_idle()
            m_txt = "\n".join(cli.screen_lines()[0])
            assert "Mold" in m_txt and "Hurt: FIR ACD" in m_txt and "CLD" not in m_txt, (
                f"Mold Recall Hurt: wrong/inverted tags:\n{m_txt}"
            )
            cli.send_keys(" ")
            cli.run_idle()
            assert cli.read_z80_state()["overlay_depth"] == 0
            cli.send_keys("QY")
            cli.run_idle()

            # 2. Non-Wizard Hero kills Balrog -> GAME_FLAG_WINNER -> Royal Crown screen + single score.s screen + HISCORE.DAT
            _create_human_warrior(cli, name="Victor")
            _clear_all_monsters(cli, syms)
            st = cli.read_z80_state()
            _set_map_tile(cli, st["player_x"] + 1, st["player_y"], 0x9C)
            _walk_steps(cli, "l>")
            _clear_all_monsters(cli, syms)

            st_d = cli.read_z80_state()
            px, py = st_d["player_x"], st_d["player_y"]
            _write_mem(cli, syms["cat_slot_id_lo"], [278 & 0xFF])
            _write_mem(cli, syms["cat_slot_id_hi"], [278 >> 8])
            _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
            _write_mem(cli, syms["monster_table"], [px + 1, py, 0, 1, 0, 0x09, 0, 0, 0, 0, 0, 0])
            _write_mem(cli, syms["zp_mon_count"], [1])
            _write_mem(cli, syms["abi_mon_count"], [1])
            _write_mem(cli, syms["player_data"] + 40, [120, 20])  # PL_TOHIT=120, PL_TODMG=20
            _write_mem(cli, syms["pcc_eq_tohit"], [120, 20])
            _write_mem(cli, syms["inv_to_hit"] + 22, [120])
            _write_mem(cli, syms["inv_to_dam"] + 22, [20])

            # Non-melee (wand) Balrog kill prints "You have slain" BEFORE "You have won!", and second Balrog does not repeat victory!
            cli.write_mem(syms["inv_item_id"], bytes([0xFF] * 22))
            _set_inv_item(cli, syms, 0, 150, qty=1, p1=3, flags=2)  # Wand of Magic Missile
            _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
            _write_mem(cli, syms["monster_table"], [px + 1, py, 0, 1, 0, 0x09, 0, 0, 0, 0, 0, 0])
            _write_mem(cli, syms["zp_mon_count"], [1])
            _write_mem(cli, syms["abi_mon_count"], [1])
            cli.send_keys("aal")
            cli.run_idle()
            first_w_msg = cli.screen_lines()[0][0]
            assert "You have slain the" in first_w_msg, f"Wand Balrog kill printed wrong first msg: {first_w_msg!r}"
            _dismiss_more(cli)
            assert (cli.read_z80_state()["game_flags"] & 0x04) != 0, "Killing Balrog did not set GAME_FLAG_WINNER"
            assert cli.read_mem(syms["recall_data"] + 278 * 4, 1)[0] >= 1, "Balrog recall kill count stayed 0"
            # Kill second Balrog via bump -> already-won guard suppresses duplicate victory notice
            _set_map_tile(cli, px + 1, py, 0x0C | 0x01)
            _write_mem(cli, syms["monster_table"], [px + 1, py, 0, 1, 0, 0x09, 0, 0, 0, 0, 0, 0])
            _write_mem(cli, syms["zp_mon_count"], [1])
            _write_mem(cli, syms["abi_mon_count"], [1])
            _write_mem(cli, syms["player_data"] + 40, [120, 20])
            _write_mem(cli, syms["pcc_eq_tohit"], [120, 20])
            _write_mem(cli, syms["inv_to_hit"] + 22, [120])
            _write_mem(cli, syms["inv_to_dam"] + 22, [20])
            cli.send_keys("l")
            cli.run_idle()
            second_w_msg = cli.screen_lines()[0][0]
            assert "You have won" not in second_w_msg, f"Second Balrog repeated victory banner: {second_w_msg!r}"
            _dismiss_more(cli)

            # Winner Quit ('Q', no prompt) -> Royal Crown screen -> any key -> Total Winner Score + HISCORE.DAT
            cli.send_keys("Q")
            cli.run_idle()
            win_txt = "\n".join(cli.screen_lines()[0])
            assert "Veni, Vidi, Vici!" in win_txt and "Victor" in win_txt, (
                f"Expected Royal Winner screen:\n{win_txt}"
            )
            cli.send_keys(" ")
            cli.run_idle()
            hof_txt = "\n".join(cli.screen_lines()[0])
            assert "* Total Winner *" in hof_txt and "Victor" in hof_txt, f"Winner missing from score screen:\n{hof_txt}"
            assert (workdir / "HISCORE.DAT").is_file(), "Non-wizard Winner failed to persist HISCORE.DAT"
            cli.send_keys(" ")
            cli.run_idle()
            assert cli.read_z80_state()["current_overlay"] == OVL_TITLE
            cli.send_keys("Q")
            assert cli.run_until_exit()["exit_code"] == 0
            assert cli.read_stack_canary() == STACK_CANARY_BYTES
            assert cli.close() == 0
        finally:
            cli.force_cleanup()


SCENARIO_FUNCS = {
    "tpa_guard_reject": scenario_tpa_guard_reject,
    "boot_title_adm3a": scenario_boot_title_adm3a,
    "boot_title_color": scenario_boot_title_color,
    "boot_title_mono": scenario_boot_title_mono,
    "cli_tail_and_missing_overlay": scenario_cli_tail_and_missing_overlay,
    "legal_viewer_nested_trampoline": scenario_legal_viewer_nested_trampoline,
    "huffman_and_rng_entropy": scenario_huffman_and_rng_entropy,
    "core_hal_unit_probe": scenario_core_hal_unit_probe,
    "chargen_and_town_render": scenario_chargen_and_town_render,
    "town_store_buy_sell": scenario_town_store_buy_sell,
    "town_home_deposit_withdraw": scenario_town_home_deposit_withdraw,
    "save_v2_roundtrip_and_checksum": scenario_save_v2_roundtrip_and_checksum,
    "multi_drive_save_setup": scenario_multi_drive_save_setup,
    "hiscore_io_roundtrip": scenario_hiscore_io_roundtrip,
    "dungeon_gen_topology_soak": scenario_dungeon_gen_topology_soak,
    "los_stairs_and_exploration": scenario_los_stairs_and_exploration,
    "features_doors_traps_chests": scenario_features_doors_traps_chests,
    "turn_regen_poison_repeat": scenario_turn_regen_poison_repeat,
    "ui_help_wizard_death_hiscore": scenario_ui_help_wizard_death_hiscore,
    "monster_catalog_spawn_and_visibility": scenario_monster_catalog_spawn_and_visibility,
    "monster_ai_combat_and_drops": scenario_monster_ai_combat_and_drops,
    "monster_attacks_and_magic": scenario_monster_attacks_and_magic,
    "item_mgt_ranged_throw_and_egos": scenario_item_mgt_ranged_throw_and_egos,
    "items_potions_scrolls_wands_staves": scenario_items_potions_scrolls_wands_staves,
    "spells_prayers_and_detect_lifecycle": scenario_spells_prayers_and_detect_lifecycle,
    "recall_and_balrog_victory": scenario_recall_and_balrog_victory,
    "runcpm_pty_smoke": scenario_runcpm_pty_smoke,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path, default=None, help="Path to cpm_runner binary")
    parser.add_argument("--runcpm", type=Path, default=None, help="Path to RunCPM binary")
    parser.add_argument("--sjasmplus", type=Path, default=None, help="Path to sjasmplus binary")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR, help="CP/M build dir")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--all", action="store_true", help="Run all M5 smoke scenarios")
    mode.add_argument("--scenario", choices=SCENARIOS, help="Run a single named scenario")
    args = parser.parse_args(argv)

    runner = _resolve_tool(args.runner, "CPM_RUNNER", DEFAULT_RUNNER)
    runcpm = _resolve_tool(args.runcpm, "RUNCPM", DEFAULT_RUNCPM)
    sjasmplus = _resolve_tool(args.sjasmplus, "SJASMPLUS", DEFAULT_SJASMPLUS)
    selected = SCENARIOS if args.all else (args.scenario,)

    for name in selected:
        SCENARIO_FUNCS[name](runner, runcpm, sjasmplus, args.build_dir)
        print(f"PASS {name}")
    print(f"CP/M M5 smoke harness PASSED ({len(selected)}/{len(selected)} scenarios).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
