#importonce
// item.s — Item data structures, floor items, inventory, and gold spawning
//
// Phase 6.1: Master item type table (SoA), floor item table at $CF00,
// inventory/equipment table, and subroutines for managing both.
// Gold spawning on dungeon floors.

#import "input_ui_helpers.s"

// ============================================================
// Item Category Constants live in item_defs.s (imported early everywhere)
// ============================================================

// Item system constants (IF_*, FI_*, EQUIP_*, inventory sizes)
// are defined in item_defs.s (imported early in build order)

#import "item_tables.s"

// ============================================================
// Floor Item Table — 42 slots packed into $CF00-$CFFB (252 bytes)
// ============================================================
// Layout:
//   fi_item_id[42]  item type ($ff = empty)
//   fi_x[42]        map X
//   fi_y[42]        map Y
//   fi_qty[42]      quantity / gold amount lo
//   fi_p1[42]       p1 for non-gold, gold amount hi for gold
//   fi_meta[42]     IF_* flags (bits 0-3)
.label fi_item_id = FLOOR_ITEM_BASE + 0
.label fi_x       = fi_item_id + MAX_FLOOR_ITEMS
.label fi_y       = fi_x + MAX_FLOOR_ITEMS
.label fi_qty     = fi_y + MAX_FLOOR_ITEMS
.label fi_p1      = fi_qty + MAX_FLOOR_ITEMS
.label fi_meta    = fi_p1 + MAX_FLOOR_ITEMS
.assert "Floor item table fits in platform floor-item page", fi_meta + MAX_FLOOR_ITEMS <= FLOOR_ITEM_BASE + 256, true

// ============================================================
// Inventory Table — TOTAL_INV_SLOTS slots: 22 carried, then equipment
// (EQUIP_WEAPON..EQUIP_RING2, EQUIP_CLOAK, EQUIP_SECONDARY)
// ============================================================
inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_qty:     .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0     // bit 6 = ITEM_PAGE_BIT, bits 0-5 = ego ID

// Split stat & page+ego sidecars for floor slots. The packed floor table
// intentionally stays inside its fixed 256-byte page; fi_meta_hi MUST sit outside it.
fi_to_hit:   .fill MAX_FLOOR_ITEMS, 0
fi_to_dam:   .fill MAX_FLOOR_ITEMS, 0
fi_to_ac:    .fill MAX_FLOOR_ITEMS, 0
fi_meta_hi:  .fill MAX_FLOOR_ITEMS, 0   // bit 6 = ITEM_PAGE_BIT, bits 0-5 = ego ID

glyph_x:      .fill MAX_GLYPHS, 0
glyph_y:      .fill MAX_GLYPHS, 0
glyph_active: .fill MAX_GLYPHS, 0

// ============================================================
// Scratch & running state variables
// ============================================================
fi_add_x:   .byte 0       // Position for floor_item_add
fi_add_y:   .byte 0
fi_add_id:  .byte 0       // Paged item slot_lo (0..254)
fi_add_qty: .byte 0       // Quantity / gold amount
fi_add_qty_hi: .byte 0    // Gold qty high byte (auto-reset after add)
fi_add_p1:  .byte 0       // Charges/fuel/type-specific p1
fi_add_to_hit: .byte 0    // Split item to-hit
fi_add_to_dam: .byte 0    // Split item to-damage
fi_add_to_ac:  .byte 0    // Split item to-AC
fi_add_ego: .byte 0       // Packed (ITEM_PAGE_BIT | ego_id)
isl_target: .byte 0       // item_spawn_level loop target
isl_idx:    .byte 0       // item_spawn_level loop counter
inven_weight_lo: .byte 0  // Running 16-bit inventory+equipment weight (0.1 lb)
inven_weight_hi: .byte 0
iac_lo:     .byte 0       // Weight-check candidate total lo (InvAddCarriedBody)
iac_hi:     .byte 0       // Weight-check candidate total hi

// ============================================================
// Subroutines
// ============================================================

// fi_add_clear_plain_meta — clear metadata for plain/generated items
// Clears qty_hi plus non-quantity metadata so fresh generated items do not
// inherit stale state from prior item-generation flows.
// Preserves: nothing
fi_add_clear_plain_meta:
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    rts

// floor_item_get_qty_hi_x — Get 16-bit gold high byte for floor slot X
// Output: A = qty_hi for Page-0 gold items (#0/#1), 0 for non-gold
floor_item_get_qty_hi_x:
    lda fi_meta_hi,x
    and #ITEM_PAGE_BIT
    bne !fi_qty_zero+
    lda fi_item_id,x
    cmp #2
    bcc !fi_get_qty_hi_gold+
!fi_qty_zero:
    lda #0
    rts
!fi_get_qty_hi_gold:
    lda fi_p1,x
    rts

// floor_item_get_p1_x — Get p1/charges for non-gold floor slot X
// Output: A = p1 for non-gold, 0 for Page-0 gold (#0/#1)
floor_item_get_p1_x:
    lda fi_meta_hi,x
    and #ITEM_PAGE_BIT
    bne !fi_get_p1_ok+
    lda fi_item_id,x
    cmp #2
    bcs !fi_get_p1_ok+
    lda #0
    rts
!fi_get_p1_ok:
    lda fi_p1,x
    rts

// floor_item_get_flags_x — Unpack IF_* flags from floor slot X
// Output: A = flags (0..$0F)
floor_item_get_flags_x:
    lda fi_meta,x
    and #ITEM_META_FLAGS_MASK
    rts

// floor_item_get_ego_x — Read packed (ITEM_PAGE_BIT | ego_id) from floor slot X
// Output: A = packed page+ego byte
floor_item_get_ego_x:
    lda fi_meta_hi,x
    rts

// item_init_floor — Clear all floor item slots
// Sets all fi_item_id to $FF, zp_item_count = 0
// Clobbers: A, X
item_init_floor:
    ldx #MAX_FLOOR_ITEMS - 1
    lda #FI_EMPTY
!iif_loop:
    sta fi_item_id,x
    lda #0
    sta fi_x,x
    sta fi_y,x
    sta fi_qty,x
    sta fi_p1,x
    sta fi_meta,x
    lda #FI_EMPTY
    dex
    bpl !iif_loop-
    lda #0
    sta zp_item_count
    ldx #MAX_FLOOR_ITEMS - 1
    lda #0
!iif_stat_loop:
    sta fi_to_hit,x
    sta fi_to_dam,x
    sta fi_to_ac,x
    sta fi_meta_hi,x
    dex
    bpl !iif_stat_loop-
    jmp glyph_clear_all

// item_init_inventory — Clear all inventory/equipment slots and reset weight
// Clobbers: A, X
item_init_inventory:
    ldx #TOTAL_INV_SLOTS - 1
!iiv_loop:
    jsr inv_clear_slot
    dex
    bpl !iiv_loop-
    lda #0
    sta inven_weight_lo
    sta inven_weight_hi
    rts

// floor_item_add — Add an item to the floor item table
// Input: fi_add_x/y/id/qty/p1/to_hit/to_dam/to_ac/flags/ego
// Output: carry set = success (X = slot), carry clear = table full
// Clobbers: A, X, Y, zp_ptr0
floor_item_add:
    // Find first empty slot
    ldx #0
!fia_scan:
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fia_found+
    inx
    cpx #MAX_FLOOR_ITEMS
    bne !fia_scan-
    clc
    rts

!fia_found:
    // Write all fields
    lda fi_add_id
    sta fi_item_id,x
    lda fi_add_x
    sta fi_x,x
    lda fi_add_y
    sta fi_y,x
    lda fi_add_qty
    sta fi_qty,x
    lda fi_add_ego
    and #ITEM_PAGE_BIT
    bne !fia_non_gold+
    lda fi_add_id
    cmp #2
    bcc !fia_gold_hi+
!fia_non_gold:
    lda fi_add_p1
    sta fi_p1,x
    jmp !fia_store_meta+
!fia_gold_hi:
    lda fi_add_qty_hi
    sta fi_p1,x
!fia_store_meta:
    lda fi_add_flags
    and #ITEM_META_FLAGS_MASK
    sta fi_meta,x
    lda fi_add_ego
    sta fi_meta_hi,x
    lda fi_add_to_hit
    sta fi_to_hit,x
    lda fi_add_to_dam
    sta fi_to_dam,x
    lda fi_add_to_ac
    sta fi_to_ac,x
    lda #0
    sta fi_add_qty_hi       // Auto-reset for non-gold callers

    // Set FLAG_HAS_ITEM on map tile at (x, y)
    stx zp_temp4                // Save slot index
    ldy fi_add_y
    jsr map_row_ptr0_y
    ldy fi_add_x
    :MapRead_ptr0_y()
    ora #FLAG_HAS_ITEM
    :MapWrite_ptr0_y()
    ldx zp_temp4                // Restore slot index

    // Increment floor item count
    inc zp_item_count

    sec                         // Success
    rts

// floor_item_remove — Remove floor item at slot X
// Input: X = slot index
// Clears FLAG_HAS_ITEM on map if no other item at same position.
// Clobbers: A, Y, zp_ptr0, zp_temp4
floor_item_remove:
    // Save position before clearing
    lda fi_x,x
    sta fi_add_x                // Reuse scratch for saved x
    lda fi_y,x
    sta fi_add_y                // Reuse scratch for saved y

    // Mark slot empty
    lda #FI_EMPTY
    sta fi_item_id,x
    lda #0
    sta fi_qty,x
    sta fi_p1,x
    sta fi_meta,x
    sta fi_to_hit,x
    sta fi_to_dam,x
    sta fi_to_ac,x
    sta fi_meta_hi,x

    // Decrement count
    dec zp_item_count

    // Check if any other item shares the same (x, y)
    stx zp_temp4                // Save removed slot index
    ldx #0
!fir_scan:
    cpx #MAX_FLOOR_ITEMS
    bcs !fir_clear_flag+        // No other item found — clear flag
    cpx zp_temp4
    beq !fir_next+              // Skip the just-removed slot
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fir_next+
    lda fi_x,x
    cmp fi_add_x
    bne !fir_next+
    lda fi_y,x
    cmp fi_add_y
    bne !fir_next+
    // Found another item at same position — keep flag
    ldx zp_temp4                // Restore X
    rts
!fir_next:
    inx
    jmp !fir_scan-

!fir_clear_flag:
    // Clear FLAG_HAS_ITEM on map tile
    ldy fi_add_y
    jsr map_row_ptr0_y
    ldy fi_add_x
    :MapRead_ptr0_y()
    and #~FLAG_HAS_ITEM & $ff
    :MapWrite_ptr0_y()
    ldx zp_temp4                // Restore X
    rts

// floor_item_find_at — Find a floor item at map position
// Input: A = map_x, Y = map_y
// Output: carry set = found (X = slot), carry clear = not found
// Clobbers: X
// Does NOT use zp_ptr0 (uses absolute indexed addressing into $CF00+)
floor_item_find_at:
    sta fi_add_x                // Stash search x
    sty fi_add_y                // Stash search y
    ldx #MAX_FLOOR_ITEMS - 1
!fifa_loop:
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fifa_next+
    lda fi_x,x
    cmp fi_add_x
    bne !fifa_next+
    lda fi_y,x
    cmp fi_add_y
    bne !fifa_next+
    // Found
    rts
!fifa_next:
    dex
    bpl !fifa_loop-
!fifa_miss:
    clc
    rts

// chest_find_at_df_target — Is the floor item at (df_target_x, df_target_y)
// a chest? Resident pre-dispatch helper for the chest overlay routing
// (docs/CHEST_DESIGN.md): Open checks it from cmd_open; Bash/Disarm check it
// from their overlay command bodies after direction resolution.
// Output: carry set = chest (X = floor slot), carry clear = no chest there
// Clobbers: A, Y (X preserved as the floor slot on a hit)
chest_find_at_df_target:
    lda df_target_x
    ldy df_target_y
    jsr floor_item_find_at
    bcc !cfdt_done+             // No floor item — carry already clear
    jsr item_get_category_floor_x
    cmp #ICAT_CHEST
    beq !cfdt_done+             // CMP equal sets carry
    clc
!cfdt_done:
    rts

glyph_clear_all:
    lda #0
    ldx #MAX_GLYPHS - 1
!gca_loop:
    sta glyph_active,x
    dex
    bpl !gca_loop-
    rts

glyph_find_at:
    sta fi_add_x
glyph_find_at_stashed:
    ldx #MAX_GLYPHS - 1
!gfa_loop:
    lda glyph_active,x
    beq !gfa_next+
    lda glyph_x,x
    cmp fi_add_x
    bne !gfa_next+
    tya
    cmp glyph_y,x
    beq !gfa_hit+
!gfa_next:
    dex
    bpl !gfa_loop-
!gfa_miss:
    clc
    rts
!gfa_hit:
    rts

glyph_add_at:
    sty fi_add_y
    jsr glyph_find_at
    bcs !gaa_done+
    ldx #0
!gaa_scan:
    lda glyph_active,x
    beq !gaa_store+
    inx
    cpx #MAX_GLYPHS
    bcc !gaa_scan-
!gaa_full:
    clc
    rts
!gaa_store:
    lda fi_add_x
    sta glyph_x,x
    lda fi_add_y
    sta glyph_y,x
    lda #1
    sta glyph_active,x
!gaa_done:
    sec
    rts

glyph_remove:
    lda #0
    sta glyph_active,x
    rts

#if !INV_ADD_EXTERNAL
#import "inv_add.s"
#endif

// inv_consume_one — Use one item of inventory slot X: a stack shrinks by one;
// the last one (or a zero-quantity record from an older save) frees the slot.
// Preserves: X, Y. Clobbers: A (calls inv_remove_item which preserves Y)
inv_consume_one:
    lda inv_qty,x
    cmp #2
    bcc inv_remove_item
    jsr inven_sub_one_slot_x
    dec inv_qty,x
    rts

// inv_remove_item — Remove item from inventory slot X
// Carried slots compact after removal; equipment clears in place.
// Input: X = slot index (0..TOTAL_INV_SLOTS-1)
// Preserves: Y. Clobbers: A, X
inv_remove_item:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !iri_skip_wt+
    jsr inven_sub_slot_x
!iri_skip_wt:
    cpx #MAX_INV_SLOTS - 1
    bcs inv_clear_slot
!iri_shift_loop:
    lda inv_item_id + 1,x
    sta inv_item_id,x
    lda inv_qty + 1,x
    sta inv_qty,x
    lda inv_p1 + 1,x
    sta inv_p1,x
    lda inv_to_hit + 1,x
    sta inv_to_hit,x
    lda inv_to_dam + 1,x
    sta inv_to_dam,x
    lda inv_to_ac + 1,x
    sta inv_to_ac,x
    lda inv_flags + 1,x
    sta inv_flags,x
    lda inv_ego + 1,x
    sta inv_ego,x
    inx
    cpx #MAX_INV_SLOTS - 1
    bcc !iri_shift_loop-
// inv_clear_slot — Empty inventory slot X. Preserves: X, Y. Clobbers: A
inv_clear_slot:
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_qty,x
    sta inv_p1,x
    sta inv_to_hit,x
    sta inv_to_dam,x
    sta inv_to_ac,x
    sta inv_flags,x
    sta inv_ego,x
    rts

// ============================================================
// Running 16-bit Inventory Weight Helpers (in 0.1 lb units)
// ZP-free BSS arithmetic; safe for overlays and inventory callers.
// ============================================================

iw_qty:     .byte 0
iw_mc_lo:   .byte 0
iw_mc_hi:   .byte 0
iw_mc_2:    .byte 0
iw_res_0:   .byte 0
iw_res_1:   .byte 0
iw_res_2:   .byte 0
iw_save_x:  .byte 0

// inven_mul_item_qty — Multiply 16-bit weight of (item_cur_page, A) by iw_qty.
// Output: iw_res_0/1/2 = 24-bit weight; carry set if iw_res_2 != 0 (>= 65536).
// Preserves: X, Y. Clobbers: A.
inven_mul_item_qty:
    stx iw_save_x
    tax
    jsr item_get_weight_x           // sets icat_weight_lo/hi; preserves X, Y
    lda #0
    sta iw_res_0
    sta iw_res_1
    sta iw_res_2
    sta iw_mc_2
    lda icat_weight_lo
    sta iw_mc_lo
    lda icat_weight_hi
    sta iw_mc_hi
    ldx #8
!im_loop:
    lsr iw_qty
    bcc !im_skip+
    clc
    lda iw_res_0
    adc iw_mc_lo
    sta iw_res_0
    lda iw_res_1
    adc iw_mc_hi
    sta iw_res_1
    lda iw_res_2
    adc iw_mc_2
    sta iw_res_2
!im_skip:
    asl iw_mc_lo
    rol iw_mc_hi
    rol iw_mc_2
    dex
    bne !im_loop-
    ldx iw_save_x
    lda iw_res_2
    beq !im_fit+
    sec
    rts
!im_fit:
    clc
    rts

// inven_calc_fi_add_weight — Candidate total weight = inven_weight + fi_add_qty * wt(fi_add).
// Output: iac_lo/hi updated; carry set on 16-bit overflow.
// Preserves: X, Y. Clobbers: A.
inven_calc_fi_add_weight:
    lda fi_add_ego
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda fi_add_qty
    sta iw_qty
    lda fi_add_id
    jsr inven_mul_item_qty
    bcs !icw_ov+
    lda iw_res_0
    clc
    adc inven_weight_lo
    sta iac_lo
    lda iw_res_1
    adc inven_weight_hi
    sta iac_hi
!icw_ov:
    rts

// inven_add_fi_add_weight — Add fi_add_qty * wt(fi_add) to inven_weight_lo/hi (saturating at $FFFF).
// Preserves: X, Y. Clobbers: A.
inven_add_fi_add_weight:
    jsr inven_calc_fi_add_weight
    bcs !iaw_sat+
    lda iac_lo
    sta inven_weight_lo
    lda iac_hi
    sta inven_weight_hi
    rts
!iaw_sat:
    lda #$ff
    sta inven_weight_lo
    sta inven_weight_hi
    rts

// inven_sub_one_slot_x / inven_sub_slot_x — Subtract 1 or inv_qty[X] item weight from inven_weight_lo/hi.
// Preserves: X, Y. Clobbers: A.
inven_sub_one_slot_x:
    lda #1
    bne !isw_set_qty+
inven_sub_slot_x:
    lda inv_qty,x
!isw_set_qty:
    sta iw_qty
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda inv_item_id,x
    jsr inven_mul_item_qty
    bcs !isw_zero+
    lda inven_weight_lo
    sec
    sbc iw_res_0
    sta inven_weight_lo
    lda inven_weight_hi
    sbc iw_res_1
    sta inven_weight_hi
    bcs !isw_done+
!isw_zero:
    lda #0
    sta inven_weight_lo
    sta inven_weight_hi
!isw_done:
    rts

// inven_recalc_weight — Recompute inven_weight_lo/hi cleanly from all TOTAL_INV_SLOTS.
// Clobbers: A, X, Y.
inven_recalc_weight:
    lda #0
    sta inven_weight_lo
    sta inven_weight_hi
    ldx #TOTAL_INV_SLOTS - 1
!irw_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !irw_next+
    lda inv_qty,x
    beq !irw_next+
    sta iw_qty
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda inv_item_id,x
    jsr inven_mul_item_qty
    bcs !irw_sat+
    lda inven_weight_lo
    clc
    adc iw_res_0
    sta inven_weight_lo
    lda inven_weight_hi
    adc iw_res_1
    sta inven_weight_hi
    bcc !irw_next+
!irw_sat:
    lda #$ff
    sta inven_weight_lo
    sta inven_weight_hi
!irw_next:
    dex
    bpl !irw_loop-
    rts

#if C64_UNIT_TEST || C128_UNIT_TEST
// inv_count_items — Count used carried slots (0-21). No product caller; the
// unit tests keep it (test_item.s).
// Output: A = count
// Clobbers: X
inv_count_items:
    ldx #0
!ici_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ici_done+
    inx
    cpx #MAX_INV_SLOTS
    bcc !ici_loop-
!ici_done:
    txa
    rts
#endif

#if ITEM_SPAWN_IN_GEN_OVERLAY
// The port runs this from OVL.GEN behind a resident item_spawn_level
// trampoline (BBC Master: resident image headroom); the picker is then
// called directly in the loaded overlay.
:ItemSpawnSegment()
#endif
// ============================================================
// item_spawn_level — Spawn gold and items on the dungeon floor
// Called after monster_spawn_level at each level transition.
// Phase 1: Gold (2 + rng(3) + dlvl/2, cap 16)
// Phase 2: Non-gold items (1 + rng(2) + dlvl/3, cap 8)
// Phase 3: Treasure room (dlvl >= 3, one room gets extra items)
// Town = 0 items.
// Clobbers: everything
// ============================================================
isl_ngold_target: .byte 0      // Non-gold item count target
isl_treasure_dlvl: .byte 0     // Effective dlvl for treasure room enchant

#if ITEM_SPAWN_IN_GEN_OVERLAY
item_spawn_level_gen:
#else
item_spawn_level:
#endif
    jsr item_init_floor

    // Town = no items
    lda zp_player_dlvl
    bne !isl_dungeon+
    rts

!isl_dungeon:
    // ---- Phase 1: Gold ----
    // Base count = 2
    lda #2
    sta isl_target

    // + rng(3) → [0, 2]
    lda #3
    jsr rng_range
    clc
    adc isl_target
    sta isl_target

    // + dlvl / 2
    lda zp_player_dlvl
    lsr                         // A = dlvl / 2
    clc
    adc isl_target
    sta isl_target

    // Cap at 16
    cmp #17
    bcc !isl_gold_capped+
    lda #16
    sta isl_target
!isl_gold_capped:

    lda #0
    sta isl_idx

!isl_gold_loop:
    lda isl_idx
    cmp isl_target
    bcs !isl_gold_done+

    // Find a random floor tile
    jsr find_random_floor
    bcc !isl_gold_done+

    // Set up floor item add
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Gold type: rng(2) → ID 0 or 1
    lda #2
    jsr rng_range
    sta fi_add_id
    jsr fi_add_clear_plain_meta

    // Gold qty: rng_range_word(dlvl * 10) + 5 (16-bit)
    lda zp_player_dlvl
    ldx #10
    jsr math_multiply           // zp_math_a=lo, zp_math_b=hi
    lda zp_math_a
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1                // N = dlvl * 10
    jsr rng_range_word          // result in zp_temp2/3
    // Add 5 to 16-bit result
    lda zp_temp2
    clc
    adc #5
    sta fi_add_qty
    lda zp_temp3
    adc #0
    sta fi_add_qty_hi

    jsr floor_item_add
    // Ignore failure (table full)

    inc isl_idx
    jmp !isl_gold_loop-

!isl_gold_done:

    // ---- Phase 2: Non-gold items ----
    // Count: 1 + rng(2) + dlvl/3, cap 8
    lda #1
    sta isl_ngold_target

    lda #2
    jsr rng_range               // [0, 1]
    clc
    adc isl_ngold_target
    sta isl_ngold_target

    // + dlvl / 3 (approximate: dlvl * 85 / 256 ≈ dlvl/3)
    // Simple approach: subtract 3 repeatedly
    lda zp_player_dlvl
    ldx #0
!isl_div3:
    cmp #3
    bcc !isl_div3_done+
    sec
    sbc #3
    inx
    jmp !isl_div3-
!isl_div3_done:
    txa
    clc
    adc isl_ngold_target
    sta isl_ngold_target

    // Cap at 8
    cmp #9
    bcc !isl_ngold_capped+
    lda #8
    sta isl_ngold_target
!isl_ngold_capped:

    lda #0
    sta isl_idx

!isl_ngold_loop:
    lda isl_idx
    cmp isl_ngold_target
    bcs !isl_ngold_done+

    // Find a random floor tile
    jsr find_random_floor
    bcc !isl_ngold_done+
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Pick item type
#if ITEM_SPAWN_IN_GEN_OVERLAY
    jsr pick_item_type_overlay
#else
    jsr pick_item_type
#endif
    jsr isl_roll_item           // id, enchantment, ego

    // Set qty: ammo spawns in stacks, everything else = 1
    lda #1
    sta fi_add_qty
    lda fi_add_ego
    and #ITEM_PAGE_BIT
    sta item_cur_page
    ldx fi_add_id
    jsr item_get_missile
    bpl !isl_qty_done+          // Bit 7 clear = not ammo
    // Ammo: qty = 7d6 → [7, 42] (VMS magic_treasure, misc.inc)
    lda #7
    ldx #6
    ldy #0
    jsr math_dice
    lda zp_math_a
    sta fi_add_qty
!isl_qty_done:

    jsr floor_item_add          // a full table skips it

    inc isl_idx
    jmp !isl_ngold_loop-

!isl_ngold_done:

    // ---- Phase 3: Treasure room ----
    // Only on dlvl >= 3
    lda zp_player_dlvl
    cmp #3
    bcs !isl_has_treasure+
    jmp !isl_all_done+
!isl_has_treasure:

    // Check for vault room → enhanced treasure
    lda #RT_VAULT
    jsr tramp_find_special_room
    bcc !isl_no_vault+

    // Vault: use vault room, dlvl+8, 4-8 items
    stx isl_idx
    lda zp_player_dlvl
    clc
    adc #8                      // dlvl+8
    sta isl_treasure_dlvl
    lda #5
    jsr rng_range               // [0, 4]
    clc
    adc #4                      // [4, 8]
    sta isl_ngold_target
    jmp !isl_treasure_setup_done+

!isl_no_vault:
    // Spawn nest gold if applicable (no-op if no nest)
    jsr tramp_spawn_nest_gold

    // Normal treasure room (pick random room)
    lda room_count
    bne !isl_has_rooms+
    jmp !isl_all_done+
!isl_has_rooms:
    jsr rng_range               // [0, room_count-1]
    sta isl_idx                 // Reuse as room index

    // Effective dlvl for treasure = dlvl + 5
    lda zp_player_dlvl
    clc
    adc #5
    sta isl_treasure_dlvl

    // Extra items: 2 + rng(3)
    lda #3
    jsr rng_range               // [0, 2]
    clc
    adc #2                      // [2, 4]
    sta isl_ngold_target        // Reuse as treasure count

!isl_treasure_setup_done:
    lda #0
    sta isl_target              // Reuse as treasure loop counter

!isl_treasure_loop:
    lda isl_target
    cmp isl_ngold_target
    bcs !isl_all_done+

    // Random position within room bounds
    // x = room_x[idx] + rng(room_w[idx])
    ldx isl_idx
    lda room_w,x
    jsr rng_range
    ldx isl_idx
    clc
    adc room_x,x
    sta fi_add_x

    // y = room_y[idx] + rng(room_h[idx])
    ldx isl_idx
    lda room_h,x
    jsr rng_range
    ldx isl_idx
    clc
    adc room_y,x
    sta fi_add_y

    // Verify it's a floor tile
    ldy fi_add_y
    jsr map_row_ptr0_y
    ldy fi_add_x
    :MapRead_ptr0_y()
    and #$f0                    // TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !isl_treasure_skip+

    // Pick item with boosted dlvl
    // Temporarily boost dlvl for pick + enchant
    lda zp_player_dlvl
    pha                         // Save real dlvl
    lda isl_treasure_dlvl
    sta zp_player_dlvl

#if ITEM_SPAWN_IN_GEN_OVERLAY
    jsr pick_item_type_overlay
#else
    jsr pick_item_type
#endif
    jsr isl_roll_item           // id, enchantment, ego

    pla                         // Restore real dlvl
    sta zp_player_dlvl

    lda #1
    sta fi_add_qty

    jsr floor_item_add          // a full table skips it

!isl_treasure_skip:
    inc isl_target
    jmp !isl_treasure_loop-

!isl_all_done:
    rts

// isl_roll_item — A = the item type picked: store it, roll its enchantment
// (roll_enchantment also sets the fi_add_* stat fields and flags) and its ego
// type (0 for non-weapons).
isl_roll_item:
    sta fi_add_id
    lda item_cur_page
    sta isl_page
    jsr roll_enchantment
    sta fi_add_p1
    lda isl_page
    sta item_cur_page
    lda fi_add_id
#if HAL_PLATFORM_CHEST_LOOT_EGO_GEN_TRAMP
    // A2/CX16: generation executes in the GEN overlay window; the ego trampoline
    // must restore it or the item_spawn_level continuation runs OVL.ITEMS.
    jsr tramp_roll_ego_type_gen
#else
    jsr tramp_roll_ego_type
#endif
    ora isl_page
    sta fi_add_ego
    rts
isl_page: .byte 0
#if ITEM_SPAWN_IN_GEN_OVERLAY
:ItemSpawnRestoreSegment()
#endif

// ============================================================
// Pickup and Drop
// ============================================================

// item_pickup — Pick up item at player's position
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
#if HAL_PLATFORM_ITEM_PICKUP_OVERLAY
// The port runs this from its items overlay behind a resident
// tramp_item_pickup (Atari 8-bit: Default resident headroom).
:ItemPickupSegment()
#endif
item_pickup:
    // Find item at player position
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcs !ipu_found+

    // Nothing here
    ldx #HSTR_IPU_NOTHING
    jsr huff_print_msg
    clc
    rts

!ipu_found:
    // X = floor slot index. Save it.
    stx ipu_slot

    // Check if it's gold
    jsr item_get_category_floor_x
    cmp #ICAT_GOLD
    bne !ipu_not_gold+

    // --- Gold pickup ---
    // Add 16-bit fi_qty/fi_qty_hi to 24-bit player gold. Fetch the high byte
    // first: floor_item_get_qty_hi_x compares, which would drop the carry.
    ldx ipu_slot
    jsr floor_item_get_qty_hi_x
    sta zp_temp1
    lda player_data + PL_GOLD_0
    clc
    adc fi_qty,x
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc zp_temp1
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #0
    sta player_data + PL_GOLD_2
    :GoldCapOnCarry()

    // Build message: "You found N gold pieces."
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_IPU_FOUND
    jsr huff_append_combat

    ldx ipu_slot
    lda fi_qty,x
    sta zp_temp0
    jsr floor_item_get_qty_hi_x
    sta zp_temp1
    jsr combat_append_decimal_16

    ldx #HSTR_IPU_GOLD
    jsr huff_append_combat

    // Null-terminate
    jsr cmb_term_and_print

    // Remove from floor
    ldx ipu_slot
    jsr floor_item_remove

    lda #SFX_PICKUP
    jsr hal_sound_play

    sec
    rts

!ipu_not_gold:
    // --- Non-gold item pickup ---
    // Copy item to inventory: a full pack still takes one that stacks (VMS
    // inven_check_num, Umoria inventoryCanCarryItemCount)
    ldx ipu_slot
    lda fi_item_id,x
    sta fi_add_id
    lda fi_qty,x
    sta fi_add_qty
    jsr floor_item_get_p1_x
    sta fi_add_p1
    lda fi_to_hit,x
    sta fi_add_to_hit
    lda fi_to_dam,x
    sta fi_add_to_dam
    lda fi_to_ac,x
    sta fi_add_to_ac
    jsr floor_item_get_flags_x
    sta fi_add_flags                // Preserve floor item flags (IF_CURSED etc.)
    jsr floor_item_get_ego_x
    sta fi_add_ego
#if HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL
    jsr tramp_inv_add_carried       // the weight limit, then a slot (VMS carry)
#else
    jsr inv_add_carried             // the weight limit, then a slot (VMS carry)
#endif
    bcs !ipu_added+
    jsr huff_print_msg              // X = the refusal: too heavy or the pack full
    clc
    rts

!ipu_added:

    // Build message: "You picked up a <name>."
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_IPU_PICKED
    jsr huff_append_combat

    lda fi_add_id
    jsr item_append_desc

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    // Null-terminate
    jsr cmb_term_and_print

    // Remove from floor
    ldx ipu_slot
    jsr floor_item_remove

    lda #SFX_PICKUP
    jsr hal_sound_play

    sec
    rts
#if HAL_PLATFORM_ITEM_PICKUP_OVERLAY
:ItemPickupRestoreSegment()
#endif

// item_drop — Drop a carried item to the floor (prompted)
// Prompts "Drop which item (a-v)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
item_drop:
    // Print prompt
    lda #$ff
    ldx #HSTR_IDR_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !idr_have_choices+
    clc
    rts
!idr_have_choices:

    jsr input_prepare_followup_key

    // Wait for keypress
    jsr hal_input_get_key

    // '?' shows inventory (all items) and re-prompts
    cmp #$3f
    bne !idr_direct_pick+
    lda #$ff                    // Filter: show all items with real slot letters
    jsr show_inv_and_select

!idr_direct_pick:
    jsr input_normalize_inventory_letter_key

    // Convert PETSCII letter to slot index (A-V = $41-$56 -> 0-21)
    sec
    sbc #$41
    bcc !idr_cancel+
    cmp #MAX_INV_SLOTS
    bcs !idr_cancel+

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !idr_empty+

    // X = inventory slot. Save it.
    stx ipu_slot
    bne !idr_have_item+

    // Empty slot
!idr_empty:
    ldx #HSTR_PIW_NOTHING
    jsr huff_print_msg
    clc
    rts

!idr_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
    rts

!idr_have_item:
    // Set up floor item from inventory data
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    jsr inv_slot_to_fi_add

    jsr floor_item_add
    bcs !idr_placed+

    // Floor full
    ldx #HSTR_IDR_FLOOR_FULL
    jsr huff_print_msg
    clc
    rts

!idr_placed:
    // Remove from inventory
    ldx ipu_slot
    jsr inv_remove_item

    // Build message: "You drop a <name>."
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_IDR_DROP
    jsr huff_append_combat

    lda fi_add_id
    jsr item_append_desc

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    // Null-terminate
    jsr cmb_term_and_print

    lda #SFX_PICKUP
    jsr hal_sound_play

    sec
    rts

// item_append_name — Append item type name to combat_msg_buf
// Input: A = item type ID
// Uses item_get_name_ptr for identification-aware name resolution.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
// inv_slot_to_fi_add — Copy inventory slot X into the fi_add_* scratch
// (item_append_desc, floor_item_add and inv_add_item read it).
// Output: A = item id. Preserves X, Y.
inv_slot_to_fi_add:
    lda inv_qty,x
    sta fi_add_qty
    lda inv_p1,x
    sta fi_add_p1
    lda inv_to_hit,x
    sta fi_add_to_hit
    lda inv_to_dam,x
    sta fi_add_to_dam
    lda inv_to_ac,x
    sta fi_add_to_ac
    lda inv_flags,x
    sta fi_add_flags
    lda inv_ego,x
    sta fi_add_ego
    lda inv_item_id,x
    sta fi_add_id
    rts

// fi_add_to_inv_slot — Write the fi_add_* scratch into inventory slot X.
// Preserves X, Y.
fi_add_to_inv_slot:
    lda fi_add_id
    sta inv_item_id,x
    lda fi_add_qty
    sta inv_qty,x
    lda fi_add_p1
    sta inv_p1,x
    lda fi_add_to_hit
    sta inv_to_hit,x
    lda fi_add_to_dam
    sta inv_to_dam,x
    lda fi_add_to_ac
    sta inv_to_ac,x
    lda fi_add_flags
    sta inv_flags,x
    lda fi_add_ego
    sta inv_ego,x
    rts

item_append_name:
    sta fi_add_id
    lda fi_add_ego
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda fi_add_id
    jsr item_get_name_ptr           // zp_ptr0 = name string
    lda zp_ptr0
    ldy zp_ptr0_hi
    jsr combat_append_str
    // Append ego suffix if present (reads fi_add_ego set by caller, masked to 6 bits)
    lda fi_add_ego
    and #EGO_ID_MASK
    jmp tramp_ego_append_suffix

// item_append_desc — Append item name plus identified stat suffixes to
// combat_msg_buf. Uses fi_add_* staging fields for the selected instance.
// Input: A = item type ID (slot_lo), fi_add_ego holds (page_bit | ego_id)
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
item_append_desc:
    jsr item_append_name
    lda fi_add_flags
    and #IF_IDENTIFIED
    bne !iad_identified+
    rts
!iad_identified:
    lda fi_add_ego
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda fi_add_id
    jsr item_get_category_a
    cmp #ICAT_WEAPON
    beq !iad_weapon+
    cmp #ICAT_CLOAK
    beq !iad_armor+
    cmp #ICAT_ARMOR
    bcc !iad_done+
    cmp #ICAT_BOOTS + 1
    bcc !iad_armor+
    cmp #ICAT_LIGHT
    beq !iad_turns_tramp+
    cmp #ICAT_RING
    beq !iad_ring_tramp+
    cmp #ICAT_AMULET
    beq !iad_amulet_tramp+
    cmp #ICAT_WAND
    beq !iad_charges_tramp+
    cmp #ICAT_STAFF
    beq !iad_charges_tramp+
!iad_done:
    rts
!iad_ring_tramp:
    jmp !iad_ring+
!iad_amulet_tramp:
    jmp !iad_ring_p1+
!iad_charges_tramp:
    jmp !iad_charges+
!iad_turns_tramp:
    jmp !iad_turns+
!iad_weapon:
    lda fi_add_to_hit
    ora fi_add_to_dam
    bne !iad_weapon_has_bonus+
    rts
!iad_weapon_has_bonus:
    lda #$20
    jsr combat_append_char
    lda #$28
    jsr combat_append_char
    lda fi_add_to_hit
    jsr item_append_signed_combat
    lda #$2c
    jsr combat_append_char
    lda fi_add_to_dam
    jsr item_append_signed_combat
    lda #$29
    jmp combat_append_char
!iad_armor:
    lda #$20
    jsr combat_append_char
    lda #$1b                    // '[' screen code
    jsr combat_append_char
    ldy fi_add_id
    jsr item_get_base_ac
    jsr combat_append_decimal
    lda #$2c
    jsr combat_append_char
    lda fi_add_to_ac
    jsr item_append_signed_combat
    lda #$1d                    // ']' screen code
    jsr combat_append_char
    jmp !iad_ring_p1+           // Crown of the Magi INT; 0 elsewhere
!iad_ring:
    bit item_cur_page
    bvs !iad_ring_p1_chk+
    lda fi_add_id
    cmp #23
    beq !iad_ring_ac+
    cmp #24
    beq !iad_ring_p1+
!iad_ring_p1_chk:
    lda fi_add_to_ac
    bne !iad_ring_ac+
    lda fi_add_to_hit
    ora fi_add_to_dam
    bne !iad_weapon-
    jmp !iad_ring_p1+
!iad_ring_ac:
    lda fi_add_to_ac
    bne !iad_ring_ac_has_bonus+
    rts
!iad_ring_ac_has_bonus:
    lda #$20
    jsr combat_append_char
    lda #$1b                    // '[' screen code
    jsr combat_append_char
    lda fi_add_to_ac
    jsr item_append_signed_combat
    lda #$1d                    // ']' screen code
    jsr combat_append_char
    // fall through to show Ring of WOE p1 if non-zero
!iad_ring_p1:
    lda fi_add_p1
    bne !iad_ring_p1_has_bonus+
    rts
!iad_ring_p1_has_bonus:
    lda #$20
    jsr combat_append_char
    lda #$28
    jsr combat_append_char
    lda fi_add_p1
    jsr item_append_signed_combat
    lda #$29
    jmp combat_append_char
!iad_charges:
    lda #<item_append_charges_str
    ldy #>item_append_charges_str
    jmp item_append_count_suffix_combat
!iad_turns:
    lda #<item_append_turns_str
    ldy #>item_append_turns_str
item_append_count_suffix_combat:
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #$20
    jsr combat_append_char
    lda #$28
    jsr combat_append_char
    lda fi_add_p1
    jsr combat_append_decimal
    lda #$20
    jsr combat_append_char
    lda zp_ptr0
    ldy zp_ptr0_hi
    jsr combat_append_str
    lda #$29
    jmp combat_append_char

item_append_signed_combat:
    sta item_append_signed
    bmi !iasc_negative+
    lda #$2b
    jsr combat_append_char
    lda item_append_signed
    jmp combat_append_decimal
!iasc_negative:
    lda #$2d
    jsr combat_append_char
    lda item_append_signed
    eor #$ff
    clc
    adc #1
    jmp combat_append_decimal

item_append_signed: .byte 0
item_append_charges_str: .text "charges" ; .byte 0
item_append_turns_str: .text "turns" ; .byte 0

// Scratch variables for pickup/drop
ipu_slot: .byte 0              // Floor/inventory slot being processed

// ============================================================
// tunnel_spawn_gold — Spawn gold at a tunneled vein location
// Input: df_target_x/y = position to place gold
// Gold amount scales with dungeon level
// Clobbers: A, X, Y, zp_ptr0, zp_math_a/b, zp_temp0/1/2/3
// ============================================================
tunnel_spawn_gold:
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Gold type: rng(2) → ID 0 or 1 (small or large)
    lda #2
    jsr rng_range
    sta fi_add_id
    jsr fi_add_clear_plain_meta

    // Gold amount: (5 + dlvl*3) base, rng(base)*2 + 1
    // Gives ~6-60 GP on DL1, ~15-170 GP on DL10
    lda zp_player_dlvl
    ldx #3
    jsr math_multiply           // zp_math_a = lo
    lda zp_math_a
    clc
    adc #5                      // base = 5 + dlvl*3
    sta zp_temp0
    jsr rng_range               // rng(base)
    asl                         // × 2
    clc
    adc #1                      // At least 1 GP
    sta fi_add_qty

    jmp floor_item_add
    // Ignore failure (table full)

// ============================================================
// pick_item_type — Select a random non-gold item type for floor spawning
// Uses umoria-faithful depth-bucketed 50/50 flat/best-of-3 algorithm.
// 50% flat pick from level-appropriate pool.
// 50% best-of-3 random picks (highest index wins), then re-roll
//      within the winner's depth tier for uniform intra-tier distribution.
// 1-in-12 "great item" chance sets effective level up toward max.
// Output: A = slot_lo (0..254), item_cur_page ($00 or $40)
// Clobbers: A, X, Y, zp_temp0..zp_temp4
// ============================================================
.const PIT_MAX_LEVEL = 12
.const PIT_SPAWNABLE_COUNT = 349
pit_best_lo: .byte 0
pit_best_hi: .byte 0
pit_tmp:     .byte 0

#if PICKER_IN_CHEST_OVERLAY
.segment ChestOverlay
#elif PLATFORM_PRODUCT_OVERLAY_RUNTIME
.segment DungeonGenOverlay
#endif

// 349 spawnable items (0..369 excluding gold #0/#1/#214..#231 and Ruined Chest #134),
// sorted ascending by min_lvl_m8 (0..12).
pit_sorted_lo:
    // Level 0 (25 items)
    .byte 13, 15, 61, 62, 63, 167, 182, 183, 184, 185, 232, 233, 234, 235, 236, 243
    .byte 244, 245, 246, 15, 16, 17, 18, 19, 40
    // Level 1 (55 items)
    .byte 2, 3, 6, 11, 12, 16, 17, 19, 20, 28, 29, 37, 51, 52, 54, 64
    .byte 77, 85, 98, 99, 103, 114, 135, 136, 161, 162, 186, 187, 188, 189, 190, 191
    .byte 237, 238, 239, 240, 241, 242, 247, 20, 21, 22, 23, 24, 25, 41, 42, 43
    .byte 44, 83, 84, 85, 86, 87, 88
    // Level 2 (50 items)
    .byte 5, 7, 9, 14, 21, 30, 31, 47, 48, 49, 53, 66, 74, 82, 84, 100
    .byte 102, 126, 128, 163, 168, 169, 192, 193, 248, 249, 250, 251, 252, 253, 254, 0
    .byte 45, 46, 47, 48, 62, 63, 64, 65, 66, 67, 68, 69, 70, 89, 94, 95
    .byte 96, 109
    // Level 3 (39 items)
    .byte 4, 18, 22, 25, 36, 39, 43, 44, 46, 50, 65, 70, 86, 88, 115, 164
    .byte 170, 171, 194, 1, 2, 3, 4, 5, 26, 49, 50, 51, 52, 53, 54, 90
    .byte 97, 98, 99, 100, 101, 102, 111
    // Level 4 (31 items)
    .byte 23, 27, 33, 40, 42, 55, 58, 67, 78, 87, 89, 95, 96, 109, 110, 129
    .byte 137, 172, 195, 196, 207, 208, 209, 210, 211, 6, 7, 8, 9, 55, 112
    // Level 5 (30 items)
    .byte 10, 32, 41, 45, 72, 79, 90, 92, 94, 101, 116, 124, 157, 158, 165, 197
    .byte 198, 199, 212, 10, 11, 12, 71, 72, 73, 91, 92, 103, 104, 110
    // Level 6 (6 items)
    .byte 34, 35, 68, 73, 93, 56
    // Level 7 (15 items)
    .byte 8, 26, 71, 80, 91, 122, 130, 173, 174, 13, 27, 28, 29, 93, 105
    // Level 8 (22 items)
    .byte 24, 38, 56, 59, 69, 75, 139, 140, 141, 142, 143, 144, 145, 149, 153, 166
    .byte 175, 200, 14, 74, 75, 76
    // Level 9 (9 items)
    .byte 76, 104, 106, 112, 131, 155, 176, 177, 201
    // Level 10 (20 items)
    .byte 83, 97, 108, 118, 121, 138, 159, 178, 202, 30, 31, 32, 33, 34, 35, 36
    .byte 37, 57, 106, 107
    // Level 11 (14 items)
    .byte 105, 117, 119, 132, 150, 154, 156, 179, 180, 77, 78, 79, 80, 81
    // Level 12 (33 items)
    .byte 57, 60, 81, 107, 111, 113, 120, 123, 125, 127, 133, 146, 147, 148, 151, 152
    .byte 160, 181, 203, 204, 205, 206, 213, 38, 39, 58, 59, 60, 61, 82, 108, 113
    .byte 114
pit_sorted_lo_end:

// Packed page bits (1 bit per sorted index: 1 = Page 1 [255..369], 0 = Page 0)
pit_sorted_hi_bits:
    .byte $00, $00, $f8, $01, $00, $00, $00, $00, $ff, $ff, $00, $00, $00, $80, $ff, $ff
    .byte $03, $00, $e0, $ff, $ff, $01, $00, $00, $fc, $00, $00, $f8, $3f, $08, $e0, $07
    .byte $00, $e0, $01, $00, $f8, $3f, $80, $0f, $00, $00, $f8, $1f
pit_sorted_hi_bits_end:

// Cumulative 16-bit item count per compressed depth tier (0..12)
pit_level_bounds_lo:
    .byte 25, 80, 130, 169, 200, 230, 236, 251, 17, 26, 46, 60, 93
pit_level_bounds_lo_end:
pit_level_bounds_hi:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1
pit_level_bounds_hi_end:
pit_bit_masks:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
pick_item_type_overlay:
#else
pick_item_type:
#endif
    // Compressed level: eff_level = min((dlvl + 3) / 4, PIT_MAX_LEVEL).
    lda zp_player_dlvl
    clc
    adc #3
    lsr
    lsr
    cmp #PIT_MAX_LEVEL + 1
    bcc !pit_level_ok+
    lda #PIT_MAX_LEVEL
!pit_level_ok:
    tay                          // Y = eff_level (preserved by rng_range)

    // Great item, 1 in 12 (none at town level 0)
    lda #12
    jsr rng_range                // [0, 11]
    bne !pit_no_great+
    tya
    beq !pit_no_great+
    lda #PIT_MAX_LEVEL
    jsr rng_range                // [0, 11]
    clc
    adc #1
    sta zp_temp1                 // randint(12)
    tya
    asl
    asl
    sta zp_temp0                 // eff * 4
    asl                          // C clear: eff * 8 <= 96
    adc zp_temp0                 // eff * 12 (<= 144)
    ldy #0
    sec
!pit_great_div:
    iny                          // quotient + 1
    sbc zp_temp1
    bcs !pit_great_div-
    cpy #PIT_MAX_LEVEL + 1
    bcc !pit_no_great+
    ldy #PIT_MAX_LEVEL
!pit_no_great:

    // 16-bit pool_size = pit_level_bounds[eff_level] -> zp_temp0/1
    lda pit_level_bounds_lo,y
    sta zp_temp0
    lda pit_level_bounds_hi,y
    sta zp_temp1

    // 50/50 coin flip: flat pick vs best-of-3
    lda #2
    jsr rng_range
    bne !pit_best_of_3+

    jsr rng_range_word           // [0, pool_size-1] in zp_temp2/3

!pit_return_idx:
    // Decode 16-bit index (zp_temp2=lo, zp_temp3=hi) into (item_cur_page, A=slot_lo)
    lda zp_temp2
    and #$07
    tay
    lda zp_temp2
    sta pit_tmp
    lda zp_temp3
    lsr
    ror pit_tmp
    lsr
    ror pit_tmp
    lsr
    ror pit_tmp
    ldx pit_tmp
    lda pit_sorted_hi_bits,x
    and pit_bit_masks,y
    beq !pit_page0+
    lda #ITEM_PAGE_BIT
    bne !pit_set_page+
!pit_page0:
    lda #0
!pit_set_page:
    sta item_cur_page
    ldx zp_temp2
    lda zp_temp3
    bne !pit_hi_slice+
    lda pit_sorted_lo,x
    rts
!pit_hi_slice:
    lda pit_sorted_lo + 256,x
    rts

!pit_best_of_3:
    jsr rng_range_word
    lda zp_temp2
    sta pit_best_lo
    lda zp_temp3
    sta pit_best_hi

    ldy #2
!pit_bo3_loop:
    sty pit_tmp
    jsr rng_range_word
    lda pit_best_lo
    cmp zp_temp2
    lda pit_best_hi
    sbc zp_temp3
    bcs !pit_bo3_keep+
    lda zp_temp2
    sta pit_best_lo
    lda zp_temp3
    sta pit_best_hi
!pit_bo3_keep:
    ldy pit_tmp
    dey
    bne !pit_bo3_loop-

    // Find winner's depth tier X (0..PIT_MAX_LEVEL) where pit_best < bounds[X]
    ldx #0
!pit_find_tier:
    lda pit_best_lo
    cmp pit_level_bounds_lo,x
    lda pit_best_hi
    sbc pit_level_bounds_hi,x
    bcc !pit_found_tier+
    inx
    cpx #PIT_MAX_LEVEL
    bcc !pit_find_tier-
!pit_found_tier:
    txa
    beq !pit_reroll_l0+
    stx pit_tmp
    lda pit_level_bounds_lo,x
    sec
    sbc pit_level_bounds_lo - 1,x   // Every tier span <= 55 < 256
    jsr rng_range
    ldx pit_tmp
    clc
    adc pit_level_bounds_lo - 1,x
    sta zp_temp2
    lda pit_level_bounds_hi - 1,x
    adc #0
    sta zp_temp3
    jmp !pit_return_idx-

!pit_reroll_l0:
    lda pit_level_bounds_lo
    jsr rng_range
    sta zp_temp2
    lda #0
    sta zp_temp3
    jmp !pit_return_idx-

#if HAL_PLATFORM_PICK_ITEM_RESIDENT_ITEMS_SEGMENT
:ResidentItemsSegment()
#elif HAL_PLATFORM_PICK_ITEM_IN_GEN_OVERLAY
.segment Default
#endif

#if HAL_PLATFORM_PICK_ITEM_PLUS4_BANK_RAM
pick_item_type:
    lda current_overlay
#if PICKER_IN_CHEST_OVERLAY
    cmp #OVL_CHEST
#else
    cmp #OVL_DUNGEON_GEN
#endif
    beq !pit_overlay_loaded+

#if PICKER_IN_CHEST_OVERLAY
    ldx #OVL_CHEST - 1
#else
    ldx #OVL_DUNGEON_GEN - 1
#endif
    jsr overlay_load_disk        // asks for the program disk until it loads
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
    sta current_overlay

!pit_overlay_loaded:
    sei
    jsr plus4_bank_ram
    jsr pick_item_type_overlay
    pha
    jsr plus4_bank_ram
    cli
    pla
    rts
#elif PLATFORM_PRODUCT_OVERLAY_RUNTIME
pick_item_type:
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
    jsr overlay_load
    bcc !pit_overlay_loaded+
    lda #2                      // Fallback to first non-gold type on media error.
    rts
!pit_overlay_loaded:
    sei
    :BankOutKernal()
    jsr pick_item_type_overlay
    pha
    :BankInKernal()
    cli
    pla
    rts
#endif

// ============================================================
// roll_enchantment — Roll enchantment value for a spawned item
// Input: A = item type ID
// Output: A = p1 value for charges/fuel/ring misc bonuses, 0 otherwise
//         fi_add_to_hit/to_dam/to_ac set for combat/armor stats
//         fi_add_flags scratch = IF_CURSED if cursed, else 0
// For lights: returns charge count instead of enchantment.
// For non-equipment: returns 0.
// Clobbers: A, X, Y
// ============================================================
fi_add_flags: .byte 0          // Scratch: flags for floor_item_add
re_bonus_hit: .byte 0
re_bonus_dam: .byte 0
re_bonus_ac:  .byte 0
re_bonus_p1:  .byte 0
re_page:      .byte 0
re_cat:       .byte 0

roll_enchantment:
    sta zp_temp0                // Save slot_lo
    lda item_cur_page
    sta re_page
    lda #0
    sta fi_add_flags            // Default: not cursed
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta re_bonus_hit
    sta re_bonus_dam
    sta re_bonus_ac
    sta re_bonus_p1

    // Check category — lights/wands/staves/chests/tools/equipment
    lda zp_temp0
    jsr item_get_category_a
    sta re_cat

    // Special case: digging tools (ICAT_DIGGING = 0) take catalog p1
    cmp #ICAT_DIGGING
    beq !re_digging+

    // Special case: lights get charges, not enchantment
    cmp #ICAT_LIGHT
    beq !re_light+

    // Special case: books get p1=0
    cmp #ICAT_BOOK
    beq !re_book_far+

    // Special case: wands and staves get charges
    cmp #ICAT_WAND
    beq !re_wand+
    cmp #ICAT_STAFF
    beq !re_staff_far+

    // Special case: chests get source level + trap state
    cmp #ICAT_CHEST
    beq !re_chest_far+

    // Equipment categories: WEAPON(2)..BOOTS(7), RING(12), AMULET(16), CLOAK(19)
    cmp #ICAT_WEAPON
    bcc !re_zero+
    cmp #ICAT_LIGHT
    bcc !re_equip_load+         // WEAPON..BOOTS (2-7) -> enchant
    cmp #ICAT_RING
    beq !re_equip_load+         // RING(12) -> enchant
    cmp #ICAT_AMULET
    beq !re_equip_load+         // AMULET(16) -> enchant
    cmp #ICAT_CLOAK
    beq !re_equip_load+         // CLOAK(19) -> enchant
!re_zero:
    lda #0
    rts
!re_digging:
    lda zp_temp0
    jsr item_cat_select_id
    jsr item_cat_get_effects
    lda icat_p1_lo
    rts
!re_book_far:
    jmp !re_book+
!re_staff_far:
    jmp !re_staff+
!re_chest_far:
    jmp !re_chest+
!re_equip_load:
    // Load ITEM.CAT flags/p1 while resident/KERNAL-safe before re_equip_entry ($F000).
    lda zp_temp0
    jsr item_cat_select_id
    jsr item_cat_get_effects
    jmp re_equip_entry

!re_light:
    bit re_page
    bvs !re_zero-
    lda zp_temp0
    cmp #13
    bne !re_lantern+
    lda #67
    jsr rng_range
    clc
    adc #67
    rts

!re_lantern:
    lda zp_temp0
    cmp #14
    bne !re_flask_oil+
    lda #125
    jsr rng_range
    clc
    adc #125
    rts

!re_flask_oil:
    lda #LANTERN_MAX_CHARGES
    rts

!re_wand:
    bit re_page
    bvs !re_wand_std+
    lda zp_temp0
    cmp #39                         // Wand of Light: [10,15]
    beq !re_wand_light+
!re_wand_std:
    lda #4                          // Others: [5,8]
    jsr rng_range
    clc
    adc #5
    rts
!re_wand_light:
    lda #6
    jsr rng_range
    clc
    adc #10
    rts

!re_staff:
    bit re_page
    bvs !re_staff_std+
    lda zp_temp0
    cmp #43                         // Staff of Light: [10,15]
    beq !re_staff_light+
    cmp #45                         // Staff of Teleportation: [3,5]
    beq !re_staff_tele+
!re_staff_std:
    lda #6                          // Others: [3,8]
    jsr rng_range
    clc
    adc #3
    rts
!re_staff_tele:
    lda #3
    jsr rng_range
    clc
    adc #3
    rts
!re_staff_light:
    lda #6
    jsr rng_range
    clc
    adc #10
    rts

!re_book:
    lda #0
    rts

!re_chest:
    lda zp_temp0
    sec
    sbc #ITEM_TYPE_CHEST_SMALL_WOOD
    tax
    lda chest_source_level,x
    sta fi_add_to_hit
    lda zp_player_dlvl
    jsr rng_range
    cmp #14
    bcc !re_chest_idx+
    lda #13
!re_chest_idx:
    tax
    lda chest_trap_band,x
    ora #CHEST_P1_LOCKED
    rts

chest_source_level:
    .byte 7, 15, 25, 35, 45, 50, 0  // IDs 128-133; ruined (134) = 0

chest_trap_band:
    .byte CHEST_P1_TRAP_POISON, CHEST_P1_TRAP_POISON
    .byte CHEST_P1_TRAP_PARA, CHEST_P1_TRAP_PARA, CHEST_P1_TRAP_PARA
    .byte CHEST_P1_TRAP_EXPL, CHEST_P1_TRAP_EXPL
    .byte CHEST_P1_TRAP_SUMMON, CHEST_P1_TRAP_SUMMON, CHEST_P1_TRAP_SUMMON
    .byte (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA), (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA), (CHEST_P1_TRAP_STR | CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_PARA)
    .byte (CHEST_P1_TRAP_SUMMON | CHEST_P1_TRAP_EXPL)

// re_equip — roll_enchantment's equipment branch (re_page, zp_temp0, re_cat,
// and icat_flags_0..3 / icat_p1_lo preloaded). NEVER calls ITEM.CAT I/O!
#if !RE_EQUIP_SEGMENT_CUSTOM
.macro ReEquipSegment() {}
.macro ReEquipRestoreSegment() {}
.label re_equip_entry = re_equip
#endif
:ReEquipSegment()
re_equip:
    // Honor intrinsic catalog curse bit (ITR3_CURSED) even if enchantment roll skips.
    lda icat_flags_3
    and #ITR3_CURSED
    beq !re_chk_chance+
    lda #IF_CURSED
    sta fi_add_flags
!re_chk_chance:
    // magic_chance = min(15 + dlvl, 70)
    lda zp_player_dlvl
    clc
    adc #15
    cmp #71
    bcc !re_chance_ok+
    lda #70
!re_chance_ok:
    sta zp_temp1

    lda #100
    jsr rng_range
    cmp zp_temp1
    bcc !re_enchant_roll+
    // Unenchanted roll: if intrinsically cursed with catalog p1/AC (Weakness/Stupidity/WOE/DOOM),
    // still apply catalog base penalty so item matches its negative description.
    lda fi_add_flags
    and #IF_CURSED
    beq !re_no_magic+
    lda re_page
    beq !re_cursed_base_p1+
    lda zp_temp0
    cmp #337 - ITEM_PAGE_SIZE       // Ring of WOE carries -3 AC
    bne !re_cursed_base_p1+
    lda #$fd
    sta fi_add_to_ac
!re_cursed_base_p1:
    lda icat_p1_lo
    rts
!re_no_magic:
    lda #0
    rts

!re_enchant_roll:
    jsr re_roll_bonus
    sta re_bonus_hit
    jsr re_roll_bonus
    sta re_bonus_dam
    jsr re_roll_bonus
    sta re_bonus_ac
    jsr re_roll_bonus
    sta re_bonus_p1

    // 1-in-13 chance of cursed, OR intrinsically cursed in ITEM.CAT
    lda icat_flags_3
    and #ITR3_CURSED
    bne !re_apply_curse+
    lda #13
    jsr rng_range
    bne !re_not_cursed+

!re_apply_curse:
    lda #IF_CURSED
    sta fi_add_flags
    lda re_bonus_hit
    jsr re_negate_a
    sta re_bonus_hit
    lda re_bonus_dam
    jsr re_negate_a
    sta re_bonus_dam
    lda re_bonus_ac
    jsr re_negate_a
    sta re_bonus_ac
    lda re_bonus_p1
    jsr re_negate_a
    sta re_bonus_p1

!re_not_cursed:
    lda re_cat
    cmp #ICAT_WEAPON
    beq !re_weapon+
    cmp #ICAT_RING
    beq !re_ring+
    cmp #ICAT_AMULET
    beq !re_amulet_far+
    cmp #ICAT_CLOAK
    beq !re_armor+
    cmp #ICAT_ARMOR
    bcc !re_ret_zero+
    cmp #ICAT_BOOTS + 1
    bcc !re_armor+
!re_ret_zero:
    lda #0
    rts
!re_amulet_far:
    jmp !re_amulet+

!re_weapon:
    lda re_bonus_hit
    sta fi_add_to_hit
    lda re_bonus_dam
    sta fi_add_to_dam
    lda #0
    rts

!re_armor:
    lda re_bonus_ac
    sta fi_add_to_ac
    lda #0
    rts

!re_ring:
    bit re_page
    bvs !re_ring_p1+
    lda zp_temp0
    cmp #23                         // Ring of Protection
    beq !re_ring_ac+
    cmp #146
    bcc !re_not_lordly+
    cmp #149                        // Rings of Lordly Protection (146-148)
    bcc !re_ring_ac+
!re_not_lordly:
    cmp #ITEM_TYPE_RING_SLAYING     // Ring of Slaying (113)
    beq !re_weapon-
    cmp #ITEM_TYPE_RING_SPEED       // Ring of Speed (111): +1 (or -1 if cursed)
    bne !re_ring_misc+
    lda fi_add_flags
    and #IF_CURSED
    bne !re_speed_neg+
    lda #1
    rts
!re_speed_neg:
    lda #$ff
    rts
!re_ring_p1:
    lda zp_temp0
    cmp #327 - ITEM_PAGE_SIZE       // Ring of Increase Damage
    bne !+
    lda re_bonus_dam
    sta fi_add_to_dam
    lda #0
    rts
!:  cmp #328 - ITEM_PAGE_SIZE       // Ring of Increase To-Hit
    bne !+
    lda re_bonus_hit
    sta fi_add_to_hit
    lda #0
    rts
!:  cmp #337 - ITEM_PAGE_SIZE       // Ring of WOE: negative AC + stat penalty
    bne !re_ring_misc+
    lda re_bonus_ac
    sta fi_add_to_ac
    lda re_bonus_p1
    rts
!re_ring_ac:
    lda re_bonus_ac
    sta fi_add_to_ac
    lda #0
    rts
!re_ring_misc:
    // Sustain rings encode stat ID in ITEM.CAT p1; inv_p1 stays 0 so no (+N) prints.
    lda icat_flags_2
    and #ITR2_SUST_STAT
    bne !re_ret_zero2+
!re_amulet:
    // Rings & amulets with STR..CHR/SEARCH flags take p1 bonus/penalty
    lda icat_flags_0
    and #(ITR0_STR | ITR0_DEX | ITR0_CON | ITR0_INT | ITR0_WIS | ITR0_CHR | ITR0_SEARCH)
    beq !re_ret_zero2+
    lda re_bonus_p1
    rts
!re_ret_zero2:
    lda #0
    rts

re_roll_bonus:
    lda zp_player_dlvl
    lsr
    lsr
    clc
    adc #1
    jsr rng_range
    clc
    adc #1
    rts

re_negate_a:
    eor #$ff
    clc
    adc #1
    rts
:ReEquipRestoreSegment()

#import "item_identification.s"

// ============================================================
// Compile-time validation
// ============================================================
.assert "Item type count", ITEM_TYPE_COUNT, 370
.assert "pit_sorted_lo size (excludes gold and ruined chest)", pit_sorted_lo_end - pit_sorted_lo, PIT_SPAWNABLE_COUNT
.assert "pit_sorted_hi_bits size", pit_sorted_hi_bits_end - pit_sorted_hi_bits, (PIT_SPAWNABLE_COUNT + 7) >> 3
.assert "pit_level_bounds_lo size", pit_level_bounds_lo_end - pit_level_bounds_lo, PIT_MAX_LEVEL + 1
.assert "pit_level_bounds_hi size", pit_level_bounds_hi_end - pit_level_bounds_hi, PIT_MAX_LEVEL + 1
.assert "pick_item_type entry stays resident", pick_item_type < $e000, true
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
.assert "pick_item_type overlay impl lives in the $E000 overlay window", pick_item_type_overlay >= BANKED_DATA_BASE && pick_item_type_overlay <= BANKED_DATA_END, true
#endif
.assert "Inventory total slots", TOTAL_INV_SLOTS, 34
