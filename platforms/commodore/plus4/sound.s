// sound.s — Plus/4 TED sound effect approximations

.const TED_VOL     = $08
.const TED_SND1_ON = $10
.const TED_SND2_ON = $20
.const TED_NOISE2  = $40

.const SFX_NONE        = $ff
.const SFX_BUMP        = $00
.const SFX_HIT         = $01
.const SFX_MISS        = $02
.const SFX_PICKUP      = $03
.const SFX_DEATH       = $04
.const SFX_LEVELUP     = $05
.const SFX_SPELL       = $06
.const SFX_SPELL_FAIL  = $07
.const SFX_HUNGER_WARN = $08
.const SFX_HUNGER_FAINT = $09

sound_init:
    lda #0
    sta TED_SOUND_CTRL
    sta TED_SND1_LO
    sta TED_SND2_LO
    sta TED_SND2_HI
    lda TED_BMP_SOUND
    and #$fc
    sta TED_BMP_SOUND
    jsr plus4_display_resync
    lda #SFX_NONE
    sta zp_snd_effect
    rts
.label hal_sound_init = sound_init
.label hal_sound_stop = sound_init

// No sound effects yet: playing one only silences TED, as sound_init does.
.label sound_play = sound_init
.label hal_sound_play = sound_play

hal_sound_update:
    clc
    rts

