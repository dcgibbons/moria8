#!/usr/bin/env python3
"""Validate CX16 PRG and symbol memory contracts.

The normal CX16 image is runtime code and must stay below the fixed live-map
region. The shared-gameplay image is intentionally a link-only probe; this
checker verifies that the generated symbols still make that distinction
mechanical rather than relying on comments.
"""

import argparse
import os
import sys


CX16_PRG_LOAD_BASE = 0x0801
CX16_RAM_BANK_REG = 0x0000
CX16_RAM_BANK_COUNT = 64
CX16_RAM_BANK_DEFAULT = 0
CX16_RAM_BANK_LAST = CX16_RAM_BANK_COUNT - 1
CX16_TRANSIENT_BANK_BASE = 1
CX16_TRANSIENT_BANK_END = 3
CX16_RESIDENT_CODE_BASE = 0x0810
CX16_RESIDENT_CODE_LIMIT = 0x6800
CX16_FIXED_LIVE_MAP_BASE = 0x6800
CX16_FIXED_LIVE_MAP_END = 0x9B0B
CX16_FLOOR_ITEM_BASE = 0x9C00
CX16_FLOOR_ITEM_END = 0x9CFF
CX16_CREATURE_BASE = 0x9D00
CX16_CREATURE_END = 0x9E7F
CX16_ACTIVE_MONSTER_TABLE_BYTES = 32 * 12
CX16_BFS_QUEUE_BASE = 0x0400
CX16_BFS_QUEUE_END = 0x07FF
CX16_IO_BASE = 0x9F00
CX16_IO_END = 0x9FFF
CX16_BANKED_RAM_BASE = 0xA000
CX16_BANKED_RAM_END = 0xBFFF
CX16_TIER_BANK_BASE = 4
CX16_TIER_BANK_END = 7
CX16_TIER_LOAD_BASE = CX16_BANKED_RAM_BASE
CX16_TIER_LOAD_END = 0xA80D
CX16_DUNGEON_MODULE_BANK = 8
CX16_DUNGEON_MODULE_LOAD_BASE = CX16_BANKED_RAM_BASE
CX16_DUNGEON_MODULE_LOAD_END = CX16_BANKED_RAM_END
CX16_DUNGEON_MODULE_ENTRY = CX16_DUNGEON_MODULE_LOAD_BASE
CX16_ITEM_CATALOG_BANK_BASE = 9
CX16_ITEM_CATALOG_BANK_END = 10
CX16_ITEM_CATALOG_PRIMARY_BANK = CX16_ITEM_CATALOG_BANK_BASE
CX16_ITEM_CATALOG_LOAD_BASE = CX16_BANKED_RAM_BASE
CX16_ITEM_CATALOG_LOAD_END = CX16_BANKED_RAM_END
CX16_TITLE_SOURCE_BANK = 11
CX16_TITLE_SOURCE_LOAD_BASE = CX16_BANKED_RAM_BASE
CX16_TITLE_SOURCE_LOAD_END = CX16_BANKED_RAM_END
CX16_OVERLAY_CACHE_BANK_BASE = 12
CX16_OVERLAY_CACHE_BANK_END = 31
CX16_OVERLAY_STARTUP_BANK = CX16_OVERLAY_CACHE_BANK_BASE
CX16_OVERLAY_TOWN_BANK = CX16_OVERLAY_STARTUP_BANK + 1
CX16_OVERLAY_DEATH_BANK = CX16_OVERLAY_TOWN_BANK + 1
CX16_OVERLAY_ROYAL_BANK = CX16_OVERLAY_DEATH_BANK + 1
CX16_OVERLAY_GEN_BANK = CX16_OVERLAY_ROYAL_BANK + 1
CX16_OVERLAY_HELP_BANK = CX16_OVERLAY_GEN_BANK + 1
CX16_OVERLAY_UI_BANK = CX16_OVERLAY_HELP_BANK + 1
CX16_OVERLAY_ITEMS_BANK = CX16_OVERLAY_UI_BANK + 1
CX16_OVERLAY_SPELL_BANK = CX16_OVERLAY_ITEMS_BANK + 1
CX16_OVERLAY_DISARM_BANK = CX16_OVERLAY_SPELL_BANK + 1
CX16_OVERLAY_SLOT_BANK_BASE = CX16_OVERLAY_STARTUP_BANK
CX16_OVERLAY_SLOT_BANK_END = CX16_OVERLAY_DISARM_BANK
CX16_OVERLAY_PRELOAD_COUNT = CX16_OVERLAY_SLOT_BANK_END - CX16_OVERLAY_SLOT_BANK_BASE + 1
CX16_OVERLAY_FREE_BANK_BASE = CX16_OVERLAY_SLOT_BANK_END + 1
CX16_OVERLAY_FREE_BANK_END = CX16_OVERLAY_CACHE_BANK_END
CX16_DATA_CACHE_BANK_BASE = 32
CX16_DATA_CACHE_BANK_END = 47
CX16_WORK_BANK_BASE = 48
CX16_WORK_BANK_END = CX16_RAM_BANK_LAST


class ContractError(Exception):
    pass


def load_symbols(path):
    labels = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith(".label "):
                continue
            name_value = line[len(".label ") :].split()[0]
            if "=" not in name_value:
                continue
            name, value = name_value.split("=", 1)
            if value.startswith("$"):
                labels[name] = int(value[1:], 16)
    return labels


def require(labels, name):
    try:
        return labels[name]
    except KeyError:
        raise ContractError(f"missing symbol: {name}") from None


def read_prg_span(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 2:
        raise ContractError(f"{path}: PRG is too short")
    load = data[0] | (data[1] << 8)
    end_exclusive = load + len(data) - 2
    return load, end_exclusive


def expect_addr(actual, expected, label):
    if actual != expected:
        raise ContractError(f"{label}: expected ${expected:04X}, got ${actual:04X}")


def expect_true(condition, label):
    if not condition:
        raise ContractError(label)


def fmt_addr(value):
    return f"${value:04X}"


def fmt_span(start, end_exclusive):
    return f"{fmt_addr(start)}-{fmt_addr(end_exclusive - 1)}"


def span_size(start, end_exclusive):
    return end_exclusive - start


def overlap_span(start, end_exclusive, region_start, region_end_inclusive):
    overlap_start = max(start, region_start)
    overlap_end = min(end_exclusive, region_end_inclusive + 1)
    if overlap_start >= overlap_end:
        return None
    return overlap_start, overlap_end


def emit_report(product, shared_probe, title, tiers, modules, items, overlays):
    product_load, product_end, product_program_end = product
    probe_load, probe_end, probe_program_end = shared_probe
    title_load, title_end = title
    live_map_size = CX16_FIXED_LIVE_MAP_END - CX16_FIXED_LIVE_MAP_BASE + 1
    bank_window_size = CX16_BANKED_RAM_END - CX16_BANKED_RAM_BASE + 1
    product_headroom = CX16_RESIDENT_CODE_LIMIT - product_program_end
    probe_over_fixed_limit = probe_program_end - CX16_RESIDENT_CODE_LIMIT
    probe_io_overlap = overlap_span(probe_load, probe_end, CX16_IO_BASE, CX16_IO_END)
    probe_bank_overlap = overlap_span(probe_load, probe_end, CX16_BANKED_RAM_BASE, CX16_BANKED_RAM_END)
    probe_after_bank = max(0, probe_program_end - (CX16_BANKED_RAM_END + 1))

    print("CX16 memory contract check passed")
    print(f"  product image: {fmt_span(product_load, product_end)} ({span_size(product_load, product_end)} bytes)")
    print(f"  product program_end: {fmt_addr(product_program_end)}")
    print(f"  product fixed-code headroom: {product_headroom} bytes before {fmt_addr(CX16_RESIDENT_CODE_LIMIT)}")
    print(
        "  fixed live map: "
        f"{fmt_span(CX16_FIXED_LIVE_MAP_BASE, CX16_FIXED_LIVE_MAP_END + 1)} "
        f"({live_map_size} bytes)"
    )
    print(f"  floor items: {fmt_span(CX16_FLOOR_ITEM_BASE, CX16_FLOOR_ITEM_END + 1)}")
    print(f"  active monster arena: {fmt_span(CX16_CREATURE_BASE, CX16_CREATURE_END + 1)}")
    print(f"  BFS queue: {fmt_span(CX16_BFS_QUEUE_BASE, CX16_BFS_QUEUE_END + 1)}")
    print(f"  RAM bank register/default: {fmt_addr(CX16_RAM_BANK_REG)} / {CX16_RAM_BANK_DEFAULT}")
    print(f"  banked RAM window: {fmt_span(CX16_BANKED_RAM_BASE, CX16_BANKED_RAM_END + 1)} ({bank_window_size} bytes)")
    print(f"  RAM banks: 0-{CX16_RAM_BANK_LAST} ({CX16_RAM_BANK_COUNT} banks)")
    print(f"  transient scratch banks: {CX16_TRANSIENT_BANK_BASE}-{CX16_TRANSIENT_BANK_END}")
    print(f"  tier banks: {CX16_TIER_BANK_BASE}-{CX16_TIER_BANK_END}")
    for index, (tier_load, tier_end) in enumerate(tiers, start=1):
        print(f"  tier {index} PRG: {fmt_span(tier_load, tier_end)} ({span_size(tier_load, tier_end)} bytes)")
    print(f"  dungeon module bank: {CX16_DUNGEON_MODULE_BANK}")
    for module_load, module_end in modules:
        print(f"  dungeon module PRG: {fmt_span(module_load, module_end)} ({span_size(module_load, module_end)} bytes)")
    print(f"  item catalog banks: {CX16_ITEM_CATALOG_BANK_BASE}-{CX16_ITEM_CATALOG_BANK_END}")
    print(f"  item catalog primary bank: {CX16_ITEM_CATALOG_PRIMARY_BANK}")
    for item_load, item_end in items:
        print(f"  item catalog PRG: {fmt_span(item_load, item_end)} ({span_size(item_load, item_end)} bytes)")
    print(f"  title source bank: {CX16_TITLE_SOURCE_BANK}")
    print(f"  title PRG: {fmt_span(title_load, title_end)} ({span_size(title_load, title_end)} bytes)")
    print(f"  title source load window: {fmt_span(CX16_TITLE_SOURCE_LOAD_BASE, CX16_TITLE_SOURCE_LOAD_END + 1)}")
    print(
        "  overlay slots: "
        f"STARTUP={CX16_OVERLAY_STARTUP_BANK}, "
        f"TOWN={CX16_OVERLAY_TOWN_BANK}, "
        f"DEATH={CX16_OVERLAY_DEATH_BANK}, "
        f"ROYAL={CX16_OVERLAY_ROYAL_BANK}, "
        f"GEN={CX16_OVERLAY_GEN_BANK}, "
        f"HELP={CX16_OVERLAY_HELP_BANK}, "
        f"UI={CX16_OVERLAY_UI_BANK}, "
        f"ITEMS={CX16_OVERLAY_ITEMS_BANK}, "
        f"SPELL={CX16_OVERLAY_SPELL_BANK}, "
        f"DISARM={CX16_OVERLAY_DISARM_BANK}"
    )
    print(f"  overlay slot banks: {CX16_OVERLAY_SLOT_BANK_BASE}-{CX16_OVERLAY_SLOT_BANK_END}")
    for index, (overlay_load, overlay_end) in enumerate(overlays, start=1):
        print(f"  overlay slot {index} PRG: {fmt_span(overlay_load, overlay_end)} ({span_size(overlay_load, overlay_end)} bytes)")
    print(f"  overlay expansion banks: {CX16_OVERLAY_FREE_BANK_BASE}-{CX16_OVERLAY_FREE_BANK_END}")
    print(f"  unallocated data-cache banks: {CX16_DATA_CACHE_BANK_BASE}-{CX16_DATA_CACHE_BANK_END}")
    print(f"  unallocated work banks: {CX16_WORK_BANK_BASE}-{CX16_WORK_BANK_END}")
    print(f"  shared probe image: {fmt_span(probe_load, probe_end)} ({span_size(probe_load, probe_end)} bytes)")
    print(f"  shared probe program_end: {fmt_addr(probe_program_end)}")
    print(f"  shared probe over fixed-code limit: {probe_over_fixed_limit} bytes")
    if probe_io_overlap:
        print(f"  shared probe overlaps VERA I/O: {fmt_span(*probe_io_overlap)}")
    if probe_bank_overlap:
        print(f"  shared probe overlaps bank window: {fmt_span(*probe_bank_overlap)}")
    if probe_after_bank:
        print(f"  shared probe extends past bank window: {probe_after_bank} bytes")


def check_contract_symbols(labels):
    expected = {
        "cx16_contract_prg_load_base": CX16_PRG_LOAD_BASE,
        "cx16_contract_ram_bank_count": CX16_RAM_BANK_COUNT,
        "cx16_contract_ram_bank_reg": CX16_RAM_BANK_REG,
        "cx16_contract_ram_bank_default": CX16_RAM_BANK_DEFAULT,
        "cx16_contract_ram_bank_last": CX16_RAM_BANK_LAST,
        "cx16_contract_transient_bank_base": CX16_TRANSIENT_BANK_BASE,
        "cx16_contract_transient_bank_end": CX16_TRANSIENT_BANK_END,
        "cx16_contract_resident_code_base": CX16_RESIDENT_CODE_BASE,
        "cx16_contract_resident_code_limit": CX16_RESIDENT_CODE_LIMIT,
        "cx16_contract_fixed_live_map_base": CX16_FIXED_LIVE_MAP_BASE,
        "cx16_contract_fixed_live_map_end": CX16_FIXED_LIVE_MAP_END,
        "cx16_contract_floor_item_base": CX16_FLOOR_ITEM_BASE,
        "cx16_contract_floor_item_end": CX16_FLOOR_ITEM_END,
        "cx16_contract_creature_base": CX16_CREATURE_BASE,
        "cx16_contract_creature_end": CX16_CREATURE_END,
        "cx16_contract_bfs_queue_base": CX16_BFS_QUEUE_BASE,
        "cx16_contract_bfs_queue_end": CX16_BFS_QUEUE_END,
        "cx16_contract_banked_ram_base": CX16_BANKED_RAM_BASE,
        "cx16_contract_banked_ram_end": CX16_BANKED_RAM_END,
        "cx16_contract_banked_data_base": CX16_BANKED_RAM_BASE,
        "cx16_contract_banked_data_end": CX16_BANKED_RAM_END,
        "cx16_contract_tier_bank_base": CX16_TIER_BANK_BASE,
        "cx16_contract_tier_bank_end": CX16_TIER_BANK_END,
        "cx16_contract_tier_load_base": CX16_TIER_LOAD_BASE,
        "cx16_contract_tier_load_end": CX16_TIER_LOAD_END,
        "cx16_contract_dungeon_module_bank": CX16_DUNGEON_MODULE_BANK,
        "cx16_contract_dungeon_module_load_base": CX16_DUNGEON_MODULE_LOAD_BASE,
        "cx16_contract_dungeon_module_load_end": CX16_DUNGEON_MODULE_LOAD_END,
        "cx16_contract_dungeon_module_entry": CX16_DUNGEON_MODULE_ENTRY,
        "cx16_contract_item_catalog_bank_base": CX16_ITEM_CATALOG_BANK_BASE,
        "cx16_contract_item_catalog_bank_end": CX16_ITEM_CATALOG_BANK_END,
        "cx16_contract_item_catalog_primary_bank": CX16_ITEM_CATALOG_PRIMARY_BANK,
        "cx16_contract_item_catalog_load_base": CX16_ITEM_CATALOG_LOAD_BASE,
        "cx16_contract_item_catalog_load_end": CX16_ITEM_CATALOG_LOAD_END,
        "cx16_contract_title_source_bank": CX16_TITLE_SOURCE_BANK,
        "cx16_contract_title_source_load_base": CX16_TITLE_SOURCE_LOAD_BASE,
        "cx16_contract_title_source_load_end": CX16_TITLE_SOURCE_LOAD_END,
        "cx16_contract_overlay_cache_bank_base": CX16_OVERLAY_CACHE_BANK_BASE,
        "cx16_contract_overlay_cache_bank_end": CX16_OVERLAY_CACHE_BANK_END,
        "cx16_contract_overlay_startup_bank": CX16_OVERLAY_STARTUP_BANK,
        "cx16_contract_overlay_town_bank": CX16_OVERLAY_TOWN_BANK,
        "cx16_contract_overlay_death_bank": CX16_OVERLAY_DEATH_BANK,
        "cx16_contract_overlay_royal_bank": CX16_OVERLAY_ROYAL_BANK,
        "cx16_contract_overlay_gen_bank": CX16_OVERLAY_GEN_BANK,
        "cx16_contract_overlay_help_bank": CX16_OVERLAY_HELP_BANK,
        "cx16_contract_overlay_ui_bank": CX16_OVERLAY_UI_BANK,
        "cx16_contract_overlay_items_bank": CX16_OVERLAY_ITEMS_BANK,
        "cx16_contract_overlay_spell_bank": CX16_OVERLAY_SPELL_BANK,
        "cx16_contract_overlay_disarm_bank": CX16_OVERLAY_DISARM_BANK,
        "cx16_contract_overlay_slot_bank_base": CX16_OVERLAY_SLOT_BANK_BASE,
        "cx16_contract_overlay_slot_bank_end": CX16_OVERLAY_SLOT_BANK_END,
        "cx16_contract_overlay_free_bank_base": CX16_OVERLAY_FREE_BANK_BASE,
        "cx16_contract_overlay_free_bank_end": CX16_OVERLAY_FREE_BANK_END,
        "cx16_contract_data_cache_bank_base": CX16_DATA_CACHE_BANK_BASE,
        "cx16_contract_data_cache_bank_end": CX16_DATA_CACHE_BANK_END,
        "cx16_contract_work_bank_base": CX16_WORK_BANK_BASE,
        "cx16_contract_work_bank_end": CX16_WORK_BANK_END,
    }
    for name, value in expected.items():
        expect_addr(require(labels, name), value, name)

    expect_true(
        require(labels, "cx16_contract_fixed_live_map_end")
        - require(labels, "cx16_contract_fixed_live_map_base")
        + 1
        > CX16_BANKED_RAM_END - CX16_BANKED_RAM_BASE + 1,
        "fixed live map must remain larger than one banked-RAM window",
    )
    expect_true(
        require(labels, "cx16_contract_bfs_queue_end") < require(labels, "cx16_contract_prg_load_base"),
        "BFS queue must stay below the PRG load base",
    )
    expect_true(
        require(labels, "cx16_contract_ram_bank_count")
        * (require(labels, "cx16_contract_banked_ram_end") - require(labels, "cx16_contract_banked_ram_base") + 1)
        == 512 * 1024,
        "bank count must cover baseline 512KB CX16 banked RAM",
    )
    expect_true(
        require(labels, "cx16_contract_ram_bank_last") == require(labels, "cx16_contract_ram_bank_count") - 1,
        "last bank must match bank count",
    )
    expect_true(
        require(labels, "cx16_contract_transient_bank_base")
        == require(labels, "cx16_contract_ram_bank_default") + 1,
        "transient banks must follow default bank",
    )
    expect_true(
        require(labels, "cx16_contract_transient_bank_end") < require(labels, "cx16_contract_tier_bank_base"),
        "transient banks must end before persistent tier banks",
    )
    expect_true(
        require(labels, "cx16_contract_fixed_live_map_end") < require(labels, "cx16_contract_floor_item_base"),
        "floor-item table must stay after fixed live map",
    )
    expect_true(
        require(labels, "cx16_contract_creature_end") - require(labels, "cx16_contract_creature_base") + 1
        >= CX16_ACTIVE_MONSTER_TABLE_BYTES,
        "active monster arena must fit the shared active monster table",
    )
    expect_true(
        require(labels, "cx16_contract_creature_end") < CX16_IO_BASE,
        "fixed world must stay below the VERA I/O hole",
    )
    expect_true(
        require(labels, "cx16_contract_banked_ram_base") > CX16_IO_END,
        "banked RAM must start after the VERA I/O hole",
    )
    expect_true(
        require(labels, "cx16_contract_tier_bank_base") > require(labels, "cx16_contract_ram_bank_default"),
        "tier banks must not use the default RAM bank",
    )
    expect_true(
        require(labels, "cx16_contract_tier_load_base") == require(labels, "cx16_contract_banked_ram_base"),
        "tier load base must match banked RAM base",
    )
    expect_true(
        require(labels, "cx16_contract_dungeon_module_bank") > require(labels, "cx16_contract_tier_bank_end"),
        "dungeon module bank must not overlap tier banks",
    )
    expect_true(
        require(labels, "cx16_contract_dungeon_module_load_base") == require(labels, "cx16_contract_banked_ram_base"),
        "dungeon module load base must match banked RAM base",
    )
    expect_true(
        require(labels, "cx16_contract_dungeon_module_load_end") == require(labels, "cx16_contract_banked_ram_end"),
        "dungeon module load end must match banked RAM end",
    )
    expect_true(
        require(labels, "cx16_contract_item_catalog_bank_base") > require(labels, "cx16_contract_dungeon_module_bank"),
        "item catalog banks must follow dungeon module bank",
    )
    expect_true(
        require(labels, "cx16_contract_item_catalog_bank_end") >= require(labels, "cx16_contract_item_catalog_bank_base"),
        "item catalog bank range must be non-empty",
    )
    expect_true(
        require(labels, "cx16_contract_item_catalog_primary_bank") == require(labels, "cx16_contract_item_catalog_bank_base"),
        "item catalog primary bank must be the first item catalog bank",
    )
    expect_true(
        require(labels, "cx16_contract_item_catalog_load_base") == require(labels, "cx16_contract_banked_ram_base"),
        "item catalog load base must match banked RAM base",
    )
    expect_true(
        require(labels, "cx16_contract_item_catalog_load_end") == require(labels, "cx16_contract_banked_ram_end"),
        "item catalog load end must match banked RAM end",
    )
    expect_true(
        require(labels, "cx16_contract_title_source_bank") > require(labels, "cx16_contract_item_catalog_bank_end"),
        "title source bank must follow item catalog banks",
    )
    expect_true(
        require(labels, "cx16_contract_title_source_load_base") == require(labels, "cx16_contract_banked_ram_base"),
        "title source load base must match banked RAM base",
    )
    expect_true(
        require(labels, "cx16_contract_title_source_load_end") == require(labels, "cx16_contract_banked_ram_end"),
        "title source load end must match banked RAM end",
    )
    expect_true(
        require(labels, "cx16_contract_overlay_cache_bank_base") == require(labels, "cx16_contract_title_source_bank") + 1,
        "overlay cache bank class must follow title source bank",
    )
    expect_true(
        require(labels, "cx16_contract_overlay_slot_bank_base")
        == require(labels, "cx16_contract_overlay_cache_bank_base"),
        "overlay slot range must start at overlay cache bank base",
    )
    overlay_chain = (
        "startup",
        "town",
        "death",
        "royal",
        "gen",
        "help",
        "ui",
        "items",
        "spell",
        "disarm",
    )
    previous_name = None
    for slot_name in overlay_chain:
        symbol_name = f"cx16_contract_overlay_{slot_name}_bank"
        if previous_name is None:
            expect_true(
                require(labels, symbol_name) == require(labels, "cx16_contract_overlay_slot_bank_base"),
                f"overlay {slot_name} bank must start the overlay slot range",
            )
        else:
            expect_true(
                require(labels, symbol_name) == require(labels, previous_name) + 1,
                f"overlay {slot_name} bank must follow {previous_name}",
            )
        previous_name = symbol_name
    expect_true(
        require(labels, "cx16_contract_overlay_slot_bank_end")
        == require(labels, "cx16_contract_overlay_disarm_bank"),
        "overlay slot range must end at disarm bank",
    )
    expect_true(
        require(labels, "cx16_contract_overlay_free_bank_base")
        == require(labels, "cx16_contract_overlay_slot_bank_end") + 1,
        "overlay expansion banks must follow named overlay slots",
    )
    expect_true(
        require(labels, "cx16_contract_overlay_free_bank_end")
        == require(labels, "cx16_contract_overlay_cache_bank_end"),
        "overlay expansion banks must end at overlay cache bank end",
    )
    expect_true(
        require(labels, "cx16_contract_data_cache_bank_base") == require(labels, "cx16_contract_overlay_cache_bank_end") + 1,
        "data cache bank class must follow overlay cache bank class",
    )
    expect_true(
        require(labels, "cx16_contract_work_bank_base") == require(labels, "cx16_contract_data_cache_bank_end") + 1,
        "work bank class must follow data cache bank class",
    )
    expect_true(
        require(labels, "cx16_contract_work_bank_end") == require(labels, "cx16_contract_ram_bank_last"),
        "work bank class must reach last RAM bank",
    )


def check_product_symbols(labels):
    check_contract_symbols(labels)
    program_end = require(labels, "program_end")
    expect_true(program_end >= CX16_RESIDENT_CODE_BASE, "product image ends before resident code starts")
    expect_true(program_end <= CX16_RESIDENT_CODE_LIMIT, "product image overlaps fixed live-map region")


def check_shared_probe_symbols(labels):
    check_contract_symbols(labels)
    program_end = require(labels, "program_end")
    expect_true(program_end > CX16_FIXED_LIVE_MAP_BASE, "shared probe no longer crosses live-map base")
    expect_true(program_end > CX16_IO_BASE, "shared probe no longer crosses VERA I/O hole")
    expect_addr(require(labels, "monster_table"), CX16_CREATURE_BASE, "shared probe monster_table")


def check_product(prg_path, sym_path):
    labels = load_symbols(sym_path)
    check_product_symbols(labels)
    load, end_exclusive = read_prg_span(prg_path)
    program_end = require(labels, "program_end")

    expect_addr(load, CX16_PRG_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_addr(end_exclusive, program_end, f"{os.path.basename(prg_path)} file end")
    return load, end_exclusive, program_end


def check_shared_probe(prg_path, sym_path):
    labels = load_symbols(sym_path)
    check_shared_probe_symbols(labels)
    load, end_exclusive = read_prg_span(prg_path)
    program_end = require(labels, "program_end")

    expect_addr(load, CX16_PRG_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_addr(end_exclusive, program_end, f"{os.path.basename(prg_path)} file end")
    return load, end_exclusive, program_end


def check_tier_prg(prg_path):
    load, end_exclusive = read_prg_span(prg_path)
    expect_addr(load, CX16_TIER_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_true(
        end_exclusive <= CX16_TIER_LOAD_END + 1,
        f"{os.path.basename(prg_path)} exceeds banked RAM window",
    )
    return load, end_exclusive


def check_module_prg(prg_path):
    load, end_exclusive = read_prg_span(prg_path)
    expect_addr(load, CX16_DUNGEON_MODULE_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_true(
        end_exclusive <= CX16_DUNGEON_MODULE_LOAD_END + 1,
        f"{os.path.basename(prg_path)} exceeds banked RAM window",
    )
    return load, end_exclusive


def check_item_prg(prg_path):
    load, end_exclusive = read_prg_span(prg_path)
    expect_addr(load, CX16_ITEM_CATALOG_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_true(
        end_exclusive <= CX16_ITEM_CATALOG_LOAD_END + 1,
        f"{os.path.basename(prg_path)} exceeds banked RAM window",
    )
    return load, end_exclusive


def check_title_prg(prg_path):
    load, end_exclusive = read_prg_span(prg_path)
    expect_addr(load, CX16_TITLE_SOURCE_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_true(
        end_exclusive <= CX16_TITLE_SOURCE_LOAD_END + 1,
        f"{os.path.basename(prg_path)} exceeds banked RAM window",
    )
    return load, end_exclusive


def check_overlay_prg(prg_path):
    load, end_exclusive = read_prg_span(prg_path)
    expect_addr(load, CX16_BANKED_RAM_BASE, f"{os.path.basename(prg_path)} load address")
    expect_true(
        end_exclusive <= CX16_BANKED_RAM_END + 1,
        f"{os.path.basename(prg_path)} exceeds banked RAM window",
    )
    return load, end_exclusive


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--main-prg", required=True)
    parser.add_argument("--main-symbols", required=True)
    parser.add_argument("--title-prg", required=True)
    parser.add_argument("--shared-prg", required=True)
    parser.add_argument("--shared-symbols", required=True)
    parser.add_argument("--tier-prg", action="append", default=[])
    parser.add_argument("--module-prg", action="append", default=[])
    parser.add_argument("--item-prg", action="append", default=[])
    parser.add_argument("--overlay-prg", action="append", default=[])
    args = parser.parse_args()

    product = check_product(args.main_prg, args.main_symbols)
    shared_probe = check_shared_probe(args.shared_prg, args.shared_symbols)
    title = check_title_prg(args.title_prg)
    tiers = [check_tier_prg(path) for path in args.tier_prg]
    modules = [check_module_prg(path) for path in args.module_prg]
    items = [check_item_prg(path) for path in args.item_prg]
    overlays = [check_overlay_prg(path) for path in args.overlay_prg]
    if len(tiers) != 4:
        raise ContractError(f"expected 4 tier PRGs, got {len(tiers)}")
    if len(modules) != 1:
        raise ContractError(f"expected 1 module PRG, got {len(modules)}")
    if len(items) != 1:
        raise ContractError(f"expected 1 item catalog PRG, got {len(items)}")
    if len(overlays) != CX16_OVERLAY_PRELOAD_COUNT:
        raise ContractError(f"expected {CX16_OVERLAY_PRELOAD_COUNT} overlay PRGs, got {len(overlays)}")
    emit_report(product, shared_probe, title, tiers, modules, items, overlays)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
