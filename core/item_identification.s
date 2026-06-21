#importonce
// item_identification.s — item ID state, shuffled descriptions, and lookup helpers

// ============================================================
// Item Identification System
// ============================================================

// Per-type identification state (0=unknown, 1=known)
id_known:
    .byte 1, 1              // 0-1: Gold — always known
    .byte 1, 1, 1, 1        // 2-5: Weapons — always known
    .byte 1, 1, 1           // 6-8: Armor — always known
    .byte 1                  // 9: Shield — always known
    .byte 1                  // 10: Helm — always known
    .byte 1, 1              // 11-12: Gloves, boots — always known
    .byte 1, 1              // 13-14: Lights — always known
    .byte 1, 1              // 15-16: Food — always known
    .byte 0, 0, 0           // 17-19: Potions — unknown at start
    .byte 0, 0, 0           // 20-22: Scrolls — unknown at start
    .byte 0, 0              // 23-24: Rings — unknown at start
    .byte 0, 0, 0, 0, 0, 0, 0  // 25-31: Potions — unknown at start
    .byte 0, 0, 0, 0, 0, 0, 0  // 32-38: Scrolls — unknown at start
    .byte 0, 0, 0, 0           // 39-42: Wands — unknown at start
    .byte 0, 0, 0, 0           // 43-46: Staves — unknown at start
    .byte 1, 1                  // 47-48: Books — always known
    .byte 1, 1, 1, 1, 1, 1      // 49-54: Ranged weapons/ammo — always known
    .byte 1, 1, 1, 1, 1, 1      // 55-60: Books — always known
    .byte 1                      // 61: Flask of Oil — always known
    .byte 1, 1                  // 62-63: Digging tools — always known
    .fill ITEM_TYPE_COUNT - LEGACY_ITEM_TYPE_COUNT, 1
    .fill ITEM_ID_CAPACITY - ITEM_TYPE_COUNT, 0
.assert "id_known capacity", it_unknown_desc - id_known, ITEM_ID_CAPACITY

.const IUK_FIXED  = 0
.const IUK_POTION = $10
.const IUK_SCROLL = $20
.const IUK_RING   = $30
.const IUK_WAND   = $40
.const IUK_STAFF  = $50
.const IUK_CLASS_MASK = $f0
.const IUK_INDEX_MASK = $0f

// Packed unknown-description metadata: high nibble = class, low nibble = class-local index.
// Fixed rows render their real name/color even if a bad save marks them unknown.
it_unknown_desc:
    .fill 17, IUK_FIXED
    .byte IUK_POTION | 0, IUK_POTION | 1, IUK_POTION | 2
    .byte IUK_SCROLL | 0, IUK_SCROLL | 1, IUK_SCROLL | 2
    .byte IUK_RING | 0, IUK_RING | 1
    .byte IUK_POTION | 3, IUK_POTION | 4, IUK_POTION | 5, IUK_POTION | 6
    .byte IUK_POTION | 7, IUK_POTION | 8, IUK_POTION | 9
    .byte IUK_SCROLL | 3, IUK_SCROLL | 4, IUK_SCROLL | 5, IUK_SCROLL | 6
    .byte IUK_SCROLL | 7, IUK_SCROLL | 8, IUK_SCROLL | 9
    .byte IUK_WAND | 0, IUK_WAND | 1, IUK_WAND | 2, IUK_WAND | 3
    .byte IUK_STAFF | 0, IUK_STAFF | 1, IUK_STAFF | 2, IUK_STAFF | 3
    .fill ITEM_TYPE_COUNT - 47, IUK_FIXED
.assert "it_unknown_desc size", potion_shuffle - it_unknown_desc, ITEM_TYPE_COUNT

// Shuffle tables: map category-local index → description index
// 12 potions, 12 scrolls, 4 rings — full pool shuffled, first N used
potion_shuffle: .fill 12, 0
scroll_shuffle: .fill 12, 0
ring_shuffle:   .fill 4, 0
wand_shuffle:   .fill 5, 0
staff_shuffle:  .fill 5, 0

// Unidentified name strings (screen codes, null-terminated)
pn_0:  .byte ITOK_A_SPACE ; .text "Blue" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_1:  .byte ITOK_A_SPACE ; .text "Red" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_2:  .byte ITOK_A_SPACE ; .text "Green" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_3:  .byte ITOK_A_SPACE ; .text "Yellow" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_4:  .byte ITOK_A_SPACE ; .text "Clear" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_5:  .byte ITOK_AN_SPACE ; .text "Azure" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_6:  .byte ITOK_A_SPACE ; .text "Smoky" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_7:  .byte ITOK_A_SPACE ; .text "Brown" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_8:  .byte ITOK_A_SILVER ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_9:  .byte ITOK_A_SPACE ; .text "Pink" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_10: .text "a" ; .byte ITOK_CLOUD_SUFFIX ; .text "y" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_11: .byte ITOK_A_SPACE ; .byte ITOK_GOLD ; .text "en" ; .byte ITOK_POTION_SUFFIX ; .byte 0

sn_0:  .byte ITOK_A_SPACE ; .text "White " ; .byte ITOK_SCROLL ; .byte 0
sn_1:  .byte ITOK_A_SPACE ; .text "Brown " ; .byte ITOK_SCROLL ; .byte 0
sn_2:  .byte ITOK_A_SPACE ; .text "Grey " ; .byte ITOK_SCROLL ; .byte 0
sn_3:  .byte ITOK_A_SPACE ; .text "Faded " ; .byte ITOK_SCROLL ; .byte 0
sn_4:  .byte ITOK_A_SPACE ; .text "Glowing " ; .byte ITOK_SCROLL ; .byte 0
sn_5:  .byte ITOK_SCROLL_OF_ART ; .text "Lumen" ; .byte 0
sn_6:  .byte ITOK_SCROLL_OF_ART ; .text "Veritas" ; .byte 0
sn_7:  .byte ITOK_SCROLL_OF_ART ; .text "Dura" ; .byte 0
sn_8:  .byte ITOK_SCROLL_OF_ART ; .text "Libera" ; .byte 0
sn_9:  .byte ITOK_SCROLL_OF_ART ; .text "Acuta" ; .byte 0
sn_10: .byte ITOK_SCROLL_OF_ART ; .text "Ferox" ; .byte 0
sn_11: .byte ITOK_SCROLL_OF_ART ; .text "Tutela" ; .byte 0

rn_0: .byte ITOK_A_SPACE ; .byte ITOK_GOLD ; .byte ITOK_RING_SUFFIX ; .byte 0
rn_1: .byte ITOK_A_SILVER ; .byte ITOK_RING_SUFFIX ; .byte 0
rn_2: .text "a Bronze" ; .byte ITOK_RING_SUFFIX ; .byte 0
rn_3: .byte ITOK_A_COPPER ; .byte ITOK_RING_SUFFIX ; .byte 0

// Pointer tables for unidentified names
potion_name_lo:
    .byte <pn_0, <pn_1, <pn_2, <pn_3, <pn_4, <pn_5
    .byte <pn_6, <pn_7, <pn_8, <pn_9, <pn_10, <pn_11
potion_name_hi:
    .byte >pn_0, >pn_1, >pn_2, >pn_3, >pn_4, >pn_5
    .byte >pn_6, >pn_7, >pn_8, >pn_9, >pn_10, >pn_11

scroll_name_lo:
    .byte <sn_0, <sn_1, <sn_2, <sn_3, <sn_4, <sn_5
    .byte <sn_6, <sn_7, <sn_8, <sn_9, <sn_10, <sn_11

ring_name_lo: .byte <rn_0, <rn_1, <rn_2, <rn_3
ring_name_hi: .byte >rn_0, >rn_1, >rn_2, >rn_3

.assert "Scroll unidentified names stay within two pages", floor(sn_11 / 256) - floor(sn_0 / 256) <= 1, true

// Unidentified color tables (indexed by shuffle output)
potion_colors:
    .byte COL_BLUE, COL_LRED, COL_GREEN, COL_YELLOW, COL_WHITE, COL_CYAN
    .byte COL_GREY, COL_BROWN, COL_LGREY, COL_LRED, COL_WHITE, COL_YELLOW
scroll_colors:
    .byte COL_WHITE, COL_BROWN, COL_GREY, COL_LGREY, COL_LGREEN, COL_CYAN
    .byte COL_BLUE, COL_ORANGE, COL_PURPLE, COL_LRED, COL_RED, COL_YELLOW
ring_colors:   .byte COL_YELLOW, COL_LGREY, COL_BROWN, COL_ORANGE

// Wand identification
wn_0: .byte ITOK_AN_SPACE ; .text "Iron " ; .byte ITOK_WAND ; .byte 0
wn_1: .byte ITOK_A_COPPER ; .text " " ; .byte ITOK_WAND ; .byte 0
wn_2: .byte ITOK_A_SILVER ; .text " " ; .byte ITOK_WAND ; .byte 0
wn_3: .byte ITOK_A_SPACE ; .text "Bone " ; .byte ITOK_WAND ; .byte 0
wn_4: .byte ITOK_AN_SPACE ; .text "Oak " ; .byte ITOK_WAND ; .byte 0

wand_name_lo: .byte <wn_0, <wn_1, <wn_2, <wn_3, <wn_4
wand_name_hi: .byte >wn_0, >wn_1, >wn_2, >wn_3, >wn_4
wand_colors:  .byte COL_LGREY, COL_ORANGE, COL_WHITE, COL_LGREY, COL_BROWN

// Staff identification
sfn_0: .byte ITOK_A_SPACE ; .text "Birch " ; .byte ITOK_STAFF ; .byte 0
sfn_1: .byte ITOK_A_SPACE ; .text "Pine " ; .byte ITOK_STAFF ; .byte 0
sfn_2: .byte ITOK_A_SPACE ; .text "Maple " ; .byte ITOK_STAFF ; .byte 0
sfn_3: .byte ITOK_A_SPACE ; .text "Willow " ; .byte ITOK_STAFF ; .byte 0
sfn_4: .byte ITOK_AN_SPACE ; .text "Ash " ; .byte ITOK_STAFF ; .byte 0

staff_name_lo: .byte <sfn_0, <sfn_1, <sfn_2, <sfn_3, <sfn_4
staff_name_hi: .byte >sfn_0, >sfn_1, >sfn_2, >sfn_3, >sfn_4
staff_colors:  .byte COL_WHITE, COL_BROWN, COL_ORANGE, COL_LGREEN, COL_LGREY

// ============================================================
// item_init_identification — Reset id_known and shuffle tables
// Called once at new game start.
// Clobbers: A, X, Y
// ============================================================
item_init_identification:
    // Clear the full save runway, then mark implemented fixed-description IDs known.
    ldx #ITEM_ID_CAPACITY - 1
    lda #0
!iid_clear:
    sta id_known,x
    dex
    bpl !iid_clear-
    ldx #0
!iid_default:
    lda it_unknown_desc,x
    and #IUK_CLASS_MASK
    bne !iid_next+
    lda #1
    sta id_known,x
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

// ============================================================
// item_get_name_ptr — Get name string pointer for an item type
// Input: A = item type ID
// Output: zp_ptr0 = pointer to null-terminated name string
// Clobbers: A, X, Y
// ============================================================
item_get_name_ptr:
    tax
    // Check if this type is known
    lda id_known,x
    beq !ignp_unknown+
    jmp !ignp_known+

    // Unknown — look up randomized description
!ignp_unknown:
    stx item_display_id
    lda it_unknown_desc,x
    and #IUK_CLASS_MASK
    cmp #IUK_POTION
    beq !ignp_potion+
    cmp #IUK_SCROLL
    beq !ignp_scroll+
    cmp #IUK_RING
    beq !ignp_ring+
    cmp #IUK_WAND
    beq !ignp_wand+
    cmp #IUK_STAFF
    beq !ignp_staff+
    jmp !ignp_known+

!ignp_staff:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda staff_shuffle,x
    tax
    lda staff_name_lo,x
    sta zp_ptr0
    lda staff_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_potion:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda potion_shuffle,x            // Shuffled description index
    tax
    lda potion_name_lo,x
    sta zp_ptr0
    lda potion_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_scroll:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda scroll_shuffle,x
    tax
    lda scroll_name_lo,x
    sta zp_ptr0
    lda #>sn_0
    ldy zp_ptr0
    cpy #<sn_0
    bcs !ignp_scroll_same_page+
    adc #1
!ignp_scroll_same_page:
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_ring:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda ring_shuffle,x
    tax
    lda ring_name_lo,x
    sta zp_ptr0
    lda ring_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_wand:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda wand_shuffle,x
    tax
    lda wand_name_lo,x
    sta zp_ptr0
    lda wand_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

    // Fallback (shouldn't happen): return real name
!ignp_known:
    stx item_display_id
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_category_x
#else
    lda it_category,x
#endif
    cmp #ICAT_POTION
    beq !ignp_potion_prefix+
    cmp #ICAT_SCROLL
    beq !ignp_scroll_prefix+
    cmp #ICAT_RING
    beq !ignp_ring_prefix+
    cmp #ICAT_BOOK
    beq !ignp_book_prefix+
!ignp_raw_known:
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    jsr item_load_known_name_ptr
#else
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
#endif
#if C128_PRODUCT_OVERLAY_RUNTIME
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
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    jsr item_load_known_name_ptr
#else
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
#endif
#if C128_PRODUCT_OVERLAY_RUNTIME
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
idgp_mage_book_prefix:   .text "Spellbook " ; .byte 0
idgp_priest_book_prefix: .text "Holy Book of Prayers " ; .byte 0
item_display_id: .byte 0

#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
// item_load_known_name_ptr — Resolve a known-name stream pointer without the
// resident high-byte table. Name streams are emitted in item-ID order, so a
// low-byte wrap between adjacent entries means the stream crossed a page.
// Input: X = item type ID
// Output: zp_ptr0/zp_ptr0_hi = tokenized known-name stream
// Clobbers: A, Y
item_load_known_name_ptr:
    stx item_display_id
    lda it_name_lo,x
    sta zp_ptr0
    lda #>itn_0
    sta zp_ptr0_hi
    txa
    beq !ilkn_done+
    ldy #0
!ilkn_loop:
    lda it_name_lo + 1,y
    cmp it_name_lo,y
    bcs !ilkn_same_page+
    inc zp_ptr0_hi
!ilkn_same_page:
    iny
    cpy item_display_id
    bcc !ilkn_loop-
!ilkn_done:
    rts
#endif

// Decode an item-name token stream from zp_ptr0 into item_name_decode_buf.
// Bytes below $80 copy literally; bytes $80+ index item_name_token_lo/hi.
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
    beq !idnp_done+
    bmi !idnp_token+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    inc item_name_src_idx
    bne !idnp_loop-
!idnp_token:
    and #$7f
    tax
    lda item_name_token_lo,x
    sta zp_ptr1
    lda item_name_token_hi,x
    sta zp_ptr1_hi
    ldy #0
!idnp_copy_token:
    lda (zp_ptr1),y
    beq !idnp_token_done+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    iny
    bne !idnp_copy_token-
!idnp_token_done:
    inc item_name_src_idx
    bne !idnp_loop-
!idnp_done:
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

#if C128_PRODUCT_OVERLAY_RUNTIME
// C128 known item-name streams live in Bank 1 DB RAM. Token strings remain in
// Bank 0 resident item data, so only source stream reads use the MMU helper.
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
    jsr mmu_safe_db_read_ptr0
    beq !idnp_done+
    bmi !idnp_token+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    inc item_name_src_idx
    bne !idnp_loop-
!idnp_token:
    and #$7f
    tax
    lda item_name_token_lo,x
    sta zp_ptr1
    lda item_name_token_hi,x
    sta zp_ptr1_hi
    ldy #0
!idnp_copy_token:
    lda (zp_ptr1),y
    beq !idnp_token_done+
    ldx item_name_dst_idx
    sta item_name_decode_buf,x
    inc item_name_dst_idx
    iny
    bne !idnp_copy_token-
!idnp_token_done:
    inc item_name_src_idx
    bne !idnp_loop-
!idnp_done:
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
#endif

.const ITEM_NAME_DECODE_BUF_SIZE = 48
item_name_decode_buf: .fill ITEM_NAME_DECODE_BUF_SIZE, 0
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
    lda id_known,x
    bne !igfc_known+

    // Unknown — return randomized color
    stx item_display_id
    lda it_unknown_desc,x
    and #IUK_CLASS_MASK
    cmp #IUK_POTION
    beq !igfc_potion+
    cmp #IUK_SCROLL
    beq !igfc_scroll+
    cmp #IUK_RING
    beq !igfc_ring+
    cmp #IUK_WAND
    beq !igfc_wand+
    cmp #IUK_STAFF
    beq !igfc_staff+
    jmp !igfc_known+

!igfc_staff:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda staff_shuffle,x
    tax
    lda staff_colors,x
    rts

!igfc_known:
#if HAL_PLATFORM_ITEM_CATALOG_BANKED
    jsr item_load_color_x
#else
    lda it_color,x
#endif
    rts

!igfc_potion:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda potion_shuffle,x
    tax
    lda potion_colors,x
    rts

!igfc_scroll:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda scroll_shuffle,x
    tax
    lda scroll_colors,x
    rts

!igfc_ring:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda ring_shuffle,x
    tax
    lda ring_colors,x
    rts

!igfc_wand:
    ldx item_display_id
    lda it_unknown_desc,x
    and #IUK_INDEX_MASK
    tax
    lda wand_shuffle,x
    tax
    lda wand_colors,x
    rts
