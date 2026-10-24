"""C64 screen RAM decoding (mixed-case character set, 40x25)."""

from __future__ import annotations

COLS = 40
ROWS = 25


def screen_code_to_char(code: int) -> str:
    code &= 0x7F  # reverse video bit
    if code == 0x00:
        return "@"
    if 0x01 <= code <= 0x1A:
        return chr(ord("a") + code - 1)
    if code in (0x1B, 0x1D):
        return "[" if code == 0x1B else "]"
    if 0x20 <= code <= 0x3F:
        return chr(code)
    if 0x41 <= code <= 0x5A:
        return chr(code)
    return "·"  # graphics glyph


# Screen code -> character for all 256 codes, for one-call decoding of a row.
_DECODE = {code: screen_code_to_char(code) for code in range(256)}


def decode_rows(screen: bytes) -> list[str]:
    text = screen[:COLS * ROWS].decode("latin-1").translate(_DECODE)
    return [text[r * COLS:(r + 1) * COLS] for r in range(ROWS)]


def text(rows: list[str]) -> str:
    return "\n".join(rows)
