"""Tests for symbol_loader.py — parsing KickAssembler .vs files."""

import tempfile
from pathlib import Path

import pytest

from moria_ai.symbol_loader import load_symbols, get_required_symbols


SAMPLE_VS = """\
al C:0f69 .input_get_key
al C:3996 .monster_table
al C:002b .zp_player_x
al C:002c .zp_player_y
al C:c000 .map_base
al C:1475 .player_data
al C:76ad .rv_mon_x
"""


@pytest.fixture
def vs_file(tmp_path):
    p = tmp_path / "main.vs"
    p.write_text(SAMPLE_VS)
    return p


def test_load_symbols_parses_addresses(vs_file):
    syms = load_symbols(vs_file)
    assert syms["input_get_key"] == 0x0F69
    assert syms["monster_table"] == 0x3996
    assert syms["zp_player_x"] == 0x002B
    assert syms["map_base"] == 0xC000


def test_load_symbols_count(vs_file):
    syms = load_symbols(vs_file)
    assert len(syms) == 7


def test_load_symbols_file_not_found():
    with pytest.raises(FileNotFoundError):
        load_symbols("/nonexistent/file.vs")


def test_get_required_symbols_success(vs_file):
    syms = load_symbols(vs_file)
    result = get_required_symbols(syms, ["input_get_key", "monster_table"])
    assert result["input_get_key"] == 0x0F69
    assert len(result) == 2


def test_get_required_symbols_missing(vs_file):
    syms = load_symbols(vs_file)
    with pytest.raises(KeyError, match="game_loop"):
        get_required_symbols(syms, ["input_get_key", "game_loop"])


def test_load_actual_symbol_file():
    """Test against the real build output if available."""
    vs_path = Path(__file__).resolve().parent.parent.parent / "commodore" / "c64" / "out" / "main.vs"
    if not vs_path.exists():
        pytest.skip("Build output not available — run 'make build' first")

    syms = load_symbols(vs_path)
    assert "input_get_key" in syms
    assert "monster_table" in syms
    assert syms["input_get_key"] > 0
    assert len(syms) > 100  # should have hundreds of symbols
