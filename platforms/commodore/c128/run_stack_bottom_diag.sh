#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
COMMODORE_MAKE=(make -s -C "$SCRIPT_DIR/..")

KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-x128}"
C1541_BIN="${C1541:-c1541}"

build_log="/tmp/stack_bottom_diag_build.log"
diag_main="../../../build/test/c128/moria128.stackbottom.prg"
diag_d64="../../../build/test/c128/moria128_stackbottom.d64"

if ! "${COMMODORE_MAKE[@]}" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "stack_bottom_diag build128/disk128 failed"
    tail -20 "$build_log"
    exit 1
fi

if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
        -define C128 -define OVL_OUT='"../../../build/test/c128"' -define C128_TEST_STACK_BOTTOM_DIAG \
        -o "$diag_main" >>"$build_log" 2>&1; then
    echo "stack_bottom_diag assembly failed"
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
    echo "stack_bottom_diag disk build failed"
    tail -20 "$build_log"
    exit 1
fi

abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_stackbottom.d64"
echo "Launch this image: $abs_d64"
exec "$VICE" -80col -drive8truedrive -drive8type 1541 +iecdevice8 \
    -sound -sounddev coreaudio -autostart "$abs_d64"
