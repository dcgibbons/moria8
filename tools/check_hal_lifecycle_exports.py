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
PLATFORM_MAINS = {
    "c64": ROOT / "commodore/c64/main.s",
    "c128": ROOT / "commodore/c128/main.s",
    "plus4": ROOT / "commodore/plus4/main.s",
}

REQUIRED_EXPORTS = (
    "hal_platform_main_loop_begin",
    "hal_platform_vector_reassert",
    "hal_platform_runtime_resync",
)

REQUIRED_DIRECT_EXPORTS = (
    "hal_platform_character_sheet_begin",
)

FORBIDDEN_COMMON_CALLS = (
    "platform_main_loop_begin_api",
    "platform_vector_reassert_api",
    "platform_runtime_resync_api",
)

REQUIRED_POLICY_CONSTANTS = (
    "hal_platform_reassert_before_message_render",
    "hal_platform_restore_tier_after_overlay",
    "hal_platform_string_bank_load_invalidates_tier",
    "hal_platform_mark_modal_restore_perf",
    "hal_platform_perf_p1_command_instrumentation",
    "hal_platform_render_ball_effect_direct_perf",
    "hal_platform_character_sheet_begin_enabled",
    "hal_platform_character_background_resync",
    "hal_platform_player_magic_helpers_external",
    "hal_platform_item_action_key_restores_bank",
    "hal_platform_ego_holy_avenger_string_external",
    "hal_platform_ego_ac_bonus_external",
    "hal_platform_chargen_runtime_resync",
    "hal_platform_chargen_cutpoint",
    "hal_platform_wizard_entry_uses_overlay",
    "hal_platform_wizard_40col_resident_enabled",
    "hal_platform_wizard_reveal_uses_trampoline",
    "hal_platform_levelup_magic_uses_trampoline",
    "hal_platform_title_sysinfo_80col",
    "hal_platform_title_sysinfo_sx64_probe",
    "hal_platform_player_move_diag_labels",
    "hal_platform_describe_look_masks_irq",
    "hal_platform_game_loop_runtime_resync",
    "hal_platform_game_loop_main_loop_begin",
    "hal_platform_game_loop_restore_generation_overlay",
    "hal_platform_game_loop_save_clears_screen",
    "hal_platform_game_loop_save_return_view",
    "hal_platform_game_loop_run_stop_reset_input",
    "hal_platform_game_loop_scroll_delta_render",
    "hal_platform_game_loop_item_actions_trampolined",
    "hal_platform_overlay_count",
    "hal_platform_overlay_state_external",
    "hal_platform_overlay_force_reload",
    "hal_platform_overlay_tier_cache_guard",
    "hal_platform_overlay_cache_enabled",
    "hal_platform_overlay_reu_stash_enabled",
    "hal_platform_overlay_prompt_program_media",
    "hal_platform_overlay_cpu_port_dma_bank",
    "hal_platform_item_prompt_overlay_runtime",
    "hal_platform_item_prompt_reload_installs_irq",
    "hal_platform_item_prompt_reload_resync",
    "hal_platform_equip_prepare_key_before_display",
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
    direct_missing: list[str] = []
    for platform, path in PLATFORMS.items():
        if not path.exists():
            policy_missing.append(f"{platform}: missing {path.relative_to(ROOT)}")
            continue
        constants = source_constants(path)
        for name in REQUIRED_POLICY_CONSTANTS:
            if name not in constants:
                policy_missing.append(f"{platform}: missing {name} in {path.relative_to(ROOT)}")
    for platform, path in PLATFORM_MAINS.items():
        if platform != "c128":
            continue
        labels = exported_labels(path)
        for name in REQUIRED_DIRECT_EXPORTS:
            if name not in labels:
                direct_missing.append(f"{platform}: missing {name} in {path.relative_to(ROOT)}")
    policy_consumers = {
        "hal_platform_reassert_before_message_render": (COMMON_DIR / "ui_messages.s",),
        "hal_platform_restore_tier_after_overlay": (
            COMMON_DIR / "ui_restore.s",
            "HAL_PLATFORM_RESTORE_TIER_AFTER_OVERLAY",
        ),
        "hal_platform_string_bank_load_invalidates_tier": (
            COMMON_DIR / "string_bank.s",
            "HAL_PLATFORM_STRING_BANK_LOAD_INVALIDATES_TIER",
        ),
        "hal_platform_mark_modal_restore_perf": (COMMON_DIR / "ui_restore.s",),
        "hal_platform_perf_p1_command_instrumentation": (COMMON_DIR / "game_loop_helpers.s",),
        "hal_platform_render_ball_effect_direct_perf": (COMMON_DIR / "player_magic_ball.s",),
        "hal_platform_levelup_magic_uses_trampoline": (COMMON_DIR / "combat.s",),
        "hal_platform_character_background_resync": (COMMON_DIR / "player.s",),
        "hal_platform_player_magic_helpers_external": (
            COMMON_DIR / "player_magic.s",
            "HAL_PLATFORM_PLAYER_MAGIC_HELPERS_EXTERNAL",
        ),
        "hal_platform_item_action_key_restores_bank": (COMMON_DIR / "item_actions_overlay.s",),
        "hal_platform_chargen_runtime_resync": (COMMON_DIR / "player_create.s",),
        "hal_platform_chargen_cutpoint": (COMMON_DIR / "player_create.s",),
        "hal_platform_title_sysinfo_80col": (
            COMMON_DIR / "title_sysinfo_banked.s",
            "HAL_PLATFORM_TITLE_SYSINFO_80COL",
        ),
        "hal_platform_title_sysinfo_sx64_probe": (
            COMMON_DIR / "title_sysinfo_banked.s",
            "HAL_PLATFORM_TITLE_SYSINFO_SX64_PROBE",
        ),
        "hal_platform_player_move_diag_labels": (
            COMMON_DIR / "player_move.s",
            "HAL_PLATFORM_GAME_LOOP_PLAYER_MOVE_DIAG_LABELS",
        ),
        "hal_platform_describe_look_masks_irq": (COMMON_DIR / "player_move.s",),
        "hal_platform_game_loop_runtime_resync": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_RUNTIME_RESYNC",
        ),
        "hal_platform_game_loop_main_loop_begin": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_MAIN_LOOP_BEGIN",
        ),
        "hal_platform_game_loop_restore_generation_overlay": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_RESTORE_GENERATION_OVERLAY",
        ),
        "hal_platform_game_loop_save_clears_screen": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_SAVE_CLEARS_SCREEN",
        ),
        "hal_platform_game_loop_save_return_view": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_SAVE_RETURN_VIEW",
        ),
        "hal_platform_game_loop_run_stop_reset_input": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_RUN_STOP_RESET_INPUT",
        ),
        "hal_platform_game_loop_scroll_delta_render": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_SCROLL_DELTA_RENDER",
        ),
        "hal_platform_game_loop_item_actions_trampolined": (
            COMMON_DIR / "game_loop.s",
            "HAL_PLATFORM_GAME_LOOP_ITEM_ACTIONS_TRAMPOLINED",
        ),
        "hal_platform_overlay_count": (COMMON_DIR / "overlay.s",),
        "hal_platform_overlay_state_external": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_STATE_LOCAL",
        ),
        "hal_platform_overlay_force_reload": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_FORCE_RELOAD",
        ),
        "hal_platform_overlay_tier_cache_guard": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_TIER_CACHE_GUARD",
        ),
        "hal_platform_overlay_cache_enabled": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_CACHE_ENABLED",
        ),
        "hal_platform_overlay_reu_stash_enabled": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_REU_STASH_ENABLED",
        ),
        "hal_platform_overlay_prompt_program_media": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_PROMPT_PROGRAM_MEDIA",
        ),
        "hal_platform_overlay_cpu_port_dma_bank": (
            COMMON_DIR / "overlay.s",
            "HAL_PLATFORM_OVERLAY_CPU_PORT_DMA_BANK",
        ),
        "hal_platform_item_prompt_overlay_runtime": (COMMON_DIR / "player_items.s",),
        "hal_platform_item_prompt_reload_installs_irq": (COMMON_DIR / "player_items.s",),
        "hal_platform_item_prompt_reload_resync": (COMMON_DIR / "player_items.s",),
        "hal_platform_equip_prepare_key_before_display": (COMMON_DIR / "player_items.s",),
    }
    for name, consumer_spec in policy_consumers.items():
        consumer_path = consumer_spec[0]
        consumer_text = consumer_path.read_text(encoding="utf-8", errors="replace")
        accepted_names = (name, *consumer_spec[1:])
        if not any(accepted_name in consumer_text for accepted_name in accepted_names):
            policy_missing.append(f"{consumer_path.relative_to(ROOT)} does not consume {name}")

    wizard_text = (COMMON_DIR / "wizard.s").read_text(
        encoding="utf-8", errors="replace"
    )
    wizard_policy_consumers = (
        "HAL_PLATFORM_WIZARD_ENTRY_OVERLAY",
        "HAL_PLATFORM_WIZARD_40COL_RESIDENT",
        "HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE",
    )
    for name in wizard_policy_consumers:
        if name not in wizard_text:
            policy_missing.append(f"commodore/common/wizard.s does not consume {name}")

    ego_policy_consumers = (
        "HAL_PLATFORM_EGO_HOLY_AVENGER_STRING_EXTERNAL",
        "HAL_PLATFORM_EGO_AC_BONUS_LOCAL",
    )
    ego_text = (COMMON_DIR / "ego_items.s").read_text(
        encoding="utf-8", errors="replace"
    )
    for name in ego_policy_consumers:
        if name not in ego_text:
            policy_missing.append(f"commodore/common/ego_items.s does not consume {name}")

    spell_effects_text = (COMMON_DIR / "spell_effects.s").read_text(
        encoding="utf-8", errors="replace"
    )
    if "HAL_PLATFORM_CURE_POISON_MSG_EXTERNAL" not in spell_effects_text:
        policy_missing.append(
            "commodore/common/spell_effects.s does not consume "
            "HAL_PLATFORM_CURE_POISON_MSG_EXTERNAL"
        )

    character_text = (COMMON_DIR / "ui_character.s").read_text(
        encoding="utf-8", errors="replace"
    )
    if "hal_platform_character_sheet_begin" not in character_text:
        policy_missing.append(
            "commodore/common/ui_character.s does not consume "
            "hal_platform_character_sheet_begin"
        )

    if re.search(r"(?m)^\s*#if[^\n]*\bC128\b", ego_text):
        policy_missing.append("commodore/common/ego_items.s still branches directly on C128")

    player_create_text = (COMMON_DIR / "player_create.s").read_text(
        encoding="utf-8", errors="replace"
    )
    if re.search(
        r"(?m)^\s*#if\s+\(?\s*C128\s*\)?\s*$\n"
        r"(?:.*\n){0,4}?\s*jsr\s+hal_platform_runtime_resync\b",
        player_create_text,
    ):
        policy_missing.append(
            "commodore/common/player_create.s still gates chargen runtime resync on C128"
        )
    if "C128_CHARGEN_CUTPOINT" in player_create_text:
        policy_missing.append(
            "commodore/common/player_create.s still owns the C128 chargen cutpoint name"
        )

    if re.search(r"(?m)^\s*#if[^\n]*\bC128\b", spell_effects_text):
        policy_missing.append("commodore/common/spell_effects.s still branches directly on C128")

    if missing or violations or policy_missing or direct_missing:
        if missing:
            print("Missing lifecycle HAL service exports:")
            for name in missing:
                print(f"  {name}")
        if direct_missing:
            print("Missing direct lifecycle HAL exports:")
            for name in direct_missing:
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
        f"{len(REQUIRED_DIRECT_EXPORTS)} direct services, "
        f"{len(REQUIRED_POLICY_CONSTANTS)} policy constants, common call-site audit)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
