#importonce
// sound.s — BBC Master 128 SN76489 4-channel sound driver via MOS OSWORD $07 (< $3000).
//
// Exports hal_sound_init, hal_sound_play, hal_sound_stop, hal_sound_update.
// Uses MOS OSWORD A=$07 (8-byte SOUND parameter block at BEEB_OS_CTRL_BASE):
//   +0..+1: channel ($0011 = Tone Channel 1 with flush, $0010 = Noise Channel 0)
//   +2..+3: amplitude ($FFF1 = -15 loudest, $0000 = silent)
//   +4..+5: pitch (0..255 for tone, 4..6 for periodic/white noise)
//   +6..+7: duration in 50 Hz ticks (20 ms units)

#import "memory.s"

// SFX_* semantic sound IDs (kept in sync with core/sound.s).
.const SFX_NONE         = $ff
.const SFX_BUMP         = $00
.const SFX_HIT          = $01
.const SFX_MISS         = $02
.const SFX_PICKUP       = $03
.const SFX_DEATH        = $04
.const SFX_LEVELUP      = $05
.const SFX_SPELL        = $06
.const SFX_SPELL_FAIL   = $07
.const SFX_HUNGER_WARN  = $08
.const SFX_HUNGER_FAINT = $09

hal_sound_init:
hal_sound_stop:
    lda #0
    sta zp_snd_timer
    sta zp_snd_phase
    lda #$ff                // SFX_NONE
    sta zp_snd_effect
    clc
    rts

hal_sound_update:
    clc
    rts

// hal_sound_play — A = SFX_* ID (0-9). Enqueues non-blocking MOS SOUND.
hal_sound_play:
    cmp #10
    bcs !done+
    tax
    lda beeb_sfx_chan_lo,x
    sta BEEB_OS_CTRL_BASE + 0
    lda #$00
    sta BEEB_OS_CTRL_BASE + 1
    lda #$f1                // amplitude -15 ($FFF1)
    sta BEEB_OS_CTRL_BASE + 2
    lda #$ff
    sta BEEB_OS_CTRL_BASE + 3
    lda beeb_sfx_pitch,x
    sta BEEB_OS_CTRL_BASE + 4
    lda #$00
    sta BEEB_OS_CTRL_BASE + 5
    lda beeb_sfx_dur,x
    sta BEEB_OS_CTRL_BASE + 6
    lda #$00
    sta BEEB_OS_CTRL_BASE + 7

    jsr EnterMos
    lda #$07
    ldx #<BEEB_OS_CTRL_BASE
    ldy #>BEEB_OS_CTRL_BASE
    jsr MOS_OSWORD
    jsr ExitMos
!done:
    clc
    rts

// 10 semantic SFX definitions (0=BUMP, 1=HIT, 2=MISS, 3=PICKUP, 4=DEATH,
// 5=LEVELUP, 6=SPELL, 7=SPELL_FAIL, 8=HUNGER_WARN, 9=HUNGER_FAINT)
beeb_sfx_chan_lo:
    .byte $11, $10, $11, $11, $11, $11, $11, $10, $11, $11
beeb_sfx_pitch:
    .byte  28,   6, 120, 148,  20, 164, 132,   5,  44,  24
beeb_sfx_dur:
    .byte   2,   2,   1,   3,   8,   5,   4,   4,   3,   5
