// input.s — Keyboard input and command parsing
//
// Uses KERNAL GETIN ($FFE4) to read keyboard buffer.
// Maps PETSCII key codes to internal command IDs.
// Supports vi-keys (HJKLYUBN) for 8-direction movement
// Numeric repeat prefixes are intentionally unimplemented.
// `zp_input_count` is currently fixed to 1 for all commands.

#import "../../../core/input_contract.s"
#import "../../../core/input_tables.s"
#import "../../../core/input_run_cancel.s"
//
// Note: GETIN returns PETSCII codes. We convert to command IDs
// via a lookup table. The KERNAL IRQ handler must remain active
// for keyboard scanning to work.

// KERNAL vectors
.const KERNAL_GETIN = $ffe4

// Keyboard/CIA registers
.const KBDBUF_COUNT = $c6
.const hal_input_kbdbuf_count = KBDBUF_COUNT
.const hal_input_modal_dismiss_uses_fast_key = false
.const hal_input_followup_uses_fast_key = false
.const hal_input_selectable_overlay_prepare_followup = false
.const hal_input_modal_escape_primary = $03
.const hal_input_modal_escape_secondary = $1b
.const hal_input_flush_run_cancel_buffer = true
.const hal_input_help_footer_uses_esc_stop = false
.const hal_input_inventory_letter_normalize_shifted = false
.const KERNAL_SHIFT_MODE = $0291
.const KERNAL_CHARSET_SWITCH_LOCK = $80
.const CIA1_PORTA   = $dc00
.const CIA1_PORTB   = $dc01
.const CIA1_DDRA    = $dc02
.const CIA1_DDRB    = $dc03

// ============================================================
// Subroutines
// ============================================================

// input_lock_charset_switch — Disable KERNAL Shift+C= charset switching.
// The game owns the active C64 charset; the KERNAL scanner must not let
// Commodore+Shift toggle $D018 while IRQ-backed input is active.
// Preserves: X, Y
input_lock_charset_switch:
    lda #KERNAL_CHARSET_SWITCH_LOCK
    sta KERNAL_SHIFT_MODE
    rts

// input_get_key — Wait for a keypress, return PETSCII code
// Output: A = PETSCII code of key pressed
// Banking-safe + IRQ-safe: banks in KERNAL, enables IRQ for keyboard
// scanning, polls until key available, then restores original banking
// and interrupt state. Works from ANY context — main game (CLI/$36),
// overlays (SEI/$34), or banked code (SEI/$34).
// NOTE: Polls $C6 (keyboard buffer count) before calling GETIN.
// GETIN sets $CC=$C6 internally — calling with $C6>0 keeps $CC
// non-zero, preventing KERNAL cursor blink from corrupting color RAM.
// Preserves: X, Y
// input_run_key_held — Non-blocking: returns nonzero if any key is physically held
// Used by the pre-arm running path in game_loop.s. This must ignore KERNAL
// key-repeat semantics; buffered repeats would cancel a run after a short delay.
// Output: A = nonzero if any key held, 0 if no key
// Preserves: X, Y
input_run_key_held:
#if C64_TEST_SCRIPTED_SPELL || C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT || C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT || C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT || C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SCROLL_SELECTOR
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    lda #0
    rts
#else
    lda $01
    pha
    php
    sei
    lda #BANK_NO_BASIC
    sta $01

    lda CIA1_PORTA
    sta irk_save_pra
    lda CIA1_DDRA
    sta irk_save_ddra
    lda CIA1_DDRB
    sta irk_save_ddrb

    lda #$ff
    sta CIA1_DDRA
    lda #$00
    sta CIA1_DDRB
    lda #$00
    sta CIA1_PORTA
    lda CIA1_PORTB
    cmp #$ff
    beq !irk_none+
    lda #1
    bne !irk_store+
!irk_none:
    lda #0
!irk_store:
    sta irk_result

    lda irk_save_pra
    sta CIA1_PORTA
    lda irk_save_ddra
    sta CIA1_DDRA
    lda irk_save_ddrb
    sta CIA1_DDRB

    plp
    pla
    sta $01
    lda irk_result
    rts
#endif
#endif
#endif
#endif
#endif

// input_run_key_check — Backward-compatible alias for held-state polling
input_run_key_check:
    jmp input_run_key_held

// input_run_cancel_check — Non-blocking run cancel poll
// Uses the same edge detector contract as C128, but samples only physical held state.
input_run_cancel_check:
    jsr input_run_key_held
    jmp input_run_process_sample

irk_save_pra:  .byte 0
irk_save_ddra: .byte 0
irk_save_ddrb: .byte 0
irk_result: .byte 0

.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
.label hal_input_get_command = input_get_command
.label hal_input_wait_release = input_wait_release
.label hal_input_any_key_held = input_run_key_held
.label hal_input_run_cancel_check = input_run_cancel_check
.label hal_input_followup_prepare = input_noop
.label hal_input_modal_prepare = input_modal_prepare
.label hal_input_modal_finish = input_noop

input_modal_prepare:
    lda #0
    sta KBDBUF_COUNT
    jmp input_wait_release

input_noop:
    rts

input_get_key:
#if C64_TEST_SCRIPTED_SPELL || C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT || C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT || C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT || C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
    ldx c64_test_input_idx
    lda c64_test_input_script,x
    bne !igk_script_ok+
#if C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT
    lda disk_setup_done
    bne !igk_disk_setup_done+
    jmp c64_test_disk_setup_fail_input_sym
!igk_disk_setup_done:
    jmp c64_test_after_disk_setup_product
#else
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    brk
#else
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    jmp c64_test_save_write_fail_input_sym
#else
#if C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
    jmp c64_test_save_write_fail_input_sym
#else
#if C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT
    jmp c64_test_change_save_drive_unexpected_return
#else
#if C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT
    jmp c64_test_load_resume_fail_input_sym
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT
!igk_exhaust_wait:
    jmp !igk_exhaust_wait-
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT
!igk_exhaust_wait:
    jmp !igk_exhaust_wait-
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
!igk_exhaust_wait:
    jmp !igk_exhaust_wait-
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    jmp c64_test_single_drive_fresh_save_unexpected_return
#else
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    jmp c64_test_load_then_save_new_empty_fail
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
    jmp c64_test_load_resume_fail_input_sym
#else
#if C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT
    jmp c64_test_load_missing_save_fail_input_sym
#else
#if C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
    jmp c64_test_dungeon_ascent_fail_input_sym
#else
    jmp c64_test_spell_fail_input_sym
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
!igk_script_ok:
    inx
    stx c64_test_input_idx
    rts
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SCROLL_SELECTOR
    ldx c64_test_input_idx
    lda c64_test_input_script,x
    bne !igk_book_script_ok+
#if C64_TEST_SCRIPTED_SCROLL_SELECTOR
    jmp c64_test_scroll_selector_fail_input_sym
#else
    jmp c64_test_book_overlay_fail_input_sym
#endif
!igk_book_script_ok:
    inx
    stx c64_test_input_idx
    rts
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
    ldx c64_test_input_idx
    lda c64_test_input_script,x
    bne !igk_list_script_ok+
    jmp c64_test_spell_list_overlay_fail_input_sym
!igk_list_script_ok:
    inx
    stx c64_test_input_idx
    rts
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    ldx c64_test_input_idx
    lda c64_test_input_script,x
    bne !igk_dungeon_script_ok+
    jmp c64_test_spell_fail_input_sym
!igk_dungeon_script_ok:
    inx
    stx c64_test_input_idx
    rts
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    ldx c64_test_input_idx
    lda c64_test_input_script,x
    bne !igk_detect_script_ok+
    jmp c64_test_spell_fail_input_sym
!igk_detect_script_ok:
    inx
    stx c64_test_input_idx
    rts
#else
    php                     // Save processor flags (preserves I flag)
    lda $01
    pha
    lda #BANK_NO_BASIC      // $36 — KERNAL + I/O, no BASIC ROM
    sta $01
#if C64_PRODUCT_IRQ_VECTOR_RUNTIME
    jsr c64_install_ram_irq_vectors
#endif
    jsr input_lock_charset_switch
    cli                     // Enable IRQ — keyboard scan needs it
!igk_poll:
    inc zp_entropy
    jsr input_sound_update
    jsr input_ctrl_r_held
    beq !igk_no_ctrl_r+
    lda #$12
    sta igk_key
    jmp !igk_done+
!igk_no_ctrl_r:
    lda KBDBUF_COUNT        // Keyboard buffer count (filled by IRQ handler)
    beq !igk_poll-          // No key yet, keep polling
    jsr KERNAL_GETIN        // Read key ($CC set to non-zero = blink suppressed)
    sta igk_key
!igk_done:
    sei
    pla
    sta $01                 // Restore original banking state
#if C64_PRODUCT_IRQ_VECTOR_RUNTIME
    jsr c64_install_ram_irq_vectors
#endif
    plp                     // Restore original I flag (SEI if was SEI)
    lda igk_key
    rts
#endif
#endif
#endif
#endif
#endif
igk_key: .byte 0

// input_wait_release — Drain pending buffered keys and wait until no key is pending
// Used before one-shot "press any key" prompts so a prior selection key does
// not auto-dismiss the next screen.
// Preserves: X, Y
input_wait_release:
#if C64_TEST_SCRIPTED_SPELL || C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT || C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT || C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT || C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
    rts
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SCROLL_SELECTOR
    rts
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
    rts
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    rts
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    rts
#else
    php                     // Save processor flags (preserves I flag)
    lda $01
    pha
    lda #BANK_NO_BASIC      // $36 — KERNAL + I/O, no BASIC ROM
    sta $01
#if C64_PRODUCT_IRQ_VECTOR_RUNTIME
    jsr c64_install_ram_irq_vectors
#endif
    jsr input_lock_charset_switch
    cli                     // Keep KERNAL keyboard IRQ scanning active

    // Drain any already-buffered keypresses.
!iwr_drain:
    inc zp_entropy
    jsr input_sound_update
    lda KBDBUF_COUNT
    beq !iwr_wait+
    jsr KERNAL_GETIN
    jmp !iwr_drain-

    // Require two consecutive empty-buffer polls for stability.
!iwr_wait:
    inc zp_entropy
    jsr input_sound_update
    lda KBDBUF_COUNT
    bne !iwr_drain-
    jsr input_run_key_held
    bne !iwr_wait-
    lda KBDBUF_COUNT
    bne !iwr_drain-

    sei
    pla
    sta $01                 // Restore original banking state
#if C64_PRODUCT_IRQ_VECTOR_RUNTIME
    jsr c64_install_ram_irq_vectors
#endif
    plp                     // Restore original I flag
    rts
#endif
#endif
#endif
#endif
#endif

input_sound_update:
#if C64_PRODUCT_SOUND_UPDATE_FROM_INPUT
    jmp hal_sound_update
#else
    rts
#endif

// input_ctrl_r_held — Detect physical C64 CTRL+R regardless of KERNAL PETSCII.
// The KERNAL keyboard buffer does not provide a reliable command code for this
// chord across real hardware/emulator keymaps, so command input checks the CIA
// matrix directly while polling.
// Output: A = 1 when both CTRL and R are down, 0 otherwise
// Preserves: X, Y
input_ctrl_r_held:
#if C64_TEST_SCRIPTED_SPELL || C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT || C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT || C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT || C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SCROLL_SELECTOR
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    lda #0
    rts
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    lda #0
    rts
#else
    lda CIA1_PORTA
    pha
    lda CIA1_DDRA
    pha
    lda CIA1_DDRB
    pha

    lda #$ff
    sta CIA1_DDRA
    lda #$00
    sta CIA1_DDRB

    lda #$fb                // Row 2: R is column 1
    sta CIA1_PORTA
    lda CIA1_PORTB
    and #%00000010
    bne !not_held+

    lda #$7f                // Row 7: CTRL is column 2
    sta CIA1_PORTA
    lda CIA1_PORTB
    and #%00000100
    bne !not_held+

    lda #1
    bne !done+
!not_held:
    lda #0
!done:
    sta icr_result
    pla
    sta CIA1_DDRB
    pla
    sta CIA1_DDRA
    pla
    sta CIA1_PORTA
    lda icr_result
    rts
#endif
#endif
#endif
#endif
#endif

icr_result: .byte 0

#if C64_TEST_SCRIPTED_SPELL || C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT || C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT || C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT || C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT || C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT || C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT || C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT || C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
c64_test_input_idx: .byte 0
c64_test_input_script:
#if C64_TEST_SCRIPTED_DISK_SETUP_PRODUCT
    .byte $44              // D = Disk Setup from title
    .byte $32              // 2 = save drive
    .byte $39              // 9
    .byte $0d              // RETURN
    .byte $33              // 3 = done
    .byte $20              // SPACE = inserted save disk prompt
    .byte $59              // Y = initialize missing marker
    .byte $00
#else
#if C64_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    .byte $44              // D = Disk Setup from title
    .byte $33              // 3 = done; keep default save drive 8
    .byte $20              // SPACE = inserted save disk prompt
    .byte $59              // Y = initialize missing marker
    .byte $20              // SPACE = acknowledge insert-program-disk prompt
    .byte $00
#else
#if C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    .byte $4c              // L = load from title
    .byte $32              // 2 = save drive if Disk Setup prompts
    .byte $39              // 9
    .byte $0d              // RETURN
    .byte $33              // 3 = done
    .byte $20              // SPACE = acknowledge insert-save-disk prompt
    .byte $59              // Y = initialize marker if the fixture marker is not accepted
    .byte $d3              // SHIFT+S = absorbed by post-load fresh-key path
    .byte $d3              // SHIFT+S = save in gameplay
    .byte $59              // Y = overwrite existing save
    .byte $53              // S = start from title after save
#else
#if C64_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
    .byte $4c              // L = load from title
    .byte $32              // 2 = save drive if Disk Setup prompts
    .byte $39              // 9
    .byte $0d              // RETURN
    .byte $33              // 3 = done
    .byte $20              // SPACE = acknowledge insert-save-disk prompt
    .byte $59              // Y = initialize marker if the fixture marker is not accepted
    .byte $d3              // SHIFT+S = absorbed by post-load fresh-key path
    .byte $d3              // SHIFT+S = save in gameplay
    .byte $20              // SPACE = dismiss save-disk prompt
    .byte $20              // SPACE = dismiss disk error
    .byte $00
#else
#if C64_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT
    .byte $20              // SPACE = dismiss saved message if shown
    .byte $00
#else
#if C64_TEST_SCRIPTED_LOAD_RESUME_PRODUCT
    .byte $4c              // L = load from title
    .byte $32              // 2 = save drive if Disk Setup prompts
    .byte $39              // 9
    .byte $0d              // RETURN
    .byte $33              // 3 = done
    .byte $00
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
    .byte $20              // SPACE = acknowledge save-disk prompt before loading
    .byte $20              // SPACE = dismiss program-disk prompt after harness swap
    .byte $20              // SPACE = spare modal dismiss if KERNAL prints status text
    .byte $20              // SPACE = fail-safe extra prompt budget
    .byte $00
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT
    .byte $20              // SPACE = acknowledge title save-disk prompt
    .byte $20              // SPACE = leave program disk in at setup insert prompt
    .byte $00
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
    .byte $20              // SPACE = acknowledge save-disk prompt
    .byte $20              // SPACE = dismiss corrupt-save prompt
    .byte $20              // SPACE = acknowledge insert-program-disk prompt
    .byte $00
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    .byte $20              // SPACE = acknowledge insert-save-disk prompt
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT
    .byte $4e              // N = do not initialize fresh save disk
#else
    .byte $59              // Y = initialize fresh save disk
    .byte $20              // SPACE = acknowledge insert-program-disk prompt
#endif
    .byte $00
#else
#if C64_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    .byte $20              // SPACE = acknowledge load save-disk prompt
    .byte $20              // SPACE = acknowledge save save-disk prompt
    .byte $59              // Y = initialize fresh save disk
    .byte $59              // Y = tolerate repeated initialize prompt after media settle
    .byte $20              // SPACE = acknowledge insert-program-disk prompt
    .byte $00
#else
#if C64_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT
    .byte $20              // SPACE = acknowledge first save-disk prompt
    .byte $20              // SPACE = leave program disk in at setup insert prompt
    .byte $20              // SPACE = dismiss program-disk warning
    .byte $00
#else
#if C64_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT
    .byte $4c              // L = load from title
    .byte $20              // SPACE = dismiss missing-save message
    .byte $20              // SPACE = dismiss single program-disk prompt
    .byte $00
#else
#if C64_TEST_SCRIPTED_DUNGEON_ASCENT_PRODUCT
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4c              // L = step onto town stairs
    .byte $3e              // > = descend into dungeon
    .byte $3c              // < = immediately ascend from dungeon up-stairs
    .byte $00
#else
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    .byte $43              // C = priest
#else
    .byte $42              // B = mage
#endif
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    .byte $4c              // L = step onto town stairs
    .byte $3e              // > = descend into dungeon
    .byte $50, $41, $41    // P A A = pray Detect Evil once
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
#else
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
    .byte $4d, $41, $41, $4c, $20
#endif
    .byte $00
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif
#endif

#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SCROLL_SELECTOR
c64_test_input_idx: .byte 0
c64_test_input_script:
#if C64_TEST_SCRIPTED_SCROLL_SELECTOR
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $52              // R = read scroll
    .byte $3f              // ? = inventory overlay from scroll prompt
    .byte $41              // A = first visible scroll
    .byte $00
#else
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4d              // M = cast
    .byte $3f              // ? = inventory overlay from book prompt
    .byte $00
#endif
#endif

#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
c64_test_input_idx: .byte 0
c64_test_input_script:
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4d              // M = cast
    .byte $41              // A = first visible book
    .byte $3f              // ? = spell list overlay
    .byte $00
#endif

#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_input_idx: .byte 0
c64_test_input_script:
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4c              // L = step onto town stairs
    .byte $3e              // > = descend into dungeon
    .for (var i = 0; i < 24; i++) {
        .byte $4d, $41, $41, $4c // M A A L = Magic Missile east
    }
    .byte $00
#endif

#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_input_idx: .byte 0
c64_test_input_script:
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $43              // C = priest
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $50, $41, $41    // P A A = pray Detect Evil once
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $2e, $2e, $2e, $2e
    .byte $00
#endif

// input_get_command — Wait for a keypress, return command ID
// Output: A = command ID (CMD_* constant)
//         zp_input_cmd = same
//         zp_input_count = repeat count (currently always 1; numeric prefixes are deferred)
// Preserves: nothing
input_get_command:
    // Flush keyboard buffer to discard keys pressed during rendering
    lda #0
    sta KBDBUF_COUNT        // KERNAL keyboard buffer count

    lda #1
    sta zp_input_count      // Default repeat count = 1
    // Numeric repeat prefixes are not implemented.
    // Keep `zp_input_count` pinned to 1 until the feature is explicitly revived.

!get_key:
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_RUN
    beq !run_prefix+
    cmp #CMD_NONE
    beq !get_key-           // Unknown key, try again

    sta zp_input_cmd
    rts

!run_prefix:
    jsr input_wait_release
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_MOVE_N
    bcc !get_key-
    cmp #CMD_MOVE_SE + 1
    bcs !get_key-
    clc
    adc #(CMD_RUN_N - CMD_MOVE_N)
    sta zp_input_cmd
    rts

// petscii_to_command — Convert PETSCII key code to command ID
// Input:  A = PETSCII code
// Output: A = command ID
// Preserves: X, Y
petscii_to_command:
    // Check the key mapping table
    ldx #0
!loop:
    cmp key_map_petscii,x
    beq !found+
    inx
    cpx #key_map_count
    bcc !loop-
    // Not found
    lda #CMD_NONE
    rts
!found:
    lda key_map_cmd,x
    rts

// ============================================================
// Key mapping table
// PETSCII codes → command IDs
// C64 PETSCII: uppercase letters are $41-$5A in shifted mode,
// but in unshifted mode (which we use), pressing a letter key
// produces $41-$5A regardless. KERNAL GETIN returns these codes.
// ============================================================

key_map_petscii:
    :EmitBasePetsciiKeyMap()

key_map_cmd:
    :EmitBaseCommandKeyMap()

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
