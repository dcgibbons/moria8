#!/usr/bin/env python3
"""Static memory-contract checker for the Acorn BBC Master 128 port (platforms/bbcmaster/)."""

from __future__ import annotations

import argparse
import re
import struct
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BEEB_SRC_DIR = Path(__file__).resolve().parent
DEFAULT_BUILD_DIR = ROOT / "build" / "bbcmaster"
STORAGE_SRC = BEEB_SRC_DIR / "hal" / "storage.s"
OVERLAY_STORAGE_SRC = BEEB_SRC_DIR / "overlay_storage.s"
MAIN_SRC = BEEB_SRC_DIR / "main.s"

MOS_WORKSPACE_BASE = 0x0800
MOS_WORKSPACE_END = 0x0DFF
LOW_RESIDENT_START = 0x0E00
LOW_HELPERS_LIMIT = 0x3000
LYNNE_AUX_BASE = 0x3F80
LYNNE_AUX_LIMIT = 0x4400
RESIDENT_LIMIT = 0x8000

PLAY_SLOT_BASE = 0x8000
PLAY_SLOT_LIMIT = 0xA400
TIER_POOL_BASE = 0xA400
TIER_POOL_END = 0xA7FF
OVERLAY_BASE = 0xA800
OVERLAY_LIMIT = 0xC000
MOS_ROM_BASE = 0xC000
MOS_ROM_END = 0xFDFF

AUXDATA_VIRT_BASE = 0x6000
AUXDATA_VIRT_LIMIT = 0x7300   # 19 pages: ITEMCAT Slots 0..1 ($9300-$94FF) & monster catalog follow in Bank 6
HUFFDATA_BASE = 0x8000
ZP_SAVE_BASE = 0x8F00
ZP_SAVE_SIZE = 174
HUFFDATA_LIMIT = 0x9000
CATALOG_BASE = 0x9500         # the monster catalog's fields and names, Bank 6
CATALOG_LIMIT = 0xBA00        # cached OVL.UI follows

SWR_CACHE_CAPS = {
    "ovl.ui": 6 * 256,
    "ovl.modal": 12 * 256,
    "ovl.spell": 21 * 256,
    "ovl.items": 23 * 256,
    "ovl.gen": 16 * 256,      # $BC00-$BFFF holds ITEMCAT Slots 2..5 (4 pages)
}

REQUIRED_LOW_SYMBOLS = (
    "entry_bootstrap",
    "save_zp",
    "restore_zp",
    "EnterMos",
    "ExitMos",
    "hal_memory_restore_runtime",
    "beeb_platform_runtime_resync",
    "mmu_safe_huff_read_ptr0",
    "mmu_safe_huff_read_ptr1",
    "mmu_safe_map_read_ptr0",
    "mmu_safe_map_read_ptr1",
    "mmu_safe_map_write_ptr0",
    "mmu_safe_map_write_ptr1",
    "mmu_safe_map_read_block",
    "beeb_swr_copy_to_window",
    "beeb_font_init",
    "screen_init",
    "beeb_wrch_noop",
    "beeb_write_cell",
    "beeb_read_cell",
    "screen_clear",
    "screen_clear_row",
    "beeb_flush_row_buf",
    "bsd_stage_shadow_row",
    "beeb_overlay_try_cache",
    "beeb_require_play",
    "beeb_call_osfile",
    "beeb_call_osfind",
    "beeb_call_osgbpb",
    "beeb_mos_osfile_path_05",
    "beeb_mos_osfile_a",
    "beeb_mos_osword7f",
    "beeb_dfs_load_to_bank",
    "hal_asset_load_prg_header",
    "hal_asset_load_title",
    "hal_item_cat_read_byte",
    "hal_recall_read_byte",
    "hal_recall_write_byte",
    "hal_storage_probe_media",
    "hal_storage_open",
    "hal_storage_chrin",
    "hal_storage_chrout",
    "hal_storage_close",
    "beeb_brk_handler",
    "hal_platform_init_early",
    "low_helpers_end",
)

OVERLAY_FILES = (
    "ovl.start",
    "ovl.town",
    "ovl.death",
    "ovl.modal",
    "ovl.help",
    "ovl.ui",
    "ovl.items",
    "ovl.spell",
    "ovl.chest",
    "ovl.home",
    "ovl.gen",
    "legalui",
    "ovl.storage",
    "ovl.title",
)

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


def strip_asm_comments(text: str) -> str:
    """Remove // line comments, /* ... */ block comments, and "..." strings while keeping line breaks."""
    out: list[str] = []
    i = 0
    n = len(text)
    in_block = False
    in_line = False
    in_str = False
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
        elif in_line:
            if ch == "\n":
                in_line = False
                out.append("\n")
            i += 1
        elif in_str:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                in_str = False
            elif ch == "\n":
                in_str = False
                out.append("\n")
            i += 1
        else:
            if ch == "/" and nxt == "*":
                in_block = True
                i += 2
            elif ch == "/" and nxt == "/":
                in_line = True
                i += 2
            elif ch == '"':
                in_str = True
                out.append(" ")
                i += 1
            else:
                out.append(ch)
                i += 1
    return "".join(out)


ROMSEL_STORE_RE = re.compile(r"^(st[axyz])\s+SHEILA_ROMSEL(?:\s|$)", re.IGNORECASE)
ROMSEL_SHADOW_NAMES = ("zp_mos_romsel_shadow", "ZP_MOS_ROMSEL")
SHADOW_STORE_RE = re.compile(
    r"^(st[axyz])\s+(?:zp_mos_romsel_shadow|ZP_MOS_ROMSEL)(?:\s|$)", re.IGNORECASE
)
LABEL_DEF_RE = re.compile(r"^(![A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*)\s*:")
COND_BRANCH_OPS = {"bcc", "bcs", "beq", "bne", "bmi", "bpl", "bvc", "bvs"}
UNCOND_END_OPS = {"rts", "rti", "brk", "jmp", "bra"}
LOW_MOS_CALLER_FILES = {
    "boot.s",
    "memory_bank.s",
    "storage.s",
    "save_stream.s",
    "sound.s",
    "services.s",
    "screen.s",
    "input.s",
    "overlay_storage.s",
    "legal.s",
}
DIRECT_MOS_CALL_RE = re.compile(
    r"^(?:jsr|jmp|bra)\s+(EnterMos|ExitMos|beeb_call_os\w+|beeb_mos_open_read)(?:\s|$)",
    re.IGNORECASE,
)


def validate_low_mos_callers(src_dir: Path = BEEB_SRC_DIR) -> list[str]:
    """Ensure only < $3000 low-resident modules call EnterMos/ExitMos/beeb_call_os* directly."""
    errors: list[str] = []
    for path in sorted(src_dir.rglob("*.s")):
        rel = path.relative_to(src_dir) if path.is_relative_to(src_dir) else Path(path.name)
        if str(rel) in LOW_MOS_CALLER_FILES:
            continue
        cleaned = strip_asm_comments(path.read_text(encoding="utf-8", errors="replace"))
        for line_no, line in enumerate(cleaned.splitlines(), start=1):
            for raw_part in line.split(";"):
                part = raw_part.strip()
                while True:
                    m_lbl = LABEL_DEF_RE.match(part)
                    if not m_lbl:
                        break
                    part = part[m_lbl.end():].strip()
                m_call = DIRECT_MOS_CALL_RE.match(part)
                if m_call:
                    errors.append(
                        f"{rel}:{line_no}: '{part}' calls {m_call.group(1)} outside < $3000 low-resident modules"
                    )
    return errors


def validate_romsel_sync(src_dir: Path = BEEB_SRC_DIR) -> list[str]:
    """Verify every SHEILA_ROMSEL store in bbcmaster assembly syncs $00F4 under SEI."""
    errors: list[str] = []
    files = sorted(src_dir.rglob("*.s"))
    parsed_files: list[tuple[Path, list[dict]]] = []
    jsr_targets: set[str] = set()

    for path in files:
        cleaned = strip_asm_comments(path.read_text(encoding="utf-8", errors="replace"))
        stmts: list[dict] = []
        for line_no, line in enumerate(cleaned.splitlines(), start=1):
            for raw_part in line.split(";"):
                part = raw_part.strip().lstrip("{").rstrip("}").strip()
                if not part:
                    continue
                labels_here: list[str] = []
                while True:
                    m = LABEL_DEF_RE.match(part)
                    if not m:
                        break
                    labels_here.append(m.group(1))
                    part = part[m.end():].strip()
                if not part and not labels_here:
                    continue
                op = ""
                operand = ""
                if part and not part.startswith((".", "#")):
                    tokens = part.split(None, 1)
                    op = tokens[0].lower()
                    operand = tokens[1].strip() if len(tokens) > 1 else ""
                    if op == "jsr" and operand:
                        jsr_targets.add(operand.split()[0])
                stmts.append({
                    "line": line_no,
                    "labels": labels_here,
                    "text": part,
                    "op": op,
                    "operand": operand,
                })
        parsed_files.append((path, stmts))

    for path, stmts in parsed_files:
        n = len(stmts)
        if n == 0:
            continue
        named_labels: dict[str, int] = {}
        local_positions: dict[str, list[int]] = {}
        for idx, st in enumerate(stmts):
            for lbl in st["labels"]:
                if lbl.startswith("!"):
                    local_positions.setdefault(lbl[1:], []).append(idx)
                else:
                    named_labels[lbl] = idx

        def resolve_target(src_idx: int, expr: str) -> int | None:
            tok = expr.split(",")[0].split()[0]
            if tok.startswith("!") and tok.endswith("+"):
                name = tok[1:-1]
                for pos in local_positions.get(name, ()):
                    if pos > src_idx:
                        return pos
                return None
            if tok.startswith("!") and tok.endswith("-"):
                name = tok[1:-1]
                for pos in reversed(local_positions.get(name, ())):
                    if pos <= src_idx:
                        return pos
                return None
            return named_labels.get(tok)

        preds: list[list[int]] = [[] for _ in range(n)]
        for idx, st in enumerate(stmts):
            op = st["op"]
            if op in COND_BRANCH_OPS:
                tgt = resolve_target(idx, st["operand"])
                if tgt is not None:
                    preds[tgt].append(idx)
                if idx + 1 < n:
                    preds[idx + 1].append(idx)
            elif op in ("bra", "jmp"):
                tgt = resolve_target(idx, st["operand"])
                if tgt is not None:
                    preds[tgt].append(idx)
            elif op in ("rts", "rti", "brk"):
                pass
            else:
                if idx + 1 < n:
                    preds[idx + 1].append(idx)

        def is_entry_node(idx: int) -> bool:
            if not preds[idx]:
                return True
            return any(not lbl.startswith("!") and lbl in jsr_targets for lbl in stmts[idx]["labels"])

        in_masked = [not is_entry_node(i) for i in range(n)]
        out_masked = [not is_entry_node(i) for i in range(n)]
        changed = True
        while changed:
            changed = False
            for idx, st in enumerate(stmts):
                new_in = False if is_entry_node(idx) else all(out_masked[p] for p in preds[idx])
                op = st["op"]
                if op == "sei":
                    new_out = True
                elif op in ("cli", "plp"):
                    new_out = False
                else:
                    new_out = new_in
                if new_in != in_masked[idx] or new_out != out_masked[idx]:
                    in_masked[idx] = new_in
                    out_masked[idx] = new_out
                    changed = True

        rel = path.relative_to(src_dir) if path.is_relative_to(src_dir) else path
        prev_inst_idx: int | None = None
        for idx, st in enumerate(stmts):
            if st["labels"]:
                prev_inst_idx = None
            text = st["text"]
            m_romsel = ROMSEL_STORE_RE.match(text) if text else None
            if m_romsel:
                op = m_romsel.group(1).lower()
                if not in_masked[idx]:
                    errors.append(
                        f"{rel}:{st['line']}: '{text}' writes SHEILA_ROMSEL outside an SEI critical section"
                    )
                prev_text = stmts[prev_inst_idx]["text"] if prev_inst_idx is not None else ""
                m_shadow = SHADOW_STORE_RE.match(prev_text)
                if not m_shadow or m_shadow.group(1).lower() != op:
                    errors.append(
                        f"{rel}:{st['line']}: '{text}' is not immediately preceded by matching '{op} zp_mos_romsel_shadow'"
                    )
            if st["op"]:
                if st["op"] in UNCOND_END_OPS or st["op"] in COND_BRANCH_OPS:
                    prev_inst_idx = None
                else:
                    prev_inst_idx = idx
            elif text:
                # Directives break adjacency between stores
                prev_inst_idx = None

    return errors


def validate_build(build_dir: Path, src_dir: Path | None = BEEB_SRC_DIR) -> list[str]:
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
            errors.append(f"{sym} at ${addr:04X} violates < $3000 low-RAM contract")

    if symbols.get("entry_bootstrap") != LOW_RESIDENT_START:
        errors.append(
            f"entry_bootstrap at ${symbols.get('entry_bootstrap', 0):04X} != ${LOW_RESIDENT_START:04X}"
        )

    if "program_end" not in symbols:
        errors.append("missing symbol program_end")
    else:
        prog_end = symbols["program_end"]
        if not (LOW_RESIDENT_START <= prog_end <= RESIDENT_LIMIT):
            errors.append(f"program_end at ${prog_end:04X} exceeds $8000 Main RAM limit")

    # Check zp_save_buf placement in 4 KB ANDY ($8F00-$8FFF) and zero overlap with BeebHuffData
    if "zp_save_buf" not in symbols:
        errors.append("missing symbol zp_save_buf")
    else:
        zp_buf = symbols["zp_save_buf"]
        if zp_buf < ZP_SAVE_BASE or zp_buf + ZP_SAVE_SIZE > HUFFDATA_LIMIT:
            errors.append(
                f"zp_save_buf at ${zp_buf:04X}..${zp_buf + ZP_SAVE_SIZE - 1:04X} violates ANDY ${ZP_SAVE_BASE:04X}..${HUFFDATA_LIMIT - 1:04X}"
            )
        if "ovl_huffdata_end" not in symbols:
            errors.append("missing symbol ovl_huffdata_end")
        elif symbols["ovl_huffdata_end"] > zp_buf:
            errors.append(
                f"ovl_huffdata_end at ${symbols['ovl_huffdata_end']:04X} overlaps ANDY zp_save_buf (${zp_buf:04X})"
            )

    # Check LYNNE aux range ($3F80-$43FF) below Mode 0 bitmap ($4400)
    for req_sym in ("recall_data_start", "recall_data_end", "beeb_lynne_aux_end"):
        if req_sym not in symbols:
            errors.append(f"missing LYNNE aux symbol {req_sym}")
    if all(s in symbols for s in ("recall_data_start", "recall_data_end", "beeb_lynne_aux_end")):
        r_start = symbols["recall_data_start"]
        r_end = symbols["recall_data_end"]
        l_end = symbols["beeb_lynne_aux_end"]
        if not (LYNNE_AUX_BASE <= r_start <= r_end <= l_end <= LYNNE_AUX_LIMIT):
            errors.append(
                f"LYNNE aux span ${r_start:04X}..${l_end:04X} violates ${LYNNE_AUX_BASE:04X}..${LYNNE_AUX_LIMIT - 1:04X}"
            )
        if r_end - r_start != 1116:
            errors.append(
                f"recall_data span ${r_start:04X}..${r_end:04X} is {r_end - r_start} B, expected 1116 B (279 * 4)"
            )

    # Check symbol overlap with protected windows ($0800-$0DFF MOS workspace, $A400-$A7FF tier pool, $C000-$FDFF MOS ROM)
    allowed_tier_pool = {"PLATFORM_TIER_NAME_POOL_BASE", "PLATFORM_TIER_NAME_POOL_END", "tier_name_pool"}
    # The monster catalog's labels are Sideways Bank 6 addresses
    # (catalog_fields..beeb_catalog_end, read only with Bank 6 selected):
    # their numbers fall in Bank 4's windows without sharing their RAM.
    catalog_span = range(symbols.get("catalog_fields", 0), symbols.get("beeb_catalog_end", 0))
    for sym, addr in symbols.items():
        if addr in catalog_span and sym.startswith(("cat_", "catn_", "catalog_")):
            continue
        if MOS_WORKSPACE_BASE <= addr <= MOS_WORKSPACE_END:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps untouched MOS/DFS workspace ($0800-$0DFF)"
            )
        elif TIER_POOL_BASE <= addr <= TIER_POOL_END and sym not in allowed_tier_pool:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps tier-name pool ($A400-$A7FF)"
            )
        elif MOS_ROM_BASE <= addr <= MOS_ROM_END:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps MOS 3.20 ROM ($C000-$FDFF)"
            )

    # Check moria8.res.prg ($0E00-$7FFF)
    res_prg = build_dir / "moria8.res.prg"
    if not res_prg.exists():
        errors.append("missing moria8.res.prg")
    else:
        start, end_excl = prg_span(res_prg)
        if start != LOW_RESIDENT_START:
            errors.append(f"moria8.res.prg load address ${start:04X} != ${LOW_RESIDENT_START:04X}")
        if end_excl > RESIDENT_LIMIT:
            errors.append(f"moria8.res.prg end ${end_excl:04X} exceeds ${RESIDENT_LIMIT:04X}")

    # Check beeb.play ($8000-$A3FF, starts with "M8P")
    play_prg = build_dir / "beeb.play"
    if not play_prg.exists():
        errors.append("missing beeb.play")
    else:
        start, end_excl = prg_span(play_prg)
        if start != PLAY_SLOT_BASE:
            errors.append(f"beeb.play load address ${start:04X} != ${PLAY_SLOT_BASE:04X}")
        if end_excl > PLAY_SLOT_LIMIT:
            errors.append(f"beeb.play end ${end_excl:04X} exceeds ${PLAY_SLOT_LIMIT:04X}")
        raw = play_prg.read_bytes()[2:5]
        if raw != b"M8P":
            errors.append(f"beeb.play missing 'M8P' signature (got {raw!r})")

    # Check beeb.auxdata ($6000-$76FF)
    aux_prg = build_dir / "beeb.auxdata"
    if not aux_prg.exists():
        errors.append("missing beeb.auxdata")
    else:
        start, end_excl = prg_span(aux_prg)
        if start != AUXDATA_VIRT_BASE:
            errors.append(f"beeb.auxdata load address ${start:04X} != ${AUXDATA_VIRT_BASE:04X}")
        if end_excl > AUXDATA_VIRT_LIMIT:
            errors.append(f"beeb.auxdata end ${end_excl:04X} exceeds ${AUXDATA_VIRT_LIMIT:04X}")

    # Check beeb.catalog ($9500-$B9FF in Bank 6)
    cat_prg = build_dir / "beeb.catalog"
    if not cat_prg.exists():
        errors.append("missing beeb.catalog")
    else:
        start, end_excl = prg_span(cat_prg)
        if start != CATALOG_BASE:
            errors.append(f"beeb.catalog load address ${start:04X} != ${CATALOG_BASE:04X}")
        if end_excl > CATALOG_LIMIT:
            errors.append(f"beeb.catalog end ${end_excl:04X} exceeds ${CATALOG_LIMIT:04X}")

    # Check beeb.huffdata ($8000-$8FFF in 4 KB ANDY, below zp_save_buf)
    huff_prg = build_dir / "beeb.huffdata"
    if not huff_prg.exists():
        errors.append("missing beeb.huffdata")
    else:
        start, end_excl = prg_span(huff_prg)
        huff_limit = symbols.get("zp_save_buf", ZP_SAVE_BASE)
        if start != HUFFDATA_BASE:
            errors.append(f"beeb.huffdata load address ${start:04X} != ${HUFFDATA_BASE:04X}")
        if end_excl > HUFFDATA_LIMIT:
            errors.append(f"beeb.huffdata end ${end_excl:04X} exceeds 4 KB ANDY limit (${HUFFDATA_LIMIT:04X})")
        elif end_excl > huff_limit:
            errors.append(
                f"beeb.huffdata end ${end_excl:04X} overlaps ANDY zp_save_buf (${huff_limit:04X})"
            )

    # Check overlays ($A800-$BFFF) and Sideways RAM cache caps
    sizes: dict[str, int] = {}
    if aux_prg.exists():
        aux_start, aux_end = prg_span(aux_prg)
        sizes["beeb.auxdata"] = aux_end - aux_start
    if cat_prg.exists():
        cat_start, cat_end = prg_span(cat_prg)
        sizes["beeb.catalog"] = cat_end - cat_start
    for name in OVERLAY_FILES:
        p = build_dir / name
        if not p.exists():
            errors.append(f"missing {name}")
            continue
        start, end_excl = prg_span(p)
        if start != OVERLAY_BASE:
            errors.append(f"{name} load address ${start:04X} != ${OVERLAY_BASE:04X}")
        if end_excl > OVERLAY_LIMIT:
            errors.append(f"{name} end ${end_excl:04X} exceeds ${OVERLAY_LIMIT:04X}")
        size = end_excl - start
        sizes[name] = size
        if name in SWR_CACHE_CAPS and size > SWR_CACHE_CAPS[name]:
            errors.append(f"{name} size {size} B exceeds Sideways RAM cache cap {SWR_CACHE_CAPS[name]} B")

    # Verify aggregate Sideways RAM bank page sums (<= 64 pages = 16,384 B per 16 KB bank)
    bank5_items = ("ovl.modal",)   # after the 52 pages of map and guard
    if all(k in sizes for k in bank5_items):
        bank5_pages = 52 + sum((sizes[k] + 255) // 256 for k in bank5_items)
        if bank5_pages > 64:
            errors.append(f"Sideways Bank 5 aggregate pages ({bank5_pages}) exceed 64-page (16 KB) bank limit")

    bank6_items = ("beeb.auxdata", "beeb.catalog", "ovl.ui")
    if all(k in sizes for k in bank6_items):
        bank6_pages = 2 + sum((sizes[k] + 255) // 256 for k in bank6_items)  # +2 pages ITEMCAT Slots 0..1 ($9300-$94FF)
        if bank6_pages > 64:
            errors.append(f"Sideways Bank 6 aggregate pages ({bank6_pages}) exceed 64-page (16 KB) bank limit")

    bank7_items = ("ovl.spell", "ovl.items", "ovl.gen")
    if all(k in sizes for k in bank7_items):
        bank7_pages = 4 + sum((sizes[k] + 255) // 256 for k in bank7_items)  # +4 pages ITEMCAT Slots 2..5 ($BC00-$BFFF)
        if bank7_pages > 64:
            errors.append(f"Sideways Bank 7 aggregate pages ({bank7_pages}) exceed 64-page (16 KB) bank limit")

    # Check title.prg ($8000) and boot.prg ($1900, <= 512 B)
    title_prg = build_dir / "title.prg"
    if not title_prg.exists():
        errors.append("missing title.prg")
    else:
        start, end_excl = prg_span(title_prg)
        if start != 0x8000:
            errors.append(f"title.prg load address ${start:04X} != $8000")

    boot_prg = build_dir / "boot.prg"
    if not boot_prg.exists():
        errors.append("missing boot.prg")
    else:
        start, end_excl = prg_span(boot_prg)
        if start != 0x1900 or (end_excl - start) > 512:
            errors.append(f"boot.prg span ${start:04X}-${end_excl:04X} must start at $1900 and fit <= 512 B")

    if src_dir is not None:
        errors.extend(validate_romsel_sync(src_dir))
        errors.extend(validate_low_mos_callers(src_dir))

    return errors


def loader_disk_names(storage: Path = STORAGE_SRC,
                      overlay_storage: Path = OVERLAY_STORAGE_SRC) -> dict[str, str]:
    """What -> DFS name for every file the game loads from the disk: each
    monster tier (none with the monster catalog), and each overlay the boot
    pack does not preload into Sideways RAM (beeb_ovl_cache_bank $00). Names
    come from the .byte data of the loader's own table in hal/storage.s."""
    names = {}
    for match in re.finditer(r"^hal_storage_(tier_\d|overlay_\w+?|item_cat)_name:\s*\n\s*\.byte\s+([^/\n]+)",
                             storage.read_text(), re.M):
        names[match.group(1)] = "".join(chr(int(b, 16)) for b in re.findall(r"\$([0-9a-fA-F]{2})", match.group(2)))
    text = overlay_storage.read_text()
    order = re.search(r"// Order: (.+?)\n// =+", text, re.S)
    if order is None:
        raise ValueError("overlay_storage.s: the '// Order:' comment listing the overlay classes is missing")
    order = order.group(1)
    classes = [c.lower() for c in re.findall(r"([A-Z]+)\(\d+\)", order)]
    banks = re.search(r"^beeb_ovl_cache_bank:\s*\n((?:\s*\.byte[^\n]*\n)+)", text, re.M)
    if banks is None:
        raise ValueError("overlay_storage.s: the beeb_ovl_cache_bank .byte table is missing")
    banks = banks.group(1)
    cached = [b.strip() != "$00" for b in re.sub(r"\s*\.byte\s*", ",", banks).strip(",").split(",")]
    if len(classes) != len(cached):
        raise ValueError(f"overlay_storage.s: {len(classes)} overlay classes, {len(cached)} cache entries")
    for cls, is_cached in zip(classes, cached):
        key = next((k for k in names if k.startswith(f"overlay_{cls}")), None)
        if key is None:
            raise ValueError(f"hal/storage.s has no filename for overlay {cls.upper()}")
        if is_cached:
            del names[key]
    main_text = MAIN_SRC.read_text()
    if "#define HAL_PLATFORM_MONSTER_CATALOG" in main_text:
        # The tier filenames compile out (#if !HAL_PLATFORM_MONSTER_CATALOG).
        names = {k: v for k, v in names.items() if not k.startswith("tier_")}
    elif sum(k.startswith("tier_") for k in names) != 4:
        raise ValueError("hal/storage.s: expected the four monster tier filenames")
    if "#define HAL_PLATFORM_ITEM_CAT_CUSTOM" in main_text:
        if "item_cat" not in names:
            raise ValueError("hal/storage.s has no filename for ITEMCAT")
    else:
        names.pop("item_cat", None)
    return names


def ssd_catalog(ssd: bytes) -> set[str]:
    """Names in the default ($) directory of an Acorn DFS single-sided
    image's catalogue, the one the loader reads."""
    return {ssd[8 + i * 8:15 + i * 8].decode("latin-1").rstrip()
            for i in range(ssd[0x105] // 8)
            if ssd[15 + i * 8] & 0x7F == ord("$")}   # bit 7: locked


def validate_disk(ssd: bytes, wanted: dict[str, str]) -> list[str]:
    """Every file the loader reads from DFS by name (loader_disk_names: the
    monster tiers and the overlays the boot pack does not preload) is on the
    disk, in the default directory."""
    catalog = ssd_catalog(ssd)
    return [f"{what} loads {name} from the disk, which does not have it"
            for what, name in sorted(wanted.items()) if name not in catalog]


def write_synthetic_prg(path: Path, start: int, length: int, prefix: bytes = b"") -> None:
    body = prefix + (b"\xea" * max(0, length - len(prefix)))
    path.write_bytes(struct.pack("<H", start) + body)


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        bdir = Path(tmp)
        sym_lines = [
            f".label {name}=${LOW_RESIDENT_START + i * 0x10:04x}"
            for i, name in enumerate(REQUIRED_LOW_SYMBOLS)
        ]
        sym_lines.extend([
            ".label program_end=$7b00",
            f".label ovl_huffdata_end=$8d94",
            f".label zp_save_buf=${ZP_SAVE_BASE:04x}",
            f".label recall_data_start=${LYNNE_AUX_BASE:04x}",
            f".label recall_data_end=${LYNNE_AUX_BASE + 1116:04x}",
            f".label beeb_lynne_aux_end=${LYNNE_AUX_BASE + 1116:04x}",
        ])
        base_sym_text = "\n".join(sym_lines) + "\n"
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")

        write_synthetic_prg(bdir / "moria8.res.prg", LOW_RESIDENT_START, 0x6D00)
        write_synthetic_prg(bdir / "beeb.play", PLAY_SLOT_BASE, 0x2000, prefix=b"M8P")
        write_synthetic_prg(bdir / "beeb.auxdata", AUXDATA_VIRT_BASE, 0x1300)
        write_synthetic_prg(bdir / "beeb.huffdata", HUFFDATA_BASE, 0x0D94)
        write_synthetic_prg(bdir / "beeb.catalog", CATALOG_BASE, 0x2417)
        write_synthetic_prg(bdir / "title.prg", 0x8000, 620)
        write_synthetic_prg(bdir / "boot.prg", 0x1900, 320)
        for name in OVERLAY_FILES:
            write_synthetic_prg(bdir / name, OVERLAY_BASE, 0x0400)

        errs = validate_build(bdir, src_dir=BEEB_SRC_DIR)
        if errs:
            print(f"FAIL: valid synthetic build rejected: {errs}", file=sys.stderr)
            return 1

        # Negative test 1: low helper at or above $3000 must fail
        (bdir / "main.sym").write_text(
            re.sub(r"\.label EnterMos=\$[0-9a-f]+", ".label EnterMos=$3000", base_sym_text),
            encoding="utf-8",
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch EnterMos >= $3000", file=sys.stderr)
            return 1

        # Negative test 2: program_end exceeding $8000 must fail
        (bdir / "main.sym").write_text(
            base_sym_text.replace("program_end=$7b00", "program_end=$8001"), encoding="utf-8"
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch program_end > $8000", file=sys.stderr)
            return 1

        # Negative test 3: symbol in MOS workspace ($0800-$0DFF) must fail
        (bdir / "main.sym").write_text(
            base_sym_text + ".label bad_mos_sym=$0900\n", encoding="utf-8"
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch symbol in $0800-$0DFF", file=sys.stderr)
            return 1

        # Negative test 4: symbol in tier-name pool ($A400-$A7FF) must fail
        (bdir / "main.sym").write_text(
            base_sym_text + ".label bad_tier_sym=$a500\n", encoding="utf-8"
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch symbol in $A400-$A7FF", file=sys.stderr)
            return 1

        # Negative test 5: beeb.huffdata exceeding 4 KB ANDY ($9000) must fail
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")
        write_synthetic_prg(bdir / "beeb.huffdata", HUFFDATA_BASE, 0x1001)
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch beeb.huffdata > $9000", file=sys.stderr)
            return 1

        # Negative test 6: beeb.huffdata overlapping zp_save_buf ($8F00) must fail
        write_synthetic_prg(bdir / "beeb.huffdata", HUFFDATA_BASE, 0x0F01)
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch beeb.huffdata overlapping zp_save_buf ($8F00)", file=sys.stderr)
            return 1
        write_synthetic_prg(bdir / "beeb.huffdata", HUFFDATA_BASE, 0x0D94)

        # Negative test 7: zp_save_buf + ZP_SAVE_SIZE exceeding $9000 must fail
        (bdir / "main.sym").write_text(
            base_sym_text.replace("zp_save_buf=$8f00", "zp_save_buf=$8f80"), encoding="utf-8"
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch zp_save_buf exceeding $9000", file=sys.stderr)
            return 1

        # Negative test 8: ovl_huffdata_end overlapping zp_save_buf must fail
        (bdir / "main.sym").write_text(
            base_sym_text.replace("ovl_huffdata_end=$8d94", "ovl_huffdata_end=$8f01"), encoding="utf-8"
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch ovl_huffdata_end > zp_save_buf", file=sys.stderr)
            return 1

        # Negative test 9: LYNNE aux exceeding $4400 Mode 0 bitmap must fail
        (bdir / "main.sym").write_text(
            base_sym_text.replace(
                f"beeb_lynne_aux_end=${LYNNE_AUX_BASE + 1116:04x}",
                "beeb_lynne_aux_end=$4401",
            ),
            encoding="utf-8",
        )
        if not validate_build(bdir, src_dir=None):
            print("FAIL: failed to catch LYNNE aux >= $4400", file=sys.stderr)
            return 1

        # Negative tests 10-11: static SHEILA_ROMSEL sync and SEI audit
        bad_src = bdir / "src"
        bad_src.mkdir()
        (bad_src / "good.s").write_text(
            "ok_fn:\n    php\n    sei\n    lda #ROMSEL_BANK4\n    sta zp_mos_romsel_shadow\n    sta SHEILA_ROMSEL\n    plp\n    rts\n",
            encoding="utf-8",
        )
        if validate_romsel_sync(bad_src):
            print("FAIL: valid ROMSEL switch rejected", file=sys.stderr)
            return 1
        (bad_src / "no_shadow.s").write_text(
            "bad_shadow:\n    sei\n    lda #ROMSEL_BANK5\n    sta SHEILA_ROMSEL\n    cli\n    rts\n",
            encoding="utf-8",
        )
        if not validate_romsel_sync(bad_src):
            print("FAIL: failed to catch SHEILA_ROMSEL write missing zp_mos_romsel_shadow sync", file=sys.stderr)
            return 1
        (bad_src / "no_shadow.s").unlink()
        (bad_src / "no_sei.s").write_text(
            "bad_sei:\n    lda #ROMSEL_BANK4\n    sta zp_mos_romsel_shadow\n    sta SHEILA_ROMSEL\n    rts\n",
            encoding="utf-8",
        )
        if not validate_romsel_sync(bad_src):
            print("FAIL: failed to catch SHEILA_ROMSEL write outside SEI", file=sys.stderr)
            return 1
        (bad_src / "no_sei.s").write_text(
            "bad_after_plp:\n    php\n    sei\n    plp\n    lda #ROMSEL_BANK4\n    sta zp_mos_romsel_shadow\n    sta SHEILA_ROMSEL\n    rts\n",
            encoding="utf-8",
        )
        if not validate_romsel_sync(bad_src):
            print("FAIL: failed to catch SHEILA_ROMSEL write after plp", file=sys.stderr)
            return 1
        (bad_src / "disk_setup_beeb.s").write_text(
            "bad_ovl_mos:\n    jsr EnterMos\n    rts\n",
            encoding="utf-8",
        )
        if not validate_low_mos_callers(bad_src):
            print("FAIL: failed to catch EnterMos call outside < $3000 modules", file=sys.stderr)
            return 1

        # The disk: every file the loader takes from DFS is on it.
        sys.path.insert(0, str(ROOT / "tools"))
        from make_ssd import DfsFileSpec, build_ssd_image
        wanted = loader_disk_names()
        if (wanted.get("overlay_town") != "OVLTWN"
                or wanted.get("overlay_home") != "OVLHOM"
                or wanted.get("item_cat") != "ITEMCAT"
                or any(k.startswith("tier_") for k in wanted)):
            print(f"FAIL: loader names misread: {wanted}", file=sys.stderr)
            return 1
        def spec(n: str, d: str = "$", lk: bool = False) -> DfsFileSpec:
            return DfsFileSpec(name=n, directory=d, locked=lk, load_addr=0, exec_addr=0, data=b"x")

        full = build_ssd_image([spec(n, lk=(n == "OVLTWN")) for n in wanted.values()])
        if validate_disk(full, wanted):
            print("FAIL: a disk with every loaded file rejected", file=sys.stderr)
            return 1
        short = build_ssd_image([spec(n) for n in wanted.values() if n != "OVLTWN"])
        if not validate_disk(short, wanted):
            print("FAIL: failed to catch OVLTWN missing from the disk", file=sys.stderr)
            return 1
        elsewhere = build_ssd_image([spec(n, "A" if n == "OVLTWN" else "$") for n in wanted.values()])
        if not validate_disk(elsewhere, wanted):
            print("FAIL: failed to catch OVLTWN outside the default directory", file=sys.stderr)
            return 1

    print("BBC Master 128 memory contract self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run synthetic pass/fail self-tests.")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--disk", type=Path, help="check this .ssd holds every file the game loads from DFS")
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    if args.disk:
        errors = validate_disk(args.disk.read_bytes(), loader_disk_names())
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        print(f"BBC Master 128 disk check {'FAILED' if errors else 'passed'}: {args.disk.name}")
        return 1 if errors else 0

    errors = validate_build(args.build_dir)
    if errors:
        print("BBC Master 128 memory contract check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    print("BBC Master 128 memory contract check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
