#importonce
// score_io.s — High score disk I/O (main RAM)
//
// hiscore_load and hiscore_save use storage HAL I/O and must stay in main RAM.
// Score calculation and death screen display live in the death overlay
// at $E000 (score.s).

// ============================================================
// High score file constants
// ============================================================
.const HISCORE_FILE_NUM = 4
.const HISCORE_SEC_RD   = 7
.const HISCORE_SEC_WR   = 8
.const HISCORE_ENTRY_SIZE = 23
.const HISCORE_MAX_ENTRIES = 10
.const HISCORE_HEADER_SIZE = 4
.const SCORE_SETNAM = hal_storage_setnam
.const SCORE_SETLFS = hal_storage_setlfs
.const SCORE_OPEN   = hal_storage_open
.const SCORE_CLOSE  = hal_storage_close
.const SCORE_CHKIN  = hal_storage_chkin
.const SCORE_CHKOUT = hal_storage_chkout
.const SCORE_CHRIN  = hal_storage_chrin
.const SCORE_CHROUT = hal_storage_chrout
.const SCORE_CLRCHN = hal_storage_clrchn

// ============================================================
// Shared state (must be readable from main RAM with KERNAL banked in)
// ============================================================
.label hiscore_table = CREATURE_BASE
hiscore_count:  .byte 0

// ============================================================
// hiscore_load — Load high score table from disk
// On failure/missing file → count = 0
// Clobbers: A, X, Y
// ============================================================
hiscore_load:
    jsr disk_require_save_media
    bcc !hl_ready+
    lda #0
    sta hiscore_count
    rts
!hl_ready:
    // Clear table (230 bytes; can't use bpl since 230 > 127)
    lda #0
    sta hiscore_count
    tax
!hl_clear:
    sta hiscore_table,x
    inx
    cpx #HISCORE_MAX_ENTRIES * HISCORE_ENTRY_SIZE
    bne !hl_clear-

    // Open file for reading
    lda #hal_storage_score_read_name_len
    ldx #<hal_storage_score_read_name
    ldy #>hal_storage_score_read_name
    jsr SCORE_SETNAM
    lda #HISCORE_FILE_NUM
    ldx save_device
    ldy #HISCORE_SEC_RD
    jsr SCORE_SETLFS
    jsr SCORE_OPEN
    bcs !hl_fail+

    ldx #HISCORE_FILE_NUM
    jsr SCORE_CHKIN
    bcs !hl_fail_close+

    // Read header: 'M' 'H' version count
    jsr SCORE_CHRIN
    cmp #$4d                    // 'M'
    bne !hl_fail_close+
    jsr SCORE_CHRIN
    cmp #$48                    // 'H'
    bne !hl_fail_close+
    jsr SCORE_CHRIN
    cmp #$01                    // Version 1
    bne !hl_fail_close+
    jsr SCORE_CHRIN
    cmp #HISCORE_MAX_ENTRIES + 1
    bcs !hl_fail_close+         // Invalid count
    sta hiscore_count

    // Read entries
    lda #<hiscore_table
    sta zp_ptr0
    lda #>hiscore_table
    sta zp_ptr0_hi

    // Compute total bytes: count * HISCORE_ENTRY_SIZE
    lda hiscore_count
    beq !hl_close_ok+           // No entries to read
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply           // zp_math_a = total bytes lo
    lda zp_math_a
    sta save_count_lo
    lda zp_math_b
    sta save_count_hi

    // Read block (reuse save.s loader — just read bytes into ptr0)
    ldy #0
!hl_read:
    lda save_count_lo
    ora save_count_hi
    beq !hl_close_ok+
    jsr SCORE_CHRIN
    sta (zp_ptr0),y
    iny
    bne !hl_no_page+
    inc zp_ptr0_hi
!hl_no_page:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !hl_read-
    dec save_count_hi
    jmp !hl_read-

!hl_close_ok:
    jsr SCORE_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr SCORE_CLOSE
    rts

!hl_fail_close:
    jsr SCORE_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr SCORE_CLOSE
!hl_fail:
    lda #0
    sta hiscore_count
    rts

// ============================================================
// hiscore_save — Scratch old file, write header + entries
// Clobbers: A, X, Y
// ============================================================
hiscore_save:
    jsr disk_require_save_media
    bcc !hs_ready+
    rts
!hs_ready:
    // Scratch existing file (ignore errors)
    lda #hal_storage_score_scratch_name_len
    ldx #<hal_storage_score_scratch_name
    ldy #>hal_storage_score_scratch_name
    jsr SCORE_SETNAM
    lda #hal_storage_cmd_channel
    ldx save_device
    ldy #hal_storage_cmd_channel
    jsr SCORE_SETLFS
    jsr SCORE_OPEN
    bcs !hs_scratch_done+
    lda #hal_storage_cmd_channel
    jsr SCORE_CLOSE
!hs_scratch_done:
    jsr SCORE_CLRCHN

    // Open for writing
    lda #hal_storage_score_write_name_len
    ldx #<hal_storage_score_write_name
    ldy #>hal_storage_score_write_name
    jsr SCORE_SETNAM
    lda #HISCORE_FILE_NUM
    ldx save_device
    ldy #HISCORE_SEC_WR
    jsr SCORE_SETLFS
    jsr SCORE_OPEN
    bcs !hs_fail+

    ldx #HISCORE_FILE_NUM
    jsr SCORE_CHKOUT
    bcs !hs_fail_close+

    // Write header
    lda #$4d                    // 'M'
    jsr SCORE_CHROUT
    lda #$48                    // 'H'
    jsr SCORE_CHROUT
    lda #$01                    // Version
    jsr SCORE_CHROUT
    lda hiscore_count
    jsr SCORE_CHROUT

    // Write entries
    lda hiscore_count
    beq !hs_close_ok+
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply
    lda zp_math_a
    sta save_count_lo
    lda zp_math_b
    sta save_count_hi

    lda #<hiscore_table
    sta zp_ptr0
    lda #>hiscore_table
    sta zp_ptr0_hi

    ldy #0
!hs_write:
    lda save_count_lo
    ora save_count_hi
    beq !hs_close_ok+
    lda (zp_ptr0),y
    jsr SCORE_CHROUT
    iny
    bne !hs_no_page+
    inc zp_ptr0_hi
!hs_no_page:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !hs_write-
    dec save_count_hi
    jmp !hs_write-

!hs_close_ok:
    jsr SCORE_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr SCORE_CLOSE
    rts

!hs_fail_close:
    jsr SCORE_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr SCORE_CLOSE
!hs_fail:
    rts
