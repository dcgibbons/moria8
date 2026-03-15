#!/usr/bin/env python3
"""Smoke test: connect to VICE, read game state, play random turns.

Prerequisites:
  1. Build the game:  make build  (from project root)
  2. Launch VICE:     ./scripts/launch_vice.sh
  3. Navigate past character creation manually (for now)
  4. Run this script: python3 scripts/smoke_test.py

This will:
  - Connect to VICE binary monitor on localhost:6502
  - Set a breakpoint at input_get_key
  - Wait for the game to reach the input prompt
  - Read and print game state
  - Play N random turns, printing state after each
"""

import argparse
import logging
import random
import sys
import time
from pathlib import Path

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from moria_ai.game_interface import GameInterface
from moria_ai.action_map import Action, SIMPLE_ACTIONS


def main():
    parser = argparse.ArgumentParser(description="Moria AI smoke test")
    parser.add_argument("--port", type=int, default=6502, help="VICE monitor port")
    parser.add_argument("--turns", type=int, default=20, help="Number of random turns")
    parser.add_argument("--symbols", type=str,
                        default=str(Path(__file__).resolve().parent.parent.parent /
                                    "commodore" / "c64" / "out" / "main.vs"),
                        help="Path to .vs symbol file")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s: %(message)s",
    )

    gi = GameInterface(symbol_file=args.symbols, port=args.port)

    try:
        print(f"Connecting to VICE on port {args.port}...")
        gi.connect()
        print("Connected! Setting breakpoints...")
        gi.setup_breakpoints()

        print("Waiting for game to reach input prompt...")
        print("  (Make sure you've completed character creation in VICE)")
        gi.wait_for_input(timeout=30.0)

        state = gi.read_state()
        print_state(state, turn=0)

        print(f"\nPlaying {args.turns} random turns...\n")
        for turn in range(1, args.turns + 1):
            action = random.choice(SIMPLE_ACTIONS)
            state = gi.step(action)
            print_state(state, turn=turn, action=action)

            if state.is_dead:
                print("\n*** PLAYER DIED ***")
                break

            time.sleep(0.05)  # Small delay for readability

        print("\nSmoke test complete!")

    except KeyboardInterrupt:
        print("\nInterrupted.")
    except Exception as e:
        print(f"\nError: {e}")
        raise
    finally:
        gi.disconnect()
        print("Disconnected.")


def print_state(state, turn=0, action=None):
    action_str = f" [{action.name}]" if action else ""
    print(f"Turn {turn:4d}{action_str}: "
          f"pos=({state.player_x},{state.player_y}) "
          f"HP={state.hp}/{state.max_hp} "
          f"MP={state.mp}/{state.max_mp} "
          f"dlvl={state.dungeon_level} "
          f"hunger={state.hunger_state} "
          f"monsters={state.monster_count} "
          f"flags=0x{state.game_flags:02X}")


if __name__ == "__main__":
    main()
