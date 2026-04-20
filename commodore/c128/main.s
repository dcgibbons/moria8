#importonce
#import "../common/zeropage.s"
// C128 operational layout:
//   - Bank 0 main code = $1C01-$BFFF
//   - Bank 1 map = $4000-$4EFF
//   - Bank 1 ownership manifest lives in memory128.s
//   - BASIC Stub = $1C01 (SYS 7182)
//
// MMU set to $0E at startup (System ROM in, BASIC out via MMU), then $01
// used for runtime banking (same values as C64 for common code compatibility).

// ============================================================
// Overlay segments — produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
//
// $E000 works for both C64 and C128:
//   C64:  KERNAL LOAD secondary=1 uses PRG header ($E000). VIC-II
//         bank must be restored after KERNAL serial I/O (done in
//         overlay_load_disk). Execution: $01=$35 hides KERNAL ROM.
//   C128: KERNAL LOAD secondary=1 uses PRG header ($E000). Writes
//         go to Bank 0 RAM under KERNAL ROM (same as C64). Execution:
//         $FF00=$3E hides KERNAL ROM → $E000+ = Bank 0 RAM.
//
// banked_payload runtime code is forced to start above the dungeon overlay
// footprint so overlays ($E000-$EFFF) never overlap live banked routines.
// ============================================================
.eval var OVL_OUT = "out"
.segmentdef StartupOverlay    [outPrg=OVL_OUT + "/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg=OVL_OUT + "/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg=OVL_OUT + "/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",   start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items", start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeInputData  [outPrg=OVL_OUT + "/128.input.prg", start=$0b00, min=$0b00, max=$0bff]
.segmentdef RuntimeCommonData [outPrg=OVL_OUT + "/128.fdisk.prg", start=$0d20, min=$0d20, max=$0fff]
.segmentdef RuntimeLowData    [outPrg=OVL_OUT + "/128.runtime.prg", start=$1000, min=$1000, max=$3fff]

#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
.const C128_REAL_BOOT_DIAG = 1
#else
.const C128_REAL_BOOT_DIAG = 0
#endif

#if C128_TEST_CHARGEN_CUTPOINT
.const C128_CHARGEN_CUTPOINT = C128_TEST_CHARGEN_CUTPOINT
#else
.const C128_CHARGEN_CUTPOINT = -1
#endif

#if C128_TEST_TOWN_SELF_DUMP_TARGET
.const C128_TOWN_SELF_DUMP_TARGET = C128_TEST_TOWN_SELF_DUMP_TARGET
#else
.const C128_TOWN_SELF_DUMP_TARGET = $70
#endif

#if C128_TEST_OVERLAY_TRANSITION_DIAG
.const C128_OVERLAY_TRANSITION_DIAG = 1
#else
.const C128_OVERLAY_TRANSITION_DIAG = 0
#endif

#if C128_TEST_VIC40_CLEAN_BOOT
.const C128_VIC40_BOOT_PROBE = 1
#else
.const C128_VIC40_BOOT_PROBE = 0
#endif

#if C128_TEST_STACK_SLOT_DIAG
.macro C128StackSlotGuardInit(stage) {
    lda #stage
    jsr c128_stack_slot_guard_init
}

.macro C128StackSlotGuardCheck(stage) {
    lda #stage
    jsr c128_stack_slot_guard_check
}
#endif

#if C128_TEST_STACK_BOTTOM_DIAG
.macro C128StackBottomCanaryInit(stage) {
    lda #stage
    jsr c128_stack_bottom_canary_init
}

.macro C128StackBottomCanaryCheck(stage) {
    lda #stage
    jsr c128_stack_bottom_canary_check
}
#endif

#if C128_TEST_FINAL_RETURN_DIAG
.macro C128FinalReturnCapture(stage) {
    lda #stage
    jsr c128_final_return_capture
}

.macro C128FinalReturnCheck(stage) {
    lda #stage
    jsr c128_final_return_check
}
#endif

// ============================================================
// BASIC stub at $1C01 — SYS 7182 ($1C0E)
// ============================================================
.pc = $1c01 "BASIC Stub"
    .byte $0b, $1c, $0a, $00, $9e, $37, $31, $38, $32, $00, $00, $00

.pc = $1c0e "Program"
entry:
    jmp entry_real

#if C128_TEST_TOWN_SELF_DUMP
c128_town_dump_log:
    ldx c128_town_dump_idx
    sta c128_town_dump_buf,x
    inx
    txa
    and #$1f
    sta c128_town_dump_idx
    rts

c128_town_dump_mark:
    cmp #C128_TOWN_SELF_DUMP_TARGET
    beq !hit+
    jmp c128_town_dump_log
!hit:
    jsr c128_town_dump_log
    jmp c128_town_dump_checkpoint

c128_town_dump_checkpoint:
    jsr c128_town_dump_render_vic
!hang:
    nop
    jmp !hang-

c128_town_dump_render_vic:
    lda #<$0400
    sta zp_ptr0
    lda #>$0400
    sta zp_ptr0_hi
    lda #<$d800
    sta zp_ptr1
    lda #>$d800
    sta zp_ptr1_hi
    lda #19
    sta zp_temp0
!clear_rows:
    ldx #40
!clear_cols:
    lda #$20
    ldy #0
    sta (zp_ptr0),y
    lda #1
    sta (zp_ptr1),y
    inc zp_ptr0
    bne !clr_scr_ok+
    inc zp_ptr0_hi
!clr_scr_ok:
    inc zp_ptr1
    bne !clr_col_ok+
    inc zp_ptr1_hi
!clr_col_ok:
    dex
    bne !clear_cols-
    dec zp_temp0
    bne !clear_rows-

    lda #<$0400
    sta zp_ptr0
    lda #>$0400
    sta zp_ptr0_hi
    lda #<$d800
    sta zp_ptr1
    lda #>$d800
    sta zp_ptr1_hi

    lda #<c128_town_dump_title_str
    sta zp_temp1
    lda #>c128_town_dump_title_str
    sta zp_temp2
    ldy #0
!title:
    lda (zp_temp1),y
    beq !title_done+
    jsr c128_town_dump_put_char
    iny
    bne !title-
!title_done:

    jsr c128_town_dump_next_row
    lda c128_town_dump_idx
    jsr c128_town_dump_put_hex
    lda #$20
    jsr c128_town_dump_put_char
    lda c128_town_dump_countdown
    jsr c128_town_dump_put_hex

    lda #0
    sta zp_temp0
!bc_rows:
    jsr c128_town_dump_next_row
    ldx #16
!bc_cols:
    ldy zp_temp0
    lda c128_town_dump_buf,y
    jsr c128_town_dump_put_hex
    inc zp_temp0
    dex
    bne !bc_cols-
    lda zp_temp0
    cmp #32
    bne !bc_rows-

    ldx #0
!stack_rows:
    jsr c128_town_dump_next_row
    txa
    jsr c128_town_dump_put_hex
    lda #$3a
    jsr c128_town_dump_put_char
    ldy #0
!stack_cols:
    lda $0100,x
    jsr c128_town_dump_put_hex
    inx
    iny
    cpy #16
    bne !stack_cols-
    cpx #0
    bne !stack_rows-
    rts

c128_town_dump_next_row:
    lda zp_ptr0
    clc
    adc #40
    sta zp_ptr0
    bcc !row_scr_ok+
    inc zp_ptr0_hi
!row_scr_ok:
    lda zp_ptr1
    clc
    adc #40
    sta zp_ptr1
    bcc !row_col_ok+
    inc zp_ptr1_hi
!row_col_ok:
    rts

c128_town_dump_put_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr c128_town_dump_put_nibble
    pla
    and #$0f
    jmp c128_town_dump_put_nibble

c128_town_dump_put_nibble:
    cmp #10
    bcc !digit+
    sec
    sbc #9
    jmp c128_town_dump_put_char
!digit:
    clc
    adc #$30
    jmp c128_town_dump_put_char

c128_town_dump_put_char:
    ldy #0
    sta (zp_ptr0),y
    lda #1
    sta (zp_ptr1),y
    inc zp_ptr0
    bne !put_scr_ok+
    inc zp_ptr0_hi
!put_scr_ok:
    inc zp_ptr1
    bne !put_col_ok+
    inc zp_ptr1_hi
!put_col_ok:
    rts

c128_town_dump_title_str:
    .text "BC CD STK" ; .byte 0
c128_town_dump_idx: .byte 0
c128_town_dump_countdown: .byte 8
c128_town_dump_buf:
    .fill 32, 0
#endif

// ============================================================
// Core System & UI Routines — MUST live in Safe Zone (<$C000)
// ============================================================
#import "memory128.s"
#import "../common/color.s"
#import "../common/sound.s"
#import "config128.s"
#import "screen_vdc.s"
#import "../common/title_sysinfo_banked.s"
#import "../common/reu_loading_banked.s"
#import "input128.s"

// Bootstrap — sets up MMU and processor port, jumps to main code
entry_real:
    sei
    cld
    ldx #$ff
    txs

    // Hardware Quiet Down — Acknowledge and Clear
    lda #$7f
    sta $dc0d               // CIA1 Interrupt Control Register: disable all
    sta $dd0d               // CIA2 Interrupt Control Register: disable all
    lda $dc0d               // Clear CIA1 ICR
    lda $dd0d               // Clear CIA2 ICR

    lda #$ff
    sta zp_screen_editor_mode  // Screen Editor: 80-col mode

    // Enable 2MHz mode on the C128 (set D030 bit0 while preserving other flags)
    lda $d030
    ora #$01
    sta $d030

    // Copy banked payload BEFORE installing patches so it doesn't overwrite them
    jsr init_copy_banked

    // Mirror KERNAL vectors/stubs into RAM underneath ROM ($FF05-$FFFF)
    // Skipping $FF00-$FF04 to avoid mid-loop MMU bank-switching.
    lda #$00                // Bank 15 (KERNAL + I/O)
    sta $ff00
    ldx #5
!mirror:
    lda $ff00,x
    sta $ff00,x
    inx
    bne !mirror-
    lda #$3E                // Restore All-RAM
    sta $ff00

    // --- Patch KERNAL JMP table in RAM ---
    // Read original targets from ROM stubs and patch stubs to point to our safe wrappers.
    // This allows game code to call JSR $FFxx and have the wrapper manage the MMU.
    
    lda #$4C                    // JMP absolute
    sta $ffb7                   // READST
    sta $ffba                   // SETLFS
    sta $ffbd                   // SETNAM
    sta $ffc0                   // OPEN
    sta $ffc3                   // CLOSE
    sta $ffc6                   // CHKIN
    sta $ffc9                   // CHKOUT
    sta $ffcc                   // CLRCHN
    sta $ffcf                   // CHRIN
    sta $ffd2                   // CHROUT
    sta $ffd5                   // LOAD

    // FFB7 READST
    lda #<w_readst
    sta $ffb8
    lda #>w_readst
    sta $ffb9
    // FFBA SETLFS
    lda #<w_setlfs
    sta $ffbb
    lda #>w_setlfs
    sta $ffbc
    // FFBD SETNAM
    lda #<w_setnam
    sta $ffbe
    lda #>w_setnam
    sta $ffbf
    // FFC0 OPEN
    lda #<w_open
    sta $ffc1
    lda #>w_open
    sta $ffc2
    // FFC3 CLOSE
    lda #<w_close
    sta $ffc4
    lda #>w_close
    sta $ffc5
    // FFC6 CHKIN
    lda #<w_chkin
    sta $ffc7
    lda #>w_chkin
    sta $ffc8
    // FFC9 CHKOUT
    lda #<w_chkout
    sta $ffca
    lda #>w_chkout
    sta $ffcb
    // FFCC CLRCHN
    lda #<w_clrchn
    sta $ffcd
    lda #>w_clrchn
    sta $ffce
    // FFCF CHRIN
    lda #<w_chrin
    sta $ffd0
    lda #>w_chrin
    sta $ffd1
    // FFD2 CHROUT
    lda #<w_chrout
    sta $ffd3
    lda #>w_chrout
    sta $ffd4
    // FFD5 LOAD
    lda #<w_load
    sta $ffd6
    lda #>w_load
    sta $ffd7

    // Save original hardware IRQ/NMI vectors before patching RAM copies.
    lda $fffe
    sta kernal_hw_irq_vec_lo
    lda $ffff
    sta kernal_hw_irq_vec_hi
    lda $fffa
    sta kernal_hw_nmi_vec_lo
    lda $fffb
    sta kernal_hw_nmi_vec_hi

    // Patch hardware IRQ vector ($FFFE/$FFFF) in RAM to point to Common RAM Bridge.
    // This ensures interrupts always find code even when Bank 1 is active.
    lda #<mmu_common_irq
    sta $fffe
    lda #>mmu_common_irq
    sta $ffff
    // Patch hardware NMI vector ($FFFA/$FFFB) in RAM — same issue.
    lda #<mmu_common_nmi
    sta $fffa
    lda #>mmu_common_nmi
    sta $fffb
    // Patch hardware RESET vector ($FFFC/$FFFD) in RAM for All-RAM safety.
    lda #<exit_trampoline
    sta $fffc
    lda #>exit_trampoline
    sta $fffd

    :MachineRestoreDefault()
    jmp entry_main

// ============================================================
// Safe KERNAL Wrappers
// Each wrapper switches to MMU_NORMAL, calls real target,
// then restores MMU_ALL_RAM. Flags (Carry!) are preserved via PHP/PLP.
// ============================================================
// KERNAL calls now use the Official Jump Table ($FF81-$FFF5) safely in Bank 15.

c128_wrapper_saved_a: .byte 0
c128_wrapper_saved_p: .byte 0

.macro C128KernalJumpTableWrapper(target) {
    php
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    pla
    tay
    pla
    tax
    pla
    jsr target
    php
    pha
    :ExitKernal()
    jmp c128_wrapper_finish
}

// c128_wrapper_finish — restore KERNAL result flags while preserving caller I-bit
// Stack on entry (top-first): result A, KERNAL P, caller P
c128_wrapper_finish:
    pla
    sta c128_wrapper_saved_a
    pla
    sta c128_wrapper_saved_p
    pla
    and #$04
    pha
    lda c128_wrapper_saved_p
    and #$fb
    sta c128_wrapper_saved_p
    pla
    ora c128_wrapper_saved_p
    pha
    lda c128_wrapper_saved_a
    plp
    rts

// READST / SETLFS / SETNAM / OPEN / CLOSE / CHKIN / CHKOUT / CLRCHN / CHRIN / CHROUT
w_readst:
    :C128KernalJumpTableWrapper($ffb7)
w_setlfs:
    :C128KernalJumpTableWrapper($ffba)
w_setnam:
    :C128KernalJumpTableWrapper($ffbd)
w_open:
    :C128KernalJumpTableWrapper($ffc0)
w_close:
    :C128KernalJumpTableWrapper($ffc3)
w_chkin:
    :C128KernalJumpTableWrapper($ffc6)
w_chkout:
    :C128KernalJumpTableWrapper($ffc9)
w_clrchn:
    :C128KernalJumpTableWrapper($ffcc)
w_chrin:
    :C128KernalJumpTableWrapper($ffcf)
w_chrout:
    :C128KernalJumpTableWrapper($ffd2)
// LOAD
w_load:
    stx c128_load_arg_x
    sty c128_load_arg_y
    php
    pha
#if C128_REAL_BOOT_DIAG
    ldx #$51
    jsr c128_stack_guard_begin
#endif
    :EnterKernal()
#if C128_REAL_BOOT_DIAG
    ldx #$52
    stx c128_stack_guard_stage
    jsr c128_stack_guard_snapshot_banking
#endif
    pla
    ldx c128_load_arg_x
    ldy c128_load_arg_y
    jsr $ffd5
#if C128_REAL_BOOT_DIAG
    ldx #$53
    stx c128_stack_guard_stage
    jsr c128_stack_guard_snapshot_banking
#endif
    php
    pha
    :ExitKernal()
    pla
    sta c128_wrapper_saved_a
    pla
    sta c128_wrapper_saved_p
    pla
    and #$04
    pha
    lda c128_wrapper_saved_p
    and #$fb
    sta c128_wrapper_saved_p
    pla
    ora c128_wrapper_saved_p
    pha
    lda c128_wrapper_saved_a
    plp
#if C128_REAL_BOOT_DIAG
    ldx #$54
    jsr c128_stack_guard_check
    jsr c128_stack_guard_snapshot_banking
    jsr c128_stack_guard_snapshot_return
#endif
    rts

// safe_irq and safe_nmi have been replaced by Common RAM trampolines
// mmu_common_irq and mmu_common_nmi (see memory128.s).

// kernal_load_safe — KERNAL LOAD wrapper for C128
// Reinstalls keyboard stub on exit. Callers manage MMU.
kernal_load_safe:
    php
    :EnterKernal()
    jsr $ffd5
    php
    pha
    :ExitKernal()
    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303
    jmp c128_wrapper_finish

chrin_keyboard_stub:
    lda #0
    clc
    rts

// c128_restore_runtime_vectors — Reassert the all-RAM IRQ/NMI and CHRIN stubs.
// Use this on long-lived runtime paths that do not need the full helper reinstall.
c128_restore_runtime_state_core:
    :MachineRestoreAllRam()
    lda #<mmu_common_irq
    sta $fffe
    lda #>mmu_common_irq
    sta $ffff
    lda #<mmu_common_nmi
    sta $fffa
    lda #>mmu_common_nmi
    sta $fffb
    lda #<exit_trampoline
    sta $fffc
    lda #>exit_trampoline
    sta $fffd
    lda #<mmu_common_irq
    sta $0314
    lda #>mmu_common_irq
    sta $0315
    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303
    lda #$ff
    sta zp_screen_editor_state
    rts

c128_restore_runtime_vectors:
    php
    sei
    jsr c128_restore_runtime_state_core
    plp
    rts

// Reassert runtime-owned low/common RAM state after KERNAL-visible work.
// Multiple public entry labels resolve to the same implementation so callers
// can keep their semantic name without paying extra trampoline hops.
c128_restore_runtime_state:
c128_restore_runtime_guards:
c128_return_to_runtime_after_kernal:
    pha
    txa
    pha
    tya
    pha
    php
    sei
    :MachineRestoreAllRam()
    jsr init_common_mmu_helpers
    jsr c128_vdc_reassert_mode
    plp
    pla
    tay
    pla
    tax
    pla
    rts

platform_services_install128:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<c128_restore_runtime_vectors
    sta platform_main_loop_begin_api + 1
    lda #>c128_restore_runtime_vectors
    sta platform_main_loop_begin_api + 2

    lda #<c128_restore_runtime_vectors
    sta platform_vector_reassert_api + 1
    lda #>c128_restore_runtime_vectors
    sta platform_vector_reassert_api + 2

    lda #<c128_restore_runtime_guards
    sta platform_runtime_resync_api + 1
    lda #>c128_restore_runtime_guards
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

// safe_setbnk — SETBNK ($FF68) wrapper for C128
// Temporarily enables KERNAL ROM, calls real SETBNK, restores MMU.
// $FF68 is in the banked code range ($F000-$FFB6) so it can't be
// patched via the JMP table — call this routine directly instead.
safe_setbnk:
    php
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    pla
    tay
    pla
    tax
    pla
    jsr $ff68
    php
    pha
    :ExitKernal()
    jmp c128_wrapper_finish

// init_copy_banked — Copy banked code payload to $F000
// Uses $3F (NOIO) instead of $3E because source data crosses the I/O
// range $D000-$DFFF. With $3E, reads from $D000+ return I/O register
// garbage instead of game data.
init_copy_banked:
#if C128_TEST_OVERLAY_RELOAD_GUARD
    lda c128_startup_overlay_executing
    beq !guard_ok+
    brk
!guard_ok:
#endif
    sei
    lda #<banked_payload
    sta zp_ptr0
    lda #>banked_payload
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$F0
    sta zp_ptr1_hi
    ldx #((banked_payload_end - banked_payload + 255) / 256)
    ldy #0
    // Switch to NOIO for the copy (source crosses $D000)
    lda #$3f                // MMU_ALL_RAM but with I/O hidden (RAM at $D000)
    sta $ff00
!copy:
    lda zp_ptr1_hi
    cmp #$ff
    bne !do_copy+
    // Protect MMU/Vectors in page $FF ($FF00-$FF0D)
    cpy #$0e
    bcc !skip_copy+
!do_copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
!skip_copy:
    iny
    bne !copy-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !copy-
    lda #MMU_ALL_RAM
    sta $ff00
    rts

// Exit trampoline — MUST live below $A000
exit_trampoline:
    lda #0
    sta $d418
    sei
    // Restore full ROM map before handing control back to ROM.
    lda #$00
    sta $ff00
    lda #BANK_ALL_ROM
    sta $01

    // Native C128 warm-start paths proved unstable after game runtime state
    // mutation. Use the hardware reset vector for deterministic return.
    // This is equivalent to a soft reboot to BASIC.
    jmp ($fffc)



// ============================================================
// Critical trampolines — pin these near program start so they
// can never drift into the $D000 I/O hole.
// ============================================================
tramp_player_create:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$71
    jsr c128_town_dump_mark
#endif
#if !C128_TEST_SKIP_PLAYER_CREATE_OVERLAY
    lda #1                      // OVL_STARTUP
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_tramp_player_create_overlay_req
#endif
#if C128_REAL_BOOT_DIAG
    ldx #$31
    jsr c128_stack_guard_begin
#endif
    jsr overlay_load
#if C128_REAL_BOOT_DIAG
    ldx #$32
    jsr c128_stack_guard_check
#endif
    bcc !tpc_loaded+
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    brk
#endif
    jmp entry_main
!tpc_loaded:
#if !C128_TEST_SKIP_PLAYER_CREATE_GUARDS
    jsr c128_restore_runtime_guards
#endif
#endif
#if C128_REAL_BOOT_DIAG
    ldx #$33
    jsr c128_stack_guard_begin
#endif
#if !C128_TEST_SKIP_PLAYER_CREATE_CALL
    lda #1
    sta c128_startup_overlay_executing
    jsr player_create
tramp_player_create_return_site:
    lda #0
    sta c128_startup_overlay_executing
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardCheck($86)
#endif
#endif
    jsr c128_restore_runtime_guards
    rts

tramp_game_over:
    lda death_source_saved
    sta zp_death_source

    // 1. Resolve creature name while tier data still at $E000
    lda zp_death_source
    cmp #$fd                    // DEATH_CURSED
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name

!tgo_load_overlay:
    // 2. Load death overlay at $0400
    lda #3                      // OVL_DEATH
    jsr overlay_load
    bcc !tgo_loaded+
    jmp entry_main
!tgo_loaded:
    jsr c128_restore_runtime_guards

    // 3. Calculate score
    jsr score_calculate

    // 4. Load high scores from disk (needs KERNAL-visible ROM)
    php
    sei
    lda #$ff
    sta zp_screen_editor_state
    lda #$0e                    // MMU_NORMAL
    sta $ff00
    lda #$37                    // BANK_ALL_ROM
    sta $01
    jsr hiscore_load
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    jsr c128_vdc_reassert_mode
    plp

    // 5. Insert/save only for non-wizard characters
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    jsr hiscore_insert

    // 6. Save high scores to disk (needs KERNAL-visible ROM)
    php
    sei
    lda #$ff
    sta zp_screen_editor_state
    lda #$0e                    // MMU_NORMAL
    sta $ff00
    lda #$37                    // BANK_ALL_ROM
    sta $01
    jsr hiscore_save
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    jsr c128_vdc_reassert_mode
    plp
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source

    // 7. Display death screen (death overlay code at $E000)
    jmp score_death_screen

tramp_store_init_all:
    lda #2                      // OVL_TOWN
#if C128_REAL_BOOT_DIAG
    ldx #$34
    jsr c128_stack_guard_begin
#endif
    jsr overlay_load
#if C128_REAL_BOOT_DIAG
    ldx #$35
    jsr c128_stack_guard_check
#endif
    bcc !tsia_loaded+
    jmp entry_main
!tsia_loaded:
    jsr c128_restore_runtime_guards
#if C128_REAL_BOOT_DIAG
    ldx #$36
    jsr c128_stack_guard_begin
#endif
    jmp store_init_all

tramp_store_restock_all:
    lda #2                      // OVL_TOWN
    jsr overlay_load
    bcc !tsra_loaded+
    jmp entry_main
!tsra_loaded:
    jsr c128_restore_runtime_guards
    jmp store_restock_all

tramp_store_enter:
    lda #2                      // OVL_TOWN
    jsr overlay_load
    bcc !tse_loaded+
    jmp entry_main
!tse_loaded:
    jsr c128_restore_runtime_guards
    jmp store_enter

#if C128_TEST_SCRIPTED_INPUT
c128_test_town_fail_sym:
    brk
c128_test_town_pass_sym:
    brk
#elif C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_SPELL_CANCEL
c128_test_spell_fail_no_cast_sym:
    brk
c128_test_spell_fail_level_sym:
    brk
c128_test_spell_fail_known_sym:
    brk
c128_test_spell_fail_validate_sym:
    brk
c128_test_spell_fail_roll_sym:
    brk
c128_test_spell_fail_cancel_sym:
    brk
c128_test_spell_pass_sym:
    brk
#if C128_TEST_SCRIPTED_SPELL_CANCEL
c128_test_spell_cancel_pass_sym:
    brk
#endif
#elif C128_TEST_CACHE_SURVIVAL
c128_test_town_fail_sym:
    brk
c128_test_town_pass_sym:
    brk
#endif
#if C128_CACHE_TEST_SKIP_TIER
c128_test_partial_cache_fail_sym:
    brk
#endif
#if C128_CACHE_TEST_SKIP_OVERLAY
c128_test_overlay_cache_fail_sym:
    brk
#endif
#if C128_TEST_CACHE_SURVIVAL
c128_test_cache_survival_fail_sym:
    brk
c128_test_cache_survival_pass_sym:
    brk
#endif
#if C128_TEST_TITLE_ART_CONTENT
c128_test_title_art_fail_sym:
    brk
c128_test_title_art_pass_sym:
    brk
#endif
#if C128_TEST_OVERLAY_TRANSITION_DIAG
c128_overlay_transition_fail_sym:
    brk
c128_overlay_transition_pass_sym:
    nop
    jmp c128_overlay_transition_pass_sym
#endif
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
c128_diag_fail_sym:
    lda c128_stack_guard_stage
    cmp #$11
    bne !chk12+
    jmp c128_diag_fail_stage_11
!chk12:
    cmp #$12
    bne !chk13+
    jmp c128_diag_fail_stage_12
!chk13:
    cmp #$13
    bne !chk14+
    jmp c128_diag_fail_stage_13
!chk14:
    cmp #$14
    bne !chk15+
    jmp c128_diag_fail_stage_14
!chk15:
    cmp #$15
    bne !chk16+
    jmp c128_diag_fail_stage_15
!chk16:
    cmp #$16
    bne !chk17+
    jmp c128_diag_fail_stage_16
!chk17:
    cmp #$17
    bne !chk18+
    jmp c128_diag_fail_stage_17
!chk18:
    cmp #$18
    bne !chk19+
    jmp c128_diag_fail_stage_18
!chk19:
    cmp #$19
    bne !chk1a+
    jmp c128_diag_fail_stage_19
!chk1a:
    cmp #$1a
    bne !chk1b+
    jmp c128_diag_fail_stage_1a
!chk1b:
    cmp #$1b
    bne !chk1c+
    jmp c128_diag_fail_stage_1b
!chk1c:
    cmp #$1c
    bne !chk1d+
    jmp c128_diag_fail_stage_1c
!chk1d:
    cmp #$1d
    bne !chk1e+
    jmp c128_diag_fail_stage_1d
!chk1e:
    cmp #$1e
    bne !chk1f+
    jmp c128_diag_fail_stage_1e
!chk1f:
    cmp #$1f
    bne !chk21+
    jmp c128_diag_fail_stage_1f
!chk21:
    cmp #$21
    bne !chk22+
    jmp c128_diag_fail_stage_21
!chk22:
    cmp #$22
    bne !chk23+
    jmp c128_diag_fail_stage_22
!chk23:
    cmp #$23
    bne !chk24+
    jmp c128_diag_fail_stage_23
!chk24:
    cmp #$24
    bne !chk25+
    jmp c128_diag_fail_stage_24
!chk25:
    cmp #$25
    bne !chk26+
    jmp c128_diag_fail_stage_25
!chk26:
    cmp #$26
    bne !chk27+
    jmp c128_diag_fail_stage_26
!chk27:
    cmp #$27
    bne !chk28+
    jmp c128_diag_fail_stage_27
!chk28:
    cmp #$28
    bne !chk31+
    jmp c128_diag_fail_stage_28
!chk31:
    cmp #$31
    bne !chk32+
    jmp c128_diag_fail_stage_31
!chk32:
    cmp #$32
    bne !chk33+
    jmp c128_diag_fail_stage_32
!chk33:
    cmp #$33
    bne !chk34+
    jmp c128_diag_fail_stage_33
!chk34:
    cmp #$34
    bne !chk35+
    jmp c128_diag_fail_stage_34
!chk35:
    cmp #$35
    bne !chk36+
    jmp c128_diag_fail_stage_35
!chk36:
    cmp #$36
    bne !chk39+
    jmp c128_diag_fail_stage_36
!chk39:
    cmp #$39
    bne !chk3a+
    jmp c128_diag_fail_stage_39
!chk3a:
    cmp #$3a
    bne !chk41+
    jmp c128_diag_fail_stage_3a
!chk41:
    cmp #$41
    bne !chk42+
    jmp c128_diag_fail_stage_41
!chk42:
    cmp #$42
    bne !chk43+
    jmp c128_diag_fail_stage_42
!chk43:
    cmp #$43
    bne !chk44+
    jmp c128_diag_fail_stage_43
!chk44:
    cmp #$44
    bne !chk45+
    jmp c128_diag_fail_stage_44
!chk45:
    cmp #$45
    bne !chk46+
    jmp c128_diag_fail_stage_45
!chk46:
    cmp #$46
    bne !chk47+
    jmp c128_diag_fail_stage_46
!chk47:
    cmp #$47
    bne !chk48+
    jmp c128_diag_fail_stage_47
!chk48:
    cmp #$48
    bne !chk49+
    jmp c128_diag_fail_stage_48
!chk49:
    cmp #$49
    bne !chk4a+
    jmp c128_diag_fail_stage_49
!chk4a:
    cmp #$4a
    bne !chk4b+
    jmp c128_diag_fail_stage_4a
!chk4b:
    cmp #$4b
    bne !chk4c+
    jmp c128_diag_fail_stage_4b
!chk4c:
    cmp #$4c
    bne !chk51+
    jmp c128_diag_fail_stage_4c
!chk51:
    cmp #$51
    bne !chk52+
    jmp c128_diag_fail_stage_51
!chk52:
    cmp #$52
    bne !chk53+
    jmp c128_diag_fail_stage_52
!chk53:
    cmp #$53
    bne !chk54+
    jmp c128_diag_fail_stage_53
!chk54:
    cmp #$54
    bne !chk61+
    jmp c128_diag_fail_stage_54
!chk61:
    cmp #$61
    bne !chk62+
    jmp c128_diag_fail_stage_61
!chk62:
    cmp #$62
    bne !chk63+
    jmp c128_diag_fail_stage_62
!chk63:
    cmp #$63
    bne !chk64+
    jmp c128_diag_fail_stage_63
!chk64:
    cmp #$64
    bne !chk71+
    jmp c128_diag_fail_stage_64
!chk71:
    cmp #$71
    bne !chk72+
    jmp c128_diag_fail_stage_71
!chk72:
    cmp #$72
    bne !chk73+
    jmp c128_diag_fail_stage_72
!chk73:
    cmp #$73
    bne !chk74+
    jmp c128_diag_fail_stage_73
!chk74:
    cmp #$74
    bne !chk75+
    jmp c128_diag_fail_stage_74
!chk75:
    cmp #$75
    bne !chk76+
    jmp c128_diag_fail_stage_75
!chk76:
    cmp #$76
    bne !chk77+
    jmp c128_diag_fail_stage_76
!chk77:
    cmp #$77
    bne !chk78+
    jmp c128_diag_fail_stage_77
!chk78:
    cmp #$78
    bne !chk81+
    jmp c128_diag_fail_stage_78
!chk81:
    cmp #$81
    bne !chk82+
    jmp c128_diag_fail_stage_81
!chk82:
    cmp #$82
    bne !chk83+
    jmp c128_diag_fail_stage_82
!chk83:
    cmp #$83
    bne !chk84+
    jmp c128_diag_fail_stage_83
!chk84:
    cmp #$84
    bne !chk91+
    jmp c128_diag_fail_stage_84
!chk91:
    cmp #$91
    bne !chk92+
    jmp c128_diag_fail_stage_91
!chk92:
    cmp #$92
    bne !chk93+
    jmp c128_diag_fail_stage_92
!chk93:
    cmp #$93
    bne !chk94+
    jmp c128_diag_fail_stage_93
!chk94:
    cmp #$94
    bne !chk95+
    jmp c128_diag_fail_stage_94
!chk95:
    cmp #$95
    bne !chk96+
    jmp c128_diag_fail_stage_95
!chk96:
    cmp #$96
    bne !chk97+
    jmp c128_diag_fail_stage_96
!chk97:
    cmp #$97
    bne !chk98+
    jmp c128_diag_fail_stage_97
!chk98:
    cmp #$98
    bne !diag_default+
    jmp c128_diag_fail_stage_98
!diag_default:
    jmp c128_diag_fail_default
c128_diag_fail_default:
    nop
    jmp c128_diag_fail_default
c128_diag_fail_stage_11:
    nop
    jmp c128_diag_fail_stage_11
c128_diag_fail_stage_12:
    nop
    jmp c128_diag_fail_stage_12
c128_diag_fail_stage_13:
    nop
    jmp c128_diag_fail_stage_13
c128_diag_fail_stage_14:
    nop
    jmp c128_diag_fail_stage_14
c128_diag_fail_stage_15:
    nop
    jmp c128_diag_fail_stage_15
c128_diag_fail_stage_16:
    nop
    jmp c128_diag_fail_stage_16
c128_diag_fail_stage_17:
    nop
    jmp c128_diag_fail_stage_17
c128_diag_fail_stage_18:
    nop
    jmp c128_diag_fail_stage_18
c128_diag_fail_stage_19:
    nop
    jmp c128_diag_fail_stage_19
c128_diag_fail_stage_1a:
    nop
    jmp c128_diag_fail_stage_1a
c128_diag_fail_stage_1b:
    nop
    jmp c128_diag_fail_stage_1b
c128_diag_fail_stage_1c:
    nop
    jmp c128_diag_fail_stage_1c
c128_diag_fail_stage_1d:
    nop
    jmp c128_diag_fail_stage_1d
c128_diag_fail_stage_1e:
    nop
    jmp c128_diag_fail_stage_1e
c128_diag_fail_stage_1f:
    nop
    jmp c128_diag_fail_stage_1f
c128_diag_fail_stage_21:
    nop
    jmp c128_diag_fail_stage_21
c128_diag_fail_stage_22:
    nop
    jmp c128_diag_fail_stage_22
c128_diag_fail_stage_23:
    nop
    jmp c128_diag_fail_stage_23
c128_diag_fail_stage_24:
    nop
    jmp c128_diag_fail_stage_24
c128_diag_fail_stage_25:
    nop
    jmp c128_diag_fail_stage_25
c128_diag_fail_stage_26:
    nop
    jmp c128_diag_fail_stage_26
c128_diag_fail_stage_27:
    nop
    jmp c128_diag_fail_stage_27
c128_diag_fail_stage_28:
    nop
    jmp c128_diag_fail_stage_28
c128_diag_fail_stage_31:
    nop
    jmp c128_diag_fail_stage_31
c128_diag_fail_stage_32:
    nop
    jmp c128_diag_fail_stage_32
c128_diag_fail_stage_33:
    nop
    jmp c128_diag_fail_stage_33
c128_diag_fail_stage_34:
    nop
    jmp c128_diag_fail_stage_34
c128_diag_fail_stage_35:
    nop
    jmp c128_diag_fail_stage_35
c128_diag_fail_stage_36:
    nop
    jmp c128_diag_fail_stage_36
c128_diag_fail_stage_39:
    nop
    jmp c128_diag_fail_stage_39
c128_diag_fail_stage_3a:
    nop
    jmp c128_diag_fail_stage_3a
c128_diag_fail_stage_41:
    nop
    jmp c128_diag_fail_stage_41
c128_diag_fail_stage_42:
    nop
    jmp c128_diag_fail_stage_42
c128_diag_fail_stage_43:
    nop
    jmp c128_diag_fail_stage_43
c128_diag_fail_stage_44:
    nop
    jmp c128_diag_fail_stage_44
c128_diag_fail_stage_45:
    nop
    jmp c128_diag_fail_stage_45
c128_diag_fail_stage_46:
    nop
    jmp c128_diag_fail_stage_46
c128_diag_fail_stage_47:
    nop
    jmp c128_diag_fail_stage_47
c128_diag_fail_stage_48:
    nop
    jmp c128_diag_fail_stage_48
c128_diag_fail_stage_49:
    nop
    jmp c128_diag_fail_stage_49
c128_diag_fail_stage_4a:
    nop
    jmp c128_diag_fail_stage_4a
c128_diag_fail_stage_4b:
    nop
    jmp c128_diag_fail_stage_4b
c128_diag_fail_stage_4c:
    nop
    jmp c128_diag_fail_stage_4c
c128_diag_fail_stage_51:
    nop
    jmp c128_diag_fail_stage_51
c128_diag_fail_stage_52:
    nop
    jmp c128_diag_fail_stage_52
c128_diag_fail_stage_53:
    nop
    jmp c128_diag_fail_stage_53
c128_diag_fail_stage_54:
    nop
    jmp c128_diag_fail_stage_54
c128_diag_fail_stage_61:
    nop
    jmp c128_diag_fail_stage_61
c128_diag_fail_stage_62:
    nop
    jmp c128_diag_fail_stage_62
c128_diag_fail_stage_63:
    nop
    jmp c128_diag_fail_stage_63
c128_diag_fail_stage_64:
    nop
    jmp c128_diag_fail_stage_64
c128_diag_fail_stage_71:
    nop
    jmp c128_diag_fail_stage_71
c128_diag_fail_stage_72:
    nop
    jmp c128_diag_fail_stage_72
c128_diag_fail_stage_73:
    nop
    jmp c128_diag_fail_stage_73
c128_diag_fail_stage_74:
    nop
    jmp c128_diag_fail_stage_74
c128_diag_fail_stage_75:
    nop
    jmp c128_diag_fail_stage_75
c128_diag_fail_stage_76:
    nop
    jmp c128_diag_fail_stage_76
c128_diag_fail_stage_77:
    nop
    jmp c128_diag_fail_stage_77
c128_diag_fail_stage_78:
    nop
    jmp c128_diag_fail_stage_78
c128_diag_fail_stage_81:
    nop
    jmp c128_diag_fail_stage_81
c128_diag_fail_stage_82:
    nop
    jmp c128_diag_fail_stage_82
c128_diag_fail_stage_83:
    nop
    jmp c128_diag_fail_stage_83
c128_diag_fail_stage_84:
    nop
    jmp c128_diag_fail_stage_84
c128_diag_fail_stage_91:
    nop
    jmp c128_diag_fail_stage_91
c128_diag_fail_stage_92:
    nop
    jmp c128_diag_fail_stage_92
c128_diag_fail_stage_93:
    nop
    jmp c128_diag_fail_stage_93
c128_diag_fail_stage_94:
    nop
    jmp c128_diag_fail_stage_94
c128_diag_fail_stage_95:
    nop
    jmp c128_diag_fail_stage_95
c128_diag_fail_stage_96:
    nop
    jmp c128_diag_fail_stage_96
c128_diag_fail_stage_97:
    nop
    jmp c128_diag_fail_stage_97
c128_diag_fail_stage_98:
    nop
    jmp c128_diag_fail_stage_98
#endif

tramp_ui_enter:
    sei
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    lda #$34                    // BANK_NO_ROMS
    sta $01
    rts

tramp_ui_exit:
    lda #$36                    // BANK_NO_BASIC
    sta $01
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    jsr c128_restore_runtime_guards
    jsr c128_restore_runtime_vectors
    cli
    rts

.macro C128UIBankedDisplayTrampoline(target) {
    jsr tramp_ui_enter
    jsr target
    jmp tramp_ui_exit
}

.const C128_HELP_OVERLAY_ID = 5
.const C128_UI_OVERLAY_ID = 6
.const C128_ITEMS_OVERLAY_ID = 7

.macro C128UIOverlayDisplayTrampoline(target) {
    jsr tramp_ui_enter
    lda #C128_UI_OVERLAY_ID
    jsr overlay_load
    bcs !done+
    jsr target
!done:
    jmp tramp_ui_exit
}

tramp_ui_help_display:
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
!done:
    jmp tramp_ui_exit

tramp_ui_ui_overlay_patch_target:
    sta !ui_target+ + 1
    stx !ui_target+ + 2
tramp_ui_ui_overlay_common:
    jsr tramp_ui_enter
    lda #C128_UI_OVERLAY_ID
    jsr overlay_load
    bcs !done+
!ui_target:
    jsr ui_char_display
!done:
    jmp tramp_ui_exit

tramp_ui_char_display:
    jmp tramp_ui_ui_overlay_common

tramp_ui_inv_display:
    lda #<ui_inv_display
    jmp tramp_ui_inv_common

tramp_ui_inv_select_display:
    lda #<ui_inv_select_display
tramp_ui_inv_common:
    sta !inv_target+ + 1
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
!inv_target:
    jsr ui_inv_display
!done:
    jmp tramp_ui_exit

tramp_ui_equip_display:
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
    jsr ui_equip_display
!done:
    jmp tramp_ui_exit

tramp_ui_recall:
    lda #<ui_recall_display
    ldx #>ui_recall_display
    jmp tramp_ui_ui_overlay_patch_target

tramp_ui_wizard_display:
    lda #<ui_wizard_display
    ldx #>ui_wizard_display
    jmp tramp_ui_ui_overlay_patch_target

tramp_item_gain_spell:
    lda #<item_gain_spell
    ldx #>item_gain_spell
    jmp tramp_ui_ui_overlay_patch_target

.macro C128OverlayComputeTrampoline(overlay_id, target) {
    lda #overlay_id
    jsr overlay_load
    bcs !done+
    jsr c128_restore_runtime_guards
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr target
    pla
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    cli
!done:
    rts
}

tramp_item_read_scroll:
    :C128OverlayComputeTrampoline(C128_ITEMS_OVERLAY_ID, item_read_scroll)

tramp_item_aim_wand:
    :C128OverlayComputeTrampoline(C128_ITEMS_OVERLAY_ID, item_aim_wand)

tramp_item_use_staff:
    :C128OverlayComputeTrampoline(C128_ITEMS_OVERLAY_ID, item_use_staff)

tramp_item_refuel:
    :C128OverlayComputeTrampoline(C128_ITEMS_OVERLAY_ID, item_refuel)

tramp_title_load_and_draw:
    lda #C128_UI_OVERLAY_ID
    jsr overlay_load
    bcs !ttld_fail+
    jsr c128_restore_runtime_guards
    jmp title_load_and_draw
!ttld_fail:
    jmp entry_main

.macro C128BankedComputeTrampoline(target) {
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr target
    pla
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts
}

tramp_player_cast_spell:
    :C128BankedComputeTrampoline(player_cast_spell)

tramp_player_pray:
    :C128BankedComputeTrampoline(player_pray)

tramp_spell_list_display:
    :C128UIOverlayDisplayTrampoline(spell_list_display)

tramp_spell_execute_selected:
    lda #3                      // OVL_DEATH
    jsr overlay_load
    bcc !tses_loaded+
    rts
!tses_loaded:
    jsr c128_restore_runtime_guards
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr spell_execute_selected
    pla
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts

tramp_magic_recalc_mana:
    :C128BankedComputeTrampoline(magic_recalc_mana)

tramp_magic_check_new_spells:
    :C128BankedComputeTrampoline(magic_check_new_spells)

tramp_ranged_fire:
    :C128BankedComputeTrampoline(ranged_fire)

tramp_player_tunnel:
    :C128BankedComputeTrampoline(player_tunnel)

tramp_throw_item:
    :C128BankedComputeTrampoline(throw_item)

tramp_bash_command:
    :C128BankedComputeTrampoline(bash_command)

// tramp_dig_ability — Calculate digging ability.
// Pinned low to avoid $D000 drift.
tramp_dig_ability:
    jmp calc_dig_ability

.macro C128BankedPreserveATrampoline(target) {
    pha
    sei
    :BankOutKernal()
    pla
    jsr target
    jmp tramp_sr_epilogue
}

.macro C128BankedPreserveAReturnTrampoline(target) {
    pha
    sei
    :BankOutKernal()
    pla
    jsr target
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    pla
    rts
}

// tramp_ego_get_ac_bonus — Get ego AC bonus from the low-RAM table.
// Keep this inline on C128 so low runtime does not carry a separate helper.
tramp_ego_apply_damage:
    :C128BankedPreserveATrampoline(ego_apply_damage)

tramp_ego_get_ac_bonus:
    tax
    lda ego_ac_bonus,x
    rts

.macro C128BankedStatusTrampoline(target) {
    php
    sei
    lda #$35                    // BANK_NO_KERNAL (I/O visible)
    sta $01
    jsr target
    jsr c128_restore_runtime_guards
    plp
    rts
}

// title_show_sysinfo — trampoline to banked routine at $EB00.
// Pinned low to avoid drifting into $D000 I/O space.
title_show_sysinfo:
    :C128BankedStatusTrampoline(title_show_sysinfo_banked)

tsi_krev_cached: .byte 0

// tramp_reu_show_status — banked status display hook.
// Pinned low to avoid drifting into $D000 I/O space.
tramp_reu_show_status:
    :C128BankedStatusTrampoline(reu_show_status_banked)

// ============================================================
// game_over_prompt — R)EBOOT / S)TART OVER / Q)UIT prompt
// ============================================================
game_over_str:
    .text "R)EBOOT S)TART Q)UIT" ; .byte 0
game_over_str_end:

.const GAME_OVER_COL = (SCREEN_COLS - 20) / 2
.const TITLE_MENU_COL = (SCREEN_COLS - 25) / 2
.const SAVE_DISK_IND_COL = (SCREEN_COLS - 10) / 2

game_over_prompt:
    jsr screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #12
    sta zp_cursor_row
    lda #GAME_OVER_COL
    sta zp_cursor_col
    lda #<game_over_str
    sta zp_ptr0
    lda #>game_over_str
    sta zp_ptr0_hi
    jsr screen_put_string
!gop_loop:
    jsr input_get_key
    cmp #$52                    // 'R' — reboot (same path as quit)
    beq !gop_quit+
    cmp #$53                    // 'S' — start over (restart to title)
    beq !gop_restart+
    cmp #$51                    // 'Q' — quit to BASIC
    bne !gop_loop-
!gop_quit:
    jmp exit_trampoline         // Unified C128 behavior: R == Q
!gop_restart:
    jmp restart_entry
game_over_prompt_end:

// ============================================================
// Entry point
// ============================================================
entry_main:
    sei
    cld
    ldx #$ff
    txs

    // Mask CIA1 interrupts — game mode uses direct hardware access.
    lda #$7f
    sta $dc0d
    lda $dc0d                   // Acknowledge any pending CIA1 interrupt

    // Reset SETBNK to Bank 0 — boot128 left SETBNK=Bank1 after loading
    // the game PRG. Without this reset, all subsequent KERNAL LOADs
    // (overlays, title, etc.) silently write to Bank1 while game reads Bank0.
    lda #0
    ldx #0
    jsr $ff68                   // SETBNK: reset to Bank 0
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp
    jsr disk_reset_session_state

    // Patch reu_show_status: RTS → JMP tramp_reu_show_status
    lda #$4c                    // JMP absolute opcode
    sta reu_show_status
    lda #<tramp_reu_show_status
    sta reu_show_status + 1
    lda #>tramp_reu_show_status
    sta reu_show_status + 2

    // Disable hardware cursor (register 10, bits 6-5 = 01 = cursor off)
    // Prevents KERNAL cursor-blink IRQ from writing to VDC regs 14/15/18/19
    lda #$20
    ldx #10
    jsr vdc_write_reg

    // Initialize VDC display/attribute base explicitly (don't rely on KERNAL defaults).
    // Reg 12/13 = display start address ($0000), Reg 20/21 = attribute start ($0800).
    lda #0
    ldx #12
    jsr vdc_write_reg
    inx                         // 13
    jsr vdc_write_reg
    ldx #21
    jsr vdc_write_reg
    lda #8
    dex                         // 20
    jsr vdc_write_reg

    // Ensure VDC uses per-character attributes (reg 25 bit 6 = 1).
    // Some environments leave this mode undefined after reset/ROM paths.
    ldx #25
    jsr vdc_read_reg
    ora #%01000000
    sta c128_vdc_reg25_cached
    jsr vdc_write_reg

    // Set VDC default colors: foreground white, background black.
    // In attribute mode these are defaults/fallbacks, but setting them
    // explicitly avoids emulator-dependent tinting.
    lda #$f0                    // fg=white (F), bg=black (0)
    sta c128_vdc_reg26_cached
    ldx #26
    jsr vdc_write_reg

    // Set border and background to black (VIC-II — harmless in 80-col mode)
    lda #0
    sta $d020               // Border
    sta $d021               // Background

    // Capture the KERNAL-installed IRQ tail vector before preload starts.
    // Shared preload LOAD transactions temporarily restore this vector.
    lda $0314
    sta kernal_irq_vec_lo
    lda $0315
    sta kernal_irq_vec_hi
    jsr init_common_mmu_helpers
    jsr generation_busy_install
    jsr platform_services_install128
    jsr platform_services_assert_installed

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine

    // Cache KERNAL revision byte — must read from low RAM (below $C000)
    // because MMU_NORMAL banks Screen Editor ROM over $C000-$CFFF.
    lda #MMU_NORMAL             // Expose KERNAL ROM at $E000-$FFFF
    sta $ff00
    lda KERNAL_REV              // $FF80 — in KERNAL ROM
    sta tsi_krev_cached
    :MachineRestoreAllRam()     // Stable runtime invariant: Top Common ON ($D506=$0D)

    lda #0                      // Force REU absent for C128 MVP
    sta reu_present
    sta reu_banks
    sta reu_size_kb
    sta reu_size_kb + 1

    jsr tier_init
    jsr sound_init
    jsr rng_seed

    // Runtime switches to an all-RAM IRQ regime only after preload/KERNAL I/O
    // is complete. Preload asset LOADs require normal CIA/VIC interrupt service.
    lda #$7f
    sta $dc0d               // Mask all CIA1 interrupt sources
    sta $dd0d               // Mask all CIA2 interrupt sources
    lda $dc0d               // Acknowledge pending CIA1
    lda $dd0d               // Acknowledge pending CIA2
    lda #0
    sta $d01a               // Disable all VIC-II interrupt sources
    lda #$ff
    sta $d019               // Acknowledge any pending VIC-II interrupts

    // Disable Screen Editor software cursor blink.
    // VDC reg 10 only disables hardware cursor display; the Screen Editor
    // blink path still runs unless $CC is non-zero.
    lda #$ff
    sta zp_screen_editor_state
    // Keep KERNAL IRQ tail dispatch off the Screen Editor path in runtime.
    lda #<mmu_common_irq
    sta $0314
    lda #>mmu_common_irq
    sta $0315

    lda #$ff
    sta zp_screen_editor_mode   // Screen Editor: 80-col mode

    cli

    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303

    lda #COL_LGREY
    sta zp_text_color

    lda c128_cache_enabled
    beq !load_runtime_low+
    lda #<runtime_low_display_str
    sta zp_ptr0
    lda #>runtime_low_display_str
    sta zp_ptr0_hi
    jsr reu_show_file
!load_runtime_low:
    jsr c128_load_runtime_low_prg
    bcc !runtime_low_loaded+
    jmp entry_main
!runtime_low_loaded:
    jsr c128_load_runtime_input_prg
    bcc !runtime_input_loaded+
    jmp entry_main
!runtime_input_loaded:
    jsr c128_load_runtime_common_prg
    bcc !runtime_common_loaded+
    jmp entry_main
!runtime_common_loaded:
title_enter_menu:
#if C128_REAL_BOOT_DIAG
    ldx #$27
    jsr c128_stack_guard_begin
#endif
    jsr tramp_title_load_and_draw
title_menu_after_art:
#if C128_REAL_BOOT_DIAG
    ldx #$28
    jsr c128_stack_guard_check
#endif
#if C128_TEST_TITLE_ART_CONTENT
    jsr c128_test_title_art_assert
#endif

title_menu_draw:
    sei
    lda #STATUS_ROW
    jsr screen_clear_row
    lda #STATUS_ROW + 1
    jsr screen_clear_row
    lda #STATUS_ROW + 2
    jsr screen_clear_row

    jsr title_show_sysinfo

    // --- Show title menu ---
    lda #COL_WHITE
    sta zp_text_color
    lda #17
    sta zp_cursor_row
    lda #TITLE_MENU_COL
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda disk_setup_done
    beq title_menu_ready
    jsr title_draw_save_disk_indicator

title_menu_ready:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$60
    jsr c128_town_dump_mark
#endif
#if C128_VIC40_BOOT_PROBE
    jsr c128_vic40_boot_probe
#endif
#if C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_overlay_transition_pass_sym
#endif
    cli
!title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
#if C128_TEST_TOWN_SELF_DUMP
    lda #$61
    jsr c128_town_dump_mark
#endif
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    jsr title_require_disk_setup
    bcs title_enter_menu
    jmp title_load_game
!not_l:
    cmp #$44                // 'D' — disk setup
    bne !title_menu_loop-
    jsr tramp_disk_setup
    jmp title_enter_menu

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr sound_play
    jsr msg_init
    jsr disk_prompt_save
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jsr disk_prompt_game
    jmp title_enter_menu

// ============================================================
// c128_load_runtime_low_prg — Load low-RAM resident runtime code to $1000 in Bank 0
// Output: carry clear = success, carry set = error
// ============================================================
.const RUNTIME_LOW_FILE_NUM = 2
runtime_low_filename:
    .byte $31, $32, $38, $2e, $52, $55, $4e, $54, $49, $4d, $45 // "128.RUNTIME"
.const RUNTIME_LOW_FILENAME_LEN = * - runtime_low_filename
runtime_low_display_str:
    .text "128.RUNTIME" ; .byte 0
.const RUNTIME_INPUT_FILE_NUM = 3
runtime_input_filename:
    .byte $31, $32, $38, $2e, $49, $4e, $50, $55, $54 // "128.INPUT"
.const RUNTIME_INPUT_FILENAME_LEN = * - runtime_input_filename
.const RUNTIME_COMMON_FILE_NUM = 4
runtime_common_filename:
    .byte $31, $32, $38, $2e, $46, $44, $49, $53, $4b // "128.FDISK"
.const RUNTIME_COMMON_FILENAME_LEN = * - runtime_common_filename

c128_load_runtime_prg:
    lda #0
    ldx #0
    jsr safe_setbnk

    lda disk_status
    ldx zp_ptr0
    ldy zp_ptr0_hi
    jsr $ffbd

    lda disk_temp
    ldx save_device
    ldy #1
    jsr $ffba

    lda #0
    ldx zp_ptr1
    ldy zp_ptr1_hi
    jsr kernal_load
    php

    lda disk_temp
    jsr $ffc3
    jsr $ffcc

    lda #0
    ldx #0
    jsr safe_setbnk

    plp
    bcs !done+

    lda $dd00
    ora #%00000011
    sta $dd00
    lda #0
    sta zp_kernal_status
!done:
    rts

c128_load_runtime_low_prg:
    lda #RUNTIME_LOW_FILE_NUM
    sta disk_temp
    lda #RUNTIME_LOW_FILENAME_LEN
    sta disk_status
    lda #<runtime_low_filename
    sta zp_ptr0
    lda #>runtime_low_filename
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$10
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg

c128_load_runtime_input_prg:
    lda #RUNTIME_INPUT_FILE_NUM
    sta disk_temp
    lda #RUNTIME_INPUT_FILENAME_LEN
    sta disk_status
    lda #<runtime_input_filename
    sta zp_ptr0
    lda #>runtime_input_filename
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$0b
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg

c128_load_runtime_common_prg:
    lda #RUNTIME_COMMON_FILE_NUM
    sta disk_temp
    lda #RUNTIME_COMMON_FILENAME_LEN
    sta disk_status
    lda #<runtime_common_filename
    sta zp_ptr0
    lda #>runtime_common_filename
    sta zp_ptr0_hi
    lda #$20
    sta zp_ptr1
    lda #$0d
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg


// ============================================================
// Dungeon gen overlay trampoline — overlays now at $0400 (Safe Zone)
// ============================================================

tramp_level_generate:
#if C128_REAL_BOOT_DIAG
    ldx #$39
    jsr c128_stack_guard_begin
#endif
    jsr level_generate
#if C128_REAL_BOOT_DIAG
    ldx #$3a
    jsr c128_stack_guard_check
#endif
    rts

// ============================================================
// Special rooms trampolines — SEI + bank out KERNAL, call $E000+
// ============================================================
.macro C128BankedPreserveFlagsTrampoline(target) {
    php
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr target
    pla
    sta $01
    plp
    rts
}

tramp_assign_special_room:
    :C128BankedPreserveFlagsTrampoline(assign_special_room)

tramp_vault_seal_entrance:
    :C128BankedPreserveFlagsTrampoline(vault_seal_entrance)

.macro C128BankedSharedEpilogueTrampoline(target) {
    sei
    :BankOutKernal()
    jsr target
    jmp tramp_sr_epilogue
}

tramp_spawn_special_room_monsters:
    :C128BankedSharedEpilogueTrampoline(spawn_special_room_monsters)

tramp_spawn_nest_gold:
    :C128BankedSharedEpilogueTrampoline(spawn_nest_gold)

tramp_find_special_room:
    :C128BankedPreserveATrampoline(find_special_room)

tramp_sr_epilogue:
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_roll_ego_type:
    :C128BankedPreserveAReturnTrampoline(roll_ego_type)

tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+
    pha
    sei
    :BankOutKernal()
    pla
    jsr ego_get_suffix_ptr
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
    lda #MMU_ALL_RAM
    sta $ff00
    cli
!teas_done:
    rts

c128_load_arg_x: .byte 0
c128_load_arg_y: .byte 0
kernal_irq_vec_lo: .byte 0
kernal_irq_vec_hi: .byte 0
kernal_hw_irq_vec_lo: .byte 0
kernal_hw_irq_vec_hi: .byte 0
kernal_hw_nmi_vec_lo: .byte 0
kernal_hw_nmi_vec_hi: .byte 0

// C128 cache/overlay state lives in a dedicated main-RAM block.
// Do not place this adjacent to preload UI strings or transient workspace.
c128_cache_state_start:
c128_cache_enabled:        .byte 1
c128_cache_tiers_ready:    .byte 0
c128_cache_overlays_ready: .byte 0
c128_cache_failed:         .byte 0
c128_cache_tier_bits:      .byte 0
c128_cache_overlay_bits:   .byte 0
c128_preload_fn_len:       .byte 0
c128_preload_status:       .byte 0
#if C128_CACHE_TEST_SKIP_TIER
c128_cache_test_skip_tier: .byte 1
#else
c128_cache_test_skip_tier: .byte 0
#endif
#if C128_CACHE_TEST_SKIP_OVERLAY
c128_cache_test_skip_overlay: .byte 2
#else
c128_cache_test_skip_overlay: .byte 0
#endif
c128_startup_overlay_executing: .byte 0

// Keep C128 overlay metadata/state in resident main RAM instead of adjacent
// to overlay code, which was getting trampled before startup overlay loads.
overlay_state_block_start:
current_overlay: .byte 0
ovl_fn_start: .byte $31,$32,$38,$2e,$53,$54,$41,$52,$54              // "128.START"
ovl_fn_start_end:
ovl_fn_town:  .byte $31,$32,$38,$2e,$54,$4f,$57,$4e                  // "128.TOWN"
ovl_fn_town_end:
ovl_fn_death: .byte $31,$32,$38,$2e,$44,$45,$41,$54,$48              // "128.DEATH"
ovl_fn_death_end:
ovl_fn_gen:   .byte $31,$32,$38,$2e,$47,$45,$4e                      // "128.GEN"
ovl_fn_gen_end:
ovl_fn_help:  .byte $31,$32,$38,$2e,$48,$45,$4c,$50                  // "128.HELP"
ovl_fn_help_end:
ovl_fn_ui:    .byte $31,$32,$38,$2e,$55,$49                          // "128.UI"
ovl_fn_ui_end:
ovl_fn_items: .byte $31,$32,$38,$2e,$49,$54,$45,$4d,$53              // "128.ITEMS"
ovl_fn_items_end:
ovl_fn_addr_lo:
    .byte <ovl_fn_start, <ovl_fn_town, <ovl_fn_death, <ovl_fn_gen, <ovl_fn_help, <ovl_fn_ui, <ovl_fn_items
ovl_fn_addr_hi:
    .byte >ovl_fn_start, >ovl_fn_town, >ovl_fn_death, >ovl_fn_gen, >ovl_fn_help, >ovl_fn_ui, >ovl_fn_items
ovl_fn_len:
    .byte ovl_fn_start_end - ovl_fn_start, ovl_fn_town_end - ovl_fn_town, ovl_fn_death_end - ovl_fn_death, ovl_fn_gen_end - ovl_fn_gen, ovl_fn_help_end - ovl_fn_help, ovl_fn_ui_end - ovl_fn_ui, ovl_fn_items_end - ovl_fn_items
ovl_reu_start_lo: .byte 0, 0, 0, 0, 0, 0, 0, 0
ovl_reu_start_hi: .byte 0, 0, 0, 0, 0, 0, 0, 0
ovl_reu_size_lo:  .byte 0, 0, 0, 0, 0, 0, 0, 0
ovl_reu_size_hi:  .byte 0, 0, 0, 0, 0, 0, 0, 0
ol_target:        .byte 0
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
c128_overlay_load_disk_index:  .byte 0
c128_overlay_load_disk_target: .byte 0
c128_overlay_load_disk_len:    .byte 0
c128_overlay_load_disk_lo:     .byte 0
c128_overlay_load_disk_hi:     .byte 0
c128_tramp_player_create_overlay_req: .byte 0
c128_overlay_load_entry_req:          .byte 0
c128_overlay_load_entry_target:       .byte 0
c128_preload_diag_stage:              .byte 0
c128_preload_diag_a:                  .byte 0
c128_preload_diag_x:                  .byte 0
c128_preload_diag_y:                  .byte 0
c128_preload_diag_status:             .byte 0
c128_preload_diag_readst:             .byte 0
c128_preload_diag_port1:              .byte 0
c128_preload_diag_mmu:                .byte 0
c128_preload_diag_pcra:               .byte 0
#endif
ol_save_p:        .byte 0
ol_status_p:      .byte 0
#if C128_TEST_OVERLAY_FN_GUARD
c128_overlay_fn_guard_stage:   .byte 0
c128_overlay_fn_guard_index:   .byte 0
c128_overlay_fn_guard_actual:  .byte 0
c128_overlay_fn_guard_expect:  .byte 0
#endif
overlay_state_block_end:

// c128_stack_guard_begin/check — capture and validate stack balance around
// high-risk KERNAL/overlay/runtime boundaries. On mismatch, preserve the
// expected SP, actual SP, and stage tag in RAM and break immediately.
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG || C128_TEST_TITLE_ART_CONTENT || C128_TEST_STATUS_SP_CANARY || C128_TEST_STACK_SLOT_DIAG || C128_TEST_STACK_BOTTOM_DIAG || C128_TEST_FINAL_RETURN_DIAG
c128_stack_guard_begin:
    jsr c128_stack_guard_verify_canaries
    stx c128_stack_guard_stage
    lda #0
    sta c128_stack_guard_fail_code
    sta c128_stack_guard_substage
    tsx
    stx c128_stack_guard_expected
    rts

c128_stack_guard_check:
    jsr c128_stack_guard_verify_canaries
    stx c128_stack_guard_stage
    tsx
    stx c128_stack_guard_actual
    cpx c128_stack_guard_expected
    beq !c128_stack_guard_ok+
    lda #$e1
    sta c128_stack_guard_fail_code
    stx c128_stack_guard_substage
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_diag_fail_sym
#else
    brk
#endif
!c128_stack_guard_ok:
    rts

c128_stack_guard_verify_canaries:
    lda c128_stack_guard_canary_lo
    cmp #$a5
    bne !c128_stack_guard_bad+
    lda c128_stack_guard_canary_hi
    cmp #$5a
    beq !c128_stack_guard_canaries_ok+
!c128_stack_guard_bad:
    lda #$e0
    sta c128_stack_guard_fail_code
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_diag_fail_sym
#else
    brk
#endif
!c128_stack_guard_canaries_ok:
    rts

c128_stack_guard_snapshot_banking:
    lda $00
    sta c128_stack_guard_port0
    lda $01
    sta c128_stack_guard_port1
    lda $ff00
    sta c128_stack_guard_mmu
    rts

c128_stack_guard_snapshot_return:
    tsx
    lda $0103,x
    sta c128_stack_guard_ret_lo
    lda $0104,x
    sta c128_stack_guard_ret_hi
    rts

#if C128_TEST_STACK_SLOT_DIAG
c128_stack_slot_guard_init:
    sta c128_stack_guard_stage
    lda $01fa
    sta c128_stack_slot_01fa
    lda $01fb
    sta c128_stack_slot_01fb
    lda $01fc
    sta c128_stack_slot_01fc
    lda $01fd
    sta c128_stack_slot_01fd
    lda $01fe
    sta c128_stack_slot_01fe
    lda $01ff
    sta c128_stack_slot_01ff
    rts

c128_stack_slot_guard_check:
    sta c128_stack_guard_stage
    lda $01fa
    cmp c128_stack_slot_01fa
    beq !slot_fb+
    ldx #$fa
    jmp c128_stack_slot_fail
!slot_fb:
    lda $01fb
    cmp c128_stack_slot_01fb
    beq !slot_fc+
    ldx #$fb
    jmp c128_stack_slot_fail
!slot_fc:
    lda $01fc
    cmp c128_stack_slot_01fc
    beq !slot_fd+
    ldx #$fc
    jmp c128_stack_slot_fail
!slot_fd:
    lda $01fd
    cmp c128_stack_slot_01fd
    beq !slot_fe+
    ldx #$fd
    jmp c128_stack_slot_fail
!slot_fe:
    lda $01fe
    cmp c128_stack_slot_01fe
    beq !slot_ff+
    ldx #$fe
    jmp c128_stack_slot_fail
!slot_ff:
    lda $01ff
    cmp c128_stack_slot_01ff
    beq !slot_ok+
    ldx #$ff
    jmp c128_stack_slot_fail
!slot_ok:
    rts

c128_stack_slot_fail:
    stx c128_stack_guard_substage
    sta c128_stack_guard_fail_code
    brk
#endif

#if C128_TEST_STACK_BOTTOM_DIAG
c128_stack_bottom_canary_init:
    sta c128_stack_guard_stage
    lda #$de
    sta $0100
    lda #$ad
    sta $0101
    lda #$be
    sta $0102
    rts

c128_stack_bottom_canary_check:
    sta c128_stack_guard_stage
    lda $0100
    cmp #$de
    beq !bottom_0101+
    ldx #$00
    jmp c128_stack_bottom_fail
!bottom_0101:
    lda $0101
    cmp #$ad
    beq !bottom_0102+
    ldx #$01
    jmp c128_stack_bottom_fail
!bottom_0102:
    lda $0102
    cmp #$be
    beq !bottom_ok+
    ldx #$02
    jmp c128_stack_bottom_fail
!bottom_ok:
    rts

c128_stack_bottom_fail:
    stx c128_stack_guard_substage
    sta c128_stack_guard_fail_code
    brk
#endif

#if C128_TEST_FINAL_RETURN_DIAG
c128_final_return_capture:
    sta c128_final_return_stage
    tsx
    stx c128_final_return_sp
    lda $01
    sta c128_final_return_port1
    lda $ff00
    sta c128_final_return_mmu
    lda #<tramp_player_create_return_site
    sta c128_final_return_expected_lo
    lda #>tramp_player_create_return_site
    sta c128_final_return_expected_hi
    lda $0101,x
    sta c128_final_return_stack_0
    lda $0102,x
    sta c128_final_return_stack_1
    lda $0103,x
    sta c128_final_return_stack_2
    lda $0104,x
    sta c128_final_return_stack_3
    lda $0105,x
    sta c128_final_return_stack_4
    lda $0106,x
    sta c128_final_return_stack_5
    lda $0107,x
    sta c128_final_return_stack_6
    lda $0108,x
    sta c128_final_return_stack_7
    rts

c128_final_return_check:
    jsr c128_final_return_capture
    lda c128_final_return_stack_0
    cmp c128_final_return_expected_lo
    beq !final_ret_hi+
    ldx #0
    jmp c128_final_return_fail
!final_ret_hi:
    lda c128_final_return_stack_1
    cmp c128_final_return_expected_hi
    beq !final_ret_ok+
    ldx #1
    jmp c128_final_return_fail
!final_ret_ok:
    rts

c128_final_return_fail:
    stx c128_final_return_fail_slot
    sta c128_final_return_fail_actual
    brk
#endif


#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
c128_diag_validate_runtime_invariants:
    stx c128_stack_guard_stage
    jsr c128_stack_guard_snapshot_banking
    tsx
    stx c128_stack_guard_actual
    cpx #$40
    bcs !stack_ok+
    lda #$e2
    sta c128_stack_guard_fail_code
    stx c128_stack_guard_substage
    jmp c128_diag_fail_sym
!stack_ok:
    lda $00
    cmp #CPU_PORT_DDR_DEFAULT
    beq !port0_ok+
    sta c128_stack_guard_fail_code
    lda #1
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!port0_ok:
    lda $01
    tax
    and #$07
    cmp #(BANK_NO_BASIC & $07)
    beq !port1_ok+
    txa
    sta c128_stack_guard_fail_code
    lda #2
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!port1_ok:
    lda $ff00
    cmp #MMU_ALL_RAM
    beq !mmu_ok+
    sta c128_stack_guard_fail_code
    lda #3
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!mmu_ok:
    lda $0314
    cmp #<mmu_common_irq
    beq !irq_lo_ok+
    sta c128_stack_guard_fail_code
    lda #4
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!irq_lo_ok:
    lda $0315
    cmp #>mmu_common_irq
    beq !irq_hi_ok+
    sta c128_stack_guard_fail_code
    lda #5
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!irq_hi_ok:
    lda $fffa
    cmp #<mmu_common_nmi
    beq !nmi_lo_ok+
    sta c128_stack_guard_fail_code
    lda #6
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!nmi_lo_ok:
    lda $fffb
    cmp #>mmu_common_nmi
    beq !nmi_hi_ok+
    sta c128_stack_guard_fail_code
    lda #7
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!nmi_hi_ok:
    lda $fffe
    cmp #<mmu_common_irq
    beq !hw_irq_lo_ok+
    sta c128_stack_guard_fail_code
    lda #8
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!hw_irq_lo_ok:
    lda $ffff
    cmp #>mmu_common_irq
    beq !hw_irq_hi_ok+
    sta c128_stack_guard_fail_code
    lda #9
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!hw_irq_hi_ok:
    lda $0302
    cmp #<chrin_keyboard_stub
    beq !chrin_lo_ok+
    sta c128_stack_guard_fail_code
    lda #$0a
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!chrin_lo_ok:
    lda $0303
    cmp #>chrin_keyboard_stub
    beq !chrin_hi_ok+
    sta c128_stack_guard_fail_code
    lda #$0b
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!chrin_hi_ok:
    jsr c128_diag_verify_helper_blob
    rts

c128_diag_verify_helper_blob:
    ldx #0
!helper_loop:
    lda MMU_COMMON_HELPERS_BASE,x
    cmp mmu_common_helpers_blob,x
    beq !helper_next+
    sta c128_stack_guard_fail_code
    txa
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!helper_next:
    inx
    cpx #mmu_common_helpers_blob_end - mmu_common_helpers_blob - 1
    bne !helper_loop-
    rts
#endif

#if C128_TEST_STATUS_SP_CANARY
.assert "Status canary trap stays below fixed debug slot", * <= $3ef8, true
c128_status_ret_corrupt:
    nop
    jmp c128_status_ret_corrupt
.assert "Status canary state fits before fixed debug slot", * <= $3efc, true
c128_status_ret_expected_lo: .byte 0
c128_status_ret_expected_hi: .byte 0
c128_status_ret_actual_lo:   .byte 0
c128_status_ret_actual_hi:   .byte 0
#endif

c128_stack_guard_canary_lo: .byte $a5
c128_stack_guard_expected:  .byte 0
c128_stack_guard_actual:    .byte 0
c128_stack_guard_stage:     .byte 0
c128_stack_guard_canary_hi: .byte $5a
c128_stack_guard_port0:     .byte 0
c128_stack_guard_port1:     .byte 0
c128_stack_guard_mmu:       .byte 0
c128_stack_guard_ret_lo:    .byte 0
c128_stack_guard_ret_hi:    .byte 0
c128_stack_guard_fail_code: .byte 0
c128_stack_guard_substage:  .byte 0
#if C128_TEST_STACK_SLOT_DIAG
c128_stack_slot_01fa:       .byte 0
c128_stack_slot_01fb:       .byte 0
c128_stack_slot_01fc:       .byte 0
c128_stack_slot_01fd:       .byte 0
c128_stack_slot_01fe:       .byte 0
c128_stack_slot_01ff:       .byte 0
#endif
#if C128_TEST_FINAL_RETURN_DIAG
c128_final_return_stage:       .byte 0
c128_final_return_sp:          .byte 0
c128_final_return_port1:       .byte 0
c128_final_return_mmu:         .byte 0
c128_final_return_expected_lo: .byte 0
c128_final_return_expected_hi: .byte 0
c128_final_return_fail_slot:   .byte 0
c128_final_return_fail_actual: .byte 0
c128_final_return_stack_0:     .byte 0
c128_final_return_stack_1:     .byte 0
c128_final_return_stack_2:     .byte 0
c128_final_return_stack_3:     .byte 0
c128_final_return_stack_4:     .byte 0
c128_final_return_stack_5:     .byte 0
c128_final_return_stack_6:     .byte 0
c128_final_return_stack_7:     .byte 0
.label final_return_diag_stage = c128_final_return_stage
.label final_return_diag_sp = c128_final_return_sp
.label final_return_diag_port1 = c128_final_return_port1
.label final_return_diag_mmu = c128_final_return_mmu
.label final_return_diag_expected_lo = c128_final_return_expected_lo
.label final_return_diag_expected_hi = c128_final_return_expected_hi
.label final_return_diag_fail_slot = c128_final_return_fail_slot
.label final_return_diag_fail_actual = c128_final_return_fail_actual
.label final_return_diag_stack0 = c128_final_return_stack_0
.label final_return_diag_stack7 = c128_final_return_stack_7
#endif
#endif
ovl_cache_base_lo: .byte 0
ovl_cache_base_hi: .byte 0
ovl_ready_mask:
    .byte 0, %00000001, %00000010, %00000100, %00001000, %00010000, %00100000, %01000000
c128_cache_state_end:

.assert "Program fits below map area", * <= MAP_BASE, true

.const DUNGEON_GEN_BUSY = 1

// ============================================================
// Imports — Game Engine (Safe to spill past $C000)
// ============================================================
#import "../common/tables.s"
#import "../common/item_defs.s"
#import "../common/reu.s"
#import "../common/rng.s"
#import "../common/math.s"
#import "../common/player.s"
#import "../common/ui_messages.s"
#import "../common/ui_status.s"
#import "../common/generation_busy.s"
#import "../common/stat_display.s"
#import "../common/huffman.s"
#import "../common/runtime_ui_strings.s"
#import "../common/io_kernal_consts.s"
#import "../common/score_io.s"

#import "../common/dungeon_data.s"
#import "../common/dungeon_features.s"
#import "../common/monster.s"
#import "../common/tier_manager.s"
#import "../common/overlay.s"
#import "../common/monster_ai.s"
#import "../common/recall.s"
#import "../common/monster_magic.s"
#import "../common/spell_data.s"
#import "../common/spell_effects.s"
#import "../common/item.s"
#import "../common/store_data.s"
#import "../common/save.s"
#import "../common/disk_swap.s"
#import "../common/dungeon_los.s"
#import "../common/monster_attack.s"
#import "../common/combat.s"
#import "../common/player_move.s"
#import "../common/look_flash_target.s"
#import "../common/ui_help_clear.s"
#import "../common/wizard.s"
#import "../common/game_loop.s"
#import "../common/turn.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../common/player_items.s"
#import "../common/player_magic_state.s"
#import "../common/perf_p1.s"

// Init-only strings — kept in main RAM
// ============================================================
title_str:
    .text "MORIA8 C=128" ; .byte 0
#if C128_TEST_TITLE_ART_CONTENT
c128_test_title_art_assert:
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    ldy #0
    jsr mmu_safe_map_read_ptr1
    cmp #1
    beq !check_screen+
    sta c128_stack_guard_fail_code
    lda #$10
    sta c128_stack_guard_substage
    jmp c128_test_title_art_fail_sym
!check_screen:
    lda #1
    sta zp_cursor_row
    lda #21
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$2b
    beq !check_logo+
    sta c128_stack_guard_fail_code
    lda #1
    sta c128_stack_guard_substage
    jmp c128_test_title_art_fail_sym
!check_logo:

    lda #3
    sta zp_cursor_row
    lda #24
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$20
    bne !block_fail+
    lda zp_color_hi
    ldy zp_color_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #(VDC_WHITE | $40)
    beq !pass+
!block_fail:
    sta c128_stack_guard_fail_code
    lda #2
    sta c128_stack_guard_substage
    jmp c128_test_title_art_fail_sym

!pass:
    jmp c128_test_title_art_pass_sym
#endif
#if C128_TEST_TITLE_KEY_TRAP
title_key_trap_base:
    .fill 256, $00
#endif
#if C128_TEST_SCRIPTED_INPUT
c128_test_summary_seen:
    .byte 0
c128_test_summary_count:
    .byte 0
#elif C128_TEST_CACHE_SURVIVAL
c128_test_summary_seen:
    .byte 0
c128_test_summary_count:
    .byte 0
#endif
#if C128_TEST_CACHE_SURVIVAL
c128_test_cache_probe_common:      .byte 0
c128_test_cache_probe_tier:        .byte 0
c128_test_cache_probe_ovl_start:   .byte 0
c128_test_cache_probe_ovl_town:    .byte 0
c128_test_cache_probe_ovl_death:   .byte 0
c128_test_cache_probe_ovl_gen:     .byte 0

c128_test_read_bank1_probe_ptr1:
    ldy #0
    jsr mmu_safe_db_read_ptr1
    rts

c128_test_snapshot_cache_probes:
    lda MMU_COMMON_HELPERS_BASE
    sta c128_test_cache_probe_common

    lda #<BANK1_TIER_CACHE_BASE
    sta zp_ptr1
    lda #>BANK1_TIER_CACHE_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    sta c128_test_cache_probe_tier

    lda #<BANK1_OVERLAY_STARTUP_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_STARTUP_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    sta c128_test_cache_probe_ovl_start

    lda #<BANK1_OVERLAY_TOWN_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_TOWN_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    sta c128_test_cache_probe_ovl_town

    lda #<BANK1_OVERLAY_DEATH_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_DEATH_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    sta c128_test_cache_probe_ovl_death

    lda #<BANK1_OVERLAY_DUNGEON_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_DUNGEON_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    sta c128_test_cache_probe_ovl_gen
    clc
    rts
#endif

#if C128
c128_test_expected_tier_bits:
    lda #%00001111
#if C128_CACHE_TEST_SKIP_TIER
    ldx c128_cache_test_skip_tier
    beq !ctet_done+
    eor c128_tier_ready_mask_minus1,x
!ctet_done:
#endif
    rts

c128_test_expected_overlay_bits:
    lda #%00011111
#if C128_CACHE_TEST_SKIP_OVERLAY
    ldx c128_cache_test_skip_overlay
    beq !cteo_done+
    eor ovl_ready_mask,x
!cteo_done:
#endif
    rts

c128_test_validate_tier_partial_state:
    lda c128_cache_tiers_ready
    cmp #1
    bne !ctv_fail+
    jsr c128_test_expected_tier_bits
    cmp c128_cache_tier_bits
    bne !ctv_fail+
    lda c128_cache_overlays_ready
    cmp #1
    bne !ctv_fail+
    jsr c128_test_expected_overlay_bits
    cmp c128_cache_overlay_bits
    bne !ctv_fail+
    clc
    rts
!ctv_fail:
    sec
    rts

c128_test_validate_overlay_partial_state:
    lda c128_cache_tiers_ready
    cmp #1
    bne !ctvo_fail+
    jsr c128_test_expected_tier_bits
    cmp c128_cache_tier_bits
    bne !ctvo_fail+
    lda c128_cache_overlays_ready
    cmp #1
    bne !ctvo_fail+
    jsr c128_test_expected_overlay_bits
    cmp c128_cache_overlay_bits
    bne !ctvo_fail+
    clc
    rts
!ctvo_fail:
    sec
    rts
#endif

#if C128_VIC40_BOOT_PROBE
c128_vic40_boot_probe:
    lda $d011
    cmp #$1b
    bne c128_vic40_boot_probe_fail_sym
    lda $d018
    cmp #$14
    bne c128_vic40_boot_probe_fail_sym

    ldx #0
!vic40_screen_loop:
    lda $0400,x
    cmp #$20
    beq !vic40_screen_ok+
    cmp #$00
    bne c128_vic40_boot_probe_fail_sym
!vic40_screen_ok:
    inx
    cpx #$40
    bne !vic40_screen_loop-

    lda $d800
    sta zp_temp0
    ldx #0
!vic40_color_loop:
    lda $d800,x
    cmp zp_temp0
    bne c128_vic40_boot_probe_fail_sym
    inx
    cpx #$40
    bne !vic40_color_loop-

    jmp c128_vic40_boot_probe_pass_sym
#endif

c128_vic40_boot_probe_pass_sym:
    nop
    jmp c128_vic40_boot_probe_pass_sym

c128_vic40_boot_probe_fail_sym:
    nop
    jmp c128_vic40_boot_probe_fail_sym

#if C128_TEST_CACHE_SURVIVAL
c128_test_verify_cache_survival:
    lda c128_cache_tiers_ready
    cmp #1
    bne !ctcs_fail+
    lda c128_cache_tier_bits
    cmp #%00001111
    bne !ctcs_fail+
    lda c128_cache_overlays_ready
    cmp #1
    bne !ctcs_fail+
    lda c128_cache_overlay_bits
    cmp #%00011111
    bne !ctcs_fail+

    lda MMU_COMMON_HELPERS_BASE
    cmp c128_test_cache_probe_common
    bne !ctcs_fail+

    lda #<BANK1_TIER_CACHE_BASE
    sta zp_ptr1
    lda #>BANK1_TIER_CACHE_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    cmp c128_test_cache_probe_tier
    bne !ctcs_fail+

    lda #<BANK1_OVERLAY_STARTUP_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_STARTUP_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    cmp c128_test_cache_probe_ovl_start
    bne !ctcs_fail+

    lda #<BANK1_OVERLAY_TOWN_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_TOWN_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    cmp c128_test_cache_probe_ovl_town
    bne !ctcs_fail+

    lda #<BANK1_OVERLAY_DEATH_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_DEATH_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    cmp c128_test_cache_probe_ovl_death
    bne !ctcs_fail+

    lda #<BANK1_OVERLAY_DUNGEON_BASE
    sta zp_ptr1
    lda #>BANK1_OVERLAY_DUNGEON_BASE
    sta zp_ptr1_hi
    jsr c128_test_read_bank1_probe_ptr1
    cmp c128_test_cache_probe_ovl_gen
    bne !ctcs_fail+
    clc
    rts
!ctcs_fail:
    sec
    rts
#endif

.segment RuntimeCommonData
.pseudopc $0d20 {
runtime_common_data_start:
    #import "../common/disk_setup_runtime128.s"
    #import "../common/title_cache_runtime128.s"
runtime_common_data_end:
}
.segment Default

// RuntimeInputData segment — dedicated raw C128 run-input helpers loaded into
// the reclaimed boot-sector page after boot completes.
.segment RuntimeInputData
.pseudopc $0b00 {
runtime_input_data_start:
    #import "input_run_raw128.s"
runtime_input_data_end:
}
.segment Default

// RuntimeLowData segment — low-RAM resident code loaded into Bank 0 before title.
.segment RuntimeLowData
.pseudopc $1000 {
runtime_low_data_start:
    #import "monster_threat_vdc.s"
    #import "dungeon_render_vdc.s"
    #import "../common/ego_items.s"
runtime_low_data_end:
}
.segment Default


// ============================================================
// Banked code payload — stored inline here, copied to $F000
// at startup by init_copy_banked. Runs in Bank 0 at $F000-$FFFA.
// Banked UI/logic functions live in Bank 0 and are accessible with
// $FF00=$3E (MMU_ALL_RAM).
//
// Keep $E000-$EFFF reserved for OVL_* (overlays). Banked UI/logic
// occupies the resident window at $F000-$FFFA; UI trampolines recopy
// the payload before entry so overlay/cache activity cannot leave stale code
// there.
// ============================================================
banked_payload:
.pseudopc $F000 {
first_banked_function:
    #import "../common/ui_home.s"
    #import "../common/player_magic_display.s"
    #import "../common/player_magic_state_ops.s"
    #import "../common/player_magic.s"
    #import "../common/player_magic_levelup.s"
    #import "../common/player_magic_learn_op.s"
    #import "../common/player_magic_tail.s"
    #import "../common/projectile.s"
    #import "../common/ranged_fire.s"
    #import "../common/tunnel.s"
    #import "../common/throw.s"
    #import "../common/bash.s"

banked_code_end:
}
banked_payload_end:

.print "Banked payload: " + (banked_payload_end - banked_payload) + " bytes at $" + toHexString(banked_payload) + "-$" + toHexString(banked_payload_end)
.assert "Banked code fits below CPU vectors", banked_code_end <= $FFFA, true
.assert "Banked payload starts above overlay window", first_banked_function >= $F000, true
.assert "Banked payload staged source ends below overlay window", banked_payload_end <= $E000, true

// ============================================================
// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.print "Program image: $" + toHexString($1c01) + "-$" + toHexString(program_end - 1)
#if C128
.assert "boot128 staged image reaches map region", program_end - 1 >= MAP_BASE, true
.assert "boot128 staged image reaches Bank1 DB region", program_end - 1 >= BANK1_DB_BASE, true
.assert "Staged Bank1 source span matches boot scrub ceiling", BANK1_STAGE_SOURCE_END == BANK1_RESERVED_TOP_END, true
.assert "Tier cache window remains large enough for tier preload", BANK1_TIER_CACHE_SIZE >= TIER_PRELOAD_REQUIRED, true
.assert "MMU helper page stays inside common RAM ownership", MMU_COMMON_HELPERS_BASE >= BANK1_COMMON_BASE, true
.assert "MMU helper page ends inside common RAM ownership", MMU_COMMON_HELPERS_BASE + (mmu_common_helpers_blob_end - mmu_common_helpers_blob) - 1 <= BANK1_COMMON_END, true
.assert "Runtime input code stays inside boot-sector page ownership", runtime_input_data_start >= $0b00 && runtime_input_data_end <= $0c00, true
.assert "C128 FEAT-DISK common runtime stays in common RAM", runtime_common_data_end <= $1000, true
.assert "Low runtime code stays below floor-item table", runtime_low_data_end <= FLOOR_ITEM_BASE, true
.assert "Ego roll routine stays in low runtime RAM", roll_ego_type < FLOOR_ITEM_BASE, true
.assert "Ego damage routine stays in low runtime RAM", ego_apply_damage < FLOOR_ITEM_BASE, true
.assert "Ego AC table stays in low runtime RAM", ego_ac_bonus < FLOOR_ITEM_BASE, true
.assert "Cache state block stays in Bank0 program RAM", c128_cache_state_start >= $1c01, true
.assert "Cache state block ends before overlay window", c128_cache_state_end < $e000, true
.assert "Overlay state block starts in resident Bank0 RAM", overlay_state_block_start >= c128_cache_state_start && overlay_state_block_start < $e000, true
.assert "Overlay state block ends before overlay window", overlay_state_block_end < $e000, true
.assert "Overlay state block stays inside cache-state ownership", overlay_state_block_end <= c128_cache_state_end, true
#endif
.macro C128AuditBelowIo(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays below the I/O hole", symbol < $D000, true
}

.macro C128AuditOutOfIo(name, symbol, window_start) {
    .assert "AUDIT-IO-C128 " + name + " stays out of the I/O hole", symbol < $D000 || symbol >= window_start, true
}

.macro C128AuditRuntimeLow(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in runtime.low Bank 0 RAM", symbol >= runtime_low_data_start && symbol < runtime_low_data_end, true
}

.macro C128AuditRuntimeInput(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in runtime.input Bank 0 RAM", symbol >= runtime_input_data_start && symbol < runtime_input_data_end, true
}

.macro C128AuditStartupOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the startup overlay", symbol >= $E000 && symbol < ovl_start_end, true
}

.macro C128AuditTownOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the town overlay", symbol >= $E000 && symbol < ovl_town_end, true
}

.macro C128AuditDeathOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the death overlay", symbol >= $E000 && symbol < ovl_death_end, true
}

.macro C128AuditHelpOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the help overlay", symbol >= $E000 && symbol < ovl_help_end, true
}

.macro C128AuditUiOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the UI overlay", symbol >= $E000 && symbol < ovl_ui_end, true
}

.macro C128AuditItemsOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the items overlay", symbol >= $E000 && symbol < ovl_items_end, true
}

.macro C128AuditDungeonOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the dungeon overlay", symbol >= $E000 && symbol < ovl_gen_end, true
}

.macro C128AuditBanked(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the reloadable banked window", symbol >= $F000 && symbol < banked_code_end, true
}

#import "io_contracts.s"

.assert "Title menu string stays below I/O hole", title_menu_str < $D000, true
.assert "Save-disk indicator stays below I/O hole", ds_ind_pfx < $D000, true
.assert "Need-save message stays below I/O hole", disk_need_save_str < $D000, true
.assert "Wrong-save message stays below I/O hole", disk_bad_save_str < $D000, true
.assert "Game-over prompt end stays below I/O hole", game_over_prompt_end < $D000, true
.assert "Game-over prompt text stays below I/O hole", game_over_str < $D000, true
.assert "Game-over prompt text end stays below I/O hole", game_over_str_end < $D000, true
.assert "Message history buffer matches configured width", (msg_hist_idx - msg_history) == MSG_HIST_BYTES, true
.assert "VDC attribute mode keeps alternate charset enabled", VDC_ATTR_MODE == $80, true


// ============================================================
// Init-only code — lives past CREATURE_BASE, safe because it runs
// once at startup before dungeon map or RLE workspace are used.
// ============================================================

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
.segment TownOverlay
    #import "../common/store.s"
    #import "../common/ui_store.s"
    #import "../common/ui_home_text.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $f000, true

// ============================================================
// Startup overlay — character creation at $E000
// ============================================================
.segment StartupOverlay
    #import "../common/background_data.s"
    #import "../common/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $f000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
.segment DeathOverlay
    #import "../common/score.s"
    #import "../common/player_magic_execute_overlay.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $f000, true

// ============================================================
// Help overlay — dedicated help screen at $E000
// ============================================================
.segment HelpOverlay
    #import "ui_help_data_80.s"
    #import "../common/ui_help.s"
    #import "../common/ui_disk_setup.s"
    #import "../common/ui_inventory.s"
    #import "../common/ui_equipment.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $f000, true

// ============================================================
// UI overlay — modal UI and symbol identify screens at $E000
// ============================================================
.segment UiOverlay
    #import "../common/ui_character.s"
    #import "../common/ui_recall.s"
    #import "../common/ui_wizard.s"
    #import "../common/spell_names.s"
    #import "../common/player_magic_select_overlay.s"
    #import "../common/player_gain_spell.s"
    #import "../common/title_screen.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $f000, true
.assert "Help title text stays inside help overlay", help_title_str >= $E000 && help_title_str < ovl_help_end, true
.assert "Help content table stays inside help overlay", help_lines >= $E000 && help_lines < ovl_help_end, true

// ============================================================
// Item actions overlay — low-frequency read/aim/use/refuel commands
// ============================================================
.segment ItemActionsOverlay
    #import "../common/item_actions_overlay.s"
ovl_items_end:
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $f000, true

// ============================================================
// Dungeon generation overlay
// ============================================================
.segment DungeonGenOverlay
    #import "../common/special_rooms.s"
    #import "../common/dungeon_gen.s"
ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $f000, true
.assert "banked_payload_start above overlay ceiling", first_banked_function > ovl_gen_end, true
