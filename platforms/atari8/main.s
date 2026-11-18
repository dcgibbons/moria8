#define HAL_PLATFORM_LEGAL_VIEWER
#define HELP_TITLE_EXTERNAL
// main.s — Moria8 for Atari 8-Bit (64 KB 800XL/65XE + 128 KB 130XE)
//
// Assembled with Kick Assembler.
// Boot loader (boot.s at $0800) loads MORIA8.RES ($0C00-$C0FF) and jumps to
// entry_main ($0C00). See docs/ATARI8_MEMORY_CONTRACT.md.

.encoding "screencode_mixed"

#define ATARI8
// The VMS monster catalog as disk records (2026-11-05, monster_catalog_a8.s):
// MONSTER.CAT read a sector per species, or preloaded on a 130XE.
#define HAL_PLATFORM_MONSTER_CATALOG
#define HAL_PLATFORM_CATALOG_RECORDS
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#define HAL_PLATFORM_EFF_ITEM_P1_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
#define ATARI8_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_REQUIRES_MEDIA_PROBE
#define HOME_OVERLAY_SEPARATE
#define SAVE_IN_STORAGE_OVERLAY
#define HELP_CMD_BODY_EXTERNAL
#define DOOR_OPEN_CLOSE_EXTERNAL
#define ITEM_DROP_EXTERNAL
#define ITEM_REFRESH_KNOWN_EXTERNAL
#define EFF_IDENTIFY_PROMPT_EXTERNAL
#define EFF_DETECT_EVIL_EXTERNAL
#define PLAYER_CAST_RESIDENT
#define PLAYER_MAGIC_BROWSE_EXTERNAL
#define STARTING_KIT_EXTERNAL
#define LOAD_RESUME_RESET_EXTERNAL
#define CALC_DIG_EXTERNAL
#define CALC_DIG_CO_LOCATED
#define STORE_CHECK_CAT_DUPLICATED
#if ATARI8_CARTRIDGE
#import "cartridge_contract.s"
#endif
#define STORAGE_STATUS_HELPER
#define RECALL_VIEW_OVERLAYED
.const RECALL_VIEW_OVL = 3
.macro RecallViewBodySegment() {
    .segment DeathOverlay
}
.macro RecallViewBodyRestoreSegment() {
    .segment Default
}

.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")

// ============================================================
// Overlay & Banked Segments
// ============================================================
.segmentdef StartupOverlay     [outPrg=OVL_OUT + "/OVL.STA", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay        [outPrg=OVL_OUT + "/OVL.TWN", start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay       [outPrg=OVL_OUT + "/OVL.DTH", start=$e000, min=$e000, max=$efff]
.segmentdef ModalMiscOverlay   [outPrg=OVL_OUT + "/OVL.MDL", start=$e000, min=$e000, max=$efff]
.const LEGAL_BASE = $e000
.const LEGAL_LIMIT = $f000
.segmentdef LegalOverlay [outPrg=OVL_OUT + "/legalui", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay        [outPrg=OVL_OUT + "/OVL.HLP", start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay          [outPrg=OVL_OUT + "/OVL.UI",  start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/OVL.ITM", start=$e000, min=$e000, max=$efff]
.segmentdef SpellOverlay       [outPrg=OVL_OUT + "/OVL.SPL", start=$e000, min=$e000, max=$efff]
.segmentdef ChestOverlay       [outPrg=OVL_OUT + "/OVL.CHS", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay  [outPrg=OVL_OUT + "/OVL.GEN", start=$e000, min=$e000, max=$efff]
.segmentdef HomeOverlay        [outPrg=OVL_OUT + "/OVL.HOM", start=$e000, min=$e000, max=$efff]
.segmentdef StorageOverlay     [outPrg=OVL_OUT + "/OVL.STO", start=$e000, min=$e000, max=$efff]
.segmentdef TitleOverlay       [outPrg=OVL_OUT + "/OVL.TTL", start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeBanked      [outPrg=OVL_OUT + "/ATARI.BNK", start=$f000, min=$f000, max=$fffa]
.segmentdef HighResident       [start=$ddce, min=$ddce, max=$dfff, virtual]

#import "hal/hal_contract.s"
#import "../../core/zeropage.s"
#import "../commodore/common/vic_palette_consts.s"
#import "memory.s"
#import "hal/layout.s"
#import "hal/lifecycle_policy.s"
#import "../commodore/common/save_slot_policy.s"

// Segment routing macros for core modules
.macro HuffmanDataSegment() {
    .segment Default
}
.macro PlayerCastSegment() {
    .segment Default
}
.macro PlayerCastRestoreResidentSegment() {
    .segment Default
}
.macro PmHelpersSegment() {
    .segment Default
}
.macro PmHelpersRestoreSegment() {
    .segment Default
}
.macro ItemInitIdentSegment() {
    .segment DeathOverlay
}
.macro ItemInitIdentRestoreSegment() {
    .segment Default
}
.macro WizardGenExecSegment() {
    .segment ModalMiscOverlay
}
.macro WizardGenExecRestoreSegment() {
    .segment Default
}
.macro ChestRouteSegment() {
    .segment Default
}
.macro ChestRouteRestoreSegment() {
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

// ============================================================
// Low Resident (< $4000) — Boot Entry, Font, Interrupts, Storage, & 130XE Cache
// ============================================================
.pc = $0c00 "Low Resident (< $4000)"

entry_main:
    sei
    cld
    ldx #$ff
    txs

    // Blank ANTIC DMA and disable NMIs before touching PORTB
    lda #$00
    sta NMIEN
    sta DMACTL
    lda #PORTB_GAME_RAM
    sta PORTB

    // Clear shared game zero-page ($02-$8F) and initialize zp_save_buf ($DD40)
    lda #$00
    ldx #$02
!clr_zp:
    sta $00,x
    inx
    cpx #$90
    bne !clr_zp-

    ldx #$8e
    lda #$00
!clr_save:
    sta zp_save_buf - 1,x
    dex
    bne !clr_save-

    // Initialize C64-ordered 1 KB RAM font at $0400-$07FF from Atari ROM font
    jsr atari_font_init

    // Install RAM NMI ($FFFA) and IRQ/BRK ($FFFE) vectors and enable VBI + DLI
    jsr atari_install_vectors

    // Initialize ANTIC Mode 2 Display List and clear screen
    jsr screen_init
    lda #12
    sta zp_cursor_row
    lda #11
    sta zp_cursor_col
    lda #<boot_loading_str
    sta zp_ptr0
    lda #>boot_loading_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Initialize POKEY sound and keyboard IRQ
    jsr hal_sound_init
    jsr input_init
    cli

#if !ATARI8_CARTRIDGE
    // Detect 130XE extended RAM (64 KB vs 128 KB)
    jsr xe_detect
#endif

    // Load RuntimeBanked payload (ATARI.BNK -> $F000-$FFF9)
    jsr init_load_banked

#if !ATARI8_CARTRIDGE
    // Preload hot assets into 130XE extended RAM if present
    jsr init_xe_preload
#endif

    // Install platform lifecycle services and generation busy hook
    jsr generation_busy_install
    jsr atari_platform_services_install
    jsr platform_services_assert_installed
    jmp restart_entry

// ============================================================
// Low Resident Modules (< $4000)
// ============================================================
.const DUNGEON_GEN_BUSY = 1

#import "config.s"
#import "reu_stub.s"
#import "screen.s"
#import "sound.s"
#import "input.s"
#import "storage.s"
#import "save_stream.s"
#import "item_catalog_a8.s"
.segment RuntimeBanked
#import "legal.s"
.segment Default
#import "../../core/ui_help_command.s"
#import "monster_catalog_a8.s"
// find_special_room only: item placement calls it with OVL.CHEST loaded
// (the rest of special_rooms.s is in OVL.GEN, 2026-11-08).
#import "../../core/special_rooms_find.s"

// ============================================================
// atari_install_vectors & exit_trampoline (< $4000)
// ============================================================
atari_install_vectors:
    php
    sei
    lda #$00
    sta NMIEN
    sta IRQEN
    lda #PORTB_GAME_RAM
    sta PORTB
    lda #<atari_nmi_handler
    sta $fffa
    lda #>atari_nmi_handler
    sta $fffb
    lda #<exit_trampoline
    sta $fffc
    lda #>exit_trampoline
    sta $fffd
    lda #<atari_irq_handler
    sta $fffe
    lda #>atari_irq_handler
    sta $ffff
    sta NMIRES
    lda #$c0                // Enable VBI ($40) + DLI ($80)
#if ATARI8_CARTRIDGE
    sta atari_nmi_enabled
#endif
    sta NMIEN
    lda #$c0                // Enable POKEY Break/Backspace ($80) + keyboard IRQ ($40)
    sta IRQEN
    plp
    rts

.label hal_irq_install_runtime = atari_install_vectors

exit_trampoline:
    sei
    lda #$00
#if ATARI8_CARTRIDGE
    sta atari_nmi_enabled
#endif
    sta NMIEN
    sta IRQEN
    sta DMACTL
    jsr hal_sound_init
    lda #$00
    sta OS_WARMST
    lda #PORTB_OS_ROM
    sta PORTB
    sta NMIRES
#if ATARI8_CARTRIDGE
    sta CART_BANK_SELECT       // Remap Bank 0 so cold reset re-enters cartridge
#endif
    jmp OS_COLDSV

low_helpers_end:
.assert "Help and legal controllers stay outside the overlay window", cmd_show_help_view < MAP_BASE && tramp_ui_legal_display >= $f000, true
.assert "Low helpers stay below $4000", low_helpers_end <= $4000, true

// ============================================================
// Resident Core Gameplay Modules ($1400-$C0FF)
// ============================================================
#import "build/version_strings.inc"
#import "../../core/color.s"
#import "../../core/rng.s"
#import "../../core/math.s"
#import "../../core/tables.s"
#import "../../core/item_defs.s"
// Equipment effect flags ride OVL.DTH behind hal_player_recalc_pflags
// (Phase 4, frees ~400 B from RuntimeBanked $F000-$FFFA). OVL.DTH hosts
// item_exchange, whose recalculation then needs no overlay swap on an 800XL
// disk (a swap and its reload are two ~3 s loads).
#define PFLAGS_SEGMENT_CUSTOM
#define PLAYER_RECALC_PFLAGS_EXTERNAL
.macro PflagsSegment() {
    .segment DeathOverlay
}
.macro PflagsRestoreSegment() {
    .segment Default
}
// Move roll_enchantment's equipment branch into OVL.CHS behind tramp_re_equip,
// beside item_spawn_level_gen and pick_item_type_overlay: floor-item and chest
// generation roll enchantments per item with zero overlay swaps on 800XL disk.
// ITEM.CAT is preloaded before jumping to re_equip_entry.
#define RE_EQUIP_SEGMENT_CUSTOM
.macro ReEquipSegment() {
    .segment ChestOverlay
}
.macro ReEquipRestoreSegment() {
    .segment Default
}
.label re_equip_entry = tramp_re_equip
#import "../../core/player.s"
#import "../../core/ui_messages.s"
.segment HighResident
.pc = PLATFORM_ITEM_NAME_DECODE_BUF_BASE "item_name_decode_buf"
atari_item_name_decode_buf: .fill 48, 0     // core item_name_decode_buf (config.s)
high_resident_end:
.assert "HighResident fits before $E000", high_resident_end <= $e000, true
.assert "HighResident ends before config.s's fixed high-RAM buffers", high_resident_end <= PLATFORM_COMBAT_MSG_BUF_BASE, true
.segment Default
// The status words and status_state in RuntimeBanked: the Poisoned indicator
// (2026-11-10) left Default 36 bytes over MAP_BASE.
#define STATUS_TEXT_SEGMENT_CUSTOM
.macro StatusTextSegment() {
    .segment RuntimeBanked
}
.macro StatusTextRestoreSegment() {
    .segment Default
}
#import "../../core/ui_status.s"
#import "../../core/ui_help_clear.s"
.segment RuntimeBanked
#import "../../core/generation_busy.s"
.segment Default
// put_stat_val in Default, where the low buffers moved to PRNBUF and high
// RAM (memory.s, config.s) left room; the $F000 runtime is full.
#import "../../core/stat_display.s"
#import "../../core/huffman.s"
#import "../../core/dungeon_data.s"
#define CMD_JAM_EXTERNAL
#define CMD_JAM_SEGMENT_CUSTOM
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
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
.macro ChestSearchSegment() {
    .segment Default
}
.macro ChestSearchRestoreSegment() {
    .segment Default
}
#define CHEST_ROUTING_ENABLED
#define PLACE_SECRETS_EXTERNAL
#define PICKER_IN_CHEST_OVERLAY
#import "../../core/dungeon_features.s"
#import "../../core/chest_search.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../core/monster.s"
#import "../../core/recall_defs.s"
#import "../../core/monster_catalog.s"
#import "../../core/tier_manager.s"
#define ASSET_LOAD_PROMPT_EXTERNAL  // in RuntimeBanked below: Default is full
#import "../commodore/common/overlay.s"
#undef ASSET_LOAD_PROMPT_EXTERNAL
#import "../../core/monster_ai.s"
#import "../../core/scene_dirty.s"
#import "../../core/scene_mat_tile.s"
#import "../../core/scene_force.s"
#import "../../core/recall.s"
#import "../../core/monster_magic.s"
.macro ChestSummonsSegment() {
    .segment Default
}
.macro ChestSummonsRestoreSegment() {
    .segment Default
}
// item_pickup runs from OVL.ITM behind tramp_item_pickup: the weight limit
// (inv_add_carried) left Default no room for it.
.macro ItemPickupSegment() {
    .segment ItemActionsOverlay
}
.macro ItemPickupRestoreSegment() {
    .segment Default
}
#define ITEM_SPAWN_IN_GEN_OVERLAY
.macro ItemSpawnSegment() {
    .segment ChestOverlay
}
.macro ItemSpawnRestoreSegment() {
    .segment Default
}
#import "../../core/item.s"
#import "../../core/chest_summons.s"
.macro ChestLootSegment() {
    .segment ChestOverlay
}
.macro ChestLootRestoreSegment() {
    .segment Default
}
.macro ChestFixtureSegment() {
    .segment ChestOverlay
}
.macro ChestFixtureRestoreSegment() {
    .segment Default
}
#import "../../core/chest_loot.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
// Potions of gain stat: imported here first (#importonce) so the quaff
// dispatch's own import is empty and the code stays out of a full Default.
.segment RuntimeBanked
#import "../../core/eff_gain_stat.s"
.segment Default
#define PLAYER_RECALC_EQUIPMENT_EXTERNAL
#define PLAYER_ITEM_COMMANDS_EXTERNAL
#import "../../core/player_items.s"
#import "../../core/player_recalc_equipment.s"
#undef PLAYER_ITEM_COMMANDS_EXTERNAL
#undef PLAYER_RECALC_EQUIPMENT_EXTERNAL
#import "../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
// Stone-to-Mud rides OVL.SPELL beside its only callers, the spell table and the
// Phase 3 wand dispatch (2026-11-11: the VMS wands left Default 10 bytes past
// $C100).
#define WALL_TO_MUD_SEGMENT_CUSTOM
.macro WallToMudSegment() {
    .segment SpellOverlay
}
.macro WallToMudRestoreSegment() {
    .segment Default
}
#import "../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
.segment ModalMiscOverlay
#import "../../core/player_magic_levelup.s"
#import "../../core/player_magic_tail.s"
.segment Default
#import "../../core/player_magic.s"

#import "dungeon_render.s"
#import "../../core/dungeon_los.s"
.macro PlayerMoveRestoreResidentSegment() {
    .segment Default
}
.macro PlayerMoveLookSegment() {
    .segment ModalMiscOverlay
}
#define PLAYER_LOOK_EXTERNAL
#import "../../core/player_move.s"
.macro PlayerRunInitializeSegment() {
    .segment RuntimeBanked
}
.macro PlayerRunRestoreResidentSegment() {
    .segment Default
}
#define PLAYER_RUN_INITIALIZE_EXTERNAL
#import "../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL

run_initialize:
    jmp run_initialize_impl
.assert "Atari 8-bit runner initialization implementation stays banked", run_initialize_impl >= $F000 && run_initialize_impl < $FFFA, true
.assert "Atari 8-bit runner initialization entry stays resident", run_initialize < MAP_BASE, true

#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../../core/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../../core/projectile.s"
#define MON_ATK_ACID_EXTERNAL
#import "../../core/monster_attack.s"
#undef MON_ATK_ACID_EXTERNAL
#import "../../core/turn.s"
.segment RuntimeBanked
#import "../../core/store_data.s"
#import "../../core/runtime_ui_strings.s"
#import "../../core/monster_acid.s"
.segment Default
#import "../commodore/common/compat/io_kernal_consts.s"
#define SAVE_STATE_SEGMENT_CUSTOM
.macro SaveStateResidentSegment() {
    .segment Default
}
.macro SaveStateRestoreSegment() {
    .segment StorageOverlay
}
#define SAVE_PROBE_SEGMENT_CUSTOM
.macro SaveProbeResidentSegment() {
    .segment Default
}
.macro SaveProbeRestoreSegment() {
    .segment StorageOverlay
}
.segment StorageOverlay
#import "../shared/save.s"
.segment Default
#import "hal/storage_policy.s"
#define WIZARD_PROMPT_HELPERS_EXTERNAL
#import "../../core/wizard.s"
#undef WIZARD_PROMPT_HELPERS_EXTERNAL
#define DISARM_COMMAND_EXTERNAL
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#import "hal/storage.s"

// ============================================================
// Title Loop & Platform Lifecycle Services
// ============================================================
restart_entry:
    jsr detect_machine
    lda #0
    sta reu_present
    sta reu_banks
    sta reu_size_kb
    sta reu_size_kb + 1
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #$ff
    sta save_slot_index
    lda #COL_LGREY
    sta zp_text_color
    jsr tramp_title_draw_screen
    jsr msg_init
    jsr title_draw_menu

title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
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
    bcs title_enter_menu
    jsr disk_prompt_game
    jsr disk_prompt_game_required
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

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
    jsr disk_prompt_save
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
    jsr save_select_slot_prompt
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game
    jsr disk_prompt_game_required
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jsr disk_prompt_game_required
    jmp title_enter_menu

atari_banked_fname:
    .text "ATARI.BNK"
.const atari_banked_fname_len = 9
#if ATARI8_CARTRIDGE
.assert "Runtime filename length matches cartridge reader", CART_RUNTIME_NAME_LEN == atari_banked_fname_len, true
#endif

init_load_banked:
    lda #atari_banked_fname_len
    ldx #<atari_banked_fname
    ldy #>atari_banked_fname
    jsr asset_load_retry        // not asset_load_required: its prompt lives in
    bcc !ok+                    // the RuntimeBanked code this very load brings
!halt:
    inc COLBK
    jmp !halt-
!ok:
    rts

#if !ATARI8_CARTRIDGE
init_xe_preload:
    lda xe_present
    beq !done+
    lda #0
    sta xe_loading_count

    // Preload the monster catalog's records (130XE slots 10..13 and 15)
    jsr a8_catalog_xe_preload

    // Preload all 12 cached gameplay overlays (OVL_STARTUP..OVL_STORAGE,
    // populates 130XE slots 0..9, 16..17; cold OVL.TTL is uncached;
    // TITLE.DAT populates slot 14 on title draw)
    ldx #1
!ovl_loop:
    stx xe_preload_idx
    jsr xe_show_progress
    lda xe_preload_idx
    jsr overlay_load
    ldx xe_preload_idx
    inx
    cpx #hal_platform_overlay_count
    bcc !ovl_loop-

    lda #OVL_NONE
    sta current_overlay
!done:
    rts

xe_show_progress:
    inc xe_loading_count
    lda #12
    jsr hal_screen_clear_row
    lda #12
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<xe_loading_prefix
    sta zp_ptr0
    lda #>xe_loading_prefix
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda xe_loading_count
    jsr screen_put_decimal
    lda #$2f
    jsr hal_screen_put_char
    lda #A8_CATALOG_SLOT_COUNT + hal_platform_overlay_count - 1
    jsr screen_put_decimal
    lda #<xe_loading_suffix
    sta zp_ptr0
    lda #>xe_loading_suffix
    sta zp_ptr0_hi
    jmp hal_screen_put_string

xe_preload_idx:   .byte 0
xe_loading_count: .byte 0
plus4_title_art_cached: .byte 0
boot_loading_str:  .text "LOADING MORIA8..." ; .byte 0
xe_loading_prefix: .text "MORIA8 LOADING " ; .byte 0
xe_loading_suffix: .text " PLEASE WAIT" ; .byte 0
#else
plus4_title_art_cached: .byte 0
boot_loading_str:  .text "LOADING MORIA8..." ; .byte 0
#endif

atari_platform_main_loop_begin:
atari_platform_vector_reassert:
atari_platform_runtime_resync:
plus4_bank_ram:
    lda #PORTB_GAME_RAM
    sta PORTB
    rts

hal_overlay_post_reload:
    sei
    jsr atari_install_vectors
    jmp plus4_bank_ram

atari_platform_services_install:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<atari_platform_main_loop_begin
    sta platform_main_loop_begin_api + 1
    sta platform_vector_reassert_api + 1
    sta platform_runtime_resync_api + 1
    lda #>atari_platform_main_loop_begin
    sta platform_main_loop_begin_api + 2
    sta platform_vector_reassert_api + 2
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

.label overlay_load_no_kernal = overlay_load

tramp_title_draw_screen:
    lda #OVL_TITLE
    jsr overlay_load_no_kernal
    bcs !done+
    jsr title_draw_overlay_screen
    jmp tramp_sr_epilogue
!done:
    rts

save_prepare_slot_prompt:
    lda #OVL_STORAGE
    jmp overlay_load_no_kernal

save_select_slot_prompt:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !slot_done+
    jsr disk_require_save_media
    bcc !slot_media_ok+
    jsr disk_prepare_selected_save_media
    bcc !slot_prepared+
    lda #$ff
    sta save_slot_index
    jmp atari_platform_runtime_resync
!slot_prepared:
    lda #1
    sta disk_setup_done
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
!slot_media_ok:
    jsr save_select_slot_prompt_impl
    jmp atari_platform_runtime_resync
!slot_done:
    rts

save_game:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !sg_ovl_fail+
    jsr save_game_impl
    jmp atari_platform_runtime_resync
!sg_ovl_fail:
    clc
    rts

load_game:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !lg_ovl_fail+
    jsr load_game_impl
    jmp atari_platform_runtime_resync
!lg_ovl_fail:
    lda #LOAD_RESULT_IOERR
    sta load_result
    clc
    rts

#import "build/trampolines/atari8_trampolines.inc"

// tramp_sr_gen_loaded — OVL.GEN in the $E000 window (asks for the program
// disk until it loads). Clobbers: A, X
tramp_sr_gen_loaded:
    lda current_overlay
    cmp #OVL_DUNGEON_GEN
    beq !tsgl_loaded+
    ldx #OVL_DUNGEON_GEN - 1
    jsr overlay_load_disk
    lda #OVL_DUNGEON_GEN
    sta current_overlay
!tsgl_loaded:
    rts

tramp_spawn_nest_gold:
    lda #RT_NEST
    jsr find_special_room
    bcc !tsng_done+
    lda #<spawn_nest_gold
    ldy #>spawn_nest_gold
    jmp a8_swap_gen
!tsng_done:
    rts

item_spawn_level:
    jsr item_init_floor
    lda zp_player_dlvl
    beq !isl_town+
    lda #<item_spawn_level_gen
    ldy #>item_spawn_level_gen
    jmp a8_disp_chs
!isl_town:
    rts

hal_player_recalc_pflags:
    lda #<player_recalc_pflags_equipment
    ldy #>player_recalc_pflags_equipment
    jmp a8_swap_dth

a8_caller_ovl_restore: .byte 0

// Shared A/Y dispatcher for OVL_HELP commands (wear/eat/quaff) whose '?'
// inventory picker swaps in OVL_UI via tramp_ui_inv_select_display.
a8_disp_hlp_piw:
    sta !adhp_jsr+ + 1
    sty !adhp_jsr+ + 2
    lda #OVL_HELP
    sta a8_caller_ovl_restore
    jsr overlay_load_no_kernal
    bcs !adhp_fail+
!adhp_jsr:
    jsr $0000
    ldx #0
    stx a8_caller_ovl_restore
    jmp tramp_sr_epilogue
!adhp_fail:
    lda #0
    sta a8_caller_ovl_restore
    clc
    jmp tramp_sr_epilogue

tramp_ui_inv_select_display:
    lda piw_return_overlay
    bne !tuisd_go+
    lda a8_caller_ovl_restore
    sta piw_return_overlay
!tuisd_go:
    lda #<ui_inv_select_display
    ldy #>ui_inv_select_display
    jmp a8_disp_ui

// Shared ovl_sr dispatch tails -> a8_ovl_sr_common (every OVL_* ID != 0).
a8_disp_mdl:
    ldx #OVL_MODAL_MISC
    bne a8_ovl_sr_common
a8_disp_ui:
    ldx #OVL_UI
    bne a8_ovl_sr_common
a8_disp_dth:
    ldx #OVL_DEATH
    bne a8_ovl_sr_common
a8_disp_hlp:
    ldx #OVL_HELP
    bne a8_ovl_sr_common
a8_disp_itm:
    ldx #OVL_ITEMS
    bne a8_ovl_sr_common
a8_disp_chs:
    ldx #OVL_CHEST
    bne a8_ovl_sr_common
a8_disp_spl:
    ldx #OVL_SPELL
    bne a8_ovl_sr_common
a8_disp_hom:
    ldx #OVL_HOME
    bne a8_ovl_sr_common
a8_disp_sto:
    ldx #OVL_STORAGE
    bne a8_ovl_sr_common
a8_disp_ttl:
    ldx #OVL_TITLE
a8_ovl_sr_common:
    sta !aosc_jsr+ + 1
    sty !aosc_jsr+ + 2
    txa
    jsr overlay_load_no_kernal
    bcs !aosc_done+
!aosc_jsr:
    jsr $0000
    jmp tramp_sr_epilogue
!aosc_done:
    rts

// Shared overlay swap-and-restore tails -> a8_ovl_swap_restore (re-entrant;
// preserves returned A and Carry; load failure returns A=0 with Carry set).
a8_swap_dth:
    ldx #OVL_DEATH
    bne a8_ovl_swap_restore
a8_swap_mdl:
    ldx #OVL_MODAL_MISC
    bne a8_ovl_swap_restore
a8_swap_hom:
    ldx #OVL_HOME
    bne a8_ovl_swap_restore
a8_swap_chs:
    ldx #OVL_CHEST
    bne a8_ovl_swap_restore
a8_swap_ui:
    ldx #OVL_UI
    bne a8_ovl_swap_restore
a8_swap_hlp:
    ldx #OVL_HELP
    bne a8_ovl_swap_restore
a8_swap_spl:
    ldx #OVL_SPELL
    bne a8_ovl_swap_restore
a8_swap_sto:
    ldx #OVL_STORAGE
    bne a8_ovl_swap_restore
a8_swap_ttl:
    ldx #OVL_TITLE
    bne a8_ovl_swap_restore
a8_swap_gen:
    ldx #OVL_DUNGEON_GEN
a8_ovl_swap_restore:
    sta !aosr_jsr+ + 1
    sty !aosr_jsr+ + 2
    txa
    cmp current_overlay
    bne !aosr_load+
!aosr_jsr:
    jmp $0000
!aosr_load:
    ldy current_overlay
    tya
    pha
    txa
    jsr overlay_load_no_kernal
    bcs !aosr_fail+
    jsr !aosr_jsr-
    pha
    php
    tsx
    lda $0103,x
    beq !aosr_done+
    jsr overlay_load_no_kernal
!aosr_done:
    plp
    pla
    tax
    pla
    txa
    rts
!aosr_fail:
    pla
    lda #0
    rts

tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+
    jsr item_cat_decode_ego
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #COMBAT_MSG_BUF_LAST
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
!teas_done:
    rts

tramp_roll_ego_type:
    sta !tret_call+ + 1
    lda #<!tret_call+
    ldy #>!tret_call+
    ldx #OVL_STORAGE
    bne a8_ovl_swap_restore
!tret_call:
    lda #$00
    jmp roll_ego_type

tramp_help_cmd_body:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcc !thcb_loaded+
    clc
    jmp tramp_sr_epilogue
!thcb_loaded:
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr help_cmd_body
    jmp tramp_sr_epilogue

tramp_eff_ext_eat:
    lda #<eff_ext_eat_piw
    ldy #>eff_ext_eat_piw
    jmp !teeg_go+
tramp_eff_ext_quaff:
    lda #<eff_ext_quaff_piw
    ldy #>eff_ext_quaff_piw
!teeg_go:
    sta !teeg_jsr+ + 1
    sty !teeg_jsr+ + 2
    lda current_overlay
    pha
    lda #OVL_TITLE
    jsr overlay_load_no_kernal
    bcs !teeg_fail+
!teeg_jsr:
    jsr $ffff
!teeg_fail:
    pla
    beq !teeg_done+
    jmp overlay_load_no_kernal
!teeg_done:
    rts

tramp_door_pick_roll:
    lda current_overlay
    pha
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !load_failed+
    jsr door_pick_roll
    pla
    beq !tdpr_done+
    php
    jsr overlay_load_no_kernal
    plp
!tdpr_done:
    rts
!load_failed:
    pla
    clc
    rts

chest_dispatch:
    sta chest_disp_jmp + 1
    sty chest_disp_jmp + 2
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
chest_disp_jmp:
    jmp $0000
!done:
    rts

tramp_ui_identify:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_identify_print
    jsr tier_restore_after_overlay
!done:
    jmp tramp_sr_epilogue

tramp_disk_setup:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !done+
    jsr disk_setup_menu
    bcc !done+
    jsr disk_prompt_game_required
    sec
!done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !done+
    jmp disk_prepare_selected_save_media
!done:
    rts

tramp_store_enter:
    lda zp_store_idx
    cmp #STORE_HOME
    beq !home+
    lda #OVL_TOWN
    jsr overlay_load
    bcs !done+
    jsr store_enter
    jmp !done+
!home:
    lda #OVL_HOME
    jsr overlay_load
    bcs !done+
    jsr home_enter
!done:
    jmp tramp_sr_epilogue

tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    bcs !done+
    jsr player_create
!done:
    jmp tramp_sr_epilogue

tramp_game_over_disk_setup:
    jsr tramp_disk_setup
    bcs !done+
    jsr disk_prompt_game
    jsr disk_prompt_game_required
    lda #1
    sta disk_setup_done
    jsr tramp_game_over_prepare
    clc
!done:
    rts

tramp_game_over_disk_setup_failed:
    jsr disk_prompt_game
    jmp disk_prompt_game_required

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
    jsr overlay_load
    bcc !tgo_ovl_ok+
    jsr disk_prompt_game_required
    jmp !tgo_load_overlay-
!tgo_ovl_ok:
    rts

tramp_game_over:
    jsr tramp_game_over_prepare
    jmp tramp_game_over_run

tramp_winner_royal:
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !done+
    jsr winner_apply_retirement_bonus_overlay
    jmp royal_screen
!done:
    rts

game_over_prompt:
    jsr disk_prompt_game_required
    jmp restart_entry

program_end:
.print "Atari 8-bit Resident Default: " + (program_end - $0c00) + " bytes at $0C00-$" + toHexString(program_end)
.assert "Program fits below MAP_BASE ($C100)", program_end <= MAP_BASE, true
.assert "Save probe helpers and state stay resident", save_block_lo < MAP_BASE && save_magic < MAP_BASE && save_version_supported < MAP_BASE && save_file_exists < MAP_BASE && save_restore_channels < MAP_BASE, true
#if ATARI8_CARTRIDGE
.assert "Cartridge entry address matches resident entry", entry_main == CART_ENTRY, true
.assert "Overlay order matches cartridge descriptors", OVL_STARTUP == 1 && OVL_TOWN == 2 && OVL_DEATH == 3 && OVL_DUNGEON_GEN == 4 && OVL_HELP == 5 && OVL_UI == 6 && OVL_ITEMS == 7 && OVL_SPELL == 8 && OVL_MODAL_MISC == 9 && OVL_CHEST == 10 && OVL_HOME == 11 && OVL_STORAGE == 12 && OVL_TITLE == 13 && OVL_TITLE == CART_OVERLAY_COUNT, true
.assert "Post-boot MAP_BASE lies outside cartridge ROM window", MAP_BASE >= CART_WINDOW_END, true
#endif

// ============================================================
// RuntimeBanked ($F000-$FFF9)
// ============================================================
.segment RuntimeBanked
#if !ATARI8_CARTRIDGE
    // Asks for the program disk when a required load keeps failing. Safe
    // here: every load that reaches it comes after ATARI.BNK is in place.
    #import "../commodore/common/asset_load_prompt.s"
#endif
    #define EGO_ARMOUR_SEGMENT_CUSTOM
    .macro EgoArmourSegment() {
        .segment StorageOverlay
    }
    .macro EgoArmourRestoreSegment() {
        .segment RuntimeBanked
    }
    #define EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    .macro EgoArmourDataSegment() {
        .segment StorageOverlay
    }
    .macro EgoArmourDataRestoreSegment() {
        .segment RuntimeBanked
    }
    #import "../../core/ego_items.s"
    #undef EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    #undef EGO_ARMOUR_SEGMENT_CUSTOM
    #import "../../core/item_desc_banked.s"

// ============================================================
// disk_prompt_save / disk_prompt_game — 1-drive swap prompts in RuntimeBanked
// ============================================================
#if ATARI8_CARTRIDGE
disk_prompt_save:
disk_prompt_game:
    clc
    rts
#else
disk_prompt_save:
    lda disk_mode
    cmp #1
    bne !dps_done+
    lda disk_setup_done
    cmp #2
    bcc !dps_prompt+
    lda #1
    sta disk_setup_done
    clc
    rts
!dps_prompt:
    lda #<ds_save_str
    ldy #>ds_save_str
    jmp dsm_show_swap_prompt
!dps_done:
    clc
    rts

disk_prompt_game:
    lda disk_mode
    cmp #1
    bne !dpg_done+
    jsr disk_note_program_media_current
    lda #<ds_game_str
    ldy #>ds_game_str
    jmp dsm_show_swap_prompt
!dpg_done:
    clc
    rts

dsm_show_swap_prompt:
    sta zp_ptr0
    sty zp_ptr0_hi
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #12
    sta zp_cursor_col
    jsr hal_screen_put_string
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    lda #12
    sta zp_cursor_row
    lda #13
    sta zp_cursor_col
    jsr hal_screen_put_string
    jsr input_get_modal_dismiss_key
    jsr hal_screen_clear
    clc
    rts
#endif

banked_code_end:
.print "Atari 8-bit Banked runtime: " + (banked_code_end - $f000) + " bytes at $F000-$" + toHexString(banked_code_end)
.assert "Banked code fits before CPU vectors ($FFFA)", banked_code_end <= $fffa, true

// ============================================================
// Overlays ($E000-$EFFF)
// ============================================================
.segment TownOverlay
    #import "../../core/store.s"
    #import "../../core/ui_store.s"
inv_add_carried:
    :InvAddCarriedBody()
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $f000, true

.segment StartupOverlay
    #import "../../core/background_data.s"
    #import "../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $f000, true

.segment DeathOverlay
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
    #import "../../core/ui_recall.s"
    #import "../../core/player_magic_earthquake.s"
    #import "../../core/item_exchange.s"
    #import "../../core/item_drop_cold.s"
    #import "../../core/load_resume_reset_cold.s"
ovl_death_end:
.assert "Game-over tail runs in OVL.DTH", tramp_game_over_run >= $e000 && tramp_game_over_run < ovl_death_end, true
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $f000, true

.segment ModalMiscOverlay
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
    ldy #>wizard_bad_value_str
    jsr msg_print_ay
    jmp wizard_prompt_clear_digits

wizard_bad_value_str:
    .text "BAD" ; .byte 0
    #import "../../core/player_destroy_area.s"
ovl_modal_misc_end:
.assert "Wizard prompt helpers run in OVL.MDL", wizard_prompt_clear_digits >= $e000 && wizard_bad_value_str < ovl_modal_misc_end, true
.print "Modal-misc overlay: " + (ovl_modal_misc_end - $e000) + " bytes at $E000-$" + toHexString(ovl_modal_misc_end)
.assert "Modal-misc overlay fits in $E000-$EFFF", ovl_modal_misc_end <= $f000, true

.segment SpellOverlay
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_DETECT_EFFECTS_EXTERNAL
    #define PMX_DESTROY_AREA_EXTERNAL
    #define PMX_MAP_AREA_EXTERNAL
    #define PMX_MAP_AREA_TRAMPOLINE
    #import "../../core/player_magic_slow_runtime.s"
    #define PMU_TURN_FEEDBACK_ONLY
    #import "../../core/player_magic_turn_banked.s"
    #undef PMU_TURN_FEEDBACK_ONLY
    #import "../../core/player_magic_execute_overlay.s"
    #undef PMX_MAP_AREA_TRAMPOLINE
    #undef PMX_MAP_AREA_EXTERNAL
    #undef PMX_DESTROY_AREA_EXTERNAL
    #undef PMX_DETECT_EFFECTS_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
    #import "../../core/player_magic_display.s"
    #import "../../core/spell_effects_overlay.s"
    #import "../../core/eff_identify_prompt_cold.s"
    #import "../../core/eff_detect_evil_cold.s"
    #define SCROLL_P3_EXISTING_OWNER
    #define SCROLL_P3_NEW_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_NEW_OWNER
    #undef SCROLL_P3_EXISTING_OWNER
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $e000) + " bytes at $E000-$" + toHexString(ovl_spell_end)
.assert "Spell overlay fits in $E000-$EFFF", ovl_spell_end <= $f000, true

.segment HelpOverlay
    #import "../../core/ui_help_title.s"
    #import "../../core/ui_help_data.s"
    #import "../../core/ui_help_page2_data.s"
    #import "../../core/ui_help.s"
    #import "../../core/ui_help_cmd_cold.s"
    #import "../../core/ui_character.s"
    #import "../../core/ui_equipment.s"
    #define PLAYER_RECALC_EQUIPMENT_EXTERNAL
    #import "../../core/player_item_commands.s"
    #undef PLAYER_RECALC_EQUIPMENT_EXTERNAL
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $f000, true

.segment UiOverlay
    #import "../../core/ui_identify.s"
    #import "../../core/ui_inventory.s"
    #import "../../core/spell_names.s"
    #import "../../core/player_magic_select_overlay.s"
    #import "../../core/player_gain_spell_impl.s"
    #import "../../core/player_magic_browse_cold.s"
    #import "../../core/player_magic_learn_op.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $f000, true

.segment ItemActionsOverlay
    #define SCROLL_P3_ROUTER_ENABLED
    #import "../../core/item_actions_overlay.s"
    #import "../../core/ranged_fire.s"
    #import "../../core/throw.s"
    #import "../../core/bash.s"
    #import "../../core/calc_dig_cold.s"
    #import "../../core/tunnel.s"
inv_add_carried_items:
    :InvAddCarriedBody()
ovl_items_end:
.assert "item_pickup runs in OVL.ITM", item_pickup >= $e000 && item_pickup < ovl_items_end, true
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $f000, true

.segment DungeonGenOverlay
    #import "../../core/special_rooms.s"
    #import "../../core/dungeon_gen.s"
ovl_gen_end:
.assert "Special rooms run in OVL.GEN", assign_special_room >= $e000 && spawn_nest_gold < ovl_gen_end, true
.assert "find_special_room is outside the $E000 window (the CHEST-loaded picker calls it)", find_special_room < MAP_BASE, true
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $f000, true

.segment ChestOverlay
    #import "../../core/chest.s"
    #import "../../core/disarm.s"
    #import "../../core/disarm_helpers.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $e000) + " bytes at $E000-$" + toHexString(ovl_chest_end)
.assert "Chest overlay fits in $E000-$EFFF", ovl_chest_end <= $f000, true

.segment HomeOverlay
    #import "../../core/ui_home_text.s"
    #import "../../core/ui_home.s"
    #import "../../core/eff_item_p1.s"
    #import "../../core/door_open_close_cold.s"
ovl_home_end:
.assert "Home overlay runs home_enter in $E000-$EFFF", home_enter >= $e000 && home_enter < ovl_home_end && home_draw_screen >= $e000 && home_draw_screen < ovl_home_end, true
.print "Home overlay: " + (ovl_home_end - $e000) + " bytes at $E000-$" + toHexString(ovl_home_end)
.assert "Home overlay fits in $E000-$EFFF", ovl_home_end <= $f000, true

.segment StorageOverlay
    #import "../commodore/common/save_slot_menu.s"
    #import "disk_setup_atari.s"
    #import "../../core/item_refresh_known_cold.s"
ovl_storage_end:
.assert "Storage overlay hosts save/load, slot menu, and disk setup", save_game_impl >= $e000 && save_game_impl < ovl_storage_end && load_game_impl >= $e000 && load_game_impl < ovl_storage_end && save_select_slot_prompt_impl >= $e000 && save_select_slot_prompt_impl < ovl_storage_end && disk_setup_menu >= $e000 && disk_setup_menu < ovl_storage_end, true
.print "Storage overlay: " + (ovl_storage_end - $e000) + " bytes at $E000-$" + toHexString(ovl_storage_end)
.assert "Storage overlay fits in $E000-$EFFF", ovl_storage_end <= $f000, true

.segment TitleOverlay
title_str:
    .text "MORIA8 ATARI XL/XE" ; .byte 0
    #import "../commodore/common/title_screen.s"
    #import "../../core/eff_item_extended.s"
    #import "../../core/store_restock_overlay.s"
    #import "../../core/player_magic_map.s"
    #import "../../core/starting_kit_cold.s"
title_show_sysinfo:
    lda #COL_DGREY
    sta zp_text_color
    lda #23
    sta zp_cursor_row
#if ATARI8_CARTRIDGE
    lda #8
    sta zp_cursor_col
    lda #<atari_sysinfo_cart_str
    sta zp_ptr0
    lda #>atari_sysinfo_cart_str
    sta zp_ptr0_hi
    jmp hal_screen_put_string

atari_sysinfo_cart_str: .text "ATARI XL/XE  128KB CART" ; .byte 0
#else
    lda xe_present
    bne !xe_str+
    lda #12
    sta zp_cursor_col
    lda #<atari_sysinfo_xl_str
    sta zp_ptr0
    lda #>atari_sysinfo_xl_str
    sta zp_ptr0_hi
    jmp hal_screen_put_string
!xe_str:
    lda #11
    sta zp_cursor_col
    lda #<atari_sysinfo_xe_str
    sta zp_ptr0
    lda #>atari_sysinfo_xe_str
    sta zp_ptr0_hi
    jmp hal_screen_put_string

atari_sysinfo_xl_str: .text "ATARI 800XL  64KB" ; .byte 0
atari_sysinfo_xe_str: .text "ATARI 130XE  128KB" ; .byte 0
#endif

title_draw_overlay_screen:
    jsr title_load_and_draw
    jsr title_clear_below_menu
    jmp title_show_sysinfo
ovl_title_end:
.assert "Title overlay hosts title_load_and_draw in $E000-$EFFF", title_load_and_draw >= $e000 && title_load_and_draw < ovl_title_end && title_draw_overlay_screen >= $e000 && title_draw_overlay_screen < ovl_title_end, true
.print "Title overlay: " + (ovl_title_end - $e000) + " bytes at $E000-$" + toHexString(ovl_title_end)
.assert "Title overlay fits in $E000-$EFFF", ovl_title_end <= $f000, true

// Cold legal modal: workspace is reserved but not emitted to disk.
.segment LegalOverlay
#import "../../core/ui_legal.s"
#if ATARI8_CARTRIDGE
#import "legal_stream.s"
#else
#import "../shared/legal_disk_stream.s"
#endif
legal_code_end:
.assert "Legal code stays below its modal workspace", legal_code_end <= legal_zp_save, true
.assert "Legal ZP snapshot stays below input cache", legal_zp_save + $8e <= legal_input_cache, true
.segment Default
.assert "Atari 8-bit cast/pray shell stays resident (< MAP_BASE) while spell failure and inventory '?' co-locate in OVL.SPL / OVL.UI", player_cast_spell < MAP_BASE && player_pray < MAP_BASE && pm_build_known_list_from_book < MAP_BASE && calc_spell_failure >= $e000 && calc_spell_failure < ovl_spell_end && ui_inv_select_display >= $e000 && ui_inv_select_display < ovl_ui_end && ui_char_display >= $e000 && ui_char_display < ovl_help_end, true
#if !ATARI8_CARTRIDGE
.assert "130XE Slot 0 covers OVL.STA", (ovl_start_end - $e000) <= XE_SLOT0_PAGES * 256, true
.assert "130XE Slot 1 covers OVL.TWN", (ovl_town_end - $e000) <= XE_SLOT1_PAGES * 256, true
.assert "130XE Slot 2 covers OVL.DTH", (ovl_death_end - $e000) <= XE_SLOT2_PAGES * 256, true
.assert "130XE Slot 3 covers OVL.GEN", (ovl_gen_end - $e000) <= XE_SLOT3_PAGES * 256, true
.assert "130XE Slot 4 covers OVL.HLP", (ovl_help_end - $e000) <= XE_SLOT4_PAGES * 256, true
.assert "130XE Slot 5 covers OVL.UI",  (ovl_ui_end - $e000) <= XE_SLOT5_PAGES * 256, true
.assert "130XE Slot 6 covers OVL.ITM", (ovl_items_end - $e000) <= XE_SLOT6_PAGES * 256, true
.assert "130XE Slot 7 covers OVL.SPL", (ovl_spell_end - $e000) <= XE_SLOT7_PAGES * 256, true
.assert "130XE Slot 8 covers OVL.MDL", (ovl_modal_misc_end - $e000) <= XE_SLOT8_PAGES * 256, true
.assert "130XE Slot 9 covers OVL.CHS", (ovl_chest_end - $e000) <= XE_SLOT9_PAGES * 256, true
.assert "130XE Slot 16 covers OVL.HOM", (ovl_home_end - $e000) <= XE_SLOT16_PAGES * 256, true
.assert "130XE Slot 17 covers OVL.STO", (ovl_storage_end - $e000) <= XE_SLOT17_PAGES * 256, true
.print "Atari 130XE extended RAM: " + XE_TOTAL_USED_PAGES + "/" + XE_TOTAL_PAGES + " pages used, " + XE_TOTAL_FREE_PAGES + " free (" + (XE_TOTAL_FREE_PAGES * 256) + " B at Bank 3 $" + toHexString(XE_BANK3_FREE_HI) + "00-$7FFF)"
#endif
