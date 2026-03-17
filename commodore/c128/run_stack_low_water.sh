#!/usr/bin/env bash
# Incident-scoped diagnostic runner for C128 preload/stack failures.
# Keep as a transient debug tool; do not treat its layout as architectural truth.
set -euo pipefail

cd "$(dirname "$0")"

VICE="${VICE128:-x128}"
C1541_BIN="${C1541:-c1541}"
JAVA_BIN="${JAVA:-java}"
KICKASS_JAR="${KICKASS:-../../tools/kickass/KickAss.jar}"

out_dir="out"
diag_main="$out_dir/moria128.stacklow.prg"
diag_d64="$out_dir/moria128_stacklow.d64"
build_log="/tmp/moria128_stacklow_build.log"

mkdir -p "$out_dir"

if ! make -s build128 disk128 >"$build_log" 2>&1 || grep -q "FAILED!" "$build_log"; then
    echo "stack_low_water build128/disk128 failed"
    cat "$build_log"
    exit 1
fi

if ! "$JAVA_BIN" -jar "$KICKASS_JAR" main.s -showmem -vicesymbols -libdir ../c64 \
        -define C128 -define OVL_OUT='"out"' -define C128_TEST_STACK_LOW_WATER \
        -define C128_TEST_OVERLAY_LOAD_FAIL_TRAP -define C128_TEST_OVERLAY_FN_GUARD \
        -o "$diag_main" >/tmp/moria128_stacklow_kickass.log 2>&1; then
    echo "stack_low_water KickAssembler build failed"
    cat /tmp/moria128_stacklow_kickass.log
    exit 1
fi

if ! "$C1541_BIN" -format "moria128,m8" d64 "$diag_d64" \
        -attach "$diag_d64" \
        -write "$out_dir/boot128.prg" "moria8.128" \
        -write "$diag_main" "moria128" \
        -write "$out_dir/title" "title" \
        -write "$out_dir/monster.db.1" "monster.db.1" \
        -write "$out_dir/monster.db.2" "monster.db.2" \
        -write "$out_dir/monster.db.3" "monster.db.3" \
        -write "$out_dir/monster.db.4" "monster.db.4" \
        -write "$out_dir/ovl.town" "ovl.town" \
        -write "$out_dir/ovl.start" "ovl.start" \
        -write "$out_dir/ovl.death" "ovl.death" \
        -write "$out_dir/ovl.gen" "ovl.gen" \
        -write "$out_dir/bank1.dat" "bank1.dat" >/tmp/moria128_stacklow_c1541.log 2>&1; then
    echo "stack_low_water d64 creation failed"
    cat /tmp/moria128_stacklow_c1541.log
    exit 1
fi

abs_d64="$(cd "$out_dir" && pwd)/moria128_stacklow.d64"
echo "Launching: $abs_d64"
"$VICE" -80col -drive8truedrive -drive8type 1541 +iecdevice8 \
    -sound -sounddev coreaudio -autostart "$abs_d64"
