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
VICE="x64sc"
C1541="${C1541:-c1541}"
PASS=0
FAIL=0
TOTAL=0

check_static_contract() {
    local name="$1"
    local file="$2"
    local pattern="$3"

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

    echo -n "  $name: "

    # Assemble and capture output
    local asm_output
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" "$src" -showmem -o "${src%.s}.prg" 2>&1)

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
            "$VICE" -warp -config /dev/null -default -console -nativemonitor -autostartprgmode 1 \
            -autostart "${src%.s}.prg" -moncommands "$mon_file" \
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
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" "$src" -showmem -vicesymbols -o "${src%.s}.prg" 2>&1)

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

    local stages=(init none invalid bump hit miss pickup death levelup spell spell_fail hunger_warn hunger_faint)

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
            -write "$marker_blob" "MORIA8.ID" \
            -write "$save_blob" "THE.GAME" >"$build_log" 2>&1; then
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
    pass_addr=$(awk '/\.c64_test_after_save_restart_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_save_write_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing save-write smoke symbols in out/main.vs)"
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
            -write "$marker_blob" "MORIA8.ID" \
            -write "$save_blob" "THE.GAME" >"$build_log" 2>&1; then
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
    pass_addr=$(awk '/\.c64_test_after_save_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.save_select_output_name_c64$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing save-media-fail smoke symbols in out/main.vs)"
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

    local run_log
    run_log=$(mktemp -t "test_${name}_runlog")
    awk 'seen { print } /Monitor playback command: g/ { seen=1 }' "$tty_log" > "$run_log"

    if grep -qiE "Stop on  exec ${fail_lc}" "$run_log" || grep -qi "^BREAK: .*C:\$${fail_addr}" "$run_log"; then
        echo "FAIL (entered overwrite prompt after media failure)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${pass_lc}" "$run_log" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$run_log"; then
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
        echo "FAIL (save-media-fail flow hung or jammed)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "cycle limit reached" "$tty_log"; then
        echo "FAIL (save-media-fail flow timed out)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "FAIL (did not reach save-media-fail pass trap)"
    echo "    Log: $tty_log"
    FAIL=$((FAIL + 1))
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
            -write "$marker_blob" "MORIA8.ID" \
            -write "$save_blob" "THE.GAME" >"$build_log" 2>&1; then
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
    pass_addr=$(awk '/\.c64_test_after_load_resume_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_load_resume_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing load-resume smoke symbols in out/main.vs)"
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
        echo "FAIL (scripted input exhausted)"
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
check_static_contract "c64_disk_prompt_dismiss_clears_full_modal_contract" "../common/disk_swap.s" \
    "disk_prompt:|||jsr input_get_key|||jsr ui_clear_full_screen_safe|||jsr msg_init|||jsr hal_storage_init_selected_drive"
check_static_contract "disk_setup_insert_dismiss_clears_modal_contract" "../common/ui_disk_setup.s" \
    "uds_show_insert_prompt:|||jsr input_get_modal_dismiss_key|||lda #DISK_UI_RES_OK|||sta disk_ui_result|||jsr uds_clear_after_modal"
check_static_contract "load_resume_suppresses_tier_loading_message_contract" "../common/game_loop.s" \
    "load_resume_game:|||jsr tier_invalidate_state|||jsr tier_restore_after_overlay"
check_static_contract "learn_spell_followup_contract" "../common/player_gain_spell_impl.s" \
    "item_gain_spell:|||jsr input_prepare_modal_dismiss_key|||jsr spell_list_display|||jsr input_get_key|||jsr pm_pick_visible_spell"
check_static_contract "book_prompt_fresh_key_contract" "../common/player_magic.s" \
    "pm_select_book:|||jsr piw_prompt_filtered_inv|||jsr input_prepare_modal_dismiss_key|||jsr input_get_key|||jsr piw_pick_filtered_inv_key"
check_static_contract "c64_wait_release_physical_key_contract" "input.s" \
    "input_wait_release:|||!iwr_wait:|||lda KBDBUF_COUNT|||bne !iwr_drain-|||jsr input_run_key_held|||bne !iwr_wait-|||lda KBDBUF_COUNT"
check_static_contract "c64_charset_switch_locked_before_irq_input_contract" "input.s" \
    "input_get_key:|||lda #BANK_NO_BASIC|||sta \$01|||jsr c64_install_ram_irq_vectors|||jsr input_lock_charset_switch|||cli|||!igk_poll:"
check_static_contract "c64_charset_switch_locked_before_irq_release_contract" "input.s" \
    "input_wait_release:|||lda #BANK_NO_BASIC|||sta \$01|||jsr c64_install_ram_irq_vectors|||jsr input_lock_charset_switch|||cli|||!iwr_drain:"
check_static_contract "c64_input_restores_bank_before_irq_contract" "input.s" \
    "input_get_key:|||jsr KERNAL_GETIN|||sta igk_key|||sei|||pla|||sta \$01|||jsr c64_install_ram_irq_vectors|||plp|||lda igk_key"
check_static_contract "inventory_overlay_fresh_key_contract" "../common/player_items.s" \
    "show_inv_and_select:|||jsr input_prepare_modal_dismiss_key|||jsr tramp_ui_inv_select_display|||jsr input_get_key"
check_static_contract "inventory_overlay_items_reload_contract" "../common/player_items.s" \
    "show_inv_and_select:|||lda #OVL_NONE|||sta piw_return_overlay|||tsx|||lda \$0102,x|||cmp #\$e0|||lda current_overlay|||cmp #OVL_ITEMS|||sta piw_return_overlay|||jsr ui_view_restore_modal_overlay|||cmp #OVL_ITEMS|||lda #OVL_ITEMS|||jsr overlay_load|||sei|||jsr c64_install_ram_irq_vectors|||lda #BANK_NO_KERNAL|||sta \$01"
check_static_contract "identify_scroll_resident_completion_contract" "../common/item_actions_overlay.s" \
    "irs_effect_identify:|||jmp eff_identify_scroll_resident"
check_static_contract "itemdesc_armor_brackets_screen_code_contract" "../common/item_desc_banked.s" \
    "!idps_armor:|||lda #\$1b                    // '[' screen code|||lda #\$1d                    // ']' screen code|||!idps_ring:|||lda #\$1b                    // '[' screen code|||lda #\$1d                    // ']' screen code"
check_static_contract "save_split_item_stats_contract" "../common/save.s" \
    ":save_block(inv_p1, TOTAL_INV_SLOTS)|||:save_block(inv_to_hit, TOTAL_INV_SLOTS)|||:save_block(inv_to_dam, TOTAL_INV_SLOTS)|||:save_block(inv_to_ac, TOTAL_INV_SLOTS)|||:save_block(si_p1, STORE_TOTAL_SLOTS)|||:save_block(si_to_hit, STORE_TOTAL_SLOTS)|||:save_block(si_to_dam, STORE_TOTAL_SLOTS)|||:save_block(si_to_ac, STORE_TOTAL_SLOTS)|||:load_block(inv_p1, TOTAL_INV_SLOTS)|||:load_block(inv_to_hit, TOTAL_INV_SLOTS)|||:load_block(inv_to_dam, TOTAL_INV_SLOTS)|||:load_block(inv_to_ac, TOTAL_INV_SLOTS)|||:load_block(si_p1, STORE_TOTAL_SLOTS)|||:load_block(si_to_hit, STORE_TOTAL_SLOTS)|||:load_block(si_to_dam, STORE_TOTAL_SLOTS)|||:load_block(si_to_ac, STORE_TOTAL_SLOTS)|||:save_block(fi_to_hit, MAX_FLOOR_ITEMS)|||:save_block(fi_to_dam, MAX_FLOOR_ITEMS)|||:save_block(fi_to_ac, MAX_FLOOR_ITEMS)|||lda #<fi_to_hit|||jsr load_read_block|||lda #<fi_to_dam|||jsr load_read_block|||lda #<fi_to_ac|||jsr load_read_block"
check_static_contract "item_action_messages_stat_desc_contract" "../common/item.s" \
    "Build message: \"You picked up a <name>.\"|||lda fi_add_id|||jsr item_append_desc|||Build message: \"You drop a <name>.\"|||lda fi_add_id|||jsr item_append_desc|||item_append_desc:|||jsr item_append_name|||and #IF_IDENTIFIED"
check_static_contract "equip_action_messages_stat_desc_contract" "../common/player_item_commands.s" \
    "Build message: \"YOU ARE WIELDING A <name>.\"|||lda piw_item_id|||jsr item_append_desc|||Build message: \"YOU TAKE OFF THE <name>.\"|||lda piw_item_id|||jsr item_append_desc"
check_static_contract "throw_action_messages_stat_desc_contract" "../common/throw.s" \
    "tw_msg_item_prefix:|||jsr tw_stage_saved_item_fields|||lda tw_item_id|||jsr item_append_desc|||tw_stage_saved_item_fields:|||lda tw_save_to_hit|||sta fi_add_to_hit|||lda tw_save_to_dam|||sta fi_add_to_dam|||lda tw_save_flags|||sta fi_add_flags"
check_static_contract "equip_overlay_fresh_key_contract" "../common/player_items.s" \
    "show_equip_and_restore:|||jsr input_prepare_modal_dismiss_key|||jsr tramp_ui_equip_display|||jsr input_get_modal_dismiss_key"
check_static_contract "spell_list_overlay_fresh_key_contract" "../common/player_magic.s" \
    "!pm_psc_show_list:|||jsr input_prepare_modal_dismiss_key|||jsr tramp_spell_list_display|||jsr input_get_key"
check_static_contract "overcast_faint_more_contract" "../common/player_magic.s" \
    "ldx #HSTR_PM_NO_MANA|||jsr huff_print_msg|||jsr msg_show_more|||jsr input_get_key"
check_static_contract "paralysis_final_tick_message_contract" "../common/game_loop.s" \
    "lda zp_eff_paralyze|||beq !not_paralyzed+|||cmp #1|||bne !paralyzed_tick+|||jsr msg_clear|||!paralyzed_tick:|||jsr turn_post_action"
check_static_contract "earthquake_trampoline_no_hidden_kernal_load_contract" "main.s" \
    "tramp_eff_earthquake:|||sei|||lda #BANK_NO_KERNAL|||sta \$01|||jsr eff_earthquake_banked|||rts|||tramp_item_refuel:"
check_static_contract "spell_execute_dedicated_overlay_contract" "main.s" \
    "tramp_spell_execute_selected:|||lda #OVL_SPELL|||jsr overlay_load_no_kernal|||jsr spell_execute_selected|||jmp tramp_sr_epilogue"
check_static_contract "wizard_reveal_uses_spell_overlay_contract" "main.s" \
    "tramp_reveal_floorplan:|||lda #OVL_SPELL|||jsr overlay_load_no_kernal|||jsr eff_reveal_floorplan|||jmp tramp_sr_epilogue"
check_static_contract "c64_game_over_prompt_spacing_contract" "main.s" \
    "game_over_prompt:|||lda #8                      // Col 8: (40-24)/2 = 8|||game_over_str:|||.text \"R)EBOOT  S)TART  Q)UIT\""
check_static_contract "c64_hidden_kernal_irq_vector_contract" "main.s" \
    "c64_irq_hidden_rom:|||lda \$dc0d|||lda \$dd0d|||lda \$d019|||sta \$d019|||rti|||c64_install_ram_irq_vectors:|||lda #BANK_NO_KERNAL|||sta \$01|||sta \$fffa|||sta \$fffe|||sta \$fffb|||sta \$ffff|||overlay_load_no_kernal:|||pha|||lda #BANK_NO_BASIC|||sta \$01|||cli|||pla|||jsr overlay_load|||sei|||jsr c64_install_ram_irq_vectors|||lda #BANK_NO_KERNAL"
check_static_contract "c64_disk_call_preserves_args_contract" "main.s" \
    "c64_disk_call:|||lda \$01|||sta c64_disk_call_saved_bank|||lda #\$36|||sta \$01|||cli|||pla|||tay|||pla|||tax|||pla|||!cdc_jsr:|||jsr \$ffff"
check_static_contract "c64_game_over_overlay_exit_contract" "main.s" \
    "!gop_restart:|||jmp game_restart_overlay|||game_restart_overlay:|||lda #>(restart_entry - 1)|||pha|||lda #<(restart_entry - 1)|||pha|||jmp platform_runtime_resync_c64"
check_static_contract "c64_save_media_hal_contract" "../common/save.s" \
    "!save_wrong_media:|||jsr hal_storage_save_media_status|||cmp #HAL_STORAGE_STATUS_WRONG_MEDIA|||beq !save_bad_media+|||ldx #HSTR_SAVE_IOERR"
check_static_contract "c64_storage_classifier_export_contract" "hal/storage.s" \
    ".label hal_storage_save_media_status = disk_save_media_status"
check_static_contract "c64_save_stream_banks_kernal_contract" "../common/save.s" \
    "!save_media_ok:|||lda #BANK_NO_BASIC|||sta \$01|||jsr save_select_output_name_c64"
check_static_contract "c64_load_stream_banks_kernal_contract" "../common/save.s" \
    "!load_media_ok:|||lda #BANK_NO_BASIC|||sta \$01|||ldx #HSTR_SAVE_LOADING"

# Runtime tests
# Args: name, source, result memory range, expected pass count
run_test "math"   "tests/test_math.s"   "0400 040f" 16
run_test "rng"    "tests/test_rng.s"    "0400 0409" 10
run_test "memory" "tests/test_memory.s" "0400 0402" 3
run_test "config" "tests/test_config.s" "0400 0400" 1
run_test "input"  "tests/test_input.s"  "0400 040d" 14
run_test "main_loop" "tests/test_main_loop.s" "0400 041f" 32 500000000
run_test "turn" "tests/test_turn.s" "0400 0416" 23 500000000
run_test "player" "tests/test_player.s" "0400 0409" 10
run_test "dungeon" "tests/test_dungeon.s" "0400 0426" 39 500000000
run_test "monster" "tests/test_monster.s" "0400 040c" 13 500000000
run_test "monster_ai" "tests/test_monster_ai.s" "0400 0419" 26 500000000
run_test "combat" "tests/test_combat.s" "0400 041c" 29 500000000
run_test "msg_long" "tests/test_msg_long.s" "0400 0400" 1 20000000
run_test "monster_attack" "tests/test_monster_attack.s" "0400 040c" 13 500000000
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
run_test "item_desc" "tests/test_item_desc.s" "0400 0403" 4 500000000
run_test "item_ui" "tests/test_item_ui.s" "0400 040f" 16 1000000000
run_test "store" "tests/test_store.s" "0400 0426" 39 1000000000
run_test "ui_views" "tests/test_ui_views.s" "0400 0413" 14 500000000
run_test "ui_views_filters" "tests/test_ui_views_filters.s" "0400 0413" 7 500000000
run_test "subsystems" "tests/test_subsystems.s" "0400 0409" 10
run_sound_monitor_test
run_test "save"  "tests/test_save.s"  "0400 0413" 20 1000000000
run_test "score" "tests/test_score.s" "0400 040b" 12 500000000
run_test "wands_staves" "tests/test_wands_staves.s" "0400 0406" 7 100000000
run_test "monster_magic" "tests/test_monster_magic.s" "0400 040a" 11 500000000
run_test "tier" "tests/test_tier.s" "0400 040d" 14 500000000
run_test "disk_swap" "tests/test_disk_swap.s" "0400 040d" 14 500000000
run_test "render" "tests/test_render.s" "0400 0407" 8 500000000
run_test "ranged" "tests/test_ranged.s" "0400 0409" 10 500000000
run_test "ego" "tests/test_ego.s" "0400 0409" 10 500000000
run_test "throw" "tests/test_throw.s" "0400 040a" 11 500000000
run_test "bash" "tests/test_bash.s" "0400 0407" 8 500000000
run_test "tunnel" "tests/test_tunnel.s" "0400 0407" 8 500000000
run_test "background" "tests/test_background.s" "0400 0407" 8
run_scripted_spell_cast_smoke
run_scripted_book_overlay_smoke
run_scripted_spell_list_overlay_smoke
run_scripted_dungeon_target_spell_smoke
run_load_resume_product_smoke
run_save_media_fail_product_smoke
run_save_write_product_smoke
echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
