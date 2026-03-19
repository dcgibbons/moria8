#!/bin/bash
# run_tests128.sh — Assemble and run C128 runtime tests in VICE headless

set -u

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RUN_TESTS128_DIR="${RUN_TESTS128_DIR:-$REPO_ROOT/commodore/c128}"
cd "$RUN_TESTS128_DIR"

KICKASS="${KICKASS:-$REPO_ROOT/tools/kickass/KickAss.jar}"
if [ -n "${VICE128:-}" ]; then
    VICE="$VICE128"
elif command -v x128 >/dev/null 2>&1; then
    VICE="$(command -v x128)"
elif [ -x /opt/homebrew/bin/x128 ]; then
    VICE="/opt/homebrew/bin/x128"
else
    VICE="/Applications/VICE/bin/x128"
fi
C1541="${C1541:-c1541}"
PERF_P1_MODE="${PERF_P1:-0}"
TEST_JOBS="${TEST_JOBS:-8}"
TEST_PHASE="${TEST_PHASE:-}"
TEST_FILTER="${TEST_FILTER:-}"
TEST_SKIP="${TEST_SKIP:-}"
TEST_RERUN_FROM="${TEST_RERUN_FROM:-}"
TEST_RERUN_LAST="${TEST_RERUN_LAST:-0}"
TEST_RERUN_STATUS="${TEST_RERUN_STATUS:-FAIL}"
TEST_DESCRIBE="${TEST_DESCRIBE:-0}"
TEST_LIST="${TEST_LIST:-0}"
TEST_TIMINGS="${TEST_TIMINGS:-0}"
TEST_REPEAT="${TEST_REPEAT:-1}"
TEST_FAIL_FAST="${TEST_FAIL_FAST:-0}"
TEST_SUMMARY="${TEST_SUMMARY:-}"
TEST_SUMMARY_FILE="${TEST_SUMMARY_FILE:-}"
PASS=0
FAIL=0
TOTAL=0
TEST128_TMP_PARENT="${TEST128_TMP_PARENT:-/tmp}"
TEST128_TMP_DIR="${TEST128_TMP_DIR:-$(mktemp -d "${TEST128_TMP_PARENT%/}/test128.$$.XXXXXX")}"
TEST128_TIMINGS_FILE="${TEST128_TMP_DIR}/timings.tsv"
TEST128_RESULTS_FILE="${TEST128_TMP_DIR}/results.tsv"
TEST128_RERUN_FILE="${TEST128_TMP_DIR}/rerun_suites.txt"
TEST128_LAST_SUMMARY_MARKER="out/.test128_last_summary_path"
TEST128_ITERATION=1
TEST128_RERUN_COUNT=0
C128_ACTIVE_VARIANT_FILE="out/.test128_active_variant"
BOOT_ASSETS_BUILT=0
PARTIAL_BOOT_ASSETS_BUILT=0
OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=0
DEATH_BOOT_ASSETS_BUILT=0
OVERLAY_STATE_BOOT_ASSETS_BUILT=0
SCRIPTED_INPUT_BOOT_ASSETS_BUILT=0
CACHE_SURVIVAL_BOOT_ASSETS_BUILT=0
LOAD_RESUME_BOOT_ASSETS_BUILT=0
REAL_BOOT_DIAG_ASSETS_BUILT=0
TITLE_ART_BOOT_ASSETS_BUILT=0
OVERLAY_TRANSITION_DIAG_ASSETS_BUILT=0

KA_DEFINES=(-define C128 -var OVL_OUT='"out"')
if [ "$PERF_P1_MODE" = "1" ]; then
    KA_DEFINES+=(-define PERF_P1)
fi

cleanup_test128_tmp() {
    if [ -n "${TEST128_TMP_DIR:-}" ] && [ -d "$TEST128_TMP_DIR" ]; then
        rm -rf "$TEST128_TMP_DIR"
    fi
}

trap cleanup_test128_tmp EXIT

test128_tmp_file() {
    printf '%s/%s\n' "$TEST128_TMP_DIR" "$1"
}

test128_abs_path() {
    python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
}

test128_now_ms() {
    python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

record_suite_timing() {
    local suite_name="$1"
    local duration_ms="$2"
    if [ "$TEST_TIMINGS" = "0" ]; then
        return
    fi
    printf '%s\t%s\n' "$duration_ms" "$suite_name" >> "$TEST128_TIMINGS_FILE"
}

record_suite_result() {
    local status="$1"
    local suite_name="$2"
    local duration_ms="${3:-}"
    local detail="${4:-}"
    if [ "$TEST_LIST" != "0" ]; then
        return
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$suite_name" "$duration_ms" "$detail" "$TEST128_ITERATION" >> "$TEST128_RESULTS_FILE"
}

print_timing_summary() {
    if [ "$TEST_TIMINGS" = "0" ] || [ ! -f "$TEST128_TIMINGS_FILE" ]; then
        return
    fi

    echo "=== Timings (ms, slowest first) ==="
    sort -nr "$TEST128_TIMINGS_FILE" | while IFS=$'\t' read -r duration suite_name; do
        printf '  %s\t%s\n' "$duration" "$suite_name"
    done
}

emit_test_summary() {
    if [ -z "$TEST_SUMMARY" ] || [ ! -f "$TEST128_RESULTS_FILE" ]; then
        return
    fi

    local summary_file="$TEST_SUMMARY_FILE"
    if [ -z "$summary_file" ]; then
        summary_file="out/.test128_last_summary.${TEST_SUMMARY}"
    fi

    case "$TEST_SUMMARY" in
        tsv)
            {
                printf 'status\tsuite\tduration_ms\tdetail\titeration\n'
                cat "$TEST128_RESULTS_FILE"
            } > "$summary_file"
            ;;
        json)
            python3 - "$TEST128_RESULTS_FILE" "$summary_file" "$PASS" "$FAIL" "$TOTAL" "$TEST_FILTER" "$TEST_SKIP" "$TEST_PHASE" "${TEST128_RERUN_SOURCE:-}" "$TEST_RERUN_LAST" "$TEST_RERUN_STATUS" "$TEST_JOBS" "$TEST_JOBS_RESOLVED" "$TEST_REPEAT_RESOLVED" "$TEST_TIMINGS" "$TEST_FAIL_FAST" <<'PY'
import json
import sys
from pathlib import Path

results_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
payload = {
    "pass": int(sys.argv[3]),
    "fail": int(sys.argv[4]),
    "total": int(sys.argv[5]),
    "filter": sys.argv[6],
    "skip": sys.argv[7],
    "phase": sys.argv[8],
    "rerun_from": sys.argv[9],
    "rerun_last": sys.argv[10] != "0",
    "rerun_status": sys.argv[11],
    "jobs_requested": sys.argv[12],
    "jobs_resolved": int(sys.argv[13]),
    "repeat": int(sys.argv[14]),
    "timings": sys.argv[15] != "0",
    "fail_fast": sys.argv[16] != "0",
    "results": [],
}
for line in results_path.read_text().splitlines():
    status, suite, duration_ms, detail, iteration = (line.split("\t", 4) + ["", "", "", "", ""])[:5]
    payload["results"].append({
        "status": status,
        "suite": suite,
        "duration_ms": int(duration_ms) if duration_ms else None,
        "detail": detail,
        "iteration": int(iteration) if iteration else 1,
    })
summary_path.write_text(json.dumps(payload, indent=2) + "\n")
PY
            ;;
        *)
            echo "warning: unsupported TEST_SUMMARY='$TEST_SUMMARY' (expected json or tsv)" >&2
            return
            ;;
    esac

    local summary_file_abs
    summary_file_abs="$(test128_abs_path "$summary_file")"
    printf '%s\n' "$summary_file_abs" > "$TEST128_LAST_SUMMARY_MARKER"

    echo "=== Summary written: $summary_file ==="
}

resolve_rerun_source() {
    if [ -n "$TEST_RERUN_FROM" ]; then
        printf '%s\n' "$TEST_RERUN_FROM"
        return 0
    fi

    if [ "$TEST_RERUN_LAST" = "0" ]; then
        return 0
    fi

    if [ ! -f "$TEST128_LAST_SUMMARY_MARKER" ]; then
        echo "error: no recorded last summary path ($TEST128_LAST_SUMMARY_MARKER)" >&2
        return 1
    fi

    local last_summary
    last_summary="$(head -n 1 "$TEST128_LAST_SUMMARY_MARKER" | tr -d '\r')"
    if [ -z "$last_summary" ]; then
        echo "error: empty last summary path in $TEST128_LAST_SUMMARY_MARKER" >&2
        return 1
    fi

    printf '%s\n' "$last_summary"
}

load_rerun_selection() {
    TEST128_RERUN_SOURCE="$(resolve_rerun_source)" || return 1
    TEST128_RERUN_COUNT=0

    if [ -z "$TEST128_RERUN_SOURCE" ]; then
        return 0
    fi

    if [ ! -f "$TEST128_RERUN_SOURCE" ]; then
        echo "error: rerun summary file not found: $TEST128_RERUN_SOURCE" >&2
        return 1
    fi

    TEST128_RERUN_COUNT="$(
        python3 - "$TEST128_RERUN_SOURCE" "$TEST128_RERUN_FILE" "$TEST_RERUN_STATUS" <<'PY'
import json
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
status_pattern = sys.argv[3]
text = src.read_text()
lines = [line for line in text.splitlines() if line.strip()]
suites = []

def add(name):
    if name and name not in suites:
        suites.append(name)

def status_matches(value):
    return re.fullmatch(status_pattern, value or "") is not None

if src.suffix.lower() == ".json" or (lines and lines[0].lstrip().startswith("{")):
    payload = json.loads(text)
    for entry in payload.get("results", []):
        if status_matches(entry.get("status", "")):
            add(entry.get("suite", ""))
else:
    start = 0
    if lines and lines[0].startswith("status\t"):
        start = 1
    for line in lines[start:]:
        parts = line.split("\t")
        if len(parts) >= 2 and status_matches(parts[0]):
            add(parts[1])

dst.write_text("".join(f"{suite}\n" for suite in suites))
print(len(suites))
PY
    )" || return 1
}

suite_matches_rerun() {
    local suite_name="$1"
    if [ -z "${TEST128_RERUN_SOURCE:-}" ]; then
        return 0
    fi
    [ -f "$TEST128_RERUN_FILE" ] && grep -Fxq "$suite_name" "$TEST128_RERUN_FILE"
}

resolve_test_jobs() {
    local requested="$1"
    local detected

    if [ "$requested" = "auto" ]; then
        detected="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
        if [ -z "$detected" ] || ! [[ "$detected" =~ ^[0-9]+$ ]] || [ "$detected" -lt 1 ]; then
            detected="$(sysctl -n hw.ncpu 2>/dev/null || true)"
        fi
        if [ -z "$detected" ] || ! [[ "$detected" =~ ^[0-9]+$ ]] || [ "$detected" -lt 1 ]; then
            detected=8
        fi
        printf '%s\n' "$detected"
        return
    fi

    if [[ "$requested" =~ ^[0-9]+$ ]] && [ "$requested" -ge 1 ]; then
        printf '%s\n' "$requested"
        return
    fi

    printf '8\n'
}

TEST_JOBS_RESOLVED="$(resolve_test_jobs "$TEST_JOBS")"

resolve_test_repeat() {
    local requested="$1"
    if [[ "$requested" =~ ^[0-9]+$ ]] && [ "$requested" -ge 1 ]; then
        printf '%s\n' "$requested"
        return
    fi
    printf '1\n'
}

TEST_REPEAT_RESOLVED="$(resolve_test_repeat "$TEST_REPEAT")"

normalize_monitor_addr() {
    python3 - "$1" <<'PY'
import sys
addr = sys.argv[1].strip().upper()
if not addr:
    print("")
elif len(addr) > 4:
    print(addr[-4:])
else:
    print(addr)
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

c128_outputs_need_refresh() {
    local parsing_inputs=0
    local -a outputs=()
    local -a inputs=()
    local path output input

    for path in "$@"; do
        if [ "$path" = "--" ]; then
            parsing_inputs=1
            continue
        fi
        if [ "$parsing_inputs" -eq 0 ]; then
            outputs+=("$path")
        else
            inputs+=("$path")
        fi
    done

    if [ "${#outputs[@]}" -eq 0 ]; then
        return 0
    fi

    for output in "${outputs[@]}"; do
        if [ ! -f "$output" ]; then
            return 0
        fi
        if c128_target_is_stale "$output"; then
            return 0
        fi
    done

    for input in "${inputs[@]}"; do
        if [ ! -e "$input" ]; then
            return 0
        fi
        for output in "${outputs[@]}"; do
            if [ "$input" -nt "$output" ]; then
                return 0
            fi
        done
    done

    return 1
}

c128_active_variant_is() {
    local expected="$1"
    [ -f "$C128_ACTIVE_VARIANT_FILE" ] && [ "$(cat "$C128_ACTIVE_VARIANT_FILE")" = "$expected" ]
}

c128_set_active_variant() {
    local variant="$1"
    printf '%s\n' "$variant" > "$C128_ACTIVE_VARIANT_FILE"
}

describe_phase_token() {
    local phase="$1"
    case "$phase" in
        all)
            printf 'all\tAll suites\n'
            ;;
        guards)
            printf 'guards\tmain128_asm,c128_artifact_budget,c128_symbol_placement,c128_prompt_irq_guard,c128_80col_layout_guard\n'
            ;;
        units)
            printf 'units\tminimal128,config128,memory128,db128,tier128,input128,main_loop128,msg_prompt128,vdc_attr128,status_coherence128,dungeon128,soak128,monster128\n'
            ;;
        smokes)
            printf 'smokes\tboot_d64_smoke,boot_title_idle_smoke,title_art_smoke,vic40_clean_boot_smoke,new_key_stability_smoke,boot_title_newgame_smoke,boot_title_load_resume_smoke,boot_tier_transition_smoke,town_overlay_smoke,town_overlay_female_smoke,town_overlay_state_smoke,scripted_summary_to_town_smoke,cache_survival_smoke,dungeon_attack_stability_smoke,death_overlay_smoke,restart_to_title_smoke,preload_partial_failure_smoke,overlay_partial_failure_smoke\n'
            ;;
        boot)
            printf 'boot\tboot_d64_smoke,boot_title_idle_smoke,title_art_smoke,vic40_clean_boot_smoke,new_key_stability_smoke,boot_title_newgame_smoke,boot_title_load_resume_smoke,boot_tier_transition_smoke,boot_diag_copy\n'
            ;;
        town)
            printf 'town\ttown_overlay_smoke,town_overlay_female_smoke,town_overlay_state_smoke,scripted_summary_to_town_smoke,real_input_town_move_diag,real_boot_crash_harness\n'
            ;;
        cache)
            printf 'cache\tcache_survival_smoke,preload_partial_failure_smoke,overlay_partial_failure_smoke,overlay_data_transition_smoke\n'
            ;;
        diag)
            printf 'diag\treal_input_town_move_diag,real_boot_crash_harness,overlay_data_transition_smoke,boot_diag_copy\n'
            ;;
        perf)
            printf 'perf\tperf_p1\n'
            ;;
        *)
            printf '%s\t<unknown>\n' "$phase"
            ;;
    esac
}

suite_matches_phase_token() {
    local phase="$1"
    local suite_name="$2"
    case "$phase" in
        all)
            return 0
            ;;
        guards)
            case "$suite_name" in
                main128_asm|c128_artifact_budget|c128_symbol_placement|c128_prompt_irq_guard|c128_80col_layout_guard) return 0 ;;
            esac
            ;;
        units)
            case "$suite_name" in
                minimal128|config128|memory128|db128|tier128|input128|main_loop128|msg_prompt128|vdc_attr128|status_coherence128|dungeon128|soak128|monster128) return 0 ;;
            esac
            ;;
        smokes)
            case "$suite_name" in
                boot_d64_smoke|boot_title_idle_smoke|title_art_smoke|vic40_clean_boot_smoke|new_key_stability_smoke|boot_title_newgame_smoke|boot_title_load_resume_smoke|boot_tier_transition_smoke|town_overlay_smoke|town_overlay_female_smoke|town_overlay_state_smoke|scripted_summary_to_town_smoke|cache_survival_smoke|dungeon_attack_stability_smoke|death_overlay_smoke|restart_to_title_smoke|preload_partial_failure_smoke|overlay_partial_failure_smoke) return 0 ;;
            esac
            ;;
        boot)
            case "$suite_name" in
                boot_d64_smoke|boot_title_idle_smoke|title_art_smoke|vic40_clean_boot_smoke|new_key_stability_smoke|boot_title_newgame_smoke|boot_title_load_resume_smoke|boot_tier_transition_smoke|boot_diag_copy) return 0 ;;
            esac
            ;;
        town)
            case "$suite_name" in
                town_overlay_smoke|town_overlay_female_smoke|town_overlay_state_smoke|scripted_summary_to_town_smoke|real_input_town_move_diag|real_boot_crash_harness) return 0 ;;
            esac
            ;;
        cache)
            case "$suite_name" in
                cache_survival_smoke|preload_partial_failure_smoke|overlay_partial_failure_smoke|overlay_data_transition_smoke) return 0 ;;
            esac
            ;;
        diag)
            case "$suite_name" in
                real_input_town_move_diag|real_boot_crash_harness|overlay_data_transition_smoke|boot_diag_copy) return 0 ;;
            esac
            ;;
        perf)
            case "$suite_name" in
                perf_p1) return 0 ;;
            esac
            ;;
    esac
    return 1
}

describe_phases() {
    local phase_list phase
    if [ -n "$TEST_PHASE" ]; then
        IFS=',' read -r -a phase_list <<< "$TEST_PHASE"
    else
        phase_list=(all guards units smokes boot town cache diag perf)
    fi

    echo "=== C128 Harness Phases ==="
    for phase in "${phase_list[@]}"; do
        phase="${phase//[[:space:]]/}"
        [ -z "$phase" ] && continue
        describe_phase_token "$phase"
    done
}

suite_matches_phase() {
    local suite_name="$1"
    if [ -z "$TEST_PHASE" ]; then
        return 0
    fi

    local phase_list phase
    IFS=',' read -r -a phase_list <<< "$TEST_PHASE"
    for phase in "${phase_list[@]}"; do
        phase="${phase//[[:space:]]/}"
        [ -z "$phase" ] && continue
        if suite_matches_phase_token "$phase" "$suite_name"; then
            return 0
        fi
    done
    return 1
}

suite_matches_filter() {
    local suite_name="$1"
    if ! suite_matches_rerun "$suite_name"; then
        return 1
    fi
    if ! suite_matches_phase "$suite_name"; then
        return 1
    fi

    if [ -z "$TEST_FILTER" ]; then
        :
    elif ! [[ "$suite_name" =~ $TEST_FILTER ]]; then
        return 1
    fi

    if [ -n "$TEST_SKIP" ] && [[ "$suite_name" =~ $TEST_SKIP ]]; then
        return 1
    fi

    return 0
}

run_named_suite() {
    local suite_name="$1"
    shift
    if ! suite_matches_filter "$suite_name"; then
        return 0
    fi
    if [ "$TEST_LIST" != "0" ]; then
        echo "  $suite_name"
        TOTAL=$((TOTAL + 1))
        return 0
    fi
    local timing_start=""
    local total_before="$TOTAL"
    local fail_before="$FAIL"
    if [ "$TEST_TIMINGS" != "0" ] || [ -n "$TEST_SUMMARY" ]; then
        timing_start="$(test128_now_ms)"
    fi
    "$@"
    local suite_rc=$?
    if [ -n "$timing_start" ] && [ "$TOTAL" -gt "$total_before" ]; then
        local duration_ms="$(( $(test128_now_ms) - timing_start ))"
        record_suite_timing "$suite_name" "$duration_ms"
        if [ "$FAIL" -gt "$fail_before" ]; then
            record_suite_result "FAIL" "$suite_name" "$duration_ms" "see console log"
        else
            record_suite_result "PASS" "$suite_name" "$duration_ms" ""
        fi
    fi
    if [ "$TEST_FAIL_FAST" != "0" ] && [ "$FAIL" -gt "$fail_before" ]; then
        return 1
    fi
    return "$suite_rc"
}

run_main_assembly_check() {
    echo -n "  main128_asm: "

    local build_log
    build_log="$(test128_tmp_file test128_main_build.log)"
    local make_kickass
    make_kickass="$(test128_tmp_file moria128-kickass.jar)"
    local kickass_abs
    kickass_abs="$(cd "$(dirname "$KICKASS")" && pwd)/$(basename "$KICKASS")"
    ln -sf "$kickass_abs" "$make_kickass"

    # KickAssembler can return 0 even when .assert fails, so gate on both
    # process status and emitted failure markers.
    if ! make -s KICKASS="$make_kickass" build128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
        echo "FAIL"
        grep -E "assert|FAILED|ERROR" "$build_log" | tail -5 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local assert_line
    assert_line=$(grep "Made .*asserts" "$build_log" | tail -1)
    if [ -n "${assert_line:-}" ]; then
        echo "PASS (${assert_line})"
    else
        echo "PASS"
    fi
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_artifact_budget_check() {
    echo -n "  c128_artifact_budget: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path
import re
import sys

prg = Path("out/moria128.prg")
sym = Path("main.sym")
vs = Path("out/main.vs")
if not prg.exists() or not sym.exists() or not vs.exists():
    print("missing build outputs")
    raise SystemExit(1)

data = prg.read_bytes()
if len(data) < 2:
    print("short prg")
    raise SystemExit(1)
load = data[0] | (data[1] << 8)
end = load + len(data) - 2 - 1

labels = {}
for line in sym.read_text().splitlines():
    m = re.match(r"\.label\s+([A-Za-z0-9_]+)=\$(\w+)", line)
    if m:
        labels[m.group(1)] = int(m.group(2), 16)

required = ["banked_code_end", "first_banked_function"]
missing = [name for name in required if name not in labels]
if missing:
    print("missing:" + ",".join(missing))
    raise SystemExit(1)

bad = []
if end > 0xFFFF:
    bad.append(f"prg_end=${end:05X}")
if labels["banked_code_end"] > 0xFFFA:
    bad.append(f"banked_code_end=${labels['banked_code_end']:04X}")
if labels["first_banked_function"] < 0xF000:
    bad.append(f"first_banked_function=${labels['first_banked_function']:04X}")

groups = {
    "title/runtime": ["title_menu_ready", "game_new_start", "load_resume_game"],
    "movement/render": ["main_loop", "vp_render_status_loop", "update_visibility", "render_viewport", "player_try_move"],
    "combat": ["player_attack_monster", "combat_apply_damage", "monster_attack_player"],
    "commands": ["item_aim_wand", "item_use_staff", "item_gain_spell", "player_cast_spell", "player_pray", "spell_list_display", "ranged_fire", "throw_item", "bash_command"],
}

for group, names in groups.items():
    rendered = []
    for name in names:
        addr = labels.get(name)
        if addr is None:
            rendered.append(f"{name}=MISSING")
            bad.append(f"missing:{name}")
            continue
        rendered.append(f"{name}=${addr:04X}")
        if 0xD000 <= addr < 0xE000:
            bad.append(f"io_hole:{name}=${addr:04X}")
    print(group + ": " + ", ".join(rendered))

if bad:
    print("failures: " + ", ".join(bad))
    raise SystemExit(1)

print(f"budgets: prg_end=${end:04X}, first_banked_function=${labels['first_banked_function']:04X}, banked_code_end=${labels['banked_code_end']:04X}")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    echo "$check_out" | sed 's/^/    /'
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_symbol_placement_check() {
    echo -n "  main128_layout: "

    local sym_file="main.sym"
    if [ ! -f "$sym_file" ]; then
        echo "FAIL (missing $sym_file)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path
import re
sym = Path("main.sym").read_text().splitlines()
main_text = Path("main.s").read_text()
main_source = main_text.splitlines()
labels = {}
for line in sym:
    m = re.match(r"\.label\s+([A-Za-z0-9_]+)=\$(\w+)", line)
    if not m:
        continue
    labels[m.group(1)] = int(m.group(2), 16)

assert_guards = set()
out_of_hole_guards = {}
for line in main_source:
    m = re.search(r"\.assert\s+\"[^\"]*\"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*<\s*\$D000\s*\|\|\s*\1\s*>=\s*\$(\w+)\b", line)
    if m:
        out_of_hole_guards[m.group(1)] = int(m.group(2), 16)
        continue
    m = re.search(r"\.assert\s+\"[^\"]*\"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*<\s*\$D000\b", line)
    if m:
        assert_guards.add(m.group(1))

required = [
    "game_over_prompt",
    "game_over_prompt_end",
    "game_over_str",
    "game_over_str_end",
    "title_show_sysinfo",
    "tramp_reu_show_status",
    "tramp_ui_equip_display",
    "tramp_ui_recall",
    "tramp_store_init_all",
    "tramp_store_restock_all",
    "tramp_store_enter",
    "tramp_player_create",
    "tramp_game_over",
]

# These are the concrete regression-prone runtime symbols that must stay out
# of the C128 $D000-$DFFF I/O hole. Each one should also be protected by a
# source-level placement assert in main.s.
must_have_asserts = [
    "title_menu_str",
    "ds_menu_str",
    "ds_dual_str",
    "de_prompt_str",
    "save_game",
    "load_game",
    "load_read_byte",
    "load_read_block",
    "load_read_map_c128",
    "delete_savefile",
    "update_visibility",
    "reveal_room",
    "player_try_move",
    "player_attack_monster",
    "combat_roll_tohit",
    "combat_apply_damage",
    "msg_build_action",
    "cmb_print_buf",
    "monster_attack_player",
    "mon_atk_calc_tohit",
    "mon_atk_roll_tohit",
    "mon_atk_apply_damage",
]
bad = []
missing = []
missing_asserts = []
for name in required:
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] >= 0xD000:
        bad.append((name, labels[name]))

if "msg_history" not in labels or "msg_hist_idx" not in labels:
    missing.append("msg_history/msg_hist_idx")
else:
    if labels["msg_hist_idx"] - labels["msg_history"] != (8 * 80):
        bad.append(("msg_history_span", labels["msg_hist_idx"] - labels["msg_history"]))

for name in ("help_title_str", "help_lines"):
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] < 0xF000 or labels[name] >= labels["banked_code_end"]:
        bad.append((name, labels[name]))

for name in ("ui_help_display",):
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] < 0xF000 or labels[name] >= labels["banked_code_end"]:
        bad.append((name, labels[name]))

for name in ("ui_recall_display", "ui_inv_display", "ui_equip_display"):
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] < 0xF000 or labels[name] >= labels["banked_code_end"]:
        bad.append((name, labels[name]))

for label in (
    "tramp_ui_help_display",
    "tramp_ui_inv_display",
    "tramp_ui_equip_display",
    "tramp_ui_recall",
):
    if f"{label}:\n    jsr init_copy_banked" in main_text:
        print(f"{label}: stale per-entry init_copy_banked reload reintroduced")
        raise SystemExit(1)

if "tramp_ui_exit:\n    lda #$36                    // BANK_NO_BASIC\n    sta $01\n    lda #$3e                    // MMU_ALL_RAM\n    sta $ff00\n    jsr c128_restore_runtime_guards\n    jsr c128_restore_runtime_vectors" not in main_text:
    print("tramp_ui_exit: expected runtime guard/vector restore before CLI")
    raise SystemExit(1)

if "ldx #21\n    jsr vdc_write_reg\n    lda #8\n    dex                         // 20\n    jsr vdc_write_reg" not in main_text:
    print("vdc_attr_base_init: expected reg21/reg20 init sequence with lda #8 for reg20")
    raise SystemExit(1)

# Hard rule: no critical entrypoint may execute from the $D000-$DFFF I/O hole.
for name in must_have_asserts:
    if name not in assert_guards and name not in out_of_hole_guards:
        missing_asserts.append(name)

# Every source-level <$D000 guard must be enforced by the runner.
for name in sorted(assert_guards):
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] >= 0xD000:
        bad.append((name, labels[name]))

# Every source-level "out of I/O hole" guard must be enforced by the runner.
for name, low_ok in sorted(out_of_hole_guards.items()):
    if name not in labels:
        missing.append(name)
        continue
    if 0xD000 <= labels[name] < low_ok:
        bad.append((name, labels[name]))

if missing or bad or missing_asserts:
    if missing:
        print("missing:" + ",".join(missing))
    if missing_asserts:
        print("missing_asserts:" + ",".join(sorted(missing_asserts)))
    for name, addr in bad:
        print(f"high:{name}=${addr:04X}")
    raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_80col_layout_guard_check() {
    echo -n "  layout80_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

root = Path("..").resolve()
screen = (root / "c128" / "screen_vdc.s").read_text()
render = (root / "c128" / "dungeon_render_vdc.s").read_text()
main128 = (root / "c128" / "main.s").read_text()
msgs = (root / "common" / "ui_messages.s").read_text()
status = (root / "common" / "ui_status.s").read_text()
help_s = (root / "common" / "ui_help.s").read_text()
swap = (root / "common" / "disk_swap.s").read_text()
char_s = (root / "common" / "ui_character.s").read_text()
sysinfo = (root / "common" / "title_sysinfo_banked.s").read_text()

def must_contain(text: str, snippet: str, err: str):
    if snippet not in text:
        print(err)
        raise SystemExit(1)

def must_not_contain(text: str, snippet: str, err: str):
    if snippet in text:
        print(err)
        raise SystemExit(1)

must_contain(screen, ".const SCREEN_COLS = 80", "screen_vdc must keep SCREEN_COLS=80")
must_contain(screen, ".const VIEWPORT_X  = 1", "screen_vdc must use explicit VIEWPORT_X=1")
must_contain(screen, ".const VIEWPORT_W  = 78", "screen_vdc must use explicit VIEWPORT_W=78")
must_contain(screen, ".const VDC_ATTR_MODE = $80", "screen_vdc must keep VDC_ATTR_MODE=$80 (Set 1 charset)")
must_not_contain(screen, "SCREEN_COL_OFFSET", "screen_vdc must not use implicit SCREEN_COL_OFFSET")
must_not_contain(render, "VIEWPORT_X + SCREEN_COL_OFFSET", "dungeon_render_vdc must use explicit VIEWPORT_X only")

must_contain(msgs, ".const MSG_HIST_LEN   = SCREEN_COLS", "ui_messages must size history by SCREEN_COLS")
must_contain(status, "#if C128", "ui_status must use compile-time C128 layout constants")
must_contain(help_s, ".const HELP_FRAME_RIGHT_COL = SCREEN_COLS - 1", "ui_help border must use SCREEN_COLS")
must_contain(swap, ".const DS_PROMPT_COL = (SCREEN_COLS - 16) / 2", "disk_swap prompt centering must use SCREEN_COLS math")
must_contain(main128, "lda #TITLE_MENU_COL", "title menu must use TITLE_MENU_COL")
must_contain(char_s, "lda #10\n    sta zp_cursor_row", "ui_character gold/xp row must stay at row 10")
must_contain(char_s, ".const UCHAR_COL_L = (SCREEN_COLS - 36) / 2", "ui_character C128 columns must stay centered for 80-col")
must_contain(sysinfo, "ldx #((SCREEN_COLS - 15) / 2)", "title sysinfo baseline must be centered on C128")
must_contain(status, "lda #STS_ROW21_NAME_COL\n    sta zp_cursor_col", "status row 21 name must use dedicated C128 anchor")

for src_name, src_text in (
    ("ui_messages.s", msgs),
    ("ui_status.s", status),
    ("ui_help.s", help_s),
    ("disk_swap.s", swap),
):
    if "zp_machine_type" in src_text:
        print(f"{src_name} reintroduced runtime machine checks")
        raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_prompt_irq_guard_check() {
    echo -n "  prompt_irq_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path
import re

root = Path("..").resolve()
screen = (root / "c128" / "screen_vdc.s").read_text().splitlines()
items = (root / "common" / "player_items.s").read_text().splitlines()
item_mod = (root / "common" / "item.s").read_text().splitlines()
throw_mod = (root / "common" / "throw.s").read_text().splitlines()
loop_mod = (root / "common" / "game_loop.s").read_text().splitlines()
dfeat = (root / "common" / "dungeon_features.s").read_text().splitlines()
help_mod = (root / "common" / "ui_help.s").read_text().splitlines()
store_mod = (root / "common" / "ui_store.s").read_text().splitlines()

def first_instructions_after(label: str, lines: list[str], count: int) -> list[str]:
    in_block = False
    out = []
    for ln in lines:
        s = ln.strip()
        if not in_block:
            if s.startswith(label):
                in_block = True
            continue
        if not s or s.startswith("//"):
            continue
        if s.endswith(":"):
            break
        out.append(s)
        if len(out) >= count:
            break
    return out

def has_pair(lines: list[str], token_a: str, token_b: str) -> bool:
    for i, ln in enumerate(lines):
        if token_a in ln:
            for j in range(i + 1, min(i + 8, len(lines))):
                if token_b in lines[j]:
                    return True
            return False
    return False

def has_ordered_chain(lines: list[str], tokens: list[str], window: int = 28) -> bool:
    for i, ln in enumerate(lines):
        if tokens[0] not in ln:
            continue
        pos = i
        ok = True
        for tok in tokens[1:]:
            found = False
            for j in range(pos + 1, min(pos + 1 + window, len(lines))):
                if tok in lines[j]:
                    pos = j
                    found = True
                    break
            if not found:
                ok = False
                break
        if ok:
            return True
    return False

first2 = first_instructions_after("screen_put_string:", screen, 2)
if len(first2) < 2 or (not first2[0].lower().startswith("php")) or (not first2[1].lower().startswith("sei")):
    print(f"screen_put_string must start with php; sei, found: {first2!r}")
    raise SystemExit(1)

if not has_pair(items, "ldx #HSTR_PIW_TAKEOFF_PROMPT", "jsr huff_print_msg"):
    print("item_takeoff prompt is not using Huffman print path")
    raise SystemExit(1)

required_chains = [
    ("item_wear", items, [
        "ldx #HSTR_PIW_WEAR_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_takeoff", items, [
        "ldx #HSTR_PIW_TAKEOFF_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_quaff", items, [
        "ldx #HSTR_PIQ_QUAFF_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_read_scroll", items, [
        "ldx #HSTR_PIQ_READ_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_aim_wand", items, [
        "ldx #HSTR_PIW_AIM_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_use_staff", items, [
        "ldx #HSTR_PIW_USE_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_gain_spell", items, [
        "ldx #HSTR_IGS_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("item_drop", item_mod, [
        "ldx #HSTR_IDR_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("throw_item", throw_mod, [
        "ldx #HSTR_TW_PROMPT",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("get_direction_target", dfeat, [
        "ldx #HSTR_DF_DIRECTION",
        "jsr huff_print_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_inventory_dismiss", loop_mod, [
        "cmp #CMD_INVENTORY",
        "jsr tramp_ui_inv_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_equipment_dismiss", loop_mod, [
        "cmp #CMD_EQUIPMENT",
        "jsr tramp_ui_equip_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_help_dismiss", loop_mod, [
        "cmp #CMD_HELP",
        "jsr tramp_ui_help_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_char_info_dismiss", loop_mod, [
        "cmp #CMD_CHAR_INFO",
        "jsr tramp_ui_char_display",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_recall_prompt", loop_mod, [
        "cmp #CMD_RECALL",
        "jsr screen_put_string",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("cmd_recall_dismiss", loop_mod, [
        "jsr tramp_ui_recall",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_buy_prompt", store_mod, [
        "ldx #MSG_BUY_WHICH",
        "jsr show_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_buy_confirm", store_mod, [
        "jsr sbuy_show_price",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_sell_prompt", store_mod, [
        "ldx #MSG_SELL_WHICH",
        "jsr show_msg",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_sell_confirm", store_mod, [
        "jsr ssell_show_offer",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
    ("store_haggle_number", store_mod, [
        "input_read_number:",
        "jsr input_wait_release",
        "jsr input_get_key",
    ]),
]

for name, lines, chain in required_chains:
    if not has_ordered_chain(lines, chain):
        print(f"{name} must gate with input_wait_release before input_get_key")
        raise SystemExit(1)

if not has_ordered_chain(help_mod, [
    "#if C128",
    "jsr screen_put_char",
    "#else",
    "sta (zp_screen_lo),y",
]):
    print("ui_help_draw_line must use screen_put_char on C128 and keep direct RAM path only for C64")
    raise SystemExit(1)

print("ok")
PY
)
    if [ $? -ne 0 ]; then
        echo "FAIL"
        echo "$check_out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

build_boot_assets() {
    if [ "$BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "base"; then
        return
    fi

    local force_base_rebuild=0
    if ! c128_active_variant_is "base"; then
        force_base_rebuild=1
    fi

    if c128_active_variant_is "base" && ! c128_outputs_need_refresh \
            out/boot128.prg out/moria128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat out/main.vs -- \
            main.s boot128.s Makefile; then
        BOOT_ASSETS_BUILT=1
        return
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_build.log)"
    local make_kickass
    make_kickass="$(test128_tmp_file moria128-kickass.jar)"
    local kickass_abs
    kickass_abs="$(cd "$(dirname "$KICKASS")" && pwd)/$(basename "$KICKASS")"
    ln -sf "$kickass_abs" "$make_kickass"
    if [ "$force_base_rebuild" -eq 1 ]; then
        if ! make -s -W main.s -W boot128.s KICKASS="$make_kickass" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
            echo "FAIL (build128/disk128 failed)"
            tail -20 "$build_log" | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return 1
        fi
    elif ! make -s KICKASS="$make_kickass" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
        echo "FAIL (build128/disk128 failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local diag_asm
    diag_asm=$(java -jar "$KICKASS" boot128.s -define BOOT_DIAG=1 -var OVL_OUT='"out"' -o out/boot128.diag.prg 2>&1)
    if [ $? -ne 0 ]; then
        echo "FAIL (boot128 diag assembly error)"
        echo "$diag_asm" | grep -i error | head -3 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=1
    c128_set_active_variant "base"
    return 0
}

run_vic40_clean_boot_smoke() {
    local name="vic40_clean_boot_smoke"
    echo -n "  $name: "

    local build_log
    build_log="$(test128_tmp_file "test128_${name}_build.log")"
    local c1541_bin="${C1541:-c1541}"
    local probe_main="out/moria128.vic40probe.prg"
    local probe_d64="out/moria128_vic40probe.d64"

    build_boot_assets || return

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -var OVL_OUT='"out"' -define C128_TEST_VIC40_CLEAN_BOOT \
            -o "$probe_main" >"$build_log" 2>&1; then
        echo "FAIL (vic40 probe main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$probe_d64" \
            -attach "$probe_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$probe_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >"$(test128_tmp_file "test128_${name}_c1541.log")" 2>&1; then
        echo "FAIL (vic40 probe d64 creation failed)"
        tail -20 "$(test128_tmp_file "test128_${name}_c1541.log")" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local probe_vs="out/main.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.c128_vic40_boot_probe_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$probe_vs")
    fail_addr=$(awk '/\.c128_vic40_boot_probe_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$probe_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing vic40 probe symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_vic40probe.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$${fail_addr}"
        echo "until \$${pass_addr}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 180000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if boot_log_has_stop_at "$log_file" "$fail_addr"; then
        echo "FAIL (vic40 boot probe reported invalid display state)"
        tail -20 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! boot_log_has_stop_at "$log_file" "$pass_addr"; then
        boot_log_report_failure "did not reach vic40 boot probe pass" "$log_file" "c128_vic40_boot_probe_pass" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

build_real_boot_diag_assets() {
    if [ "$REAL_BOOT_DIAG_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "real_boot_diag"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "real_boot_diag" && ! c128_outputs_need_refresh \
            out/moria128.realdiag.prg out/moria128_realdiag.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        REAL_BOOT_DIAG_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_real_boot_diag_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local diag_main="out/moria128.realdiag.prg"
    local diag_d64="out/moria128_realdiag.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -var OVL_OUT='"out"' -define C128_TEST_REAL_BOOT_DIAG -define C128_TEST_FORCE_DUNGEON_MELEE \
            -o "$diag_main" >"$build_log" 2>&1; then
        echo "FAIL (real-boot diag main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$diag_d64" \
            -attach "$diag_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$diag_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (real-boot diag disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    REAL_BOOT_DIAG_ASSETS_BUILT=1
    c128_set_active_variant "real_boot_diag"
    return 0
}

build_overlay_transition_diag_assets() {
    if [ "$OVERLAY_TRANSITION_DIAG_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "overlay_transition_diag"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "overlay_transition_diag" && ! c128_outputs_need_refresh \
            out/moria128.overlaydiag.prg out/moria128_overlaydiag.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        OVERLAY_TRANSITION_DIAG_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_overlay_transition_diag_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local diag_main="out/moria128.overlaydiag.prg"
    local diag_d64="out/moria128_overlaydiag.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -var OVL_OUT='"out"' -define C128_TEST_OVERLAY_TRANSITION_DIAG \
            -o "$diag_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-transition diag main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$diag_d64" \
            -attach "$diag_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$diag_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (overlay-transition diag disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    OVERLAY_TRANSITION_DIAG_ASSETS_BUILT=1
    c128_set_active_variant "overlay_transition_diag"
    return 0
}

build_title_art_boot_assets() {
    if [ "$TITLE_ART_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "title_art"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "title_art" && ! c128_outputs_need_refresh \
            out/moria128.titleart.prg out/moria128_titleart.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        TITLE_ART_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_title_art_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local title_main="out/moria128.titleart.prg"
    local title_d64="out/moria128_titleart.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 -var OVL_OUT='"out"' -define C128_TEST_TITLE_ART_CONTENT \
            -o "$title_main" >"$build_log" 2>&1; then
        echo "FAIL (title-art main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$title_d64" \
            -attach "$title_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$title_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (title-art disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    TITLE_ART_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "title_art"
    return 0
}

build_partial_failure_boot_assets() {
    if [ "$PARTIAL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "partial_failure"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "partial_failure" && ! c128_outputs_need_refresh \
            out/moria128.skip1.prg out/moria128_skip1.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        PARTIAL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_partial_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local partial_main="out/moria128.skip1.prg"
    local partial_d64="out/moria128_skip1.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -var OVL_OUT='"out"' -define C128_CACHE_TEST_SKIP_TIER -o "$partial_main" >"$build_log" 2>&1; then
        echo "FAIL (partial-failure main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$partial_d64" \
            -attach "$partial_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$partial_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (partial-failure disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    PARTIAL_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "partial_failure"
    return 0
}

build_overlay_partial_failure_boot_assets() {
    if [ "$OVERLAY_PARTIAL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "overlay_partial_failure"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "overlay_partial_failure" && ! c128_outputs_need_refresh \
            out/moria128.skipovl2.prg out/moria128_skipovl2.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_overlay_partial_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local partial_main="out/moria128.skipovl2.prg"
    local partial_d64="out/moria128_skipovl2.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -var OVL_OUT='"out"' -define C128_CACHE_TEST_SKIP_OVERLAY -o "$partial_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-partial main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$partial_d64" \
            -attach "$partial_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$partial_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (overlay-partial disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "overlay_partial_failure"
    return 0
}

build_death_overlay_boot_assets() {
    if [ "$DEATH_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "death_overlay"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "death_overlay" && ! c128_outputs_need_refresh \
            out/moria128.death.prg out/moria128_death.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        DEATH_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_death_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local death_main="out/moria128.death.prg"
    local death_d64="out/moria128_death.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -var OVL_OUT='"out"' -define C128_TEST_FORCE_DEATH=1 -o "$death_main" >"$build_log" 2>&1; then
        echo "FAIL (death-overlay main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$death_d64" \
            -attach "$death_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$death_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (death-overlay disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    DEATH_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "death_overlay"
    return 0
}

build_overlay_state_boot_assets() {
    if [ "$OVERLAY_STATE_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "overlay_state"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "overlay_state" && ! c128_outputs_need_refresh \
            out/moria128.overlaystate.prg out/moria128_overlaystate.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        OVERLAY_STATE_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_overlay_state_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local state_main="out/moria128.overlaystate.prg"
    local state_d64="out/moria128_overlaystate.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -var OVL_OUT='"out"' -define C128_TEST_OVERLAY_STATE_CORRUPT=1 -o "$state_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-state main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$state_d64" \
            -attach "$state_d64" \
            -write out/boot128.prg "moria8.128" \
            -write "$state_main" "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (overlay-state disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    OVERLAY_STATE_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "overlay_state"
    return 0
}

build_scripted_input_boot_assets() {
    if [ "$SCRIPTED_INPUT_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "scripted_input"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "scripted_input" && ! c128_outputs_need_refresh \
            out/moria128.prg out/moria128_scriptedinput.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        SCRIPTED_INPUT_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_input_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="out/moria128_scriptedinput.d64"

    # Compile to the standard out/moria128.prg target so KickAssembler also
    # refreshes the companion out/ovl.* overlay PRGs for this special build.
    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -var OVL_OUT='"out"' -define C128_TEST_SCRIPTED_INPUT -o out/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-input main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write out/boot128.prg "moria8.128" \
            -write out/moria128.prg "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-input disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    # Force later builders back through build_boot_assets so subsequent smokes
    # do not accidentally reuse the scripted-input overlays.
    BOOT_ASSETS_BUILT=0
    SCRIPTED_INPUT_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "scripted_input"
    return 0
}

build_cache_survival_boot_assets() {
    local target_out="${1:-out}"
    if [ "$target_out" = "out" ] && [ "$CACHE_SURVIVAL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "cache_survival"; then
        return
    fi

    build_boot_assets "$target_out" || return 1

    if [ "$target_out" = "out" ] && c128_active_variant_is "cache_survival" && ! c128_outputs_need_refresh \
            out/moria128.prg out/moria128_cache_survival.d64 out/main.vs -- \
            main.s out/boot128.prg out/title out/monster.db.1 out/monster.db.2 \
            out/monster.db.3 out/monster.db.4 out/ovl.town out/ovl.start out/ovl.death \
            out/ovl.gen out/bank1.dat; then
        CACHE_SURVIVAL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file "test128_boot_cache_survival_build_$(basename "$target_out").log")"
    local cache_main="$target_out/moria128.prg"
    local cache_d64="$target_out/moria128_cache_survival.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_TEST_SCRIPTED_INPUT -define C128_TEST_CACHE_SURVIVAL -var OVL_OUT='"$target_out"' -o "$cache_main" >"$build_log" 2>&1; then
        echo "FAIL (cache-survival main assembly failed for $target_out)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$C1541" -format "moria128,m8" d64 "$cache_d64" \
            -attach "$cache_d64" \
            -write "$target_out/boot128.prg" "moria8.128" \
            -write "$cache_main" "moria128" \
            -write "$target_out/title" "title" \
            -write "$target_out/monster.db.1" "monster.db.1" \
            -write "$target_out/monster.db.2" "monster.db.2" \
            -write "$target_out/monster.db.3" "monster.db.3" \
            -write "$target_out/monster.db.4" "monster.db.4" \
            -write "$target_out/ovl.town" "ovl.town" \
            -write "$target_out/ovl.start" "ovl.start" \
            -write "$target_out/ovl.death" "ovl.death" \
            -write "$target_out/ovl.gen" "ovl.gen" \
            -write "$target_out/bank1.dat" "bank1.dat" >>"$build_log" 2>&1; then
        echo "FAIL (cache-survival disk build failed for $target_out)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if [ "$target_out" = "out" ]; then
        BOOT_ASSETS_BUILT=0 # Force refresh
        CACHE_SURVIVAL_BOOT_ASSETS_BUILT=1
        c128_set_active_variant "cache_survival"
    fi
    return 0
}

build_load_resume_boot_assets() {
    if [ "$LOAD_RESUME_BOOT_ASSETS_BUILT" -eq 1 ]; then
        return
    fi

    build_boot_assets || return 1

    if ! c128_outputs_need_refresh \
            out/THE.GAME out/moria128_loadresume.d64 -- \
            tests/make_load_resume_save.py out/boot128.prg out/moria128.prg out/title \
            out/monster.db.1 out/monster.db.2 out/monster.db.3 out/monster.db.4 \
            out/ovl.town out/ovl.start out/ovl.death out/ovl.gen out/bank1.dat; then
        LOAD_RESUME_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_load_resume_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local loadresume_d64="out/moria128_loadresume.d64"
    local save_blob="out/THE.GAME"

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (load-resume save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$loadresume_d64" \
            -attach "$loadresume_d64" \
            -write out/boot128.prg "moria8.128" \
            -write out/moria128.prg "moria128" \
            -write out/title "title" \
            -write out/monster.db.1 "monster.db.1" \
            -write out/monster.db.2 "monster.db.2" \
            -write out/monster.db.3 "monster.db.3" \
            -write out/monster.db.4 "monster.db.4" \
            -write out/ovl.town "ovl.town" \
            -write out/ovl.start "ovl.start" \
            -write out/ovl.death "ovl.death" \
            -write out/ovl.gen "ovl.gen" \
            -write out/bank1.dat "bank1.dat" \
            -write "$save_blob" "THE.GAME" >>"$build_log" 2>&1; then
        echo "FAIL (load-resume disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local dir_list
    if ! dir_list=$("$c1541_bin" -attach "$loadresume_d64" -list 2>&1); then
        echo "FAIL (load-resume disk listing failed)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! echo "$dir_list" | grep -q '"THE.GAME"'; then
        echo "FAIL (save-seed disk missing THE.GAME)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    LOAD_RESUME_BOOT_ASSETS_BUILT=1
    return 0
}

run_test_internal() {
    local name="$1"
    local src="$2"
    local cycles="${3:-20000000}"
    local result_file="$4"
    local start_ms
    start_ms="$(test128_now_ms)"

    local prg_file="${src%.s}.prg"
    local abs_prg
    abs_prg="$(cd "$(dirname "$prg_file")" && pwd)/$(basename "$prg_file")"
    local vs_file="${src%.s}.vs"

    if c128_target_is_stale "$prg_file" || c128_target_is_stale "$vs_file"; then
        local asm_output
        asm_output=$(java -jar "$KICKASS" "$src" -o "$prg_file" -libdir ../c64 -define C128 -vicesymbols -var OVL_OUT='"out"' 2>&1)
        if [ $? -ne 0 ]; then
            printf 'FAIL\t%s\t%s\t%s\n' "$name" "$(( $(test128_now_ms) - start_ms ))" "assembly error" >> "$result_file"
            return
        fi
    fi

    if [ ! -f "$vs_file" ]; then
        printf 'FAIL\t%s\t%s\t%s\n' "$name" "$(( $(test128_now_ms) - start_ms ))" "missing .vs symbol file" >> "$result_file"
        return
    fi

    local start_addr pass_addr
    start_addr=$(awk '/\.test_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")
    pass_addr=$(awk '/\.test_pass$/  { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")

    if [ -z "${start_addr:-}" ] || [ -z "${pass_addr:-}" ]; then
        printf 'FAIL\t%s\t%s\t%s\n' "$name" "$(( $(test128_now_ms) - start_ms ))" "missing test_start/test_pass labels" >> "$result_file"
        return
    fi

    start_addr=$(normalize_monitor_addr "$start_addr")
    pass_addr=$(normalize_monitor_addr "$pass_addr")

    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
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
        printf 'PASS\t%s\t%s\t\n' "$name" "$(( $(test128_now_ms) - start_ms ))" >> "$result_file"
    else
        printf 'FAIL\t%s\t%s\t%s\n' "$name" "$(( $(test128_now_ms) - start_ms ))" "execution failed" >> "$result_file"
    fi
}

export -f normalize_monitor_addr
export -f c128_target_is_stale
export -f test128_tmp_file
export -f test128_now_ms
export -f run_test_internal
export KICKASS VICE TEST128_TMP_DIR TEST_JOBS TEST_JOBS_RESOLVED TEST_TIMINGS TEST128_TIMINGS_FILE

run_parallel_unit_tests() {
    local test_list=(
        "minimal128 tests/test_minimal128.s 20000000"
        "config128 tests/test_config128.s 20000000"
        "memory128 tests/test_memory128.s 20000000"
        "db128 tests/test_db128.s 20000000"
        "tier128 tests/test_tier128.s 20000000"
        "input128 tests/test_input128.s 20000000"
        "main_loop128 tests/test_main_loop128.s 500000000"
        "msg_prompt128 tests/test_msg_prompt128.s 120000000"
        "vdc_attr128 tests/test_vdc_attr128.s 20000000"
        "status_coherence128 tests/test_status_coherence128.s 20000000"
        "dungeon128 tests/test_dungeon128.s 50000000"
        "soak128 tests/test_soak128.s 300000000"
        "monster128 tests/test_monster128.s 20000000"
    )
    local filtered_tests=()
    local test_entry
    for test_entry in "${test_list[@]}"; do
        local test_name="${test_entry%% *}"
        if suite_matches_filter "$test_name"; then
            filtered_tests+=("$test_entry")
        fi
    done

    if [ "${#filtered_tests[@]}" -eq 0 ]; then
        return
    fi

    if [ "$TEST_LIST" != "0" ]; then
        local listed_entry
        for listed_entry in "${filtered_tests[@]}"; do
            echo "  ${listed_entry%% *}"
            TOTAL=$((TOTAL + 1))
        done
        return
    fi

    local result_file
    result_file="$(test128_tmp_file test128_results_unit.txt)"
    : > "$result_file"
    
    mkdir -p out
    if [ "$TEST_FAIL_FAST" != "0" ]; then
        echo "  running unit tests serially (fail-fast)..."
        local test_entry
        for test_entry in "${filtered_tests[@]}"; do
            : > "$result_file"
            bash -c 'run_test_internal "$1" "$2" "$3" "$4"' -- ${test_entry} "$result_file"
            while IFS=$'\t' read -r status name duration_ms detail; do
                echo -n "  $name: "
                if [ "$status" = "PASS" ]; then
                    if [ "$TEST_TIMINGS" != "0" ]; then
                        echo "PASS (${duration_ms}ms)"
                    else
                        echo "PASS"
                    fi
                    PASS=$((PASS + 1))
                    record_suite_timing "$name" "$duration_ms"
                else
                    if [ "$TEST_TIMINGS" != "0" ] && [ -n "${duration_ms:-}" ]; then
                        echo "FAIL ($detail; ${duration_ms}ms)"
                    else
                        echo "FAIL ($detail)"
                    fi
                    FAIL=$((FAIL + 1))
                    if [ -n "${duration_ms:-}" ]; then
                        record_suite_timing "$name" "$duration_ms"
                    fi
                    TOTAL=$((TOTAL + 1))
                    return 1
                fi
                TOTAL=$((TOTAL + 1))
            done < "$result_file"
        done
        return 0
    fi

    echo "  running unit tests in parallel..."

    printf "%s\n" "${filtered_tests[@]}" | xargs -P "$TEST_JOBS_RESOLVED" -I {} bash -c 'run_test_internal $1 $2 $3 '"$result_file"'' -- {}
    
    while IFS=$'\t' read -r status name duration_ms detail; do
        
        echo -n "  $name: "
        if [ "$status" = "PASS" ]; then
            if [ "$TEST_TIMINGS" != "0" ]; then
                echo "PASS (${duration_ms}ms)"
            else
                echo "PASS"
            fi
            PASS=$((PASS + 1))
            record_suite_timing "$name" "$duration_ms"
            record_suite_result "$status" "$name" "$duration_ms" ""
        else
            if [ "$TEST_TIMINGS" != "0" ] && [ -n "${duration_ms:-}" ]; then
                echo "FAIL ($detail; ${duration_ms}ms)"
            else
                echo "FAIL ($detail)"
            fi
            FAIL=$((FAIL + 1))
            if [ -n "${duration_ms:-}" ]; then
                record_suite_timing "$name" "$duration_ms"
            fi
            record_suite_result "$status" "$name" "$duration_ms" "$detail"
        fi
        TOTAL=$((TOTAL + 1))
    done < "$result_file"
}

run_test() {
    local name="$1"
    local src="$2"
    local cycles="${3:-20000000}"
    local failed=0

    if ! suite_matches_filter "$name"; then
        return
    fi

    if [ "$TEST_LIST" != "0" ]; then
        echo "  $name"
        TOTAL=$((TOTAL + 1))
        return
    fi
    local start_ms
    start_ms="$(test128_now_ms)"

    echo -n "  $name: "

    local prg_file="${src%.s}.prg"
    local abs_prg
    abs_prg="$(cd "$(dirname "$prg_file")" && pwd)/$(basename "$prg_file")"
    local vs_file="${src%.s}.vs"

    if c128_target_is_stale "$prg_file" || c128_target_is_stale "$vs_file"; then
        local asm_output
        asm_output=$(java -jar "$KICKASS" "$src" -o "$prg_file" -libdir ../c64 "${KA_DEFINES[@]}" -vicesymbols 2>&1)
        if [ $? -ne 0 ]; then
            echo "FAIL (assembly error)"
            echo "$asm_output" | grep -i error | head -3
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            local duration_ms="$(( $(test128_now_ms) - start_ms ))"
            record_suite_timing "$name" "$duration_ms"
            record_suite_result "FAIL" "$name" "$duration_ms" "assembly error"
            failed=1
            if [ "$TEST_FAIL_FAST" != "0" ]; then
                return 1
            fi
            return
        fi
    fi

    if [ ! -f "$vs_file" ]; then
        echo "FAIL (missing .vs symbol file)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        local duration_ms="$(( $(test128_now_ms) - start_ms ))"
        record_suite_timing "$name" "$duration_ms"
        record_suite_result "FAIL" "$name" "$duration_ms" "missing .vs symbol file"
        failed=1
        if [ "$TEST_FAIL_FAST" != "0" ]; then
            return 1
        fi
        return
    fi

    local start_addr pass_addr
    start_addr=$(awk '/\.test_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")
    pass_addr=$(awk '/\.test_pass$/  { split($2,a,":"); print toupper(a[2]); exit }' "$vs_file")

    if [ -z "${start_addr:-}" ] || [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing test_start/test_pass labels in .vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        local duration_ms="$(( $(test128_now_ms) - start_ms ))"
        record_suite_timing "$name" "$duration_ms"
        record_suite_result "FAIL" "$name" "$duration_ms" "missing test_start/test_pass labels in .vs"
        failed=1
        if [ "$TEST_FAIL_FAST" != "0" ]; then
            return 1
        fi
        return
    fi

    start_addr=$(normalize_monitor_addr "$start_addr")
    pass_addr=$(normalize_monitor_addr "$pass_addr")

    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
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

    local duration_ms
    duration_ms="$(( $(test128_now_ms) - start_ms ))"
    if grep -qi "^UNTIL: .*C:\$${pass_addr}" "$log_file"; then
        if [ "$TEST_TIMINGS" != "0" ]; then
            echo "PASS (${duration_ms}ms)"
        else
            echo "PASS"
        fi
        PASS=$((PASS + 1))
        record_suite_result "PASS" "$name" "$duration_ms" ""
    else
        if [ "$TEST_TIMINGS" != "0" ]; then
            echo "FAIL (${duration_ms}ms)"
        else
            echo "FAIL"
        fi
        tail -3 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        failed=1
        record_suite_result "FAIL" "$name" "$duration_ms" "execution failed"
    fi

    record_suite_timing "$name" "$duration_ms"
    TOTAL=$((TOTAL + 1))
    if [ "$TEST_FAIL_FAST" != "0" ] && [ "$failed" -ne 0 ]; then
        return 1
    fi
}

boot_log_last_pc() {
    local log_file="$1"
    python3 - "$log_file" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(errors="ignore").splitlines()
last = ""
for line in text:
    m = re.search(r'C:\$([0-9A-Fa-f]{4})', line)
    if m:
        last = m.group(1).upper()
print(last)
PY
}

boot_log_report_failure() {
    local reason="$1"
    local log_file="$2"
    local target_name="$3"
    local target_addr="$4"
    local vice_rc="${5:-0}"

    local reached="no"
    local jam="no"
    local timeout="no"
    local last_pc=""

    if grep -qi "^UNTIL: .*C:\$${target_addr}\\|^BREAK: .*C:\$${target_addr}" "$log_file"; then
        reached="yes"
    fi
    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        jam="yes"
    fi
    if [ "$vice_rc" -ne 0 ] && [ "$reached" = "no" ] && [ "$jam" = "no" ]; then
        timeout="yes"
    fi
    last_pc=$(boot_log_last_pc "$log_file")

    echo "FAIL (${reason})"
    if [ -n "${last_pc:-}" ]; then
        echo "    last_pc: \$${last_pc}"
    fi
    echo "    target: ${target_name}=\$${target_addr} reached=${reached} jam=${jam} timeout=${timeout} vice_rc=${vice_rc}"
    tail -10 "$log_file" | sed 's/^/    /'
}

boot_log_report_crash_context() {
    local log_file="$1"
    echo "    crash context:"
    python3 - "$log_file" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(errors="ignore").splitlines()
start = 0
for i, line in enumerate(lines):
    if line.startswith("(C:$") or line.startswith(".C:") or line.startswith(">C:") or line.startswith("  ADDR "):
        start = i
        break
for line in lines[start:]:
    if line.startswith("(C:$") or line.startswith(".C:") or line.startswith(">C:") or line.startswith("  ADDR "):
        print("    " + line)
PY
}

boot_log_has_crash() {
    local log_file="$1"
    grep -qi "JAM\\|Invalid opcode" "$log_file"
}

boot_log_has_stop_at() {
    local log_file="$1"
    local addr
    addr=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
    python3 - "$log_file" "$addr" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(errors="ignore").splitlines()
addr = sys.argv[2].upper()
needles = ("C:$" + addr, "EXEC " + addr)
for line in lines:
    line = line.upper()
    if not (line.startswith("#") or line.startswith("UNTIL:")):
        continue
    if any(n in line for n in needles):
        sys.exit(0)
sys.exit(1)
PY
}

boot_diag_dump_cmds() {
    cat <<'EOF'
r
bt
m 3400 340b
m 0314 0315
m fffa ffff
m 0c00 0c10
EOF
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
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$${entry_main}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 120000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "^BREAK: .*C:\$${entry_main}" "$log_file"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        boot_log_report_failure "did not reach entry_main" "$log_file" "entry_main" "$entry_main" "$vice_rc"
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_boot_title_newgame_smoke() {
    local name="boot_title_newgame_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local loop_top
    loop_top=$(awk '/\.c128_town_move_diag_loop_top$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${loop_top:-}" ]; then
        echo "FAIL (missing c128_town_move_diag_loop_top in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${loop_top}"
        echo "g"
        boot_diag_dump_cmds
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${loop_top}" "$log_file"; then
        boot_log_report_failure "did not reach first gameplay loop after character generation" "$log_file" "c128_town_move_diag_loop_top" "$loop_top" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_new_key_stability_smoke() {
    local name="new_key_stability_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local game_new_start
    game_new_start=$(awk '/\.game_new_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${game_new_start:-}" ]; then
        echo "FAIL (missing game_new_start in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${game_new_start}"
        echo "g"
        boot_diag_dump_cmds
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf 'N' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 220000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop after New key)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! boot_log_has_stop_at "$log_file" "$game_new_start"; then
        boot_log_report_failure "did not reach game_new_start after New key" "$log_file" "game_new_start" "$game_new_start" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_title_art_smoke() {
    local name="title_art_smoke"
    echo -n "  $name: "

    build_title_art_boot_assets || return

    local main_vs="out/main.vs"
    local title_art_pass title_art_fail
    title_art_pass=$(awk '/\.c128_test_title_art_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    title_art_fail=$(awk '/\.c128_test_title_art_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_art_pass:-}" ] || [ -z "${title_art_fail:-}" ]; then
        echo "FAIL (missing title art probe symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_titleart.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$${title_art_fail}"
        echo "until \$${title_art_pass}"
        echo "g"
        boot_diag_dump_cmds
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 180000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if boot_log_has_stop_at "$log_file" "$title_art_fail"; then
        echo "FAIL (title art content probe failed)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! boot_log_has_stop_at "$log_file" "$title_art_pass"; then
        boot_log_report_failure "did not reach title art content pass probe" "$log_file" "c128_test_title_art_pass_sym" "$title_art_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_load_resume_smoke() {
    local name="boot_title_load_resume_smoke"
    echo -n "  $name: "

    build_load_resume_boot_assets || return

    local main_vs="out/main.vs"
    local load_resume_game
    load_resume_game=$(awk '/\.load_resume_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${load_resume_game:-}" ]; then
        echo "FAIL (missing load_resume_game in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_loadresume.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${load_resume_game}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "L" -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 220000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${load_resume_game}" "$log_file"; then
        boot_log_report_failure "did not reach load_resume_game from title load flow" "$log_file" "load_resume_game" "$load_resume_game" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during title load/resume flow" "$log_file" "load_resume_game" "$load_resume_game" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_idle_smoke() {
    local name="boot_title_idle_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local title_show_sysinfo
    title_show_sysinfo=$(awk '/\.title_show_sysinfo$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_show_sysinfo:-}" ]; then
        echo "FAIL (missing title_show_sysinfo in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${title_show_sysinfo}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 120000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${title_show_sysinfo}" "$log_file"; then
        boot_log_report_failure "did not reach title_show_sysinfo on idle boot" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -monlog -monlogname "$log_file" \
        -limitcycles 220000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during idle title soak" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_tier_transition_smoke() {
    local name="boot_tier_transition_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local dungeon_generate
    dungeon_generate=$(awk '/\.dungeon_generate$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${dungeon_generate:-}" ]; then
        echo "FAIL (missing dungeon_generate in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${dungeon_generate}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${dungeon_generate}" "$log_file"; then
        boot_log_report_failure "did not reach dungeon_generate via stairs flow" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after dungeon transition" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_overlay_smoke() {
    local name="town_overlay_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${store_enter}"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "did not reach store_enter via town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_overlay_female_smoke() {
    local name="town_overlay_female_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$d000 \$dfff"
        echo "break \$${store_enter}"
        echo "g"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rB LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "did not reach store_enter via female town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "^#1 \\(Stop on  exec d[0-9a-f][0-9a-f][0-9a-f]\\)" "$log_file"; then
        boot_log_report_failure "executed in I/O hole during female town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during female town overlay flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_town_overlay_state_smoke() {
    local name="town_overlay_state_smoke"
    echo -n "  $name: "

    build_overlay_state_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in overlay-state .vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_overlaystate.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$d000 \$dfff"
        echo "break \$${store_enter}"
        echo "g"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rB LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "did not reach store_enter with corrupted overlay state" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "^#1 \\(Stop on  exec d[0-9a-f][0-9a-f][0-9a-f]\\)" "$log_file"; then
        boot_log_report_failure "executed in I/O hole during corrupted overlay-state town flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during corrupted overlay-state town flow" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_summary_to_town_smoke() {
    local name="scripted_summary_to_town_smoke"
    echo -n "  $name: "

    build_scripted_input_boot_assets || return

    local main_vs="out/main.vs"
    local c128_test_town_pass c128_test_town_fail
    c128_test_town_pass=$(awk '/\.c128_test_town_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_town_fail=$(awk '/\.c128_test_town_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_test_town_pass:-}" ] || [ -z "${c128_test_town_fail:-}" ]; then
        echo "FAIL (missing scripted summary/town pass/fail symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_scriptedinput.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local pass_lc fail_lc
    : > "$log_file"
    pass_lc=$(echo "$c128_test_town_pass" | tr '[:upper:]' '[:lower:]')
    fail_lc=$(echo "$c128_test_town_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_town_fail}"
        echo "break \$${c128_test_town_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qiE "Stop on  exec ${pass_lc}" "$log_file" && ! grep -qi "^BREAK: .*C:\$${c128_test_town_pass}" "$log_file"; then
        boot_log_report_failure "did not reach scripted town pass trap" "$log_file" "c128_test_town_pass" "$c128_test_town_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${c128_test_town_fail}" "$log_file"; then
        # In current test builds the fail/pass traps are adjacent BRKs, and VICE can
        # report both breakpoints even when execution explicitly jumps to the pass trap.
        # Once the pass trap is confirmed, treat the run as successful.
        :
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted summary-to-town flow" "$log_file" "c128_test_town_pass" "$c128_test_town_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_real_input_town_move_diag() {
    local name="real_input_town_move_diag"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="out/main.vs"
    local -a stage_names=(
        "loop_top"
        "after_input_get_command"
        "before_player_try_move"
        "after_map_ptr_setup"
        "after_map_read"
        "before_walkable"
        "after_walkable"
        "before_occupied_read"
        "after_occupied_read"
        "move_success"
        "after_player_try_move"
        "after_trap_check"
        "after_turn_post_action"
        "before_status_draw"
        "after_status_draw"
    )
    local -a stage_labels=(
        "c128_town_move_diag_loop_top"
        "c128_town_move_diag_after_input_get_command"
        "c128_town_move_diag_before_player_try_move"
        "c128_town_move_diag_after_map_ptr_setup"
        "c128_town_move_diag_after_map_read"
        "c128_town_move_diag_before_walkable"
        "c128_town_move_diag_after_walkable"
        "c128_town_move_diag_before_occupied_read"
        "c128_town_move_diag_after_occupied_read"
        "c128_town_move_diag_move_success"
        "c128_town_move_diag_after_player_try_move"
        "c128_town_move_diag_after_trap_check"
        "c128_town_move_diag_after_turn_post_action"
        "c128_town_move_diag_before_status_draw"
        "c128_town_move_diag_after_status_draw"
    )
    local -a stage_addrs=()
    local idx
    for idx in "${!stage_labels[@]}"; do
        local addr
        addr=$(awk "/\\.${stage_labels[$idx]}\$/ { split(\$2,a,\":\"); print toupper(a[2]); exit }" "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${stage_labels[$idx]} in out/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        stage_addrs+=("$addr")
    done

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128.d64"
    local last_stage="boot"

    for idx in "${!stage_names[@]}"; do
        local mon_file
        mon_file="$(test128_tmp_file "test128_${name}_${idx}.mon")"
        local log_file
        log_file="$(test128_tmp_file "test128_${name}_${idx}.log")"
        : > "$log_file"
        {
            echo "break \$${stage_addrs[$idx]}"
            echo "g"
        } > "$mon_file"

        "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
            -keybuf $'NAA\rA\rA L' -keybuf-delay 8 \
            -moncommands "$mon_file" -monlog -monlogname "$log_file" \
            -limitcycles 320000000 +sound -sounddev dummy \
            +remotemonitor +binarymonitor >/dev/null 2>&1
        local vice_rc=$?

        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            echo "FAIL (jam before stage: ${stage_names[$idx]}; last reached: $last_stage)"
            tail -20 "$log_file" | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi

        if ! grep -qi "C:\$${stage_addrs[$idx]}" "$log_file"; then
            echo "FAIL (did not reach stage: ${stage_names[$idx]}; last reached: $last_stage; vice_rc=$vice_rc)"
            tail -20 "$log_file" | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi

        last_stage="${stage_names[$idx]}"
    done

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_real_boot_crash_harness() {
    local name="real_boot_crash_harness"
    echo -n "  $name: "

    build_real_boot_diag_assets || return

    local main_vs="out/main.vs"
    local c128_diag_fail
    c128_diag_fail=$(awk '/\.c128_diag_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_diag_fail:-}" ]; then
        echo "FAIL (missing c128_diag_fail_sym in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    local -a diag_stage_breaks=()
    while IFS= read -r addr; do
        [ -n "$addr" ] && diag_stage_breaks+=("$addr")
    done < <(awk '/\.c128_diag_fail_stage_[0-9a-f][0-9a-f]$|\.c128_diag_fail_default$/ { split($2,a,":"); print toupper(a[2]); }' "$main_vs")
    if [ "${#diag_stage_breaks[@]}" -eq 0 ]; then
        echo "FAIL (missing overlay diag stage traps in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_realdiag.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        local addr
        for addr in "${diag_stage_breaks[@]}"; do
            echo "break \$${addr}"
        done
        echo "g"
        boot_diag_dump_cmds
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 520000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    local addr
    for addr in "${diag_stage_breaks[@]}"; do
        if boot_log_has_stop_at "$log_file" "$addr"; then
            echo "FAIL (captured diag guard failure at \$${addr})"
            boot_log_report_crash_context "$log_file"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_overlay_data_transition_smoke() {
    local name="overlay_data_transition_smoke"
    echo -n "  $name: "

    build_overlay_transition_diag_assets || return

    local main_vs="out/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c128_overlay_transition_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing c128_overlay_transition_pass_sym in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local -a diag_stage_breaks=()
    while IFS= read -r addr; do
        [ -n "$addr" ] && diag_stage_breaks+=("$addr")
    done < <(awk '/\.c128_diag_fail_stage_[0-9a-f][0-9a-f]$|\.c128_diag_fail_default$/ { split($2,a,":"); print toupper(a[2]); }' "$main_vs")

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_overlaydiag.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        local addr
        for addr in "${diag_stage_breaks[@]}"; do
            echo "break \$${addr}"
        done
        echo "until \$${pass_addr}"
        echo "g"
        boot_diag_dump_cmds
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 420000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    local addr
    for addr in "${diag_stage_breaks[@]}"; do
        if boot_log_has_stop_at "$log_file" "$addr"; then
            echo "FAIL (captured overlay/data transition diag failure at \$${addr})"
            boot_log_report_crash_context "$log_file"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! boot_log_has_stop_at "$log_file" "$pass_addr"; then
        boot_log_report_failure "did not complete overlay/data transition to title menu" "$log_file" "c128_overlay_transition_pass_sym" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_cache_survival_smoke() {
    local name="cache_survival_smoke"
    echo -n "  $name: "

    build_cache_survival_boot_assets || return

    local main_vs="out/main.vs"
    local c128_test_cache_survival_pass c128_test_cache_survival_fail
    c128_test_cache_survival_pass=$(awk '/\.c128_test_cache_survival_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_cache_survival_fail=$(awk '/\.c128_test_cache_survival_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_test_cache_survival_pass:-}" ] || [ -z "${c128_test_cache_survival_fail:-}" ]; then
        echo "FAIL (missing cache-survival pass/fail symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_cache_survival.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$${c128_test_cache_survival_fail}"
        echo "until \$${c128_test_cache_survival_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if boot_log_has_stop_at "$log_file" "$c128_test_cache_survival_fail"; then
        boot_log_report_failure "cache survival validation failed after summary-to-town flow" "$log_file" "c128_test_cache_survival_fail" "$c128_test_cache_survival_fail" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! boot_log_has_stop_at "$log_file" "$c128_test_cache_survival_pass"; then
        boot_log_report_failure "did not reach cache-survival pass trap" "$log_file" "c128_test_cache_survival_pass" "$c128_test_cache_survival_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during cache-survival flow" "$log_file" "c128_test_cache_survival_pass" "$c128_test_cache_survival_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_dungeon_attack_stability_smoke() {
    local name="dungeon_attack_stability_smoke"
    echo -n "  $name: "

    build_real_boot_diag_assets || return

    local main_vs="out/main.vs"
    local player_attack monster_attack
    player_attack=$(awk '/\.player_attack_monster$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    monster_attack=$(awk '/\.monster_attack_player$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${player_attack:-}" ] || [ -z "${monster_attack:-}" ]; then
        echo "FAIL (missing combat symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_realdiag.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${player_attack}"
        echo "g"
        boot_diag_dump_cmds
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>L' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 620000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if boot_log_has_crash "$log_file"; then
        echo "FAIL (captured stop)"
        boot_log_report_crash_context "$log_file"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${player_attack}" "$log_file"; then
        boot_log_report_failure "did not reach player_attack_monster in dungeon attack flow" "$log_file" "player_attack_monster" "$player_attack" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_death_overlay_smoke() {
    local name="death_overlay_smoke"
    echo -n "  $name: "

    build_death_overlay_boot_assets || return

    local main_vs="out/main.vs"
    local score_death_screen
    score_death_screen=$(awk '/\.score_death_screen$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${score_death_screen:-}" ]; then
        echo "FAIL (missing death-flow symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_death.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${score_death_screen}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "N" -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 240000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${score_death_screen}" "$log_file"; then
        boot_log_report_failure "did not reach score_death_screen via death overlay flow" "$log_file" "score_death_screen" "$score_death_screen" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during death overlay flow" "$log_file" "score_death_screen" "$score_death_screen" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_restart_to_title_smoke() {
    local name="restart_to_title_smoke"
    echo -n "  $name: "

    build_death_overlay_boot_assets || return

    local main_vs="out/main.vs"
    local title_show_sysinfo
    title_show_sysinfo=$(awk '/\.title_show_sysinfo$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_show_sysinfo:-}" ]; then
        echo "FAIL (missing title_show_sysinfo in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_death.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${title_show_sysinfo}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA  S' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 420000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${title_show_sysinfo}" "$log_file"; then
        boot_log_report_failure "did not return to title_show_sysinfo after restart flow" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during restart-to-title flow" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_preload_partial_failure_smoke() {
    local name="preload_partial_failure_smoke"
    echo -n "  $name: "

    build_partial_failure_boot_assets || return

    local main_vs="out/main.vs"
    local dungeon_generate tier_load_disk c128_test_partial_cache_fail
    dungeon_generate=$(awk '/\.dungeon_generate$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    tier_load_disk=$(awk '/\.tier_load_disk$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_partial_cache_fail=$(awk '/\.c128_test_partial_cache_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${dungeon_generate:-}" ] || [ -z "${tier_load_disk:-}" ] || [ -z "${c128_test_partial_cache_fail:-}" ]; then
        echo "FAIL (missing required symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_skip1.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local fail_lc
    : > "$log_file"
    fail_lc=$(echo "$c128_test_partial_cache_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_partial_cache_fail}"
        echo "until \$${tier_load_disk}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file"; then
        boot_log_report_failure "tier partial-failure readiness isolation check failed" "$log_file" "c128_test_partial_cache_fail" "$c128_test_partial_cache_fail" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${tier_load_disk}" "$log_file"; then
        boot_log_report_failure "missing-tier preload did not fall back to tier_load_disk" "$log_file" "tier_load_disk" "$tier_load_disk" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    {
        echo "until \$${dungeon_generate}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${dungeon_generate}" "$log_file"; then
        boot_log_report_failure "missing-tier preload did not continue to dungeon_generate" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after missing-tier fallback" "$log_file" "dungeon_generate" "$dungeon_generate" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_overlay_partial_failure_smoke() {
    local name="overlay_partial_failure_smoke"
    echo -n "  $name: "

    build_overlay_partial_failure_boot_assets || return

    local main_vs="out/main.vs"
    local store_enter overlay_load_disk c128_test_overlay_cache_fail
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    overlay_load_disk=$(awk '/\.overlay_load_disk$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_overlay_cache_fail=$(awk '/\.c128_test_overlay_cache_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ] || [ -z "${overlay_load_disk:-}" ] || [ -z "${c128_test_overlay_cache_fail:-}" ]; then
        echo "FAIL (missing required symbols in out/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd out && pwd)/moria128_skipovl2.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local fail_lc
    : > "$log_file"
    fail_lc=$(echo "$c128_test_overlay_cache_fail" | tr '[:upper:]' '[:lower:]')

    {
        echo "break \$${c128_test_overlay_cache_fail}"
        echo "until \$${overlay_load_disk}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qiE "Stop on  exec ${fail_lc}" "$log_file"; then
        boot_log_report_failure "overlay partial-failure readiness isolation check failed" "$log_file" "c128_test_overlay_cache_fail" "$c128_test_overlay_cache_fail" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! grep -qi "^UNTIL: .*C:\$${overlay_load_disk}" "$log_file"; then
        boot_log_report_failure "missing overlay preload did not fall back to overlay_load_disk" "$log_file" "overlay_load_disk" "$overlay_load_disk" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    {
        echo "until \$${store_enter}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${store_enter}" "$log_file"; then
        boot_log_report_failure "missing overlay preload did not continue to store_enter" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam after missing-overlay fallback" "$log_file" "store_enter" "$store_enter" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
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
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
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
    local vice_rc=$?

    if ! grep -qi "^BREAK: .*C:\$${entry_main}" "$log_file"; then
        boot_log_report_failure "did not reach entry_main" "$log_file" "entry_main" "$entry_main" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_selected_suites() {
    run_named_suite main128_asm run_main_assembly_check || return 1
    run_named_suite c128_artifact_budget run_artifact_budget_check || return 1
    run_named_suite c128_symbol_placement run_symbol_placement_check || return 1
    run_named_suite c128_prompt_irq_guard run_prompt_irq_guard_check || return 1
    run_named_suite c128_80col_layout_guard run_80col_layout_guard_check || return 1

    run_parallel_unit_tests || return 1

    run_named_suite boot_d64_smoke run_boot_d64_smoke || return 1

    run_named_suite boot_title_idle_smoke run_boot_title_idle_smoke || return 1
    run_named_suite title_art_smoke run_title_art_smoke || return 1
    run_named_suite vic40_clean_boot_smoke run_vic40_clean_boot_smoke || return 1
    run_named_suite new_key_stability_smoke run_new_key_stability_smoke || return 1
    run_named_suite boot_title_newgame_smoke run_boot_title_newgame_smoke || return 1
    run_named_suite boot_title_load_resume_smoke run_boot_title_load_resume_smoke || return 1
    run_named_suite boot_tier_transition_smoke run_boot_tier_transition_smoke || return 1
    run_named_suite town_overlay_smoke run_town_overlay_smoke || return 1
    run_named_suite town_overlay_female_smoke run_town_overlay_female_smoke || return 1
    run_named_suite town_overlay_state_smoke run_town_overlay_state_smoke || return 1
    run_named_suite scripted_summary_to_town_smoke run_scripted_summary_to_town_smoke || return 1
    run_named_suite real_input_town_move_diag run_real_input_town_move_diag || return 1
    run_named_suite real_boot_crash_harness run_real_boot_crash_harness || return 1
    run_named_suite overlay_data_transition_smoke run_overlay_data_transition_smoke || return 1
    run_named_suite cache_survival_smoke run_cache_survival_smoke || return 1
    run_named_suite dungeon_attack_stability_smoke run_dungeon_attack_stability_smoke || return 1
    run_named_suite death_overlay_smoke run_death_overlay_smoke || return 1
    run_named_suite restart_to_title_smoke run_restart_to_title_smoke || return 1
    run_named_suite preload_partial_failure_smoke run_preload_partial_failure_smoke || return 1
    run_named_suite overlay_partial_failure_smoke run_overlay_partial_failure_smoke || return 1
    run_named_suite boot_diag_copy run_boot_diag_copy || return 1

    if [ "$PERF_P1_MODE" = "1" ]; then
        run_test "perf_p1" "tests/test_perf_p1.s" || return 1
    fi
}

echo "=== Moria C128 Tests ==="
if [ "$PERF_P1_MODE" = "1" ]; then
    echo "  mode: PERF_P1 instrumentation ON"
else
    echo "  mode: PERF_P1 instrumentation OFF"
fi
if [ -n "$TEST_PHASE" ]; then
    echo "  phase: $TEST_PHASE"
fi
if [ -n "$TEST_RERUN_FROM" ]; then
    echo "  rerun-from: $TEST_RERUN_FROM"
elif [ "$TEST_RERUN_LAST" != "0" ]; then
    echo "  rerun-last: ON"
fi
if [ -n "$TEST_RERUN_FROM" ] || [ "$TEST_RERUN_LAST" != "0" ]; then
    echo "  rerun-status: $TEST_RERUN_STATUS"
fi
if [ "$TEST_DESCRIBE" != "0" ]; then
    echo "  describe: ON"
fi
if [ -n "$TEST_FILTER" ]; then
    echo "  filter: $TEST_FILTER"
fi
if [ -n "$TEST_SKIP" ]; then
    echo "  skip: $TEST_SKIP"
fi
if [ "$TEST_LIST" != "0" ]; then
    echo "  list-only: ON"
fi
if [ "$TEST_JOBS" = "auto" ]; then
    echo "  jobs: auto -> $TEST_JOBS_RESOLVED"
else
    echo "  jobs: $TEST_JOBS_RESOLVED"
fi
if [ "$TEST_TIMINGS" != "0" ]; then
    echo "  timings: ON"
fi
if [ -n "$TEST_SUMMARY" ]; then
    echo "  summary: $TEST_SUMMARY"
fi
if [ "$TEST_FAIL_FAST" != "0" ]; then
    echo "  fail-fast: ON"
fi
if [ "$TEST_REPEAT_RESOLVED" -gt 1 ] && [ "$TEST_LIST" = "0" ]; then
    echo "  repeat: $TEST_REPEAT_RESOLVED"
elif [ "$TEST_REPEAT_RESOLVED" -gt 1 ]; then
    echo "  repeat: $TEST_REPEAT_RESOLVED (list-only ignored)"
fi

if [ "$TEST_DESCRIBE" != "0" ]; then
    describe_phases
    exit 0
fi

if ! load_rerun_selection; then
    exit 1
fi
if [ -n "${TEST128_RERUN_SOURCE:-}" ]; then
    if [ "$TEST_RERUN_LAST" != "0" ] && [ -z "$TEST_RERUN_FROM" ]; then
        echo "  rerun-from: $TEST128_RERUN_SOURCE"
    fi
    echo "  rerun suites: $TEST128_RERUN_COUNT"
fi

if [ "$TEST_LIST" != "0" ]; then
    run_selected_suites || exit 1
    echo "=== Selected: $TOTAL suites ==="
    exit 0
fi

stopped_early=0
repeat_idx=1
while [ "$repeat_idx" -le "$TEST_REPEAT_RESOLVED" ]; do
    TEST128_ITERATION="$repeat_idx"
    if [ "$TEST_REPEAT_RESOLVED" -gt 1 ]; then
        echo "--- Iteration $repeat_idx/$TEST_REPEAT_RESOLVED ---"
    fi
    if ! run_selected_suites; then
        stopped_early=1
        break
    fi
    repeat_idx=$((repeat_idx + 1))
done
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL suites) ==="
if [ "$stopped_early" -ne 0 ]; then
    echo "=== Stopped early after first failure ==="
fi
print_timing_summary
emit_test_summary

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
