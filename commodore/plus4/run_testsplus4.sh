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

run_test "minimalplus4" "tests/test_minimalplus4.s"

echo "=== Plus/4 runtime summary: $PASS passed, $FAIL failed, $TOTAL total ==="
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
