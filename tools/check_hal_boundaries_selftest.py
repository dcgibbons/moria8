#!/usr/bin/env python3
"""Self-test HAL boundary scanner precision."""

from __future__ import annotations

import tempfile
from pathlib import Path

import check_hal_boundaries


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "common"
        root.mkdir()
        sample = root / "sample.s"
        sample.write_text(
            "\n".join(
                (
                    ".const COL_WHITE = $01",
                    ".const SAVE_VERSION = $01",
                    ".byte $01, $02, $03",
                    "    lda #$01",
                    "    adc #$01",
                    "    lda $0101,x",
                    "    lda $01",
                    "    sta $0001",
                    "    inc $01",
                    "    dec $01",
                    "// lda $01 in a comment",
                )
            )
            + "\n",
            encoding="utf-8",
        )

        findings = check_hal_boundaries.find_violations(root)
        bank_tokens = sorted(
            finding.token
            for finding in findings
            if finding.rule == "raw-c64-bank-port"
        )
        expected = ["dec $01", "inc $01", "lda $01", "sta $0001"]
        if bank_tokens != expected:
            print("HAL boundary self-test failed:")
            print(f"  expected: {expected}")
            print(f"  observed: {bank_tokens}")
            return 1

    print("HAL boundary self-test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
