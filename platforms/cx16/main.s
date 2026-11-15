#define HAL_PLATFORM_LEGAL_VIEWER
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
#define HOME_OVERLAY_SEPARATE
#define WALL_TO_MUD_SEGMENT_CUSTOM
#define ITEM_SPAWN_IN_GEN_OVERLAY
#define RE_EQUIP_SEGMENT_CUSTOM
#define CX16_DETECT_MACHINE_EXTERNAL
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#define HAL_PLATFORM_EFF_ITEM_P1_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
#define HELP_TITLE_EXTERNAL
#define PFLAGS_SEGMENT_CUSTOM
#define PLAYER_RECALC_PFLAGS_EXTERNAL
#define TURN_REST_DISTURBED_EXTERNAL
#define LEVELUP_MAGIC_PENDING_EXTERNAL
#define PLATFORM_NF_DIGIT_BUF_EXTERNAL
#define PLATFORM_ITEM_NAME_BUF_LOW
#define PLATFORM_LIST_BUFS_LOW
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
.const LEGAL_BASE = $a000
.const LEGAL_LIMIT = $c000
.segmentdef LegalOverlay [outPrg=OVL_OUT + "/LEGALUI", start=$a000, min=$a000, max=$bfff]
.segmentdef HelpOverlay        [outPrg=OVL_OUT + "/OVL.HELP",      start=$a000, min=$a000, max=$bfff]
.segmentdef UiOverlay          [outPrg=OVL_OUT + "/OVL.UI",        start=$a000, min=$a000, max=$bfff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/OVL.ITEMS",     start=$a000, min=$a000, max=$bfff]
.segmentdef SpellOverlay       [outPrg=OVL_OUT + "/OVL.SPELL",     start=$a000, min=$a000, max=$bfff]
.segmentdef DungeonGenOverlay  [outPrg=OVL_OUT + "/OVL.GEN",       start=$a000, min=$a000, max=$bfff]
.segmentdef StorageOverlay     [outPrg=OVL_OUT + "/OVL.STORAGE",   start=$a000, min=$a000, max=$bfff]
.segmentdef TitleOverlay       [outPrg=OVL_OUT + "/OVL.TITLE",     start=$a000, min=$a000, max=$bfff]
.segmentdef ChestOverlay       [outPrg=OVL_OUT + "/OVL.CHEST",     start=$a000, min=$a000, max=$bfff]
.segmentdef HomeOverlay        [outPrg=OVL_OUT + "/OVL.HOME",      start=$a000, min=$a000, max=$bfff]
.segmentdef Cx16Catalog        [outPrg=OVL_OUT + "/MONSTER.CAT",   start=$a000, min=$a000, max=$bfff]
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
#if CX16_CARTRIDGE
#import "cartridge_contract.s"
#endif
:BasicUpstart2(entry_bootstrap)

.pc = $080d "Resident"
entry_bootstrap:
#if CX16_CARTRIDGE
.assert "CART_ENTRY matches entry_bootstrap", entry_bootstrap == CART_ENTRY, true
#endif
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

// ============================================================
// Resident import cascade
// ============================================================
#import "../../core/zeropage.s"
#import "hal/layout.s"
#import "memory.s"
// Cold/transient item and UI buffers share unused tail of the $0600-$06FF scratch
// page above hd_decode_buf ($0600-$063F) and dungeon_door_scan ($0600-$0640).
.const PLATFORM_ITEM_NAME_DECODE_BUF_BASE = $0642 // 48 B ($0642-$0671)
.const PLATFORM_PIW_VISIBLE_SLOTS_BASE    = $0672 // 22 B ($0672-$0687)
.const PLATFORM_PM_SPELL_LIST_BASE        = $0688 //  9 B ($0688-$0690)
.const PLATFORM_NF_DIGIT_BUF_BASE         = $0691 //  8 B ($0691-$0698)
.label turn_rest_disturbed                = $0699 //  1 B
.label levelup_magic_pending              = $069a //  1 B
.assert "CX16 $0642-$069A scratch fits $0600-$06FF clear of door scan", PLATFORM_ITEM_NAME_DECODE_BUF_BASE >= DUNGEON_GEN_DOOR_SCAN_BASE + 65 && $069a < DUNGEON_GEN_DOOR_SCAN_LIMIT, true
#import "bank_port_consts.s"
#import "hal/lifecycle_policy.s"
#import "overlay.s"
.const OVL_HOME    = 11
.const OVL_STORAGE = 12
.const OVL_TITLE   = 13
.const CX16_BANK_MODAL = CX16_BANK_OVERLAY_BASE + OVL_MODAL_MISC - 1
.const CX16_BANK_ITEMS = CX16_BANK_OVERLAY_BASE + OVL_ITEMS - 1
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
#import "../../core/recall_defs.s"
.macro PflagsSegment() {
    .segment ModalMiscOverlay
}
.macro PflagsRestoreSegment() {
    .segment Default
}
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
#if HAL_PLATFORM_MONSTER_CATALOG
#import "../shared/catalog/catalog_names.s"    // The catalog's names, read like the corpus
#endif
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
#import "monster_catalog_bank.s"
#import "../../core/monster_catalog.s"
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
.macro ItemSpawnSegment() {
    .segment DungeonGenOverlay
}
.macro ItemSpawnRestoreSegment() {
    .segment Default
}
.macro ItemPickupSegment() {
    .segment ItemActionsOverlay
}
.macro ItemPickupRestoreSegment() {
    .segment Default
}
.macro ReEquipSegment() {
    .segment ModalMiscOverlay
}
.macro ReEquipRestoreSegment() {
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
.macro WallToMudSegment() {
    .segment SpellOverlay
}
.macro WallToMudRestoreSegment() {
    .segment Default
}
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY

#import "../../core/store_data_defs.s"
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
#if CX16_CARTRIDGE
#import "cartridge_copy.s"
#endif
#import "storage_kernal.s"
#import "overlay_storage.s"
#import "services.s"

// ============================================================
// entry — jumped to via entry_bootstrap
// ============================================================
entry_main:
    jsr hal_platform_init_early
    jsr cx16_preload_banks
    jsr generation_busy_install
    lda #OVL_TITLE
    jsr overlay_load
    bcs !preload_halt+
    jsr cx16_cold_boot_init
    jsr platform_services_assert_installed
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #OVL_TITLE
    jsr overlay_load
    bcs !preload_halt+
    jmp title_enter_menu_ovl
!preload_halt:
    lda #$01
    jmp hal_platform_panic

tramp_title_load_game:
    lda disk_setup_done
    bne !load_now+
    jsr tramp_disk_setup
    bcs title_enter_menu
!load_now:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs title_enter_menu
    jmp title_load_game_ovl

// ============================================================
// Special rooms & level item-spawn trampolines
// ============================================================
tramp_gen_dispatch:
    sta tramp_gen_jmp+1
    sty tramp_gen_jmp+2
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcs !done+
tramp_gen_jmp:
    jmp $0000
!done:
    rts

item_spawn_level:
    lda #<item_spawn_level_gen
    ldy #>item_spawn_level_gen
    bra tramp_gen_dispatch

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
    ldx CX16_RAM_BANK_REG
    phx
    ldx #CX16_BANK_MODAL
    stx CX16_RAM_BANK_REG
    jsr run_initialize_impl
    plx
    stx CX16_RAM_BANK_REG
    rts

re_equip_entry:
    ldx CX16_RAM_BANK_REG
    phx
    ldx #CX16_BANK_MODAL
    stx CX16_RAM_BANK_REG
    jsr re_equip
    tay
    plx
    stx CX16_RAM_BANK_REG
    tya
    rts

tramp_item_pickup:
    lda #OVL_ITEMS
    jsr overlay_load
    bcs !load_failed+
    jmp item_pickup
!load_failed:
    clc
    rts

#import "legal.s"
#import "../../build/trampolines/cx16_trampolines.inc"

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

tramp_spell_dispatch:
    sta tramp_spell_jmp+1
    sty tramp_spell_jmp+2
    lda #OVL_SPELL
    jsr overlay_load
    bcs !done+
tramp_spell_jmp:
    jmp $0000
!done:
    rts

tramp_disk_setup:
    lda CX16_RAM_BANK_REG
    pha
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !done+
    jsr cx16_disk_setup_run
!done:
    pla
    sta CX16_RAM_BANK_REG
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
    .segment ModalMiscOverlay
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

ovl_auxdata_end:
.print "CX16 AuxData: " + (ovl_auxdata_end - $6000) + " bytes"
.assert "CX16 AuxData fits Bank 3 ($6000-$7FFF)", ovl_auxdata_end <= $8000, true
.segment Default

// ============================================================
// Overlay segment blocks (Banks 9-21 at $A000-$BFFF)
// ============================================================
.segment TownOverlay
#import "../../core/store.s"
#import "../../core/ui_store.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $a000) + " bytes"
.assert "Town overlay fits 8KB bank", ovl_town_end <= $c000, true

.segment HomeOverlay
#import "../../core/ui_home.s"
#import "../../core/ui_home_text.s"
#import "../../core/eff_item_p1.s"
#import "../../core/eff_item_extended.s"
ovl_home_end:
.print "Home overlay: " + (ovl_home_end - $a000) + " bytes"
.assert "Home overlay fits 8KB bank", ovl_home_end <= $c000, true

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
#import "../../core/ui_help_title.s"
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
    #import "../../core/item_exchange.s"
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
// Find Traps and Destroy Traps/Doors (2026-11-08): their only callers are
// the spell dispatch above, so they run here, not resident (as on the C64).
#import "../../core/spell_effects_overlay.s"
.assert "The trap effects are in OVL.SPELL with their callers", eff_find_traps >= $a000 && eff_destroy_traps_doors >= $a000, true

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
title_load_game_ovl:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
    jsr disk_prompt_save
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt_impl
#endif
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game
    jsr disk_prompt_game_required
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jmp title_enter_menu
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $a000) + " bytes"
.assert "Storage overlay fits 8KB bank", ovl_storage_end <= $c000, true

.segment TitleOverlay
#import "title_screen.s"

cx16_cold_boot_init:
    jsr cx16_reset_session_state
    jsr detect_machine
    jsr cx16_input_install_key_events
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

cx16_reset_session_state:
    lda #8
    sta save_device
    sta program_device
    lda #1
    sta disk_mode
    lda #hal_storage_disk_setup_done_value
    sta disk_setup_done
    rts

detect_machine:
    lda #MACHINE_CX16
    sta zp_machine_type
    lda #COLUMNS_80
    sta zp_column_mode
    stz CX16_ROM_BANK_REG
    lda CX16_KERNAL_REV
    sta tsi_krev_cached
    sec
    jsr CX16_KERNAL_MEMTOP
    sta tsi_ram_banks_cached
    rts

title_enter_menu_ovl:
    lda #$ff
    sta save_slot_index
    lda #COL_LGREY
    sta zp_text_color

    jsr title_clear_full_screen
    jsr title_load_and_draw
    jsr title_clear_below_menu

    jsr msg_init
    jsr title_show_sysinfo_ovl
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
    jmp tramp_title_load_game
!not_l:
    cmp #$41                // A: About, before a character exists
    bne !not_legal_title+
    jsr tramp_ui_legal_display
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

title_str:
    .text "MORIA 8 (COMMANDER X16)"
    .byte 0

title_show_sysinfo_ovl:
    stz CX16_ROM_BANK_REG
    lda CX16_KERNAL_REV
    sta tsi_krev_cached
    sec
    jsr CX16_KERNAL_MEMTOP
    sta tsi_ram_banks_cached

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

tramp_ui_view_restore_spell_overlay:
    jsr ui_view_restore_modal_overlay
    lda #OVL_SPELL
    bne !restore_overlay+

tramp_ui_view_restore_items_overlay:
    jsr ui_view_restore_modal_overlay
    jmp !restore_items+

tramp_eff_ext_eat:
    lda #OVL_HOME
    jsr overlay_load
    bcs !te_done+
    jsr eff_ext_eat_piw
    jmp !restore_items+

tramp_eff_ext_quaff:
    lda #OVL_HOME
    jsr overlay_load
    bcs !te_done+
    jsr eff_ext_quaff_piw
    jmp !restore_items+
!te_done:
    rts

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

// hal_item_cat_read_byte — Read byte at item_cat_off_lo/hi from Bank 6 ITEM.CAT ($A000-$BD94).
// Input: item_cat_off_lo/hi. Output: A = byte. Clobbers: A, Y (preserves X, ZP).
hal_item_cat_read_byte:
    php
    sei
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_BANK_ITEM_CAT
    sta CX16_RAM_BANK_REG
    lda item_cat_off_lo
    sta hicr_lda + 1
    clc
    lda #>BANKED_DATA_BASE
    adc item_cat_off_hi
    sta hicr_lda + 2
hicr_lda:
    lda $a000
    tay
    pla
    sta CX16_RAM_BANK_REG
    plp
    tya
    rts

// tramp_ego_append_suffix — Decode ego 1..55 via resident item_cat_decode_ego
// into item_name_decode_buf and append to combat_msg_buf without evicting caller
// overlays (OVL_CHEST/OVL_ITEMS).
// Input: A = ego type. Clobbers: A, Y, zp_ptr0.
tramp_ego_append_suffix:
    and #EGO_ID_MASK
    beq !teas_done+
    cmp #EGO_TYPE_COUNT
    bcs !teas_done+
    jsr item_cat_decode_ego
    lda zp_ptr0
    ldy zp_ptr0_hi
    jmp combat_append_str
!teas_done:
    rts

// Resident bank-switch wrapper for relocated equipment pflags recalc
hal_player_recalc_pflags:
    ldx CX16_RAM_BANK_REG
    phx
    ldx #CX16_BANK_MODAL
    stx CX16_RAM_BANK_REG
    jsr player_recalc_pflags_equipment
    plx
    stx CX16_RAM_BANK_REG
    rts

// ============================================================
// Final boundary assertions
// ============================================================
program_end:
.print "CX16 Unified Resident+Play end: $" + toHexString(program_end)
.assert "Unified Resident+Play image fits below $9B00 tier name pool", program_end <= PLATFORM_TIER_NAME_POOL_BASE, true
.assert "HuffData fits Bank 4 ($8000-$9FFF)", ovl_huffdata_end <= $a000, true
.assert "Home overlay owns home_enter separately from TownOverlay", home_enter >= $a000 && home_enter < ovl_home_end && store_enter >= $a000 && store_enter < ovl_town_end, true
.assert "Evicted Low-RAM trampolines stay resident while targets live in HiRAM", re_equip_entry < PLATFORM_TIER_NAME_POOL_BASE && re_equip >= $a000 && re_equip < ovl_modal_misc_end && run_initialize < PLATFORM_TIER_NAME_POOL_BASE && run_initialize_impl >= $a000 && run_initialize_impl < ovl_modal_misc_end && item_spawn_level < PLATFORM_TIER_NAME_POOL_BASE && item_spawn_level_gen >= $a000 && item_spawn_level_gen < ovl_gen_end && tramp_item_pickup < PLATFORM_TIER_NAME_POOL_BASE && item_pickup >= $a000 && item_pickup < ovl_items_end && eff_wall_to_mud >= $a000 && eff_wall_to_mud < ovl_spell_end && title_enter_menu < PLATFORM_TIER_NAME_POOL_BASE && title_enter_menu_ovl >= $a000 && title_enter_menu_ovl < ovl_title_end && cx16_cold_boot_init >= $a000 && cx16_cold_boot_init < ovl_title_end, true

// Cold legal modal: workspace is reserved but not emitted to disk.
.segment LegalOverlay
#import "../../core/ui_legal.s"
#if CX16_CARTRIDGE
#import "legal_stream.s"
#else
#import "../shared/legal_disk_stream.s"
#endif
legal_code_end:
.assert "Legal code stays below its modal workspace", legal_code_end <= legal_zp_save, true
.assert "Legal ZP snapshot stays below input cache", legal_zp_save + $8e <= legal_input_cache, true
.segment Default
