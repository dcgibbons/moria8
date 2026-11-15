#define HAL_PLATFORM_LEGAL_VIEWER
#define HELP_TITLE_EXTERNAL
#define HOME_OVERLAY_SEPARATE
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#define HAL_PLATFORM_RECALL_CUSTOM
#define RECALL_ARRAY_DATA_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_P1_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
// main.s — Apple IIe moria8 linker script + entry
//
// Assemble from platforms/apple2 with:
//   -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -define APPLE2
//
// Memory authority: docs/APPLE2_MEMORY_POLICY.md.
//   Default (resident): $0A00-$7BFF, entry pinned at $0A00 for boot.s
//   A2PlaySlot:         $7C00-$9FFF (play payload, load-once + signature)
//   Tier-name pool:     $A000-$A3FF
//   Overlay window:     $A400-$BAFF (code region $A400-$B9FF)
//
// All 11 overlay classes are window-hosted (STORAGE ~3.1K and TITLE ~0.4K
// fit the 4,608 B code region), so there is no runtime slot swap: the play
// payload is loaded once per session by a2_require_play (overlay_storage.s)
// with signature validation and disk-reload fallback.

// The VMS monster catalog (2026-11-05): fields and Huffman names in aux RAM
// (monster_catalog_a2.s, cache_layout.s), replacing the four tier files.
#define HAL_PLATFORM_MONSTER_CATALOG
#define APPLE2_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define APPLE2_PRODUCT_IRQ_VECTOR_RUNTIME
#define PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME
.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")

// ============================================================
// Segment definitions
// ============================================================
.segmentdef StartupOverlay    [outPrg=OVL_OUT + "/ovl.start",   start=$a400, min=$a400, max=$b9ff]
.segmentdef TownOverlay       [outPrg=OVL_OUT + "/ovl.town",    start=$a400, min=$a400, max=$b9ff]
.segmentdef DeathOverlay      [outPrg=OVL_OUT + "/ovl.death",   start=$a400, min=$a400, max=$b9ff]
.segmentdef ModalMiscOverlay  [outPrg=OVL_OUT + "/ovl.modal",   start=$a400, min=$a400, max=$b9ff]
.const LEGAL_BASE = $a400
.const LEGAL_LIMIT = $ba00
.segmentdef LegalOverlay [outPrg=OVL_OUT + "/legalui", start=$a400, min=$a400, max=$b9ff]
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",    start=$a400, min=$a400, max=$b9ff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",      start=$a400, min=$a400, max=$b9ff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items",  start=$a400, min=$a400, max=$b9ff]
.segmentdef SpellOverlay      [outPrg=OVL_OUT + "/ovl.spell",   start=$a400, min=$a400, max=$b9ff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",     start=$a400, min=$a400, max=$b9ff]
.segmentdef StorageOverlay    [outPrg=OVL_OUT + "/ovl.storage", start=$a400, min=$a400, max=$b9ff]
.segmentdef TitleOverlay      [outPrg=OVL_OUT + "/ovl.title",   start=$a400, min=$a400, max=$b9ff]
.segmentdef ChestOverlay      [outPrg=OVL_OUT + "/ovl.chest",   start=$a400, min=$a400, max=$b9ff]
.segmentdef HomeOverlay       [outPrg=OVL_OUT + "/ovl.home",    start=$a400, min=$a400, max=$b9ff]
.segmentdef A2PlaySlot        [outPrg=OVL_OUT + "/a2.play",     start=$7c00, min=$7c00, max=$9fff]
.segmentdef A2AuxData         [outPrg=OVL_OUT + "/a2.auxdata",  start=$3b0c, min=$3b0c, max=$4fff]
.segmentdef A2Catalog         [outPrg=OVL_OUT + "/a2.catalog",  start=$5000, min=$5000, max=$66ff]
.segmentdef A2HuffData        [outPrg=OVL_OUT + "/a2.huffdata", start=$8d00, min=$8d00, max=$a9ff]
.const A2_HUFFDATA_BASE = $8d00

// Huffman data placement: aux RAM at $3B0C (boot-preloaded).
.macro HuffmanDataSegment() {
    .segment A2HuffData
}
.macro AuxDataSegment() {
    .segment A2AuxData
}
.macro ItemNameStreamsSegment() {
    .segment A2AuxData
}
.macro ItemNameStreamsRestoreSegment() {
    .segment Default
}
.macro ResidentItemsSegment() {
    .segment Default
}
.macro ResidentItemNamesSegment() {
    .segment Default
}
.macro ResidentWorldSegment() {
    .segment Default
}
.macro ResidentPlaySegment() {
    .segment A2PlaySlot
}

#import "hal/storage_policy.s"
#import "save_slot_policy.s"
#import "vic_palette_consts.s"

// SFX_* semantic sound IDs (keep in sync with core/sound.s, which this port
// cannot import — it programs the SID directly).
.const SFX_NONE     = $ff
.const SFX_BUMP     = $00
.const SFX_HIT      = $01
.const SFX_MISS     = $02
.const SFX_PICKUP   = $03
.const SFX_DEATH    = $04
.const SFX_LEVELUP  = $05
.const SFX_SPELL    = $06
.const SFX_SPELL_FAIL = $07
.const SFX_HUNGER_WARN  = $08
.const SFX_HUNGER_FAINT = $09

// ============================================================
// Default segment opens at $0A00 with the pinned bootstrap boot.s
// jumps to; everything resident follows (C64 main.s shape).
// ============================================================
.pc = $0a00 "Resident"
entry_bootstrap:
    jmp entry_main

// ============================================================
// Platform media state bytes (shared save.s bookkeeping surface).
// save_device/program_device hold ProDOS unit bytes (drive/slot nibbles)
// resolved by ON_LINE; disk_mode uses the A2_DISK_MODE_* values
// (1 = game disk, 2 = two-drive, 3 = one-drive swap).
// ============================================================
save_device:        .byte 0
program_device:     .byte 0
disk_mode:          .byte 0
disk_setup_done:    .byte 0
tsi_krev_cached:    .byte 0

// save_slot_index lives in unbanked platform ZP: the shared save engine runs
// in the OVL.STORAGE window (evicted on overlay swaps), and any address >=
// $0200 is RAMRD/RAMWRT bank-switched on the IIe, so a resident non-ZP byte
// can read back aux data when map code leaves RAMRD on. $aa is free in the
// $90-$ef platform window (memory.s).
.label save_slot_index = $aa

// tramp_dig_ability — pinned jump for tunnel code (resident).
tramp_dig_ability:
    jmp calc_dig_ability

// ============================================================
// Resident import cascade (clone c64 main.s order; transitive core
// imports are NOT repeated here — core files pull their own parts
// via libdir, and duplicate paths double-define symbols)
// ============================================================
#import "../../core/zeropage.s"
#import "hal/layout.s"
#import "memory.s"
#import "cache_layout.s"   // the aux spans: aux data, catalog fields, overlay cache
#import "bank_port_consts.s"
#import "hal/lifecycle_policy.s"
#import "overlay.s"
// Apple II overlay IDs 11..13 sit after shared OVL_CHEST (10). Because
// HAL_PLATFORM_MAP_GET_TILE_USES_SUBROUTINE gates 11..13 in common/overlay.s,
// define OVL_HOME/OVL_STORAGE/OVL_TITLE explicitly here.
.const OVL_HOME    = 11
.const OVL_STORAGE = 12
.const OVL_TITLE   = 13
// save_slot_index is declared in main.s (resident), not in the shared save
// engine's overlay window, so the loaded/saved slot survives overlay swaps.
#define SAVE_SLOT_INDEX_EXTERNAL
#import "reu_stub.s"
#import "screen_a2.s"
#import "../../core/color.s"
#import "config.s"
#import "input.s"
#import "../../core/rng.s"
#import "../../core/math.s"
#import "../../core/tables.s"
#import "../../core/item_defs.s"
#define PLAYER_RECALC_PFLAGS_EXTERNAL
#define PFLAGS_SEGMENT_CUSTOM
.macro PflagsSegment() {
    .segment ModalMiscOverlay
}
.macro PflagsRestoreSegment() {
    .segment Default
}
#import "../../core/player.s"
// The message-history ring buffer lives in aux data (the resident
// always-region is full); writes go through mmu_safe_map_write_ptr1.
#define MSG_HISTORY_IN_AUX
.macro MsgHistorySegment() {
    .segment A2AuxData
}
.macro MsgHistoryRestoreSegment() {
    .segment Default
}
#import "../../core/ui_messages.s"
#import "../../core/ui_status.s"
#import "../../core/runtime_ui_strings.s"
// Resident, not in the play slot: asset_load_ask_for_disk shows it when the
// play slot's own load has failed.
#define PRESS_KEY_STR_EXTERNAL
press_key_str:
    .text "Press any key" ; .byte 0
#import "../../core/generation_busy.s"
#define SMALL_PLAY_EXTERNAL
#import "../../core/stat_display.s"
#import "../../core/huffman.s"
.segment A2HuffData
#import "../shared/catalog/catalog_names.s"    // The catalog's names, read like the corpus
// Read-only aux tables ride the corpus slot (boot-loaded, never evicted):
// 16-item stores filled A2AuxData. Readers use 16-bit aux pointers.
// Screen-code -> Apple display-code table for inputs $00-$7F (P6). Must
// reproduce a2_map_char (screen_a2.s) exactly for that range: $00->$C0,
// $01-$1A->$E1-$FA, $1B-$1F->$DB-$DF, $20-$5A->code|$80, $5B-$5F->$9B-$9F,
// $60-$7F->$A0. High-half inputs stay on the branch chain. Block-read into
// the tail of a2_ss_buf once per render_viewport (rv_char_map).
a2_char_map_aux:
    .fill $80, i == 0 ? $c0 : i < $1b ? (i + $60) | $80 : i < $20 ? (i + $40) | $80 : i < $5b ? i | $80 : i < $60 ? (i + $40) | $80 : $a0
.assert "Char map table covers $00-$7F", * - a2_char_map_aux, $80

ovl_huffdata_end:
.segment Default
// Speaker sound patterns for hal_sound_play (services.s), in main resident
// RAM since 2026-11-11 (the element touches' messages filled the corpus
// slot; the resident image had room): one 16-byte slot
// per SFX ID, as (period, toggles) pairs with period 0 = end. Period:
// smaller = higher pitch. Shapes mirror the C64 SID intent (core/sound.s).
// Parked in A2AuxData and read via A2_ZP_THUNK_READ_P1 to save Default bytes.
.segment A2AuxData
a2_sfx_patterns:
    .byte $e0, 10, $c0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   // BUMP: low double thud
    .byte $50, 8, $90, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    // HIT: high-to-low snap
    .byte $28, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0       // MISS: quick high blip
    .byte $a0, 6, $70, 6, $48, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0  // PICKUP: rising chirp
    .byte $60, 20, $90, 20, $c0, 24, $f0, 28, 0, 0, 0, 0, 0, 0, 0, 0 // DEATH: long descent
    .byte $80, 8, $60, 8, $40, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0  // LEVELUP: arpeggio up
    .byte $58, 12, $66, 12, $58, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 // SPELL: wobble
    .byte $d0, 16, $b0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    // SPELL_FAIL: low buzz
    .byte $c8, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0      // HUNGER_WARN: single low tone
    .byte $e8, 18, $d8, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   // HUNGER_FAINT: lower, harsher
.assert "Sound patterns are 10 x 16-byte slots", * - a2_sfx_patterns, 160
.segment Default
#import "../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
// place_secrets runs only from dungeon generation, so on this port it lives
// in the GEN overlay (dungeon_gen.s) instead of resident dungeon_features.s.
#define PLACE_SECRETS_EXTERNAL
.macro ChestSearchSegment() {
    .segment Default
}
.macro ChestSearchRestoreSegment() {
    .segment Default
}
#define CHEST_ROUTING_ENABLED
#define CMD_JAM_SEGMENT_CUSTOM
#define CMD_JAM_WRAPPER_CUSTOM
#define CMD_JAM_EXTERNAL
// The jam command handler parks with the cold chest commands (the play slot
// is full); its wrapper lives resident like the other A2 overlay trampolines.
.macro CmdJamSegment() {
    .segment ChestOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
// The locked-door pick roll needs the effective-disarm formula; it parks in
// the chest overlay with chest_disarm_skill.
#define DOOR_PICK_EXTERNAL
.macro DoorPickSegment() {
    .segment ChestOverlay
}
.macro DoorPickRestoreSegment() {
    .segment Default
}
.macro CmdJamWrapperSegment() {
    .segment Default
}
.macro CmdJamWrapperRestoreSegment() {
    // Only the tiny cmd_jam wrapper is resident (the dispatch table jumps
    // to it while overlays own the window); the rest of game_loop.s stays
    // in the play slot.
    .segment A2PlaySlot
}
#import "../../core/dungeon_features.s"
#import "../../core/chest_search.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../core/monster.s"
// A2 play slot is full, so the door-close refusal helper lives resident near
// its only caller (door_try_close). combat_msg_monster_suffix and friends
// stay in the play slot; resident->play calls during the play phase are
// precedented (monster_magic.s -> combat.s message builders).
combat_msg_monster_in_way:
    jsr monster_get_ptr         // zp_ptr0 = entry
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    lda #<cmb_in_way_str
    ldy #>cmb_in_way_str
    jmp combat_msg_monster_suffix
cmb_in_way_str:
    .text " is in your way!" ; .byte 0
#import "../../core/recall_defs.s"
#import "monster_catalog_a2.s"
#import "../../core/monster_catalog.s"
#import "../../core/tier_manager.s"
#import "../../core/monster_ai.s"
#import "../../core/scene_dirty.s"
// scene_mat_tile lives in dungeon_render_a2.s (falls into render_single_tile).
#import "../../core/scene_force.s"
#import "../../core/monster_magic.s"
.macro ChestSummonsSegment() {
    .segment A2PlaySlot
}
.macro ChestSummonsRestoreSegment() {
    .segment A2PlaySlot
}
#define ITEM_SPAWN_IN_GEN_OVERLAY
.macro ItemSpawnSegment() {
    .segment DungeonGenOverlay
}
.macro ItemSpawnRestoreSegment() {
    .segment Default
}
#define HAL_PLATFORM_ITEM_PICKUP_OVERLAY
.macro ItemPickupSegment() {
    .segment ItemActionsOverlay
}
.macro ItemPickupRestoreSegment() {
    .segment Default
}
#define RE_EQUIP_SEGMENT_CUSTOM
.macro ReEquipSegment() {
    .segment ModalMiscOverlay
}
.macro ReEquipRestoreSegment() {
    .segment Default
}
.label re_equip_entry = tramp_re_equip
#import "../../core/item.s"
#define MON_ATK_ACID_EXTERNAL   // monster_acid.s rides the resident image (below)
// Step-13 chest loot: latch + resident handoff stay in Default (play slot is
// full); the generator parks in the GEN overlay with the picker it uses.
.macro ChestLootSegment() {
    .segment DungeonGenOverlay
}
.macro ChestLootRestoreSegment() {
    .segment Default
}
#import "../../core/chest_loot.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#define PLAYER_ITEM_COMMANDS_EXTERNAL
#define PLAYER_ITEM_SELECT_EXTERNAL
#import "../../core/player_items.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#define EFF_FIND_DOORS_EXTERNAL
#import "../../core/spell_effects.s"
#undef EFF_FIND_DOORS_EXTERNAL
#define EFF_DESTROY_TRAPS_DOORS_EXTERNAL
#import "../../core/spell_effects_overlay.s"
#undef EFF_DESTROY_TRAPS_DOORS_EXTERNAL
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
// turn.s's regen/poison tables in resident main RAM: the play slot has no
// room (#importonce: turn.s's own import is then a no-op).
#import "../../core/turn_data.s"
// Heal feedback (spell/potion heal + message) in resident main RAM too: the
// play slot has no room. The potion heal/cure effects sit beside it, where
// both the items overlay (#17, #25) and the spell overlay (#96, #100) reach.
#import "../../core/player_heal_feedback.s"
#import "../../core/eff_potion_cure.s"

// Constants are needed by resident consumers before the data/code placement
// later in A2PlaySlot and A2AuxData. These imports emit no bytes.
#import "../../core/store_data_defs.s"
#import "../../core/spell_data_defs.s"

#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
#import "../../core/player_magic.s"
#import "dungeon_render_a2.s"
// C64 $F000-banked content is ordinary resident bytes on this platform,
// except the map/earthquake spell engines, which ride the death overlay
// beside player_destroy_area.s behind tramp_eff_* overlay swaps.
#import "../../core/item_desc_banked.s"
#import "../../core/projectile.s"
// The ball's per-creature damage and Orb of Draining's entry (resident: the
// SPELL cache slot is full; called only from eff_ball in OVL.SPELL).
#import "../../core/player_magic_ball_harm.s"
#import "../../core/player_magic_ball_holy.s"
#import "compat/io_kernal_consts.s"
#import "../../core/storage_status.s"
#import "memory_aux.s"
.assert "Recall Aux LC Bank 1 allocation fits below $E000", A2_LC_RECALL_BASE + RECALL_DATA_SIZE - 1 <= $dfff, true
.assert "ITEM.CAT Aux LC High allocation fits before Aux vectors", A2_LC_ITEM_CAT_BASE + ITMCAT_TOTAL_SIZE - 1 <= A2_LC_MAX_DATA_END, true
#import "mmu_macros.s"
#import "save_stream.s"
#import "storage_mli.s"
#import "overlay_storage.s"
#import "services.s"

// ============================================================
// entry — jumped to via entry_bootstrap after payload load
// ============================================================
entry_main:
    jsr hal_platform_init_early     // soft switches + ZP thunks
    jsr a2_reset_session_state
    jsr generation_busy_install
    jsr platform_services_install_a2
    jsr platform_services_assert_installed
    lda #OVL_TITLE
    jsr overlay_load
    bcc !preload_ok+
    jmp hal_platform_panic
!preload_ok:
    jsr a2_boot_preload_aux_lc

restart_entry:
    jsr detect_machine              // fixed Apple IIe / 80-col identity
    jsr reu_detect                  // stub: zeroes REU state
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #<title_enter_menu_ovl
    ldy #>title_enter_menu_ovl
    ldx #OVL_TITLE
    jsr tramp_ovl_dispatch
    jsr title_draw_menu

#if A2_DEBUG_AUTONEW
    jmp !new_game+
#endif
title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
!new_game:
    jsr a2_require_play
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    lda disk_setup_done
    bne !load_now+
    jsr tramp_disk_setup
    bcs title_enter_menu
!load_now:
    jmp title_load_game
!not_l:
    cmp #$41                // A: About, before a character exists
    bne !not_legal_title+
    jsr tramp_ui_legal_display
    bcc !legal_done+
    // No program disk is needed to return to the resident title menu.
    jsr hal_screen_clear
    jsr title_draw_menu
    jmp title_menu_loop
!legal_done:
    jmp title_enter_menu
!not_legal_title:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    jmp title_enter_menu

title_draw_menu:
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #(SCREEN_COLS - (title_menu_str_end - title_menu_str)) / 2
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jmp screen_put_string

a2_reset_session_state:
    lda #0
    sta disk_setup_done
    sta disk_mode
    sta save_device
    sta program_device
    ldx #(A2_LOW_SCRATCH_END - A2_LOW_SCRATCH_BASE)
!clr_low:
    sta A2_LOW_SCRATCH_BASE,x
    dex
    bpl !clr_low-
    rts

title_load_game:
    lda #<title_load_game_ovl
    ldy #>title_load_game_ovl
    ldx #OVL_STORAGE
    jsr tramp_ovl_dispatch
    bcs !title_load_fail+
    // Media handling order matters here: disk_prompt_game_required lives in
    // the play slot (game_loop.s), which a cold boot has not loaded yet.
    // Probe/prompt game media with the resident prompt first, then load the
    // play payload, then run the play-slot verifier.
    jsr disk_prompt_game        // Resident: swap back to the game disk if dual
    jsr a2_require_play
    jsr disk_prompt_game_required
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jmp title_enter_menu

// ============================================================
// Platform services (indirect API slots in core/platform_services_api.s)
// ============================================================
platform_services_install_a2:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<a2_platform_main_loop_begin
    sta platform_main_loop_begin_api + 1
    lda #>a2_platform_main_loop_begin
    sta platform_main_loop_begin_api + 2

    lda #<a2_platform_vector_reassert
    sta platform_vector_reassert_api + 1
    lda #>a2_platform_vector_reassert
    sta platform_vector_reassert_api + 2

    lda #<a2_platform_runtime_resync
    sta platform_runtime_resync_api + 1
    lda #>a2_platform_runtime_resync
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

// ============================================================
// Special rooms trampolines — implementations live in OVL.GEN,
// which stays current through the whole generate+spawn phase
// ============================================================

// Shared overlay dispatch for single-call trampolines with no register inputs.
// Input: A/Y = target routine, X = overlay ID.
tramp_ovl_dispatch:
    sta tod_jmp+1
    sty tod_jmp+2
    txa
    jsr overlay_load
    bcs !done+
tod_jmp:
    jmp $0000
!done:
    rts

// ============================================================
// Ego-item trampolines (C64 banks ego_items.s at $F000; resident here).
// Placed late: tramp_ego_append_suffix needs combat.s's COMBAT_MSG_BUF_LAST.
// ============================================================
#if !BYPASS_SLOT_PROMPT
save_prepare_slot_prompt:
    lda #OVL_STORAGE
    jmp overlay_load

save_select_slot_prompt:
    jmp save_select_slot_prompt_impl
#endif

// ============================================================
// UI / item / store / spell trampolines. The window is plain main
// RAM, so these are direct calls after overlay_load — no banking,
// no epilogue.
// ============================================================
overlay_load_no_kernal:
    jmp overlay_load

run_initialize:
    lda #<run_initialize_impl
    ldy #>run_initialize_impl
    ldx #OVL_MODAL_MISC
    jmp tramp_ovl_dispatch

item_spawn_level:
    lda #<item_spawn_level_gen
    ldy #>item_spawn_level_gen
    ldx #OVL_DUNGEON_GEN
    jmp tramp_ovl_dispatch

// Shared OVL.MODAL_MISC swap-and-restore dispatcher (used by
// hal_player_recalc_pflags and generated tramp_re_equip). Preserves
// return A across caller overlay restore.
hal_player_recalc_pflags:
    lda #<player_recalc_pflags_equipment
    ldy #>player_recalc_pflags_equipment
modal_swap_dispatch:
    sta msd_call+1
    sty msd_call+2
    lda current_overlay
    pha
    cmp #OVL_MODAL_MISC
    beq msd_call
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !msd_fail+
msd_call:
    jsr $0000
    tax
    pla
    beq !msd_done+
    cmp #OVL_MODAL_MISC
    beq !msd_done+
    jsr overlay_load
!msd_done:
    txa
    rts
!msd_fail:
    pla
    lda #0
    rts

#import "legal.s"
#import "../../build/trampolines/apple2_trampolines.inc"

// Chest routing (docs/CHEST_DESIGN.md). tramp_chest_open is called from the
// resident cmd_open pre-dispatch. chest_dispatch is tail-called (A/Y =
// handler) from bash_command/disarm_command inside OVL.ITEMS; the overlay
// swap runs from resident code, so the evicted caller is never returned into
// (its caller trampoline owns the continuation). Store init/restock also ride
// the chest overlay on this platform (transition-only code, safe in a
// non-town overlay) because the ITEMS window is full.
chest_dispatch:
    sta chest_disp_jmp+1
    sty chest_disp_jmp+2
    lda #OVL_CHEST
    jsr overlay_load
    bcs !done+
chest_disp_jmp:
    jmp $0000               // SMC dispatch target (never JMP (addr); the
                            // 6502 page-crossing bug reads the high byte
                            // from $xx00 when the pointer is at $xxFF)
!done:
    rts

// Call an OVL.DEATH routine from OVL.SPELL, preserving A across the overlay
// swap and restoring OVL.SPELL before returning.
// Input: X/Y = target routine address in OVL.DEATH; A = target argument.
tramp_death_call_restore_spell:
    stx tdcr_target+1
    sty tdcr_target+2
    pha
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    pla
tdcr_target:
    jsr $0000
    jmp tramp_restore_spell_overlay
!load_failed:
    pla
    rts

eff_destroy_traps_doors:
    ldx #<eff_destroy_traps_doors_impl
    ldy #>eff_destroy_traps_doors_impl
    jmp tramp_death_call_restore_spell

eff_find_doors:
    lda current_overlay
    pha
    ldx #<eff_find_doors_impl
    ldy #>eff_find_doors_impl
    jsr tramp_death_call_restore_spell
    pla
    cmp #OVL_SPELL
    beq !efd_done+
    jmp overlay_load
!efd_done:
    rts

// Shared OVL.CHEST -> OVL.ITEMS dispatcher for extended food/potion effects
// (eff_item_extended.s). Caller (player_item_commands.s) runs in OVL_ITEMS.
// Input: A/Y = target handler in ChestOverlay.
tramp_chest_call_restore_items:
    sta tccri_target+1
    sty tccri_target+2
    lda #OVL_CHEST
    jsr overlay_load
    bcs !tccri_restore+
tccri_target:
    jsr $0000
!tccri_restore:
    lda #OVL_ITEMS
    jmp overlay_load

tramp_store_enter:
    lda zp_store_idx
    cmp #STORE_HOME
    beq !home+
    lda #<store_enter
    ldy #>store_enter
    ldx #OVL_TOWN
    jmp tramp_ovl_dispatch
!home:
    lda #<home_enter
    ldy #>home_enter
    ldx #OVL_HOME
    jmp tramp_ovl_dispatch

// ============================================================
// Media prompts (Commodore parity). Resident like the Commodore originals:
// callers run with arbitrary overlays live (death flow keeps OVL.DEATH),
// so no overlay loads may happen here. Only one-drive swap mode prompts:
// two-drive mode assumes the save disk stays mounted (failures route through
// tramp_disk_prepare_selected), and game-disk mode needs no media handling.
// The prompt bodies live in the storage overlay (_impl): every call flow
// (title load, in-game save, post-save swap-back) has already loaded
// OVL.STORAGE via save_prepare_slot_prompt or the save itself, so the
// resident names below are skip-if-current trampolines that never load.
// Probes reuse the resident media probes: the marker probe answers "is the
// save volume mounted" and the program probe answers "is the game volume
// mounted" without an ON_LINE scan.
// ============================================================
disk_prompt_save:
    lda disk_mode
    cmp #A2_DISK_MODE_SWAP
    beq !dps_load+
    clc
    rts
!dps_load:
    lda #<disk_prompt_save_impl
    ldy #>disk_prompt_save_impl
    ldx #OVL_STORAGE
    jmp tramp_ovl_dispatch

disk_prompt_game:
    lda disk_mode
    cmp #A2_DISK_MODE_SWAP
    beq !dpg_load+
    clc
    rts
!dpg_load:
    lda #<disk_prompt_game_impl
    ldy #>disk_prompt_game_impl
    ldx #OVL_STORAGE
    jmp tramp_ovl_dispatch

// ============================================================
// Death orchestration
// ============================================================

tramp_winner_royal:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !done+
    jsr winner_apply_retirement_bonus_overlay
    jmp royal_screen
!done:
    rts

// ============================================================
// game_over_prompt — return to title/menu after save, quit, or death.
// ============================================================
game_over_prompt:
    lda #OVL_DEATH
    jsr overlay_load
    bcc !overlay_ok+
    jmp title_enter_menu
!overlay_ok:
    jmp game_restart_overlay

// a2_msg_print_indirect_aux — Print the NUL-terminated AUX string at
// (zp_ptr0) via a main-RAM staging buffer. Used by MsgPrintStr for
// platform-externalized strings (idle-lifetime alias of a2_ss_buf: save
// streams, title staging, and these message prints never overlap).
// Clobbers: A, Y, zp_ptr0.
.label a2_aux_str_stage = a2_ss_buf
a2_msg_print_indirect_aux:
hal_msg_print_indirect_aux:
    ldy #$ff
!loop:
    iny
    jsr mmu_safe_map_read_ptr0
    sta a2_aux_str_stage,y
    bne !loop-
    lda #<a2_aux_str_stage
    sta zp_ptr0
    lda #>a2_aux_str_stage
    sta zp_ptr0_hi
    jmp msg_print

// ============================================================
// A2PlaySlot segment — play payload (C128 play-class composition).
// Signature "M8P" validated by a2_require_play after every load.
// ============================================================
.segment A2PlaySlot
a2_play_start:
    .byte $4d, $38, $50     // "M8P"
a2_play_body:
// Chest summoning-trap runner is called only from game_loop.s (play), so it
// parks here in the play slot rather than the full resident Default payload.
#import "../../core/chest_summons.s"
// Apple item commands call this resident routine while the item overlay is
// active. Keep the stat transition code in the always-loaded play payload.
player_adjust_equipment_stat:
    // As core/player_adjust_equipment_stat.s: the stat by the item
    // (equip_stat_index, core/player.s), p1 added or taken away.
    jsr player_adjust_equipment_stat_prepare
    jsr equip_stat_index
    bcc !paes_done+
    jmp player_adjust_equipment_stat_apply   // Y = the stat
!paes_done:
    rts

#define STORE_RUNTIME_DATA_EXTERNAL
#define STORE_INVENTORY_DATA_EXTERNAL
#import "../../core/store_data.s"
#undef STORE_INVENTORY_DATA_EXTERNAL
#undef STORE_RUNTIME_DATA_EXTERNAL
#import "../../core/store_hot_data.s"
#import "../../core/recall.s"
#import "../../core/dungeon_los.s"
#import "../../core/monster_attack.s"

.macro PlayerMoveRestoreResidentSegment() {
    .segment A2PlaySlot
}
.macro PlayerMoveLookSegment() {
    .segment ModalMiscOverlay
}
.macro PlayerCastSegment() {
    .segment SpellOverlay
}
.macro PlayerCastRestoreResidentSegment() {
    .segment Default
}
.macro PmHelpersSegment() {
    .segment SpellOverlay
}
.macro PmHelpersRestoreSegment() {
    .segment Default
}
.macro ItemInitIdentSegment() {
    .segment StartupOverlay
}
.macro ItemInitIdentRestoreSegment() {
    .segment Default
}
.macro WizardGenExecRestoreSegment() {
    .segment A2PlaySlot
}
.macro WizardGenExecSegment() {
    .segment ModalMiscOverlay
}
// The recall-view (monster memory) command body lives in ModalMiscOverlay
// on this platform; the play-slot stub loads the overlay and tail-calls.
#define RECALL_VIEW_OVERLAYED
.const RECALL_VIEW_OVL = OVL_MODAL_MISC
.macro RecallViewBodySegment() {
    .segment ModalMiscOverlay
}
.macro RecallViewBodyRestoreSegment() {
    .segment A2PlaySlot
}
.macro ChestRouteSegment() {
    // Resident, not the play slot: the slot is full, and the open pre-dispatch
    // is reachable from every phase anyway.
    .segment Default
}
.macro ChestRouteRestoreSegment() {
    .segment A2PlaySlot
}
#define PLAYER_LOOK_EXTERNAL
#import "../../core/player_move.s"
#undef PLAYER_LOOK_EXTERNAL
.macro PlayerRunInitializeSegment() {
    .segment ModalMiscOverlay
}
.macro PlayerRunRestoreResidentSegment() {
    .segment A2PlaySlot
}
#define PLAYER_RUN_INITIALIZE_EXTERNAL
#import "../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL
#define PMU_TURN_FEEDBACK_EXTERNAL
#define CMB_WINNER_STR_EXTERNAL
#define CMB_IN_WAY_EXTERNAL
#import "../../core/combat.s"
#undef CMB_IN_WAY_EXTERNAL
#undef CMB_WINNER_STR_EXTERNAL
#undef PMU_TURN_FEEDBACK_EXTERNAL
#define WIZARD_PROMPT_HELPERS_EXTERNAL
#import "../../core/wizard.s"
#undef WIZARD_PROMPT_HELPERS_EXTERNAL
#define PLAYER_LOOK_EXTERNAL
#define DISARM_COMMAND_EXTERNAL
#define WELCOME_STR_EXTERNAL
#define GAME_LOOP_NAV_STRINGS_EXTERNAL
#define GAME_LOOP_NO_STAIRS_STR_EXTERNAL
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#undef PLAYER_LOOK_EXTERNAL
#import "dungeon_scroll_a2.s"
#define TURN_REST_DISTURBED_EXTERNAL
#import "../../core/turn.s"
#undef TURN_REST_DISTURBED_EXTERNAL
// Small play-resident modules (play is present in every gameplay phase).
#import "../../core/ui_restore.s"
#import "../../core/ui_help_clear.s"
#import "../../core/stat_display.s"

// LOOK lives in the cold modal overlay; dispatch from the load-once play slot
// so the call cannot enter whichever unrelated payload currently owns $A400.
tramp_do_look:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr do_look
!done:
    jmp tramp_sr_epilogue

.assert "Play payload starts with 3-byte signature", a2_play_body - a2_play_start, 3

// Data-only aux blocks. No labels in these files are executable, and all
// runtime access is routed through the Apple II AuxRead/AuxWrite thunks.
.segment A2AuxData
#import "../../core/store_inventory_data.s"
#import "../../core/spell_class_data.s"
#define STORE_HOT_DATA_EXTERNAL
#import "../../core/store_runtime_data.s"
#undef STORE_HOT_DATA_EXTERNAL
#import "../../core/spell_helper_tables.s"
// Spell/prayer name pointer tables and strings. Consumed only by
// spell_list_display (OVL.SPELL), so they cannot stay in OVL.UI; aux keeps
// them readable through the map thunks regardless of the loaded overlay.
#import "../../core/spell_names.s"

// Platform-externalized game_loop message strings (welcome, search toggle,
// stairs). Staged to main RAM by a2_msg_print_indirect_aux at print time;
// frees ~160 bytes of play-slot space.
welcome_str:
    .text "Welcome to Moria! ?=help. Shift+Q=quit." ; .byte 0
search_mode_on_str:
    .text "Search mode on." ; .byte 0
search_mode_off_str:
    .text "Search mode off." ; .byte 0
descend_str:
    .text "You descend the staircase." ; .byte 0
ascend_str:
    .text "You ascend the staircase." ; .byte 0
at_surface_str:
    .text "You are already at the surface." ; .byte 0
no_stairs_str:
    .text "You see no stairs here." ; .byte 0
cmb_winner_str:
    .text "You have won! Shift+Q to claim victory." ; .byte 0

.segment Default

// Auto-rest disturbance flag (core/turn.s, TRN-007) in resident main RAM:
// the play slot has no room for it (TURN_REST_DISTURBED_EXTERNAL).
turn_rest_disturbed: .byte 0

// The acid attack's armour damage (MON-015), resident for the same reason
// (MON_ATK_ACID_EXTERNAL).
#import "../../core/monster_acid.s"

// ============================================================
// Overlay segment blocks (C64 composition, adjusted)
// ============================================================
.segment TownOverlay
#import "../../core/store.s"
#import "../../core/ui_store.s"
inv_add_carried:                    // the store's (HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL)
    :InvAddCarriedBody()
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $a400) + " bytes"
.assert "Town overlay fits window code region", ovl_town_end <= $ba00, true

.segment HomeOverlay
#import "../../core/ui_home.s"
#import "../../core/ui_home_text.s"
#import "../../core/eff_item_p1.s"
ovl_home_end:
.print "Home overlay: " + (ovl_home_end - $a400) + " bytes"
.assert "Home overlay fits window code region", ovl_home_end <= $ba00, true

.segment StartupOverlay
#import "../../core/background_data.s"
#import "../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $a400) + " bytes"
.assert "Startup overlay fits", ovl_start_end <= $ba00, true

.segment DeathOverlay
// winner_apply_retirement_bonus_overlay — applies the retirement bonus from
// the royal flow (same shape as C64/Plus4): game_loop.s skips its plain-name
// call on this platform so the bonus is applied exactly once. It rides the
// death overlay (game-end services) because the modal overlay's aux cache
// slot is full and the resident image funds the chest routing.
winner_apply_retirement_bonus_overlay:
    lda player_data + PL_LEVEL
    cmp #41
    bcs !gold+
    clc
    adc #40
    sta player_data + PL_LEVEL
    sta zp_player_lvl
!gold:
    lda player_data + PL_GOLD_0
    clc
    adc #$90
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc #$d0
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #$03
    sta player_data + PL_GOLD_2
    :GoldCapOnCarry()               // 250,000 more stops at 16,777,215
    lda player_data + PL_XP_0
    clc
    adc #$40
    sta player_data + PL_XP_0
    lda player_data + PL_XP_1
    adc #$4b
    sta player_data + PL_XP_1
    lda player_data + PL_XP_2
    adc #$4c
    sta player_data + PL_XP_2
    rts
#import "../../core/royal.s"
// game_restart_overlay — reset game state, return to title screen
// (C64 main.s:2225 semantics, de-banked).
game_restart_overlay:
    lda #0
    ldx #0
!clr_zp:
    sta zp_player_x,x
    inx
    cpx #(zp_entropy - zp_player_x + 1)
    bne !clr_zp-

    lda #0
    sta eff_fear_timer
    ldx #3
!clr_recall:
    sta recall_query_sc,x
    dex
    bpl !clr_recall-

    lda #$ff
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv_id:
    sta inv_item_id,x
    dex
    bpl !clr_inv_id-

    lda #0
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv_rest:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    dex
    bpl !clr_inv_rest-

    sta current_tier
    sta tier_loaded
    jmp title_enter_menu
#import "../../core/score_io.s"
#import "../../core/score.s"

// tramp_game_over_run — Death orchestration tail, colocated in the death
// overlay with its callees (score, hiscore, death screen). Both entry paths
// (tramp_game_over after prepare, game_over_save_and_show for save+quit)
// reach it with the overlay active.
tramp_game_over_run:
    jsr score_calculate
    jsr hiscore_load
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    jsr hiscore_insert
    jsr hiscore_save
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source
    jmp score_death_screen
    #define SCROLL_P3_NEW_OWNER
    #define SCROLL_P3_EXISTING_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER
    #undef SCROLL_P3_NEW_OWNER
    // Word of Destruction devastation engine: co-located with the scroll/
    // staff router here (direct jsr). The mage path reaches it via resident
    // tramp_eff_destroy_area (one disk load for a rare spell; OVL.SPELL
    // restore is an aux-cached RAM copy).
    #import "../../core/player_destroy_area.s"
    // Map Area and Earthquake engines: spell-execution engines relocated from
    // the resident image; reached via tramp_eff_map_area / tramp_eff_earthquake
    // (same OVL_DEATH swap + OVL.SPELL restore as Word of Destruction).
    #import "../../core/player_magic_map.s"
    #import "../../core/player_magic_earthquake.s"
    // Cold spell effects and gain-stat potions relocated from Default /
    // A2PlaySlot into OVL.DEATH behind tramp_death_call_restore_spell.
    #import "../../core/eff_gain_stat.s"

eff_fd_row: .byte 0

eff_find_doors_impl:
    lda #1
    sta eff_fd_row
!efd_row_loop:
    lda eff_fd_row
    cmp #MAP_ROWS - 1
    bcs !efd_done+
    ldx eff_fd_row
    jsr map_row_ptr0_x
    ldy #1
!efd_col_loop:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !efd_col_next+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!efd_col_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efd_col_loop-
    inc eff_fd_row
    jmp !efd_row_loop-
!efd_done:
    lda #1
    sta vis_room_revealed
    rts

eff_destroy_traps_doors_impl:
    lda #0
    sta adj_dir_idx
!edtd_tile_loop:
    lda adj_dir_idx
    cmp #8
    bcs !edtd_tiles_done+
    tax
    jsr df_target_from_dir
    jsr !edtd_tile_cb+
    inc adj_dir_idx
    jmp !edtd_tile_loop-
!edtd_tiles_done:
    jsr !edtd_remove_adjacent_traps+
    lda #1
    sta vis_room_revealed
    rts

!edtd_tile_cb:
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    sta zp_temp0
    cmp #TILE_TRAP
    bne !edtd_check_door+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    :MapWrite_ptr0_y()
    rts

!edtd_check_door:
    lda zp_temp0
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_tile_done+

!edtd_open_door:
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    lda df_target_x
    ldy df_target_y
    jsr door_state_clear_at
!edtd_tile_done:
    rts

!edtd_remove_adjacent_traps:
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+
    lda trap_x,x
    sec
    sbc zp_player_x
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_y,x
    sec
    sbc zp_player_y
    clc
    adc #1
    cmp #3
    bcs !edtd_scan_next+
    lda trap_x,x
    cmp zp_player_x
    bne !edtd_remove+
    lda trap_y,x
    cmp zp_player_y
    beq !edtd_scan_next+

!edtd_remove:
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    jmp !edtd_scan-

!edtd_scan_next:
    inx
    jmp !edtd_scan-

!edtd_scan_done:
    rts
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $a400) + " bytes"
.assert "High-score I/O counter is owned by death overlay", hiscore_io_count_lo >= $a400 && hiscore_io_count_hi < ovl_death_end, true
.assert "High-score I/O does not alias storage counter", hiscore_io_count_lo != save_count_lo && hiscore_io_count_hi != save_count_hi, true
.assert "Death overlay fits", ovl_death_end <= $ba00, true

.segment ModalMiscOverlay
#import "../../core/ui_recall.s"
#import "../../core/ui_wizard.s"

// Wizard prompt helpers ride the modal overlay (their remaining callers are
// here; the resident image funds chest gameplay).
wizard_prompt_clear_digits:
    lda #0
    sta wizard_num_digits
    lda #5
    sta zp_cursor_row
    lda wizard_prompt_input_col
    sta zp_cursor_col
    lda #$20
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
    lda #5
    sta zp_cursor_row
    lda wizard_prompt_input_col
    sta zp_cursor_col
    rts

wizard_prompt_bad_value:
    lda #<wizard_bad_value_str
    sta zp_ptr0
    lda #>wizard_bad_value_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp wizard_prompt_clear_digits

wizard_bad_value_str:
    .text "BAD" ; .byte 0
ovl_modal_misc_end:
.print "Modal misc overlay: " + (ovl_modal_misc_end - $a400) + " bytes"
.assert "Modal misc overlay fits", ovl_modal_misc_end <= $ba00, true

.segment HelpOverlay
#import "../../core/ui_help_title.s"
#import "../../commodore/c128/ui_help_data_80.s"
#import "../../core/ui_help.s"
#import "../../core/ui_identify.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $a400) + " bytes"
.assert "Help overlay fits", ovl_help_end <= $ba00, true

.segment UiOverlay
#import "../../core/ui_character.s"
#import "../../core/ui_inventory.s"
#import "../../core/ui_equipment.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $a400) + " bytes"
.assert "UI overlay fits", ovl_ui_end <= $ba00, true

.segment ItemActionsOverlay
#define SCROLL_P3_ROUTER_ENABLED
    #import "../../core/item_actions_overlay.s"
    #import "../../core/item_exchange.s"
inv_add_carried_items:              // the floor pickup's, through tramp_inv_add_carried
    :InvAddCarriedBody()
.segment A2PlaySlot
// tramp_inv_add_carried — the resident floor pickup's way to inv_add_carried
// (OVL.ITEMS); the play slot holds it, the resident image being full. An
// overlay that will not load refuses the item, which stays on the floor.
tramp_inv_add_carried:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !tiac_fail+
    jmp inv_add_carried_items
!tiac_fail:
    ldx #HSTR_UIS_PACK_FULL
    clc
    rts
.segment ItemActionsOverlay

player_adjust_equipment_stat_prepare:
    lda inv_p1,x
    bcs !paes_prepare_store+
    eor #$ff
    adc #1                      // carry clear: -p1
!paes_prepare_store:
    sta stat_work
    rts

player_adjust_equipment_stat_apply:
    lda player_data + PL_STR_CUR,y
    clc
    adc stat_work
    sta player_data + PL_STR_CUR,y
    rts

#import "../../core/player_item_commands.s"
#import "../../core/ego_items.s"
#import "../../core/ranged_fire.s"
#import "../../core/throw.s"
#import "../../core/bash.s"
#import "../../core/tunnel.s"
ovl_items_end:
.print "Item actions overlay: " + (ovl_items_end - $a400) + " bytes"
.assert "Item actions overlay fits", ovl_items_end <= $ba00, true

.segment SpellOverlay
#define SPELL_CLASS_DATA_EXTERNAL
#define SPELL_HELPER_TABLES_EXTERNAL
#import "../../core/spell_data.s"
#undef SPELL_HELPER_TABLES_EXTERNAL
#undef SPELL_CLASS_DATA_EXTERNAL
#define PMX_EARTHQUAKE_EXTERNAL
#define PMX_MAP_AREA_EXTERNAL
#define PMX_MAP_AREA_TRAMPOLINE
#define PMX_DETECT_EFFECTS_EXTERNAL
#define PMX_DESTROY_AREA_EXTERNAL
#define BALL_HARM_EXTERNAL
#import "../../core/player_magic_slow_runtime.s"
#define PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_turn_banked.s"
#undef PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_execute_overlay.s"
#import "../../core/wand_bolt_entries.s"   // the Fire Bolts and Drain Life entries (OVL.SPELL)
#undef PMX_DETECT_EFFECTS_EXTERNAL
#undef PMX_MAP_AREA_TRAMPOLINE
#undef PMX_MAP_AREA_EXTERNAL
#undef BALL_HARM_EXTERNAL



// Phase 3 potion handlers live in the spell overlay on Apple IIe (the items
// overlay is full). The quaff dispatch swaps here via OVL.SPELL.
    #define SCROLL_P3_EXISTING_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER

iq_dispatch_p3_spell:
    cmp #ITEM_TYPE_POT_GAIN_STR
    bcc !iqp3_not_gain+
    jmp tramp_eff_potion_gain_stat  // potions of gain stat (140-145, OVL.DEATH)
!iqp3_not_gain:
    cmp #ITEM_TYPE_POT_HEALING
    beq iqp3_healing
    cmp #ITEM_TYPE_POT_RESTORATION
    beq iqp3_restoration
    cmp #ITEM_TYPE_POT_RESIST_HEAT
    beq iqp3_resist_heat
    cmp #ITEM_TYPE_POT_RESIST_COLD
    beq iqp3_resist_cold
    cmp #ITEM_TYPE_POT_CURE_CRITICAL
    beq iqp3_cure_critical
    cmp #ITEM_TYPE_POT_NEUTRALIZE
    beq iqp3_neutralize
    // Fall through: caller constrains A to {96-100, 126} (140-145 above)

iqp3_healing:
    jmp eff_potion_healing          // 1000 HP + cures (eff_potion_cure.s)

iqp3_cure_critical:
    // 6d7 HP, cures blindness, confusion and poison
    lda #EFF_CURE_ALL
    ldx #7
    ldy #6
    jmp eff_potion_heal_cure

iqp3_restoration:
    jsr player_calc_stats
    ldx #HSTR_PIQ_RESTORED
    jmp huff_print_msg

iqp3_resist_heat:
    // No message (upstream prints nothing for resist potions)
    lda #10
    jsr rng_range
    sec                             // + 1: VMS randint(10) + 10, 11-20
    adc #10
    clc
    adc zp_eff_resist
    bcc !iqp3_rh_store+
    lda #255
!iqp3_rh_store:
    sta zp_eff_resist
    rts

iqp3_resist_cold:
    lda #10
    jsr rng_range
    sec                             // + 1: VMS randint(10) + 10, 11-20
    adc #10
    clc
    adc eff_resist_cold_timer
    bcc !iqp3_rc_store+
    lda #255
!iqp3_rc_store:
    sta eff_resist_cold_timer
    rts

iqp3_neutralize:
    jsr eff_cure_poison
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg
#undef PMX_DESTROY_AREA_EXTERNAL
#undef PMX_EARTHQUAKE_EXTERNAL
#import "../../core/player_magic_levelup.s"
#import "../../core/player_magic_display.s"
#import "../../core/player_magic_tail.s"
#import "../../core/player_magic_select_overlay.s"
#import "../../core/player_gain_spell_impl.s"
#import "../../core/player_magic_learn_op.s"
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $a400) + " bytes"
.assert "Spell overlay fits", ovl_spell_end <= $ba00, true

// Boot copies cached payloads in PAK order. These guards couple current
// linked sizes to the shared boot/runtime aux-cache manifest.
.assert "A2 cache UI slot fits payload", ovl_ui_end - BANKED_DATA_BASE <= A2_AUX_CACHE_SPELL - A2_AUX_CACHE_UI, true
.assert "A2 cache SPELL slot fits payload", ovl_spell_end - BANKED_DATA_BASE <= A2_AUX_CACHE_MODAL - A2_AUX_CACHE_SPELL, true
.assert "A2 cache MODAL slot fits payload", ovl_modal_misc_end - BANKED_DATA_BASE <= A2_AUX_CACHE_HUFF - A2_AUX_CACHE_MODAL, true

.segment DungeonGenOverlay
#import "../../core/special_rooms.s"
#import "../../core/dungeon_tunnel_guard.s"
#import "../../core/dungeon_gen.s"
ovl_gen_end:
.print "Dungeon gen overlay: " + (ovl_gen_end - $a400) + " bytes"
.assert "Dungeon gen overlay fits", ovl_gen_end <= $ba00, true
.assert "Huffman segment is linked at its cache slot", A2_HUFFDATA_BASE, A2_AUX_CACHE_HUFF
.assert "Huffman corpus and catalog names fit their cache slot", ovl_huffdata_end <= A2_AUX_CACHE_ITEMS, true
.assert "A2 cache ITEMS slot fits payload", ovl_items_end - BANKED_DATA_BASE <= A2_AUX_CACHE_END - A2_AUX_CACHE_ITEMS, true
.assert "A2 cache full-window read stays in aux RAM", A2_AUX_CACHE_ITEMS + $1600 <= A2_AUX_CACHE_LIMIT, true

.segment StorageOverlay
// title_load_game_ovl — Load-game pre-load setup in StorageOverlay (returns C=0
// when load_game succeeds, C=1 on cancel or failure).
title_load_game_ovl:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !tlg_fail+
#endif
    jsr disk_prompt_save        // Swap to save disk in one-drive mode
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    bcc !tlg_fail+
    clc
    rts
!tlg_fail:
    sec
    rts

// disk_prompt_save_impl / disk_prompt_game_impl — swap-mode media prompts.
// Resident names trampoline here; see the resident block for the contract.
disk_prompt_save_impl:
    lda disk_mode
    cmp #A2_DISK_MODE_SWAP
    beq !dps_check+
    clc
    rts
!dps_check:
    jsr hal_storage_marker_present
    bcs !dps_prompt+
    clc
    rts
!dps_prompt:
    jsr ui_clear_full_screen_safe
    jsr msg_init
    lda #COL_WHITE
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #32                         // (80-16)/2 for ds_save_str
    sta zp_cursor_col
    lda #<ds_save_str
    sta zp_ptr0
    lda #>ds_save_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #11
    sta zp_cursor_row
    lda #33                         // (80-13)/2 for press_key_str
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    jsr input_get_modal_dismiss_key
    jmp !dps_check-

disk_prompt_game_impl:
    lda disk_mode
    cmp #A2_DISK_MODE_SWAP
    bne !dpg_ok+
    jsr hal_storage_probe_media
    bcs !dpg_off+
!dpg_ok:
    clc
    rts
!dpg_off:
    sec
    rts

#import "../../shared/save.s"
#import "save_slot_menu.s"
#import "disk_setup_a2.s"
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $a400) + " bytes"
.assert "Storage overlay fits", ovl_storage_end <= $ba00, true

.segment TitleOverlay
title_enter_menu_ovl:
    lda #$ff
    sta save_slot_index
    lda #COL_LGREY
    sta zp_text_color
    jsr title_clear_full_screen
    jsr title_load_and_draw
    jsr title_clear_below_menu
    jsr msg_init
    jmp title_show_sysinfo_banked

title_str:
    .text "MORIA 8 (APPLE II)"
    .byte 0

#import "title_screen.s"
#import "../../core/title_sysinfo_banked.s"
ovl_title_end:
.print "Title overlay: " + (ovl_title_end - $a400) + " bytes"
.assert "Title overlay fits", ovl_title_end <= $ba00, true

// Chest overlay — chest open/disarm/bash handlers plus store init/restock
// (transition-only code, safe in a non-town overlay; the ITEMS window is
// full). Cold MLI load, like DEATH/HELP/STORAGE (docs/CHEST_DESIGN.md).
.segment ChestOverlay
#import "../../core/chest.s"
#import "../../core/store_restock_overlay.s"
#import "../../core/eff_item_extended.s"
#import "../../core/disarm.s"
#import "../../core/disarm_helpers.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $a400) + " bytes"
.assert "Chest overlay fits", ovl_chest_end <= $ba00, true

// ============================================================
// Ego-item trampolines (ego_items.s lives in OVL.ITEMS on this
// platform; roll_tool_ego_check continues into game_loop.s in play,
// which is also resident whenever the overlay is needed)
// ============================================================
.segment Default
// Shared OVL.ITEMS dispatch for the compact trampolines: A/Y = target.
tramp_items_dispatch:
    sta tramp_items_jmp+1
    sty tramp_items_jmp+2
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
tramp_items_jmp:
    jmp $0000               // SMC dispatch target (never JMP (addr); the
                            // 6502 page-crossing bug reads the high byte
                            // from $xx00 when the pointer is at $xxFF)
!done:
    rts

// tramp_spell_call_items — Call an OVL.SPELL routine from a caller in another
// overlay, restoring OVL.ITEMS afterward. Phase 3 potion/scroll handlers live
// in OVL.SPELL; loading it from inside the items or death overlay would evict
// the caller's continuation, so the swap runs from this resident trampoline.
// Input: tsci_target staged to the handler; a2_tsci_arg = handler arg.
// Clobbers: A, X, Y
tramp_spell_call_items:
    lda #OVL_SPELL
    jsr overlay_load
    lda a2_tsci_arg
tsci_target:
    jsr $0000               // SMC dispatch target (staged by caller)
    lda #OVL_ITEMS
    jmp overlay_load
hal_tsci_arg:
a2_tsci_arg: .byte 0

// irs_p3_swap_exec — Resident Phase 3 scroll/wand/staff router entry. The
// items-overlay router jumps here because loading OVL.DEATH from the items
// overlay would evict the router's own code mid-flight. A = item type ID on
// entry; the dispatch reads it from A, so preserve it across the load.
irs_p3_swap_exec:
    pha                         // save item type ID
    lda #OVL_DEATH
    jsr overlay_load
    pla                         // restore item type ID
    jsr irs_dispatch_p3_overlay
    lda #OVL_ITEMS
    jsr overlay_load
    sec
    rts

// Modal restore replaces the overlay window with the live tier. Reload
// OVL.SPELL before returning to the spell-selection continuation.
tramp_ui_view_restore_spell_overlay:
    jsr ui_view_restore_modal_overlay
    lda #OVL_SPELL
    bne !restore_overlay+

// The takeoff equipment selector's continuation is inside OVL.ITEMS.
tramp_ui_view_restore_items_overlay:
    jsr ui_view_restore_modal_overlay
    jmp !restore_items+

// combat_check_levelup may load OVL.SPELL for mana/spell learning. Bash's
// continuation is inside OVL.ITEMS, so restore that owner before returning.
tramp_combat_check_levelup_items:
    jsr combat_check_levelup
!restore_items:
    lda #OVL_ITEMS
!restore_overlay:
    jsr overlay_load
    bcc !restored+
    brk                         // saved continuation is inside the window
!restored:
    rts

// Wizard gain-level runs with OVL.MODAL owning the window. apply_levelup no
// longer loads OVL.SPELL itself (main_loop runs the mana/spell recalc, TRN-008);
// the reload stays as a guard so the continuation always finds OVL.MODAL.
tramp_combat_apply_levelup_modal:
    jsr combat_apply_levelup
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcc !restored+
    brk                         // saved continuation is inside OVL.MODAL
!restored:
    rts

.assert "Window-return trampolines stay resident", tramp_ui_view_restore_spell_overlay >= $0a00 && * <= $7c00, true

// tramp_ego_append_suffix — Append ego suffix to combat_msg_buf.
// Decodes ego 1..55 dynamically via ITEM.CAT without evicting caller's overlay.
// Input: A = ego byte (low 6 bits = ego ID). Clobbers: A, X, Y, zp_ptr0, zp_ptr1.
.segment A2PlaySlot
tramp_ego_append_suffix:
    and #EGO_ID_MASK
    beq !teas_done+
    cmp #EGO_TYPE_COUNT
    bcs !teas_done+
    jsr item_cat_decode_ego     // zp_ptr0/hi = item_name_decode_buf
    lda zp_ptr0
    ldy zp_ptr0_hi
    jmp combat_append_str
!teas_done:
    rts

a2_play_end:
.print "Play payload: " + (a2_play_end - $7c00) + " bytes ($" + toHexString(a2_play_end) + ")"
.assert "Play payload fits slot", a2_play_end <= $a000, true
.assert "Ego suffix trampoline stays in play", tramp_ego_append_suffix >= $7c00 && tramp_ego_append_suffix < a2_play_end, true
.assert "Potions of gain stat run in death overlay", eff_potion_gain_stat >= $a400 && eff_potion_gain_stat < ovl_death_end, true

// ============================================================
// Final boundary assertions
// ============================================================
.segment Default
program_end:
.print "Resident Default: " + (program_end - $0a00) + " bytes ($" + toHexString(program_end) + ")"
.assert "Resident image fits always-region", program_end <= $7c00, true
.assert "Ego call trampolines stay resident", tramp_roll_ego_type < $7c00 && tramp_ego_get_ac_bonus < $7c00, true
.assert "Death overlay owns royal_screen", royal_screen >= $a400 && royal_screen < ovl_death_end, true
.assert "Phase 4 evicted trampolines stay resident while targets live in overlays", re_equip_entry < $7c00 && re_equip >= $a400 && re_equip < ovl_modal_misc_end && hal_player_recalc_pflags < $7c00 && player_recalc_pflags_equipment >= $a400 && player_recalc_pflags_equipment < ovl_modal_misc_end && run_initialize < $7c00 && run_initialize_impl >= $a400 && run_initialize_impl < ovl_modal_misc_end && item_spawn_level < $7c00 && item_spawn_level_gen >= $a400 && item_spawn_level_gen < ovl_gen_end && tramp_item_pickup < $7c00 && item_pickup >= $a400 && item_pickup < ovl_items_end && title_load_game_ovl >= $a400 && title_load_game_ovl < ovl_storage_end && title_enter_menu_ovl >= $a400 && title_enter_menu_ovl < ovl_title_end, true

// Cold legal modal: workspace is reserved but not emitted to disk.
.segment LegalOverlay
#import "../../core/ui_legal.s"
#import "../shared/legal_disk_stream.s"
legal_code_end:
.assert "Legal code stays below its modal workspace", legal_code_end <= legal_zp_save, true
.assert "Legal ZP snapshot stays below input cache", legal_zp_save + $8e <= legal_input_cache, true
.segment Default
