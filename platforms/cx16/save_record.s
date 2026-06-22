#importonce
// save_record.s - CX16 native save/load record.
//
// This is a platform HAL record writer, not a gameplay shortcut: it persists
// the live shared gameplay blocks currently owned by the CX16 vertical slice.

.const CX16_SAVE_LFN = 2
.const CX16_SAVE_DEVICE = 8
.const CX16_SAVE_SECONDARY = 2
.const CX16_SAVE_BLOCK_DESC_SIZE = 4
.const CX16_SAVE_ZP_START = zp_player_x
.const CX16_SAVE_ZP_SIZE = zp_death_source - zp_player_x + 1
.const CX16_SAVE_INV_SIZE = TOTAL_INV_SLOTS * 8
.const CX16_SAVE_FLOOR_SIZE = 256
.const CX16_SAVE_MONSTER_SIZE = MAX_MONSTERS * MONSTER_ENTRY_SIZE
.const CX16_SAVE_DUNGEON_META_SIZE = level_entry_dir - room_count + 1
.const CX16_SAVE_TRAP_SIZE = trap_type + MAX_TRAPS - trap_count
.const CX16_SAVE_BLOCK_COUNT = 11

cx16_overlay_save_entry:
    cmp #CX16_SAVE_CMD_MESSAGE
    bne !not_message+
    jmp cx16_save_print_message
!not_message:
    cmp #CX16_SAVE_CMD_LOAD
    beq cx16_save_load_record
    cmp #CX16_SAVE_CMD_SAVE
    beq cx16_save_write_record
    sec
    rts

cx16_save_write_record:
    lda #cx16_save_write_name_len
    ldx #<cx16_save_write_name
    ldy #>cx16_save_write_name
    jsr KERNAL_SETNAM
    lda #CX16_SAVE_LFN
    ldx #CX16_SAVE_DEVICE
    ldy #CX16_SAVE_SECONDARY
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !fail_open+
    ldx #CX16_SAVE_LFN
    jsr KERNAL_CHKOUT
    bcs !fail_open+
    jsr KERNAL_READST
    and #$03
    bne !fail_open+
    lda #<cx16_save_write_block_table
    sta zp_ptr1
    lda #>cx16_save_write_block_table
    sta zp_ptr1_hi
    lda #CX16_SAVE_BLOCK_COUNT
    sta cx16_save_block_count
!block:
    jsr cx16_save_load_block_desc
!byte:
    jsr cx16_save_count_done
    beq !next_block+
    ldy #0
    lda (zp_ptr0),y
    jsr KERNAL_CHROUT
    jsr KERNAL_READST
    and #$03
    bne !fail+
    jsr cx16_save_advance_ptr
    jmp !byte-
!next_block:
    jsr cx16_save_advance_table
    dec cx16_save_block_count
    bne !block-
    jsr cx16_save_close
    clc
    rts
!fail_open:
!fail:
    jsr cx16_save_close
    sec
    rts

cx16_save_load_record:
    lda #cx16_save_read_name_len
    ldx #<cx16_save_read_name
    ldy #>cx16_save_read_name
    jsr KERNAL_SETNAM
    lda #CX16_SAVE_LFN
    ldx #CX16_SAVE_DEVICE
    ldy #CX16_SAVE_SECONDARY
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !fail_open+
    ldx #CX16_SAVE_LFN
    jsr KERNAL_CHKIN
    bcs !fail_open+
    jsr KERNAL_READST
    and #$bf
    bne !fail_open+
    lda #<cx16_save_load_block_table
    sta zp_ptr1
    lda #>cx16_save_load_block_table
    sta zp_ptr1_hi
    lda #CX16_SAVE_BLOCK_COUNT
    sta cx16_save_block_count
!block:
    jsr cx16_save_load_block_desc
!byte:
    jsr cx16_save_count_done
    beq !next_block+
    jsr KERNAL_CHRIN
    pha
    jsr KERNAL_READST
    and #$bf
    bne !fail_read+
    pla
    ldy #0
    sta (zp_ptr0),y
    jsr cx16_save_advance_ptr
    jmp !byte-
!fail_read:
    pla
    jmp !fail+
!next_block:
    jsr cx16_save_advance_table
    dec cx16_save_block_count
    bne !block-
    jsr cx16_save_close
    jsr cx16_save_validate_magic
    bcs !bad_magic+
    clc
    rts
!bad_magic:
    sec
    rts
!fail_open:
!fail:
    jsr cx16_save_close
    sec
    rts

cx16_save_close:
    jsr KERNAL_CLRCHN
    lda #CX16_SAVE_LFN
    jmp KERNAL_CLOSE

cx16_save_load_block_desc:
    ldy #0
    lda (zp_ptr1),y
    sta zp_ptr0
    iny
    lda (zp_ptr1),y
    sta zp_ptr0_hi
    iny
    lda (zp_ptr1),y
    sta cx16_save_count_lo
    iny
    lda (zp_ptr1),y
    sta cx16_save_count_hi
    rts

cx16_save_advance_table:
    clc
    lda zp_ptr1
    adc #CX16_SAVE_BLOCK_DESC_SIZE
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #0
    sta zp_ptr1_hi
    rts

cx16_save_count_done:
    lda cx16_save_count_lo
    ora cx16_save_count_hi
    rts

cx16_save_advance_ptr:
    inc zp_ptr0
    bne !ptr_ok+
    inc zp_ptr0_hi
!ptr_ok:
    lda cx16_save_count_lo
    bne !dec_lo+
    dec cx16_save_count_hi
!dec_lo:
    dec cx16_save_count_lo
    rts

cx16_save_validate_magic:
    ldx #0
!loop:
    lda cx16_save_magic_buf,x
    cmp cx16_save_magic,x
    bne !bad+
    inx
    cpx #CX16_SAVE_MAGIC_SIZE
    bne !loop-
    clc
    rts
!bad:
    sec
    rts

cx16_save_print_message:
    cpx #CX16_SAVE_MSG_SAVE_OK
    bne !not_save_ok+
    lda #<cx16_save_ok_text
    sta zp_ptr0
    lda #>cx16_save_ok_text
    sta zp_ptr0_hi
    jmp cx16_save_print_system_message
!not_save_ok:
    cpx #CX16_SAVE_MSG_SAVE_FAILED
    bne !not_save_failed+
    lda #<cx16_save_failed_text
    sta zp_ptr0
    lda #>cx16_save_failed_text
    sta zp_ptr0_hi
    jmp cx16_save_print_system_message
!not_save_failed:
    cpx #CX16_SAVE_MSG_LOAD_OK
    bne !not_load_ok+
    lda #<cx16_load_ok_text
    sta zp_ptr0
    lda #>cx16_load_ok_text
    sta zp_ptr0_hi
    jmp cx16_save_print_system_message
!not_load_ok:
    cpx #CX16_SAVE_MSG_LOAD_FAILED
    bne !done+
    lda #<cx16_load_failed_text
    sta zp_ptr0
    lda #>cx16_load_failed_text
    sta zp_ptr0_hi
    jmp cx16_save_print_system_message
!done:
    rts

cx16_save_print_system_message:
    jsr msg_clear
    jsr msg_print
    rts

.macro Cx16SaveBlock(addr, size) {
    .byte <addr, >addr, <size, >size
}

cx16_save_write_block_table:
    :Cx16SaveBlock(cx16_save_magic, CX16_SAVE_MAGIC_SIZE)
    :Cx16SaveBlock(cx16_runtime_state_start, cx16_runtime_state_end - cx16_runtime_state_start)
    :Cx16SaveBlock(player_data, PL_STRUCT_SIZE)
    :Cx16SaveBlock(CX16_SAVE_ZP_START, CX16_SAVE_ZP_SIZE)
    :Cx16SaveBlock(inv_item_id, CX16_SAVE_INV_SIZE)
    :Cx16SaveBlock(FLOOR_ITEM_BASE, CX16_SAVE_FLOOR_SIZE)
    :Cx16SaveBlock(monster_table, CX16_SAVE_MONSTER_SIZE)
    :Cx16SaveBlock(room_count, CX16_SAVE_DUNGEON_META_SIZE)
    :Cx16SaveBlock(trap_count, CX16_SAVE_TRAP_SIZE)
    :Cx16SaveBlock(eff_detect_timer, 1)
    :Cx16SaveBlock(MAP_BASE, MAP_SIZE)
cx16_save_write_block_table_end:

cx16_save_load_block_table:
    :Cx16SaveBlock(cx16_save_magic_buf, CX16_SAVE_MAGIC_SIZE)
    :Cx16SaveBlock(cx16_runtime_state_start, cx16_runtime_state_end - cx16_runtime_state_start)
    :Cx16SaveBlock(player_data, PL_STRUCT_SIZE)
    :Cx16SaveBlock(CX16_SAVE_ZP_START, CX16_SAVE_ZP_SIZE)
    :Cx16SaveBlock(inv_item_id, CX16_SAVE_INV_SIZE)
    :Cx16SaveBlock(FLOOR_ITEM_BASE, CX16_SAVE_FLOOR_SIZE)
    :Cx16SaveBlock(monster_table, CX16_SAVE_MONSTER_SIZE)
    :Cx16SaveBlock(room_count, CX16_SAVE_DUNGEON_META_SIZE)
    :Cx16SaveBlock(trap_count, CX16_SAVE_TRAP_SIZE)
    :Cx16SaveBlock(eff_detect_timer, 1)
    :Cx16SaveBlock(MAP_BASE, MAP_SIZE)
cx16_save_load_block_table_end:
.assert "CX16 save write descriptors are 4 bytes", CX16_SAVE_BLOCK_COUNT * CX16_SAVE_BLOCK_DESC_SIZE, cx16_save_write_block_table_end - cx16_save_write_block_table
.assert "CX16 save load descriptor count matches write", cx16_save_load_block_table_end - cx16_save_load_block_table, cx16_save_write_block_table_end - cx16_save_write_block_table

cx16_save_magic:
    .byte $4d, $38, $43, $58, $31, $36, $30, $31 // "M8CX1601"
.label CX16_SAVE_MAGIC_SIZE = * - cx16_save_magic
cx16_save_magic_buf:
    .fill CX16_SAVE_MAGIC_SIZE, 0

cx16_save_write_name:
    .byte $40, $30, $3a, $54, $48, $45, $2e, $47, $41, $4d, $45, $2c, $53, $2c, $57 // "@0:THE.GAME,S,W"
.label cx16_save_write_name_len = * - cx16_save_write_name

cx16_save_read_name:
    .byte $30, $3a, $54, $48, $45, $2e, $47, $41, $4d, $45, $2c, $53, $2c, $52 // "0:THE.GAME,S,R"
.label cx16_save_read_name_len = * - cx16_save_read_name

cx16_save_ok_text:
    :ScreenText("Game saved.")
    .byte 0

cx16_save_failed_text:
    :ScreenText("Save failed.")
    .byte 0

cx16_load_ok_text:
    :ScreenText("Game loaded.")
    .byte 0

cx16_load_failed_text:
    :ScreenText("Load failed.")
    .byte 0

cx16_save_count_lo: .byte 0
cx16_save_count_hi: .byte 0
cx16_save_block_count: .byte 0
