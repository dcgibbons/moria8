#!/bin/bash
# run_tests128.sh — Assemble and run C128 runtime tests in VICE headless

set -u

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
PASS=0
FAIL=0
TOTAL=0

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
    asm_output=$(java -jar "$KICKASS" "$src" -o "$prg_file" -libdir ../c64 -vicesymbols 2>&1)
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

    if grep -q "^UNTIL: .*C:\$${pass_addr}" "$log_file"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        tail -3 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi

    TOTAL=$((TOTAL + 1))
}

echo "=== Moria C128 Tests ==="
run_test "minimal128" "tests/test_minimal128.s"
run_test "memory128" "tests/test_memory128.s"
run_test "dungeon128" "tests/test_dungeon128.s" 50000000
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
