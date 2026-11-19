#!/usr/bin/env python3
"""
tools/gen_trampolines.py
Module ownership: platform-tooling trampoline generator & validator (Phase 3).
Generates per-port Kick Assembler trampoline include files from
``tools/trampoline_manifest.py``, validates source/manifest bijection across all
7 Moria8 ports, and provides built-in self-tests (``--selftest``).
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

sys.dont_write_bytecode = True

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from trampoline_manifest import (  # noqa: E402
    PORT_ENTRIES,
    PORTS,
    STANDARD_KINDS,
    TrampolineEntry,
    manifest_index,
)


GENERATED_HEADER = (
    "// GENERATED FILE — DO NOT EDIT.\n"
    "// Source: tools/trampoline_manifest.py via tools/gen_trampolines.py\n"
)

_LABEL_COLON_RE = re.compile(r"^\s*(tramp_[A-Za-z0-9_]+)\s*:")
_LABEL_ALIAS_RE = re.compile(r"^\s*\.label\s+(tramp_[A-Za-z0-9_]+)\s*=")
_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)


def _req(val: Optional[str], field: str, entry: TrampolineEntry) -> str:
    if not val:
        raise ValueError(f"{entry.port}:{entry.name} ({entry.kind}) missing required '{field}'")
    return val


def _emit_lines(lines: Sequence[str]) -> str:
    return "\n".join(lines) + "\n"


def _render_a2_ovl_dispatch(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    ovl = _req(e.overlay, "overlay", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #<{target}",
        f"    ldy #>{target}",
        f"    ldx #{ovl}",
        "    jmp tramp_ovl_dispatch",
    ])


def _render_a8_ovl_gen_loaded(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    jsr tramp_sr_gen_loaded",
        f"    jmp {target}",
    ])


def _render_alias(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return f".label {e.name} = {target}\n"


def _render_ax_dispatch(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    disp = _req(e.dispatcher, "dispatcher", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #<{target}",
        f"    ldx #>{target}",
        f"    jmp {disp}",
    ])


def _render_ay_dispatch(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    disp = _req(e.dispatcher, "dispatcher", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #<{target}",
        f"    ldy #>{target}",
        f"    jmp {disp}",
    ])


def _render_c128_macro(macro_name: str, with_overlay: bool) -> Callable[[TrampolineEntry], str]:
    def _fn(e: TrampolineEntry) -> str:
        target = _req(e.target, "target", e)
        if with_overlay:
            ovl = _req(e.overlay, "overlay", e)
            call = f"    :{macro_name}({ovl}, {target})"
        else:
            call = f"    :{macro_name}({target})"
        return _emit_lines([f"{e.name}:", call])

    return _fn


def _render_c128_ovl_death_return(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !done+",
        "    jsr c128_restore_runtime_guards",
        "    sei",
        "    lda $01",
        "    pha",
        "    :BankOutKernal()",
        f"    jsr {target}",
        "    pla",
        "    sta $01",
        "    lda #MMU_ALL_RAM",
        "    sta $ff00",
        "    cli",
        "    jmp c128_return_to_death_overlay",
        "!done:",
        "    rts",
    ])


def _render_c128_ovl_tail(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !fail+",
        "    jsr c128_restore_runtime_guards",
        f"    jmp {target}",
        "!fail:",
        "    jmp entry_main",
    ])


def _render_c64_bank_no_roms_preserve_flags(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    php",
        "    sei",
        "    lda $01",
        "    pha",
        "    lda #BANK_NO_ROMS",
        "    sta $01",
        f"    jsr {target}",
        "    pla",
        "    sta $01",
        "    plp",
        "    rts",
    ])


def _render_c64_ovl_gen_bank_no_roms_sr(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !failed+",
        "    sei",
        "    lda #BANK_NO_ROMS",
        "    sta $01",
        f"    jsr {target}",
        "    jmp tramp_sr_epilogue",
        "!failed:",
        "    rts",
    ])


def _render_clc_rts(e: TrampolineEntry) -> str:
    return _emit_lines([f"{e.name}:", "    clc", "    rts"])


def _render_direct_jmp(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([f"{e.name}:", f"    jmp {target}"])


def _render_game_over_direct(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    jsr tramp_game_over_prepare",
        "    bcs !done+",
        f"    jmp {target}",
        "!done:",
        "    rts",
    ])


def _render_game_over_disk_setup_ovl(e: TrampolineEntry) -> str:
    return _emit_lines([
        f"{e.name}:",
        "    jsr tramp_disk_setup",
        "    bcs !done+",
        "    lda #1",
        "    sta disk_setup_done",
        "    jsr tramp_game_over_prepare",
        "    clc",
        "!done:",
        "    rts",
    ])


def _render_game_over_prepare_ovl(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    lda death_source_saved",
        "    sta zp_death_source",
        "    lda zp_game_flags",
        "    and #GAME_FLAG_WINNER",
        "    bne !tgo_load_overlay+",
        "    lda zp_death_source",
        "    cmp #DEATH_ALIVE",
        "    beq !tgo_load_overlay+",
        "    cmp #DEATH_CHEST_NEEDLE",
        "    bcs !tgo_load_overlay+",
        "    tax",
        f"    jsr {target}",
        "!tgo_load_overlay:",
        f"    lda #{ovl}",
        "    jmp overlay_load",
    ])


def _render_noop_rts(e: TrampolineEntry) -> str:
    return _emit_lines([f"{e.name}:", "    rts"])


def _render_ovl_chest_door_pick(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        f"    jsr {target}",
        "    rts",
        "!load_failed:",
        "    clc",
        "    rts",
    ])


def _render_ovl_death_restore_spell(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        f"    jsr {target}",
        "    jmp tramp_restore_spell_overlay",
        "!load_failed:",
        "    rts",
    ])


def _render_ovl_death_restore_spell_fatal(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load_no_kernal",
        "    bcs !done+",
        f"    jsr {target}",
        "    lda #OVL_SPELL",
        "    jsr overlay_load_no_kernal",
        "    bcs !fatal+",
        "!done:",
        "    rts",
        "!fatal:",
        "    jmp entry_main",
    ])


def _render_ovl_direct(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jsr {target}",
        "!done:",
        "    rts",
    ])


def _render_ovl_help_direct(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !done+",
        "    lda #<help_pages",
        "    sta help_pages_src_lo",
        "    lda #>help_pages",
        "    sta help_pages_src_hi",
        f"    jsr {target}",
        "!done:",
        "    rts",
    ])


def _render_ovl_help_sr(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load_no_kernal",
        "    bcc !loaded+",
        "    jmp tramp_sr_epilogue",
        "!loaded:",
        "    lda #<help_pages",
        "    sta help_pages_src_lo",
        "    lda #>help_pages",
        "    sta help_pages_src_hi",
        f"    jsr {target}",
        "    jmp tramp_sr_epilogue",
    ])


def _render_ovl_identify_direct(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jsr {target}",
        "    jsr tier_restore_after_overlay",
        "!done:",
        "    rts",
    ])


def _render_ovl_items_ret_fail(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    pha",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        "    pla",
        f"    jsr {target}",
        "    rts",
        "!load_failed:",
        "    pla",
        "    rts",
    ])


def _render_ovl_items_ret_zero(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    pha",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        "    pla",
        f"    jsr {target}",
        "    rts",
        "!load_failed:",
        "    pla",
        "    lda #0",
        "    rts",
    ])


def _render_ovl_spell_restore(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jsr {target}",
        "!done:",
        "    jmp tramp_restore_spell_overlay",
    ])


def _render_ovl_sr(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        f"    lda #{ovl}",
        "    jsr overlay_load_no_kernal",
        "    bcs !done+",
        f"    jsr {target}",
        "!done:",
        "    jmp tramp_sr_epilogue",
    ])


def _render_plus4_bank_ram_preserve_a_ret(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    pha",
        "    sei",
        "    jsr plus4_bank_ram",
        "    pla",
        f"    jsr {target}",
        "    pha",
        "    jsr plus4_bank_ram",
        "    pla",
        "    rts",
    ])


def _render_plus4_bank_ram_preserve_flags(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    php",
        "    sei",
        "    jsr plus4_bank_ram",
        f"    jsr {target}",
        "    jsr plus4_bank_ram",
        "    plp",
        "    rts",
    ])


def _render_plus4_ovl_gen_cached_sr(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    lda current_overlay",
        f"    cmp #{ovl}",
        "    beq !loaded+",
        f"    ldx #{ovl} - 1",
        "    jsr overlay_load_disk",
        f"    lda #{ovl}",
        "    sta current_overlay",
        "!loaded:",
        "#if !PLUS4_CARTRIDGE",
        "    jsr plus4_catalog_cache_invalidate",
        "#endif",
        "    sei",
        "    jsr plus4_bank_ram",
        f"    jsr {target}",
        "    jmp tramp_sr_epilogue",
    ])


def _render_plus4_title_ovl(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    jsr title_overlay_preamble",
        "    bcs !done+",
        f"    jsr {target}",
        "!done:",
        "    jmp tramp_sr_epilogue",
    ])


def _render_restore_spell_overlay(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    return _emit_lines([
        f"{e.name}:",
        "    php",
        "    pha",
        "    txa",
        "    pha",
        "    lda #OVL_NONE",
        "    sta piw_return_overlay",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcc !restored+",
        "    brk",
        "!restored:",
        "    pla",
        "    tax",
        "    pla",
        "    plp",
        "    rts",
    ])


def _render_roll_ego_ovl_restore(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    pha",
        "    lda #OVL_ITEMS",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        "    pla",
        f"    jsr {target}",
        "    pha",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcc !restored+",
        "    brk",
        "!restored:",
        "    pla",
        "    rts",
        "!load_failed:",
        "    pla",
        "    lda #0",
        "    rts",
    ])


def _render_select_filtered_inv_key_spell(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    pha",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        f"    lda #{ovl}",
        "    sta piw_return_overlay",
        "    pla",
        f"    jsr {target}",
        "    jmp tramp_restore_spell_overlay",
        "!load_failed:",
        "    pla",
        "    clc",
        "    rts",
    ])


def _render_select_filtered_inv_spell(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    pha",
        "    txa",
        "    pha",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !load_failed+",
        f"    lda #{ovl}",
        "    sta piw_return_overlay",
        "    pla",
        "    tax",
        "    pla",
        f"    jsr {target}",
        "    jmp tramp_restore_spell_overlay",
        "!load_failed:",
        "    pla",
        "    pla",
        "    clc",
        "    rts",
    ])


def _render_sr_epilogue_resync(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    return _emit_lines([
        f"{e.name}:",
        "    php",
        f"    jsr {target}",
        "    plp",
        "    rts",
    ])


def _render_store_enter_town_home(e: TrampolineEntry) -> str:
    if len(e.targets) != 2:
        raise ValueError(f"{e.port}:{e.name} requires targets=(town_target, home_target)")
    town_target, home_target = e.targets
    return _emit_lines([
        f"{e.name}:",
        "    lda zp_store_idx",
        "    cmp #STORE_HOME",
        "    beq !home+",
        "    lda #OVL_TOWN",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jmp {town_target}",
        "!home:",
        "    lda #OVL_HOME",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jmp {home_target}",
        "!done:",
        "    rts",
    ])


def _render_winner_royal_death_modal(e: TrampolineEntry) -> str:
    ovl = _req(e.overlay, "overlay", e)
    if len(e.targets) != 2:
        raise ValueError(f"{e.port}:{e.name} requires targets=(bonus_target, screen_target)")
    bonus_target, screen_target = e.targets
    return _emit_lines([
        f"{e.name}:",
        "    lda #OVL_DEATH",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jsr {bonus_target}",
        f"    lda #{ovl}",
        "    jsr overlay_load",
        "    bcs !done+",
        f"    jsr {screen_target}",
        "!done:",
        "    rts",
    ])


def _render_xy_dispatch(e: TrampolineEntry) -> str:
    target = _req(e.target, "target", e)
    disp = _req(e.dispatcher, "dispatcher", e)
    return _emit_lines([
        f"{e.name}:",
        f"    ldx #<{target}",
        f"    ldy #>{target}",
        f"    jmp {disp}",
    ])


_RENDERERS: Mapping[str, Callable[[TrampolineEntry], str]] = {
    "a2_ovl_dispatch": _render_a2_ovl_dispatch,
    "a8_ovl_gen_loaded": _render_a8_ovl_gen_loaded,
    "alias": _render_alias,
    "ax_dispatch": _render_ax_dispatch,
    "ay_dispatch": _render_ay_dispatch,
    "c128_banked_compute": _render_c128_macro("C128BankedComputeTrampoline", False),
    "c128_banked_preserve_a": _render_c128_macro("C128BankedPreserveATrampoline", False),
    "c128_banked_preserve_flags": _render_c128_macro("C128BankedPreserveFlagsTrampoline", False),
    "c128_banked_shared_epilogue": _render_c128_macro("C128BankedSharedEpilogueTrampoline", False),
    "c128_ovl_compute": _render_c128_macro("C128OverlayComputeTrampoline", True),
    "c128_ovl_death_return": _render_c128_ovl_death_return,
    "c128_ovl_tail": _render_c128_ovl_tail,
    "c128_ui_display": _render_c128_macro("C128UIOverlayDisplayTrampoline", False),
    "c64_bank_no_roms_preserve_flags": _render_c64_bank_no_roms_preserve_flags,
    "c64_ovl_gen_bank_no_roms_sr": _render_c64_ovl_gen_bank_no_roms_sr,
    "clc_rts": _render_clc_rts,
    "direct_jmp": _render_direct_jmp,
    "game_over_direct": _render_game_over_direct,
    "game_over_disk_setup_ovl": _render_game_over_disk_setup_ovl,
    "game_over_prepare_ovl": _render_game_over_prepare_ovl,
    "noop_rts": _render_noop_rts,
    "ovl_chest_door_pick": _render_ovl_chest_door_pick,
    "ovl_death_restore_spell": _render_ovl_death_restore_spell,
    "ovl_death_restore_spell_fatal": _render_ovl_death_restore_spell_fatal,
    "ovl_direct": _render_ovl_direct,
    "ovl_help_direct": _render_ovl_help_direct,
    "ovl_help_sr": _render_ovl_help_sr,
    "ovl_identify_direct": _render_ovl_identify_direct,
    "ovl_items_ret_fail": _render_ovl_items_ret_fail,
    "ovl_items_ret_zero": _render_ovl_items_ret_zero,
    "ovl_spell_restore": _render_ovl_spell_restore,
    "ovl_sr": _render_ovl_sr,
    "plus4_bank_ram_preserve_a_ret": _render_plus4_bank_ram_preserve_a_ret,
    "plus4_bank_ram_preserve_flags": _render_plus4_bank_ram_preserve_flags,
    "plus4_ovl_gen_cached_sr": _render_plus4_ovl_gen_cached_sr,
    "plus4_title_ovl": _render_plus4_title_ovl,
    "restore_spell_overlay": _render_restore_spell_overlay,
    "roll_ego_ovl_restore": _render_roll_ego_ovl_restore,
    "select_filtered_inv_key_spell": _render_select_filtered_inv_key_spell,
    "select_filtered_inv_spell": _render_select_filtered_inv_spell,
    "sr_epilogue_resync": _render_sr_epilogue_resync,
    "store_enter_town_home": _render_store_enter_town_home,
    "winner_royal_death_modal": _render_winner_royal_death_modal,
    "xy_dispatch": _render_xy_dispatch,
}


def render_entry(entry: TrampolineEntry) -> str:
    renderer = _RENDERERS.get(entry.kind)
    if renderer is None:
        raise ValueError(f"Unsupported template kind {entry.kind!r} on {entry.port}:{entry.name}")
    return renderer(entry)


def render_port(port: str, entries: Optional[Sequence[TrampolineEntry]] = None) -> str:
    port_entries = entries if entries is not None else PORT_ENTRIES[port]
    chunks: List[str] = [GENERATED_HEADER.rstrip("\n")]
    chunks.append(f"// Port: {port}\n")
    for entry in port_entries:
        if entry.is_generated:
            chunks.append(render_entry(entry).rstrip("\n"))
    return "\n\n".join(chunks) + "\n"


def _write_if_changed(path: Path, content: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        if existing == content:
            return False
    path.write_text(content, encoding="utf-8")
    return True


def classify_platform_file(rel_path: str) -> Optional[str]:
    norm = rel_path.replace("\\", "/")
    if not norm.startswith("platforms/") or not norm.endswith(".s"):
        return None
    parts = norm.split("/")
    if "tests" in parts or parts[-1].startswith("test_"):
        return None
    if norm == "platforms/commodore/common/disk_setup_runtime128.s":
        return "c128"
    if len(parts) >= 2 and parts[1] in ("apple2", "bbcmaster", "cx16", "atari8"):
        return parts[1]
    if len(parts) >= 3 and parts[1] == "commodore" and parts[2] in ("c64", "plus4", "c128"):
        return parts[2]
    return "unassigned"


def scan_tramp_definitions(
    sources: Mapping[str, str],
) -> Tuple[Dict[str, List[Tuple[str, str, int, Tuple[int, ...]]]], List[str]]:
    """
    Scan source files for ``tramp_*`` definitions while tracking conditional
    ``#if``/``#elif``/``#else`` branches so mutually exclusive platform/build
    branches in the same file are distinguishable from same-branch duplicates.
    """
    defs_by_port: Dict[str, List[Tuple[str, str, int, Tuple[int, ...]]]] = {p: [] for p in PORTS}
    errors: List[str] = []

    for rel_path in sorted(sources):
        port = classify_platform_file(rel_path)
        if port is None:
            continue
        raw = sources[rel_path]
        # Strip /* ... */ block comments while preserving newline count.
        cleaned = _BLOCK_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), raw)
        branch_stack: List[List[int]] = []
        next_block_id = 0

        for lineno, line in enumerate(cleaned.splitlines(), start=1):
            code = line.split("//", 1)[0]
            stripped = code.strip()
            if stripped.startswith("#if"):
                next_block_id += 1
                branch_stack.append([next_block_id, 0])
                continue
            if stripped.startswith("#elif") or stripped.startswith("#else"):
                if branch_stack:
                    branch_stack[-1][1] += 1
                continue
            if stripped.startswith("#endif"):
                if branch_stack:
                    branch_stack.pop()
                continue

            match = _LABEL_COLON_RE.match(code) or _LABEL_ALIAS_RE.match(code)
            if not match:
                continue
            label = match.group(1)
            if port == "unassigned":
                errors.append(
                    f"{rel_path}:{lineno}: tramp_* label {label} outside mapped port tree"
                )
                continue
            branch_sig = tuple(item for pair in branch_stack for item in pair)
            defs_by_port[port].append((label, rel_path, lineno, branch_sig))

    return defs_by_port, errors


def collect_platform_sources(repo_root: Path) -> Dict[str, str]:
    sources: Dict[str, str] = {}
    platforms_dir = repo_root / "platforms"
    for path in sorted(platforms_dir.rglob("*.s")):
        rel = path.relative_to(repo_root).as_posix()
        sources[rel] = path.read_text(encoding="utf-8")
    return sources


def validate_manifest_and_sources(
    port_entries: Mapping[str, Sequence[TrampolineEntry]],
    sources: Mapping[str, str],
    *,
    strict_migrated: bool,
    out_dir: Optional[Path] = None,
) -> Tuple[List[str], Dict[str, Tuple[int, int, int]]]:
    errors: List[str] = []
    stats: Dict[str, Tuple[int, int, int]] = {}

    if set(_RENDERERS) != set(STANDARD_KINDS):
        errors.append("Internal mismatch between STANDARD_KINDS and _RENDERERS")

    # 1. Validate manifest schema itself
    indices: Dict[str, Dict[str, TrampolineEntry]] = {}
    for port in PORTS:
        entries = port_entries.get(port, ())
        seen: Dict[str, TrampolineEntry] = {}
        gen_count = 0
        custom_count = 0
        for entry in entries:
            if entry.port != port:
                errors.append(f"{port}:{entry.name}: entry.port mismatch ({entry.port})")
            if entry.name in seen:
                errors.append(f"{port}:{entry.name}: duplicate manifest entry")
                continue
            seen[entry.name] = entry
            if entry.kind == "custom":
                custom_count += 1
                if not entry.owner_file:
                    errors.append(f"{port}:{entry.name}: custom entry missing owner_file")
                if not entry.reason:
                    errors.append(f"{port}:{entry.name}: custom entry missing reason")
            else:
                gen_count += 1
                if entry.kind not in _RENDERERS:
                    errors.append(f"{port}:{entry.name}: unknown template kind {entry.kind!r}")
                else:
                    try:
                        render_entry(entry)
                    except ValueError as exc:
                        errors.append(str(exc))
                if entry.owner_file is not None:
                    errors.append(
                        f"{port}:{entry.name}: generated entry must not declare owner_file"
                    )
        indices[port] = seen
        stats[port] = (len(entries), gen_count, custom_count)

    # 2. Scan platform sources
    defs_by_port, scan_errors = scan_tramp_definitions(sources)
    errors.extend(scan_errors)

    for port in PORTS:
        manifest = indices[port]
        defs = defs_by_port.get(port, ())
        by_label: Dict[str, List[Tuple[str, int, Tuple[int, ...]]]] = {}
        for label, rel_path, lineno, branch_sig in defs:
            by_label.setdefault(label, []).append((rel_path, lineno, branch_sig))

        # Check every definition in platforms/
        for label, occs in sorted(by_label.items()):
            # Detect duplicates in different files or overlapping conditional branches
            seen_branches: List[Tuple[str, int, Tuple[int, ...]]] = []
            for rel_path, lineno, branch_sig in occs:
                for prev_file, prev_line, prev_sig in seen_branches:
                    if prev_file != rel_path or _branches_overlap(prev_sig, branch_sig):
                        errors.append(
                            f"{port}:{label}: duplicate source definition at "
                            f"{rel_path}:{lineno} (previous {prev_file}:{prev_line})"
                        )
                seen_branches.append((rel_path, lineno, branch_sig))

            entry = manifest.get(label)
            if entry is None:
                rel_path, lineno, _ = occs[0]
                errors.append(
                    f"{port}:{label}: undeclared tramp_* label at {rel_path}:{lineno}"
                )
                continue

            if entry.is_generated and strict_migrated:
                rel_path, lineno, _ = occs[0]
                errors.append(
                    f"{port}:{label}: generated trampoline is still hand-defined at "
                    f"{rel_path}:{lineno}"
                )

            if entry.kind == "custom":
                for rel_path, lineno, _ in occs:
                    if rel_path != entry.owner_file:
                        errors.append(
                            f"{port}:{label}: custom entry declared owner_file="
                            f"{entry.owner_file} but found at {rel_path}:{lineno}"
                        )

        # Ensure every custom entry exists in its declared owner_file
        for name, entry in manifest.items():
            if entry.kind == "custom":
                occs = by_label.get(name, [])
                if not any(rel_path == entry.owner_file for rel_path, _, _ in occs):
                    errors.append(
                        f"{port}:{name}: custom entry missing from declared "
                        f"owner_file={entry.owner_file}"
                    )

    # 3. Check on-disk generated .inc files if they exist in out_dir
    if out_dir is not None and out_dir.exists():
        for port in PORTS:
            inc_path = out_dir / f"{port}_trampolines.inc"
            if inc_path.exists():
                expected = render_port(port, port_entries.get(port, ()))
                actual = inc_path.read_text(encoding="utf-8")
                if actual != expected:
                    errors.append(
                        f"{inc_path}: generated trampoline include is stale "
                        "(re-run tools/gen_trampolines.py)"
                    )

    return errors, stats


def _branches_overlap(sig_a: Tuple[int, ...], sig_b: Tuple[int, ...]) -> bool:
    """Return True unless the two signatures diverge at an #if/#elif/#else block."""
    pairs_a = [(sig_a[i], sig_a[i + 1]) for i in range(0, len(sig_a), 2)]
    pairs_b = [(sig_b[i], sig_b[i + 1]) for i in range(0, len(sig_b), 2)]
    for (blk_a, br_a), (blk_b, br_b) in zip(pairs_a, pairs_b):
        if blk_a != blk_b:
            return True
        if br_a != br_b:
            return False
    return True


def run_selftest() -> int:
    # 1. Verify every port & every standard kind renders deterministically
    rendered_kinds: Set[str] = set()
    for port in PORTS:
        text = render_port(port)
        assert GENERATED_HEADER.splitlines()[0] in text
        for entry in PORT_ENTRIES[port]:
            if entry.is_generated:
                rendered_kinds.add(entry.kind)
                snippet = render_entry(entry)
                assert entry.name in snippet, f"{entry.name} missing in snippet"
    assert rendered_kinds == set(STANDARD_KINDS), (
        f"Unused standard kinds: {sorted(set(STANDARD_KINDS) - rendered_kinds)}"
    )

    # Verify CX16 ay_dispatch uses jmp (never short bra)
    cx16_text = render_port("cx16")
    assert "bra tramp_gen_dispatch" not in cx16_text
    assert "bra tramp_spell_dispatch" not in cx16_text
    assert "jmp tramp_gen_dispatch" in cx16_text
    assert "jmp tramp_spell_dispatch" in cx16_text

    # Verify Mage Spell #20 fix targets tramp_restore_spell_overlay on A2/BBC/CX16
    for ovl_port in ("apple2", "bbcmaster", "cx16"):
        idx = manifest_index(ovl_port)
        assert idx["tramp_spell_execute_selected"].kind == "ovl_spell_restore"
        assert "jmp tramp_restore_spell_overlay" in render_entry(idx["tramp_spell_execute_selected"])

    # 2. Synthetic validation fixtures (in-memory, zero host paths)
    sample_custom = TrampolineEntry(
        port="c64",
        name="tramp_custom_ok",
        kind="custom",
        owner_file="platforms/commodore/c64/main.s",
        reason="synthetic test",
    )
    sample_gen = TrampolineEntry(
        port="c64",
        name="tramp_gen_ok",
        kind="ovl_sr",
        overlay="OVL_UI",
        target="ui_char_display",
    )
    sample_entries = {p: () for p in PORTS}
    sample_entries["c64"] = (sample_custom, sample_gen)

    # Clean post-migration fixture (generated not in platforms/, custom in owner_file)
    clean_sources = {"platforms/commodore/c64/main.s": "tramp_custom_ok:\n    rts\n"}
    errs, _ = validate_manifest_and_sources(sample_entries, clean_sources, strict_migrated=True)
    assert not errs, f"Unexpected errors on clean fixture: {errs}"

    # Mutually exclusive #if/#else custom definitions pass as one logical entry
    cond_entries = {p: () for p in PORTS}
    cond_entries["atari8"] = (
        TrampolineEntry(
            port="atari8",
            name="tramp_ui_legal_display",
            kind="custom",
            owner_file="platforms/atari8/legal.s",
            reason="conditional dual branch",
        ),
    )
    cond_sources = {
        "platforms/atari8/legal.s": (
            "#if ATARI8_CARTRIDGE\ntramp_ui_legal_display:\n    rts\n"
            "#else\ntramp_ui_legal_display:\n    rts\n#endif\n"
        )
    }
    errs, _ = validate_manifest_and_sources(cond_entries, cond_sources, strict_migrated=True)
    assert not errs, f"Unexpected errors on #if/#else fixture: {errs}"

    # Undeclared tramp_* detection
    undeclared_sources = {
        "platforms/commodore/c64/main.s": "tramp_custom_ok:\n    rts\ntramp_rogue:\n    rts\n"
    }
    errs, _ = validate_manifest_and_sources(sample_entries, undeclared_sources, strict_migrated=True)
    assert any("undeclared tramp_* label" in e and "tramp_rogue" in e for e in errs), errs

    # Generated label still hand-defined triggers --check failure
    stale_gen_sources = {
        "platforms/commodore/c64/main.s": "tramp_custom_ok:\n    rts\ntramp_gen_ok:\n    rts\n"
    }
    errs, _ = validate_manifest_and_sources(sample_entries, stale_gen_sources, strict_migrated=True)
    assert any("still hand-defined" in e and "tramp_gen_ok" in e for e in errs), errs

    # Duplicate definition in same branch fails
    dup_sources = {
        "platforms/commodore/c64/main.s": "tramp_custom_ok:\n    rts\ntramp_custom_ok:\n    rts\n"
    }
    errs, _ = validate_manifest_and_sources(sample_entries, dup_sources, strict_migrated=True)
    assert any("duplicate source definition" in e for e in errs), errs

    # Missing custom entry in owner_file fails
    errs, _ = validate_manifest_and_sources(sample_entries, {}, strict_migrated=True)
    assert any("missing from declared owner_file" in e for e in errs), errs

    print(f"gen_trampolines selftest passed (all 7 ports, {len(STANDARD_KINDS)} template kinds, 6 fixture assertions)")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate and validate Moria8 trampoline includes across all 7 ports."
    )
    parser.add_argument(
        "--out-dir",
        default="build/trampolines",
        help="Directory to write <port>_trampolines.inc files (default: build/trampolines)",
    )
    parser.add_argument(
        "--port",
        choices=PORTS,
        help="Generate only a single port (requires --output)",
    )
    parser.add_argument(
        "--output",
        help="Output path when using --port",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Strict post-migration check: manifest integrity, no undeclared/duplicate/hand-defined generated stubs, and non-stale existing .inc",
    )
    parser.add_argument(
        "--check-manifest",
        action="store_true",
        help="Pre-migration check: manifest integrity, no undeclared/duplicate/missing custom stubs, and non-stale existing .inc",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="Run built-in unit self-tests",
    )
    args = parser.parse_args(argv)

    if args.selftest:
        return run_selftest()

    if args.port or args.output:
        if not (args.port and args.output):
            parser.error("--port and --output must be specified together")
        out_path = Path(args.output)
        content = render_port(args.port)
        changed = _write_if_changed(out_path, content)
        state = "updated" if changed else "unchanged"
        print(f"trampolines [{args.port}] -> {out_path} ({state})")
        return 0

    out_dir = REPO_ROOT / "build/trampolines" if args.out_dir == "build/trampolines" else Path(args.out_dir)

    if args.check or args.check_manifest:
        sources = collect_platform_sources(REPO_ROOT)
        errors, stats = validate_manifest_and_sources(
            PORT_ENTRIES,
            sources,
            strict_migrated=bool(args.check),
            out_dir=out_dir,
        )
        total_all = sum(v[0] for v in stats.values())
        total_gen = sum(v[1] for v in stats.values())
        total_custom = sum(v[2] for v in stats.values())
        pct = (100.0 * total_gen / total_all) if total_all else 0.0
        if errors:
            for err in errors:
                print(f"ERROR: {err}", file=sys.stderr)
            print(
                f"trampoline check FAILED ({len(errors)} issue(s); "
                f"manifest {total_gen}/{total_all} generated [{pct:.1f}%], {total_custom} custom)",
                file=sys.stderr,
            )
            return 1
        mode = "strict" if args.check else "manifest"
        print(
            f"trampoline {mode} check passed ({total_all} symbols across {len(PORTS)} ports: "
            f"{total_gen} generated [{pct:.1f}%], {total_custom} custom)"
        )
        return 0

    updated = 0
    for port in PORTS:
        dest = out_dir / f"{port}_trampolines.inc"
        content = render_port(port)
        if _write_if_changed(dest, content):
            updated += 1
    total_all = sum(len(PORT_ENTRIES[p]) for p in PORTS)
    total_gen = sum(1 for p in PORTS for e in PORT_ENTRIES[p] if e.is_generated)
    pct = 100.0 * total_gen / total_all
    print(
        f"Generated {len(PORTS)} trampoline includes in {out_dir} "
        f"({updated} updated; {total_gen}/{total_all} stubs generated [{pct:.1f}%])"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
