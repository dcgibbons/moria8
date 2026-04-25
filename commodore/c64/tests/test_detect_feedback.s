// test_detect_feedback.s — Focused runtime tests for detect spell/prayer feedback
//
// Covers shared detect result vs no-result behavior without importing the full
// spell execute overlay into a large suite.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    ldx #3
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

#import "../../common/zeropage.s"
#import "../memory.s"

.const MAX_MONSTERS = 4
.const MONSTER_ENTRY_SIZE = 12
.const EMPTY_SLOT = $ff
.const MX_TYPE = 2
.const CF_EVIL = $04
.const HSTR_PIQ_SENSE = 0

tc_results: .fill 4, $ff

test_detect_calls:   .byte 0
test_msg_calls:      .byte 0
test_last_msg_lo:    .byte 0
test_last_msg_hi:    .byte 0
test_huff_calls:     .byte 0
test_last_huff:      .byte 0

cr_mflags:
    .byte 0
    .byte CF_EVIL
    .byte 0
    .byte 0

test_mon_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, 0

test_mon_ptr_lo:
    .fill MAX_MONSTERS, <(test_mon_table + i * MONSTER_ENTRY_SIZE)
test_mon_ptr_hi:
    .fill MAX_MONSTERS, >(test_mon_table + i * MONSTER_ENTRY_SIZE)

eff_detect_monsters:
    inc test_detect_calls
    rts

eff_detect_evil_only:
    inc test_detect_calls
    ldx #0
!edeo_loop:
    cpx #MAX_MONSTERS
    bcs !edeo_none+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edeo_next+
    tay
    lda cr_mflags,y
    and #CF_EVIL
    bne !edeo_found+
!edeo_next:
    inx
    jmp !edeo_loop-
!edeo_found:
    lda #1
    rts
!edeo_none:
    lda #0
    rts

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

msg_print:
    inc test_msg_calls
    lda zp_ptr0
    sta test_last_msg_lo
    lda zp_ptr0_hi
    sta test_last_msg_hi
    rts

monster_get_ptr:
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
    rts

#import "../../common/player_magic_detect.s"

test_clear_monsters:
    ldx #MAX_MONSTERS * MONSTER_ENTRY_SIZE - 1
    lda #0
!clear_loop:
    sta test_mon_table,x
    dex
    bpl !clear_loop-

    lda #EMPTY_SLOT
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_TYPE
    sta test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_TYPE
    sta test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_TYPE
    rts

test_start:
    // Test 1: Detect Monsters with no active monsters reports no creatures.
    jsr test_clear_monsters
    lda #0
    sta test_detect_calls
    sta test_msg_calls
    sta test_huff_calls
    jsr pmx_detect_monsters_msg
    lda test_detect_calls
    cmp #1
    bne !t1_fail+
    lda test_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_no_creatures
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_no_creatures
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: Detect Monsters with an active monster uses the shared huffman message.
!t2:
    jsr test_clear_monsters
    lda #0
    sta test_detect_calls
    sta test_msg_calls
    sta test_huff_calls
    lda #0
    sta test_mon_table + MX_TYPE
    jsr pmx_detect_monsters_msg
    lda test_detect_calls
    cmp #1
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_SENSE
    bne !t2_fail+
    lda test_msg_calls
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: Detect Evil with only non-evil monsters reports none.
!t3:
    jsr test_clear_monsters
    lda #0
    sta test_detect_calls
    sta test_msg_calls
    sta test_huff_calls
    lda #0
    sta test_mon_table + MX_TYPE
    jsr pmx_detect_evil_msg
    lda test_detect_calls
    cmp #1
    bne !t3_fail+
    lda test_msg_calls
    cmp #1
    bne !t3_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_no_evil
    bne !t3_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_no_evil
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: Detect Evil with an evil monster reports presence of evil.
!t4:
    jsr test_clear_monsters
    lda #0
    sta test_detect_calls
    sta test_msg_calls
    sta test_huff_calls
    lda #1
    sta test_mon_table + MX_TYPE
    jsr pmx_detect_evil_msg
    lda test_detect_calls
    cmp #1
    bne !t4_fail+
    lda test_msg_calls
    cmp #1
    bne !t4_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_evil_on
    bne !t4_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_evil_on
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !tests_done+
!t4_fail:
    lda #$00
    sta tc_results + 3

!tests_done:
    jmp test_finish
