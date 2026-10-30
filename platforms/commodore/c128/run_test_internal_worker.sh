#!/bin/bash
set -u

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RESULT_FILE="$1"
NAME="$2"
SRC="$3"
CYCLES="${4:-20000000}"

# normalize_monitor_addr, c128_target_is_stale, test128_now_ms and
# test128_tmp_file come from run_tests128.sh (export -f), the only caller.
if ! declare -F c128_target_is_stale >/dev/null; then
    echo "run_test_internal_worker.sh: run it through run_tests128.sh" >&2
    exit 2
fi

start_ms="$(test128_now_ms)"

prg_file="${SRC%.s}.prg"
abs_prg="$(cd "$(dirname "$prg_file")" && pwd)/$(basename "$prg_file")"
vs_file="${SRC%.s}.vs"

if c128_target_is_stale "$prg_file" || c128_target_is_stale "$vs_file"; then
    # kickass_java.sh fails a build whose .assert failed (KickAssembler exits 0).
    asm_output=$("$REPO_ROOT/tools/kickass_java.sh" -jar "$KICKASS" "$SRC" -o "$prg_file" \
        -libdir "$REPO_ROOT/core" \
        -libdir "$REPO_ROOT/platforms/commodore/common" \
        -libdir "$REPO_ROOT/platforms/commodore" \
        -afo -libdir ../c64 -define C128 -vicesymbols :OVL_OUT=../../../build/test/c128 2>&1)
    if [ $? -ne 0 ]; then
        # The assembler still wrote them; left behind, the staleness check
        # would skip this build next run.
        rm -f "$prg_file" "$vs_file"
        printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "assembly error" >> "$RESULT_FILE"
        exit 0
    fi
fi

if [ ! -f "$vs_file" ]; then
    printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "missing .vs symbol file" >> "$RESULT_FILE"
    exit 0
fi

pass_addr=$(awk '/\.test_pass$/  { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")
start_addr=$(awk '/\.test_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")
fail_addr=$(awk '/\.test_fail$/  { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")

if [ -z "${pass_addr:-}" ]; then
    printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "missing test_pass label" >> "$RESULT_FILE"
    exit 0
fi

if [ -z "${start_addr:-}" ]; then
    printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "missing test_start label" >> "$RESULT_FILE"
    exit 0
fi

pass_addr="$(normalize_monitor_addr "$pass_addr")"
start_addr="$(normalize_monitor_addr "$start_addr")"
if [ -n "${fail_addr:-}" ]; then
    fail_addr="$(normalize_monitor_addr "$fail_addr")"
fi

mon_file="$(test128_tmp_file "test128_${NAME}.mon")"
log_file="$(test128_tmp_file "test128_${NAME}.log")"
: > "$log_file"

{
    echo "f 0000 00FF 00"
    echo "> FF00 3E"
    echo "> D506 07"
    echo "load \"${abs_prg}\" 0"
    if [ -n "${fail_addr:-}" ]; then
        echo "break \$${fail_addr}"
    fi
    echo "r sp=ff"
    echo "r pc=\$${start_addr}"
    echo "until \$${pass_addr}"
    echo "quit"
} > "$mon_file"

exit_png="../../../build/test/c128/exit/${NAME}_exit.png"
mkdir -p "${exit_png%/*}"
rm -f "$exit_png"    # never name a stale screen

# -initbreak ready: see run_tests128.sh run_test().
"$VICE" -config "$VICE_CONFIG" -default +saveres +autostart-delay-random -exitscreenshot "$exit_png" -console -nativemonitor -warp -80col -initbreak ready \
    -moncommands "$mon_file" -monlogname "$log_file" -monlog \
    -limitcycles "$CYCLES" +sound -sounddev dummy \
    +remotemonitor +binarymonitor >/dev/null 2>&1

screen_note=""
[ -s "$exit_png" ] && screen_note="; screen: $exit_png"
pass_addr_lc="$(printf '%s' "$pass_addr" | tr '[:upper:]' '[:lower:]')"
# Only a real stop counts: see run_tests128.sh boot_log_has_stop_at().
if grep -qiE "^#[0-9]+ \(Stop on[[:space:]]+exec[[:space:]]+${pass_addr_lc}\)" "$log_file"; then
    printf 'PASS\t%s\t%s\t\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" >> "$RESULT_FILE"
    exit 0
fi

if [ -n "${fail_addr:-}" ]; then
    fail_addr_lc="$(printf '%s' "$fail_addr" | tr '[:upper:]' '[:lower:]')"
    if grep -qiE "^#[0-9]+ \(Stop on[[:space:]]+exec[[:space:]]+${fail_addr_lc}\)" "$log_file"; then
        printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "hit test_fail$screen_note" >> "$RESULT_FILE"
        exit 0
    fi
fi

printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "execution failed$screen_note" >> "$RESULT_FILE"
