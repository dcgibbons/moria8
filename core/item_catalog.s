#importonce
// item_catalog.s — Cold 'ITM2' ITEM.CAT reader and canonical Huffman decoder
//
// Reads item records, cold stats, ego records (1..55), and canonical
// Huffman + non-recursive $80+ token strings via hal_item_cat_read_byte
// using item_cat_off_lo/hi. Uses zero new zero-page variables.

#import "../platforms/shared/item_catalog/item_cat_layout.s"

// Byte offset interface for hal_item_cat_read_byte (16-bit offset into ITEM.CAT).
item_cat_off_lo: .byte 0
item_cat_off_hi: .byte 0

#if !HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../platforms/shared/item_catalog/item_cat_data.s"

// hal_item_cat_read_byte — Default reader over in-binary item_cat_data.
// Input: item_cat_off_lo/hi. Output: A = byte. Clobbers: A, Y (preserves X, ZP).
hal_item_cat_read_byte:
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    clc
    lda #<item_cat_data
    adc item_cat_off_lo
    sta zp_ptr0
    lda #>item_cat_data
    adc item_cat_off_hi
    sta zp_ptr0_hi
    ldy #0
    lda (zp_ptr0),y
    tay
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    tya
    rts
#endif

// ============================================================
// Reader State & Decoded Field Outputs (BSS — zero ZP)
// ============================================================
icat_sel_lo:        .byte 0
icat_sel_hi:        .byte 0
icat_cached_lo:     .byte $ff
icat_cached_hi:     .byte $ff
icat_rec_0:         .byte 0
icat_rec_1:         .byte 0
icat_rec_2:         .byte 0
icat_rec_3:         .byte 0

icat_cost_lo:       .byte 0
icat_cost_hi:       .byte 0
icat_weight_lo:     .byte 0
icat_weight_hi:     .byte 0
icat_dmg_dice:      .byte 0
icat_dmg_sides:     .byte 0
icat_flags_0:       .byte 0
icat_flags_1:       .byte 0
icat_flags_2:       .byte 0
icat_flags_3:       .byte 0
icat_p1_lo:         .byte 0
icat_p1_hi:         .byte 0
icat_tohit:         .byte 0
icat_todam:         .byte 0
icat_toac:          .byte 0
icat_ego_cost_lo:   .byte 0
icat_ego_cost_hi:   .byte 0

// Lazy canonical Huffman tables cache (loaded once from ITEM.CAT on first decode)
icat_canon_loaded:  .byte 0
icat_canon_counts:  .fill ITMCAT_CANON_MAX_LEN + 1, 0
icat_canon_syms:    .fill ITMCAT_CANON_NUM_SYMS, 0

// Canonical string decoder scratch (all BSS — zero ZP)
icat_str_id_lo:     .byte 0
icat_str_id_hi:     .byte 0
icat_str_off_lo:    .byte 0
icat_str_off_hi:    .byte 0
icat_cur_byte:      .byte 0
icat_bits_left:     .byte 0
icat_outer_off_lo:  .byte 0
icat_outer_off_hi:  .byte 0
icat_outer_byte:    .byte 0
icat_outer_bits:    .byte 0
icat_code_lo:       .byte 0
icat_code_hi:       .byte 0
icat_sym_idx:       .byte 0
icat_bl:            .byte 0
icat_skip:          .byte 0
icat_tmp:           .byte 0
icat_tmp2:          .byte 0
item_name_dst_idx:  .byte 0

// icat_read_next — Read byte at item_cat_off_lo/hi and increment offset.
// Output: A = byte. Clobbers: A, Y (preserves X).
icat_read_next:
    jsr hal_item_cat_read_byte
    inc item_cat_off_lo
    bne !irn_done+
    inc item_cat_off_hi
!irn_done:
    rts

// icat_select_id — Select paged item slot A (0..254) using item_cur_page,
// loading icat_rec_0..3 from ITMCAT_OFF_RECORDS + logical_id * 4.
// Input: A = slot_lo (0..254), item_cur_page ($00 or $40).
// Output: icat_sel_lo/hi = 9-bit logical ID, icat_rec_0..3 loaded.
// Clobbers: A, Y (preserves X).
item_cat_select_id:
    ldy #0
    sty icat_sel_hi
    bit item_cur_page
    bvc !ics_p0+
    clc
    adc #ITEM_PAGE_SIZE
    bcc !ics_p0+
    inc icat_sel_hi
!ics_p0:
    sta icat_sel_lo
item_cat_select_cur:
    lda icat_sel_lo
    cmp icat_cached_lo
    bne !ics_load+
    lda icat_sel_hi
    cmp icat_cached_hi
    bne !ics_load+
    rts
!ics_load:
    lda icat_sel_lo
    sta icat_cached_lo
    lda icat_sel_hi
    sta icat_cached_hi
    // offset = ITMCAT_OFF_RECORDS + (sel * 4)
    lda icat_sel_lo
    asl
    sta item_cat_off_lo
    lda icat_sel_hi
    rol
    sta item_cat_off_hi
    asl item_cat_off_lo
    rol item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_RECORDS
    sta item_cat_off_lo
    lda item_cat_off_hi
    adc #>ITMCAT_OFF_RECORDS
    sta item_cat_off_hi
    jsr icat_read_next
    sta icat_rec_0
    jsr icat_read_next
    sta icat_rec_1
    jsr icat_read_next
    sta icat_rec_2
    jsr hal_item_cat_read_byte
    sta icat_rec_3
    rts

// item_cat_select_16 — Select logical item ID A (lo), Y (hi). Preserves: X.
item_cat_select_16:
    sta icat_sel_lo
    sty icat_sel_hi
    jmp item_cat_select_cur

// item_cat_get_cost — Load 16-bit cost of currently selected item.
// Output: A = lo, Y = hi (also icat_cost_lo/hi). Preserves: X.
item_cat_get_cost:
    lda icat_rec_0
    and #ITMCAT_REC_COST_MASK
    asl
    sta item_cat_off_lo
    lda #0
    rol
    clc
    adc #>ITMCAT_OFF_COSTS
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_COSTS
    sta item_cat_off_lo
    bcc !icgc_nc+
    inc item_cat_off_hi
!icgc_nc:
    jsr icat_read_next
    sta icat_cost_lo
    jsr hal_item_cat_read_byte
    sta icat_cost_hi
    tay
    lda icat_cost_lo
    rts

// item_cat_is_depth_variant — Output: C = 1 if depth variant, C = 0 otherwise. Preserves: X, Y.
item_cat_is_depth_variant:
    lda icat_rec_0
    asl
    rts

// item_cat_get_weight — Load 16-bit weight (0.1 lb) of selected item.
// Output: A = lo, Y = hi (also icat_weight_lo/hi). Preserves: X.
item_cat_get_weight:
    jsr icat_seek_wd
    jsr hal_item_cat_read_byte   // weight_idx
    asl
    sta item_cat_off_lo
    lda #0
    rol
    clc
    adc #>ITMCAT_OFF_WEIGHTS
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_WEIGHTS
    sta item_cat_off_lo
    bcc !icgw_nc+
    inc item_cat_off_hi
!icgw_nc:
    jsr icat_read_next
    sta icat_weight_lo
    jsr hal_item_cat_read_byte
    sta icat_weight_hi
    tay
    lda icat_weight_lo
    rts

// item_cat_get_dmg — Load dice (A, icat_dmg_dice) and sides (Y, icat_dmg_sides). Preserves: X.
item_cat_get_dmg:
    jsr icat_seek_wd
    inc item_cat_off_lo
    bne !+
    inc item_cat_off_hi
!:  jsr hal_item_cat_read_byte   // dmg_idx
    asl
    sta item_cat_off_lo
    lda #0
    rol
    clc
    adc #>ITMCAT_OFF_DMGS
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_DMGS
    sta item_cat_off_lo
    bcc !icgd_nc+
    inc item_cat_off_hi
!icgd_nc:
    jsr icat_read_next
    sta icat_dmg_dice
    jsr hal_item_cat_read_byte
    sta icat_dmg_sides
    tay
    lda icat_dmg_dice
    rts

// item_cat_get_dmg_packed — Output: A = (dice << 4) | (sides & $0F). Preserves: X.
item_cat_get_dmg_packed:
    jsr item_cat_get_dmg
    asl
    asl
    asl
    asl
    sta icat_tmp
    tya
    and #$0f
    ora icat_tmp
    rts

// icat_seek_wd — Set item_cat_off to ITMCAT_OFF_WDS + (icat_rec_1 & $7F) * 2. Preserves: X.
icat_seek_wd:
    lda icat_rec_1
    and #ITMCAT_REC_WD_MASK
    asl
    sta item_cat_off_lo
    lda #0
    rol
    clc
    adc #>ITMCAT_OFF_WDS
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_WDS
    sta item_cat_off_lo
    bcc !isw_nc+
    inc item_cat_off_hi
!isw_nc:
    rts

// item_cat_get_level — Output: A = vms_level (0..63). Preserves: X, Y.
item_cat_get_level:
    lda icat_rec_3
    and #ITMCAT_REC_LVL_MASK
    rts

// item_cat_get_missile_type — Output: A = 0, 1..3 (launcher), $81..$83 (ammo). Preserves: X, Y.
item_cat_get_missile_type:
    lda icat_rec_3
    asl
    rol
    rol
    and #$03
    sta icat_tmp
    lda icat_rec_1
    and #ITMCAT_REC_AMMO_BIT
    ora icat_tmp
    rts

// item_cat_get_effects — Load icat_flags_0..3 and icat_p1_lo/hi, tohit, todam, toac
// for currently selected item. Preserves: X.
item_cat_get_effects:
    lda icat_rec_2
// item_cat_load_effect_a — Load flags/bonuses for effect index A. Preserves: X.
item_cat_load_effect_a:
    sta item_cat_off_lo
    lda #0
    asl item_cat_off_lo
    rol
    clc
    adc #>ITMCAT_OFF_EFFECTS
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_EFFECTS
    sta item_cat_off_lo
    bcc !icle_nc+
    inc item_cat_off_hi
!icle_nc:
    jsr icat_read_next           // flags_idx
    pha
    jsr hal_item_cat_read_byte   // bonus_idx
    sta icat_tmp

    // Read 4 flag bytes at ITMCAT_OFF_FLAGS + flags_idx * 4
    pla
    sta item_cat_off_lo
    lda #0
    asl item_cat_off_lo
    rol
    asl item_cat_off_lo
    rol
    clc
    adc #>ITMCAT_OFF_FLAGS
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_FLAGS
    sta item_cat_off_lo
    bcc !icf_nc+
    inc item_cat_off_hi
!icf_nc:
    jsr icat_read_next
    sta icat_flags_0
    jsr icat_read_next
    sta icat_flags_1
    jsr icat_read_next
    sta icat_flags_2
    jsr hal_item_cat_read_byte
    sta icat_flags_3

    // Read 5 bonus bytes at ITMCAT_OFF_BONUSES + bonus_idx * 5
    lda icat_tmp
    sta item_cat_off_lo
    lda #0
    asl item_cat_off_lo
    rol
    asl item_cat_off_lo
    rol
    sta item_cat_off_hi
    clc
    lda item_cat_off_lo
    adc icat_tmp
    sta item_cat_off_lo
    bcc !icb_nc1+
    inc item_cat_off_hi
!icb_nc1:
    clc
    lda item_cat_off_lo
    adc #<ITMCAT_OFF_BONUSES
    sta item_cat_off_lo
    lda item_cat_off_hi
    adc #>ITMCAT_OFF_BONUSES
    sta item_cat_off_hi
    jsr icat_read_next
    sta icat_p1_lo
    jsr icat_read_next
    sta icat_p1_hi
    jsr icat_read_next
    sta icat_tohit
    jsr icat_read_next
    sta icat_todam
    jsr hal_item_cat_read_byte
    sta icat_toac
    rts

// item_cat_get_ego — Load ego record (ego_id 1..EGO_COUNT, or 0 for zeroed).
// Input: A = ego_id (0..EGO_COUNT).
// Output: icat_ego_cost_lo/hi, icat_flags_0..3, icat_p1_lo/hi, tohit, todam, toac.
// Preserves: X.
item_cat_get_ego:
    beq !icge_zero+
    cmp #EGO_COUNT + 1
    bcs !icge_zero+
    sec
    sbc #1                       // 0..54
    sta icat_tmp
    asl                          // * 2 (<= 108)
    clc
    adc icat_tmp                 // * 3 (<= 162 < 256)
    clc
    adc #<ITMCAT_OFF_EGOS
    sta item_cat_off_lo
    lda #>ITMCAT_OFF_EGOS
    adc #0
    sta item_cat_off_hi
    jsr icat_read_next           // effect_idx
    pha
    jsr icat_read_next
    sta icat_ego_cost_lo
    jsr hal_item_cat_read_byte
    sta icat_ego_cost_hi
    pla
    jmp item_cat_load_effect_a
!icge_zero:
    lda #0
    sta icat_ego_cost_lo
    sta icat_ego_cost_hi
    sta icat_flags_0
    sta icat_flags_1
    sta icat_flags_2
    sta icat_flags_3
    sta icat_p1_lo
    sta icat_p1_hi
    sta icat_tohit
    sta icat_todam
    sta icat_toac
    rts

// ============================================================
// Canonical Huffman + Non-Recursive $80+ Token String Decoder
// ============================================================

// icat_ensure_canon — Load canonical length counts & symbols lazily once. Preserves: X.
icat_ensure_canon:
    lda icat_canon_loaded
    bne !iec_done+
    lda #<ITMCAT_OFF_CANON_COUNTS
    sta item_cat_off_lo
    lda #>ITMCAT_OFF_CANON_COUNTS
    sta item_cat_off_hi
    lda #0
    sta icat_tmp
!iec_cnt:
    jsr icat_read_next
    ldy icat_tmp
    sta icat_canon_counts,y
    iny
    sty icat_tmp
    cpy #ITMCAT_CANON_MAX_LEN + 1
    bcc !iec_cnt-

    lda #<ITMCAT_OFF_CANON_SYMS
    sta item_cat_off_lo
    lda #>ITMCAT_OFF_CANON_SYMS
    sta item_cat_off_hi
    lda #0
    sta icat_tmp
!iec_sym:
    jsr icat_read_next
    ldy icat_tmp
    sta icat_canon_syms,y
    iny
    sty icat_tmp
    cpy #ITMCAT_CANON_NUM_SYMS
    bcc !iec_sym-
    lda #1
    sta icat_canon_loaded
!iec_done:
    rts

// icat_seek_entry — Seek compressed stream to string entry (icat_str_id_lo/hi).
// Handles ITMCAT_STR_STRIDE (= 8) block indexing and skipping NUL-terminated entries.
// Preserves: X.
.assert "String stride is 8", ITMCAT_STR_STRIDE, 8
icat_seek_entry:
    jsr icat_ensure_canon
    lda icat_str_id_lo
    and #$07
    sta icat_skip
    // blk = str_id >> 3 (0..88)
    lda icat_str_id_lo
    sta icat_tmp
    lda icat_str_id_hi
    lsr
    ror icat_tmp
    lsr
    ror icat_tmp
    lsr
    ror icat_tmp
    lda icat_tmp                 // blk
    asl                          // * 2 (<= 176)
    clc
    adc #<ITMCAT_OFF_BLK_INDEX
    sta item_cat_off_lo
    lda #>ITMCAT_OFF_BLK_INDEX
    adc #0
    sta item_cat_off_hi
    jsr icat_read_next           // bp lo
    pha
    jsr hal_item_cat_read_byte   // bp hi
    sta icat_str_off_hi
    pla
    sta icat_str_off_lo
    and #$07
    sta icat_tmp2                // shift = bp & 7
    // icat_str_off = ITMCAT_OFF_STREAM + (bp >> 3)
    lsr icat_str_off_hi
    ror icat_str_off_lo
    lsr icat_str_off_hi
    ror icat_str_off_lo
    lsr icat_str_off_hi
    ror icat_str_off_lo
    clc
    lda icat_str_off_lo
    adc #<ITMCAT_OFF_STREAM
    sta icat_str_off_lo
    sta item_cat_off_lo
    lda icat_str_off_hi
    adc #>ITMCAT_OFF_STREAM
    sta icat_str_off_hi
    sta item_cat_off_hi

    jsr hal_item_cat_read_byte
    sta icat_cur_byte
    inc icat_str_off_lo
    bne !ise_no_hi+
    inc icat_str_off_hi
!ise_no_hi:
    lda #8
    sec
    sbc icat_tmp2
    sta icat_bits_left
    ldy icat_tmp2
    beq !ise_skip_loop+
!ise_align:
    asl icat_cur_byte
    dey
    bne !ise_align-

!ise_skip_loop:
    lda icat_skip
    beq !ise_done+
!ise_skip_chars:
    jsr icat_read_sym
    bne !ise_skip_chars-
    dec icat_skip
    bne !ise_skip_loop-
!ise_done:
    rts

// icat_read_sym — Decode next canonical Huffman symbol from stream.
// Output: A = symbol (0 = end, 1..$7F = char, $80+ = token). Preserves: X.
icat_read_sym:
    lda #0
    sta icat_code_lo
    sta icat_code_hi
    sta icat_sym_idx
    lda #1
    sta icat_bl
!irs_bit:
    lda icat_bits_left
    bne !irs_have_bit+
    lda icat_str_off_lo
    sta item_cat_off_lo
    lda icat_str_off_hi
    sta item_cat_off_hi
    jsr hal_item_cat_read_byte
    sta icat_cur_byte
    inc icat_str_off_lo
    bne !irs_hi+
    inc icat_str_off_hi
!irs_hi:
    lda #8
    sta icat_bits_left
!irs_have_bit:
    dec icat_bits_left
    asl icat_cur_byte
    rol icat_code_lo
    rol icat_code_hi
    ldy icat_bl
    lda icat_canon_counts,y
    sta icat_tmp
    lda icat_code_hi
    bne !irs_miss+
    lda icat_code_lo
    cmp icat_tmp
    bcs !irs_miss+
    clc
    adc icat_sym_idx
    tay
    lda icat_canon_syms,y
    rts
!irs_miss:
    sec
    lda icat_code_lo
    sbc icat_tmp
    sta icat_code_lo
    lda icat_code_hi
    sbc #0
    sta icat_code_hi
    clc
    lda icat_sym_idx
    adc icat_tmp
    sta icat_sym_idx
    inc icat_bl
    lda icat_bl
    cmp #ITMCAT_CANON_MAX_LEN + 1
    bcc !irs_bit-
    lda #0
    rts

// item_cat_decode_item — Decode paged item name A (slot_lo, with item_cur_page) into item_name_decode_buf.
// item_cat_decode_item_at_dst — Same, appending at item_name_dst_idx.
// Output: zp_ptr0/hi = item_name_decode_buf, NUL-terminated. Preserves: X.
item_cat_decode_item:
    ldy #0
    sty item_name_dst_idx
item_cat_decode_item_at_dst:
    ldy #0
    bit item_cur_page
    bvc !icdi_p0+
    clc
    adc #ITEM_PAGE_SIZE
    bcc !icdi_p0+
    iny
!icdi_p0:
    sta icat_str_id_lo
    sty icat_str_id_hi
    jmp item_cat_decode_entry_at_dst

// item_cat_decode_ego — Decode ego name A (1..EGO_COUNT) into item_name_decode_buf.
// Output: zp_ptr0/hi = item_name_decode_buf, NUL-terminated. Preserves: X.
item_cat_decode_ego:
    ldy #0
    sty item_name_dst_idx
item_cat_decode_ego_at_dst:
    sec
    sbc #1
    clc
    adc #<ITMCAT_STR_BASE_EGO
    sta icat_str_id_lo
    lda #>ITMCAT_STR_BASE_EGO
    adc #0
    sta icat_str_id_hi
    jmp item_cat_decode_entry_at_dst

// item_cat_decode_flavour — Decode flavour A (0..FLAVOUR_COUNT-1) into item_name_decode_buf.
// Output: zp_ptr0/hi = item_name_decode_buf, NUL-terminated. Preserves: X.
item_cat_decode_flavour:
    ldy #0
    sty item_name_dst_idx
item_cat_decode_flavour_at_dst:
    clc
    adc #<ITMCAT_STR_BASE_FLAV
    sta icat_str_id_lo
    lda #>ITMCAT_STR_BASE_FLAV
    adc #0
    sta icat_str_id_hi

// item_cat_decode_entry_at_dst — Decode string entry (icat_str_id_lo/hi) starting at
// item_name_dst_idx, expanding non-recursive $80+ tokens. Sets zp_ptr0 -> item_name_decode_buf.
// Preserves: X.
item_cat_decode_entry_at_dst:
    jsr icat_seek_entry
!icde_loop:
    jsr icat_read_sym
    beq !icde_done+
    bmi !icde_token+
    ldy item_name_dst_idx
    cpy #ITEM_NAME_DECODE_BUF_SIZE - 1
    bcs !icde_loop-
    sta item_name_decode_buf,y
    inc item_name_dst_idx
    bne !icde_loop-
!icde_token:
    // Save outer stream cursor in BSS (non-recursive 1-level token expansion)
    pha
    lda icat_str_off_lo
    sta icat_outer_off_lo
    lda icat_str_off_hi
    sta icat_outer_off_hi
    lda icat_cur_byte
    sta icat_outer_byte
    lda icat_bits_left
    sta icat_outer_bits
    pla
    sec
    sbc #ITMCAT_TOK_MIN
    clc
    adc #<ITMCAT_STR_BASE_TOK
    sta icat_str_id_lo
    lda #>ITMCAT_STR_BASE_TOK
    adc #0
    sta icat_str_id_hi
    jsr icat_seek_entry
!icde_tok_loop:
    jsr icat_read_sym
    beq !icde_tok_done+
    ldy item_name_dst_idx
    cpy #ITEM_NAME_DECODE_BUF_SIZE - 1
    bcs !icde_tok_loop-
    sta item_name_decode_buf,y
    inc item_name_dst_idx
    bne !icde_tok_loop-
!icde_tok_done:
    lda icat_outer_off_lo
    sta icat_str_off_lo
    lda icat_outer_off_hi
    sta icat_str_off_hi
    lda icat_outer_byte
    sta icat_cur_byte
    lda icat_outer_bits
    sta icat_bits_left
    jmp !icde_loop-
!icde_done:
    ldy item_name_dst_idx
    lda #0
    sta item_name_decode_buf,y
    lda #<item_name_decode_buf
    sta zp_ptr0
    lda #>item_name_decode_buf
    sta zp_ptr0_hi
    rts
