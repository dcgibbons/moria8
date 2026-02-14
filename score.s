// score.s — Score calculation, death screen, and high score table
//
// Phase 9.3: Death screen with killer identification, score breakdown,
// and persistent top-10 high score table stored on disk.

// Death source constants: DEATH_ALIVE/CURSED/POISON/STARVE defined in config.s

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
// Score scratch variables
// ============================================================
score_accum_0:  .byte 0       // 24-bit score accumulator (LSB)
score_accum_1:  .byte 0
score_accum_2:  .byte 0       // (MSB)
score_operand_0: .byte 0      // 24-bit operand for add/compare
score_operand_1: .byte 0
score_operand_2: .byte 0
score_new_rank: .byte 0       // Rank of new entry ($FF = didn't qualify)

// ============================================================
// High score table RAM
// ============================================================
// Entry format (23 bytes):
//  0-15  Player name (16 bytes, space-padded)
// 16-18  Score (24-bit LE)
//    19  Player level
//    20  Max dungeon depth
//    21  Race index
//    22  Class index
// High score table lives in CREATURE_BASE scratch area (only used at game over,
// never simultaneously with BFS/RLE which use the same area during gameplay).
.label hiscore_table = CREATURE_BASE
hiscore_count:  .byte 0

// ============================================================
// math_add_24 — Add score_operand to score_accum (24-bit)
// Output: score_accum += score_operand
// Clobbers: A
// ============================================================
math_add_24:
    lda score_accum_0
    clc
    adc score_operand_0
    sta score_accum_0
    lda score_accum_1
    adc score_operand_1
    sta score_accum_1
    lda score_accum_2
    adc score_operand_2
    sta score_accum_2
    rts

// ============================================================
// math_cmp_24 — Compare score_accum vs score_operand (24-bit)
// Output: carry set if accum >= operand, zero set if equal
//         (same semantics as CMP instruction)
// Clobbers: A
// ============================================================
math_cmp_24:
    lda score_accum_2
    cmp score_operand_2
    bne !mc24_done+
    lda score_accum_1
    cmp score_operand_1
    bne !mc24_done+
    lda score_accum_0
    cmp score_operand_0
!mc24_done:
    rts

// ============================================================
// score_calculate — Compute total score
// score = XP(24-bit) + gold(24-bit) + max_depth * 50
// Output: score_accum_0/1/2
// Clobbers: A, X, Y, zp_math_*, zp_temp0/1
// ============================================================
score_calculate:
    // Start with XP
    lda player_data + PL_XP_0
    sta score_accum_0
    lda player_data + PL_XP_1
    sta score_accum_1
    lda player_data + PL_XP_2
    sta score_accum_2

    // Add gold
    lda player_data + PL_GOLD_0
    sta score_operand_0
    lda player_data + PL_GOLD_1
    sta score_operand_1
    lda player_data + PL_GOLD_2
    sta score_operand_2
    jsr math_add_24

    // Add max_depth * 50
    lda player_data + PL_MAX_DLVL
    ldx #50
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda zp_math_a
    sta score_operand_0
    lda zp_math_b
    sta score_operand_1
    lda #0
    sta score_operand_2
    jsr math_add_24

    rts

// ============================================================
// screen_put_decimal_24 — Write a 24-bit value as decimal at cursor
// Input:  score_accum_0/1/2 = 24-bit value
//         zp_cursor_row, zp_cursor_col = position
// Preserves: nothing
// Uses:   sd24_work_0/1/2 (working copy), zp_temp2 (leading zero flag)
// ============================================================
sd24_work_0: .byte 0
sd24_work_1: .byte 0
sd24_work_2: .byte 0

screen_put_decimal_24:
    // Copy value to working area
    lda score_accum_0
    sta sd24_work_0
    lda score_accum_1
    sta sd24_work_1
    lda score_accum_2
    sta sd24_work_2

    lda #0
    sta zp_temp2                // Leading zero flag

    ldx #7                      // 8 digits (10M, 1M, 100K, 10K, 1K, 100, 10, 1), index 7..0
!sd24_digit_loop:
    lda #0
    sta zp_temp3                // Digit counter
!sd24_sub_loop:
    // Subtract power of 10 from working value
    lda sd24_work_0
    sec
    sbc dec24_pow10_0,x
    tay                         // Save lo result
    lda sd24_work_1
    sbc dec24_pow10_1,x
    sta zp_temp4                // Save mid result
    lda sd24_work_2
    sbc dec24_pow10_2,x
    bcc !sd24_digit_done+       // Underflow — done with this digit
    sta sd24_work_2
    lda zp_temp4
    sta sd24_work_1
    sty sd24_work_0
    inc zp_temp3
    jmp !sd24_sub_loop-
!sd24_digit_done:
    lda zp_temp3
    bne !sd24_print_digit+
    // Check if leading zero
    lda zp_temp2
    beq !sd24_next_digit+       // Still leading zeros, skip
!sd24_print_digit:
    lda #1
    sta zp_temp2                // No more leading zeros
    lda zp_temp3
    ora #$30                    // Digit → screen code
    jsr screen_put_char
!sd24_next_digit:
    dex
    bne !sd24_digit_loop-
    // Always print ones digit
    lda sd24_work_0
    ora #$30
    jmp screen_put_char

// Powers of 10 for 24-bit decimal (8 entries × 3 bytes)
// Index: 0=1, 1=10, 2=100, 3=1000, 4=10000, 5=100000, 6=1000000, 7=10000000
dec24_pow10_0:
    .byte <1, <10, <100, <1000, <10000, <100000, <1000000, <10000000
dec24_pow10_1:
    .byte >1, >10, >100, >1000, >10000, >100000, >1000000, >10000000
dec24_pow10_2:
    .byte 0, 0, 0, 0, 0, 1, 15, 152
    // $000001=1, $00000A=10, $000064=100, $0003E8=1000, $002710=10000
    // $0186A0=100000 (byte2=1), $0F4240=1000000 (byte2=15), $989680=10000000 (byte2=152)

// ============================================================
// score_death_screen — Display the full death screen
// Input: score calculated, hiscore table loaded + inserted
// Clobbers: everything
// ============================================================
score_death_screen:
    jsr screen_clear

    // Row 1: "* YOU HAVE DIED *"
    lda #1
    sta zp_cursor_row
    lda #11
    sta zp_cursor_col
    lda #COL_RED
    sta zp_text_color
    lda #<sds_died_str
    sta zp_ptr0
    lda #>sds_died_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 3: Player name
    lda #3
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    lda #<player_data
    sta zp_ptr0
    lda #>player_data
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 4: "<race> <class>  LEVEL <lvl>"
    lda #4
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    // Print race name
    ldx player_data + PL_RACE
    lda race_name_ptrs_lo,x
    sta zp_ptr0
    lda race_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #$20                    // Space
    jsr screen_put_char
    // Print class name
    ldx player_data + PL_CLASS
    lda class_name_ptrs_lo,x
    sta zp_ptr0
    lda class_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    // "  LEVEL "
    lda #<sds_level_str
    sta zp_ptr0
    lda #>sds_level_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda player_data + PL_LEVEL
    jsr screen_put_decimal

    // Row 5: "KILLED ON DUNGEON LEVEL <depth>"
    lda #5
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<sds_dungeon_str
    sta zp_ptr0
    lda #>sds_dungeon_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda player_data + PL_MAX_DLVL
    jsr screen_put_decimal

    // Row 7: "KILLED BY <source>"
    lda #7
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_ORANGE
    sta zp_text_color
    lda #<sds_killed_by_str
    sta zp_ptr0
    lda #>sds_killed_by_str
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr sds_print_death_source

    // Row 9: "EXPERIENCE:" + value
    lda #9
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<sds_xp_str
    sta zp_ptr0
    lda #>sds_xp_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #22
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_XP_0
    sta score_accum_0
    lda player_data + PL_XP_1
    sta score_accum_1
    lda player_data + PL_XP_2
    sta score_accum_2
    jsr screen_put_decimal_24

    // Row 10: "GOLD:" + value
    lda #10
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<sds_gold_str
    sta zp_ptr0
    lda #>sds_gold_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #22
    sta zp_cursor_col
    lda #COL_YELLOW
    sta zp_text_color
    lda player_data + PL_GOLD_0
    sta score_accum_0
    lda player_data + PL_GOLD_1
    sta score_accum_1
    lda player_data + PL_GOLD_2
    sta score_accum_2
    jsr screen_put_decimal_24

    // Row 11: "DEPTH BONUS:" + value
    lda #11
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<sds_depth_str
    sta zp_ptr0
    lda #>sds_depth_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #22
    sta zp_cursor_col
    lda #COL_WHITE
    sta zp_text_color
    // Compute depth bonus: max_depth * 50
    lda player_data + PL_MAX_DLVL
    ldx #50
    jsr math_multiply
    lda zp_math_a
    sta score_accum_0
    lda zp_math_b
    sta score_accum_1
    lda #0
    sta score_accum_2
    jsr screen_put_decimal_24

    // Row 12: "TOTAL SCORE:" + value
    lda #12
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<sds_total_str
    sta zp_ptr0
    lda #>sds_total_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #22
    sta zp_cursor_col
    lda #COL_GREEN
    sta zp_text_color
    // Recalculate total score for display
    jsr score_calculate
    jsr screen_put_decimal_24

    // Row 14: High score header
    lda #14
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #COL_CYAN
    sta zp_text_color
    lda #<sds_hiscore_hdr
    sta zp_ptr0
    lda #>sds_hiscore_hdr
    sta zp_ptr0_hi
    jsr screen_put_string

    // Display high score table
    jsr hiscore_display

    // Row 24: "PRESS ANY KEY"
    lda #24
    sta zp_cursor_row
    lda #13
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<sds_anykey_str
    sta zp_ptr0
    lda #>sds_anykey_str
    sta zp_ptr0_hi
    jsr screen_put_string

    rts

// ============================================================
// sds_print_death_source — Print death source at cursor
// Input: zp_death_source
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
sds_print_death_source:
    lda zp_death_source
    cmp #DEATH_POISON
    beq !sds_poison+
    cmp #DEATH_STARVE
    beq !sds_starve+
    cmp #DEATH_CURSED
    beq !sds_cursed+
    // Monster: print "A " + cr_name_lo/hi[death_source]
    cmp #0
    beq !sds_unknown+           // Should not happen ($00 = alive)
    tax
    lda #<sds_a_str
    sta zp_ptr0
    lda #>sds_a_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda cr_name_lo,x
    sta zp_ptr0
    lda cr_name_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string
    rts
!sds_poison:
    lda #<sds_src_poison
    sta zp_ptr0
    lda #>sds_src_poison
    sta zp_ptr0_hi
    jsr screen_put_string
    rts
!sds_starve:
    lda #<sds_src_starve
    sta zp_ptr0
    lda #>sds_src_starve
    sta zp_ptr0_hi
    jsr screen_put_string
    rts
!sds_cursed:
    lda #<sds_src_cursed
    sta zp_ptr0
    lda #>sds_src_cursed
    sta zp_ptr0_hi
    jsr screen_put_string
    rts
!sds_unknown:
    lda #<sds_src_unknown
    sta zp_ptr0
    lda #>sds_src_unknown
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

// ============================================================
// hiscore_insert — Insert current player into high score table
// Walks table highest-first, compares 24-bit scores,
// shifts entries down, inserts. Returns index in A.
// Input: score_accum_0/1/2 = player's score
// Output: A = index where inserted ($FF = didn't qualify)
//         score_new_rank updated
// Clobbers: everything
// ============================================================
hi_insert_idx:  .byte 0
hi_insert_off:  .byte 0       // Byte offset into table for insert point

hiscore_insert:
    // Find insertion point (walk from 0 = highest to count-1)
    lda #0
    sta hi_insert_idx

!hi_find:
    lda hi_insert_idx
    cmp hiscore_count
    bcs !hi_insert_here+        // Past end of entries → insert here

    // Compute byte offset = idx * HISCORE_ENTRY_SIZE
    lda hi_insert_idx
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply           // zp_math_a = offset lo
    lda zp_math_a
    sta hi_insert_off

    // Compare: player score vs table[idx] score (bytes 16-18)
    tax
    lda hiscore_table + 18,x    // Table entry score byte 2 (MSB)
    sta score_operand_2
    lda hiscore_table + 17,x
    sta score_operand_1
    lda hiscore_table + 16,x
    sta score_operand_0
    jsr math_cmp_24             // accum vs operand
    bcc !hi_next+               // accum < operand → keep looking
    // accum >= operand → insert here
    jmp !hi_insert_here+

!hi_next:
    inc hi_insert_idx
    jmp !hi_find-

!hi_insert_here:
    // Check if table is already full and we're past the end
    lda hi_insert_idx
    cmp #HISCORE_MAX_ENTRIES
    bcc !hi_can_insert+
    // Didn't qualify
    lda #$ff
    sta score_new_rank
    rts

!hi_can_insert:
    // Shift entries down from count-1 to insert_idx
    // If count < MAX, increment count first
    lda hiscore_count
    cmp #HISCORE_MAX_ENTRIES
    bcs !hi_no_grow+
    inc hiscore_count
!hi_no_grow:

    // Shift: start from count-1, move to count-2, ... down to insert_idx+1
    // We copy entry[n-1] → entry[n] working backwards
    lda hiscore_count
    sec
    sbc #1                      // Last valid index
    sta zp_temp0                // Destination index

!hi_shift:
    lda zp_temp0
    cmp hi_insert_idx
    beq !hi_shift_done+         // Reached insert point
    // Source = dest - 1
    lda zp_temp0
    sec
    sbc #1
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply
    // zp_math_a = source offset
    lda zp_math_a
    sta zp_temp1                // Source offset

    lda zp_temp0
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply
    // zp_math_a = dest offset
    lda zp_math_a
    sta zp_temp2                // Dest offset

    // Copy HISCORE_ENTRY_SIZE bytes
    ldy #0
!hi_copy:
    ldx zp_temp1
    lda hiscore_table,x
    ldx zp_temp2
    sta hiscore_table,x
    inc zp_temp1
    inc zp_temp2
    iny
    cpy #HISCORE_ENTRY_SIZE
    bne !hi_copy-

    dec zp_temp0
    jmp !hi_shift-

!hi_shift_done:
    // Write new entry at insert_idx
    lda hi_insert_idx
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply
    lda zp_math_a
    sta hi_insert_off           // Byte offset

    // Copy player name (16 bytes)
    ldx hi_insert_off
    ldy #0
!hi_name:
    lda player_data + PL_NAME,y
    beq !hi_pad_name+           // Null terminator → pad with spaces
    sta hiscore_table,x
    inx
    iny
    cpy #16
    bne !hi_name-
    jmp !hi_name_done+

!hi_pad_name:
    lda #$20                    // Space (screen code)
    sta hiscore_table,x
    inx
    iny
    cpy #16
    bne !hi_pad_name-

!hi_name_done:
    // Score (3 bytes)
    ldx hi_insert_off
    lda score_accum_0
    sta hiscore_table + 16,x
    lda score_accum_1
    sta hiscore_table + 17,x
    lda score_accum_2
    sta hiscore_table + 18,x

    // Level
    lda player_data + PL_LEVEL
    sta hiscore_table + 19,x

    // Max depth
    lda player_data + PL_MAX_DLVL
    sta hiscore_table + 20,x

    // Race
    lda player_data + PL_RACE
    sta hiscore_table + 21,x

    // Class
    lda player_data + PL_CLASS
    sta hiscore_table + 22,x

    lda hi_insert_idx
    sta score_new_rank
    rts

// ============================================================
// hiscore_display — Draw high score table at rows 15-24
// Highlights the new entry (score_new_rank)
// Clobbers: everything
// ============================================================
hd_row:     .byte 0
hd_idx:     .byte 0
hd_offset:  .byte 0

hiscore_display:
    lda #0
    sta hd_idx
    lda #15
    sta hd_row

!hd_loop:
    lda hd_idx
    cmp hiscore_count
    bcc !hd_not_done+
    jmp !hd_done+
!hd_not_done:
    cmp #HISCORE_MAX_ENTRIES
    bcc !hd_not_max+
    jmp !hd_done+
!hd_not_max:

    // Check if this row would exceed screen
    lda hd_row
    cmp #24
    bcc !hd_not_screen+
    jmp !hd_done+
!hd_not_screen:

    // Compute byte offset
    lda hd_idx
    ldx #HISCORE_ENTRY_SIZE
    jsr math_multiply
    lda zp_math_a
    sta hd_offset

    // Set color: yellow for new entry, light grey for others
    lda hd_idx
    cmp score_new_rank
    bne !hd_not_new+
    lda #COL_YELLOW
    sta zp_text_color
    jmp !hd_print+
!hd_not_new:
    lda #COL_LGREY
    sta zp_text_color

!hd_print:
    // Position cursor
    lda hd_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Print rank: " N. " (1-based, right-justified in 2 chars)
    lda hd_idx
    clc
    adc #1
    jsr screen_put_decimal_rj2
    lda #$2e                    // '.'
    jsr screen_put_char
    lda #$20                    // ' '
    jsr screen_put_char

    // Print score (24-bit)
    ldx hd_offset
    lda hiscore_table + 16,x
    sta score_accum_0
    lda hiscore_table + 17,x
    sta score_accum_1
    lda hiscore_table + 18,x
    sta score_accum_2
    jsr screen_put_decimal_24
    lda #$20
    jsr screen_put_char

    // Print name (up to 12 chars to fit)
    ldx hd_offset
    ldy #0
!hd_name:
    lda hiscore_table,x
    cmp #$20
    beq !hd_name_end+           // Stop at first space/pad (truncate)
    jsr screen_put_char
    inx
    iny
    cpy #12
    bne !hd_name-
!hd_name_end:
    // Pad to column 30
!hd_pad:
    lda zp_cursor_col
    cmp #30
    bcs !hd_pad_done+
    lda #$20
    jsr screen_put_char
    jmp !hd_pad-
!hd_pad_done:

    // Print " LV" + level
    lda #<sds_lv_str
    sta zp_ptr0
    lda #>sds_lv_str
    sta zp_ptr0_hi
    jsr screen_put_string
    ldx hd_offset
    lda hiscore_table + 19,x
    jsr screen_put_decimal_rj2

    inc hd_row
    inc hd_idx
    jmp !hd_loop-

!hd_done:
    rts

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
    .byte $4d, $4f, $52, $49, $41, $2e, $48, $49  // "MORIA.HI"
    .byte $2c, $53, $2c, $52   // ",S,R"
.label hi_read_fname_len = * - hi_read_fname

hi_write_fname:
    .byte $40                   // "@"
    .byte $30, $3a              // "0:"
    .byte $4d, $4f, $52, $49, $41, $2e, $48, $49  // "MORIA.HI"
    .byte $2c, $53, $2c, $57   // ",S,W"
.label hi_write_fname_len = * - hi_write_fname

hi_scratch_cmd:
    .byte $53, $30, $3a         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $2e, $48, $49  // "MORIA.HI"
.label hi_scratch_len = * - hi_scratch_cmd

// ============================================================
// Screen-code strings for death screen
// ============================================================
sds_died_str:      .text "* YOU HAVE DIED *" ; .byte 0
sds_level_str:     .text "  LEVEL " ; .byte 0
sds_dungeon_str:   .text "KILLED ON DUNGEON LEVEL " ; .byte 0
sds_killed_by_str: .text "KILLED BY " ; .byte 0
sds_a_str:         .text "A " ; .byte 0
sds_src_poison:    .text "POISON" ; .byte 0
sds_src_starve:    .text "STARVATION" ; .byte 0
sds_src_cursed:    .text "A CURSED ITEM" ; .byte 0
sds_src_unknown:   .text "UNKNOWN CAUSES" ; .byte 0
sds_xp_str:        .text "EXPERIENCE:" ; .byte 0
sds_gold_str:      .text "GOLD:" ; .byte 0
sds_depth_str:     .text "DEPTH BONUS:" ; .byte 0
sds_total_str:     .text "TOTAL SCORE:" ; .byte 0
sds_hiscore_hdr:   .text "-------- HIGH SCORES --------" ; .byte 0
sds_lv_str:        .text "LV" ; .byte 0
sds_anykey_str:    .text "PRESS ANY KEY" ; .byte 0
