// main.s — Commander X16 moria8 linker script + entry
//
// Assemble from platforms/cx16 with:
//   -libdir ../../core -libdir . -libdir hal -libdir ../commodore/common -libdir ../shared -define CX16
//
// Memory authority: docs/CX16_MEMORY_CONTRACT.md.
//   Default (unified Resident + Play): $0801-$9AFF (MORIA8.PRG)
//   Tier-name pool:                    $9B00-$9EFF (1,024 B)
//   Hardware I/O hole:                 $9F00-$9FFF (VIA1/2 + VERA)
//   Banked RAM window:                 $A000-$BFFF (8,192 B x 64 banks via $00)

.cpu _65c02
#define CX16_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define CX16_PRODUCT_IRQ_VECTOR_RUNTIME
#define PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME
.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")

// ============================================================
// Segment definitions (Banked $A000-$BFFF overlays + virtual data banks)
// ============================================================
.segmentdef StartupOverlay     [outPrg=OVL_OUT + "/OVL.START",     start=$a000, min=$a000, max=$bfff]
.segmentdef TownOverlay        [outPrg=OVL_OUT + "/OVL.TOWN",      start=$a000, min=$a000, max=$bfff]
.segmentdef DeathOverlay       [outPrg=OVL_OUT + "/OVL.DEATH",     start=$a000, min=$a000, max=$bfff]
.segmentdef ModalMiscOverlay   [outPrg=OVL_OUT + "/OVL.MODAL",     start=$a000, min=$a000, max=$bfff]
.segmentdef HelpOverlay        [outPrg=OVL_OUT + "/OVL.HELP",      start=$a000, min=$a000, max=$bfff]
.segmentdef UiOverlay          [outPrg=OVL_OUT + "/OVL.UI",        start=$a000, min=$a000, max=$bfff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/OVL.ITEMS",     start=$a000, min=$a000, max=$bfff]
.segmentdef SpellOverlay       [outPrg=OVL_OUT + "/OVL.SPELL",     start=$a000, min=$a000, max=$bfff]
.segmentdef DungeonGenOverlay  [outPrg=OVL_OUT + "/OVL.GEN",       start=$a000, min=$a000, max=$bfff]
.segmentdef StorageOverlay     [outPrg=OVL_OUT + "/OVL.STORAGE",   start=$a000, min=$a000, max=$bfff]
.segmentdef TitleOverlay       [outPrg=OVL_OUT + "/OVL.TITLE",     start=$a000, min=$a000, max=$bfff]
.segmentdef ChestOverlay       [outPrg=OVL_OUT + "/OVL.CHEST",     start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16AuxData        [outPrg=OVL_OUT + "/CX16.AUXDATA",  start=$6000, min=$6000, max=$7fff]
.segmentdef Cx16HuffData       [outPrg=OVL_OUT + "/CX16.HUFFDATA", start=$8000, min=$8000, max=$9fff]

.macro HuffmanDataSegment() {
    .segment Cx16HuffData
}
.macro AuxDataSegment() {
    .segment Cx16AuxData
}
.macro ItemNameStreamsSegment() {
    .segment Cx16AuxData
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
    .segment Default
}

#import "hal/storage_policy.s"
#import "save_slot_policy.s"
#import "palette_consts.s"

// SFX_* semantic sound IDs (kept in sync with core/sound.s).
.const SFX_NONE         = $ff
.const SFX_BUMP         = $00
.const SFX_HIT          = $01
.const SFX_MISS         = $02
.const SFX_PICKUP       = $03
.const SFX_DEATH        = $04
.const SFX_LEVELUP      = $05
.const SFX_SPELL        = $06
.const SFX_SPELL_FAIL   = $07
.const SFX_HUNGER_WARN  = $08
.const SFX_HUNGER_FAINT = $09

// ============================================================
// Default segment opens at $0801 with BASIC Upstart stub
// ============================================================
.pc = $0801 "BasicUpstart"
:BasicUpstart2(entry_bootstrap)

.pc = $080d "Resident"
entry_bootstrap:
    jmp entry_main

// ============================================================
// Platform media state bytes (shared save.s bookkeeping surface).
// ============================================================
save_device:        .byte 8
program_device:     .byte 8
disk_mode:          .byte 1
disk_setup_done:    .byte 1
tsi_krev_cached:      .byte 0
tsi_ram_banks_cached: .byte 0
// save_slot_index lives in unbanked resident low RAM so the selected slot
// survives overlay bank switches.
save_slot_index:    .byte $ff

// tramp_dig_ability — pinned jump for tunnel code (resident).
tramp_dig_ability:
    jmp calc_dig_ability

// ============================================================
// Resident import cascade
// ============================================================
#import "../../core/zeropage.s"
#import "hal/layout.s"
#import "memory.s"
#import "bank_port_consts.s"
#import "hal/lifecycle_policy.s"
#import "overlay.s"
.const OVL_STORAGE = 11
.const OVL_TITLE   = 12
#define SAVE_SLOT_INDEX_EXTERNAL
#import "reu_stub.s"
#import "screen_vera.s"
#import "../../core/color.s"
#import "config.s"
#import "input.s"
#import "../../core/rng.s"
#import "../../core/math.s"
#import "../../core/tables.s"
#import "../../core/item_defs.s"
#import "../../core/player.s"
#define MSG_HISTORY_IN_AUX
.macro MsgHistorySegment() {
    .segment Cx16AuxData
}
.macro MsgHistoryRestoreSegment() {
    .segment Default
}
#import "../../core/ui_messages.s"
#import "../../core/ui_status.s"
#import "../../core/runtime_ui_strings.s"
#import "../../core/generation_busy.s"
#import "../../core/stat_display.s"
#import "../../core/huffman.s"
.segment Cx16HuffData
ovl_huffdata_end:
.segment Default
#import "../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
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
.macro CmdJamSegment() {
    .segment ChestOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
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
    .segment Default
}
#import "../../core/dungeon_features.s"
#import "../../core/chest_search.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../core/monster.s"
combat_msg_monster_in_way:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    lda #<cmb_in_way_str
    ldy #>cmb_in_way_str
    jmp combat_msg_monster_suffix
cmb_in_way_str:
    .text " is in your way!" ; .byte 0
#import "../../core/tier_manager.s"
#import "../../core/monster_ai.s"
#import "../../core/scene_dirty.s"
#import "../../core/scene_force.s"
#import "../../core/monster_magic.s"
.macro ChestSummonsSegment() {
    .segment Default
}
.macro ChestSummonsRestoreSegment() {
    .segment Default
}
#import "../../core/item.s"
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
#import "../../core/spell_effects.s"
#import "../../core/spell_effects_overlay.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY

#import "../../core/store_data_defs.s"
#import "../../core/recall_defs.s"
#import "../../core/spell_data_defs.s"

#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
#import "../../core/player_magic.s"
#import "dungeon_render_vera.s"
#import "../../core/item_desc_banked.s"
#import "../../core/projectile.s"
#import "../../core/storage_status.s"
#import "memory_bank.s"
#import "mmu_macros.s"
#import "save_stream.s"
#import "storage_kernal.s"
#import "overlay_storage.s"
#import "services.s"

// ============================================================
// entry — jumped to via entry_bootstrap
// ============================================================
entry_main:
    jsr hal_platform_init_early
    jsr cx16_reset_session_state
    jsr cx16_preload_banks
    jsr generation_busy_install
    jsr platform_services_install_cx16
    jsr platform_services_assert_installed

restart_entry:
    jsr detect_machine
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

title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
!new_game:
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
    jmp screen_put_string

title_str:
    .text "MORIA 8 (COMMANDER X16)"
    .byte 0

cx16_reset_session_state:
    lda #8
    sta save_device
    sta program_device
    lda #1
    sta disk_mode
    lda #hal_storage_disk_setup_done_value
    sta disk_setup_done
    rts

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
#endif
    jsr disk_prompt_save
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game
    jsr disk_prompt_game_required
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jmp title_enter_menu

title_show_sysinfo:
    stz CX16_ROM_BANK_REG
    lda CX16_KERNAL_REV
    sta tsi_krev_cached
    sec
    jsr CX16_KERNAL_MEMTOP
    sta tsi_ram_banks_cached
    lda #OVL_TITLE
    jsr overlay_load
    bcs !done+
    jsr title_show_sysinfo_banked
!done:
    rts

// ============================================================
// Platform services (indirect API slots in core/platform_services_api.s)
// ============================================================
platform_services_install_cx16:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<cx16_platform_main_loop_begin
    sta platform_main_loop_begin_api + 1
    lda #>cx16_platform_main_loop_begin
    sta platform_main_loop_begin_api + 2

    lda #<cx16_platform_vector_reassert
    sta platform_vector_reassert_api + 1
    lda #>cx16_platform_vector_reassert
    sta platform_vector_reassert_api + 2

    lda #<cx16_platform_runtime_resync
    sta platform_runtime_resync_api + 1
    lda #>cx16_platform_runtime_resync
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

// ============================================================
// Special rooms trampolines
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
    jsr cx16_platform_runtime_resync
    plp
    rts

#if !BYPASS_SLOT_PROMPT
save_prepare_slot_prompt:
    lda #OVL_STORAGE
    jmp overlay_load

save_select_slot_prompt:
    jmp save_select_slot_prompt_impl
#endif

// ============================================================
// UI / item / store / spell trampolines
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
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    jsr eff_earthquake
    jmp tramp_restore_spell_overlay
!load_failed:
    rts

tramp_eff_map_area:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    jsr eff_map_area
    jmp tramp_restore_spell_overlay
!load_failed:
    rts

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

tramp_chest_open:
    lda #<chest_open_command
    ldy #>chest_open_command
    jmp chest_dispatch

chest_dispatch:
    sta chest_disp_jmp+1
    sty chest_disp_jmp+2
    lda #OVL_CHEST
    jsr overlay_load
    bcs !done+
chest_disp_jmp:
    jmp $0000
!done:
    rts

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

tramp_cmd_jam:
    lda #OVL_CHEST
    jsr overlay_load
    bcs !done+
    jsr door_jam_command
!done:
    rts

tramp_door_pick_roll:
    lda #OVL_CHEST
    jsr overlay_load
    bcs !load_failed+
    jsr door_pick_roll
    rts
!load_failed:
    clc
    rts

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
    pha
    txa
    pha
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

tramp_eff_destroy_area:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !load_failed+
    jsr da_devastate
    jmp tramp_restore_spell_overlay
!load_failed:
    rts

tramp_restore_spell_overlay:
    php
    pha
    lda #OVL_NONE
    sta piw_return_overlay
    lda #OVL_SPELL
    jsr overlay_load
    bcc !restored+
    brk
!restored:
    pla
    plp
    rts

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
    jsr cx16_disk_setup_run
!done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr cx16_disk_prepare_selected
!done:
    rts

tramp_store_init_all:
    lda #<store_init_all
    ldy #>store_init_all
    jmp chest_dispatch

tramp_store_restock_all:
    lda #<store_restock_all
    ldy #>store_restock_all
    jmp chest_dispatch

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
// Media prompts (no-ops on CX16 SD/HostFS; all 21 banks preloaded in RAM)
// ============================================================
disk_prompt_save:
    clc
    rts

disk_prompt_game:
    clc
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
    cmp #DEATH_CHEST_NEEDLE
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name

!tgo_load_overlay:
    lda #OVL_DEATH
    jmp overlay_load

tramp_game_over:
    jsr tramp_game_over_prepare
    bcs !done+
    jmp tramp_game_over_run
!done:
    rts

tramp_winner_royal:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !done+
    jsr winner_apply_retirement_bonus_overlay
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr royal_screen
!done:
    rts

game_over_prompt:
    lda #OVL_DEATH
    jsr overlay_load
    bcc !overlay_ok+
    jmp title_enter_menu
!overlay_ok:
    jmp game_restart_overlay

// ============================================================
// Play-phase modules (unified in Default segment on CX16)
// ============================================================
.segment Default
#import "../../core/chest_summons.s"
#define STORE_RUNTIME_DATA_EXTERNAL
#define STORE_INVENTORY_DATA_EXTERNAL
#import "../../core/store_data.s"
#undef STORE_INVENTORY_DATA_EXTERNAL
#undef STORE_RUNTIME_DATA_EXTERNAL
#import "../../core/store_hot_data.s"
#define RECALL_ARRAY_DATA_EXTERNAL
#import "../../core/recall.s"
#undef RECALL_ARRAY_DATA_EXTERNAL
#import "../../core/dungeon_los.s"
#import "../../core/monster_attack.s"

.macro PlayerMoveRestoreResidentSegment() {
    .segment Default
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
    .segment Default
}
.macro WizardGenExecSegment() {
    .segment ModalMiscOverlay
}
#define RECALL_VIEW_OVERLAYED
.const RECALL_VIEW_OVL = OVL_MODAL_MISC
.macro RecallViewBodySegment() {
    .segment ModalMiscOverlay
}
.macro RecallViewBodyRestoreSegment() {
    .segment Default
}
.macro ChestRouteSegment() {
    .segment Default
}
.macro ChestRouteRestoreSegment() {
    .segment Default
}
#define PLAYER_LOOK_EXTERNAL
#import "../../core/player_move.s"
#undef PLAYER_LOOK_EXTERNAL
.macro PlayerRunInitializeSegment() {
    .segment Default
}
.macro PlayerRunRestoreResidentSegment() {
    .segment Default
}
#define PLAYER_RUN_INITIALIZE_EXTERNAL
#import "../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL
#define PMU_TURN_FEEDBACK_EXTERNAL
#define CMB_IN_WAY_EXTERNAL
#import "../../core/combat.s"
#undef CMB_IN_WAY_EXTERNAL
#undef PMU_TURN_FEEDBACK_EXTERNAL
#define WIZARD_PROMPT_HELPERS_EXTERNAL
#import "../../core/wizard.s"
#undef WIZARD_PROMPT_HELPERS_EXTERNAL
#define PLAYER_LOOK_EXTERNAL
#define DISARM_COMMAND_EXTERNAL
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#undef PLAYER_LOOK_EXTERNAL
#import "dungeon_scroll_vera.s"
#import "../../core/turn.s"
#import "../../core/ui_restore.s"
#import "../../core/ui_help_clear.s"

tramp_do_look:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr do_look
!done:
    jmp tramp_sr_epilogue

// ============================================================
// Data-only Bank 3 (Cx16AuxData at virtual $6000-$7FFF)
// ============================================================
.segment Cx16AuxData
#import "../../core/store_inventory_data.s"
#import "../../core/recall_array_data.s"
#import "../../core/spell_class_data.s"
#define STORE_HOT_DATA_EXTERNAL
#import "../../core/store_runtime_data.s"
#undef STORE_HOT_DATA_EXTERNAL
#import "../../core/spell_helper_tables.s"
#import "../../core/spell_names.s"

.align $100
cx16_ego_suffix_slots:
hal_ego_suffix_slots:
cx16_ego_suffix_none: .byte 0
    .fill 16 - (* - cx16_ego_suffix_none), 0
cx16_ego_suffix_slay_animal: .text " (Slay Animal)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_slay_animal), 0
cx16_ego_suffix_slay_evil: .text " (Slay Evil)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_slay_evil), 0
cx16_ego_suffix_slay_undead: .text " (Slay Undead)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_slay_undead), 0
cx16_ego_suffix_flame: .text " (Flame)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_flame), 0
cx16_ego_suffix_frost: .text " (Frost)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_frost), 0
cx16_ego_suffix_defender: .text " (Defender)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_defender), 0
cx16_ego_suffix_holy_avenger: .text " (Holy Avenger)" ; .byte 0
    .fill 16 - (* - cx16_ego_suffix_holy_avenger), 0
cx16_ego_suffix_slots_end:
.assert "CX16 ego suffix slots are page aligned", <cx16_ego_suffix_slots, 0
.assert "CX16 ego suffix slots are 8 x 16 bytes", cx16_ego_suffix_slots_end - cx16_ego_suffix_slots, EGO_TYPE_COUNT * 16

ovl_auxdata_end:
.print "CX16 AuxData: " + (ovl_auxdata_end - $6000) + " bytes"
.assert "CX16 AuxData fits Bank 3 ($6000-$7FFF)", ovl_auxdata_end <= $8000, true
.segment Default

// ============================================================
// Overlay segment blocks (Banks 9-20 at $A000-$BFFF)
// ============================================================
.segment TownOverlay
#import "../../core/store.s"
#import "../../core/ui_store.s"
#import "../../core/ui_home.s"
#import "../../core/ui_home_text.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $a000) + " bytes"
.assert "Town overlay fits 8KB bank", ovl_town_end <= $c000, true

.segment StartupOverlay
#import "../../core/background_data.s"
#import "../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $a000) + " bytes"
.assert "Startup overlay fits 8KB bank", ovl_start_end <= $c000, true

.segment DeathOverlay
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
    #import "../../core/player_destroy_area.s"
    #import "../../core/player_magic_map.s"
    #import "../../core/player_magic_earthquake.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $a000) + " bytes"
.assert "High-score I/O counter is owned by death overlay", hiscore_io_count_lo >= $a000 && hiscore_io_count_hi < ovl_death_end, true
.assert "High-score I/O does not alias storage counter", hiscore_io_count_lo != save_count_lo && hiscore_io_count_hi != save_count_hi, true
.assert "Death overlay fits 8KB bank", ovl_death_end <= $c000, true

.segment ModalMiscOverlay
#import "../../core/royal.s"
#import "../../core/ui_recall.s"
#import "../../core/ui_wizard.s"

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
.print "Modal misc overlay: " + (ovl_modal_misc_end - $a000) + " bytes"
.assert "Modal misc overlay fits 8KB bank", ovl_modal_misc_end <= $c000, true

.segment HelpOverlay
#import "../commodore/c128/ui_help_data_80.s"
#import "../../core/ui_help.s"
#import "../../core/ui_inventory.s"
#import "../../core/ui_equipment.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $a000) + " bytes"
.assert "Help overlay fits 8KB bank", ovl_help_end <= $c000, true

.segment UiOverlay
#import "../../core/ui_character.s"
#import "../../core/ui_identify.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $a000) + " bytes"
.assert "UI overlay fits 8KB bank", ovl_ui_end <= $c000, true

.segment ItemActionsOverlay
#define SCROLL_P3_ROUTER_ENABLED
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
.print "Item actions overlay: " + (ovl_items_end - $a000) + " bytes"
.assert "Item actions overlay fits 8KB bank", ovl_items_end <= $c000, true

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
#import "../../core/player_magic_slow_runtime.s"
#define PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_turn_banked.s"
#undef PMU_TURN_FEEDBACK_ONLY
#import "../../core/player_magic_execute_overlay.s"
#undef PMX_DETECT_EFFECTS_EXTERNAL
#undef PMX_MAP_AREA_TRAMPOLINE
#undef PMX_MAP_AREA_EXTERNAL

    #define SCROLL_P3_NEW_OWNER
    #define SCROLL_P3_EXISTING_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER
    #undef SCROLL_P3_NEW_OWNER
#undef PMX_DESTROY_AREA_EXTERNAL
#undef PMX_EARTHQUAKE_EXTERNAL
#import "../../core/player_magic_levelup.s"
#import "../../core/player_magic_display.s"
#import "../../core/player_magic_tail.s"
#import "../../core/player_magic_select_overlay.s"
#import "../../core/player_gain_spell_impl.s"
#import "../../core/player_magic_learn_op.s"
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $a000) + " bytes"
.assert "Spell overlay fits 8KB bank", ovl_spell_end <= $c000, true

.segment DungeonGenOverlay
#import "../../core/special_rooms.s"
#import "../../core/dungeon_tunnel_guard.s"
#import "../../core/dungeon_gen.s"
ovl_gen_end:
.print "Dungeon gen overlay: " + (ovl_gen_end - $a000) + " bytes"
.assert "Dungeon gen overlay fits 8KB bank", ovl_gen_end <= $c000, true

.segment StorageOverlay
#import "../shared/save.s"
#import "save_slot_menu.s"
#import "disk_setup_cx16.s"
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $a000) + " bytes"
.assert "Storage overlay fits 8KB bank", ovl_storage_end <= $c000, true

.segment TitleOverlay
#import "title_screen.s"
title_show_sysinfo_banked:
    lda #COL_DGREY
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #((SCREEN_COLS - 34) / 2)
    sta zp_cursor_col
    lda #<cx16_sysinfo_prefix_str
    sta zp_ptr0
    lda #>cx16_sysinfo_prefix_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // KERNAL ROM revision byte ($FF80 cached in tsi_krev_cached):
    //   $01..$7F = official release R<N>
    //   $80..$FE = prerelease/custom build (-N -> R<N>+)
    //   $00/$FF  = unknown ('?')
    lda tsi_krev_cached
    beq !krev_unknown+
    cmp #$ff
    beq !krev_unknown+
    bpl !krev_release+
    eor #$ff
    clc
    adc #1
    jsr screen_put_decimal
    lda #$2b                // '+'
    jsr hal_screen_put_char
    bra !print_ram+
!krev_release:
    jsr screen_put_decimal
    bra !print_ram+
!krev_unknown:
    lda #$3f                // '?'
    jsr hal_screen_put_char

!print_ram:
    lda #<cx16_sysinfo_sep_str
    sta zp_ptr0
    lda #>cx16_sysinfo_sep_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Banked RAM size from MEMTOP ($FF99 with C=1 -> A = 8KB bank count;
    // 0 means 256 banks = 2048KB, 1..255 means A * 8KB).
    lda tsi_ram_banks_cached
    bne !banks_nonzero+
    stz zp_temp0
    lda #>2048
    sta zp_temp1
    bra !emit_ram_kb+
!banks_nonzero:
    sta zp_temp0
    stz zp_temp1
    asl zp_temp0
    rol zp_temp1
    asl zp_temp0
    rol zp_temp1
    asl zp_temp0
    rol zp_temp1
!emit_ram_kb:
    jsr screen_put_decimal_16
    lda #<cx16_sysinfo_suffix_str
    sta zp_ptr0
    lda #>cx16_sysinfo_suffix_str
    sta zp_ptr0_hi
    jmp hal_screen_put_string

cx16_sysinfo_prefix_str:
    .text "COMMANDER X16  ROM R" ; .byte 0
cx16_sysinfo_sep_str:
    .text "  " ; .byte 0
cx16_sysinfo_suffix_str:
    .text "KB RAM" ; .byte 0
ovl_title_end:
.print "Title overlay: " + (ovl_title_end - $a000) + " bytes"
.assert "Title overlay fits 8KB bank", ovl_title_end <= $c000, true

.segment ChestOverlay
#import "../../core/chest.s"
#import "../../core/store_restock_overlay.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $a000) + " bytes"
.assert "Chest overlay fits 8KB bank", ovl_chest_end <= $c000, true

// ============================================================
// Ego-item & cross-overlay trampolines (resident)
// ============================================================
.segment Default
tramp_roll_ego_type:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr roll_ego_type
    rts
!load_failed:
    pla
    lda #0
    rts

tramp_items_dispatch:
    sta tramp_items_jmp+1
    sty tramp_items_jmp+2
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !done+
tramp_items_jmp:
    jmp $0000
!done:
    rts

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
    brk
!restored:
    pla
    rts
!load_failed:
    pla
    lda #0
    rts

tramp_roll_ego_type_gen:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr roll_ego_type
    pha
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcc !restored+
    brk
!restored:
    pla
    rts
!load_failed:
    pla
    lda #0
    rts

tramp_ego_apply_damage:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr ego_apply_damage
    rts
!load_failed:
    pla
    rts

tramp_ego_get_ac_bonus:
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    pla
    jsr ego_get_ac_bonus
    rts
!load_failed:
    pla
    lda #0
    rts

tramp_ui_view_restore_spell_overlay:
    jsr ui_view_restore_modal_overlay
    lda #OVL_SPELL
    bne !restore_overlay+

tramp_ui_view_restore_items_overlay:
    jsr ui_view_restore_modal_overlay
    jmp !restore_items+

tramp_combat_check_levelup_items:
    jsr combat_check_levelup
!restore_items:
    lda #OVL_ITEMS
!restore_overlay:
    jsr overlay_load
    bcc !restored+
    brk
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
    brk
!restored:
    rts

tramp_ego_append_suffix:
    beq !teas_done+
    pha
    lda #OVL_ITEMS
    jsr overlay_load
    pla
    bcs !teas_done+
    jsr ego_get_suffix_ptr
    lda zp_ptr0
    ldy zp_ptr0_hi
    jmp combat_append_str
!teas_done:
    rts

// ============================================================
// Final boundary assertions
// ============================================================
program_end:
.print "CX16 Unified Resident+Play end: $" + toHexString(program_end)
.assert "Unified Resident+Play image fits below $9B00 tier name pool", program_end <= PLATFORM_TIER_NAME_POOL_BASE, true
.assert "HuffData fits Bank 4 ($8000-$9FFF)", ovl_huffdata_end <= $a000, true
