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
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",    start=$a400, min=$a400, max=$b9ff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",      start=$a400, min=$a400, max=$b9ff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items",  start=$a400, min=$a400, max=$b9ff]
.segmentdef SpellOverlay      [outPrg=OVL_OUT + "/ovl.spell",   start=$a400, min=$a400, max=$b9ff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",     start=$a400, min=$a400, max=$b9ff]
.segmentdef StorageOverlay    [outPrg=OVL_OUT + "/ovl.storage", start=$a400, min=$a400, max=$b9ff]
.segmentdef TitleOverlay      [outPrg=OVL_OUT + "/ovl.title",   start=$a400, min=$a400, max=$b9ff]
.segmentdef A2PlaySlot        [outPrg=OVL_OUT + "/a2.play",     start=$7c00, min=$7c00, max=$9fff]
.segmentdef A2AuxData         [outPrg=OVL_OUT + "/a2.auxdata",  start=$3b0c, min=$3b0c, max=$56ff]

// Huffman data placement: aux RAM at $3B0C (boot-preloaded).
.macro HuffmanDataSegment() {
    .segment A2AuxData
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
#import "bank_port_consts.s"
#import "hal/lifecycle_policy.s"
#import "overlay.s"
// Apple II-only overlay classes (slot-free; both window-hosted).
.const OVL_STORAGE = 10
.const OVL_TITLE   = 11
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
#import "../../core/player.s"
#import "../../core/ui_messages.s"
#import "../../core/ui_status.s"
#import "../../core/runtime_ui_strings.s"
#import "../../core/generation_busy.s"
#define A2_SMALL_PLAY_EXTERNAL
#import "../../core/stat_display.s"
#import "../../core/huffman.s"
.segment Default
#import "../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../core/dungeon_features.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../core/monster.s"
#import "../../core/tier_manager.s"
#import "../../core/monster_ai.s"
#import "../../core/scene_dirty.s"
// scene_mat_tile lives in dungeon_render_a2.s (falls into render_single_tile).
#import "../../core/scene_force.s"
#import "../../core/monster_magic.s"
#import "../../core/item.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#define PLAYER_ITEM_COMMANDS_EXTERNAL
#define PLAYER_ITEM_SELECT_EXTERNAL
#import "../../core/player_items.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY

// Constants are needed by resident consumers before the data/code placement
// later in A2PlaySlot and A2AuxData. These imports emit no bytes.
#import "../../core/store_data_defs.s"
#import "../../core/recall_defs.s"
#import "../../core/spell_data_defs.s"

#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
#import "../../core/player_magic.s"
#import "dungeon_render_a2.s"
// C64 $F000-banked content is ordinary resident bytes on this platform.
#import "../../core/item_desc_banked.s"
#import "../../core/player_magic_map.s"
#import "../../core/player_magic_earthquake.s"
#import "../../core/projectile.s"
#import "compat/io_kernal_consts.s"
#import "../../core/storage_status.s"
#import "memory_aux.s"
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

restart_entry:
    jsr detect_machine              // fixed Apple IIe / 80-col identity
    jsr reu_detect                  // stub: zeroes REU state
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #$ff
    sta save_slot_index
    lda #COL_LGREY
    sta zp_text_color

    lda #OVL_TITLE
    jsr overlay_load
    jsr title_clear_full_screen
    jsr title_load_and_draw
    jsr title_clear_below_menu

    jsr msg_init
    jsr title_show_sysinfo
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
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    jmp title_enter_menu

title_draw_menu:
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #28                 // Center 80-col: (80-24)/2 = 28
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

title_str:
    .text "MORIA 8 (APPLE II)"
    .byte 0

a2_reset_session_state:
    lda #0
    sta disk_setup_done
    sta disk_mode
    sta save_device
    sta program_device
    sta a2_save_volume            // length 0 = no save volume selected
    sta a2_program_volume         // rediscovered lazily by Disk Setup
    rts

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
#endif
    jsr disk_prompt_save        // Swap to save disk in one-drive mode
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    bcc !title_load_fail+
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

// title_show_sysinfo — title-sysinfo display lives in the TITLE overlay.
title_show_sysinfo:
    lda #OVL_TITLE
    jsr overlay_load
    bcs !done+
    jsr title_show_sysinfo_banked
!done:
    rts

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
tramp_level_generate:
    jmp level_generate

tramp_assign_special_room:
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
    jsr assign_special_room
!done:
    rts

tramp_vault_seal_entrance:
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
    jsr vault_seal_entrance
!done:
    rts

tramp_spawn_special_room_monsters:
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
    jsr spawn_special_room_monsters
!done:
    rts

tramp_spawn_nest_gold:
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
    jsr spawn_nest_gold
!done:
    rts

tramp_find_special_room:
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
    jsr find_special_room
!done:
    rts

tramp_sr_epilogue:
    php
    jsr a2_platform_runtime_resync
    plp
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
    jsr save_select_slot_prompt_impl
    rts
#endif

// ============================================================
// UI / item / store / spell trampolines. The window is plain main
// RAM, so these are direct calls after overlay_load — no banking,
// no epilogue.
// ============================================================
overlay_load_no_kernal:
    jmp overlay_load

run_initialize:
    jmp run_initialize_impl

tramp_ui_help_display:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
!done:
    rts

tramp_ui_char_display:
    lda #OVL_UI
    jsr overlay_load
    bcs !done+
    jsr ui_char_display
!done:
    rts

tramp_ui_inv_display:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    jsr ui_inv_display
!done:
    rts

tramp_ui_inv_select_display:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    jsr ui_inv_select_display
!done:
    rts

tramp_ui_equip_display:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    jsr ui_equip_display
!done:
    rts

tramp_ui_equip_select_display:
    lda #OVL_HELP
    jsr overlay_load
    bcs !done+
    jsr ui_equip_select_display
!done:
    rts

tramp_ui_recall:
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr ui_recall_display
!done:
    rts

tramp_item_gain_spell:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr item_gain_spell
!done:
    rts

tramp_item_read_scroll:
    lda #<item_read_scroll
    ldy #>item_read_scroll
    jmp tramp_items_dispatch

tramp_item_aim_wand:
    lda #<item_aim_wand
    ldy #>item_aim_wand
    jmp tramp_items_dispatch

tramp_item_use_staff:
    lda #<item_use_staff
    ldy #>item_use_staff
    jmp tramp_items_dispatch

tramp_eff_earthquake:
    jmp eff_earthquake

tramp_item_refuel:
    lda #<item_refuel
    ldy #>item_refuel
    jmp tramp_items_dispatch

tramp_ranged_fire:
    lda #<ranged_fire
    ldy #>ranged_fire
    jmp tramp_items_dispatch

tramp_throw_item:
    lda #<throw_item
    ldy #>throw_item
    jmp tramp_items_dispatch

tramp_bash_command:
    lda #<bash_command
    ldy #>bash_command
    jmp tramp_items_dispatch

tramp_disarm_command:
    lda #<disarm_command
    ldy #>disarm_command
    jmp tramp_items_dispatch

tramp_player_tunnel:
    lda #<player_tunnel
    ldy #>player_tunnel
    jmp tramp_items_dispatch

tramp_spell_list_display:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr spell_list_display
!done:
    rts

tramp_spell_execute_selected:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr spell_execute_selected
!done:
    rts

tramp_reveal_floorplan:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr eff_reveal_floorplan
!done:
    rts

// Level-up and failure-calculation magic helpers live in OVL.SPELL on this
// platform (fit lever L7); the policy flag routes combat.s/level-up here.
tramp_magic_recalc_mana:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr magic_recalc_mana
!done:
    rts

tramp_magic_check_new_spells:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr magic_check_new_spells
!done:
    rts

tramp_calc_spell_failure:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr calc_spell_failure
!done:
    rts

// Cast/pray cores live in OVL.SPELL (fit lever); shared pm_* helpers stay
// resident for both the cast flow and the UI gain-spell flow.
tramp_player_cast_spell:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr player_cast_spell
!done:
    rts

tramp_player_pray:
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
    jsr player_pray
!done:
    rts

// Wear/takeoff/eat/quaff bodies live in OVL.ITEMS (fit lever R1); the
// trampolined-command policy flag routes game_loop's command dispatch here.
tramp_item_wear:
    lda #<item_wear
    ldy #>item_wear
    jmp tramp_items_dispatch

tramp_item_takeoff:
    lda #<item_takeoff
    ldy #>item_takeoff
    jmp tramp_items_dispatch

tramp_item_eat:
    lda #<item_eat
    ldy #>item_eat
    jmp tramp_items_dispatch

tramp_item_quaff:
    lda #<item_quaff
    ldy #>item_quaff
    jmp tramp_items_dispatch

tramp_item_recalc:
    lda #<player_recalc_equipment
    ldy #>player_recalc_equipment
    jmp tramp_items_dispatch

tramp_select_filtered_inv:
    pha                         // Preserve filter (A) and prompt id (X):
    txa                         // overlay_load clobbers both, and
    pha                         // piw_select_filtered_inv takes them as input.
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    lda #OVL_ITEMS
    sta piw_return_overlay
    pla
    tax
    pla
    jsr piw_select_filtered_inv
    jmp tramp_restore_spell_overlay
!load_failed:
    pla
    pla
    clc
    rts

// Shared epilogue for the two item-selector trampolines: restore OVL.SPELL
// and return A/flags from the selector. The brk is fatal because the saved
// continuation is inside OVL.SPELL.
tramp_restore_spell_overlay:
    php
    pha
    lda #OVL_NONE
    sta piw_return_overlay
    lda #OVL_SPELL
    jsr overlay_load
    bcc !restored+
    brk                         // saved continuation is inside OVL.SPELL
!restored:
    pla
    plp
    rts

// Spell-overlay recharge selection enters the item selector with an already
// captured key. Restore ITEMS after nested '?' UI, then SPELL before returning.
tramp_select_filtered_inv_key_spell:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    lda #OVL_ITEMS
    sta piw_return_overlay
    pla
    jsr piw_select_filtered_inv_key
    jmp tramp_restore_spell_overlay
!load_failed:
    pla
    clc
    rts

tramp_ui_identify:
    lda #OVL_UI
    jsr overlay_load
    bcs !done+
    jsr ui_identify_print
    jsr tier_restore_after_overlay
!done:
    rts

tramp_ui_wizard_display:
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr ui_wizard_display
!done:
    rts

tramp_item_init_identification:
    lda #OVL_STARTUP
    jsr overlay_load
    bcs !done+
    jsr item_init_identification
!done:
    rts

tramp_disk_setup:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr a2_disk_setup_run
!done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr a2_disk_prepare_selected
!done:
    rts

tramp_store_init_all:
    lda #<store_init_all
    ldy #>store_init_all
    jmp tramp_items_dispatch

tramp_store_restock_all:
    lda #<store_restock_all
    ldy #>store_restock_all
    jmp tramp_items_dispatch

tramp_store_enter:
    lda #OVL_TOWN
    jsr overlay_load
    bcs !done+
    jsr store_enter
!done:
    rts

tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    bcs !done+
    jsr player_create
!done:
    rts

// ============================================================
// Media prompts (Commodore parity). Resident like the Commodore originals:
// callers run with arbitrary overlays live (death flow keeps OVL.DEATH),
// so no overlay loads may happen here. Only one-drive swap mode prompts:
// two-drive mode assumes the save disk stays mounted (failures route through
// tramp_disk_prepare_selected), and game-disk mode needs no media handling.
// Probes reuse the resident media probes: the marker probe answers "is the
// save volume mounted" and the program probe answers "is the game volume
// mounted" without an ON_LINE scan.
// ============================================================
disk_prompt_save:
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

disk_prompt_game:
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

// winner_apply_retirement_bonus — core calls the plain name on this
// platform (game_loop.s:2460 !C64_PRODUCT path); the ModalMisc inline is a
// bare rts so the bonus is applied exactly once.
winner_apply_retirement_bonus:
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

// ============================================================
// Death orchestration
// ============================================================
tramp_game_over_disk_setup:
    jsr tramp_disk_setup
    bcs !done+
    lda #1
    sta disk_setup_done
    jsr tramp_game_over_prepare
    clc
!done:
    rts

tramp_game_over_disk_setup_failed:
    clc
    rts

tramp_game_over_prepare:
    lda death_source_saved
    sta zp_death_source

    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !tgo_load_overlay+
    lda zp_death_source
    cmp #DEATH_ALIVE
    beq !tgo_load_overlay+
    cmp #DEATH_TRAP_PIT
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name

!tgo_load_overlay:
    lda #OVL_DEATH
    jsr overlay_load
    rts

tramp_game_over:
    jsr tramp_game_over_prepare
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
    jsr score_death_screen
    rts

tramp_winner_royal:
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr winner_apply_retirement_bonus_overlay
    jsr royal_screen
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
#define STORE_INVENTORY_DATA_EXTERNAL
#define STORE_RUNTIME_DATA_EXTERNAL
#import "../../core/store_data.s"
#undef STORE_RUNTIME_DATA_EXTERNAL
#undef STORE_INVENTORY_DATA_EXTERNAL
#import "../../core/store_hot_data.s"
#define RECALL_ARRAY_DATA_EXTERNAL
#import "../../core/recall.s"
#undef RECALL_ARRAY_DATA_EXTERNAL
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
#define PLAYER_LOOK_EXTERNAL
#import "../../core/player_move.s"
#undef PLAYER_LOOK_EXTERNAL
.macro PlayerRunInitializeSegment() {
    .segment A2PlaySlot
}
.macro PlayerRunRestoreResidentSegment() {
    .segment A2PlaySlot
}
#define PLAYER_RUN_INITIALIZE_EXTERNAL
#import "../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL
#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../../core/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../../core/wizard.s"
#define PLAYER_LOOK_EXTERNAL
#define DISARM_COMMAND_EXTERNAL
#define WELCOME_STR_EXTERNAL
#define GAME_LOOP_NAV_STRINGS_EXTERNAL
#define GAME_LOOP_NO_STAIRS_STR_EXTERNAL
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#undef PLAYER_LOOK_EXTERNAL
#import "dungeon_scroll_a2.s"
#import "../../core/turn.s"
#import "../../core/dungeon_tunnel_guard.s"
// Small play-resident modules (play is present in every gameplay phase).
#import "../../core/player_heal_feedback.s"
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
#import "../../core/recall_array_data.s"
#import "../../core/spell_class_data.s"
#define STORE_HOT_DATA_EXTERNAL
#import "../../core/store_runtime_data.s"
#undef STORE_HOT_DATA_EXTERNAL
#import "../../core/spell_helper_tables.s"
// Spell/prayer name pointer tables and strings. Consumed only by
// spell_list_display (OVL.SPELL), so they cannot stay in OVL.UI; aux keeps
// them readable through the map thunks regardless of the loaded overlay.
#import "../../core/spell_names.s"

// Presentation-time ego suffixes must remain readable while HELP or TOWN owns
// the code window. Fixed 16-byte slots make the aux pointer calculation fit in
// the two remaining A2.PLAY bytes without loading OVL.ITEMS.
.align $100
a2_ego_suffix_slots:
a2_ego_suffix_none: .byte 0
    .fill 16 - (* - a2_ego_suffix_none), 0
a2_ego_suffix_slay_animal: .text " (Slay Animal)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_slay_animal), 0
a2_ego_suffix_slay_evil: .text " (Slay Evil)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_slay_evil), 0
a2_ego_suffix_slay_undead: .text " (Slay Undead)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_slay_undead), 0
a2_ego_suffix_flame: .text " (Flame)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_flame), 0
a2_ego_suffix_frost: .text " (Frost)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_frost), 0
a2_ego_suffix_defender: .text " (Defender)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_defender), 0
a2_ego_suffix_holy_avenger: .text " (Holy Avenger)" ; .byte 0
    .fill 16 - (* - a2_ego_suffix_holy_avenger), 0
a2_ego_suffix_slots_end:
.assert "Apple ego suffix slots are page aligned", <a2_ego_suffix_slots, 0
.assert "Apple ego suffix slots are 8 x 16 bytes", a2_ego_suffix_slots_end - a2_ego_suffix_slots, EGO_TYPE_COUNT * 16

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

// Screen-code -> Apple display-code table for inputs $00-$7F (P6). Must
// reproduce a2_map_char (screen_a2.s) exactly for that range: $00->$C0,
// $01-$1A->$E1-$FA, $1B-$1F->$DB-$DF, $20-$5A->code|$80, $5B-$5F->$9B-$9F,
// $60-$7F->$A0. High-half inputs stay on the branch chain. Block-read into
// the tail of a2_ss_buf once per render_viewport (rv_char_map).
a2_char_map_aux:
    .fill $80, i == 0 ? $c0 : i < $1b ? (i + $60) | $80 : i < $20 ? (i + $40) | $80 : i < $5b ? i | $80 : i < $60 ? (i + $40) | $80 : $a0
.assert "Char map table covers $00-$7F", * - a2_char_map_aux, $80

// Speaker sound patterns for hal_sound_play (services.s): one 16-byte slot
// per SFX ID, as (period, toggles) pairs with period 0 = end. Period:
// smaller = higher pitch. Shapes mirror the C64 SID intent (core/sound.s).
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

// ============================================================
// Overlay segment blocks (C64 composition, adjusted)
// ============================================================
.segment TownOverlay
#import "../../core/store.s"
#import "../../core/ui_store.s"
#import "../../core/ui_home.s"
#import "../../core/ui_home_text.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $a400) + " bytes"
.assert "Town overlay fits window code region", ovl_town_end <= $ba00, true

.segment StartupOverlay
#import "../../core/background_data.s"
#import "../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $a400) + " bytes"
.assert "Startup overlay fits", ovl_start_end <= $ba00, true

.segment DeathOverlay
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
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $a400) + " bytes"
.assert "High-score I/O counter is owned by death overlay", hiscore_io_count_lo >= $a400 && hiscore_io_count_hi < ovl_death_end, true
.assert "High-score I/O does not alias storage counter", hiscore_io_count_lo != save_count_lo && hiscore_io_count_hi != save_count_hi, true
.assert "Death overlay fits", ovl_death_end <= $ba00, true

.segment ModalMiscOverlay
// winner_apply_retirement_bonus_overlay — the bonus was already applied by
// the plain-name call in core/game_loop.s before tramp_winner_royal; this
// overlay entry exists only so the C64-shaped royal flow links.
winner_apply_retirement_bonus_overlay:
    rts
#import "../../core/royal.s"
#import "../../core/ui_recall.s"
#import "../../core/ui_wizard.s"
ovl_modal_misc_end:
.print "Modal misc overlay: " + (ovl_modal_misc_end - $a400) + " bytes"
.assert "Modal misc overlay fits", ovl_modal_misc_end <= $ba00, true

.segment HelpOverlay
#import "../../commodore/c128/ui_help_data_80.s"
#import "../../core/ui_help.s"
#import "../../core/ui_inventory.s"
#import "../../core/ui_equipment.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $a400) + " bytes"
.assert "Help overlay fits", ovl_help_end <= $ba00, true

.segment UiOverlay
#import "../../core/ui_character.s"
#import "../../core/ui_identify.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $a400) + " bytes"
.assert "UI overlay fits", ovl_ui_end <= $ba00, true

.segment ItemActionsOverlay
#import "../../core/store_restock_overlay.s"
#import "../../core/item_actions_overlay.s"
#import "../../core/player_item_commands.s"
#import "../../core/ego_items.s"
#import "../../core/ranged_fire.s"
#import "../../core/throw.s"
#import "../../core/bash.s"
#import "../../core/disarm.s"
#import "../../core/disarm_helpers.s"
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
#define PMX_DETECT_EFFECTS_EXTERNAL
#import "../../core/player_magic_slow_runtime.s"
#define PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_turn_banked.s"
#undef PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_execute_overlay.s"
#undef PMX_DETECT_EFFECTS_EXTERNAL
#undef PMX_MAP_AREA_EXTERNAL
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
.assert "A2 cache TOWN slot fits payload", ovl_town_end - BANKED_DATA_BASE <= A2_AUX_CACHE_UI - A2_AUX_CACHE_TOWN, true
.assert "A2 cache UI slot fits payload", ovl_ui_end - BANKED_DATA_BASE <= A2_AUX_CACHE_SPELL - A2_AUX_CACHE_UI, true
.assert "A2 cache SPELL slot fits payload", ovl_spell_end - BANKED_DATA_BASE <= A2_AUX_CACHE_MODAL - A2_AUX_CACHE_SPELL, true
.assert "A2 cache MODAL slot fits payload", ovl_modal_misc_end - BANKED_DATA_BASE <= A2_AUX_CACHE_GEN - A2_AUX_CACHE_MODAL, true

.segment DungeonGenOverlay
#import "../../core/special_rooms.s"
#import "../../core/dungeon_gen.s"
ovl_gen_end:
.print "Dungeon gen overlay: " + (ovl_gen_end - $a400) + " bytes"
.assert "Dungeon gen overlay fits", ovl_gen_end <= $ba00, true
.assert "A2 cache GEN slot fits payload", ovl_gen_end - BANKED_DATA_BASE <= A2_AUX_CACHE_ITEMS - A2_AUX_CACHE_GEN, true
.assert "A2 cache ITEMS slot fits payload", ovl_items_end - BANKED_DATA_BASE <= A2_AUX_CACHE_END - A2_AUX_CACHE_ITEMS, true
.assert "A2 cache full-window read stays in aux RAM", A2_AUX_CACHE_ITEMS + $1600 <= A2_AUX_CACHE_LIMIT, true

.segment StorageOverlay
#import "../../shared/save.s"
#import "save_slot_menu.s"
#import "disk_setup_a2.s"
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $a400) + " bytes"
.assert "Storage overlay fits", ovl_storage_end <= $ba00, true

.segment TitleOverlay
#import "title_screen.s"
#import "../../core/title_sysinfo_banked.s"
ovl_title_end:
.print "Title overlay: " + (ovl_title_end - $a400) + " bytes"
.assert "Title overlay fits", ovl_title_end <= $ba00, true

// ============================================================
// Ego-item trampolines (ego_items.s lives in OVL.ITEMS on this
// platform; roll_tool_ego_check continues into game_loop.s in play,
// which is also resident whenever the overlay is needed)
// ============================================================
.segment Default
tramp_roll_ego_type:
    lda #<roll_ego_type
    ldy #>roll_ego_type
    jmp tramp_items_dispatch

// Wizard item generation calls the ego roll from OVL.MODAL; restore the
// caller overlay before returning or the continuation executes OVL.ITEMS
// contents at the same addresses.
// Shared OVL.ITEMS dispatch for the compact trampolines: A/Y = target.
tramp_items_dispatch:
    sta tramp_items_target
    sty tramp_items_target_hi
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jmp (tramp_items_target)
!done:
    rts
tramp_items_target:     .byte 0
tramp_items_target_hi:  .byte 0

tramp_roll_ego_type_modal:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr roll_ego_type
    pha
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcc !restored+
    brk                         // saved continuation is inside OVL.MODAL
!restored:
    pla
    rts
!load_failed:
    pla
    rts

tramp_ego_apply_damage:
    lda #<ego_apply_damage
    ldy #>ego_apply_damage
    jmp tramp_items_dispatch

tramp_ego_get_ac_bonus:
    lda #<ego_get_ac_bonus
    ldy #>ego_get_ac_bonus
    jmp tramp_items_dispatch

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

// Wizard gain-level runs with OVL.MODAL owning the window; apply_levelup
// loads OVL.SPELL for mana/spell learning, so restore the caller overlay
// before returning or the continuation executes OVL.SPELL contents.
tramp_combat_apply_levelup_modal:
    jsr combat_apply_levelup
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcc !restored+
    brk                         // saved continuation is inside OVL.MODAL
!restored:
    rts

.assert "Window-return trampolines stay resident", tramp_ui_view_restore_spell_overlay >= $0a00 && * <= $7c00, true

// tramp_ego_append_suffix — Append ego suffix to combat_msg_buf
// (C64 main.s:1108 semantics, overlay-backed).
// Input: A = ego type. Clobbers: A, X, Y, zp_ptr0.
.segment A2PlaySlot
tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    pla
    bcs !teas_done+
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string
    lda zp_ptr0
    ldy zp_ptr0_hi
    jmp combat_append_str
!teas_done:
    rts

a2_play_end:
.assert "Play payload fits slot", a2_play_end <= $a000, true
.assert "Ego suffix trampoline stays in play", tramp_ego_append_suffix >= $7c00 && tramp_ego_append_suffix < a2_play_end, true

// ============================================================
// Final boundary assertions
// ============================================================
.segment Default
program_end:
.assert "Resident image fits always-region", program_end <= $7c00, true
.assert "Ego call trampolines stay resident", tramp_roll_ego_type < $7c00 && tramp_ego_get_ac_bonus < $7c00, true
