#!/usr/bin/env python3
"""Self-tests for the CX16 memory contract checker."""

import os
import sys
import tempfile
from contextlib import redirect_stdout
from io import StringIO

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CX16_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, CX16_DIR)

import check_memory_contract as contract


def base_labels(program_end):
    return {
        "program_end": program_end,
        "monster_table": contract.CX16_CREATURE_BASE,
        "cx16_contract_prg_load_base": contract.CX16_PRG_LOAD_BASE,
        "cx16_contract_ram_bank_count": contract.CX16_RAM_BANK_COUNT,
        "cx16_contract_ram_bank_reg": contract.CX16_RAM_BANK_REG,
        "cx16_contract_ram_bank_default": contract.CX16_RAM_BANK_DEFAULT,
        "cx16_contract_ram_bank_last": contract.CX16_RAM_BANK_LAST,
        "cx16_contract_transient_bank_base": contract.CX16_TRANSIENT_BANK_BASE,
        "cx16_contract_transient_bank_end": contract.CX16_TRANSIENT_BANK_END,
        "cx16_contract_resident_code_base": contract.CX16_RESIDENT_CODE_BASE,
        "cx16_contract_resident_code_limit": contract.CX16_RESIDENT_CODE_LIMIT,
        "cx16_contract_resident_product_limit": contract.CX16_RESIDENT_PRODUCT_LIMIT,
        "cx16_contract_fixed_live_map_base": contract.CX16_FIXED_LIVE_MAP_BASE,
        "cx16_contract_fixed_live_map_end": contract.CX16_FIXED_LIVE_MAP_END,
        "cx16_contract_floor_item_base": contract.CX16_FLOOR_ITEM_BASE,
        "cx16_contract_floor_item_end": contract.CX16_FLOOR_ITEM_END,
        "cx16_contract_creature_base": contract.CX16_CREATURE_BASE,
        "cx16_contract_creature_end": contract.CX16_CREATURE_END,
        "cx16_contract_bfs_queue_base": contract.CX16_BFS_QUEUE_BASE,
        "cx16_contract_bfs_queue_end": contract.CX16_BFS_QUEUE_END,
        "cx16_contract_banked_ram_base": contract.CX16_BANKED_RAM_BASE,
        "cx16_contract_banked_ram_end": contract.CX16_BANKED_RAM_END,
        "cx16_contract_banked_data_base": contract.CX16_BANKED_RAM_BASE,
        "cx16_contract_banked_data_end": contract.CX16_BANKED_RAM_END,
        "cx16_contract_tier_bank_base": contract.CX16_TIER_BANK_BASE,
        "cx16_contract_tier_bank_end": contract.CX16_TIER_BANK_END,
        "cx16_contract_tier_load_base": contract.CX16_TIER_LOAD_BASE,
        "cx16_contract_tier_load_end": contract.CX16_TIER_LOAD_END,
        "cx16_contract_dungeon_module_bank": contract.CX16_DUNGEON_MODULE_BANK,
        "cx16_contract_dungeon_module_load_base": contract.CX16_DUNGEON_MODULE_LOAD_BASE,
        "cx16_contract_dungeon_module_load_end": contract.CX16_DUNGEON_MODULE_LOAD_END,
        "cx16_contract_dungeon_module_entry": contract.CX16_DUNGEON_MODULE_ENTRY,
        "cx16_contract_item_catalog_bank_base": contract.CX16_ITEM_CATALOG_BANK_BASE,
        "cx16_contract_item_catalog_bank_end": contract.CX16_ITEM_CATALOG_BANK_END,
        "cx16_contract_item_catalog_primary_bank": contract.CX16_ITEM_CATALOG_PRIMARY_BANK,
        "cx16_contract_item_catalog_load_base": contract.CX16_ITEM_CATALOG_LOAD_BASE,
        "cx16_contract_item_catalog_load_end": contract.CX16_ITEM_CATALOG_LOAD_END,
        "cx16_contract_title_source_bank": contract.CX16_TITLE_SOURCE_BANK,
        "cx16_contract_title_source_load_base": contract.CX16_TITLE_SOURCE_LOAD_BASE,
        "cx16_contract_title_source_load_end": contract.CX16_TITLE_SOURCE_LOAD_END,
        "cx16_contract_overlay_cache_bank_base": contract.CX16_OVERLAY_CACHE_BANK_BASE,
        "cx16_contract_overlay_cache_bank_end": contract.CX16_OVERLAY_CACHE_BANK_END,
        "cx16_contract_overlay_startup_bank": contract.CX16_OVERLAY_STARTUP_BANK,
        "cx16_contract_overlay_town_bank": contract.CX16_OVERLAY_TOWN_BANK,
        "cx16_contract_overlay_death_bank": contract.CX16_OVERLAY_DEATH_BANK,
        "cx16_contract_overlay_gen_bank": contract.CX16_OVERLAY_GEN_BANK,
        "cx16_contract_overlay_help_bank": contract.CX16_OVERLAY_HELP_BANK,
        "cx16_contract_overlay_ui_bank": contract.CX16_OVERLAY_UI_BANK,
        "cx16_contract_overlay_items_bank": contract.CX16_OVERLAY_ITEMS_BANK,
        "cx16_contract_overlay_storage_bank": contract.CX16_OVERLAY_STORAGE_BANK,
        "cx16_contract_overlay_disarm_bank": contract.CX16_OVERLAY_DISARM_BANK,
        "cx16_contract_overlay_slot_bank_base": contract.CX16_OVERLAY_SLOT_BANK_BASE,
        "cx16_contract_overlay_slot_bank_end": contract.CX16_OVERLAY_SLOT_BANK_END,
        "cx16_contract_overlay_free_bank_base": contract.CX16_OVERLAY_FREE_BANK_BASE,
        "cx16_contract_overlay_free_bank_end": contract.CX16_OVERLAY_FREE_BANK_END,
        "cx16_contract_data_cache_bank_base": contract.CX16_DATA_CACHE_BANK_BASE,
        "cx16_contract_data_cache_bank_end": contract.CX16_DATA_CACHE_BANK_END,
        "cx16_contract_work_bank_base": contract.CX16_WORK_BANK_BASE,
        "cx16_contract_work_bank_end": contract.CX16_WORK_BANK_END,
        "title_load_and_draw": contract.CX16_BANKED_RAM_BASE,
        "ui_inv_display": contract.CX16_BANKED_RAM_BASE,
        "itemdesc_put_inv_slot": contract.CX16_BANKED_RAM_BASE,
        "piw_prompt_filtered_inv": contract.CX16_BANKED_RAM_BASE,
        "door_try_open": contract.CX16_BANKED_RAM_BASE,
        "door_try_close": contract.CX16_BANKED_RAM_BASE,
        "do_search": contract.CX16_BANKED_RAM_BASE,
        "bash_command": contract.CX16_BANKED_RAM_BASE,
        "player_tunnel": contract.CX16_BANKED_RAM_BASE,
        "disarm_command": contract.CX16_BANKED_RAM_BASE,
        "get_direction_target": contract.CX16_RESIDENT_CODE_BASE,
        "item_load_category_x": contract.CX16_RESIDENT_CODE_BASE,
        "item_load_name_lo_x": contract.CX16_RESIDENT_CODE_BASE,
        "item_load_name_hi_x": contract.CX16_RESIDENT_CODE_BASE,
        "item_decode_name_ptr_cx16_catalog": contract.CX16_RESIDENT_CODE_BASE,
    }


def assert_raises(fn, expected_text):
    try:
        fn()
    except contract.ContractError as exc:
        if expected_text not in str(exc):
            raise AssertionError(f"expected error containing {expected_text!r}, got {exc!r}") from exc
        return
    raise AssertionError(f"expected ContractError containing {expected_text!r}")


def write_prg(path, load, body_size):
    body = bytes((i & 0xFF for i in range(body_size)))
    with open(path, "wb") as fh:
        fh.write(bytes((load & 0xFF, load >> 8)))
        fh.write(body)


def write_symbols(path, labels):
    with open(path, "w", encoding="utf-8") as fh:
        for name, value in sorted(labels.items()):
            fh.write(f".label {name}=${value:04x}\n")


def test_product_symbol_contract():
    contract.check_product_symbols(base_labels(0x1754))

    bad = base_labels(contract.CX16_RESIDENT_CODE_LIMIT + 1)
    assert_raises(lambda: contract.check_product_symbols(bad), "overlaps fixed live-map")

    over_policy = base_labels(contract.CX16_RESIDENT_PRODUCT_LIMIT + 1)
    assert_raises(lambda: contract.check_product_symbols(over_policy), "resident product policy")

    resident_item_names = base_labels(0x1754)
    resident_item_names["it_name_lo"] = contract.CX16_RESIDENT_CODE_BASE
    assert_raises(lambda: contract.check_product_symbols(resident_item_names), "known item names")


def test_shared_probe_symbol_contract():
    contract.check_shared_probe_symbols(base_labels(0xCD1D))

    too_small = base_labels(0x3000)
    assert_raises(lambda: contract.check_shared_probe_symbols(too_small), "live-map base")

    no_io_cross = base_labels(contract.CX16_IO_BASE)
    assert_raises(lambda: contract.check_shared_probe_symbols(no_io_cross), "VERA I/O")

    wrong_monster_table = base_labels(0xCD1D)
    wrong_monster_table["monster_table"] = contract.CX16_CREATURE_BASE - 1
    assert_raises(lambda: contract.check_shared_probe_symbols(wrong_monster_table), "shared probe monster_table")


def test_region_symbol_contracts():
    bad_floor = base_labels(0x1754)
    bad_floor["cx16_contract_floor_item_base"] = contract.CX16_FIXED_LIVE_MAP_END
    assert_raises(lambda: contract.check_product_symbols(bad_floor), "cx16_contract_floor_item_base")

    bad_bank = base_labels(0x1754)
    bad_bank["cx16_contract_banked_ram_base"] = contract.CX16_IO_END
    assert_raises(lambda: contract.check_product_symbols(bad_bank), "cx16_contract_banked_ram_base")


def test_missing_symbol_contract():
    labels = base_labels(0x1754)
    del labels["cx16_contract_banked_data_end"]
    assert_raises(lambda: contract.check_product_symbols(labels), "missing symbol: cx16_contract_banked_data_end")


def test_prg_reader_rejects_malformed_file():
    with tempfile.TemporaryDirectory() as tmpdir:
        prg_path = os.path.join(tmpdir, "short.prg")
        with open(prg_path, "wb") as fh:
            fh.write(b"\x01")
        assert_raises(lambda: contract.read_prg_span(prg_path), "PRG is too short")


def test_prg_symbol_span_match():
    with tempfile.TemporaryDirectory() as tmpdir:
        prg_path = os.path.join(tmpdir, "moria16.prg")
        sym_path = os.path.join(tmpdir, "main.sym")

        program_end = 0x1800
        write_prg(prg_path, contract.CX16_PRG_LOAD_BASE, program_end - contract.CX16_PRG_LOAD_BASE)
        write_symbols(sym_path, base_labels(program_end))
        contract.check_product(prg_path, sym_path)

        stale_symbols = os.path.join(tmpdir, "stale.sym")
        write_symbols(stale_symbols, base_labels(program_end + 1))
        assert_raises(lambda: contract.check_product(prg_path, stale_symbols), "file end")

        wrong_load = os.path.join(tmpdir, "wrong_load.prg")
        write_prg(wrong_load, contract.CX16_PRG_LOAD_BASE + 1, program_end - contract.CX16_PRG_LOAD_BASE)
        assert_raises(lambda: contract.check_product(wrong_load, sym_path), "load address")


def test_shared_probe_prg_symbol_span_match():
    with tempfile.TemporaryDirectory() as tmpdir:
        prg_path = os.path.join(tmpdir, "shared_probe.prg")
        sym_path = os.path.join(tmpdir, "shared_probe.sym")

        program_end = contract.CX16_BANKED_RAM_END + 0x0100
        write_prg(prg_path, contract.CX16_PRG_LOAD_BASE, program_end - contract.CX16_PRG_LOAD_BASE)
        write_symbols(sym_path, base_labels(program_end))
        contract.check_shared_probe(prg_path, sym_path)

        stale_symbols = os.path.join(tmpdir, "stale_shared_probe.sym")
        write_symbols(stale_symbols, base_labels(program_end - 1))
        assert_raises(lambda: contract.check_shared_probe(prg_path, stale_symbols), "file end")


def test_tier_prg_contract():
    with tempfile.TemporaryDirectory() as tmpdir:
        tier_path = os.path.join(tmpdir, "MONSTER.DB.1")
        write_prg(tier_path, contract.CX16_TIER_LOAD_BASE, 0x0200)
        contract.check_tier_prg(tier_path)

        wrong_load = os.path.join(tmpdir, "MONSTER.DB.BADLOAD")
        write_prg(wrong_load, contract.CX16_TIER_LOAD_BASE + 1, 0x0200)
        assert_raises(lambda: contract.check_tier_prg(wrong_load), "load address")

        too_large = os.path.join(tmpdir, "MONSTER.DB.BIG")
        write_prg(too_large, contract.CX16_TIER_LOAD_BASE, contract.CX16_BANKED_RAM_END - contract.CX16_TIER_LOAD_BASE + 2)
        assert_raises(lambda: contract.check_tier_prg(too_large), "exceeds banked RAM window")


def test_module_prg_contract():
    with tempfile.TemporaryDirectory() as tmpdir:
        module_path = os.path.join(tmpdir, "DUNGEON.GEN")
        write_prg(module_path, contract.CX16_DUNGEON_MODULE_LOAD_BASE, 0x0200)
        contract.check_module_prg(module_path)

        wrong_load = os.path.join(tmpdir, "DUNGEON.BADLOAD")
        write_prg(wrong_load, contract.CX16_DUNGEON_MODULE_LOAD_BASE + 1, 0x0200)
        assert_raises(lambda: contract.check_module_prg(wrong_load), "load address")

        too_large = os.path.join(tmpdir, "DUNGEON.BIG")
        write_prg(
            too_large,
            contract.CX16_DUNGEON_MODULE_LOAD_BASE,
            contract.CX16_BANKED_RAM_END - contract.CX16_DUNGEON_MODULE_LOAD_BASE + 2,
        )
        assert_raises(lambda: contract.check_module_prg(too_large), "exceeds banked RAM window")


def test_item_prg_contract():
    with tempfile.TemporaryDirectory() as tmpdir:
        item_path = os.path.join(tmpdir, "ITEMCAT.1")
        write_prg(item_path, contract.CX16_ITEM_CATALOG_LOAD_BASE, 0x0200)
        contract.check_item_prg(item_path)

        wrong_load = os.path.join(tmpdir, "ITEMCAT.BADLOAD")
        write_prg(wrong_load, contract.CX16_ITEM_CATALOG_LOAD_BASE + 1, 0x0200)
        assert_raises(lambda: contract.check_item_prg(wrong_load), "load address")

        too_large = os.path.join(tmpdir, "ITEMCAT.BIG")
        write_prg(
            too_large,
            contract.CX16_ITEM_CATALOG_LOAD_BASE,
            contract.CX16_ITEM_CATALOG_LOAD_END - contract.CX16_ITEM_CATALOG_LOAD_BASE + 2,
        )
        assert_raises(lambda: contract.check_item_prg(too_large), "exceeds banked RAM window")


def test_title_prg_contract():
    with tempfile.TemporaryDirectory() as tmpdir:
        title_path = os.path.join(tmpdir, "TITLE")
        write_prg(title_path, contract.CX16_TITLE_SOURCE_LOAD_BASE, 0x0200)
        contract.check_title_prg(title_path)

        wrong_load = os.path.join(tmpdir, "TITLE.BADLOAD")
        write_prg(wrong_load, contract.CX16_TITLE_SOURCE_LOAD_BASE + 1, 0x0200)
        assert_raises(lambda: contract.check_title_prg(wrong_load), "load address")

        too_large = os.path.join(tmpdir, "TITLE.BIG")
        write_prg(
            too_large,
            contract.CX16_TITLE_SOURCE_LOAD_BASE,
            contract.CX16_TITLE_SOURCE_LOAD_END - contract.CX16_TITLE_SOURCE_LOAD_BASE + 2,
        )
        assert_raises(lambda: contract.check_title_prg(too_large), "exceeds banked RAM window")


def test_overlay_prg_contract():
    with tempfile.TemporaryDirectory() as tmpdir:
        overlay_path = os.path.join(tmpdir, "X16.START")
        write_prg(overlay_path, contract.CX16_BANKED_RAM_BASE, 0x0200)
        contract.check_overlay_prg(overlay_path)

        wrong_load = os.path.join(tmpdir, "X16.BADLOAD")
        write_prg(wrong_load, contract.CX16_BANKED_RAM_BASE + 1, 0x0200)
        assert_raises(lambda: contract.check_overlay_prg(wrong_load), "load address")

        too_large = os.path.join(tmpdir, "X16.BIG")
        write_prg(
            too_large,
            contract.CX16_BANKED_RAM_BASE,
            contract.CX16_BANKED_RAM_END - contract.CX16_BANKED_RAM_BASE + 2,
        )
        assert_raises(lambda: contract.check_overlay_prg(too_large), "exceeds banked RAM window")


def test_overlap_span_edges():
    assert contract.overlap_span(0x0801, 0x1000, 0x9F00, 0x9FFF) is None
    assert contract.overlap_span(0x0801, 0x9F00, 0x9F00, 0x9FFF) is None
    assert contract.overlap_span(0x0801, 0x9F01, 0x9F00, 0x9FFF) == (0x9F00, 0x9F01)
    assert contract.overlap_span(0x9FFF, 0xA100, 0x9F00, 0x9FFF) == (0x9FFF, 0xA000)


def test_report_contains_actionable_memory_lines():
    product = (contract.CX16_PRG_LOAD_BASE, 0x1754, 0x1754)
    shared = (contract.CX16_PRG_LOAD_BASE, contract.CX16_BANKED_RAM_END + 0x0100, contract.CX16_BANKED_RAM_END + 0x0100)
    title = (contract.CX16_TITLE_SOURCE_LOAD_BASE, contract.CX16_TITLE_SOURCE_LOAD_BASE + 0x0200)
    tiers = [(contract.CX16_TIER_LOAD_BASE, contract.CX16_TIER_LOAD_BASE + 0x0200)]
    modules = [(contract.CX16_DUNGEON_MODULE_LOAD_BASE, contract.CX16_DUNGEON_MODULE_LOAD_BASE + 0x0200)]
    items = [(contract.CX16_ITEM_CATALOG_LOAD_BASE, contract.CX16_ITEM_CATALOG_LOAD_BASE + 0x0200)]
    overlays = [(contract.CX16_BANKED_RAM_BASE, contract.CX16_BANKED_RAM_BASE + 0x0020)]
    output = StringIO()
    with redirect_stdout(output):
        contract.emit_report(product, shared, title, tiers, modules, items, overlays)

    report = output.getvalue()
    for expected in (
        "product fixed-code headroom",
        "fixed live map",
        "RAM bank register/default",
        "RAM banks",
        "transient scratch banks",
        "tier banks",
        "tier 1 PRG",
        "dungeon module bank",
        "dungeon module PRG",
        "item catalog banks",
        "item catalog primary bank",
        "item catalog PRG",
        "title source bank",
        "title PRG",
        "overlay slots",
        "overlay slot banks",
        "overlay slot 1 PRG",
        "overlay expansion banks",
        "unallocated data-cache banks",
        "unallocated work banks",
        "shared probe over fixed-code limit",
        "shared probe overlaps VERA I/O",
        "shared probe overlaps bank window",
        "shared probe extends past bank window",
    ):
        if expected not in report:
            raise AssertionError(f"missing report line containing {expected!r}:\n{report}")


def main():
    test_product_symbol_contract()
    test_shared_probe_symbol_contract()
    test_region_symbol_contracts()
    test_missing_symbol_contract()
    test_prg_reader_rejects_malformed_file()
    test_prg_symbol_span_match()
    test_shared_probe_prg_symbol_span_match()
    test_tier_prg_contract()
    test_module_prg_contract()
    test_item_prg_contract()
    test_title_prg_contract()
    test_overlay_prg_contract()
    test_overlap_span_edges()
    test_report_contains_actionable_memory_lines()
    print("CX16 memory contract self-test passed")


if __name__ == "__main__":
    main()
