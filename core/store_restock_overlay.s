#importonce
// store_restock_overlay.s — Store initialization/restocking.
//
// Owner: ChestOverlay (OVL_CHEST) on all seven ports (C64, C128, Plus/4,
// Apple IIe, Commander X16, Atari 8-bit, BBC Master 128).
// Lifetime: one transition call per new game (store_init_all), town re-entry
// (store_restock_all), or wizard jump to town.
// Callers: resident tramp_store_init_all / tramp_store_restock_all when no
// TownOverlay frame is on the stack; ego rolls go through
// tramp_roll_ego_type_chest (which reloads OVL_CHEST where ego_items.s lives
// in OVL_ITEMS) before returning to resident transition code.

#import "store_meta_macros.s"
#import "item_stack_macros.s"

// Stock choices: VMS store_choice (values.inc, indexing inventory_init) for
// the General Store, Temple and Alchemy shop (26 entries each); the other
// stores pick by category. Page-1 entries (>= ITEM_PAGE_SIZE) store their
// Page-1 slot_lo (id - ITEM_PAGE_SIZE) in the contiguous slice
// [sro_choices_p1_start, sro_choices_p1_end).
sro_choices:
// General Store: 15 of 26 food (Ration x8, Hard Biscuit x3, Beef Jerky x2,
// Fine Ale, Fine Wine), Flask of Oil x2, Wooden Torch x3, Brass Lantern,
// Iron Spike x2, Shovel, Pick, Cloak: 26 entries (all Page 0).
sro_general_choice:
    .byte ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD
    .byte ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_RATION_OF_FOOD
    .byte ITEM_SLOT_HARD_BISCUIT, ITEM_SLOT_HARD_BISCUIT, ITEM_SLOT_HARD_BISCUIT
    .byte ITEM_SLOT_STRIP_OF_BEEF_JERKY, ITEM_SLOT_STRIP_OF_BEEF_JERKY
    .byte ITEM_SLOT_PINT_OF_FINE_ALE, ITEM_SLOT_PINT_OF_FINE_WINE
    .byte ITEM_SLOT_FLASK_OF_OIL, ITEM_SLOT_FLASK_OF_OIL
    .byte ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_BRASS_LANTERN
    .byte ITEM_SLOT_IRON_SPIKE, ITEM_SLOT_IRON_SPIKE, ITEM_SLOT_SHOVEL, ITEM_SLOT_PICK, ITEM_SLOT_CLOAK
.const SRO_GENERAL_CHOICES = * - sro_general_choice
// Temple: Prayer books 1-4 (Words of Wisdom x2), Remove Curse x2, Blessing,
// Cure Light x3, Serious x3, Critical x2, Heroism, Boldness, Word of Recall x2,
// Restore Wisdom, Restore Life Levels, Neutralize Poison, Morningstar, Mace,
// War Hammer: 26 entries (23 Page 0, 3 Page 1).
sro_temple_choice:
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_CHANTS_AND_BLESSINGS
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_EXORCISM
    .byte ITEM_SLOT_HOLY_BOOK_OF_PRAYERS_WORDS_OF_WISDOM
    .byte ITEM_SLOT_SCROLL_OF_REMOVE_CURSE, ITEM_SLOT_SCROLL_OF_REMOVE_CURSE
    .byte ITEM_SLOT_SCROLL_OF_BLESSING
    .byte ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    .byte ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS, ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS, ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS
    .byte ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS, ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS
    .byte ITEM_SLOT_POTION_OF_HEROISM, ITEM_SLOT_POTION_OF_BOLDNESS
    .byte ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL
    .byte ITEM_SLOT_POTION_OF_RESTORE_WISDOM, ITEM_SLOT_POTION_OF_RESTORE_LIFE_LEVELS
    .byte ITEM_SLOT_POTION_OF_NEUTRALIZE_POISON
sro_choices_p1_start:
    .byte ITEM_SLOT_MORNINGSTAR, ITEM_SLOT_MACE, ITEM_SLOT_WAR_HAMMER
sro_choices_p1_end:
.const SRO_TEMPLE_CHOICES = * - sro_temple_choice
// Alchemy shop (values.inc:1679): Enchant Weapon To-Hit, Enchant Weapon To-Dam,
// Enchant Armor, Identify x2, Light x2, Phase Door x2, Magic Mapping x2,
// Treasure Detection x2, Object Detection x2, Detect Invisible, Recharging,
// Restore Str/Int/Dex/Con/Chr, Word of Recall x3, Slow Poison: 26 entries (all Page 0).
sro_alchemy_choice:
    .byte ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_HIT
    .byte ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_DAM
    .byte ITEM_SLOT_SCROLL_OF_ENCHANT_ARMOR
    .byte ITEM_SLOT_SCROLL_OF_IDENTIFY, ITEM_SLOT_SCROLL_OF_IDENTIFY, ITEM_SLOT_SCROLL_OF_LIGHT, ITEM_SLOT_SCROLL_OF_LIGHT
    .byte ITEM_SLOT_SCROLL_OF_PHASE_DOOR, ITEM_SLOT_SCROLL_OF_PHASE_DOOR
    .byte ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING, ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING
    .byte ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION, ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION
    .byte ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION, ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION
    .byte ITEM_SLOT_SCROLL_OF_DETECT_INVISIBLE, ITEM_SLOT_SCROLL_OF_RECHARGING
    .byte ITEM_SLOT_POTION_OF_RESTORE_STRENGTH
    .byte ITEM_SLOT_POTION_OF_RESTORE_INTELLIGENCE
    .byte ITEM_SLOT_POTION_OF_RESTORE_DEXTERITY
    .byte ITEM_SLOT_POTION_OF_RESTORE_CONSTITUTION
    .byte ITEM_SLOT_POTION_OF_RESTORE_CHARISMA
    .byte ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL
    .byte ITEM_SLOT_POTION_OF_SLOW_POISON
.const SRO_ALCHEMY_CHOICES = * - sro_alchemy_choice
.assert "General Store choices", SRO_GENERAL_CHOICES, 26
.assert "Temple choices", SRO_TEMPLE_CHOICES, 26
.assert "Alchemy choices", SRO_ALCHEMY_CHOICES, 26
.assert "Store choice table indexes in one page", * - sro_choices <= 256, true
.assert "General, Alchemy, and non-weapon Temple choices live on Page 0 while Temple hafted weapons live on Page 1", ITEM_PAGE_RATION_OF_FOOD == 0 && ITEM_PAGE_PINT_OF_FINE_WINE == 0 && ITEM_PAGE_FLASK_OF_OIL == 0 && ITEM_PAGE_BRASS_LANTERN == 0 && ITEM_PAGE_IRON_SPIKE == 0 && ITEM_PAGE_PICK == 0 && ITEM_PAGE_SHOVEL == 0 && ITEM_PAGE_CLOAK == 0 && ITEM_PAGE_HOLY_BOOK_OF_PRAYERS_EXORCISM == 0 && ITEM_PAGE_POTION_OF_INFRAVISION == 0 && ITEM_PAGE_SCROLL_OF_STAR_DESTRUCTION == 0 && ITEM_PAGE_MORNINGSTAR == ITEM_PAGE_BIT && ITEM_PAGE_MACE == ITEM_PAGE_BIT && ITEM_PAGE_WAR_HAMMER == ITEM_PAGE_BIT, true

// Per store 0-4: number of choices (0 = pick by category) and table offset.
.const SRO_CHOICE_STORES = 5
sro_choice_count:
    .byte SRO_GENERAL_CHOICES, 0, 0, SRO_TEMPLE_CHOICES, SRO_ALCHEMY_CHOICES
sro_choice_base:
    .byte sro_general_choice - sro_choices, 0, 0
    .byte sro_temple_choice - sro_choices, sro_alchemy_choice - sro_choices

// Fallback items per store (used when rejection sampling fails; the entries
// of stores with a choice table are unused)
store_fallback:
    .byte ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_LEATHER_ARMOR, ITEM_SLOT_DAGGER, ITEM_SLOT_SCROLL_OF_LIGHT
    .byte ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_RING_OF_PROTECTION, ITEM_SLOT_DAGGER, ITEM_SLOT_RATION_OF_FOOD
store_fallback_page:
    .byte ITEM_PAGE_RATION_OF_FOOD, ITEM_PAGE_LEATHER_ARMOR, ITEM_PAGE_DAGGER, ITEM_PAGE_SCROLL_OF_LIGHT
    .byte ITEM_PAGE_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_PAGE_RING_OF_PROTECTION, ITEM_PAGE_DAGGER, ITEM_PAGE_RATION_OF_FOOD
.assert "store_fallback_page matches store_fallback", (* - store_fallback_page == store_fallback_page - store_fallback) && (store_fallback_page - store_fallback == STORE_COUNT), true

srr_abs_slot:  .byte 0
srr_save_x:    .byte 0
srr_retry:     .byte 0
srr_store_idx: .byte 0
srr_count:     .byte 0
srr_tmp0:      .byte 0
srr_key:       .fill 7, 0
srr_one:       .byte 0              // sro_sell_one: one of a stack at a time

// store_init_all — Empty all store slots and restock
// Called once at game start. Only item ids are cleared: every path that
// fills a slot (stocking, selling, home deposit) writes all of its sro_merge_fields.
// Clobbers: everything
store_init_all:
    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!sia_clr:
    :AuxWriteX(si_item_id)
    dex
    bpl !sia_clr-
    // fall through: stock the empty stores

// store_restock_all — Restock all stores + reset kicked flags
// Skips home (STORE_HOME) — player items persist, no restock.
// Clobbers: everything
store_restock_all:
    ldx #7
    lda #0
!sra_clr_kick:
    sta hg_kicked,x
    dex
    bpl !sra_clr_kick-

    sta srr_store_idx
!sra_loop:
    lda srr_store_idx
    cmp #STORE_COUNT
    bcs !sra_done+
    cmp #STORE_HOME
    beq !sra_skip+
    sta zp_store_idx
    jsr store_restock_one
!sra_skip:
    inc srr_store_idx
    jmp !sra_loop-
!sra_done:
    rts

// store_restock_one — VMS store_maint (store1.inc) for store zp_store_idx:
//   more than STORE_MAX_KEEP items: sell off (count - STORE_MAX_KEEP + 2)
//   fewer than STORE_MIN_KEEP items: stock (STORE_MIN_KEEP - count + 2)
//   otherwise: sell off 1+randint(STORE_TURN_AROUND), stock as many again
// Slots are chosen uniformly among the occupied (sell) or empty (stock) ones.
// First, items sold since the last restock join their stacks: Umoria
// storeCarryItem merges a sale at once, but the C64 town overlay has no room
// for the merge.
// Clobbers: everything
store_restock_one:
    ldx zp_store_idx
    lda store_base_idx,x
    sta srr_retry
!sro_compact:
    ldy srr_retry
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    beq !sro_compact_next+
    jsr sro_merge_slot
!sro_compact_next:
    inc srr_retry
    ldx zp_store_idx
    lda store_base_idx,x
    clc
    adc #STORE_MAX_ITEMS
    cmp srr_retry
    bne !sro_compact-
    jsr sro_count
    cmp #STORE_MAX_KEEP + 1
    bcc !sro_not_over+
    sbc #STORE_MAX_KEEP - 2         // carry set: count - MAX + 2
    bne sro_sell_off                // always taken
!sro_not_over:
    cmp #STORE_MIN_KEEP
    bcs !sro_turnover+
    eor #$ff                        // carry clear: MIN + 2 - count
    adc #STORE_MIN_KEEP + 3
    bne sro_stock                   // always taken
!sro_turnover:
    jsr sro_turn_around
    jsr sro_sell_one
    jsr sro_turn_around
    // fall through: stock 1+randint(STORE_TURN_AROUND)

// sro_stock — Stock A new items into empty slots (fewer if the store fills).
sro_stock:
    sta srr_retry
!sst_loop:
    dec srr_retry
    bmi !sst_done+
    jsr sro_count
    ldy srr_save_x                  // first empty slot
    bmi !sst_done+                  // none: the store is full
    sty srr_abs_slot
    jsr store_pick_item         // A = slot_lo, item_cur_page set
    tax
    jsr id_known_set            // VMS store_carry: identify(), preserves X & page
    txa
    ldy srr_abs_slot
    :AuxWriteY(si_item_id)
    jsr sro_stock_qty           // preserves X
    ldy srr_abs_slot
    :AuxWriteY(si_qty)
    txa
    jsr item_get_category_a     // uses item_cur_page
    jsr sro_set_p1
    ldy srr_abs_slot
    jsr sro_merge_slot
    jmp !sst_loop-
!sst_done:
    rts

// sro_sell_off — Sell off A random occupied slots (fewer if the store runs
// out), whole entries: VMS store_destroy(randint(store_ctr), false), the
// over-stocked branch.
// sro_sell_one — The same, one item at a time: VMS store_destroy(..., true),
// the turnover branch, takes one from a stack and the entry only when it is
// the last. (Umoria storeDestroyItem takes randint(count) of a stack instead;
// VMS is the oracle, and its slow turnover lets food stacks build up.)
// Only the item id of an emptied slot is cleared: stocking and selling rewrite
// every field.
sro_sell_one:
    ldx #1
    .byte $2c                       // bit abs: skips the ldx #0
sro_sell_off:
    ldx #0
    stx srr_one
    sta srr_retry
!sso_loop:
    dec srr_retry
    bmi !sst_done-
    jsr sro_count
    beq !sst_done-
!sso_retry:                         // uniform over occupied slots by rejection
    lda #STORE_MAX_ITEMS
    jsr rng_range
    clc
    adc srr_abs_slot
    tay
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    beq !sso_retry-
    lda srr_one
    beq !sso_empty+                 // over-stocked: the whole entry goes
    :AuxReadY(si_qty)
    sec
    sbc #1
    beq !sso_empty+                 // the last of a stack, or a single item
    :AuxWriteY(si_qty)
    jmp !sso_loop-
!sso_empty:
    lda #FI_EMPTY
    :AuxWriteY(si_item_id)
    jmp !sso_loop-

// sro_merge_slot — The item in store slot Y joins an identical stack in the
// same store, as Umoria storeCarryItem adds a stocked or sold item to the
// stack it matches (kinds that stack only; count capped at STORE_STACK_MAX).
// Slot Y is then emptied.
// Input: Y = slot, zp_store_idx. Clobbers: A, X, Y, srr_save_x, srr_key,
// srr_tmp0
sro_merge_slot:
    .var sro_merge_fields = List().add(si_item_id, si_p1, si_to_hit, si_to_dam, si_meta, si_meta_hi, si_qty)
    sty srr_save_x
    :LoadStorePageY()
    sta item_cur_page
    :AuxReadY(si_item_id)
    tax
    :ItemStacksX(smg_single)
    jmp !smg_stacks+
smg_single:
    rts
!smg_stacks:
    .for (var i = 0; i < sro_merge_fields.size(); i++) {
        :AuxReadY(sro_merge_fields.get(i))
        sta srr_key + i
    }
    ldx zp_store_idx
    lda store_base_idx,x
    tay
    clc
    adc #STORE_MAX_ITEMS
    sta srr_tmp0
!smg_next:
    cpy srr_save_x
    beq !smg_skip+
    // (no stacking kind carries a to-AC)
    .for (var i = 0; i < sro_merge_fields.size() - 1; i++) {
        :AuxReadY(sro_merge_fields.get(i))
        cmp srr_key + i
        bne !smg_skip+
    }
    jmp !smg_merge+
!smg_skip:
    iny
    cpy srr_tmp0
    bcc !smg_next-
    rts
!smg_merge:
    :AuxReadY(si_qty)
    clc
    adc srr_key + sro_merge_fields.size() - 1
    cmp #STORE_STACK_MAX + 1
    bcc !smg_fits+
    lda #STORE_STACK_MAX
!smg_fits:
    :AuxWriteY(si_qty)
    ldy srr_save_x
    lda #FI_EMPTY
    :AuxWriteY(si_item_id)
    rts

// sro_turn_around — A = 1 + randint(STORE_TURN_AROUND) (VMS randint is 1..n)
sro_turn_around:
    lda #STORE_TURN_AROUND
    jsr rng_range
    clc
    adc #2
    rts

// sro_count — A = occupied slots in store zp_store_idx (Z set when none);
// srr_abs_slot = the store's first slot; srr_save_x = its first empty slot,
// or $FF when full.
sro_count:
    ldx zp_store_idx
    lda store_base_idx,x
    sta srr_abs_slot
    tay
    lda #$ff
    sta srr_save_x
    lda #0
    sta srr_count
    ldx #STORE_MAX_ITEMS
!src_loop:
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    bne !src_full+
    lda srr_save_x
    bpl !src_next+
    sty srr_save_x
    bmi !src_next+                  // always taken (srr_save_x was $FF)
!src_full:
    inc srr_count
!src_next:
    iny
    dex
    bne !src_loop-
    lda srr_count
    rts

// sro_stock_qty — How many of item X a store stocks at once: the VMS store
// templates' number (values.inc store items): 5 rations, biscuits, jerky,
// torches and flasks, 3 Fine Ale, Word of Recall and Light, 2 of a few
// potions and scrolls (on Page 0 and Page 1), else 1. Moria8 stocked one of
// everything until 2026-10-26 (M5b playtest). Ammunition: VMS magic_treasure
// gives every stack 7d6 (misc.inc), the store's too (store_create); Moria8
// stocks the average at Umoria's 24-item store cap, as the town overlay has
// no room for the roll (M5d playtest, 2026-10-26).
// Input: X = slot_lo, item_cur_page = 0 or ITEM_PAGE_BIT.
// Output: A = count. Clobbers: Y. Preserves: X.
sro_stock_qty:
    txa
    ldy item_cur_page
    bne !ssq_p1+
    ldy #sro_stack_qty - sro_stack_id
!ssq_loop:
    cmp sro_stack_id - 1,y
    beq !ssq_found+
    dey
    bne !ssq_loop-
!ssq_found:                         // Y = 0: not listed, one
    lda sro_stack_qty,y
    rts
!ssq_p1:
    lda #1
    rts
sro_stack_id:
    .byte ITEM_SLOT_RATION_OF_FOOD, ITEM_SLOT_HARD_BISCUIT, ITEM_SLOT_STRIP_OF_BEEF_JERKY
    .byte ITEM_SLOT_WOODEN_TORCH, ITEM_SLOT_FLASK_OF_OIL
    .byte ITEM_SLOT_PINT_OF_FINE_ALE, ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL, ITEM_SLOT_SCROLL_OF_LIGHT
    .byte ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_SCROLL_OF_IDENTIFY, ITEM_SLOT_POTION_OF_HEROISM
    .byte ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING, ITEM_SLOT_SCROLL_OF_OBJECT_DETECTION, ITEM_SLOT_SCROLL_OF_PHASE_DOOR
    .byte ITEM_SLOT_POTION_OF_BOLDNESS, ITEM_SLOT_POTION_OF_SLOW_POISON
    .byte ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION, ITEM_SLOT_SCROLL_OF_BLESSING, ITEM_SLOT_SCROLL_OF_DETECT_INVISIBLE
    .byte ITEM_SLOT_ARROW, ITEM_SLOT_BOLT, ITEM_SLOT_ROCK, ITEM_SLOT_IRON_SHOT
sro_stack_qty:
    .byte 1                         // not listed
    .byte 5, 5, 5, 5, 5
    .byte 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    .byte 24, 24, 24, 24
.assert "sro_stack tables pair up", sro_stack_qty - sro_stack_id + 1, * - sro_stack_qty
.assert "All sro_stack_id entries live on Page 0", ITEM_PAGE_RATION_OF_FOOD == 0 && ITEM_PAGE_HARD_BISCUIT == 0 && ITEM_PAGE_STRIP_OF_BEEF_JERKY == 0 && ITEM_PAGE_WOODEN_TORCH == 0 && ITEM_PAGE_FLASK_OF_OIL == 0 && ITEM_PAGE_PINT_OF_FINE_ALE == 0 && ITEM_PAGE_POTION_OF_INFRAVISION == 0 && ITEM_PAGE_SCROLL_OF_STAR_DESTRUCTION == 0 && ITEM_PAGE_IRON_SHOT == 0, true
.assert "Stocked ammunition fits a store stack", 24 <= STORE_STACK_MAX, true

// sro_set_p1 — Set p1 and flags for newly stocked item
// Input: A = category, srr_abs_slot = target slot
// Clobbers: A, X, Y
sro_set_p1:
    cmp #ICAT_CLOAK
    beq !sro_enchant+
    cmp #ICAT_WEAPON
    bcc !sro_default+
    cmp #ICAT_BOOTS + 1
    bcc !sro_enchant+
    cmp #ICAT_BOOK
    beq !sro_default+
    cmp #ICAT_RING
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    bne !sro_not_ring+
    jmp !sro_ring+
!sro_not_ring:
#else
    beq !sro_ring+
#endif
    cmp #ICAT_LIGHT
    bne !sro_not_light+
    jmp !sro_light+
!sro_not_light:
    cmp #ICAT_WAND
    bcc !sro_default+
    cmp #ICAT_STAFF + 1
    bcc !sro_charges+
    cmp #ICAT_AMULET
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    bne !sro_default+
    jmp !sro_ring+
#else
    beq !sro_ring+
    jmp !sro_default+
#endif

!sro_default:
    lda #0
    jmp sro_store_p1

!sro_charges:
    lda #6
    jsr rng_range
    clc
    adc #3
    jmp sro_store_p1

!sro_enchant:
    sta srr_count                   // category (free: sro_count recounts)
    jsr sro_bonus_base
    lda srr_count
    cmp #ICAT_WEAPON
    bne !sro_enchant_armor+
!sro_slaying:
    lda srr_tmp0
    :AuxWriteY(si_to_hit)
    lda srr_tmp0
    :AuxWriteY(si_to_dam)
    rts
!sro_enchant_armor:
    lda srr_tmp0
    :AuxWriteY(si_to_ac)
    rts

!sro_ring:
    .assert "All rings and amulets in sro_set_p1 live on Page 1 with Strength..Searching and Wisdom..Charisma contiguous", ITEM_PAGE_RING_OF_STRENGTH == ITEM_PAGE_BIT && ITEM_RING_OF_GAIN_DEXTERITY == ITEM_RING_OF_STRENGTH + 1 && ITEM_RING_OF_GAIN_CONSTITUTION == ITEM_RING_OF_STRENGTH + 2 && ITEM_RING_OF_GAIN_INTELLIGENCE == ITEM_RING_OF_STRENGTH + 3 && ITEM_RING_OF_SPEED == ITEM_RING_OF_STRENGTH + 4 && ITEM_RING_OF_SEARCHING == ITEM_RING_OF_STRENGTH + 5 && ITEM_PAGE_RING_OF_SLAYING == ITEM_PAGE_BIT && ITEM_AMULET_OF_CHARISMA == ITEM_AMULET_OF_WISDOM + 1 && ITEM_PAGE_AMULET_OF_THE_MAGI == ITEM_PAGE_BIT, true
    jsr sro_bonus_base
    lda item_cur_page
    beq !sro_ring_done+
    :AuxReadY(si_item_id)
    cmp #ITEM_SLOT_RING_OF_PROTECTION
    beq !sro_enchant_armor-         // Ring of Protection: AC bonus
    cmp #ITEM_SLOT_RING_OF_SLAYING
    beq !sro_slaying-
    cmp #ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    beq !sro_ring_dam+
    cmp #ITEM_SLOT_RING_OF_INCREASE_TO_HIT
    beq !sro_ring_hit+
    cmp #ITEM_SLOT_AMULET_OF_THE_MAGI
    beq !sro_ring_strength+
    cmp #ITEM_SLOT_RING_OF_STRENGTH
    bcc !sro_ring_done+
    cmp #ITEM_SLOT_RING_OF_SEARCHING + 1
    bcc !sro_ring_strength+
    sec
    sbc #ITEM_SLOT_AMULET_OF_WISDOM
    cmp #2
    bcc !sro_ring_strength+
!sro_ring_done:
    rts
!sro_ring_hit:
    lda srr_tmp0
    :AuxWriteY(si_to_hit)
    rts
!sro_ring_dam:
    lda srr_tmp0
    :AuxWriteY(si_to_dam)
    rts
!sro_ring_strength:
    lda srr_tmp0
    :AuxWriteY(si_p1)
    rts

// sro_bonus_base — srr_tmp0 = bonus 0..2; zero p1/to_hit/to_dam/to_ac and
// mark identified; Y = srr_abs_slot.
sro_bonus_base:
    lda #3
    jsr rng_range
    sta srr_tmp0
    lda #0
    jmp sro_store_p1

!sro_light:
    lda item_cur_page
    bne !sro_light_lantern+
    ldy srr_abs_slot
    :AuxReadY(si_item_id)
    cmp #ITEM_SLOT_WOODEN_TORCH
    beq !sro_light_torch+
!sro_light_lantern:
    lda #LANTERN_MAX_CHARGES
    jmp sro_store_p1
!sro_light_torch:
    lda #134

sro_store_p1:
    ldy srr_abs_slot
    :AuxWriteY(si_p1)
    lda #0
    :AuxWriteY(si_to_hit)
    :AuxWriteY(si_to_dam)
    :AuxWriteY(si_to_ac)
    :StoreStoreMetaY(IF_IDENTIFIED, 0)
    rts

// store_pick_item — Pick a random item suitable for store zp_store_idx
// Output: A = slot_lo (0..254), item_cur_page = 0 or ITEM_PAGE_BIT ($40)
// Clobbers: A, X, Y
store_pick_item:
    ldy zp_store_idx
    cpy #SRO_CHOICE_STORES
    bcs !spi_category+
    lda sro_choice_count,y
    beq !spi_category+              // Armoury, Weaponsmith: by category
    jsr rng_range                   // VMS store_choice; preserves Y, carry clear
    adc sro_choice_base,y
    tax
    lda #0
    cpx #sro_choices_p1_start - sro_choices
    bcc !spi_choice_page+
    cpx #sro_choices_p1_end - sro_choices
    bcs !spi_choice_page+
    lda #ITEM_PAGE_BIT
!spi_choice_page:
    sta item_cur_page
    lda sro_choices,x
    rts
!spi_category:
    lda #STORE_PICK_RETRIES
    sta srr_count                   // free here: sro_count recounts each pass

!spi_loop:
    .assert "All 20 gold types occupy 0..19", ITEM_GOLD_SMALL == 0 && ITEM_GOLD_MITHRIL == 19, true
    lda #<(ITEM_TYPE_COUNT - (ITEM_GOLD_MITHRIL + 1))
    sta zp_temp0
    lda #>(ITEM_TYPE_COUNT - (ITEM_GOLD_MITHRIL + 1))
    sta zp_temp1
    jsr rng_range_word              // zp_temp2/3 in 0..ITEM_TYPE_COUNT-(ITEM_GOLD_MITHRIL+2)
    lda zp_temp2
    clc
    adc #(ITEM_GOLD_MITHRIL + 1)
    ldy zp_temp3
    bcc !spi_no_carry+
    iny
!spi_no_carry:
    jsr item_unpack_id_ay           // A = slot_lo, item_cur_page set
    pha
    jsr item_get_category_a         // uses item_cur_page
#if STORE_CHECK_CAT_DUPLICATED
    jsr check_store_category_restock
#else
    jsr check_store_category
#endif
    bcc !spi_reject+

    pla
    rts

!spi_reject:
    pla
    dec srr_count
    bne !spi_loop-

    ldx zp_store_idx
    lda store_fallback_page,x
    sta item_cur_page
    lda store_fallback,x
    rts

#if STORE_CHECK_CAT_DUPLICATED
#import "store_check_category_macro.s"
check_store_category_restock:
    :CheckStoreCategoryBody()
#endif
