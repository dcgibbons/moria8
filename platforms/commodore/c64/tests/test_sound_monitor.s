.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

.pc = $0828 "Main"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../../../../core/sound.s"

reset_sid_window:
    lda #0
    sta SID_V3_FREQ_LO
    sta SID_V3_FREQ_HI
    sta SID_V3_PW_LO
    sta SID_V3_PW_HI
    sta SID_V3_CTRL
    sta SID_V3_AD
    sta SID_V3_SR
    sta SID_FILTER_LO
    sta SID_FILTER_HI
    sta SID_FILTER_CTRL
    sta SID_VOLUME
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    jsr reset_sid_window
    jsr hal_sound_init
sound_stage_init:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_NONE
    jsr hal_sound_play
sound_stage_none:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #$0a
    jsr hal_sound_play
sound_stage_invalid:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_BUMP
    jsr hal_sound_play
sound_stage_bump:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_HIT
    jsr hal_sound_play
sound_stage_hit:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_MISS
    jsr hal_sound_play
sound_stage_miss:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_PICKUP
    jsr hal_sound_play
sound_stage_pickup:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_DEATH
    jsr hal_sound_play
sound_stage_death:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_LEVELUP
    jsr hal_sound_play
sound_stage_levelup:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_SPELL
    jsr hal_sound_play
sound_stage_spell:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_SPELL_FAIL
    jsr hal_sound_play
sound_stage_spell_fail:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_HUNGER_WARN
    jsr hal_sound_play
sound_stage_hunger_warn:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_HUNGER_FAINT
    jsr hal_sound_play
sound_stage_hunger_faint:
    nop

    jsr reset_sid_window
    jsr hal_sound_init
    lda #SFX_BUMP
    jsr hal_sound_play
    lda #1
    sta zp_snd_timer
    sta zp_snd_phase
    jsr hal_sound_update
sound_stage_update_gateoff:
    brk
