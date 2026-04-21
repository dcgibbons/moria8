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
            -write out/ovl.ui "64.ui" >>"$build_log" 2>&1; then
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
            -write out/ovl.ui "64.ui" >>"$build_log" 2>&1; then
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
            -write out/ovl.ui "64.ui" >>"$build_log" 2>&1; then
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

check_static_contract "wizard_heal_contract" "../common/wizard.s" \
    "wizard_cmd_heal_cure:|||lda player_data + PL_MAX_MANA|||sta player_data + PL_MANA|||sta zp_player_mp|||sta zp_player_mmp"
check_static_contract "learn_spell_followup_contract" "../common/player_gain_spell_impl.s" \
    "item_gain_spell:|||jsr input_prepare_modal_dismiss_key|||jsr spell_list_display|||jsr input_get_key|||jsr pm_pick_visible_spell"

# Runtime tests
# Args: name, source, result memory range, expected pass count
run_test "math"   "tests/test_math.s"   "0400 040f" 16
run_test "rng"    "tests/test_rng.s"    "0400 0409" 10
run_test "memory" "tests/test_memory.s" "0400 0402" 3
run_test "config" "tests/test_config.s" "0400 0400" 1
run_test "input"  "tests/test_input.s"  "0400 040a" 11
run_test "main_loop" "tests/test_main_loop.s" "0400 041c" 29 500000000
run_test "turn" "tests/test_turn.s" "0400 0416" 23 500000000
run_test "player" "tests/test_player.s" "0400 0409" 10
run_test "dungeon" "tests/test_dungeon.s" "0400 0424" 37 500000000
run_test "monster" "tests/test_monster.s" "0400 040c" 13 500000000
run_test "monster_ai" "tests/test_monster_ai.s" "0400 0419" 26 500000000
run_test "combat" "tests/test_combat.s" "0400 041c" 29 500000000
run_test "monster_attack" "tests/test_monster_attack.s" "0400 040c" 13 500000000
run_test "effects" "tests/test_effects.s" "0400 0431" 50 1000000000
run_test "genocide" "tests/test_genocide.s" "0400 0400" 1 500000000
run_test "directional_effects" "tests/test_directional_effects.s" "0400 0403" 4 500000000
run_test "overcast_ordering" "tests/test_overcast_ordering.s" "0400 0400" 1 500000000
run_test "ball_effects" "tests/test_ball_effects.s" "0400 0401" 2 500000000
run_test "utility_effects" "tests/test_utility_effects.s" "0400 0408" 9 500000000
    run_test "prayer_feedback" "tests/test_prayer_feedback.s" "0400 040c" 13 500000000
run_test "detect_feedback" "tests/test_detect_feedback.s" "0400 0403" 4 500000000
run_test "item" "tests/test_item.s" "0400 0433" 52 1000000000
run_test "store" "tests/test_store.s" "0400 0424" 37 1000000000
run_test "ui_views" "tests/test_ui_views.s" "0400 0413" 20 500000000
run_test "subsystems" "tests/test_subsystems.s" "0400 0409" 10
run_sound_monitor_test
run_test "save"  "tests/test_save.s"  "0400 040b" 12 1000000000
run_test "score" "tests/test_score.s" "0400 040b" 12 500000000
run_test "wands_staves" "tests/test_wands_staves.s" "0400 0406" 7 100000000
run_test "monster_magic" "tests/test_monster_magic.s" "0400 0409" 10 500000000
run_test "tier" "tests/test_tier.s" "0400 040d" 14 500000000
run_test "disk_swap" "tests/test_disk_swap.s" "0400 040b" 12 500000000
run_test "render" "tests/test_render.s" "0400 0407" 8 500000000
run_test "ranged" "tests/test_ranged.s" "0400 0407" 8 500000000
run_test "ego" "tests/test_ego.s" "0400 0409" 10 500000000
run_test "throw" "tests/test_throw.s" "0400 0405" 6 500000000
run_test "bash" "tests/test_bash.s" "0400 0407" 8 500000000
run_test "tunnel" "tests/test_tunnel.s" "0400 0407" 8 500000000
run_test "background" "tests/test_background.s" "0400 0407" 8
run_scripted_spell_cast_smoke
run_scripted_dungeon_target_spell_smoke
run_scripted_detect_evil_smoke

echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
