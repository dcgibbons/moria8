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
.eval var OVL_OUT = "out"
.if (cmdLineVars.containsKey("OVL_OUT")) {
    .eval OVL_OUT = cmdLineVars.get("OVL_OUT")
}
.segmentdef StartupOverlay    [outPrg=OVL_OUT + "/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg=OVL_OUT + "/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg=OVL_OUT + "/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef ModalMiscOverlay      [outPrg=OVL_OUT + "/ovl.modal", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items", start=$e000, min=$e000, max=$efff]
.segmentdef SpellOverlay      [outPrg=OVL_OUT + "/ovl.spell", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",   start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeBanked     [outPrg=OVL_OUT + "/64.bank",   start=$f000, min=$f000, max=$fffa]

#import "hal/storage_policy.s"
#import "../common/save_slot_policy.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(entry)

// ============================================================
// Imports — order matters: labels must be defined before use
// ============================================================
.pc = $080e "Program"

// Bootstrap — MUST live below $A000 so BASIC's SYS can reach it
// before BASIC ROM is banked out.
entry:
    lda #$36                // Bank out BASIC ROM (keep KERNAL + I/O)
    sta $01
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
    lda $dd00
    ora #%00000011          // Restore VIC-II bank 0 (serial I/O may have corrupted)
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
    bcc !cdmw_open_ok+
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
#if C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
c64_test_save_media_fail_armed: .byte 0
#endif
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
c64_test_restart_after_save_armed: .byte 0
#endif
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
c64_test_disk_setup_single_drive_return_armed: .byte 0
#endif
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
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
    jsr c64_restore_vic_bank0_after_serial
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

c64_disk_chrin:
    jsr c64_disk_call
    .word $ffcf
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
    bcc !cdmp_open_ok+
    bcs !cdmp_open_fail+
!cdmp_open_ok:
    ldx #hal_storage_check_file_num
    jsr $ffc6
    bcc !cdmp_chkin_ok+
    bcs !cdmp_read_fail+
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
!cdmp_read_fail:
    jmp !cdmp_close-
!cdmp_marker_fail:
    jmp !cdmp_close-
!cdmp_open_fail:
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
#import "../common/reu.s"
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
#import "../../../core/generation_busy.s"
#import "../../../core/stat_display.s"
#import "../../../core/sound.s"
#import "../../../core/huffman.s"
#import "../../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../../core/dungeon_features.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../../core/monster.s"
#import "../../../core/tier_manager.s"

// Overlay state is platform-owned so product/test variant layout changes
// cannot place these bytes inside later resident code.
current_overlay: .byte 0
ovl_reu_start_lo: .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
ovl_reu_start_hi: .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
ovl_reu_size_lo:  .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
ovl_reu_size_hi:  .byte 0, 0, 0, 0, 0, 0, 0, 0, 0
ol_target:        .byte 0

#define OVERLAY_LOAD_PROMPT_GAME
#import "../common/overlay.s"
#undef OVERLAY_LOAD_PROMPT_GAME
#import "../../../core/monster_ai.s"
#import "../../../core/recall.s"
#import "../../../core/monster_magic.s"
#import "../../../core/item.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../../../core/player_items.s"
#import "../../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../core/player_magic_state.s"
#import "../../../core/player_magic_state_ops.s"
#import "../../../core/player_magic.s"
#import "dungeon_render.s"
#import "../../../core/dungeon_los.s"
#import "../../../core/player_move.s"
#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../../../core/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../../../core/projectile.s"
#import "../../../core/monster_attack.s"
#import "../../../core/turn.s"
#import "../../../core/store_data.s"
#import "../../../core/runtime_ui_strings.s"
#import "../common/compat/io_kernal_consts.s"
#import "../common/save.s"
#import "../common/disk_swap.s"
#import "../../../core/score_io.s"
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

    // BASIC ROM already banked out by bootstrap above

    // Load banked runtime payload to $F000 before any $F000 trampoline calls.
    jsr init_load_banked

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
    lda #$ff
    sta save_slot_index
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    lda c64_test_restart_after_save_armed
    beq !restart_test_done+
c64_test_after_save_restart_start:
    lda #0
    sta c64_test_restart_after_save_armed
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
    lda #2
    sta disk_setup_done
    lda #0
    sta save_slot_index
    lda #OVL_HELP
    jsr overlay_load
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
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
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
    bcs title_enter_menu
!load_now:
    jmp title_load_game
!not_l:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    bcs title_enter_menu
    jsr disk_prompt_game_required
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda #1
    sta c64_test_disk_setup_single_drive_return_armed
#endif
#if C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT
c64_test_after_disk_setup_product:
#endif
    jmp title_enter_menu
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
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
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
#endif
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    // Fail closed on the explicit load carry result before resuming gameplay.
    bcc !title_load_fail+
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
c64_test_single_drive_load_return_before_program_prompt:
    jmp c64_test_single_drive_load_return_loaded_low
#endif
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
c64_test_load_then_save_new_empty_loaded:
c64_test_load_then_save_new_empty_before_save:
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
    jmp title_enter_menu

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
    lda $dc0d
    lda $dd0d
    lda $d019
    sta $d019
    pla
    rti

c64_install_ram_irq_vectors:
    php
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL
    sta $01
    lda #<c64_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>c64_irq_hidden_rom
    sta $fffb
    sta $ffff
    pla
    sta $01
    plp
    rts

.label hal_irq_install_runtime = c64_install_ram_irq_vectors

// ============================================================
// kernal_load_safe — KERNAL LOAD wrapper for C64
// ============================================================
kernal_load_safe:
    jsr $ffd5               // KERNAL LOAD — carry set on error
    php                     // Preserve carry for caller
    jsr platform_runtime_resync_c64
    plp
    rts

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

c64u_turbo_force_normal:
    lda c64_hw_flags
    and #C64_HW_TURBO_AVAIL
    beq !done+
    lda #0
    sta c64u_turbo_depth
    lda #C64U_TURBO_NORMAL
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
    sei
    dec $01                     // $36 -> $35 — I/O visible for color RAM
    jsr title_show_sysinfo_banked
    inc $01
    cli
    rts
tsi_krev_cached: .byte 0

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
    lda $dd00
    ora #%00000011
    sta $dd00
    cli
    rts

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

#if !BYPASS_SLOT_PROMPT
save_prepare_slot_prompt:
    lda #OVL_MODAL_MISC
    jmp overlay_load_no_kernal

save_select_slot_prompt:
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr save_select_slot_prompt_impl
    jmp platform_runtime_resync_c64
#endif

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

tramp_ui_char_display:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_char_display
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
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_recall_display
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

tramp_eff_earthquake:
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr c64u_turbo_fast
    jsr eff_earthquake_banked
    jsr c64u_turbo_normal
    rts

tramp_item_refuel:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr item_refuel
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
    lda #BANK_NO_BASIC
    sta $01
    cli
    jsr tier_restore_after_overlay
!done:
    jmp tramp_sr_epilogue

tramp_ui_wizard_display:
    jmp wizard_40col_menu_display

tramp_disk_setup:
    lda #OVL_HELP
    jsr overlay_load
    bcs !tds_done+
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr disk_setup_run
    jmp tramp_sr_epilogue

!tds_done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_HELP
    jsr overlay_load
    bcs !tdps_done+
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr disk_setup_prepare_selected
    php
    jsr platform_runtime_resync_c64
    plp
!tdps_done:
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

tramp_store_init_all:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr store_init_all
!done:
    jmp tramp_sr_epilogue

tramp_store_restock_all:
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs !done+
    jsr store_restock_all
!done:
    jmp tramp_sr_epilogue

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
test_inventory_title_str: .text "Inventory" ; .byte 0
test_beginner_book_str:   .text "Beginner's Spellbook" ; .byte 0
test_mage_book_title_str: .text "Mage Book" ; .byte 0
test_magic_missile_str:   .text "Magic Missile" ; .byte 0
test_phase_door_str:      .text "Phase Door" ; .byte 0
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
    lda #<test_mage_book_title_str
    sta zp_ptr0
    lda #>test_mage_book_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #14
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<test_magic_missile_str
    sta zp_ptr0
    lda #>test_magic_missile_str
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<test_phase_door_str
    sta zp_ptr0
    lda #>test_phase_door_str
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

#if C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT
c64_test_disk_setup_fail_input_sym:
    brk
#endif

#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
c64_test_save_write_fail_input_sym:
    brk
#endif

#if C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
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
    cmp #DEATH_TRAP_PIT         // Special sources ($F9-$FF) don't need name
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name       // Copies name to creature_name_buf in main RAM

!tgo_load_overlay:
    // 2. Load death overlay (replaces tier data at $E000)
    lda #OVL_DEATH
    jsr overlay_load
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
    jsr disk_prompt_game
    lda #BANK_NO_BASIC
    sta $01
    cli
    lda #hal_storage_modal_misc_name_len
    ldx #<hal_storage_modal_misc_name
    ldy #>hal_storage_modal_misc_name
    jsr hal_asset_load_prg_header
#if C64_TEST_SCRIPTED_RETIREMENT_PRODUCT
    bcc !retirement_loaded+
    jmp c64_test_retirement_fail_sym
!retirement_loaded:
    jmp c64_test_retirement_pass_sym
#else
    bcs !done+
#endif
    lda #0
    sta current_overlay
    sei
    lda #BANK_NO_KERNAL
    sta $01
    jsr royal_screen
    inc $01
    cli
!done:
    rts

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

// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.assert "Program fits below MAP_BASE", program_end <= MAP_BASE, true

// ============================================================
// Init-only code below — lives past CREATURE_BASE, safe because
// it runs once at startup before dungeon map or RLE workspace
// are used. Overwritten during normal gameplay.
// ============================================================

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
    lda #0
    ldx #$00
    ldy #$f0
    jsr KERNAL_LOAD
    php
    lda #2
    jsr KERNAL_CLOSE
    jsr KERNAL_CLRCHN
    sei
    lda $dd00
    ora #%00000011
    sta $dd00
    lda #BANK_NO_BASIC
    sta $01
    plp
    bcs !load_failed+
    rts
!load_failed:
    lda #2
    sta $d020
    jmp !load_failed-

c64_banked_fname:
    .byte $36,$34,$2e,$42,$41,$4e,$4b  // "64.BANK" in PETSCII/ASCII bytes
.label c64_banked_fname_len = * - c64_banked_fname

// ============================================================
// Banked runtime payload — loadable PRG at $F000.
// ============================================================
.segment RuntimeBanked
    #import "../../../core/special_rooms.s"
    #import "../../../core/ego_items.s"
    #import "../../../core/title_sysinfo_banked.s"
    #import "../common/reu_loading_banked.s"
    #import "../../../core/ui_home.s"
    #import "../../../core/ui_recall.s"
    #import "../../../core/item_desc_banked.s"
    #import "../common/disk_setup_banked.s"
    #import "../../../core/player_magic_learn_op.s"
    #define PM_MAP_BANKED
    #import "../../../core/player_magic_map.s"
    #undef PM_MAP_BANKED
    #import "../../../core/player_magic_turn_banked.s"
    #import "../../../core/player_magic_slow_runtime.s"
    #define PM_EQ_BANKED
    #import "../../../core/player_magic_earthquake.s"
    #undef PM_EQ_BANKED

banked_code_end:

.print "Banked runtime: " + (banked_code_end - $f000) + " bytes at $F000-$" + toHexString(banked_code_end)
.assert "Banked code fits below CPU vectors", banked_code_end <= $FFFA, true

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
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    lda #1
    sta c64_test_restart_after_save_armed
#endif
    lda #>(title_enter_menu - 1)
    pha
    lda #<(title_enter_menu - 1)
    pha
    jmp platform_runtime_resync_c64

    #import "../../../core/score.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $F000, true

// ============================================================
// Modal-misc overlay — winner retirement art at $E000
// ============================================================
.segment ModalMiscOverlay
    #import "../../../core/royal.s"
    #import "../common/save_slot_menu.s"
ovl_modal_misc_end:
.print "Modal-misc overlay: " + (ovl_modal_misc_end - $e000) + " bytes at $E000-$" + toHexString(ovl_modal_misc_end)
.assert "Modal-misc overlay fits in $E000-$EFFF", ovl_modal_misc_end <= $F000, true

// ============================================================
// Spell overlay — spell/prayer execution at $E000
// ============================================================
.segment SpellOverlay
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_MAP_AREA_EXTERNAL
    #define PMU_VISIBLE_FLAGGED_EXTERNAL
    #import "../../../core/player_magic_execute_overlay.s"
    #undef PMU_VISIBLE_FLAGGED_EXTERNAL
    #undef PMX_MAP_AREA_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
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
    #import "../../../core/ui_disk_setup.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $F000, true

// ============================================================
// UI overlay — low-frequency modal UI and symbol identify screens
// ============================================================
.segment UiOverlay
    #import "../../../core/ui_character.s"
    #import "../../../core/ui_identify.s"
    #import "../../../core/spell_names.s"
    #import "../../../core/player_magic_select_overlay.s"
    #import "../../../core/player_gain_spell_impl.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $F000, true

// ============================================================
// Item actions overlay — low-frequency read/aim/use/refuel commands
// ============================================================
.segment ItemActionsOverlay
    #import "../../../core/store_restock_overlay.s"
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

ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $F000, true
.assert "irq_no_blink begins with CLD", irq_no_blink_after_cld == irq_no_blink + 1, true
