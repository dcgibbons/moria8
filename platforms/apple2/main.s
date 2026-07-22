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
// Platform media state bytes (shared save.s bookkeeping surface;
// device numbers are meaningless on ProDOS but the labels are
// referenced by shared code)
// ============================================================
save_device:        .byte 0
program_device:     .byte 0
disk_mode:          .byte 0
disk_setup_done:    .byte 0
tsi_krev_cached:    .byte 0

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
    rts

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
#endif
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    bcc !title_load_fail+
    jsr a2_require_play
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
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_read_scroll
!done:
    rts

tramp_item_aim_wand:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_aim_wand
!done:
    rts

tramp_item_use_staff:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_use_staff
!done:
    rts

tramp_eff_earthquake:
    jmp eff_earthquake

tramp_item_refuel:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_refuel
!done:
    rts

tramp_ranged_fire:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr ranged_fire
!done:
    rts

tramp_throw_item:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr throw_item
!done:
    rts

tramp_bash_command:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr bash_command
!done:
    rts

tramp_disarm_command:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr disarm_command
!done:
    rts

tramp_player_tunnel:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr player_tunnel
!done:
    rts

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
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_wear
!done:
    rts

tramp_item_takeoff:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_takeoff
!done:
    rts

tramp_item_eat:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_eat
!done:
    rts

tramp_item_quaff:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr item_quaff
!done:
    rts

tramp_item_recalc:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr player_recalc_equipment
!done:
    rts

tramp_select_filtered_inv:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    lda #OVL_ITEMS
    sta piw_return_overlay
    jsr piw_select_filtered_inv
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
!done:
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
    php
    pha
    lda #OVL_NONE
    sta piw_return_overlay
    lda #OVL_SPELL
    jsr overlay_load
    bcc !key_restored+
    brk                         // saved continuation is inside OVL.SPELL
!key_restored:
    pla
    plp
    rts
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
    jsr a2_disk_setup_run
!done:
    rts

tramp_store_init_all:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr store_init_all
!done:
    rts

tramp_store_restock_all:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr store_restock_all
!done:
    rts

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
// Media prompts. The Apple II game volume is always present (plan:
// "the two-drive swap UX degrades to always-present probes"), so the
// Commodore swap prompts are genuine no-op successes.
// ============================================================
disk_prompt_game:
disk_prompt_save:
    clc
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
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#undef PLAYER_LOOK_EXTERNAL
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
#import "../../core/spell_names.s"
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
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr roll_ego_type
!done:
    rts

tramp_ego_apply_damage:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr ego_apply_damage
!done:
    rts

tramp_ego_get_ac_bonus:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
    jsr ego_get_ac_bonus
!done:
    rts

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
