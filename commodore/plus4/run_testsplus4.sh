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

run_boot_title_smoke() {
    local name="boot_title_plus4"
    local out_dir="$PLUS4_DIR/out"
    local smoke_out_rel="plus4/out/product-boot-title-smoke"
    local smoke_out="$PLUS4_DIR/out/product-boot-title-smoke"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-boot-title-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4" \
        "$smoke_out_rel/plus4/moria4.prg" \
        "$smoke_out_rel/plus4/title" \
        "$smoke_out_rel/plus4/monster.db.1" \
        "$smoke_out_rel/plus4/monster.db.2" \
        "$smoke_out_rel/plus4/monster.db.3" \
        "$smoke_out_rel/plus4/monster.db.4" >"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$C1541" -format "moria8 plus4,m8" d64 "$boot_d64" \
        -attach "$boot_d64" \
        -write "$smoke_plus4/moria4.prg" "moria8" \
        -write "$smoke_plus4/moria4.prg" "moria4" \
        -write "$smoke_plus4/title" "t64" \
        -write "$smoke_plus4/monster.db.1" "monster.db.1" \
        -write "$smoke_plus4/monster.db.2" "monster.db.2" \
        -write "$smoke_plus4/monster.db.3" "monster.db.3" \
        -write "$smoke_plus4/monster.db.4" "monster.db.4" \
        -write "$smoke_plus4/ovl.start" "4.start" \
        -write "$smoke_plus4/ovl.town" "4.town" \
        -write "$smoke_plus4/ovl.death" "4.death" \
        -write "$smoke_plus4/ovl.gen" "4.gen" \
        -write "$smoke_plus4/ovl.help" "4.help" \
        -write "$smoke_plus4/ovl.ui" "4.ui" \
        -write "$smoke_plus4/ovl.items" "4.items" \
        -write "$smoke_plus4/ovl.spell" "4.spell" \
        -write "$smoke_plus4/4.bank" "4.bank" >/dev/null; then
        echo "FAIL: $name (product disk image)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".title_menu_loop" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --vice "$VICE"; then
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

run_disk_setup_product_smoke() {
    local name="disk_setup_product_plus4"
    local out_dir="$PLUS4_DIR/out"
    local smoke_out_rel="plus4/out/product-smoke"
    local smoke_out="$PLUS4_DIR/out/product-smoke"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-disk-setup-product-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_DISK_SETUP_PRODUCT" \
        "$smoke_out_rel/plus4/moria4.prg" \
        "$smoke_out_rel/plus4/title" \
        "$smoke_out_rel/plus4/monster.db.1" \
        "$smoke_out_rel/plus4/monster.db.2" \
        "$smoke_out_rel/plus4/monster.db.3" \
        "$smoke_out_rel/plus4/monster.db.4" >"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$C1541" -format "moria8 plus4,m8" d64 "$boot_d64" \
        -attach "$boot_d64" \
        -write "$smoke_plus4/moria4.prg" "moria8" \
        -write "$smoke_plus4/moria4.prg" "moria4" \
        -write "$smoke_plus4/title" "t64" \
        -write "$smoke_plus4/monster.db.1" "monster.db.1" \
        -write "$smoke_plus4/monster.db.2" "monster.db.2" \
        -write "$smoke_plus4/monster.db.3" "monster.db.3" \
        -write "$smoke_plus4/monster.db.4" "monster.db.4" \
        -write "$smoke_plus4/ovl.start" "4.start" \
        -write "$smoke_plus4/ovl.town" "4.town" \
        -write "$smoke_plus4/ovl.death" "4.death" \
        -write "$smoke_plus4/ovl.gen" "4.gen" \
        -write "$smoke_plus4/ovl.help" "4.help" \
        -write "$smoke_plus4/ovl.ui" "4.ui" \
        -write "$smoke_plus4/ovl.items" "4.items" \
        -write "$smoke_plus4/ovl.spell" "4.spell" \
        -write "$smoke_plus4/4.bank" "4.bank" >/dev/null; then
        echo "FAIL: $name (product disk image)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/disk_setup_product_smoke.py \
        --vice "$VICE" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --main-vs "$main_vs"; then
        if "$C1541" -attach "$save_d64" -list 2>/dev/null | grep -qi '"MORIA4.ID".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (save marker not present)"
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_disk_setup_missing_save_smoke() {
    local name="disk_setup_missing_save_plus4"
    local out_dir="$PLUS4_DIR/out"
    local smoke_out_rel="plus4/out/product-missing-save-smoke"
    local smoke_out="$PLUS4_DIR/out/product-missing-save-smoke"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_DISK_SETUP_PRODUCT" \
        "$smoke_out_rel/plus4/moria4.prg" \
        "$smoke_out_rel/plus4/title" \
        "$smoke_out_rel/plus4/monster.db.1" \
        "$smoke_out_rel/plus4/monster.db.2" \
        "$smoke_out_rel/plus4/monster.db.3" \
        "$smoke_out_rel/plus4/monster.db.4" >"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$C1541" -format "moria8 plus4,m8" d64 "$boot_d64" \
        -attach "$boot_d64" \
        -write "$smoke_plus4/moria4.prg" "moria8" \
        -write "$smoke_plus4/moria4.prg" "moria4" \
        -write "$smoke_plus4/title" "t64" \
        -write "$smoke_plus4/monster.db.1" "monster.db.1" \
        -write "$smoke_plus4/monster.db.2" "monster.db.2" \
        -write "$smoke_plus4/monster.db.3" "monster.db.3" \
        -write "$smoke_plus4/monster.db.4" "monster.db.4" \
        -write "$smoke_plus4/ovl.start" "4.start" \
        -write "$smoke_plus4/ovl.town" "4.town" \
        -write "$smoke_plus4/ovl.death" "4.death" \
        -write "$smoke_plus4/ovl.gen" "4.gen" \
        -write "$smoke_plus4/ovl.help" "4.help" \
        -write "$smoke_plus4/ovl.ui" "4.ui" \
        -write "$smoke_plus4/ovl.items" "4.items" \
        -write "$smoke_plus4/ovl.spell" "4.spell" \
        -write "$smoke_plus4/4.bank" "4.bank" >/dev/null; then
        echo "FAIL: $name (product disk image)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/disk_setup_product_smoke.py \
        --vice "$VICE" \
        --boot-d64 "$boot_d64" \
        --main-vs "$main_vs" \
        --expect init-fail \
        --expect-dos-code 74 \
        --expect-phase 0x83 \
        --expect-disk-status 74; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_save_write_product_smoke() {
    local name="save_write_product_plus4"
    local out_dir="$PLUS4_DIR/out"
    local smoke_out_rel="plus4/out/product-save-write-smoke"
    local smoke_out="$PLUS4_DIR/out/product-save-write-smoke"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-save-write-product-save.d64"
    local save_blob="$out_dir/P4.THE.GAME"
    local marker_blob="$out_dir/MORIA4.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT" \
        "$smoke_out_rel/plus4/moria4.prg" \
        "$smoke_out_rel/plus4/title" \
        "$smoke_out_rel/plus4/monster.db.1" \
        "$smoke_out_rel/plus4/monster.db.2" \
        "$smoke_out_rel/plus4/monster.db.3" \
        "$smoke_out_rel/plus4/monster.db.4" >"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$C1541" -format "moria8 plus4,m8" d64 "$boot_d64" \
        -attach "$boot_d64" \
        -write "$smoke_plus4/moria4.prg" "moria8" \
        -write "$smoke_plus4/moria4.prg" "moria4" \
        -write "$smoke_plus4/title" "t64" \
        -write "$smoke_plus4/monster.db.1" "monster.db.1" \
        -write "$smoke_plus4/monster.db.2" "monster.db.2" \
        -write "$smoke_plus4/monster.db.3" "monster.db.3" \
        -write "$smoke_plus4/monster.db.4" "monster.db.4" \
        -write "$smoke_plus4/ovl.start" "4.start" \
        -write "$smoke_plus4/ovl.town" "4.town" \
        -write "$smoke_plus4/ovl.death" "4.death" \
        -write "$smoke_plus4/ovl.gen" "4.gen" \
        -write "$smoke_plus4/ovl.help" "4.help" \
        -write "$smoke_plus4/ovl.ui" "4.ui" \
        -write "$smoke_plus4/ovl.items" "4.items" \
        -write "$smoke_plus4/ovl.spell" "4.spell" \
        -write "$smoke_plus4/4.bank" "4.bank" >/dev/null; then
        echo "FAIL: $name (product disk image)"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! python3 tests/make_load_resume_save_plus4.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL: $name (save generation)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$save_blob" "p4.the.game,seq" \
        -write "$marker_blob" "moria4.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_save_overwrite_prompt" \
        --pass-symbol ".plus4_test_after_save_game" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --vice "$VICE"; then
        if "$C1541" -attach "$save_d64" -list 2>/dev/null | grep -qi '"P4.THE.GAME".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (save file not present)"
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_load_wrong_media_product_smoke() {
    local name="load_wrong_media_product_plus4"
    local out_dir="$PLUS4_DIR/out"
    local smoke_out_rel="plus4/out/product-load-wrong-media-smoke"
    local smoke_out="$PLUS4_DIR/out/product-load-wrong-media-smoke"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-load-wrong-media-product-save.d64"
    local marker_blob="$out_dir/WRONG.MORIA4.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_LOAD_WRONG_MEDIA_PRODUCT" \
        "$smoke_out_rel/plus4/moria4.prg" \
        "$smoke_out_rel/plus4/title" \
        "$smoke_out_rel/plus4/monster.db.1" \
        "$smoke_out_rel/plus4/monster.db.2" \
        "$smoke_out_rel/plus4/monster.db.3" \
        "$smoke_out_rel/plus4/monster.db.4" >"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$C1541" -format "moria8 plus4,m8" d64 "$boot_d64" \
        -attach "$boot_d64" \
        -write "$smoke_plus4/moria4.prg" "moria8" \
        -write "$smoke_plus4/moria4.prg" "moria4" \
        -write "$smoke_plus4/title" "t64" \
        -write "$smoke_plus4/monster.db.1" "monster.db.1" \
        -write "$smoke_plus4/monster.db.2" "monster.db.2" \
        -write "$smoke_plus4/monster.db.3" "monster.db.3" \
        -write "$smoke_plus4/monster.db.4" "monster.db.4" \
        -write "$smoke_plus4/ovl.start" "4.start" \
        -write "$smoke_plus4/ovl.town" "4.town" \
        -write "$smoke_plus4/ovl.death" "4.death" \
        -write "$smoke_plus4/ovl.gen" "4.gen" \
        -write "$smoke_plus4/ovl.help" "4.help" \
        -write "$smoke_plus4/ovl.ui" "4.ui" \
        -write "$smoke_plus4/ovl.items" "4.items" \
        -write "$smoke_plus4/ovl.spell" "4.spell" \
        -write "$smoke_plus4/4.bank" "4.bank" >/dev/null; then
        echo "FAIL: $name (product disk image)"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! python3 -c 'from pathlib import Path; import sys; Path(sys.argv[1]).write_bytes(b"BADP4!")' "$marker_blob"; then
        echo "FAIL: $name (wrong marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "wrong save,m8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria4.id,seq" >/dev/null; then
        echo "FAIL: $name (wrong save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".plus4_test_load_media_fail" \
        --fail-symbol ".main_loop" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_load_resume_product_smoke() {
    local name="load_resume_product_plus4"
    local out_dir="$PLUS4_DIR/out"
    local smoke_out_rel="plus4/out/product-load-resume-smoke"
    local smoke_out="$PLUS4_DIR/out/product-load-resume-smoke"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-load-resume-product-save.d64"
    local save_blob="$out_dir/P4.THE.GAME"
    local marker_blob="$out_dir/MORIA4.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if [ -n "$TEST_FILTER" ] && [[ ! "$name" =~ $TEST_FILTER ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT" \
        "$smoke_out_rel/plus4/moria4.prg" \
        "$smoke_out_rel/plus4/title" \
        "$smoke_out_rel/plus4/monster.db.1" \
        "$smoke_out_rel/plus4/monster.db.2" \
        "$smoke_out_rel/plus4/monster.db.3" \
        "$smoke_out_rel/plus4/monster.db.4" >"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$boot_d64"
    if ! "$C1541" -format "moria8 plus4,m8" d64 "$boot_d64" \
        -attach "$boot_d64" \
        -write "$smoke_plus4/moria4.prg" "moria8" \
        -write "$smoke_plus4/moria4.prg" "moria4" \
        -write "$smoke_plus4/title" "t64" \
        -write "$smoke_plus4/monster.db.1" "monster.db.1" \
        -write "$smoke_plus4/monster.db.2" "monster.db.2" \
        -write "$smoke_plus4/monster.db.3" "monster.db.3" \
        -write "$smoke_plus4/monster.db.4" "monster.db.4" \
        -write "$smoke_plus4/ovl.start" "4.start" \
        -write "$smoke_plus4/ovl.town" "4.town" \
        -write "$smoke_plus4/ovl.death" "4.death" \
        -write "$smoke_plus4/ovl.gen" "4.gen" \
        -write "$smoke_plus4/ovl.help" "4.help" \
        -write "$smoke_plus4/ovl.ui" "4.ui" \
        -write "$smoke_plus4/ovl.items" "4.items" \
        -write "$smoke_plus4/ovl.spell" "4.spell" \
        -write "$smoke_plus4/4.bank" "4.bank" >/dev/null; then
        echo "FAIL: $name (product disk image)"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! python3 tests/make_load_resume_save_plus4.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL: $name (save generation)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,m8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$save_blob" "p4.the.game,seq" \
        -write "$marker_blob" "moria4.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".main_loop" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_test "minimalplus4" "tests/test_minimalplus4.s"
run_boot_title_smoke
run_disk_setup_product_smoke
run_disk_setup_missing_save_smoke
run_load_wrong_media_product_smoke
run_save_write_product_smoke
run_load_resume_product_smoke

echo "=== Plus/4 runtime summary: $PASS passed, $FAIL failed, $TOTAL total ==="
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
