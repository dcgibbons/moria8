"""Action enum and PETSCII key mappings.

Maps high-level game actions to PETSCII codes for injection via
VICE Keyboard Feed command.
"""

from __future__ import annotations

from enum import IntEnum


class Action(IntEnum):
    """Game actions mapped to integer IDs."""
    # Movement (8 directions + rest)
    NORTH     = 0   # 'K'
    SOUTH     = 1   # 'J'
    WEST      = 2   # 'H'
    EAST      = 3   # 'L'
    NORTHWEST = 4   # 'Y'
    NORTHEAST = 5   # 'U'
    SOUTHWEST = 6   # 'B'
    SOUTHEAST = 7   # 'N'
    REST      = 8   # '.'

    # Stairs
    GO_DOWN   = 9   # '>'
    GO_UP     = 10  # '<'

    # Combat / interaction
    SEARCH    = 11  # 'S'
    OPEN      = 12  # 'O' (then direction)
    CLOSE     = 13  # 'C' (shifted, then direction)

    # Items
    PICKUP    = 14  # 'G'
    DROP      = 15  # 'D'
    INVENTORY = 16  # 'I'
    EQUIPMENT = 17  # 'E'
    WEAR      = 18  # 'W'
    TAKEOFF   = 19  # 'T'
    EAT       = 20  # shifted 'E'
    QUAFF     = 21  # 'Q'
    READ_SCR  = 22  # 'R'

    # Magic
    CAST      = 23  # 'M'
    PRAY      = 24  # 'P'

    # Ranged
    FIRE      = 25  # 'F' (then direction)

    # Meta
    LOOK      = 26  # 'X'

    # Sub-prompt responses (directions for Open/Close/Fire)
    DIR_NORTH     = 27
    DIR_SOUTH     = 28
    DIR_WEST      = 29
    DIR_EAST      = 30
    DIR_NORTHWEST = 31
    DIR_NORTHEAST = 32
    DIR_SOUTHWEST = 33
    DIR_SOUTHEAST = 34

    # Misc
    SPACE     = 35  # dismiss -more- prompts
    ESCAPE    = 36  # cancel sub-prompt


# PETSCII codes for each action
# These are the actual byte values injected via Keyboard Feed
ACTION_TO_PETSCII: dict[Action, int] = {
    Action.NORTH:     0x4B,  # 'K'
    Action.SOUTH:     0x4A,  # 'J'
    Action.WEST:      0x48,  # 'H'
    Action.EAST:      0x4C,  # 'L'
    Action.NORTHWEST: 0x59,  # 'Y'
    Action.NORTHEAST: 0x55,  # 'U'
    Action.SOUTHWEST: 0x42,  # 'B'
    Action.SOUTHEAST: 0x4E,  # 'N'
    Action.REST:      0x2E,  # '.'

    Action.GO_DOWN:   0x3E,  # '>'
    Action.GO_UP:     0x3C,  # '<'

    Action.SEARCH:    0x53,  # 'S'
    Action.OPEN:      0x4F,  # 'O'
    Action.CLOSE:     0xC3,  # shifted 'C' (PETSCII)

    Action.PICKUP:    0x47,  # 'G'
    Action.DROP:      0x44,  # 'D'
    Action.INVENTORY: 0x49,  # 'I'
    Action.EQUIPMENT: 0x45,  # 'E'
    Action.WEAR:      0x57,  # 'W'
    Action.TAKEOFF:   0x54,  # 'T'
    Action.EAT:       0xC5,  # shifted 'E'
    Action.QUAFF:     0x51,  # 'Q'
    Action.READ_SCR:  0x52,  # 'R'

    Action.CAST:      0x4D,  # 'M'
    Action.PRAY:      0x50,  # 'P'

    Action.FIRE:      0x46,  # 'F'

    Action.LOOK:      0x58,  # 'X'

    # Direction keys (same PETSCII as movement)
    Action.DIR_NORTH:     0x4B,
    Action.DIR_SOUTH:     0x4A,
    Action.DIR_WEST:      0x48,
    Action.DIR_EAST:      0x4C,
    Action.DIR_NORTHWEST: 0x59,
    Action.DIR_NORTHEAST: 0x55,
    Action.DIR_SOUTHWEST: 0x42,
    Action.DIR_SOUTHEAST: 0x4E,

    Action.SPACE:     0x20,  # space
    Action.ESCAPE:    0x03,  # RUN/STOP (C64 escape key)
}


# Simplified action set for initial testing/training
SIMPLE_ACTIONS = [
    Action.NORTH, Action.SOUTH, Action.WEST, Action.EAST,
    Action.NORTHWEST, Action.NORTHEAST, Action.SOUTHWEST, Action.SOUTHEAST,
    Action.REST,
    Action.GO_DOWN, Action.GO_UP,
    Action.SEARCH,
    Action.PICKUP,
    Action.EAT, Action.QUAFF,
]
