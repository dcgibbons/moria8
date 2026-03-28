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

// Lookup tables: item type ID → local category index ($FF = not that category)
potion_local_idx:
    .fill 17, $ff       // 0-16: not potions
    .byte 0, 1, 2       // 17-19: CLW, Speed, Poison
    .fill 5, $ff        // 20-24: not potions
    .byte 3, 4, 5, 6, 7, 8, 9  // 25-31: CSW, RestMana, Hero, Blind, Conf, DetMon, Infra
    .fill 18, $ff       // 32-48: not potions
    .fill 6, $ff        // 49-54: not potions
    .fill 6, $ff        // 55-60: not potions (books)

scroll_local_idx:
    .fill 20, $ff       // 0-19: not scrolls
    .byte 0, 1, 2       // 20-22: Light, Identify, Teleport
    .fill 2, $ff        // 23-24: not scrolls
    .fill 7, $ff        // 25-31: not scrolls
    .byte 3, 4, 5, 6, 7, 8, 9  // 32-38: WoR, RemCurse, EnchW, EnchA, MonConf, Aggrav, ProtEvil
    .fill 10, $ff       // 39-48: not scrolls
    .fill 6, $ff        // 49-54: not scrolls
    .fill 7, $ff        // 55-61: not scrolls (books + flask)

// Unidentified name strings (screen codes, null-terminated)
pn_0:  .text "a Blue Potion" ; .byte 0
pn_1:  .text "a Red Potion" ; .byte 0
pn_2:  .text "a Green Potion" ; .byte 0
pn_3:  .text "a Yellow Potion" ; .byte 0
pn_4:  .text "a Clear Potion" ; .byte 0
pn_5:  .text "an Azure Potion" ; .byte 0
pn_6:  .text "a Smoky Potion" ; .byte 0
pn_7:  .text "a Brown Potion" ; .byte 0
pn_8:  .text "a Silver Potion" ; .byte 0
pn_9:  .text "a Pink Potion" ; .byte 0
pn_10: .text "a Cloudy Potion" ; .byte 0
pn_11: .text "a Golden Potion" ; .byte 0

sn_0:  .text "a White Scroll" ; .byte 0
sn_1:  .text "a Brown Scroll" ; .byte 0
sn_2:  .text "a Grey Scroll" ; .byte 0
sn_3:  .text "a Faded Scroll" ; .byte 0
sn_4:  .text "a Glowing Scroll" ; .byte 0
sn_5:  .text "a Scroll of Lumen" ; .byte 0
sn_6:  .text "a Scroll of Veritas" ; .byte 0
sn_7:  .text "a Scroll of Dura" ; .byte 0
sn_8:  .text "a Scroll of Libera" ; .byte 0
sn_9:  .text "a Scroll of Acuta" ; .byte 0
sn_10: .text "a Scroll of Ferox" ; .byte 0
sn_11: .text "a Scroll of Tutela" ; .byte 0

rn_0: .text "a Gold Ring" ; .byte 0
rn_1: .text "a Silver Ring" ; .byte 0
rn_2: .text "a Bronze Ring" ; .byte 0
rn_3: .text "a Copper Ring" ; .byte 0

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
scroll_name_hi:
    .byte >sn_0, >sn_1, >sn_2, >sn_3, >sn_4, >sn_5
    .byte >sn_6, >sn_7, >sn_8, >sn_9, >sn_10, >sn_11

ring_name_lo: .byte <rn_0, <rn_1, <rn_2, <rn_3
ring_name_hi: .byte >rn_0, >rn_1, >rn_2, >rn_3

// Unidentified color tables (indexed by shuffle output)
potion_colors:
    .byte COL_BLUE, COL_LRED, COL_GREEN, COL_YELLOW, COL_WHITE, COL_CYAN
    .byte COL_GREY, COL_BROWN, COL_LGREY, COL_LRED, COL_WHITE, COL_YELLOW
scroll_colors:
    .byte COL_WHITE, COL_BROWN, COL_GREY, COL_LGREY, COL_LGREEN, COL_CYAN
    .byte COL_BLUE, COL_ORANGE, COL_PURPLE, COL_LRED, COL_RED, COL_YELLOW
ring_colors:   .byte COL_YELLOW, COL_LGREY, COL_BROWN, COL_ORANGE

// Wand identification
wn_0: .text "an Iron Wand" ; .byte 0
wn_1: .text "a Copper Wand" ; .byte 0
wn_2: .text "a Silver Wand" ; .byte 0
wn_3: .text "a Bone Wand" ; .byte 0
wn_4: .text "an Oak Wand" ; .byte 0

wand_name_lo: .byte <wn_0, <wn_1, <wn_2, <wn_3, <wn_4
wand_name_hi: .byte >wn_0, >wn_1, >wn_2, >wn_3, >wn_4
wand_colors:  .byte COL_LGREY, COL_ORANGE, COL_WHITE, COL_LGREY, COL_BROWN

// Staff identification
sfn_0: .text "a Birch Staff" ; .byte 0
sfn_1: .text "a Pine Staff" ; .byte 0
sfn_2: .text "a Maple Staff" ; .byte 0
sfn_3: .text "a Willow Staff" ; .byte 0
sfn_4: .text "an Ash Staff" ; .byte 0

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

    // Fisher-Yates shuffle: potions (12 elements)
    ldx #11                         // i = 11 down to 1
!iid_pot_loop:
    txa
    clc
    adc #1                          // rng_range(i+1) → [0, i]
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay                             // Y = j = random index
    // Swap potion_shuffle[i] and potion_shuffle[j]
    lda potion_shuffle,x
    pha
    lda potion_shuffle,y
    sta potion_shuffle,x
    pla
    sta potion_shuffle,y
    dex
    bne !iid_pot_loop-

    // Fisher-Yates shuffle: scrolls (12 elements)
    ldx #11
!iid_scr_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    // Swap scroll_shuffle[i] and scroll_shuffle[j]
    lda scroll_shuffle,x
    pha
    lda scroll_shuffle,y
    sta scroll_shuffle,x
    pla
    sta scroll_shuffle,y
    dex
    bne !iid_scr_loop-

    // Fisher-Yates shuffle: rings (4 elements)
    ldx #3
!iid_ring_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    lda ring_shuffle,x
    pha
    lda ring_shuffle,y
    sta ring_shuffle,x
    pla
    sta ring_shuffle,y
    dex
    bne !iid_ring_loop-

    // Fisher-Yates shuffle: wands (5 elements)
    ldx #4
!iid_wand_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    lda wand_shuffle,x
    pha
    lda wand_shuffle,y
    sta wand_shuffle,x
    pla
    sta wand_shuffle,y
    dex
    bne !iid_wand_loop-

    // Fisher-Yates shuffle: staves (5 elements)
    ldx #4
!iid_staff_loop:
    txa
    clc
    adc #1
    stx iid_save_x
    jsr rng_range
    ldx iid_save_x
    tay
    lda staff_shuffle,x
    pha
    lda staff_shuffle,y
    sta staff_shuffle,x
    pla
    sta staff_shuffle,y
    dex
    bne !iid_staff_loop-

    rts

iid_save_x: .byte 0                // Scratch for Fisher-Yates

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
    bne !ignp_known+

    // Unknown — look up randomized description
    lda it_category,x
    cmp #ICAT_POTION
    beq !ignp_potion+
    cmp #ICAT_SCROLL
    beq !ignp_scroll+
    cmp #ICAT_RING
    beq !ignp_ring+
    cmp #ICAT_WAND
    beq !ignp_wand+
    cmp #ICAT_STAFF
    beq !ignp_staff+

    // Fallback (shouldn't happen): return real name
!ignp_known:
    lda it_name_lo,x
    sta zp_ptr0
    lda it_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_potion:
    lda potion_local_idx,x          // Local index for this potion type
    tax
    lda potion_shuffle,x            // Shuffled description index
    tax
    lda potion_name_lo,x
    sta zp_ptr0
    lda potion_name_hi,x
    sta zp_ptr0_hi
    rts

!ignp_scroll:
    lda scroll_local_idx,x          // Local index for this scroll type
    tax
    lda scroll_shuffle,x
    tax
    lda scroll_name_lo,x
    sta zp_ptr0
    lda scroll_name_hi,x
    sta zp_ptr0_hi
    rts

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
    rts

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
    rts

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
    rts

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
    lda it_category,x
    cmp #ICAT_POTION
    beq !igfc_potion+
    cmp #ICAT_SCROLL
    beq !igfc_scroll+
    cmp #ICAT_RING
    beq !igfc_ring+
    cmp #ICAT_WAND
    beq !igfc_wand+
    cmp #ICAT_STAFF
    beq !igfc_staff+

!igfc_known:
    lda it_color,x
    rts

!igfc_potion:
    lda potion_local_idx,x
    tax
    lda potion_shuffle,x
    tax
    lda potion_colors,x
    rts

!igfc_scroll:
    lda scroll_local_idx,x
    tax
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

!igfc_staff:
    txa
    sec
    sbc #43
    tax
    lda staff_shuffle,x
    tax
    lda staff_colors,x
    rts
