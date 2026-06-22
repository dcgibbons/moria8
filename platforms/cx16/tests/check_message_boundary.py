#!/usr/bin/env python3
"""Guard CX16 gameplay prose from leaking back into main.s."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "main.s"

FORBIDDEN_MAIN_PHRASES = {
    "Rested and resupplied.",
    "Dungeon level ",
    " ready.",
    "You die. Shift-Q returns to title.",
    "That is only useful in the dungeon.",
    "You hit the kobold.",
    "You have slain the kobold.",
    "The kobold hits you.",
}


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main():
    main_text = MAIN.read_text()

    leaked_phrases = sorted(phrase for phrase in FORBIDDEN_MAIN_PHRASES if phrase in main_text)
    if leaked_phrases:
        return fail("CX16 scaffold message text leaked into main.s: " + ", ".join(leaked_phrases))

    if '#import "../../core/gameplay_messages.s"' not in main_text:
        return fail('main.s must import shared gameplay messages for non-platform gameplay prose')

    print("CX16 message boundary check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
