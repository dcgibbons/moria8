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

// Shuffle tables: map category-local index → description index
// 12 potions, 12 scrolls, 4 rings — full pool shuffled, first N used
potion_shuffle: .fill 12, 0
scroll_shuffle: .fill 12, 0
ring_shuffle:   .fill 4, 0
wand_shuffle:   .fill 5, 0
staff_shuffle:  .fill 5, 0

// Unidentified name strings (screen codes, null-terminated)
pn_0:  .text "a Blue" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_1:  .text "a Red" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_2:  .text "a Green" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_3:  .text "a Yellow" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_4:  .text "a Clear" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_5:  .text "an Azure" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_6:  .text "a Smoky" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_7:  .text "a Brown" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_8:  .byte ITOK_A_SILVER ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_9:  .text "a Pink" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_10: .text "a" ; .byte ITOK_CLOUD_SUFFIX ; .text "y" ; .byte ITOK_POTION_SUFFIX ; .byte 0
pn_11: .text "a " ; .byte ITOK_GOLD ; .text "en" ; .byte ITOK_POTION_SUFFIX ; .byte 0

sn_0:  .text "a White " ; .byte ITOK_SCROLL ; .byte 0
sn_1:  .text "a Brown " ; .byte ITOK_SCROLL ; .byte 0
sn_2:  .text "a Grey " ; .byte ITOK_SCROLL ; .byte 0
sn_3:  .text "a Faded " ; .byte ITOK_SCROLL ; .byte 0
sn_4:  .text "a Glowing " ; .byte ITOK_SCROLL ; .byte 0
sn_5:  .byte ITOK_SCROLL_OF_ART ; .text "Lumen" ; .byte 0
sn_6:  .byte ITOK_SCROLL_OF_ART ; .text "Veritas" ; .byte 0
sn_7:  .byte ITOK_SCROLL_OF_ART ; .text "Dura" ; .byte 0
sn_8:  .byte ITOK_SCROLL_OF_ART ; .text "Libera" ; .byte 0
sn_9:  .byte ITOK_SCROLL_OF_ART ; .text "Acuta" ; .byte 0
sn_10: .byte ITOK_SCROLL_OF_ART ; .text "Ferox" ; .byte 0
sn_11: .byte ITOK_SCROLL_OF_ART ; .text "Tutela" ; .byte 0

rn_0: .text "a " ; .byte ITOK_GOLD ; .byte ITOK_RING_SUFFIX ; .byte 0
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
wn_0: .text "an Iron " ; .byte ITOK_WAND ; .byte 0
wn_1: .byte ITOK_A_COPPER ; .text " " ; .byte ITOK_WAND ; .byte 0
wn_2: .byte ITOK_A_SILVER ; .text " " ; .byte ITOK_WAND ; .byte 0
wn_3: .text "a Bone " ; .byte ITOK_WAND ; .byte 0
wn_4: .text "an Oak " ; .byte ITOK_WAND ; .byte 0

wand_name_lo: .byte <wn_0, <wn_1, <wn_2, <wn_3, <wn_4
wand_name_hi: .byte >wn_0, >wn_1, >wn_2, >wn_3, >wn_4
wand_colors:  .byte COL_LGREY, COL_ORANGE, COL_WHITE, COL_LGREY, COL_BROWN

// Staff identification
sfn_0: .text "a Birch " ; .byte ITOK_STAFF ; .byte 0
sfn_1: .text "a Pine " ; .byte ITOK_STAFF ; .byte 0
sfn_2: .text "a Maple " ; .byte ITOK_STAFF ; .byte 0
sfn_3: .text "a Willow " ; .byte ITOK_STAFF ; .byte 0
sfn_4: .text "an Ash " ; .byte ITOK_STAFF ; .byte 0

staff_name_lo: .byte <sfn_0, <sfn_1, <sfn_2, <sfn_3, <sfn_4
staff_name_hi: .byte >sfn_0, >sfn_1, >sfn_2, >sfn_3, >sfn_4
staff_colors:  .byte COL_WHITE, COL_BROWN, COL_ORANGE, COL_LGREEN, COL_LGREY

// ============================================================
// item_init_identification — Reset id_known and shuffle tables
// Called once at new game start.
// Clobbers: A, X, Y
// ============================================================
item_init_identification:
    // Reset id_known: types 0-16 = known(1), 17-46 = unknown(0), 47-48 = known(1)
    ldx #16
    lda #1
!iid_known_1:
    sta id_known,x
    dex
    bpl !iid_known_1-
    ldx #17
    lda #0
!iid_unknown:
    sta id_known,x
    inx
    cpx #47                     // Up to type 46 (inclusive)
    bcc !iid_unknown-
    ldx #47
    lda #1
!iid_known_2:
    sta id_known,x
    inx
    cpx #ITEM_TYPE_COUNT
    bcc !iid_known_2-

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
    cpx #20
    bcc !ignp_potion_low+
    cpx #23
    bcc !ignp_scroll_low+
    cpx #25
    bcc !ignp_ring+
    cpx #32
    bcc !ignp_potion_high+
    cpx #39
    bcc !ignp_scroll_high+
    cpx #43
    bcc !ignp_wand+

!ignp_staff:
    // Local index = type - 43
    txa
    sec
    sbc #43
    tax
    lda staff_shuffle,x
    tax
    lda staff_name_lo,x
    sta zp_ptr0
    lda staff_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_potion_high:
    txa
    sec
    sbc #22                        // 25-31 -> 3-9
    tax
    bcs !ignp_potion_have_idx+
!ignp_potion_low:
    txa
    sec
    sbc #17                        // 17-19 -> 0-2
    tax
!ignp_potion_have_idx:
    lda potion_shuffle,x            // Shuffled description index
    tax
    lda potion_name_lo,x
    sta zp_ptr0
    lda potion_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_scroll_high:
    txa
    sec
    sbc #29                        // 32-38 -> 3-9
    tax
    bcs !ignp_scroll_have_idx+
!ignp_scroll_low:
    txa
    sec
    sbc #20                        // 20-22 -> 0-2
    tax
!ignp_scroll_have_idx:
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
    // Local index = type - 23
    txa
    sec
    sbc #23
    tax
    lda ring_shuffle,x
    tax
    lda ring_name_lo,x
    sta zp_ptr0
    lda ring_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr

!ignp_wand:
    // Local index = type - 39
    txa
    sec
    sbc #39
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
    lda it_category,x
    cmp #ICAT_POTION
    beq !ignp_potion_prefix+
    cmp #ICAT_SCROLL
    beq !ignp_scroll_prefix+
    cmp #ICAT_RING
    beq !ignp_ring_prefix+
    cmp #ICAT_BOOK
    beq !ignp_book_prefix+
!ignp_raw_known:
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr
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
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
    jmp item_decode_name_ptr_at_dst

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

item_name_decode_buf: .fill HD_DECODE_BUF_SIZE, 0
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
    cpx #20
    bcc !igfc_potion_low+
    cpx #23
    bcc !igfc_scroll_low+
    cpx #25
    bcc !igfc_ring+
    cpx #32
    bcc !igfc_potion_high+
    cpx #39
    bcc !igfc_scroll_high+
    cpx #43
    bcc !igfc_wand+

!igfc_staff:
    txa
    sec
    sbc #43
    tax
    lda staff_shuffle,x
    tax
    lda staff_colors,x
    rts

!igfc_known:
    lda it_color,x
    rts

!igfc_potion_high:
    txa
    sec
    sbc #22
    tax
    bcs !igfc_potion_have_idx+
!igfc_potion_low:
    txa
    sec
    sbc #17
    tax
!igfc_potion_have_idx:
    lda potion_shuffle,x
    tax
    lda potion_colors,x
    rts

!igfc_scroll_high:
    txa
    sec
    sbc #29
    tax
    bcs !igfc_scroll_have_idx+
!igfc_scroll_low:
    txa
    sec
    sbc #20
    tax
!igfc_scroll_have_idx:
    lda scroll_shuffle,x
    tax
    lda scroll_colors,x
    rts

!igfc_ring:
    txa
    sec
    sbc #23
    tax
    lda ring_shuffle,x
    tax
    lda ring_colors,x
    rts

!igfc_wand:
    txa
    sec
    sbc #39
    tax
    lda wand_shuffle,x
    tax
    lda wand_colors,x
    rts
