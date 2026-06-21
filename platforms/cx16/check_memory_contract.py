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
CX16_RESIDENT_CODE_BASE = 0x0810
CX16_RESIDENT_CODE_LIMIT = 0x4000
CX16_FIXED_LIVE_MAP_BASE = 0x4000
CX16_FIXED_LIVE_MAP_END = 0x730B
CX16_FLOOR_ITEM_BASE = 0x7400
CX16_FLOOR_ITEM_END = 0x74FF
CX16_CREATURE_BASE = 0x7500
CX16_CREATURE_END = 0x75FF
CX16_BFS_QUEUE_BASE = 0x0400
CX16_BFS_QUEUE_END = 0x07FF
CX16_IO_BASE = 0x9F00
CX16_IO_END = 0x9FFF
CX16_BANKED_RAM_BASE = 0xA000
CX16_BANKED_RAM_END = 0xBFFF


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


def check_contract_symbols(labels):
    expected = {
        "cx16_contract_prg_load_base": CX16_PRG_LOAD_BASE,
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
        require(labels, "cx16_contract_fixed_live_map_end") < require(labels, "cx16_contract_floor_item_base"),
        "floor-item table must stay after fixed live map",
    )
    expect_true(
        require(labels, "cx16_contract_creature_end") < CX16_IO_BASE,
        "fixed world must stay below the VERA I/O hole",
    )
    expect_true(
        require(labels, "cx16_contract_banked_ram_base") > CX16_IO_END,
        "banked RAM must start after the VERA I/O hole",
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


def check_product(prg_path, sym_path):
    labels = load_symbols(sym_path)
    check_product_symbols(labels)
    load, end_exclusive = read_prg_span(prg_path)
    program_end = require(labels, "program_end")

    expect_addr(load, CX16_PRG_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_addr(end_exclusive, program_end, f"{os.path.basename(prg_path)} file end")


def check_shared_probe(prg_path, sym_path):
    labels = load_symbols(sym_path)
    check_shared_probe_symbols(labels)
    load, end_exclusive = read_prg_span(prg_path)
    program_end = require(labels, "program_end")

    expect_addr(load, CX16_PRG_LOAD_BASE, f"{os.path.basename(prg_path)} load address")
    expect_addr(end_exclusive, program_end, f"{os.path.basename(prg_path)} file end")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--main-prg", required=True)
    parser.add_argument("--main-symbols", required=True)
    parser.add_argument("--shared-prg", required=True)
    parser.add_argument("--shared-symbols", required=True)
    args = parser.parse_args()

    check_product(args.main_prg, args.main_symbols)
    check_shared_probe(args.shared_prg, args.shared_symbols)
    print("CX16 memory contract check passed")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
