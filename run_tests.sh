#!/bin/bash
# run_tests.sh — Assemble and run all Phase 1 tests in VICE headless
#
# Usage: ./run_tests.sh
# Requires: Kick Assembler, VICE (x64sc)

KICKASS="/Applications/C64/KickAssembler/KickAss.jar"
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
    asm_output=$(java -jar "$KICKASS" "$src" -o "${src%.s}.prg" 2>&1)

    if ! echo "$asm_output" | grep -q "0 failed"; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Extract end address from "Test Code" segment in assembler output
    # Format: "$0810-$0B10 Test Code" — the end address is where BRK sits
    local end_addr
    end_addr=$(echo "$asm_output" | grep "Test Code" | sed 's/.*\$\([0-9A-Fa-f]*\) Test Code/\1/')

    if [ -z "$end_addr" ]; then
        echo "FAIL (could not determine BRK address)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Create monitor script: set breakpoint at end of test code
    local mon_file="/tmp/test_${name}.mon"
    echo "break exec \$${end_addr}" > "$mon_file"

    # Run in VICE: moncommands sets breakpoint, piped commands dump results after break
    local result
    result=$(echo -e "m ${result_range}\nquit\n" | \
        "$VICE" -console -nativemonitor -autostartprgmode 1 \
        -autostart "${src%.s}.prg" -moncommands "$mon_file" \
        -limitcycles "$cycles" 2>&1 | grep "^>C:0")

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

echo "=== Moria Phase 1 Tests ==="
echo ""

# Build main program first (compile-time asserts)
echo -n "  main.s assembly: "
cd "$(dirname "$0")"
asm_out=$(java -jar "$KICKASS" main.s -o moria.prg 2>&1)
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
run_test "rng"    "tests/test_rng.s"    "0400 0405" 6
run_test "memory" "tests/test_memory.s" "0400 0402" 3
run_test "player" "tests/test_player.s" "0400 0409" 10
run_test "dungeon" "tests/test_dungeon.s" "0400 041b" 28 500000000
run_test "monster" "tests/test_monster.s" "0400 0409" 10 500000000
run_test "monster_ai" "tests/test_monster_ai.s" "0400 0409" 10 500000000
run_test "combat" "tests/test_combat.s" "0400 0409" 10 500000000
run_test "monster_attack" "tests/test_monster_attack.s" "0400 0409" 10 500000000
run_test "effects" "tests/test_effects.s" "0400 0409" 10 500000000
run_test "item" "tests/test_item.s" "0400 041f" 32 1000000000

echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
