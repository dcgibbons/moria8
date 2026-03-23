.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

.pc = $0828 "Main"

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../../common/sound.s"

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
    jsr sound_init
sound_stage_init:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_NONE
    jsr sound_play
sound_stage_none:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #$08
    jsr sound_play
sound_stage_invalid:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_BUMP
    jsr sound_play
sound_stage_bump:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_HIT
    jsr sound_play
sound_stage_hit:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_MISS
    jsr sound_play
sound_stage_miss:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_PICKUP
    jsr sound_play
sound_stage_pickup:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_DEATH
    jsr sound_play
sound_stage_death:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_LEVELUP
    jsr sound_play
sound_stage_levelup:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_SPELL
    jsr sound_play
sound_stage_spell:
    nop

    jsr reset_sid_window
    jsr sound_init
    lda #SFX_SPELL_FAIL
    jsr sound_play
sound_stage_spell_fail:
    brk
