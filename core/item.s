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

#if !ITEM_SPAWN_EXTERNAL
#if ITEM_SPAWN_IN_GEN_OVERLAY
// The port runs this from OVL.GEN behind a resident item_spawn_level
// trampoline (BBC Master: resident image headroom); the picker is then
// called directly in the loaded overlay.
:ItemSpawnSegment()
#endif
#import "item_spawn_cold.s"
#if ITEM_SPAWN_IN_GEN_OVERLAY
:ItemSpawnRestoreSegment()
#endif
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

// ItemDropBody — Shared implementation of item_drop (expanded inline here when
// !ITEM_DROP_EXTERNAL, or inside core/item_drop_cold.s when overlay-hosted).
// Ends with rts so overlay expansions never fall through.
.macro ItemDropBody() {
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
#if ITEM_DROP_EXTERNAL && HAL_PLATFORM_ITEM_ACTION_KEY_RESTORES_BANK
    jsr hal_platform_item_action_restore_bank
#endif

    // '?' shows inventory (all items) and re-prompts
    cmp #$3f
    bne !idr_direct_pick+
#if ITEM_DROP_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME
    lda current_overlay
    sta piw_return_overlay
#endif
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
}

#if !ITEM_DROP_EXTERNAL
#import "item_drop_cold.s"
#endif

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

#if !PICK_ITEM_TYPE_EXTERNAL
#import "pick_item_type_cold.s"
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
.assert "Inventory total slots", TOTAL_INV_SLOTS, 34
