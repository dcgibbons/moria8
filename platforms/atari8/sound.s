#importonce
// sound.s — Atari 8-bit 4-channel POKEY sound effects engine.
//
// Exports HAL sound services (hal_sound_init, hal_sound_play, hal_sound_stop,
// hal_sound_update) using POKEY Channels 1 & 2 ($D200-$D203).

#import "memory.s"

// ============================================================
// Effect ID Constants (Shared Across All Platforms)
// ============================================================
.const SFX_NONE       = 0
.const SFX_BUMP       = 1
.const SFX_HIT        = 2
.const SFX_MISS       = 3
.const SFX_PICKUP     = 4
.const SFX_DEATH      = 5
.const SFX_LEVELUP    = 6
.const SFX_SPELL      = 7
.const SFX_SPELL_FAIL = 8
.const SFX_HUNGER       = 9
.const SFX_FAINT        = 10
.const SFX_HUNGER_WARN  = 9
.const SFX_HUNGER_FAINT = 10
.const SFX_COUNT        = 10

.label hal_sound_init   = sound_init
.label hal_sound_play   = sound_play
.label hal_sound_stop   = sound_stop
.label hal_sound_update = sound_update

// ============================================================
// State
// ============================================================
sfx_timer:     .byte 0
sfx_freq1:     .byte 0
sfx_ctrl1:     .byte 0
sfx_delta1:    .byte 0
sfx_freq2:     .byte 0
sfx_ctrl2:     .byte 0
sfx_delta2:    .byte 0

// ============================================================
// Subroutines
// ============================================================

sound_init:
    lda #0
    sta AUDCTL
    sta sfx_timer
    jmp sound_stop

sound_stop:
    lda #0
    sta sfx_timer
    sta AUDC1
    sta AUDC2
    sta AUDC3
    sta AUDC4
    rts

// sound_play — Trigger sound effect A (1..SFX_COUNT)
// Preserves: X, Y
sound_play:
    beq !done+
    cmp #SFX_COUNT + 1
    bcs !done+
    stx sfx_save_x
    tax
    dex
    lda sfx_init_freq1,x
    sta sfx_freq1
    sta AUDF1
    lda sfx_init_ctrl1,x
    sta sfx_ctrl1
    sta AUDC1
    lda sfx_init_delta1,x
    sta sfx_delta1
    lda sfx_init_freq2,x
    sta sfx_freq2
    sta AUDF2
    lda sfx_init_ctrl2,x
    sta sfx_ctrl2
    sta AUDC2
    lda sfx_init_delta2,x
    sta sfx_delta2
    lda sfx_init_dur,x
    sta sfx_timer
    ldx sfx_save_x
!done:
    rts

sfx_save_x: .byte 0

// sound_update — Advance active POKEY envelope at 60/50 Hz from VBI
// Clobbers: A
sound_update:
    lda sfx_timer
    beq !idle+
    dec sfx_timer
    beq sound_stop
    lda sfx_freq1
    clc
    adc sfx_delta1
    sta sfx_freq1
    sta AUDF1
    lda sfx_freq2
    clc
    adc sfx_delta2
    sta sfx_freq2
    sta AUDF2
!idle:
    rts

// ============================================================
// POKEY Effect Parameter Tables (10 Effects)
// ============================================================
// POKEY AUDCn: bits 7..5 = distortion ($A0 = pure square, $80 = white noise,
// $C0 = gritty bass), bits 3..0 = volume (0..15).
//Order: BUMP, HIT,  MISS, PICK, DTH,  LVL,  SPL,  SFL,  HNG,  FNT
sfx_init_dur:
    .byte 4,   6,    5,    8,    24,   16,   12,   10,   8,    14
sfx_init_freq1:
    .byte 180, 90,   140,  70,   120,  96,   60,   130,  150,  110
sfx_init_ctrl1:
    .byte $a6, $88,  $84,  $a8,  $c8,  $a8,  $a7,  $c6,  $a5,  $a6
sfx_init_delta1:
    .byte 8,   10,   12,   $fc,  4,    $fd,  $fe,  6,    4,    5
sfx_init_freq2:
    .byte 0,   130,  0,    50,   180,  72,   90,   190,  0,    160
sfx_init_ctrl2:
    .byte $00, $a5,  $00,  $a6,  $a6,  $a6,  $a5,  $a4,  $00,  $a4
sfx_init_delta2:
    .byte 0,   6,    0,    $fd,  3,    $fe,  2,    4,    0,    4
