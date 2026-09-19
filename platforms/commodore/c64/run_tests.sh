#!/bin/bash
# run_tests.sh — Assemble and run all Phase 1 tests in VICE headless
#
# Usage: ./run_tests.sh
# Requires: Kick Assembler, VICE (x64sc)

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

java() {
    if [ "$1" = "-jar" ]; then
        local jar_path="$2"
        shift 2
        command java -jar "$jar_path" -libdir "$REPO_ROOT/core" -libdir "$REPO_ROOT/platforms/commodore/common" -libdir "$REPO_ROOT/platforms/commodore" -afo "$@"
    else
        command java "$@"
    fi
}
RUN_TESTS64_DIR="${RUN_TESTS64_DIR:-$REPO_ROOT/platforms/commodore/c64}"
cd "$RUN_TESTS64_DIR"
C64_TEST_OUT="${C64_TEST_OUT:-../../../build/test/c64}"
C64_BUILD_OUT="${C64_BUILD_OUT:-../../../build/c64}"
mkdir -p "$C64_TEST_OUT"
if [ -d "$C64_BUILD_OUT" ]; then
    cp -p "$C64_BUILD_OUT"/* "$C64_TEST_OUT"/ 2>/dev/null || true
fi
cleanup() {
        rm -f ./*.prg ./*.sym ./*.vs tests/*.prg tests/*.sym tests/*.vs
    rm -f creature_data/*.sym creature_data/*.vs "$REPO_ROOT"/core/*.sym "$REPO_ROOT"/core/*.vs
}
trap cleanup EXIT
COMMODORE_MAKE=(make -s -C "$REPO_ROOT/platforms/commodore")
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
# Test assemblies of main.s embed the Krill resident binary; build it (and the
# boot/install payloads used by test disks) once up front.
krill_status=0
"${COMMODORE_MAKE[@]}" ../../build/version_strings.inc \
    ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
    ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
    ../../build/c64/krill-resident.bin ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg || krill_status=$?
if [ "$krill_status" -ne 0 ]; then
    exit 1
fi
if ! cp -Rp "$C64_BUILD_OUT"/. "$C64_TEST_OUT/"; then
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
TEST_JOBS="${TEST_JOBS:-1}"
PRODUCT_TEST_JOBS="${PRODUCT_TEST_JOBS:-1}"
PASS=0
FAIL=0
TOTAL=0

if ! [[ "$TEST_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: TEST_JOBS must be a positive integer" >&2
    exit 2
fi
if ! [[ "$PRODUCT_TEST_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: PRODUCT_TEST_JOBS must be a positive integer" >&2
    exit 2
fi

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

SUITE_NAMES=()
SUITE_FUNCTIONS=()

run_suite_function() {
    local name="$1"
    local fn="$2"
    shift 2
    if ! suite_selected_any "$name" "$@"; then
        return
    fi
    SUITE_NAMES+=("$name")
    SUITE_FUNCTIONS+=("$fn")
}

create_suite_workspace() {
    local workspace="$1"
    local source name

    mkdir -p "$workspace/platforms/commodore/c64" "$workspace/build/test/c64" "$workspace/build/c64"
    for source in "$REPO_ROOT"/*; do
        name=$(basename "$source")
        case "$name" in
            build|platforms) continue ;;
        esac
        ln -s "$source" "$workspace/$name"
    done
    for source in "$REPO_ROOT/platforms"/*; do
        name=$(basename "$source")
        [ "$name" = "commodore" ] && continue
        ln -s "$source" "$workspace/platforms/$name"
    done
    for source in "$REPO_ROOT/platforms/commodore"/*; do
        name=$(basename "$source")
        [ "$name" = "c64" ] && continue
        ln -s "$source" "$workspace/platforms/commodore/$name"
    done
    for source in "$REPO_ROOT/platforms/commodore/c64"/*; do
        name=$(basename "$source")
        if [ "$name" = "main.s" ]; then
            cp -p "$source" "$workspace/platforms/commodore/c64/$name"
        else
            ln -s "$source" "$workspace/platforms/commodore/c64/$name"
        fi
    done
    if [ -d "$C64_BUILD_OUT" ]; then
        cp -Rp "$C64_BUILD_OUT"/. "$workspace/build/c64/" 2>/dev/null || true
    fi
    if [ -d "$C64_BUILD_OUT" ]; then
        cp -Rp "$C64_BUILD_OUT"/. "$workspace/build/test/c64/" 2>/dev/null || true
    fi
}

seed_product_build_out() {
    local output="$1"
    mkdir -p "$output/c64"
    cp -Rp "$C64_BUILD_OUT"/. "$output/c64/"
    rm -f "$output/c64/moria8.prg" "$output/c64/main.vs" "$output/c64/64.bank" "$output/c64"/ovl.*
}

run_suite_worker() {
    local name="$1"
    local fn="$2"
    local port="$3"
    local workspace
    workspace=$(mktemp -d "${TMPDIR:-/tmp}/moria8-c64-${name}.XXXXXX") || return 1
    if ! create_suite_workspace "$workspace"; then
        rm -rf "$workspace"
        return 1
    fi

    (
        trap - EXIT
        cd "$workspace/platforms/commodore/c64" || exit 1
        C64_TEST_OUT="$workspace/build/test/c64"
        C64_BUILD_OUT="$workspace/build/c64"
        export VICE_MONITOR_PORT="$port"
        PASS=0
        FAIL=0
        TOTAL=0
        "$fn"
        [ "$FAIL" -eq 0 ] && [ "$TOTAL" -gt 0 ]
    )
    local status=$?
    rm -rf "$workspace"
    return "$status"
}

run_parallel_suite_tests() {
    local count="${#SUITE_NAMES[@]}"
    local idx slot active=0
    local pids=()
    local logs=()

    if [ "$count" -eq 0 ]; then
        return
    fi

    if [ "$PRODUCT_TEST_JOBS" -eq 1 ]; then
        echo "  running product/media suites serially..."
        for ((idx=0; idx<count; idx++)); do
            if run_suite_worker "${SUITE_NAMES[$idx]}" "${SUITE_FUNCTIONS[$idx]}" 6510; then
                PASS=$((PASS + 1))
            else
                FAIL=$((FAIL + 1))
            fi
            TOTAL=$((TOTAL + 1))
        done
        return
    fi

    echo "  running product/media suites in parallel..."
    for ((idx=0; idx<count; idx++)); do
        while [ "$active" -ge "$PRODUCT_TEST_JOBS" ]; do
            for ((slot=0; slot<PRODUCT_TEST_JOBS; slot++)); do
                if [ -n "${pids[$slot]:-}" ] && ! kill -0 "${pids[$slot]}" 2>/dev/null; then
                    if wait "${pids[$slot]}"; then
                        PASS=$((PASS + 1))
                    else
                        FAIL=$((FAIL + 1))
                    fi
                    while IFS= read -r line; do
                        printf '%s\n' "$line"
                    done < "${logs[$slot]}"
                    rm -f "${logs[$slot]}"
                    unset 'pids[slot]' 'logs[slot]'
                    TOTAL=$((TOTAL + 1))
                    active=$((active - 1))
                    break
                fi
            done
            if [ "$active" -ge "$PRODUCT_TEST_JOBS" ]; then
                sleep 0.05
            fi
        done

        for ((slot=0; slot<PRODUCT_TEST_JOBS; slot++)); do
            if [ -z "${pids[$slot]:-}" ]; then
                break
            fi
        done
        logs[$slot]=$(mktemp -t "test_${SUITE_NAMES[$idx]}_worker")
        run_suite_worker "${SUITE_NAMES[$idx]}" "${SUITE_FUNCTIONS[$idx]}" \
            "$((6510 + slot))" >"${logs[$slot]}" 2>&1 &
        pids[$slot]=$!
        active=$((active + 1))
    done

    for ((slot=0; slot<PRODUCT_TEST_JOBS; slot++)); do
        if [ -z "${pids[$slot]:-}" ]; then
            continue
        fi
        if wait "${pids[$slot]}"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
        while IFS= read -r line; do
            printf '%s\n' "$line"
        done < "${logs[$slot]}"
        rm -f "${logs[$slot]}"
        TOTAL=$((TOTAL + 1))
    done
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

run_vice_resource_contract() {
    local name="vice_resource_contract"

    if ! suite_selected "$name"; then
        return
    fi

    echo -n "  $name: "
    if python3 - "$REPO_ROOT/platforms/commodore/c64/tests" "$REPO_ROOT/platforms/commodore/c64/run_tests.sh" <<'PY'
from pathlib import Path
import ast
import sys

root = Path(sys.argv[1])
runner = Path(sys.argv[2])
bad = []
for path in sorted(root.glob("*.py")):
    tree = ast.parse(path.read_text(), filename=str(path))
    for node in ast.walk(tree):
        if not isinstance(node, ast.List):
            continue
        values = []
        for elt in node.elts:
            if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                values.append(elt.value)
            elif isinstance(elt, ast.Attribute) and elt.attr == "vice":
                values.append("args.vice")
        if "args.vice" not in values:
            continue
        if "-remotemonitor" not in values and "-nativemonitor" not in values:
            continue
        missing = [flag for flag in ("-config", "-default", "+saveres") if flag not in values]
        if "-config" in values:
            config_index = values.index("-config")
            if config_index + 1 >= len(values) or values[config_index + 1] != "/dev/null":
                missing.append("-config /dev/null")
        if missing:
            bad.append(f"{path.name}: missing {', '.join(missing)}")

for lineno, line in enumerate(runner.read_text().splitlines(), start=1):
    stripped = line.strip()
    if not stripped.startswith('"$VICE" '):
        continue
    missing = [flag for flag in ("-config /dev/null", "-default", "+saveres") if flag not in line]
    if missing:
        bad.append(f"{runner.name}:{lineno}: missing {', '.join(missing)}")

if bad:
    print("; ".join(bad))
    raise SystemExit(1)
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

run_boot_disk_inventory_contract() {
    local name="boot_disk_64_init_inventory_contract"

    if ! suite_selected "$name"; then
        return
    fi

    echo -n "  $name: "
    if python3 - "$REPO_ROOT/platforms/commodore/c64/run_tests.sh" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
booting = [i for i, line in enumerate(lines) if '-write ' in line and '"moria64"' in line]
bad = [i + 1 for i in booting if i + 1 >= len(lines) or '"64.init"' not in lines[i + 1]]
if not booting or bad:
    raise SystemExit(f"MORIA64 disk recipes missing adjacent 64.init at lines: {bad}")
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

run_c64_shipping_init_contract() {
    local name="c64_shipping_64_init_contract"

    if ! suite_selected "$name"; then
        return
    fi

    echo -n "  $name: "
    if "${COMMODORE_MAKE[@]}" disk64 >/dev/null && \
       python3 - "$C1541" "$REPO_ROOT/build" <<'PY'
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

c1541 = sys.argv[1]
build = Path(sys.argv[2])
disk = build / "moria8-c64.d64"
source = (build / "c64" / "64.init").read_bytes()
dist = build / "c64-dist"
archive_path = build / "moria8-c64.zip"

listing = subprocess.run(
    [c1541, "-attach", str(disk), "-list"],
    check=True,
    capture_output=True,
    text=True,
).stdout.lower()
if len(re.findall(r'"64\.init"\s+prg', listing)) != 1:
    raise SystemExit("shipping D64 must contain exactly one 64.init PRG")
for required in ('"license"', '"source-offer"'):
    if required not in listing:
        raise SystemExit(f"shipping D64 missing {required}")

with tempfile.TemporaryDirectory(prefix="moria8-c64-init-") as tmp:
    extracted = Path(tmp) / "64.init"
    subprocess.run(
        [c1541, "-attach", str(disk), "-read", "64.init", str(extracted)],
        check=True,
        capture_output=True,
    )
    disk_bytes = extracted.read_bytes()

with zipfile.ZipFile(archive_path) as archive:
    names = archive.namelist()
    if names.count("64.init") != 1:
        raise SystemExit("shipping ZIP must contain exactly one 64.init")
    if not {"license", "source-offer"}.issubset(names):
        raise SystemExit("shipping ZIP missing release-compliance files")
    zip_bytes = archive.read("64.init")

if not (dist / "license").is_file() or not (dist / "source-offer").is_file():
    raise SystemExit("loose C64 distribution missing release-compliance files")
dist_bytes = (dist / "64.init").read_bytes()
if not (source == disk_bytes == dist_bytes == zip_bytes):
    raise SystemExit("packaged 64.init copies are not byte-identical")
if len(source) != 875 or source[:2] != bytes((0x00, 0xC0)):
    raise SystemExit("64.init must be an 875-byte true-address $C000 PRG")
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

run_test_internal() {
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
    asm_output=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" -define C64_UNIT_TEST "$src" -showmem -vicesymbols -o "$prg_file" 2>&1)

    if ! echo "$asm_output" | grep -q "0 failed"; then
        echo "FAIL (assembly error)"
        echo "$asm_output" | grep -i error | head -3
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
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
        return 1
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
        return 1
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
        return 1
    fi
    brk_byte=$(dd if="$prg_file" bs=1 skip="$offset" count=1 2>/dev/null | od -An -tx1 -v | tr -d ' \n')
    if [ "$brk_byte" != "00" ]; then
        echo "FAIL (Test Code stop address is not BRK: \$$end_addr)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local sym_file
    local bootstrap_addr
    sym_file="$(dirname "$prg_file")/$(basename "${src%.s}").vs"
    if [ ! -f "$sym_file" ]; then
        echo "FAIL (missing VICE symbol file)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi
    bootstrap_addr=$(awk '$3 == ".test_bootstrap" { split($2,a,":"); print toupper(a[2]); exit }' "$sym_file")
    if [ -z "$bootstrap_addr" ]; then
        bootstrap_addr=$(awk '$3 == ".bootstrap" { split($2,a,":"); print toupper(a[2]); exit }' "$sym_file")
    fi
    if [ -z "$bootstrap_addr" ]; then
        bootstrap_addr=$(awk '$3 == ".test_start" { split($2,a,":"); print toupper(a[2]); exit }' "$sym_file")
    fi
    rm -f "$sym_file"
    if [[ "$bootstrap_addr" =~ ^[0-9A-Fa-f]{1,4}$ ]]; then
        bootstrap_addr=$(printf '%04X' "$((16#$bootstrap_addr))")
    fi
    if ! [[ "$bootstrap_addr" =~ ^[0-9A-Fa-f]{4}$ ]] || [ $((16#$bootstrap_addr)) -ge $((16#A000)) ]; then
        echo "FAIL (missing low test bootstrap below \$A000)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    # Arm the completion breakpoint only after autostart reaches low RAM.
    # Otherwise BASIC ROM can execute a high stop address before PRG injection.
    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    {
        echo "break exec \$${bootstrap_addr}"
        echo "g"
        echo "delete 1"
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
            "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
        TOTAL=$((TOTAL + 1))
        return 1
    fi
    TOTAL=$((TOTAL + 1))
}

UNIT_NAMES=()
UNIT_SOURCES=()
UNIT_RANGES=()
UNIT_COUNTS=()
UNIT_CYCLES=()

run_test() {
    local name="$1"
    if ! suite_selected "$name"; then
        return
    fi
    UNIT_NAMES+=("$name")
    UNIT_SOURCES+=("$2")
    UNIT_RANGES+=("$3")
    UNIT_COUNTS+=("$4")
    UNIT_CYCLES+=("${5:-20000000}")
}

run_parallel_unit_tests() {
    local count="${#UNIT_NAMES[@]}"
    local idx slot active=0
    local pids=()
    local logs=()

    if [ "$count" -eq 0 ]; then
        return
    fi

    if [ "$TEST_JOBS" -eq 1 ]; then
        echo "  running unit tests serially..."
        for ((idx=0; idx<count; idx++)); do
            run_test_internal "${UNIT_NAMES[$idx]}" "${UNIT_SOURCES[$idx]}" \
                "${UNIT_RANGES[$idx]}" "${UNIT_COUNTS[$idx]}" \
                "${UNIT_CYCLES[$idx]}" || true
        done
        return
    fi

    echo "  running unit tests in parallel..."
    for ((idx=0; idx<count; idx++)); do
        while [ "$active" -ge "$TEST_JOBS" ]; do
            for ((slot=0; slot<TEST_JOBS; slot++)); do
                if [ -n "${pids[$slot]:-}" ] && ! kill -0 "${pids[$slot]}" 2>/dev/null; then
                    if wait "${pids[$slot]}"; then
                        PASS=$((PASS + 1))
                    else
                        FAIL=$((FAIL + 1))
                    fi
                    while IFS= read -r line; do
                        printf '%s\n' "$line"
                    done < "${logs[$slot]}"
                    rm -f "${logs[$slot]}"
                    unset 'pids[slot]' 'logs[slot]'
                    TOTAL=$((TOTAL + 1))
                    active=$((active - 1))
                    break
                fi
            done
            if [ "$active" -ge "$TEST_JOBS" ]; then
                sleep 0.05
            fi
        done

        for ((slot=0; slot<TEST_JOBS; slot++)); do
            if [ -z "${pids[$slot]:-}" ]; then
                break
            fi
        done
        logs[$slot]=$(mktemp -t "test_${UNIT_NAMES[$idx]}_worker")
        run_test_internal "${UNIT_NAMES[$idx]}" "${UNIT_SOURCES[$idx]}" \
            "${UNIT_RANGES[$idx]}" "${UNIT_COUNTS[$idx]}" \
            "${UNIT_CYCLES[$idx]}" >"${logs[$slot]}" 2>&1 &
        pids[$slot]=$!
        active=$((active + 1))
    done

    for ((slot=0; slot<TEST_JOBS; slot++)); do
        if [ -z "${pids[$slot]:-}" ]; then
            continue
        fi
        if wait "${pids[$slot]}"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
        while IFS= read -r line; do
            printf '%s\n' "$line"
        done < "${logs[$slot]}"
        rm -f "${logs[$slot]}"
        TOTAL=$((TOTAL + 1))
    done
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/krill-resident.bin ../../build/c64/kinst64.prg ../../build/c64/kres64.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols -define C64_TEST_SCRIPTED_SPELL -o ../../../build/test/c64/moria_spell_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_spell_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/c64/kinst64.prg "kinst64" \
            -write ../../../build/c64/kres64.prg "kres64" \
            -write ../../../build/test/c64/moria_spell_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
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
            echo "FAIL (missing ${label} in ../../../build/test/c64/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_BOOK_OVERLAY \
            -o ../../../build/test/c64/moria_book_overlay_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_book_overlay_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_book_overlay_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
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
            echo "FAIL (missing ${label} in ../../../build/test/c64/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted book overlay pass symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SCROLL_SELECTOR \
            -o ../../../build/test/c64/moria_scroll_selector_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_scroll_selector_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_scroll_selector_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
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
            echo "FAIL (missing ${label} in ../../../build/test/c64/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted scroll selector pass symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY \
            -o ../../../build/test/c64/moria_spell_list_overlay_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_spell_list_overlay_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_spell_list_overlay_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
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
            echo "FAIL (missing ${label} in ../../../build/test/c64/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell list overlay pass symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DUNGEON_SPELL \
            -o ../../../build/test/c64/moria_dungeon_spell_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_dungeon_spell_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_dungeon_spell_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
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
            echo "FAIL (missing ${label} in ../../../build/test/c64/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT \
            -o ../../../build/test/c64/moria_detect_evil_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_detect_evil_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_detect_evil_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
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
            echo "FAIL (missing ${label} in ../../../build/test/c64/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT \
            -o ../../../build/test/c64/moria_dungeon_ascent_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_dungeon_ascent_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_dungeon_ascent_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.tramp_store_restock_all$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_dungeon_ascent_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing dungeon-ascent smoke symbols in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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

run_wizard_reveal_product_smoke() {
    local name="wizard_reveal_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_WIZARD_REVEAL_PRODUCT \
            -o ../../../build/test/c64/moria_wizard_reveal_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_wizard_reveal_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_wizard_reveal_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
    local fail_addr dlvl_addr vis_addr ovl_addr arm_addr
    fail_addr=$(awk '/\.c64_test_wizard_reveal_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    dlvl_addr=$(awk '/\.zp_player_dlvl$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    vis_addr=$(awk '/\.vis_room_revealed$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    ovl_addr=$(awk '/\.current_overlay$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    arm_addr=$(awk '/\.item_init_identification$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${fail_addr:-}" ] || [ -z "${dlvl_addr:-}" ] || [ -z "${vis_addr:-}" ] || [ -z "${ovl_addr:-}" ] || [ -z "${arm_addr:-}" ]; then
        echo "FAIL (missing wizard-reveal smoke symbols in ../../../build/test/c64/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    fail_addr=$(printf '%04X' "$((16#$fail_addr))")
    dlvl_addr=$(printf '%04X' "$((16#$dlvl_addr))")
    vis_addr=$(printf '%04X' "$((16#$vis_addr))")
    ovl_addr=$(printf '%04X' "$((16#$ovl_addr))")
    arm_addr=$(printf '%04X' "$((16#$arm_addr))")

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local fail_lc
    fail_lc=$(echo "$fail_addr" | tr '[:upper:]' '[:lower:]')

    # VICE exec breakpoints match PC regardless of banking, so a raw break on
    # the brk address can fire during boot while BASIC ROM ($A000-$BFFF) is
    # banked in and the interpreter happens to execute that address; sampling
    # dlvl/current_overlay then reads boot-time garbage. Arm the brk break only
    # after the game is running: item_init_identification sits below $A000
    # (always RAM, never executed by boot/BASIC) and runs once at new-game
    # start, before the wizard reveal flow.
    {
        echo "break \$${arm_addr}"
        echo "g"
        echo "delete 1"
        echo "break \$${fail_addr}"
        echo "g"
        echo "m \$${dlvl_addr} \$${dlvl_addr}"
        echo "m \$${vis_addr} \$${vis_addr}"
        echo "m \$${ovl_addr} \$${ovl_addr}"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
        -8 "$scripted_d64" -autostart "$scripted_d64" \
        -moncommands "$mon_file" \
        -limitcycles 900000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if ! grep -qiE "Stop on  exec ${fail_lc}" "$tty_log" && ! grep -qi "^BREAK: .*C:\$${fail_addr}" "$tty_log"; then
        if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
            echo "FAIL (wizard reveal flow jammed)"
        elif grep -qi "cycle limit reached" "$tty_log"; then
            echo "FAIL (wizard reveal flow timed out)"
        else
            echo "FAIL (did not reach scripted-input exhaustion)"
        fi
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Reaching scripted-input exhaustion means the reveal returned to the main
    # loop. Verify the invariants: still on dungeon level 1, and the wizard
    # menu overlay was restored after the spell overlay ran
    # (OVL_MODAL_MISC = 9). vis_room_revealed is per-turn transient and is
    # cleared by the follow-up visibility update, so it cannot be checked here.
    local dlvl_lc ovl_lc
    dlvl_lc=$(echo "$dlvl_addr" | tr '[:upper:]' '[:lower:]')
    ovl_lc=$(echo "$ovl_addr" | tr '[:upper:]' '[:lower:]')

    if ! grep -qiE "^>C:${dlvl_lc}  01" "$tty_log"; then
        echo "FAIL (player left dungeon level 1 after wizard reveal)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qiE "^>C:${ovl_lc}  09" "$tty_log"; then
        echo "FAIL (wizard menu overlay not restored after reveal)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_wizard_item_product_smoke() {
    local name="wizard_item_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_WIZARD_ITEM_PRODUCT \
            -o ../../../build/test/c64/moria_wizard_item_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_wizard_item_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_wizard_item_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Wizard generate item (G 128, G 96, then G 127) exercises the modal flow
    # whose ego roll banks the $F000 runtime while returning through $E000.
    # The resident post-ego breakpoint arms the overlay-address redraw probe
    # only after the target item roll, avoiding earlier hits at the same
    # $E000 address during dungeon generation.
    local main_vs="../../../build/test/c64/main.vs"
    local fail_addr redraw_addr ego_addr dlvl_addr ovl_addr arm_addr inv_addr
    fail_addr=$(awk '/\.c64_test_wizard_reveal_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    redraw_addr=$(awk '/\.c64_test_wizard_item_redraw_done_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    dlvl_addr=$(awk '/\.zp_player_dlvl$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    ovl_addr=$(awk '/\.current_overlay$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    arm_addr=$(awk '/\.item_init_identification$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    inv_addr=$(awk '/\.inv_item_id$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    ego_addr=$(awk '/\.c64_test_wizard_ego_bank_restored_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${fail_addr:-}" ] || [ -z "${redraw_addr:-}" ] || [ -z "${ego_addr:-}" ] || [ -z "${dlvl_addr:-}" ] || [ -z "${ovl_addr:-}" ] || [ -z "${arm_addr:-}" ] || [ -z "${inv_addr:-}" ]; then
        echo "FAIL (missing wizard-item smoke symbols in ../../../build/test/c64/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    fail_addr=$(printf '%04X' "$((16#$fail_addr))")
    redraw_addr=$(printf '%04X' "$((16#$redraw_addr))")
    dlvl_addr=$(printf '%04X' "$((16#$dlvl_addr))")
    ovl_addr=$(printf '%04X' "$((16#$ovl_addr))")
    arm_addr=$(printf '%04X' "$((16#$arm_addr))")
    inv_addr=$(printf '%04X' "$((16#$inv_addr))")
    ego_addr=$(printf '%04X' "$((16#$ego_addr))")
    inv_end=$(printf '%04X' "$((16#$inv_addr + 4))")

    local mon_file
    mon_file=$(mktemp -t "test_${name}_mon")
    local tty_log
    tty_log=$(mktemp -t "test_${name}_ttylog")
    local fail_lc
    fail_lc=$(echo "$fail_addr" | tr '[:upper:]' '[:lower:]')

    # Same boot-time BASIC ROM breakpoint hazard as the reveal smoke; arm the
    # brk break only after item_init_identification runs at new-game start.
    {
        echo "break \$${arm_addr}"
        echo "g"
        echo "delete"
        echo "break \$${ego_addr}"
        echo "g"
        echo "delete"
        echo "break \$${redraw_addr}"
        echo "g"
        echo "m 0001 0001"
        echo "m d800 dbe7"
        echo "delete"
        echo "break \$${fail_addr}"
        echo "g"
        echo "m \$${dlvl_addr} \$${dlvl_addr}"
        echo "m \$${ovl_addr} \$${ovl_addr}"
        echo "m \$${inv_addr} \$${inv_end}"
        echo "quit"
    } > "$mon_file"

    script -q "$tty_log" \
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
        -8 "$scripted_d64" -autostart "$scripted_d64" \
        -moncommands "$mon_file" \
        -limitcycles 900000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor > /dev/null 2>&1

    if ! grep -qiE "Stop on  exec ${fail_lc}" "$tty_log" && ! grep -qi "^BREAK: .*C:\$${fail_addr}" "$tty_log"; then
        if grep -qiE "JAM|Invalid opcode" "$tty_log"; then
            echo "FAIL (wizard item flow jammed)"
        elif grep -qi "cycle limit reached" "$tty_log"; then
            echo "FAIL (wizard item flow timed out)"
        else
            echo "FAIL (did not reach scripted-input exhaustion)"
        fi
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qiE "^>C:0001  35" "$tty_log"; then
        echo "FAIL (wizard item redraw ran without C64 I/O visible)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! python3 - "$tty_log" <<'PY'
import re
import sys
from pathlib import Path

values = []
for line in Path(sys.argv[1]).read_text(errors="ignore").splitlines():
    if not re.match(r"^>C:d[89ab][0-9a-f]{2}\s", line, re.IGNORECASE):
        continue
    for token in line.split()[1:17]:
        if re.fullmatch(r"[0-9a-f]{2}", token, re.IGNORECASE):
            values.append(int(token, 16) & 0x0f)

if len(values) < 1000 or values.count(0x0b) < 8 or values.count(0x0f) < 8:
    raise SystemExit(1)
PY
    then
        echo "FAIL (wizard item redraw did not restore physical dungeon colors)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Reaching scripted-input exhaustion means all three generations, the overlay
    # restore, and the inventory view returned to the main loop. Verify
    # invariants: still on dungeon level 1, and the inventory display left its
    # owning overlay resident (OVL_HELP = 5).
    local dlvl_lc ovl_lc
    dlvl_lc=$(echo "$dlvl_addr" | tr '[:upper:]' '[:lower:]')
    ovl_lc=$(echo "$ovl_addr" | tr '[:upper:]' '[:lower:]')

    if ! grep -qiE "^>C:${dlvl_lc}  01" "$tty_log"; then
        echo "FAIL (player left dungeon level 1 after wizard item generation)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qiE "^>C:${ovl_lc}  05" "$tty_log"; then
        echo "FAIL (inventory overlay not resident after inventory display)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Chest 128 ($80) and the appended-range boundaries (96=$60, 127=$7f)
    # must all land in inventory through the production grant path (starting
    # gear occupies the leading slots).
    local inv_lc
    inv_lc=$(echo "$inv_addr" | tr '[:upper:]' '[:lower:]')
    if ! grep -qiE "^>C:${inv_lc}.*80.*60[[:space:]]+7f" "$tty_log"; then
        echo "FAIL (item IDs 128/96/127 not granted into inventory)"
        echo "    Log: $tty_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_chest_open_product_smoke() {
    local name="chest_open_product_smoke"
    echo -n "  $name: "

    local smoke_out build_log smoke_c64 boot_d64 main_vs
    smoke_out=$(mktemp -d "${TMPDIR:-/tmp}/moria8-c64-chest-open.XXXXXX")
    smoke_c64="$smoke_out/c64"
    boot_d64="$smoke_out/moria8-c64.d64"
    main_vs="$smoke_c64/main.vs"
    build_log=$(mktemp -t "build_${name}_log")
    seed_product_build_out "$smoke_out"

    if ! make -s -C "$REPO_ROOT/platforms/commodore" \
            KICKASS="$KICKASS" \
            OUT="$smoke_out" \
            KA_FLAGS64="-showmem -vicesymbols -libdir ../../core -libdir common -afo -libdir c64 -define DEBUG_FEAT_DISK_TRACE=0 -define C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT" \
            build64 "$smoke_out/c64/kinst64.prg" "$smoke_out/c64/kres64.prg" "$smoke_out/c64/kinst41.prg" >"$build_log" 2>&1; then
        echo "FAIL (product build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$C1541" -format "moria8 c64,m8" d64 "$boot_d64" \
            -attach "$boot_d64" \
            -write "$smoke_c64/boot.prg" "moria8" \
            -write "$smoke_c64/boot.prg" "boot64" \
            -write "$smoke_c64/bootart64.prg" "bootart64" \
            -write "$smoke_c64/kinst64.prg" "kinst64" \
            -write "$smoke_c64/kres64.prg" "kres64" \
            -write "$smoke_c64/kinst41.prg" "kinst41" \
            -write "$smoke_c64/moria8.prg" "moria64" \
            -write "$smoke_c64/64.init" "64.init" \
            -write "$smoke_c64/64.bank" "64.bank" \
            -write "$smoke_c64/title" "t64" \
            -write "$smoke_c64/monster.db.1" "monster.db.1" \
            -write "$smoke_c64/monster.db.2" "monster.db.2" \
            -write "$smoke_c64/monster.db.3" "monster.db.3" \
            -write "$smoke_c64/monster.db.4" "monster.db.4" \
            -write "$smoke_c64/ovl.start" "64.start" \
            -write "$smoke_c64/ovl.town" "64.town" \
            -write "$smoke_c64/ovl.death" "64.death" \
            -write "$smoke_c64/ovl.modal" "64.modal" \
            -write "$smoke_c64/ovl.gen" "64.gen" \
            -write "$smoke_c64/ovl.help" "64.help" \
            -write "$smoke_c64/ovl.ui" "64.ui" \
            -write "$smoke_c64/ovl.items" "64.items" \
            -write "$smoke_c64/ovl.spell" "64.spell" \
            -write "$smoke_c64/ovl.chest" "64.chest" >"$build_log" 2>&1; then
        echo "FAIL (product disk image)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --pass-symbol ".c64_test_script_exhausted_wait" \
            --start-symbol ".title_menu_loop" \
            --require-hit-symbol ".krill_load_file" \
            --require-hit-symbol ".tramp_level_generate" \
            --require-hit-symbol ".chest_product_setup" \
            --until-pass \
            --main-vs "$main_vs" \
            --boot-d64 "$boot_d64" \
            --expect-byte-symbol ".chest_product_path_stage=0x05" \
            --expect-byte-symbol ".chest_product_loot_placed=0x01" \
            --expect-byte-symbol ".zp_dirty_count=0x00" \
            --expect-byte-symbol ".turn_scene_dirty=0x00" \
            --expect-byte-symbol ".chest_product_runtime_state=0x36" \
            --expect-byte-symbol ".chest_loot_pending=0x00" \
            --expect-byte-symbol ".chest_pending_summons=0x00" \
            --expect-byte-symbol ".current_overlay=0x0a" \
            --expect-byte-symbol ".fi_item_id=0x81" \
            --expect-byte-symbol ".fi_p1=0x80" \
            --expect-byte-symbol ".zp_player_dlvl=0x01" \
            --timeout 30 \
            --retry-timeouts 0 \
            --vice "$VICE" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}
run_chest_open_product_reu_smoke() {
    local name="chest_open_product_reu_smoke"
    echo -n "  $name: "

    local smoke_out build_log boot_d64 main_vs
    smoke_out=$(mktemp -d "${TMPDIR:-/tmp}/moria8-c64-chest-open-reu.XXXXXX")
    boot_d64="$smoke_out/moria8-c64.d64"
    main_vs="$smoke_out/c64/main.vs"
    build_log=$(mktemp -t "build_${name}_log")
    seed_product_build_out "$smoke_out"

    if ! make -s -C "$REPO_ROOT/platforms/commodore" \
            KICKASS="$KICKASS" \
            OUT="$smoke_out" \
            KA_FLAGS64="-showmem -vicesymbols -libdir ../../core -libdir common -afo -libdir c64 -define DEBUG_FEAT_DISK_TRACE=0 -define C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT" \
            build64 "$smoke_out/c64/kinst64.prg" "$smoke_out/c64/kres64.prg" "$smoke_out/c64/kinst41.prg" >"$build_log" 2>&1; then
        echo "FAIL (product build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$C1541" -format "moria8 c64,m8" d64 "$boot_d64" \
            -attach "$boot_d64" \
            -write "$smoke_out/c64/boot.prg" "moria8" \
            -write "$smoke_out/c64/boot.prg" "boot64" \
            -write "$smoke_out/c64/bootart64.prg" "bootart64" \
            -write "$smoke_out/c64/kinst64.prg" "kinst64" \
            -write "$smoke_out/c64/kres64.prg" "kres64" \
            -write "$smoke_out/c64/kinst41.prg" "kinst41" \
            -write "$smoke_out/c64/moria8.prg" "moria64" \
            -write "$smoke_out/c64/64.init" "64.init" \
            -write "$smoke_out/c64/64.bank" "64.bank" \
            -write "$smoke_out/c64/title" "t64" \
            -write "$smoke_out/c64/monster.db.1" "monster.db.1" \
            -write "$smoke_out/c64/monster.db.2" "monster.db.2" \
            -write "$smoke_out/c64/monster.db.3" "monster.db.3" \
            -write "$smoke_out/c64/monster.db.4" "monster.db.4" \
            -write "$smoke_out/c64/ovl.start" "64.start" \
            -write "$smoke_out/c64/ovl.town" "64.town" \
            -write "$smoke_out/c64/ovl.death" "64.death" \
            -write "$smoke_out/c64/ovl.modal" "64.modal" \
            -write "$smoke_out/c64/ovl.gen" "64.gen" \
            -write "$smoke_out/c64/ovl.help" "64.help" \
            -write "$smoke_out/c64/ovl.ui" "64.ui" \
            -write "$smoke_out/c64/ovl.items" "64.items" \
            -write "$smoke_out/c64/ovl.spell" "64.spell" \
            -write "$smoke_out/c64/ovl.chest" "64.chest" >"$build_log" 2>&1; then
        echo "FAIL (product disk image)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Same scripted chest open, but with a 512K REU attached: overlays stash
    # into the REU at boot and the deferred GEN fetch (and CHEST load) come
    # from REU DMA rather than disk. reu_overlays_stashed=1 proves the boot
    # stash ran; the stage/loot state proves the REU-backed path completes.
    # kinst64/kres64 are on the disk, so the boot and the REU preloads run
    # through Krill: krill_boot_used/krill_active prove that path engaged
    # (same evidence bytes as fastload_product_smoke).
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --pass-symbol ".c64_test_script_exhausted_wait" \
            --start-symbol ".title_menu_loop" \
            --until-pass \
            --main-vs "$main_vs" \
            --boot-d64 "$boot_d64" \
            --vice-extra-arg=-reu \
            --vice-extra-arg=-reusize \
            --vice-extra-arg=512 \
            --expect-byte-symbol ".krill_active=0xff" \
            --expect-byte-symbol ".krill_boot_used=0x01" \
            --expect-byte-symbol ".reu_overlays_stashed=0x01" \
            --expect-byte-symbol ".chest_product_path_stage=0x05" \
            --expect-byte-symbol ".chest_product_loot_placed=0x01" \
            --expect-byte-symbol ".zp_dirty_count=0x00" \
            --expect-byte-symbol ".turn_scene_dirty=0x00" \
            --expect-byte-symbol ".chest_product_runtime_state=0x36" \
            --expect-byte-symbol ".chest_loot_pending=0x00" \
            --expect-byte-symbol ".chest_pending_summons=0x00" \
            --expect-byte-symbol ".current_overlay=0x0a" \
            --expect-byte-symbol ".fi_item_id=0x81" \
            --expect-byte-symbol ".fi_p1=0x80" \
            --expect-byte-symbol ".zp_player_dlvl=0x01" \
            --timeout 30 \
            --retry-timeouts 0 \
            --vice "$VICE" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_chest_open_product_genfail_smoke() {
    local name="chest_open_product_genfail_smoke"
    echo -n "  $name: "

    local smoke_out build_log boot_d64 nogen_d64 main_vs
    smoke_out=$(mktemp -d "${TMPDIR:-/tmp}/moria8-c64-chest-open-genfail.XXXXXX")
    boot_d64="$smoke_out/moria8-c64.d64"
    nogen_d64="$smoke_out/moria8-c64-nogen.d64"
    main_vs="$smoke_out/c64/main.vs"
    build_log=$(mktemp -t "build_${name}_log")
    seed_product_build_out "$smoke_out"

    if ! make -s -C "$REPO_ROOT/platforms/commodore" \
            KICKASS="$KICKASS" \
            OUT="$smoke_out" \
            KA_FLAGS64="-showmem -vicesymbols -libdir ../../core -libdir common -afo -libdir c64 -define DEBUG_FEAT_DISK_TRACE=0 -define C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT" \
            build64 >"$build_log" 2>&1; then
        echo "FAIL (product build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$C1541" -format "moria8 c64,m8" d64 "$boot_d64" \
            -attach "$boot_d64" \
            -write "$smoke_out/c64/boot.prg" "moria8" \
            -write "$smoke_out/c64/boot.prg" "boot64" \
            -write "$smoke_out/c64/bootart64.prg" "bootart64" \
            -write "$smoke_out/c64/moria8.prg" "moria64" \
            -write "$smoke_out/c64/64.init" "64.init" \
            -write "$smoke_out/c64/64.bank" "64.bank" \
            -write "$smoke_out/c64/title" "t64" \
            -write "$smoke_out/c64/monster.db.1" "monster.db.1" \
            -write "$smoke_out/c64/monster.db.2" "monster.db.2" \
            -write "$smoke_out/c64/monster.db.3" "monster.db.3" \
            -write "$smoke_out/c64/monster.db.4" "monster.db.4" \
            -write "$smoke_out/c64/ovl.start" "64.start" \
            -write "$smoke_out/c64/ovl.town" "64.town" \
            -write "$smoke_out/c64/ovl.death" "64.death" \
            -write "$smoke_out/c64/ovl.modal" "64.modal" \
            -write "$smoke_out/c64/ovl.gen" "64.gen" \
            -write "$smoke_out/c64/ovl.help" "64.help" \
            -write "$smoke_out/c64/ovl.ui" "64.ui" \
            -write "$smoke_out/c64/ovl.items" "64.items" \
            -write "$smoke_out/c64/ovl.spell" "64.spell" \
            -write "$smoke_out/c64/ovl.chest" "64.chest" >"$build_log" 2>&1; then
        echo "FAIL (product disk image)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Swap target: every file except 64.gen, so the deferred GEN fulfillment
    # load fails on real media after the chest overlay has already loaded.
    cp "$boot_d64" "$nogen_d64"
    if ! "$C1541" -attach "$nogen_d64" -delete "64.gen" >>"$build_log" 2>&1; then
        echo "FAIL (nogen disk image)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # The swap triggers at tramp_chest_open (resident; reached only when the
    # Open command finds a chest). At that point dungeon generation is long
    # done and the CHEST overlay still loads fine from the swapped disk; only
    # the deferred GEN fulfillment load fails. Expected state: stage stays at
    # 2 (overlay entered, generator never ran), no loot placed, latch cleared,
    # current_overlay=NONE after the failed load, and the game reaches the
    # script-exhaustion trap (still responsive).
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --pass-symbol ".c64_test_script_exhausted_wait" \
            --start-symbol ".title_menu_loop" \
            --until-pass \
            --main-vs "$main_vs" \
            --boot-d64 "$boot_d64" \
            --swap-symbol ".tramp_chest_open" \
            --swap-attach8-d64 "$nogen_d64" \
            --swap-attach-after-hits 1 \
            --expect-byte-symbol ".chest_product_path_stage=0x02" \
            --expect-byte-symbol ".chest_product_loot_placed=0x00" \
            --expect-byte-symbol ".chest_loot_pending=0x00" \
            --expect-byte-symbol ".chest_pending_summons=0x00" \
            --expect-byte-symbol ".current_overlay=0x00" \
            --expect-byte-symbol ".fi_item_id=0x81" \
            --expect-byte-symbol ".fi_p1=0x80" \
            --expect-byte-symbol ".zp_player_dlvl=0x01" \
            --timeout 30 \
            --retry-timeouts 0 \
            --vice "$VICE" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_disk_setup_product_smoke() {
    local name="disk_setup_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT \
            -o ../../../build/test/c64/moria_disk_setup_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_disk_setup_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_disk_setup_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="../../../build/test/c64/moria_disk_setup_save.d64"
    rm -f "$save_d64"
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

    local main_vs="../../../build/test/c64/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c64_test_after_disk_setup_product$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing disk-setup smoke symbols in ../../../build/test/c64/main.vs)"
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

run_fastload_product_smoke() {
    local name="fastload_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/krill-resident.bin ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_FASTLOAD_PRODUCT \
            -o ../../../build/test/c64/moria_fastload_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Program disk WITH the Krill install payload: install succeeds, title art
    # and startup overlay load through the Krill resident.
    local fastload_d64="../../../build/test/c64/moria_fastload_smoke.d64"
    rm -f "$fastload_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$fastload_d64" \
            -attach "$fastload_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/c64/kinst64.prg "kinst64" \
            -write ../../../build/c64/kres64.prg "kres64" \
            -write ../../../build/c64/kinst41.prg "kinst41" \
            -write ../../../build/test/c64/moria_fastload_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    # Same disk WITHOUT kinst64: install fails cleanly and the game must fall
    # back to the stock KERNAL path.
    local fallback_d64="../../../build/test/c64/moria_fastload_fallback.d64"
    rm -f "$fallback_d64"
    if ! "$C1541" -format "moria8 c64,m9" d64 "$fallback_d64" \
            -attach "$fallback_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_fastload_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (fallback disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c64/main.vs"
    if ! grep -q "\.c64_test_fastload_pass_sym" "$main_vs"; then
        echo "FAIL (missing fastload smoke symbols in $main_vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "fastload_krill_active" \
            --vice "$VICE" \
            --boot-d64 "$fastload_d64" \
            --main-vs "$main_vs" \
            --start-symbol ".title_enter_menu" \
            --require-hit-symbol ".hal_asset_krill_call" \
            --pass-symbol ".c64_test_fastload_pass_sym" \
            --expect-byte-symbol ".krill_active=0xff" \
            --expect-byte-symbol ".krill_boot_used=0x01" \
            --expect-byte-symbol ".krill_boot_art_used=0x81" \
            --screen-base 0x0400; then
        echo "FAIL (Krill fastload path)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "fastload_kernal_fallback" \
            --vice "$VICE" \
            --boot-d64 "$fallback_d64" \
            --main-vs "$main_vs" \
            --pass-symbol ".c64_test_fastload_pass_sym" \
            --expect-byte-symbol ".krill_active=0x00" \
            --expect-byte-symbol ".krill_boot_used=0x00" \
            --expect-byte-symbol ".krill_boot_art_used=0x80" \
            --screen-base 0x0400; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (KERNAL fallback path)"
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_boot_handoff_runtime_matrix() {
    local name="boot_handoff_runtime_matrix"
    echo -n "  $name: "

    local out="../../../build/test/c64/boot-handoff"
    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p "$out"

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT="$out" \
            -showmem -vicesymbols -define C64_TEST_SCRIPTED_FASTLOAD_PRODUCT \
            -define C64_TEST_BOOT_HANDOFF -o "$out/moria64.prg" >"$build_log" 2>&1 || \
       ! java -jar "$KICKASS" boot.s -vicesymbols -define C64_TEST_BOOT_HANDOFF \
            -o "$out/boot.prg" >>"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local boot_vs="$out/boot.vs"
    local main_vs="$out/main.vs"
    if [ ! -f "$boot_vs" ] || [ ! -f "$main_vs" ]; then
        echo "FAIL (missing boot/main symbols)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local krill_d64="$out/krill.d64"
    local krill_noart_d64="$out/krill-noart.d64"
    local fallback_d64="$out/fallback.d64"
    rm -f "$krill_d64" "$krill_noart_d64" "$fallback_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$krill_d64" -attach "$krill_d64" \
            -write "$out/boot.prg" "moria8" -write "$out/boot.prg" "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/kinst64.prg "kinst64" \
            -write ../../../build/test/c64/kres64.prg "kres64" \
            -write ../../../build/test/c64/kinst41.prg "kinst41" \
            -write "$out/moria64.prg" "moria64" \
            -write "$out/64.init" "64.init" \
            -write "$out/64.bank" "64.bank" -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write "$out/ovl.start" "64.start" -write "$out/ovl.town" "64.town" \
            -write "$out/ovl.death" "64.death" -write "$out/ovl.modal" "64.modal" \
            -write "$out/ovl.gen" "64.gen" -write "$out/ovl.help" "64.help" \
            -write "$out/ovl.ui" "64.ui" -write "$out/ovl.items" "64.items" \
            -write "$out/ovl.spell" "64.spell" -write "$out/ovl.chest" "64.chest" \
            >"$build_log" 2>&1 || \
       ! "$C1541" -format "moria8 c64,m8" d64 "$fallback_d64" -attach "$fallback_d64" \
            -write "$out/boot.prg" "moria8" -write "$out/boot.prg" "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write "$out/moria64.prg" "moria64" \
            -write "$out/64.init" "64.init" \
            -write "$out/64.bank" "64.bank" -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write "$out/ovl.start" "64.start" -write "$out/ovl.town" "64.town" \
            -write "$out/ovl.death" "64.death" -write "$out/ovl.modal" "64.modal" \
            -write "$out/ovl.gen" "64.gen" -write "$out/ovl.help" "64.help" \
            -write "$out/ovl.ui" "64.ui" -write "$out/ovl.items" "64.items" \
            -write "$out/ovl.spell" "64.spell" -write "$out/ovl.chest" "64.chest" \
            >>"$build_log" 2>&1 || \
       ! "$C1541" -format "moria8 c64,m8" d64 "$krill_noart_d64" -attach "$krill_noart_d64" \
            -write "$out/boot.prg" "moria8" -write "$out/boot.prg" "boot64" \
            -write ../../../build/test/c64/kinst64.prg "kinst64" \
            -write ../../../build/test/c64/kres64.prg "kres64" \
            -write ../../../build/test/c64/kinst41.prg "kinst41" \
            -write "$out/moria64.prg" "moria64" \
            -write "$out/64.init" "64.init" \
            -write "$out/64.bank" "64.bank" -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write "$out/ovl.start" "64.start" -write "$out/ovl.town" "64.town" \
            -write "$out/ovl.death" "64.death" -write "$out/ovl.modal" "64.modal" \
            -write "$out/ovl.gen" "64.gen" -write "$out/ovl.help" "64.help" \
            -write "$out/ovl.ui" "64.ui" -write "$out/ovl.items" "64.items" \
            -write "$out/ovl.spell" "64.spell" -write "$out/ovl.chest" "64.chest" \
            >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    local scenario disk device timeout
    local scenarios=(
        kinst_failure:krill:8
        bootart_failure:fallback:8
        missing_bootart_krill:noart:8
        display_integrity:krill:8
        display_canary_failure:krill:8
        installer_1541u_warning:krill:8
        installer_mute_failure:krill:8
        krill_install_success_cleanup:krill:8
        kernal_success_cleanup:fallback:8
        kernal_moria_failure:fallback:8
        kernal_init_failure:fallback:8
        recovery_moria_failure:krill:8
        recovery_init_failure:krill:8
        recovery_success_cleanup:krill:8
        p6_bank_failure:fallback:8
        krill_moria_failure:krill:8
        krill_bank_failure:krill:8
        krill_init_failure:krill:8
        device9_krill:krill:9
        device9_fallback:fallback:9
        rom_vector_nmi:fallback:8
        terminal_rom_vector_nmi:fallback:8
    )
    for entry in "${scenarios[@]}"; do
        IFS=: read -r scenario disk device <<<"$entry"
        case "$disk" in
            krill) disk="$krill_d64" ;;
            noart) disk="$krill_noart_d64" ;;
            *) disk="$fallback_d64" ;;
        esac
        timeout=30
        [ "$device" = 9 ] && timeout=90
        if ! python3 -u tests/boot_handoff_smoke.py \
                --scenario "$scenario" --vice "$VICE" --boot-d64 "$disk" \
                --boot-prg "$out/boot.prg" --device "$device" \
                --boot-vs "$boot_vs" --main-vs "$main_vs" \
                --kinst-prg ../../../build/test/c64/kinst64.prg \
                --kres-prg ../../../build/test/c64/kres64.prg \
                --port "$VICE_MONITOR_PORT" --timeout "$timeout"; then
            echo "FAIL ($scenario)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    echo "PASS (${#scenarios[@]} production scenarios)"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_retirement_royal_product_smoke() {

    local name="retirement_royal_product_smoke"
    echo -n "  $name: "

    local smoke_out build_log smoke_c64 boot_d64 main_vs marker_blob
    smoke_out=$(mktemp -d "${TMPDIR:-/tmp}/moria8-c64-retirement.XXXXXX")
    smoke_c64="$smoke_out/c64"
    boot_d64="$smoke_out/moria8-c64.d64"
    main_vs="$smoke_c64/main.vs"
    marker_blob="$smoke_out/MORIA8.ID"
    build_log=$(mktemp -t "build_${name}_log")
    seed_product_build_out "$smoke_out"

    if ! make -s -C "$REPO_ROOT/platforms/commodore" \
            KICKASS="$KICKASS" \
            OUT="$smoke_out" \
            KA_FLAGS64="-showmem -vicesymbols -libdir ../../core -libdir common -afo -libdir c64 -define DEBUG_FEAT_DISK_TRACE=0 -define C64_TEST_SCRIPTED_RETIREMENT_PRODUCT" \
            build64 >"$build_log" 2>&1; then
        echo "FAIL (product build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$C1541" -format "moria8 c64,m8" d64 "$boot_d64" \
            -attach "$boot_d64" \
            -write "$smoke_c64/boot.prg" "moria8" \
            -write "$smoke_c64/boot.prg" "boot64" \
            -write "$smoke_c64/bootart64.prg" "bootart64" \
            -write "$smoke_c64/kinst64.prg" "kinst64" \
            -write "$smoke_c64/kres64.prg" "kres64" \
            -write "$smoke_c64/kinst41.prg" "kinst41" \
            -write "$smoke_c64/moria8.prg" "moria64" \
            -write "$smoke_c64/64.init" "64.init" \
            -write "$smoke_c64/64.bank" "64.bank" \
            -write "$smoke_c64/title" "t64" \
            -write "$marker_blob" "MORIA8.ID" \
            -write "$smoke_c64/monster.db.1" "monster.db.1" \
            -write "$smoke_c64/monster.db.2" "monster.db.2" \
            -write "$smoke_c64/monster.db.3" "monster.db.3" \
            -write "$smoke_c64/monster.db.4" "monster.db.4" \
            -write "$smoke_c64/ovl.start" "64.start" \
            -write "$smoke_c64/ovl.town" "64.town" \
            -write "$smoke_c64/ovl.death" "64.death" \
            -write "$smoke_c64/ovl.modal" "64.modal" \
            -write "$smoke_c64/ovl.gen" "64.gen" \
            -write "$smoke_c64/ovl.help" "64.help" \
            -write "$smoke_c64/ovl.ui" "64.ui" \
            -write "$smoke_c64/ovl.items" "64.items" \
            -write "$smoke_c64/ovl.spell" "64.spell" \
            -write "$smoke_c64/ovl.chest" "64.chest" >"$build_log" 2>&1; then
        echo "FAIL (product disk image)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --pass-symbol ".c64_test_retirement_pass_sym" \
            --fail-symbol ".c64_test_retirement_fail_sym" \
            --main-vs "$main_vs" \
            --boot-d64 "$boot_d64" \
            --vice "$VICE" \
            --timeout 20 \
            --retry-timeouts 0 \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_save_write_product_smoke() {
    run_save_write_product_smoke_impl "save_write_product_smoke" \
        "C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT" \
        "the.game,s" \
        '"THE.GAME".*SEQ' \
        "post_save_krill"
}

run_resume_missing_kinst41_product_smoke() {
    run_save_write_product_smoke_impl "resume_missing_kinst41_product_smoke" \
        "C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT" \
        "the.game,s" \
        '"THE.GAME".*SEQ' \
        "post_save_krill" \
        "missing_kinst41"
}

run_slot2_save_product_smoke() {
    run_save_write_product_smoke_impl "slot2_save_product_smoke" \
        "C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT" \
        "the.game2,s" \
        '"THE.GAME2".*SEQ'
}

run_save_write_product_smoke_impl() {
    local name="$1"
    local test_define="$2"
    local save_filename="$3"
    local expected_save_re="$4"
    local post_save_mode="${5:-}"
    local resume_failure_mode="${6:-}"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define "$test_define" \
            -o "../../../build/test/c64/${name}.prg" >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/${name}.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/c64/kinst64.prg "kinst64" \
            -write ../../../build/c64/kres64.prg "kres64" \
            -write ../../../build/c64/kinst41.prg "kinst41" \
            -write "../../../build/test/c64/${name}.prg" "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if [ "$resume_failure_mode" = "missing_kinst41" ] && \
            ! "$C1541" -attach "$scripted_d64" -delete "kinst41" >>"$build_log" 2>&1; then
        echo "FAIL (failed to remove resume installer)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="../../../build/test/c64/THE.GAME"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    local save_d64="../../../build/test/c64/${name}_save.d64"
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
            -write "$save_blob" "$save_filename" >"$build_log" 2>&1; then
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

    local main_vs="../../../build/test/c64/main.vs"
    local pass_symbol=".title_menu_loop"
    local drive9_args=(
        --start-symbol ".title_menu_loop"
        --native-start
        --attach9-at-start-d64 "$save_d64"
    )
    if [ "$post_save_mode" = "post_save_krill" ]; then
        pass_symbol=".c64_test_post_save_krill_overlay_pass"
        drive9_args=(
            --save-d64 "$save_d64"
            --enable-drive9-bus
        )
    fi
    local krill_state_expectations=(
        --expect-byte-symbol ".krill_active=0xff"
        --expect-byte-symbol ".krill_suspended=0x00"
    )
    if [ "$resume_failure_mode" = "missing_kinst41" ]; then
        krill_state_expectations=(
            --expect-byte-symbol ".krill_active=0x00"
            --expect-byte-symbol ".krill_suspended=0x00"
        )
    fi
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            "${drive9_args[@]}" \
            --drive8-type 1542 \
            --drive9-type 1542 \
            --main-vs "$main_vs" \
            --require-hit-symbol ".c64_test_after_save_restart_start" \
            --pass-symbol "$pass_symbol" \
            --fail-symbol ".c64_test_save_write_fail_input_sym" \
            "${krill_state_expectations[@]}" \
            --expect-byte-symbol ".krill_boot_used=0x01" \
            --c64-ram-breakpoints \
            --timeout 20 \
            --retry-timeouts 0 \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi "$expected_save_re"; then
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

    echo "FAIL (save-write product harness)"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_save_media_fail_product_smoke() {
    local name="save_media_fail_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT \
            -o ../../../build/test/c64/moria_save_media_fail_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_save_media_fail_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_save_media_fail_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="../../../build/test/c64/THE.GAME"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    local save_d64="../../../build/test/c64/moria_save_media_fail_save.d64"
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

    local main_vs="../../../build/test/c64/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.c64_test_after_save_media_fail$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.save_select_output_name_c64$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing save-media-fail smoke symbols in ../../../build/test/c64/main.vs)"
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

run_change_save_drive_product_smoke() {
    local name="change_save_drive_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT \
            -o ../../../build/test/c64/moria_change_save_drive_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_change_save_drive_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_change_save_drive_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save10_d64="../../../build/test/c64/moria_change_save_drive_save10.d64"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    rm -f "$save10_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save10_d64" \
            -attach "$save10_d64" \
            -write "$marker_blob" "moria8.id,s" >"$build_log" 2>&1; then
        echo "FAIL (drive-10 save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --save10-d64 "$save10_d64" \
            --main-vs ../../../build/test/c64/main.vs \
            --start-symbol ".c64_test_change_save_drive_wait_for_harness" \
            --resume-symbol ".c64_test_change_save_drive_before_save" \
            --pass-symbol ".c64_test_change_save_drive_pass" \
            --fail-symbol ".c64_test_change_save_drive_unexpected_return" \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save10_d64" -list 2>&1); then
            echo "FAIL (drive-10 save disk listing error)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        elif echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL (drive-10 save disk missing THE.GAME)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        fi
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT \
            -o ../../../build/test/c64/moria_disk_setup_single_drive_return.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_disk_setup_single_drive_return.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/c64/kinst64.prg "kinst64" \
            -write ../../../build/c64/kres64.prg "kres64" \
            -write ../../../build/c64/kinst41.prg "kinst41" \
            -write ../../../build/test/c64/moria_disk_setup_single_drive_return.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="../../../build/test/c64/moria_disk_setup_single_drive_return_save.d64"
    local program_d64="../../../build/test/c64/moria_disk_setup_single_drive_return_program.d64"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    rm -f "$save_d64" "$program_d64"
    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation error)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$scripted_d64" "$program_d64"

    local main_vs="../../../build/test/c64/main.vs"
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "$main_vs" \
            --start-symbol ".c64_test_disk_setup_single_drive_return_wait_for_harness" \
            --resume-symbol ".c64_test_disk_setup_single_drive_return_before_disk_setup" \
            --pass-symbol ".c64_test_after_disk_setup_single_drive_return" \
            --swap-symbol ".uds_insert_prompt_wait_key" \
            --swap-attach8-d64 "$save_d64" \
            --swap2-symbol ".disk_prompt_game_required_error_shown" \
            --swap2-attach8-d64 "$program_d64" \
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

run_disk_setup_then_load_prompts_save_product_smoke() {
    local name="disk_setup_then_load_prompts_save_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_DISK_SETUP_THEN_LOAD_PRODUCT \
            -o ../../../build/test/c64/moria_disk_setup_then_load.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_disk_setup_then_load.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/c64/kinst64.prg "kinst64" \
            -write ../../../build/c64/kres64.prg "kres64" \
            -write ../../../build/c64/kinst41.prg "kinst41" \
            -write ../../../build/test/c64/moria_disk_setup_then_load.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="../../../build/test/c64/moria_disk_setup_then_load_save.d64"
    local program_d64="../../../build/test/c64/moria_disk_setup_then_load_program.d64"
    rm -f "$save_d64" "$program_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$scripted_d64" "$program_d64"

    local main_vs="../../../build/test/c64/main.vs"
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs "$main_vs" \
            --start-symbol ".c64_test_disk_setup_single_drive_return_wait_for_harness" \
            --resume-symbol ".c64_test_disk_setup_single_drive_return_before_disk_setup" \
            --pass-symbol ".c64_test_disk_setup_then_load_save_prompt_seen" \
            --swap-symbol ".uds_insert_prompt_wait_key" \
            --swap-attach8-d64 "$save_d64" \
            --swap2-symbol ".disk_prompt_game_required_error_shown" \
            --swap2-attach8-d64 "$program_d64" \
            --screen-base 0x0400; then
        echo "PASS"
        PASS=$((PASS + 1))
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/kinst64.prg ../../build/c64/kres64.prg ../../build/c64/kinst41.prg \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SLOT2_LOAD_PRODUCT \
            -o ../../../build/test/c64/moria_load_resume_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_load_resume_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/c64/kinst64.prg "kinst64" \
            -write ../../../build/c64/kres64.prg "kres64" \
            -write ../../../build/c64/kinst41.prg "kinst41" \
            -write ../../../build/test/c64/moria_load_resume_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="../../../build/test/c64/THE.GAME"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    local save_d64="../../../build/test/c64/moria_load_resume_save.d64"
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
            -write "$save_blob" "the.game2,s" >"$build_log" 2>&1; then
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

    local main_vs="../../../build/test/c64/main.vs"
    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --save-d64 "$save_d64" \
            --enable-drive9-bus \
            --start-symbol ".c64_test_slot2_load_wait_for_harness" \
            --resume-symbol ".c64_test_slot2_load_resume" \
            --drive8-type 1542 \
            --drive9-type 1542 \
            --main-vs "$main_vs" \
            --require-hit-symbol ".krill_load_file" \
            --pass-symbol ".c64_test_after_load_resume_game" \
            --fail-symbol ".c64_test_load_resume_fail_input_sym" \
            --expect-byte-symbol ".krill_active=0xff" \
            --expect-byte-symbol ".krill_suspended=0x00" \
            --expect-byte-symbol ".krill_boot_used=0x01" \
            --expect-byte-symbol ".c64_test_restored_map_last=0x10" \
            --c64-ram-breakpoints \
            --timeout 45 \
            --retry-timeouts 0 \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_single_drive_load_return_product_smoke() {
    local name="single_drive_load_return_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT \
            -o ../../../build/test/c64/moria_single_drive_load_return_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_single_drive_load_return_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_single_drive_load_return_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="../../../build/test/c64/THE.GAME"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    local save_d64="../../../build/test/c64/moria_single_drive_load_return_save.d64"
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
            --main-vs "../../../build/test/c64/main.vs" \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT \
            -o ../../../build/test/c64/moria_load_then_save_new_empty.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_load_then_save_new_empty.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_load_then_save_new_empty.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="../../../build/test/c64/THE.GAME"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
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
            --main-vs "../../../build/test/c64/main.vs" \
            --start-symbol ".c64_test_load_then_save_new_empty_wait_for_harness" \
            --resume-symbol ".c64_test_load_then_save_new_empty_resume_low" \
            --attach8-at-start-d64 "$load_save_d64" \
            --swap-symbol ".c64_test_load_then_save_new_empty_before_save" \
            --swap-attach8-d64 "$new_save_d64" \
            --swap2-symbol ".disk_prompt_game_required_error_shown" \
            --swap2-attach8-d64 "$swap_program_d64" \
            --swap3-symbol ".uds_show_insert_prompt" \
            --swap3-attach8-d64 "$new_save_d64" \
            --swap4-symbol ".c64_test_load_then_save_new_empty_before_program_prompt" \
            --swap4-attach8-d64 "$swap_program_d64" \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT \
            -o ../../../build/test/c64/moria_single_drive_save_wrong_media_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_single_drive_save_wrong_media_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_single_drive_save_wrong_media_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
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
            --main-vs "../../../build/test/c64/main.vs" \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT \
            -o ../../../build/test/c64/moria_single_drive_load_wrong_media_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_single_drive_load_wrong_media_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_single_drive_load_wrong_media_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
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
            --main-vs "../../../build/test/c64/main.vs" \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT \
            -o ../../../build/test/c64/moria_single_drive_load_corrupt_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_single_drive_load_corrupt_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_single_drive_load_corrupt_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_blob="../../../build/test/c64/THE.GAME"
    local marker_blob="../../../build/test/c64/MORIA8.ID"
    local save_d64="../../../build/test/c64/moria_single_drive_load_corrupt_save.d64"
    local program_d64="../../../build/test/c64/moria_single_drive_load_corrupt_program.d64"
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
            --main-vs "../../../build/test/c64/main.vs" \
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT \
            -o ../../../build/test/c64/moria_single_drive_fresh_save_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_single_drive_fresh_save_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_single_drive_fresh_save_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
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

    local main_vs="../../../build/test/c64/main.vs"
    local start_addr resume_addr swap_addr pass_addr fail_addr
    start_addr=$(awk '/\.c64_test_single_drive_fresh_save_wait_for_harness$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    resume_addr=$(awk '/\.c64_test_single_drive_fresh_save_resume_low$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    swap_addr=$(awk '/\.disk_prompt_game_required_error_shown$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    pass_addr=$(awk '/\.c64_test_after_save_restart_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_single_drive_fresh_save_unexpected_return$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${start_addr:-}" ] || [ -z "${resume_addr:-}" ] || [ -z "${swap_addr:-}" ] || \
            [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing fresh-save smoke symbols in ../../../build/test/c64/main.vs)"
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
            --resume-symbol ".c64_test_single_drive_fresh_save_resume_low" \
            --swap-symbol ".c64_test_single_drive_fresh_save_before_save" \
            --swap-attach8-d64 "$save_d64" \
            --swap2-symbol ".disk_prompt_game_required_error_shown" \
            --swap2-attach8-d64 "$swap_program_d64" \
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

run_single_drive_fresh_save_no_init_product_smoke() {
    local name="single_drive_fresh_save_no_init_product_smoke"
    echo -n "  $name: "

    local build_log
    build_log=$(mktemp -t "build_${name}_log")
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT \
            -define C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT \
            -o ../../../build/test/c64/moria_single_drive_fresh_save_no_init_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_single_drive_fresh_save_no_init_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_single_drive_fresh_save_no_init_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local save_d64="/tmp/moria_single_drive_fresh_save_no_init_$$.d64"
    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (save disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$scripted_d64" \
            --main-vs ../../../build/test/c64/main.vs \
            --start-symbol ".c64_test_single_drive_fresh_save_wait_for_harness" \
            --resume-symbol ".c64_test_single_drive_fresh_save_resume_low" \
            --swap-symbol ".c64_test_single_drive_fresh_save_before_save" \
            --swap-attach8-d64 "$save_d64" \
            --pass-symbol ".c64_test_single_drive_fresh_save_no_init_return" \
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
        if echo "$dir_list" | grep -qi '"THE.GAME"'; then
            echo "FAIL (no-init path wrote THE.GAME)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        else
            echo "PASS"
            PASS=$((PASS + 1))
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
    mkdir -p ../../../build/test/c64

    if ! make -s -C .. ../../build/c64/boot.prg ../../build/c64/bootart64.prg ../../build/c64/title \
            ../../build/c64/monster.db.1 ../../build/c64/monster.db.2 ../../build/c64/monster.db.3 ../../build/c64/monster.db.4 \
            >"$build_log" 2>&1; then
        echo "FAIL (asset build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -showmem -vicesymbols \
            -define C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT \
            -o ../../../build/test/c64/moria_load_missing_save_smoke.prg >"$build_log" 2>&1; then
        echo "FAIL (assembly error)"
        grep -i error "$build_log" | head -5
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local scripted_d64="../../../build/test/c64/moria_load_missing_save_smoke.d64"
    rm -f "$scripted_d64"
    if ! "$C1541" -format "moria8 c64,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c64/boot.prg "moria8" \
            -write ../../../build/test/c64/boot.prg "boot64" \
            -write ../../../build/test/c64/bootart64.prg "bootart64" \
            -write ../../../build/test/c64/moria_load_missing_save_smoke.prg "moria64" \
            -write ../../../build/test/c64/64.init "64.init" \
            -write ../../../build/test/c64/64.bank "64.bank" \
            -write ../../../build/test/c64/title "t64" \
            -write ../../../build/test/c64/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c64/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c64/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c64/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c64/ovl.start "64.start" \
            -write ../../../build/test/c64/ovl.town "64.town" \
            -write ../../../build/test/c64/ovl.death "64.death" \
            -write ../../../build/test/c64/ovl.modal "64.modal" \
            -write ../../../build/test/c64/ovl.gen "64.gen" \
            -write ../../../build/test/c64/ovl.help "64.help" \
            -write ../../../build/test/c64/ovl.ui "64.ui" \
            -write ../../../build/test/c64/ovl.items "64.items" \
            -write ../../../build/test/c64/ovl.spell "64.spell" \
            -write ../../../build/test/c64/ovl.chest "64.chest" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local marker_blob="../../../build/test/c64/MORIA8.ID"
    local save_d64="../../../build/test/c64/moria_load_missing_save.d64"
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

    local main_vs="../../../build/test/c64/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.c64_test_after_load_missing_save_return$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c64_test_load_missing_save_fail_input_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing load-missing-save smoke symbol in ../../../build/test/c64/main.vs)"
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
        "$VICE" -warp -config /dev/null -default +saveres -console -nativemonitor -autostartprgmode 1 \
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

queue_product_suites() {
    run_suite_function "chest_open_product_smoke" run_chest_open_product_smoke
    run_suite_function "chest_open_product_reu_smoke" run_chest_open_product_reu_smoke
    run_suite_function "chest_open_product_genfail_smoke" run_chest_open_product_genfail_smoke
    run_suite_function "retirement_royal_product_smoke" run_retirement_royal_product_smoke "retirement_flow_product_smoke"
    run_suite_function "fastload_product_smoke" run_fastload_product_smoke "fastload_krill_active" "fastload_kernal_fallback"
    run_suite_function "boot_handoff_runtime_matrix" run_boot_handoff_runtime_matrix \
        "kinst_failure" "bootart_failure" "missing_bootart_krill" "display_integrity" "display_canary_failure" \
        "installer_1541u_warning" "installer_mute_failure" \
        "kernal_moria_failure" "kernal_init_failure" \
        "krill_install_success_cleanup" "kernal_success_cleanup" \
        "recovery_moria_failure" "recovery_init_failure" "recovery_success_cleanup" "p6_bank_failure" \
        "krill_moria_failure" "krill_bank_failure" "krill_init_failure" \
        "device9_krill" "device9_fallback" "rom_vector_nmi" "terminal_rom_vector_nmi"
    run_suite_function "title_disk_setup_single_drive_returns_program_prompt" run_disk_setup_single_drive_return_product_smoke "disk_setup_single_drive_return_product_smoke"
    run_suite_function "disk_setup_then_load_prompts_save_disk" run_disk_setup_then_load_prompts_save_product_smoke "disk_setup_then_load_prompts_save_product_smoke"
    run_suite_function "load_initialized_save" run_load_resume_product_smoke "load_resume_product_smoke"
    run_suite_function "prompt_sequence_no_repeat" run_single_drive_load_return_product_smoke "single_drive_load_return_product_smoke"
    run_suite_function "load_then_save_new_empty_disk" run_load_then_save_new_empty_product_smoke "load_then_save_new_empty_product_smoke"
    run_suite_function "change_save_drive_after_save" run_change_save_drive_product_smoke "change_save_drive_product_smoke" "alternate_drive_change_smoke" "alternate_drive_prompt_no_repeat"
    run_suite_function "single_drive_save_program_disk_rejected" run_single_drive_save_wrong_media_product_smoke "single_drive_save_wrong_media_product_smoke" "wrong_media_recovery"
    run_suite_function "single_drive_load_program_disk_rejected" run_single_drive_load_wrong_media_product_smoke "single_drive_load_wrong_media_product_smoke" "wrong_media_recovery" "wrong_media_detection_selected_devices"
    run_suite_function "single_drive_corrupt_save_recovery_requires_program_disk" run_single_drive_load_corrupt_product_smoke "single_drive_load_corrupt_product_smoke" "corrupt_save_file"
    run_suite_function "new_save_empty_init_writes" run_single_drive_fresh_save_product_smoke "single_drive_fresh_save_product_smoke"
    run_suite_function "new_save_empty_no_init_returns_setup" run_single_drive_fresh_save_no_init_product_smoke "single_drive_fresh_save_no_init_product_smoke" "cancel_supported_prompts"
    run_suite_function "load_missing_savefile_product_smoke" run_load_missing_savefile_product_smoke "missing_device_or_no_disk"
    run_suite_function "save_media_fail_product_smoke" run_save_media_fail_product_smoke "wrong_media_detection_selected_devices" "write_protected_or_forced_write_error"
    run_suite_function "dual_drive_load_then_save_no_program_prompt" run_save_write_product_smoke "save_existing_overwrite" "save_write_product_smoke"
    run_suite_function "resume_missing_kinst41_product_smoke" run_resume_missing_kinst41_product_smoke
    run_suite_function "slot2_save_product_smoke" run_slot2_save_product_smoke
    run_suite_function "disk_setup_product_smoke" run_disk_setup_product_smoke
    run_suite_function "scripted_spell_cast_smoke" run_scripted_spell_cast_smoke
    run_suite_function "scripted_book_overlay_smoke" run_scripted_book_overlay_smoke
    run_suite_function "scripted_scroll_selector_smoke" run_scripted_scroll_selector_smoke
    run_suite_function "scripted_spell_list_overlay_smoke" run_scripted_spell_list_overlay_smoke
    run_suite_function "scripted_dungeon_target_spell_smoke" run_scripted_dungeon_target_spell_smoke
    run_suite_function "scripted_detect_evil_smoke" run_scripted_detect_evil_smoke
    run_suite_function "dungeon_ascent_product_smoke" run_dungeon_ascent_product_smoke
    run_suite_function "wizard_reveal_product_smoke" run_wizard_reveal_product_smoke
    run_suite_function "wizard_item_product_smoke" run_wizard_item_product_smoke
    run_suite_function "media_drive8_attach_read_write" run_media_drive8_attach_read_write
    run_suite_function "media_drive9_attach_read_write" run_media_drive9_attach_read_write
    run_suite_function "media_drive10_11_device_probe" run_media_drive10_11_device_probe "alternate_drive10_11_save_load_smoke"
}

echo "=== Moria Phase 1 Tests ==="
echo ""
queue_product_suites

# Build main program first (compile-time asserts)
echo -n "  main.s assembly: "
cd "$RUN_TESTS64_DIR"
asm_out=$(java -jar "$KICKASS" "${KICKASS_TRACE_DEFINE[@]}" main.s :OVL_OUT=../../../build/test/c64 -o moria.prg 2>&1)
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

check_static_contract "wizard_heal_contract" "../../../core/wizard.s" \
    "wizard_cmd_heal_cure:|||lda player_data + PL_MAX_MANA|||sta player_data + PL_MANA|||sta zp_player_mp|||sta zp_player_mmp"
check_static_contract "wizard_footer_full_copy_contract" "../../../core/wizard.s" \
    "wiz_footer_str:|||.text \"Q to cancel\""
check_static_contract "wizard_cancel_text_contract" "../../../core/wizard.s" \
    "wiz_row4_str:|||.text \"Q to cancel\""
check_static_contract "wizard_menu_aligned_rows_contract" "../../../core/wizard.s" \
    "wiz_row1_str:|||.text \"L jump    A reveal    H heal\"|||wiz_row2_str:|||.text \"I ident   X level     G item\"|||wiz_row3_str:|||.text \"S summon  T tele      W wall\""
check_static_contract "wizard_item_prompt_range_contract" "../../../core/wizard.s" \
    "wiz_item_prompt_str:|||.text \"ITEM 0-135: \""
check_static_contract "wizard_bad_prompt_cleanup_contract" "../../../core/wizard.s" \
    "wizard_prompt_bad_value:|||jsr msg_print|||jmp wizard_prompt_clear_digits|||wizard_prompt_two_digit:|||jsr wizard_prompt_bad_value|||jmp !wiz_num_loop-"
check_static_contract "c64_disk_prompt_dismiss_clears_full_modal_contract" "../common/disk_swap.s" \
    "disk_prompt:|||jsr hal_input_get_key|||jsr ui_clear_full_screen_safe|||jsr msg_init|||jsr hal_storage_init_selected_drive"
check_static_contract "disk_setup_insert_dismiss_clears_modal_contract" "../../../core/ui_disk_setup.s" \
    "uds_show_insert_prompt:|||jsr input_get_modal_dismiss_key|||lda #DISK_UI_RES_OK|||sta disk_ui_result|||jsr uds_clear_after_modal"
check_static_contract "load_resume_suppresses_tier_loading_message_contract" "../../../core/game_loop.s" \
    "load_resume_game:|||jsr tier_invalidate_state|||jsr tier_restore_after_overlay"
check_static_contract "learn_spell_followup_contract" "../../../core/player_gain_spell_impl.s" \
    "item_gain_spell:|||jsr input_prepare_modal_dismiss_key|||jsr spell_list_display|||jsr hal_input_get_key|||jsr pm_pick_visible_spell"
check_static_contract "book_prompt_fresh_key_contract" "../../../core/player_item_select.s" \
    "piw_select_filtered_inv:|||jsr piw_prompt_filtered_inv|||jsr input_prepare_followup_key|||jsr hal_input_get_key|||piw_select_filtered_inv_key:|||jsr piw_pick_filtered_inv_key"
check_static_contract "c64_wait_release_physical_key_contract" "input.s" \
    "input_wait_release:|||!iwr_wait:|||lda KBDBUF_COUNT|||bne !iwr_drain-|||jsr input_run_key_held|||bne !iwr_wait-|||lda KBDBUF_COUNT"
check_static_contract "c64_charset_switch_locked_before_irq_input_contract" "input.s" \
    "input_get_key:|||lda #BANK_NO_BASIC|||sta \$01|||jsr c64_install_ram_irq_vectors|||jsr input_lock_charset_switch|||cli|||!igk_poll:"
check_static_contract "c64_charset_switch_locked_before_irq_release_contract" "input.s" \
    "input_wait_release:|||lda #BANK_NO_BASIC|||sta \$01|||jsr c64_install_ram_irq_vectors|||jsr input_lock_charset_switch|||cli|||!iwr_drain:"
check_static_contract "c64_input_restores_bank_before_irq_contract" "input.s" \
    "input_get_key:|||jsr KERNAL_GETIN|||sta igk_key|||sei|||pla|||sta \$01|||jsr c64_install_ram_irq_vectors|||plp|||lda igk_key"
check_static_contract "inventory_overlay_fresh_key_contract" "../../../core/player_items.s" \
    "show_inv_and_select:|||jsr input_prepare_selectable_overlay_key|||jsr tramp_ui_inv_select_display|||jsr input_get_followup_key"
check_static_contract "inventory_overlay_items_reload_contract" "../../../core/player_items.s" \
    "show_inv_and_select:|||lda piw_return_overlay|||bne !sias_have_return_overlay+|||tsx|||lda \$0102,x|||cmp #hal_platform_overlay_window_hi_min|||!sias_check_outer_return:|||lda \$0104,x|||!sias_return_overlay:|||lda current_overlay|||cmp #OVL_ITEMS|||!sias_store_return_overlay:|||sta piw_return_overlay|||jsr ui_view_restore_modal_overlay|||lda #OVL_NONE|||sta piw_return_overlay|||txa|||beq !sias_no_overlay_reload+|||jsr overlay_load|||brk|||sei|||jsr hal_irq_install_runtime|||lda #BANK_NO_KERNAL|||sta hal_memory_cpu_port"
check_static_contract "item_action_inventory_overlay_hint_contract" "../../../core/item_actions_overlay.s" \
    "item_action_select_filtered_inv:|||jsr item_action_get_key|||cmp #\$3f|||lda #OVL_ITEMS|||sta piw_return_overlay|||jmp piw_select_filtered_inv_key"
check_static_contract "spell_recharge_inventory_overlay_hint_contract" "../../../core/player_magic_execute_overlay.s" \
    "pmx_pick_recharge_item:|||jsr hal_input_get_key|||cmp #\$3f|||lda #OVL_SPELL|||sta piw_return_overlay|||jmp piw_select_filtered_inv_key"
check_static_contract "identify_scroll_resident_completion_contract" "../../../core/item_actions_overlay.s" \
    "irs_effect_identify:|||jmp eff_identify_scroll_resident"
check_static_contract "itemdesc_armor_brackets_screen_code_contract" "../../../core/item_desc_banked.s" \
    "!idps_armor:|||jsr itemdesc_put_open_bracket|||lda #\$1d                    // ']' screen code|||!idps_ring_ac_has_bonus:|||jsr itemdesc_put_open_bracket|||lda #\$1d                    // ']' screen code|||itemdesc_put_open_bracket:|||lda #\$1b                    // '[' screen code"
check_static_contract "save_split_item_stats_contract" "../../shared/save.s" \
    "save_block_table_inventory_current:|||:save_block_desc(inv_p1, TOTAL_INV_SLOTS)|||:save_block_desc(inv_to_hit, TOTAL_INV_SLOTS)|||:save_block_desc(inv_to_dam, TOTAL_INV_SLOTS)|||:save_block_desc(inv_to_ac, TOTAL_INV_SLOTS)|||save_block_table_inventory_legacy:|||:save_block_desc(inv_p1, LEGACY_TOTAL_INV_SLOTS)|||:save_block_desc(si_p1, STORE_TOTAL_SLOTS)|||:save_block_desc(si_to_hit, STORE_TOTAL_SLOTS)|||:save_block_desc(si_to_dam, STORE_TOTAL_SLOTS)|||:save_block_desc(si_to_ac, STORE_TOTAL_SLOTS)|||save_block_table_floor_items_direct:|||:save_block_desc(fi_qty, MAX_FLOOR_ITEMS)|||:save_block_desc(fi_to_hit, MAX_FLOOR_ITEMS)|||:save_block_desc(fi_to_dam, MAX_FLOOR_ITEMS)|||:save_block_desc(fi_to_ac, MAX_FLOOR_ITEMS)|||load_read_floor_block_table:|||lda load_floor_item_count|||jsr load_read_block|||save_write_floor_items:|||lda #<save_block_table_floor_items_direct|||jsr save_write_block_table|||lda #<SAVE_BLOCK_FLOOR_ITEMS_STAT_TABLE|||jsr save_write_block_table|||load_read_floor_items:|||lda #<save_block_table_floor_items_direct|||jsr load_read_floor_block_table|||lda #<SAVE_BLOCK_FLOOR_ITEMS_STAT_TABLE|||jsr load_read_floor_block_table"
check_static_contract "item_action_messages_stat_desc_contract" "../../../core/item.s" \
    "Build message: \"You picked up a <name>.\"|||lda fi_add_id|||jsr item_append_desc|||Build message: \"You drop a <name>.\"|||lda fi_add_id|||jsr item_append_desc|||item_append_desc:|||jsr item_append_name|||and #IF_IDENTIFIED"
check_static_contract "equip_action_messages_stat_desc_contract" "../../../core/player_item_commands.s" \
    "Build message: \"YOU ARE WIELDING A <name>.\"|||jmp piw_report_item_use|||piw_report_item_use:|||lda piw_item_id|||jsr item_append_desc|||Build message: \"YOU TAKE OFF THE <name>.\"|||jmp piw_report_item_use"
check_static_contract "throw_action_messages_stat_desc_contract" "../../../core/throw.s" \
    "tw_msg_item_prefix:|||jsr tw_stage_saved_item_fields|||lda tw_item_id|||jsr item_append_desc|||tw_stage_saved_item_fields:|||lda tw_save_to_hit|||sta fi_add_to_hit|||lda tw_save_to_dam|||sta fi_add_to_dam|||lda tw_save_flags|||sta fi_add_flags"
check_static_contract "equip_overlay_fresh_key_contract" "../../../core/player_items.s" \
    "show_equip_and_select:|||jsr input_prepare_selectable_overlay_key|||jsr tramp_ui_equip_select_display|||jsr input_get_followup_key"
check_static_contract "spell_list_overlay_fresh_key_contract" "../../../core/player_magic.s" \
    "!pm_psc_show_list:|||jsr input_prepare_selectable_overlay_key|||jsr tramp_spell_list_display|||jsr input_get_followup_key"
check_static_contract "overcast_faint_more_contract" "../../../core/player_magic.s" \
    "ldx #HSTR_PM_NO_MANA|||jsr huff_print_msg|||jsr msg_show_more|||jsr hal_input_get_key"
check_static_contract "paralysis_final_tick_message_contract" "../../../core/game_loop.s" \
    "lda zp_eff_paralyze|||beq !not_paralyzed+|||cmp #1|||bne !paralyzed_tick+|||jsr msg_clear|||!paralyzed_tick:|||jsr turn_post_action"
check_static_contract "earthquake_trampoline_no_hidden_kernal_load_contract" "main.s" \
    "tramp_eff_earthquake:|||sei|||lda #BANK_NO_KERNAL|||sta \$01|||jsr eff_earthquake_banked|||rts"
check_static_contract "chest_loot_gen_overlay_no_hidden_kernal_contract" "../../../core/chest_loot.s" \
    "chest_fulfill_loot:|||lda #OVL_DUNGEON_GEN|||#if C64_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME|||jsr overlay_load_no_kernal|||jsr hal_platform_runtime_resync|||!cfl_loaded:|||jsr chest_generate_loot|||jsr hal_platform_runtime_resync"
check_static_contract "chest_loot_c64_ego_overlay_return_contract" "../../../core/chest_loot.s" \
    "jsr roll_enchantment|||#if C64_PRODUCT_OVERLAY_RUNTIME|||jsr tramp_roll_ego_type_modal|||sta fi_add_ego"
check_static_contract "chest_loot_object_drop_marks_redraw_contract" "../../../core/chest_loot.s" \
    "!clpo_qty_done:|||jsr floor_item_add|||bcc !clpo_object_done+|||inc zp_dirty_count|||!clpo_object_done:|||jsr floor_item_add|||bcc !clpo_gold_done+|||inc zp_dirty_count|||!clpo_gold_done:"
check_static_contract "chest_search_vms_discovery_only_contract" "../../../core/chest_search.s" \
    "and #CHEST_P1_TRAP_FOUND|||bne !csr_found+|||ldx #HSTR_CHEST_FOUND_TRAP|||jsr huff_print_msg|||!csr_found:"
check_static_contract "spell_execute_dedicated_overlay_contract" "main.s" \
    "tramp_spell_execute_selected:|||ldx #27|||tramp_reveal_floorplan:|||ldx #28|||lda #OVL_SPELL|||tramp_overlay_target_lo:|||<spell_execute_selected, <eff_reveal_floorplan"
check_static_contract "priest_sense_surroundings_dispatch_contract" "../../../core/player_magic_execute_overlay.s" \
    "ped_tbl_lo:|||.byte <(ped_s20-1), <(PMX_EARTHQUAKE_TARGET-1), <(ped_s22-1), <(ped_s23-1)|||ped_tbl_hi:|||.byte >(ped_s20-1), >(PMX_EARTHQUAKE_TARGET-1), >(ped_s22-1), >(ped_s23-1)|||ped_s22:|||jmp PMX_MAP_AREA_TARGET"
check_static_contract "wizard_reveal_uses_spell_overlay_contract" "main.s" \
    "tramp_reveal_floorplan:|||ldx #28|||lda #OVL_SPELL|||tramp_overlay_target_hi:|||>spell_execute_selected, >eff_reveal_floorplan"
check_static_contract "c64_game_over_returns_to_title_contract" "main.s" \
    "game_over_prompt:|||lda #OVL_DEATH|||jsr overlay_load|||bcc !overlay_ok+|||jmp title_enter_menu|||!overlay_ok:|||sei|||dec \$01|||jmp game_restart_overlay"
check_static_contract "title_screen_clear_ownership_contract" "../common/title_screen.s" \
    "title_clear_full_screen:|||jsr hal_screen_clear_row|||cmp #SCREEN_ROWS|||title_clear_below_menu:|||lda #TITLE_CLEAR_FIRST_ROW|||sta title_clear_row|||jsr hal_screen_clear_row|||cmp #TITLE_CLEAR_AFTER_LAST_ROW|||title_load_and_draw:|||jsr title_clear_full_screen|||jsr title_render_data|||title_fallback_render:|||jsr title_clear_full_screen"
check_static_contract "c64_title_reentry_uses_owned_clear_contract" "main.s" \
    "title_enter_menu:|||jsr title_clear_full_screen|||jsr title_load_and_draw|||jsr title_clear_below_menu|||jsr msg_init|||jsr title_show_sysinfo|||jsr title_draw_menu"
check_static_contract "modal_restore_uses_safe_full_clear_contract" "../../../core/ui_restore.s" \
    "ui_view_redraw_gameplay_view:|||jsr ui_reset_message_state|||#if HAL_PLATFORM_RESTORE_TIER_AFTER_OVERLAY|||jsr tier_restore_after_overlay|||#endif|||jsr ui_clear_full_screen_safe|||jsr viewport_update|||jsr render_viewport|||jmp status_draw"
check_static_contract "c64_look_overlay_cleanup_contract" "main.s" \
    "tramp_do_look:|||ldx #10|||lda #OVL_MODAL_MISC|||tramp_overlay_dispatch:|||jsr overlay_load_no_kernal|||jmp tramp_sr_epilogue|||tramp_overlay_target_lo:|||<do_look"
check_static_contract "c64_restore_stages_map_load_only_contract" "../../../platforms/shared/save.s" \
    "save_block_table_post_floor:|||save_block_desc(MAP_BASE, MAP_SIZE)|||save_block_table_post_floor_load:|||save_block_desc(MAP_STAGE_BASE, MAP_SIZE)|||lda #<save_block_table_post_floor_load|||jsr load_read_block_table"
check_static_contract "c64_restore_resume_copy_order_contract" "main.s" \
    "title_load_game:|||jsr load_game|||jsr overlay_invalidate|||bcc !title_load_fail+|||jsr disk_prompt_game_required|||jsr krill_resume|||jsr map_stage_copy|||jmp load_resume_game"
check_static_contract "c64_hidden_kernal_irq_vector_contract" "main.s" \
    "c64_irq_hidden_rom:|||cld|||pha|||lda \$01|||pha|||lda #BANK_NO_KERNAL|||sta \$01|||lda \$dc0d|||lda \$dd0d|||lda \$d019|||sta \$d019|||pla|||sta \$01|||pla|||rti|||c64_install_ram_irq_vectors:|||php|||sei|||sta \$fffa|||sta \$fffe|||sta \$fffb|||sta \$ffff|||plp|||rts"
check_static_contract "c64_boot_true_address_init_contract" "boot.s" \
    "ART_BITMAP_DEST  = \$c000|||ART_SCREEN_DEST  = \$e000|||display_boot_art:|||jsr copy_color_to_vic_ram|||jsr copy_screen_to_vic_ram|||jsr copy_bitmap_to_vic_ram|||jsr boot_integrity_baseline|||jsr chain_integrity_checkpoint|||jsr chain_wait_18|||jsr chain_blank|||ldx #<init_filename|||jsr KRILL_BOOT_LOADRAW"
check_static_contract "c64_boot_kernal_cleanup_contract" "boot.s" \
    "boot_kernal_load:|||jsr \$ffd5|||php|||pha|||jsr \$ffc3|||jsr \$ffcc|||pla|||plp|||chain_kernal_load:|||jsr \$ffd5|||php|||pha|||jsr \$ffc3|||jsr \$ffcc|||pla|||plp"
check_static_contract "c64_boot_recovery_blanks_first_contract" "boot.s" \
    "chain_krill_fail:|||jsr chain_blank|||jsr KRILL_BOOT_UNINSTALL|||lda #VIC_BANK0_SELECT|||sta \$dd00"
check_static_contract "c64_boot_error_trampoline_contract" "boot.s" \
    "error_trampoline:|||pha|||php|||sei|||sta error_load_p|||sta error_load_a|||ldx #\$ff|||txs|||lda #\$37|||sta \$01|||jsr \$e544|||jmp (\$a002)"
check_static_contract "c64_boot_runtime_hook_contract" "boot.s" \
    "#if C64_TEST_BOOT_HANDOFF|||c64_test_boot_kernal_load_return:|||c64_test_kinst_call_return:|||c64_test_installer_pre:|||c64_test_installer_return:|||c64_test_installer_reblanked:|||c64_test_installer_result_restored:|||c64_test_installer_resident_copied:|||c64_test_installer_failure_continuation:|||c64_test_art_canaries_ready:|||c64_test_krill_moria_return:|||c64_test_krill_bank_return:|||c64_test_krill_init_return:|||c64_test_kernal_moria_pre:|||c64_test_kernal_moria_return:|||c64_test_kernal_init_pre:|||c64_test_kernal_init_return:|||c64_test_recovery_moria_pre:|||c64_test_recovery_moria_return:|||c64_test_recovery_init_pre:|||c64_test_recovery_init_return:|||c64_test_chain_kernal_load_return:|||c64_test_integrity_pre:"
check_static_contract "c64_p6_runtime_hook_contract" "main.s" \
    "c64_test_runtime_vectors_ready:|||c64_test_p6_bank_pre:|||jsr KERNAL_LOAD|||c64_test_p6_kernal_load_return:|||php|||pha|||jsr KERNAL_CLOSE|||jsr KERNAL_CLRCHN|||pla|||plp|||c64_test_p6_cleanup_return:|||c64_test_p6_bank_failure:"
check_static_contract "c64_boot_runtime_matrix_contract" "tests/boot_handoff_smoke.py" \
    "kinst_failure|||bootart_failure|||missing_bootart_krill|||display_integrity|||display_canary_failure|||installer_1541u_warning|||installer_mute_failure|||krill_install_success_cleanup|||kernal_success_cleanup|||device9_krill|||device9_fallback|||rom_vector_nmi|||terminal_rom_vector_nmi|||kernal_moria_failure|||kernal_init_failure|||krill_moria_failure|||krill_bank_failure|||krill_init_failure|||recovery_moria_failure|||recovery_init_failure|||recovery_success_cleanup|||p6_bank_failure"
check_static_contract "c64_boot_runtime_evidence_contract" "tests/boot_handoff_smoke.py" \
    "ERROR_MUTE_MESSAGE =|||WARNING_1541U_MESSAGE =|||def vendor_layout|||vendor message routine|||patched 1541U warning exit|||vendor second-device loop|||vendor mutefail path|||def snapshot_canaries|||read_bytes(self.connector, 0x0340, 77)|||def assert_canaries|||read_bytes(self.connector, 0x0340, 77)|||def assert_vendor_message_entry|||def assert_vendor_message_visible"
check_static_contract "c64_boot_mutefail_vendor_path_contract" "tests/boot_handoff_smoke.py" \
    "scenario == \"installer_mute_failure\"|||second_device_probe|||vendor second-device state is not device 9|||vendor active-device stack byte is not device 8|||set_register(\"pc\", int(self.vendor[\"mutefail\"]))|||vendor mutefail message entry|||vendor mutefail message return|||vendor mutefail path did not restore active FA|||self.assert_title(evidence=0x80)"
check_static_contract "c64_boot_recovery_success_cleanup_contract" "tests/boot_handoff_smoke.py" \
    "scenario == \"recovery_success_cleanup\"|||c64_test_recovery_moria_pre|||observe_chain_cleanup|||c64_test_recovery_init_pre|||observe_chain_cleanup|||c64_test_p6_bank_pre|||observe_chain_cleanup|||self.assert_title(evidence=0)"
check_static_contract "c64_boot_runtime_registration_contract" "run_tests.sh" \
    "missing_bootart_krill:noart:8|||display_integrity:krill:8|||display_canary_failure:krill:8|||installer_1541u_warning:krill:8|||installer_mute_failure:krill:8|||recovery_success_cleanup:krill:8|||device9_krill:krill:9|||device9_fallback:fallback:9|||rom_vector_nmi:fallback:8|||terminal_rom_vector_nmi:fallback:8|||\"missing_bootart_krill\"|||\"display_integrity\"|||\"display_canary_failure\"|||\"installer_1541u_warning\"|||\"installer_mute_failure\"|||\"recovery_success_cleanup\"|||\"device9_krill\"|||\"device9_fallback\"|||\"rom_vector_nmi\"|||\"terminal_rom_vector_nmi\""
check_static_contract "c64_boot_device9_runtime_contract" "tests/boot_handoff_smoke.py" \
    "if self.args.device == 9:|||+busdevice8|||drive8type|||drive9truedrive|||autostart|||self.args.boot_prg|||time.sleep(2.0)|||self.connector.poke(0xBA, self.args.device)|||scenario == \"device9_krill\"|||self.assert_title(evidence=0x81, device=9)|||scenario == \"device9_fallback\"|||self.assert_title(evidence=0x80, device=9)"
check_static_contract "c64_boot_rom_vector_nmi_contract" "tests/boot_handoff_smoke.py" \
    "def inject_nmi_and_continue_to|||send_command(\"nmi\")|||scenario == \"rom_vector_nmi\"|||c64_test_chain_rom_vectors_ready|||chain did not expose ROM vectors|||c64_test_runtime_vectors_ready|||scenario == \"terminal_rom_vector_nmi\"|||c64_test_terminal_rom_vectors_ready|||terminal path did not expose ROM vectors|||c64_test_terminal_before_warm_start"
check_static_contract "c64_main_init_tail_contract" "main.s" \
    ".segmentdef InitTail|||outPrg=OVL_OUT + \"/64.init\"|||program_end:|||.assert \"Program ends exactly at MAP_BASE\"|||.segment InitTail|||init_tail_start:|||init_tail_end:|||.assert \"InitTail content is 873 bytes\""
run_boot_disk_inventory_contract
run_c64_shipping_init_contract
check_static_contract "c64_modal_ego_restores_io_contract" "main.s" \
    "tramp_roll_ego_type_modal:|||lda #BANK_NO_ROMS|||jsr roll_ego_type|||pha|||lda #BANK_NO_KERNAL|||sta \$01|||pla|||rts"
check_static_contract "c64_disk_call_preserves_args_contract" "main.s" \
    "c64_disk_call:|||lda \$01|||sta c64_disk_call_saved_bank|||lda #\$36|||sta \$01|||cli|||pla|||tay|||pla|||tax|||pla|||!cdc_jsr:|||jsr \$ffff"
check_static_contract "c64_game_over_overlay_exit_contract" "main.s" \
    "game_restart_overlay:|||lda #>(title_enter_menu - 1)|||pha|||lda #<(title_enter_menu - 1)|||pha|||jmp platform_runtime_resync_c64"
check_static_contract "c64_save_media_hal_contract" "../../shared/save.s" \
    "!save_wrong_media:|||jsr hal_storage_save_media_status|||cmp #HAL_STORAGE_STATUS_WRONG_MEDIA|||jsr tramp_disk_prepare_selected|||bcc !save_media_ok+"
check_static_contract "c64_storage_classifier_export_contract" "hal/storage.s" \
    ".label hal_storage_save_media_status = disk_save_media_status"
check_static_contract "c64_storage_diag_export_contract" "hal/storage.s" \
    ".label hal_storage_diag_code = disk_status|||.label hal_storage_diag_device = save_device"
check_static_contract "c64_save_stream_banks_kernal_contract" "../../shared/save.s" \
    "!save_media_ok:|||lda #BANK_NO_BASIC|||sta hal_memory_cpu_port|||jsr save_select_output_name_c64"
check_static_contract "c64_load_stream_banks_kernal_contract" "../../shared/save.s" \
    "!load_media_ok:|||lda #BANK_NO_BASIC|||sta hal_memory_cpu_port|||ldx #HSTR_SAVE_LOADING"
run_vice_resource_contract

# Runtime tests
# Args: name, source, result memory range, expected pass count
run_test "math"   "tests/test_math.s"   "0400 040f" 16
run_test "rng"    "tests/test_rng.s"    "0400 0409" 10
run_test "memory" "tests/test_memory.s" "0400 0402" 3
run_test "config" "tests/test_config.s" "0400 0400" 1
run_test "input"  "tests/test_input.s"  "0400 040e" 15
run_test "main_loop" "tests/test_main_loop.s" "0400 042b" 44 500000000
run_test "run_visibility_bank" "tests/test_run_visibility_bank.s" "0400 0400" 1 500000000
run_test "turn" "tests/test_turn.s" "0400 041c" 29 500000000
run_test "player" "tests/test_player.s" "0400 0409" 10
run_test "dungeon" "tests/test_dungeon.s" "0400 0441" 66 500000000
run_test "monster" "tests/test_monster.s" "0400 0412" 19 500000000
run_test "monster_ai" "tests/test_monster_ai.s" "0400 0437" 56 500000000
run_test "combat" "tests/test_combat.s" "0400 0428" 41 500000000
run_test "msg_long" "tests/test_msg_long.s" "0400 0400" 1 20000000
run_test "monster_attack" "tests/test_monster_attack.s" "0400 040d" 14 500000000
run_test "effects" "tests/test_effects.s" "0400 041e" 31 1000000000
run_test "effects_magic" "tests/test_effects_magic.s" "0400 0433" 24 1000000000
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
run_test "sleep_ii" "tests/test_sleep_ii.s" "0400 0404" 5 500000000
run_test "sleep_iii" "tests/test_sleep_iii.s" "0400 0402" 3 500000000
run_test "cure_poison" "tests/test_cure_poison.s" "0400 0402" 3 500000000
run_test "fire_bolt" "tests/test_fire_bolt.s" "0400 0402" 3 500000000
run_test "slow_monster" "tests/test_slow_monster.s" "0400 0402" 3 500000000
run_test "polymorph_other" "tests/test_polymorph_other.s" "0400 0402" 3 500000000
run_test "identify_spell" "tests/test_identify_spell.s" "0400 0403" 4 500000000
run_test "teleport_self" "tests/test_teleport_self.s" "0400 0401" 2 500000000
run_test "remove_curse" "tests/test_remove_curse.s" "0400 0402" 3 500000000
run_test "find_hidden_traps_doors" "tests/test_find_hidden_traps_doors.s" "0400 0408" 9 500000000
run_test "chest_open" "tests/test_chest_open.s" "0400 040C" 13 500000000
run_test "chest_disarm" "tests/test_chest_disarm.s" "0400 0406" 7 500000000
run_test "chest_bash" "tests/test_chest_bash.s" "0400 0404" 5 500000000
run_test "chest_loot" "tests/test_chest_loot.s" "0400 0409" 10 500000000
run_test "balrog_victory" "tests/test_balrog_victory.s" "0400 0405" 6 500000000
run_test "stinking_cloud" "tests/test_stinking_cloud.s" "0400 0402" 3 500000000
run_test "frost_ball" "tests/test_frost_ball.s" "0400 0402" 3 500000000
run_test "teleport_other" "tests/test_teleport_other.s" "0400 0402" 3 500000000
run_test "haste_self" "tests/test_haste_self.s" "0400 0402" 3 500000000
run_test "fire_ball" "tests/test_fire_ball.s" "0400 0402" 3 500000000
run_test "word_of_destruction" "tests/test_word_of_destruction.s" "0400 0406" 7 500000000
run_test "light_area" "tests/test_light_area.s" "0400 0401" 2 500000000
run_test "phase_door" "tests/test_phase_door.s" "0400 0402" 3 500000000
run_test "genocide" "tests/test_genocide.s" "0400 0401" 2 500000000
run_test "directional_effects" "tests/test_directional_effects.s" "0400 0403" 4 500000000
run_test "overcast_ordering" "tests/test_overcast_ordering.s" "0400 0400" 1 500000000
run_test "ball_effects" "tests/test_ball_effects.s" "0400 0401" 2 500000000
run_test "utility_effects" "tests/test_utility_effects.s" "0400 040c" 13 500000000
run_test "detect_evil" "tests/test_detect_evil.s" "0400 0403" 4 500000000
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
run_test "dispel_evil_prayer" "tests/test_dispel_evil_prayer.s" "0400 0404" 5 500000000
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
run_test "item" "tests/test_item.s" "0400 0438" 57 1000000000
run_test "scroll_p3" "tests/test_scroll_p3.s" "0400 040d" 14 1000000000
run_test "item_desc" "tests/test_item_desc.s" "0400 0409" 10 500000000
run_test "item_ui" "tests/test_item_ui.s" "0400 040f" 16 1000000000
run_test "store" "tests/test_store.s" "0400 042a" 43 1000000000
run_test "ui_views" "tests/test_ui_views.s" "0400 0413" 19 500000000
run_test "ui_views_filters" "tests/test_ui_views_filters.s" "0400 0413" 7 500000000
run_test "subsystems" "tests/test_subsystems.s" "0400 0409" 10
run_sound_monitor_test
run_test "save"  "tests/test_save.s"  "0400 0421" 34 1000000000
run_test "score" "tests/test_score.s" "0400 040c" 13 500000000
run_test "wands_staves" "tests/test_wands_staves.s" "0400 0406" 7 100000000
run_test "monster_magic" "tests/test_monster_magic.s" "0400 040d" 14 500000000
run_test "tier" "tests/test_tier.s" "0400 0410" 17 500000000
run_test "disk_swap" "tests/test_disk_swap.s" "0400 040e" 15 500000000
run_test "render" "tests/test_render.s" "0400 0417" 24 500000000
run_test "ranged" "tests/test_ranged.s" "0400 0409" 10 500000000
run_test "ego" "tests/test_ego.s" "0400 0409" 10 500000000
run_test "throw" "tests/test_throw.s" "0400 040a" 11 500000000
run_test "bash" "tests/test_bash.s" "0400 040d" 14 500000000
run_test "tunnel" "tests/test_tunnel.s" "0400 0407" 8 500000000
run_test "background" "tests/test_background.s" "0400 0407" 8
run_test "look_trampoline" "tests/test_look_trampoline.s" "0400 0401" 2
run_parallel_suite_tests
run_parallel_unit_tests
echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
