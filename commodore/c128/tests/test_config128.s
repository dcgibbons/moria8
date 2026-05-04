#importonce
// test_config128.s — C128 config contract smoke test

#import "../../common/zeropage.s"

mmu_common_map_read_ptr0: rts
mmu_common_map_write_ptr0: rts
mmu_common_map_read_ptr1: rts
mmu_common_map_write_ptr1: rts
mmu_common_mark_visited_row_ptr0: rts
mmu_common_db_read_ptr0: rts
mmu_common_db_write_ptr0: rts
mmu_common_db_read_ptr1: rts
mmu_common_db_write_ptr1: rts
mmu_select_bank0: rts
mmu_select_bank1: rts

#import "../config128.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #0
    sta zp_machine_type
    sta zp_column_mode

    jsr detect_machine

    lda zp_machine_type
    cmp #MACHINE_C128
    bne test_fail

    lda zp_column_mode
    cmp #COLUMNS_80
    bne test_fail

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
