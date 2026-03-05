#!/bin/bash
# run_tests128.sh — Assemble and run C128 runtime tests in VICE headless

set -u

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
PASS=0
FAIL=0
TOTAL=0
BOOT_ASSETS_BUILT=0

run_main_assembly_check() {
    echo -n "  main128_asm: "

    local asm_output
    asm_output=$(java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -o out/moria128.prg 2>&1)

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
main_source = Path("main.s").read_text().splitlines()
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
bad = []
missing = []
missing_asserts = []
for name in required:
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] >= 0xD000:
        bad.append((name, labels[name]))

# Hard rule: no critical entrypoint may execute from the $D000-$DFFF I/O hole.
for name, addr in labels.items():
    if not name.startswith("tramp_"):
        continue
    if name not in assert_guards:
        missing_asserts.append(name)
    if addr >= 0xD000:
        bad.append((name, addr))

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
]

for name, lines, chain in required_chains:
    if not has_ordered_chain(lines, chain):
        print(f"{name} must gate with input_wait_release before input_get_key")
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
    if ! make -s build128 disk128 >"$build_log" 2>&1; then
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
    asm_output=$(java -jar "$KICKASS" "$src" -o "$prg_file" -libdir ../c64 -define C128 -vicesymbols 2>&1)
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

    if grep -qi "^BREAK: .*C:\$${entry_main}" "$log_file"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        tail -6 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
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

    if ! grep -qi "^BREAK: .*C:\$${entry_main}" "$log_file"; then
        echo "FAIL (did not reach entry_main)"
        tail -6 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

echo "=== Moria C128 Tests ==="
run_main_assembly_check
run_symbol_placement_check
run_prompt_irq_guard_check
run_test "minimal128" "tests/test_minimal128.s"
run_test "memory128" "tests/test_memory128.s"
run_test "db128" "tests/test_db128.s"
run_test "tier128" "tests/test_tier128.s"
run_test "input128" "tests/test_input128.s"
run_test "msg_prompt128" "tests/test_msg_prompt128.s" 120000000
run_test "dungeon128" "tests/test_dungeon128.s" 50000000
run_test "soak128" "tests/test_soak128.s" 300000000
run_boot_d64_smoke
run_boot_diag_copy
run_test "monster128" "tests/test_monster128.s"
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
