#importonce
// preload128.s — C128 preload-only LOAD transaction.
//
// Moved here from platforms/commodore/common/reu.s: this routine is C128-only
// (HAL_MEMORY_PRELOAD_ASSET_LOAD) and is the platform asset-load HAL entry
// (hal_asset_load_prg_header in config128.s). It is not REU code.

#if HAL_MEMORY_PRELOAD_ASSET_LOAD
// ============================================================
// c128_preload_asset_load — Shared preload-only LOAD transaction
// ============================================================
// Input:
//   A = filename length
//   X = filename pointer lo
//   Y = filename pointer hi
// Output:
//   carry clear = success
//   carry set   = LOAD failed
// Clobbers: A, X, Y
c128_preload_asset_load:
    php
    sei
#if C128_TEST_STACK_LOW_WATER
    lda #$a5
    jsr c128_stack_low_water_check
#endif
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_a
    stx c128_preload_diag_x
    sty c128_preload_diag_y
    lda #$c1
    sta c128_preload_diag_stage
#endif
    sta c128_preload_fn_len
    stx c128_preload_fn_lo
    sty c128_preload_fn_hi
    pla
    sta c128_preload_saved_p
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$11
    jsr c128_stack_guard_begin
#endif

    lda #0
    ldx #0
    jsr safe_setbnk             // LOAD destination bank = Bank 0

    lda #2
    jsr w_close                 // Pre-close stale preload channel
    jsr w_clrchn                // Restore default I/O channels

    lda c128_preload_fn_len
    ldx c128_preload_fn_lo
    ldy c128_preload_fn_hi
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_a
    stx c128_preload_diag_x
    sty c128_preload_diag_y
    lda #$c2
    sta c128_preload_diag_stage
#endif
    jsr w_setnam

    lda #2
    ldx program_device
    ldy #1
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_a
    stx c128_preload_diag_x
    sty c128_preload_diag_y
    lda #$c3
    sta c128_preload_diag_stage
#endif
    jsr w_setlfs                // PRG header address

    lda #0
    ldx #0
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    lda #$00
    sta c128_preload_diag_a
    sta c128_preload_diag_x
    lda #$e0
    sta c128_preload_diag_y
    lda #$c4
    sta c128_preload_diag_stage
#endif
    ldy #$e0
    jsr w_load
#if C128_TEST_STACK_LOW_WATER
    lda #$a6
    jsr c128_stack_low_water_check
#endif
    lda #0
    rol                         // A=1 on error, 0 on success
    sta c128_preload_status
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_status
    lda zp_kernal_status
    sta c128_preload_diag_readst
    lda hal_memory_cpu_port
    sta c128_preload_diag_port1
    lda hal_memory_mmu_config_register
    sta c128_preload_diag_mmu
    lda hal_memory_mmu_preconfig_a
    sta c128_preload_diag_pcra
    lda #$c5
    sta c128_preload_diag_stage
#endif

    lda #2
    jsr w_close
    jsr w_clrchn
    lda #0
    ldx #0
    jsr safe_setbnk             // Restore default LOAD destination bank
#if C128_TEST_STACK_LOW_WATER
    lda #$a7
    jsr c128_stack_low_water_check
#endif
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$19
    jsr c128_stack_guard_snapshot_banking
    jsr c128_diag_validate_runtime_invariants
#endif

    lda c128_preload_status
    beq !c128_preload_ok+
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$12
    jsr c128_stack_guard_check
#endif
    sec
    jmp c128_preload_finish
!c128_preload_ok:
#if C128_TEST_STACK_LOW_WATER
    lda #$a8
    jsr c128_stack_low_water_check
#endif
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$13
    jsr c128_stack_guard_check
#endif
    clc
c128_preload_finish:
    php
    lda c128_preload_saved_p
    and #$04
    bne !restore_p+
    pla
    and #$fb
    pha
!restore_p:
    plp
    rts

c128_preload_fn_lo: .byte 0
c128_preload_fn_hi: .byte 0
c128_preload_saved_p: .byte 0
#endif
