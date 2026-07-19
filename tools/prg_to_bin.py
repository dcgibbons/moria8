#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_addr(text: str) -> int:
    value = int(text, 0)
    if not 0 <= value <= 0xFFFF:
        raise argparse.ArgumentTypeError(f"address out of range: {text}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Strip the 2-byte PRG load header from a Kick Assembler payload "
            "and assert the header matches the expected load address "
            "(guards segment-start drift)."
        )
    )
    parser.add_argument("input", type=Path, help="input .prg with 2-byte load header")
    parser.add_argument("output", type=Path, help="output raw binary")
    parser.add_argument(
        "--expect-addr",
        type=parse_addr,
        required=True,
        metavar="ADDR",
        help="expected load address (e.g. 0x7C00); must match the PRG header",
    )
    args = parser.parse_args()

    data = args.input.read_bytes()
    if len(data) < 2:
        print(f"error: {args.input}: too short for a PRG header ({len(data)} bytes)", file=sys.stderr)
        return 1

    load_addr = data[0] | (data[1] << 8)
    if load_addr != args.expect_addr:
        print(
            f"error: {args.input}: PRG load address ${load_addr:04X} != "
            f"expected ${args.expect_addr:04X}",
            file=sys.stderr,
        )
        return 1

    args.output.write_bytes(data[2:])
    print(f"{args.output}: ${load_addr:04X}, {len(data) - 2} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
