#!/bin/bash
# run_testsplus4.sh — Assemble and run Plus/4 runtime smoke tests in VICE.

set -u

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

java() {
    if [ "$1" = "-jar" ]; then
        local jar_path="$2"
        shift 2
        command java -jar "$jar_path" -libdir "$REPO_ROOT/core" -libdir "$REPO_ROOT/platforms/commodore/common" -libdir "$REPO_ROOT/platforms/commodore" -afo "$@"
    else
        command java "$@"
    fi
}
PLUS4_DIR="${PLUS4_DIR:-$REPO_ROOT/platforms/commodore/plus4}"
cd "$PLUS4_DIR"
PLUS4_TEST_OUT="${PLUS4_TEST_OUT:-../../../build/test/plus4}"
mkdir -p "$PLUS4_TEST_OUT"
cleanup() {
    rm -f ./*.prg ./*.sym ./*.vs tests/*.prg tests/*.sym tests/*.vs
    rm -f "$REPO_ROOT"/platforms/commodore/c64/creature_data/*.sym "$REPO_ROOT"/platforms/commodore/c64/creature_data/*.vs
    rm -f "$REPO_ROOT"/core/*.sym "$REPO_ROOT"/core/*.vs
}
trap cleanup EXIT

KICKASS="${KICKASS:-$REPO_ROOT/tools/kickass/KickAss.jar}"
case "$KICKASS" in
    /*) ;;
    *) KICKASS="$(pwd)/$KICKASS" ;;
esac

make -s -C "$REPO_ROOT/platforms/commodore" KICKASS="$KICKASS" ensure-kickass || exit 1

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

suite_selected() {
    local name
    if [ -z "$TEST_FILTER" ]; then
        return 0
    fi
    for name in "$@"; do
        if [ -n "$name" ] && [[ "$name" =~ $TEST_FILTER ]]; then
            return 0
        fi
    done
    return 1
}

make_product_out() {
    mktemp -d "${TMPDIR:-/tmp}/moria8-plus4-$1.XXXXXX"
}

run_test() {
    local name="$1"
    local source="$2"
    local prg="${source%.s}.prg"
    local vs="${source%.s}.vs"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    java -jar "$KICKASS" "$source" -libdir "$REPO_ROOT/platforms/commodore/c64" -define PLUS4 -vicesymbols -o "$prg" >/dev/null || {
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

run_disk_media_probe() {
    local name="$1"
    shift

    if ! suite_selected "$name" "$@"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    if python3 -u ../disk_media_probe.py --scenario "$name" --platform plus4 --c1541 "$C1541"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_media_drive8_attach_read_write() {
    if ! suite_selected "media_drive8_attach_read_write"; then
        return
    fi
    run_disk_media_probe "media_drive8_attach_read_write"
}

run_media_drive9_attach_read_write() {
    if ! suite_selected "media_drive9_attach_read_write"; then
        return
    fi
    run_disk_media_probe "media_drive9_attach_read_write"
}

run_media_drive10_11_device_probe() {
    if ! suite_selected "media_drive10_11_device_probe" "alternate_drive10_11_save_load_smoke"; then
        return
    fi
    run_disk_media_probe "media_drive10_11_device_probe" "alternate_drive10_11_save_load_smoke"
}

run_plus4_static_contracts() {
    local name="plus4_static_contracts"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    if python3 - <<'PY'
from pathlib import Path

root = Path("../../..").resolve()
player_item_prompt = (root / "core" / "player_item_prompt.s").read_text().splitlines()
item_actions_overlay = (root / "core" / "item_actions_overlay.s").read_text().splitlines()

def has_ordered_chain(lines: list[str], tokens: list[str], window: int = 40) -> bool:
    for i, line in enumerate(lines):
        if tokens[0] not in line:
            continue
        pos = i
        for token in tokens[1:]:
            for j in range(pos + 1, min(pos + 1 + window, len(lines))):
                if token in lines[j]:
                    pos = j
                    break
            else:
                break
        else:
            return True
    return False

if not has_ordered_chain(player_item_prompt, [
    "show_inv_and_select:",
    "$0102,x",
    "$0104,x",
    "lda #OVL_NONE",
    "jsr overlay_load",
    "brk",
    "#if PLUS4_PRODUCT_OVERLAY_RUNTIME",
    "jsr plus4_install_ram_irq_vectors",
    "jsr plus4_bank_ram",
], window=80):
    print("Plus/4 inventory selector must detect outer overlay continuations and restore RAM-visible overlay execution after reloading the caller overlay")
    raise SystemExit(1)

if not has_ordered_chain(item_actions_overlay, [
    "item_action_select_filtered_inv:",
    "jsr item_action_get_key",
    "cmp #$3f",
    "lda #OVL_ITEMS",
    "sta piw_return_overlay",
    "jmp piw_select_filtered_inv_key",
]):
    print("Plus/4 item overlay must mark ?-opened inventory selectors as returning to OVL_ITEMS")
    raise SystemExit(1)
PY
    then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

run_boot_title_smoke() {
    local name="boot_title_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-boot-title-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4" \
        "$smoke_out_rel/plus4/boot4.prg" \
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
        -write "$smoke_plus4/boot4.prg" "moria8" \
        -write "$smoke_plus4/boot4.prg" "boot4" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".input_get_key_poll" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_new_game_to_town_smoke() {
    local name="new_game_to_town_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-new-game-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_NEW_GAME_PRODUCT" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".plus4_test_script_exhausted_wait" \
        --start-symbol ".title_menu_loop" \
        --until-pass \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_dungeon_entry_smoke() {
    local name="dungeon_entry_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-dungeon-entry-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_DUNGEON_ENTRY_PRODUCT" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".plus4_test_script_exhausted_wait" \
        --start-symbol ".title_menu_loop" \
        --until-pass \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_dungeon_ascent_smoke() {
    local name="dungeon_ascent_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-dungeon-ascent-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".plus4_test_script_exhausted_wait" \
        --start-symbol ".title_menu_loop" \
        --until-pass \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_overlay_load_smoke() {
    local name="overlay_load_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-overlay-load-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_OVERLAY_LOAD_PRODUCT" \
        "$smoke_out_rel/plus4/boot4.prg" \
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
        -write "$smoke_plus4/boot4.prg" "moria8" \
        -write "$smoke_plus4/boot4.prg" "boot4" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".plus4_test_overlay_load_pass_sym" \
        --fail-symbol ".plus4_test_overlay_load_fail_sym" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_wand_selector_product_smoke() {
    local name="wand_selector_product_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_WAND_SELECTOR_PRODUCT" \
        "$smoke_out_rel/plus4/boot4.prg" \
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
        -write "$smoke_plus4/boot4.prg" "moria8" \
        -write "$smoke_plus4/boot4.prg" "boot4" \
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

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --pass-symbol ".plus4_test_wand_selector_pass_sym" \
        --fail-symbol ".plus4_test_wand_selector_fail_sym" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_marker_init_smoke() {
    local name="marker_init_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local save_d64="$out_dir/test-marker-init-save.d64"
    local main_vs="$REPO_ROOT/build/plus4/main.vs"
    local boot_d64="$REPO_ROOT/build/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" KICKASS="$KICKASS" ../../build/plus4/moria4.prg >"$build_log" 2>&1 || \
       ! make -s -C "$REPO_ROOT/platforms/commodore" KICKASS="$KICKASS" diskplus4 >>"$build_log" 2>&1; then
        echo "FAIL: $name (product disk build)"
        tail -80 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
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
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-disk-setup-product-save.d64"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"
    local smoke_log="$out_dir/$name.run.log"

    if ! suite_selected "$name" "prompt_sequence_no_repeat"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/disk_setup_product_smoke.py \
        --vice "$VICE" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --main-vs "$main_vs" >"$smoke_log" 2>&1; then
        if "$C1541" -attach "$save_d64" -list 2>/dev/null | grep -qi '"MORIA8.ID".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (save marker not present)"
            tail -20 "$smoke_log"
            FAIL=$((FAIL + 1))
        fi
    else
        if "$C1541" -attach "$save_d64" -list 2>/dev/null | grep -qi '"MORIA8.ID".*SEQ'; then
            PASS=$((PASS + 1))
        else
            tail -20 "$smoke_log"
            FAIL=$((FAIL + 1))
        fi
    fi
}

run_disk_setup_missing_save_smoke() {
    local name="disk_setup_missing_save_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "missing_device_or_no_disk"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
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
        --expect setup-fail; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_save_write_product_smoke() {
    local name="save_write_product_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-save-write-product-save.d64"
    local save_blob="$out_dir/THE.GAME"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "dual_drive_load_then_save_no_program_prompt" "save_existing_overwrite"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$save_blob" "the.game,seq" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_save_overwrite_prompt" \
        --pass-symbol ".plus4_test_after_save_game" \
        --fail-symbol ".disk_prompt_game_required_error_shown" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --enable-drive9-bus \
        --pass-on-script-exhausted \
        --vice "$VICE"; then
        if "$C1541" -attach "$save_d64" -list 2>/dev/null | grep -qi '"THE.GAME".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (save file not present)"
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_save_media_fail_product_smoke() {
    local name="save_media_fail_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-save-media-fail-plus4.d64"
    local marker_blob="$out_dir/MORIA8.ID"
    local save_blob="$out_dir/THE.GAME"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"
    local dir_type_offset0=$(((357 + 1) * 256 + 2))
    local dir_type_offset1=$((dir_type_offset0 + 32))

    if ! suite_selected "$name" "write_protected_or_forced_write_error"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT" \
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

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL: $name (marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! python3 "$PLUS4_DIR/tests/make_load_resume_save_plus4.py" "$save_blob" >"$build_log" 2>&1; then
        echo "FAIL: $name (save generation)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria8.id,s" \
        -write "$save_blob" "the.game,s" >"$build_log" 2>&1; then
        echo "FAIL: $name (save disk fixture)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset0" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL: $name (marker directory patch)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! printf '\201' | dd of="$save_d64" bs=1 seek="$dir_type_offset1" conv=notrunc status=none 2>>"$build_log"; then
        echo "FAIL: $name (savefile directory patch)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_save_media_fail_wait_for_harness" \
        --resume-symbol ".plus4_test_save_media_fail_before_save" \
        --pass-symbol ".plus4_test_after_save_media_fail" \
        --fail-symbol ".plus4_test_save_media_fail_unexpected_return" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --enable-drive9-bus \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_change_save_drive_product_smoke() {
    local name="change_save_drive_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save10_d64="$out_dir/test-change-save-drive-plus4-save10.d64"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "change_save_drive_after_save" "alternate_drive_change_smoke" "alternate_drive_prompt_no_repeat"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT" \
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

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL: $name (marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi
    rm -f "$save10_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save10_d64" \
        -attach "$save10_d64" \
        -write "$marker_blob" "moria8.id,s" >"$build_log" 2>&1; then
        echo "FAIL: $name (drive-10 save disk fixture)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_change_save_drive_wait_for_harness" \
        --resume-symbol ".plus4_test_change_save_drive_before_save" \
        --pass-symbol ".plus4_test_change_save_drive_pass" \
        --fail-symbol ".plus4_test_change_save_drive_unexpected_return" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save10-d64 "$save10_d64" \
        --vice "$VICE"; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save10_d64" -list 2>&1); then
            echo "FAIL: $name (drive-10 save disk listing)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
        elif echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (drive-10 save disk missing THE.GAME)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_save_return_product_smoke() {
    local name="single_drive_save_return_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-single-drive-save-return-plus4.d64"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_RETURN_PRODUCT" \
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

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL: $name (marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_before_save" \
        --pass-symbol ".plus4_test_single_drive_save_return_fail" \
        --fail-symbol ".plus4_test_single_drive_after_program_prompt" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --attach8-at-start-d64 "$save_d64" \
        --pass-on-script-exhausted \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_fresh_save_product_smoke() {
    local name="single_drive_fresh_save_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local save_d64="/tmp/moria8-plus4-single-drive-fresh-save-$$.d64"
    local swap_program_d64="/tmp/moria8-plus4-single-drive-fresh-program-$$.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "new_save_empty_init_writes"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT" \
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

    rm -f "$save_d64" "$swap_program_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL: $name (save disk fixture)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi
    cp "$boot_d64" "$swap_program_d64"

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_fresh_save_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_fresh_save_before_save" \
        --pass-symbol ".plus4_test_single_drive_fresh_save_after_restart" \
        --fail-symbol ".plus4_test_single_drive_fresh_save_unexpected_return" \
        --swap-symbol ".uds_show_insert_prompt" \
        --swap-attach8-d64 "$save_d64" \
        --swap2-symbol ".disk_prompt_game_required_error_shown" \
        --swap2-attach8-d64 "$swap_program_d64" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --attach-delay 5.0 \
        --startup-delay 2.0 \
        --vice "$VICE"; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL: $name (save disk listing)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ' && \
                echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (fresh save disk missing marker or save file)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_fresh_save_no_init_product_smoke() {
    local name="single_drive_fresh_save_no_init_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local save_d64="/tmp/moria8-plus4-single-drive-fresh-save-no-init-$$.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "new_save_empty_no_init_returns_setup" "cancel_supported_prompts"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT" \
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
        -write "$smoke_plus4/4.bank" "4.bank" >>"$build_log" 2>&1; then
        echo "FAIL: $name (product disk fixture)"
        tail -40 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" >"$build_log" 2>&1; then
        echo "FAIL: $name (save disk fixture)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_fresh_save_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_fresh_save_before_save" \
        --pass-symbol ".plus4_test_single_drive_fresh_save_no_init_return" \
        --fail-symbol ".plus4_test_single_drive_fresh_save_unexpected_return" \
        --swap-symbol ".uds_show_insert_prompt" \
        --swap-attach8-d64 "$save_d64" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --attach-delay 5.0 \
        --startup-delay 2.0 \
        --vice "$VICE"; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$save_d64" -list 2>&1); then
            echo "FAIL: $name (save disk listing)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
            return
        fi
        if echo "$dir_list" | grep -qi '"THE.GAME"'; then
            echo "FAIL: $name (no-init path wrote THE.GAME)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
        else
            PASS=$((PASS + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_save_wrong_media_product_smoke() {
    local name="single_drive_save_wrong_media_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "single_drive_save_program_disk_rejected" "wrong_media_recovery"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT" \
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

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_save_wrong_media_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_save_wrong_media_before_save" \
        --pass-symbol ".uds_insert_prompt_wait_key" \
        --fail-symbol ".plus4_test_single_drive_save_wrong_media_unexpected_return" \
        --require-hit-symbol ".uds_show_program_disk" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --expect-byte-symbol ".disk_test_program_warning_seen=1" \
        --expect-screen-symbol ".uds_insert_one_drive_str:3:8" \
        --expect-screen-symbol ".press_key_str:6:10" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_load_wrong_media_product_smoke() {
    local name="single_drive_load_wrong_media_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "single_drive_load_program_disk_rejected" "wrong_media_recovery" "wrong_media_detection_selected_devices"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT" \
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

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_load_wrong_media_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_load_wrong_media_before_load" \
        --pass-symbol ".title_menu_loop" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --pass-on-script-exhausted \
        --expect-byte-symbol ".disk_test_program_warning_seen=1" \
        --expect-screen-symbol ".uds_program_disk_str:3:8" \
        --expect-screen-symbol ".press_key_str:5:10" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_disk_setup_single_drive_return_product_smoke() {
    local name="disk_setup_single_drive_return_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local save_d64="$smoke_out/moria8-plus4-save.d64"
    local program_d64="$smoke_out/moria8-plus4-program.d64"
    local marker_blob="$smoke_out/MORIA8.ID"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "title_disk_setup_single_drive_returns_program_prompt"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT" \
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

    rm -f "$boot_d64" "$save_d64" "$program_d64"
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

    printf 'M8SAVE' > "$marker_blob"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria8.id,s" >"$build_log" 2>&1; then
        echo "FAIL: $name (save disk fixture)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi
    cp "$boot_d64" "$program_d64"

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_disk_setup_single_drive_return_wait_for_harness" \
        --resume-symbol ".plus4_test_disk_setup_single_drive_return_before_disk_setup" \
        --pass-symbol ".plus4_test_after_disk_setup_single_drive_return" \
        --swap-symbol ".uds_show_insert_prompt" \
        --swap-attach8-d64 "$save_d64" \
        --swap2-symbol ".disk_prompt_game_required_error_shown" \
        --swap2-attach8-d64 "$program_d64" \
        --expect-screen-symbol ".title_menu_str:18:7" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --attach-delay 5.0 \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_load_wrong_media_product_smoke() {
    local name="load_wrong_media_product_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-load-wrong-media-product-save.d64"
    local marker_blob="$out_dir/WRONG.MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "wrong_media_detection_selected_devices"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
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

    if ! python3 -c 'from pathlib import Path; import sys; Path(sys.argv[1]).write_bytes(b"BADM8!")' "$marker_blob"; then
        echo "FAIL: $name (wrong marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "wrong save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
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
        --enable-drive9-bus \
        --pass-on-script-exhausted \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_load_resume_product_smoke() {
    local name="load_resume_product_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-load-resume-product-save.d64"
    local save_blob="$out_dir/THE.GAME"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "load_initialized_save"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$save_blob" "the.game,seq" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
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
        --enable-drive9-bus \
        --pass-on-script-exhausted \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_death_hiscore_single_drive_product_smoke() {
    local name="death_hiscore_single_drive_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-death-hiscore-single-drive-plus4.d64"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_DEATH_RETURN_PRODUCT" \
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

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL: $name (marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_death_return_wait_for_harness" \
        --resume-symbol ".plus4_test_death_return_before_prepare" \
        --pass-symbol ".plus4_test_death_return_after_score" \
        --fail-symbol ".disk_prompt_game_required_error_shown" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --swap-symbol ".plus4_test_death_return_after_prepare" \
        --swap-attach8-d64 "$save_d64" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_load_return_product_smoke() {
    local name="single_drive_load_return_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-single-drive-load-return-plus4.d64"
    local save_drive8_d64="$out_dir/test-single-drive-load-return-plus4-drive8.d64"
    local save_blob="$out_dir/THE.GAME"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "prompt_sequence_no_repeat"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT" \
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
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$save_blob" "the.game,seq" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi
    cp "$save_d64" "$save_drive8_d64"

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_load_return_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_load_return_before_load" \
        --pass-symbol ".disk_prompt_game_required_error_shown" \
        --fail-symbol ".main_loop" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --enable-drive9-bus \
        --attach8-at-start-d64 "$save_drive8_d64" \
        --pass-on-script-exhausted \
        --expect-screen-symbol ".ds_game_str:10:10" \
        --expect-screen-symbol ".press_key_str:11:13" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_load_then_save_new_empty_product_smoke() {
    local name="load_then_save_new_empty_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local load_save_d64="$out_dir/test-load-then-save-new-empty-plus4-load.d64"
    local new_save_d64="$out_dir/test-load-then-save-new-empty-plus4-save.d64"
    local swap_program_d64="$out_dir/test-load-then-save-new-empty-plus4-program.d64"
    local save_blob="$out_dir/THE.GAME"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "load_then_save_new_empty_disk"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT" \
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
        echo "FAIL: $name (load save generation)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$load_save_d64" "$new_save_d64" "$swap_program_d64"
    if ! "$C1541" -format "moria8 load,s8" d64 "$load_save_d64" \
        -attach "$load_save_d64" \
        -write "$save_blob" "the.game,seq" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (load save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! "$C1541" -format "moria8 save,s8" d64 "$new_save_d64" >"$build_log" 2>&1; then
        echo "FAIL: $name (new save disk fixture)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi
    cp "$boot_d64" "$swap_program_d64"

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_load_then_save_new_empty_wait_for_harness" \
        --resume-symbol ".plus4_test_load_then_save_new_empty_before_load" \
        --attach8-at-start-d64 "$load_save_d64" \
        --swap-symbol ".plus4_test_load_then_save_new_empty_before_save" \
        --swap-attach8-d64 "$new_save_d64" \
        --swap2-symbol ".disk_prompt_game_required_error_shown" \
        --swap2-attach8-d64 "$swap_program_d64" \
        --swap3-symbol ".plus4_test_load_then_save_new_empty_prepare_insert_prompt" \
        --swap3-attach8-d64 "$new_save_d64" \
        --swap4-symbol ".disk_prompt_game_required_error_shown" \
        --swap4-attach8-d64 "$swap_program_d64" \
        --pass-symbol ".plus4_test_load_then_save_new_empty_done" \
        --fail-symbol ".plus4_test_load_then_save_new_empty_fail" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --attach-delay 5.0 \
        --startup-delay 2.0 \
        --vice "$VICE"; then
        local dir_list
        if ! dir_list=$("$C1541" -attach "$new_save_d64" -list 2>&1); then
            echo "FAIL: $name (new save disk listing)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
        elif echo "$dir_list" | grep -qi '"MORIA8.ID".*SEQ' && \
                echo "$dir_list" | grep -qi '"THE.GAME".*SEQ'; then
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (new save disk missing marker or save file)"
            echo "$dir_list" | tail -20
            FAIL=$((FAIL + 1))
        fi
    else
        FAIL=$((FAIL + 1))
    fi
}

run_single_drive_load_corrupt_product_smoke() {
    local name="single_drive_load_corrupt_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-single-drive-load-corrupt-plus4.d64"
    local program_d64="$out_dir/test-single-drive-load-corrupt-plus4-program.d64"
    local save_blob="$out_dir/THE.GAME"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "single_drive_corrupt_save_recovery_requires_program_disk" "corrupt_save_file"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT" \
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

    if ! python3 ../c64/tests/make_load_resume_save64.py "$save_blob" "$marker_blob" >"$build_log" 2>&1; then
        echo "FAIL: $name (c64 save generation)"
        tail -20 "$build_log"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64" "$program_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$save_blob" "the.game,seq" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi
    cp "$boot_d64" "$program_d64"

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_single_drive_load_corrupt_wait_for_harness" \
        --resume-symbol ".plus4_test_single_drive_load_corrupt_before_load" \
        --pass-symbol ".title_menu_loop" \
        --fail-symbol ".main_loop" \
        --swap-symbol ".disk_prompt_game_required_error_shown" \
        --swap-attach8-d64 "$program_d64" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --attach8-at-start-d64 "$save_d64" \
        --pass-on-script-exhausted \
        --expect-screen-symbol ".title_menu_str:18:7" \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_load_missing_savefile_product_smoke() {
    local name="load_missing_savefile_product_plus4"
    local out_dir="$PLUS4_TEST_OUT"
    local smoke_out
    smoke_out="$(make_product_out "$name")"
    local smoke_out_rel="$smoke_out"
    local smoke_plus4="$smoke_out/plus4"
    local save_d64="$out_dir/test-load-missing-savefile-product-save.d64"
    local marker_blob="$out_dir/MORIA8.ID"
    local main_vs="$smoke_out/plus4/main.vs"
    local boot_d64="$smoke_out/moria8-plus4.d64"
    local build_log="$out_dir/$name.build.log"

    if ! suite_selected "$name" "missing_device_or_no_disk"; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    mkdir -p "$out_dir"

    if ! make -s -B -C "$REPO_ROOT/platforms/commodore" \
        KICKASS="$KICKASS" \
        OUT="$smoke_out_rel" \
        KA_FLAGSPLUS4="-showmem -vicesymbols -libdir c64 -define PLUS4 -define PLUS4_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT" \
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

    if ! printf 'M8SAVE' > "$marker_blob"; then
        echo "FAIL: $name (marker generation)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -f "$save_d64"
    if ! "$C1541" -format "moria8 save,s8" d64 "$save_d64" \
        -attach "$save_d64" \
        -write "$marker_blob" "moria8.id,seq" >/dev/null; then
        echo "FAIL: $name (save disk fixture)"
        FAIL=$((FAIL + 1))
        return
    fi

    if python3 -u tests/product_scripted_smoke.py \
        --name "$name" \
        --start-symbol ".plus4_test_load_notfound" \
        --pass-symbol ".title_enter_menu" \
        --main-vs "$main_vs" \
        --boot-d64 "$boot_d64" \
        --save-d64 "$save_d64" \
        --enable-drive9-bus \
        --pass-on-script-exhausted \
        --vice "$VICE"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_plus4_static_contracts
run_test "minimalplus4" "tests/test_minimalplus4.s"
run_media_drive8_attach_read_write
run_media_drive9_attach_read_write
run_media_drive10_11_device_probe
run_boot_title_smoke
run_new_game_to_town_smoke
run_dungeon_entry_smoke
run_dungeon_ascent_smoke
run_overlay_load_smoke
run_wand_selector_product_smoke
run_disk_setup_product_smoke
run_disk_setup_missing_save_smoke
run_load_wrong_media_product_smoke
run_save_write_product_smoke
run_save_media_fail_product_smoke
run_change_save_drive_product_smoke
run_single_drive_save_return_product_smoke
run_single_drive_fresh_save_product_smoke
run_single_drive_fresh_save_no_init_product_smoke
run_single_drive_save_wrong_media_product_smoke
run_single_drive_load_wrong_media_product_smoke
run_disk_setup_single_drive_return_product_smoke
run_death_hiscore_single_drive_product_smoke
run_load_resume_product_smoke
run_single_drive_load_return_product_smoke
run_load_then_save_new_empty_product_smoke
run_single_drive_load_corrupt_product_smoke
run_load_missing_savefile_product_smoke

echo "=== Plus/4 runtime summary: $PASS passed, $FAIL failed, $TOTAL total ==="
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
