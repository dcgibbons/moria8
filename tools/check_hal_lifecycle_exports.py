#!/usr/bin/env python3
"""Verify lifecycle HAL service names and common call-site ownership."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_SERVICES = ROOT / "commodore/common/platform_services_api.s"
COMMON_DIR = ROOT / "commodore/common"
PLATFORMS = {
    "c64": ROOT / "commodore/c64/hal/lifecycle_policy.s",
    "c128": ROOT / "commodore/c128/hal/lifecycle_policy.s",
    "plus4": ROOT / "commodore/plus4/hal/lifecycle_policy.s",
}

REQUIRED_EXPORTS = (
    "hal_platform_main_loop_begin",
    "hal_platform_vector_reassert",
    "hal_platform_runtime_resync",
)

FORBIDDEN_COMMON_CALLS = (
    "platform_main_loop_begin_api",
    "platform_vector_reassert_api",
    "platform_runtime_resync_api",
)

REQUIRED_POLICY_CONSTANTS = (
    "hal_platform_reassert_before_message_render",
)


def exported_labels(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    labels: set[str] = set(re.findall(r"(?m)^([A-Za-z_][A-Za-z0-9_]*):", text))
    labels.update(re.findall(r"(?m)^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
    return labels


def common_call_violations() -> list[str]:
    violations: list[str] = []
    for path in sorted(COMMON_DIR.glob("*.s")):
        if path.name == "platform_services_api.s":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for name in FORBIDDEN_COMMON_CALLS:
            if re.search(rf"\b(?:jsr|jmp)\s+{re.escape(name)}\b", text):
                violations.append(f"{path.relative_to(ROOT)} calls {name}")
    return violations


def source_constants(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r"(?m)^\s*\.const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))


def main() -> int:
    labels = exported_labels(PLATFORM_SERVICES)
    missing = [name for name in REQUIRED_EXPORTS if name not in labels]
    violations = common_call_violations()
    policy_missing: list[str] = []
    for platform, path in PLATFORMS.items():
        if not path.exists():
            policy_missing.append(f"{platform}: missing {path.relative_to(ROOT)}")
            continue
        constants = source_constants(path)
        for name in REQUIRED_POLICY_CONSTANTS:
            if name not in constants:
                policy_missing.append(f"{platform}: missing {name} in {path.relative_to(ROOT)}")
    ui_messages_text = (COMMON_DIR / "ui_messages.s").read_text(encoding="utf-8", errors="replace")
    for name in REQUIRED_POLICY_CONSTANTS:
        if name not in ui_messages_text:
            policy_missing.append(f"commodore/common/ui_messages.s does not consume {name}")

    if missing or violations or policy_missing:
        if missing:
            print("Missing lifecycle HAL service exports:")
            for name in missing:
                print(f"  {name}")
        if policy_missing:
            print("Missing lifecycle HAL policy constants:")
            for name in policy_missing:
                print(f"  {name}")
        if violations:
            print("Common code must call lifecycle HAL names, not service-vector internals:")
            for item in violations:
                print(f"  {item}")
        return 1

    print(
        "HAL lifecycle export check passed "
        f"({len(REQUIRED_EXPORTS)} runtime services, "
        f"{len(REQUIRED_POLICY_CONSTANTS)} policy constants, common call-site audit)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
