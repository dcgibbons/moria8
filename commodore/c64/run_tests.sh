#!/bin/bash
# run_tests.sh — Assemble and run all Phase 1 tests in VICE headless
#
# Usage: ./run_tests.sh
# Requires: Kick Assembler, VICE (x64sc)

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RUN_TESTS64_DIR="${RUN_TESTS64_DIR:-$REPO_ROOT/commodore/c64}"
cd "$RUN_TESTS64_DIR"
COMMODORE_MAKE=(make -s -C "$REPO_ROOT/commodore")
KICKASS_WAS_SET="${KICKASS+x}"
KICKASS="${KICKASS:-$REPO_ROOT/tools/kickass/KickAss.jar}"
case "$KICKASS" in
    /*) ;;
    *) KICKASS="$(pwd)/$KICKASS" ;;
esac
if [ -n "$KICKASS_WAS_SET" ]; then
    kickass_status=0
    "${COMMODORE_MAKE[@]}" KICKASS="$KICKASS" ensure-kickass || kickass_status=$?
else
    kickass_status=0
    "${COMMODORE_MAKE[@]}" ensure-kickass || kickass_status=$?
fi
if [ "$kickass_status" -ne 0 ]; then
    exit 1
fi
KICKASS="$(cd "$(dirname "$KICKASS")" && pwd)/$(basename "$KICKASS")"
DEBUG_FEAT_DISK_TRACE="${DEBUG_FEAT_DISK_TRACE:-0}"
if [ "$DEBUG_FEAT_DISK_TRACE" = "1" ]; then
    KICKASS_TRACE_DEFINE=(-define DEBUG_FEAT_DISK_TRACE)
else
    KICKASS_TRACE_DEFINE=(-define DEBUG_FEAT_DISK_TRACE=0)
fi
VICE="${VICE:-x64sc}"
C1541="${C1541:-c1541}"
TEST_FILTER="${TEST_FILTER:-}"
PASS=0
FAIL=0
TOTAL=0

suite_selected() {
    local name="$1"
    [ -z "$TEST_FILTER" ] || [[ "$name" =~ $TEST_FILTER ]]
}

suite_selected_any() {
    local name
    for name in "$@"; do
        if [ -n "$name" ] && suite_selected "$name"; then
            return 0
        fi
    done
    return 1
}

run_suite_function() {
    local name="$1"
    local fn="$2"
    shift 2
    if ! suite_selected_any "$name" "$@"; then
        return
    fi
    "$fn"
}

run_disk_media_probe() {
    local name="$1"

    echo -n "  $name: "
    if python3 -u ../disk_media_probe.py --scenario "$name" --platform c64 --c1541 "$C1541"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_media_drive8_attach_read_write() {
    run_disk_media_probe "media_drive8_attach_read_write"
}

run_media_drive9_attach_read_write() {
    run_disk_media_probe "media_drive9_attach_read_write"
}

run_media_drive10_11_device_probe() {
    run_disk_media_probe "media_drive10_11_device_probe"
}

check_static_contract() {
    local name="$1"
    local file="$2"
    local pattern="$3"

    if ! suite_selected "$name"; then
        return
    fi

    echo -n "  $name: "
    if python3 - "$file" "$pattern" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
needles = [part.strip() for part in sys.argv[2].split("|||") if part.strip()]
pos = 0
for needle in needles:
    idx = text.find(needle, pos)
    if idx < 0:
        raise SystemExit(1)
    pos = idx + len(needle)
PY
    then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_test() {
    local name="$1"
    local src="$2"
    local result_range="$3"   # e.g. "0400 040b"
    local expected_count="$4"
    local cycles="${5:-20000000}"  # Optional cycle limit (default 20M)

    if ! suite_selected "$name"; then
        return
    fi

    echo -n "  $name: "

    local prg_file
    prg_file=$(mktemp -t "test_${name}_prg")

    # Assemble and capture output
    local asm_output
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" -define C64_UNIT_TEST "$src" -showmem -o "$prg_file" 2>&1)

    if ! echo "$asm_output" | grep -q "0 failed"; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local test_code_line
    local test_code_count
    # Extract the stop address from exactly one "Test Code" memory-map segment.
    # Format: "$0810-$0B10 Test Code" — the end address is where BRK sits.
    test_code_line=$(echo "$asm_output" | grep -E '^[[:space:]]+\$[0-9A-Fa-f]+-\$[0-9A-Fa-f]+[[:space:]]+Test Code$')
    test_code_count=$(echo "$test_code_line" | grep -c .)

    if [ "$test_code_count" -ne 1 ]; then
        echo "FAIL (expected one Test Code segment, found $test_code_count)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local start_addr
    local end_addr
    start_addr=$(echo "$test_code_line" | sed 's/.*$\([0-9A-Fa-f]*\)-$\([0-9A-Fa-f]*\).*/\1/')
    end_addr=$(echo "$test_code_line" | sed 's/.*$\([0-9A-Fa-f]*\)-$\([0-9A-Fa-f]*\).*/\2/')

    local start_dec=$((16#$start_addr))
    local end_dec=$((16#$end_addr))
    if [ "$end_dec" -lt "$start_dec" ] || [ "$end_dec" -lt $((16#0801)) ] || [ "$end_dec" -ge $((16#C000)) ]; then
        echo "FAIL (invalid Test Code BRK address: \$$end_addr)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local load_lo load_hi load_addr offset brk_byte
    load_lo=$(od -An -N1 -tx1 -v "$prg_file" | tr -d ' \n')
    load_hi=$(od -An -j1 -N1 -tx1 -v "$prg_file" | tr -d ' \n')
    load_addr=$((16#$load_hi$load_lo))
    offset=$((end_dec - load_addr + 2))
    if [ "$offset" -lt 2 ]; then
        echo "FAIL (Test Code BRK address precedes PRG load address: \$$end_addr)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    brk_byte=$(dd if="$prg_file" bs=1 skip="$offset" count=1 2>/dev/null | od -An -tx1 -v | tr -d ' \n')
    if [ "$brk_byte" != "00" ]; then
        echo "FAIL (Test Code stop address is not BRK: \$$end_addr)"
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
            "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
            -autostart "$prg_file" -moncommands "$mon_file" \
            -limitcycles "$cycles" +sound -sounddev dummy \
            +remotemonitor +binarymonitor > /dev/null 2>&1
    }

    run_vice_once "$tty_log"

    local result
    result=$(grep -a "^>C:0" "$tty_log")
    if [ -z "$result" ]; then
        run_vice_once "$tty_log"
        result=$(grep -a "^>C:0" "$tty_log")
    fi

    # Count $01 bytes (passes) in result
    local pass_count
    pass_count=$(echo "$result" | grep -o " 01" | wc -l | tr -d ' ')

    if [ "$pass_count" -ge "$expected_count" ]; then
        echo "PASS ($pass_count/$expected_count tests)"
        PASS=$((PASS + 1))
    else
        echo "FAIL ($pass_count/$expected_count tests passed)"
        echo "    Raw: $result"
        if [ -z "$result" ]; then
            echo "    Log tail:"
            tail -40 "$tty_log" | sed 's/^/    /'
        fi
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
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" -define C64_UNIT_TEST "$src" -showmem -vicesymbols -o "${src%.s}.prg" 2>&1)

    if ! echo "$asm_output" | grep -q "0 failed"; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local sym_file="${src%.s}.vs"
    local mon_file
    local log_file
    mon_file=$(mktemp -t "test_${name}_mon")
    log_file=$(mktemp -t "test_${name}_log")

    lookup_label() {
        local label="$1"
        awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$sym_file"
    }

    local stages=(init none invalid bump hit miss pickup death levelup spell spell_fail hunger_warn hunger_faint update_gateoff)

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
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
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
    ("hunger_warn", ["00","08","00","02","41","27","00"], "0F", "08"),
    ("hunger_faint",["00","05","00","01","41","3A","00"], "0F", "09"),
    ("update_gateoff",["00","04","00","00","00","08","00"], "0F", "FF"),
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

run_scripted_spell_cast_smoke() {
    local name="scripted_spell_cast_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols -define C64_TEST_SCRIPTED_SPELL -o out/moria_spell_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_spell_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_spell_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c64_test_spell_fail_no_cast_sym"
        "c64_test_spell_fail_level_sym"
        "c64_test_spell_fail_known_sym"
        "c64_test_spell_fail_validate_sym"
        "c64_test_spell_fail_roll_sym"
        "c64_test_spell_fail_cancel_sym"
        "c64_test_spell_fail_input_sym"
    )
    local -a fail_addrs=()
    local label addr

    pass_addr=$(awk '/\.c64_test_spell_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc
    local pass_hit
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -autostart "$scripted_d64" -moncommands "$mon_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qiE "Stop on  exec $(echo "$addr" | tr '[:upper:]' '[:lower:]')" "$tty_log" || \
           grep -qi "^BREAK: .*C:\$${addr}" "$tty_log"; then
            echo "FAIL (scripted spell hit ${fail_labels[$idx]})"
            echo "    Log: $tty_log"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (scripted spell flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (scripted spell flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach scripted spell pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_book_overlay_smoke() {
    local name="scripted_book_overlay_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_BOOK_OVERLAY \
            -o out/moria_book_overlay_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_book_overlay_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_book_overlay_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c64_test_book_overlay_fail_sym"
        "c64_test_book_overlay_fail_input_sym"
    )
    local -a fail_addrs=()
    local label addr

    pass_addr=$(awk '/\.c64_test_book_overlay_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted book overlay pass symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc
    local pass_hit
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -autostart "$scripted_d64" -moncommands "$mon_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qiE "Stop on  exec $(echo "$addr" | tr '[:upper:]' '[:lower:]')" "$tty_log" || \
           grep -qi "^BREAK: .*C:\$${addr}" "$tty_log"; then
            echo "FAIL (book overlay hit ${fail_labels[$idx]})"
            echo "    Log: $tty_log"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (book overlay flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (book overlay flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach scripted book overlay pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_scroll_selector_smoke() {
    local name="scripted_scroll_selector_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SCROLL_SELECTOR \
            -o out/moria_scroll_selector_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_scroll_selector_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_scroll_selector_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c64_test_scroll_selector_fail_sym"
        "c64_test_scroll_selector_fail_input_sym"
    )
    local -a fail_addrs=()
    local label addr

    pass_addr=$(awk '/\.c64_test_scroll_selector_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted scroll selector pass symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc
    local pass_hit
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -autostart "$scripted_d64" -moncommands "$mon_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qiE "Stop on  exec $(echo "$addr" | tr '[:upper:]' '[:lower:]')" "$tty_log" || \
           grep -qi "^BREAK: .*C:\$${addr}" "$tty_log"; then
            echo "FAIL (scroll selector hit ${fail_labels[$idx]})"
            echo "    Log: $tty_log"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (scroll selector flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (scroll selector flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach scripted scroll selector pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_spell_list_overlay_smoke() {
    local name="scripted_spell_list_overlay_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY \
            -o out/moria_spell_list_overlay_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_spell_list_overlay_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_spell_list_overlay_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c64_test_spell_list_overlay_fail_sym"
        "c64_test_spell_list_overlay_fail_input_sym"
    )
    local -a fail_addrs=()
    local label addr

    pass_addr=$(awk '/\.c64_test_spell_list_overlay_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell list overlay pass symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc
    local pass_hit
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -autostart "$scripted_d64" -moncommands "$mon_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qiE "Stop on  exec $(echo "$addr" | tr '[:upper:]' '[:lower:]')" "$tty_log" || \
           grep -qi "^BREAK: .*C:\$${addr}" "$tty_log"; then
            echo "FAIL (spell list overlay hit ${fail_labels[$idx]})"
            echo "    Log: $tty_log"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (spell list overlay flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (spell list overlay flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach scripted spell list overlay pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_dungeon_target_spell_smoke() {
    local name="scripted_dungeon_target_spell_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DUNGEON_SPELL \
            -o out/moria_dungeon_spell_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_dungeon_spell_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_dungeon_spell_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c64_test_spell_fail_no_cast_sym"
        "c64_test_spell_fail_level_sym"
        "c64_test_spell_fail_known_sym"
        "c64_test_spell_fail_validate_sym"
        "c64_test_spell_fail_roll_sym"
        "c64_test_spell_fail_cancel_sym"
        "c64_test_spell_fail_input_sym"
    )
    local -a fail_addrs=()
    local label addr

    pass_addr=$(awk '/\.c64_test_spell_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc
    local pass_hit
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -reu -reusize 512 \
        -autostart "$scripted_d64" -moncommands "$mon_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qiE "Stop on  exec $(echo "$addr" | tr '[:upper:]' '[:lower:]')" "$tty_log" || \
           grep -qi "^BREAK: .*C:\$${addr}" "$tty_log"; then
            echo "FAIL (scripted dungeon spell hit ${fail_labels[$idx]})"
            echo "    Log: $tty_log"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (scripted dungeon spell flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (scripted dungeon spell flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach scripted dungeon spell pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_detect_evil_smoke() {
    local name="scripted_detect_evil_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT \
            -o out/moria_detect_evil_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_detect_evil_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_detect_evil_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c64_test_spell_fail_no_cast_sym"
        "c64_test_spell_fail_level_sym"
        "c64_test_spell_fail_known_sym"
        "c64_test_spell_fail_validate_sym"
        "c64_test_spell_fail_roll_sym"
        "c64_test_spell_fail_cancel_sym"
        "c64_test_spell_fail_input_sym"
    )
    local -a fail_addrs=()
    local label addr

    pass_addr=$(awk '/\.c64_test_spell_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc
    local pass_hit
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -autostart "$scripted_d64" -moncommands "$mon_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qiE "Stop on  exec $(echo "$addr" | tr '[:upper:]' '[:lower:]')" "$tty_log" || \
           grep -qi "^BREAK: .*C:\$${addr}" "$tty_log"; then
            echo "FAIL (scripted detect evil hit ${fail_labels[$idx]})"
            echo "    Log: $tty_log"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (scripted detect evil jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (scripted detect evil timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach scripted detect evil pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_dungeon_ascent_product_smoke() {
    local name="dungeon_ascent_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT \
            -o out/moria_dungeon_ascent_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_dungeon_ascent_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_dungeon_ascent_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.tramp_store_restock_all$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_dungeon_ascent_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing dungeon-ascent smoke symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc fail_lc swap_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    fail_lc=$(echo "$fail_addr" | tr '[:upper:]' '[:lower:]')
    swap_lc=$(echo "$swap_addr" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${fail_addr}"
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -8 "$scripted_d64" -autostart "$scripted_d64" \
        -moncommands "$mon_file" \
        -limitcycles 900000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${fail_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${fail_addr}" "$tty_log"; then
        echo "FAIL (scripted input exhausted before ascent)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (dungeon ascent flow jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (dungeon ascent flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach dungeon-ascent pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_disk_setup_product_smoke() {
    local name="disk_setup_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT \
            -o out/moria_disk_setup_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_disk_setup_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_disk_setup_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="out/moria_disk_setup_save.d64"
    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c64_test_after_disk_setup_product$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing disk-setup smoke symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --save-d64 "$save_d64" \
            --enable-drive9-bus \
            --main-vs "$main_vs" \
            --pass-symbol ".c64_test_after_disk_setup_product" \
            --expect-byte-symbol ".disk_setup_done=2" \
            --expect-byte-symbol ".disk_status=0" \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ'; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL (save marker not present as SEQ)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
        TOTAL=$((TOTAL + 1))
        return
    fi
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_save_write_product_smoke() {
    local name="save_write_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT \
            -o out/moria_save_write_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_save_write_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_save_write_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="out/THE.GAME"
    local marker_blob="out/MORIA8.ID"
    local save_d64="out/moria_save_write_save.d64"
    if ! python3 tests/make_load_resume_save64.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL (save generation error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_dir_type_offset=$(((357 + 1) * 256 + 2 + 32))
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$save_dir_type_offset" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (savefile directory patch error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr fail_addr prompt_addr
    pass_addr=$(awk '/\.c64_test_after_save_restart_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_save_write_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    prompt_addr=$(awk '/\.disk_prompt_game_required_error_shown$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ] || [ -z "${prompt_addr:-}" ]; then
        echo "FAIL (missing save-write smoke symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc fail_lc prompt_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    fail_lc=$(echo "$fail_addr" | tr '[:upper:]' '[:lower:]')
    prompt_lc=$(echo "$prompt_addr" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${fail_addr}"
        echo "break \$${prompt_addr}"
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -drive9type 1541 -8 "$scripted_d64" -attach9rw -9 "$save_d64" -autostart "$scripted_d64" \
        -moncommands "$mon_file" \
        -limitcycles 900000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL (save file not present as SEQ)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${prompt_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${prompt_addr}" "$tty_log"; then
        echo "FAIL (unexpected post-save program-disk prompt in dual-drive mode)"
        tail -60 "$tty_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${fail_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${fail_addr}" "$tty_log"; then
        echo "FAIL (scripted input exhausted)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (save-write flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (save-write flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach save-write pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_save_media_fail_product_smoke() {
    local name="save_media_fail_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT \
            -o out/moria_save_media_fail_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_save_media_fail_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_save_media_fail_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="out/THE.GAME"
    local marker_blob="out/MORIA8.ID"
    local save_d64="out/moria_save_media_fail_save.d64"
    if ! python3 tests/make_load_resume_save64.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL (save generation error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local dir_type_offset0=$(((357 + 1) * 256 + 2))
    local dir_type_offset1=$((dir_type_offset0 + 32))
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (marker directory patch error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset1" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (savefile directory patch error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.c64_test_after_save_media_fail$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.save_select_output_name_c64$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing save-media-fail smoke symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --save-d64 "$save_d64" \
            --enable-drive9-bus \
            --main-vs "$main_vs" \
            --start-symbol ".c64_test_save_media_fail_wait_for_harness" \
            --resume-symbol ".c64_test_save_media_fail_before_save" \
            --pass-symbol ".c64_test_after_save_media_fail" \
            --fail-symbol ".c64_test_save_media_fail_unexpected_return" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_disk_setup_single_drive_return_product_smoke() {
    local name="disk_setup_single_drive_return_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT \
            -o out/moria_disk_setup_single_drive_return.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_disk_setup_single_drive_return.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_disk_setup_single_drive_return.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="out/moria_disk_setup_single_drive_return_save.d64"
    local program_d64="out/moria_disk_setup_single_drive_return_program.d64"
    local marker_blob="out/MORIA8.ID"
    rm -f "$save_d64" "$program_d64"
    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "moria8.id,s" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$scripted_d64" "$program_d64"

    local main_vs="out/main.vs"
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "$main_vs" \
            --start-symbol ".c64_test_disk_setup_single_drive_return_wait_for_harness" \
            --resume-symbol ".c64_test_disk_setup_single_drive_return_before_disk_setup" \
            --pass-symbol ".c64_test_after_disk_setup_single_drive_return" \
            --swap-symbol ".disk_prompt_game_required_error_shown" \
            --swap-attach8-d64 "$program_d64" \
            --attach8-at-start-d64 "$save_d64" \
            --expect-screen-symbol ".title_menu_str:18:7" \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ'; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL (save marker not present as SEQ)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_load_resume_product_smoke() {
    local name="load_resume_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT \
            -o out/moria_load_resume_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_load_resume_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_load_resume_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="out/THE.GAME"
    local marker_blob="out/MORIA8.ID"
    local save_d64="out/moria_load_resume_save.d64"
    if ! python3 tests/make_load_resume_save64.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL (save generation error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local dir_type_offset0=$(((357 + 1) * 256 + 2))
    local dir_type_offset1=$((dir_type_offset0 + 32))
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (marker directory patch error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset1" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (savefile directory patch error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr fail_addr prompt_fail_addr
    pass_addr=$(awk '/\.c64_test_after_load_resume_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_load_resume_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    prompt_fail_addr=$(awk '/\.disk_prompt_game_required_error_shown$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ] || [ -z "${prompt_fail_addr:-}" ]; then
        echo "FAIL (missing load-resume smoke symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc fail_lc prompt_fail_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    fail_lc=$(echo "$fail_addr" | tr '[:upper:]' '[:lower:]')
    prompt_fail_lc=$(echo "$prompt_fail_addr" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${fail_addr}"
        echo "break \$${prompt_fail_addr}"
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -drive9type 1541 -8 "$scripted_d64" -attach9rw -9 "$save_d64" -autostart "$scripted_d64" \
        -moncommands "$mon_file" \
        -limitcycles 900000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${fail_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${fail_addr}" "$tty_log"; then
        echo "FAIL (scripted input exhausted)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${prompt_fail_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${prompt_fail_addr}" "$tty_log"; then
        echo "FAIL (program-media verify prompt shown)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (load-resume flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (load-resume flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach load-resume pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_single_drive_load_return_product_smoke() {
    local name="single_drive_load_return_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT \
            -o out/moria_single_drive_load_return_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_single_drive_load_return_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_single_drive_load_return_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="out/THE.GAME"
    local marker_blob="out/MORIA8.ID"
    local save_d64="out/moria_single_drive_load_return_save.d64"
    if ! python3 tests/make_load_resume_save64.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL (save generation error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$C1541" -attach "$scripted_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >>"$build_log" 2>&1; then
        echo "FAIL (combined single-drive disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "out/main.vs" \
            --start-symbol ".c64_test_single_drive_load_return_wait_for_harness" \
            --resume-symbol ".c64_test_single_drive_load_return_resume_low" \
            --pass-symbol ".c64_test_single_drive_load_return_loaded_low" \
            --fail-symbol ".c64_test_single_drive_load_return_load_fail" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_load_then_save_new_empty_product_smoke() {
    local name="load_then_save_new_empty_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT \
            -o out/moria_load_then_save_new_empty.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_load_then_save_new_empty.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_load_then_save_new_empty.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="out/THE.GAME"
    local marker_blob="out/MORIA8.ID"
    local load_save_d64="/tmp/moria_load_then_save_new_empty_load_$$.d64"
    local new_save_d64="/tmp/moria_load_then_save_new_empty_$$.d64"
    local swap_program_d64="/tmp/moria_load_then_save_new_empty_program_$$.d64"
    if ! python3 tests/make_load_resume_save64.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL (save generation error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$load_save_d64" "$new_save_d64" "$swap_program_d64"
    if ! "$C1541" -format "moria8 load,m8" d64 "$load_save_d64" \
            -attach "$load_save_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >>"$build_log" 2>&1; then
        echo "FAIL (load save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$C1541" -format "moria8 save,m8" d64 "$new_save_d64" >>"$build_log" 2>&1; then
        echo "FAIL (new save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! cp "$scripted_d64" "$swap_program_d64"; then
        echo "FAIL (program disk swap copy error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "out/main.vs" \
            --start-symbol ".c64_test_load_then_save_new_empty_wait_for_harness" \
            --resume-symbol ".c64_test_load_then_save_new_empty_resume_low" \
            --attach8-at-start-d64 "$load_save_d64" \
            --swap-symbol ".c64_test_load_then_save_new_empty_before_save" \
            --swap-attach8-d64 "$new_save_d64" \
            --swap2-symbol ".disk_prompt_game_required_error_shown" \
            --swap2-attach8-d64 "$swap_program_d64" \
            --pass-symbol ".c64_test_load_then_save_new_empty_done" \
            --fail-symbol ".c64_test_load_then_save_new_empty_fail" \
            --limitcycles 900000000 \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$new_save_d64" -list 2>&1); then
            echo "FAIL (new save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ' && \
                echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL (new save disk missing marker or save file)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_single_drive_save_wrong_media_product_smoke() {
    local name="single_drive_save_wrong_media_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT \
            -o out/moria_single_drive_save_wrong_media_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_single_drive_save_wrong_media_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_single_drive_save_wrong_media_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "out/main.vs" \
            --start-symbol ".c64_test_single_drive_save_wrong_media_wait_for_harness" \
            --resume-symbol ".c64_test_single_drive_save_wrong_media_before_save" \
            --pass-symbol ".title_menu_loop" \
            --fail-symbol ".c64_test_single_drive_save_wrong_media_unexpected_return" \
            --pass-on-script-exhausted \
            --expect-byte-symbol ".disk_test_program_warning_seen=1" \
            --expect-screen-symbol ".uds_insert_one_drive_str:3:8" \
            --expect-screen-symbol ".press_key_str:6:10" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_single_drive_load_wrong_media_product_smoke() {
    local name="single_drive_load_wrong_media_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT \
            -o out/moria_single_drive_load_wrong_media_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_single_drive_load_wrong_media_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_single_drive_load_wrong_media_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "out/main.vs" \
            --start-symbol ".c64_test_single_drive_load_wrong_media_wait_for_harness" \
            --resume-symbol ".c64_test_single_drive_load_wrong_media_before_load" \
            --pass-symbol ".title_menu_loop" \
            --pass-on-script-exhausted \
            --expect-byte-symbol ".disk_test_program_warning_seen=1" \
            --expect-screen-symbol ".uds_program_disk_str:3:8" \
            --expect-screen-symbol ".press_key_str:5:10" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_single_drive_load_corrupt_product_smoke() {
    local name="single_drive_load_corrupt_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT \
            -o out/moria_single_drive_load_corrupt_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_single_drive_load_corrupt_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_single_drive_load_corrupt_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="out/THE.GAME"
    local marker_blob="out/MORIA8.ID"
    local save_d64="out/moria_single_drive_load_corrupt_save.d64"
    local program_d64="out/moria_single_drive_load_corrupt_program.d64"
    if ! python3 ../c128/tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (c128 save generation error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    printf 'M8SAVE' > "$marker_blob"

    rm -f "$save_d64" "$program_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "moria8.id,s" \
            -write "$save_blob" "the.game,s" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$scripted_d64" "$program_d64"

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "out/main.vs" \
            --start-symbol ".c64_test_single_drive_load_corrupt_wait_for_harness" \
            --resume-symbol ".c64_test_single_drive_load_corrupt_before_load" \
            --pass-symbol ".title_menu_loop" \
            --fail-symbol ".main_loop" \
            --swap-symbol ".disk_prompt_game_required_error_shown" \
            --swap-attach8-d64 "$program_d64" \
            --attach8-at-start-d64 "$save_d64" \
            --pass-on-script-exhausted \
            --expect-screen-symbol ".title_menu_str:18:7" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_single_drive_fresh_save_product_smoke() {
    local name="single_drive_fresh_save_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT \
            -o out/moria_single_drive_fresh_save_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_single_drive_fresh_save_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_single_drive_fresh_save_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="/tmp/moria_single_drive_fresh_save_$$.d64"
    local swap_program_d64="/tmp/moria_single_drive_fresh_program_$$.d64"
    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! cp "$scripted_d64" "$swap_program_d64"; then
        echo "FAIL (program disk swap copy error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local start_addr resume_addr swap_addr pass_addr fail_addr
    start_addr=$(awk '/\.c64_test_single_drive_fresh_save_wait_for_harness$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    resume_addr=$(awk '/\.c64_test_single_drive_fresh_save_before_save$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    swap_addr=$(awk '/\.disk_prompt_game_required_error_shown$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    pass_addr=$(awk '/\.c64_test_after_save_restart_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_single_drive_fresh_save_unexpected_return$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${start_addr:-}" ] || [ -z "${resume_addr:-}" ] || [ -z "${swap_addr:-}" ] || \
            [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing fresh-save smoke symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "$main_vs" \
            --start-symbol ".c64_test_single_drive_fresh_save_wait_for_harness" \
            --resume-symbol ".c64_test_single_drive_fresh_save_before_save" \
            --attach8-at-start-d64 "$save_d64" \
            --swap-symbol ".disk_prompt_game_required_error_shown" \
            --swap-attach8-d64 "$swap_program_d64" \
            --pass-symbol ".c64_test_after_save_restart_start" \
            --fail-symbol ".c64_test_single_drive_fresh_save_unexpected_return" \
            --limitcycles 900000000 \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ' && \
                echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL (fresh save disk missing marker or save file)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_load_missing_savefile_product_smoke() {
    local name="load_missing_savefile_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p out

    if ! make -s -C .. out/c64/boot.prg out/c64/bootart64.prg out/c64/title \
            out/c64/monster.db.1 out/c64/monster.db.2 out/c64/monster.db.3 out/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT \
            -o out/moria_load_missing_save_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="out/moria_load_missing_save_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../out/c64/boot.prg "moria8" \
            -write ../out/c64/boot.prg "boot64" \
            -write ../out/c64/bootart64.prg "bootart64" \
            -write out/moria_load_missing_save_smoke.prg "moria64" \
            -write out/64.bank "64.bank" \
            -write ../out/c64/title "t64" \
            -write ../out/c64/monster.db.1 "monster.db.1" \
            -write ../out/c64/monster.db.2 "monster.db.2" \
            -write ../out/c64/monster.db.3 "monster.db.3" \
            -write ../out/c64/monster.db.4 "monster.db.4" \
            -write out/ovl.start "64.start" \
            -write out/ovl.town "64.town" \
            -write out/ovl.death "64.death" \
            -write out/ovl.gen "64.gen" \
            -write out/ovl.help "64.help" \
            -write out/ovl.ui "64.ui" \
            -write out/ovl.items "64.items" \
            -write out/ovl.spell "64.spell" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local marker_blob="out/MORIA8.ID"
    local save_d64="out/moria_load_missing_save.d64"
    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "MORIA8.ID" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local dir_type_offset=$(((357 + 1) * 256 + 2))
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (marker directory patch error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="out/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.c64_test_after_load_missing_save_return$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_load_missing_save_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing load-missing-save smoke symbol in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local pass_lc fail_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    fail_lc=$(echo "$fail_addr" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${fail_addr}"
        echo "break \$${pass_addr}"
        echo "g"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
        -drive9type 1541 -8 "$scripted_d64" -attach9rw -9 "$save_d64" -autostart "$scripted_d64" \
        -moncommands "$mon_file" \
        -limitcycles 900000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if grep -qiE "Stop on  exec ${pass_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$tty_log"; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${fail_lc}" "$tty_log" || grep -qi "^BREAK: .*C:\$${fail_addr}" "$tty_log"; then
        echo "FAIL (scripted input exhausted before single-prompt return)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (load-missing-save flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (load-missing-save flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not return to title input after missing save)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

echo "=== Moria Phase 1 Tests ==="
echo ""

# Build main program first (compile-time asserts)
echo -n "  main.s assembly: "
cd "$RUN_TESTS64_DIR"
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

check_static_contract "wizard_heal_contract" "../common/wizard.s" \
    "wizard_cmd_heal_cure:|||lda player_data + PL_MAX_MANA|||sta player_data + PL_MANA|||sta zp_player_mp|||sta zp_player_mmp"
check_static_contract "wizard_footer_full_copy_contract" "../common/wizard.s" \
    "wiz_footer_str:|||.text \"Q to cancel\""
check_static_contract "wizard_cancel_text_contract" "../common/wizard.s" \
    "wiz_row4_str:|||.text \"Q to cancel\""
check_static_contract "wizard_menu_aligned_rows_contract" "../common/wizard.s" \
    "wiz_row1_str:|||.text \"L jump    A reveal    H heal\"|||wiz_row2_str:|||.text \"I ident   X level     G item\"|||wiz_row3_str:|||.text \"S summon  T tele      W wall\""
check_static_contract "wizard_item_prompt_range_contract" "../common/wizard.s" \
    "wiz_item_prompt_str:|||.text \"ITEM 0-95: \""
check_static_contract "wizard_bad_prompt_cleanup_contract" "../common/wizard.s" \
    "wizard_prompt_bad_value:|||jsr msg_print|||jmp wizard_prompt_clear_digits|||wizard_prompt_two_digit:|||jsr wizard_prompt_bad_value|||jmp !wiz_num_loop-"
check_static_contract "c64_disk_prompt_dismiss_clears_full_modal_contract" "../common/disk_swap.s" \
    "disk_prompt:|||jsr hal_input_get_key|||jsr ui_clear_full_screen_safe|||jsr msg_init|||jsr hal_storage_init_selected_drive"
check_static_contract "disk_setup_insert_dismiss_clears_modal_contract" "../common/ui_disk_setup.s" \
    "uds_show_insert_prompt:|||jsr input_get_modal_dismiss_key|||lda #DISK_UI_RES_OK|||sta disk_ui_result|||jsr uds_clear_after_modal"
check_static_contract "load_resume_suppresses_tier_loading_message_contract" "../common/game_loop.s" \
    "load_resume_game:|||jsr tier_invalidate_state|||jsr tier_restore_after_overlay"
check_static_contract "learn_spell_followup_contract" "../common/player_gain_spell_impl.s" \
    "item_gain_spell:|||jsr input_prepare_modal_dismiss_key|||jsr spell_list_display|||jsr hal_input_get_key|||jsr pm_pick_visible_spell"
check_static_contract "book_prompt_fresh_key_contract" "../common/player_item_select.s" \
    "piw_select_filtered_inv:|||jsr piw_prompt_filtered_inv|||jsr input_prepare_followup_key|||jsr hal_input_get_key|||piw_select_filtered_inv_key:|||jsr piw_pick_filtered_inv_key"
check_static_contract "c64_wait_release_physical_key_contract" "input.s" \
    "input_wait_release:|||!iwr_wait:|||lda KBDBUF_COUNT|||bne !iwr_drain-|||jsr input_run_key_held|||bne !iwr_wait-|||lda KBDBUF_COUNT"
check_static_contract "c64_charset_switch_locked_before_irq_input_contract" "input.s" \
    "input_get_key:|||lda #BANK_NO_BASIC|||sta \$01|||jsr c64_install_ram_irq_vectors|||jsr input_lock_charset_switch|||cli|||!igk_poll:"
check_static_contract "c64_charset_switch_locked_before_irq_release_contract" "input.s" \
    "input_wait_release:|||lda #BANK_NO_BASIC|||sta \$01|||jsr c64_install_ram_irq_vectors|||jsr input_lock_charset_switch|||cli|||!iwr_drain:"
check_static_contract "c64_input_restores_bank_before_irq_contract" "input.s" \
    "input_get_key:|||jsr KERNAL_GETIN|||sta igk_key|||sei|||pla|||sta \$01|||jsr c64_install_ram_irq_vectors|||plp|||lda igk_key"
check_static_contract "inventory_overlay_fresh_key_contract" "../common/player_items.s" \
    "show_inv_and_select:|||jsr input_prepare_selectable_overlay_key|||jsr tramp_ui_inv_select_display|||jsr input_get_followup_key"
check_static_contract "inventory_overlay_items_reload_contract" "../common/player_items.s" \
    "show_inv_and_select:|||lda piw_return_overlay|||bne !sias_have_return_overlay+|||tsx|||lda \$0102,x|||cmp #\$e0|||!sias_check_outer_return:|||lda \$0104,x|||cmp #\$e0|||!sias_return_overlay:|||lda current_overlay|||cmp #OVL_ITEMS|||!sias_store_return_overlay:|||sta piw_return_overlay|||jsr ui_view_restore_modal_overlay|||lda #OVL_NONE|||sta piw_return_overlay|||txa|||beq !sias_no_overlay_reload+|||jsr overlay_load|||brk|||sei|||jsr hal_irq_install_runtime|||lda #BANK_NO_KERNAL|||sta hal_memory_cpu_port"
check_static_contract "item_action_inventory_overlay_hint_contract" "../common/item_actions_overlay.s" \
    "item_action_select_filtered_inv:|||jsr item_action_get_key|||cmp #\$3f|||lda #OVL_ITEMS|||sta piw_return_overlay|||jmp piw_select_filtered_inv_key"
check_static_contract "spell_recharge_inventory_overlay_hint_contract" "../common/player_magic_execute_overlay.s" \
    "pmx_pick_recharge_item:|||jsr hal_input_get_key|||cmp #\$3f|||lda #OVL_SPELL|||sta piw_return_overlay|||jmp piw_select_filtered_inv_key"
check_static_contract "identify_scroll_resident_completion_contract" "../common/item_actions_overlay.s" \
    "irs_effect_identify:|||jmp eff_identify_scroll_resident"
check_static_contract "itemdesc_armor_brackets_screen_code_contract" "../common/item_desc_banked.s" \
    "!idps_armor:|||lda #\$1b                    // '[' screen code|||lda #\$1d                    // ']' screen code|||!idps_ring:|||lda #\$1b                    // '[' screen code|||lda #\$1d                    // ']' screen code"
check_static_contract "save_split_item_stats_contract" "../common/save.s" \
    "save_block_table_inventory_current:|||:save_block_desc(inv_p1, TOTAL_INV_SLOTS)|||:save_block_desc(inv_to_hit, TOTAL_INV_SLOTS)|||:save_block_desc(inv_to_dam, TOTAL_INV_SLOTS)|||:save_block_desc(inv_to_ac, TOTAL_INV_SLOTS)|||save_block_table_inventory_legacy:|||:save_block_desc(inv_p1, LEGACY_TOTAL_INV_SLOTS)|||:save_block_desc(si_p1, STORE_TOTAL_SLOTS)|||:save_block_desc(si_to_hit, STORE_TOTAL_SLOTS)|||:save_block_desc(si_to_dam, STORE_TOTAL_SLOTS)|||:save_block_desc(si_to_ac, STORE_TOTAL_SLOTS)|||save_block_table_floor_items_direct:|||:save_block_desc(fi_qty, MAX_FLOOR_ITEMS)|||:save_block_desc(fi_to_hit, MAX_FLOOR_ITEMS)|||:save_block_desc(fi_to_dam, MAX_FLOOR_ITEMS)|||:save_block_desc(fi_to_ac, MAX_FLOOR_ITEMS)|||load_read_floor_block_table:|||lda load_floor_item_count|||jsr load_read_block|||save_write_floor_items:|||lda #<save_block_table_floor_items_direct|||jsr save_write_block_table|||lda #<SAVE_BLOCK_FLOOR_ITEMS_STAT_TABLE|||jsr save_write_block_table|||load_read_floor_items:|||lda #<save_block_table_floor_items_direct|||jsr load_read_floor_block_table|||lda #<SAVE_BLOCK_FLOOR_ITEMS_STAT_TABLE|||jsr load_read_floor_block_table"
check_static_contract "item_action_messages_stat_desc_contract" "../common/item.s" \
    "Build message: \"You picked up a <name>.\"|||lda fi_add_id|||jsr item_append_desc|||Build message: \"You drop a <name>.\"|||lda fi_add_id|||jsr item_append_desc|||item_append_desc:|||jsr item_append_name|||and #IF_IDENTIFIED"
check_static_contract "equip_action_messages_stat_desc_contract" "../common/player_item_commands.s" \
    "Build message: \"YOU ARE WIELDING A <name>.\"|||lda piw_item_id|||jsr item_append_desc|||Build message: \"YOU TAKE OFF THE <name>.\"|||lda piw_item_id|||jsr item_append_desc"
check_static_contract "throw_action_messages_stat_desc_contract" "../common/throw.s" \
    "tw_msg_item_prefix:|||jsr tw_stage_saved_item_fields|||lda tw_item_id|||jsr item_append_desc|||tw_stage_saved_item_fields:|||lda tw_save_to_hit|||sta fi_add_to_hit|||lda tw_save_to_dam|||sta fi_add_to_dam|||lda tw_save_flags|||sta fi_add_flags"
check_static_contract "equip_overlay_fresh_key_contract" "../common/player_items.s" \
    "show_equip_and_select:|||jsr input_prepare_selectable_overlay_key|||jsr tramp_ui_equip_select_display|||jsr input_get_followup_key"
check_static_contract "spell_list_overlay_fresh_key_contract" "../common/player_magic.s" \
    "!pm_psc_show_list:|||jsr input_prepare_selectable_overlay_key|||jsr tramp_spell_list_display|||jsr input_get_followup_key"
check_static_contract "overcast_faint_more_contract" "../common/player_magic.s" \
    "ldx #HSTR_PM_NO_MANA|||jsr huff_print_msg|||jsr msg_show_more|||jsr hal_input_get_key"
check_static_contract "paralysis_final_tick_message_contract" "../common/game_loop.s" \
    "lda zp_eff_paralyze|||beq !not_paralyzed+|||cmp #1|||bne !paralyzed_tick+|||jsr msg_clear|||!paralyzed_tick:|||jsr turn_post_action"
check_static_contract "earthquake_trampoline_no_hidden_kernal_load_contract" "main.s" \
    "tramp_eff_earthquake:|||sei|||lda #BANK_NO_KERNAL|||sta \$01|||jsr eff_earthquake_banked|||rts|||tramp_item_refuel:"
check_static_contract "spell_execute_dedicated_overlay_contract" "main.s" \
    "tramp_spell_execute_selected:|||lda #OVL_SPELL|||jsr overlay_load_no_kernal|||jsr spell_execute_selected|||jmp tramp_sr_epilogue"
check_static_contract "priest_sense_surroundings_dispatch_contract" "../common/player_magic_execute_overlay.s" \
    "ped_tbl_lo:|||.byte <(ped_s20-1), <(PMX_EARTHQUAKE_TARGET-1), <(ped_s22-1), <(ped_s23-1)|||ped_tbl_hi:|||.byte >(ped_s20-1), >(PMX_EARTHQUAKE_TARGET-1), >(ped_s22-1), >(ped_s23-1)|||ped_s22:|||jmp eff_map_area"
check_static_contract "wizard_reveal_uses_spell_overlay_contract" "main.s" \
    "tramp_reveal_floorplan:|||lda #OVL_SPELL|||jsr overlay_load_no_kernal|||jsr eff_reveal_floorplan|||jmp tramp_sr_epilogue"
check_static_contract "c64_game_over_returns_to_title_contract" "main.s" \
    "game_over_prompt:|||lda #OVL_DEATH|||jsr overlay_load|||bcc !overlay_ok+|||jmp title_enter_menu|||!overlay_ok:|||sei|||dec \$01|||jmp game_restart_overlay"
check_static_contract "title_screen_clear_ownership_contract" "../common/title_screen.s" \
    "title_clear_full_screen:|||jsr hal_screen_clear_row|||cmp #SCREEN_ROWS|||title_clear_below_menu:|||lda #TITLE_CLEAR_FIRST_ROW|||sta title_clear_row|||jsr hal_screen_clear_row|||cmp #TITLE_CLEAR_AFTER_LAST_ROW|||title_load_and_draw:|||jsr title_clear_full_screen|||jsr title_render_data|||title_fallback_render:|||jsr title_clear_full_screen"
check_static_contract "c64_title_reentry_uses_owned_clear_contract" "main.s" \
    "title_enter_menu:|||jsr title_clear_full_screen|||jsr title_load_and_draw|||jsr title_clear_below_menu|||jsr msg_init|||jsr title_show_sysinfo|||jsr title_draw_menu"
check_static_contract "modal_restore_uses_safe_full_clear_contract" "../common/ui_restore.s" \
    "ui_view_redraw_gameplay_view:|||jsr ui_reset_message_state|||jsr ui_clear_full_screen_safe|||jsr viewport_update|||jsr render_viewport|||jsr status_draw"
check_static_contract "c64_hidden_kernal_irq_vector_contract" "main.s" \
    "c64_irq_hidden_rom:|||lda \$dc0d|||lda \$dd0d|||lda \$d019|||sta \$d019|||rti|||c64_install_ram_irq_vectors:|||lda #BANK_NO_KERNAL|||sta \$01|||sta \$fffa|||sta \$fffe|||sta \$fffb|||sta \$ffff|||overlay_load_no_kernal:|||pha|||lda #BANK_NO_BASIC|||sta \$01|||cli|||pla|||jsr overlay_load|||sei|||jsr c64_install_ram_irq_vectors|||lda #BANK_NO_KERNAL"
check_static_contract "c64_disk_call_preserves_args_contract" "main.s" \
    "c64_disk_call:|||lda \$01|||sta c64_disk_call_saved_bank|||lda #\$36|||sta \$01|||cli|||pla|||tay|||pla|||tax|||pla|||!cdc_jsr:|||jsr \$ffff"
check_static_contract "c64_game_over_overlay_exit_contract" "main.s" \
    "game_restart_overlay:|||lda #>(title_enter_menu - 1)|||pha|||lda #<(title_enter_menu - 1)|||pha|||jmp platform_runtime_resync_c64"
check_static_contract "c64_save_media_hal_contract" "../common/save.s" \
    "!save_wrong_media:|||jsr hal_storage_save_media_status|||cmp #HAL_STORAGE_STATUS_WRONG_MEDIA|||jsr tramp_disk_prepare_selected|||bcc !save_media_ok+"
check_static_contract "c64_storage_classifier_export_contract" "hal/storage.s" \
    ".label hal_storage_save_media_status = disk_save_media_status"
check_static_contract "c64_storage_diag_export_contract" "hal/storage.s" \
    ".label hal_storage_diag_code = disk_status|||.label hal_storage_diag_device = save_device"
check_static_contract "c64_save_stream_banks_kernal_contract" "../common/save.s" \
    "!save_media_ok:|||lda #BANK_NO_BASIC|||sta hal_memory_cpu_port|||jsr save_select_output_name_c64"
check_static_contract "c64_load_stream_banks_kernal_contract" "../common/save.s" \
    "!load_media_ok:|||lda #BANK_NO_BASIC|||sta hal_memory_cpu_port|||ldx #HSTR_SAVE_LOADING"

# Runtime tests
# Args: name, source, result memory range, expected pass count
run_test "math"   "tests/test_math.s"   "0400 040f" 16
run_test "rng"    "tests/test_rng.s"    "0400 0409" 10
run_test "memory" "tests/test_memory.s" "0400 0402" 3
run_test "config" "tests/test_config.s" "0400 0400" 1
run_test "input"  "tests/test_input.s"  "0400 040d" 14
run_test "main_loop" "tests/test_main_loop.s" "0400 0427" 40 500000000
run_test "turn" "tests/test_turn.s" "0400 0416" 23 500000000
run_test "player" "tests/test_player.s" "0400 0409" 10
run_test "dungeon" "tests/test_dungeon.s" "0400 042a" 43 500000000
run_test "monster" "tests/test_monster.s" "0400 040c" 13 500000000
run_test "monster_ai" "tests/test_monster_ai.s" "0400 0419" 26 500000000
run_test "combat" "tests/test_combat.s" "0400 0427" 40 500000000
run_test "msg_long" "tests/test_msg_long.s" "0400 0400" 1 20000000
run_test "monster_attack" "tests/test_monster_attack.s" "0400 040f" 16 500000000
run_test "effects" "tests/test_effects.s" "0400 0431" 27 1000000000
run_test "effects_magic" "tests/test_effects_magic.s" "0400 0433" 23 1000000000
run_test "cure_light_wounds" "tests/test_cure_light_wounds.s" "0400 0402" 3 500000000
run_test "confusion" "tests/test_confusion.s" "0400 0402" 3 500000000
run_test "lightning_bolt" "tests/test_lightning_bolt.s" "0400 0402" 3 500000000
run_test "frost_bolt" "tests/test_frost_bolt.s" "0400 0402" 3 500000000
run_test "turn_stone_to_mud" "tests/test_turn_stone_to_mud.s" "0400 0402" 3 500000000
run_test "create_food" "tests/test_create_food.s" "0400 0402" 3 500000000
run_test "recharge_item_i" "tests/test_recharge_item_i.s" "0400 0403" 4 500000000
run_test "recharge_item_ii" "tests/test_recharge_item_ii.s" "0400 0403" 4 500000000
run_test "trap_door_destruction" "tests/test_trap_door_destruction.s" "0400 0402" 3 500000000
run_test "sleep_i" "tests/test_sleep_i.s" "0400 0402" 3 500000000
run_test "sleep_ii" "tests/test_sleep_ii.s" "0400 0403" 4 500000000
run_test "sleep_iii" "tests/test_sleep_iii.s" "0400 0402" 3 500000000
run_test "cure_poison" "tests/test_cure_poison.s" "0400 0402" 3 500000000
run_test "fire_bolt" "tests/test_fire_bolt.s" "0400 0402" 3 500000000
run_test "slow_monster" "tests/test_slow_monster.s" "0400 0402" 3 500000000
run_test "polymorph_other" "tests/test_polymorph_other.s" "0400 0402" 3 500000000
run_test "identify_spell" "tests/test_identify_spell.s" "0400 0403" 4 500000000
run_test "teleport_self" "tests/test_teleport_self.s" "0400 0401" 2 500000000
run_test "remove_curse" "tests/test_remove_curse.s" "0400 0402" 3 500000000
run_test "find_hidden_traps_doors" "tests/test_find_hidden_traps_doors.s" "0400 0402" 3 500000000
run_test "stinking_cloud" "tests/test_stinking_cloud.s" "0400 0402" 3 500000000
run_test "frost_ball" "tests/test_frost_ball.s" "0400 0402" 3 500000000
run_test "teleport_other" "tests/test_teleport_other.s" "0400 0402" 3 500000000
run_test "haste_self" "tests/test_haste_self.s" "0400 0402" 3 500000000
run_test "fire_ball" "tests/test_fire_ball.s" "0400 0402" 3 500000000
run_test "word_of_destruction" "tests/test_word_of_destruction.s" "0400 0401" 2 500000000
run_test "light_area" "tests/test_light_area.s" "0400 0401" 2 500000000
run_test "phase_door" "tests/test_phase_door.s" "0400 0402" 3 500000000
run_test "genocide" "tests/test_genocide.s" "0400 0401" 2 500000000
run_test "directional_effects" "tests/test_directional_effects.s" "0400 0403" 4 500000000
run_test "overcast_ordering" "tests/test_overcast_ordering.s" "0400 0400" 1 500000000
run_test "ball_effects" "tests/test_ball_effects.s" "0400 0401" 2 500000000
run_test "utility_effects" "tests/test_utility_effects.s" "0400 0409" 10 500000000
run_test "detect_evil" "tests/test_detect_evil.s" "0400 0402" 3 500000000
run_test "cure_light_wounds_prayer" "tests/test_cure_light_wounds_prayer.s" "0400 0402" 3 500000000
run_test "bless_prayer" "tests/test_bless_prayer.s" "0400 0402" 3 500000000
run_test "remove_fear_prayer" "tests/test_remove_fear_prayer.s" "0400 0402" 3 500000000
run_test "call_light_prayer" "tests/test_call_light_prayer.s" "0400 0401" 2 500000000
run_test "find_traps_prayer" "tests/test_find_traps_prayer.s" "0400 0402" 3 500000000
run_test "detect_doors_stairs_prayer" "tests/test_detect_doors_stairs_prayer.s" "0400 0402" 3 500000000
run_test "slow_poison_prayer" "tests/test_slow_poison_prayer.s" "0400 0402" 3 500000000
run_test "blind_creature_prayer" "tests/test_blind_creature_prayer.s" "0400 0402" 3 500000000
run_test "portal_prayer" "tests/test_portal_prayer.s" "0400 0401" 2 500000000
run_test "cure_medium_wounds_prayer" "tests/test_cure_medium_wounds_prayer.s" "0400 0402" 3 500000000
run_test "cure_serious_wounds_prayer" "tests/test_cure_serious_wounds_prayer.s" "0400 0402" 3 500000000
run_test "sense_invisible_prayer" "tests/test_sense_invisible_prayer.s" "0400 0402" 3 500000000
run_test "protection_from_evil_prayer" "tests/test_protection_from_evil_prayer.s" "0400 0402" 3 500000000
run_test "earthquake_prayer" "tests/test_earthquake_prayer.s" "0400 0402" 3 500000000
run_test "sense_surroundings_prayer" "tests/test_sense_surroundings_prayer.s" "0400 0402" 3 500000000
run_test "cure_critical_wounds_prayer" "tests/test_cure_critical_wounds_prayer.s" "0400 0402" 3 500000000
run_test "turn_undead_prayer" "tests/test_turn_undead_prayer.s" "0400 0402" 3 500000000
run_test "prayer_prayer" "tests/test_prayer_prayer.s" "0400 0402" 3 500000000
run_test "dispel_undead_prayer" "tests/test_dispel_undead_prayer.s" "0400 0402" 3 500000000
run_test "dispel_evil_prayer" "tests/test_dispel_evil_prayer.s" "0400 0402" 3 500000000
run_test "glyph_of_warding_prayer" "tests/test_glyph_of_warding_prayer.s" "0400 0402" 3 500000000
run_test "holy_word_prayer" "tests/test_holy_word_prayer.s" "0400 0401" 2 500000000
run_test "heal_prayer" "tests/test_heal_prayer.s" "0400 0402" 3 500000000
run_test "chant_prayer" "tests/test_chant_prayer.s" "0400 0402" 3 500000000
run_test "sanctuary_prayer" "tests/test_sanctuary_prayer.s" "0400 0403" 4 500000000
run_test "neutralize_poison_prayer" "tests/test_neutralize_poison_prayer.s" "0400 0402" 3 500000000
run_test "create_food_prayer" "tests/test_create_food_prayer.s" "0400 0402" 3 500000000
run_test "remove_curse_prayer" "tests/test_remove_curse_prayer.s" "0400 0402" 3 500000000
run_test "orb_of_draining_prayer" "tests/test_orb_of_draining_prayer.s" "0400 0402" 3 500000000
    run_test "prayer_feedback" "tests/test_prayer_feedback.s" "0400 040c" 13 500000000
run_test "detect_feedback" "tests/test_detect_feedback.s" "0400 0403" 4 500000000
run_test "item" "tests/test_item.s" "0400 042e" 47 1000000000
run_test "item_desc" "tests/test_item_desc.s" "0400 0408" 9 500000000
run_test "item_ui" "tests/test_item_ui.s" "0400 040f" 16 1000000000
run_test "store" "tests/test_store.s" "0400 0428" 41 1000000000
run_test "ui_views" "tests/test_ui_views.s" "0400 0413" 17 500000000
run_test "ui_views_filters" "tests/test_ui_views_filters.s" "0400 0413" 7 500000000
run_test "subsystems" "tests/test_subsystems.s" "0400 0409" 10
run_sound_monitor_test
run_test "save"  "tests/test_save.s"  "0400 0418" 25 1000000000
run_test "score" "tests/test_score.s" "0400 040b" 12 500000000
run_test "wands_staves" "tests/test_wands_staves.s" "0400 0406" 7 100000000
run_test "monster_magic" "tests/test_monster_magic.s" "0400 040a" 11 500000000
run_test "tier" "tests/test_tier.s" "0400 040d" 14 500000000
run_test "disk_swap" "tests/test_disk_swap.s" "0400 040d" 14 500000000
run_test "render" "tests/test_render.s" "0400 040b" 12 500000000
run_test "ranged" "tests/test_ranged.s" "0400 0409" 10 500000000
run_test "ego" "tests/test_ego.s" "0400 0409" 10 500000000
run_test "throw" "tests/test_throw.s" "0400 040a" 11 500000000
run_test "bash" "tests/test_bash.s" "0400 0407" 8 500000000
run_test "tunnel" "tests/test_tunnel.s" "0400 0407" 8 500000000
run_test "background" "tests/test_background.s" "0400 0407" 8
run_suite_function "media_drive8_attach_read_write" run_media_drive8_attach_read_write
run_suite_function "media_drive9_attach_read_write" run_media_drive9_attach_read_write
run_suite_function "media_drive10_11_device_probe" run_media_drive10_11_device_probe
run_suite_function "scripted_spell_cast_smoke" run_scripted_spell_cast_smoke
run_suite_function "scripted_book_overlay_smoke" run_scripted_book_overlay_smoke
run_suite_function "scripted_scroll_selector_smoke" run_scripted_scroll_selector_smoke
run_suite_function "scripted_spell_list_overlay_smoke" run_scripted_spell_list_overlay_smoke
run_suite_function "scripted_dungeon_target_spell_smoke" run_scripted_dungeon_target_spell_smoke
run_suite_function "dungeon_ascent_product_smoke" run_dungeon_ascent_product_smoke
run_suite_function "disk_setup_product_smoke" run_disk_setup_product_smoke
run_suite_function "title_disk_setup_single_drive_returns_program_prompt" run_disk_setup_single_drive_return_product_smoke "disk_setup_single_drive_return_product_smoke"
run_suite_function "load_initialized_save" run_load_resume_product_smoke "load_resume_product_smoke"
run_suite_function "prompt_sequence_no_repeat" run_single_drive_load_return_product_smoke "single_drive_load_return_product_smoke"
run_suite_function "load_then_save_new_empty_disk" run_load_then_save_new_empty_product_smoke "load_then_save_new_empty_product_smoke"
run_suite_function "single_drive_save_program_disk_rejected" run_single_drive_save_wrong_media_product_smoke "single_drive_save_wrong_media_product_smoke" "wrong_media_recovery"
run_suite_function "single_drive_load_program_disk_rejected" run_single_drive_load_wrong_media_product_smoke "single_drive_load_wrong_media_product_smoke" "wrong_media_recovery"
run_suite_function "single_drive_corrupt_save_recovery_requires_program_disk" run_single_drive_load_corrupt_product_smoke "single_drive_load_corrupt_product_smoke" "corrupt_save_file"
run_suite_function "new_save_empty_init_writes" run_single_drive_fresh_save_product_smoke "single_drive_fresh_save_product_smoke"
run_suite_function "load_missing_savefile_product_smoke" run_load_missing_savefile_product_smoke
run_suite_function "save_media_fail_product_smoke" run_save_media_fail_product_smoke
run_suite_function "dual_drive_load_then_save_no_program_prompt" run_save_write_product_smoke "save_existing_overwrite" "save_write_product_smoke"
echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
