// main.s — Entry point for Moria8 C128 (80-column VDC mode)
//
// SKELETON — Not yet buildable. This file will be fleshed out in
// Phase 10.1 (VDC rendering backend) and later sub-phases.
//
// Structure mirrors c64/main.s:
//   - BASIC stub + bootstrap (C128 MMU banking instead of $01)
//   - Platform-specific hardware init (VDC setup, MMU config)
//   - Imports shared game logic from ../common/
//   - Trampoline routines using MMU $FF00 banking
//   - Overlay segment definitions

// ============================================================
// Shared game logic — imported from commodore/common/
// ============================================================
// These will be #imported once the C128 platform modules exist:
//
// #import "../common/zeropage.s"
// #import "../common/rng.s"
// #import "../common/math.s"
// #import "../common/tables.s"
// #import "../common/item_defs.s"
// #import "../common/player.s"
// #import "../common/ui_messages.s"
// #import "../common/ui_status.s"
// #import "../common/stat_display.s"
// #import "../common/sound.s"
// #import "../common/huffman.s"
// #import "../common/dungeon_data.s"
// #import "../common/dungeon_features.s"
// #import "../common/monster.s"
// #import "../common/tier_manager.s"
// #import "../common/overlay.s"
// #import "../common/monster_ai.s"
// #import "../common/recall.s"
// #import "../common/monster_magic.s"
// #import "../common/item.s"
// #import "../common/player_items.s"
// #import "../common/spell_data.s"
// #import "../common/spell_effects.s"
// #import "../common/player_magic.s"
// #import "../common/dungeon_los.s"
// #import "../common/player_move.s"
// #import "../common/combat.s"
// #import "../common/projectile.s"
// #import "../common/ranged_fire.s"
// #import "../common/throw.s"
// #import "../common/bash.s"
// #import "../common/tunnel.s"
// #import "../common/monster_attack.s"
// #import "../common/turn.s"
// #import "../common/store_data.s"
// #import "../common/string_bank.s"
// #import "../common/save.s"
// #import "../common/disk_swap.s"
// #import "../common/score_io.s"
// #import "../common/color.s"
// #import "../common/reu.s"
// #import "../common/title_screen.s"
// #import "../common/game_loop.s"

// ============================================================
// C128-specific platform modules (to be implemented)
// ============================================================
// #import "memory128.s"        // MMU $FF00/$D500 banking, memory map constants
// #import "screen_vdc.s"       // VDC 80-col rendering (register-indirect writes)
// #import "dungeon_render_vdc.s" // VDC viewport rendering
// #import "config128.s"        // C128 detection, VDC type probe
// #import "input128.s"         // C128 keyboard via KERNAL or direct scan

// ============================================================
// Trampoline stubs — same labels as c64/main.s, MMU banking
// ============================================================
// The C128 uses MMU register $FF00 for fast bank configuration
// instead of the C64's PLA register at $01.
//
// Each trampoline will:
//   sei
//   lda #$xx        ; MMU configuration for RAM-only access
//   sta $ff00
//   jsr target      ; Call overlay/banked routine
//   lda #$xx        ; Restore normal MMU config
//   sta $ff00
//   cli
//   rts
//
// Trampoline labels that game_loop.s expects:
//   tramp_level_generate
//   tramp_store_enter
//   tramp_player_create
//   tramp_game_over
//   tramp_ui_help_display
//   tramp_ui_char_display
//   tramp_ui_inv_display
//   tramp_ui_equip_display
//   tramp_ui_recall
//   tramp_roll_ego_type
//   tramp_ego_append_suffix
//   tramp_ego_apply_damage
//   tramp_ego_get_ac_bonus
//   title_show_sysinfo
//   game_over_prompt
//   exit_trampoline
//
// Platform-specific labels that game_loop.s calls:
//   render_viewport
//   render_local_area
//   viewport_update
//   screen_clear
//   screen_clear_row
//   screen_put_string
//   screen_put_char
//   input_get_key
//   input_get_command

// ============================================================
// C128-specific string data
// ============================================================
// title_str:
//     .text "MORIA8 C=128" ; .byte 0
