#!/bin/bash
# run_tests128.sh — Assemble and run C128 runtime tests in VICE headless

set -u

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
PASS=0
FAIL=0
TOTAL=0
BOOT_ASSETS_BUILT=0

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
run_test "minimal128" "tests/test_minimal128.s"
run_test "memory128" "tests/test_memory128.s"
run_test "db128" "tests/test_db128.s"
run_test "tier128" "tests/test_tier128.s"
run_test "input128" "tests/test_input128.s"
run_test "dungeon128" "tests/test_dungeon128.s" 50000000
run_test "soak128" "tests/test_soak128.s" 300000000
run_boot_d64_smoke
run_boot_diag_copy
run_test "monster128" "tests/test_monster128.s"
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
