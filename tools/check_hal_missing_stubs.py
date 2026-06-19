#!/usr/bin/env python3
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = [
    "hal_lifecycle.s",
    "hal_memory.s",
    "hal_irq.s",
    "hal_screen.s",
    "hal_input.s",
    "hal_sound.s",
]
STUB_FILE = ROOT / "core" / "hal_missing_service_stubs.s"


def required_exports(path):
    exports = []
    in_required = False
    for line in path.read_text().splitlines():
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


def stub_labels(text):
    return set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*):", text, re.MULTILINE))


def main():
    expected = []
    for contract in CONTRACTS:
        expected.extend(required_exports(ROOT / "platforms" / "commodore" / "hal" / contract))

    labels = stub_labels(STUB_FILE.read_text())
    missing = [name for name in expected if name not in labels]
    allowed_extra = {"hal_missing_service", "hal_missing_service_id"}
    extra = sorted(
        name for name in labels
        if name.startswith("hal_") and name not in expected and name not in allowed_extra
    )

    if missing or extra:
        if missing:
            print("Missing fail-loud HAL stubs:")
            for name in missing:
                print(f"  {name}")
        if extra:
            print("Unexpected fail-loud HAL stubs:")
            for name in extra:
                print(f"  {name}")
        return 1

    print(f"HAL missing-service stubs cover {len(expected)} required exports.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
