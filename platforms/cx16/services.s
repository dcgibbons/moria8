#importonce
// services.s — Commander X16 hal_sound_*, hal_irq_*, and hal_platform_*
// lifecycle routines.

#import "hal/layout.s"

// ============================================================
// Sound HAL (VERA PSG Voice 0 at VRAM $1F9C0-$1F9C3)
// ============================================================
.const VERA_PSG_BASE_LO     = $c0
.const VERA_PSG_BASE_MID    = $f9
.const VERA_PSG_BASE_HI     = VERA_INC_1 | $01
.const VERA_PSG_LR_MAX      = $ff       // L+R ($C0) + max volume ($3F)
.const VERA_PSG_LR_MASK     = $c0
.const VERA_PSG_WAVE_PULSE  = $00
.const VERA_PSG_WAVE_SAW    = $40
.const VERA_PSG_WAVE_TRI    = $80
.const VERA_PSG_WAVE_NOISE  = $c0
.const CX16_KERNAL_RDTIM    = $ffde     // Returns A = 60 Hz jiffy low byte

cx16_snd_last_jiffy: .byte 0
cx16_snd_vol:        .byte 0
cx16_snd_freq_lo:    .byte 0
cx16_snd_freq_hi:    .byte 0

// hal_sound_init / hal_sound_stop — Silence all 16 VERA PSG voices and reset
// software timer state. Preserves X, Y.
hal_sound_init:
hal_sound_stop:
    phx
    php
    sei
    stz VERA_CTRL
    lda #VERA_PSG_BASE_LO
    sta VERA_ADDR_L
    lda #VERA_PSG_BASE_MID
    sta VERA_ADDR_M
    lda #VERA_PSG_BASE_HI
    sta VERA_ADDR_H
    ldx #64
!clr_psg:
    stz VERA_DATA0
    dex
    bne !clr_psg-
    plp
    stz zp_snd_timer
    stz zp_snd_phase
    stz cx16_snd_vol
    lda #SFX_NONE
    sta zp_snd_effect
    plx
    clc
    rts

// hal_sound_play — Play semantic sound effect A (0..9) on VERA PSG Voice 0.
// Paced at 60 Hz via KERNAL RDTIM ($FFDE) in hal_sound_update so durations
// and pitch/volume envelopes match 1 MHz SID ADSR feel regardless of 8 MHz CPU.
// Preserves X, Y.
hal_sound_play:
    cmp #10
    bcs !play_done+
    sta zp_snd_effect
    phx
    phy
    tax
    lda cx16_sfx_duration,x
    sta zp_snd_timer
    stz zp_snd_phase
    lda #$3f
    sta cx16_snd_vol
    lda cx16_sfx_freq_lo,x
    sta cx16_snd_freq_lo
    lda cx16_sfx_freq_hi,x
    sta cx16_snd_freq_hi
    php
    sei
    stz VERA_CTRL
    lda #VERA_PSG_BASE_LO
    sta VERA_ADDR_L
    lda #VERA_PSG_BASE_MID
    sta VERA_ADDR_M
    lda #VERA_PSG_BASE_HI
    sta VERA_ADDR_H
    lda cx16_snd_freq_lo
    sta VERA_DATA0
    lda cx16_snd_freq_hi
    sta VERA_DATA0
    lda #VERA_PSG_LR_MAX
    sta VERA_DATA0
    lda cx16_sfx_wave_pw,x
    sta VERA_DATA0
    plp
    stz CX16_ROM_BANK_REG
    jsr CX16_KERNAL_RDTIM
    sta cx16_snd_last_jiffy
    ply
    plx
!play_done:
    clc
    rts

// hal_sound_update — Advance VERA PSG pitch/volume envelope once per 60 Hz
// jiffy tick (RDTIM $FFDE) and gate off Voice 0 when zp_snd_timer expires.
// Preserves X, Y.
hal_sound_update:
    lda zp_snd_timer
    bne !upd_active+
    clc
    rts
!upd_active:
    phx
    phy
    stz CX16_ROM_BANK_REG
    jsr CX16_KERNAL_RDTIM
    cmp cx16_snd_last_jiffy
    bne !upd_tick+
    ply
    plx
    clc
    rts
!upd_tick:
    sta cx16_snd_last_jiffy

    dec zp_snd_timer
    beq !upd_silence+

    // Apply per-effect signed frequency sweep
    ldx zp_snd_effect
    cpx #10
    bcs !skip_sweep+
    lda cx16_sfx_freq_delta,x
    beq !skip_sweep+
    bpl !sweep_up+
    clc
    adc cx16_snd_freq_lo
    sta cx16_snd_freq_lo
    lda cx16_snd_freq_hi
    adc #$ff
    sta cx16_snd_freq_hi
    bra !skip_sweep+
!sweep_up:
    clc
    adc cx16_snd_freq_lo
    sta cx16_snd_freq_lo
    lda cx16_snd_freq_hi
    adc #0
    sta cx16_snd_freq_hi
!skip_sweep:

    // Gentle logarithmic decay (-2 per 60 Hz frame from 63, floor at 24)
    lda cx16_snd_vol
    sec
    sbc #2
    cmp #24
    bcs !vol_ok+
    lda #24
!vol_ok:
    sta cx16_snd_vol
    ora #VERA_PSG_LR_MASK
    tay
    php
    sei
    stz VERA_CTRL
    lda #VERA_PSG_BASE_LO
    sta VERA_ADDR_L
    lda #VERA_PSG_BASE_MID
    sta VERA_ADDR_M
    lda #VERA_PSG_BASE_HI
    sta VERA_ADDR_H
    lda cx16_snd_freq_lo
    sta VERA_DATA0
    lda cx16_snd_freq_hi
    sta VERA_DATA0
    sty VERA_DATA0
    plp
    bra !upd_restore+

!upd_silence:
    lda #SFX_NONE
    sta zp_snd_effect
    stz cx16_snd_vol
    php
    sei
    stz VERA_CTRL
    lda #(VERA_PSG_BASE_LO + 2)
    sta VERA_ADDR_L
    lda #VERA_PSG_BASE_MID
    sta VERA_ADDR_M
    lda #$01
    sta VERA_ADDR_H
    stz VERA_DATA0
    plp

!upd_restore:
    ply
    plx
!upd_done:
    clc
    rts

// Effect tables indexed by SFX_* (0..9: bump, hit, miss, pickup, death,
// levelup, spell, spell_fail, hunger_warn, hunger_faint).
// Durations are in 60 Hz frames (e.g. 8 = 133ms, 12 = 200ms, 24 = 400ms).
cx16_sfx_duration:
    .byte 8, 10, 7, 12, 24, 18, 12, 10, 12, 18
cx16_sfx_freq_lo:
    .byte $a4, $90, $20, $40, $a0, $00, $00, $ec, $48, $cd
cx16_sfx_freq_hi:
    .byte $00, $02, $05, $03, $00, $04, $03, $01, $01, $00
cx16_sfx_freq_delta:
    .byte 0, -$18, 0, $28, -$03, $28, $18, -$12, 0, 0
cx16_sfx_wave_pw:
    .byte VERA_PSG_WAVE_NOISE
    .byte VERA_PSG_WAVE_SAW
    .byte VERA_PSG_WAVE_NOISE
    .byte VERA_PSG_WAVE_TRI
    .byte VERA_PSG_WAVE_NOISE
    .byte VERA_PSG_WAVE_PULSE | $3f
    .byte VERA_PSG_WAVE_TRI
    .byte VERA_PSG_WAVE_NOISE
    .byte VERA_PSG_WAVE_PULSE | $08
    .byte VERA_PSG_WAVE_PULSE | $04

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
