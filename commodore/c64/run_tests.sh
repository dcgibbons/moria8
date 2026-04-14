#!/bin/bash
# run_tests.sh — Assemble and run all Phase 1 tests in VICE headless
#
# Usage: ./run_tests.sh
# Requires: Kick Assembler, VICE (x64sc)

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
DEBUG_FEAT_DISK_TRACE="${DEBUG_FEAT_DISK_TRACE:-0}"
if [ "$DEBUG_FEAT_DISK_TRACE" = "1" ]; then
    KICKASS_TRACE_DEFINE=(-define DEBUG_FEAT_DISK_TRACE)
else
    KICKASS_TRACE_DEFINE=(-define DEBUG_FEAT_DISK_TRACE=0)
fi
VICE="x64sc"
PASS=0
FAIL=0
TOTAL=0

run_test() {
    local name="$1"
    local src="$2"
    local result_range="$3"   # e.g. "0400 040b"
    local expected_count="$4"
    local cycles="${5:-20000000}"  # Optional cycle limit (default 20M)

    echo -n "  $name: "

    # Assemble and capture output
    local asm_output
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" "$src" -o "${src%.s}.prg" 2>&1)

    if ! echo "$asm_output" | grep -q "0 failed"; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local end_addr
    # Extract end address from "Test Code" segment in assembler output
    # Format: "$0810-$0B10 Test Code" — the end address is where BRK sits
    end_addr=$(echo "$asm_output" | grep "Test Code" | sed 's/.*\$\([0-9A-Fa-f]*\) Test Code/\1/')

    if [ -z "$end_addr" ]; then
        echo "FAIL (could not determine BRK address)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Create monitor script: set breakpoint, continue, dump results, exit.
    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    {
        echo "break exec \$${end_addr}"
        echo "g"
        echo "m ${result_range}"
        echo "quit"
    } > "$mon_file"

    # Run in VICE with an all-in-one monitor script; piping monitor commands
    # can race VICE startup and leave suites hanging.
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    run_vice_once() {
        local log_path="$1"
        script -q "$log_path" \
            "$VICE" -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
            -autostart "${src%.s}.prg" -moncommands "$mon_file" \
            -limitcycles "$cycles" +sound -sounddev dummy \
            +remotemonitor +binarymonitor > /dev/null 2>&1
    }

    run_vice_once "$tty_log"

    local result
    result=$(grep "^>C:0" "$tty_log")

    # Count $01 bytes (passes) in result
    local pass_count
    pass_count=$(echo "$result" | grep -o " 01" | wc -l | tr -d ' ')

    if [ "$pass_count" -ge "$expected_count" ]; then
        echo "PASS ($pass_count/$expected_count tests)"
        PASS=$((PASS + 1))
    else
        echo "FAIL ($pass_count/$expected_count tests passed)"
        echo "    Raw: $result"
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_sound_monitor_test() {
    local name="sound"
    local src="tests/test_sound_monitor.s"
    local cycles="500000000"

    echo -n "  $name: "

    local asm_output
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" "$src" -o "${src%.s}.prg" 2>&1)

    if ! echo "$asm_output" | grep -q "0 failed"; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local sym_file="${src%.s}.sym"
    local mon_file
    local log_file
    mon_file=$(mktemp -t "test_${name}_mon")
    log_file=$(mktemp -t "test_${name}_log")

    lookup_label() {
        local label="$1"
        awk -F'[$=]' "/\\.label ${label}=\\$/{print toupper(\$3); exit}" "$sym_file"
    }

    local stages=(init none invalid bump hit miss pickup death levelup spell spell_fail)

    {
        local stage addr
        for stage in "${stages[@]}"; do
            addr="$(lookup_label "sound_stage_${stage}")"
            if [ -z "$addr" ]; then
                echo "FAIL (missing sound stage label: $stage)"
                return 1
            fi
            echo "break exec \$${addr}"
            echo "g"
            echo "m d40e d414"
            echo "m d418 d418"
            echo "m 006c 006c"
        done
        echo "quit"
    } > "$mon_file" || {
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    }

    script -q "$log_file" \
        "$VICE" -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -autostart "${src%.s}.prg" -moncommands "$mon_file" \
        -limitcycles "$cycles" +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if python3 - "$log_file" <<'PY'
import re
import sys
from pathlib import Path

expected = [
    ("init",      ["00","00","00","00","00","00","00"], "0F", "FF"),
    ("none",      ["00","00","00","00","00","00","00"], "0F", "FF"),
    ("invalid",   ["00","00","00","00","00","00","00"], "0F", "FF"),
    ("bump",      ["00","04","00","00","81","08","00"], "0F", "00"),
    ("hit",       ["00","10","00","00","21","09","00"], "0F", "01"),
    ("miss",      ["00","20","00","00","81","05","00"], "0F", "02"),
    ("pickup",    ["00","18","00","00","11","0A","00"], "0F", "03"),
    ("death",     ["00","03","00","00","81","0F","09"], "0F", "04"),
    ("levelup",   ["00","1C","00","08","41","0C","00"], "0F", "05"),
    ("spell",     ["00","14","00","00","11","08","00"], "0F", "06"),
    ("spell_fail",["00","0C","00","00","81","06","00"], "0F", "07"),
]

lines = Path(sys.argv[1]).read_text(encoding="latin-1").splitlines()
d40e = []
d418 = []
snd = []

for line in lines:
    upper = line.upper()
    if upper.startswith(">C:D40E"):
        payload = line.split(None, 1)[1] if len(line.split(None, 1)) > 1 else ""
        d40e.append(re.findall(r"\b[0-9A-Fa-f]{2}\b", payload)[:7])
    elif upper.startswith(">C:D418"):
        payload = line.split(None, 1)[1] if len(line.split(None, 1)) > 1 else ""
        vals = re.findall(r"\b[0-9A-Fa-f]{2}\b", payload)
        d418.append(vals[:1])
    elif upper.startswith(">C:006C"):
        payload = line.split(None, 1)[1] if len(line.split(None, 1)) > 1 else ""
        vals = re.findall(r"\b[0-9A-Fa-f]{2}\b", payload)
        snd.append(vals[:1])

if not (len(d40e) == len(d418) == len(snd) == len(expected)):
    print(f"FAIL (unexpected dump counts d40e={len(d40e)} d418={len(d418)} snd={len(snd)})")
    sys.exit(1)

for index, (stage, exp_regs, exp_vol, exp_snd) in enumerate(expected):
    got_regs = [value.upper() for value in d40e[index]]
    got_vol = d418[index][0].upper() if d418[index] else ""
    got_snd = snd[index][0].upper() if snd[index] else ""
    if got_regs != exp_regs or got_vol != exp_vol or got_snd != exp_snd:
        print(f"FAIL ({stage}: regs={got_regs} vol={got_vol} snd={got_snd})")
        sys.exit(1)

print(f"PASS ({len(expected)}/{len(expected)} checkpoints)")
PY
    then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

echo "=== Moria Phase 1 Tests ==="
echo ""

# Build main program first (compile-time asserts)
echo -n "  main.s assembly: "
cd "$(dirname "$0")"
asm_out=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -o moria.prg 2>&1)
assert_info=$(echo "$asm_out" | grep "asserts")
if echo "$asm_out" | grep -q "0 failed"; then
    echo "PASS ($assert_info)"
    PASS=$((PASS + 1))
else
    echo "FAIL (assembly errors)"
    echo "$asm_out" | grep -i error | head -5
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Runtime tests
# Args: name, source, result memory range, expected pass count
run_test "math"   "tests/test_math.s"   "0400 040f" 16
run_test "rng"    "tests/test_rng.s"    "0400 0409" 10
run_test "memory" "tests/test_memory.s" "0400 0402" 3
run_test "config" "tests/test_config.s" "0400 0400" 1
run_test "input"  "tests/test_input.s"  "0400 040a" 11
run_test "main_loop" "tests/test_main_loop.s" "0400 0417" 24 500000000
run_test "turn" "tests/test_turn.s" "0400 040a" 11 500000000
run_test "player" "tests/test_player.s" "0400 0409" 10
run_test "dungeon" "tests/test_dungeon.s" "0400 0424" 37 500000000
run_test "monster" "tests/test_monster.s" "0400 040c" 13 500000000
run_test "monster_ai" "tests/test_monster_ai.s" "0400 0415" 22 500000000
run_test "combat" "tests/test_combat.s" "0400 041b" 28 500000000
run_test "monster_attack" "tests/test_monster_attack.s" "0400 040b" 12 500000000
run_test "effects" "tests/test_effects.s" "0400 041f" 32 1000000000
run_test "item" "tests/test_item.s" "0400 042e" 47 1000000000
run_test "store" "tests/test_store.s" "0400 0424" 37 1000000000
run_test "ui_views" "tests/test_ui_views.s" "0400 040c" 13 500000000
run_test "subsystems" "tests/test_subsystems.s" "0400 0409" 10
run_sound_monitor_test
run_test "save"  "tests/test_save.s"  "0400 0409" 10 1000000000
run_test "score" "tests/test_score.s" "0400 040b" 12 500000000
run_test "wands_staves" "tests/test_wands_staves.s" "0400 0406" 7 100000000
run_test "monster_magic" "tests/test_monster_magic.s" "0400 0407" 8 500000000
run_test "tier" "tests/test_tier.s" "0400 040a" 11 500000000
run_test "disk_swap" "tests/test_disk_swap.s" "0400 040b" 12 500000000
run_test "render" "tests/test_render.s" "0400 0403" 4 500000000
run_test "ranged" "tests/test_ranged.s" "0400 0407" 8 500000000
run_test "ego" "tests/test_ego.s" "0400 0409" 10 500000000
run_test "throw" "tests/test_throw.s" "0400 0405" 6 500000000
run_test "bash" "tests/test_bash.s" "0400 0407" 8 500000000
run_test "tunnel" "tests/test_tunnel.s" "0400 0407" 8 500000000
run_test "background" "tests/test_background.s" "0400 0407" 8

echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
