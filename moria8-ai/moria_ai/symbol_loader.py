"""Parse KickAssembler VICE symbol files (.vs).

Symbol file format (one symbol per line):
    al C:XXXX .symbol_name

Where XXXX is a hex address and symbol_name is the label.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)

# Pattern: "al C:XXXX .symbol_name"
_SYMBOL_RE = re.compile(r"^al\s+C:([0-9a-fA-F]+)\s+\.(.+)$")


def load_symbols(path: str | Path) -> dict[str, int]:
    """Load all symbols from a VICE symbol file.

    Args:
        path: Path to the .vs file.

    Returns:
        Dict mapping symbol name to address.
    """
    symbols: dict[str, int] = {}
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Symbol file not found: {path}")

    with path.open() as f:
        for line in f:
            line = line.strip()
            m = _SYMBOL_RE.match(line)
            if m:
                addr = int(m.group(1), 16)
                name = m.group(2)
                symbols[name] = addr

    logger.info("Loaded %d symbols from %s", len(symbols), path)
    return symbols


def get_required_symbols(symbols: dict[str, int],
                         names: list[str]) -> dict[str, int]:
    """Extract required symbols, raising if any are missing.

    Args:
        symbols: Full symbol dict from load_symbols().
        names: List of symbol names that must be present.

    Returns:
        Dict with only the requested symbols.

    Raises:
        KeyError: If any required symbol is missing.
    """
    result = {}
    missing = []
    for name in names:
        if name in symbols:
            result[name] = symbols[name]
        else:
            missing.append(name)
    if missing:
        raise KeyError(f"Missing required symbols: {', '.join(missing)}")
    return result


# Symbols needed by the AI bridge
REQUIRED_SYMBOLS = [
    "input_get_key",      # Primary breakpoint — game waits for input here
    "monster_table",      # Active monster table base (32 slots x 12 bytes)
]

# Optional symbols — useful but not critical
OPTIONAL_SYMBOLS = [
    "input_get_command",  # Higher-level input (flushes buffer first)
    "game_loop",          # Main game loop entry
    "player_data",        # Player data struct base
    "zp_game_flags",      # Game flags (death detection)
]
