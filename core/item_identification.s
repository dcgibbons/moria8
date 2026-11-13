#importonce
// item_identification.s — item ID state, shuffled descriptions, and lookup helpers

// ============================================================
// Item Identification System
// ============================================================

// Per-type identification state lives in id_known_bits (item_defs.s): one bit
// per item type ID, set = known. Runtime initialization below derives defaults
// from it_category; there is no ROM-initialized copy.

// Packed unknown-description indexes: two types per byte, even type in the low
// nibble, odd type in the high nibble. Class membership is not stored; it is
// derived from it_category (potion/scroll/ring/wand/staff are the randomized
// classes, everything else renders its real name/color even if a bad save
// marks it unknown). Apple IIe keeps this table in aux RAM (A2AuxData) and
// reads it through the aux thunk; other ports keep it resident.
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
:AuxDataSegment()
#endif
// C128 keeps it in the resident items payload: it rode the Bank 1 names
// payload until 2026-11-07, when the potions of gain stat needed the room.
it_unknown_idx:
    .fill 9, 0              // types 0-17: fixed, 17 = potion 0
    .byte $21               // 18: potion 1, 19: potion 2
    .byte $10               // 20: scroll 0, 21: scroll 1
    .byte $02               // 22: scroll 2, 23: ring 0
    .byte $31               // 24: ring 1, 25: potion 3
    .byte $54               // 26: potion 4, 27: potion 5
    .byte $76               // 28: potion 6, 29: potion 7
    .byte $98               // 30: potion 8, 31: potion 9
    .byte $43               // 32: scroll 3, 33: scroll 4
    .byte $65               // 34: scroll 5, 35: scroll 6
    .byte $87               // 36: scroll 7, 37: scroll 8
    .byte $09               // 38: scroll 9, 39: wand 0
    .byte $21               // 40: wand 1, 41: wand 2
    .byte $03               // 42: wand 3, 43: staff 0
    .byte $21               // 44: staff 1, 45: staff 2
    .byte $03               // 46: staff 3, 47: fixed
    .fill 24, 0             // types 48-95: fixed/ordinary, no randomized class
    // Approved pool-wrap assignment for appended randomized-class rows:
    // class-local indexes wrap modulo pool size (potions/scrolls 12, rings 4,
    // wands/staves 5). Duplicate appearances are cosmetic and save-free.
    .byte $ba               // 96: potion 10, 97: potion 11
    .byte $10               // 98: potion 0, 99: potion 1
    .byte $a2               // 100: potion 2, 101: scroll 10
    .byte $0b               // 102: scroll 11, 103: scroll 0
    .byte $21               // 104: scroll 1, 105: scroll 2
    .byte $43               // 106: scroll 3, 107: scroll 4
    .byte $25               // 108: scroll 5, 109: ring 2
    .byte $03               // 110: ring 3, 111: ring 0
    .byte $21               // 112: ring 1, 113: ring 2
    .byte $04               // 114: wand 4, 115: wand 0
    .byte $21               // 116: wand 1, 117: wand 2
    .byte $43               // 118: wand 3, 119: staff 4
    .byte $10               // 120: staff 0, 121: staff 1
    .byte $00               // 122-123: fixed armor
    .byte $00               // 124-125: fixed amulets
    .byte $23               // 126: potion 3, 127: staff 2
    .fill 4, 0              // 128-134: fixed chest names
    .byte $06               // 136: scroll 6 (pool wrap, as 96-127); 137: fixed
    .byte $00               // 138-139: fixed launcher names
    .byte $54, $76, $98     // 140-145: potions 4-9 (pool wrap, as 96-127)
    .byte $03, $01          // 146-148: rings 3, 0, 1 (pool wrap); 149: fixed amulet
    .byte $00               // 150-151: fixed crowns
    .byte $40, $10, $02     // 152: fixed crown; 153-156: wands 4, 0, 1, 2 (pool wrap, as 114-118)
it_unknown_idx_end:
.assert "it_unknown_idx size", it_unknown_idx_end - it_unknown_idx, (ITEM_TYPE_COUNT + 1) >> 1
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
.segment Default
#endif
#if HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
:ResidentItemsSegment()
#endif

// Shuffle tables: map category-local index → description index
// 12 potions, 12 scrolls, 4 rings — full pool shuffled, first N used.
// Set at a new game and by a load, so a port short of room may place them in
// uninitialized RAM (PLATFORM_SHUFFLES_EXTERNAL: the C64's page 3, the
// Atari's high RAM).
#if PLATFORM_SHUFFLES_EXTERNAL
.label potion_shuffle = PLATFORM_SHUFFLE_BASE
.label scroll_shuffle = potion_shuffle + 12
.label ring_shuffle   = scroll_shuffle + 12
.label wand_shuffle   = ring_shuffle + 4
.label staff_shuffle  = wand_shuffle + 5
#else
potion_shuffle: .fill 12, 0
scroll_shuffle: .fill 12, 0
ring_shuffle:   .fill 4, 0
wand_shuffle:   .fill 5, 0
staff_shuffle:  .fill 5, 0
#endif
.assert "The shuffle tables are contiguous in class order", staff_shuffle - potion_shuffle, 33

// iuk_flavour_x — The global flavour index of unknown item type X: carry
// clear and X = the index into flavour_name_lo/hi and flavour_colors for a
// potion, scroll, ring, wand or staff; carry set for any other category.
// Sets item_display_id. Clobbers: A, X, Y.
iuk_flavour_x:
    stx item_display_id
    ldy it_category,x
    cpy #ICAT_POTION
    bcc !iuf_none+
    cpy #ICAT_STAFF + 1
    bcs !iuf_none+
    lda iuf_class_base - ICAT_POTION,y
    bmi !iuf_none+              // a book
    sta iuf_base
    jsr iuk_index_for_type      // A = class-local index (X preserved)
    clc
    adc iuf_base
    tax
    lda potion_shuffle,x        // shuffled class-local description index
    clc
    adc iuf_base
    tax
    clc
    rts
!iuf_none:
    sec
    rts
iuf_class_base: .byte 0, 12, 24, $ff, 28, 33   // potion, scroll, ring, book, wand, staff
iuf_base:       .byte 0
.assert "ICAT ids iuf_class_base assumes", ICAT_STAFF - ICAT_POTION, 5
.assert "ICAT_BOOK sits between rings and wands", ICAT_BOOK - ICAT_POTION, 3

// iuk_index_for_type — Class-local unknown-description index for item type X.
// Input: X = item type ID. Output: A = index (0-15). Preserves X. Clobbers: A, Y.
// Aux-resident on Apple IIe: the read goes through the aux thunk.
iuk_index_for_type:
    txa
    lsr
    tay
    bcs !iuk_odd+
    :AuxReadY(it_unknown_idx)
    and #$0f
    rts
!iuk_odd:
    :AuxReadY(it_unknown_idx)
    lsr
    lsr
    lsr
    lsr
    rts

// Unidentified name strings (screen codes, null-terminated). No article, as
// identified names have none ("Potion of Cure Light Wounds"): with one, the
// game said "You see a a Blue Potion." (maintainer, 2026-11-05: drop them).
pn_0:  .text "Blue" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_1:  .text "Red" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_2:  .text "Green" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_3:  .text "Yellow" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_4:  .text "Clear" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_5:  .text "Azure" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_6:  .text "Smoky" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_7:  .text "Brown" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_8:  .byte ITOK_A_SILVER ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_9:  .text "Pink" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_10: .text "Cloudy" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_11: .byte ITOK_GOLD ; .text "en" ; .byte ITOK_POTION_SUFFIX ; .byte 0

sn_0:  .text "White " ; .byte ITOK_SCROLL ; .byte 0
sn_1:  .text "Brown " ; .byte ITOK_SCROLL ; .byte 0
sn_2:  .text "Grey " ; .byte ITOK_SCROLL ; .byte 0
sn_3:  .text "Faded " ; .byte ITOK_SCROLL ; .byte 0
sn_4:  .text "Glowing " ; .byte ITOK_SCROLL ; .byte 0
sn_5:  .byte ITOK_SCROLL_OF_ART ; .text "Lumen" ; .byte 0
sn_6:  .byte ITOK_SCROLL_OF_ART ; .text "Veritas" ; .byte 0
sn_7:  .byte ITOK_SCROLL_OF_ART ; .text "Dura" ; .byte 0
sn_8:  .byte ITOK_SCROLL_OF_ART ; .text "Libera" ; .byte 0
sn_9:  .byte ITOK_SCROLL_OF_ART ; .text "Acuta" ; .byte 0
sn_10: .byte ITOK_SCROLL_OF_ART ; .text "Ferox" ; .byte 0
sn_11: .byte ITOK_SCROLL_OF_ART ; .text "Tutela" ; .byte 0

rn_0: .byte ITOK_GOLD ; .byte ITOK_RING_SUFFIX ; .byte 0
rn_1: .byte ITOK_A_SILVER ; .byte ITOK_RING_SUFFIX ; .byte 0
rn_2: .text "Bronze" ; .byte ITOK_RING_SUFFIX ; .byte 0
rn_3: .byte ITOK_A_COPPER ; .byte ITOK_RING_SUFFIX ; .byte 0


// Wand identification
wn_0: .text "Iron " ; .byte ITOK_WAND ; .byte 0
wn_1: .byte ITOK_A_COPPER ; .text " " ; .byte ITOK_WAND ; .byte 0
wn_2: .byte ITOK_A_SILVER ; .text " " ; .byte ITOK_WAND ; .byte 0
wn_3: .text "Bone " ; .byte ITOK_WAND ; .byte 0
wn_4: .text "Oak " ; .byte ITOK_WAND ; .byte 0


// Staff identification
sfn_0: .text "Birch " ; .byte ITOK_STAFF ; .byte 0
sfn_1: .text "Pine " ; .byte ITOK_STAFF ; .byte 0
sfn_2: .text "Maple " ; .byte ITOK_STAFF ; .byte 0
sfn_3: .text "Willow " ; .byte ITOK_STAFF ; .byte 0
sfn_4: .text "Ash " ; .byte ITOK_STAFF ; .byte 0

// Unidentified names and colours, one table each in class order (potions
// 0-11, scrolls 12-23, rings 24-27, wands 28-32, staffs 33-37: the shuffle
// tables' order), indexed by the global flavour index iuk_flavour_x returns.
// One per class, and one copy of each lookup per class, until 2026-11-07.
flavour_name_lo:
    .byte <pn_0, <pn_1, <pn_2, <pn_3, <pn_4, <pn_5
    .byte <pn_6, <pn_7, <pn_8, <pn_9, <pn_10, <pn_11
    .byte <sn_0, <sn_1, <sn_2, <sn_3, <sn_4, <sn_5
    .byte <sn_6, <sn_7, <sn_8, <sn_9, <sn_10, <sn_11
    .byte <rn_0, <rn_1, <rn_2, <rn_3
    .byte <wn_0, <wn_1, <wn_2, <wn_3, <wn_4
    .byte <sfn_0, <sfn_1, <sfn_2, <sfn_3, <sfn_4
flavour_name_hi:
    .byte >pn_0, >pn_1, >pn_2, >pn_3, >pn_4, >pn_5
    .byte >pn_6, >pn_7, >pn_8, >pn_9, >pn_10, >pn_11
    .byte >sn_0, >sn_1, >sn_2, >sn_3, >sn_4, >sn_5
    .byte >sn_6, >sn_7, >sn_8, >sn_9, >sn_10, >sn_11
    .byte >rn_0, >rn_1, >rn_2, >rn_3
    .byte >wn_0, >wn_1, >wn_2, >wn_3, >wn_4
    .byte >sfn_0, >sfn_1, >sfn_2, >sfn_3, >sfn_4
flavour_colors:
    .byte COL_BLUE, COL_LRED, COL_GREEN, COL_YELLOW, COL_WHITE, COL_CYAN
    .byte COL_GREY, COL_BROWN, COL_LGREY, COL_LRED, COL_WHITE, COL_YELLOW
    .byte COL_WHITE, COL_BROWN, COL_GREY, COL_LGREY, COL_LGREEN, COL_CYAN
    .byte COL_BLUE, COL_ORANGE, COL_PURPLE, COL_LRED, COL_RED, COL_YELLOW
    .byte COL_YELLOW, COL_LGREY, COL_BROWN, COL_ORANGE
    .byte COL_LGREY, COL_ORANGE, COL_WHITE, COL_LGREY, COL_BROWN
    .byte COL_WHITE, COL_BROWN, COL_ORANGE, COL_LGREEN, COL_LGREY
.assert "flavour_name_lo covers the five classes", flavour_name_hi - flavour_name_lo, 38
.assert "flavour_colors covers the five classes", * - flavour_colors, 38

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
:ItemInitIdentSegment()
#endif
// ============================================================
// item_init_identification — Reset id_known and shuffle tables
// Called once at new game start.
// Clobbers: A, X, Y
// ============================================================
item_init_identification:
    // Clear the full bitset, then mark implemented fixed-description IDs known.
    ldx #ID_KNOWN_BYTES - 1
    lda #0
!iid_clear:
    sta id_known_bits,x
    dex
    bpl !iid_clear-
    ldx #0
!iid_default:
    // Randomized-appearance classes (potion/scroll/ring/wand/staff) start
    // unknown; fixed-description classes (everything else) start known.
    ldy it_category,x
    cpy #ICAT_POTION
    bcc !iid_set_known+
    cpy #ICAT_AMULET
    bcs !iid_set_known+     // AMULET, CHEST, and later fixed classes
    cpy #ICAT_BOOK
    beq !iid_set_known+
    bne !iid_next+
!iid_set_known:
    jsr id_known_set
!iid_next:
    inx
    cpx #ITEM_TYPE_COUNT
    bcc !iid_default-

    // Initialize shuffle tables to identity (0..11 / 0..3 / 0..4)
    ldx #11                         // For 12 elements (0-11)
!iid_init_ps:
    txa
    sta potion_shuffle,x
    sta scroll_shuffle,x
    dex
    bpl !iid_init_ps-
    ldx #3                          // For 4 elements (0-3)
!iid_init_rs:
    txa
    sta ring_shuffle,x
    dex
    bpl !iid_init_rs-
    ldx #4                          // For 5 elements (0-4)
!iid_init_ws:
    txa
    sta wand_shuffle,x
    sta staff_shuffle,x
    dex
    bpl !iid_init_ws-

    lda #<potion_shuffle
    sta zp_ptr0
    lda #>potion_shuffle
    sta zp_ptr0_hi
    ldx #11
    jsr iid_shuffle_ptr

    lda #<scroll_shuffle
    sta zp_ptr0
    lda #>scroll_shuffle
    sta zp_ptr0_hi
    ldx #11
    jsr iid_shuffle_ptr

    lda #<ring_shuffle
    sta zp_ptr0
    lda #>ring_shuffle
    sta zp_ptr0_hi
    ldx #3
    jsr iid_shuffle_ptr

    lda #<wand_shuffle
    sta zp_ptr0
    lda #>wand_shuffle
    sta zp_ptr0_hi
    ldx #4
    jsr iid_shuffle_ptr

    lda #<staff_shuffle
    sta zp_ptr0
    lda #>staff_shuffle
    sta zp_ptr0_hi
    ldx #4
    jmp iid_shuffle_ptr

iid_shuffle_ptr:
!iid_shuffle_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    sta iid_rand_y
    ldy iid_save_x
    lda (zp_ptr0),y
    pha
    ldy iid_rand_y
    lda (zp_ptr0),y
    ldy iid_save_x
    sta (zp_ptr0),y
    pla
    ldy iid_rand_y
    sta (zp_ptr0),y
    ldx iid_save_x
    dex
    bne !iid_shuffle_loop-

    rts

iid_save_x: .byte 0                // Scratch for Fisher-Yates
iid_rand_y: .byte 0

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
:ItemInitIdentRestoreSegment()
#endif
// ============================================================
// item_get_name_ptr — Get name string pointer for an item type
// Input: A = item type ID
// Output: zp_ptr0 = pointer to null-terminated name string
// Clobbers: A, X, Y
// ============================================================
item_get_name_ptr:
    tax
    // Check if this type is known
    jsr id_known_test
    beq !ignp_unknown+
    jmp !ignp_known+

    // Unknown — look up randomized description
!ignp_unknown:
    jsr iuk_flavour_x
    bcs !ignp_fallback+
    lda flavour_name_lo,x
    sta zp_ptr0
    lda flavour_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr
!ignp_fallback:
    ldx item_display_id

    // Fallback (shouldn't happen): return real name
!ignp_known:
    stx item_display_id
    lda it_category,x
    cmp #ICAT_POTION
    beq !ignp_potion_prefix+
    cmp #ICAT_SCROLL
    beq !ignp_scroll_prefix+
    cmp #ICAT_RING
    beq !ignp_ring_prefix+
    cmp #ICAT_AMULET
    beq !ignp_amulet_prefix+
    cmp #ICAT_BOOK
    beq !ignp_book_prefix+
!ignp_raw_known:
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
    jsr item_load_known_name_ptr
#else
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
#endif
#if HAL_PLATFORM_ITEM_NAME_STREAMS_BANKED
    jmp item_decode_name_ptr_bank1
#else
    jmp item_decode_name_ptr
#endif
!ignp_qualified:
    ldy #0
!ignp_copy_prefix:
    lda (zp_ptr0),y
    beq !ignp_prefix_done+
    sta item_name_decode_buf,y
    iny
    bne !ignp_copy_prefix-
!ignp_prefix_done:
    sty item_name_dst_idx
    ldx item_display_id
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
    jsr item_load_known_name_ptr
#else
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
#endif
#if HAL_PLATFORM_ITEM_NAME_STREAMS_BANKED
    jmp item_decode_name_ptr_bank1_at_dst
#else
    jmp item_decode_name_ptr_at_dst
#endif

!ignp_potion_prefix:
    lda #<idgp_potion_prefix
    ldx #>idgp_potion_prefix
    bne !ignp_prefix_set+
!ignp_scroll_prefix:
    lda #<idgp_scroll_prefix
    ldx #>idgp_scroll_prefix
    bne !ignp_prefix_set+
!ignp_ring_prefix:
    lda #<idgp_ring_prefix
    ldx #>idgp_ring_prefix
    bne !ignp_prefix_set+
!ignp_amulet_prefix:
    lda #<idgp_amulet_prefix
    ldx #>idgp_amulet_prefix
    bne !ignp_prefix_set+
!ignp_book_prefix:
    ldx item_display_id
    cpx #48
    beq !ignp_priest_prefix+
    cpx #58
    bcs !ignp_priest_prefix+
    lda #<idgp_mage_book_prefix
    ldx #>idgp_mage_book_prefix
    bne !ignp_prefix_set+
!ignp_priest_prefix:
    lda #<idgp_priest_book_prefix
    ldx #>idgp_priest_book_prefix
!ignp_prefix_set:
    sta zp_ptr0
    stx zp_ptr0_hi
    jmp !ignp_qualified-

idgp_potion_prefix:      .text "Potion of " ; .byte 0
idgp_scroll_prefix:      .text "Scroll of " ; .byte 0
idgp_ring_prefix:        .text "Ring of " ; .byte 0
idgp_amulet_prefix:      .text "Amulet of " ; .byte 0
idgp_mage_book_prefix:   .text "Spellbook " ; .byte 0
idgp_priest_book_prefix: .text "Holy Book of Prayers " ; .byte 0
item_display_id: .byte 0

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
// item_load_known_name_ptr — Resolve a known-name stream pointer without the
// resident high-byte table. Name streams are emitted in item-ID order, so a
// low-byte wrap between adjacent entries means the stream crossed a page.
// Input: X = item type ID
// Output: zp_ptr0/zp_ptr0_hi = tokenized known-name stream
// Clobbers: A, Y
item_load_known_name_ptr:
    stx item_display_id
#if HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
    // it_name_lo rides the Bank 1 names payload on C128 (see item_tables.s).
    jsr inl_read_lo_bank1_x
#else
    lda it_name_lo,x
#endif
    sta zp_ptr0
    lda #>itn_0
    sta zp_ptr0_hi
    txa
    beq !ilkn_done+
    ldy #0
!ilkn_loop:
#if HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
    sty ilkn_save_y
    lda #<it_name_lo
    sta zp_ptr1
    lda #>it_name_lo
    sta zp_ptr1_hi
    ldy ilkn_save_y
    jsr mmu_safe_db_read_ptr1
    sta ilkn_save_a
    ldy ilkn_save_y
    iny
    jsr mmu_safe_db_read_ptr1
    ldy ilkn_save_y
    cmp ilkn_save_a
#else
    lda it_name_lo + 1,y
    cmp it_name_lo,y
#endif
    bcs !ilkn_same_page+
    inc zp_ptr0_hi
!ilkn_same_page:
    iny
    cpy item_display_id
    bcc !ilkn_loop-
!ilkn_done:
    rts

#if HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
// inl_read_lo_bank1_x — Bank 1 read of it_name_lo,x (names payload).
inl_read_lo_bank1_x:
    stx ilkn_save_y
    lda #<it_name_lo
    sta zp_ptr1
    lda #>it_name_lo
    sta zp_ptr1_hi
    ldy ilkn_save_y
    jmp mmu_safe_db_read_ptr1
ilkn_save_y: .byte 0
ilkn_save_a: .byte 0
#endif
#endif

// Decode an item-name token stream from zp_ptr0 into item_name_decode_buf.
// Bytes below $80 copy literally; bytes $80+ index item_name_token_lo/hi.
// ItemNameExpandToken — Append token A ($80 | index) to item_name_decode_buf
// and step past it in the stream; Z clear after (the source index is
// non-zero). One copy, called by both decoders, where the banked streams
// need a second decoder; inline otherwise.
.macro ItemNameExpandToken() {
    and #$7f
    tax
    lda item_name_token_lo,x
    sta zp_ptr1
    lda item_name_token_hi,x
    sta zp_ptr1_hi
    ldy #0
!copy:
    lda (zp_ptr1),y
    beq !done+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    iny
    bne !copy-
!done:
    inc item_name_src_idx
}

item_decode_name_ptr:
    lda #0
    sta item_name_dst_idx
item_decode_name_ptr_at_dst:
    lda zp_ptr1
    sta item_name_save_ptr1
    lda zp_ptr1_hi
    sta item_name_save_ptr1_hi
    lda #0
    sta item_name_src_idx
!idnp_loop:
    ldy item_name_src_idx
    lda (zp_ptr0),y
    beq item_name_decode_finish
    bmi !idnp_token+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    inc item_name_src_idx
    bne !idnp_loop-
!idnp_token:
#if HAL_PLATFORM_ITEM_NAME_STREAMS_BANKED
    jsr item_name_expand_token
#else
    :ItemNameExpandToken()
#endif
    bne !idnp_loop-
// item_name_decode_finish — Terminate the buffer, restore zp_ptr1 and point
// zp_ptr0 at the decoded name (both decoders end here).
item_name_decode_finish:
    ldx item_name_dst_idx
    lda #0
    sta item_name_decode_buf,x
    lda item_name_save_ptr1
    sta zp_ptr1
    lda item_name_save_ptr1_hi
    sta zp_ptr1_hi
    lda #<item_name_decode_buf
    sta zp_ptr0
    lda #>item_name_decode_buf
    sta zp_ptr0_hi
    rts

#if HAL_PLATFORM_ITEM_NAME_STREAMS_BANKED
item_name_expand_token:
    :ItemNameExpandToken()
    rts

// C128 known item-name streams live in Bank 1 DB RAM (mmu_safe_db_read_ptr0);
// on Apple II they live in aux RAM (mmu_safe_map_read_ptr0 aux thunk). Token
// strings remain resident, so only source stream reads need the safe read.
item_decode_name_ptr_bank1:
    lda #0
    sta item_name_dst_idx
item_decode_name_ptr_bank1_at_dst:
    lda zp_ptr1
    sta item_name_save_ptr1
    lda zp_ptr1_hi
    sta item_name_save_ptr1_hi
    lda #0
    sta item_name_src_idx
!idnp_loop:
    ldy item_name_src_idx
    :ItemNameRead_ptr0_y()
    beq !idnp_done+
    bmi !idnp_token+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    inc item_name_src_idx
    bne !idnp_loop-
!idnp_token:
    jsr item_name_expand_token
    bne !idnp_loop-
!idnp_done:
    jmp item_name_decode_finish
#endif

.const ITEM_NAME_DECODE_BUF_SIZE = 48
#if PLATFORM_SCRATCH_BUFS_IN_PAGE2 || PLATFORM_ITEM_NAME_BUF_LOW
.label item_name_decode_buf = PLATFORM_ITEM_NAME_DECODE_BUF_BASE
.assert "item_name_decode_buf size matches its page-2 home", ITEM_NAME_DECODE_BUF_SIZE, 48
#else
item_name_decode_buf: .fill ITEM_NAME_DECODE_BUF_SIZE, 0
#endif
item_name_src_idx: .byte 0
item_name_dst_idx: .byte 0
item_name_save_ptr1: .byte 0
item_name_save_ptr1_hi: .byte 0

// ============================================================
// item_get_floor_color — Get display color for a floor item
// Input: A = item type ID
// Output: A = color byte
// Clobbers: X
// ============================================================
item_get_floor_color:
    tax
    // Check if known
    jsr id_known_test
    bne !igfc_known+

    // Unknown — return randomized color
    jsr iuk_flavour_x
    bcs !igfc_fallback+
    lda flavour_colors,x
    rts
!igfc_fallback:
    ldx item_display_id
!igfc_known:
    lda it_color_ac,x
    lsr
    lsr
    lsr
    lsr
    rts

