// main.s — Entry point for Moria8 C64/C128
//
// BASIC stub at $0801 with SYS entry.
// Saves BASIC ZP state, disables BASIC ROM, runs game,
// restores state and exits cleanly to BASIC.

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
// Overlay segments: produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
#define C64_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define C64_PRODUCT_IRQ_VECTOR_RUNTIME
#define PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME
.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")
.segmentdef StartupOverlay    [outPrg=OVL_OUT + "/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg=OVL_OUT + "/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg=OVL_OUT + "/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef ModalMiscOverlay      [outPrg=OVL_OUT + "/ovl.modal", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items", start=$e000, min=$e000, max=$efff]
.segmentdef SpellOverlay      [outPrg=OVL_OUT + "/ovl.spell", start=$e000, min=$e000, max=$efff]
.segmentdef ChestOverlay      [outPrg=OVL_OUT + "/ovl.chest", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",   start=$e000, min=$e000, max=$efff]
.segmentdef SaveOverlay       [outPrg=OVL_OUT + "/ovl.save",  start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeBanked     [outPrg=OVL_OUT + "/64.bank",   start=$f000, min=$f000, max=$fffa]
.segmentdef InitTail          [outPrg=OVL_OUT + "/64.init",   start=$c000, min=$c000, max=$cfff]

// Krill's Loader r194 resident (raw-load only build, assembled for $F000).
// Emitted into RuntimeBanked before any other import can emit into the
// segment, so link order pins it at $F000 where the resident was assembled.
// Visible whenever KERNAL is banked out ($01=$34/$35), same as the rest of
// the payload. Entry point is at the base of the resident.
.segment RuntimeBanked
krill_resident_base:
#if !C64_UNIT_TEST
    .import binary "../../../build/c64/krill-resident.bin"
#else
    // Unit tests never exercise the fast loader; keep a size-identical hole
    // so label offsets match the shipping payload.
    .fill 382, 0
#endif
.label krill_loadraw = krill_resident_base
.label krill_loadraw_bounded = krill_resident_base + 4
.label krill_uninstall = krill_resident_base + 369
.label krill_resident_end = *
.assert "Krill bounded resident is 382 bytes", krill_resident_end - krill_resident_base, 382
// krill_load_file — Load a file via the Krill resident.
// Input:  X/Y = 0-terminated PETSCII filename (storage HAL name tables
//         already carry a trailing zero past their counted length).
//         Caller must have $F000 visible ($01=$34/$35).
// Output: carry clear = success, carry set = load error.
// Pinned immediately after the resident; config.s calls it through the
// KRILL_LOAD_FILE address constant (asserted in the init tail below, where
// config.s symbols are visible).
krill_load_file:
    jsr krill_loadraw
    jmp krill_load_file_cleanup
krill_load_file_bounded:
    jsr krill_loadraw_bounded
krill_load_file_cleanup:
    php
    pha
    lda #$03                    // VIC-II bank 0, IEC released; Krill contract:
    sta $dd00                   // $DD00 upper 6 bits must be 0 while installed
    pla
    plp
    rts
.segment Default

#import "hal/storage_policy.s"
#import "../common/save_slot_policy.s"

// Huffman data placement: resident on this platform.
.macro HuffmanDataSegment() {
    .segment Default
}

// Cast/pray cores stay resident on this platform.
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
    // One-shot new-game identification init runs from the items overlay so
    // the resident image keeps room for the chest catalog rows.
    .segment ItemActionsOverlay
}
.macro ChestRouteSegment() {
    .segment Default
}
.macro ChestRouteRestoreSegment() {
    .segment Default
}
.macro WizardGenExecSegment() {
    .segment Default
}
.macro WizardGenExecRestoreSegment() {
    .segment Default
}
.macro ItemInitIdentRestoreSegment() {
    .segment Default
}

.pc = $0801 "BASIC Stub"
:BasicUpstart2(entry)

// ============================================================
// Imports — order matters: labels must be defined before use
// ============================================================
.pc = $080e "Program"

// Bootstrap — MUST live below $A000 so BASIC's SYS can reach it
// before BASIC ROM is banked out.
entry:
    dec $01                 // BASIC entry has $37: bank out BASIC, keep KERNAL/I/O.
#if C64_TEST_SCRIPTED_SLOT2_LOAD_PRODUCT
c64_test_slot2_load_wait_for_harness:
    jmp c64_test_slot2_load_wait_for_harness
c64_test_slot2_load_resume:
#endif
    cld
    jmp entry_main          // Now code past $A000 is accessible

// Exit trampoline — MUST live below $A000 because it banks BASIC
// ROM back in. If this ran from $A000+ the CPU would start executing
// BASIC ROM the instant we set bit 0 of $01.
exit_trampoline:
    lda #0
    sta $d418               // Silence SID
    jsr restore_zp          // Must run BEFORE banking BASIC in (buffer may be under BASIC ROM)
    sei
    // Restore default IRQ vector — our handler (irq_no_blink) is in the
    // $A000-$BFFF region, hidden once BASIC ROM is banked in.
    lda #$31
    sta $0314
    lda #$ea
    sta $0315
    lda $01
    ora #%00000001          // Set bit 0 (LORAM) — bank in BASIC ROM
    sta $01
    cli
    lda #$0e
    sta $d020               // Restore default border (light blue)
    lda #$06
    sta $d021               // Restore default background (blue)
    lda $d018
    ora #%00000010          // Lowercase mode (BASIC default)
    sta $d018
    lda #$03                // VIC-II bank 0, IEC lines released, upper bits 0
    sta $dd00
    lda #$93                // PETSCII clear screen
    jsr $ffd2               // KERNAL CHROUT
    jmp ($a002)             // BASIC warm-start (works for both SYS and chain-load)

#import "hal/storage_title_name.s"

c64_marker_magic_low:
    .byte $4d, $38, $53, $41, $56, $45
c64_init_command_low:
    .byte $49, $30
c64_marker_name_low:
    .byte $40
    .byte $30, $3a
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44
    .byte $2c, $53, $2c
c64_marker_name_mode_low:
    .byte $57
.label c64_marker_name_low_len = * - c64_marker_name_low

// Resident helper for C64 save-disk marker creation. This must stay below
// $A000: it runs while KERNAL and BASIC ROM are banked in.
c64_disk_marker_write_resident:
    lda #2
    sta disk_status
    lda #$57
    sta c64_marker_name_mode_low
    lda #$36
    sta $01
    cli
    lda #hal_storage_marker_file_num
    jsr $ffc3
    lda #c64_marker_name_low_len
    ldx #<c64_marker_name_low
    ldy #>c64_marker_name_low
    jsr $ffbd
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_write
    jsr $ffba
    jsr $ffc0
    bcs !cdmw_close+
!cdmw_open_ok:
    ldx #hal_storage_marker_file_num
    jsr $ffc9
    bcs !cdmw_close+
    ldx #0
!cdmw_write:
    txa
    pha
    lda c64_marker_magic_low,x
    jsr $ffd2
    pla
    tax
    inx
    cpx #hal_storage_marker_magic_len
    bcc !cdmw_write-
    clc
!cdmw_close:
    php
    jsr $ffcc
    lda #hal_storage_marker_file_num
    jsr $ffc3
    lda #$34
    sta $01
    jsr c64_restore_vic_bank0_after_serial
    plp
    bcs !cdmw_done+
    lda #0
    sta disk_status
!cdmw_done:
    rts

#import "../../../core/zeropage.s"

c64_disk_call_saved_bank: .byte 0
ultimate_model_present: .byte 0
.label c64_hw_flags = ultimate_model_present
c64u_turbo_depth: .byte 0
c64u_turbo_prev: .byte 0
.const C64_HW_C64U        = $01
.const C64_HW_TURBO_AVAIL = $02
.const C64_HW_TURBO_ON    = $04
.const C64U_TURBO_CONTROL = $d031
.const C64U_TURBO_DISABLED = $ff
.const C64U_TURBO_NORMAL  = $00
.const C64U_TURBO_FAST    = $0f
.const KERNAL_CURRENT_DEVICE = $ba
#if C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
c64_test_save_media_fail_armed: .byte 0
#endif
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
c64_test_restart_after_save_armed: .byte 0
#endif
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
c64_test_krill_resume_stage: .byte 0
#endif
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
c64_test_disk_setup_single_drive_return_armed: .byte 0
#endif
#if C64_TEST_SCRIPTED_DISK_SETUP_THEN_LOAD_PRODUCT
c64_test_disk_setup_then_load_started: .byte 0
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
.label c64_test_fast_map_marker = $ceff
.label c64_test_kernal_chrin_entry = $ffcf
.label c64_test_kernal_load_entry = $ffd5
c64_test_single_drive_load_return_resume_low:
    lda #$36                // Monitor attach/resume may expose BASIC ROM.
    sta $01
    jmp title_load_game
c64_test_single_drive_load_return_loaded_low:
    jmp c64_test_single_drive_load_return_loaded_low
#endif
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
c64_test_load_then_save_new_empty_resume_low:
    lda #$36                // Monitor attach/resume may expose BASIC ROM.
    sta $01
    jmp title_load_game
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
c64_test_single_drive_fresh_save_resume_low:
    lda #$36                // Monitor attach/resume may expose BASIC ROM.
    sta $01
    jmp c64_test_single_drive_fresh_save_before_save
#endif

c64_disk_call:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda $0104,x
    sta zp_vol_2
    clc
    adc #2
    sta $0104,x
    lda $0105,x
    sta zp_vol_3
    bcc !cdc_target+
    inc $0105,x
!cdc_target:
    ldy #1
    lda (zp_vol_2),y
    sta !cdc_jsr+ + 1
    iny
    lda (zp_vol_2),y
    sta !cdc_jsr+ + 2
    lda $01
    sta c64_disk_call_saved_bank
    lda #$36
    sta $01
    cli
    pla
    tay
    pla
    tax
    pla
!cdc_jsr:
    jsr $ffff
    php
    pha
    sei
    lda c64_disk_call_saved_bank
    sta $01
    pla
    plp
    sei
    rts

c64_disk_setnam:
    jsr c64_disk_call
    .word $ffbd
    rts

c64_disk_setlfs:
    jsr c64_disk_call
    .word $ffba
    rts

c64_disk_open:
    jsr c64_disk_call
    .word $ffc0
    rts

c64_disk_close:
    jsr c64_disk_call
    .word $ffc3
    rts

c64_disk_chkin:
    jsr c64_disk_call
    .word $ffc6
    rts

c64_disk_chkout:
    jsr c64_disk_call
    .word $ffc9
    rts

c64_disk_chrin:
    jsr c64_disk_call
    .word $ffcf
    rts

c64_disk_chrout:
    jsr c64_disk_call
    .word $ffd2
    rts

c64_disk_readst:
    jsr c64_disk_call
    .word $ffb7
    rts

c64_disk_clrchn:
    jsr c64_disk_call
    .word $ffcc
    rts

c64_disk_marker_present:
    lda #1
    sta disk_status
    lda $01
    pha
#if C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
    lda c64_test_save_media_fail_armed
    beq !cdmp_test_normal+
    lda #2
    sta disk_status
    jmp !cdmp_done+
!cdmp_test_normal:
#endif
    lda #$52
    sta c64_marker_name_mode_low
    lda #$36
    sta $01
    cli
    jsr $ffcc
    lda #hal_storage_check_file_num
    jsr $ffc3
    lda #c64_marker_name_low_len - 1
    ldx #<(c64_marker_name_low + 1)
    ldy #>(c64_marker_name_low + 1)
    jsr $ffbd
    lda #hal_storage_check_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr $ffba
    jsr $ffc0
    bcs !cdmp_close+
!cdmp_open_ok:
    ldx #hal_storage_check_file_num
    jsr $ffc6
    bcs !cdmp_close+
!cdmp_chkin_ok:
    jsr $ffcf
    cmp #$4d
    bne !cdmp_marker_fail+
    jsr $ffcf
    cmp #$38
    bne !cdmp_marker_fail+
    dec disk_status
!cdmp_close:
    jsr $ffcc
    lda #hal_storage_check_file_num
    jsr $ffc3
    jmp !cdmp_done+
!cdmp_marker_fail:
    jmp !cdmp_close-
!cdmp_done:
    jsr c64_restore_vic_bank0_after_serial
    pla
    sta $01
    sei
    lda disk_status
    cmp #1
    rts

// tramp_dig_ability — pinned low for common tunnel code.
tramp_dig_ability:
    jmp calc_dig_ability

// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_mixed"

.const DUNGEON_GEN_BUSY = 1

#import "../../../core/zeropage.s"
#import "memory.s"
#import "hal/layout.s"
#import "hal/lifecycle_policy.s"
#define REU_STASH_OVERLAYS_EXTERNAL
#define REU_LOAD_ALL_TIERS_EXTERNAL
#import "../common/reu.s"
#undef REU_LOAD_ALL_TIERS_EXTERNAL
#undef REU_STASH_OVERLAYS_EXTERNAL
#import "screen.s"
#import "../../../core/color.s"
#import "config.s"
#define C64_PRODUCT_SOUND_UPDATE_FROM_INPUT
#import "input.s"
#import "../../../core/rng.s"
#import "../../../core/math.s"
#import "../../../core/tables.s"
#import "../../../core/item_defs.s"
#import "../../../core/player.s"
#import "../../../core/ui_messages.s"
#import "../../../core/ui_status.s"
#define GENERATION_BUSY_INSTALL_EXTERNAL
#import "../../../core/generation_busy.s"
#undef GENERATION_BUSY_INSTALL_EXTERNAL
#import "../../../core/stat_display.s"
#import "../../../core/sound.s"
#import "../../../core/huffman.s"
#import "../../../core/dungeon_data.s"
// The jam command handler parks in the items overlay with the other
// directional action commands (resident budget).
#define CMD_JAM_EXTERNAL
#define CMD_JAM_SEGMENT_CUSTOM
.macro CmdJamSegment() {
    .segment ItemActionsOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
// The locked-door pick roll needs the effective-disarm formula; it parks in
// the chest overlay with chest_disarm_skill (resident budget).
#define DOOR_PICK_EXTERNAL
.macro DoorPickSegment() {
    .segment ChestOverlay
}
.macro DoorPickRestoreSegment() {
    .segment Default
}
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
// place_secrets parks in the GEN overlay (only generation calls it), funding
// the monster door engine in Default.
#define PLACE_SECRETS_EXTERNAL
// Chest loot generator + the shared item picker park in the CHEST overlay
// on this platform (GEN is full); gameplay drops reach the picker through the
// resident pick_item_type wrapper, fulfillment loads OVL_CHEST.
#define PICKER_IN_CHEST_OVERLAY
.macro ChestSearchSegment() {
    .segment Default
}
.macro ChestSearchRestoreSegment() {
    .segment Default
}
#define CHEST_ROUTING_ENABLED
#import "../../../core/dungeon_features.s"
#import "../../../core/chest_search.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../../core/monster.s"
#import "../../../core/tier_manager.s"

// Overlay state is platform-owned so product/test variant layout changes
// cannot place these bytes inside later resident code.
current_overlay: .byte 0
ovl_reu_start_lo: .fill hal_platform_overlay_count + 1, 0
ovl_reu_start_hi: .fill hal_platform_overlay_count + 1, 0
ol_target:        .byte 0

#define OVERLAY_LOAD_PROMPT_GAME
#import "../common/overlay.s"
#undef OVERLAY_LOAD_PROMPT_GAME
#import "../../../core/monster_ai.s"
#import "../../../core/scene_dirty.s"
#import "../../../core/scene_mat_tile.s"
#import "../../../core/scene_force.s"
#import "../../../core/recall.s"
#import "../../../core/monster_magic.s"
.macro ChestSummonsSegment() {
    .segment Default
}
.macro ChestSummonsRestoreSegment() {
    .segment Default
}
#import "../../../core/item.s"
#import "../../../core/chest_summons.s"
// Step-13 chest loot: latch + resident handoff stay in Default; the generator
// (chest_generate_loot) parks in the CHEST overlay with the picker it uses.
.macro ChestLootSegment() {
    .segment ChestOverlay
}
.macro ChestLootRestoreSegment() {
    .segment Default
}
// Scripted chest-open fixture rides the CHEST overlay on C64: GEN has no
// room beside place_secrets and the loot generator.
.macro ChestFixtureSegment() {
    .segment ChestOverlay
}
.macro ChestFixtureRestoreSegment() {
    .segment Default
}
#import "../../../core/chest_loot.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../../../core/player_items.s"
#import "../../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../core/player_magic_state.s"
#import "../../../core/player_magic_state_ops.s"
// Park level-up magic recomputation (cold, level-up-only) in ModalMisc:
// pre-importing here makes player_magic.s's own tail imports no-ops.
// combat.s reaches them via tramp_magic_* (HAL_PLATFORM_LEVELUP_MAGIC_USES_TRAMPOLINE).
.segment ModalMiscOverlay
#import "../../../core/player_magic_levelup.s"
#import "../../../core/player_magic_tail.s"
// Spell-failure calc is cold (per cast attempt); parks here to fund the
// state-aware monster door engine. player_magic.s reaches it via
// tramp_calc_spell_failure (HAL_PLATFORM_CAST_FAILURE_USES_TRAMPOLINE).
#import "../../../core/player_magic_display.s"
.segment Default
#import "../../../core/player_magic.s"

#import "dungeon_render.s"
#import "../../../core/dungeon_los.s"
.macro PlayerMoveRestoreResidentSegment() {
    .segment Default
}
.macro PlayerMoveLookSegment() {
    .segment ModalMiscOverlay
}
#define PLAYER_LOOK_EXTERNAL
#import "../../../core/player_move.s"
.macro PlayerRunInitializeSegment() {
    .segment RuntimeBanked
}
.macro PlayerRunRestoreResidentSegment() {
    .segment Default
}
#define RUN_MONSTER_VISIBILITY_EXTERNAL
#define PLAYER_RUN_INITIALIZE_EXTERNAL
// player_run uses pm_live_occ_x/y defined by the preceding player_move import.
#import "../../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL
#undef RUN_MONSTER_VISIBILITY_EXTERNAL
#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../../../core/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../../../core/projectile.s"
#import "../../../core/monster_attack.s"
#import "../../../core/turn.s"
#import "../../../core/store_data.s"
#import "../../../core/runtime_ui_strings.s"
#import "../common/compat/io_kernal_consts.s"
#import "../../shared/save.s"
#import "../common/disk_swap.s"
#import "../common/title_screen.s"
#import "../../../core/wizard.s"
#define DISARM_COMMAND_EXTERNAL
#import "../../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#import "hal/storage.s"

c64_storage_read_command_status:
    lda #2
    sta disk_status
    lda #0
    tax
    tay
    jsr c64_disk_setnam
    lda #15
    ldx disk_prompt_device
    tay
    jsr c64_disk_setlfs
    jsr c64_disk_open
    bcs !cdrs_close+
    ldx #15
    jsr c64_disk_chkin
    bcs !cdrs_close+
    jsr c64_disk_chrin
    cmp #$30
    beq !cdrs_check_0x+
    cmp #$32
    beq !cdrs_check_26+
    cmp #$36
    beq !cdrs_check_62+
    cmp #$37
    beq !cdrs_check_7x+
    jmp !cdrs_close+
!cdrs_check_0x:
    jsr c64_disk_chrin
    cmp #$32
    beq !cdrs_wrong_media+
    lda #0
    sta disk_status
    beq !cdrs_close+
!cdrs_check_26:
    jsr c64_disk_chrin
    cmp #$36
    bne !cdrs_close+
    lda #26
    sta disk_status
    bne !cdrs_close+
!cdrs_check_62:
    jsr c64_disk_chrin
    cmp #$32
    bne !cdrs_close+
    jmp !cdrs_wrong_media+
!cdrs_check_7x:
    jsr c64_disk_chrin
    cmp #$32
    beq !cdrs_disk_full+
    cmp #$33
    beq !cdrs_wrong_media+
    cmp #$34
    bne !cdrs_close+
    lda #74
    sta disk_status
    jmp !cdrs_close+
!cdrs_disk_full:
    lda #72
    sta disk_status
    jmp !cdrs_close+
!cdrs_wrong_media:
    lda #1
    sta disk_status
!cdrs_close:
    jsr c64_disk_clrchn
    lda #15
    jsr c64_disk_close
    rts
// ============================================================
// Entry point
// ============================================================
entry_main:
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp
    jsr disk_reset_session_state
    jsr c64_install_ram_irq_vectors
#if C64_TEST_BOOT_HANDOFF
c64_test_runtime_vectors_ready:
#endif

    // BASIC ROM already banked out by bootstrap above

    // Load banked runtime payload to $F000 before any $F000 trampoline calls.
    jsr init_load_banked
#if C64_TEST_BOOT_HANDOFF
c64_test_p6_complete:
#endif
    // Patch reu_show_status: RTS → JMP tramp_reu_show_status
    lda #$4c                    // JMP absolute opcode
    sta reu_show_status
    lda #<tramp_reu_show_status
    sta reu_show_status + 1
    lda #>tramp_reu_show_status
    sta reu_show_status + 2

    jsr generation_busy_install
    jsr platform_services_install64
    jsr platform_services_assert_installed
    jsr input_lock_charset_switch

    // Select lowercase/uppercase character set (52 letter symbols)
    // Bit 1 of $D018 selects character set: 0=uppercase+graphics, 1=lowercase+uppercase
    lda $d018
    ora #%00000010          // Set bit 1 → lowercase + uppercase
    sta $d018
    // Also set via $D016 to ensure proper state
    // (Actually $D018 bit 1 is sufficient on C64)

    // Set border and background to black
    lda #COL_BLACK
    sta $d020               // Border
    sta $d021               // Background

    jsr ultimate_detect
    jsr c64u_turbo_detect

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine
    jsr reu_detect
    jsr reu_detect_extended_c64
    jsr tier_init
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    lda c64_test_restart_after_save_armed
    beq !cached_resume_test_done+
c64_test_before_cached_krill_resume:
#endif
    jsr krill_resume
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    lda c64_test_restart_after_save_armed
    beq !cached_resume_test_done+
c64_test_after_cached_krill_resume:
!cached_resume_test_done:
#endif
    jsr platform_runtime_resync_c64
    lda #$ff
    sta save_slot_index
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    lda c64_test_restart_after_save_armed
    beq !restart_test_done+
c64_test_after_save_restart_start:
    lda #0
    sta c64_test_restart_after_save_armed
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT
    .label c64_test_kernal_load_entry = $ffd5
    lda #OVL_HELP
    jsr overlay_load
    bcc !post_save_overlay_loaded+
    jmp c64_test_save_write_fail_input_sym
!post_save_overlay_loaded:
c64_test_post_save_krill_overlay_pass:
    jmp c64_test_post_save_krill_overlay_pass
#endif
!restart_test_done:
#endif
    // Set default text color
    lda #COL_LGREY
    sta zp_text_color

    // Title is a full-screen view; clear before KERNAL LOAD starts printing
    // "SEARCHING...", then title_load_and_draw clears again after the load.
    jsr title_clear_full_screen

    // Load and display title (clears screen internally after KERNAL LOAD)
    jsr title_load_and_draw

    // The title art stream owns the art, not the rows below the menu.
    jsr title_clear_below_menu

    // Title re-entry must rebuild message/title UI state from scratch after
    // any failed load attempt, not just branch back into the old loop.
    jsr msg_init

    // Show system info on row 23 (machine type, KERNAL rev, REU)
    jsr title_show_sysinfo

    jsr title_draw_menu

#if C64_TEST_SCRIPTED_FASTLOAD_PRODUCT
    // Fastloader smoke: reaching this point means the title art (T64) and the
    // startup overlay were loaded via Krill when krill_active is set (or via
    // KERNAL in the fallback case). Harness asserts .krill_active.
c64_test_fastload_pass_sym:
#endif
#if C64_TEST_SCRIPTED_RETIREMENT_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
    jsr tramp_winner_royal
c64_test_retirement_unexpected_return:
    jmp c64_test_retirement_unexpected_return
c64_test_retirement_pass_sym:
    jmp c64_test_retirement_pass_sym
c64_test_retirement_fail_sym:
    jmp c64_test_retirement_fail_sym
#endif

#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda c64_test_disk_setup_single_drive_return_armed
    beq !disk_setup_return_test_not_armed+
    lda #0
    sta c64_test_disk_setup_single_drive_return_armed
c64_test_after_disk_setup_single_drive_return:
    jmp c64_test_after_disk_setup_single_drive_return
!disk_setup_return_test_not_armed:
#endif

#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #1
    sta disk_setup_done
c64_test_single_drive_load_return_wait_for_harness:
    jmp c64_test_single_drive_load_return_wait_for_harness
c64_test_single_drive_load_return_before_load:
    jmp title_load_game
#endif
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #1
    sta disk_setup_done
c64_test_load_then_save_new_empty_wait_for_harness:
    jmp c64_test_load_then_save_new_empty_wait_for_harness
c64_test_load_then_save_new_empty_before_load:
    jmp title_load_game
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
c64_test_single_drive_load_wrong_media_wait_for_harness:
    jmp c64_test_single_drive_load_wrong_media_wait_for_harness
c64_test_single_drive_load_wrong_media_before_load:
    jmp title_load_game
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
c64_test_single_drive_load_corrupt_wait_for_harness:
    jmp c64_test_single_drive_load_corrupt_wait_for_harness
c64_test_single_drive_load_corrupt_before_load:
    jmp title_load_game
#endif
#if C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
    sta c64_test_save_media_fail_armed
c64_test_save_media_fail_wait_for_harness:
    jmp c64_test_save_media_fail_wait_for_harness
c64_test_save_media_fail_before_save:
    jsr save_game
c64_test_save_media_fail_unexpected_return:
    brk
#endif
#if C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
    lda #OVL_HELP
    jsr overlay_load
    bcs c64_test_change_save_drive_unexpected_return
    jsr save_prepare_slot_prompt
    bcs c64_test_change_save_drive_unexpected_return
c64_test_change_save_drive_wait_for_harness:
    jmp c64_test_change_save_drive_wait_for_harness
c64_test_change_save_drive_before_save:
    lda #10
    sta save_device
    jsr save_game
    bcc c64_test_change_save_drive_unexpected_return
c64_test_change_save_drive_pass:
    jmp c64_test_change_save_drive_pass
c64_test_change_save_drive_unexpected_return:
    brk
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    jsr save_prepare_slot_prompt
    bcs c64_test_single_drive_save_wrong_media_unexpected_return
c64_test_single_drive_save_wrong_media_wait_for_harness:
    jmp c64_test_single_drive_save_wrong_media_wait_for_harness
c64_test_single_drive_save_wrong_media_before_save:
    jsr disk_prompt_save
    jsr save_game
c64_test_single_drive_save_wrong_media_unexpected_return:
    brk
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #0
    sta save_slot_index
    lda #OVL_HELP
    jsr overlay_load
    bcs c64_test_single_drive_fresh_save_unexpected_return
    jsr save_prepare_slot_prompt
    bcs c64_test_single_drive_fresh_save_unexpected_return
c64_test_single_drive_fresh_save_wait_for_harness:
    jmp c64_test_single_drive_fresh_save_wait_for_harness
c64_test_single_drive_fresh_save_before_save:
    jsr disk_prompt_save
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT
    bcs c64_test_single_drive_fresh_save_unexpected_return
    jsr save_game
    bcs c64_test_single_drive_fresh_save_unexpected_return
c64_test_single_drive_fresh_save_no_init_return:
    jmp c64_test_single_drive_fresh_save_no_init_return
#else
    bcs c64_test_single_drive_fresh_save_unexpected_return
    jsr save_game
    bcc c64_test_single_drive_fresh_save_unexpected_return
    lda #1
    sta c64_test_restart_after_save_armed
    jsr disk_prompt_game_required
    jmp game_over_prompt
#endif
c64_test_single_drive_fresh_save_unexpected_return:
    brk
#endif
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_THEN_LOAD_PRODUCT
#if C64_TEST_SCRIPTED_DISK_SETUP_THEN_LOAD_PRODUCT
    lda c64_test_disk_setup_then_load_started
    bne !disk_setup_then_load_continue+
    lda #1
    sta c64_test_disk_setup_then_load_started
#endif
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #0
    sta disk_setup_done
    lda #OVL_HELP
    jsr overlay_load
    bcs c64_test_disk_setup_single_drive_return_unexpected_return
c64_test_disk_setup_single_drive_return_wait_for_harness:
    jmp c64_test_disk_setup_single_drive_return_wait_for_harness
c64_test_disk_setup_single_drive_return_before_disk_setup:
#if C64_TEST_SCRIPTED_DISK_SETUP_THEN_LOAD_PRODUCT
!disk_setup_then_load_continue:
#endif
#endif

#if C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
c64_test_slot2_save_wait_for_harness:
    jmp c64_test_slot2_save_wait_for_harness
c64_test_slot2_save_resume_low:
    jmp title_load_game
#endif

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
    bcs !enter_menu+
!load_now:
    jmp title_load_game
!not_l:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    bcs !enter_menu+
    jsr disk_prompt_game_required
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda #1
    sta c64_test_disk_setup_single_drive_return_armed
#endif
#if C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT
c64_test_after_disk_setup_product:
#endif
!enter_menu:
    jmp title_enter_menu
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_THEN_LOAD_PRODUCT
c64_test_disk_setup_single_drive_return_unexpected_return:
    brk
#endif

title_draw_menu:
    // --- Show title menu: N)EW  L)OAD  D)ISK SETUP ---
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #7                  // Center: (40-25)/2 ~= 7
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

title_load_game:
    jsr c64_title_load_preflight
    bcs !title_load_fail+
    jsr disk_prompt_save        // OVL_SAVE is resident before save-media I/O.
    bcs !title_load_fail+
    lda save_device
    cmp program_device
    bne !dual_stock_load+
    jsr c64_try_fast_save_load
    cmp #0
    bne !fast_not_ok+
    jsr overlay_invalidate
    jmp !title_load_loaded+
!fast_not_ok:
    cmp #2
    beq !title_load_fail+
    jsr load_game
    jsr overlay_invalidate
    // Fail closed on the explicit load carry result before resuming gameplay.
    bcc !title_load_fail+
    jmp !title_load_loaded+
!dual_stock_load:
    jsr c64_prepare_stock_save_load
    cmp #2
    beq !title_load_fail+
    jsr load_game
    jsr overlay_invalidate
    bcc !title_load_fail+
!title_load_loaded:
#if C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT
c64_test_slot2_save_loaded:
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
c64_test_single_drive_load_return_before_program_prompt:
    jmp c64_test_single_drive_load_return_loaded_low
#endif
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
c64_test_load_then_save_new_empty_loaded:
c64_test_load_then_save_new_empty_before_save:
    jsr save_prepare_slot_prompt
c64_test_load_then_save_new_empty_after_save_prepare:
    bcs c64_test_load_then_save_new_empty_fail
    jsr disk_prompt_save
    bcs c64_test_load_then_save_new_empty_fail
    jsr save_game
    bcc c64_test_load_then_save_new_empty_fail
c64_test_load_then_save_new_empty_before_program_prompt:
    jsr disk_prompt_game_required
c64_test_load_then_save_new_empty_done:
    jmp c64_test_load_then_save_new_empty_done
c64_test_load_then_save_new_empty_fail:
    brk
#endif
    jsr disk_prompt_game        // Swap back for tier loading
    jsr disk_prompt_game_required // Verify program media before resume loads tiers
    bit krill_active
    bmi !fast_resume+
    jsr krill_resume
    jsr map_stage_copy
!fast_resume:
#if C64_TEST_SCRIPTED_SLOT2_LOAD_PRODUCT
c64_test_after_restore_map_copy:
.label c64_test_restored_map_last = MAP_END
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
c64_test_single_drive_load_return_media_ready:
#endif
    jmp load_resume_game
!title_load_fail:
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
c64_test_single_drive_load_return_load_fail:
    brk
#endif
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    jmp c64_test_load_then_save_new_empty_fail
#endif
    jsr input_get_modal_dismiss_key
    jsr disk_prompt_game_required // Verify program media before returning to title
#if C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT
c64_test_after_load_missing_save_return:
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
c64_test_single_drive_load_corrupt_clean_return:
#endif
    jmp title_enter_menu

// Return A=0 success, nonzero/non-2 stock-DOS fallback, A=2 corrupt split save.
c64_try_fast_save_load:
    lda save_device
    cmp program_device
    bne !fallback_stage_transport+
    bit krill_drive_1541
    bpl !fallback_stage_transport+
    jsr krill_resume
    bit krill_active
    bpl !fallback_stage_transport+
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr ovl_save_fast_load
    pha
    jsr platform_runtime_resync_c64
    pla
    cmp #1
    beq !fallback_stage_transport+
    rts
!fallback_stage_transport:
    jmp c64_prepare_stock_save_load

// Both callers enter with the normal $36 banking established.
c64_prepare_stock_save_load:
    sei
    dec $01                     // $36 -> $35, exposing the save overlay
    jsr ovl_save_prepare_stock_load
    jsr platform_runtime_resync_c64
    rts

// ============================================================
// IRQ wedge — suppress KERNAL cursor blink
// Forces $CC non-zero before KERNAL IRQ handler checks it.
// Must live in main RAM (always accessible during IRQ).
// ============================================================
irq_no_blink:
    cld
irq_no_blink_after_cld:
    lda #1
    sta zp_screen_editor_state // Force non-zero (inc wraps $FF→$00, re-enabling blink)
    jmp $ea31               // Continue to standard KERNAL IRQ handler

// c64_irq_hidden_rom — IRQ/NMI handler for all-RAM mode.
// If an interrupt leaks through while $01 hides KERNAL, CPU vectors read RAM
// at $FFFA/$FFFE. Acknowledge likely interrupt sources and return without
// touching KERNAL ROM, which is not visible in that banking mode.
c64_irq_hidden_rom:
    cld
    pha
    lda $01
    pha
    lda #BANK_NO_KERNAL
    sta $01
    lda $dc0d
    lda $dd0d
    lda $d019
    sta $d019
    pla
    sta $01
    pla
    rti
c64_irq_hidden_rom_end:

c64_install_ram_irq_vectors:
    php
    sei
    lda #<c64_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>c64_irq_hidden_rom
    sta $fffb
    sta $ffff
    plp
    rts
c64_install_ram_irq_vectors_end:

.assert "hidden-ROM NMI handler is fixed at 26 bytes", c64_irq_hidden_rom_end - c64_irq_hidden_rom, 26
.assert "RAM vector installer is fixed at 20 bytes", c64_install_ram_irq_vectors_end - c64_install_ram_irq_vectors, 20
.assert "hidden-ROM handler and installer retain their 46-byte span", c64_install_ram_irq_vectors_end - c64_irq_hidden_rom, 46
.assert "hidden-ROM handler remains resident below MAP_BASE", c64_irq_hidden_rom < MAP_BASE && c64_irq_hidden_rom_end <= MAP_BASE, true

.label hal_irq_install_runtime = c64_install_ram_irq_vectors

// ============================================================
// kernal_load_safe — KERNAL LOAD wrapper for C64
// ============================================================
kernal_load_safe:
    jsr $ffd5               // KERNAL LOAD — carry set on error
    jmp tramp_sr_epilogue   // Preserve carry while restoring runtime state

// ============================================================
// C64 Ultimate turbo wrappers — resident, callable from any overlay
// ============================================================
c64u_turbo_fast:
    lda c64_hw_flags
    and #C64_HW_TURBO_AVAIL
    beq !done+
    lda c64u_turbo_depth
    bne !nested+
    lda C64U_TURBO_CONTROL
    sta c64u_turbo_prev
    lda #C64U_TURBO_FAST
    sta C64U_TURBO_CONTROL
!nested:
    inc c64u_turbo_depth
    lda c64_hw_flags
    ora #C64_HW_TURBO_ON
    sta c64_hw_flags
!done:
    rts

c64u_turbo_normal:
    lda c64u_turbo_depth
    beq !done+
    dec c64u_turbo_depth
    lda c64u_turbo_depth
    bne !done+
    lda c64u_turbo_prev
    sta C64U_TURBO_CONTROL
    lda c64_hw_flags
    and #($ff - C64_HW_TURBO_ON)
    sta c64_hw_flags
!done:
    rts

// ============================================================
// Dungeon gen overlay trampoline — bank KERNAL out, call $E000 overlay
// ============================================================
// KERNAL must be off ($34) while executing overlay code at $E000.
// IRQs must stay DISABLED for the entire overlay execution:
//   - tramp_level_generate holds sei from entry to exit
//   - inner trampolines (tramp_assign_special_room, tramp_vault_seal_entrance,
//     verify_connectivity) use php/plp to preserve the caller's interrupt state
//     instead of cli, so IRQs remain disabled throughout dungeon generation
tramp_level_generate:
    sei
    lda #BANK_NO_ROMS           // $34 — KERNAL off, I/O on; $E000 = overlay RAM
    sta $01
    jsr level_generate          // executes from DungeonGenOverlay at $E000
    lda #BANK_NO_BASIC          // $36 — KERNAL back on; restore normal game banking
    sta $01
    cli
    rts

// ============================================================
// Special rooms trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_assign_special_room:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    lda $01
    pha                         // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr assign_special_room
    pla
    sta $01                     // Restore caller's banking state
    plp                         // Restore interrupt state (no cli — would re-enable IRQs with $01=$34)
    rts

tramp_vault_seal_entrance:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    lda $01
    pha                         // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr vault_seal_entrance
    pla
    sta $01                     // Restore caller's banking state
    plp                         // Restore interrupt state
    rts

tramp_spawn_special_room_monsters:
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr spawn_special_room_monsters
    jmp tramp_sr_epilogue

tramp_spawn_nest_gold:
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr spawn_nest_gold
    jmp tramp_sr_epilogue

tramp_find_special_room:
    pha                         // Save A (room type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr find_special_room
    // Carry flag preserved — lda/sta don't affect carry
    jmp tramp_sr_epilogue

tramp_sr_epilogue:
    php
    jsr platform_runtime_resync_c64
    plp
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_roll_ego_type:
    pha                         // Save A (item type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr roll_ego_type
    pha                         // Save result
    lda #BANK_NO_BASIC
    sta $01
    cli
    pla                         // Restore result
    rts

// tramp_roll_ego_type_modal — Ego roll for callers executing from the $E000
// overlay window (Wizard generate item). The standard trampoline exits with
// KERNAL mapped at $E000, so an overlay caller's return address would execute
// KERNAL ROM instead of overlay code. This variant keeps overlay RAM visible
// and stays SEI'd, matching the overlay's entry banking.
tramp_roll_ego_type_modal:
    pha                         // Save A (item type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr roll_ego_type
    pha                         // Restore I/O while keeping KERNAL hidden so
    lda #BANK_NO_KERNAL         // modal/GEN overlay continuations stay visible.
    sta $01
#if C64_TEST_SCRIPTED_WIZARD_ITEM_PRODUCT
c64_test_wizard_ego_bank_restored_sym:
#endif
    pla
    rts

// tramp_ego_append_suffix — Append ego suffix to combat_msg_buf
// Input: A = ego type
// Copies suffix string from $F000 region to combat_msg_buf while banked out.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+             // No ego → nothing to append
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string (in $F000)
    // Copy string to combat_msg_buf (while banked out so we can read $F000)
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #COMBAT_MSG_BUF_LAST    // Buffer overflow protection
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
    lda #BANK_NO_BASIC
    sta $01
    cli
!teas_done:
    rts

// ============================================================
// tramp_ego_apply_damage — Apply ego slay/bonus damage (banked at $F000)
// Input: A = ego type (1-7), cmb_damage and cmb_type set
// Output: cmb_damage updated
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
tramp_ego_apply_damage:
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_apply_damage
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// tramp_ego_get_ac_bonus — Get ego AC bonus (banked at $F000)
// Input: A = ego type (1-7)
// Output: A = AC bonus (0 if none)
// Clobbers: X
tramp_ego_get_ac_bonus:
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_get_ac_bonus
    pha
    lda #BANK_NO_BASIC
    sta $01
    cli
    pla
    rts


// Init-only strings — kept in main RAM (small, referenced by title_screen.s)
// ============================================================
title_str:
    .text "MORIA8 C=64" ; .byte 0

// title_show_sysinfo — Trampoline to call banked version at $F000
// Reads KERNAL_REV while KERNAL is still banked in, then banks out.
title_show_sysinfo:
    lda KERNAL_REV              // Read from ROM while KERNAL banked in
    sta tsi_krev_cached
    jmp title_show_sysinfo_banked
tsi_krev_cached: .byte 0

#import "../../../core/title_sysinfo_banked.s"

// tramp_reu_show_status — Bank out KERNAL to call banked status display
// Patched into reu_show_status at startup by init code.
tramp_reu_show_status:
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL         // $35 — I/O visible for screen writes
    sta $01
    jsr reu_show_status_banked
    pla
    sta $01
    cli
    rts

platform_main_loop_begin_c64:
platform_vector_reassert_c64:
platform_runtime_resync_c64:
    sei
    lda #<irq_no_blink
    sta $0314
    lda #>irq_no_blink
    sta $0315
    jsr c64_install_ram_irq_vectors
    lda #BANK_NO_BASIC
    sta $01
    lda #$03                // VIC-II bank 0, IEC lines released, upper bits 0
    sta $dd00
    cli
    rts

#import "../../../core/ui_help_clear.s"

// ============================================================
// UI screen trampolines — help and modal UI load from $E000 overlays
// ============================================================
overlay_load_no_kernal:
    pha
    lda #BANK_NO_BASIC        // KERNAL visible for overlay disk LOAD
    sta $01
    cli
    pla
    jsr overlay_load
    bcs !done+
    sei
    jsr c64_install_ram_irq_vectors
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
!done:
    rts

save_prepare_slot_prompt:
    lda #OVL_SAVE
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ovl_save_krill_suspend
    clc
!done:
    rts

#if !BYPASS_SLOT_PROMPT
save_select_slot_prompt:
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr save_select_slot_prompt_impl
    jmp platform_runtime_resync_c64
#endif

#import "run_visibility_trampoline.s"

// Run initialization executes once when SHIFT+direction begins. Its larger
// CJS setup routine lives in the banked payload; per-step running stays local.
run_initialize:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL
    sta $01
    jsr run_initialize_impl
    pla
    sta $01
    plp
    rts

tramp_ui_help_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcc !loaded+
    jmp tramp_sr_epilogue
!loaded:
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
    jmp tramp_sr_epilogue

// Compact dispatch for overlay calls whose targets take no live register input.
tramp_ui_char_display:
    ldx #1
    bne !ui+
tramp_item_gain_spell:
    ldx #2
    bne !ui+
tramp_spell_list_display:
    ldx #3
!ui:
    lda #OVL_UI
    bne tramp_overlay_dispatch

tramp_magic_recalc_mana:
    ldx #4
    bne !modal+
tramp_magic_check_new_spells:
    ldx #5
    bne !modal+
tramp_calc_spell_failure:
    ldx #6
    bne !modal+
tramp_ui_wizard_display:
    ldx #7
    bne !modal+
tramp_store_init_all:
    ldx #8
    bne !modal+
tramp_store_restock_all:
    ldx #9
    bne !modal+
tramp_do_look:
    ldx #10
!modal:
    lda #OVL_MODAL_MISC
    bne tramp_overlay_dispatch

tramp_ui_inv_display:
    ldx #11
    bne !help+
tramp_ui_inv_select_display:
    ldx #12
    bne !help+
tramp_ui_equip_display:
    ldx #13
    bne !help+
tramp_ui_equip_select_display:
    ldx #14
!help:
    lda #OVL_HELP
    bne tramp_overlay_dispatch

tramp_item_read_scroll:
    ldx #15
    bne !items+
tramp_item_aim_wand:
    ldx #16
    bne !items+
tramp_item_use_staff:
    ldx #17
    bne !items+
tramp_item_refuel:
    ldx #18
    bne !items+
tramp_ranged_fire:
    ldx #19
    bne !items+
tramp_throw_item:
    ldx #20
    bne !items+
tramp_bash_command:
    ldx #21
    bne !items+
tramp_disarm_command:
    ldx #22
    bne !items+
tramp_cmd_jam:
    ldx #23
    bne !items+
tramp_item_init_identification:
    ldx #24
    bne !items+
tramp_player_tunnel:
    ldx #25
!items:
    lda #OVL_ITEMS
    bne tramp_overlay_dispatch

tramp_chest_open:
    ldx #26
    bne !chest+
!chest:
    lda #OVL_CHEST
    bne tramp_overlay_dispatch

tramp_spell_execute_selected:
    ldx #27
    bne !spell+
tramp_reveal_floorplan:
    ldx #28
!spell:
    lda #OVL_SPELL

tramp_overlay_dispatch:
    pha
    lda tramp_overlay_target_lo - 1,x
    sta !call+ + 1
    lda tramp_overlay_target_hi - 1,x
    sta !call+ + 2
    pla
    jsr overlay_load_no_kernal
    bcs !done+
!call:
    jsr $ffff
!done:
    jmp tramp_sr_epilogue

tramp_overlay_target_lo:
    .byte <ui_char_display, <item_gain_spell, <spell_list_display
    .byte <magic_recalc_mana, <magic_check_new_spells, <calc_spell_failure
    .byte <ui_wizard_display, <store_init_all, <store_restock_all, <do_look
    .byte <ui_inv_display, <ui_inv_select_display, <ui_equip_display, <ui_equip_select_display
    .byte <item_read_scroll, <item_aim_wand, <item_use_staff, <item_refuel
    .byte <ranged_fire, <throw_item, <bash_command, <disarm_command, <door_jam_command
    .byte <item_init_identification, <player_tunnel, <chest_open_command
    .byte <spell_execute_selected, <eff_reveal_floorplan
tramp_overlay_target_hi:
    .byte >ui_char_display, >item_gain_spell, >spell_list_display
    .byte >magic_recalc_mana, >magic_check_new_spells, >calc_spell_failure
    .byte >ui_wizard_display, >store_init_all, >store_restock_all, >do_look
    .byte >ui_inv_display, >ui_inv_select_display, >ui_equip_display, >ui_equip_select_display
    .byte >item_read_scroll, >item_aim_wand, >item_use_staff, >item_refuel
    .byte >ranged_fire, >throw_item, >bash_command, >disarm_command, >door_jam_command
    .byte >item_init_identification, >player_tunnel, >chest_open_command
    .byte >spell_execute_selected, >eff_reveal_floorplan

tramp_ui_recall:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_recall_display
    jmp tramp_sr_epilogue

tramp_eff_earthquake:
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr c64u_turbo_fast
    jsr eff_earthquake_banked
    jsr c64u_turbo_normal
    rts

// door_pick_roll lives in the chest overlay with chest_disarm_skill; carry
// (picked) propagates through the epilogue. A failed overlay load reads as
// an ordinary pick miss (turn still consumed by the caller).
tramp_door_pick_roll:
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !load_failed+
    jsr door_pick_roll
    jmp tramp_sr_epilogue
!load_failed:
    jsr platform_runtime_resync_c64
    clc
    rts

// Chest routing (docs/CHEST_DESIGN.md). tramp_chest_open is called from the
// resident cmd_open pre-dispatch and owns the epilogue. chest_dispatch is
// tail-called (A/Y = handler) from bash_command/disarm_command inside the
// items overlay; their caller trampolines run the epilogue.
chest_dispatch:
    sta chest_disp_jmp+1
    sty chest_disp_jmp+2
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
chest_disp_jmp:
    jmp $0000               // SMC dispatch target (never JMP (addr))
!done:
    rts

tramp_ui_identify:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_identify_print
    lda #BANK_NO_BASIC
    sta $01
    cli
    jsr tier_restore_after_overlay
!done:
    jmp tramp_sr_epilogue

tramp_disk_setup:
    lda #OVL_SAVE
    jsr overlay_load_no_kernal
    bcs !tds_done+
    jsr ovl_save_krill_suspend
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr disk_setup_run
    jmp tramp_sr_epilogue

!tds_done:
    rts

tramp_disk_prepare_selected:
    lda current_overlay
    cmp #OVL_SAVE
    bne !tdps_fail+
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr disk_setup_prepare_selected
    php
    jsr platform_runtime_resync_c64
    plp
!tdps_done:
    rts
!tdps_fail:
    sec
    rts


// ============================================================
// Store overlay trampolines — load overlay, bank out KERNAL, call $E000+
// ============================================================
// Shared preamble: ensure town overlay is loaded, then bank out KERNAL
store_overlay_preamble:
    lda #OVL_TOWN
    jsr overlay_load
    sei
    lda #BANK_NO_KERNAL         // $35 — $E000 = RAM + I/O for color RAM
    sta $01
    rts

tramp_store_enter:
    jsr store_overlay_preamble
    jsr store_enter
    jmp tramp_sr_epilogue

#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_expect_screen_string:
    sta test_expect_row
    stx test_expect_col
    ldx test_expect_row
    lda screen_row_lo,x
    clc
    adc test_expect_col
    sta zp_ptr2
    lda screen_row_hi,x
    adc #0
    sta zp_ptr2_hi
    ldy #0
!tes_loop:
    lda (zp_ptr0),y
    beq !tes_ok+
    cmp (zp_ptr2),y
    bne !tes_fail+
    iny
    bne !tes_loop-
!tes_fail:
    clc
    rts
!tes_ok:
    sec
    rts

test_expect_row: .byte 0
test_expect_col: .byte 0

.encoding "screencode_mixed"
#if C64_TEST_SCRIPTED_BOOK_OVERLAY
test_inventory_title_str: .text "Inventory" ; .byte 0
test_beginner_book_str:   .text "Beginner's Spellbook" ; .byte 0
#endif
#endif

#if C64_TEST_SCRIPTED_BOOK_OVERLAY
test_assert_book_overlay:
    lda #<test_inventory_title_str
    sta zp_ptr0
    lda #>test_inventory_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #15
    jsr test_expect_screen_string
    bcc !book_fail+

    lda #<test_beginner_book_str
    sta zp_ptr0
    lda #>test_beginner_book_str
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !book_fail+

    jmp c64_test_book_overlay_pass_sym
!book_fail:
    jmp c64_test_book_overlay_fail_sym
#endif

#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_assert_spell_list_overlay:
    lda #<pm_title_mage_str
    sta zp_ptr0
    lda #>pm_title_mage_str
    sta zp_ptr0_hi
    lda #0
    ldx #14
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<msn_0
    sta zp_ptr0
    lda #>msn_0
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<msn_2
    sta zp_ptr0
    lda #>msn_2
    sta zp_ptr0_hi
    lda #4
    ldx #4
    jsr test_expect_screen_string
    bcc !list_fail+

    jmp c64_test_spell_list_overlay_pass_sym
!list_fail:
    jmp c64_test_spell_list_overlay_fail_sym
#endif

#if C64_TEST_SCRIPTED_SPELL
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_roll_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY
c64_test_book_overlay_fail_sym:
    brk
c64_test_book_overlay_fail_input_sym:
    brk
c64_test_book_overlay_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
c64_test_spell_list_overlay_fail_sym:
    brk
c64_test_spell_list_overlay_fail_input_sym:
    brk
c64_test_spell_list_overlay_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_SCROLL_SELECTOR
c64_test_scroll_selector_fail_sym:
    brk
c64_test_scroll_selector_fail_input_sym:
    brk
c64_test_scroll_selector_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_roll_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_WIZARD_REVEAL_PRODUCT || C64_TEST_SCRIPTED_WIZARD_ITEM_PRODUCT || C64_TEST_SCRIPTED_SCROLL_TELEPORT_PRODUCT
c64_test_wizard_reveal_fail_input_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
c64_test_dungeon_ascent_fail_input_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_roll_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif

#if C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT
c64_test_disk_setup_fail_input_sym:
    brk
#endif

#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
c64_test_save_write_fail_input_sym:
    brk
#endif

#if C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || C64_TEST_SCRIPTED_SLOT2_LOAD_PRODUCT
c64_test_load_resume_fail_input_sym:
    brk
#endif

#if C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT
c64_test_load_missing_save_fail_input_sym:
    brk
#endif

// ============================================================
// Startup overlay trampoline — load overlay, bank out KERNAL, call $E000+
// ============================================================
tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    sei
    lda #BANK_NO_KERNAL         // $35 — $E000 = RAM + I/O for color RAM
    sta $01
    jsr player_create
    jmp tramp_sr_epilogue

// Verify that the selected program disk is actually present.
// Output: carry clear = program media present, carry set = absent/wrong media.
c64_require_program_media:
    bit krill_active
    bmi !crpm_ok+
    // An active Krill session cannot issue the KERNAL probe: shared IEC ATN
    // would uninstall the drive code. The following asset load is the media
    // check and reports its own carry/status.
    lda save_device
    pha
    lda disk_prompt_device
    sta save_device
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr disk_program_media_present
    lda #0
    adc #0
    pha
    jsr platform_runtime_resync_c64
    pla
    tax
    pla
    sta save_device
    txa
    beq !crpm_ok+
    sec
    rts
!crpm_ok:
    clc
    rts

// ============================================================
// Death overlay trampoline — orchestrates the full game-over sequence
// ============================================================
// Interleaves overlay calls ($E000, $01=$34) with KERNAL I/O ($01=$36).
// Pre-resolves creature name before overlay overwrites tier data.
tramp_game_over_disk_setup:
    jsr tramp_disk_setup
    bcs !done+
    jsr disk_prompt_game        // Disk Setup used the overlay window; reload from program media
    lda #1
    sta disk_setup_done         // Save disk is no longer mounted in one-drive mode
    jsr tramp_game_over_prepare
    clc
!done:
    rts

tramp_game_over_disk_setup_failed:
    jmp disk_prompt_game

tramp_game_over_prepare:
    lda death_source_saved
    sta zp_death_source

    // 1. Resolve death source text while tier data still at $E000
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !tgo_load_overlay+
    lda zp_death_source
    cmp #DEATH_ALIVE
    beq !tgo_load_overlay+
    cmp #DEATH_CHEST_NEEDLE         // Special sources ($F7-$FF) don't need name
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name       // Copies name to creature_name_buf in main RAM

!tgo_load_overlay:
    // 2. Suspend Krill before the score stream's standard-DOS transactions.
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !tgo_done+
    jsr krill_suspend_for_stock

    // 3. Load death overlay (replaces the modal helper at $E000).
    lda #OVL_DEATH
    jsr overlay_load
!tgo_done:
    rts

tramp_game_over:
    jsr tramp_game_over_prepare
tramp_game_over_run:
    // 3. Calculate score (overlay code, no KERNAL needed)
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr score_calculate
    lda #BANK_NO_BASIC
    sta $01
    cli

    // 4. Load high scores from disk (main RAM, needs KERNAL)
    jsr hiscore_load

    // 5. Insert into high score table (overlay code)
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr hiscore_insert
    lda #BANK_NO_BASIC
    sta $01
    cli

    // 6. Save high scores to disk (main RAM, needs KERNAL)
    jsr hiscore_save
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source

    // 7. Display death screen (overlay code)
    // Defensive: restore VIC-II bank 0 after KERNAL serial I/O
    // KERNAL uses CIA2 ($DD00) bits 3-5 for serial bus;
    // bits 0-1 select VIC bank. Ensure bank 0 ($0000-$3FFF).
    jsr c64_restore_vic_bank0_after_serial
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    jsr score_death_screen
    inc $01
    cli
    rts

tramp_winner_royal:
    jsr tramp_game_over_prepare
    bcs !done+
    sei
    dec $01
    jmp winner_royal_overlay
!done:
    rts

// ============================================================
// game_over_prompt — return to title/menu after save, quit, or death.
// Shown at all exit points (save+quit, voluntary quit, death).
// ============================================================
game_over_prompt:
    lda #OVL_DEATH
    jsr overlay_load
    bcc !overlay_ok+
    jmp title_enter_menu
!overlay_ok:
    sei
    dec $01
    jmp game_restart_overlay

// Reinstall only while title owns the map window used by KINST41 at $C000.
// Installer failure is nonfatal: clear suspension and continue on the KERNAL path.
krill_resume:
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    lda #1
    sta c64_test_krill_resume_stage
#endif
    bit krill_suspended
    bmi !resume+
    rts
!resume:
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    inc c64_test_krill_resume_stage
#endif
    bit krill_drive_1541
    bmi !drive_supported+
    jmp !clear_suspended+
!drive_supported:
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    inc c64_test_krill_resume_stage
#endif
    php
    sei
    lda $01
    pha
    lda #BANK_ALL_RAM
    sta $01
    lda KRILL_INSTALL_CACHE_MAGIC
    cmp #KRILL_INSTALL_CACHE_MAGIC_LO
    bne !cache_miss+
    lda KRILL_INSTALL_CACHE_MAGIC + 1
    cmp #KRILL_INSTALL_CACHE_MAGIC_HI
    bne !cache_miss+
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    inc c64_test_krill_resume_stage
#endif
    lda #<KRILL_INSTALL_CACHE_BASE
    sta zp_ptr0
    lda #>KRILL_INSTALL_CACHE_BASE
    sta zp_ptr0_hi
    ldy #0
    sty zp_ptr1
    lda #>$c000
    sta zp_ptr1_hi
    ldx #>KRILL_INSTALL_CACHE_SIZE
    jsr banked_page_copy
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    cpy #<KRILL_INSTALL_CACHE_SIZE
    bne !tail-
    pla
    sta $01
    plp
    lda program_device
    sta KERNAL_CURRENT_DEVICE
    jsr c64_disk_call
    .word $c000
    bcs !clear_suspended+
    // The enabled drive watchdog resets after a few starved frames.
    lda #$ff
    sta krill_active
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    inc c64_test_krill_resume_stage
#endif
    jmp !clear_suspended+
!cache_miss:
    pla
    sta $01
    plp
!clear_suspended:
    lda #0
    sta krill_suspended
    rts

// Restore the staged map after KINST41 has finished using MAP_BASE.
.assert "C64 staged map copy requires page-aligned MAP_SIZE", <MAP_SIZE, 0
map_stage_copy:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL
    sta $01
    ldy #0
    sty zp_ptr0
    sty zp_ptr1
    lda #>MAP_STAGE_BASE
    sta zp_ptr0_hi
    lda #>MAP_BASE
    sta zp_ptr1_hi
    ldx #>MAP_SIZE
    jsr banked_page_copy
    pla
    sta $01
    plp
    rts

banked_page_copy:
!page:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page-
    rts

// Safety: ensure runtime code doesn't overlap runtime data areas
pm_map_min_x: .byte 0
pm_map_max_x: .byte 0
pm_map_min_y: .byte 0
pm_map_max_y: .byte 0
pm_map_max_col: .byte 0
pm_map_max_row: .byte 0
eq_cur_x: .byte 0
eq_cur_y: .byte 0
eq_rows_left: .byte 0
eq_cols_left: .byte 0
eq_changed: .byte 0
eq_mon_slot: .byte 0
eq_mon_alive: .byte 0
eq_saved_tile: .byte 0
eq_saved_flags: .byte 0

// KINST41 consumes the init-only $C000 window, so reusable title preflight
// code remains in resident RAM.
c64_title_load_preflight:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
    jsr save_prepare_slot_prompt
    bcs !failed+
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    clc
    rts
!failed:
    sec
    rts

.fill MAP_BASE - *, 0
program_end:
.print "program_end = $" + toHexString(program_end)
.assert "Program ends exactly at MAP_BASE", program_end, MAP_BASE
.assert "Map and earthquake scratch stay resident below MAP_BASE", pm_map_min_x < program_end && eq_saved_flags < program_end, true
.assert "C64 title load preflight stays resident", c64_title_load_preflight < MAP_BASE, true

.segment InitTail
init_tail_start:
.assert "InitTail starts exactly at MAP_BASE", init_tail_start, MAP_BASE

// ============================================================
// Init-only code below — lives past CREATURE_BASE, safe because
// it runs once at startup before dungeon map or RLE workspace
// are used. Overwritten during normal gameplay.
// ============================================================

// REU preload status is startup-only and is dead before MAP_BASE takes over
// this init tail. Keeping it here leaves runtime-bank space for run setup.
#import "../common/reu_loading_banked.s"

// One-shot platform-services installer (called once at boot, before the map
// exists). Lives in the init-only tail so the resident runtime image keeps
// room for the chest routing trampolines.
platform_services_install64:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<platform_main_loop_begin_c64
    sta platform_main_loop_begin_api + 1
    lda #>platform_main_loop_begin_c64
    sta platform_main_loop_begin_api + 2

    lda #<platform_vector_reassert_c64
    sta platform_vector_reassert_api + 1
    lda #>platform_vector_reassert_c64
    sta platform_vector_reassert_api + 2

    lda #<platform_runtime_resync_c64
    sta platform_runtime_resync_api + 1
    lda #>platform_runtime_resync_c64
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

// One-shot generation-busy API installer (also called once at boot; the core
// copy is skipped via GENERATION_BUSY_INSTALL_EXTERNAL). Same init-tail
// treatment: frees resident room for the save invalid-ID hardening.
generation_busy_install:
    lda #$4c
    sta generation_busy_begin_api
    sta generation_busy_tick_api
    sta generation_busy_end_api

    lda #<generation_busy_begin
    sta generation_busy_begin_api + 1
    lda #>generation_busy_begin
    sta generation_busy_begin_api + 2

    lda #<generation_busy_tick
    sta generation_busy_tick_api + 1
    lda #>generation_busy_tick
    sta generation_busy_tick_api + 2

    lda #<generation_busy_end
    sta generation_busy_end_api + 1
    lda #>generation_busy_end
    sta generation_busy_end_api + 2

    lda #0
    sta generation_busy_active_api
    rts

// One-shot REU tier and overlay stashes (run once at boot when an REU is
// present, before the map exists; the core copies are skipped via
// REU_LOAD_ALL_TIERS_EXTERNAL / REU_STASH_OVERLAYS_EXTERNAL). Same
// init-tail treatment: frees resident room for chest search/trap discovery.
reu_load_all_tiers:
    lda #0
    sta reu_tier_offset_lo
    sta reu_tier_offset_hi
    sta reu_tiers_loaded

    ldx #1                      // Start with tier 1
!rlt_loop:
    stx reu_tier_idx

    // Save REU start offset for this tier BEFORE stashing
    lda reu_tier_offset_lo
    sta reu_tier_start_lo,x
    lda reu_tier_offset_hi
    sta reu_tier_start_hi,x

    // Display tier filename
    stx current_tier            // tier_load_disk reads current_tier for filename
    dex                         // 0-based index for display table
    lda reu_fn_tier_lo,x
    sta zp_ptr0
    lda reu_fn_tier_hi,x
    sta zp_ptr0_hi
    jsr reu_show_file

    // Load tier file from disk to $E000
    jsr tier_load_disk
    bcs !rlt_skip+              // Skip if load failed
    inc reu_tiers_loaded

    // Stash from $E000 to REU at current offset
    sei
    lda hal_memory_cpu_port
    pha
    lda #$35                    // Bank out KERNAL (so REU DMA reads RAM at $E000)
    sta hal_memory_cpu_port

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI
    ldx reu_tier_idx
    lda reu_tier_start_lo,x
    sta REU_REULO
    lda reu_tier_start_hi,x
    sta REU_REUHI
    lda #0
    sta REU_BANK                // All tier data fits in bank 0
    lda tier_size_lo,x
    sta REU_LENLO
    lda tier_size_hi,x
    sta REU_LENHI
    lda #0
    sta REU_CONTROL             // Both addresses increment
    lda #REU_CMD_STASH
    sta REU_COMMAND             // Execute DMA

    pla
    sta hal_memory_cpu_port     // Restore bank config
    cli

!rlt_skip:
    // Advance REU offset by tier size (even if load failed, reserve space)
    ldx reu_tier_idx
    clc
    lda reu_tier_offset_lo
    adc tier_size_lo,x
    sta reu_tier_offset_lo
    lda reu_tier_offset_hi
    adc tier_size_hi,x
    sta reu_tier_offset_hi

    // Update status display with new usage
    jsr reu_show_status

    ldx reu_tier_idx
    inx
    cpx #5                      // Tiers 1-4
    beq !rlt_all_done+
    jmp !rlt_loop-
!rlt_all_done:

    // Reset game state — no tier active yet (player starts in town)
    lda #0
    sta current_tier

    // If no tiers loaded successfully, disable REU tier path
    // so tier_load falls back to disk → embedded creature fallback
    lda reu_tiers_loaded
    bne !rlt_done+
    sta reu_present             // A is already 0
!rlt_done:
    rts

reu_stash_overlays:
    ldx #1                      // Start with overlay 1 (OVL_STARTUP)
!rso_loop:
    stx reu_ovl_idx

    // Record REU start offset for this overlay
    lda reu_tier_offset_lo
    sta ovl_reu_start_lo,x
    lda reu_tier_offset_hi
    sta ovl_reu_start_hi,x

    // Display overlay filename
    dex                         // 0-based index
    lda reu_fn_ovl_lo,x
    sta zp_ptr0
    lda reu_fn_ovl_hi,x
    sta zp_ptr0_hi
    jsr reu_show_file

    // Load overlay PRG from disk to $E000
    ldx reu_ovl_idx
    dex                         // 0-based index for overlay_load_disk
    jsr overlay_load_disk
    bcs !rso_skip+              // Skip stash if load failed

    // Stash $E000 (4KB) to REU at current offset
    sei
    lda hal_memory_cpu_port
    pha
    lda #$35                    // Bank out KERNAL for DMA to read RAM at $E000
    sta hal_memory_cpu_port

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI
    ldx reu_ovl_idx
    lda ovl_reu_start_lo,x
    sta REU_REULO
    lda ovl_reu_start_hi,x
    sta REU_REUHI
    lda #0
    sta REU_BANK
    sta REU_LENLO               // Length lo = $00
    lda #$10                    // Length hi = $10 → $1000 = 4KB
    sta REU_LENHI
    lda #0
    sta REU_CONTROL
    lda #REU_CMD_STASH
    sta REU_COMMAND             // Execute DMA

    pla
    sta hal_memory_cpu_port
    cli

!rso_skip:
    // Advance REU offset by $1000 (4KB) — low byte unchanged
    lda reu_tier_offset_hi
    clc
    adc #$10
    sta reu_tier_offset_hi

    // Update status display with new usage
    jsr reu_show_status

    ldx reu_ovl_idx
    inx
    cpx #(REU_OVERLAY_COUNT + 1)
    bne !rso_loop-

    lda #1
    sta reu_overlays_stashed
    rts

// ultimate_detect — One-shot C64 Ultimate / Ultimate-family title marker.
// Full UCI model queries do not fit the current resident/banked layout. This
// passive ID-byte check is only used for title display and runs before MAP_BASE
// owns this init-only tail.
.const UCI_DATA_ID        = $df1d
.const UCI_ID_MASKED      = $49
ultimate_detect:
    lda #0
    sta c64_hw_flags
    lda UCI_DATA_ID
    and #$7f                    // $c9 normally, $49 while UCI IRQ is active
    cmp #UCI_ID_MASKED
    bne !done+
    lda #C64_HW_C64U
    sta c64_hw_flags
!done:
    rts

// c64u_turbo_detect — C64U can be present while software turbo control is off.
// $D031 reads $FF unless the Ultimate turbo-control mode exposes registers.
c64u_turbo_detect:
    lda c64_hw_flags
    and #C64_HW_C64U
    beq !done+
    lda C64U_TURBO_CONTROL
    cmp #C64U_TURBO_DISABLED
    beq !done+
    lda c64_hw_flags
    ora #C64_HW_TURBO_AVAIL
    sta c64_hw_flags
!done:
    rts

// reu_detect_extended_c64 — Extend display size detection above 2MB.
// The resident REU path only needs bank 0, so this init-only probe updates
// reu_size_kb for title/loading display without changing cache placement.
reu_detect_extended_c64:
    lda reu_present
    bne !has_reu+
    jmp !done+
!has_reu:
    lda reu_size_kb
    beq !size_lo_ok+
    jmp !done+
!size_lo_ok:
    lda reu_size_kb + 1
    cmp #$08                    // Existing probe capped at 2048KB.
    beq !probe+
    jmp !done+
!probe:

    // Stage 4: banks 32-63 -> 32 or 64+ banks.
    ldy #32
!write_s4:
    tya
    clc
    adc #1
    sta reu_probe_byte
    lda #REU_CMD_STASH
    jsr reu_probe_xfer
    iny
    cpy #64
    bne !write_s4-

    lda #0
    sta reu_probe_byte
    tay
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$01
    beq !s4_bank0_ok+
    jmp !done+                  // Bank 32 aliased: 2048KB.
!s4_bank0_ok:

    lda #0
    sta reu_probe_byte
    ldy #32
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$21
    beq !s4_bank32_ok+
    jmp !done+                  // Bank 32 discarded: 2048KB.
!s4_bank32_ok:

    // Stage 5: banks 64-127 -> 64 or 128+ banks.
    ldy #64
!write_s5:
    tya
    clc
    adc #1
    sta reu_probe_byte
    lda #REU_CMD_STASH
    jsr reu_probe_xfer
    iny
    cpy #128
    bne !write_s5-

    lda #0
    sta reu_probe_byte
    tay
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$01
    bne !is_64+                 // Bank 64 aliased.

    lda #0
    sta reu_probe_byte
    ldy #64
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$41
    bne !is_64+                 // Bank 64 discarded.

    // Stage 6: banks 128-255 -> 128 or 256 banks.
    ldy #128
!write_s6:
    tya
    clc
    adc #1
    sta reu_probe_byte
    lda #REU_CMD_STASH
    jsr reu_probe_xfer
    iny
    bne !write_s6-

    lda #0
    sta reu_probe_byte
    tay
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$01
    bne !is_128+                // Bank 128 aliased.

    lda #0
    sta reu_probe_byte
    ldy #128
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$81
    bne !is_128+                // Bank 128 discarded.

    lda #0
    sta reu_banks               // 256 banks does not fit in one byte.
    sta reu_size_kb
    lda #$40                    // 16384KB = $4000.
    sta reu_size_kb + 1
    rts

!is_128:
    ldy #128
    bne !found+
!is_64:
    ldy #64
!found:
    sty reu_banks
    tya
    sta reu_size_kb + 1
    lda #0
    sta reu_size_kb
    lsr reu_size_kb + 1
    ror reu_size_kb
    lsr reu_size_kb + 1
    ror reu_size_kb
!done:
    rts

// init_load_banked — Load banked runtime payload to $F000.
// Called once at startup before any $F000 trampoline is used.
// Clobbers: A, X, Y
init_load_banked:
    lda #0
    sta krill_active
    sta krill_boot_used
    sta krill_suspended
    // Adopt the boot loader's Krill install result (see boot.s) at the first
    // point of use. The two-byte magic at $0334/$0335 is set only after a
    // successful drive-code install; anything else (including a direct
    // MORIA64 start) keeps the KERNAL path.
    lda $0334
    cmp #$4b
    bne !banked_kernal+
    lda $0335
    cmp #$d2
    bne !banked_kernal+
    // Magic present: the chain stub already Krill-loaded 64.BANK to $F000
    // (a failed stub load clears the magic, so magic means it is there).
    dec krill_active
    inc krill_boot_used         // Evidence for the fastload runtime smoke:
                                // the $F000 payload genuinely came via Krill
    jmp !banked_done+
!banked_kernal:
    lda #BANK_NO_BASIC          // $36 — KERNAL visible for LOAD
    sta $01
    cli
    lda #c64_banked_fname_len
    ldx #<c64_banked_fname
    ldy #>c64_banked_fname
    jsr KERNAL_SETNAM
    lda #2
    ldx program_device
    ldy #1                      // Use PRG header address ($F000)
    jsr KERNAL_SETLFS
#if C64_TEST_BOOT_HANDOFF
c64_test_p6_bank_pre:
#endif
    lda #0
    ldy #$f0
    jsr KERNAL_LOAD
#if C64_TEST_BOOT_HANDOFF
c64_test_p6_kernal_load_return:
#endif
    php
    pha
    lda #2
    jsr KERNAL_CLOSE
    jsr KERNAL_CLRCHN
    lda #$03                // VIC-II bank 0, IEC lines released, upper bits 0
    sta $dd00
    lda #BANK_NO_BASIC
    sta $01
    pla
    plp
    sei
#if C64_TEST_BOOT_HANDOFF
c64_test_p6_cleanup_return:
#endif
    bcs !load_failed+
    jmp !banked_done+
!load_failed:
#if C64_TEST_BOOT_HANDOFF
c64_test_p6_bank_failure:
#endif
    lda #2
    sta $d020
    jmp !load_failed-
!banked_done:
    jsr $e544               // Clear the retired boot resident and chain.
    lda #$1b
    sta $d011
    rts

c64_banked_fname:
    .byte $36,$34,$2e,$42,$41,$4e,$4b  // "64.BANK" in PETSCII/ASCII bytes
.label c64_banked_fname_len = * - c64_banked_fname
    .byte 0                         // 0-terminated for Krill loadraw

    .fill 26, 0                 // Preserve the fixed 64.INIT payload shape.

.assert "krill resident base matches KRILL_RUNTIME_LOADRAW", krill_resident_base, KRILL_RUNTIME_LOADRAW
.assert "krill_uninstall matches KRILL_RUNTIME_UNINSTALL", krill_uninstall, KRILL_RUNTIME_UNINSTALL
.assert "krill_load_file pinned at KRILL_LOAD_FILE", krill_load_file, KRILL_LOAD_FILE
.assert "bounded Krill wrapper pinned at KRILL_LOAD_FILE_BOUNDED", krill_load_file_bounded, KRILL_LOAD_FILE_BOUNDED

init_tail_end:
.print "Init tail: " + (init_tail_end - init_tail_start) + " bytes at $C000-$" + toHexString(init_tail_end)
.assert "InitTail content is 899 bytes", init_tail_end - init_tail_start, 899
.assert "InitTail fits below floor-item/map runtime ceiling", init_tail_end <= $d000, true
.assert "boot device handoff does not overlap init tail", krill_boot_device < init_tail_start, true
.assert "program_device does not overlap init tail", program_device < init_tail_start, true
.assert "RAM vectors do not overlap init tail", $fffa >= init_tail_end, true

// ============================================================
// Banked runtime payload — loadable PRG at $F000.
// ============================================================
.segment RuntimeBanked
    #import "../../../core/ego_items.s"
    #import "../../../core/special_rooms.s"
    #import "../../../core/ui_home.s"
    #import "../../../core/ui_recall.s"
    #import "../../../core/item_desc_banked.s"
    #import "../common/disk_setup_banked.s"
    #define PM_MAP_BANKED
    #define PM_MAP_SCRATCH_EXTERNAL
    #import "../../../core/player_magic_map.s"
    #undef PM_MAP_SCRATCH_EXTERNAL
    #undef PM_MAP_BANKED
    #define PM_EQ_BANKED
    #define PM_EQ_SCRATCH_EXTERNAL
    #import "../../../core/player_magic_earthquake.s"
    #undef PM_EQ_SCRATCH_EXTERNAL
    #undef PM_EQ_BANKED

    // Preserve the fixed 64.BANK load span while retaining reclaimed code space.
    .fill $fff8 - *, 0
banked_code_end:

.print "Banked runtime: " + (banked_code_end - $f000) + " bytes at $F000-$" + toHexString(banked_code_end)
.assert "Banked code fits below CPU vectors", banked_code_end <= $FFFA, true
.assert "Runner visibility implementation stays under KERNAL ROM", monster_update_visibility_one >= $F000 && monster_update_visibility_one < banked_code_end, true
.assert "Runner visibility trampoline stays resident", run_monster_update_visibility_one < MAP_BASE, true
.assert "Runner initialization implementation stays banked", run_initialize_impl >= $F000 && run_initialize_impl < banked_code_end, true
.assert "Runner initialization trampoline stays resident", run_initialize < MAP_BASE, true

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
// This segment produces the configured OVL.TOWN PRG (loaded from disk as OVL.TOWN).
// Labels resolve to $E000+ but bytes go to the overlay PRG file,
// not the main moria.prg. All main RAM symbols are accessible.
.segment TownOverlay
    #import "../../../core/store.s"
    #import "../../../core/ui_store.s"
    #import "../../../core/ui_home_text.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $F000, true

// ============================================================
// Startup overlay — character creation at $E000, output to separate PRG
// ============================================================
// This segment produces the configured OVL.START PRG (loaded from disk as OVL.START).
// Used once during new game, then replaced by town/death overlays.
.segment StartupOverlay
    #import "../../../core/background_data.s"
    #import "../../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $F000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
// This segment produces the configured OVL.DEATH PRG (loaded from disk as OVL.DEATH).
// Used once at game over. Contains scoring math, death screen display,
// and high score insertion/display. KERNAL I/O stays in score_io.s.
.segment DeathOverlay
// game_restart_overlay — reset game state, return to title screen.
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
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SLOT2_SAVE_PRODUCT
    lda #1
    sta c64_test_restart_after_save_armed
#endif
    lda #>(title_enter_menu - 1)
    pha
    lda #<(title_enter_menu - 1)
    pha
    jmp platform_runtime_resync_c64

    // score_io.s lives in the death overlay on this port (its only callers
    // are the death overlay and the resident death orchestration, which runs
    // with this overlay already loaded). Imported before score.s for its
    // constants.
    #import "../../../core/score_io.s"
    #import "../../../core/score.s"
winner_royal_overlay:
    jsr winner_apply_retirement_bonus_overlay
    jsr royal_screen
#if C64_TEST_SCRIPTED_RETIREMENT_PRODUCT
    jmp c64_test_retirement_pass_sym
#else
    jmp platform_runtime_resync_c64
#endif

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
    #import "../../../core/royal.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $F000, true

// ============================================================
// Modal-misc overlay — winner retirement art at $E000
// ============================================================
.segment ModalMiscOverlay
// Temporarily return the IEC bus to stock DOS. Match Krill's standalone
// uninstall sequence: make only the VIC bank bits outputs and clear the IEC
// output latches before the resident switches CIA2 back to KERNAL mode.
krill_suspend:
    bit krill_active
    bpl !done+
    sei
    lda #BANK_NO_KERNAL
    sta $01
    lda #$03
    sta $dd02
    and $dd00
    sta $dd00
    jsr KRILL_RUNTIME_UNINSTALL
    lda #$03
    sta $dd00
    lda #0
    sta krill_active
    lda #$ff
    sta krill_suspended
!done:
    rts

krill_suspend_for_stock:
    jsr krill_suspend
    jmp platform_runtime_resync_c64

// C64 v16 writer. It executes with overlay RAM visible and reaches every
// KERNAL routine through the resident c64_disk_call wrappers.
.segment SaveOverlay
ovl_save_writer_run:
    jsr ovl_save_krill_suspend
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jmp ovl_save_write_split

ovl_save_write_split:
    lda save_slot_index
    cmp #SAVE_SLOT_COUNT
    bcc !slot_ready+
    lda #0
    sta save_slot_index
!slot_ready:
    lda #0
    sta save_io_error
    lda #hal_storage_map_write_name_len
    ldx save_slot_index
    cpx #1
    bcc !map_len_ready+
    clc
    adc #1
!map_len_ready:
    ldx #<hal_storage_map_write_name
    ldy #>hal_storage_map_write_name
    jsr ovl_save_open_output
    bcc !map_open+
    clc
    rts
!map_open:
    lda #$00
    jsr save_write_byte_raw
    lda #$c0
    jsr save_write_byte_raw
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    :save_block(MAP_BASE, MAP_SIZE)
    lda save_cksum_lo
    sta save_map_cksum_lo
    lda save_cksum_hi
    sta save_map_cksum_hi
    jsr ovl_save_close_output
    lda save_io_error
    beq !map_written+
    clc
    rts
!map_written:

    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    lda #hal_storage_save_write_name_len
    ldx save_slot_index
    cpx #1
    bcc !state_len_ready+
    clc
    adc #1
!state_len_ready:
    ldx #<hal_storage_save_write_name
    ldy #>hal_storage_save_write_name
    jsr ovl_save_open_output
    bcc !state_open+
    clc
    rts
!state_open:
    lda #$00
    jsr save_write_byte_raw
    lda #$c0
    jsr save_write_byte_raw
    :save_block(save_magic, SAVE_MAGIC_SIZE)
    lda #<save_block_table_pre_inventory
    sta zp_ptr1
    lda #>save_block_table_pre_inventory
    sta zp_ptr1_hi
    lda #SAVE_BLOCK_PRE_INVENTORY_COUNT
    jsr save_write_block_table
    jsr save_write_inventory_state
    :save_block(id_known_bits, ID_KNOWN_BYTES)
    lda #<save_block_table_post_known
    sta zp_ptr1
    lda #>save_block_table_post_known
    sta zp_ptr1_hi
    lda #SAVE_BLOCK_POST_KNOWN_COUNT
    jsr save_write_block_table
    lda #<save_block_table_door_state
    sta zp_ptr1
    lda #>save_block_table_door_state
    sta zp_ptr1_hi
    lda #SAVE_BLOCK_DOOR_STATE_COUNT
    jsr save_write_block_table
    jsr save_write_floor_items
    lda #<save_block_table_post_floor
    sta zp_ptr1
    lda #>save_block_table_post_floor
    sta zp_ptr1_hi
    lda #1
    jsr save_write_block_table
    lda save_io_error
    bne !close_fail+
    lda save_map_cksum_lo
    jsr save_write_byte_raw
    lda save_map_cksum_hi
    jsr save_write_byte_raw
    lda save_cksum_lo
    sta save_block_lo
    lda save_cksum_hi
    sta save_block_hi
    lda save_block_lo
    jsr save_write_byte_raw
    lda save_block_hi
    jsr save_write_byte_raw
    jsr ovl_save_close_output
    lda save_io_error
    bne !fail+
    sec
    rts
!close_fail:
    jsr ovl_save_close_output
!fail:
    clc
    rts

ovl_save_close_output:
    jsr save_restore_channels
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
    jsr SAVE_READST
    and #$83
    pha
    jsr c64_restore_vic_bank0_after_serial
    pla
    beq !done+
    lda #1
    sta save_io_error
!done:
    rts

ovl_save_open_output:
    jsr SAVE_SETNAM
    lda #hal_storage_save_file_num
    ldx save_device
    ldy #hal_storage_save_sec_write
    jsr SAVE_SETLFS
    jsr SAVE_OPEN
    bcs !done+
    ldx #hal_storage_save_file_num
    jsr SAVE_CHKOUT
    bcc !done+
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
    sec
!done:
    rts

    #import "../common/save_slot_menu.s"
    #import "../../../core/ui_disk_setup.s"
.segment ModalMiscOverlay
    #import "../../../core/ui_wizard.s"
    // Store init/restock is cold (new game, town re-entry); parks in this
    // overlay to fund door-aware bash in the items overlay. Reached via the
    // tramp_store_init_all/tramp_store_restock_all trampolines (OVL_MODAL_MISC).
    #import "../../../core/store_restock_overlay.s"
ovl_modal_misc_end:
.print "Modal-misc overlay: " + (ovl_modal_misc_end - $e000) + " bytes at $E000-$" + toHexString(ovl_modal_misc_end)
.assert "Modal-misc overlay fits in $E000-$EFFF", ovl_modal_misc_end <= $F000, true

// ============================================================
// Save overlay — C64 storage UI, split writer/loader, and staged reader
// ============================================================
.segment SaveOverlay
// OVL_SAVE is loaded before media swaps and remains resident through marker
// initialization, slot selection, writing, and loading.
ovl_save_prepare_stock_load:
    jsr ovl_save_krill_suspend
    jsr ovl_save_stage_chr_transport
    rts

ovl_save_krill_suspend:
    bit krill_active
    bpl !done+
    sei
    lda #BANK_NO_KERNAL
    sta $01
    lda #$03
    sta $dd02
    and $dd00
    sta $dd00
    jsr KRILL_RUNTIME_UNINSTALL
    lda #$03
    sta $dd00
    lda #0
    sta krill_active
    lda #$ff
    sta krill_suspended
!done:
    rts

ovl_save_stage_chr_transport:
    lda save_slot_index
    cmp #SAVE_SLOT_COUNT
    bcc !slot_ready+
    lda #0
    sta save_slot_index
!slot_ready:
    lda #<c64_load_transport_blob
    sta zp_ptr0
    lda #>c64_load_transport_blob
    sta zp_ptr0_hi
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    lda #<(c64_load_transport_blob_end - c64_load_transport_blob)
    sta save_count_lo
    lda #>(c64_load_transport_blob_end - c64_load_transport_blob)
    sta save_count_hi
!copy:
    lda save_count_lo
    ora save_count_hi
    beq !done+
    ldy #0
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    inc zp_ptr0
    bne !source_ready+
    inc zp_ptr0_hi
!source_ready:
    inc zp_ptr1
    bne !dest_ready+
    inc zp_ptr1_hi
!dest_ready:
    lda save_count_lo
    bne !dec_lo+
    dec save_count_hi
!dec_lo:
    dec save_count_lo
    bne !copy-
    lda save_count_hi
    bne !copy-
!done:
    rts

ovl_save_fast_load:
    lda #1
    sta load_stage_mode
    lda #<MAP_BASE
    sta load_stage_ptr_lo
    lda #>MAP_BASE
    sta load_stage_ptr_hi
    jsr ovl_save_patch_fast_names
    lda #<MAP_BASE
    sta KRILL_ZP_LOADADDR_LO
    lda #>MAP_BASE
    sta KRILL_ZP_LOADADDR_HI
    lda #<C64_V16_STATE_STAGE_END
    sta KRILL_ZP_BOUNDEND_LO
    lda #>C64_V16_STATE_STAGE_END
    sta KRILL_ZP_BOUNDEND_HI
    ldx #<ovl_save_state_name
    ldy #>ovl_save_state_name
    jsr KRILL_LOAD_FILE_BOUNDED
    bcc !state_loaded+
    jmp !bounded_error+
!state_loaded:
c64_test_split_state_loaded:
    lda MAP_BASE + SAVE_MAGIC_SIZE - 1
    cmp #SAVE_SPLIT_VERSION
    bcs !stage_version_ok+
    jmp !corrupt+
!stage_version_ok:
    lda #BANK_NO_KERNAL
    sta save_return_c64_bank + 1
    jsr load_parse_staged
    php
    lda #BANK_NO_BASIC
    sta save_return_c64_bank + 1
    plp
    bcs !stage_parsed+
    jmp !parse_corrupt+
!stage_parsed:
c64_test_split_state_parsed:
    lda load_stage_ptr_lo
    cmp #<C64_V16_STATE_STAGE_END
    beq !stage_end_lo_ok+
    jmp !parse_corrupt+
!stage_end_lo_ok:
    lda load_stage_ptr_hi
    cmp #>C64_V16_STATE_STAGE_END
    beq !stage_end_ok+
    jmp !parse_corrupt+
!stage_end_ok:
c64_test_split_state_exact:
    lda #<MAP_BASE
    sta KRILL_ZP_LOADADDR_LO
    lda #>MAP_BASE
    sta KRILL_ZP_LOADADDR_HI
    lda #<C64_V16_MAP_STAGE_END
    sta KRILL_ZP_BOUNDEND_LO
    lda #>C64_V16_MAP_STAGE_END
    sta KRILL_ZP_BOUNDEND_HI
    ldx #<ovl_save_map_name
    ldy #>ovl_save_map_name
    jsr KRILL_LOAD_FILE_BOUNDED
    bcc !map_loaded+
    jmp !corrupt+
!map_loaded:
c64_test_split_map_loaded:
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #<MAP_SIZE
    sta save_count_lo
    lda #>MAP_SIZE
    sta save_count_hi
!sum_loop:
    lda save_count_lo
    ora save_count_hi
    beq !sum_done+
    ldy #0
    lda (zp_ptr0),y
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !sum_no_carry+
    inc save_cksum_hi
!sum_no_carry:
    inc zp_ptr0
    bne !sum_ptr_ok+
    inc zp_ptr0_hi
!sum_ptr_ok:
    lda save_count_lo
    bne !sum_dec_lo+
    dec save_count_hi
!sum_dec_lo:
    dec save_count_lo
    jmp !sum_loop-
!sum_done:
    lda save_cksum_lo
    cmp save_map_cksum_lo
    bne !corrupt+
    lda save_cksum_hi
    cmp save_map_cksum_hi
    bne !corrupt+
    lda #0
    sta load_stage_mode
    lda #LOAD_RESULT_OK
    sta load_result
c64_test_split_fast_success:
    rts
!bounded_error:
c64_test_split_bounded_error:
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
.label c64_test_split_bounded_status = $033c
    sta c64_test_split_bounded_status
#endif
    cmp #KRILL_STATUS_LOAD_ADDRESS_MISMATCH
    beq !corrupt+
    cmp #KRILL_STATUS_FILE_TOO_SMALL
    beq !corrupt+
    cmp #KRILL_STATUS_FILE_TOO_LARGE
    beq !corrupt+
!fallback:
    lda #0
    sta load_stage_mode
    lda #1
    rts
!parse_corrupt:
c64_test_split_parse_corrupt:
    lda #0
    sta load_stage_mode
    lda #LOAD_RESULT_CORRUPT
    sta load_result
    lda #2
    rts
!corrupt:
    lda #0
    sta load_stage_mode
    lda #LOAD_RESULT_CORRUPT
    sta load_result
    ldx #HSTR_SAVE_CORRUPT
    jsr huff_print_msg
    lda #2
    rts

ovl_save_staged_read_block:
!loop:
    lda save_count_lo
    ora save_count_hi
    beq !done+
    jsr ovl_save_staged_read_byte_raw
    ldy #0
    sta (zp_ptr0),y
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !no_carry+
    inc save_cksum_hi
!no_carry:
    inc zp_ptr0
    bne !dest_ok+
    inc zp_ptr0_hi
!dest_ok:
    lda save_count_lo
    bne !dec_lo+
    dec save_count_hi
!dec_lo:
    dec save_count_lo
    jmp !loop-
!done:
    rts

ovl_save_staged_read_byte_raw:
    lda load_stage_ptr_lo
    sta zp_ptr2
    lda load_stage_ptr_hi
    sta zp_ptr2_hi
    ldy #0
    lda (zp_ptr2),y
    pha
    inc load_stage_ptr_lo
    bne !ptr_ok+
    inc load_stage_ptr_hi
!ptr_ok:
    pla
    rts

ovl_save_patch_fast_names:
    lda #0
    sta ovl_save_state_suffix
    sta ovl_save_map_suffix
    ldx save_slot_index
    cpx #SAVE_SLOT_COUNT
    bcc !slot_valid+
    ldx #0
    stx save_slot_index
!slot_valid:
    cpx #1
    bcc !done+
    txa
    clc
    adc #$31
    sta ovl_save_state_suffix
    sta ovl_save_map_suffix
!done:
    rts

ovl_save_state_name:
    .byte $54,$48,$45,$2e,$53,$41,$56,$45       // "THE.SAVE"
ovl_save_state_suffix: .byte 0
    .byte 0
ovl_save_map_name:
    .byte $54,$48,$45,$2e,$4d,$41,$50           // "THE.MAP"
ovl_save_map_suffix: .byte 0
    .byte 0

ovl_save_end:
.print "Save overlay: " + (ovl_save_end - $e000) + " bytes at $E000-$" + toHexString(ovl_save_end)
.assert "Save overlay fits in $E000-$EFFF", ovl_save_end <= $F000, true
.assert "C64 split map payload is 3840 bytes", C64_V16_MAP_PAYLOAD_SIZE, 3840
.assert "C64 split map PRG is 3842 bytes", C64_V16_MAP_FILE_SIZE, 3842
.const C64_V16_STATE_LAYOUT_SIZE = SAVE_MAGIC_SIZE + PL_STRUCT_SIZE + 160 + ZP_STATE_SIZE + 1 + ZP_RNG_SIZE + (TOTAL_INV_SLOTS * 8) + floor(ID_KNOWN_BYTES) + 12 + 12 + 4 + 5 + 5 + (STORE_TOTAL_SLOTS * 7) + 7 + 1 + (MAX_ROOMS * 6) + 1 + (MAX_TRAPS * 3) + (MAX_MONSTERS * MONSTER_ENTRY_SIZE) + 1 + (MAX_DOOR_STATES * 3) + (MAX_FLOOR_ITEMS * 11) + RECALL_DATA_SIZE
.assert "C64 v16 checksum covers exactly 2554 state bytes", C64_V16_STATE_LAYOUT_SIZE, C64_V16_STATE_CHECKSUM_SIZE
.assert "C64 v16 payload is state plus map and stored state checksums", C64_V16_STATE_PAYLOAD_SIZE, 2558
.assert "C64 v16 state PRG includes header", C64_V16_STATE_FILE_SIZE, 2560
.assert "C64 state stage endpoint is exclusive", C64_V16_STATE_STAGE_END, $C9FE
.assert "C64 map stage endpoint is exclusive", C64_V16_MAP_STAGE_END, $CF00

// ============================================================
// Spell overlay — spell/prayer execution at $E000
// ============================================================
.segment SpellOverlay
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_MAP_AREA_EXTERNAL
    #define PMX_DETECT_EFFECTS_EXTERNAL
    #import "../../../core/player_magic_slow_runtime.s"
    #define PMU_TURN_FEEDBACK_ONLY
    #import "../../../core/player_magic_turn_banked.s"
    #undef PMU_TURN_FEEDBACK_ONLY
    #import "../../../core/player_magic_execute_overlay.s"
    #undef PMX_DETECT_EFFECTS_EXTERNAL
    #undef PMX_MAP_AREA_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
    // Word of Destruction devastation engine: co-located with its only C64
    // callers (mage dispatch + scroll/staff router) in this overlay.
    #import "../../../core/player_destroy_area.s"
    // eff_find_traps / eff_destroy_traps_doors: only callers are the spell-exec
    // and utility code in this overlay, so park them here to free resident room.
    #import "../../../core/spell_effects_overlay.s"
    #define SCROLL_P3_EXISTING_OWNER
    #define SCROLL_P3_NEW_OWNER
    #import "../../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_NEW_OWNER
    #undef SCROLL_P3_EXISTING_OWNER
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $e000) + " bytes at $E000-$" + toHexString(ovl_spell_end)
.assert "Spell overlay fits in $E000-$EFFF", ovl_spell_end <= $F000, true

// ============================================================
// Help overlay — dedicated help modal screen at $E000
// ============================================================
.segment HelpOverlay
    #import "../../../core/ui_help_data.s"
    #import "../../../core/ui_help_page2_data.s"
    #import "../../../core/ui_help.s"
    #import "../../../core/ui_inventory.s"
    #import "../../../core/ui_equipment.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $F000, true
.assert "C64 marker initialization stays in storage overlay", disk_marker_init >= $E000 && disk_marker_init < ovl_save_end, true
.assert "C64 disk setup coordinator stays in storage overlay", disk_setup_run >= $E000 && disk_setup_run < ovl_save_end, true

// ============================================================
// UI overlay — low-frequency modal UI and symbol identify screens
// ============================================================
.segment UiOverlay
    #import "../../../core/ui_character.s"
    #import "../../../core/ui_identify.s"
    #import "../../../core/spell_names.s"
    #import "../../../core/player_magic_select_overlay.s"
    #import "../../../core/player_gain_spell_impl.s"
    #import "../../../core/player_magic_learn_op.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $F000, true

// ============================================================
// Item actions overlay — low-frequency read/aim/use/refuel commands
// ============================================================
.segment ItemActionsOverlay
    #define SCROLL_P3_ROUTER_ENABLED
    #import "../../../core/item_actions_overlay.s"
    #import "../../../core/ranged_fire.s"
    #import "../../../core/throw.s"
    #import "../../../core/bash.s"
    #import "../../../core/disarm.s"
    #import "../../../core/disarm_helpers.s"
    #import "../../../core/tunnel.s"
ovl_items_end:
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $F000, true

// ============================================================
// Dungeon generation overlay — town + dungeon generation at $E000
// ============================================================
// This segment produces the configured OVL.GEN PRG (loaded from disk as OVL.GEN).
// Loaded on demand whenever stairs are used or a new game starts.
// Shared constants and data tables stay in dungeon_data.s (main segment).
.segment DungeonGenOverlay
    #import "../../../core/dungeon_gen.s"
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_force_spell_target_monster_impl:
    lda zp_player_dlvl
    bne !have_dlvl+
    rts
!have_dlvl:
    lda c64_test_spell_return_pending
    beq !ready+
    rts
!ready:
    lda c64_test_spell_success_count
    cmp active_dungeon_count
    bcc !have_type+
    rts
!have_type:
    sta c64_test_spell_target_type
    lda zp_player_y
    sta c64_test_spell_target_y
    lda #1
    sta c64_test_spell_path_offset
!clear_path:
    lda zp_player_x
    clc
    adc c64_test_spell_path_offset
    sta c64_test_spell_target_x
    lda c64_test_spell_target_x
    ldy c64_test_spell_target_y
    jsr monster_find_at
    bcc !clear_tile+
    jsr monster_remove
!clear_tile:
    ldx c64_test_spell_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy c64_test_spell_target_x
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    inc c64_test_spell_path_offset
    lda c64_test_spell_path_offset
    cmp #7
    bcc !clear_path-
    lda c64_test_spell_target_x
    sta ms_spawn_x
    lda c64_test_spell_target_y
    sta ms_spawn_y
    lda c64_test_spell_target_type
    jsr monster_spawn_one
    bcs !spawned+
    rts
!spawned:
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    lda #0
    sta current_tier
    sta tier_loaded
    rts

c64_test_spell_target_x: .byte 0
c64_test_spell_target_y: .byte 0
c64_test_spell_target_type: .byte 0
c64_test_spell_path_offset: .byte 0
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_force_detect_evil_monster_impl:
    ldx #0
!spawn_loop:
    lda zp_player_y
    sta c64_test_detect_row
    ldy c64_test_detect_offsets,x
    sty c64_test_detect_offset
    lda zp_player_x
    clc
    adc c64_test_detect_offset
    sta c64_test_detect_col
    ldy c64_test_detect_row
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy c64_test_detect_col
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !next+
    ldy c64_test_detect_col
    :MapRead_ptr0_y()
    and #(TILE_TYPE_MASK | FLAG_LIT)
    :MapWrite_ptr0_y()
    lda c64_test_detect_col
    sta ms_spawn_x
    lda c64_test_detect_row
    sta ms_spawn_y
    lda c64_test_detect_types,x
    jsr monster_spawn_one
!next:
    inx
    cpx #5
    bcc !spawn_loop-
    rts

c64_test_detect_row: .byte 0
c64_test_detect_col: .byte 0
c64_test_detect_offset: .byte 0
c64_test_detect_offsets:
    .byte 6, 8, 10, 12, 14
c64_test_detect_types:
    .byte 0, 4, 8, 14, 22
#endif

ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $F000, true


// ============================================================
// Chest overlay — chest open/disarm/bash handlers at $E000 (cold;
// REU-stashed when an REU is present, disk otherwise)
// ============================================================
.segment ChestOverlay
    #import "../../../core/chest.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $e000) + " bytes at $E000-$" + toHexString(ovl_chest_end)
.assert "Chest overlay fits in $E000-$EFFF", ovl_chest_end <= $F000, true
.assert "irq_no_blink begins with CLD", irq_no_blink_after_cld == irq_no_blink + 1, true
