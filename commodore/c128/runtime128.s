// runtime128.s — Centralized C128 runtime ownership
//
// This is the only module that owns the long-lived runtime transition state:
//   - MMU/processor port mode for gameplay vs KERNAL I/O
//   - hardware and low-RAM IRQ/NMI vectors
//   - CHRIN keyboard stub
//   - common-RAM MMU helper integrity

// safe_irq — Minimal IRQ handler for $FF00=$3E mode.
// When $FF00=$3E (game mode), the CPU reads the IRQ vector from RAM.
// We can't dispatch to the KERNAL handler (hidden behind RAM), so we
// just acknowledge all interrupt sources and return.
safe_irq:
    pha
    txa
    pha
    tya
    pha
    lda $dc0d               // Acknowledge CIA1 interrupt (read clears flags)
    lda #$ff
    sta $d019               // Acknowledge VIC-II interrupts
safe_irq_restore:
    pla
    tay
    pla
    tax
    pla
    rti

// safe_nmi — Minimal NMI handler for $FF00=$3E mode.
safe_nmi:
    pha
    lda $dd0d               // Acknowledge CIA2 NMI
    pla
    rti

chrin_keyboard_stub:
    lda #0
    clc
    rts

// c128_runtime_capture_kernal_vectors — Snapshot the live KERNAL vector state
// before runtime replaces it with the all-RAM handlers.
c128_runtime_capture_kernal_vectors:
    lda $0314
    sta kernal_irq_vec_lo
    lda $0315
    sta kernal_irq_vec_hi
    lda $0302
    sta kernal_chrin_vec_lo
    lda $0303
    sta kernal_chrin_vec_hi
    lda $fffa
    sta kernal_nmi_vec_lo
    lda $fffb
    sta kernal_nmi_vec_hi
    lda $fffe
    sta kernal_hw_irq_vec_lo
    lda $ffff
    sta kernal_hw_irq_vec_hi
    rts

// c128_runtime_enter_kernal_io — Restore the real KERNAL/Screen Editor runtime.
// Callers must preserve their own registers if needed.
c128_runtime_enter_kernal_io:
    php
    sei
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_ALL_ROM
    sta $01
    lda kernal_irq_vec_lo
    sta $0314
    lda kernal_irq_vec_hi
    sta $0315
    lda kernal_chrin_vec_lo
    sta $0302
    lda kernal_chrin_vec_hi
    sta $0303
    lda kernal_nmi_vec_lo
    sta $fffa
    lda kernal_nmi_vec_hi
    sta $fffb
    lda kernal_hw_irq_vec_lo
    sta $fffe
    lda kernal_hw_irq_vec_hi
    sta $ffff
    lda #MMU_ALL_RAM
    sta c128_kernal_return_mmu
    lda #C128_RUNTIME_STATE_KERNAL_IO
    sta c128_runtime_state_current
    plp
    rts

// c128_runtime_enter_game_ram — Restore the stable all-RAM gameplay runtime.
// Callers must preserve their own registers if needed.
c128_runtime_enter_game_ram:
    php
    sei
    lda #BANK_NO_BASIC
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    lda #<safe_irq
    sta $fffe
    lda #>safe_irq
    sta $ffff
    lda #<safe_nmi
    sta $fffa
    lda #>safe_nmi
    sta $fffb
    lda #<safe_irq_restore
    sta $0314
    lda #>safe_irq_restore
    sta $0315
    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303
    lda #$ff
    sta $cc
    lda #MMU_ALL_RAM
    sta c128_kernal_return_mmu
    lda #C128_RUNTIME_STATE_GAME_RAM
    sta c128_runtime_state_current
    plp
    rts

// c128_runtime_fail_helper_integrity — Deterministic stop for helper corruption.
c128_runtime_fail_helper_integrity:
    brk
    jmp c128_runtime_fail_helper_integrity

// c128_runtime_require_helpers — Validate and reinstall the common helper page.
c128_runtime_require_helpers:
    jsr c128_ensure_common_mmu_helpers
    bcc !ok+
    jmp c128_runtime_fail_helper_integrity
!ok:
    rts

// Compatibility surface for existing shared code.
c128_restore_runtime_vectors:
    jmp c128_runtime_enter_game_ram

c128_restore_runtime_guards:
    pha
    txa
    pha
    tya
    pha
    php
    sei
    jsr c128_runtime_enter_game_ram
    jsr c128_runtime_require_helpers
    plp
    pla
    tay
    pla
    tax
    pla
    rts

c128_runtime_state_current: .byte C128_RUNTIME_STATE_GAME_RAM
c128_kernal_return_mmu: .byte MMU_ALL_RAM
kernal_irq_vec_lo: .byte 0
kernal_irq_vec_hi: .byte 0
kernal_chrin_vec_lo: .byte 0
kernal_chrin_vec_hi: .byte 0
kernal_nmi_vec_lo: .byte 0
kernal_nmi_vec_hi: .byte 0
kernal_hw_irq_vec_lo: .byte 0
kernal_hw_irq_vec_hi: .byte 0
