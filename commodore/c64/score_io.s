// score_io.s — High score disk I/O (main RAM)
//
// hiscore_load and hiscore_save use KERNAL I/O and must stay in main RAM.
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
    lda #hi_read_fname_len
    ldx #<hi_read_fname
    ldy #>hi_read_fname
    jsr KERNAL_SETNAM
    lda #HISCORE_FILE_NUM
    ldx #SAVE_DEVICE
    ldy #HISCORE_SEC_RD
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !hl_fail+

    ldx #HISCORE_FILE_NUM
    jsr KERNAL_CHKIN
    bcs !hl_fail_close+

    // Read header: 'M' 'H' version count
    jsr KERNAL_CHRIN
    cmp #$4d                    // 'M'
    bne !hl_fail_close+
    jsr KERNAL_CHRIN
    cmp #$48                    // 'H'
    bne !hl_fail_close+
    jsr KERNAL_CHRIN
    cmp #$01                    // Version 1
    bne !hl_fail_close+
    jsr KERNAL_CHRIN
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
    jsr KERNAL_CHRIN
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
    jsr KERNAL_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr KERNAL_CLOSE
    rts

!hl_fail_close:
    jsr KERNAL_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr KERNAL_CLOSE
!hl_fail:
    lda #0
    sta hiscore_count
    rts

// ============================================================
// hiscore_save — Scratch old file, write header + entries
// Clobbers: A, X, Y
// ============================================================
hiscore_save:
    // Scratch existing file (ignore errors)
    lda #hi_scratch_len
    ldx #<hi_scratch_cmd
    ldy #>hi_scratch_cmd
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx #SAVE_DEVICE
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !hs_scratch_done+
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
!hs_scratch_done:
    jsr KERNAL_CLRCHN

    // Open for writing
    lda #hi_write_fname_len
    ldx #<hi_write_fname
    ldy #>hi_write_fname
    jsr KERNAL_SETNAM
    lda #HISCORE_FILE_NUM
    ldx #SAVE_DEVICE
    ldy #HISCORE_SEC_WR
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !hs_fail+

    ldx #HISCORE_FILE_NUM
    jsr KERNAL_CHKOUT
    bcs !hs_fail_close+

    // Write header
    lda #$4d                    // 'M'
    jsr KERNAL_CHROUT
    lda #$48                    // 'H'
    jsr KERNAL_CHROUT
    lda #$01                    // Version
    jsr KERNAL_CHROUT
    lda hiscore_count
    jsr KERNAL_CHROUT

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
    jsr KERNAL_CHROUT
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
    jsr KERNAL_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr KERNAL_CLOSE
    rts

!hs_fail_close:
    jsr KERNAL_CLRCHN
    lda #HISCORE_FILE_NUM
    jsr KERNAL_CLOSE
!hs_fail:
    rts

// ============================================================
// High score file I/O strings (PETSCII for KERNAL)
// ============================================================
hi_read_fname:
    .byte $30, $3a              // "0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45  // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $52   // ",S,R"
.label hi_read_fname_len = * - hi_read_fname

hi_write_fname:
    .byte $40                   // "@"
    .byte $30, $3a              // "0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45  // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $57   // ",S,W"
.label hi_write_fname_len = * - hi_write_fname

hi_scratch_cmd:
    .byte $53, $30, $3a         // "S0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45  // "HALL.OF.FAME"
.label hi_scratch_len = * - hi_scratch_cmd
