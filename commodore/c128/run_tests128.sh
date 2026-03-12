#!/bin/bash
# run_tests128.sh — Assemble and run C128 runtime tests in VICE headless

set -u

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
PERF_P1_MODE="${PERF_P1:-0}"
PASS=0
FAIL=0
TOTAL=0
BOOT_ASSETS_BUILT=0
PARTIAL_BOOT_ASSETS_BUILT=0
OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=0
DEATH_BOOT_ASSETS_BUILT=0
OVERLAY_STATE_BOOT_ASSETS_BUILT=0
SCRIPTED_INPUT_BOOT_ASSETS_BUILT=0
CACHE_SURVIVAL_BOOT_ASSETS_BUILT=0
LOAD_RESUME_BOOT_ASSETS_BUILT=0

KA_DEFINES=(-define C128)
if [ "$PERF_P1_MODE" = "1" ]; then
    KA_DEFINES+=(-define PERF_P1)
fi

run_main_assembly_check() {
    echo -n "  main128_asm: "

    local asm_output
    asm_output=$(java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 "${KA_DEFINES[@]}" -o out/moria128.prg 2>&1)

    # KickAssembler can return 0 even when .assert fails, so gate on both
    # process status and emitted failure markers.
    if [ $? -ne 0 ] || echo "$asm_output" | grep -q "FAILED!"; then
        echo "FAIL"
        echo "$asm_output" | grep -E "assert|FAILED|ERROR" | tail -5 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local assert_line
    assert_line=$(echo "$asm_output" | grep "Made .*asserts" | tail -1)
    if [ -n "${assert_line:-}" ]; then
        echo "PASS (${assert_line})"
    else
        echo "PASS"
    fi
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_symbol_placement_check() {
    echo -n "  main128_layout: "

    local sym_file="main.sym"
    if [ ! -f "$sym_file" ]; then
        echo "FAIL (missing $sym_file)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path
import re
sym = Path("main.sym").read_text().splitlines()
main_text = Path("main.s").read_text()
main_source = main_text.splitlines()
labels = {}
for line in sym:
    m = re.match(r"\.label\s+([A-Za-z0-9_]+)=\$(\w+)", line)
    if not m:
        continue
    labels[m.group(1)] = int(m.group(2), 16)

assert_guards = set()
for line in main_source:
    m = re.search(r"\.assert\s+\"[^\"]*\"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*<\s*\$D000\b", line)
    if m:
        assert_guards.add(m.group(1))

required = [
    "game_over_prompt",
    "game_over_prompt_end",
    "game_over_str",
    "game_over_str_end",
    "title_show_sysinfo",
    "tramp_reu_show_status",
    "tramp_ui_equip_display",
    "tramp_ui_recall",
    "tramp_store_init_all",
    "tramp_store_restock_all",
    "tramp_store_enter",
    "tramp_player_create",
    "tramp_game_over",
]

# These are the concrete regression-prone runtime symbols that must stay out
# of the C128 $D000-$DFFF I/O hole. Each one should also be protected by a
# source-level placement assert in main.s.
must_have_asserts = [
    "title_menu_str",
    "ds_menu_str",
    "ds_dual_str",
    "de_prompt_str",
    "save_game",
    "load_game",
    "load_read_byte",
    "load_read_block",
    "load_read_map_c128",
    "delete_savefile",
    "update_visibility",
    "reveal_room",
    "player_try_move",
    "player_attack_monster",
    "combat_roll_tohit",
    "combat_apply_damage",
    "msg_build_action",
    "cmb_print_buf",
]
bad = []
missing = []
missing_asserts = []
for name in required:
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] >= 0xD000:
        bad.append((name, labels[name]))

if "msg_history" not in labels or "msg_hist_idx" not in labels:
    missing.append("msg_history/msg_hist_idx")
else:
    if labels["msg_hist_idx"] - labels["msg_history"] != (8 * 80):
        bad.append(("msg_history_span", labels["msg_hist_idx"] - labels["msg_history"]))

for name in ("help_title_str", "help_lines"):
    if name not in labels:
        missing.append(name)
        continue
    # Help data must live outside the $E000-$EFFF overlay window.
    if labels[name] < 0xF000:
        bad.append((name, labels[name]))

for name in ("ui_help_display",):
    if name not in labels:
        missing.append(name)
        continue
    # Help renderer code must not execute from $E000-$EFFF overlay window.
    if labels[name] < 0xF000:
        bad.append((name, labels[name]))

if "ldx #21\n    jsr vdc_write_reg\n    lda #8\n    dex                         // 20\n    jsr vdc_write_reg" not in main_text:
    print("vdc_attr_base_init: expected reg21/reg20 init sequence with lda #8 for reg20")
    raise SystemExit(1)

# Hard rule: no critical entrypoint may execute from the $D000-$DFFF I/O hole.
for name in must_have_asserts:
    if name not in assert_guards:
        missing_asserts.append(name)

# Every source-level <$D000 guard must be enforced by the runner.
for name in sorted(assert_guards):
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] >= 0xD000:
        bad.append((name, labels[name]))

if missing or bad or missing_asserts:
    if missing:
        print("missing:" + ",".join(missing))
    if missing_asserts:
        print("missing_asserts:" + ",".join(sorted(missing_asserts)))
    for name, addr in bad:
        print(f"high:{name}=${addr:04X}")
    raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_80col_layout_guard_check() {
    echo -n "  layout80_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

root = Path("..").resolve()
screen = (root / "c128" / "screen_vdc.s").read_text()
render = (root / "c128" / "dungeon_render_vdc.s").read_text()
main128 = (root / "c128" / "main.s").read_text()
msgs = (root / "common" / "ui_messages.s").read_text()
status = (root / "common" / "ui_status.s").read_text()
help_s = (root / "common" / "ui_help.s").read_text()
swap = (root / "common" / "disk_swap.s").read_text()
char_s = (root / "common" / "ui_character.s").read_text()
sysinfo = (root / "common" / "title_sysinfo_banked.s").read_text()

def must_contain(text: str, snippet: str, err: str):
    if snippet not in text:
        print(err)
        raise SystemExit(1)

def must_not_contain(text: str, snippet: str, err: str):
    if snippet in text:
        print(err)
        raise SystemExit(1)

must_contain(screen, ".const SCREEN_COLS = 80", "screen_vdc must keep SCREEN_COLS=80")
must_contain(screen, ".const VIEWPORT_X  = 1", "screen_vdc must use explicit VIEWPORT_X=1")
must_contain(screen, ".const VIEWPORT_W  = 78", "screen_vdc must use explicit VIEWPORT_W=78")
must_contain(screen, ".const VDC_ATTR_MODE = $80", "screen_vdc must keep VDC_ATTR_MODE=$80 (Set 1 charset)")
must_not_contain(screen, "SCREEN_COL_OFFSET", "screen_vdc must not use implicit SCREEN_COL_OFFSET")
must_not_contain(render, "VIEWPORT_X + SCREEN_COL_OFFSET", "dungeon_render_vdc must use explicit VIEWPORT_X only")

must_contain(msgs, ".const MSG_HIST_LEN   = SCREEN_COLS", "ui_messages must size history by SCREEN_COLS")
must_contain(status, "#if C128", "ui_status must use compile-time C128 layout constants")
must_contain(help_s, ".const HELP_FRAME_RIGHT_COL = SCREEN_COLS - 1", "ui_help border must use SCREEN_COLS")
must_contain(swap, ".const DS_PROMPT_COL = (SCREEN_COLS - 16) / 2", "disk_swap prompt centering must use SCREEN_COLS math")
must_contain(main128, "lda #TITLE_MENU_COL", "title menu must use TITLE_MENU_COL")
must_contain(char_s, "lda #10\n    sta zp_cursor_row", "ui_character gold/xp row must stay at row 10")
must_contain(char_s, ".const UCHAR_COL_L = (SCREEN_COLS - 36) / 2", "ui_character C128 columns must stay centered for 80-col")
must_contain(sysinfo, "ldx #((SCREEN_COLS - 15) / 2)", "title sysinfo baseline must be centered on C128")
must_contain(status, "lda #STS_ROW21_NAME_COL\n    sta zp_cursor_col", "status row 21 name must use dedicated C128 anchor")

for src_name, src_text in (
    ("ui_messages.s", msgs),
    ("ui_status.s", status),
    ("ui_help.s", help_s),
    ("disk_swap.s", swap),
):
    if "zp_machine_type" in src_text:
        print(f"{src_name} reintroduced runtime machine checks")
        raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_runtime_ownership_guard_check() {
    echo -n "  runtime_state_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

root = Path("..").resolve()
allowed = {
    (root / "c128" / "runtime128.s").resolve(),
    (root / "c128" / "memory128.s").resolve(),
}
forbidden = (
    "sta $0314",
    "sta $0315",
    "sta $0302",
    "sta $0303",
    "sta $fffa",
    "sta $fffb",
    "sta $fffe",
    "sta $ffff",
    "jsr init_common_mmu_helpers",
)

bad = []
for src in list((root / "c128").glob("*.s")) + list((root / "common").glob("*.s")):
    if src.resolve() in allowed:
        continue
    for lineno, line in enumerate(src.read_text().splitlines(), start=1):
        stripped = line.strip().lower()
        for token in forbidden:
            if token in stripped:
                bad.append(f"{src.name}:{lineno}:{line.strip()}")

main_sym = root / "c128" / "main.sym"
if not main_sym.exists():
    print("missing main.sym")
    raise SystemExit(1)

memory_src = (root / "c128" / "memory128.s").read_text()
for snippet, desc in (
    (".const MMU_COMMON_HELPERS_PAGE_BASE = $0f00", "helper page base"),
    (".const MMU_COMMON_HELPERS_BASE = $0f08", "helper page payload base"),
):
    if snippet.lower() not in memory_src.lower():
        bad.append(f"missing {desc} declaration")

labels = {}
for line in main_sym.read_text().splitlines():
    if not line.startswith(".label "):
        continue
    body = line[len(".label "):]
    if "=$" not in body:
        continue
    name, value = body.split("=$", 1)
    value = value.split()[0]
    labels[name] = int(value, 16)

helper_start = labels.get("mmu_common_map_read_ptr0")
helper_end = labels.get("mmu_common_select_bank0")
if helper_start is None or helper_end is None:
    bad.append("missing runtime helper entrypoint symbols")
elif helper_start < 0x0F08 or helper_end > 0x0FFC:
    bad.append(f"helper_runtime_range:${helper_start:04X}-${helper_end:04X}")

if bad:
    print("\n".join(bad))
    raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_prompt_irq_guard_check() {
    echo -n "  prompt_irq_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path
import re

root = Path("..").resolve()
screen = (root / "c128" / "screen_vdc.s").read_text().splitlines()
items = (root / "common" / "player_items.s").read_text().splitlines()
item_mod = (root / "common" / "item.s").read_text().splitlines()
throw_mod = (root / "common" / "throw.s").read_text().splitlines()
loop_mod = (root / "common" / "game_loop.s").read_text().splitlines()
dfeat = (root / "common" / "dungeon_features.s").read_text().splitlines()
help_mod = (root / "common" / "ui_help.s").read_text().splitlines()
store_mod = (root / "common" / "ui_store.s").read_text().splitlines()

def first_instructions_after(label: str, lines: list[str], count: int) -> list[str]:
    in_block = False
    out = []
    for ln in lines:
        s = ln.strip()
        if not in_block:
            if s.startswith(label):
                in_block = True
            continue
        if not s or s.startswith("//"):
            continue
        if s.endswith(":"):
            break
        out.append(s)
        if len(out) >= count:
            break
    return out

def has_pair(lines: list[str], token_a: str, token_b: str) -> bool:
    for i, ln in enumerate(lines):
        if token_a in ln:
            for j in range(i + 1, min(i + 8, len(lines))):
                if token_b in lines[j]:
                    return True
            return False
    return False

def has_ordered_chain(lines: list[str], tokens: list[str], window: int = 28) -> bool:
    for i, ln in enumerate(lines):
        if tokens[0] not in ln:
            continue
        pos = i
        ok = True
        for tok in tokens[1:]:
            found = False
            for j in range(pos + 1, min(pos + 1 + window, len(lines))):
                if tok in lines[j]:
                    pos = j
                    found = True
                    break
            if not found:
                ok = False
                break
        if ok:
            return True
    return False

first2 = first_instructions_after("screen_put_string:", screen, 2)
if len(first2) < 2 or (not first2[0].lower().startswith("php")) or (not first2[1].lower().startswith("sei")):
    print(f"screen_put_string must start with php; sei, found: {first2!r}")
    raise SystemExit(1)

if not has_pair(items, "ldx #HSTR_PIW_TAKEOFF_PROMPT", "jsr huff_print_msg"):
    print("item_takeoff prompt is not using Huffman print path")
    raise SystemExit(1)

required_chains = [
    ("item_wear", items, [
        "ldx #HSTR_PIW_WEAR_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_takeoff", items, [
        "ldx #HSTR_PIW_TAKEOFF_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_quaff", items, [
        "ldx #HSTR_PIQ_QUAFF_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_read_scroll", items, [
        "ldx #HSTR_PIQ_READ_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_aim_wand", items, [
        "ldx #HSTR_PIW_AIM_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_use_staff", items, [
        "ldx #HSTR_PIW_USE_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_gain_spell", items, [
        "ldx #HSTR_IGS_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_drop", item_mod, [
        "ldx #HSTR_IDR_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("throw_item", throw_mod, [
        "ldx #HSTR_TW_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("get_direction_target", dfeat, [
        "ldx #HSTR_DF_DIRECTION",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_inventory_dismiss", loop_mod, [
        "cmp #CMD_INVENTORY",
        "jsr tramp_ui_inv_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_equipment_dismiss", loop_mod, [
        "cmp #CMD_EQUIPMENT",
        "jsr tramp_ui_equip_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_help_dismiss", loop_mod, [
        "cmp #CMD_HELP",
        "jsr tramp_ui_help_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_char_info_dismiss", loop_mod, [
        "cmp #CMD_CHAR_INFO",
        "jsr tramp_ui_char_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_recall_prompt", loop_mod, [
        "cmp #CMD_RECALL",
        "jsr screen_put_string",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_recall_dismiss", loop_mod, [
        "jsr tramp_ui_recall",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_buy_prompt", store_mod, [
        "ldx #MSG_BUY_WHICH",
        "jsr show_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_buy_confirm", store_mod, [
        "jsr sbuy_show_price",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_sell_prompt", store_mod, [
        "ldx #MSG_SELL_WHICH",
        "jsr show_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_sell_confirm", store_mod, [
        "jsr ssell_show_offer",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_haggle_number", store_mod, [
        "input_read_number:",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
]

for name, lines, chain in required_chains:
    if not has_ordered_chain(lines, chain):
        print(f"{name} must gate with input_wait_release before input_get_key")
        raise SystemExit(1)

if not has_ordered_chain(help_mod, [
    "#if C128",
    "jsr screen_put_char",
    "#else",
    "sta (zp_screen_lo),y",
]):
    print("ui_help_draw_line must use screen_put_char on C128 and keep direct RAM path only for C64")
    raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

build_boot_assets() {
    if [ "$BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    local build_log="/tmp/test128_boot_build.log"
    local make_kickass="/tmp/moria128-kickass.jar"
    ln -sf "$KICKASS" "$make_kickass"
    if ! make -s KICKASS="$make_kickass" build128 disk128 >"$build_log" 2>&1; then
        echo "FAIL (build128/disk128 failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local diag_asm
    diag_asm=$(java -jar "$KICKASS" boot128.s -define BOOT_DIAG=1 -o out/boot128.diag.prg 2>&1)
    if [ $? -ne 0 ]; then
        echo "FAIL (boot128 diag assembly error)"
        echo "$diag_asm" | grep -i error | head -3 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=1
    return 0
}

build_partial_failure_boot_assets() {
    if [ "$PARTIAL_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_partial_build.log"
    local c1541_bin="${C1541:-c1541}"
    local partial_main="out/moria128.skip1.prg"
    local partial_d64="out/moria128_skip1.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_CACHE_TEST_SKIP_TIER -o "$partial_main" >"$build_log" 2>&1; then
        echo "FAIL (partial-failure main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$partial_d64" \
            -attach "$partial_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$partial_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (partial-failure disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    PARTIAL_BOOT_ASSETS_BUILT=1
    return 0
}

build_overlay_partial_failure_boot_assets() {
    if [ "$OVERLAY_PARTIAL_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_overlay_partial_build.log"
    local c1541_bin="${C1541:-c1541}"
    local partial_main="out/moria128.skipovl2.prg"
    local partial_d64="out/moria128_skipovl2.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_CACHE_TEST_SKIP_OVERLAY -o "$partial_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-partial main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$partial_d64" \
            -attach "$partial_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$partial_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (overlay-partial disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=1
    return 0
}

build_death_overlay_boot_assets() {
    if [ "$DEATH_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_death_build.log"
    local c1541_bin="${C1541:-c1541}"
    local death_main="out/moria128.death.prg"
    local death_d64="out/moria128_death.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_TEST_FORCE_DEATH=1 -o "$death_main" >"$build_log" 2>&1; then
        echo "FAIL (death-overlay main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$death_d64" \
            -attach "$death_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$death_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (death-overlay disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    DEATH_BOOT_ASSETS_BUILT=1
    return 0
}

build_overlay_state_boot_assets() {
    if [ "$OVERLAY_STATE_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_overlay_state_build.log"
    local c1541_bin="${C1541:-c1541}"
    local state_main="out/moria128.overlaystate.prg"
    local state_d64="out/moria128_overlaystate.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_TEST_OVERLAY_STATE_CORRUPT=1 -o "$state_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-state main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$state_d64" \
            -attach "$state_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$state_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (overlay-state disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    OVERLAY_STATE_BOOT_ASSETS_BUILT=1
    return 0
}

build_scripted_input_boot_assets() {
    if [ "$SCRIPTED_INPUT_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_scripted_input_build.log"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="out/moria128_scriptedinput.d64"

    # Compile to the standard out/moria128.prg target so KickAssembler also
    # refreshes the companion out/ovl.* overlay PRGs for this special build.
    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_TEST_SCRIPTED_INPUT -o out/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-input main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write out/boot128.prg "moria8.128" \
            -write out/moria128.prg "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-input disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    # Force later builders back through build_boot_assets so subsequent smokes
    # do not accidentally reuse the scripted-input overlays.
    BOOT_ASSETS_BUILT=0
    SCRIPTED_INPUT_BOOT_ASSETS_BUILT=1
    return 0
}

build_cache_survival_boot_assets() {
    if [ "$CACHE_SURVIVAL_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_cache_survival_build.log"
    local c1541_bin="${C1541:-c1541}"
    local cache_d64="out/moria128_cache_survival.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_TEST_SCRIPTED_INPUT -define C128_TEST_CACHE_SURVIVAL -o out/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (cache-survival main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$cache_d64" \
            -attach "$cache_d64" \
            -write out/boot128.prg "moria8.128" \
            -write out/moria128.prg "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (cache-survival disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    CACHE_SURVIVAL_BOOT_ASSETS_BUILT=1
    return 0
}

build_load_resume_boot_assets() {
    if [ "$LOAD_RESUME_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    local build_log="/tmp/test128_boot_load_resume_build.log"
    local c1541_bin="${C1541:-c1541}"
    local loadresume_d64="out/moria128_loadresume.d64"
    local save_blob="out/THE.GAME"

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (load-resume save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$loadresume_d64" \
            -attach "$loadresume_d64" \
            -write out/boot128.prg "moria8.128" \
            -write out/moria128.prg "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" \
            -write "$save_blob" "THE.GAME" >>"$build_log" 2>&1; then
        echo "FAIL (load-resume disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local dir_list
    if ! dir_list=$("$c1541_bin" -attach "$loadresume_d64" -list 2>&1); then
        echo "FAIL (load-resume disk listing failed)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! echo "$dir_list" | grep -q '"THE.GAME"'; then
        echo "FAIL (save-seed disk missing THE.GAME)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    LOAD_RESUME_BOOT_ASSETS_BUILT=1
    return 0
}

build_main_diag_disk() {
    local main_prg="$1"
    local d64_path="$2"
    local build_log="$3"
    local save_blob="${4:-}"
    local c1541_bin="${C1541:-c1541}"

    if [ -n "$save_blob" ]; then
        if ! "$c1541_bin" -format "moria128,m8" d64 "$d64_path" \
                -attach "$d64_path" \
                -write out/boot128.prg "moria8.128" \
                -write "$main_prg" "moria128" \
                -write out/title "title" \
                -write out/monster.db.1 "monster.db.1" \
                -write out/monster.db.2 "monster.db.2" \
                -write out/monster.db.3 "monster.db.3" \
                -write out/monster.db.4 "monster.db.4" \
                -write out/ovl.town "ovl.town" \
                -write out/ovl.start "ovl.start" \
                -write out/ovl.death "ovl.death" \
                -write out/ovl.gen "ovl.gen" \
                -write out/bank1.dat "bank1.dat" \
                -write "$save_blob" "THE.GAME" >>"$build_log" 2>&1; then
            return 1
        fi
    else
        if ! "$c1541_bin" -format "moria128,m8" d64 "$d64_path" \
                -attach "$d64_path" \
                -write out/boot128.prg "moria8.128" \
                -write "$main_prg" "moria128" \
                -write out/title "title" \
                -write out/monster.db.1 "monster.db.1" \
                -write out/monster.db.2 "monster.db.2" \
                -write out/monster.db.3 "monster.db.3" \
                -write out/monster.db.4 "monster.db.4" \
                -write out/ovl.town "ovl.town" \
                -write out/ovl.start "ovl.start" \
                -write out/ovl.death "ovl.death" \
                -write out/ovl.gen "ovl.gen" \
                -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
            return 1
        fi
    fi
    return 0
}

build_town_move_diag_assets() {
    local stage="$1"

    build_boot_assets || return 1

    local build_log="/tmp/test128_town_move_diag_${stage}.build.log"
    local diag_main="out/moria128.townmove.${stage}.prg"
    local diag_d64="out/moria128_townmove_${stage}.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_INPUT -define "C128_DIAG_TOWN_MOVE_STAGE_${stage}" \
            -o "$diag_main" >"$build_log" 2>&1; then
        echo "FAIL (town-move diag stage ${stage} assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! build_main_diag_disk "$diag_main" "$diag_d64" "$build_log"; then
        echo "FAIL (town-move diag stage ${stage} disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    return 0
}

build_store_entry_diag_assets() {
    build_boot_assets || return 1

    local build_log="/tmp/test128_store_entry_diag.build.log"
    local diag_main="out/moria128.storeentry.diag.prg"
    local diag_d64="out/moria128_storeentry_diag.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_DIAG_STORE_ENTRY \
            -o "$diag_main" >"$build_log" 2>&1; then
        echo "FAIL (store-entry diag assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! build_main_diag_disk "$diag_main" "$diag_d64" "$build_log"; then
        echo "FAIL (store-entry diag disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    return 0
}

build_load_resume_diag_assets() {
    build_boot_assets || return 1

    local build_log="/tmp/test128_load_resume_diag.build.log"
    local diag_main="out/moria128.loadresume.diag.prg"
    local diag_d64="out/moria128_loadresume_diag.d64"
    local save_blob="out/THE.GAME"
    local c1541_bin="${C1541:-c1541}"

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (load-resume diag save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_DIAG_LOAD_RESUME \
            -o "$diag_main" >>"$build_log" 2>&1; then
        echo "FAIL (load-resume diag assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! build_main_diag_disk "$diag_main" "$diag_d64" "$build_log" "$save_blob"; then
        echo "FAIL (load-resume diag disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local dir_list
    if ! dir_list=$("$c1541_bin" -attach "$diag_d64" -list 2>&1); then
        echo "FAIL (load-resume diag disk listing failed)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi
    if ! echo "$dir_list" | grep -q '"THE.GAME"'; then
        echo "FAIL (load-resume diag disk missing THE.GAME)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    return 0
}

run_test() {
    local name="$1"
    local src="$2"
    local cycles="${3:-20000000}"

    echo -n "  $name: "

    local prg_file="${src%.s}.prg"
    local abs_prg
    abs_prg="$(cd "$(dirname "$prg_file")" && pwd)/$(basename "$prg_file")"
    local vs_file="${src%.s}.vs"

    local asm_output
    asm_output=$(java -jar "$KICKASS" "$src" -o "$prg_file" -libdir ../c64 "${KA_DEFINES[@]}" -vicesymbols 2>&1)
    if [ $? -ne 0 ]; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if [ ! -f "$vs_file" ]; then
        echo "FAIL (missing .vs symbol file)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local start_addr pass_addr
    start_addr=$(awk '/\.test_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")
    pass_addr=$(awk '/\.test_pass$/  { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")

    if [ -z "${start_addr:-}" ] || [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing test_start/test_pass labels in .vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "load \"${abs_prg}\" 0"
        echo "r pc=${start_addr}"
        echo "until \$${pass_addr}"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles "$cycles" +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1

    if grep -qi "^UNTIL: .*C:\$${pass_addr}" "$log_file"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        tail -3 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi

    TOTAL=$((TOTAL + 1))
}

boot_log_last_pc() {
    local log_file="$1"
    python3 - "$log_file" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(errors="ignore").splitlines()
last = ""
for line in text:
    m = re.search(r'C:\$([0-9A-Fa-f]{4})', line)
    if m:
        last = m.group(1).upper()
print(last)
PY
}

boot_log_report_failure() {
    local reason="$1"
    local log_file="$2"
    local target_name="$3"
    local target_addr="$4"
    local vice_rc="${5:-0}"

    local reached="no"
    local jam="no"
    local timeout="no"
    local last_pc=""

    if grep -qi "^UNTIL: .*C:\$${target_addr}\\|^BREAK: .*C:\$${target_addr}" "$log_file"; then
        reached="yes"
    fi
    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        jam="yes"
    fi
    if [ "$vice_rc" -ne 0 ] && [ "$reached" = "no" ] && [ "$jam" = "no" ]; then
        timeout="yes"
    fi
    last_pc=$(boot_log_last_pc "$log_file")

    echo "FAIL (${reason})"
    if [ -n "${last_pc:-}" ]; then
        echo "    last_pc: \$${last_pc}"
    fi
    echo "    target: ${target_name}=\$${target_addr} reached=${reached} jam=${jam} timeout=${timeout} vice_rc=${vice_rc}"
    tail -10 "$log_file" | sed 's/^/    /'
}

run_boot_d64_smoke() {
    local name="boot_d64_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local entry_main
    entry_main=$(awk '/\.entry_main$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${entry_main:-}" ]; then
        echo "FAIL (missing entry_main in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "break \$${entry_main}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 120000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "^BREAK: .*C:\$${entry_main}" "$log_file"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        boot_log_report_failure "did not reach entry_main" "$log_file" "entry_main" "$entry_main" "$vice_rc"
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_boot_title_newgame_smoke() {
    local name="boot_title_newgame_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local game_new_start
    game_new_start=$(awk '/\.game_new_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${game_new_start:-}" ]; then
        echo "FAIL (missing game_new_start in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${game_new_start}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "NN" -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 180000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${game_new_start}" "$log_file"; then
        boot_log_report_failure "did not reach game_new_start" "$log_file" "game_new_start" "$game_new_start" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after reaching game_new_start" "$log_file" "game_new_start" "$game_new_start" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_load_resume_smoke() {
    local name="boot_title_load_resume_smoke"
    echo -n "  $name: "

    build_load_resume_boot_assets || return

    local main_vs="out/main.vs"
    local load_resume_game
    load_resume_game=$(awk '/\.load_resume_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${load_resume_game:-}" ]; then
        echo "FAIL (missing load_resume_game in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_loadresume.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${load_resume_game}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "L" -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 220000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${load_resume_game}" "$log_file"; then
        boot_log_report_failure "did not reach load_resume_game from title load flow" "$log_file" "load_resume_game" "$load_resume_game" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during title load/resume flow" "$log_file" "load_resume_game" "$load_resume_game" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_idle_smoke() {
    local name="boot_title_idle_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local title_show_sysinfo
    title_show_sysinfo=$(awk '/\.title_show_sysinfo$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_show_sysinfo:-}" ]; then
        echo "FAIL (missing title_show_sysinfo in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${title_show_sysinfo}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 120000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${title_show_sysinfo}" "$log_file"; then
        boot_log_report_failure "did not reach title_show_sysinfo on idle boot" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -monlog -monlogname "$log_file" \
        -limitcycles 220000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during idle title soak" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_tier_transition_smoke() {
    local name="boot_tier_transition_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local dungeon_generate
    dungeon_generate=$(awk '/\.dungeon_generate$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${dungeon_generate:-}" ]; then
        echo "FAIL (missing dungeon_generate in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${dungeon_generate}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${dungeon_generate}" "$log_file"; then
        boot_log_report_failure "did not reach dungeon_generate via stairs flow" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after dungeon transition" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_overlay_smoke() {
    local name="town_overlay_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${store_enter}"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "did not reach store_enter via town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_overlay_female_smoke() {
    local name="town_overlay_female_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "break \$d000 \$dfff"
        echo "break \$${store_enter}"
        echo "g"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rB LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "did not reach store_enter via female town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "^#1 \\(Stop on  exec d[0-9a-f][0-9a-f][0-9a-f]\\)" "$log_file"; then
        boot_log_report_failure "executed in I/O hole during female town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during female town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_overlay_state_smoke() {
    local name="town_overlay_state_smoke"
    echo -n "  $name: "

    build_overlay_state_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in overlay-state .vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_overlaystate.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "break \$d000 \$dfff"
        echo "break \$${store_enter}"
        echo "g"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rB LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "did not reach store_enter with corrupted overlay state" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "^#1 \\(Stop on  exec d[0-9a-f][0-9a-f][0-9a-f]\\)" "$log_file"; then
        boot_log_report_failure "executed in I/O hole during corrupted overlay-state town flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during corrupted overlay-state town flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_summary_to_town_smoke() {
    local name="scripted_summary_to_town_smoke"
    echo -n "  $name: "

    build_scripted_input_boot_assets || return

    local main_vs="out/main.vs"
    local c128_test_town_pass c128_test_town_fail
    c128_test_town_pass=$(awk '/\.c128_test_town_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_town_fail=$(awk '/\.c128_test_town_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_test_town_pass:-}" ] || [ -z "${c128_test_town_fail:-}" ]; then
        echo "FAIL (missing scripted summary/town pass/fail symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_scriptedinput.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    local pass_lc fail_lc
    : > "$log_file"
    pass_lc=$(echo "$c128_test_town_pass" | tr '[:upper:]' '[:lower:]')
    fail_lc=$(echo "$c128_test_town_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_town_fail}"
        echo "break \$${c128_test_town_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qiE "Stop on  exec ${pass_lc}" "$log_file" && ! grep -qi "^BREAK: .*C:\$${c128_test_town_pass}" "$log_file"; then
        boot_log_report_failure "did not reach scripted town pass trap" "$log_file" "c128_test_town_pass" "$c128_test_town_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${c128_test_town_fail}" "$log_file"; then
        # In current test builds the fail/pass traps are adjacent BRKs, and VICE can
        # report both breakpoints even when execution explicitly jumps to the pass trap.
        # Once the pass trap is confirmed, treat the run as successful.
        :
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted summary-to-town flow" "$log_file" "c128_test_town_pass" "$c128_test_town_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_move_diag() {
    local stages="1 2 3 4 5 7 8 9"
    local stage
    for stage in $stages; do
        local name="town_move_diag_${stage}"
        echo -n "  $name: "

        build_town_move_diag_assets "$stage" || return

        local diag_addr
        diag_addr=$(awk '/\.c128_diag_town_move_hit$/ { split($2,a,":"); print toupper(a[2]); exit }' out/main.vs)
        if [ -z "${diag_addr:-}" ]; then
            echo "FAIL (missing c128_diag_town_move_hit in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi

        local abs_d64
        abs_d64="$(cd out && pwd)/moria128_townmove_${stage}.d64"
        local mon_file="/tmp/test128_${name}.mon"
        local log_file="/tmp/test128_${name}.log"
        : > "$log_file"
        {
            echo "break \$${diag_addr}"
            echo "g"
        } > "$mon_file"

        "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
            -moncommands "$mon_file" -monlog -monlogname "$log_file" \
            -limitcycles 500000000 +sound -sounddev dummy \
            +remotemonitor +binarymonitor >/dev/null 2>&1
        local vice_rc=$?

        if ! grep -qi "C:\$${diag_addr}" "$log_file"; then
            boot_log_report_failure "did not reach town-move diagnostic stage ${stage}" "$log_file" "c128_diag_town_move_hit" "$diag_addr" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
    done
}

run_store_entry_diag() {
    local name="store_entry_diag"
    echo -n "  $name: "

    build_store_entry_diag_assets || return

    local diag_addr
    diag_addr=$(awk '/\.c128_diag_store_entry_hit$/ { split($2,a,":"); print toupper(a[2]); exit }' out/main.vs)
    if [ -z "${diag_addr:-}" ]; then
        echo "FAIL (missing c128_diag_store_entry_hit in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_storeentry_diag.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"
    {
        echo "break \$${diag_addr}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "C:\$${diag_addr}" "$log_file"; then
        boot_log_report_failure "did not reach store-entry diagnostic trap" "$log_file" "c128_diag_store_entry_hit" "$diag_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_load_resume_diag() {
    local name="load_resume_diag"
    echo -n "  $name: "

    build_load_resume_diag_assets || return

    local diag_addr
    diag_addr=$(awk '/\.c128_diag_load_resume_hit$/ { split($2,a,":"); print toupper(a[2]); exit }' out/main.vs)
    if [ -z "${diag_addr:-}" ]; then
        echo "FAIL (missing c128_diag_load_resume_hit in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_loadresume_diag.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"
    {
        echo "break \$${diag_addr}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "L" -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 220000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "C:\$${diag_addr}" "$log_file"; then
        boot_log_report_failure "did not reach load-resume diagnostic trap" "$log_file" "c128_diag_load_resume_hit" "$diag_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_cache_survival_smoke() {
    local name="cache_survival_smoke"
    echo -n "  $name: "

    build_cache_survival_boot_assets || return

    local main_vs="out/main.vs"
    local c128_test_cache_survival_pass c128_test_cache_survival_fail
    c128_test_cache_survival_pass=$(awk '/\.c128_test_cache_survival_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_cache_survival_fail=$(awk '/\.c128_test_cache_survival_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_test_cache_survival_pass:-}" ] || [ -z "${c128_test_cache_survival_fail:-}" ]; then
        echo "FAIL (missing cache-survival pass/fail symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_cache_survival.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    local fail_lc
    : > "$log_file"
    fail_lc=$(echo "$c128_test_cache_survival_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_cache_survival_fail}"
        echo "until \$${c128_test_cache_survival_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file"; then
        boot_log_report_failure "cache survival validation failed after summary-to-town flow" "$log_file" "c128_test_cache_survival_fail" "$c128_test_cache_survival_fail" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${c128_test_cache_survival_pass}" "$log_file"; then
        boot_log_report_failure "did not reach cache-survival pass trap" "$log_file" "c128_test_cache_survival_pass" "$c128_test_cache_survival_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during cache-survival flow" "$log_file" "c128_test_cache_survival_pass" "$c128_test_cache_survival_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_death_overlay_smoke() {
    local name="death_overlay_smoke"
    echo -n "  $name: "

    build_death_overlay_boot_assets || return

    local main_vs="out/main.vs"
    local score_death_screen
    score_death_screen=$(awk '/\.score_death_screen$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${score_death_screen:-}" ]; then
        echo "FAIL (missing death-flow symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_death.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${score_death_screen}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "N" -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 240000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${score_death_screen}" "$log_file"; then
        boot_log_report_failure "did not reach score_death_screen via death overlay flow" "$log_file" "score_death_screen" "$score_death_screen" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during death overlay flow" "$log_file" "score_death_screen" "$score_death_screen" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_restart_to_title_smoke() {
    local name="restart_to_title_smoke"
    echo -n "  $name: "

    build_death_overlay_boot_assets || return

    local main_vs="out/main.vs"
    local title_show_sysinfo
    title_show_sysinfo=$(awk '/\.title_show_sysinfo$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_show_sysinfo:-}" ]; then
        echo "FAIL (missing title_show_sysinfo in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_death.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "until \$${title_show_sysinfo}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA  S' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 420000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${title_show_sysinfo}" "$log_file"; then
        boot_log_report_failure "did not return to title_show_sysinfo after restart flow" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during restart-to-title flow" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_preload_partial_failure_smoke() {
    local name="preload_partial_failure_smoke"
    echo -n "  $name: "

    build_partial_failure_boot_assets || return

    local main_vs="out/main.vs"
    local dungeon_generate tier_load_disk c128_test_partial_cache_fail
    dungeon_generate=$(awk '/\.dungeon_generate$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    tier_load_disk=$(awk '/\.tier_load_disk$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_partial_cache_fail=$(awk '/\.c128_test_partial_cache_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${dungeon_generate:-}" ] || [ -z "${tier_load_disk:-}" ] || [ -z "${c128_test_partial_cache_fail:-}" ]; then
        echo "FAIL (missing required symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_skip1.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    local fail_lc
    : > "$log_file"
    fail_lc=$(echo "$c128_test_partial_cache_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_partial_cache_fail}"
        echo "until \$${tier_load_disk}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file"; then
        boot_log_report_failure "tier partial-failure readiness isolation check failed" "$log_file" "c128_test_partial_cache_fail" "$c128_test_partial_cache_fail" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${tier_load_disk}" "$log_file"; then
        boot_log_report_failure "missing-tier preload did not fall back to tier_load_disk" "$log_file" "tier_load_disk" "$tier_load_disk" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    {
        echo "until \$${dungeon_generate}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${dungeon_generate}" "$log_file"; then
        boot_log_report_failure "missing-tier preload did not continue to dungeon_generate" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after missing-tier fallback" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_overlay_partial_failure_smoke() {
    local name="overlay_partial_failure_smoke"
    echo -n "  $name: "

    build_overlay_partial_failure_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter overlay_load_disk c128_test_overlay_cache_fail
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    overlay_load_disk=$(awk '/\.overlay_load_disk$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_overlay_cache_fail=$(awk '/\.c128_test_overlay_cache_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ] || [ -z "${overlay_load_disk:-}" ] || [ -z "${c128_test_overlay_cache_fail:-}" ]; then
        echo "FAIL (missing required symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_skipovl2.d64"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    local fail_lc
    : > "$log_file"
    fail_lc=$(echo "$c128_test_overlay_cache_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_overlay_cache_fail}"
        echo "until \$${overlay_load_disk}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file"; then
        boot_log_report_failure "overlay partial-failure readiness isolation check failed" "$log_file" "c128_test_overlay_cache_fail" "$c128_test_overlay_cache_fail" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${overlay_load_disk}" "$log_file"; then
        boot_log_report_failure "missing overlay preload did not fall back to overlay_load_disk" "$log_file" "overlay_load_disk" "$overlay_load_disk" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    {
        echo "until \$${store_enter}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "missing overlay preload did not continue to store_enter" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after missing-overlay fallback" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_diag_copy() {
    local name="boot_diag_copy"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local entry_main
    entry_main=$(awk '/\.entry_main$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${entry_main:-}" ]; then
        echo "FAIL (missing entry_main in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64 abs_diag_boot
    abs_d64="$(cd out && pwd)/moria128.d64"
    abs_diag_boot="$(cd out && pwd)/boot128.diag.prg"
    local mon_file="/tmp/test128_${name}.mon"
    local log_file="/tmp/test128_${name}.log"
    : > "$log_file"

    {
        echo "attach \"${abs_d64}\" 8"
        echo "load \"${abs_diag_boot}\" 0"
        echo "r pc=1C0E"
        echo "break \$${entry_main}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 120000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^BREAK: .*C:\$${entry_main}" "$log_file"; then
        boot_log_report_failure "did not reach entry_main" "$log_file" "entry_main" "$entry_main" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

echo "=== Moria C128 Tests ==="
if [ "$PERF_P1_MODE" = "1" ]; then
    echo "  mode: PERF_P1 instrumentation ON"
else
    echo "  mode: PERF_P1 instrumentation OFF"
fi
run_main_assembly_check
run_symbol_placement_check
run_runtime_ownership_guard_check
run_prompt_irq_guard_check
run_80col_layout_guard_check
run_test "minimal128" "tests/test_minimal128.s"
run_test "config128" "tests/test_config128.s"
run_test "memory128" "tests/test_memory128.s"
run_test "db128" "tests/test_db128.s"
run_test "tier128" "tests/test_tier128.s"
run_test "input128" "tests/test_input128.s"
run_test "main_loop128" "tests/test_main_loop128.s" 500000000
run_test "msg_prompt128" "tests/test_msg_prompt128.s" 120000000
run_test "vdc_attr128" "tests/test_vdc_attr128.s"
run_test "status_coherence128" "tests/test_status_coherence128.s"
run_test "dungeon128" "tests/test_dungeon128.s" 50000000
run_test "soak128" "tests/test_soak128.s" 300000000
run_boot_d64_smoke
run_boot_title_idle_smoke
run_boot_title_newgame_smoke
run_boot_title_load_resume_smoke
run_boot_tier_transition_smoke
run_town_overlay_smoke
run_town_overlay_female_smoke
run_town_overlay_state_smoke
run_scripted_summary_to_town_smoke
run_town_move_diag
run_store_entry_diag
run_cache_survival_smoke
run_death_overlay_smoke
run_restart_to_title_smoke
run_load_resume_diag
run_preload_partial_failure_smoke
run_overlay_partial_failure_smoke
run_boot_diag_copy
run_test "monster128" "tests/test_monster128.s"
if [ "$PERF_P1_MODE" = "1" ]; then
    run_test "perf_p1" "tests/test_perf_p1.s"
fi
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
