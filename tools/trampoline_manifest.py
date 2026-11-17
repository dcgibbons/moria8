#!/usr/bin/env python3
"""
tools/trampoline_manifest.py
Module ownership: platform-tooling trampoline manifest (Phase 3 cross-port).
Owns the single declarative source of truth for 100% of non-test ``tramp_*``
labels across all 7 Moria8 ports (``apple2``, ``bbcmaster``, ``cx16``,
``atari8``, ``c64``, ``plus4``, ``c128``).

Each entry is either:
- ``kind != "custom"``: a standard generated dispatch/restore stub whose exact
  6502/65C02 instruction sequence and register/carry/bank preservation semantics
  are emitted by ``tools/gen_trampolines.py`` into ``build/trampolines/<port>_trampolines.inc``.
- ``kind == "custom"``: an irreducible port-specific trampoline or shared-tail
  dispatcher that remains hand-authored in ``owner_file`` with an explicit
  ``reason`` and declared ``targets``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple


PORTS: Tuple[str, ...] = (
    "apple2",
    "bbcmaster",
    "cx16",
    "atari8",
    "c64",
    "plus4",
    "c128",
)

COMMODORE_PORTS: Tuple[str, ...] = ("c64", "plus4", "c128")


# Standard template kinds supported by tools/gen_trampolines.py.
# Every template preserves exact instruction/register/carry/banking semantics
# for the ports that use it.
STANDARD_KINDS: Tuple[str, ...] = (
    "a2_ovl_dispatch",
    "a8_ovl_gen_loaded",
    "alias",
    "ax_dispatch",
    "ay_dispatch",
    "c128_banked_compute",
    "c128_banked_preserve_a",
    "c128_banked_preserve_a_return",
    "c128_banked_preserve_flags",
    "c128_banked_shared_epilogue",
    "c128_ovl_compute",
    "c128_ovl_death_return",
    "c128_ovl_tail",
    "c128_ui_display",
    "c64_bank_no_roms_preserve_flags",
    "c64_ovl_gen_bank_no_roms_sr",
    "clc_rts",
    "direct_jmp",
    "game_over_direct",
    "game_over_disk_setup_ovl",
    "game_over_prepare_ovl",
    "noop_rts",
    "ovl_chest_door_pick",
    "ovl_death_restore_spell",
    "ovl_death_restore_spell_fatal",
    "ovl_direct",
    "ovl_help_direct",
    "ovl_help_sr",
    "ovl_identify_direct",
    "ovl_items_ret_fail",
    "ovl_items_ret_zero",
    "ovl_spell_restore",
    "ovl_sr",
    "plus4_bank_ram_preserve_a_ret",
    "plus4_bank_ram_preserve_flags",
    "plus4_ovl_gen_cached_sr",
    "plus4_title_ovl",
    "restore_spell_overlay",
    "roll_ego_ovl_restore",
    "select_filtered_inv_key_spell",
    "select_filtered_inv_spell",
    "sr_epilogue_resync",
    "store_enter_town_home",
    "winner_royal_death_modal",
    "xy_dispatch",
)


@dataclass(frozen=True)
class TrampolineEntry:
    port: str
    name: str
    kind: str
    overlay: Optional[str] = None
    target: Optional[str] = None
    targets: Tuple[str, ...] = ()
    dispatcher: Optional[str] = None
    owner_file: Optional[str] = None
    reason: Optional[str] = None

    @property
    def is_generated(self) -> bool:
        return self.kind != "custom"

    @property
    def all_targets(self) -> Tuple[str, ...]:
        out: List[str] = []
        if self.target:
            out.append(self.target)
        for item in self.targets:
            if item not in out:
                out.append(item)
        return tuple(out)


def _gen(
    port: str,
    name: str,
    kind: str,
    *,
    overlay: Optional[str] = None,
    target: Optional[str] = None,
    dispatcher: Optional[str] = None,
    targets: Tuple[str, ...] = (),
) -> TrampolineEntry:
    return TrampolineEntry(
        port=port,
        name=name,
        kind=kind,
        overlay=overlay,
        target=target,
        targets=targets,
        dispatcher=dispatcher,
    )


def _custom(
    port: str,
    name: str,
    owner_file: str,
    reason: str,
    *,
    overlay: Optional[str] = None,
    target: Optional[str] = None,
    targets: Tuple[str, ...] = (),
) -> TrampolineEntry:
    return TrampolineEntry(
        port=port,
        name=name,
        kind="custom",
        overlay=overlay,
        target=target,
        targets=targets,
        owner_file=owner_file,
        reason=reason,
    )


# ---------------------------------------------------------------------------
# Apple IIe (86 entries: platforms/apple2/main.s + legal.s)
# ---------------------------------------------------------------------------
APPLE2_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: a2_ovl_dispatch (25)
    _gen("apple2", "tramp_assign_special_room", "a2_ovl_dispatch", overlay="OVL_DUNGEON_GEN", target="assign_special_room"),
    _gen("apple2", "tramp_vault_seal_entrance", "a2_ovl_dispatch", overlay="OVL_DUNGEON_GEN", target="vault_seal_entrance"),
    _gen("apple2", "tramp_spawn_special_room_monsters", "a2_ovl_dispatch", overlay="OVL_DUNGEON_GEN", target="spawn_special_room_monsters"),
    _gen("apple2", "tramp_spawn_nest_gold", "a2_ovl_dispatch", overlay="OVL_DUNGEON_GEN", target="spawn_nest_gold"),
    _gen("apple2", "tramp_find_special_room", "a2_ovl_dispatch", overlay="OVL_DUNGEON_GEN", target="find_special_room"),
    _gen("apple2", "tramp_ui_char_display", "a2_ovl_dispatch", overlay="OVL_UI", target="ui_char_display"),
    _gen("apple2", "tramp_ui_inv_display", "a2_ovl_dispatch", overlay="OVL_UI", target="ui_inv_display"),
    _gen("apple2", "tramp_ui_inv_select_display", "a2_ovl_dispatch", overlay="OVL_UI", target="ui_inv_select_display"),
    _gen("apple2", "tramp_ui_equip_display", "a2_ovl_dispatch", overlay="OVL_UI", target="ui_equip_display"),
    _gen("apple2", "tramp_ui_equip_select_display", "a2_ovl_dispatch", overlay="OVL_UI", target="ui_equip_select_display"),
    _gen("apple2", "tramp_ui_recall", "a2_ovl_dispatch", overlay="OVL_DEATH", target="ui_recall_display"),
    _gen("apple2", "tramp_item_gain_spell", "a2_ovl_dispatch", overlay="OVL_SPELL", target="item_gain_spell"),
    _gen("apple2", "tramp_spell_list_display", "a2_ovl_dispatch", overlay="OVL_SPELL", target="spell_list_display"),
    _gen("apple2", "tramp_reveal_floorplan", "a2_ovl_dispatch", overlay="OVL_SPELL", target="eff_reveal_floorplan"),
    _gen("apple2", "tramp_cmd_jam", "a2_ovl_dispatch", overlay="OVL_CHEST", target="door_jam_command"),
    _gen("apple2", "tramp_magic_recalc_mana", "a2_ovl_dispatch", overlay="OVL_SPELL", target="magic_recalc_mana"),
    _gen("apple2", "tramp_magic_check_new_spells", "a2_ovl_dispatch", overlay="OVL_SPELL", target="magic_check_new_spells"),
    _gen("apple2", "tramp_calc_spell_failure", "a2_ovl_dispatch", overlay="OVL_SPELL", target="calc_spell_failure"),
    _gen("apple2", "tramp_player_cast_spell", "a2_ovl_dispatch", overlay="OVL_SPELL", target="player_cast_spell"),
    _gen("apple2", "tramp_player_pray", "a2_ovl_dispatch", overlay="OVL_SPELL", target="player_pray"),
    _gen("apple2", "tramp_ui_wizard_display", "a2_ovl_dispatch", overlay="OVL_MODAL_MISC", target="ui_wizard_display"),
    _gen("apple2", "tramp_item_init_identification", "a2_ovl_dispatch", overlay="OVL_STORAGE", target="item_init_identification"),
    _gen("apple2", "tramp_disk_setup", "a2_ovl_dispatch", overlay="OVL_STORAGE", target="a2_disk_setup_run"),
    _gen("apple2", "tramp_disk_prepare_selected", "a2_ovl_dispatch", overlay="OVL_STORAGE", target="a2_disk_prepare_selected"),
    _gen("apple2", "tramp_player_create", "a2_ovl_dispatch", overlay="OVL_STARTUP", target="player_create"),
    _gen("apple2", "tramp_store_init_all", "a2_ovl_dispatch", overlay="OVL_TITLE", target="store_init_all"),
    _gen("apple2", "tramp_store_restock_all", "a2_ovl_dispatch", overlay="OVL_TITLE", target="store_restock_all"),
    _gen("apple2", "tramp_door_try_open", "a2_ovl_dispatch", overlay="OVL_HELP", target="door_try_open"),
    _gen("apple2", "tramp_door_try_close", "a2_ovl_dispatch", overlay="OVL_HELP", target="door_try_close"),
    _gen("apple2", "tramp_item_drop", "a2_ovl_dispatch", overlay="OVL_HELP", target="item_drop"),
    _gen("apple2", "tramp_init_starting_kit", "a2_ovl_dispatch", overlay="OVL_TITLE", target="init_starting_kit"),
    # Generated: ovl_spell_restore (1 - fixes Mage Spell #20 Identify '?' OVL_SPELL eviction)
    _gen("apple2", "tramp_spell_execute_selected", "ovl_spell_restore", overlay="OVL_SPELL", target="spell_execute_selected"),
    # Generated: ay_dispatch -> tramp_items_dispatch (15)
    _gen("apple2", "tramp_item_read_scroll", "ay_dispatch", overlay="OVL_ITEMS", target="item_read_scroll", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_aim_wand", "ay_dispatch", overlay="OVL_ITEMS", target="item_aim_wand", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_use_staff", "ay_dispatch", overlay="OVL_ITEMS", target="item_use_staff", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_refuel", "ay_dispatch", overlay="OVL_ITEMS", target="item_refuel", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_exchange", "ay_dispatch", overlay="OVL_ITEMS", target="item_exchange", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_ranged_fire", "ay_dispatch", overlay="OVL_ITEMS", target="ranged_fire", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_throw_item", "ay_dispatch", overlay="OVL_ITEMS", target="throw_item", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_bash_command", "ay_dispatch", overlay="OVL_ITEMS", target="bash_command", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_player_tunnel", "ay_dispatch", overlay="OVL_ITEMS", target="player_tunnel", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_wear", "ay_dispatch", overlay="OVL_ITEMS", target="item_wear", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_takeoff", "ay_dispatch", overlay="OVL_ITEMS", target="item_takeoff", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_eat", "ay_dispatch", overlay="OVL_ITEMS", target="item_eat", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_quaff", "ay_dispatch", overlay="OVL_ITEMS", target="item_quaff", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_item_pickup", "ay_dispatch", overlay="OVL_ITEMS", target="item_pickup", dispatcher="tramp_items_dispatch"),
    _gen("apple2", "tramp_re_equip", "ay_dispatch", overlay="OVL_MODAL_MISC", target="re_equip", dispatcher="modal_swap_dispatch"),
    # Generated: ay_dispatch -> chest_dispatch (2)
    _gen("apple2", "tramp_disarm_command", "ay_dispatch", overlay="OVL_CHEST", target="disarm_command", dispatcher="chest_dispatch"),
    _gen("apple2", "tramp_chest_open", "ay_dispatch", overlay="OVL_CHEST", target="chest_open_command", dispatcher="chest_dispatch"),
    # Generated: xy_dispatch -> tramp_death_call_restore_spell (4)
    _gen("apple2", "tramp_eff_earthquake", "xy_dispatch", overlay="OVL_DEATH", target="eff_earthquake", dispatcher="tramp_death_call_restore_spell"),
    _gen("apple2", "tramp_eff_map_area", "xy_dispatch", overlay="OVL_DEATH", target="eff_map_area", dispatcher="tramp_death_call_restore_spell"),
    _gen("apple2", "tramp_eff_destroy_area", "xy_dispatch", overlay="OVL_DEATH", target="da_devastate", dispatcher="tramp_death_call_restore_spell"),
    _gen("apple2", "tramp_eff_potion_gain_stat", "xy_dispatch", overlay="OVL_DEATH", target="eff_potion_gain_stat", dispatcher="tramp_death_call_restore_spell"),
    # Generated: shared stubs (20)
    _gen("apple2", "tramp_level_generate", "direct_jmp", target="level_generate"),
    _gen("apple2", "tramp_sr_epilogue", "sr_epilogue_resync", target="a2_platform_runtime_resync"),
    _gen("apple2", "tramp_help_cmd_body", "ovl_help_direct", overlay="OVL_HELP", target="help_cmd_body"),
    _gen("apple2", "tramp_select_filtered_inv", "select_filtered_inv_spell", overlay="OVL_ITEMS", target="piw_select_filtered_inv"),
    _gen("apple2", "tramp_restore_spell_overlay", "restore_spell_overlay", overlay="OVL_SPELL"),
    _gen("apple2", "tramp_select_filtered_inv_key_spell", "select_filtered_inv_key_spell", overlay="OVL_ITEMS", target="piw_select_filtered_inv_key"),
    _gen("apple2", "tramp_ui_identify", "ovl_identify_direct", overlay="OVL_HELP", target="ui_identify_print"),
    _gen("apple2", "tramp_game_over_disk_setup", "game_over_disk_setup_ovl"),
    _gen("apple2", "tramp_game_over_disk_setup_failed", "clc_rts"),
    _gen("apple2", "tramp_game_over_prepare", "game_over_prepare_ovl", overlay="OVL_DEATH", target="creature_get_name"),
    _gen("apple2", "tramp_game_over", "game_over_direct", target="tramp_game_over_run"),
    _gen("apple2", "tramp_roll_ego_type", "ovl_items_ret_zero", overlay="OVL_ITEMS", target="roll_ego_type"),
    _gen("apple2", "tramp_roll_ego_type_modal", "roll_ego_ovl_restore", overlay="OVL_MODAL_MISC", target="roll_ego_type"),
    _gen("apple2", "tramp_roll_ego_type_gen", "roll_ego_ovl_restore", overlay="OVL_DUNGEON_GEN", target="roll_ego_type"),
    _gen("apple2", "tramp_ego_apply_damage", "ovl_items_ret_fail", overlay="OVL_ITEMS", target="ego_apply_damage"),
    _gen("apple2", "tramp_ego_get_ac_bonus", "ovl_items_ret_zero", overlay="OVL_ITEMS", target="ego_get_ac_bonus"),
    _gen("apple2", "tramp_eff_item_p1", "ovl_direct", overlay="OVL_HOME", target="eff_item_p1_exec"),
    _gen("apple2", "tramp_eff_ext_eat", "ay_dispatch", overlay="OVL_CHEST", target="eff_ext_eat_piw", dispatcher="tramp_chest_call_restore_items"),
    _gen("apple2", "tramp_eff_ext_quaff", "ay_dispatch", overlay="OVL_CHEST", target="eff_ext_quaff_piw", dispatcher="tramp_chest_call_restore_items"),
    # Custom (22)
    _custom("apple2", "tramp_load_resume_reset", "platforms/apple2/main.s", "Runs load_resume_reset in OVL_STORAGE once per load and clears current_overlay", overlay="OVL_STORAGE", target="load_resume_reset"),
    _custom("apple2", "tramp_item_recalc", "platforms/apple2/main.s", "Loads OVL_ITEMS for player_recalc_equipment and restores caller current_overlay (e.g. OVL_CHEST acid traps)", overlay="OVL_ITEMS", target="player_recalc_equipment"),
    _custom("apple2", "tramp_trap_trigger", "platforms/apple2/main.s", "Loads OVL_CHEST and reloads X = df_disarm_trap_idx before jumping to trap_trigger", overlay="OVL_CHEST", target="trap_trigger"),
    _custom("apple2", "tramp_door_pick_roll", "platforms/apple2/main.s", "Loads OVL_CHEST for door_pick_roll and restores caller overlay (OVL_HELP) while preserving C", overlay="OVL_CHEST", target="door_pick_roll"),
    _custom("apple2", "tramp_winner_royal", "platforms/apple2/main.s", "royal_screen lives in DeathOverlay, freeing ModalMiscOverlay cache space", overlay="OVL_DEATH", targets=("winner_apply_retirement_bonus_overlay", "royal_screen")),
    _custom("apple2", "tramp_dig_ability", "platforms/apple2/main.s", "Lives in A2PlaySlot ($7C00-$9FFF) rather than Default", target="calc_dig_ability"),
    _custom("apple2", "tramp_ovl_dispatch", "platforms/apple2/main.s", "Shared A/Y/X self-modifying overlay dispatcher"),
    _custom("apple2", "tramp_death_call_restore_spell", "platforms/apple2/main.s", "Shared A-preserving OVL_DEATH -> OVL_SPELL dispatcher"),
    _custom("apple2", "tramp_chest_call_restore_items", "platforms/apple2/main.s", "Shared OVL_CHEST -> OVL_ITEMS dispatcher for eff_item_extended.s", overlay="OVL_CHEST"),
    _custom("apple2", "tramp_store_enter", "platforms/apple2/main.s", "Dispatches STORE_HOME vs town store via tramp_ovl_dispatch", targets=("store_enter", "home_enter")),
    _custom("apple2", "tramp_game_over_run", "platforms/apple2/main.s", "DeathOverlay tail routine importing scroll_effects_p3.s", overlay="OVL_DEATH", targets=("score_calculate", "score_death_screen")),
    _custom("apple2", "tramp_do_look", "platforms/apple2/main.s", "Lives in A2PlaySlot for resident play-turn look command", overlay="OVL_MODAL_MISC", target="do_look"),
    _custom("apple2", "tramp_inv_add_carried", "platforms/apple2/main.s", "Lives in A2PlaySlot; returns pack-full string index on failure", overlay="OVL_ITEMS", target="inv_add_carried_items"),
    _custom("apple2", "tramp_items_dispatch", "platforms/apple2/main.s", "Shared A/Y OVL_ITEMS dispatcher falling into tramp_items_jmp", overlay="OVL_ITEMS"),
    _custom("apple2", "tramp_items_jmp", "platforms/apple2/main.s", "Self-modifying jmp target inside tramp_items_dispatch"),
    _custom("apple2", "tramp_spell_call_items", "platforms/apple2/main.s", "Two-way OVL_SPELL <-> OVL_ITEMS bridge with a2_tsci_arg"),
    _custom("apple2", "tramp_ui_view_restore_spell_overlay", "platforms/apple2/main.s", "Shares !restore_overlay tail to save Default bytes", overlay="OVL_SPELL", target="ui_view_restore_modal_overlay"),
    _custom("apple2", "tramp_ui_view_restore_items_overlay", "platforms/apple2/main.s", "Shares !restore_items/!restore_overlay tail to save Default bytes", overlay="OVL_ITEMS", target="ui_view_restore_modal_overlay"),
    _custom("apple2", "tramp_combat_check_levelup_items", "platforms/apple2/main.s", "Shares !restore_items/!restore_overlay tail to save Default bytes", overlay="OVL_ITEMS", target="combat_check_levelup"),
    _custom("apple2", "tramp_combat_apply_levelup_modal", "platforms/apple2/main.s", "Asserted window-return boundary block alongside UI restore stubs", overlay="OVL_MODAL_MISC", target="combat_apply_levelup"),
    _custom("apple2", "tramp_ego_append_suffix", "platforms/apple2/main.s", "Lives in A2PlaySlot; decodes ego via item_cat_decode_ego and tail-calls combat_append_str", targets=("item_cat_decode_ego", "combat_append_str")),
    _custom("apple2", "tramp_ui_legal_display", "platforms/apple2/legal.s", "Legal modal snapshot/disk-retry/viewer trampoline", targets=("asset_load_retry", "legal_viewer")),
)


# ---------------------------------------------------------------------------
# BBC Master 128 (80 entries: platforms/bbcmaster/main.s + legal.s)
# ---------------------------------------------------------------------------
BBCMASTER_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: ay_dispatch (35)
    _gen("bbcmaster", "tramp_assign_special_room", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="assign_special_room", dispatcher="gen_dispatch"),
    _gen("bbcmaster", "tramp_vault_seal_entrance", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="vault_seal_entrance", dispatcher="gen_dispatch"),
    _gen("bbcmaster", "tramp_spawn_special_room_monsters", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="spawn_special_room_monsters", dispatcher="gen_dispatch"),
    _gen("bbcmaster", "tramp_ui_inv_display", "ay_dispatch", overlay="OVL_UI", target="ui_inv_display", dispatcher="ui_dispatch"),
    _gen("bbcmaster", "tramp_ui_inv_select_display", "ay_dispatch", overlay="OVL_UI", target="ui_inv_select_display", dispatcher="ui_dispatch"),
    _gen("bbcmaster", "tramp_ui_equip_display", "ay_dispatch", overlay="OVL_UI", target="ui_equip_display", dispatcher="ui_dispatch"),
    _gen("bbcmaster", "tramp_ui_equip_select_display", "ay_dispatch", overlay="OVL_UI", target="ui_equip_select_display", dispatcher="ui_dispatch"),
    _gen("bbcmaster", "tramp_item_gain_spell", "ay_dispatch", overlay="OVL_SPELL", target="item_gain_spell", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_spell_list_display", "ay_dispatch", overlay="OVL_SPELL", target="spell_list_display", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_reveal_floorplan", "ay_dispatch", overlay="OVL_SPELL", target="eff_reveal_floorplan", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_magic_recalc_mana", "ay_dispatch", overlay="OVL_SPELL", target="magic_recalc_mana", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_magic_check_new_spells", "ay_dispatch", overlay="OVL_SPELL", target="magic_check_new_spells", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_calc_spell_failure", "ay_dispatch", overlay="OVL_SPELL", target="calc_spell_failure", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_player_cast_spell", "ay_dispatch", overlay="OVL_SPELL", target="player_cast_spell", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_player_pray", "ay_dispatch", overlay="OVL_SPELL", target="player_pray", dispatcher="spell_dispatch"),
    _gen("bbcmaster", "tramp_item_read_scroll", "ay_dispatch", overlay="OVL_ITEMS", target="item_read_scroll", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_aim_wand", "ay_dispatch", overlay="OVL_ITEMS", target="item_aim_wand", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_use_staff", "ay_dispatch", overlay="OVL_ITEMS", target="item_use_staff", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_refuel", "ay_dispatch", overlay="OVL_ITEMS", target="item_refuel", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_exchange", "ay_dispatch", overlay="OVL_ITEMS", target="item_exchange", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_ranged_fire", "ay_dispatch", overlay="OVL_ITEMS", target="ranged_fire", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_throw_item", "ay_dispatch", overlay="OVL_ITEMS", target="throw_item", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_bash_command", "ay_dispatch", overlay="OVL_ITEMS", target="bash_command", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_disarm_command", "ay_dispatch", overlay="OVL_CHEST", target="disarm_command", dispatcher="chest_dispatch"),
    _gen("bbcmaster", "tramp_player_tunnel", "ay_dispatch", overlay="OVL_ITEMS", target="player_tunnel", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_wear", "ay_dispatch", overlay="OVL_ITEMS", target="item_wear", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_pickup", "ay_dispatch", overlay="OVL_ITEMS", target="item_pickup", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_takeoff", "ay_dispatch", overlay="OVL_ITEMS", target="item_takeoff", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_eat", "ay_dispatch", overlay="OVL_ITEMS", target="item_eat", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_item_quaff", "ay_dispatch", overlay="OVL_ITEMS", target="item_quaff", dispatcher="tramp_items_dispatch"),
    _gen("bbcmaster", "tramp_chest_open", "ay_dispatch", overlay="OVL_CHEST", target="chest_open_command", dispatcher="chest_dispatch"),
    _gen("bbcmaster", "tramp_cmd_jam", "ay_dispatch", overlay="OVL_CHEST", target="door_jam_command", dispatcher="chest_dispatch"),
    _gen("bbcmaster", "tramp_door_pick_roll", "ay_dispatch", overlay="OVL_CHEST", target="door_pick_roll", dispatcher="chest_swap_dispatch"),
    _gen("bbcmaster", "tramp_door_try_open", "ay_dispatch", overlay="OVL_HELP", target="door_try_open", dispatcher="help_dispatch"),
    _gen("bbcmaster", "tramp_door_try_close", "ay_dispatch", overlay="OVL_HELP", target="door_try_close", dispatcher="help_dispatch"),
    _gen("bbcmaster", "tramp_item_drop", "ay_dispatch", overlay="OVL_HELP", target="item_drop", dispatcher="help_dispatch"),
    _gen("bbcmaster", "tramp_store_init_all", "ay_dispatch", overlay="OVL_TITLE", target="store_init_all", dispatcher="title_dispatch"),
    _gen("bbcmaster", "tramp_store_restock_all", "ay_dispatch", overlay="OVL_TITLE", target="store_restock_all", dispatcher="title_dispatch"),
    _gen("bbcmaster", "tramp_init_starting_kit", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="init_starting_kit", dispatcher="gen_dispatch"),
    _gen("bbcmaster", "tramp_re_equip", "ay_dispatch", overlay="OVL_MODAL_MISC", target="re_equip", dispatcher="modal_swap_dispatch"),
    # Generated: ovl_direct (8)
    _gen("bbcmaster", "tramp_ui_char_display", "ovl_direct", overlay="OVL_UI", target="ui_char_display"),
    _gen("bbcmaster", "tramp_ui_recall", "ovl_direct", overlay="OVL_DEATH", target="ui_recall_display"),
    _gen("bbcmaster", "tramp_ui_wizard_display", "ovl_direct", overlay="OVL_MODAL_MISC", target="ui_wizard_display"),
    _gen("bbcmaster", "tramp_item_init_identification", "ovl_direct", overlay="OVL_ITEMS", target="item_init_identification"),
    _gen("bbcmaster", "tramp_disk_setup", "ovl_direct", overlay="OVL_STORAGE", target="beeb_disk_setup_run"),
    _gen("bbcmaster", "tramp_disk_prepare_selected", "ovl_direct", overlay="OVL_STORAGE", target="beeb_disk_prepare_selected"),
    _gen("bbcmaster", "tramp_load_resume_reset", "ovl_direct", overlay="OVL_STORAGE", target="load_resume_reset"),
    _gen("bbcmaster", "tramp_player_create", "ovl_direct", overlay="OVL_STARTUP", target="player_create"),
    # Generated: ovl_death_restore_spell (3)
    _gen("bbcmaster", "tramp_eff_earthquake", "ovl_death_restore_spell", overlay="OVL_DEATH", target="eff_earthquake"),
    _gen("bbcmaster", "tramp_eff_map_area", "ovl_death_restore_spell", overlay="OVL_DEATH", target="eff_map_area"),
    _gen("bbcmaster", "tramp_eff_destroy_area", "ovl_death_restore_spell", overlay="OVL_DEATH", target="da_devastate"),
    # Generated: ovl_spell_restore (1 - fixes Mage Spell #20 Identify '?' OVL_SPELL eviction)
    _gen("bbcmaster", "tramp_spell_execute_selected", "ovl_spell_restore", overlay="OVL_SPELL", target="spell_execute_selected"),
    # Generated: shared stubs (15)
    _gen("bbcmaster", "tramp_level_generate", "direct_jmp", target="level_generate"),
    _gen("bbcmaster", "tramp_sr_epilogue", "sr_epilogue_resync", target="beeb_platform_runtime_resync"),
    _gen("bbcmaster", "tramp_help_cmd_body", "ovl_help_direct", overlay="OVL_HELP", target="help_cmd_body"),
    _gen("bbcmaster", "tramp_select_filtered_inv", "select_filtered_inv_spell", overlay="OVL_ITEMS", target="piw_select_filtered_inv"),
    _gen("bbcmaster", "tramp_restore_spell_overlay", "restore_spell_overlay", overlay="OVL_SPELL"),
    _gen("bbcmaster", "tramp_select_filtered_inv_key_spell", "select_filtered_inv_key_spell", overlay="OVL_ITEMS", target="piw_select_filtered_inv_key"),
    _gen("bbcmaster", "tramp_ui_identify", "ovl_identify_direct", overlay="OVL_HELP", target="ui_identify_print"),
    _gen("bbcmaster", "tramp_store_enter", "store_enter_town_home", targets=("store_enter", "home_enter")),
    _gen("bbcmaster", "tramp_game_over_disk_setup", "game_over_disk_setup_ovl"),
    _gen("bbcmaster", "tramp_game_over_disk_setup_failed", "clc_rts"),
    _gen("bbcmaster", "tramp_game_over_prepare", "game_over_prepare_ovl", overlay="OVL_DEATH", target="creature_get_name"),
    _gen("bbcmaster", "tramp_game_over", "game_over_direct", target="tramp_game_over_run"),
    _gen("bbcmaster", "tramp_roll_ego_type", "ovl_items_ret_zero", overlay="OVL_ITEMS", target="roll_ego_type"),
    _gen("bbcmaster", "tramp_ego_apply_damage", "ovl_items_ret_fail", overlay="OVL_ITEMS", target="ego_apply_damage"),
    _gen("bbcmaster", "tramp_ego_get_ac_bonus", "ovl_items_ret_zero", overlay="OVL_ITEMS", target="ego_get_ac_bonus"),
    # Custom (21)
    _custom("bbcmaster", "tramp_trap_trigger", "platforms/bbcmaster/main.s", "Preserves X (trap index) across overlay_load into OVL_CHEST", overlay="OVL_CHEST", target="trap_trigger"),
    _custom("bbcmaster", "tramp_item_recalc", "platforms/bbcmaster/main.s", "Restores OVL_CHEST when called from acid/corrode traps, direct OVL_ITEMS dispatch otherwise", overlay="OVL_ITEMS", target="player_recalc_equipment"),
    _custom("bbcmaster", "tramp_winner_royal", "platforms/bbcmaster/main.s", "royal_screen lives in DeathOverlay on BBC, skipping OVL_MODAL_MISC load", overlay="OVL_DEATH", targets=("winner_apply_retirement_bonus_overlay", "royal_screen")),
    _custom("bbcmaster", "tramp_spawn_nest_gold", "platforms/bbcmaster/main.s", "Preserves OVL_CHEST across item_spawn_level_gen calls to OVL_DUNGEON_GEN", overlay="OVL_DUNGEON_GEN", target="spawn_nest_gold"),
    _custom("bbcmaster", "tramp_find_special_room", "platforms/bbcmaster/main.s", "Preserves OVL_CHEST and A/X/P across item_spawn_level_gen calls to OVL_DUNGEON_GEN", overlay="OVL_DUNGEON_GEN", target="find_special_room"),
    _custom("bbcmaster", "tramp_do_look", "platforms/bbcmaster/main.s", "Lives in BeebPlaySlot ($8000-$A3FF)", overlay="OVL_MODAL_MISC", target="do_look"),
    _custom("bbcmaster", "tramp_game_over_run", "platforms/bbcmaster/main.s", "DeathOverlay tail routine importing scroll_effects_p3.s and player_destroy_area.s", overlay="OVL_DEATH", targets=("score_calculate", "score_death_screen")),
    _custom("bbcmaster", "tramp_inv_add_carried", "platforms/bbcmaster/main.s", "Lives in BeebPlaySlot; returns pack-full string index on failure", overlay="OVL_ITEMS", target="inv_add_carried_items"),
    _custom("bbcmaster", "tramp_items_dispatch", "platforms/bbcmaster/main.s", "Shared A/Y OVL_ITEMS dispatcher forwarding into ovl_dispatch_ay", overlay="OVL_ITEMS"),
    _custom("bbcmaster", "tramp_spell_call_items", "platforms/bbcmaster/main.s", "Two-way OVL_SPELL <-> OVL_ITEMS bridge with beeb_tsci_arg"),
    _custom("bbcmaster", "tramp_roll_ego_type_modal", "platforms/bbcmaster/main.s", "Shares !roll_ego_common tail with tramp_roll_ego_type_gen to save Default bytes", overlay="OVL_MODAL_MISC", target="tramp_roll_ego_type"),
    _custom("bbcmaster", "tramp_roll_ego_type_gen", "platforms/bbcmaster/main.s", "Shared tail with tramp_roll_ego_type_modal to save Default bytes", overlay="OVL_DUNGEON_GEN", target="tramp_roll_ego_type"),
    _custom("bbcmaster", "tramp_ui_view_restore_spell_overlay", "platforms/bbcmaster/main.s", "Shares !restore_overlay tail to save Default bytes", overlay="OVL_SPELL", target="ui_view_restore_modal_overlay"),
    _custom("bbcmaster", "tramp_ui_view_restore_items_overlay", "platforms/bbcmaster/main.s", "Shares !restore_items/!restore_overlay tail to save Default bytes", overlay="OVL_ITEMS", target="ui_view_restore_modal_overlay"),
    _custom("bbcmaster", "tramp_combat_check_levelup_items", "platforms/bbcmaster/main.s", "Shares !restore_items/!restore_overlay tail to save Default bytes", overlay="OVL_ITEMS", target="combat_check_levelup"),
    _custom("bbcmaster", "tramp_combat_apply_levelup_modal", "platforms/bbcmaster/main.s", "Branch-back into !restore_overlay tail inside Default assertion block", overlay="OVL_MODAL_MISC", target="combat_apply_levelup"),
    _custom("bbcmaster", "tramp_ego_append_suffix", "platforms/bbcmaster/main.s", "Lives in BeebPlaySlot; decodes ego via item_cat_decode_ego without swapping overlays and tail-calls combat_append_str", targets=("item_cat_decode_ego", "combat_append_str")),
    _custom("bbcmaster", "tramp_eff_item_p1", "platforms/bbcmaster/main.s", "Lives in Default; saves/restores current_overlay around OVL_HOME eff_item_p1_exec", overlay="OVL_HOME", target="eff_item_p1_exec"),
    _custom("bbcmaster", "tramp_eff_ext_eat", "platforms/bbcmaster/main.s", "Lives in Default; saves/restores current_overlay around OVL_HOME eff_ext_eat_piw", overlay="OVL_HOME", target="eff_ext_eat_piw"),
    _custom("bbcmaster", "tramp_eff_ext_quaff", "platforms/bbcmaster/main.s", "Lives in Default; saves/restores current_overlay around OVL_HOME eff_ext_quaff_piw", overlay="OVL_HOME", target="eff_ext_quaff_piw"),
    _custom("bbcmaster", "tramp_ui_legal_display", "platforms/bbcmaster/legal.s", "Legal modal snapshot/disk-retry/viewer trampoline", targets=("asset_load_retry", "legal_viewer")),
)


# ---------------------------------------------------------------------------
# Commander X16 (83 entries: platforms/cx16/main.s + legal.s)
# ---------------------------------------------------------------------------
CX16_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: ay_dispatch (30 - emitted with jmp so placement avoids 65C02 bra +/-127B limit)
    _gen("cx16", "tramp_assign_special_room", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="assign_special_room", dispatcher="tramp_gen_dispatch"),
    _gen("cx16", "tramp_vault_seal_entrance", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="vault_seal_entrance", dispatcher="tramp_gen_dispatch"),
    _gen("cx16", "tramp_spawn_special_room_monsters", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="spawn_special_room_monsters", dispatcher="tramp_gen_dispatch"),
    _gen("cx16", "tramp_spawn_nest_gold", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="spawn_nest_gold", dispatcher="tramp_gen_dispatch"),
    _gen("cx16", "tramp_find_special_room", "ay_dispatch", overlay="OVL_DUNGEON_GEN", target="find_special_room", dispatcher="tramp_gen_dispatch"),
    _gen("cx16", "tramp_spell_list_display", "ay_dispatch", overlay="OVL_SPELL", target="spell_list_display", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_reveal_floorplan", "ay_dispatch", overlay="OVL_SPELL", target="eff_reveal_floorplan", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_magic_recalc_mana", "ay_dispatch", overlay="OVL_SPELL", target="magic_recalc_mana", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_magic_check_new_spells", "ay_dispatch", overlay="OVL_SPELL", target="magic_check_new_spells", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_calc_spell_failure", "ay_dispatch", overlay="OVL_SPELL", target="calc_spell_failure", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_player_cast_spell", "ay_dispatch", overlay="OVL_SPELL", target="player_cast_spell", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_player_pray", "ay_dispatch", overlay="OVL_SPELL", target="player_pray", dispatcher="tramp_spell_dispatch"),
    _gen("cx16", "tramp_item_read_scroll", "ay_dispatch", overlay="OVL_ITEMS", target="item_read_scroll", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_aim_wand", "ay_dispatch", overlay="OVL_ITEMS", target="item_aim_wand", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_use_staff", "ay_dispatch", overlay="OVL_ITEMS", target="item_use_staff", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_refuel", "ay_dispatch", overlay="OVL_ITEMS", target="item_refuel", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_exchange", "ay_dispatch", overlay="OVL_ITEMS", target="item_exchange", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_ranged_fire", "ay_dispatch", overlay="OVL_ITEMS", target="ranged_fire", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_throw_item", "ay_dispatch", overlay="OVL_ITEMS", target="throw_item", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_bash_command", "ay_dispatch", overlay="OVL_ITEMS", target="bash_command", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_disarm_command", "ay_dispatch", overlay="OVL_ITEMS", target="disarm_command", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_player_tunnel", "ay_dispatch", overlay="OVL_ITEMS", target="player_tunnel", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_wear", "ay_dispatch", overlay="OVL_ITEMS", target="item_wear", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_takeoff", "ay_dispatch", overlay="OVL_ITEMS", target="item_takeoff", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_eat", "ay_dispatch", overlay="OVL_ITEMS", target="item_eat", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_quaff", "ay_dispatch", overlay="OVL_ITEMS", target="item_quaff", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_item_recalc", "ay_dispatch", overlay="OVL_ITEMS", target="player_recalc_equipment", dispatcher="tramp_items_dispatch"),
    _gen("cx16", "tramp_chest_open", "ay_dispatch", overlay="OVL_CHEST", target="chest_open_command", dispatcher="chest_dispatch"),
    _gen("cx16", "tramp_store_init_all", "ay_dispatch", overlay="OVL_CHEST", target="store_init_all", dispatcher="chest_dispatch"),
    _gen("cx16", "tramp_store_restock_all", "ay_dispatch", overlay="OVL_CHEST", target="store_restock_all", dispatcher="chest_dispatch"),
    # Generated: ovl_direct (12)
    _gen("cx16", "tramp_ui_char_display", "ovl_direct", overlay="OVL_UI", target="ui_char_display"),
    _gen("cx16", "tramp_ui_inv_display", "ovl_direct", overlay="OVL_HELP", target="ui_inv_display"),
    _gen("cx16", "tramp_ui_inv_select_display", "ovl_direct", overlay="OVL_HELP", target="ui_inv_select_display"),
    _gen("cx16", "tramp_ui_equip_display", "ovl_direct", overlay="OVL_HELP", target="ui_equip_display"),
    _gen("cx16", "tramp_ui_equip_select_display", "ovl_direct", overlay="OVL_HELP", target="ui_equip_select_display"),
    _gen("cx16", "tramp_ui_recall", "ovl_direct", overlay="OVL_MODAL_MISC", target="ui_recall_display"),
    _gen("cx16", "tramp_item_gain_spell", "ovl_direct", overlay="OVL_SPELL", target="item_gain_spell"),
    _gen("cx16", "tramp_cmd_jam", "ovl_direct", overlay="OVL_CHEST", target="door_jam_command"),
    _gen("cx16", "tramp_ui_wizard_display", "ovl_direct", overlay="OVL_MODAL_MISC", target="ui_wizard_display"),
    _gen("cx16", "tramp_item_init_identification", "ovl_direct", overlay="OVL_STARTUP", target="item_init_identification"),
    _gen("cx16", "tramp_disk_prepare_selected", "ovl_direct", overlay="OVL_STORAGE", target="cx16_disk_prepare_selected"),
    _gen("cx16", "tramp_player_create", "ovl_direct", overlay="OVL_STARTUP", target="player_create"),
    _gen("cx16", "tramp_init_starting_kit", "ovl_direct", overlay="OVL_STARTUP", target="init_starting_kit"),
    # Generated: ovl_sr (1)
    _gen("cx16", "tramp_do_look", "ovl_sr", overlay="OVL_MODAL_MISC", target="do_look"),
    # Generated: ovl_death_restore_spell (4)
    _gen("cx16", "tramp_eff_earthquake", "ovl_death_restore_spell", overlay="OVL_DEATH", target="eff_earthquake"),
    _gen("cx16", "tramp_eff_map_area", "ovl_death_restore_spell", overlay="OVL_DEATH", target="eff_map_area"),
    _gen("cx16", "tramp_eff_destroy_area", "ovl_death_restore_spell", overlay="OVL_DEATH", target="da_devastate"),
    _gen("cx16", "tramp_eff_item_p1", "ovl_death_restore_spell", overlay="OVL_HOME", target="eff_item_p1_exec"),
    # Generated: ovl_spell_restore (1 - fixes Mage Spell #20 Identify '?' OVL_SPELL eviction)
    _gen("cx16", "tramp_spell_execute_selected", "ovl_spell_restore", overlay="OVL_SPELL", target="spell_execute_selected"),
    # Generated: shared stubs (21)
    _gen("cx16", "tramp_level_generate", "direct_jmp", target="level_generate"),
    _gen("cx16", "tramp_sr_epilogue", "sr_epilogue_resync", target="cx16_platform_runtime_resync"),
    _gen("cx16", "tramp_ui_help_display", "ovl_help_direct", overlay="OVL_HELP", target="ui_help_display"),
    _gen("cx16", "tramp_door_try_open", "ovl_chest_door_pick", overlay="OVL_HELP", target="door_try_open"),
    _gen("cx16", "tramp_door_try_close", "ovl_chest_door_pick", overlay="OVL_HELP", target="door_try_close"),
    _gen("cx16", "tramp_item_drop", "ovl_chest_door_pick", overlay="OVL_HELP", target="item_drop"),
    _gen("cx16", "tramp_select_filtered_inv", "select_filtered_inv_spell", overlay="OVL_ITEMS", target="piw_select_filtered_inv"),
    _gen("cx16", "tramp_restore_spell_overlay", "restore_spell_overlay", overlay="OVL_SPELL"),
    _gen("cx16", "tramp_select_filtered_inv_key_spell", "select_filtered_inv_key_spell", overlay="OVL_ITEMS", target="piw_select_filtered_inv_key"),
    _gen("cx16", "tramp_ui_identify", "ovl_identify_direct", overlay="OVL_UI", target="ui_identify_print"),
    _gen("cx16", "tramp_store_enter", "store_enter_town_home", targets=("store_enter", "home_enter")),
    _gen("cx16", "tramp_game_over_disk_setup", "game_over_disk_setup_ovl"),
    _gen("cx16", "tramp_game_over_disk_setup_failed", "clc_rts"),
    _gen("cx16", "tramp_game_over_prepare", "game_over_prepare_ovl", overlay="OVL_DEATH", target="creature_get_name"),
    _gen("cx16", "tramp_game_over", "game_over_direct", target="tramp_game_over_run"),
    _gen("cx16", "tramp_winner_royal", "winner_royal_death_modal", overlay="OVL_MODAL_MISC", targets=("winner_apply_retirement_bonus_overlay", "royal_screen")),
    _gen("cx16", "tramp_roll_ego_type", "ovl_items_ret_zero", overlay="OVL_ITEMS", target="roll_ego_type"),
    _gen("cx16", "tramp_roll_ego_type_modal", "roll_ego_ovl_restore", overlay="OVL_MODAL_MISC", target="roll_ego_type"),
    _gen("cx16", "tramp_roll_ego_type_gen", "roll_ego_ovl_restore", overlay="OVL_DUNGEON_GEN", target="roll_ego_type"),
    _gen("cx16", "tramp_ego_apply_damage", "ovl_items_ret_fail", overlay="OVL_ITEMS", target="ego_apply_damage"),
    _gen("cx16", "tramp_ego_get_ac_bonus", "ovl_items_ret_zero", overlay="OVL_ITEMS", target="ego_get_ac_bonus"),
    # Custom (18)
    _custom("cx16", "tramp_title_load_game", "platforms/cx16/main.s", "Ensures disk_setup_done, loads OVL_STORAGE, branches to title_enter_menu on fail", overlay="OVL_STORAGE", target="title_load_game_ovl"),
    _custom("cx16", "tramp_gen_dispatch", "platforms/cx16/main.s", "Shared A/Y OVL_DUNGEON_GEN dispatcher falling into tramp_gen_jmp", overlay="OVL_DUNGEON_GEN"),
    _custom("cx16", "tramp_gen_jmp", "platforms/cx16/main.s", "Self-modifying jmp target inside tramp_gen_dispatch"),
    _custom("cx16", "tramp_item_pickup", "platforms/cx16/main.s", "Loads OVL_ITEMS, tail-jumps item_pickup, clears carry on failure", overlay="OVL_ITEMS", target="item_pickup"),
    _custom("cx16", "tramp_trap_trigger", "platforms/cx16/main.s", "Preserves X (trap index) across overlay_load into OVL_ITEMS", overlay="OVL_ITEMS", target="trap_trigger"),
    _custom("cx16", "tramp_door_pick_roll", "platforms/cx16/main.s", "Preserves caller current_overlay and carry across OVL_CHEST door_pick_roll", overlay="OVL_CHEST", target="door_pick_roll"),
    _custom("cx16", "tramp_spell_dispatch", "platforms/cx16/main.s", "Shared A/Y OVL_SPELL dispatcher falling into tramp_spell_jmp", overlay="OVL_SPELL"),
    _custom("cx16", "tramp_spell_jmp", "platforms/cx16/main.s", "Self-modifying jmp target inside tramp_spell_dispatch"),
    _custom("cx16", "tramp_disk_setup", "platforms/cx16/main.s", "Preserves CX16_RAM_BANK_REG ($00) across OVL_STORAGE call", overlay="OVL_STORAGE", target="cx16_disk_setup_run"),
    _custom("cx16", "tramp_game_over_run", "platforms/cx16/main.s", "DeathOverlay tail routine importing destroy/map/earthquake modules", overlay="OVL_DEATH", targets=("score_calculate", "score_death_screen")),
    _custom("cx16", "tramp_items_dispatch", "platforms/cx16/main.s", "Shared A/Y OVL_ITEMS dispatcher falling into tramp_items_jmp", overlay="OVL_ITEMS"),
    _custom("cx16", "tramp_items_jmp", "platforms/cx16/main.s", "Self-modifying jmp target inside tramp_items_dispatch"),
    _custom("cx16", "tramp_eff_ext_eat", "platforms/cx16/main.s", "Loads OVL_HOME, runs eff_ext_eat_piw, and restores OVL_ITEMS via shared tail", overlay="OVL_HOME", target="eff_ext_eat_piw"),
    _custom("cx16", "tramp_eff_ext_quaff", "platforms/cx16/main.s", "Loads OVL_HOME, runs eff_ext_quaff_piw, and restores OVL_ITEMS via shared tail", overlay="OVL_HOME", target="eff_ext_quaff_piw"),
    _custom("cx16", "tramp_ui_view_restore_spell_overlay", "platforms/cx16/main.s", "Shares !restore_overlay tail with item/levelup restore stubs", overlay="OVL_SPELL", target="ui_view_restore_modal_overlay"),
    _custom("cx16", "tramp_ui_view_restore_items_overlay", "platforms/cx16/main.s", "Shares !restore_items/!restore_overlay tail", overlay="OVL_ITEMS", target="ui_view_restore_modal_overlay"),
    _custom("cx16", "tramp_combat_check_levelup_items", "platforms/cx16/main.s", "Shares !restore_items/!restore_overlay tail", overlay="OVL_ITEMS", target="combat_check_levelup"),
    _custom("cx16", "tramp_combat_apply_levelup_modal", "platforms/cx16/main.s", "Calls combat_apply_levelup and restores OVL_MODAL_MISC with brk guard", overlay="OVL_MODAL_MISC", target="combat_apply_levelup"),
    _custom("cx16", "tramp_ego_append_suffix", "platforms/cx16/main.s", "Decodes ego 1..55 via resident item_cat_decode_ego without evicting caller overlay and tail-calls combat_append_str", targets=("item_cat_decode_ego", "combat_append_str")),
    _custom("cx16", "tramp_ui_legal_display", "platforms/cx16/legal.s", "Saves/restores CX16_RAM_BANK_REG ($00) around CX16_BANK_LEGAL viewer", targets=("asset_load_required", "legal_viewer")),
)


# ---------------------------------------------------------------------------
# Atari 8-bit (67 unique entries: platforms/atari8/main.s + legal.s)
# ---------------------------------------------------------------------------
ATARI8_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: alias (8)
    _gen("atari8", "tramp_level_generate", "alias", target="level_generate"),
    _gen("atari8", "tramp_assign_special_room", "alias", target="assign_special_room"),
    _gen("atari8", "tramp_vault_seal_entrance", "alias", target="vault_seal_entrance"),
    _gen("atari8", "tramp_find_special_room", "alias", target="find_special_room"),
    _gen("atari8", "tramp_sr_epilogue", "alias", target="atari_platform_runtime_resync"),
    _gen("atari8", "tramp_ego_apply_damage", "alias", target="ego_apply_damage"),
    _gen("atari8", "tramp_ego_get_ac_bonus", "alias", target="ego_get_ac_bonus"),
    _gen("atari8", "tramp_inv_add_carried", "alias", target="inv_add_carried_items"),
    # Generated: simple resident stubs (1)
    _gen("atari8", "tramp_reu_show_status", "noop_rts"),
    # Generated: a8_ovl_gen_loaded (1)
    _gen("atari8", "tramp_spawn_special_room_monsters", "a8_ovl_gen_loaded", overlay="OVL_DUNGEON_GEN", target="spawn_special_room_monsters"),
    # Generated: ay_dispatch -> a8_ovl_sr_common (42)
    _gen("atari8", "tramp_do_look", "ay_dispatch", overlay="OVL_MODAL_MISC", target="do_look", dispatcher="a8_disp_mdl"),
    _gen("atari8", "tramp_ui_char_display", "ay_dispatch", overlay="OVL_UI", target="ui_char_display", dispatcher="a8_disp_ui"),
    _gen("atari8", "tramp_item_init_identification", "ay_dispatch", overlay="OVL_DEATH", target="item_init_identification", dispatcher="a8_disp_dth"),
    _gen("atari8", "tramp_magic_recalc_mana", "ay_dispatch", overlay="OVL_MODAL_MISC", target="magic_recalc_mana", dispatcher="a8_disp_mdl"),
    _gen("atari8", "tramp_magic_check_new_spells", "ay_dispatch", overlay="OVL_MODAL_MISC", target="magic_check_new_spells", dispatcher="a8_disp_mdl"),
    _gen("atari8", "tramp_ui_inv_display", "ay_dispatch", overlay="OVL_HELP", target="ui_inv_display", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_ui_inv_select_display", "ay_dispatch", overlay="OVL_HELP", target="ui_inv_select_display", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_ui_equip_display", "ay_dispatch", overlay="OVL_HELP", target="ui_equip_display", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_ui_equip_select_display", "ay_dispatch", overlay="OVL_HELP", target="ui_equip_select_display", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_item_wear", "ay_dispatch", overlay="OVL_HELP", target="item_wear", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_item_takeoff", "ay_dispatch", overlay="OVL_HELP", target="item_takeoff", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_item_eat", "ay_dispatch", overlay="OVL_HELP", target="item_eat", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_item_quaff", "ay_dispatch", overlay="OVL_HELP", target="item_quaff", dispatcher="a8_disp_hlp"),
    _gen("atari8", "tramp_ui_recall", "ay_dispatch", overlay="OVL_DEATH", target="ui_recall_display", dispatcher="a8_disp_dth"),
    _gen("atari8", "tramp_item_drop", "ay_dispatch", overlay="OVL_DEATH", target="item_drop", dispatcher="a8_disp_dth"),
    _gen("atari8", "tramp_load_resume_reset", "ay_dispatch", overlay="OVL_DEATH", target="load_resume_reset", dispatcher="a8_disp_dth"),
    _gen("atari8", "tramp_item_gain_spell", "ay_dispatch", overlay="OVL_UI", target="item_gain_spell", dispatcher="a8_disp_ui"),
    _gen("atari8", "tramp_item_read_scroll", "ay_dispatch", overlay="OVL_ITEMS", target="item_read_scroll", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_item_aim_wand", "ay_dispatch", overlay="OVL_ITEMS", target="item_aim_wand", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_item_use_staff", "ay_dispatch", overlay="OVL_ITEMS", target="item_use_staff", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_item_refuel", "ay_dispatch", overlay="OVL_ITEMS", target="item_refuel", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_item_pickup", "ay_dispatch", overlay="OVL_ITEMS", target="item_pickup", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_item_exchange", "ay_dispatch", overlay="OVL_DEATH", target="item_exchange", dispatcher="a8_disp_dth"),
    _gen("atari8", "tramp_ranged_fire", "ay_dispatch", overlay="OVL_ITEMS", target="ranged_fire", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_throw_item", "ay_dispatch", overlay="OVL_ITEMS", target="throw_item", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_bash_command", "ay_dispatch", overlay="OVL_ITEMS", target="bash_command", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_disarm_command", "ay_dispatch", overlay="OVL_CHEST", target="disarm_command", dispatcher="a8_disp_chs"),
    _gen("atari8", "tramp_cmd_jam", "ay_dispatch", overlay="OVL_CHEST", target="door_jam_command", dispatcher="a8_disp_chs"),
    _gen("atari8", "tramp_chest_open", "ay_dispatch", overlay="OVL_CHEST", target="chest_open_command", dispatcher="a8_disp_chs"),
    _gen("atari8", "tramp_door_try_open", "ay_dispatch", overlay="OVL_HOME", target="door_try_open", dispatcher="a8_disp_hom"),
    _gen("atari8", "tramp_door_try_close", "ay_dispatch", overlay="OVL_HOME", target="door_try_close", dispatcher="a8_disp_hom"),
    _gen("atari8", "tramp_player_tunnel", "ay_dispatch", overlay="OVL_ITEMS", target="player_tunnel", dispatcher="a8_disp_itm"),
    _gen("atari8", "tramp_spell_list_display", "ay_dispatch", overlay="OVL_UI", target="spell_list_display", dispatcher="a8_swap_ui"),
    _gen("atari8", "tramp_spell_execute_selected", "ay_dispatch", overlay="OVL_SPELL", target="spell_execute_selected", dispatcher="a8_swap_spl"),
    _gen("atari8", "tramp_reveal_floorplan", "ay_dispatch", overlay="OVL_SPELL", target="eff_reveal_floorplan", dispatcher="a8_disp_spl"),
    _gen("atari8", "tramp_eff_identify_scroll_resident", "ay_dispatch", overlay="OVL_SPELL", target="eff_identify_prompt", dispatcher="a8_disp_spl"),
    _gen("atari8", "tramp_player_cast_spell", "ay_dispatch", overlay="OVL_STORAGE", target="player_cast_spell", dispatcher="a8_disp_sto"),
    _gen("atari8", "tramp_player_pray", "ay_dispatch", overlay="OVL_STORAGE", target="player_pray", dispatcher="a8_disp_sto"),
    _gen("atari8", "tramp_ui_wizard_display", "ay_dispatch", overlay="OVL_MODAL_MISC", target="ui_wizard_display", dispatcher="a8_disp_mdl"),
    _gen("atari8", "tramp_store_init_all", "ay_dispatch", overlay="OVL_TITLE", target="store_init_all", dispatcher="a8_disp_ttl"),
    _gen("atari8", "tramp_store_restock_all", "ay_dispatch", overlay="OVL_TITLE", target="store_restock_all", dispatcher="a8_disp_ttl"),
    _gen("atari8", "tramp_init_starting_kit", "ay_dispatch", overlay="OVL_TITLE", target="init_starting_kit", dispatcher="a8_disp_ttl"),
    # Generated: ay_dispatch -> a8_ovl_swap_restore (8)
    _gen("atari8", "tramp_item_refresh_fixed_known", "ay_dispatch", overlay="OVL_STORAGE", target="item_refresh_fixed_known", dispatcher="a8_swap_sto"),
    _gen("atari8", "tramp_pm_build_learnable", "ay_dispatch", overlay="OVL_HELP", target="pm_build_learnable_list_from_book", dispatcher="a8_swap_hlp"),
    _gen("atari8", "tramp_eff_earthquake", "ay_dispatch", overlay="OVL_DEATH", target="eff_earthquake", dispatcher="a8_swap_dth"),
    _gen("atari8", "tramp_re_equip", "ay_dispatch", overlay="OVL_CHEST", target="re_equip", dispatcher="a8_swap_chs"),
    _gen("atari8", "tramp_eff_destroy_area", "ay_dispatch", overlay="OVL_MODAL_MISC", target="da_devastate", dispatcher="a8_swap_mdl"),
    _gen("atari8", "tramp_calc_spell_failure", "ay_dispatch", overlay="OVL_MODAL_MISC", target="calc_spell_failure", dispatcher="a8_swap_mdl"),
    _gen("atari8", "tramp_eff_item_p1", "ay_dispatch", overlay="OVL_HOME", target="eff_item_p1_exec", dispatcher="a8_swap_hom"),
    _gen("atari8", "tramp_eff_map_area", "ay_dispatch", overlay="OVL_TITLE", target="eff_map_area", dispatcher="a8_swap_ttl"),
    # Custom (21)
    _custom("atari8", "tramp_roll_ego_type", "platforms/atari8/main.s", "Preserves input A across OVL_STORAGE swap for roll_ego_type and restores caller overlay", overlay="OVL_STORAGE", target="roll_ego_type"),
    _custom("atari8", "tramp_help_cmd_body", "platforms/atari8/main.s", "Loads OVL_HELP, sets help_pages_src, runs help_cmd_body, clears carry on load fail", overlay="OVL_HELP", target="help_cmd_body"),
    _custom("atari8", "tramp_spawn_nest_gold", "platforms/atari8/main.s", "Checks resident find_special_room before swapping to OVL_DUNGEON_GEN", overlay="OVL_DUNGEON_GEN", targets=("find_special_room", "spawn_nest_gold")),
    _custom("atari8", "tramp_title_draw_screen", "platforms/atari8/main.s", "Loads OVL_TITLE and returns early (rts) on failure without resync", overlay="OVL_TITLE", target="title_draw_overlay_screen"),
    _custom("atari8", "tramp_sr_gen_loaded", "platforms/atari8/main.s", "Resident OVL_DUNGEON_GEN ensure helper disk-prompting until loaded", overlay="OVL_DUNGEON_GEN", target="overlay_load_disk"),
    _custom("atari8", "tramp_ego_append_suffix", "platforms/atari8/main.s", "Decodes ego via item_cat_decode_ego and copies into combat_msg_buf", targets=("item_cat_decode_ego",)),
    _custom("atari8", "tramp_eff_ext_eat", "platforms/atari8/main.s", "Loads OVL_TITLE for extended food effects and dynamically restores caller current_overlay", overlay="OVL_TITLE", target="eff_ext_eat_piw"),
    _custom("atari8", "tramp_eff_ext_quaff", "platforms/atari8/main.s", "Loads OVL_TITLE for extended potion effects and dynamically restores caller current_overlay", overlay="OVL_TITLE", target="eff_ext_quaff_piw"),
    _custom("atari8", "tramp_door_pick_roll", "platforms/atari8/main.s", "Loads OVL_CHEST for door_pick_roll and restores caller current_overlay preserving carry", overlay="OVL_CHEST", target="door_pick_roll"),
    _custom("atari8", "tramp_ui_identify", "platforms/atari8/main.s", "Loads OVL_UI, prints identify, restores tier data before tramp_sr_epilogue", overlay="OVL_UI", targets=("ui_identify_print", "tier_restore_after_overlay")),
    _custom("atari8", "tramp_disk_setup", "platforms/atari8/main.s", "Prompts for game disk if save media setup fails", overlay="OVL_STORAGE", targets=("disk_setup_menu", "disk_prompt_game_required")),
    _custom("atari8", "tramp_disk_prepare_selected", "platforms/atari8/main.s", "Loads OVL_STORAGE and tail-jumps disk_prepare_selected_save_media", overlay="OVL_STORAGE", target="disk_prepare_selected_save_media"),
    _custom("atari8", "tramp_store_enter", "platforms/atari8/main.s", "Dispatches STORE_HOME vs town store via overlay_load then tramp_sr_epilogue", targets=("store_enter", "home_enter")),
    _custom("atari8", "tramp_player_create", "platforms/atari8/main.s", "Uses overlay_load (with KERNAL/SIO) rather than overlay_load_no_kernal", overlay="OVL_STARTUP", target="player_create"),
    _custom("atari8", "tramp_game_over_disk_setup", "platforms/atari8/main.s", "Runs disk setup then required game disk prompt before game_over_prepare", targets=("tramp_disk_setup", "disk_prompt_game", "tramp_game_over_prepare")),
    _custom("atari8", "tramp_game_over_disk_setup_failed", "platforms/atari8/main.s", "Prompts game disk and game-disk-required recovery", targets=("disk_prompt_game", "disk_prompt_game_required")),
    _custom("atari8", "tramp_game_over_prepare", "platforms/atari8/main.s", "Loops disk_prompt_game_required until OVL_DEATH loads", overlay="OVL_DEATH", targets=("creature_get_name", "disk_prompt_game_required")),
    _custom("atari8", "tramp_game_over", "platforms/atari8/main.s", "Unconditional prepare + jump to tramp_game_over_run", targets=("tramp_game_over_prepare", "tramp_game_over_run")),
    _custom("atari8", "tramp_winner_royal", "platforms/atari8/main.s", "Runs OVL_MODAL_MISC winner retirement bonus and royal_screen", overlay="OVL_MODAL_MISC", targets=("winner_apply_retirement_bonus_overlay", "royal_screen")),
    _custom("atari8", "tramp_game_over_run", "platforms/atari8/main.s", "DeathOverlay tail routine asserting $E000-$EFFF bounds and importing ui_recall/earthquake", overlay="OVL_DEATH", targets=("score_calculate", "score_death_screen")),
    _custom("atari8", "tramp_ui_legal_display", "platforms/atari8/legal.s", "Cartridge/disk conditional legal viewer trampoline", targets=("cart_load_asset", "asset_load_retry", "legal_viewer")),
)


# ---------------------------------------------------------------------------
# Commodore 64 (63 entries: platforms/commodore/c64/main.s + legal.s + look_trampoline.s + monster_catalog64.s)
# ---------------------------------------------------------------------------
C64_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: simple / alias (2)
    _gen("c64", "tramp_find_special_room", "alias", target="find_special_room"),
    _gen("c64", "tramp_game_over_disk_setup_failed", "direct_jmp", target="disk_prompt_game"),
    # Generated: c64_bank_no_roms_preserve_flags (2)
    _gen("c64", "tramp_assign_special_room", "c64_bank_no_roms_preserve_flags", target="assign_special_room"),
    _gen("c64", "tramp_vault_seal_entrance", "c64_bank_no_roms_preserve_flags", target="vault_seal_entrance"),
    # Generated: c64_ovl_gen_bank_no_roms_sr (1)
    _gen("c64", "tramp_spawn_special_room_monsters", "c64_ovl_gen_bank_no_roms_sr", overlay="OVL_DUNGEON_GEN", target="spawn_special_room_monsters"),
    # Generated: ovl_help_sr (1)
    _gen("c64", "tramp_help_cmd_body", "ovl_help_sr", overlay="OVL_HELP", target="help_cmd_body"),
    # Generated: ovl_sr (24)
    _gen("c64", "tramp_ui_char_display", "ovl_sr", overlay="OVL_HELP", target="ui_char_display"),
    _gen("c64", "tramp_magic_recalc_mana", "ovl_sr", overlay="OVL_MODAL_MISC", target="magic_recalc_mana"),
    _gen("c64", "tramp_magic_check_new_spells", "ovl_sr", overlay="OVL_MODAL_MISC", target="magic_check_new_spells"),
    _gen("c64", "tramp_ui_inv_display", "ovl_sr", overlay="OVL_HELP", target="ui_inv_display"),
    _gen("c64", "tramp_ui_equip_display", "ovl_sr", overlay="OVL_HELP", target="ui_equip_display"),
    _gen("c64", "tramp_item_gain_spell", "ovl_sr", overlay="OVL_UI", target="item_gain_spell"),
    _gen("c64", "tramp_item_read_scroll", "ovl_sr", overlay="OVL_ITEMS", target="item_read_scroll"),
    _gen("c64", "tramp_item_aim_wand", "ovl_sr", overlay="OVL_ITEMS", target="item_aim_wand"),
    _gen("c64", "tramp_item_use_staff", "ovl_sr", overlay="OVL_ITEMS", target="item_use_staff"),
    _gen("c64", "tramp_item_refuel", "ovl_sr", overlay="OVL_ITEMS", target="item_refuel"),
    _gen("c64", "tramp_ranged_fire", "ovl_sr", overlay="OVL_ITEMS", target="ranged_fire"),
    _gen("c64", "tramp_throw_item", "ovl_sr", overlay="OVL_ITEMS", target="throw_item"),
    _gen("c64", "tramp_bash_command", "ovl_sr", overlay="OVL_ITEMS", target="bash_command"),
    _gen("c64", "tramp_disarm_command", "ovl_sr", overlay="OVL_DEATH", target="disarm_command"),
    _gen("c64", "tramp_cmd_jam", "ovl_sr", overlay="OVL_ITEMS", target="door_jam_command"),
    _gen("c64", "tramp_chest_open", "ovl_sr", overlay="OVL_CHEST", target="chest_open_command"),
    _gen("c64", "tramp_item_init_identification", "ovl_sr", overlay="OVL_ITEMS", target="item_init_identification"),
    _gen("c64", "tramp_player_tunnel", "ovl_sr", overlay="OVL_ITEMS", target="player_tunnel"),
    _gen("c64", "tramp_spell_list_display", "ovl_sr", overlay="OVL_UI", target="spell_list_display"),
    _gen("c64", "tramp_spell_execute_selected", "ovl_sr", overlay="OVL_SPELL", target="spell_execute_selected"),
    _gen("c64", "tramp_reveal_floorplan", "ovl_sr", overlay="OVL_SPELL", target="eff_reveal_floorplan"),
    _gen("c64", "tramp_eff_identify_scroll_resident", "ovl_sr", overlay="OVL_SPELL", target="eff_identify_prompt"),
    _gen("c64", "tramp_ui_wizard_display", "ovl_sr", overlay="OVL_MODAL_MISC", target="ui_wizard_display"),
    _gen("c64", "tramp_store_init_all", "ovl_sr", overlay="OVL_CHEST", target="store_init_all"),
    _gen("c64", "tramp_store_restock_all", "ovl_sr", overlay="OVL_CHEST", target="store_restock_all"),
    _gen("c64", "tramp_init_starting_kit", "ovl_sr", overlay="OVL_TITLE", target="init_starting_kit"),
    # Generated: ay_dispatch -> c64_title_piw_dispatch / c64_modal_cast_dispatch (6)
    _gen("c64", "tramp_item_wear", "ay_dispatch", overlay="OVL_TITLE", target="item_wear", dispatcher="c64_title_piw_dispatch"),
    _gen("c64", "tramp_item_takeoff", "ay_dispatch", overlay="OVL_TITLE", target="item_takeoff", dispatcher="c64_title_piw_dispatch"),
    _gen("c64", "tramp_item_eat", "ay_dispatch", overlay="OVL_TITLE", target="item_eat", dispatcher="c64_title_piw_dispatch"),
    _gen("c64", "tramp_item_quaff", "ay_dispatch", overlay="OVL_TITLE", target="item_quaff", dispatcher="c64_title_piw_dispatch"),
    _gen("c64", "tramp_player_cast_spell", "ay_dispatch", overlay="OVL_MODAL_MISC", target="player_cast_spell", dispatcher="c64_modal_cast_dispatch"),
    _gen("c64", "tramp_player_pray", "ay_dispatch", overlay="OVL_MODAL_MISC", target="player_pray", dispatcher="c64_modal_cast_dispatch"),
    # Generated: ovl_death_restore_spell_fatal (3)
    _gen("c64", "tramp_eff_item_p1", "ovl_death_restore_spell_fatal", overlay="OVL_HOME", target="eff_item_p1_exec"),
    _gen("c64", "tramp_eff_map_area", "ovl_death_restore_spell_fatal", overlay="OVL_DEATH", target="eff_map_area"),
    _gen("c64", "tramp_eff_destroy_area", "ovl_death_restore_spell_fatal", overlay="OVL_DEATH", target="da_devastate"),
    # Generated: shared game_over_prepare_ovl (1)
    _gen("c64", "tramp_game_over_prepare", "game_over_prepare_ovl", overlay="OVL_DEATH", target="creature_get_name"),
    # Custom (30)
    _custom("c64", "tramp_spawn_nest_gold", "platforms/commodore/c64/main.s", "Checks resident find_special_room and preserves caller overlay/$01/I across OVL_DUNGEON_GEN spawn_nest_gold", overlay="OVL_DUNGEON_GEN", targets=("find_special_room", "spawn_nest_gold")),
    _custom("c64", "tramp_ui_inv_select_display", "platforms/commodore/c64/main.s", "Propagates c64_caller_ovl_restore into piw_return_overlay before OVL_HELP inventory selection", overlay="OVL_HELP", target="ui_inv_select_display"),
    _custom("c64", "tramp_ui_equip_select_display", "platforms/commodore/c64/main.s", "Reloads caller overlay when c64_caller_ovl_restore is set after OVL_HELP equipment selection", overlay="OVL_HELP", target="ui_equip_select_display"),
    _custom("c64", "tramp_level_generate", "platforms/commodore/c64/main.s", "Switches $01 to BANK_NO_ROMS/BANK_NO_BASIC around banked level_generate", target="level_generate"),
    _custom("c64", "tramp_roll_ego_type", "platforms/commodore/c64/main.s", "Preserves caller $01/I and passes A input/result via Y around banked roll_ego_type", target="roll_ego_type"),
    _custom("c64", "tramp_roll_ego_type_modal", "platforms/commodore/c64/main.s", "Preserves caller $01/I around banked roll_ego_type and exports C64 test diag symbol when enabled", target="roll_ego_type"),
    _custom("c64", "tramp_ego_append_suffix", "platforms/commodore/c64/main.s", "Decodes ego suffix via item_cat_decode_ego and appends to combat_msg_buf", targets=("item_cat_decode_ego", "combat_append_str")),
    _custom("c64", "tramp_ego_apply_damage", "platforms/commodore/c64/main.s", "Preserves caller $01/I and passes A input via Y around banked ego_apply_damage", target="ego_apply_damage"),
    _custom("c64", "tramp_element_divisor", "platforms/commodore/c64/main.s", "Preserves caller $01/I around banked mm_element_divisor", target="mm_element_divisor"),
    _custom("c64", "tramp_re_equip", "platforms/commodore/c64/main.s", "Preserves caller $01/I and passes return A via Y across banked re_equip", target="re_equip"),
    _custom("c64", "tramp_ego_get_ac_bonus", "platforms/commodore/c64/main.s", "Preserves caller $01/I and passes A input/result via Y across $01 switch", target="ego_get_ac_bonus"),
    _custom("c64", "tramp_title_draw_screen", "platforms/commodore/c64/main.s", "Loads OVL_TITLE and tail-jumps platform_runtime_resync_c64 directly", overlay="OVL_TITLE", targets=("c64_title_draw_entry", "platform_runtime_resync_c64")),
    _custom("c64", "tramp_reu_show_status", "platforms/commodore/c64/main.s", "Banks BANK_NO_KERNAL preserving caller $01 and I flag around reu_show_status_banked", target="reu_show_status_banked"),
    _custom("c64", "tramp_ui_recall", "platforms/commodore/c64/main.s", "Loads OVL_DEATH via overlay_load_no_kernal before ui_recall_display", overlay="OVL_DEATH", target="ui_recall_display"),
    _custom("c64", "tramp_eff_earthquake", "platforms/commodore/c64/main.s", "Preserves caller $01/I and engages c64u_turbo_fast/normal around banked eff_earthquake_banked", target="eff_earthquake_banked"),
    _custom("c64", "tramp_item_exchange", "platforms/commodore/c64/main.s", "Loads via chest_dispatch and returns through tramp_sr_epilogue", overlay="OVL_ITEMS", target="item_exchange"),
    _custom("c64", "tramp_sr_epilogue", "platforms/commodore/c64/main.s", "Restores c64_caller_ovl_restore when nested inside an overlay caller, else runs platform_runtime_resync_c64", target="platform_runtime_resync_c64"),
    _custom("c64", "tramp_door_pick_roll", "platforms/commodore/c64/main.s", "Preserves caller $01, I, and Carry around banked door_pick_roll", target="door_pick_roll"),
    _custom("c64", "tramp_load_resume_reset", "platforms/commodore/c64/main.s", "Runs load_resume_reset in already-resident OVL_STORAGE and invalidates current_overlay", overlay="OVL_STORAGE", target="load_resume_reset"),
    _custom("c64", "tramp_item_refresh_fixed_known", "platforms/commodore/c64/main.s", "Swaps to OVL_STORAGE for item_refresh_fixed_known and restores caller overlay", overlay="OVL_STORAGE", target="item_refresh_fixed_known"),
    _custom("c64", "tramp_ui_identify", "platforms/commodore/c64/main.s", "Restores BANK_NO_BASIC before tier_restore_after_overlay then tramp_sr_epilogue", overlay="OVL_UI", targets=("ui_identify_print", "tier_restore_after_overlay")),
    _custom("c64", "tramp_disk_setup", "platforms/commodore/c64/main.s", "Loads OVL_STORAGE with KERNAL, switches BANK_NO_ROMS for disk_setup_run", overlay="OVL_STORAGE", target="disk_setup_run"),
    _custom("c64", "tramp_disk_prepare_selected", "platforms/commodore/c64/main.s", "Reinstalls C64 RAM IRQ vectors and preserves carry after storage prep", overlay="OVL_STORAGE", targets=("disk_setup_prepare_selected", "c64_install_ram_irq_vectors")),
    _custom("c64", "tramp_store_enter", "platforms/commodore/c64/main.s", "Dispatches STORE_HOME vs store_overlay_preamble + store_enter", targets=("home_enter", "store_enter")),
    _custom("c64", "tramp_player_create", "platforms/commodore/c64/main.s", "Loads OVL_STARTUP with KERNAL then switches BANK_NO_KERNAL for player_create", overlay="OVL_STARTUP", target="player_create"),
    _custom("c64", "tramp_game_over_disk_setup", "platforms/commodore/c64/main.s", "Prompts game disk after tramp_disk_setup before tramp_game_over_prepare", targets=("tramp_disk_setup", "disk_prompt_game", "tramp_game_over_prepare")),
    _custom("c64", "tramp_game_over", "platforms/commodore/c64/main.s", "Falls directly through from jsr tramp_game_over_prepare into tramp_game_over_run", targets=("tramp_game_over_prepare", "tramp_game_over_run")),
    _custom("c64", "tramp_game_over_run", "platforms/commodore/c64/main.s", "Banks KERNAL out for c64_death_score_io inside OVL_DEATH", overlay="OVL_DEATH", target="c64_death_score_io"),
    _custom("c64", "tramp_winner_royal", "platforms/commodore/c64/main.s", "Prompts disk, loads modal_misc asset directly, switches BANK_NO_KERNAL", targets=("winner_apply_retirement_bonus_overlay", "royal_screen")),
    _custom("c64", "tramp_ui_legal_display", "platforms/commodore/c64/legal.s", "C64 legal asset stream + RAM IRQ reinstall + dec $01 viewer wrapper", targets=("asset_load_required", "legal_viewer")),
    _custom("c64", "tramp_do_look", "platforms/commodore/c64/look_trampoline.s", "Lives in separate look_trampoline.s unit", overlay="OVL_MODAL_MISC", target="do_look"),
    _custom("c64", "tramp_catalog_place_win", "platforms/commodore/c64/monster_catalog64.s", "Banks banked win-creature catalog via hal_memory_cpu_port", target="catalog_place_win_creature"),
    _custom("c64", "tramp_item_pickup", "platforms/commodore/c64/main.s", "Preserves caller $01/I and Carry around banked item_pickup", target="item_pickup"),
)


# ---------------------------------------------------------------------------
# Commodore Plus/4 (platforms/commodore/plus4/main.s + legal.s + look_trampoline.s)
# ---------------------------------------------------------------------------
PLUS4_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: simple / resync (3)
    _gen("plus4", "tramp_sr_epilogue", "direct_jmp", target="plus4_platform_runtime_resync"),
    _gen("plus4", "tramp_reu_show_status", "noop_rts"),
    _gen("plus4", "tramp_game_over_disk_setup_failed", "direct_jmp", target="disk_prompt_game"),
    # Generated: plus4_bank_ram_preserve_flags (2)
    _gen("plus4", "tramp_assign_special_room", "plus4_bank_ram_preserve_flags", target="assign_special_room"),
    _gen("plus4", "tramp_vault_seal_entrance", "plus4_bank_ram_preserve_flags", target="vault_seal_entrance"),
    # Generated: plus4_ovl_gen_cached_sr (1)
    _gen("plus4", "tramp_spawn_special_room_monsters", "plus4_ovl_gen_cached_sr", overlay="OVL_DUNGEON_GEN", target="spawn_special_room_monsters"),
    # Generated: plus4_bank_ram_preserve_a_ret (1)
    _gen("plus4", "tramp_ego_get_ac_bonus", "plus4_bank_ram_preserve_a_ret", target="ego_get_ac_bonus"),
    # Generated: ay_dispatch -> plus4_ovl_sr_dispatch (21)
    _gen("plus4", "tramp_ui_char_display", "ay_dispatch", overlay="OVL_TITLE", target="ui_char_display", dispatcher="plus4_disp_title"),
    _gen("plus4", "tramp_magic_recalc_mana", "ay_dispatch", overlay="OVL_MODAL_MISC", target="magic_recalc_mana", dispatcher="plus4_disp_modal"),
    _gen("plus4", "tramp_magic_check_new_spells", "ay_dispatch", overlay="OVL_MODAL_MISC", target="magic_check_new_spells", dispatcher="plus4_disp_modal"),
    _gen("plus4", "tramp_ui_inv_display", "ay_dispatch", overlay="OVL_HELP", target="ui_inv_display", dispatcher="plus4_disp_help"),
    _gen("plus4", "tramp_ui_equip_display", "ay_dispatch", overlay="OVL_HELP", target="ui_equip_display", dispatcher="plus4_disp_help"),
    _gen("plus4", "tramp_item_read_scroll", "ay_dispatch", overlay="OVL_ITEMS", target="item_read_scroll", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_item_aim_wand", "ay_dispatch", overlay="OVL_ITEMS", target="item_aim_wand", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_item_use_staff", "ay_dispatch", overlay="OVL_ITEMS", target="item_use_staff", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_item_refuel", "ay_dispatch", overlay="OVL_ITEMS", target="item_refuel", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_item_exchange", "ay_dispatch", overlay="OVL_ITEMS", target="item_exchange", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_ranged_fire", "ay_dispatch", overlay="OVL_ITEMS", target="ranged_fire", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_throw_item", "ay_dispatch", overlay="OVL_ITEMS", target="throw_item", dispatcher="plus4_disp_items"),
    _gen("plus4", "tramp_bash_command", "ay_dispatch", overlay="OVL_TITLE", target="bash_command", dispatcher="plus4_disp_title"),
    _gen("plus4", "tramp_disarm_command", "ay_dispatch", overlay="OVL_TITLE", target="disarm_command", dispatcher="plus4_disp_title"),
    _gen("plus4", "tramp_cmd_jam", "ay_dispatch", overlay="OVL_CHEST", target="door_jam_command", dispatcher="plus4_disp_chest"),
    _gen("plus4", "tramp_chest_open", "ay_dispatch", overlay="OVL_CHEST", target="chest_open_command", dispatcher="plus4_disp_chest"),
    _gen("plus4", "tramp_player_tunnel", "ay_dispatch", overlay="OVL_TITLE", target="player_tunnel", dispatcher="plus4_disp_title"),
    _gen("plus4", "tramp_ui_wizard_display", "ay_dispatch", overlay="OVL_MODAL_MISC", target="ui_wizard_display", dispatcher="plus4_disp_modal"),
    _gen("plus4", "tramp_store_init_all", "ay_dispatch", overlay="OVL_HELP", target="store_init_all", dispatcher="plus4_disp_help"),
    _gen("plus4", "tramp_store_restock_all", "ay_dispatch", overlay="OVL_HELP", target="store_restock_all", dispatcher="plus4_disp_help"),
    _gen("plus4", "tramp_init_starting_kit", "ay_dispatch", overlay="OVL_HELP", target="init_starting_kit", dispatcher="plus4_disp_help"),
    # Generated: ovl_sr (4)
    _gen("plus4", "tramp_item_init_identification", "ovl_sr", overlay="OVL_DEATH", target="item_init_identification"),
    _gen("plus4", "tramp_item_gain_spell", "ovl_sr", overlay="OVL_UI", target="item_gain_spell"),
    _gen("plus4", "tramp_reveal_floorplan", "ovl_sr", overlay="OVL_SPELL", target="eff_reveal_floorplan"),
    _gen("plus4", "tramp_eff_identify_scroll_resident", "ovl_sr", overlay="OVL_SPELL", target="eff_identify_prompt"),
    # Generated: ovl_death_restore_spell_fatal (4)
    _gen("plus4", "tramp_eff_earthquake", "ovl_death_restore_spell_fatal", overlay="OVL_TITLE", target="eff_earthquake"),
    _gen("plus4", "tramp_eff_map_area", "ovl_death_restore_spell_fatal", overlay="OVL_TITLE", target="eff_map_area"),
    _gen("plus4", "tramp_eff_destroy_area", "ovl_death_restore_spell_fatal", overlay="OVL_MODAL_MISC", target="da_devastate"),
    _gen("plus4", "tramp_eff_item_p1", "ovl_death_restore_spell_fatal", overlay="OVL_HOME", target="eff_item_p1_exec"),
    # Generated: plus4_title_ovl (2)
    _gen("plus4", "tramp_title_load_and_draw", "plus4_title_ovl", overlay="OVL_TITLE", target="plus4_title_load_menu_ovl"),
    _gen("plus4", "tramp_title_render_data", "plus4_title_ovl", overlay="OVL_TITLE", target="plus4_title_redraw_menu_ovl"),
    # Generated: shared game_over_prepare_ovl + game_over_direct (2)
    _gen("plus4", "tramp_game_over_prepare", "game_over_prepare_ovl", overlay="OVL_DEATH", target="creature_get_name"),
    _gen("plus4", "tramp_game_over", "game_over_direct", target="tramp_game_over_run"),
    # Custom (37)
    _custom("plus4", "tramp_load_resume_reset", "platforms/commodore/plus4/main.s", "Runs load_resume_reset in already-resident OVL_STORAGE and invalidates current_overlay", overlay="OVL_STORAGE", target="load_resume_reset"),
    _custom("plus4", "tramp_trap_trigger", "platforms/commodore/plus4/main.s", "Banks RAM and reloads X=df_disarm_trap_idx before resident $F000 trap_trigger", target="trap_trigger"),
    _custom("plus4", "tramp_item_drop", "platforms/commodore/plus4/main.s", "Loads OVL_HELP via plus4_ovl_caller_dispatch preserving caller overlay for ? selector", overlay="OVL_HELP", target="item_drop"),
    _custom("plus4", "tramp_help_cmd_body", "platforms/commodore/plus4/main.s", "Loads OVL_HELP via plus4_ovl_caller_dispatch preserving C=1 LEGALUI request", overlay="OVL_HELP", target="plus4_help_cmd_body"),
    _custom("plus4", "tramp_spawn_nest_gold", "platforms/commodore/plus4/main.s", "Checks RT_NEST in $F000 first, loads OVL_DUNGEON_GEN, and restores caller overlay", overlay="OVL_DUNGEON_GEN", targets=("find_special_room", "spawn_nest_gold")),
    _custom("plus4", "tramp_item_wear", "platforms/commodore/plus4/main.s", "Loads OVL_ITEMS via plus4_ovl_caller_dispatch, preserving caller overlay for ?/extended calls", overlay="OVL_ITEMS", target="item_wear"),
    _custom("plus4", "tramp_item_takeoff", "platforms/commodore/plus4/main.s", "Loads OVL_ITEMS via plus4_ovl_caller_dispatch, preserving caller overlay for ? calls", overlay="OVL_ITEMS", target="item_takeoff"),
    _custom("plus4", "tramp_item_eat", "platforms/commodore/plus4/main.s", "Loads OVL_ITEMS via plus4_ovl_caller_dispatch, preserving caller overlay for ?/extended calls", overlay="OVL_ITEMS", target="item_eat"),
    _custom("plus4", "tramp_item_quaff", "platforms/commodore/plus4/main.s", "Loads OVL_ITEMS via plus4_ovl_caller_dispatch, preserving caller overlay for ?/extended calls", overlay="OVL_ITEMS", target="item_quaff"),
    _custom("plus4", "tramp_player_cast_spell", "platforms/commodore/plus4/main.s", "Loads OVL_TITLE via plus4_ovl_caller_dispatch, preserving caller overlay for ?/cast/spell calls", overlay="OVL_TITLE", target="player_cast_spell"),
    _custom("plus4", "tramp_player_pray", "platforms/commodore/plus4/main.s", "Loads OVL_TITLE via plus4_ovl_caller_dispatch, preserving caller overlay for ?/cast/spell calls", overlay="OVL_TITLE", target="player_pray"),
    _custom("plus4", "tramp_ui_inv_select_display", "platforms/commodore/plus4/main.s", "Propagates plus4_caller_ovl_restore into piw_return_overlay when zero before loading OVL_HELP", overlay="OVL_HELP", target="ui_inv_select_display"),
    _custom("plus4", "tramp_ui_equip_select_display", "platforms/commodore/plus4/main.s", "Loads OVL_HELP then restores plus4_caller_ovl_restore via plus4_ovl_caller_epilogue", overlay="OVL_HELP", target="ui_equip_select_display"),
    _custom("plus4", "tramp_spell_list_display", "platforms/commodore/plus4/main.s", "Loads OVL_UI then restores plus4_caller_ovl_restore via plus4_ovl_caller_epilogue", overlay="OVL_UI", target="spell_list_display"),
    _custom("plus4", "tramp_spell_execute_selected", "platforms/commodore/plus4/main.s", "Loads OVL_SPELL then restores plus4_caller_ovl_restore via plus4_ovl_caller_epilogue", overlay="OVL_SPELL", target="spell_execute_selected"),
    _custom("plus4", "tramp_eff_ext_eat", "platforms/commodore/plus4/main.s", "Loads OVL_DEATH then restores plus4_caller_ovl_restore via plus4_ovl_caller_epilogue", overlay="OVL_DEATH", target="eff_ext_eat_piw"),
    _custom("plus4", "tramp_eff_ext_quaff", "platforms/commodore/plus4/main.s", "Loads OVL_DEATH then restores plus4_caller_ovl_restore via plus4_ovl_caller_epilogue", overlay="OVL_DEATH", target="eff_ext_quaff_piw"),
    _custom("plus4", "tramp_level_generate", "platforms/commodore/plus4/main.s", "Invalidates non-cart catalog cache and banks RAM twice around level_generate", target="level_generate"),
    _custom("plus4", "tramp_find_special_room", "platforms/commodore/plus4/main.s", "Saves input A around sei + plus4_bank_ram before tramp_sr_epilogue", target="find_special_room"),
    _custom("plus4", "tramp_calc_spell_failure", "platforms/commodore/plus4/main.s", "Preserves carry across caller-overlay restore and plus4_platform_runtime_resync", overlay="OVL_MODAL_MISC", target="calc_spell_failure"),
    _custom("plus4", "tramp_ego_append_suffix", "platforms/commodore/plus4/main.s", "Decodes ego via item_cat_decode_ego in Default without banking RAM over KERNAL", target="item_cat_decode_ego"),
    _custom("plus4", "tramp_ego_apply_damage", "platforms/commodore/plus4/main.s", "Banks RAM around ego_apply_damage without preserving return A", target="ego_apply_damage"),
    _custom("plus4", "tramp_roll_ego_type", "platforms/commodore/plus4/main.s", "Preserves input A across OVL_CHEST swap for roll_ego_type/roll_armour_ego and restores caller overlay", overlay="OVL_CHEST", target="roll_ego_type"),
    _custom("plus4", "tramp_re_equip", "platforms/commodore/plus4/main.s", "Loads OVL_CHEST for re_equip and restores caller current_overlay returning A", overlay="OVL_CHEST", target="re_equip"),
    _custom("plus4", "tramp_ui_recall", "platforms/commodore/plus4/main.s", "Loads OVL_DEATH and calls sei + plus4_bank_ram before ui_recall_display", overlay="OVL_DEATH", target="ui_recall_display"),
    _custom("plus4", "tramp_ui_identify", "platforms/commodore/plus4/main.s", "Banks RAM before tier_restore_after_overlay after ui_identify_print", overlay="OVL_UI", targets=("ui_identify_print", "tier_restore_after_overlay")),
    _custom("plus4", "tramp_disk_setup", "platforms/commodore/plus4/main.s", "Loads OVL_STORAGE with KERNAL then banks RAM for disk_setup_run", overlay="OVL_STORAGE", target="disk_setup_run"),
    _custom("plus4", "tramp_disk_prepare_selected", "platforms/commodore/plus4/main.s", "Preserves carry across resync and returns directly on load failure", overlay="OVL_STORAGE", target="disk_setup_prepare_selected"),
    _custom("plus4", "tramp_store_enter", "platforms/commodore/plus4/main.s", "Branches STORE_HOME (overlay_load_no_kernal + bank_ram) vs store_overlay_preamble", targets=("store_enter", "home_enter")),
    _custom("plus4", "tramp_player_create", "platforms/commodore/plus4/main.s", "Loads OVL_STARTUP with KERNAL then sets sei + plus4_bank_ram", overlay="OVL_STARTUP", target="player_create"),
    _custom("plus4", "tramp_game_over_disk_setup", "platforms/commodore/plus4/main.s", "Stashes/restores $E000 across disk setup using MAP_BASE", targets=("tramp_game_over_prepare", "tramp_game_over_stash", "tramp_disk_setup", "tramp_game_over_restore_stash")),
    _custom("plus4", "tramp_game_over_run", "platforms/commodore/plus4/main.s", "DeathOverlay tail routine running score_calculate, high score I/O, and score_death_screen", overlay="OVL_DEATH", targets=("score_calculate", "score_death_screen")),
    _custom("plus4", "tramp_winner_royal", "platforms/commodore/plus4/main.s", "Direct modal_misc asset load + scripted retirement test exit hook", targets=("winner_apply_retirement_bonus_overlay", "royal_screen")),
    _custom("plus4", "tramp_game_over_stash", "platforms/commodore/plus4/main.s", "RuntimeBanked helper copying $E000-$EFFF overlay to MAP_BASE", target="plus4_copy_overlay_window"),
    _custom("plus4", "tramp_game_over_restore_stash", "platforms/commodore/plus4/main.s", "RuntimeBanked helper restoring MAP_BASE back to $E000-$EFFF", target="plus4_copy_overlay_window"),
    _custom("plus4", "tramp_ui_legal_display", "platforms/commodore/plus4/legal.s", "Plus/4 legal asset stream + RAM IRQ install + viewer trampoline", targets=("asset_load_required", "legal_viewer")),
    _custom("plus4", "tramp_do_look", "platforms/commodore/plus4/look_trampoline.s", "Lives in separate look_trampoline.s unit", overlay="OVL_MODAL_MISC", target="do_look"),
)


# ---------------------------------------------------------------------------
# Commodore 128 (73 entries: platforms/commodore/c128/main.s + legal.s + look_trampoline.s + common/disk_setup_runtime128.s)
# ---------------------------------------------------------------------------
C128_ENTRIES: Tuple[TrampolineEntry, ...] = (
    # Generated: c128_ovl_compute (15)
    _gen("c128", "tramp_eff_item_p1", "c128_ovl_compute", overlay="C128_HOME_OVERLAY_ID", target="eff_item_p1_exec"),
    _gen("c128", "tramp_init_starting_kit", "c128_ovl_compute", overlay="C128_HOME_OVERLAY_ID", target="init_starting_kit"),
    _gen("c128", "tramp_cmd_jam", "c128_ovl_compute", overlay="OVL_STORAGE", target="door_jam_command"),
    _gen("c128", "tramp_item_read_scroll", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="item_read_scroll"),
    _gen("c128", "tramp_item_aim_wand", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="item_aim_wand"),
    _gen("c128", "tramp_item_use_staff", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="item_use_staff"),
    _gen("c128", "tramp_item_refuel", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="item_refuel"),
    _gen("c128", "tramp_item_exchange", "c128_ovl_compute", overlay="OVL_STORAGE", target="item_exchange"),
    _gen("c128", "tramp_spell_execute_selected", "c128_ovl_compute", overlay="OVL_DEATH", target="spell_execute_selected"),
    _gen("c128", "tramp_ranged_fire", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="ranged_fire"),
    _gen("c128", "tramp_player_tunnel", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="player_tunnel"),
    _gen("c128", "tramp_throw_item", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="throw_item"),
    _gen("c128", "tramp_bash_command", "c128_ovl_compute", overlay="C128_ITEMS_OVERLAY_ID", target="bash_command"),
    _gen("c128", "tramp_disarm_command", "c128_ovl_compute", overlay="C128_DISARM_OVERLAY_ID", target="disarm_command"),
    _gen("c128", "tramp_item_init_identification", "c128_ovl_compute", overlay="C128_CHEST_OVERLAY_ID", target="item_init_identification"),
    # Generated: c128_banked_compute (4)
    _gen("c128", "tramp_player_cast_spell", "c128_banked_compute", target="player_cast_spell"),
    _gen("c128", "tramp_player_pray", "c128_banked_compute", target="player_pray"),
    _gen("c128", "tramp_magic_recalc_mana", "c128_banked_compute", target="magic_recalc_mana"),
    _gen("c128", "tramp_magic_check_new_spells", "c128_banked_compute", target="magic_check_new_spells"),
    # Generated: c128_ui_display (1)
    _gen("c128", "tramp_spell_list_display", "c128_ui_display", target="spell_list_display"),
    # Generated: c128 banked macro families (7)
    _gen("c128", "tramp_find_special_room", "c128_banked_preserve_a", target="find_special_room"),
    _gen("c128", "tramp_ego_apply_damage", "c128_banked_preserve_a", target="ego_apply_damage"),
    _gen("c128", "tramp_roll_ego_type", "c128_banked_preserve_a_return", target="roll_ego_type"),
    _gen("c128", "tramp_assign_special_room", "c128_banked_preserve_flags", target="assign_special_room"),
    _gen("c128", "tramp_vault_seal_entrance", "c128_banked_preserve_flags", target="vault_seal_entrance"),
    _gen("c128", "tramp_spawn_special_room_monsters", "c128_banked_shared_epilogue", target="spawn_special_room_monsters"),
    _gen("c128", "tramp_spawn_nest_gold", "c128_banked_shared_epilogue", target="spawn_nest_gold"),
    # Generated: c128_ovl_death_return (2)
    _gen("c128", "tramp_eff_earthquake", "c128_ovl_death_return", overlay="C128_ITEMS_OVERLAY_ID", target="eff_item_overlay_dispatch"),
    _gen("c128", "tramp_eff_destroy_area", "c128_ovl_death_return", overlay="C128_CHEST_OVERLAY_ID", target="da_devastate"),
    # Generated: c128_ovl_tail (2)
    _gen("c128", "tramp_store_restock_all", "c128_ovl_tail", overlay="10", target="store_restock_all"),
    _gen("c128", "tramp_title_load_and_draw", "c128_ovl_tail", overlay="C128_HELP_OVERLAY_ID", target="title_load_and_draw"),
    # Generated: ax_dispatch (17)
    _gen("c128", "tramp_item_wear", "ax_dispatch", overlay="OVL_STORAGE", target="item_wear", dispatcher="c128_storage_piw_dispatch"),
    _gen("c128", "tramp_item_eat", "ax_dispatch", overlay="OVL_STORAGE", target="item_eat", dispatcher="c128_storage_piw_dispatch"),
    _gen("c128", "tramp_item_quaff", "ax_dispatch", overlay="OVL_STORAGE", target="item_quaff", dispatcher="c128_storage_piw_dispatch"),
    _gen("c128", "tramp_ui_char_display", "ax_dispatch", overlay="C128_UI_OVERLAY_ID", target="ui_char_display", dispatcher="tramp_ui_ui_overlay_patch_target"),
    _gen("c128", "tramp_ui_recall", "ax_dispatch", overlay="C128_UI_OVERLAY_ID", target="ui_recall_display", dispatcher="tramp_ui_ui_overlay_patch_target"),
    _gen("c128", "tramp_ui_wizard_display", "ax_dispatch", overlay="C128_UI_OVERLAY_ID", target="ui_wizard_display", dispatcher="tramp_ui_ui_overlay_patch_target"),
    _gen("c128", "tramp_item_gain_spell", "ax_dispatch", overlay="C128_UI_OVERLAY_ID", target="item_gain_spell", dispatcher="tramp_ui_ui_overlay_patch_target"),
    _gen("c128", "tramp_ui_inv_display", "ax_dispatch", overlay="C128_HELP_OVERLAY_ID", target="ui_inv_display", dispatcher="tramp_ui_inv_common"),
    _gen("c128", "tramp_ui_equip_display", "ax_dispatch", overlay="C128_HELP_OVERLAY_ID", target="ui_equip_display", dispatcher="tramp_ui_equip_common"),
    _gen("c128", "tramp_door_try_open", "ax_dispatch", overlay="C128_HELP_OVERLAY_ID", target="door_try_open", dispatcher="c128_help_cmd_dispatch"),
    _gen("c128", "tramp_door_try_close", "ax_dispatch", overlay="C128_HELP_OVERLAY_ID", target="door_try_close", dispatcher="c128_help_cmd_dispatch"),
    _gen("c128", "tramp_item_drop", "ax_dispatch", overlay="C128_HELP_OVERLAY_ID", target="item_drop", dispatcher="c128_help_cmd_dispatch"),
    _gen("c128", "tramp_load_resume_reset", "ax_dispatch", overlay="C128_HELP_OVERLAY_ID", target="load_resume_reset", dispatcher="c128_help_cmd_dispatch"),
    _gen("c128", "tramp_pm_require_class_level", "ax_dispatch", overlay="2", target="pm_require_class_level", dispatcher="c128_town_magic_dispatch"),
    _gen("c128", "tramp_pm_handle_fail_roll", "ax_dispatch", overlay="2", target="pm_handle_fail_roll", dispatcher="c128_town_magic_dispatch"),
    _gen("c128", "tramp_pm_build_known_list", "ax_dispatch", overlay="2", target="pm_build_known_list_from_book", dispatcher="c128_town_magic_dispatch"),
    _gen("c128", "tramp_pm_validate_spell", "ax_dispatch", overlay="2", target="pm_validate_selected_spell", dispatcher="c128_town_magic_dispatch"),
    # Generated: ay_dispatch / alias (2)
    _gen("c128", "tramp_chest_open", "ay_dispatch", overlay="C128_CHEST_OVERLAY_ID", target="chest_open_command", dispatcher="chest_dispatch"),
    _gen("c128", "tramp_game_over_disk_setup", "alias", target="tramp_disk_setup"),
    # Custom (37)
    _custom("c128", "tramp_player_create", "platforms/commodore/c128/main.s", "Startup overlay execution tracking + C128_TEST_TOWN_SELF_DUMP diagnostics + return site", target="player_create"),
    _custom("c128", "tramp_player_create_return_site", "platforms/commodore/c128/main.s", "Continuation label cleared after player_create returns"),
    _custom("c128", "tramp_game_over_disk_setup_failed", "platforms/commodore/c128/main.s", "Falls directly through into tramp_game_over_prepare"),
    _custom("c128", "tramp_game_over_prepare", "platforms/commodore/c128/main.s", "Shared no-op rts return site for failed disk setup"),
    _custom("c128", "tramp_game_over", "platforms/commodore/c128/main.s", "Falls directly through into tramp_game_over_run"),
    _custom("c128", "tramp_game_over_run", "platforms/commodore/c128/main.s", "Loads OVL 3 (OVL_DEATH) and runs C128 high-score/death sequence", overlay="OVL_DEATH", targets=("score_calculate", "score_death_screen")),
    _custom("c128", "tramp_winner_royal", "platforms/commodore/c128/main.s", "Prompts disk, loads modal_misc directly, jumps to royal_screen", targets=("royal_screen",)),
    _custom("c128", "tramp_store_init_all", "platforms/commodore/c128/main.s", "Includes C128_REAL_BOOT_DIAG stack guard probes around store init overlay 10", target="store_init_all"),
    _custom("c128", "tramp_store_enter", "platforms/commodore/c128/main.s", "Dispatches overlay 11 (home) vs overlay 2 (town) restoring runtime guards", targets=("store_enter", "home_enter")),
    _custom("c128", "tramp_ui_enter", "platforms/commodore/c128/main.s", "C128 UI/KERNAL RAM bank-in prologue ($ff00=$3e, $01=$34)"),
    _custom("c128", "tramp_ui_exit", "platforms/commodore/c128/main.s", "C128 UI/KERNAL epilogue restoring runtime guards and CLI"),
    _custom("c128", "tramp_ui_help_display", "platforms/commodore/c128/main.s", "Uses tramp_ui_enter/exit around C128_HELP_OVERLAY_ID help_pages setup", overlay="C128_HELP_OVERLAY_ID", target="ui_help_display"),
    _custom("c128", "tramp_help_cmd_body", "platforms/commodore/c128/main.s", "Uses tramp_ui_enter/exit around C128_HELP_OVERLAY_ID help_pages setup for help_cmd_body", overlay="C128_HELP_OVERLAY_ID", target="help_cmd_body"),
    _custom("c128", "tramp_door_pick_roll", "platforms/commodore/c128/main.s", "Loads C128_DISARM_OVERLAY_ID for door_pick_roll and restores caller current_overlay preserving carry", overlay="C128_DISARM_OVERLAY_ID", target="door_pick_roll"),
    _custom("c128", "tramp_pick_item_type_spawn", "platforms/commodore/c128/main.s", "Calls pick_item_type_overlay in C128_CHEST_OVERLAY_ID preserving caller C128_HELP_OVERLAY_ID", overlay="C128_CHEST_OVERLAY_ID", target="pick_item_type_overlay"),
    _custom("c128", "tramp_ui_ui_overlay_patch_target", "platforms/commodore/c128/main.s", "Self-modifying dispatcher falling through into tramp_ui_ui_overlay_common"),
    _custom("c128", "tramp_ui_ui_overlay_common", "platforms/commodore/c128/main.s", "Shared C128_UI_OVERLAY_ID caller wrapped by tramp_ui_enter/exit", overlay="C128_UI_OVERLAY_ID"),
    _custom("c128", "tramp_ui_inv_select_display", "platforms/commodore/c128/main.s", "Falls directly through into tramp_ui_inv_common", target="ui_inv_select_display"),
    _custom("c128", "tramp_ui_inv_common", "platforms/commodore/c128/main.s", "Self-modifying C128_HELP_OVERLAY_ID inv dispatcher wrapped by tramp_ui_enter/exit", overlay="C128_HELP_OVERLAY_ID"),
    _custom("c128", "tramp_ui_equip_select_display", "platforms/commodore/c128/main.s", "Falls directly through into tramp_ui_equip_common", target="ui_equip_select_display"),
    _custom("c128", "tramp_ui_equip_common", "platforms/commodore/c128/main.s", "Self-modifying C128_HELP_OVERLAY_ID equip dispatcher wrapped by tramp_ui_enter/exit", overlay="C128_HELP_OVERLAY_ID"),
    _custom("c128", "tramp_item_takeoff", "platforms/commodore/c128/main.s", "Sets c128_equip_return_overlay before dispatching item_takeoff in OVL_STORAGE", overlay="OVL_STORAGE", target="item_takeoff"),
    _custom("c128", "tramp_ego_get_ac_bonus", "platforms/commodore/c128/main.s", "Inline indexed lookup of resident Bank 0 ego_ac_bonus table"),
    _custom("c128", "tramp_level_generate", "platforms/commodore/c128/main.s", "Includes C128_REAL_BOOT_DIAG stack guards around Banked level_generate", target="level_generate"),
    _custom("c128", "tramp_sr_epilogue", "platforms/commodore/c128/main.s", "Restores MMU_ALL_RAM ($ff00) and CLI"),
    _custom("c128", "tramp_ego_append_suffix", "platforms/commodore/c128/main.s", "Inline copy loop from ITEM.CAT ego suffix decoder to combat_msg_buf (no BankOutKernal before hal_item_cat_read_byte)", target="ego_get_suffix_ptr"),
    _custom("c128", "tramp_p3_dispatch_items", "platforms/commodore/c128/main.s", "Resident items->OVL_MODAL_MISC Phase 3 scroll bridge falling through to return", overlay="OVL_MODAL_MISC", target="irs_dispatch_p3_overlay"),
    _custom("c128", "tramp_p3_dispatch_items_return", "platforms/commodore/c128/main.s", "Continuation label restoring OVL_ITEMS after modal Phase 3 handlers", overlay="OVL_ITEMS"),
    _custom("c128", "tramp_staff_speed_items", "platforms/commodore/c128/main.s", "Runs eff_staff_speed in OVL_DEATH then restores OVL_ITEMS", overlay="OVL_DEATH", target="eff_staff_speed"),
    _custom("c128", "tramp_p3_death_items", "platforms/commodore/c128/main.s", "Self-modifying resident OVL_DEATH bridge preserving A via tpdi_arg", overlay="OVL_DEATH"),
    _custom("c128", "tramp_p3_death_cloud", "platforms/commodore/c128/main.s", "Loads OVL_DEATH for eff_directional_monster, prints message, restores OVL_ITEMS", overlay="OVL_DEATH", target="eff_directional_monster"),
    _custom("c128", "tramp_p3_death_remove_curse", "platforms/commodore/c128/main.s", "Loads OVL_DEATH for eff_remove_curse, prints message, restores OVL_ITEMS", overlay="OVL_DEATH", target="eff_remove_curse"),
    _custom("c128", "tramp_ui_legal_display", "platforms/commodore/c128/legal.s", "C128 cartridge/disk legal loader + modal persist/viewer trampoline", targets=("asset_load_required", "legal_viewer")),
    _custom("c128", "tramp_do_look", "platforms/commodore/c128/look_trampoline.s", "Lives in separate look_trampoline.s unit calling tramp_ui_enter/exit", overlay="C128_HELP_OVERLAY_ID", target="do_look"),
    _custom("c128", "tramp_disk_setup_ui_action", "platforms/commodore/common/disk_setup_runtime128.s", "Lives in shared C128 runtime disk-setup module", target="ui_disk_setup_dispatch"),
    _custom("c128", "tramp_disk_setup", "platforms/commodore/common/disk_setup_runtime128.s", "Lives in shared C128 runtime disk-setup module", targets=("c128_modal_require_persist", "disk_setup_run")),
    _custom("c128", "tramp_disk_prepare_selected", "platforms/commodore/common/disk_setup_runtime128.s", "Lives in shared C128 runtime disk-setup module", targets=("c128_modal_require_persist", "disk_setup_prepare_selected")),
)


PORT_ENTRIES: Dict[str, Tuple[TrampolineEntry, ...]] = {
    "apple2": APPLE2_ENTRIES,
    "bbcmaster": BBCMASTER_ENTRIES,
    "cx16": CX16_ENTRIES,
    "atari8": ATARI8_ENTRIES,
    "c64": C64_ENTRIES,
    "plus4": PLUS4_ENTRIES,
    "c128": C128_ENTRIES,
}


def iter_entries(port: Optional[str] = None) -> Iterable[TrampolineEntry]:
    if port is not None:
        return PORT_ENTRIES[port]
    out: List[TrampolineEntry] = []
    for key in PORTS:
        out.extend(PORT_ENTRIES[key])
    return tuple(out)


def manifest_index(port: str) -> Dict[str, TrampolineEntry]:
    index: Dict[str, TrampolineEntry] = {}
    for entry in PORT_ENTRIES[port]:
        if entry.name in index:
            raise ValueError(f"Duplicate manifest entry for {port}: {entry.name}")
        index[entry.name] = entry
    return index
