// main.s — Moria8 for Atari 8-Bit (64 KB 800XL/65XE + 128 KB 130XE)
//
// Assembled with Kick Assembler.
// Boot loader (boot.s at $0800) loads MORIA8.RES ($0C00-$C0FF) and jumps to
// entry_main ($0C00). See docs/ATARI8_MEMORY_CONTRACT.md.

.encoding "screencode_mixed"

#define ATARI8
#define ATARI8_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_REQUIRES_MEDIA_PROBE
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
.segmentdef HelpOverlay        [outPrg=OVL_OUT + "/OVL.HLP", start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay          [outPrg=OVL_OUT + "/OVL.UI",  start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/OVL.ITM", start=$e000, min=$e000, max=$efff]
.segmentdef SpellOverlay       [outPrg=OVL_OUT + "/OVL.SPL", start=$e000, min=$e000, max=$efff]
.segmentdef ChestOverlay       [outPrg=OVL_OUT + "/OVL.CHS", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay  [outPrg=OVL_OUT + "/OVL.GEN", start=$e000, min=$e000, max=$efff]
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

    // Detect 130XE extended RAM (64 KB vs 128 KB)
    jsr xe_detect

    // Load RuntimeBanked payload (ATARI.BNK -> $F000-$FFF9)
    jsr init_load_banked

    // Preload hot assets into 130XE extended RAM if present
    jsr init_xe_preload

    // Install platform lifecycle services and generation busy hook
    jsr generation_busy_install
    jsr atari_platform_services_install
    jsr platform_services_assert_installed
    jmp restart_entry

// tramp_dig_ability — pinned low for common tunnel code.
tramp_dig_ability:
    jmp calc_dig_ability

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
    sta NMIEN
    lda #$c0                // Enable POKEY Break/Backspace ($80) + keyboard IRQ ($40)
    sta IRQEN
    plp
    rts

.label hal_irq_install_runtime = atari_install_vectors
.label plus4_install_ram_irq_vectors = atari_install_vectors

exit_trampoline:
    sei
    lda #$00
    sta NMIEN
    sta IRQEN
    sta DMACTL
    jsr hal_sound_init
    lda #$00
    sta OS_WARMST
    lda #PORTB_OS_ROM
    sta PORTB
    sta NMIRES
    jmp OS_COLDSV

low_helpers_end:
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
#import "../../core/player.s"
#import "../../core/ui_messages.s"
.segment HighResident
.pc = PLATFORM_ITEM_NAME_DECODE_BUF_BASE "item_name_decode_buf"
atari_item_name_decode_buf: .fill 48, 0     // core item_name_decode_buf (config.s)
high_resident_end:
.assert "HighResident fits before $E000", high_resident_end <= $e000, true
.segment Default
#import "../../core/ui_status.s"
.segment RuntimeBanked
#import "../../core/ui_help_clear.s"
#import "../../core/stat_display.s"
#import "../../core/generation_busy.s"
.segment Default
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
#import "../../core/player_items.s"
#import "../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
.segment ModalMiscOverlay
#import "../../core/player_magic_levelup.s"
#import "../../core/player_magic_tail.s"
#import "../../core/player_magic_display.s"
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
#import "../../core/monster_attack.s"
#import "../../core/turn.s"
.segment RuntimeBanked
#import "../../core/store_data.s"
#import "../../core/runtime_ui_strings.s"
.segment Default
#import "../commodore/common/compat/io_kernal_consts.s"
#import "../shared/save.s"
#import "hal/storage_policy.s"
#import "../commodore/common/title_screen.s"
#import "../../core/wizard.s"
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
    jsr title_load_and_draw
    jsr title_clear_below_menu
    jsr msg_init
    jsr title_show_sysinfo
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
    lda #8                  // 24-char title_menu_str centered in cols 2..37: 2 + (36-24)/2 = 8
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

init_xe_preload:
    lda xe_present
    beq !done+
    lda #0
    sta xe_loading_count

    // Preload all 4 monster tiers (populates 130XE slots 10..13)
    ldx #1
!tier_loop:
    stx current_tier
    jsr xe_show_progress
    jsr tier_load_disk
    ldx current_tier
    inx
    cpx #5
    bcc !tier_loop-
    jsr tier_invalidate_state

    // Preload all 10 phase overlays (populates 130XE slots 0..9;
    // TITLE.DAT populates slot 14 on title draw)
    ldx #1
!ovl_loop:
    stx xe_preload_idx
    jsr xe_show_progress
    lda xe_preload_idx
    jsr overlay_load
    ldx xe_preload_idx
    inx
    cpx #11
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
    lda #14
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

title_str:
    .text "MORIA8 ATARI XL/XE" ; .byte 0

title_show_sysinfo:
    lda #COL_DGREY
    sta zp_text_color
    lda #23
    sta zp_cursor_row
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

tramp_reu_show_status:
    rts

atari_platform_main_loop_begin:
atari_platform_vector_reassert:
atari_platform_runtime_resync:
plus4_bank_ram:
    lda #PORTB_GAME_RAM
    sta PORTB
    rts

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

save_prepare_slot_prompt:
    lda #OVL_HELP
    jmp overlay_load_no_kernal

save_select_slot_prompt:
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

tramp_do_look:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr do_look
!done:
    jmp tramp_sr_epilogue

.label tramp_level_generate = level_generate
.label tramp_assign_special_room = assign_special_room
.label tramp_vault_seal_entrance = vault_seal_entrance
.label tramp_spawn_special_room_monsters = spawn_special_room_monsters
tramp_spawn_nest_gold:
    // pick_item_type leaves the chest overlay (PICKER_IN_CHEST_OVERLAY) in the
    // $E000 window, and spawn_nest_gold calls random_floor_in_room in the
    // dungeon-generation overlay: load it back first, as the Apple IIe and CX16
    // trampolines do (M5b round 33: nest gold placed off the map corrupted code)
    lda current_overlay
    cmp #OVL_DUNGEON_GEN
    beq !tsng_loaded+
    ldx #OVL_DUNGEON_GEN - 1
    jsr overlay_load_disk       // asks for the program disk until it loads
    lda #OVL_DUNGEON_GEN
    sta current_overlay
!tsng_loaded:
    jmp spawn_nest_gold
.label tramp_find_special_room = find_special_room
.label tramp_sr_epilogue = atari_platform_runtime_resync

tramp_calc_spell_failure:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr calc_spell_failure
!done:
    rts

.label tramp_roll_ego_type = roll_ego_type

tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+
    jsr ego_get_suffix_ptr
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

.label tramp_ego_apply_damage = ego_apply_damage
.label tramp_ego_get_ac_bonus = ego_get_ac_bonus

tramp_ui_help_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_char_display:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_char_display
!done:
    jmp tramp_sr_epilogue

tramp_item_init_identification:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_init_identification
!done:
    jmp tramp_sr_epilogue

tramp_magic_recalc_mana:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr magic_recalc_mana
!done:
    jmp tramp_sr_epilogue

tramp_magic_check_new_spells:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr magic_check_new_spells
!done:
    jmp tramp_sr_epilogue

tramp_ui_inv_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_inv_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_inv_select_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_inv_select_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_equip_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_equip_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_equip_select_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_equip_select_display
!done:
    jmp tramp_sr_epilogue

tramp_ui_recall:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_recall_display
!done:
    jmp tramp_sr_epilogue

tramp_item_gain_spell:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_gain_spell
!done:
    jmp tramp_sr_epilogue

tramp_item_read_scroll:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_read_scroll
!done:
    jmp tramp_sr_epilogue

tramp_item_aim_wand:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_aim_wand
!done:
    jmp tramp_sr_epilogue

tramp_item_use_staff:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_use_staff
!done:
    jmp tramp_sr_epilogue

tramp_item_refuel:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_refuel
!done:
    jmp tramp_sr_epilogue

tramp_item_exchange:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_exchange
!done:
    jmp tramp_sr_epilogue

tramp_ranged_fire:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ranged_fire
!done:
    jmp tramp_sr_epilogue

tramp_throw_item:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr throw_item
!done:
    jmp tramp_sr_epilogue

tramp_bash_command:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr bash_command
!done:
    jmp tramp_sr_epilogue

tramp_disarm_command:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr disarm_command
!done:
    jmp tramp_sr_epilogue

tramp_cmd_jam:
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
    jsr door_jam_command
!done:
    jmp tramp_sr_epilogue

tramp_door_pick_roll:
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !load_failed+
    jmp door_pick_roll
!load_failed:
    clc
    rts

tramp_chest_open:
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
    jsr chest_open_command
!done:
    jmp tramp_sr_epilogue

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

tramp_player_tunnel:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr player_tunnel
!done:
    jmp tramp_sr_epilogue

tramp_spell_list_display:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr spell_list_display
!done:
    jmp tramp_sr_epilogue

tramp_spell_execute_selected:
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !done+
    jsr spell_execute_selected
!done:
    jmp tramp_sr_epilogue

tramp_eff_earthquake:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !done+
    jsr eff_earthquake
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !fatal+
!done:
    rts

tramp_eff_destroy_area:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr da_devastate
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !fatal+
!done:
    rts
!fatal:
    jmp entry_main

tramp_reveal_floorplan:
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !done+
    jsr eff_reveal_floorplan
!done:
    jmp tramp_sr_epilogue

tramp_ui_identify:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_identify_print
    jsr tier_restore_after_overlay
!done:
    jmp tramp_sr_epilogue

tramp_ui_wizard_display:
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_wizard_display
!done:
    jmp tramp_sr_epilogue

tramp_disk_setup:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jsr disk_setup_menu
    bcc !done+
    jsr disk_prompt_game_required
    sec
!done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !done+
    jmp disk_prepare_selected_save_media
!done:
    rts

store_overlay_preamble:
    lda #OVL_TOWN
    jmp overlay_load

tramp_store_init_all:
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
    jsr store_init_all
!done:
    jmp tramp_sr_epilogue

tramp_store_restock_all:
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
    jsr store_restock_all
!done:
    jmp tramp_sr_epilogue

tramp_store_enter:
    jsr store_overlay_preamble
    bcs !done+
    jsr store_enter
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

// ============================================================
// RuntimeBanked ($F000-$FFF9)
// ============================================================
.segment RuntimeBanked
    // Asks for the program disk when a required load keeps failing. Safe
    // here: every load that reaches it comes after ATARI.BNK is in place.
    #import "../commodore/common/asset_load_prompt.s"
    #import "../../core/special_rooms.s"
    #import "../../core/ego_items.s"
    #import "../../core/ui_home.s"
    #import "../../core/item_desc_banked.s"

// ============================================================
// disk_prompt_save / disk_prompt_game — 1-drive swap prompts in RuntimeBanked
// ============================================================
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

banked_code_end:
.print "Atari 8-bit Banked runtime: " + (banked_code_end - $f000) + " bytes at $F000-$" + toHexString(banked_code_end)
.assert "Banked code fits before CPU vectors ($FFFA)", banked_code_end <= $fffa, true

// ============================================================
// Overlays ($E000-$EFFF)
// ============================================================
.segment TownOverlay
    #import "../../core/store.s"
    #import "../../core/ui_store.s"
    #import "../../core/ui_home_text.s"
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
    #import "../../core/ui_recall.s"
    #import "../../core/player_magic_earthquake.s"
ovl_death_end:
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
    #import "../../core/player_destroy_area.s"
ovl_modal_misc_end:
.print "Modal-misc overlay: " + (ovl_modal_misc_end - $e000) + " bytes at $E000-$" + toHexString(ovl_modal_misc_end)
.assert "Modal-misc overlay fits in $E000-$EFFF", ovl_modal_misc_end <= $f000, true

.segment SpellOverlay
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_DETECT_EFFECTS_EXTERNAL
    #define PMX_DESTROY_AREA_EXTERNAL
    #import "../../core/player_magic_slow_runtime.s"
    #define PMU_TURN_FEEDBACK_ONLY
    #import "../../core/player_magic_turn_banked.s"
    #undef PMU_TURN_FEEDBACK_ONLY
    #import "../../core/player_magic_execute_overlay.s"
    #undef PMX_DESTROY_AREA_EXTERNAL
    #undef PMX_DETECT_EFFECTS_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
    #import "../../core/spell_effects_overlay.s"
    #define SCROLL_P3_EXISTING_OWNER
    #define SCROLL_P3_NEW_OWNER
    #import "../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_NEW_OWNER
    #undef SCROLL_P3_EXISTING_OWNER
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $e000) + " bytes at $E000-$" + toHexString(ovl_spell_end)
.assert "Spell overlay fits in $E000-$EFFF", ovl_spell_end <= $f000, true

.segment HelpOverlay
    #import "../../core/ui_help_data.s"
    #import "../../core/ui_help_page2_data.s"
    #import "../../core/ui_help.s"
    #import "../../core/ui_inventory.s"
    #import "../../core/ui_equipment.s"
    #import "../commodore/common/save_slot_menu.s"
    #import "disk_setup_atari.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $f000, true

.segment UiOverlay
    #import "../../core/ui_character.s"
    #import "../../core/ui_identify.s"
    #import "../../core/spell_names.s"
    #import "../../core/player_magic_select_overlay.s"
    #import "../../core/player_gain_spell_impl.s"
    #import "../../core/player_magic_learn_op.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $f000, true

.segment ItemActionsOverlay
    #define SCROLL_P3_ROUTER_ENABLED
    #import "../../core/item_actions_overlay.s"
    #import "../../core/item_exchange.s"
    #import "../../core/ranged_fire.s"
    #import "../../core/throw.s"
    #import "../../core/bash.s"
    #import "../../core/disarm.s"
    #import "../../core/disarm_helpers.s"
    #import "../../core/tunnel.s"
ovl_items_end:
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $f000, true

.segment DungeonGenOverlay
    #import "../../core/dungeon_gen.s"
ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $f000, true

.segment ChestOverlay
    #import "../../core/chest.s"
    // Store init/restock: transition-only (new game, town re-entry), moved
    // from the full items overlay for store stacking (2026-10-25).
    #import "../../core/store_restock_overlay.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $e000) + " bytes at $E000-$" + toHexString(ovl_chest_end)
.assert "Chest overlay fits in $E000-$EFFF", ovl_chest_end <= $f000, true
