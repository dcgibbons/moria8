#!/bin/bash
# run_testsplus4.sh — Assemble and run Plus/4 runtime smoke tests in VICE.

set -u

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PLUS4_DIR="${PLUS4_DIR:-$REPO_ROOT/commodore/plus4}"
cd "$PLUS4_DIR"

KICKASS="${KICKASS:-$REPO_ROOT/tools/kickass/KickAss.jar}"
case "$KICKASS" in
    /*) ;;
    *) KICKASS="$(pwd)/$KICKASS" ;;
esac

make -s -C "$REPO_ROOT/commodore" KICKASS="$KICKASS" ensure-kickass || exit 1

if [ -n "${VICEPLUS4:-}" ]; then
    VICE="$VICEPLUS4"
elif command -v xplus4 >/dev/null 2>&1; then
    VICE="$(command -v xplus4)"
elif [ -x /opt/homebrew/bin/xplus4 ]; then
    VICE="/opt/homebrew/bin/xplus4"
else
    VICE="/Applications/VICE/bin/xplus4"
fi

C1541="${C1541:-}"
if [ -z "$C1541" ]; then
    if command -v c1541 >/dev/null 2>&1; then
        C1541="$(command -v c1541)"
    elif [ -x /opt/homebrew/bin/c1541 ]; then
        C1541="/opt/homebrew/bin/c1541"
    else
        C1541="/Applications/VICE/bin/c1541"
    fi
fi

TEST_FILTER="${TEST_FILTER:-}"
PASS=0
FAIL=0
TOTAL=0

run_test() {
    local name="$1"
    local source="$2"
    local prg="${source%.s}.prg"
    local vs="${source%.s}.vs"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    java -jar "$KICKASS" "$source" -libdir "$REPO_ROOT/commodore/c64" -define PLUS4 -vicesymbols -o "$prg" >/dev/null || {
        echo "FAIL: $name (assembly)"
        FAIL=$((FAIL + 1))
        return
    }

    if python3 -u ./harnessplus4.py --name "$name" --prg "$prg" --vs "$vs" --vice "$VICE" --timeout 5 --connect-timeout 12; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_marker_init_smoke() {
    local name="marker_init_plus4"
    local out_dir="$PLUS4_DIR/out"
    local save_d64="$out_dir/test-marker-init-save.d64"
    local main_vs="$REPO_ROOT/commodore/out/plus4/main.vs"
    local boot_d64="$REPO_ROOT/commodore/out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" KICKASS="$KICKASS" out/plus4/moria4.prg >"$build_log" 2>&1 || \
       ! make -s -C "$REPO_ROOT/commodore" KICKASS="$KICKASS" diskplus4 >>"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u ./harnessplus4.py \
        --mode marker-init-smoke \
        --name "$name" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --save-device 9 \
        --vice "$VICE" \
        --timeout 30 \
        --connect-timeout 12 \
        --vice-arg=-drive8truedrive \
        --vice-arg=-drive8type \
        --vice-arg=1541 \
        --vice-arg=-drive9truedrive \
        --vice-arg=-drive9type \
        --vice-arg=1541; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_test "minimalplus4" "tests/test_minimalplus4.s"
run_marker_init_smoke

echo "=== Plus/4 runtime summary: $PASS passed, $FAIL failed, $TOTAL total ==="
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
