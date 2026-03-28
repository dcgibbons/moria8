#!/bin/bash
set -u

RESULT_FILE="$1"
NAME="$2"
SRC="$3"
CYCLES="${4:-20000000}"

normalize_monitor_addr() {
    python3 - <<'PY' "$1"
import sys
addr = sys.argv[1].strip().upper()
if not addr:
    print("")
elif len(addr) > 4:
    print(addr[-4:])
else:
    print(addr.zfill(4))
PY
}

c128_target_is_stale() {
    local target="$1"
    if [ ! -f "$target" ]; then
        return 0
    fi

    if find . -maxdepth 1 -type f \( -name '*.s' -o -name 'Makefile' \) -newer "$target" -print -quit | grep -q .; then
        return 0
    fi
    if find tests ../common ../c64 -type f -name '*.s' -newer "$target" -print -quit | grep -q .; then
        return 0
    fi

    return 1
}

test128_now_ms() {
    python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

test128_tmp_file() {
    local name="$1"
    printf '%s/%s\n' "$TEST128_TMP_DIR" "$name"
}

stop_vice_process() {
    local vice_pid="$1"
    if kill -0 "$vice_pid" 2>/dev/null; then
        kill "$vice_pid" 2>/dev/null || true
        wait "$vice_pid" 2>/dev/null || true
    fi
}

wait_for_monlog_result() {
    local vice_pid="$1"
    local pass_addr="$2"
    local log_file="$3"
    local deadline=$((SECONDS + 25))

    while :; do
        if grep -qi "^BREAK: .*C:\$${pass_addr}" "$log_file"; then
            stop_vice_process "$vice_pid"
            return 0
        fi
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            stop_vice_process "$vice_pid"
            return 1
        fi
        if ! kill -0 "$vice_pid" 2>/dev/null; then
            wait "$vice_pid" 2>/dev/null || true
            break
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            stop_vice_process "$vice_pid"
            return 1
        fi
        sleep 0.1
    done

    grep -qi "^BREAK: .*C:\$${pass_addr}" "$log_file"
}

start_ms="$(test128_now_ms)"

prg_file="${SRC%.s}.prg"
abs_prg="$(cd "$(dirname "$prg_file")" && pwd)/$(basename "$prg_file")"
vs_file="${SRC%.s}.vs"

if c128_target_is_stale "$prg_file" || c128_target_is_stale "$vs_file"; then
    asm_output=$(java -jar "$KICKASS" "$SRC" -o "$prg_file" -libdir ../c64 -define C128 -vicesymbols -var OVL_OUT='"out"' 2>&1)
    if [ $? -ne 0 ]; then
        printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "assembly error" >> "$RESULT_FILE"
        exit 0
    fi
fi

if [ ! -f "$vs_file" ]; then
    printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "missing .vs symbol file" >> "$RESULT_FILE"
    exit 0
fi

pass_addr=$(awk '/\.test_pass$/  { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")

if [ -z "${pass_addr:-}" ]; then
    printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "missing test_pass label" >> "$RESULT_FILE"
    exit 0
fi

pass_addr="$(normalize_monitor_addr "$pass_addr")"

mon_file="$(test128_tmp_file "test128_${NAME}.mon")"
log_file="$(test128_tmp_file "test128_${NAME}.log")"
: > "$log_file"

{
    echo "break \$${pass_addr}"
    echo "g"
} > "$mon_file"

"$VICE" -console -nativemonitor -warp -80col -autostart "$abs_prg" \
    -moncommands "$mon_file" -monlog -monlogname "$log_file" \
    -limitcycles "$CYCLES" +sound -sounddev dummy \
    +remotemonitor +binarymonitor >/dev/null 2>&1 &
vice_pid=$!

if wait_for_monlog_result "$vice_pid" "$pass_addr" "$log_file"; then
    printf 'PASS\t%s\t%s\t\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" >> "$RESULT_FILE"
else
    printf 'FAIL\t%s\t%s\t%s\n' "$NAME" "$(( $(test128_now_ms) - start_ms ))" "execution failed" >> "$RESULT_FILE"
fi
