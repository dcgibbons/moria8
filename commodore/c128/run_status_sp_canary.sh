#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMODORE_MAKE=(make -s -C "$SCRIPT_DIR/..")
KICKASS="${KICKASS:-../../tools/kickass/KickAss.jar}"
VICE="${VICE128:-/Applications/VICE/bin/x128}"
C1541_BIN="${C1541:-c1541}"

build_log="/tmp/status_sp_canary_build.log"
diag_main="out/moria128.statussp.prg"
diag_d64="out/moria128_statussp.d64"

if ! "${COMMODORE_MAKE[@]}" build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "status_sp_canary build128/disk128 failed"
    tail -20 "$build_log"
    exit 1
fi

if ! java -jar "$KICKASS" main.s -showmem -vicesymbols -libdir ../c64 \
        -define C128 -var OVL_OUT='"out"' -define C128_TEST_STATUS_SP_CANARY \
        -o "$diag_main" >>"$build_log" 2>&1; then
    echo "status_sp_canary assembly failed"
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
        -write out/runtime.low.prg "runtime.low.prg" >>"$build_log" 2>&1; then
    echo "status_sp_canary disk build failed"
    tail -20 "$build_log"
    exit 1
fi

abs_d64="$(cd out && pwd)/moria128_statussp.d64"
trap_addr="$(awk '/\.c128_status_ret_corrupt$/ { split($2,a,":"); print toupper(a[2]); exit }' out/main.vs)"
if [ -z "${trap_addr:-}" ]; then
    echo "status_sp_canary missing c128_status_ret_corrupt symbol"
    exit 1
fi
mon_file="/tmp/status_sp_canary.mon"
log_file="/tmp/status_sp_canary.log"

cat >"$mon_file" <<EOF
break \$${trap_addr}
break \$4d00
g
r
m 0100 01ff
m 3ef8 3f10
x
EOF

set +e
"$VICE" -console -nativemonitor -warp -80col -autostart "$abs_d64" \
    -keybuf $'NAA\rA\rA' -keybuf-delay 8 \
    -moncommands "$mon_file" -monlog -monlogname "$log_file" \
    -limitcycles 320000000 +sound -sounddev dummy \
    +remotemonitor +binarymonitor >/dev/null 2>&1
rc=$?
set -e

echo "RC=$rc"
tail -n 120 "$log_file"
