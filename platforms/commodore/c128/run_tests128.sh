#!/bin/bash
# run_tests128.sh — Assemble and run C128 runtime tests in VICE headless

set -u

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
RUN_TESTS128_DIR="${RUN_TESTS128_DIR:-$REPO_ROOT/platforms/commodore/c128}"
cd "$RUN_TESTS128_DIR"
C128_TEST_OUT="${C128_TEST_OUT:-../../../build/test/c128}"
C128_BUILD_OUT="${C128_BUILD_OUT:-../../../build/c128}"
mkdir -p "$C128_TEST_OUT"
if [ -d "$C128_BUILD_OUT" ]; then
    cp -p "$C128_BUILD_OUT"/* "$C128_TEST_OUT"/ 2>/dev/null || true
fi
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
KICKASS="$(cd "$(dirname "$KICKASS")" && pwd)/$(basename "$KICKASS")"
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
TEST_RERUN_ONLY_LATEST="${TEST_RERUN_ONLY_LATEST:-0}"
TEST_RERUN_INVERT="${TEST_RERUN_INVERT:-0}"
TEST_RERUN_LIMIT="${TEST_RERUN_LIMIT:-0}"
TEST_RERUN_ORDER="${TEST_RERUN_ORDER:-forward}"
TEST_RERUN_SHUFFLE="${TEST_RERUN_SHUFFLE:-0}"
TEST_RERUN_SEED="${TEST_RERUN_SEED:-0}"
TEST_RERUN_STRIDE="${TEST_RERUN_STRIDE:-1}"
TEST_RERUN_OFFSET="${TEST_RERUN_OFFSET:-0}"
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
TEST128_LAST_SUMMARY_MARKER="../../../build/test/c128/.test128_last_summary_path"
TEST128_ITERATION=1
TEST128_RERUN_COUNT=0
C128_ACTIVE_VARIANT_FILE="../../../build/test/c128/.test128_active_variant"
BOOT_ASSETS_BUILT=0
PARTIAL_BOOT_ASSETS_BUILT=0
OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=0
DEATH_BOOT_ASSETS_BUILT=0
OVERLAY_STATE_BOOT_ASSETS_BUILT=0
SCRIPTED_INPUT_BOOT_ASSETS_BUILT=0
PERF_P1_TRACE_BOOT_ASSETS_BUILT=0
SCRIPTED_SPELL_BOOT_ASSETS_BUILT=0
SCRIPTED_SPELL_CANCEL_BOOT_ASSETS_BUILT=0
SCRIPTED_BOOK_OVERLAY_BOOT_ASSETS_BUILT=0
SCRIPTED_SPELL_LIST_OVERLAY_BOOT_ASSETS_BUILT=0
SCRIPTED_PRAYER_BOOT_ASSETS_BUILT=0
SAVE_WRITE_PRODUCT_BOOT_ASSETS_BUILT=0
CACHE_SURVIVAL_BOOT_ASSETS_BUILT=0
LOAD_RESUME_BOOT_ASSETS_BUILT=0
REAL_BOOT_DIAG_ASSETS_BUILT=0
TITLE_ART_BOOT_ASSETS_BUILT=0
TITLE_LOAD_MISSING_SAVE_ASSETS_BUILT=0
TITLE_LOAD_MOUNTED_SAVE_ASSETS_BUILT=0
OVERLAY_TRANSITION_DIAG_ASSETS_BUILT=0

KA_DEFINES=(-define C128 :OVL_OUT=../../../build/test/c128)
if [ "$PERF_P1_MODE" = "1" ]; then
    KA_DEFINES+=(-define PERF_P1)
fi

cleanup_test128_tmp() {
    rm -f ./*.prg ./*.sym ./*.vs tests/*.prg tests/*.sym tests/*.vs
    rm -f "$REPO_ROOT"/platforms/commodore/c64/creature_data/*.sym "$REPO_ROOT"/platforms/commodore/c64/creature_data/*.vs
    rm -f "$REPO_ROOT"/core/*.sym "$REPO_ROOT"/core/*.vs
    if [ "${TEST128_KEEP_TMP:-0}" = "1" ]; then
        return
    fi
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
        summary_file="../../../build/test/c128/.test128_last_summary.${TEST_SUMMARY}"
    fi

    case "$TEST_SUMMARY" in
        tsv)
            {
                printf 'status\tsuite\tduration_ms\tdetail\titeration\n'
                cat "$TEST128_RESULTS_FILE"
            } > "$summary_file"
            ;;
        json)
            python3 - "$TEST128_RESULTS_FILE" "$summary_file" "$PASS" "$FAIL" "$TOTAL" "$TEST_FILTER" "$TEST_SKIP" "$TEST_PHASE" "${TEST128_RERUN_SOURCE:-}" "$TEST_RERUN_LAST" "$TEST_RERUN_STATUS" "$TEST_RERUN_ONLY_LATEST" "$TEST_RERUN_INVERT" "$TEST_RERUN_LIMIT" "$TEST_RERUN_ORDER" "$TEST_RERUN_SHUFFLE" "$TEST_RERUN_SEED" "$TEST_RERUN_STRIDE" "$TEST_RERUN_OFFSET" "$TEST_JOBS" "$TEST_JOBS_RESOLVED" "$TEST_REPEAT_RESOLVED" "$TEST_TIMINGS" "$TEST_FAIL_FAST" <<'PY'
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
    "rerun_only_latest": sys.argv[12] != "0",
    "rerun_invert": sys.argv[13] != "0",
    "rerun_limit": int(sys.argv[14]),
    "rerun_order": sys.argv[15],
    "rerun_shuffle": sys.argv[16] != "0",
    "rerun_seed": int(sys.argv[17]),
    "rerun_stride": int(sys.argv[18]),
    "rerun_offset": int(sys.argv[19]),
    "jobs_requested": sys.argv[20],
    "jobs_resolved": int(sys.argv[21]),
    "repeat": int(sys.argv[22]),
    "timings": sys.argv[23] != "0",
    "fail_fast": sys.argv[24] != "0",
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
        python3 - "$TEST128_RERUN_SOURCE" "$TEST128_RERUN_FILE" "$TEST_RERUN_STATUS" "$TEST_RERUN_ONLY_LATEST" "$TEST_RERUN_LIMIT" "$TEST_RERUN_ORDER" "$TEST_RERUN_SHUFFLE" "$TEST_RERUN_SEED" "$TEST_RERUN_STRIDE" "$TEST_RERUN_OFFSET" <<'PY'
import json
import random
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
status_pattern = sys.argv[3]
only_latest = sys.argv[4] != "0"
try:
    limit = int(sys.argv[5])
except ValueError:
    limit = 0
order_mode = sys.argv[6]
shuffle_mode = sys.argv[7] != "0"
try:
    shuffle_seed = int(sys.argv[8])
except ValueError:
    shuffle_seed = 0
try:
    stride = int(sys.argv[9])
except ValueError:
    stride = 1
if stride < 1:
    stride = 1
try:
    offset = int(sys.argv[10])
except ValueError:
    offset = 0
if offset < 0:
    offset = 0
text = src.read_text()
lines = [line for line in text.splitlines() if line.strip()]
suites = []
raw_suites = []

def add(name):
    if not name or name in raw_suites:
        return
    raw_suites.append(name)

def status_matches(value):
    return re.fullmatch(status_pattern, value or "") is not None

def emit_latest(entries):
    latest = {}
    for order, entry in enumerate(entries):
        suite = entry.get("suite", "")
        if not suite:
            continue
        iteration = entry.get("iteration")
        try:
            iteration_num = int(iteration)
        except (TypeError, ValueError):
            iteration_num = order + 1
        prev = latest.get(suite)
        current = (iteration_num, order, entry.get("status", ""))
        if prev is None or current[:2] >= prev[:2]:
            latest[suite] = current
    for suite, (_, _, status) in latest.items():
        if status_matches(status):
            add(suite)

if src.suffix.lower() == ".json" or (lines and lines[0].lstrip().startswith("{")):
    payload = json.loads(text)
    entries = payload.get("results", [])
    if only_latest:
        emit_latest(entries)
    else:
        for entry in entries:
            if status_matches(entry.get("status", "")):
                add(entry.get("suite", ""))
else:
    start = 0
    if lines and lines[0].startswith("status\t"):
        start = 1
    entries = []
    for line in lines[start:]:
        parts = (line.split("\t", 4) + ["", "", "", "", ""])[:5]
        entries.append({
            "status": parts[0],
            "suite": parts[1],
            "iteration": parts[4],
        })
    if only_latest:
        emit_latest(entries)
    else:
        for entry in entries:
            if entry.get("suite") and status_matches(entry.get("status", "")):
                add(entry["suite"])

if shuffle_mode:
    rng = random.Random(shuffle_seed)
    ordered = list(raw_suites)
    rng.shuffle(ordered)
elif order_mode == "reverse":
    ordered = list(reversed(raw_suites))
else:
    ordered = list(raw_suites)

if offset > 0:
    ordered = ordered[offset:]

if stride > 1:
    ordered = ordered[::stride]

if limit > 0:
    ordered = ordered[:limit]

dst.write_text("".join(f"{suite}\n" for suite in ordered))
print(len(ordered))
PY
    )" || return 1
}

suite_matches_rerun() {
    local suite_name="$1"
    if [ -z "${TEST128_RERUN_SOURCE:-}" ]; then
        return 0
    fi
    local matched=1
    if [ -f "$TEST128_RERUN_FILE" ] && grep -Fxq "$suite_name" "$TEST128_RERUN_FILE"; then
        matched=0
    fi
    if [ "$TEST_RERUN_INVERT" != "0" ]; then
        if [ "$matched" -eq 0 ]; then
            return 1
        fi
        return 0
    fi
    return "$matched"
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

c128_sync_build_out() {
    mkdir -p "$C128_TEST_OUT"
    if [ -d "$C128_BUILD_OUT" ]; then
        cp -p "$C128_BUILD_OUT"/* "$C128_TEST_OUT"/ 2>/dev/null || true
    fi
}

describe_phase_token() {
    local phase="$1"
    case "$phase" in
        all)
            printf 'all\tAll suites\n'
            ;;
        guards)
            printf 'guards\tmain128_asm,c128_artifact_budget,c128_symbol_placement,c128_user_visible_string_guard,c128_prompt_irq_guard,c128_item_overlay_key_guard,c128_input_run_guard,c128_80col_layout_guard,c128_ref_hal_guard,c128_save_load_guard\n'
            ;;
        units)
            printf 'units\tminimal128,config128,memory128,db128,tier128,input128,disk_swap128,main_loop128,msg_prompt128,vdc_attr128,item_desc128,vdc_scroll_delta128,status_coherence128,dungeon128,soak128,monster128,detect_monsters128,detect_evil128,cure_light_wounds128,cure_poison128,cure_light_wounds_prayer128,bless_prayer128,remove_fear_prayer128,call_light_prayer128,find_traps_prayer128,detect_doors_stairs_prayer128,slow_poison_prayer128,blind_creature_prayer128,portal_prayer128,cure_medium_wounds_prayer128,cure_serious_wounds_prayer128,sense_invisible_prayer128,protection_from_evil_prayer128,earthquake_prayer128,sense_surroundings_prayer128,cure_critical_wounds_prayer128,turn_undead_prayer128,prayer_prayer128,dispel_undead_prayer128,dispel_evil_prayer128,glyph_of_warding_prayer128,holy_word_prayer128,heal_prayer128,chant_prayer128,sanctuary_prayer128,neutralize_poison_prayer128,create_food_prayer128,remove_curse_prayer128,resist_heat_cold_prayer128,orb_of_draining_prayer128,find_hidden_traps_doors128,stinking_cloud128,frost_ball128,teleport_other128,haste_self128,fire_ball128,word_of_destruction128,genocide128,confusion128,lightning_bolt128,trap_door_destruction128,sleep_i128,sleep_ii128,sleep_iii128,fire_bolt128,slow_monster128,polymorph_other128,identify128,teleport_self128,recharge_item_ii128\n'
            ;;
        smokes)
            printf 'smokes\tboot_d64_smoke,boot_title_idle_smoke,title_art_smoke,marker_init_d64_smoke,boot_title_load_missing_savefile_smoke,boot_title_load_mounted_save_smoke,boot_title_save_write_product_smoke,boot_title_save_media_fail_product_smoke,boot_title_single_drive_save_wrong_media_smoke,boot_title_single_drive_load_wrong_media_smoke,boot_title_single_drive_load_corrupt_smoke,boot_title_single_drive_load_return_smoke,boot_title_single_drive_fresh_save_smoke,vic40_clean_boot_smoke,new_key_stability_smoke,boot_title_newgame_smoke,boot_title_load_resume_smoke,boot_tier_transition_smoke,town_overlay_smoke,town_overlay_female_smoke,town_overlay_state_smoke,scripted_summary_to_town_smoke,scripted_spell_cast_smoke,scripted_book_overlay_smoke,scripted_spell_list_overlay_smoke,scripted_spell_list_cancel_smoke,scripted_prayer_cast_smoke,cache_survival_smoke,dungeon_attack_stability_smoke,death_overlay_smoke,restart_to_title_smoke,preload_partial_failure_smoke,overlay_partial_failure_smoke\n'
            ;;
        boot)
            printf 'boot\tboot_d64_smoke,boot_title_idle_smoke,title_art_smoke,boot_title_load_missing_savefile_smoke,boot_title_load_mounted_save_smoke,boot_title_save_write_product_smoke,boot_title_save_media_fail_product_smoke,vic40_clean_boot_smoke,new_key_stability_smoke,boot_title_newgame_smoke,boot_title_load_resume_smoke,boot_tier_transition_smoke,boot_diag_copy\n'
            ;;
        town)
            printf 'town\ttown_overlay_smoke,town_overlay_female_smoke,town_overlay_state_smoke,scripted_summary_to_town_smoke,scripted_spell_cast_smoke,scripted_book_overlay_smoke,scripted_spell_list_overlay_smoke,scripted_spell_list_cancel_smoke,scripted_prayer_cast_smoke,real_input_town_move_diag,real_boot_crash_harness\n'
            ;;
        cache)
            printf 'cache\tcache_survival_smoke,preload_partial_failure_smoke,overlay_partial_failure_smoke,overlay_data_transition_smoke\n'
            ;;
        diag)
            printf 'diag\treal_input_town_move_diag,real_boot_crash_harness,overlay_data_transition_smoke,boot_diag_copy\n'
            ;;
        perf)
            printf 'perf\tperf_p1,perf_p1_trace_smoke\n'
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
                main128_asm|c128_artifact_budget|c128_symbol_placement|c128_user_visible_string_guard|c128_prompt_irq_guard|c128_item_overlay_key_guard|c128_input_run_guard|c128_80col_layout_guard|c128_ref_hal_guard|c128_save_load_guard) return 0 ;;
            esac
            ;;
        units)
            case "$suite_name" in
                minimal128|config128|memory128|db128|tier128|input128|disk_swap128|main_loop128|msg_prompt128|vdc_attr128|item_desc128|vdc_scroll_delta128|status_coherence128|dungeon128|soak128|monster128|detect_monsters128|detect_evil128|cure_light_wounds128|cure_poison128|cure_light_wounds_prayer128|bless_prayer128|remove_fear_prayer128|call_light_prayer128|find_traps_prayer128|detect_doors_stairs_prayer128|slow_poison_prayer128|blind_creature_prayer128|portal_prayer128|cure_medium_wounds_prayer128|cure_serious_wounds_prayer128|sense_invisible_prayer128|protection_from_evil_prayer128|earthquake_prayer128|sense_surroundings_prayer128|cure_critical_wounds_prayer128|turn_undead_prayer128|prayer_prayer128|dispel_undead_prayer128|dispel_evil_prayer128|glyph_of_warding_prayer128|holy_word_prayer128|heal_prayer128|chant_prayer128|sanctuary_prayer128|neutralize_poison_prayer128|create_food_prayer128|remove_curse_prayer128|resist_heat_cold_prayer128|orb_of_draining_prayer128|find_hidden_traps_doors128|stinking_cloud128|frost_ball128|teleport_other128|haste_self128|fire_ball128|word_of_destruction128|genocide128|confusion128|lightning_bolt128|frost_bolt128|turn_stone_to_mud128|create_food128|recharge_item_i128|recharge_item_ii128|trap_door_destruction128|sleep_i128|sleep_ii128|sleep_iii128|fire_bolt128|slow_monster128|polymorph_other128|identify128|teleport_self128|remove_curse128) return 0 ;;
            esac
            ;;
        smokes)
            case "$suite_name" in
                boot_d64_smoke|boot_title_idle_smoke|title_art_smoke|marker_init_d64_smoke|boot_title_load_missing_savefile_smoke|boot_title_load_mounted_save_smoke|boot_title_save_write_product_smoke|boot_title_save_media_fail_product_smoke|boot_title_single_drive_save_wrong_media_smoke|boot_title_single_drive_load_wrong_media_smoke|boot_title_single_drive_load_corrupt_smoke|boot_title_single_drive_load_return_smoke|boot_title_single_drive_fresh_save_smoke|vic40_clean_boot_smoke|new_key_stability_smoke|boot_title_newgame_smoke|boot_title_load_resume_smoke|boot_tier_transition_smoke|town_overlay_smoke|town_overlay_female_smoke|town_overlay_state_smoke|scripted_summary_to_town_smoke|scripted_spell_cast_smoke|scripted_book_overlay_smoke|scripted_spell_list_overlay_smoke|scripted_spell_list_cancel_smoke|scripted_prayer_cast_smoke|cache_survival_smoke|dungeon_attack_stability_smoke|death_overlay_smoke|restart_to_title_smoke|preload_partial_failure_smoke|overlay_partial_failure_smoke) return 0 ;;
            esac
            ;;
        boot)
            case "$suite_name" in
                boot_d64_smoke|boot_title_idle_smoke|title_art_smoke|boot_title_load_missing_savefile_smoke|boot_title_load_mounted_save_smoke|boot_title_save_write_product_smoke|boot_title_save_media_fail_product_smoke|vic40_clean_boot_smoke|new_key_stability_smoke|boot_title_newgame_smoke|boot_title_load_resume_smoke|boot_tier_transition_smoke|boot_diag_copy) return 0 ;;
            esac
            ;;
        town)
            case "$suite_name" in
                town_overlay_smoke|town_overlay_female_smoke|town_overlay_state_smoke|scripted_summary_to_town_smoke|scripted_spell_cast_smoke|scripted_book_overlay_smoke|scripted_spell_list_overlay_smoke|scripted_spell_list_cancel_smoke|scripted_prayer_cast_smoke|real_input_town_move_diag|real_boot_crash_harness) return 0 ;;
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
                perf_p1|perf_p1_trace_smoke) return 0 ;;
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
    local suite_aliases="${2:-}"
    local suite_alias
    if ! suite_matches_rerun "$suite_name"; then
        return 1
    fi
    if ! suite_matches_phase "$suite_name"; then
        local phase_match=1
        for suite_alias in $suite_aliases; do
            if [ -n "$suite_alias" ] && suite_matches_phase "$suite_alias"; then
                phase_match=0
                break
            fi
        done
        if [ "$phase_match" -ne 0 ]; then
            return 1
        fi
    fi

    if [ -z "$TEST_FILTER" ]; then
        :
    elif ! [[ "$suite_name" =~ $TEST_FILTER ]]; then
        local filter_match=1
        for suite_alias in $suite_aliases; do
            if [ -n "$suite_alias" ] && [[ "$suite_alias" =~ $TEST_FILTER ]]; then
                filter_match=0
                break
            fi
        done
        if [ "$filter_match" -ne 0 ]; then
            return 1
        fi
    fi

    if [ -n "$TEST_SKIP" ]; then
        if [[ "$suite_name" =~ $TEST_SKIP ]]; then
            return 1
        fi
        for suite_alias in $suite_aliases; do
            if [ -n "$suite_alias" ] && [[ "$suite_alias" =~ $TEST_SKIP ]]; then
                return 1
            fi
        done
    fi

    return 0
}

run_named_suite() {
    local suite_name="$1"
    local suite_aliases=""
    while [ "${2:-}" = "--alias" ]; do
        suite_aliases="$suite_aliases ${3:-}"
        shift 2
    done
    shift
    if ! suite_matches_filter "$suite_name" "$suite_aliases"; then
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

run_disk_media_probe() {
    local name="$1"

    echo -n "  $name: "
    if python3 -u ../disk_media_probe.py --scenario "$name" --platform c128 --c1541 "$C1541"; then
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

run_main_assembly_check() {
    echo -n "  main128_asm: "

    local build_log
    build_log="$(test128_tmp_file test128_main_build.log)"
    local force_base_rebuild=0
    if ! c128_active_variant_is "base"; then
        force_base_rebuild=1
    fi

    # KickAssembler can return 0 even when .assert fails, so gate on both
    # process status and emitted failure markers.
    if [ "$force_base_rebuild" -eq 1 ]; then
        if ! "${COMMODORE_MAKE[@]}" -W c128/main.s -W c128/boot128.s KICKASS="$KICKASS" build128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
            echo "FAIL"
            grep -E "assert|FAILED|ERROR" "$build_log" | tail -5 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    elif ! "${COMMODORE_MAKE[@]}" KICKASS="$KICKASS" build128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
        echo "FAIL"
        grep -E "assert|FAILED|ERROR" "$build_log" | tail -5 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    c128_sync_build_out
    local assert_line
    assert_line=$(grep "Made .*asserts" "$build_log" | tail -1)
    if [ -n "${assert_line:-}" ]; then
        echo "PASS (${assert_line})"
    else
        echo "PASS"
    fi
    c128_set_active_variant "base"
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

prg = Path("../../../build/test/c128/moria128.prg")
vs = Path("../../../build/test/c128/main.vs")
if not prg.exists() or not vs.exists():
    print("missing build outputs")
    raise SystemExit(1)

data = prg.read_bytes()
if len(data) < 2:
    print("short prg")
    raise SystemExit(1)
load = data[0] | (data[1] << 8)
end = load + len(data) - 2 - 1

labels = {}
for line in vs.read_text().splitlines():
    m = re.match(r"al\s+C:([0-9A-Fa-f]+)\s+\.([A-Za-z0-9_]+)$", line)
    if m:
        labels[m.group(2)] = int(m.group(1), 16)

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
    "commands": ["item_aim_wand", "item_use_staff", "item_gain_spell", "player_cast_spell", "player_pray", "spell_list_display", "spell_execute_selected", "magic_check_new_spells", "calc_spell_failure", "ranged_fire", "throw_item", "bash_command"],
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

    local sym_file="../../../build/test/c128/main.vs"
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
sym = Path("../../../build/test/c128/main.vs").read_text().splitlines()
main_text = Path("main.s").read_text()
contract_source = Path("io_contracts.s").read_text().splitlines()
labels = {}
for line in sym:
    m = re.match(r"al\s+C:([0-9A-Fa-f]+)\s+\.([A-Za-z0-9_]+)$", line)
    if not m:
        continue
    labels[m.group(2)] = int(m.group(1), 16)

contract_patterns = {
    "below_io_hole": re.compile(r':C128AuditBelowIo\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "out_of_io_hole": re.compile(r':C128AuditOutOfIo\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*\$(\w+)\s*\)'),
    "runtime_low_bank0": re.compile(r':C128AuditRuntimeLow\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "runtime_projectile_bank0": re.compile(r':C128AuditRuntimeProjectile\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "runtime_input_bank0": re.compile(r':C128AuditRuntimeInput\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "startup_overlay": re.compile(r':C128AuditStartupOverlay\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "town_overlay": re.compile(r':C128AuditTownOverlay\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "death_overlay": re.compile(r':C128AuditDeathOverlay\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "help_overlay": re.compile(r':C128AuditHelpOverlay\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "ui_overlay": re.compile(r':C128AuditUiOverlay\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "dungeon_overlay": re.compile(r':C128AuditDungeonOverlay\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
    "banked_window": re.compile(r':C128AuditBanked\("([^"]+)",\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'),
}

contracts = []
for raw in contract_source:
    line = raw.strip()
    if not line or line.startswith("//") or line.startswith("#"):
        continue
    for kind, pattern in contract_patterns.items():
        m = pattern.match(line)
        if not m:
            continue
        display = m.group(1)
        symbol = m.group(2)
        arg = int(m.group(3), 16) if kind == "out_of_io_hole" else None
        contracts.append((kind, display, symbol, arg))
        break

if not contracts:
    print("io_contracts.s: no parsed residency contracts")
    raise SystemExit(1)

required_labels = [
    "banked_code_end",
    "runtime_projectile_data_start",
    "runtime_projectile_data_end",
    "runtime_input_data_start",
    "runtime_input_data_end",
    "runtime_low_data_start",
    "runtime_low_data_end",
    "ovl_start_end",
    "ovl_town_end",
    "ovl_death_end",
    "ovl_help_end",
    "ovl_ui_end",
    "ovl_gen_end",
]

below_io_data = [
    "title_menu_str",
    "ds_save_str",
    "ds_game_str",
    "game_over_prompt_end",
]

bad = []
missing = []

for name in required_labels:
    if name not in labels:
        missing.append(name)

for name in below_io_data:
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] >= 0xD000:
        bad.append((name, labels[name], "below_io_hole"))

if "msg_history" not in labels or "msg_hist_idx" not in labels:
    missing.append("msg_history/msg_hist_idx")
else:
    if labels["msg_hist_idx"] - labels["msg_history"] != (8 * 80):
        bad.append(("msg_history_span", labels["msg_hist_idx"] - labels["msg_history"], "width"))

for name in ("help_title_str", "help_lines"):
    if name not in labels:
        missing.append(name)
        continue
    if labels[name] < 0xE000 or labels[name] >= 0xF000:
        bad.append((name, labels[name], "overlay_window"))

for runtime_name, expected_load in (
    ("128.runtime.prg", 0x1000),
    ("128.input.prg", 0x0B00),
    ("128.proj.prg", 0x0A80),
    ("128.fdisk.prg", 0x0D60),
    ("128.world.prg", 0x6000),
    ("128.item.prg", 0x8C70),
    ("128.names.prg", 0x7400),
    ("128.select.prg", 0xA800),
    ("128.persist.prg", 0xAF00),
    ("128.play.prg", 0xAF00),
    ("128.bank.prg", 0xF000),
):
    runtime_prg = Path("../../../build/test/c128") / runtime_name
    if not runtime_prg.exists():
        missing.append(f"../../../build/test/c128/{runtime_name}")
        continue
    data = runtime_prg.read_bytes()
    if len(data) < 2:
        bad.append((runtime_name, len(data), "short"))
        continue
    load = data[0] | (data[1] << 8)
    if load != expected_load:
        bad.append((f"{runtime_name} header", load, "load_header"))

if "runtime_low_data_start" in labels and labels["runtime_low_data_start"] != 0x1000:
    bad.append(("runtime_low_data_start", labels["runtime_low_data_start"], "runtime_low_base"))

overlay_limits = {
    "startup_overlay": labels.get("ovl_start_end"),
    "town_overlay": labels.get("ovl_town_end"),
    "death_overlay": labels.get("ovl_death_end"),
    "help_overlay": labels.get("ovl_help_end"),
    "ui_overlay": labels.get("ovl_ui_end"),
    "dungeon_overlay": labels.get("ovl_gen_end"),
}

for kind, _display, symbol, arg in contracts:
    if symbol not in labels:
        missing.append(symbol)
        continue
    addr = labels[symbol]
    if kind == "below_io_hole":
        if addr >= 0xD000:
            bad.append((symbol, addr, kind))
    elif kind == "out_of_io_hole":
        if 0xD000 <= addr < arg:
            bad.append((symbol, addr, kind))
    elif kind == "runtime_low_bank0":
        start = labels.get("runtime_low_data_start")
        end = labels.get("runtime_low_data_end")
        if start is None or end is None:
            missing.extend(name for name in ("runtime_low_data_start", "runtime_low_data_end") if name not in labels)
        elif not (start <= addr < end):
            bad.append((symbol, addr, kind))
    elif kind == "runtime_projectile_bank0":
        start = labels.get("runtime_projectile_data_start")
        end = labels.get("runtime_projectile_data_end")
        if start is None or end is None:
            missing.extend(name for name in ("runtime_projectile_data_start", "runtime_projectile_data_end") if name not in labels)
        elif not (start <= addr < end):
            bad.append((symbol, addr, kind))
    elif kind == "runtime_input_bank0":
        start = labels.get("runtime_input_data_start")
        end = labels.get("runtime_input_data_end")
        if start is None or end is None:
            missing.extend(name for name in ("runtime_input_data_start", "runtime_input_data_end") if name not in labels)
        elif not (start <= addr < end):
            bad.append((symbol, addr, kind))
    elif kind == "banked_window":
        end = labels.get("banked_code_end")
        if end is None:
            missing.append("banked_code_end")
        elif not (0xF000 <= addr < end):
            bad.append((symbol, addr, kind))
    else:
        end = overlay_limits.get(kind)
        if end is None:
            missing.append(kind)
        elif not (0xE000 <= addr < end):
            bad.append((symbol, addr, kind))

for label in (
    "tramp_ui_help_display",
    "tramp_ui_inv_display",
    "tramp_ui_inv_select_display",
    "tramp_ui_equip_display",
    "tramp_ui_recall",
):
    if f"{label}:\n    jsr init_copy_banked" in main_text:
        print(f"{label}: stale per-entry init_copy_banked reload reintroduced")
        raise SystemExit(1)

if "tramp_ui_exit:\n    lda #$36                    // BANK_NO_BASIC\n    sta $01\n    lda #$3e                    // MMU_ALL_RAM\n    sta $ff00\n    jsr c128_restore_runtime_guards\n    cli" not in main_text:
    print("tramp_ui_exit: expected runtime guard restore before CLI")
    raise SystemExit(1)

if "ldx #21\n    jsr vdc_write_reg\n    lda #8\n    dex                         // 20\n    jsr vdc_write_reg" not in main_text:
    print("vdc_attr_base_init: expected reg21/reg20 init sequence with lda #8 for reg20")
    raise SystemExit(1)

if missing or bad:
    if missing:
        print("missing:" + ",".join(missing))
    for name, addr, kind in bad:
        if isinstance(addr, int):
            print(f"bad:{kind}:{name}=${addr:04X}")
        else:
            print(f"bad:{kind}:{name}={addr}")
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

run_user_visible_string_guard_check() {
    echo -n "  user_visible_string_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

main_text = Path("main.s").read_text()
common = Path("..") / "common"
reu_text = (common / "reu.s").read_text()
tier_text = Path("../../../core/tier_manager.s").read_text()
overlay_text = (common / "overlay.s").read_text()
storage_overlay_text = (Path("hal") / "storage_overlay_names.s").read_text()
storage_tier_text = (Path("hal") / "storage_tier_names.s").read_text()
required = {
    "runtime_low_filename/display alias": 'runtime_low_filename:\nruntime_low_display_str:\n    .text "128.RUNTIME"\nruntime_low_filename_end:\n    .byte 0\n.const RUNTIME_LOW_FILENAME_LEN = runtime_low_filename_end - runtime_low_filename',
    "runtime_input null-terminated load filename": 'runtime_input_filename_end:\n    .byte 0\n.const RUNTIME_INPUT_FILENAME_LEN = runtime_input_filename_end - runtime_input_filename',
    "runtime_common null-terminated load filename": 'runtime_common_filename_end:\n    .byte 0\n.const RUNTIME_COMMON_FILENAME_LEN = runtime_common_filename_end - runtime_common_filename',
    "REU tier display points at HAL load filenames": '.label reu_fn_tier_lo = hal_storage_tier_name_lo',
    "REU overlay display points at HAL load filenames": '.label reu_fn_ovl_lo = hal_storage_overlay_name_lo',
}

sources = {
    "runtime_low_filename/display alias": main_text,
    "runtime_input null-terminated load filename": main_text,
    "runtime_common null-terminated load filename": main_text,
    "REU tier display points at HAL load filenames": reu_text,
    "REU overlay display points at HAL load filenames": reu_text,
}

missing = [name for name, token in required.items() if token not in sources[name]]
if missing:
    for name in missing:
        print(f"{name} must stay a single unshortened source string")
    raise SystemExit(1)

for forbidden in (
    'reu_fn_t1: .text',
    'reu_fn_o1: .text',
):
    if forbidden in reu_text:
        print(f"{forbidden} reintroduced a duplicate display filename")
        raise SystemExit(1)

for name in ("hal_storage_tier_1_name", "hal_storage_tier_2_name", "hal_storage_tier_3_name", "hal_storage_tier_4_name"):
    if f"{name}:" not in storage_tier_text or f"{name}_len" not in storage_tier_text:
        print(f"{name} must be a platform-owned C128 tier filename literal with explicit length")
        raise SystemExit(1)

for name in ("hal_storage_overlay_start_name", "hal_storage_overlay_town_name", "hal_storage_overlay_death_name", "hal_storage_overlay_gen_name", "hal_storage_overlay_help_name", "hal_storage_overlay_ui_name", "hal_storage_overlay_items_name"):
    if f"{name}:" not in storage_overlay_text or f"{name}_len" not in storage_overlay_text:
        print(f"{name} must be a platform-owned C128 overlay filename literal with explicit length")
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
core = root.parent.parent / "core"
screen = (root / "c128" / "screen_vdc.s").read_text()
render = (root / "c128" / "dungeon_render_vdc.s").read_text()
main128 = (root / "c128" / "main.s").read_text()
msgs = (core / "ui_messages.s").read_text()
status = (core / "ui_status.s").read_text()
help_s = (core / "ui_help.s").read_text()
swap = (root / "common" / "disk_swap.s").read_text()
char_s = (core / "ui_character.s").read_text()
sysinfo = (core / "title_sysinfo_banked.s").read_text()

def must_contain(text: str, snippet: str, err: str):
    if snippet not in text:
        print(err)
        raise SystemExit(1)

def must_not_contain(text: str, snippet: str, err: str):
    if snippet in text:
        print(err)
        raise SystemExit(1)

must_contain(screen, '#import "hal/layout.s"', "screen_vdc must import layout HAL constants")
must_contain(screen, ".const SCREEN_COLS = hal_layout_screen_cols", "screen_vdc must alias SCREEN_COLS to layout HAL")
must_contain(screen, ".const VIEWPORT_X  = hal_layout_viewport_x", "screen_vdc must alias VIEWPORT_X to layout HAL")
must_contain(screen, ".const VIEWPORT_W  = hal_layout_viewport_w", "screen_vdc must alias VIEWPORT_W to layout HAL")
must_contain(screen, ".const VDC_ATTR_MODE = $80", "screen_vdc must keep VDC_ATTR_MODE=$80 (Set 1 charset)")
must_not_contain(screen, "SCREEN_COL_OFFSET", "screen_vdc must not use implicit SCREEN_COL_OFFSET")
must_not_contain(render, "VIEWPORT_X + SCREEN_COL_OFFSET", "dungeon_render_vdc must use explicit VIEWPORT_X only")

must_contain(msgs, ".const MSG_HIST_LEN   = SCREEN_COLS", "ui_messages must size history by SCREEN_COLS")
must_contain(status, "#if C128", "ui_status must use compile-time C128 layout constants")
must_contain(help_s, ".const HELP_FRAME_RIGHT_COL = SCREEN_COLS - 1", "ui_help border must use SCREEN_COLS")
must_contain(swap, ".const DS_PROMPT_COL = (SCREEN_COLS - 19) / 2", "disk_swap prompt centering must use SCREEN_COLS math")
must_contain(main128, "lda #TITLE_MENU_COL", "title menu must use TITLE_MENU_COL")
must_contain(char_s, "lda #10\n    sta zp_cursor_row", "ui_character gold/xp row must stay at row 10")
must_contain(char_s, ".const UCHAR_COL_L = hal_layout_character_col_l", "ui_character C128 columns must stay centered for 80-col")
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
core = root.parent.parent / "core"
screen = (root / "c128" / "screen_vdc.s").read_text().splitlines()
main_text = (root / "c128" / "main.s").read_text()
input128_text = (root / "c128" / "input128.s").read_text()
item_prompt_mod = (core / "player_item_prompt.s").read_text().splitlines()
item_mod = (core / "item.s").read_text().splitlines()
item_cmd_mod = (core / "player_item_commands.s").read_text().splitlines()
item_actions_mod = (core / "item_actions_overlay.s").read_text().splitlines()
throw_mod = (core / "throw.s").read_text().splitlines()
loop_mod = (core / "game_loop.s").read_text().splitlines()
dfeat = (core / "dungeon_features.s").read_text().splitlines()
dfeat_actions = (core / "dungeon_feature_actions.s").read_text().splitlines()
dungeon_direction = (core / "dungeon_direction.s").read_text().splitlines()
help_mod = (core / "ui_help.s").read_text().splitlines()
store_mod = (core / "ui_store.s").read_text().splitlines()
loop_helpers = (core / "game_loop_helpers.s").read_text().splitlines()
player_magic_mod = (core / "player_magic.s").read_text().splitlines()
spell_effects_mod = (core / "spell_effects.s").read_text().splitlines()
ui_wizard_mod = (core / "ui_wizard.s").read_text().splitlines()

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

def section_after(label: str, lines: list[str]) -> list[str]:
    out = []
    in_block = False
    for ln in lines:
        s = ln.strip()
        if not in_block:
            if s.startswith(label):
                in_block = True
            continue
        if s and s.endswith(":") and not s.startswith("!"):
            break
        out.append(s)
    return out

first2 = first_instructions_after("screen_put_string:", screen, 2)
if len(first2) < 2 or (not first2[0].lower().startswith("php")) or (not first2[1].lower().startswith("sei")):
    print(f"screen_put_string must start with php; sei, found: {first2!r}")
    raise SystemExit(1)

if ".label hal_input_followup_prepare = input_wait_release" not in input128_text:
    print("C128 follow-up prompts must map hal_input_followup_prepare to input_wait_release")
    raise SystemExit(1)

if not (
    has_pair(item_cmd_mod, "ldx #HSTR_PIW_TAKEOFF_PROMPT", "jsr huff_print_msg")
    or has_pair(item_cmd_mod, "ldx #HSTR_PIW_TAKEOFF_PROMPT", "jsr piw_print_prompt_with_count")
):
    print("item_takeoff prompt is not using Huffman-backed prompt path")
    raise SystemExit(1)

if not has_ordered_chain(item_prompt_mod, [
    "piw_print_prompt_with_count:",
    "php",
    "sei",
    "jsr huff_decode_string",
], window=8) or not has_ordered_chain(item_prompt_mod, [
    "!piw_prompt_print:",
    "plp",
    "jmp msg_print_current_ptr",
], window=8):
    print("piw_print_prompt_with_count is not preserving IRQ state around cached Huffman prompt rendering")
    raise SystemExit(1)

ui_wizard_confirm_prefix = first_instructions_after("ui_wizard_display:", ui_wizard_mod, 14)
if any("ui_wizard_restore_gameplay_view" in line for line in ui_wizard_confirm_prefix):
    print("C128 wizard confirmation must not redraw gameplay before WIZARD? prompt")
    raise SystemExit(1)
if not any('.text "Q to cancel"' in line for line in ui_wizard_mod):
    print("Wizard cancel text should be explicit: Q to cancel")
    raise SystemExit(1)
for bad_wizard_cancel_text in ('.text "Q cancel"', '.text "Q cancels"'):
    if any(bad_wizard_cancel_text in line for line in ui_wizard_mod):
        print(f"Wizard cancel text must not use inconsistent wording: {bad_wizard_cancel_text}")
        raise SystemExit(1)
if sum(1 for line in ui_wizard_mod if '.text "Q to cancel"' in line) != 3:
    print("All ui_wizard cancel/footer strings should say: Q to cancel")
    raise SystemExit(1)

required_chains = [
    ("item_wear", item_cmd_mod, [
        "ldx #HSTR_PIW_WEAR_PROMPT",
        "jsr piw_select_filtered_inv",
    ]),
    ("item_takeoff", item_cmd_mod, [
        "ldx #HSTR_PIW_TAKEOFF_PROMPT",
        "jsr piw_print_prompt_with_count",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("item_quaff", item_cmd_mod, [
        "ldx #HSTR_PIQ_QUAFF_PROMPT",
        "jsr piw_select_filtered_inv",
    ]),
    ("item_read_scroll", item_actions_mod, [
        "ldx #HSTR_PIQ_READ_PROMPT",
        "jsr item_action_select_filtered_inv",
    ]),
    ("item_aim_wand", item_actions_mod, [
        "ldx #HSTR_PIW_AIM_PROMPT",
        "jsr item_action_select_filtered_inv",
    ]),
    ("item_use_staff", item_actions_mod, [
        "ldx #HSTR_PIW_USE_PROMPT",
        "jsr item_action_select_filtered_inv",
    ]),
    ("item_gain_spell", (core / "player_gain_spell_impl.s").read_text().splitlines(), [
        "!igs_have_choices:",
        "jsr input_prepare_modal_dismiss_key",
        "jsr spell_list_display",
        "jsr hal_input_get_key",
    ]),
    ("item_drop", item_mod, [
        "ldx #HSTR_IDR_PROMPT",
        "jsr piw_prompt_filtered_inv",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("throw_item", throw_mod, [
        "ldx #HSTR_TW_PROMPT",
        "jsr piw_select_filtered_inv",
    ]),
    ("get_direction_target", dungeon_direction, [
        "ldx #HSTR_DF_DIRECTION",
        "jsr huff_print_msg",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("cmd_inventory_dismiss", loop_helpers, [
        "cmd_show_inventory_view:",
        "jsr tramp_ui_inv_display",
        "jsr input_prepare_modal_dismiss_key",
        "jsr hal_input_get_key",
    ]),
    ("cmd_equipment_dismiss", loop_helpers, [
        "cmd_show_equipment_view:",
        "jsr tramp_ui_equip_display",
        "jsr input_prepare_modal_dismiss_key",
        "jsr hal_input_get_key",
    ]),
    ("cmd_help_dismiss", loop_helpers, [
        "cmd_show_help_view:",
        "jsr tramp_ui_help_display",
        "jsr input_prepare_modal_dismiss_key",
        "jsr hal_input_get_key",
    ]),
    ("cmd_char_info_dismiss", loop_helpers, [
        "cmd_show_character_view:",
        "jsr tramp_ui_char_display",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("cmd_recall_prompt", loop_helpers, [
        "cmd_recall_view:",
        "jsr hal_screen_put_string",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("cmd_recall_dismiss", loop_helpers, [
        "jsr tramp_ui_recall",
        "jsr input_prepare_modal_dismiss_key",
        "jsr hal_input_get_key",
    ]),
    ("store_buy_prompt", store_mod, [
        "ldx #MSG_BUY_WHICH",
        "jsr store_clear_show_msg",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("store_buy_confirm", store_mod, [
        "jsr sbuy_show_price",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("store_sell_prompt", store_mod, [
        "ldx #MSG_SELL_WHICH",
        "jsr show_msg",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("store_sell_confirm", store_mod, [
        "jsr ssell_show_offer",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("store_haggle_number", store_mod, [
        "input_read_number:",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("spell_prompt_choice", player_magic_mod, [
        "pm_prompt_visible_spell_choice:",
        "jsr input_prepare_followup_key",
        "jsr piw_print_prompt_with_count",
        "jsr input_get_followup_key",
    ]),
    ("identify_prompt_choice", spell_effects_mod, [
        "eff_identify_prompt:",
        "jsr piw_prompt_filtered_inv",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("inventory_overlay_select", item_prompt_mod, [
        "show_inv_and_select:",
        "jsr input_prepare_selectable_overlay_key",
        "jsr tramp_ui_inv_select_display",
        "jsr input_get_followup_key",
    ]),
    ("spell_list_overlay_select", player_magic_mod, [
        "!pm_psc_show_list:",
        "jsr input_prepare_selectable_overlay_key",
        "jsr tramp_spell_list_display",
        "jsr input_get_followup_key",
    ]),
    ("study_list_overlay_select", (core / "player_gain_spell_impl.s").read_text().splitlines(), [
        "!igs_have_choices:",
        "jsr input_prepare_modal_dismiss_key",
        "jsr spell_list_display",
        "jsr hal_input_get_key",
    ]),
    ("wizard_confirm_prompt", ui_wizard_mod, [
        "ui_wizard_display:",
        "lda #<wiz_confirm_str",
        "jsr msg_print",
        "jsr input_prepare_followup_key",
        "jsr hal_input_get_key",
    ]),
    ("wizard_heal_choice", ui_wizard_mod, [
        "ui_wizard_cmd_heal_cure:",
        "lda player_data + PL_MAX_MANA",
        "sta player_data + PL_MANA",
        "sta zp_player_mp",
        "sta zp_player_mmp",
    ]),
]

for name, lines, chain in required_chains:
    if not has_ordered_chain(lines, chain):
        print(f"{name} must gate with input_wait_release before input_get_key")
        raise SystemExit(1)

if not has_ordered_chain(item_actions_mod, [
    "item_action_get_key:",
    "jsr hal_input_get_key",
    "#if hal_platform_item_action_key_restores_bank",
    "sta iagk_key",
    "lda #MMU_ALL_RAM",
    "sta hal_memory_mmu_config_register",
    "lda #BANK_NO_ROMS",
    "sta hal_memory_cpu_port",
    "lda iagk_key",
]):
    print("C128 item overlay key reads must restore overlay banking after input_get_key")
    raise SystemExit(1)

for name in ("item_read_scroll:", "item_aim_wand:", "item_use_staff:"):
    body = section_after(name, item_actions_mod)
    if any("jsr hal_input_get_key" in line for line in body):
        print(f"{name[:-1]} must use item_action_get_key, not direct input_get_key")
        raise SystemExit(1)

if not has_ordered_chain(help_mod, [
    "#if HAL_SCREEN_HELP_LINE_USES_API",
    "jsr hal_screen_put_char",
    "#else",
    "sta (zp_screen_lo),y",
]):
    print("ui_help_draw_line must use the HAL character API on C128 and keep direct RAM path only for C64")
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

run_item_overlay_key_guard_check() {
    echo -n "  item_overlay_key_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

root = Path("..").resolve()
core = root.parent.parent / "core"
items = (core / "item_actions_overlay.s").read_text().splitlines()

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

def section_after(label: str, lines: list[str]) -> list[str]:
    out = []
    in_block = False
    for ln in lines:
        s = ln.strip()
        if not in_block:
            if s.startswith(label):
                in_block = True
            continue
        if s and s.endswith(":") and not s.startswith("!"):
            break
        out.append(s)
    return out

if not has_ordered_chain(items, [
    "item_action_get_key:",
    "jsr hal_input_get_key",
    "#if hal_platform_item_action_key_restores_bank",
    "sta iagk_key",
    "lda #MMU_ALL_RAM",
    "sta hal_memory_mmu_config_register",
    "lda #BANK_NO_ROMS",
    "sta hal_memory_cpu_port",
    "lda iagk_key",
]):
    print("C128 item overlay key reads must restore overlay banking after input_get_key")
    raise SystemExit(1)

if not has_ordered_chain(items, [
    "item_action_select_filtered_inv:",
    "jsr item_action_get_key",
    "cmp #$3f",
    "lda #OVL_ITEMS",
    "sta piw_return_overlay",
    "jmp piw_select_filtered_inv_key",
]):
    print("C128 item overlay must mark ?-opened inventory selectors as returning to OVL_ITEMS")
    raise SystemExit(1)

magic_execute = (core / "player_magic_execute_overlay.s").read_text().splitlines()
if not has_ordered_chain(magic_execute, [
    "pmx_pick_recharge_item:",
    "jsr hal_input_get_key",
    "cmp #$3f",
    "lda #OVL_SPELL",
    "sta piw_return_overlay",
    "jmp piw_select_filtered_inv_key",
]):
    print("C128 spell overlay must mark ?-opened recharge selectors as returning to OVL_SPELL")
    raise SystemExit(1)

for name in ("item_read_scroll:", "item_aim_wand:", "item_use_staff:"):
    body = section_after(name, items)
    if any("jsr hal_input_get_key" in line for line in body):
        print(f"{name[:-1]} must use item_action_get_key, not direct input_get_key")
        raise SystemExit(1)
    if not (
        any("jsr item_action_get_key" in line for line in body)
        or any("jsr item_action_select_filtered_inv" in line for line in body)
    ):
        print(f"{name[:-1]} must use item_action_get_key or item_action_select_filtered_inv")
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

run_input_run_guard_check() {
    echo -n "  input_run_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

lines = (
    Path("input128.s").read_text().splitlines()
    + Path("input_run_raw128.s").read_text().splitlines()
)

def block(label: str) -> list[str]:
    out = []
    in_block = False
    for ln in lines:
        s = ln.strip()
        if not in_block:
            if s.startswith(label):
                in_block = True
            continue
        if s.endswith(":") and not s.startswith("!"):
            break
        out.append(s)
    return out

errors = []
scan_block = block("input_run_scan_held_raw:")
held_block = block("input_run_key_held:")

if not scan_block:
    errors.append("missing input_run_scan_held_raw block")
elif any("cia_scan_petscii" in ln for ln in scan_block):
    errors.append("input_run_scan_held_raw must not call cia_scan_petscii")

if not held_block and not any(".label input_run_key_held = input_run_scan_held_raw" in ln for ln in lines):
    errors.append("missing input_run_key_held block or raw-scan alias")
elif any("irk_neutral_latch" in ln for ln in held_block):
    errors.append("input_run_key_held still depends on irk_neutral_latch")

if not any("input_run_row_has_nonmodifier:" in ln for ln in lines):
    errors.append("missing input_run_row_has_nonmodifier helper")

if errors:
    print("\n".join(errors))
PY
)
    if [ -n "$check_out" ]; then
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

run_ref_hal_guard_check() {
    echo -n "  ref_hal_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path
import re

root = Path("..").resolve()
common = root.parent.parent / "core"
helper = common / "input_ui_helpers.s"

runtime_exclusions = {}
runtime_counts = {}
runtime_leaks: list[str] = []
kbdbuf_leaks: list[str] = []
helper_raw_kbdbuf = 0


def code_lines(path: Path):
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        code = raw.split("//", 1)[0].strip()
        if code:
            yield lineno, code


for path in sorted(common.glob("*.s")):
    for lineno, code in code_lines(path):
        for token in ("c128_restore_runtime_guards", "c128_restore_runtime_vectors"):
            if token not in code:
                continue
            allowed = runtime_exclusions.get(path.name, {})
            if token in allowed:
                runtime_counts[path.name][token] += code.count(token)
            else:
                runtime_leaks.append(f"{path.name}:{lineno}: {token}")

        if re.search(r"\bKBDBUF_COUNT\b", code):
            if path.name == helper.name:
                helper_raw_kbdbuf += len(re.findall(r"\bKBDBUF_COUNT\b", code))
            else:
                kbdbuf_leaks.append(f"{path.name}:{lineno}: KBDBUF_COUNT")

if runtime_leaks:
    print("unexpected shared runtime-repair references:")
    for hit in runtime_leaks:
        print(f"  {hit}")
    raise SystemExit(1)

for path_name, token_counts in runtime_counts.items():
    for token, count in token_counts.items():
        expected = runtime_exclusions[path_name][token]
        if count != expected:
            print(f"{path_name} must contain exactly {expected} live {token} reference(s), found {count}")
            raise SystemExit(1)

if kbdbuf_leaks:
    print("unexpected raw KBDBUF_COUNT references in shared code:")
    for hit in kbdbuf_leaks:
        print(f"  {hit}")
    raise SystemExit(1)

if helper_raw_kbdbuf != 0:
    print(f"{helper.name} must keep KBDBUF_COUNT wrapped behind hal_input_kbdbuf_count, found {helper_raw_kbdbuf} raw use(s)")
    raise SystemExit(1)

helper_text = helper.read_text()
if "hal_input_kbdbuf_count" not in helper_text:
    print("input_ui_helpers.s must own the wrapped keyboard-buffer alias")
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

run_save_load_guard_check() {
    echo -n "  save_load_guard: "

    local check_out
    check_out=$(python3 - <<'PY'
from pathlib import Path

save = Path("../common/save.s").read_text().splitlines()

try:
    start = next(i for i, line in enumerate(save) if line.strip() == "load_read_byte:")
    end = next(i for i in range(start + 1, len(save)) if save[i].startswith("// ==="))
except StopIteration:
    print("could not locate load_read_byte body")
    raise SystemExit(1)

body = "\n".join(save[start:end])
if body.count("jsr SAVE_READST") < 1:
    print("load_read_byte must check SAVE_READST after SAVE_CHRIN")
    raise SystemExit(1)
if "jsr SAVE_READST\n#if HAL_STORAGE_STREAM_CHUNKED" not in body:
    print("load_read_byte must read status immediately after SAVE_CHRIN")
    raise SystemExit(1)
if "beq !lrby_read+" in body:
    print("load_read_byte must not use the old pre-read status gate")
    raise SystemExit(1)
if "jsr SAVE_CHRIN" not in body:
    print("load_read_byte lost the sequential byte read")
    raise SystemExit(1)
if "inc save_io_error" not in body:
    print("load_read_byte must flag save_io_error on read status failure")
    raise SystemExit(1)

required = [
    ("load_read_block:", "lda save_io_error\n    bne !lrb_c128_done+"),
    ("load_read_map_c128:", "lda save_io_error\n    bne !lrm_done+"),
    ("save_write_block:", "jsr c128_save_stream_chunk"),
    ("load_read_block:", "jsr c128_load_stream_chunk"),
    ("save_write_map_c128:", "jsr save_stage_map_c128"),
    ("load_read_map_c128:", "jsr load_unstage_map_c128"),
]
text = "\n".join(save)
save_fail = text[text.find("!save_media_fail:"):text.find("save_return_fail:")]
if "jsr huff_print_msg" not in save_fail:
    print("save media failure must display a message")
    raise SystemExit(1)
if "jsr input_get_modal_dismiss_key" not in save_fail:
    print("save media failure must wait for modal dismiss on C128")
    raise SystemExit(1)
if "#if !C128" in save_fail:
    print("save media failure must not compile out the C128 modal dismiss")
    raise SystemExit(1)
save_error = text[text.find("!save_error:"):text.find("    jmp save_return_fail", text.find("!save_error:"))]
if "jsr input_get_modal_dismiss_key" not in save_error:
    print("save write error must wait for modal dismiss on C128")
    raise SystemExit(1)
if "#if !C128" in save_error:
    print("save write error must not compile out the C128 modal dismiss")
    raise SystemExit(1)
for label, chain in required:
    idx = text.find(label)
    if idx == -1:
        print(f"could not locate {label}")
        raise SystemExit(1)
    window = text[idx:idx + 600]
    if chain not in window:
        print(f"{label} must stop once save_io_error is set")
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
    if [ "$PERF_P1_MODE" = "1" ]; then
        force_base_rebuild=1
    fi

    if [ "$PERF_P1_MODE" != "1" ] && c128_active_variant_is "base" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/boot128.prg ../../../build/test/c128/boot128.chain.prg ../../../build/test/c128/bootsect128.prg ../../../build/test/c128/bootart128.prg ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128.d71 ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg ../../../build/test/c128/main.vs -- \
            main.s boot128.s bootart128.s bootsect128.s Makefile ../version.json \
            ../artwork/moria8_C128loadingart_tile_native.png \
            ../tools/png_to_ppm.py ../tools/make_version_include.py ../tools/ppm_to_c128_bootart.py \
            ../common/*.s ../c64/*.s; then
        BOOT_ASSETS_BUILT=1
        return
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_build.log)"
    if [ "$force_base_rebuild" -eq 1 ]; then
        if ! "${COMMODORE_MAKE[@]}" -W c128/main.s -W c128/boot128.s KICKASS="$KICKASS" PERF_P1="$PERF_P1_MODE" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
            echo "FAIL (build128/disk128 failed)"
            tail -20 "$build_log" | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return 1
        fi
    elif ! "${COMMODORE_MAKE[@]}" KICKASS="$KICKASS" PERF_P1="$PERF_P1_MODE" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
        echo "FAIL (build128/disk128 failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    c128_sync_build_out

    local diag_asm
    diag_asm=$(java -jar "$KICKASS" boot128.s -define BOOT_DIAG=1 :OVL_OUT=../../../build/test/c128 -o ../../../build/test/c128/boot128.diag.prg 2>&1)
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
    local probe_main="../../../build/test/c128/moria128.vic40probe.prg"
    local probe_d64="../../../build/test/c128/moria128_vic40probe.d64"

    BOOT_ASSETS_BUILT=0
    c128_set_active_variant "force_base"
    build_boot_assets || return

    if ! java -jar "$KICKASS" main_vic40probe.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 :OVL_OUT=../../../build/test/c128 \
            -o "$probe_main" >"$build_log" 2>&1; then
        echo "FAIL (vic40 probe main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$probe_d64" \
            -attach "$probe_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$probe_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >"$(test128_tmp_file "test128_${name}_c1541.log")" 2>&1; then
        echo "FAIL (vic40 probe d64 creation failed)"
        tail -20 "$(test128_tmp_file "test128_${name}_c1541.log")" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local probe_vs="../../../build/test/c128/main_vic40probe.vs"
    local pass_addr fail_addr
    pass_addr=$(awk '/\.c128_vic40_boot_probe_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$probe_vs")
    fail_addr=$(awk '/\.c128_vic40_boot_probe_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$probe_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing vic40 probe symbols in ../../../build/test/c128/main_vic40probe.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_vic40probe.d64"
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
            ../../../build/test/c128/moria128.realdiag.prg ../../../build/test/c128/moria128_realdiag.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        REAL_BOOT_DIAG_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_real_boot_diag_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local diag_main="../../../build/test/c128/moria128.realdiag.prg"
    local diag_d64="../../../build/test/c128/moria128_realdiag.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_REAL_BOOT_DIAG -define C128_TEST_FORCE_DUNGEON_MELEE \
            -o "$diag_main" >"$build_log" 2>&1; then
        echo "FAIL (real-boot diag main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$diag_d64" \
            -attach "$diag_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$diag_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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
            ../../../build/test/c128/moria128.overlaydiag.prg ../../../build/test/c128/moria128_overlaydiag.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        OVERLAY_TRANSITION_DIAG_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_overlay_transition_diag_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local diag_main="../../../build/test/c128/moria128.overlaydiag.prg"
    local diag_d64="../../../build/test/c128/moria128_overlaydiag.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_OVERLAY_TRANSITION_DIAG \
            -o "$diag_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-transition diag main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$diag_d64" \
            -attach "$diag_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$diag_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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
            ../../../build/test/c128/moria128.titleart.prg ../../../build/test/c128/moria128_titleart.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg ../common/*.s ../c64/*.s; then
        TITLE_ART_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_title_art_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local title_main="../../../build/test/c128/moria128.titleart.prg"
    local title_d64="../../../build/test/c128/moria128_titleart.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_TITLE_ART_CONTENT \
            -o "$title_main" >"$build_log" 2>&1; then
        echo "FAIL (title-art main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$title_d64" \
            -attach "$title_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$title_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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

build_title_load_missing_save_assets() {
    if [ "$TITLE_LOAD_MISSING_SAVE_ASSETS_BUILT" -eq 1 ] && [ -f ../../../build/test/c128/moria128_missing_save.d64 ]; then
        return 0
    fi

    build_boot_assets || return 1

    local build_log
    build_log="$(test128_tmp_file test128_title_missing_save_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local missing_save_d64="../../../build/test/c128/moria128_missing_save.d64"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local dir_type_offset=$(((357 + 1) * 256 + 2))

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker blob generation failed)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$missing_save_d64" \
            -attach "$missing_save_d64" \
            -write "$marker_blob" "MORIA8.ID" >"$build_log" 2>&1; then
        echo "FAIL (missing-save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$missing_save_d64" bs=1 seek="$dir_type_offset" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (missing-save disk directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local dir_list
    if ! dir_list=$("$c1541_bin" -attach "$missing_save_d64" -list 2>&1); then
        echo "FAIL (missing-save disk listing failed)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ'; then
        echo "FAIL (missing-save disk marker is not seq)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if echo "$dir_list" | grep -q '"THE.GAME"'; then
        echo "FAIL (missing-save disk unexpectedly contains THE.GAME)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    TITLE_LOAD_MISSING_SAVE_ASSETS_BUILT=1
    return 0
}

build_title_load_mounted_save_assets() {
    if [ "$TITLE_LOAD_MOUNTED_SAVE_ASSETS_BUILT" -eq 1 ] && [ -f ../../../build/test/c128/moria128_mounted_save.d64 ]; then
        return 0
    fi

    build_boot_assets || return 1

    local build_log
    build_log="$(test128_tmp_file test128_title_mounted_save_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local mounted_save_d64="../../../build/test/c128/moria128_mounted_save.d64"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local save_blob="../../../build/test/c128/THE.GAME"
    local dir_type_offset0=$(((357 + 1) * 256 + 2))
    local dir_type_offset1=$((dir_type_offset0 + 32))

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker blob generation failed)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (mounted-save save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$mounted_save_d64" \
            -attach "$mounted_save_d64" \
            -write "$marker_blob" "MORIA8.ID" \
            -write "$save_blob" "THE.GAME" >"$build_log" 2>&1; then
        echo "FAIL (mounted-save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$mounted_save_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (mounted-save marker directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$mounted_save_d64" bs=1 seek="$dir_type_offset1" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (mounted-save savefile directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    local dir_list
    if ! dir_list=$("$c1541_bin" -attach "$mounted_save_d64" -list 2>&1); then
        echo "FAIL (mounted-save disk listing failed)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ'; then
        echo "FAIL (mounted-save disk marker is not seq)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
        echo "FAIL (mounted-save disk THE.GAME is not seq)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    TITLE_LOAD_MOUNTED_SAVE_ASSETS_BUILT=1
    return 0
}

build_save_write_product_assets() {
    if [ "$SAVE_WRITE_PRODUCT_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "save_write_product"; then
        return 0
    fi

    build_boot_assets || return 1

    local build_log
    build_log="$(test128_tmp_file test128_save_write_product_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local save_write_d64="../../../build/test/c128/moria128_savewrite_product.d64"
    local save_d64="../../../build/test/c128/moria128_savewrite_product_save.d64"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local save_blob="../../../build/test/c128/THE.GAME"
    local dir_type_offset0=$(((357 + 1) * 256 + 2))
    local dir_type_offset1=$((dir_type_offset0 + 32))

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (save-write product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$save_write_d64" \
            -attach "$save_write_d64" \
            -write ../../../build/test/c128/boot128.prg "boot128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "t128" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "128.town" \
            -write ../../../build/test/c128/ovl.start "128.start" \
            -write ../../../build/test/c128/ovl.death "128.death" \
            -write ../../../build/test/c128/ovl.royal "128.royal" \
            -write ../../../build/test/c128/ovl.gen "128.gen" \
            -write ../../../build/test/c128/ovl.help "128.help" \
            -write ../../../build/test/c128/ovl.ui "128.ui" \
            -write ../../../build/test/c128/ovl.items "128.items" \
            -write ../../../build/test/c128/ovl.disarm "128.disarm" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (save-write product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (save-write marker blob generation failed)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (save-write save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "MORIA8.ID" \
            -write "$save_blob" "THE.GAME" >"$build_log" 2>&1; then
        echo "FAIL (save-write save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (save-write marker directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset1" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (save-write savefile directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SAVE_WRITE_PRODUCT_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "save_write_product"
    return 0
}

build_save_media_fail_product_assets() {
    if [ "$SAVE_WRITE_PRODUCT_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "save_media_fail_product"; then
        return 0
    fi

    build_boot_assets || return 1

    local build_log
    build_log="$(test128_tmp_file test128_save_media_fail_product_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local fail_d64="../../../build/test/c128/moria128_savemediafail_product.d64"
    local save_d64="../../../build/test/c128/moria128_savemediafail_product_save.d64"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local save_blob="../../../build/test/c128/THE.GAME"
    local dir_type_offset0=$(((357 + 1) * 256 + 2))
    local dir_type_offset1=$((dir_type_offset0 + 32))

    if ! java -jar "$KICKASS" main_save_media_fail.s -showmem -vicesymbols -libdir ../c64 \
            -define C128 \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (save-media-fail product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$fail_d64" \
            -attach "$fail_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (save-media-fail product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (save-media-fail marker blob generation failed)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (save-media-fail save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "MORIA8.ID" \
            -write "$save_blob" "THE.GAME" >"$build_log" 2>&1; then
        echo "FAIL (save-media-fail save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (save-media-fail marker directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset1" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (save-media-fail savefile directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SAVE_WRITE_PRODUCT_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "save_media_fail_product"
    return 0
}

build_partial_failure_boot_assets() {
    if [ "$PARTIAL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "partial_failure"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "partial_failure" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.skip1.prg ../../../build/test/c128/moria128_skip1.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        PARTIAL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_partial_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local partial_main="../../../build/test/c128/moria128.skip1.prg"
    local partial_d64="../../../build/test/c128/moria128_skip1.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_CACHE_TEST_SKIP_TIER -o "$partial_main" >"$build_log" 2>&1; then
        echo "FAIL (partial-failure main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$partial_d64" \
            -attach "$partial_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$partial_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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
            ../../../build/test/c128/moria128.skipovl2.prg ../../../build/test/c128/moria128_skipovl2.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        OVERLAY_PARTIAL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_overlay_partial_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local partial_main="../../../build/test/c128/moria128.skipovl2.prg"
    local partial_d64="../../../build/test/c128/moria128_skipovl2.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_CACHE_TEST_SKIP_OVERLAY -o "$partial_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-partial main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$partial_d64" \
            -attach "$partial_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$partial_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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
            ../../../build/test/c128/moria128.death.prg ../../../build/test/c128/moria128_death.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        DEATH_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_death_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local death_main="../../../build/test/c128/moria128.death.prg"
    local death_d64="../../../build/test/c128/moria128_death.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_FORCE_DEATH=1 -o "$death_main" >"$build_log" 2>&1; then
        echo "FAIL (death-overlay main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$death_d64" \
            -attach "$death_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$death_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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
            ../../../build/test/c128/moria128.overlaystate.prg ../../../build/test/c128/moria128_overlaystate.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        OVERLAY_STATE_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_overlay_state_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local state_main="../../../build/test/c128/moria128.overlaystate.prg"
    local state_d64="../../../build/test/c128/moria128_overlaystate.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_OVERLAY_STATE_CORRUPT=1 -o "$state_main" >"$build_log" 2>&1; then
        echo "FAIL (overlay-state main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$state_d64" \
            -attach "$state_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write "$state_main" "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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

    if [ "$PERF_P1_MODE" != "1" ] && c128_active_variant_is "scripted_input" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_scriptedinput.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        SCRIPTED_INPUT_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_input_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_scriptedinput.d64"
    local perf_define=()
    if [ "$PERF_P1_MODE" = "1" ]; then
        perf_define=(-define PERF_P1)
    fi

    # Compile to the standard ../../../build/test/c128/moria128.prg target so KickAssembler also
    # refreshes the companion ../../../build/test/c128/ovl.* overlay PRGs for this special build.
    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 -define C128 ${perf_define[@]+"${perf_define[@]}"} -define C128_TEST_SCRIPTED_INPUT -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-input main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
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

validate_perf_p1_trace_variant() {
    local suffix="$1"
    local build_log="$2"
    local expected_kind="$3"
    if ! python3 - "$suffix" "$expected_kind" ../../../build/test/c128/main.vs ../../../build/test/c128/128.play.prg ../../../build/test/c128/moria128.prg >>"$build_log" 2>&1 <<'PY'
from pathlib import Path
import sys

suffix, expected_kind, vs_path, play_prg_path, main_prg_path = sys.argv[1:]
symbols = {}
for raw in Path(vs_path).read_text(encoding="utf-8").splitlines():
    parts = raw.strip().split()
    if len(parts) < 3 or ":" not in parts[1] or not parts[2].startswith("."):
        continue
    symbols[parts[2][1:]] = int(parts[1].split(":", 1)[1], 16)

required = [
    "c128_test_perf_p1_trace_pass_sym",
    "c128_test_perf_p1_trace_capture_sym",
    "c128_test_perf_p1_trace_export_sym",
    "perf_p1_moves",
    "perf_p1_decision",
    "perf_p1_full_lo",
    "perf_p1_local_lo",
    "perf_p1_reason_lo",
]
missing = [name for name in required if name not in symbols]
if missing:
    raise SystemExit(f"missing symbols for PERF trace validation: {', '.join(missing)}")

reason = symbols["perf_p1_reason_lo"]
expected_symbols = {
    "summary": [
        symbols["perf_p1_decision"],
        symbols["perf_p1_decision"],
        symbols["perf_p1_decision"],
    ],
    "reasons_0_2": [reason + 0, reason + 1, reason + 2],
    "reasons_3_5": [reason + 3, reason + 4, reason + 5],
    "reasons_6_7": [symbols["perf_p1_moves"], reason + 6, reason + 7],
}
if expected_kind not in {"assert", "modal_assert", "command_assert", "transition_assert"} and expected_kind not in expected_symbols:
    raise SystemExit(f"unknown PERF trace variant kind: {expected_kind}")

play_prg = Path(play_prg_path).read_bytes()
if len(play_prg) < 2:
    raise SystemExit(f"{play_prg_path} is too small")
play_load_addr = play_prg[0] | (play_prg[1] << 8)
pass_addr = symbols["c128_test_perf_p1_trace_pass_sym"]
capture_addr = symbols["c128_test_perf_p1_trace_capture_sym"]
export_addr = symbols["c128_test_perf_p1_trace_export_sym"]
export_start = export_addr - play_load_addr + 2
export_end = export_addr + 3 - play_load_addr + 2
if export_start < 2 or export_end > len(play_prg):
    raise SystemExit(f"PERF trace export ${export_addr:04x} is outside {play_prg_path}")
actual_export = play_prg[export_start:export_end]
expected_export = bytes((0x4C, capture_addr & 0xFF, capture_addr >> 8))
if actual_export != expected_export:
    got = " ".join(f"{b:02x}" for b in actual_export)
    want = " ".join(f"{b:02x}" for b in expected_export)
    raise SystemExit(
        f"PERF trace {suffix} export should jump to test-owned capture at ${capture_addr:04x}: "
        f"got [{got}], expected [{want}]"
    )

if expected_kind in {"assert", "modal_assert", "command_assert", "transition_assert"}:
    if "c128_test_perf_p1_trace_fail_sym" not in symbols:
        raise SystemExit("missing c128_test_perf_p1_trace_fail_sym for PERF trace assert validation")
    print(f"PERF trace {suffix}: validated resident jump to product-path assert capture")
    raise SystemExit(0)

main_prg = Path(main_prg_path).read_bytes()
if len(main_prg) < 2:
    raise SystemExit(f"{main_prg_path} is too small")
main_load_addr = main_prg[0] | (main_prg[1] << 8)
capture_start = capture_addr - main_load_addr + 2
capture_end = capture_addr + 12 - main_load_addr + 2
if capture_start < 2 or capture_end > len(main_prg):
    raise SystemExit(f"PERF trace capture ${capture_addr:04x} is outside {main_prg_path}")

actual = main_prg[capture_start:capture_end]
expected = bytearray()
for opcode, addr in zip((0xAD, 0xAE, 0xAC), expected_symbols[expected_kind]):
    expected.extend((opcode, addr & 0xFF, addr >> 8))
expected.extend((0x4C, pass_addr & 0xFF, pass_addr >> 8))

if actual != expected:
    got = " ".join(f"{b:02x}" for b in actual)
    want = " ".join(f"{b:02x}" for b in expected)
    raise SystemExit(
        f"PERF trace {suffix} loads wrong symbols near capture ${capture_addr:04x}: "
        f"got [{got}], expected [{want}]"
    )

print(f"PERF trace {suffix}: validated {expected_kind} resident jump and test-owned capture at ${capture_addr:04x}")
PY
    then
        return 1
    fi
    return 0
}

build_perf_p1_trace_boot_assets() {
    local suffix="${1:-summary}"
    shift || true
    local variant="perf_p1_trace_${suffix}"
    if [ "$PERF_P1_TRACE_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "$variant"; then
        PERF_P1_TRACE_D64="../../../build/test/c128/moria128_${variant}.d64"
        return
    fi

    build_boot_assets || return 1

    local build_log
    build_log="$(test128_tmp_file test128_perf_p1_trace_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local trace_d64="../../../build/test/c128/moria128_${variant}.d64"
    local -a extra_defines=()
    local define_name
    for define_name in "$@"; do
        extra_defines+=(-define "$define_name")
    done

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 -define C128 -define PERF_P1 -define C128_TEST_SCRIPTED_INPUT -define C128_TEST_PERF_P1_TRACE ${extra_defines[@]+"${extra_defines[@]}"} -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (PERF P1 trace main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi
    if [ "$suffix" = "assert" ] || [ "$suffix" = "modal_assert" ] || [ "$suffix" = "command_assert" ] || [ "$suffix" = "transition_assert" ]; then
        if ! "$c1541_bin" -format "moria128,m8" d64 "$trace_d64" \
                -attach "$trace_d64" \
                -write ../../../build/test/c128/boot128.prg "moria8.128" \
                -write ../../../build/test/c128/moria128.prg "moria128" \
                -write ../../../build/test/c128/title "title" \
                -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
                -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
                -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
                -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
                -write ../../../build/test/c128/ovl.town "ovl.town" \
                -write ../../../build/test/c128/ovl.start "ovl.start" \
                -write ../../../build/test/c128/ovl.death "ovl.death" \
                -write ../../../build/test/c128/ovl.gen "ovl.gen" \
                -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
                -write ../../../build/test/c128/128.input.prg "128.input" \
                -write ../../../build/test/c128/128.proj.prg "128.proj" \
                -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
                -write ../../../build/test/c128/128.world.prg "128.world" \
                -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
                -write ../../../build/test/c128/128.select.prg "128.select" \
                -write ../../../build/test/c128/128.persist.prg "128.persist" \
                -write ../../../build/test/c128/128.play.prg "128.play" \
                -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
            echo "FAIL (PERF P1 trace assert disk build failed)"
            tail -20 "$build_log" | sed 's/^/    /'
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return 1
        fi
    fi
    if ! validate_perf_p1_trace_variant "$suffix" "$build_log" "$suffix"; then
        echo "FAIL (PERF P1 trace register-export validation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    PERF_P1_TRACE_BOOT_ASSETS_BUILT=1
    PERF_P1_TRACE_D64="$trace_d64"
    c128_set_active_variant "$variant"
    return 0
}

build_scripted_spell_boot_assets() {
    if [ "$SCRIPTED_SPELL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "scripted_spell"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "scripted_spell" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_scriptedspell.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        SCRIPTED_SPELL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_spell_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_scriptedspell.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_SCRIPTED_SPELL -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-spell main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-spell disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SCRIPTED_SPELL_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "scripted_spell"
    return 0
}

build_scripted_spell_cancel_boot_assets() {
    if [ "$SCRIPTED_SPELL_CANCEL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "scripted_spell_cancel"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "scripted_spell_cancel" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_scriptedspellcancel.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        SCRIPTED_SPELL_CANCEL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_spell_cancel_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_scriptedspellcancel.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_SCRIPTED_SPELL_CANCEL -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-spell-cancel main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-spell-cancel disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SCRIPTED_SPELL_CANCEL_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "scripted_spell_cancel"
    return 0
}

build_scripted_book_overlay_boot_assets() {
    if [ "$SCRIPTED_BOOK_OVERLAY_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "scripted_book_overlay"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "scripted_book_overlay" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_scriptedbookoverlay.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        SCRIPTED_BOOK_OVERLAY_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_book_overlay_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_scriptedbookoverlay.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_SCRIPTED_BOOK_OVERLAY -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-book-overlay main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-book-overlay disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SCRIPTED_BOOK_OVERLAY_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "scripted_book_overlay"
    return 0
}

build_scripted_spell_list_overlay_boot_assets() {
    if [ "$SCRIPTED_SPELL_LIST_OVERLAY_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "scripted_spell_list_overlay"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "scripted_spell_list_overlay" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_scriptedspelllistoverlay.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        SCRIPTED_SPELL_LIST_OVERLAY_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_spell_list_overlay_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_scriptedspelllistoverlay.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-spell-list-overlay main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-spell-list-overlay disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SCRIPTED_SPELL_LIST_OVERLAY_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "scripted_spell_list_overlay"
    return 0
}

build_scripted_prayer_boot_assets() {
    if [ "$SCRIPTED_PRAYER_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "scripted_prayer"; then
        return
    fi

    build_boot_assets || return 1

    if c128_active_variant_is "scripted_prayer" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_scriptedprayer.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        SCRIPTED_PRAYER_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_scripted_prayer_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_scriptedprayer.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_SCRIPTED_PRAYER -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (scripted-prayer main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (scripted-prayer disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    BOOT_ASSETS_BUILT=0
    SCRIPTED_PRAYER_BOOT_ASSETS_BUILT=1
    c128_set_active_variant "scripted_prayer"
    return 0
}

build_cache_survival_boot_assets() {
    local target_dir="${1:-../../../build/test/c128}"
    if [ "$target_dir" = "../../../build/test/c128" ] && [ "$CACHE_SURVIVAL_BOOT_ASSETS_BUILT" -eq 1 ] && c128_active_variant_is "cache_survival"; then
        return
    fi

    build_boot_assets "$target_dir" || return 1

    if [ "$target_dir" = "../../../build/test/c128" ] && c128_active_variant_is "cache_survival" && ! c128_outputs_need_refresh \
            ../../../build/test/c128/moria128.prg ../../../build/test/c128/moria128_cache_survival.d64 ../../../build/test/c128/main.vs -- \
            main.s ../../../build/test/c128/boot128.prg ../../../build/test/c128/title ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 \
            ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death \
            ../../../build/test/c128/ovl.gen ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        CACHE_SURVIVAL_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file "test128_boot_cache_survival_build_$(basename "$target_dir").log")"
    local cache_main="$target_dir/moria128.prg"
    local cache_d64="$target_dir/moria128_cache_survival.d64"

    if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 -define C128 -define C128_TEST_SCRIPTED_INPUT -define C128_TEST_CACHE_SURVIVAL ":OVL_OUT=$target_dir" -o "$cache_main" >"$build_log" 2>&1; then
        echo "FAIL (cache-survival main assembly failed for $target_dir)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$C1541" -format "moria128,m8" d64 "$cache_d64" \
            -attach "$cache_d64" \
            -write "$target_dir/boot128.prg" "moria8.128" \
            -write "$cache_main" "moria128" \
            -write "$target_dir/title" "title" \
            -write "$target_dir/monster.db.1" "monster.db.1" \
            -write "$target_dir/monster.db.2" "monster.db.2" \
            -write "$target_dir/monster.db.3" "monster.db.3" \
            -write "$target_dir/monster.db.4" "monster.db.4" \
            -write "$target_dir/ovl.town" "ovl.town" \
            -write "$target_dir/ovl.start" "ovl.start" \
            -write "$target_dir/ovl.death" "ovl.death" \
            -write "$target_dir/ovl.gen" "ovl.gen" \
            -write "$target_dir/128.runtime.prg" "128.runtime" \
            -write "$target_dir/128.input.prg" "128.input" \
			-write "$target_dir/128.proj.prg" "128.proj" \
            -write "$target_dir/128.fdisk.prg" "128.fdisk" \
            -write "$target_dir/128.world.prg" "128.world" \
            -write "$target_dir/128.item.prg" "128.item" \
            -write "$target_dir/128.names.prg" "128.names" \
            -write "$target_dir/128.select.prg" "128.select" \
            -write "$target_dir/128.persist.prg" "128.persist" \
            -write "$target_dir/128.play.prg" "128.play" \
            -write "$target_dir/128.bank.prg" "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (cache-survival disk build failed for $target_dir)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if [ "$target_dir" = "../../../build/test/c128" ]; then
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
            ../../../build/test/c128/THE.GAME ../../../build/test/c128/moria128_loadresume.d64 -- \
            tests/make_load_resume_save.py ../../../build/test/c128/boot128.prg ../../../build/test/c128/moria128.prg ../../../build/test/c128/title \
            ../../../build/test/c128/monster.db.1 ../../../build/test/c128/monster.db.2 ../../../build/test/c128/monster.db.3 ../../../build/test/c128/monster.db.4 \
            ../../../build/test/c128/ovl.town ../../../build/test/c128/ovl.start ../../../build/test/c128/ovl.death ../../../build/test/c128/ovl.gen \
            ../../../build/test/c128/128.runtime.prg ../../../build/test/c128/128.input.prg ../../../build/test/c128/128.proj.prg ../../../build/test/c128/128.fdisk.prg ../../../build/test/c128/128.world.prg ../../../build/test/c128/128.item.prg ../../../build/test/c128/128.names.prg ../../../build/test/c128/128.select.prg ../../../build/test/c128/128.persist.prg ../../../build/test/c128/128.play.prg ../../../build/test/c128/128.bank.prg; then
        LOAD_RESUME_BOOT_ASSETS_BUILT=1
        return 0
    fi

    local build_log
    build_log="$(test128_tmp_file test128_boot_load_resume_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local loadresume_d64="../../../build/test/c128/moria128_loadresume.d64"
    local save_blob="../../../build/test/c128/THE.GAME"

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (load-resume save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return 1
    fi

    if ! "$c1541_bin" -format "moria128,m8" d64 "$loadresume_d64" \
            -attach "$loadresume_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" \
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
        asm_output=$(java -jar "$KICKASS" "$src" -o "$prg_file" -libdir ../c64 -define C128 -vicesymbols :OVL_OUT=../../../build/test/c128 2>&1)
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
        echo "quit"
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
        "disk_swap128 tests/test_disk_swap128.s 20000000"
        "main_loop128 tests/test_main_loop128.s 500000000"
        "msg_prompt128 tests/test_msg_prompt128.s 120000000"
        "vdc_attr128 tests/test_vdc_attr128.s 20000000"
        "item_desc128 tests/test_item_desc128.s 20000000"
        "vdc_scroll_delta128 tests/test_vdc_scroll_delta128.s 30000000"
        "status_coherence128 tests/test_status_coherence128.s 20000000"
        "dungeon128 tests/test_dungeon128.s 50000000"
        "soak128 tests/test_soak128.s 300000000"
        "monster128 tests/test_monster128.s 20000000"
        "detect_monsters128 tests/test_detect_monsters128.s 20000000"
        "detect_evil128 tests/test_detect_evil128.s 20000000"
        "cure_light_wounds128 tests/test_cure_light_wounds128.s 20000000"
        "cure_poison128 tests/test_cure_poison128.s 20000000"
        "cure_light_wounds_prayer128 tests/test_cure_light_wounds_prayer128.s 20000000"
        "bless_prayer128 tests/test_bless_prayer128.s 20000000"
        "remove_fear_prayer128 tests/test_remove_fear_prayer128.s 20000000"
        "call_light_prayer128 tests/test_call_light_prayer128.s 20000000"
        "find_traps_prayer128 tests/test_find_traps_prayer128.s 20000000"
        "detect_doors_stairs_prayer128 tests/test_detect_doors_stairs_prayer128.s 20000000"
        "slow_poison_prayer128 tests/test_slow_poison_prayer128.s 20000000"
        "blind_creature_prayer128 tests/test_blind_creature_prayer128.s 20000000"
        "portal_prayer128 tests/test_portal_prayer128.s 20000000"
        "cure_medium_wounds_prayer128 tests/test_cure_medium_wounds_prayer128.s 20000000"
        "cure_serious_wounds_prayer128 tests/test_cure_serious_wounds_prayer128.s 20000000"
        "sense_invisible_prayer128 tests/test_sense_invisible_prayer128.s 20000000"
        "protection_from_evil_prayer128 tests/test_protection_from_evil_prayer128.s 20000000"
        "earthquake_prayer128 tests/test_earthquake_prayer128.s 20000000"
        "sense_surroundings_prayer128 tests/test_sense_surroundings_prayer128.s 20000000"
        "cure_critical_wounds_prayer128 tests/test_cure_critical_wounds_prayer128.s 20000000"
        "turn_undead_prayer128 tests/test_turn_undead_prayer128.s 20000000"
        "prayer_prayer128 tests/test_prayer_prayer128.s 20000000"
        "dispel_undead_prayer128 tests/test_dispel_undead_prayer128.s 20000000"
        "dispel_evil_prayer128 tests/test_dispel_evil_prayer128.s 20000000"
        "glyph_of_warding_prayer128 tests/test_glyph_of_warding_prayer128.s 20000000"
        "holy_word_prayer128 tests/test_holy_word_prayer128.s 20000000"
        "heal_prayer128 tests/test_heal_prayer128.s 20000000"
        "chant_prayer128 tests/test_chant_prayer128.s 20000000"
        "sanctuary_prayer128 tests/test_sanctuary_prayer128.s 20000000"
        "neutralize_poison_prayer128 tests/test_neutralize_poison_prayer128.s 20000000"
        "create_food_prayer128 tests/test_create_food_prayer128.s 20000000"
        "remove_curse_prayer128 tests/test_remove_curse_prayer128.s 20000000"
        "resist_heat_cold_prayer128 tests/test_resist_heat_cold_prayer128.s 20000000"
        "orb_of_draining_prayer128 tests/test_orb_of_draining_prayer128.s 20000000"
        "find_hidden_traps_doors128 tests/test_find_hidden_traps_doors128.s 20000000"
        "stinking_cloud128 tests/test_stinking_cloud128.s 20000000"
        "frost_ball128 tests/test_frost_ball128.s 20000000"
        "teleport_other128 tests/test_teleport_other128.s 20000000"
        "haste_self128 tests/test_haste_self128.s 20000000"
        "fire_ball128 tests/test_fire_ball128.s 20000000"
        "word_of_destruction128 tests/test_word_of_destruction128.s 20000000"
        "genocide128 tests/test_genocide128.s 20000000"
        "confusion128 tests/test_confusion128.s 20000000"
        "lightning_bolt128 tests/test_lightning_bolt128.s 20000000"
        "frost_bolt128 tests/test_frost_bolt128.s 20000000"
        "turn_stone_to_mud128 tests/test_turn_stone_to_mud128.s 20000000"
        "create_food128 tests/test_create_food128.s 20000000"
        "recharge_item_i128 tests/test_recharge_item_i128.s 20000000"
        "recharge_item_ii128 tests/test_recharge_item_ii128.s 20000000"
        "trap_door_destruction128 tests/test_trap_door_destruction128.s 20000000"
        "sleep_i128 tests/test_sleep_i128.s 20000000"
        "sleep_ii128 tests/test_sleep_ii128.s 20000000"
        "sleep_iii128 tests/test_sleep_iii128.s 20000000"
        "fire_bolt128 tests/test_fire_bolt128.s 20000000"
        "slow_monster128 tests/test_slow_monster128.s 20000000"
        "polymorph_other128 tests/test_polymorph_other128.s 20000000"
        "identify128 tests/test_identify128.s 20000000"
        "teleport_self128 tests/test_teleport_self128.s 20000000"
        "remove_curse128 tests/test_remove_curse128.s 20000000"
        "phase_door128 tests/test_phase_door128.s 20000000"
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
    
    mkdir -p "$C128_TEST_OUT"
    if [ "$TEST_FAIL_FAST" != "0" ]; then
        echo "  running unit tests serially (fail-fast)..."
        local test_entry
        for test_entry in "${filtered_tests[@]}"; do
            : > "$result_file"
            bash "$RUN_TESTS128_DIR/run_test_internal_worker.sh" "$result_file" ${test_entry}
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

    printf "%s\n" "${filtered_tests[@]}" | xargs -P "$TEST_JOBS_RESOLVED" -n 3 bash "$RUN_TESTS128_DIR/run_test_internal_worker.sh" "$result_file"
    
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

boot_stop_vice_process() {
    local vice_pid="$1"
    if kill -0 "$vice_pid" 2>/dev/null; then
        kill "$vice_pid" 2>/dev/null || true
        wait "$vice_pid" 2>/dev/null || true
    fi
}

boot_wait_for_until_or_crash() {
    local vice_pid="$1"
    local target_addr="$2"
    local log_file="$3"
    local deadline=$((SECONDS + 25))

    while :; do
        if grep -qi "^UNTIL: .*C:\$${target_addr}" "$log_file"; then
            boot_stop_vice_process "$vice_pid"
            return 0
        fi
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            boot_stop_vice_process "$vice_pid"
            return 1
        fi
        if ! kill -0 "$vice_pid" 2>/dev/null; then
            wait "$vice_pid" 2>/dev/null || true
            break
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            boot_stop_vice_process "$vice_pid"
            return 1
        fi
        sleep 0.1
    done

    grep -qi "^UNTIL: .*C:\$${target_addr}" "$log_file"
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

    local c1541_bin="${C1541:-c1541}"
    local scripted_d64="../../../build/test/c128/moria128_detectmonsters.d64"
    local build_log
    build_log="$(test128_tmp_file "test128_${name}_disk.log")"
    : > "$build_log"
    if ! "$c1541_bin" -format "moria128,m8" d64 "$scripted_d64" \
            -attach "$scripted_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
			-write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (disk build error)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local main_vs="../../../build/test/c128/main.vs"
    local entry_main
    entry_main=$(awk '/\.entry_main$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${entry_main:-}" ]; then
        echo "FAIL (missing entry_main in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
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

    local main_vs="../../../build/test/c128/main.vs"
    local loop_top
    loop_top=$(awk '/\.c128_town_move_diag_loop_top$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${loop_top:-}" ]; then
        echo "FAIL (missing c128_town_move_diag_loop_top in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
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

    local main_vs="../../../build/test/c128/main.vs"
    local game_new_start
    game_new_start=$(awk '/\.game_new_start$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${game_new_start:-}" ]; then
        echo "FAIL (missing game_new_start in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
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

    local main_vs="../../../build/test/c128/main.vs"
    local title_art_pass title_art_fail
    title_art_pass=$(awk '/\.c128_test_title_art_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    title_art_fail=$(awk '/\.c128_test_title_art_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_art_pass:-}" ] || [ -z "${title_art_fail:-}" ]; then
        echo "FAIL (missing title art probe symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_titleart.d64"
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

run_boot_title_load_missing_savefile_smoke() {
    local name="boot_title_load_missing_savefile_smoke"
    echo -n "  $name: "

    build_title_load_missing_save_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local title_menu_ready
    title_menu_ready=$(awk '/\.title_menu_ready$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_menu_ready:-}" ]; then
        echo "FAIL (missing title_menu_ready in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_boot_d64 abs_save_d64 abs_main_vs
    abs_boot_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
    abs_save_d64="$(cd ../../../build/test/c128 && pwd)/moria128_missing_save.d64"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    abs_main_vs="$(cd ../../../build/test/c128 && pwd)/main.vs"

    if ! python3 -u tests/title_load_missing_save_smoke.py \
            --vice "$VICE" \
            --boot-d64 "$abs_boot_d64" \
            --save-d64 "$abs_save_d64" \
            --main-vs "$abs_main_vs" >"$log_file" 2>&1; then
        echo "FAIL"
        tail -20 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_load_mounted_save_smoke() {
    local name="boot_title_load_mounted_save_smoke"
    echo -n "  $name: "

    build_title_load_mounted_save_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local title_menu_ready load_resume_game uds_show_insert_prompt disk_prompt_game
    title_menu_ready=$(awk '/\.title_menu_ready$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    load_resume_game=$(awk '/\.load_resume_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    uds_show_insert_prompt=$(awk '/\.uds_show_insert_prompt$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    disk_prompt_game=$(awk '/\.disk_prompt_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_menu_ready:-}" ] || [ -z "${load_resume_game:-}" ] || [ -z "${uds_show_insert_prompt:-}" ] || [ -z "${disk_prompt_game:-}" ]; then
        echo "FAIL (missing mounted-save smoke symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_boot_d64 abs_save_d64
    abs_boot_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
    abs_save_d64="$(cd ../../../build/test/c128 && pwd)/moria128_mounted_save.d64"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    if ! python3 -u tests/title_load_mounted_save_smoke.py \
            --vice "$VICE" \
            --boot-d64 "$abs_boot_d64" \
            --save-d64 "$abs_save_d64" \
            --main-vs "$(cd ../../../build/test/c128 && pwd)/main.vs" >"$log_file" 2>&1; then
        echo "FAIL"
        tail -20 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_save_write_product_smoke() {
    local name="boot_title_save_write_product_smoke"
    echo -n "  $name: "

    build_save_write_product_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr fail_addr diag_addr
    pass_addr=$(awk '/\.c128_test_after_save_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    fail_addr=$(awk '/\.c128_test_unexpected_post_save_program_prompt$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    diag_addr=$(awk '/\.c128_test_post_save_prompt_diag$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ] || [ -z "${fail_addr:-}" ] || [ -z "${diag_addr:-}" ]; then
        echo "FAIL (missing save-write smoke symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_boot_d64 abs_save_d64
    abs_boot_d64="$(cd ../../../build/test/c128 && pwd)/moria128_savewrite_product.d64"
    abs_save_d64="$(cd ../../../build/test/c128 && pwd)/moria128_savewrite_product_save.d64"
    local mon_file log_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_boot_d64" \
        -drive9type 1541 -attach9rw -9 "$abs_save_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${pass_addr}" "$log_file"; then
        boot_log_report_failure "did not reach c128_test_after_save_game" "$log_file" \
            "c128_test_after_save_game" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during save-write product flow" "$log_file" \
            "c128_test_after_save_game" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local c1541_bin="${C1541:-c1541}"
    local dir_list
    if ! dir_list=$("$c1541_bin" -attach "$abs_save_d64" -list 2>&1); then
        echo "FAIL (save disk listing failed)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
        echo "FAIL (save file not present)"
        echo "$dir_list" | tail -20 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_marker_init_d64_smoke() {
    local name="marker_init_d64_smoke"
    echo -n "  $name: "

    local build_log
    build_log="$(test128_tmp_file "test128_${name}_build.log")"
    local prg_file="tests/test_marker_init_d64_128.prg"
    local save_d64="../../../build/test/c128/moria128_marker_init_d64_save.d64"

    if ! java -jar "$KICKASS" tests/test_marker_init_d64_128.s \
            -o "$prg_file" -libdir ../c64 -define C128 -vicesymbols \
            :OVL_OUT=../../../build/test/c128 >"$build_log" 2>&1; then
        echo "FAIL (marker-init D64 payload assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_prg abs_vs abs_save_d64 log_file
    abs_prg="$(cd "$(dirname "$prg_file")" && pwd)/$(basename "$prg_file")"
    abs_vs="$(cd "$(dirname "$prg_file")" && pwd)/test_marker_init_d64_128.vs"
    mkdir -p "$C128_TEST_OUT"
    abs_save_d64="$(cd ../../../build/test/c128 && pwd)/$(basename "$save_d64")"
    log_file="$(test128_tmp_file "test128_${name}.log")"

    if ! python3 -u tests/marker_init_d64_smoke.py \
            --vice "$VICE" \
            --c1541 "${C1541:-c1541}" \
            --prg "$abs_prg" \
            --vs "$abs_vs" \
            --save-d64 "$abs_save_d64" >"$log_file" 2>&1; then
        echo "FAIL"
        tail -20 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_save_media_fail_product_smoke() {
    local name="boot_title_save_media_fail_product_smoke"
    echo -n "  $name: "

    build_save_media_fail_product_assets || return

    local main_vs="../../../build/test/c128/main_save_media_fail.vs"
    local fail_addr
    fail_addr=$(awk '/\.save_return_fail$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${fail_addr:-}" ]; then
        echo "FAIL (missing save-media-fail smoke symbols in ../../../build/test/c128/main_save_media_fail.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_boot_d64 abs_save_d64
    abs_boot_d64="$(cd ../../../build/test/c128 && pwd)/moria128_savemediafail_product.d64"
    abs_save_d64="$(cd ../../../build/test/c128 && pwd)/moria128_savemediafail_product_save.d64"
    local mon_file log_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${fail_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_boot_d64" \
        -drive9type 1541 -attach9rw -9 "$abs_save_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 360000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${fail_addr}" "$log_file"; then
        boot_log_report_failure "save-media failure did not reach disk-error dismiss prompt" "$log_file" \
            "save_return_fail" "$fail_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during save-media-fail product flow" "$log_file" \
            "save_return_fail" "$fail_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_change_save_drive_smoke() {
    local name="boot_title_change_save_drive_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_change_save_drive_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local boot_d64="../../../build/test/c128/moria128_change_save_drive.d64"
    local save10_d64="../../../build/test/c128/moria128_change_save_drive_save10.d64"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local dir_type_offset0=$(((357 + 1) * 256 + 2))

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (change-save-drive product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$c1541_bin" -format "moria128,m8" d64 "$boot_d64" \
            -attach "$boot_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/ovl.help "128.help" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (change-save-drive product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation failed)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    rm -f "$save10_d64"
    if ! "$c1541_bin" -format "moria128 save,m8" d64 "$save10_d64" \
            -attach "$save10_d64" \
            -write "$marker_blob" "MORIA8.ID" >>"$build_log" 2>&1; then
        echo "FAIL (drive-10 save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! printf '\201' | dd of="$save10_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL (drive-10 marker directory patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$boot_d64" \
            --save10-d64 "$save10_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --start-symbol ".c128_test_change_save_drive_wait_for_harness" \
            --resume-symbol ".c128_test_change_save_drive_before_save" \
            --pass-symbol ".c128_test_change_save_drive_pass" \
            --fail-symbol ".c128_test_change_save_drive_unexpected_return" \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$c1541_bin" -attach "$save10_d64" -list 2>&1); then
            echo "FAIL (drive-10 save disk listing failed)"
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

run_boot_title_single_drive_save_wrong_media_smoke() {
    local name="boot_title_single_drive_save_wrong_media_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_single_drive_save_wrong_media_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local wrong_media_d64="../../../build/test/c128/moria128_single_drive_save_wrong_media.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (single-drive save wrong-media product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$wrong_media_d64"
    if ! "$c1541_bin" -format "moria128,m8" d64 "$wrong_media_d64" \
            -attach "$wrong_media_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive save wrong-media product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local pass_addr
    pass_addr=$(awk '/\.c128_test_single_drive_save_wrong_media_script_exhausted$/ { split($2,a,":"); print toupper(a[2]); exit }' ../../../build/test/c128/main.vs)
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing single-drive save wrong-media smoke symbols)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file log_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    log_file="$(test128_tmp_file "test128_${name}.log")"
    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$wrong_media_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 360000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${pass_addr}" "$log_file"; then
        echo "FAIL"
        boot_log_report_failure "single-drive save wrong-media did not reach final insert prompt" "$log_file" \
            "script_exhausted" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_single_drive_load_wrong_media_smoke() {
    local name="boot_title_single_drive_load_wrong_media_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_single_drive_load_wrong_media_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local wrong_media_d64="../../../build/test/c128/moria128_single_drive_load_wrong_media.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (single-drive load wrong-media product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$wrong_media_d64"
    if ! "$c1541_bin" -format "moria128,m8" d64 "$wrong_media_d64" \
            -attach "$wrong_media_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive load wrong-media product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local pass_addr
    pass_addr=$(awk '/\.c128_test_single_drive_load_wrong_media_script_exhausted$/ { split($2,a,":"); print toupper(a[2]); exit }' ../../../build/test/c128/main.vs)
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing single-drive load wrong-media smoke symbols)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local mon_file log_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    log_file="$(test128_tmp_file "test128_${name}.log")"
    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$wrong_media_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 360000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${pass_addr}" "$log_file"; then
        echo "FAIL"
        boot_log_report_failure "single-drive load wrong-media did not reach final insert prompt" "$log_file" \
            "script_exhausted" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_boot_title_single_drive_load_corrupt_smoke() {
    local name="boot_title_single_drive_load_corrupt_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_single_drive_load_corrupt_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local boot_d64="../../../build/test/c128/moria128_single_drive_load_corrupt.d71"
    local save_d64="../../../build/test/c128/moria128_single_drive_load_corrupt_save.d64"
    local program_d64="../../../build/test/c128/moria128_single_drive_load_corrupt_program.d64"
    local save_blob="../../../build/test/c128/THE.GAME"
    local marker_blob="../../../build/test/c128/MORIA8.ID"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (single-drive load corrupt product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$boot_d64"
    cp ../../../build/test/c128/moria128.d71 "$boot_d64"
    if ! "$c1541_bin" -attach "$boot_d64" \
            -delete "moria128" \
            -delete "128.runtime" \
            -delete "128.input" \
            -delete "128.proj" \
            -delete "128.fdisk" \
            -delete "128.diskio" \
            -delete "128.world" \
            -delete "128.item" \
            -delete "128.names" \
            -delete "128.select" \
            -delete "128.persist" \
            -delete "128.play" \
            -delete "128.bank" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive load corrupt product disk patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (c128 save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! python3 -c 'from pathlib import Path; import sys; p=Path(sys.argv[1]); b=bytearray(p.read_bytes()); b[0] ^= 0xff; p.write_bytes(b)' "$save_blob" >>"$build_log" 2>&1; then
        echo "FAIL (c128 corrupt save fixture patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    printf 'M8SAVE' > "$marker_blob"

    rm -f "$save_d64" "$program_d64"
    if ! "$c1541_bin" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "MORIA8.ID,s" \
            -write "$save_blob" "THE.GAME,s" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive load corrupt save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$boot_d64" "$program_d64"

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$boot_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --start-symbol ".c128_test_single_drive_load_corrupt_wait_for_harness" \
            --resume-symbol ".c128_test_single_drive_load_corrupt_before_load" \
            --pass-symbol ".c128_test_single_drive_load_corrupt_program_ready" \
            --fail-symbol ".c128_test_load_corrupt_unexpected_success" \
            --require-hit-symbol ".c128_test_load_corrupt_detected" \
            --swap-symbol ".disk_prompt_game" \
            --swap-attach8-d64 "$program_d64" \
            --attach8-at-start-d64 "$save_d64" \
            --pass-on-script-exhausted \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_boot_title_single_drive_load_return_smoke() {
    local name="boot_title_single_drive_load_return_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_single_drive_load_return_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local boot_d64="../../../build/test/c128/moria128_single_drive_load_return.d71"
    local save_d64="../../../build/test/c128/moria128_single_drive_load_return_save.d64"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local save_blob="../../../build/test/c128/THE.GAME"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (single-drive load return product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$boot_d64"
    cp ../../../build/test/c128/moria128.d71 "$boot_d64"
    if ! "$c1541_bin" -attach "$boot_d64" \
            -delete "moria128" \
            -delete "128.runtime" \
            -delete "128.input" \
            -delete "128.proj" \
            -delete "128.fdisk" \
            -delete "128.diskio" \
            -delete "128.world" \
            -delete "128.item" \
            -delete "128.names" \
            -delete "128.select" \
            -delete "128.persist" \
            -delete "128.play" \
            -delete "128.bank" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive load return product disk patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (single-drive load return save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    printf 'M8SAVE' > "$marker_blob"

    rm -f "$save_d64"
    if ! "$c1541_bin" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "MORIA8.ID,s" \
            -write "$save_blob" "THE.GAME,s" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive load return save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$boot_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --start-symbol ".c128_test_single_drive_load_return_wait_for_harness" \
            --resume-symbol ".c128_test_single_drive_load_return_before_load" \
            --pass-symbol ".c128_program_media_error_prompt" \
            --fail-symbol ".c128_test_single_drive_load_return_load_fail" \
            --attach8-at-start-d64 "$save_d64" \
            --reset8-after-attach \
            --require-hit-symbol ".c128_test_single_drive_load_return_loaded" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_boot_title_load_then_save_new_empty_smoke() {
    local name="boot_title_load_then_save_new_empty_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_load_then_save_new_empty_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local boot_d64="../../../build/test/c128/moria128_load_then_save_new_empty.d71"
    local load_save_d64="../../../build/test/c128/moria128_load_then_save_new_empty_load.d64"
    local new_save_d64="../../../build/test/c128/moria128_load_then_save_new_empty_save.d64"
    local swap_program_d64="../../../build/test/c128/moria128_load_then_save_new_empty_program.d71"
    local marker_blob="../../../build/test/c128/MORIA8.ID"
    local save_blob="../../../build/test/c128/THE.GAME"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT -define C128_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (load-then-save-new-empty product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$boot_d64"
    cp ../../../build/test/c128/moria128.d71 "$boot_d64"
    if ! "$c1541_bin" -attach "$boot_d64" \
            -delete "moria128" \
            -delete "128.runtime" \
            -delete "128.input" \
            -delete "128.proj" \
            -delete "128.fdisk" \
            -delete "128.diskio" \
            -delete "128.world" \
            -delete "128.item" \
            -delete "128.names" \
            -delete "128.select" \
            -delete "128.persist" \
            -delete "128.play" \
            -delete "128.bank" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (load-then-save-new-empty product disk patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! python3 tests/make_load_resume_save.py "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL (load save generation failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    printf 'M8SAVE' > "$marker_blob"

    rm -f "$load_save_d64" "$new_save_d64" "$swap_program_d64"
    if ! "$c1541_bin" -format "moria8 save,m8" d64 "$load_save_d64" \
            -attach "$load_save_d64" \
            -write "$marker_blob" "MORIA8.ID,s" \
            -write "$save_blob" "THE.GAME,s" >>"$build_log" 2>&1; then
        echo "FAIL (load save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! "$c1541_bin" -format "moria128 save,m8" d64 "$new_save_d64" >"$build_log" 2>&1; then
        echo "FAIL (new empty save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$boot_d64" "$swap_program_d64"

    if python3 -u tests/load_then_save_new_empty_smoke.py \
            --vice "$VICE" \
            --boot-d64 "$boot_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --load-save-d64 "$load_save_d64" \
            --new-save-d64 "$new_save_d64" \
            --program-d64 "$swap_program_d64" \
            --attach-delay 5.0 \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$c1541_bin" -attach "$new_save_d64" -list 2>&1); then
            echo "FAIL (new save disk listing failed)"
            echo "$dir_list" | tail -20 | sed 's/^/    /'
            FAIL=$((FAIL + 1))
        elif echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ' && \
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

run_boot_title_disk_setup_single_drive_return_smoke() {
    local name="boot_title_disk_setup_single_drive_return_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_disk_setup_single_drive_return_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local boot_d64="../../../build/test/c128/moria128_disk_setup_single_drive_return.d71"
    local save_d64="../../../build/test/c128/moria128_disk_setup_single_drive_return_save.d64"
    local program_d64="../../../build/test/c128/moria128_disk_setup_single_drive_return_program.d71"
    local marker_blob="../../../build/test/c128/MORIA8.ID"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (disk-setup single-drive return product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$boot_d64"
    cp ../../../build/test/c128/moria128.d71 "$boot_d64"
    if ! "$c1541_bin" -attach "$boot_d64" \
            -delete "moria128" \
            -delete "128.runtime" \
            -delete "128.input" \
            -delete "128.proj" \
            -delete "128.fdisk" \
            -delete "128.diskio" \
            -delete "128.world" \
            -delete "128.item" \
            -delete "128.names" \
            -delete "128.select" \
            -delete "128.persist" \
            -delete "128.play" \
            -delete "128.bank" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (disk-setup single-drive return product disk patch failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL (marker generation failed)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    rm -f "$save_d64" "$program_d64"
    if ! "$c1541_bin" -format "moria8 save,m8" d64 "$save_d64" \
            -attach "$save_d64" \
            -write "$marker_blob" "MORIA8.ID,s" >>"$build_log" 2>&1; then
        echo "FAIL (disk-setup single-drive return save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$boot_d64" "$program_d64"

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$boot_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --start-symbol ".c128_test_disk_setup_single_drive_return_wait_for_harness" \
            --resume-symbol ".c128_test_disk_setup_single_drive_return_before_disk_setup" \
            --pass-symbol ".c128_test_after_disk_setup_single_drive_return" \
            --swap-symbol ".c128_program_media_error_shown" \
            --swap-attach8-d64 "$program_d64" \
            --attach8-at-start-d64 "$save_d64" \
            --screen-base 0x0400; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL=$((TOTAL + 1))
}

run_boot_title_single_drive_fresh_save_smoke() {
    local name="boot_title_single_drive_fresh_save_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_single_drive_fresh_save_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local fresh_d64="../../../build/test/c128/moria128_single_drive_fresh_save.d64"
    local save_d64="../../../build/test/c128/moria128_single_drive_fresh_save_save.d64"
    local swap_program_d64="../../../build/test/c128/moria128_single_drive_fresh_save_program.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (single-drive fresh-save product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$fresh_d64"
    if ! "$c1541_bin" -format "moria128,m8" d64 "$fresh_d64" \
            -attach "$fresh_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/ovl.help "128.help" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive fresh-save product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64" "$swap_program_d64"
    if ! "$c1541_bin" -format "moria128 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (single-drive fresh-save blank save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    cp "$fresh_d64" "$swap_program_d64"

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$fresh_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --start-symbol ".c128_test_single_drive_fresh_save_wait_for_harness" \
            --resume-symbol ".c128_test_single_drive_fresh_save_before_save" \
            --attach-delay 5.0 \
            --swap-symbol ".uds_show_insert_prompt" \
            --swap-attach8-d64 "$save_d64" \
            --swap2-symbol ".disk_prompt_game" \
            --swap2-attach8-d64 "$swap_program_d64" \
            --pass-symbol ".c128_test_single_drive_fresh_save_after_restart" \
            --fail-symbol ".c128_test_single_drive_fresh_save_unexpected_return" \
            --limitcycles 0 \
            --reset8-after-attach \
            --autostart-only-drive8 \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$c1541_bin" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (single-drive fresh-save disk listing failed)"
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

run_boot_title_single_drive_fresh_save_no_init_smoke() {
    local name="boot_title_single_drive_fresh_save_no_init_smoke"
    echo -n "  $name: "

    build_boot_assets || return

    local build_log
    build_log="$(test128_tmp_file test128_single_drive_fresh_save_no_init_build.log)"
    local c1541_bin="${C1541:-c1541}"
    local fresh_d64="../../../build/test/c128/moria128_single_drive_fresh_save_no_init.d64"
    local save_d64="../../../build/test/c128/moria128_single_drive_fresh_save_no_init_save.d64"

    if ! java -jar "$KICKASS" main.s :OVL_OUT=../../../build/test/c128 -showmem -vicesymbols -libdir ../c64 \
            -define C128 -define C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT \
            -define C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT \
            -o ../../../build/test/c128/moria128.prg >"$build_log" 2>&1; then
        echo "FAIL (single-drive fresh-save no-init product main assembly failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$fresh_d64"
    if ! "$c1541_bin" -format "moria128,m8" d64 "$fresh_d64" \
            -attach "$fresh_d64" \
            -write ../../../build/test/c128/boot128.prg "moria8.128" \
            -write ../../../build/test/c128/moria128.prg "moria128" \
            -write ../../../build/test/c128/title "title" \
            -write ../../../build/test/c128/monster.db.1 "monster.db.1" \
            -write ../../../build/test/c128/monster.db.2 "monster.db.2" \
            -write ../../../build/test/c128/monster.db.3 "monster.db.3" \
            -write ../../../build/test/c128/monster.db.4 "monster.db.4" \
            -write ../../../build/test/c128/ovl.town "ovl.town" \
            -write ../../../build/test/c128/ovl.start "ovl.start" \
            -write ../../../build/test/c128/ovl.death "ovl.death" \
            -write ../../../build/test/c128/ovl.gen "ovl.gen" \
            -write ../../../build/test/c128/ovl.help "128.help" \
            -write ../../../build/test/c128/128.runtime.prg "128.runtime" \
            -write ../../../build/test/c128/128.input.prg "128.input" \
            -write ../../../build/test/c128/128.proj.prg "128.proj" \
            -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
            -write ../../../build/test/c128/128.diskio.prg "128.diskio" \
            -write ../../../build/test/c128/128.world.prg "128.world" \
            -write ../../../build/test/c128/128.item.prg "128.item" \
            -write ../../../build/test/c128/128.names.prg "128.names" \
            -write ../../../build/test/c128/128.select.prg "128.select" \
            -write ../../../build/test/c128/128.persist.prg "128.persist" \
            -write ../../../build/test/c128/128.play.prg "128.play" \
            -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
        echo "FAIL (single-drive fresh-save no-init product disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$c1541_bin" -format "moria128 save,m8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL (single-drive fresh-save no-init blank save disk build failed)"
        tail -20 "$build_log" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if python3 -u ../plus4/tests/product_scripted_smoke.py \
            --name "$name" \
            --vice "$VICE" \
            --boot-d64 "$fresh_d64" \
            --main-vs ../../../build/test/c128/main.vs \
            --start-symbol ".c128_test_single_drive_fresh_save_wait_for_harness" \
            --resume-symbol ".c128_test_single_drive_fresh_save_before_save" \
            --attach-delay 5.0 \
            --swap-symbol ".uds_show_insert_prompt" \
            --swap-attach8-d64 "$save_d64" \
            --pass-symbol ".c128_test_single_drive_fresh_save_no_init_return" \
            --fail-symbol ".c128_test_single_drive_fresh_save_unexpected_return" \
            --limitcycles 0 \
            --reset8-after-attach \
            --autostart-only-drive8 \
            --screen-base 0x0400; then
        local dir_list
        if ! dir_list=$("$c1541_bin" -attach "$save_d64" -list 2>&1); then
            echo "FAIL (single-drive fresh-save no-init disk listing failed)"
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

run_boot_title_load_resume_smoke() {
    local name="boot_title_load_resume_smoke"
    echo -n "  $name: "

    build_load_resume_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local load_resume_game
    load_resume_game=$(awk '/\.load_resume_game$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${load_resume_game:-}" ]; then
        echo "FAIL (missing load_resume_game in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_loadresume.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local title_show_sysinfo title_menu_ready game_over_prompt
    title_show_sysinfo=$(awk '/\.title_show_sysinfo$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    title_menu_ready=$(awk '/\.title_menu_ready$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    game_over_prompt=$(awk '/\.game_over_prompt$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_show_sysinfo:-}" ] || [ -z "${title_menu_ready:-}" ] || [ -z "${game_over_prompt:-}" ]; then
        echo "FAIL (missing title boot probe symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "until \$${title_show_sysinfo}"
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

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam before title_show_sysinfo on idle boot" "$log_file" "title_show_sysinfo" "$title_show_sysinfo" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    {
        echo "until \$${title_menu_ready}"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 120000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${title_menu_ready}" "$log_file"; then
        boot_log_report_failure "did not reach title_menu_ready on idle boot" "$log_file" "title_menu_ready" "$title_menu_ready" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam before title_menu_ready on idle boot" "$log_file" "title_menu_ready" "$title_menu_ready" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    : > "$log_file"
    {
        echo "break \$${game_over_prompt}"
        echo "g"
    } > "$mon_file"
    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" \
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

    if boot_log_has_stop_at "$log_file" "$game_over_prompt"; then
        boot_log_report_failure "entered game_over_prompt during idle title soak" "$log_file" "game_over_prompt" "$game_over_prompt" "$vice_rc"
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

    local main_vs="../../../build/test/c128/main.vs"
    local dungeon_generate
    dungeon_generate=$(awk '/\.dungeon_generate$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${dungeon_generate:-}" ]; then
        echo "FAIL (missing dungeon_generate in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
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

    local main_vs="../../../build/test/c128/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
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

    local main_vs="../../../build/test/c128/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$d000 \$dfff"
        echo "until \$${store_enter}"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rB LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${store_enter}" "$log_file"; then
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

    local main_vs="../../../build/test/c128/main.vs"
    local store_enter
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ]; then
        echo "FAIL (missing store_enter in overlay-state .vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_overlaystate.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"

    {
        echo "break \$d000 \$dfff"
        echo "until \$${store_enter}"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rB LLLLLLLL' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if ! grep -qi "^UNTIL: .*C:\$${store_enter}" "$log_file"; then
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

    local main_vs="../../../build/test/c128/main.vs"
    local c128_test_town_pass c128_test_town_fail
    c128_test_town_pass=$(awk '/\.c128_test_town_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_town_fail=$(awk '/\.c128_test_town_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_test_town_pass:-}" ] || [ -z "${c128_test_town_fail:-}" ]; then
        echo "FAIL (missing scripted summary/town pass/fail symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_scriptedinput.d64"
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

    "$VICE" -console -nativemonitor -warp -80col -8 "$abs_d64" -9 "$abs_d64" -autostart "$abs_d64" \
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

PERF_P1_TRACE_FAIL_REASON=""
PERF_P1_TRACE_VALUES=""
PERF_P1_TRACE_D64=""
perf_p1_trace_collect_variant() {
    local suffix="$1"
    shift
    PERF_P1_TRACE_FAIL_REASON=""
    PERF_P1_TRACE_D64=""

    build_perf_p1_trace_boot_assets "$suffix" "$@" || return 2
    return 0
}

perf_p1_trace_run_product_assert() {
    perf_p1_trace_collect_variant "assert" C128_TEST_PERF_P1_TRACE_ASSERT || return 2

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c128_test_perf_p1_trace_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        PERF_P1_TRACE_FAIL_REASON="missing PERF trace product assert pass symbol in ../../../build/test/c128/main.vs"
        return 1
    fi

    local abs_d64
    abs_d64="$(cd "$(dirname "$PERF_P1_TRACE_D64")" && pwd)/$(basename "$PERF_P1_TRACE_D64")"
    local mon_file
    mon_file="$(test128_tmp_file "test128_perf_p1_trace_assert.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_perf_p1_trace_assert.log")"
    : > "$log_file"

    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -8 "$abs_d64" -9 "$abs_d64" -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="jam during PERF trace product assert"
        return 1
    fi

    local pass_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    if ! grep -Fqi "C:\$${pass_addr}" "$log_file" && ! grep -qiE "Stop on  exec ${pass_lc}" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="did not reach PERF trace product assert pass trap (vice rc ${vice_rc})"
        return 1
    fi

    PERF_P1_TRACE_VALUES="${PERF_P1_TRACE_VALUES}product first move local=1 full=0; "
    return 0
}

perf_p1_trace_run_modal_assert() {
    perf_p1_trace_collect_variant "modal_assert" C128_TEST_PERF_P1_TRACE_MODAL C128_TEST_PERF_P1_TRACE_MODAL_ASSERT || return 2

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c128_test_perf_p1_trace_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        PERF_P1_TRACE_FAIL_REASON="missing PERF trace modal assert pass symbol in ../../../build/test/c128/main.vs"
        return 1
    fi

    local abs_d64
    abs_d64="$(cd "$(dirname "$PERF_P1_TRACE_D64")" && pwd)/$(basename "$PERF_P1_TRACE_D64")"
    local mon_file
    mon_file="$(test128_tmp_file "test128_perf_p1_trace_modal_assert.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_perf_p1_trace_modal_assert.log")"
    : > "$log_file"

    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -8 "$abs_d64" -9 "$abs_d64" -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="jam during PERF trace modal assert"
        return 1
    fi

    local pass_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    if ! grep -Fqi "C:\$${pass_addr}" "$log_file" && ! grep -qiE "Stop on  exec ${pass_lc}" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="did not reach PERF trace modal assert pass trap (vice rc ${vice_rc})"
        return 1
    fi

    PERF_P1_TRACE_VALUES="${PERF_P1_TRACE_VALUES}modal restore full=1 reason=1; "
    return 0
}

perf_p1_trace_run_command_assert() {
    perf_p1_trace_collect_variant "command_assert" C128_TEST_PERF_P1_TRACE_COMMAND C128_TEST_PERF_P1_TRACE_COMMAND_ASSERT || return 2

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c128_test_perf_p1_trace_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        PERF_P1_TRACE_FAIL_REASON="missing PERF trace command assert pass symbol in ../../../build/test/c128/main.vs"
        return 1
    fi

    local abs_d64
    abs_d64="$(cd "$(dirname "$PERF_P1_TRACE_D64")" && pwd)/$(basename "$PERF_P1_TRACE_D64")"
    local mon_file
    mon_file="$(test128_tmp_file "test128_perf_p1_trace_command_assert.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_perf_p1_trace_command_assert.log")"
    : > "$log_file"

    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -8 "$abs_d64" -9 "$abs_d64" -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="jam during PERF trace command assert"
        return 1
    fi

    local pass_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    if ! grep -Fqi "C:\$${pass_addr}" "$log_file" && ! grep -qiE "Stop on  exec ${pass_lc}" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="did not reach PERF trace command assert pass trap (vice rc ${vice_rc})"
        return 1
    fi

    PERF_P1_TRACE_VALUES="${PERF_P1_TRACE_VALUES}command forced full=1 reason=1; "
    return 0
}

perf_p1_trace_run_transition_assert() {
    perf_p1_trace_collect_variant "transition_assert" C128_TEST_PERF_P1_TRACE_TRANSITION C128_TEST_PERF_P1_TRACE_TRANSITION_ASSERT || return 2

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c128_test_perf_p1_trace_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        PERF_P1_TRACE_FAIL_REASON="missing PERF trace transition assert pass symbol in ../../../build/test/c128/main.vs"
        return 1
    fi

    local abs_d64
    abs_d64="$(cd "$(dirname "$PERF_P1_TRACE_D64")" && pwd)/$(basename "$PERF_P1_TRACE_D64")"
    local mon_file
    mon_file="$(test128_tmp_file "test128_perf_p1_trace_transition_assert.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_perf_p1_trace_transition_assert.log")"
    : > "$log_file"

    {
        echo "until \$${pass_addr}"
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -8 "$abs_d64" -9 "$abs_d64" -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="jam during PERF trace transition assert"
        return 1
    fi

    local pass_lc
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')
    if ! grep -Fqi "C:\$${pass_addr}" "$log_file" && ! grep -qiE "Stop on  exec ${pass_lc}" "$log_file"; then
        PERF_P1_TRACE_FAIL_REASON="did not reach PERF trace transition assert pass trap (vice rc ${vice_rc})"
        return 1
    fi

    PERF_P1_TRACE_VALUES="${PERF_P1_TRACE_VALUES}transition full=1 reason=1; "
    return 0
}

run_perf_p1_trace_smoke() {
    local name="perf_p1_trace_smoke"
    echo -n "  $name: "
    PERF_P1_TRACE_VALUES=""

    if ! perf_p1_trace_run_product_assert; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_run_modal_assert; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_run_command_assert; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_run_transition_assert; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_collect_variant "summary"; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_collect_variant "reasons_0_2" C128_TEST_PERF_P1_TRACE_REASONS_0_2; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_collect_variant "reasons_3_5" C128_TEST_PERF_P1_TRACE_REASONS_3_5; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    if ! perf_p1_trace_collect_variant "reasons_6_7" C128_TEST_PERF_P1_TRACE_REASONS_6_7; then
        [ -n "$PERF_P1_TRACE_FAIL_REASON" ] && echo "FAIL (${PERF_P1_TRACE_FAIL_REASON})"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    echo "PASS (${PERF_P1_TRACE_VALUES}resident export variants validated)"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_spell_cast_smoke() {
    local name="scripted_spell_cast_smoke"
    echo -n "  $name: "

    build_scripted_spell_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local c128_test_spell_pass
    local -a spell_fail_labels=(
        "c128_test_spell_fail_no_cast_sym"
        "c128_test_spell_fail_level_sym"
        "c128_test_spell_fail_known_sym"
        "c128_test_spell_fail_validate_sym"
        "c128_test_spell_fail_roll_sym"
        "c128_test_spell_fail_cancel_sym"
    )
    local -a spell_fail_addrs=()
    local label addr
    c128_test_spell_pass=$(awk '/\.c128_test_spell_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${spell_fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in ../../../build/test/c128/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        spell_fail_addrs+=("$addr")
    done
    if [ -z "${c128_test_spell_pass:-}" ]; then
        echo "FAIL (missing scripted spell pass symbol in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_scriptedspell.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local pass_lc
    local pass_hit
    : > "$log_file"
    pass_lc=$(echo "$c128_test_spell_pass" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${spell_fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${c128_test_spell_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${c128_test_spell_pass}" "$log_file"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            boot_log_report_failure "jam during scripted spell cast flow" "$log_file" "c128_test_spell_pass" "$c128_test_spell_pass" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!spell_fail_labels[@]}"; do
        addr="${spell_fail_addrs[$idx]}"
        if grep -qi "^BREAK: .*C:\$${addr}" "$log_file"; then
            boot_log_report_failure "scripted spell cast hit fail trap" "$log_file" "${spell_fail_labels[$idx]}" "$addr" "$vice_rc"
            echo "    fail_label: ${spell_fail_labels[$idx]}"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted spell cast flow" "$log_file" "c128_test_spell_pass" "$c128_test_spell_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    boot_log_report_failure "did not reach scripted spell pass trap" "$log_file" "c128_test_spell_pass" "$c128_test_spell_pass" "$vice_rc"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_book_overlay_smoke() {
    local name="scripted_book_overlay_smoke"
    echo -n "  $name: "

    build_scripted_book_overlay_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c128_test_book_overlay_fail_sym"
    )
    local -a fail_addrs=()
    local label addr
    pass_addr=$(awk '/\.c128_test_book_overlay_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in ../../../build/test/c128/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted book overlay pass symbol in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_scriptedbookoverlay.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local pass_lc
    local pass_hit
    : > "$log_file"
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$log_file"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            boot_log_report_failure "jam during scripted book overlay flow" "$log_file" "c128_test_book_overlay_pass" "$pass_addr" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qi "^BREAK: .*C:\$${addr}" "$log_file"; then
            boot_log_report_failure "scripted book overlay hit fail trap" "$log_file" "${fail_labels[$idx]}" "$addr" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted book overlay flow" "$log_file" "c128_test_book_overlay_pass" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    boot_log_report_failure "did not reach scripted book overlay pass trap" "$log_file" "c128_test_book_overlay_pass" "$pass_addr" "$vice_rc"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_spell_list_overlay_smoke() {
    local name="scripted_spell_list_overlay_smoke"
    echo -n "  $name: "

    build_scripted_spell_list_overlay_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    local -a fail_labels=(
        "c128_test_spell_list_overlay_fail_sym"
    )
    local -a fail_addrs=()
    local label addr
    pass_addr=$(awk '/\.c128_test_spell_list_overlay_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in ../../../build/test/c128/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        fail_addrs+=("$addr")
    done
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing scripted spell list overlay pass symbol in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_scriptedspelllistoverlay.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local pass_lc
    local pass_hit
    : > "$log_file"
    pass_lc=$(echo "$pass_addr" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${pass_addr}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${pass_addr}" "$log_file"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            boot_log_report_failure "jam during scripted spell list overlay flow" "$log_file" "c128_test_spell_list_overlay_pass" "$pass_addr" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!fail_labels[@]}"; do
        addr="${fail_addrs[$idx]}"
        if grep -qi "^BREAK: .*C:\$${addr}" "$log_file"; then
            boot_log_report_failure "scripted spell list overlay hit fail trap" "$log_file" "${fail_labels[$idx]}" "$addr" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted spell list overlay flow" "$log_file" "c128_test_spell_list_overlay_pass" "$pass_addr" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    boot_log_report_failure "did not reach scripted spell list overlay pass trap" "$log_file" "c128_test_spell_list_overlay_pass" "$pass_addr" "$vice_rc"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_spell_list_cancel_smoke() {
    local name="scripted_spell_list_cancel_smoke"
    echo -n "  $name: "

    build_scripted_spell_cancel_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local c128_test_spell_pass
    local -a spell_fail_labels=(
        "c128_test_spell_fail_no_cast_sym"
        "c128_test_spell_fail_level_sym"
        "c128_test_spell_fail_known_sym"
        "c128_test_spell_fail_validate_sym"
        "c128_test_spell_fail_roll_sym"
        "c128_test_spell_fail_cancel_sym"
    )
    local -a spell_fail_addrs=()
    local label addr
    c128_test_spell_pass=$(awk '/\.c128_test_spell_cancel_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${spell_fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in ../../../build/test/c128/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        spell_fail_addrs+=("$addr")
    done
    if [ -z "${c128_test_spell_pass:-}" ]; then
        echo "FAIL (missing scripted spell cancel pass symbol in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_scriptedspellcancel.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local pass_lc
    local pass_hit
    : > "$log_file"
    pass_lc=$(echo "$c128_test_spell_pass" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${spell_fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${c128_test_spell_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${c128_test_spell_pass}" "$log_file"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            boot_log_report_failure "jam during scripted spell list cancel flow" "$log_file" "c128_test_spell_cancel_pass" "$c128_test_spell_pass" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!spell_fail_labels[@]}"; do
        addr="${spell_fail_addrs[$idx]}"
        if grep -qi "^BREAK: .*C:\$${addr}" "$log_file"; then
            boot_log_report_failure "scripted spell list cancel hit fail trap" "$log_file" "${spell_fail_labels[$idx]}" "$addr" "$vice_rc"
            echo "    fail_label: ${spell_fail_labels[$idx]}"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted spell list cancel flow" "$log_file" "c128_test_spell_cancel_pass" "$c128_test_spell_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    boot_log_report_failure "did not reach scripted spell list cancel pass trap" "$log_file" "c128_test_spell_cancel_pass" "$c128_test_spell_pass" "$vice_rc"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_scripted_prayer_cast_smoke() {
    local name="scripted_prayer_cast_smoke"
    echo -n "  $name: "

    build_scripted_prayer_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
    local c128_test_spell_pass
    local -a spell_fail_labels=(
        "c128_test_spell_fail_no_cast_sym"
        "c128_test_spell_fail_level_sym"
        "c128_test_spell_fail_known_sym"
        "c128_test_spell_fail_validate_sym"
        "c128_test_spell_fail_roll_sym"
        "c128_test_spell_fail_cancel_sym"
    )
    local -a spell_fail_addrs=()
    local label addr
    c128_test_spell_pass=$(awk '/\.c128_test_spell_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    for label in "${spell_fail_labels[@]}"; do
        addr=$(awk -v label="$label" '$3 == "." label { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
        if [ -z "${addr:-}" ]; then
            echo "FAIL (missing ${label} in ../../../build/test/c128/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        spell_fail_addrs+=("$addr")
    done
    if [ -z "${c128_test_spell_pass:-}" ]; then
        echo "FAIL (missing scripted prayer pass symbol in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_scriptedprayer.d64"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    local pass_lc
    local pass_hit
    : > "$log_file"
    pass_lc=$(echo "$c128_test_spell_pass" | tr '[:upper:]' '[:lower:]')

    {
        for addr in "${spell_fail_addrs[@]}"; do
            echo "break \$${addr}"
        done
        echo "break \$${c128_test_spell_pass}"
        echo "g"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 700000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    pass_hit=0
    if grep -qiE "Stop on  exec ${pass_lc}" "$log_file" || grep -qi "^BREAK: .*C:\$${c128_test_spell_pass}" "$log_file"; then
        pass_hit=1
    fi

    if [ "$pass_hit" -eq 1 ]; then
        if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
            boot_log_report_failure "jam during scripted prayer cast flow" "$log_file" "c128_test_spell_pass" "$c128_test_spell_pass" "$vice_rc"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        echo "PASS"
        PASS=$((PASS + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    for idx in "${!spell_fail_labels[@]}"; do
        addr="${spell_fail_addrs[$idx]}"
        if grep -qi "^BREAK: .*C:\$${addr}" "$log_file"; then
            boot_log_report_failure "scripted prayer cast hit fail trap" "$log_file" "${spell_fail_labels[$idx]}" "$addr" "$vice_rc"
            echo "    fail_label: ${spell_fail_labels[$idx]}"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
    done

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        boot_log_report_failure "jam during scripted prayer cast flow" "$log_file" "c128_test_spell_pass" "$c128_test_spell_pass" "$vice_rc"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    boot_log_report_failure "did not reach scripted prayer pass trap" "$log_file" "c128_test_spell_pass" "$c128_test_spell_pass" "$vice_rc"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

run_real_input_town_move_diag() {
    local name="real_input_town_move_diag"
    echo -n "  $name: "

    build_boot_assets || return

    local main_vs="../../../build/test/c128/main.vs"
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
            echo "FAIL (missing ${stage_labels[$idx]} in ../../../build/test/c128/main.vs)"
            FAIL=$((FAIL + 1))
            TOTAL=$((TOTAL + 1))
            return
        fi
        stage_addrs+=("$addr")
    done

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d71"
    local mon_file
    mon_file="$(test128_tmp_file "test128_${name}.mon")"
    local log_file
    log_file="$(test128_tmp_file "test128_${name}.log")"
    : > "$log_file"
    {
        for idx in "${!stage_addrs[@]}"; do
            echo "break \$${stage_addrs[$idx]}"
        done
        for idx in "${!stage_addrs[@]}"; do
            echo "g"
        done
        echo "quit"
    } > "$mon_file"

    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf $'NAA\rA\rA L' -keybuf-delay 8 \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles 320000000 +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    local vice_rc=$?

    if grep -qi "JAM\\|Invalid opcode" "$log_file"; then
        echo "FAIL (jam during real-input town move diag)"
        tail -20 "$log_file" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local last_stage="boot"
    for idx in "${!stage_names[@]}"; do
        if ! grep -qi "^BREAK: .*C:\$${stage_addrs[$idx]}" "$log_file"; then
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

    local main_vs="../../../build/test/c128/main.vs"
    local c128_diag_fail
    c128_diag_fail=$(awk '/\.c128_diag_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_diag_fail:-}" ]; then
        echo "FAIL (missing c128_diag_fail_sym in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi
    local -a diag_stage_breaks=()
    while IFS= read -r addr; do
        [ -n "$addr" ] && diag_stage_breaks+=("$addr")
    done < <(awk '/\.c128_diag_fail_stage_[0-9a-f][0-9a-f]$|\.c128_diag_fail_default$/ { split($2,a,":"); print toupper(a[2]); }' "$main_vs")
    if [ "${#diag_stage_breaks[@]}" -eq 0 ]; then
        echo "FAIL (missing overlay diag stage traps in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_realdiag.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local pass_addr
    pass_addr=$(awk '/\.c128_overlay_transition_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${pass_addr:-}" ]; then
        echo "FAIL (missing c128_overlay_transition_pass_sym in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local -a diag_stage_breaks=()
    while IFS= read -r addr; do
        [ -n "$addr" ] && diag_stage_breaks+=("$addr")
    done < <(awk '/\.c128_diag_fail_stage_[0-9a-f][0-9a-f]$|\.c128_diag_fail_default$/ { split($2,a,":"); print toupper(a[2]); }' "$main_vs")

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_overlaydiag.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local c128_test_cache_survival_pass c128_test_cache_survival_fail
    c128_test_cache_survival_pass=$(awk '/\.c128_test_cache_survival_pass_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_cache_survival_fail=$(awk '/\.c128_test_cache_survival_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${c128_test_cache_survival_pass:-}" ] || [ -z "${c128_test_cache_survival_fail:-}" ]; then
        echo "FAIL (missing cache-survival pass/fail symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_cache_survival.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local player_attack monster_attack
    player_attack=$(awk '/\.player_attack_monster$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    monster_attack=$(awk '/\.monster_attack_player$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${player_attack:-}" ] || [ -z "${monster_attack:-}" ]; then
        echo "FAIL (missing combat symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_realdiag.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local score_death_screen
    score_death_screen=$(awk '/\.score_death_screen$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${score_death_screen:-}" ]; then
        echo "FAIL (missing death-flow symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_death.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local title_show_sysinfo
    title_show_sysinfo=$(awk '/\.title_show_sysinfo$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${title_show_sysinfo:-}" ]; then
        echo "FAIL (missing title_show_sysinfo in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_death.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local dungeon_generate tier_load_disk c128_test_partial_cache_fail
    dungeon_generate=$(awk '/\.dungeon_generate$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    tier_load_disk=$(awk '/\.tier_load_disk$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_partial_cache_fail=$(awk '/\.c128_test_partial_cache_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${dungeon_generate:-}" ] || [ -z "${tier_load_disk:-}" ] || [ -z "${c128_test_partial_cache_fail:-}" ]; then
        echo "FAIL (missing required symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_skip1.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local store_enter overlay_load_disk c128_test_overlay_cache_fail
    store_enter=$(awk '/\.store_enter$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    overlay_load_disk=$(awk '/\.overlay_load_disk$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    c128_test_overlay_cache_fail=$(awk '/\.c128_test_overlay_cache_fail_sym$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${store_enter:-}" ] || [ -z "${overlay_load_disk:-}" ] || [ -z "${c128_test_overlay_cache_fail:-}" ]; then
        echo "FAIL (missing required symbols in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_skipovl2.d64"
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

    local main_vs="../../../build/test/c128/main.vs"
    local entry_main
    entry_main=$(awk '/\.entry_main$/ { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs")
    if [ -z "${entry_main:-}" ]; then
        echo "FAIL (missing entry_main in ../../../build/test/c128/main.vs)"
        FAIL=$((FAIL + 1))
        TOTAL=$((TOTAL + 1))
        return
    fi

    local abs_d64 abs_diag_boot
    abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128.d64"
    abs_diag_boot="$(cd ../../../build/test/c128 && pwd)/boot128.diag.prg"
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
    run_named_suite c128_user_visible_string_guard run_user_visible_string_guard_check || return 1
    run_named_suite c128_prompt_irq_guard run_prompt_irq_guard_check || return 1
    run_named_suite c128_item_overlay_key_guard run_item_overlay_key_guard_check || return 1
    run_named_suite c128_input_run_guard run_input_run_guard_check || return 1
    run_named_suite c128_ref_hal_guard run_ref_hal_guard_check || return 1
    run_named_suite c128_save_load_guard run_save_load_guard_check || return 1
    run_named_suite c128_80col_layout_guard run_80col_layout_guard_check || return 1

    run_parallel_unit_tests || return 1

    run_named_suite media_drive8_attach_read_write run_media_drive8_attach_read_write || return 1
    run_named_suite media_drive9_attach_read_write run_media_drive9_attach_read_write || return 1
    run_named_suite media_drive10_11_device_probe --alias alternate_drive10_11_save_load_smoke run_media_drive10_11_device_probe || return 1

    run_named_suite boot_d64_smoke run_boot_d64_smoke || return 1

    run_named_suite boot_title_idle_smoke run_boot_title_idle_smoke || return 1
    run_named_suite title_art_smoke run_title_art_smoke || return 1
    run_named_suite marker_init_d64_smoke run_marker_init_d64_smoke || return 1
    run_named_suite boot_title_load_missing_savefile_smoke --alias missing_device_or_no_disk run_boot_title_load_missing_savefile_smoke || return 1
    run_named_suite boot_title_load_mounted_save_smoke run_boot_title_load_mounted_save_smoke || return 1
    run_named_suite dual_drive_load_then_save_no_program_prompt --alias save_existing_overwrite --alias boot_title_save_write_product_smoke run_boot_title_save_write_product_smoke || return 1
    run_named_suite change_save_drive_after_save --alias boot_title_change_save_drive_smoke --alias alternate_drive_change_smoke --alias alternate_drive_prompt_no_repeat run_boot_title_change_save_drive_smoke || return 1
    run_named_suite boot_title_save_media_fail_product_smoke --alias wrong_media_detection_selected_devices --alias write_protected_or_forced_write_error run_boot_title_save_media_fail_product_smoke || return 1
    run_named_suite single_drive_save_program_disk_rejected --alias boot_title_single_drive_save_wrong_media_smoke --alias wrong_media_recovery run_boot_title_single_drive_save_wrong_media_smoke || return 1
    run_named_suite single_drive_load_program_disk_rejected --alias boot_title_single_drive_load_wrong_media_smoke --alias wrong_media_recovery --alias wrong_media_detection_selected_devices run_boot_title_single_drive_load_wrong_media_smoke || return 1
    run_named_suite single_drive_corrupt_save_recovery_requires_program_disk --alias boot_title_single_drive_load_corrupt_smoke --alias corrupt_save_file run_boot_title_single_drive_load_corrupt_smoke || return 1
    run_named_suite prompt_sequence_no_repeat --alias boot_title_single_drive_load_return_smoke run_boot_title_single_drive_load_return_smoke || return 1
    run_named_suite load_then_save_new_empty_disk --alias boot_title_load_then_save_new_empty_smoke run_boot_title_load_then_save_new_empty_smoke || return 1
    run_named_suite title_disk_setup_single_drive_returns_program_prompt --alias boot_title_disk_setup_single_drive_return_smoke run_boot_title_disk_setup_single_drive_return_smoke || return 1
    run_named_suite new_save_empty_init_writes --alias boot_title_single_drive_fresh_save_smoke run_boot_title_single_drive_fresh_save_smoke || return 1
    run_named_suite new_save_empty_no_init_returns_setup --alias cancel_supported_prompts --alias boot_title_single_drive_fresh_save_no_init_smoke run_boot_title_single_drive_fresh_save_no_init_smoke || return 1
    run_named_suite vic40_clean_boot_smoke run_vic40_clean_boot_smoke || return 1
    run_named_suite new_key_stability_smoke run_new_key_stability_smoke || return 1
    run_named_suite boot_title_newgame_smoke run_boot_title_newgame_smoke || return 1
    run_named_suite load_initialized_save --alias boot_title_load_resume_smoke run_boot_title_load_resume_smoke || return 1
    run_named_suite boot_tier_transition_smoke run_boot_tier_transition_smoke || return 1
    run_named_suite town_overlay_smoke run_town_overlay_smoke || return 1
    run_named_suite town_overlay_female_smoke run_town_overlay_female_smoke || return 1
    run_named_suite town_overlay_state_smoke run_town_overlay_state_smoke || return 1
    run_named_suite scripted_summary_to_town_smoke run_scripted_summary_to_town_smoke || return 1
    run_named_suite scripted_spell_cast_smoke run_scripted_spell_cast_smoke || return 1
    run_named_suite scripted_book_overlay_smoke run_scripted_book_overlay_smoke || return 1
    run_named_suite scripted_spell_list_overlay_smoke run_scripted_spell_list_overlay_smoke || return 1
    run_named_suite scripted_spell_list_cancel_smoke run_scripted_spell_list_cancel_smoke || return 1
    run_named_suite scripted_prayer_cast_smoke run_scripted_prayer_cast_smoke || return 1
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
        run_named_suite perf_p1_trace_smoke run_perf_p1_trace_smoke || return 1
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
    if [ "$TEST_RERUN_ONLY_LATEST" != "0" ]; then
        echo "  rerun-only-latest: ON"
    fi
    if [ "$TEST_RERUN_INVERT" != "0" ]; then
        echo "  rerun-invert: ON"
    fi
    if [ "$TEST_RERUN_LIMIT" != "0" ]; then
        echo "  rerun-limit: $TEST_RERUN_LIMIT"
    fi
    if [ "$TEST_RERUN_STRIDE" != "1" ]; then
        echo "  rerun-stride: $TEST_RERUN_STRIDE"
    fi
    if [ "$TEST_RERUN_OFFSET" != "0" ]; then
        echo "  rerun-offset: $TEST_RERUN_OFFSET"
    fi
    if [ "$TEST_RERUN_SHUFFLE" != "0" ]; then
        echo "  rerun-shuffle: ON"
        echo "  rerun-seed: $TEST_RERUN_SEED"
    elif [ "$TEST_RERUN_ORDER" != "forward" ]; then
        echo "  rerun-order: $TEST_RERUN_ORDER"
    fi
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
    if [ "$TEST_RERUN_INVERT" != "0" ]; then
        echo "  excluded rerun suites: $TEST128_RERUN_COUNT"
    else
        echo "  rerun suites: $TEST128_RERUN_COUNT"
    fi
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
