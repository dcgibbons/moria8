"""High-level game state and action API.

Wraps the VICE bridge, symbol loader, and memory map into a clean
interface for reading game state and sending actions.
"""

from __future__ import annotations

import logging
from pathlib import Path

from .action_map import Action, ACTION_TO_PETSCII
from .memory_map import (
    GameState, MonsterInfo,
    ZP_STATE_START, ZP_STATE_END,
    MAP_BASE, MAP_SIZE,
    MAX_MONSTERS, MONSTER_ENTRY_SIZE,
    parse_zp_state, parse_monster_table,
)
from .symbol_loader import load_symbols, REQUIRED_SYMBOLS
from .vice_bridge import ViceBridge, StoppedEvent, BridgeError, TimeoutError

logger = logging.getLogger(__name__)


class GameInterface:
    """High-level API for interacting with Moria running in VICE.

    Usage:
        gi = GameInterface(symbol_file="commodore/c64/out/main.vs")
        gi.connect()
        gi.setup_breakpoints()

        # Play one turn
        gi.wait_for_input()
        state = gi.read_state()
        gi.send_action(Action.SOUTH)

        gi.disconnect()
    """

    def __init__(self,
                 symbol_file: str | Path,
                 host: str = "127.0.0.1",
                 port: int = 6502,
                 input_timeout: float = 10.0):
        self.bridge = ViceBridge(host, port)
        self.symbol_file = Path(symbol_file)
        self.input_timeout = input_timeout

        # Loaded on connect
        self.symbols: dict[str, int] = {}
        self._input_bp: int | None = None  # checkpoint number
        self._monster_table_addr: int = 0

    def connect(self) -> None:
        """Connect to VICE and load symbols."""
        # Load symbols
        self.symbols = load_symbols(self.symbol_file)

        # Verify required symbols
        for name in REQUIRED_SYMBOLS:
            if name not in self.symbols:
                raise BridgeError(f"Required symbol '{name}' not found in {self.symbol_file}")

        self._monster_table_addr = self.symbols["monster_table"]
        logger.info("input_get_key at $%04X, monster_table at $%04X",
                    self.symbols["input_get_key"],
                    self._monster_table_addr)

        # Connect to VICE
        self.bridge.connect()
        self.bridge.ping()
        logger.info("Connected and symbols loaded")

    def disconnect(self) -> None:
        """Clean up breakpoints and disconnect."""
        if self._input_bp is not None:
            try:
                self.bridge.checkpoint_delete(self._input_bp)
            except BridgeError:
                pass
            self._input_bp = None
        self.bridge.disconnect()

    def setup_breakpoints(self) -> None:
        """Set the primary breakpoint at input_get_key."""
        addr = self.symbols["input_get_key"]
        self._input_bp = self.bridge.checkpoint_set(
            start=addr,
            end=addr,
            stop=True,
            enabled=True,
        )
        logger.info("Breakpoint set at input_get_key ($%04X) = checkpoint #%d",
                    addr, self._input_bp)

    def wait_for_input(self, timeout: float | None = None) -> StoppedEvent:
        """Wait for the game to reach input_get_key (waiting for player input).

        Returns:
            StoppedEvent with the PC address.

        Raises:
            TimeoutError: If VICE doesn't stop within timeout.
        """
        target_pc = self.symbols["input_get_key"]
        
        # Fast path: Check if we are ALREADY stopped at the input prompt.
        try:
            regs = self.bridge.registers_get()
            if regs.get("pc", 0) == target_pc:
                logger.debug("Already stopped at input_get_key ($%04X), forcing resume.", target_pc)
                # We are already here, likely from a previous session.
                # Send a dummy key (like SPACE or a null op) or just continue 
                # so it re-evaluates the loop and hits the breakpoint cleanly.
                # But since the game is waiting for a key, we MUST feed it a key to make it move.
                self.bridge.keyboard_feed(b" ")
                self.bridge.continue_execution()
        except Exception as e:
            logger.debug("Could not read registers (game might be running): %s", e)

        # Slow path: Wait for execution to hit the breakpoint
        t = timeout or self.input_timeout
        return self.bridge.wait_for_stop(timeout=t)

    def read_state(self) -> GameState:
        """Read the full game state from VICE memory.

        Call this after wait_for_input() returns (game is stopped).
        """
        # Read zero page state (0x18–0x5F = 72 bytes)
        zp_data = self.bridge.memory_get(ZP_STATE_START, ZP_STATE_END)
        state = parse_zp_state(zp_data)

        # Read monster table
        mt_size = MAX_MONSTERS * MONSTER_ENTRY_SIZE
        mt_data = self.bridge.memory_get(
            self._monster_table_addr,
            self._monster_table_addr + mt_size - 1,
        )
        state.monsters = parse_monster_table(mt_data, state.monster_count)

        return state

    def read_map(self) -> bytes:
        """Read the full dungeon map (3840 bytes).

        Returns the raw tile bytes. For tile format see memory_map.py.
        """
        return self.bridge.memory_get(MAP_BASE, MAP_BASE + MAP_SIZE - 1)

    def read_messages(self) -> list[str]:
        """Read the two message lines from screen RAM ($0400-$044F).
        
        Converts C64 screen codes to ASCII.
        """
        # Read rows 0 and 1 (80 bytes)
        data = self.bridge.memory_get(0x0400, 0x044F)
        
        lines = []
        for row in range(2):
            row_data = data[row*40 : (row+1)*40]
            # Convert screen codes to ASCII
            chars = []
            for code in row_data:
                # Basic C64 screen code to ASCII conversion
                if code == 0x20: # Space
                    chars.append(' ')
                elif 1 <= code <= 26: # A-Z
                    chars.append(chr(code + 64))
                elif 48 <= code <= 57: # 0-9
                    chars.append(chr(code))
                elif code == 0x00: # @
                    chars.append('@')
                elif code == 0x1B: # [
                    chars.append('[')
                elif code == 0x1D: # ]
                    chars.append(']')
                # Add more as needed, or just a placeholder
                elif 32 <= code <= 63:
                    # ! " # $ % & ' ( ) * + , - . / 0-9 : ; < = > ?
                    # These map directly to ASCII in this range
                    chars.append(chr(code))
                else:
                    chars.append(' ')
            lines.append("".join(chars).strip())
        return [l for l in lines if l]

    def send_action(self, action: Action) -> None:
        """Send a game action and resume execution.

        Injects the PETSCII keycode via Keyboard Feed, then continues
        VICE execution. The game will process the input and eventually
        hit input_get_key again.
        """
        petscii = ACTION_TO_PETSCII[action]
        self.bridge.keyboard_feed(bytes([petscii]))
        self.bridge.continue_execution()
        logger.debug("Sent action %s (PETSCII 0x%02X)", action.name, petscii)

    def send_raw_key(self, petscii: int) -> None:
        """Send a raw PETSCII keycode and resume."""
        self.bridge.keyboard_feed(bytes([petscii]))
        self.bridge.continue_execution()

    def dismiss_more(self) -> None:
        """Send space to dismiss a -more- prompt and resume."""
        self.send_action(Action.SPACE)

    def step(self, action: Action, timeout: float | None = None) -> GameState:
        """Execute one full game turn: send action, wait, read state.

        This is the main loop primitive:
            state = gi.step(Action.SOUTH)

        Args:
            action: The action to perform.
            timeout: Max seconds to wait for the game to process and stop.

        Returns:
            GameState after the action has been processed.
        """
        self.send_action(action)
        self.wait_for_input(timeout)
        return self.read_state()

    def get_registers(self) -> dict[str, int]:
        """Read CPU registers (for debugging)."""
        return self.bridge.registers_get()
