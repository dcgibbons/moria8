#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMODORE_MAKE=(make -s -C "$SCRIPT_DIR/..")
KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
C1541_BIN="${C1541:-c1541}"

build_log="/tmp/town_self_dump_build.log"
diag_main="../../../build/test/c128/moria128.selfdump.prg"
diag_d64="../../../build/test/c128/moria128_selfdump.d64"
screenshot_file="/tmp/town_self_dump.png"
mon_file="/tmp/town_self_dump_go.mon"
target="${TOWN_DUMP_TARGET:-112}"

if ! "${COMMODORE_MAKE[@]}" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "town_self_dump build128/disk128 failed"
    tail -20 "$build_log"
    exit 1
fi

if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
        -define C128 :OVL_OUT=../../../build/test/c128 -define C128_TEST_TOWN_SELF_DUMP \
        -define C128_TEST_TOWN_SELF_DUMP_TARGET="$target" \
        -o "$diag_main" >>"$build_log" 2>&1; then
    echo "town_self_dump assembly failed"
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
    echo "town_self_dump disk build failed"
    tail -20 "$build_log"
    exit 1
fi

rm -f "$screenshot_file"
printf 'g\n' > "$mon_file"
abs_d64="$(cd ../../../build/test/c128 && pwd)/moria128_selfdump.d64"

set +e
"$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
    -keybuf $'NAA\rA\rA LAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA>' -keybuf-delay 6 \
    -moncommands "$mon_file" -limitcycles 900000000 \
    -exitscreenshot "$screenshot_file" +sound -sounddev dummy \
    +remotemonitor +binarymonitor >/dev/null 2>&1
rc=$?
set -e

echo "RC=$rc"
echo "TARGET=$target"
ls -l "$screenshot_file"
