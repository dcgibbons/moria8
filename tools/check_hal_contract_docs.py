#!/usr/bin/env python3
"""Verify HAL contract files document every required non-storage contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = (
    "hal_lifecycle.s",
    "hal_memory.s",
    "hal_irq.s",
    "hal_layout.s",
    "hal_screen.s",
    "hal_input.s",
    "hal_sound.s",
    "hal_overlay.s",
    "hal_entropy.s",
)
CONSTANT_CONTRACTS = {"hal_layout.s", "hal_entropy.s"}


def required_exports(text: str) -> list[str]:
    exports: list[str] = []
    in_required = False
    for line in text.splitlines():
        if line.startswith("// Required exports per platform:"):
            in_required = True
            continue
        if in_required:
            match = re.match(r"//\s+(hal_[A-Za-z0-9_]+)\s*$", line)
            if match:
                exports.append(match.group(1))
                continue
            if line.strip() == "//":
                break
    return exports


def required_constants(text: str) -> list[str]:
    constants: list[str] = []
    in_required = False
    for line in text.splitlines():
        if line.startswith("// Required constants per platform:"):
            in_required = True
            continue
        if in_required:
            match = re.match(r"//\s+(hal_[A-Za-z0-9_]+)\s*$", line)
            if match:
                constants.append(match.group(1))
                continue
            if line.strip() == "//":
                break
    return constants


def main() -> int:
    errors: list[str] = []
    for contract in CONTRACTS:
        path = ROOT / "commodore" / "hal" / contract
        text = path.read_text(encoding="utf-8", errors="replace")
        if contract in CONSTANT_CONTRACTS:
            constants = required_constants(text)
            if not constants:
                errors.append(f"{contract}: no required constants found")
            continue

        exports = required_exports(text)
        if not exports:
            errors.append(f"{contract}: no required exports found")
            continue
        if "Service contracts:" not in text and contract != "hal_overlay.s":
            errors.append(f"{contract}: missing Service contracts section")
        for label in exports:
            if not re.search(rf"(?m)^// - {re.escape(label)}:", text):
                errors.append(f"{contract}: missing contract entry for {label}")

    if errors:
        print("HAL contract documentation check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    total = sum(
        len(required_exports((ROOT / "commodore" / "hal" / contract).read_text()))
        for contract in CONTRACTS
        if contract not in CONSTANT_CONTRACTS
    )
    total_constants = sum(
        len(required_constants((ROOT / "commodore" / "hal" / contract).read_text()))
        for contract in CONSTANT_CONTRACTS
    )
    print(
        "HAL contract documentation check passed "
        f"({total} services, {total_constants} constants)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
