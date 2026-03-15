"""C64 memory map for game state extraction.

All addresses verified against commodore/c64/zeropage.s and commodore/c64/memory.s.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field

# ============================================================
# Zero Page — Player State
# ============================================================
# Safe zone (never touched by KERNAL file I/O)
ZP_PLAYER_X       = 0x2B
ZP_PLAYER_Y       = 0x2C
ZP_PLAYER_HP_LO   = 0x2D
ZP_PLAYER_HP_HI   = 0x2E
ZP_PLAYER_MHP_LO  = 0x2F
ZP_PLAYER_MHP_HI  = 0x30
ZP_PLAYER_MP      = 0x31
ZP_PLAYER_MMP     = 0x32
ZP_PLAYER_LVL     = 0x33
ZP_PLAYER_DLVL    = 0x34
ZP_PLAYER_AC      = 0x35
ZP_PLAYER_STR     = 0x36
ZP_PLAYER_INT     = 0x37
ZP_PLAYER_WIS     = 0x38
ZP_PLAYER_DEX     = 0x39
ZP_PLAYER_CON     = 0x3A
ZP_PLAYER_CHR     = 0x3B
ZP_PLAYER_RACE    = 0x3C
ZP_PLAYER_CLASS   = 0x3D
ZP_PLAYER_FOOD_LO = 0x3E
ZP_PLAYER_FOOD_HI = 0x3F
ZP_TURN_LO        = 0x40
ZP_TURN_HI        = 0x41
ZP_REGEN_COUNTER  = 0x42
ZP_GAME_FLAGS     = 0x43
ZP_CURRENT_TIER   = 0x44
ZP_RUN_DIR        = 0x47
ZP_INPUT_CMD      = 0x48
ZP_HUNGER_STATE   = 0x4A
ZP_LIGHT_RADIUS   = 0x4B
ZP_MON_COUNT      = 0x4D
ZP_ITEM_COUNT     = 0x4E

# Message flags — used to detect -more- prompts
ZP_MSG_FLAGS      = 0x18

# Status effects ($50–$5F)
ZP_EFFECT_POISON      = 0x50
ZP_EFFECT_BLIND       = 0x51
ZP_EFFECT_CONFUSE     = 0x52
ZP_EFFECT_PARALYZE    = 0x53
ZP_EFFECT_SPEED       = 0x54  # >0 haste, <0 slow (signed)
ZP_EFFECT_PROTECTION  = 0x55
ZP_EFFECT_INVISIBLE   = 0x56
ZP_EFFECT_INFRAVISION = 0x57
ZP_EFFECT_RESISTANCE  = 0x58
ZP_EFFECT_BLESS       = 0x59
ZP_EFFECT_HEROISM     = 0x5A
ZP_EFFECT_REGEN       = 0x5B
ZP_EFFECT_FREE_ACTION = 0x5C
ZP_EFFECT_SEE_INVIS   = 0x5D
ZP_EFFECT_RECALL      = 0x5E
ZP_EFFECT_DEATH_SRC   = 0x5F

# Range for bulk ZP read
ZP_STATE_START = ZP_MSG_FLAGS  # 0x18
ZP_STATE_END   = 0x5F

# Game flags bits
GF_DEAD   = 0x01
GF_WIZARD = 0x02

# ============================================================
# Map
# ============================================================
MAP_BASE   = 0xC000
MAP_SIZE   = 3840      # 80 x 48 tiles
MAP_WIDTH  = 80
MAP_HEIGHT = 48

# Tile byte layout:
#   Bits 7-4: tile type
#   Bit 3:    lit
#   Bit 2:    visited/known
#   Bit 1:    treasure present
#   Bit 0:    creature present

# ============================================================
# Floor Items
# ============================================================
FLOOR_ITEM_BASE    = 0xCF00
MAX_FLOOR_ITEMS    = 32
# 8 arrays x 32 entries = 256 bytes total
FI_ITEM_ID  = FLOOR_ITEM_BASE + 0    # $CF00
FI_X        = FLOOR_ITEM_BASE + 32   # $CF20
FI_Y        = FLOOR_ITEM_BASE + 64   # $CF40
FI_QTY      = FLOOR_ITEM_BASE + 96   # $CF60
FI_P1       = FLOOR_ITEM_BASE + 128  # $CF80
FI_FLAGS    = FLOOR_ITEM_BASE + 160  # $CFA0
FI_EGO      = FLOOR_ITEM_BASE + 192  # $CFC0
FI_QTY_HI   = FLOOR_ITEM_BASE + 224  # $CFE0

# ============================================================
# Active Monster Table
# ============================================================
MAX_MONSTERS       = 32
MONSTER_ENTRY_SIZE = 12
# monster_table address comes from symbol file

# Entry offsets (within each 12-byte record)
MX_X         = 0
MX_Y         = 1
MX_TYPE      = 2
MX_HP_LO     = 3
MX_HP_HI     = 4
MX_FLAGS     = 5
MX_SPEED_CNT = 6
MX_SLEEP_CUR = 7
MX_STUN      = 8
MX_CONFUSE   = 9
MX_FLEE_LO   = 10
MX_FLEE_HI   = 11


# ============================================================
# Game State Dataclass
# ============================================================

@dataclass
class MonsterInfo:
    """One active monster."""
    slot: int
    x: int
    y: int
    type_id: int
    hp: int
    flags: int
    speed_cnt: int
    sleep: int
    stun: int
    confuse: int


@dataclass
class GameState:
    """Snapshot of game state read from VICE memory."""
    # Player
    player_x: int = 0
    player_y: int = 0
    hp: int = 0
    max_hp: int = 0
    mp: int = 0
    max_mp: int = 0
    player_level: int = 0
    dungeon_level: int = 0
    ac: int = 0
    stats: tuple[int, ...] = (0, 0, 0, 0, 0, 0)  # STR, INT, WIS, DEX, CON, CHR
    race: int = 0
    player_class: int = 0
    food: int = 0
    turn_count: int = 0
    hunger_state: int = 0
    light_radius: int = 0
    monster_count: int = 0
    item_count: int = 0
    game_flags: int = 0
    run_dir: int = 0xFF
    msg_flags: int = 0

    # Status effects (raw bytes $50–$5F)
    effects: bytes = b"\x00" * 16

    # Monsters
    monsters: list[MonsterInfo] = field(default_factory=list)

    @property
    def is_dead(self) -> bool:
        return bool(self.game_flags & GF_DEAD)

    @property
    def is_wizard(self) -> bool:
        return bool(self.game_flags & GF_WIZARD)

    @property
    def hp_percent(self) -> float:
        if self.max_hp == 0:
            return 0.0
        return self.hp / self.max_hp

    @property
    def is_poisoned(self) -> bool:
        return self.effects[0] > 0

    @property
    def is_blind(self) -> bool:
        return self.effects[1] > 0

    @property
    def is_confused(self) -> bool:
        return self.effects[2] > 0

    @property
    def is_paralyzed(self) -> bool:
        return self.effects[3] > 0


def parse_zp_state(data: bytes) -> GameState:
    """Parse zero page bytes into a GameState.

    Args:
        data: Bytes read from ZP_STATE_START (0x18) to ZP_STATE_END (0x5F),
              so data[0] corresponds to address 0x18.
    """
    def zp(addr: int) -> int:
        return data[addr - ZP_STATE_START]

    def zp16(lo_addr: int) -> int:
        return zp(lo_addr) | (zp(lo_addr + 1) << 8)

    return GameState(
        player_x=zp(ZP_PLAYER_X),
        player_y=zp(ZP_PLAYER_Y),
        hp=zp16(ZP_PLAYER_HP_LO),
        max_hp=zp16(ZP_PLAYER_MHP_LO),
        mp=zp(ZP_PLAYER_MP),
        max_mp=zp(ZP_PLAYER_MMP),
        player_level=zp(ZP_PLAYER_LVL),
        dungeon_level=zp(ZP_PLAYER_DLVL),
        ac=zp(ZP_PLAYER_AC),
        stats=(zp(ZP_PLAYER_STR), zp(ZP_PLAYER_INT), zp(ZP_PLAYER_WIS),
               zp(ZP_PLAYER_DEX), zp(ZP_PLAYER_CON), zp(ZP_PLAYER_CHR)),
        race=zp(ZP_PLAYER_RACE),
        player_class=zp(ZP_PLAYER_CLASS),
        food=zp16(ZP_PLAYER_FOOD_LO),
        turn_count=zp16(ZP_TURN_LO),
        hunger_state=zp(ZP_HUNGER_STATE),
        light_radius=zp(ZP_LIGHT_RADIUS),
        monster_count=zp(ZP_MON_COUNT),
        item_count=zp(ZP_ITEM_COUNT),
        game_flags=zp(ZP_GAME_FLAGS),
        run_dir=zp(ZP_RUN_DIR),
        msg_flags=zp(ZP_MSG_FLAGS),
        effects=data[ZP_EFFECT_POISON - ZP_STATE_START:
                      ZP_EFFECT_DEATH_SRC - ZP_STATE_START + 1],
    )


def parse_monster_table(data: bytes, count: int) -> list[MonsterInfo]:
    """Parse the active monster table.

    Args:
        data: Raw bytes of monster_table (MAX_MONSTERS * MONSTER_ENTRY_SIZE).
        count: Number of active monsters (from zp_mon_count).

    Returns:
        List of MonsterInfo for occupied slots.
    """
    monsters = []
    for i in range(MAX_MONSTERS):
        offset = i * MONSTER_ENTRY_SIZE
        entry = data[offset:offset + MONSTER_ENTRY_SIZE]
        if len(entry) < MONSTER_ENTRY_SIZE:
            break
        type_id = entry[MX_TYPE]
        if type_id == 0xFF:  # EMPTY_SLOT
            continue
        monsters.append(MonsterInfo(
            slot=i,
            x=entry[MX_X],
            y=entry[MX_Y],
            type_id=type_id,
            hp=entry[MX_HP_LO] | (entry[MX_HP_HI] << 8),
            flags=entry[MX_FLAGS],
            speed_cnt=entry[MX_SPEED_CNT],
            sleep=entry[MX_SLEEP_CUR],
            stun=entry[MX_STUN],
            confuse=entry[MX_CONFUSE],
        ))
    return monsters
