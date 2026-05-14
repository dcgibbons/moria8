#!/usr/bin/env python3
"""Guard Plus/4 HAL-owned services against C64-shaped compatibility labels."""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CHECKS = (
    (
        ROOT / "commodore" / "plus4" / "main.s",
        (
            "c64_irq_hidden_rom",
            "c64_install_ram_irq_vectors",
            "platform_main_loop_begin_c64",
            "platform_vector_reassert_c64",
            "platform_runtime_resync_c64",
            "platform_services_install64",
        ),
    ),
    (
        ROOT / "commodore" / "plus4" / "memory.s",
        (
            "C64_TIER_NAME_POOL_BASE",
            "C64_TIER_NAME_POOL_END",
        ),
    ),
    (
        ROOT / "commodore" / "plus4" / "harnessplus4.py",
        (
            ".c64_install_ram_irq_vectors",
        ),
    ),
    (
        ROOT / "commodore" / "common" / "player_items.s",
        (
            "c64_install_ram_irq_vectors",
            "C64_PRODUCT_OVERLAY_RUNTIME",
            "C64_PRODUCT_IRQ_VECTOR_RUNTIME",
        ),
    ),
    (
        ROOT / "commodore" / "plus4" / "main.s",
        (
            "C64_PRODUCT_OVERLAY_RUNTIME",
            "C64_PRODUCT_IRQ_VECTOR_RUNTIME",
        ),
    ),
)


def strip_asm_comment(line: str) -> str:
    return line.split("//", 1)[0]


def main() -> int:
    errors: list[str] = []
    for path, forbidden in CHECKS:
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_number, raw_line in enumerate(text.splitlines(), start=1):
            line = raw_line
            if path.suffix == ".s":
                line = strip_asm_comment(line)
            for token in forbidden:
                if re.search(rf"(?<![A-Za-z0-9_]){re.escape(token)}(?![A-Za-z0-9_])", line):
                    errors.append(f"{path.relative_to(ROOT)}:{line_number}: forbidden {token}")

    if errors:
        print("Plus/4 HAL independence check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    print("Plus/4 HAL independence check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
