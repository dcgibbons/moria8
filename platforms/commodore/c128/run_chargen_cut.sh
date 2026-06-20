#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
COMMODORE_MAKE=(make -s -C "$SCRIPT_DIR/..")

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-x128}"
C1541_BIN="${C1541:-c1541}"

build_log="/tmp/chargen_cut_build.log"
diag_main="../../../build/test/c128/moria128.chargen_cut.prg"
diag_d64="../../../build/test/c128/moria128_chargen_cut.d64"
cutpoint="${CUTPOINT:--1}"
skip_overlay="${SKIP_OVERLAY:-0}"
skip_summary="${SKIP_SUMMARY:-0}"
skip_call="${SKIP_CALL:-0}"
skip_guards="${SKIP_GUARDS:-0}"
final_return_diag="${FINAL_RETURN_DIAG:-0}"

if ! "${COMMODORE_MAKE[@]}" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "chargen_cut build128/disk128 failed"
    tail -20 "$build_log"
    exit 1
fi

ka_args=(
    -showmem -vicesymbols -libdir ../c64
    -define C128
    -define OVL_OUT='"../../../build/test/c128"'
    -define C128_TEST_CHARGEN_CUTPOINT="$cutpoint"
)

if [ "$skip_overlay" = "1" ]; then
    ka_args+=(-define C128_TEST_SKIP_PLAYER_CREATE_OVERLAY)
fi

if [ "$skip_summary" = "1" ]; then
    ka_args+=(-define C128_TEST_SKIP_PLAYER_SUMMARY)
fi

if [ "$skip_call" = "1" ]; then
    ka_args+=(-define C128_TEST_SKIP_PLAYER_CREATE_CALL)
fi

if [ "$skip_guards" = "1" ]; then
    ka_args+=(-define C128_TEST_SKIP_PLAYER_CREATE_GUARDS)
fi

if [ "$final_return_diag" = "1" ]; then
    ka_args+=(-define C128_TEST_FINAL_RETURN_DIAG)
fi

if ! java -jar "$KICKASS" main.s "${ka_args[@]}" -o "$diag_main" >>"$build_log" 2>&1; then
    echo "chargen_cut assembly failed"
    tail -40 "$build_log"
    exit 1
fi

if ! "$C1541_BIN" -format "moria128,m8" d64 "$diag_d64" \
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
        -write ../../../build/test/c128/128.fdisk.prg "128.fdisk" \
        -write ../../../build/test/c128/128.bank.prg "128.bank" >>"$build_log" 2>&1; then
    echo "chargen_cut disk build failed"
    tail -20 "$build_log"
    exit 1
fi

abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_chargen_cut.d64"
echo "CUTPOINT=$cutpoint SKIP_OVERLAY=$skip_overlay SKIP_SUMMARY=$skip_summary SKIP_CALL=$skip_call SKIP_GUARDS=$skip_guards FINAL_RETURN_DIAG=$final_return_diag"
echo "Launching: $abs_d64"
exec "$VICE" -80col -drive8truedrive -drive8type 1541 +iecdevice8 \
    -sound -sounddev coreaudio -autostart "$abs_d64"
