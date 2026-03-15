"""Tests for memory_map.py — parsing raw memory into GameState."""

import pytest

from moria_ai.memory_map import (
    parse_zp_state, parse_monster_table,
    ZP_STATE_START, ZP_STATE_END,
    ZP_PLAYER_X, ZP_PLAYER_HP_LO, ZP_PLAYER_HP_HI,
    ZP_PLAYER_DLVL, ZP_GAME_FLAGS, ZP_HUNGER_STATE,
    ZP_EFFECT_POISON,
    MONSTER_ENTRY_SIZE, MAX_MONSTERS,
    MX_X, MX_Y, MX_TYPE, MX_HP_LO, MX_HP_HI, MX_FLAGS,
    GF_DEAD,
)


def make_zp_data(overrides=None):
    """Create a zero page data buffer with specified values.

    Args:
        overrides: dict mapping ZP address (int) to byte value (int).
    """
    size = ZP_STATE_END - ZP_STATE_START + 1
    data = bytearray(size)
    if overrides:
        for addr, val in overrides.items():
            data[addr - ZP_STATE_START] = val
    return bytes(data)


def test_parse_zp_basic():
    data = make_zp_data({
        ZP_PLAYER_X: 40,
        ZP_PLAYER_X + 1: 24,  # player_y
        ZP_PLAYER_HP_LO: 0x1E,  # 30
        ZP_PLAYER_HP_HI: 0x00,
        ZP_PLAYER_DLVL: 3,
        ZP_HUNGER_STATE: 1,
    })
    state = parse_zp_state(data)
    assert state.player_x == 40
    assert state.player_y == 24
    assert state.hp == 30
    assert state.dungeon_level == 3
    assert state.hunger_state == 1


def test_parse_zp_16bit_hp():
    data = make_zp_data({
        ZP_PLAYER_HP_LO: 0xF4,
        ZP_PLAYER_HP_HI: 0x01,
    })
    state = parse_zp_state(data)
    assert state.hp == 0x01F4  # 500


def test_parse_zp_dead():
    data = make_zp_data({ZP_GAME_FLAGS: GF_DEAD})
    state = parse_zp_state(data)
    assert state.is_dead


def test_parse_zp_not_dead():
    data = make_zp_data()
    state = parse_zp_state(data)
    assert not state.is_dead


def test_parse_zp_effects():
    data = make_zp_data({ZP_EFFECT_POISON: 5})
    state = parse_zp_state(data)
    assert state.is_poisoned
    assert not state.is_blind


def test_hp_percent():
    data = make_zp_data({
        ZP_PLAYER_HP_LO: 25,
        ZP_PLAYER_HP_HI: 0,
        0x2F: 100,  # max hp lo
        0x30: 0,    # max hp hi
    })
    state = parse_zp_state(data)
    assert state.hp_percent == 0.25


def test_parse_monster_table_empty():
    data = bytes([0xFF] * MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    monsters = parse_monster_table(data, 0)
    assert len(monsters) == 0


def test_parse_monster_table_one():
    data = bytearray(MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    # Fill all slots with empty
    for i in range(MAX_MONSTERS):
        data[i * MONSTER_ENTRY_SIZE + MX_TYPE] = 0xFF
    # Set slot 0 to an active monster
    data[MX_X] = 10
    data[MX_Y] = 20
    data[MX_TYPE] = 5
    data[MX_HP_LO] = 30
    data[MX_HP_HI] = 0
    data[MX_FLAGS] = 0x01  # awake

    monsters = parse_monster_table(bytes(data), 1)
    assert len(monsters) == 1
    m = monsters[0]
    assert m.slot == 0
    assert m.x == 10
    assert m.y == 20
    assert m.type_id == 5
    assert m.hp == 30
    assert m.flags == 0x01


def test_parse_monster_table_multiple():
    data = bytearray(MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    for i in range(MAX_MONSTERS):
        data[i * MONSTER_ENTRY_SIZE + MX_TYPE] = 0xFF

    # Slot 0
    off = 0
    data[off + MX_TYPE] = 3
    data[off + MX_HP_LO] = 10

    # Slot 2 (skip slot 1)
    off = 2 * MONSTER_ENTRY_SIZE
    data[off + MX_TYPE] = 7
    data[off + MX_HP_LO] = 50
    data[off + MX_HP_HI] = 1  # HP = 256 + 50 = 306

    monsters = parse_monster_table(bytes(data), 2)
    assert len(monsters) == 2
    assert monsters[0].slot == 0
    assert monsters[1].slot == 2
    assert monsters[1].hp == 306
