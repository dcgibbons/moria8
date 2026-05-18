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
.const TITLE_ART_COL_OFFSET = hal_layout_title_art_col_offset
// ============================================================
// title_load_and_draw — Load and render the title screen
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_cursor_row/col, zp_text_color
// ============================================================
title_load_and_draw:
#if hal_layout_title_load_uses_cache
    jmp c128_title_load_and_draw_cached
#else
    jsr hal_asset_load_title
    bcs title_fallback_render    // Carry set = error

    // Clear KERNAL status byte — LOAD leaves EOI (bit 6) set from the last file byte.
    // Without this, READST in any subsequent file read returns stale status → false errors.
    lda #0
    sta zp_kernal_status

    // Clear screen after KERNAL LOAD (removes "SEARCHING..." messages)
    jsr hal_screen_clear

    // Render the loaded art data
    jsr title_render_data
    rts
#endif

title_fallback_render:
    // Simple text title (no disk art available)
    jsr hal_screen_clear        // Clear KERNAL residue from failed load too
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
    jsr hal_screen_put_string
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
#if hal_layout_title_art_bank1_source
    jsr mmu_safe_map_read_ptr1
#else
    lda (zp_ptr1),y
#endif
    cmp #$ff
    beq !trd_done+
    sta zp_cursor_row

    // Read col
    iny
#if hal_layout_title_art_bank1_source
    jsr mmu_safe_map_read_ptr1
#else
    lda (zp_ptr1),y
#endif
    clc
    adc #TITLE_ART_COL_OFFSET
    sta zp_cursor_col

    // Read color
    iny
#if hal_layout_title_art_bank1_source
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

#if hal_layout_title_art_bank1_source
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
    jsr hal_screen_put_char
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
    jsr hal_screen_put_string

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

#if hal_layout_title_reverse_space_attr
// C64 title data uses $A0 as reverse-space solid blocks. On the C128 VDC
// path, write a plain space and set reverse-video in the attribute byte so
// the block glyph survives the 80-column character mapping.
title_put_block_char:
    php
    stx tbc_save_x
    jsr hal_screen_set_cursor

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
