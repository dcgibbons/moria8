#!/usr/bin/env python3
"""Static linter forbidding raw numeric item IDs in assembly, Python, and shell tests.

Scans core/**/*.s, platforms/**/*.{s,py,sh} (excluding generated item_catalog and
monster catalog payloads), playtest/**/*.py, and tools/check_wizard_doc.py for:
  - Raw numeric item IDs stored into inv_item_id, fi_item_id, si_item_id,
    fi_add_id, piw_item_id, icat_sel_lo, and related item-ID holders
  - Raw numeric item IDs or ranges compared against item-ID registers/holders,
    intra-routine scratch saves (e.g. zp_temp0), or adjacent to item_cur_page /
    re_page / piw_ego page guards
  - Raw numeric item-ID .const definitions, .byte/.word item tables, and 8-byte
    inventory-record .byte fixtures (byte 0 = inv_item_id)
  - Raw numeric item IDs in Python/Lua/shell test harnesses, monitor pokes,
    --expect-byte-symbol checks, symbol aliases, field-0 readers (_inv_field /
    inv_get), and save-seed fixtures

Intentional synthetic out-of-bounds test literals may opt out on the same line
with a trailing `raw-id-ok: <reason>` comment.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import item_ids as _gen_item_ids  # noqa: E402

KNOWN_ITEM_SLUGS: frozenset[str] = frozenset(_gen_item_ids.ID_BY_SLUG.keys())
if not KNOWN_ITEM_SLUGS or len(KNOWN_ITEM_SLUGS) != _gen_item_ids.ITEM_TYPE_COUNT:
    raise RuntimeError(f"item_ids loaded invalid slug table (count={len(KNOWN_ITEM_SLUGS)})")

EXCLUDED_S_REL = {
    "platforms/shared/item_catalog/item_ids.s",
    "platforms/shared/item_catalog/item_hot_tables.s",
    "platforms/shared/item_catalog/item_cat_layout.s",
    "platforms/shared/item_catalog/item_cat_data.s",
}

WRITABLE_ITEM_ID_VARS = {
    "inv_item_id",
    "fi_item_id",
    "si_item_id",
    "fi_add_id",
    "piw_item_id",
    "itemdesc_item_id",
    "item_display_id",
    "irs_re_item",
    "ss_item_id",
    "sd_save_item_id",
    "sb_item_type",
    "tw_item_id",
    "ipc_warm_id",
}

PAGE_GUARD_VARS = {
    "item_cur_page",
    "re_page",
    "piw_ego",
}

ENTRY_ITEM_PARAM_REGS = {
    "put_tool_ego_prefix": "x",
    "eff_potion_gain_stat": "a",
    "iq_dispatch_p3_spell": "a",
    "c128_quaff_p3_dispatch": "a",
    "hal_quaff_p3_dispatch": "a",
    "ipc_check_non_gold_ay": "a",
    "ep1_run_slot": "a",
    "eff_ext_quaff": "a",
    "eff_ext_eat": "a",
    "roll_enchantment": "a",
    "irs_dispatch_p3_overlay": "a",
    "irs_p3_run_existing": "a",
}

# Scratch low-byte selectors where `lda #0` may zero-init a 16-bit accumulator,
# while any non-zero literal (or explicit item load) is a raw item ID.
SCRATCH_ZERO_OK_VARS = {
    "icat_sel_lo",
    "it_id_lo",
}

READABLE_ITEM_ID_VARS = WRITABLE_ITEM_ID_VARS | SCRATCH_ZERO_OK_VARS | {
    "sro_choices",
    "sro_general_choice",
    "sro_temple_choice",
    "sro_alchemy_choice",
    "sro_choices_p1_start",
    "sro_choices_p1_end",
    "sro_stack_id",
    "sro_stack_p1_id",
    "esm_p0_ids",
    "esm_p1_ids",
    "store_choice",
    "store_fallback",
    "book_type_ids",
    "pit_sorted_lo",
}

ITEM_TABLE_LABELS = {
    "sro_choices",
    "sro_general_choice",
    "sro_temple_choice",
    "sro_alchemy_choice",
    "sro_choices_p1_start",
    "sro_choices_p1_end",
    "sro_stack_id",
    "sro_stack_p1_id",
    "esm_p0_ids",
    "esm_p1_ids",
    "store_choice",
    "store_fallback",
    "book_type_ids",
    "pit_sorted_lo",
    "t55_ids",
    "t55_p1_ids",
    "t48_general_set",
    "t48_temple_set",
    "t48_alchemy_set",
}

# 8-byte inventory-slot fixtures `[id, qty, p1, to_hit, to_dam, to_ac, flags, ego]`
# where element [0] is an item slot_lo.
INV_RECORD_LABELS = {
    "spss_fields",
    "xps_primary",
    "xps_secondary",
}

ITEM_TABLE_LABEL_RE = re.compile(
    r"^(?:store_choice[a-z0-9_]*|starting_kit[a-z0-9_]*|[a-z0-9_]*_item_ids|[a-z0-9_]*_item_types)$",
    re.IGNORECASE,
)

NON_ITEM_MEM_PREFIXES = (
    "inv_qty",
    "inv_p1",
    "inv_to_",
    "inv_flags",
    "inv_ego",
    "fi_qty",
    "fi_p1",
    "fi_to_",
    "fi_flags",
    "fi_meta",
    "fi_x",
    "fi_y",
    "fi_add_qty",
    "fi_add_p1",
    "fi_add_to_",
    "fi_add_flags",
    "fi_add_ego",
    "si_qty",
    "si_p1",
    "si_to_",
    "si_meta",
    "piw_qty",
    "piw_p1",
    "piw_flags",
    "piw_slot",
    "piw_equip",
    "piw_filter",
    "piw_visible_count",
    "player_",
    "zp_player_",
    "zp_eff_",
    "zp_turn_",
    "zp_mon_",
    "zp_dirty_",
    "re_cat",
    "re_bonus_",
    "tun_dig_ability",
    "current_overlay",
    "pm_spell_idx",
    "icat_flags_",
    "icat_p1_",
    "icat_weight_",
    "icat_cost_",
    "icat_dmg_",
)

STRUCTURAL_ITEM_CONSTS = {
    "ITEM_TYPE_COUNT",
    "ITEM_PAGE_SIZE",
    "ITEM_PAGE_BIT",
    "ITEM_META_FLAGS_MASK",
    "ITEM_ID_CAPACITY",
    "ITEM_NAME_DECODE_BUF_SIZE",
    "ITEM_CAT_FILE_NUM",
    "ITEM_CAT_FILENAME_LEN",
    "ITEM_CAT_REU_BANK",
    "ITEM_CAT_REU_BASE",
    "ITEM_CAT_BUF_BASE",
    "ITEM_PICKUP_CACHE_BASE",
    "ITEM_PICKUP_CACHE_SIZE",
    "ITEM_PICKUP_CACHE_END",
}

ITEM_CONST_DEF_RE = re.compile(
    r"^(?:ITEM_[A-Z0-9_]+|IT_MISSILE2?_(?:BASE|END)|[A-Z0-9_]*_ITEM_ID|TEST_ITEM_[A-Z0-9_]*)$"
)

IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
INT_TOKEN_RE = re.compile(r"\$[0-9A-Fa-f]+|%[01]+|\b\d+\b")


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    detail: str

    def format(self) -> str:
        return f"{self.path}:{self.line}: [{self.rule}] {self.detail}"


def _parse_int_token(tok: str) -> int:
    if tok.startswith("$"):
        return int(tok[1:], 16)
    if tok.startswith("%"):
        return int(tok[1:], 2)
    return int(tok, 10)


def _is_structural_item_const(name: str) -> bool:
    return name in STRUCTURAL_ITEM_CONSTS or name.startswith(("ITEM_PICKUP_CACHE_", "ITEM_CAT_"))


def _has_symbolic_item_ref(expr: str) -> bool:
    for ident in IDENT_RE.findall(expr):
        if _is_structural_item_const(ident):
            continue
        if ident.startswith(("ITEM_", "IT_MISSILE")):
            return True
    return False


def is_empty_sentinel(expr: str) -> bool:
    s = expr.strip()
    while s.startswith("(") and s.endswith(")"):
        s = s[1:-1].strip()
    if s in ("FI_EMPTY", "EMPTY_SLOT"):
        return True
    if re.fullmatch(r"\$[fF]{2}|255|-1", s):
        return True
    return False


def is_raw_item_expr(expr: str, *, allow_zero: bool = False) -> bool:
    """Return True when KickAss expression encodes a raw numeric item ID."""
    s = expr.strip()
    if not s or is_empty_sentinel(s):
        return False
    if s[0] in "<>":
        s = s[1:].strip()
    while s.startswith("(") and s.endswith(")"):
        inner = s[1:-1].strip()
        if inner.count("(") == inner.count(")"):
            s = inner
        else:
            break

    if _has_symbolic_item_ref(s):
        return False

    idents = IDENT_RE.findall(s)
    if idents and all(ident == "ITEM_PAGE_SIZE" for ident in idents):
        ints = INT_TOKEN_RE.findall(s)
        return len(ints) > 0
    if idents:
        return False

    m = re.fullmatch(r"(\$[0-9A-Fa-f]+|%[01]+|\d+)", s)
    if not m:
        return False
    val = _parse_int_token(m.group(1))
    if val == 0xFF:
        return False
    if allow_zero and val == 0:
        return False
    return 0 <= val <= 511


def _strip_asm_comment(line: str) -> str:
    in_str = False
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if ch == '"':
            in_str = not in_str
        elif not in_str and ch == "/" and i + 1 < n and line[i + 1] == "/":
            return line[:i]
        i += 1
    return line


def _split_asm_statements(code: str) -> list[str]:
    parts: list[str] = []
    cur: list[str] = []
    in_str = False
    for ch in code:
        if ch == '"':
            in_str = not in_str
            cur.append(ch)
        elif ch == ";" and not in_str:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


def _split_csv_top_level(arg_str: str) -> list[str]:
    out: list[str] = []
    cur: list[str] = []
    depth = 0
    in_str = False
    for ch in arg_str:
        if ch == '"':
            in_str = not in_str
            cur.append(ch)
        elif not in_str:
            if ch == "(":
                depth += 1
                cur.append(ch)
            elif ch == ")" and depth > 0:
                depth -= 1
                cur.append(ch)
            elif ch == "," and depth == 0:
                out.append("".join(cur).strip())
                cur = []
            else:
                cur.append(ch)
        else:
            cur.append(ch)
    if cur:
        out.append("".join(cur).strip())
    return out


def _mem_base_symbol(operand: str) -> str | None:
    op = operand.strip()
    if not op or op.startswith("#"):
        return None
    op = re.sub(r",\s*[xXyY]\s*$", "", op).strip()
    m = IDENT_RE.match(op)
    return m.group(0) if m else None


def _is_known_non_item_mem(base: str | None) -> bool:
    if not base:
        return False
    return base.startswith(NON_ITEM_MEM_PREFIXES)


def _find_inv_record_labels(text: str) -> set[str]:
    """Identify 8-byte inventory-record tables copied into inv_item_id via indexed loops."""
    labels = set(INV_RECORD_LABELS)
    lines = [_strip_asm_comment(l) for l in text.splitlines()]
    for idx, line in enumerate(lines):
        for m in re.finditer(r"\blda\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*[xXyY]\b", line):
            cand = m.group(1)
            if cand in READABLE_ITEM_ID_VARS or _is_known_non_item_mem(cand):
                continue
            window = "\n".join(lines[idx : min(len(lines), idx + 6)])
            if re.search(r"\bsta\s+inv_item_id\b", window) and "TOTAL_INV_SLOTS" in "\n".join(
                lines[idx : min(len(lines), idx + 12)]
            ):
                labels.add(cand)
    return labels


def scan_asm_text(text: str, rel_path: str) -> list[Finding]:
    """Scan a Kick Assembler source file for raw numeric item IDs."""
    findings: list[Finding] = []
    backward_loop_labels = set(
        re.findall(r"\b(?:bcc|bcs|beq|bne|bmi|bpl|bvc|bvs|bra)\s+(!\w+)-", text, re.IGNORECASE)
    )
    mutated_mem_vars = set(
        re.findall(r"\b(?:inc|dec)\s+([A-Za-z_][A-Za-z0-9_]*)\b", text, re.IGNORECASE)
    )
    inv_rec_labels = _find_inv_record_labels(text)

    # Register/scratch state:
    #   None | ("raw", expr_str, src_line) | ("item_var", sym, src_line)
    #   | ("other_mem", sym, src_line) | ("non_item_mem", sym, src_line)
    #   | ("page_var", sym, src_line) | ("sym_imm", expr, src_line)
    #   | ("computed", op, src_line)
    regs: dict[str, tuple[str, str, int] | None] = {"a": None, "x": None, "y": None}
    scratch_vars: dict[str, tuple[str, str, int] | None] = {}
    stack: list[tuple[str, str, int] | None] = []
    active_table_label: str | None = None
    active_inv_rec_label: str | None = None
    page_guard_TTL = 0

    for line_no, raw_line in enumerate(text.splitlines(), 1):
        if "raw-id-ok:" in raw_line:
            continue
        stripped_comment = _strip_asm_comment(raw_line)
        if not stripped_comment.strip():
            continue

        if stripped_comment.lstrip().startswith("#"):
            if re.match(r"^\s*#(?:else|elif|endif)\b", stripped_comment):
                regs = {"a": None, "x": None, "y": None}
                page_guard_TTL = 0
            continue

        for stmt in _split_asm_statements(stripped_comment):
            s = stmt.strip()
            if not s:
                continue

            # 1. Check .const definitions
            m_const = re.match(r"^\.(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", s)
            if m_const:
                cname, cexpr = m_const.group(1), m_const.group(2).strip()
                if not _is_structural_item_const(cname) and ITEM_CONST_DEF_RE.match(cname):
                    if is_raw_item_expr(cexpr):
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-const",
                                f".const {cname} = {cexpr} uses raw numeric item ID",
                            )
                        )
                continue

            while True:
                m_lbl = re.match(r"^(!?[A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", s)
                if not m_lbl:
                    break
                lbl, rest = m_lbl.group(1), m_lbl.group(2).strip()
                if not lbl.startswith("!"):
                    if rest.startswith(".byte") and lbl in (WRITABLE_ITEM_ID_VARS | SCRATCH_ZERO_OK_VARS | PAGE_GUARD_VARS):
                        active_table_label = None
                        active_inv_rec_label = None
                    elif lbl in inv_rec_labels:
                        active_inv_rec_label = lbl
                        active_table_label = None
                    elif lbl in ITEM_TABLE_LABELS or ITEM_TABLE_LABEL_RE.match(lbl):
                        active_table_label = lbl
                        active_inv_rec_label = None
                    elif not lbl.endswith("_end"):
                        active_table_label = None
                        active_inv_rec_label = None
                    regs = {"a": None, "x": None, "y": None}
                    scratch_vars.clear()
                    if lbl in ENTRY_ITEM_PARAM_REGS:
                        regs[ENTRY_ITEM_PARAM_REGS[lbl]] = ("item_var", f"{lbl}_param", line_no)
                    stack.clear()
                    page_guard_TTL = 0
                elif lbl in backward_loop_labels:
                    regs["x"] = ("computed", "loop_idx", line_no)
                    regs["y"] = ("computed", "loop_idx", line_no)
                s = rest
                if not s:
                    break
            if not s:
                continue

            # 2. Check .byte / .word inside item ID tables or 8-byte inventory records
            m_data = re.match(r"^\.(byte|word)\s+(.+)$", s)
            if m_data:
                elems = _split_csv_top_level(m_data.group(2))
                if active_inv_rec_label is not None:
                    if elems and is_raw_item_expr(elems[0]):
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-table",
                                f"inventory record '{active_inv_rec_label}' byte 0 '{elems[0]}' uses raw numeric item ID",
                            )
                        )
                    active_inv_rec_label = None
                elif active_table_label is not None:
                    for elem in elems:
                        if is_raw_item_expr(elem):
                            findings.append(
                                Finding(
                                    rel_path,
                                    line_no,
                                    "raw-item-table",
                                    f"table '{active_table_label}' entry '{elem}' uses raw numeric item ID",
                                )
                            )
                continue

            if s.startswith("."):
                continue

            active_table_label = None
            active_inv_rec_label = None
            if page_guard_TTL > 0:
                page_guard_TTL -= 1

            # 3. Handle macros :AuxReadX(sym) / :AuxWriteX(sym)
            m_mac = re.match(r"^:([A-Za-z_][A-Za-z0-9_]*)\((.*)\)$", s)
            if m_mac:
                mname, marg = m_mac.group(1), m_mac.group(2).strip()
                base_sym = _mem_base_symbol(marg)
                if mname.startswith("AuxRead") and base_sym:
                    if base_sym in READABLE_ITEM_ID_VARS:
                        regs["a"] = ("item_var", base_sym, line_no)
                    elif _is_known_non_item_mem(base_sym):
                        regs["a"] = ("non_item_mem", base_sym, line_no)
                    else:
                        regs["a"] = ("other_mem", base_sym, line_no)
                elif mname.startswith("AuxWrite") and base_sym:
                    if base_sym in WRITABLE_ITEM_ID_VARS and regs["a"] and regs["a"][0] == "raw":
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-store",
                                f":{mname}({marg}) stores raw #{regs['a'][1]} (loaded at line {regs['a'][2]})",
                            )
                        )
                continue

            # 4. Standard 6502/65C02 instruction parsing
            m_ins = re.match(r"^([A-Za-z]{3})(?:\s+(.*))?$", s)
            if not m_ins:
                continue
            op = m_ins.group(1).lower()
            arg = (m_ins.group(2) or "").strip()

            if op == "bit" and _mem_base_symbol(arg) in PAGE_GUARD_VARS:
                page_guard_TTL = 20
                continue

            if op in ("lda", "ldx", "ldy"):
                reg = op[2]
                if arg.startswith("#"):
                    imm = arg[1:].strip()
                    if is_raw_item_expr(imm):
                        regs[reg] = ("raw", imm, line_no)
                    else:
                        regs[reg] = ("sym_imm", imm, line_no)
                else:
                    base = _mem_base_symbol(arg)
                    if base in PAGE_GUARD_VARS:
                        page_guard_TTL = 20
                        regs[reg] = ("page_var", base, line_no)
                    elif base in READABLE_ITEM_ID_VARS:
                        regs[reg] = ("item_var", base, line_no)
                    elif base and base in scratch_vars and scratch_vars[base] is not None:
                        regs[reg] = scratch_vars[base]
                    elif _is_known_non_item_mem(base):
                        regs[reg] = ("non_item_mem", base or arg, line_no)
                    else:
                        regs[reg] = ("other_mem", base or arg, line_no)
                continue

            if op in ("sta", "stx", "sty"):
                reg = op[2]
                base = _mem_base_symbol(arg)
                rstate = regs[reg]
                if rstate and rstate[0] == "raw":
                    if base in WRITABLE_ITEM_ID_VARS:
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-store",
                                f"{op} {arg} stores raw #{rstate[1]} (loaded at line {rstate[2]})",
                            )
                        )
                    elif base in SCRATCH_ZERO_OK_VARS and rstate[1].strip() not in ("0", "$00", "$0"):
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-store",
                                f"{op} {arg} stores raw #{rstate[1]} (loaded at line {rstate[2]})",
                            )
                        )
                if (
                    base
                    and "," not in arg
                    and "+" not in arg
                    and "-" not in arg
                    and base not in WRITABLE_ITEM_ID_VARS
                    and base not in PAGE_GUARD_VARS
                    and base not in mutated_mem_vars
                    and not _is_known_non_item_mem(base)
                ):
                    scratch_vars[base] = rstate
                continue

            if op in ("tax", "tay"):
                regs[op[2]] = regs["a"]
                continue
            if op in ("txa", "tya"):
                regs["a"] = regs[op[1]]
                continue
            if op == "pha":
                stack.append(regs["a"])
                continue
            if op == "pla":
                regs["a"] = stack.pop() if stack else None
                continue
            if op == "phx":
                stack.append(regs["x"])
                continue
            if op == "plx":
                regs["x"] = stack.pop() if stack else None
                continue
            if op == "phy":
                stack.append(regs["y"])
                continue
            if op == "ply":
                regs["y"] = stack.pop() if stack else None
                continue

            if op in ("cmp", "cpx", "cpy", "sbc") and arg.startswith("#"):
                reg = "a" if op in ("cmp", "sbc") else op[2]
                imm = arg[1:].strip()
                rstate = regs[reg]
                in_item_ctx = (rstate is not None and rstate[0] == "item_var") or (
                    page_guard_TTL > 0
                    and (
                        rstate is None
                        or rstate[0] in ("item_var", "raw", "other_mem")
                    )
                )
                if in_item_ctx and is_raw_item_expr(imm):
                    src_desc = (
                        f"{rstate[1]} (line {rstate[2]})"
                        if (rstate and rstate[0] == "item_var")
                        else "page-guarded item context"
                    )
                    findings.append(
                        Finding(
                            rel_path,
                            line_no,
                            "raw-item-cmp",
                            f"{op} #{imm} compares raw numeric item ID against {src_desc}",
                        )
                    )
                if op == "sbc":
                    regs["a"] = ("computed", "sbc", line_no)
                continue

            if op == "jsr":
                callee = _mem_base_symbol(arg)
                if callee in ("item_cat_select_id", "item_get_category_a", "item_get_color_a", "item_get_unknown_idx_a"):
                    if regs["a"] and regs["a"][0] == "raw":
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-call",
                                f"jsr {callee} called with raw A=#{regs['a'][1]} (line {regs['a'][2]})",
                            )
                        )
                elif callee in ("item_get_weight_x", "item_get_dmg_packed_x", "item_get_cost_x", "item_get_display_char", "item_get_missile", "id_known_test", "id_known_set"):
                    if regs["x"] and regs["x"][0] == "raw":
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-call",
                                f"jsr {callee} called with raw X=#{regs['x'][1]} (line {regs['x'][2]})",
                            )
                        )
                elif callee == "item_unpack_id_ay":
                    if regs["a"] and regs["a"][0] == "raw":
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "raw-item-call",
                                f"jsr item_unpack_id_ay called with raw A=#{regs['a'][1]} (line {regs['a'][2]})",
                            )
                        )
                regs = {"a": None, "x": None, "y": None}
                continue

            if op in ("jmp", "rts", "rti", "brk"):
                regs = {"a": None, "x": None, "y": None}
                stack.clear()
                page_guard_TTL = 0
                continue

            if op in ("adc", "and", "ora", "eor", "asl", "lsr", "rol", "ror"):
                if not arg or arg.lower() == "a":
                    regs["a"] = ("computed", op, line_no)
                elif op in ("adc", "and", "ora", "eor"):
                    regs["a"] = ("computed", op, line_no)
                continue
            if op in ("inx", "dex"):
                regs["x"] = ("computed", op, line_no)
                continue
            if op in ("iny", "dey"):
                regs["y"] = ("computed", op, line_no)
                continue

    return findings


PY_ITEM_SYM_NAMES = (
    "inv_item_id",
    "fi_item_id",
    "si_item_id",
    "fi_add_id",
    "piw_item_id",
    "store_choice",
)

PY_ALIAS_ASSIGN_RE = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[^\n#]*?[\"\']\.?(?:inv_item_id|fi_item_id|si_item_id|fi_add_id|piw_item_id)[\"\']"
)
PY_SEED_RECORD_VAR_RE = re.compile(
    r"\b(?:_?inv_seed|_?floor_seed|seed_slot)\s*\((?:[^,]+,\s*){1,2}([A-Za-z_][A-Za-z0-9_]*)\s*\)"
)
PY_WRITE_CALL_RE = re.compile(
    r"\b(?:poke|write_byte|write_u8)\s*\(\s*([^,]+?)\s*,\s*(?:bytes\(\s*\[\s*)?(0x[0-9A-Fa-f]+|\d+)\s*\]?\s*\)?\s*\)"
)
PY_INDEX_ASSIGN_RE = re.compile(
    r"\b(item_ids|inv_item_id|fi_item_id|si_item_id)\s*\[[^\]]+\]\s*=\s*(0x[0-9A-Fa-f]+|\d+)\b"
)
PY_SEED_CALL_RE = re.compile(
    r"\b(?:_?inv_seed|_?floor_seed|seed_slot)\s*\((?:[^,]+,\s*){1,2}[\{\[\(]\s*(0x[0-9A-Fa-f]+|\d+)\b"
)
PY_FIELD0_CALL_RE = re.compile(
    r"\b(?:_inv_field\s*\(\s*[^,]+,\s*[^,]+,\s*0\s*\)|inv_get\s*\(\s*[^,]+,\s*0\s*\))"
)
PY_NON_ITEM_CONST_PREFIXES = (
    "EGO_",
    "ICAT_",
    "IF_",
    "EQUIP_",
    "PL_",
    "KEY_",
    "MX_",
    "MAP_",
    "MAX_",
    "TOTAL_",
    "STORE_",
    "SAVE_",
    "FLAVOUR_",
    "ID_KNOWN_",
    "CATALOG_",
    "MONSTER_",
    "RECALL_",
    "PACK_",
    "SEED",
    "SHOT",
    "ITEM_TYPE_COUNT",
    "ITEM_PAGE_",
    "FI_EMPTY",
    "EMPTY_SLOT",
)


def _py_is_raw_id(lit: str) -> bool:
    val = int(lit, 16) if lit.lower().startswith("0x") else int(lit, 10)
    if val == 0xFF:
        return False
    return 0 <= val <= 511


def _is_py_item_const_name(name: str, comment: str) -> bool:
    if name.startswith(PY_NON_ITEM_CONST_PREFIXES):
        return False
    if name.endswith("_ITEM_ID"):
        return True
    if name in KNOWN_ITEM_SLUGS or f"SPELLBOOK_{name}" in KNOWN_ITEM_SLUGS:
        return True
    if ("WIZARD.md" in comment or "item_catalog_spec.json" in comment) and re.fullmatch(
        r"[A-Z][A-Z0-9_]*", name
    ):
        return True
    return False


def scan_py_text(text: str, rel_path: str) -> list[Finding]:
    """Scan a Python test/fixture/harness file (including embedded Lua) for raw item IDs."""
    findings: list[Finding] = []
    lines = text.splitlines()

    # Pass 1: collect 8-byte record variables passed to `_inv_seed` / `seed_slot`.
    seed_rec_vars: set[str] = set()
    for raw_line in lines:
        if "raw-id-ok:" in raw_line:
            continue
        code_only = raw_line.split("#", 1)[0]
        for m_rv in PY_SEED_RECORD_VAR_RE.finditer(code_only):
            seed_rec_vars.add(m_rv.group(1))

    base_aliases = set(PY_ITEM_SYM_NAMES) | {"inv_id_base", "fi_id_base"}
    module_aliases = set(base_aliases)
    local_aliases = set(base_aliases)

    for line_no, raw_line in enumerate(lines, 1):
        if "raw-id-ok:" in raw_line:
            continue
        py_comment = raw_line.split("#", 1)[1] if "#" in raw_line else ""
        code = raw_line.split("#", 1)[0]
        if "--" in code:
            code = code.split("--", 1)[0]
        if not code.strip():
            continue

        # Scope local symbol aliases per function (`def ...:` resets to module_aliases)
        if re.match(r"^(?:def|class)\s+[A-Za-z_]", code):
            local_aliases = set(module_aliases)

        m_al = PY_ALIAS_ASSIGN_RE.match(code)
        if m_al:
            vname = m_al.group(1)
            local_aliases.add(vname)
            if not code[0].isspace():
                module_aliases.add(vname)
        else:
            m_rebind = re.match(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", code)
            if m_rebind:
                vname = m_rebind.group(2)
                if vname not in base_aliases:
                    local_aliases.discard(vname)
                    if not m_rebind.group(1):
                        module_aliases.discard(vname)

        item_target_re = re.compile(
            r"\b(?:" + "|".join(re.escape(n) for n in sorted(local_aliases)) + r")\b"
        )
        cmp_item_re = re.compile(
            r"(" + "|".join(re.escape(n) for n in sorted(local_aliases)) + r")[^\n#]*?(?:==|!=|>=|<=|<|>)\s*(0x[0-9A-Fa-f]+|\d+)\b"
        )

        for m in PY_WRITE_CALL_RE.finditer(code):
            target_expr, lit = m.group(1), m.group(2)
            if item_target_re.search(target_expr) and _py_is_raw_id(lit):
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "py-raw-item-write",
                        f"raw item ID {lit} written to {target_expr.strip()}",
                    )
                )

        for m in PY_INDEX_ASSIGN_RE.finditer(code):
            arr, lit = m.group(1), m.group(2)
            if _py_is_raw_id(lit):
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "py-raw-item-assign",
                        f"raw item ID {lit} assigned into {arr}[...]",
                    )
                )

        for m in PY_SEED_CALL_RE.finditer(code):
            lit = m.group(1)
            if _py_is_raw_id(lit):
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "py-raw-item-seed",
                        f"inventory/floor seed uses raw item ID {lit}",
                    )
                )

        # Seed record list/tuple variable assignment: e.g. `cloak_rec = [82, 1, ...]`
        m_rec = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[\[\(]\s*(0x[0-9A-Fa-f]+|\d+)\b", code)
        if m_rec and m_rec.group(1) in seed_rec_vars and _py_is_raw_id(m_rec.group(2)):
            findings.append(
                Finding(
                    rel_path,
                    line_no,
                    "py-raw-item-seed",
                    f"seed record '{m_rec.group(1)}' byte 0 uses raw item ID {m_rec.group(2)}",
                )
            )

        # Single or tuple constant assignments: `MAGICK_I = 55`, `SHORT_BOW, ARROW = 49, 52`
        m_assign = re.match(r"^\s*([A-Z][A-Z0-9_,\s]*?)\s*=\s*([0-9A-Fa-fx,\s]+)$", code.strip())
        if m_assign:
            lhs_names = [x.strip() for x in m_assign.group(1).split(",") if x.strip()]
            rhs_vals = [x.strip() for x in m_assign.group(2).split(",") if x.strip()]
            if len(lhs_names) == len(rhs_vals):
                for cname, cval in zip(lhs_names, rhs_vals):
                    if (
                        re.fullmatch(r"0x[0-9A-Fa-f]+|\d+", cval)
                        and _is_py_item_const_name(cname, py_comment)
                        and _py_is_raw_id(cval)
                    ):
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "py-raw-item-const",
                                f"{cname} = {cval} uses raw numeric item ID",
                            )
                        )

        # Field-0 (`inv_item_id`) reader comparisons: `_inv_field(tb, slot, 0)` / `inv_get(slot, 0)`
        for m_f0 in PY_FIELD0_CALL_RE.finditer(code):
            tail = code[m_f0.end() :]
            m_eq = re.match(r"\s*(?:==|!=)\s*(0x[0-9A-Fa-f]+|\d+)\b", tail)
            if m_eq and _py_is_raw_id(m_eq.group(1)):
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "py-raw-item-cmp",
                        f"field-0 item reader compared against raw item ID {m_eq.group(1)}",
                    )
                )
            m_in = re.match(r"\s*(?:not\s+)?in\s*[\(\[\{]([^)\]\}]+)[\)\]\}]", tail)
            if m_in:
                for tok in _split_csv_top_level(m_in.group(1)):
                    if re.fullmatch(r"0x[0-9A-Fa-f]+|\d+", tok) and _py_is_raw_id(tok):
                        findings.append(
                            Finding(
                                rel_path,
                                line_no,
                                "py-raw-item-cmp",
                                f"field-0 item reader tested against raw item ID {tok}",
                            )
                        )

        for m in cmp_item_re.finditer(code):
            snippet = m.group(0)
            lit = m.group(2)
            lhs = snippet.rsplit(lit, 1)[0]
            if re.search(r"(?:==|!=|>=|<=|<|>)\s*$", lhs) and _py_is_raw_id(lit):
                if "-" in lhs and "inv_qty" in lhs:
                    continue
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "py-raw-item-cmp",
                        f"raw item ID {lit} compared in '{snippet.strip()}'",
                    )
                )

    return findings


SH_EXPECT_ITEM_SYM_RE = re.compile(
    r"--expect-byte-symbol\s+[\"\']?\.?"
    r"(fi_item_id|inv_item_id|si_item_id|fi_add_id|exchange_product_refused_primary|[A-Za-z0-9_]+_id)"
    r"=(0x[0-9A-Fa-f]+|\d+)\b"
)
SH_NON_ITEM_ID_SYMS = {
    "species_id",
    "monster_id",
    "ego_id",
    "overlay_id",
}


def scan_sh_text(text: str, rel_path: str) -> list[Finding]:
    """Scan shell test runners for monitor pokes and --expect-byte-symbol raw item IDs."""
    findings: list[Finding] = []
    for line_no, raw_line in enumerate(text.splitlines(), 1):
        if "raw-id-ok:" in raw_line:
            continue
        code = raw_line.split("#", 1)[0]

        if any(k in code for k in ("inv_item_id", "fi_item_id", "si_item_id", "fi_add_id")):
            m = re.search(
                r">\s*\$?\{?[A-Za-z0-9_+.\s]*?(?:inv_item_id|fi_item_id|si_item_id|fi_add_id)[A-Za-z0-9_+.\s]*\}?\s+([0-9a-fA-F]{1,2})\b",
                code,
            )
            if m and m.group(1).lower() != "ff":
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "sh-raw-item-poke",
                        f"monitor poke writes raw hex item ID {m.group(1)} to item_id array",
                    )
                )

        for m_exp in SH_EXPECT_ITEM_SYM_RE.finditer(code):
            sym_name, lit = m_exp.group(1), m_exp.group(2)
            if sym_name in SH_NON_ITEM_ID_SYMS:
                continue
            if _py_is_raw_id(lit):
                findings.append(
                    Finding(
                        rel_path,
                        line_no,
                        "sh-raw-item-expect",
                        f"--expect-byte-symbol .{sym_name}={lit} hardcodes raw numeric item ID",
                    )
                )

    return findings


def iter_target_files(root: Path, paths: list[Path]) -> list[Path]:
    """Collect candidate .s, .py, and .sh files under requested paths (or repo defaults)."""
    candidates: list[Path] = []
    if paths:
        for p in paths:
            resolved = p if p.is_absolute() else (root / p)
            if resolved.is_file():
                candidates.append(resolved)
            elif resolved.is_dir():
                for sub in sorted(resolved.rglob("*")):
                    if sub.is_file() and sub.suffix in (".s", ".py", ".sh"):
                        candidates.append(sub)
    else:
        for d in ("core", "platforms", "playtest"):
            base = root / d
            if base.is_dir():
                for sub in sorted(base.rglob("*")):
                    if sub.is_file() and sub.suffix in (".s", ".py", ".sh"):
                        candidates.append(sub)
        wiz_doc = root / "tools" / "check_wizard_doc.py"
        if wiz_doc.is_file():
            candidates.append(wiz_doc)

    filtered: list[Path] = []
    seen: set[Path] = set()
    for p in candidates:
        p = p.resolve()
        if p in seen:
            continue
        seen.add(p)
        try:
            rel = p.relative_to(root.resolve()).as_posix()
        except ValueError:
            rel = p.as_posix()
        if rel.startswith("build/") or "/build/" in rel or "/__pycache__/" in rel:
            continue
        if rel in EXCLUDED_S_REL or any(rel.endswith("/" + ex) for ex in EXCLUDED_S_REL):
            continue
        if rel.startswith("platforms/shared/catalog/") or "/platforms/shared/catalog/" in rel or "/creature_data/" in rel:
            continue
        if rel == "playtest/queue.json" or rel.endswith("/playtest/queue.json"):
            continue
        filtered.append(p)
    return filtered


def scan_paths(root: Path, paths: list[Path]) -> list[Finding]:
    all_findings: list[Finding] = []
    root_res = root.resolve()
    for p in iter_target_files(root, paths):
        try:
            rel = p.resolve().relative_to(root_res).as_posix()
        except ValueError:
            rel = p.as_posix()
        txt = p.read_text(errors="replace")
        if p.suffix == ".s":
            all_findings.extend(scan_asm_text(txt, rel))
        elif p.suffix == ".py":
            all_findings.extend(scan_py_text(txt, rel))
        elif p.suffix == ".sh":
            all_findings.extend(scan_sh_text(txt, rel))
    return all_findings


def run_selftest() -> None:
    """Unit self-tests verifying true-positive detection and zero false positives."""
    # 1. True positives in assembly (including #549 blind-spot regressions)
    tp_asm = """
    .const ITEM_FLASK_OIL = 61
    sro_general_choice:
        .byte 15, 61, 271 - ITEM_PAGE_SIZE
    xps_primary: .byte 5, 1, 0, 1, 0, 0, IF_IDENTIFIED, 0
    test_fn:
        lda #15
        sta fi_add_id
        ldx #34
        stx inv_item_id + 0
        lda inv_item_id,x
        cmp #47
        beq !hit+
        bit item_cur_page
        bvs !p1+
        cpx #25
        beq !hit+
        lda #96
        jsr item_cat_select_id
    !p1:
    !hit:
        rts
    put_tool_ego_prefix:
        cpx #62
        rts
    ipc_fn:
        lda ipc_warm_id
        cmp #2
        rts
    roll_enchantment:
        sta zp_temp0
        lda item_cur_page
        sta re_page
        rts
    !re_later:
        bit re_page
        bvs !re_p1+
        lda zp_temp0
        cmp #23
        rts
    !re_p1:
        rts
    calc_dig_fn:
        ldx inv_item_id + EQUIP_WEAPON
        stx zp_temp0
        rts
    !dig_branch:
        lda item_cur_page
        bne !dig_done+
        ldx zp_temp0
        cpx #157
    !dig_done:
        rts
    irs_dispatch_p3_overlay:
        bit piw_ego
        bvs !irs_done+
        cmp #42
    !irs_done:
        rts
    """
    tp_res = scan_asm_text(tp_asm, "synthetic_bad.s")
    rules_hit = {f.rule for f in tp_res}
    assert "raw-item-const" in rules_hit, f"Missed raw-item-const: {tp_res}"
    assert "raw-item-table" in rules_hit, f"Missed raw-item-table: {tp_res}"
    assert "raw-item-store" in rules_hit, f"Missed raw-item-store: {tp_res}"
    assert "raw-item-cmp" in rules_hit, f"Missed raw-item-cmp: {tp_res}"
    assert "raw-item-call" in rules_hit, f"Missed raw-item-call: {tp_res}"
    assert len(tp_res) == 15, f"Expected 15 findings on synthetic_bad.s, got {len(tp_res)}: {tp_res}"

    # 2. Zero false positives on clean symbolic assembly
    tn_asm = """
    .const ITEM_TYPE_COUNT = 361
    .const ITEM_PAGE_SIZE = 255
    .const ITEM_PAGE_BIT = $40
    .const ITEM_PICKUP_CACHE_MIN_SIZE = 464
    .const ITEM_TYPE_FLASK_OF_OIL = ITEM_FLASK_OF_OIL
    piw_item_id: .byte 0
    sro_general_choice:
        .byte ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_FLASK_OF_OIL
        .byte ITEM_SLOT_CLEAR_POTION_OF_WATER
    xps_primary: .byte ITEM_SLOT_MACE, 1, 0, 1, 0, 0, IF_IDENTIFIED, ITEM_PAGE_MACE
    clean_fn:
        lda #ITEM_SLOT_RATION_OF_FOOD
        sta fi_add_id
        lda #FI_EMPTY
        sta inv_item_id,x
        lda #$ff
        sta fi_item_id,x
        ldx #0
        cpx #MAX_INV_SLOTS
        bcc !ok+
        lda inv_qty,x
        cmp #0
        beq !ok+
        bit item_cur_page
        bvs !ok+
        lda zp_player_hp_lo
        cmp #10
        bcc !ok+
        lda inv_item_id,x
        cmp #FI_EMPTY
        beq !ok+
        cmp #ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
        beq !ok+
        sec
        sbc #ITEM_SLOT_SPELLBOOK_MAGICK_I
        cmp #3
        bcc !ok+
        lda #999 // raw-id-ok: synthetic out-of-bounds test
        sta fi_add_id // raw-id-ok: synthetic out-of-bounds test
    !ok:
        ldx #0
    !scan_loop:
        txa
        jsr item_get_category_a
        inx
        cpx #ITEM_PAGE_SIZE
        bcc !scan_loop-
        rts
    """
    tn_res = scan_asm_text(tn_asm, "synthetic_clean.s")
    assert tn_res == [], f"Unexpected false positives on clean assembly: {tn_res}"

    # 3. True positives & zero false positives in Python
    tp_py = """
PRIEST_BOOK_ITEM_ID = 48
MAGICK_I = 55  # docs/WIZARD.md: Spellbook Magick I
SHORT_BOW, ARROW, EGO_ARROW_SLAY_EVIL = 49, 52, 44  # item_catalog_spec.json
inv_id = tb.syms["inv_item_id"]
tb.write_u8(inv_id + 1, 59)
connector.poke(inv_item_id + 0, 34)
self.poke(self.sym("inv_item_id") + 0, bytes([49]))
write_byte(sym["inv_item_id"], 33)
item_ids[0] = 15
inv_seed(21, {114, 1, 5, 0, 0, 0, 2, 64})
_inv_seed(tb, book_slot, [56, 1, 0, 0, 0, 0, 2, 0])
self.seed_slot(0, (49, 1, 0, 20, 20, 0, 2, 0))
cloak_rec = [82, 1, 0, 0, 0, 2, 2, 0]
_inv_seed(tb, 32, cloak_rec)
if _inv_field(tb, i, 0) in (47, 55):
    pass
if _inv_field(tb, 22, 0) == 5:
    pass
if fi_item_id >= 2:
    pass
"""
    tp_py_res = scan_py_text(tp_py, "synthetic_bad.py")
    assert len(tp_py_res) == 17, f"Expected 17 Python findings, got {len(tp_py_res)}: {tp_py_res}"

    tn_py = """
SEED = 1004
EQUIP_WEAPON = 22
EGO_ARROW_SLAY_EVIL = 44
PRIEST_BOOK_ITEM_ID = ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
MAGICK_I = ITEM_SLOT_SPELLBOOK_MAGICK_I  # docs/WIZARD.md
inv_id = tb.syms["inv_item_id"]
tb.write_u8(inv_id + 1, ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS)
connector.poke(inv_item_id + 0, ITEM_SLOT_SCROLL_OF_IDENTIFY)
connector.poke(inv_item_id + 1, FI_EMPTY)
connector.poke(fi_item_id + 2, 0xFF)
item_ids[31] = 0xFF
inv_seed(21, {ITEM_SLOT_STAFF_OF_DARKNESS_L50, 1, 5, 0, 0, 0, 2, ITEM_PAGE_STAFF_OF_DARKNESS_L50})
_inv_seed(tb, 32, [0xFF, 0, 0, 0, 0, 0, 0, 0])
cloak_rec = [ITEM_SLOT_CLOAK, 1, 0, 0, 0, 2, 2, ITEM_PAGE_CLOAK]
_inv_seed(tb, 32, cloak_rec)
if _inv_field(tb, i, 0) != 0xFF and _inv_field(tb, i, 0) in (ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK,):
    pass
if read_bytes(connector, fi_item_id + slot, 1)[0] != EMPTY_SLOT:
    pass
state = memory(sym["inv_item_id"], 33)
assert tb.syms["inv_qty"] - tb.syms["inv_item_id"] == TOTAL_INV_SLOTS
"""
    tn_py_res = scan_py_text(tn_py, "synthetic_clean.py")
    assert tn_py_res == [], f"Unexpected false positives on clean Python: {tn_py_res}"

    # 4. True positives & zero false positives in shell runners
    tp_sh = """
    --expect-byte-symbol ".fi_item_id=0x81" \\
    --expect-byte-symbol ".exchange_product_refused_primary=0x05" \\
    --expect-byte-symbol ".save_product_secondary_id=0x02" \\
    --expect-byte-symbol ".save_product_ring2_id=0xff" \\
    > ${inv_item_id} 22
    """
    tp_sh_res = scan_sh_text(tp_sh, "synthetic_bad.sh")
    assert len(tp_sh_res) == 4, f"Expected 4 shell findings, got {len(tp_sh_res)}: {tp_sh_res}"

    tn_sh = """
    --expect-byte-symbol ".fi_item_id=${CHEST_LOOT_HEX}" \\
    --expect-byte-symbol ".exchange_product_refused_primary=${MACE_HEX}" \\
    --expect-byte-symbol ".save_product_ring2_id=0xff" \\
    --expect-byte-symbol ".zp_turn_lo=0x01" \\
    > ${inv_item_id} ${SCROLL_HEX}
    > ${inv_item_id} ff
    """
    tn_sh_res = scan_sh_text(tn_sh, "synthetic_clean.sh")
    assert tn_sh_res == [], f"Unexpected false positives on clean shell: {tn_sh_res}"

    print("check_raw_item_ids selftest PASSED (ASM + Python + Shell true-positive & zero-false-positive checks OK).")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check repository for raw numeric item IDs.")
    parser.add_argument("paths", nargs="*", type=Path, help="Optional files/directories to scan")
    parser.add_argument("--selftest", action="store_true", help="Run built-in unit self-tests")
    args = parser.parse_args(argv)

    if args.selftest:
        run_selftest()
        return 0

    findings = scan_paths(ROOT, args.paths)
    if findings:
        for f in findings:
            print(f.format())
        print(f"FAILED: {len(findings)} raw numeric item ID violation(s) found.", file=sys.stderr)
        return 1

    scope = ", ".join(str(p) for p in args.paths) if args.paths else "core, platforms, playtest, tools"
    print(f"check_raw_item_ids PASSED: 0 raw numeric item IDs across {scope}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
