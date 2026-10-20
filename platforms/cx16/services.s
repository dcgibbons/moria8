#importonce
// services.s — Commander X16 hal_sound_*, hal_irq_*, and hal_platform_*
// lifecycle routines.

#import "hal/layout.s"

// ============================================================
// Sound HAL
// ============================================================
hal_sound_init:
hal_sound_stop:
    stz zp_snd_timer
    stz zp_snd_phase
    lda #$ff                // SFX_NONE
    sta zp_snd_effect
    clc
    rts

hal_sound_play:
hal_sound_update:
    clc
    rts

// ============================================================
// IRQ HAL
// ============================================================
hal_irq_install_runtime:
    clc
    rts

hal_irq_restore_os:
    clc
    rts

hal_irq_mask:
    sei
    rts

hal_irq_unmask:
    cli
    rts

hal_irq_ack:
    rts

hal_irq_critical_begin:
    sei
    rts

hal_irq_critical_end:
    cli
    rts

// ============================================================
// Platform Lifecycle
// ============================================================
hal_platform_init_early:
    stz CX16_ROM_BANK_REG
    stz CX16_RAM_BANK_REG
    jsr screen_init
    clc
    rts

hal_platform_init_runtime:
    jsr hal_sound_init
    clc
    rts

cx16_platform_main_loop_begin:
    clc
    rts

cx16_platform_vector_reassert:
    clc
    rts

cx16_platform_runtime_resync:
    stz CX16_ROM_BANK_REG
    clc
    rts

hal_platform_character_sheet_begin:
    clc
    rts

hal_platform_shutdown:
!halt:
    jmp !halt-

// hal_platform_panic — A = status. Show "Pxx" hex at row 0 and halt.
hal_platform_panic:
    pha
    lda #COL_WHITE
    sta zp_text_color
    lda #$50                // 'P'
    ldx #0
    ldy #0
    jsr screen_put_char_at
    pla
    pha
    lsr
    lsr
    lsr
    lsr
    ldx #1
    jsr cx16_panic_hex
    pla
    and #$0f
    ldx #2
    jsr cx16_panic_hex
    lda cx16_testbench_enabled
    beq !halt+
    jmp $fffd
!halt:
    jmp !halt-

cx16_panic_hex:
    cmp #10
    bcc !digit+
    sbc #9                  // 10..15 -> $01..$06 ('A'..'F' screen code)
    jmp !show+
!digit:
    ora #$30                // 0..9 -> $30..$39 ('0'..'9' screen code)
!show:
    ldy #0
    jmp screen_put_char_at
