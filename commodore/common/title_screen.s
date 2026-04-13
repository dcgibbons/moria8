#importonce
// title_screen.s — Title screen loader and renderer
//
// Loads title art from disk into MAP_BASE,
// renders to screen RAM, then returns. MAP_BASE region is naturally
// recycled when dungeon_generate is called.
//
// Fallback: if KERNAL LOAD fails (no disk, file not found),
// displays a simple text title (original behavior).

.const TITLE_FALLBACK_COL = (SCREEN_COLS - 10) / 2
#if C128
.const TITLE_ART_COL_OFFSET = (SCREEN_COLS - 40) / 2
#endif
.const TITLE_FILENAME_LEN = title_filename_end - title_filename

// ============================================================
// title_load_and_draw — Load and render the title screen
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_cursor_row/col, zp_text_color
// ============================================================
title_load_and_draw:
#if C128
    jmp c128_title_load_and_draw_cached
#else
    // SETNAM: platform-specific title asset filename
    lda #TITLE_FILENAME_LEN
    ldx #<title_filename
    ldy #>title_filename
    jsr KERNAL_SETNAM

    // SETLFS: logical file 2, device 8.
    // C64 title PRG is linked for MAP_BASE already, so use the file header.
    // C128 MAP_BASE is Bank 1 $4000, so force caller-supplied X/Y destination.
    lda #2
    ldx #SAVE_DEVICE
#if C128
    ldy #1
#else
    ldy #0
#endif
    jsr KERNAL_SETLFS

    // LOAD: 0 = load, X/Y = destination (MAP_BASE)
    lda #0
    ldx #<MAP_BASE
    ldy #>MAP_BASE
#if C128
    jsr kernal_load         // Platform LOAD (C128: safe IRQ swap)
#else
    jsr kernal_load_safe
#endif

    php                     // Save carry (LOAD success/failure)
    sei
    lda #2
#if C128
    jsr w_close             // C128: force ROM mapping around CLOSE
#else
    jsr $FFC3               // KERNAL CLOSE file 2 — LOAD doesn't remove from file table
#endif

#if C128
    // Restore default LOAD destination to Bank 0 for subsequent file I/O.
    lda #0
    ldx #0
    jsr safe_setbnk         // SETBNK (handles Enter/Exit internally)
#endif
    plp                     // Restore carry from LOAD
    bcs title_fallback_render    // Carry set = error

    // Clear KERNAL status byte — LOAD leaves EOI (bit 6) set from the last file byte.
    // Without this, READST in any subsequent file read returns stale status → false errors.
    lda #0
    sta zp_kernal_status

    // Clear screen after KERNAL LOAD (removes "SEARCHING..." messages)
    jsr screen_clear

    // Render the loaded art data
    jsr title_render_data
    rts
#endif

title_fallback_render:
    // Simple text title (no disk art available)
    jsr screen_clear        // Clear KERNAL residue from failed load too
    lda #0
    sta zp_cursor_col
    lda #10
    sta zp_cursor_row
    lda #COL_WHITE
    sta zp_text_color
    lda #<title_str
    sta zp_ptr0
    lda #>title_str
    sta zp_ptr0_hi
    lda #TITLE_FALLBACK_COL
    sta zp_cursor_col
    jsr screen_put_string
    rts

// ============================================================
// title_render_data — Render segment stream from MAP_BASE
// Format: [row, col, color, screen_codes..., $00] ... $FF
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_cursor_row/col, zp_text_color
// ============================================================
title_render_data:
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi

!trd_loop:
    // Read first byte: row or $FF (end marker)
    ldy #0
#if C128
    jsr mmu_safe_map_read_ptr1
#else
    lda (zp_ptr1),y
#endif
    cmp #$ff
    beq !trd_done+
    sta zp_cursor_row

    // Read col
    iny
#if C128
    jsr mmu_safe_map_read_ptr1
#else
    lda (zp_ptr1),y
#endif
#if C128
    clc
    adc #TITLE_ART_COL_OFFSET
#endif
    sta zp_cursor_col

    // Read color
    iny
#if C128
    jsr mmu_safe_map_read_ptr1
#else
    lda (zp_ptr1),y
#endif
    sta zp_text_color

    // Advance ptr1 by 3 to point at string data
    clc
    lda zp_ptr1
    adc #3
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #0
    sta zp_ptr1_hi

#if C128
    // C128: segment text lives in Bank 1 MAP_BASE; render directly using
    // mmu-safe reads so we never pass Bank 1 pointers into Bank 0 string code.
!trd_draw_bank1:
    ldy #0
    jsr mmu_safe_map_read_ptr1
    beq !trd_found+
    cmp #$a0
    bne !trd_put_normal+
    jsr title_put_block_char
    jmp !trd_advance+
!trd_put_normal:
    jsr screen_put_char
!trd_advance:
    inc zp_ptr1
    bne !trd_draw_bank1-
    inc zp_ptr1_hi
    jmp !trd_draw_bank1-

!trd_found:
    // Skip null terminator.
    inc zp_ptr1
    bne !trd_next+
    inc zp_ptr1_hi
!trd_next:
#else
    // C64: title stream and render source are in the active RAM bank.
    lda zp_ptr1
    sta zp_ptr0
    lda zp_ptr1_hi
    sta zp_ptr0_hi
    jsr screen_put_string

    // Scan forward in ptr1 to find null terminator.
    ldy #0
!trd_scan:
    lda (zp_ptr1),y
    beq !trd_found+
    iny
    bne !trd_scan-         // Safety: max 255 chars per segment

!trd_found:
    // Advance ptr1 past the null byte
    iny                    // Y = length + 1
    tya
    clc
    adc zp_ptr1
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #0
    sta zp_ptr1_hi
#endif

    jmp !trd_loop-

!trd_done:
    rts

#if C128
// C64 title data uses $A0 as reverse-space solid blocks. On the C128 VDC
// path, write a plain space and set reverse-video in the attribute byte so
// the block glyph survives the 80-column character mapping.
title_put_block_char:
    php
    stx tbc_save_x
    jsr screen_set_cursor

    sei
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    lda #SC_SPACE
    jsr vdc_write_data

    lda zp_color_hi
    ldy zp_color_lo
    jsr vdc_set_update_addr
    ldx zp_text_color
    lda vic_to_vdc_color,x
    ora #$40
    jsr vdc_write_data
    plp

    ldx tbc_save_x
    inc zp_cursor_col
    rts
tbc_save_x: .byte 0
#endif

// Filename for KERNAL LOAD (PETSCII, NOT null-terminated — KERNAL uses length)
// Must use explicit PETSCII bytes — .text produces screen codes under screencode_upper
title_filename:
#if C128
    .byte $54, $31, $32, $38                       // "T128"
#else
    .byte $54, $36, $34                             // "T64"
#endif
title_filename_end:
