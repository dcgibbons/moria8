#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMODORE_MAKE=(make -s -C "$SCRIPT_DIR/..")
KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
C1541_BIN="${C1541:-c1541}"

build_log="/tmp/test128_phase1_trace_build.log"
diag_main="out/moria128.realdiag.prg"
diag_d64="out/moria128_realdiag.d64"

make_kickass="/tmp/moria128-kickass.jar"
kickass_abs="$(cd "$(dirname "$KICKASS")" && pwd)/$(basename "$KICKASS")"
ln -sf "$kickass_abs" "$make_kickass"

if ! "${COMMODORE_MAKE[@]}" KICKASS="$make_kickass" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "Phase 1 build128/disk128 failed"
    tail -20 "$build_log"
    exit 1
fi

if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
        -define C128 -var OVL_OUT='"out"' -define C128_TEST_REAL_BOOT_DIAG \
        -define C128_TEST_FORCE_DUNGEON_MELEE -o "$diag_main" >>"$build_log" 2>&1; then
    echo "Phase 1 real-diag assembly failed"
    tail -20 "$build_log"
    exit 1
fi

if ! "$C1541_BIN" -format "moria128,m8" d64 "$diag_d64" \
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
        -write out/128.runtime.prg "128.runtime" >>"$build_log" 2>&1; then
    echo "Phase 1 real-diag disk build failed"
    tail -20 "$build_log"
    exit 1
fi

main_vs="out/main.vs"
abs_d64="$(cd out && pwd)/moria128_realdiag.d64"
keybuf=$'NAA\rA\rA L>'
keybuf_delay=8
limitcycles=320000000

get_addr() {
    local symbol="$1"
    awk -v sym=".$symbol" '$3 == sym { split($2,a,":"); print toupper(a[2]); exit }' "$main_vs"
}

game_new_start="$(get_addr game_new_start)"
tramp_player_create="$(get_addr tramp_player_create)"
player_create="$(get_addr player_create)"
c128_restore_runtime_guards="$(get_addr c128_restore_runtime_guards)"
init_copy_banked="$(get_addr init_copy_banked)"

if [ -z "${game_new_start:-}" ] || [ -z "${tramp_player_create:-}" ] || \
   [ -z "${player_create:-}" ] || [ -z "${c128_restore_runtime_guards:-}" ] || \
   [ -z "${init_copy_banked:-}" ]; then
    echo "Missing required symbols in $main_vs"
    exit 1
fi

run_capture_until() {
    local label="$1"
    local addr="$2"
    local mon_file="/tmp/test128_phase1_${label}.mon"
    local log_file="/tmp/test128_phase1_${label}.log"
    : > "$log_file"
    {
        echo "break \$${addr}"
        echo "g"
        echo "r"
        echo "bt"
        echo "m 01e0 01ff"
        echo "m e80e e84d"
        echo "m 4cf0 4d20"
        echo "x"
    } > "$mon_file"
    set +e
    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "$keybuf" -keybuf-delay "$keybuf_delay" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles "$limitcycles" +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    set -e
    echo "=== ${label} (\$${addr}) ==="
    tail -n 80 "$log_file"
    echo
}

run_capture_jam() {
    local label="jam"
    local mon_file="/tmp/test128_phase1_${label}.mon"
    local log_file="/tmp/test128_phase1_${label}.log"
    : > "$log_file"
    {
        echo "g"
        echo "r"
        echo "bt"
        echo "m 0100 01ff"
        echo "m e80e e84d"
        echo "m 4cf0 4d20"
        echo "x"
    } > "$mon_file"
    set +e
    "$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
        -keybuf "$keybuf" -keybuf-delay "$keybuf_delay" \
        -moncommands "$mon_file" -monlog -monlogname "$log_file" \
        -limitcycles "$limitcycles" +sound -sounddev dummy \
        +remotemonitor +binarymonitor >/dev/null 2>&1
    set -e
    echo "=== final_jam ==="
    tail -n 120 "$log_file"
    echo
}

run_capture_until "game_new_start" "$game_new_start"
run_capture_until "tramp_player_create" "$tramp_player_create"
run_capture_until "init_copy_banked" "$init_copy_banked"
run_capture_until "c128_restore_runtime_guards" "$c128_restore_runtime_guards"
run_capture_until "player_create" "$player_create"
run_capture_jam

echo "Phase 1 logs:"
ls -1 /tmp/test128_phase1_*.log
