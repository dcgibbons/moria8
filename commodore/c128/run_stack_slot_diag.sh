#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-x128}"
C1541_BIN="${C1541:-c1541}"

build_log="/tmp/stack_slot_diag_build.log"
diag_main="out/moria128.stackslot.prg"
diag_d64="out/moria128_stackslot.d64"

if ! make -s build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "stack_slot_diag build128/disk128 failed"
    tail -20 "$build_log"
    exit 1
fi

if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
        -define C128 -define OVL_OUT='"out"' -define C128_TEST_STACK_SLOT_DIAG \
        -o "$diag_main" >>"$build_log" 2>&1; then
    echo "stack_slot_diag assembly failed"
    tail -40 "$build_log"
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
        -write out/runtime_low.prg "runtime_low.prg" >>"$build_log" 2>&1; then
    echo "stack_slot_diag disk build failed"
    tail -20 "$build_log"
    exit 1
fi

abs_d64="$(cd out && pwd)/moria128_stackslot.d64"
echo "Launch this image: $abs_d64"
exec "$VICE" -80col -drive8truedrive -drive8type 1541 +iecdevice8 \
    -sound -sounddev coreaudio -autostart "$abs_d64"
