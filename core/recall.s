#importonce
// recall.s — Monster recall data structures and tracking
//
// Legacy non-catalog builds use 4 SoA arrays x MAX_CREATURES.
// Catalog builds (HAL_PLATFORM_MONSTER_CATALOG) use persistent
// recall[RECALL_COUNT][4] interleaved [kills, deaths, attacks, spells] per
// catalog species 0..278 accessed through hal_recall_read_byte /
// hal_recall_write_byte with recall_off_lo/hi.

#import "recall_defs.s"

#if !RECALL_ARRAY_DATA_EXTERNAL && !HAL_PLATFORM_RECALL_CUSTOM
#import "recall_array_data.s"
#endif

// HAL byte-offset interface for persistent recall[RECALL_COUNT][4]
recall_off_lo: .byte 0
recall_off_hi: .byte 0

#if HAL_PLATFORM_MONSTER_CATALOG
recall_cat_id_lo:   .byte 0
recall_cat_id_hi:   .byte 0
recall_last_cat_lo: .byte 0
recall_last_cat_hi: .byte 0
recall_tmp:         .byte 0
recall_tmp2:        .byte 0
recall_tmp3:        .byte 0

// Resident recall view snapshot populated by catalog_recall_match_and_fill
// so OVL_UI (ui_recall_display) needs no cross-bank catalog/recall calls.
recall_view_display:    .byte 0
recall_view_color:      .byte 0
recall_view_level:      .byte 0
recall_view_hd_num:     .byte 0
recall_view_hd_sides:   .byte 0
recall_view_ac:         .byte 0
recall_view_atk0_type:  .byte 0
recall_view_atk0_dice:  .byte 0
recall_view_atk0_sides: .byte 0
recall_view_atk1_type:  .byte 0
recall_view_atk1_dice:  .byte 0
recall_view_atk1_sides: .byte 0
recall_view_kills:      .byte 0
recall_view_deaths:     .byte 0
recall_view_attacks:    .byte 0
recall_view_spells:     .byte 0
.assert "Recall view record fields are contiguous", recall_view_atk1_sides - recall_view_display, 11

#if !HAL_PLATFORM_RECALL_CUSTOM
// Default RAM/aux-segment accessors over recall_data_start + recall_off_lo/hi.
// hal_recall_read_byte — Input: recall_off_lo/hi. Output: A. Clobbers: A, Y (preserves X, ZP).
hal_recall_read_byte:
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    lda zp_ptr1
    pha
    lda zp_ptr1_hi
    pha
    clc
    lda #<recall_data_start
    adc recall_off_lo
    sta zp_ptr1
    lda #>recall_data_start
    adc recall_off_hi
    sta zp_ptr1_hi
    ldy #0
    jsr mmu_safe_map_read_ptr1
    tay
    pla
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    tya
    rts
#else
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    clc
    lda #<recall_data_start
    adc recall_off_lo
    sta zp_ptr0
    lda #>recall_data_start
    adc recall_off_hi
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

// hal_recall_write_byte — Input: recall_off_lo/hi, A = byte. Clobbers: A, Y (preserves X, ZP).
hal_recall_write_byte:
    tay
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    lda zp_ptr1
    pha
    lda zp_ptr1_hi
    pha
    tya
    pha
    clc
    lda #<recall_data_start
    adc recall_off_lo
    sta zp_ptr1
    lda #>recall_data_start
    adc recall_off_hi
    sta zp_ptr1_hi
    pla
    ldy #0
    jsr mmu_safe_map_write_ptr1
    pla
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    rts
#else
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    tya
    pha
    clc
    lda #<recall_data_start
    adc recall_off_lo
    sta zp_ptr0
    lda #>recall_data_start
    adc recall_off_hi
    sta zp_ptr0_hi
    pla
    ldy #0
    sta (zp_ptr0),y
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    rts
#endif
#endif

// recall_slot_to_cat_id — Resolve active creature slot X to 16-bit catalog ID.
// Input: X = creature slot (0..MAX_CREATURES-1).
// Output: recall_cat_id_lo/hi; C = 1 valid, C = 0 empty/out-of-range.
// Clobbers: A (preserves X, Y)
recall_slot_to_cat_id:
    cpx #TOWN_CREATURE_BASE
    bcc !rstc_dungeon+
    cpx #MAX_CREATURES
    bcs !rstc_invalid+
    txa
    sec
    sbc #TOWN_CREATURE_BASE
    sta recall_cat_id_lo
    lda #0
    sta recall_cat_id_hi
    sec
    rts
!rstc_dungeon:
    cpx #CAT_SLOTS
    bcs !rstc_invalid+
    lda cat_slot_id_hi,x
    bmi !rstc_invalid+
    sta recall_cat_id_hi
    lda cat_slot_id_lo,x
    sta recall_cat_id_lo
    sec
    rts
!rstc_invalid:
    clc
    rts

// recall_set_offset_cat — Compute recall_off_lo/hi = recall_cat_id * 4 + Y.
// Input: recall_cat_id_lo/hi, Y = RECALL_FIELD_* (0..3).
// Clobbers: A (preserves X, Y)
recall_set_offset_cat:
    lda recall_cat_id_lo
    asl
    pha
    lda recall_cat_id_hi
    rol
    sta recall_off_hi
    pla
    asl
    rol recall_off_hi
    sty recall_tmp
    ora recall_tmp
    sta recall_off_lo
    rts

// recall_inc_kills_slot / deaths / attacks — Input: X = slot. Clobbers: A, Y (preserves X).
recall_inc_kills_slot:
    ldy #RECALL_FIELD_KILLS
    jmp recall_inc_slot_field
recall_inc_deaths_slot:
    ldy #RECALL_FIELD_DEATHS
    jmp recall_inc_slot_field
recall_inc_attacks_slot:
    ldy #RECALL_FIELD_ATTACKS
recall_inc_slot_field:
    jsr recall_slot_to_cat_id
    bcc !risf_done+
    jsr recall_set_offset_cat
    jsr hal_recall_read_byte
    cmp #$ff
    beq !risf_done+
    clc
    adc #1
    jmp hal_recall_write_byte
!risf_done:
    rts

// recall_or_spell_slot — OR spell bit index X (0..7) into recall_spells for slot Y.
// Preserves: X
recall_or_spell_slot:
    stx recall_tmp2
    tya
    tax
    jsr recall_slot_to_cat_id
    bcc !ross_done+
    ldy #RECALL_FIELD_SPELLS
    jsr recall_set_offset_cat
    jsr hal_recall_read_byte
    ldx recall_tmp2
    ora recall_spell_bit,x
    jsr hal_recall_write_byte
!ross_done:
    ldx recall_tmp2
    rts

// recall_load_view_counters — Load kills/deaths/attacks/spells for recall_cat_id_lo/hi
// into recall_view_kills..recall_view_spells. Returns A = OR of all 4 bytes (Z=1 if unseen).
// Clobbers: A, Y (preserves X)
recall_load_view_counters:
    lda #0
    sta recall_tmp3
    sta recall_tmp2
!rlvc_loop:
    ldy recall_tmp2
    jsr recall_set_offset_cat
    jsr hal_recall_read_byte
    ldy recall_tmp2
    sta recall_view_kills,y
    ora recall_tmp3
    sta recall_tmp3
    inc recall_tmp2
    lda recall_tmp2
    cmp #4
    bcc !rlvc_loop-
    lda recall_tmp3
    rts
#endif

// Spell bit lookup table, indexed by spell handler (monster_magic.s): the
// eight MSF bits, then Hold Person, which has no bit of its own and marks
// bit 0 (recall shows only SPELLS: YES / NONE, ui_recall.s).
recall_spell_bit:
    .byte 1, 2, 4, 8, 16, 32, 64, 128
    .byte 1

// Recall is never cleared: Umoria keeps it across deaths as meta-game
// knowledge, and nothing resets it (recall_clear, unused, went 2026-11-08).
