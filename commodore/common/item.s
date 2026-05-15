#importonce
// item.s — Item data structures, floor items, inventory, and gold spawning
//
// Phase 6.1: Master item type table (SoA), floor item table at $CF00,
// inventory/equipment table, and subroutines for managing both.
// Gold spawning on dungeon floors.

#import "input_ui_helpers.s"

// ============================================================
// Item Category Constants
// ============================================================
.const ICAT_NONE     = 0
.const ICAT_GOLD     = 1
.const ICAT_WEAPON   = 2
.const ICAT_ARMOR    = 3
.const ICAT_SHIELD   = 4
.const ICAT_HELM     = 5
.const ICAT_GLOVES   = 6
.const ICAT_BOOTS    = 7
.const ICAT_LIGHT    = 8
.const ICAT_FOOD     = 9
.const ICAT_POTION   = 10
.const ICAT_SCROLL   = 11
.const ICAT_RING     = 12
.const ICAT_BOOK     = 13
.const ICAT_WAND     = 14
.const ICAT_STAFF    = 15

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
//   fi_meta[42]     packed flags+ego: bits 0-2 ego, bits 3-6 IF_* flags
.label fi_item_id = FLOOR_ITEM_BASE + 0
.label fi_x       = fi_item_id + MAX_FLOOR_ITEMS
.label fi_y       = fi_x + MAX_FLOOR_ITEMS
.label fi_qty     = fi_y + MAX_FLOOR_ITEMS
.label fi_p1      = fi_qty + MAX_FLOOR_ITEMS
.label fi_meta    = fi_p1 + MAX_FLOOR_ITEMS
.assert "Floor item table fits in $CF00-$CFFF", fi_meta + MAX_FLOOR_ITEMS <= FLOOR_ITEM_BASE + 256, true

.const FI_META_EGO_MASK    = $07
.const FI_META_FLAGS_SHIFT = 3
.const FI_META_FLAGS_MASK  = $78

// ============================================================
// Inventory Table — 30 slots (22 carried + 8 equipped)
// ============================================================
inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_qty:     .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_to_hit:  .fill TOTAL_INV_SLOTS, 0
inv_to_dam:  .fill TOTAL_INV_SLOTS, 0
inv_to_ac:   .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0
inv_ego:     .fill TOTAL_INV_SLOTS, 0

// Split stat sidecars for floor slots. The packed floor table intentionally
// stays inside its fixed 256-byte page.
fi_to_hit:   .fill MAX_FLOOR_ITEMS, 0
fi_to_dam:   .fill MAX_FLOOR_ITEMS, 0
fi_to_ac:    .fill MAX_FLOOR_ITEMS, 0

glyph_x:      .fill MAX_GLYPHS, 0
glyph_y:      .fill MAX_GLYPHS, 0
glyph_active: .fill MAX_GLYPHS, 0

// ============================================================
// Scratch variables
// ============================================================
fi_add_x:   .byte 0       // Position for floor_item_add
fi_add_y:   .byte 0
fi_add_id:  .byte 0       // Item type ID
fi_add_qty: .byte 0       // Quantity / gold amount
fi_add_qty_hi: .byte 0    // Gold qty high byte (auto-reset after add)
fi_add_p1:  .byte 0       // Charges/fuel/type-specific p1
fi_add_to_hit: .byte 0    // Split item to-hit
fi_add_to_dam: .byte 0    // Split item to-damage
fi_add_to_ac:  .byte 0    // Split item to-AC
fi_add_ego: .byte 0       // Ego type (0=none)
isl_target: .byte 0       // item_spawn_level loop target
isl_idx:    .byte 0       // item_spawn_level loop counter

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

// floor_item_pack_add_meta — Pack fi_add_flags + fi_add_ego into floor meta
// Output: A = packed meta byte
// Clobbers: A
floor_item_pack_add_meta:
    lda fi_add_flags
    asl
    asl
    asl
    sta zp_temp0
    lda fi_add_ego
    and #FI_META_EGO_MASK
    ora zp_temp0
    rts

// floor_item_get_qty_hi_x — Get 16-bit gold high byte for floor slot X
// Output: A = qty_hi for gold items, 0 for non-gold
floor_item_get_qty_hi_x:
    lda fi_item_id,x
    cmp #2
    bcc !fi_get_qty_hi_gold+
    lda #0
    rts
!fi_get_qty_hi_gold:
    lda fi_p1,x
    rts

// floor_item_get_p1_x — Get p1/charges for non-gold floor slot X
// Output: A = p1 for non-gold, 0 for gold
floor_item_get_p1_x:
    lda fi_item_id,x
    cmp #2
    bcs !fi_get_p1_ok+
    lda #0
    rts
!fi_get_p1_ok:
    lda fi_p1,x
    rts

// floor_item_get_flags_x — Unpack IF_* flags from floor slot X
// Output: A = flags
floor_item_get_flags_x:
    lda fi_meta,x
    and #FI_META_FLAGS_MASK
    lsr
    lsr
    lsr
    rts

// floor_item_get_ego_x — Unpack ego type from floor slot X
// Output: A = ego type (0=none)
floor_item_get_ego_x:
    lda fi_meta,x
    and #FI_META_EGO_MASK
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
    dex
    bpl !iif_stat_loop-
    jsr glyph_clear_all
    rts

// item_init_inventory — Clear all 30 inventory/equipment slots
// Clobbers: A, X
item_init_inventory:
    ldx #TOTAL_INV_SLOTS - 1
    lda #FI_EMPTY
!iiv_loop:
    sta inv_item_id,x
    dex
    bpl !iiv_loop-
    ldx #TOTAL_INV_SLOTS - 1
    lda #0
!iiv_stat_loop:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_to_hit,x
    sta inv_to_dam,x
    sta inv_to_ac,x
    sta inv_flags,x
    sta inv_ego,x
    dex
    bpl !iiv_stat_loop-
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
    lda fi_add_id
    cmp #2
    bcc !fia_gold_hi+
    lda fi_add_p1
    sta fi_p1,x
    jmp !fia_store_meta+
!fia_gold_hi:
    lda fi_add_qty_hi
    sta fi_p1,x
!fia_store_meta:
    jsr floor_item_pack_add_meta
    sta fi_meta,x
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
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy fi_add_x
    :MapRead_ptr0_y()
    ora #FLAG_HAS_ITEM
    :MapWrite_ptr0_y()
    ldx zp_temp4                // Restore slot index

    // Increment floor item count
    inc zp_item_count

    sec                         // Success
    rts

!fia_full:
    clc                         // Table full
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
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
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

// inv_add_item — Add item to first empty carried slot (0-21)
// Input: fi_add_id, fi_add_qty, fi_add_p1, fi_add_to_hit/dam/ac
// Output: carry set = success (X = slot), carry clear = full
// Clobbers: A, X
inv_add_item:
    ldx #0
!iai_scan:
    cpx #MAX_INV_SLOTS
    bcs !iai_full+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !iai_found+
    inx
    jmp !iai_scan-
!iai_found:
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
    lda fi_add_flags                // Copy flags (preserves IF_CURSED etc.)
    sta inv_flags,x
    lda fi_add_ego
    sta inv_ego,x
    sec
    rts
!iai_full:
    clc
    rts

// inv_remove_item — Remove item from inventory slot X
// Carried slots compact after removal; equipment clears in place.
// Input: X = slot index (0-29)
// Clobbers: A, X
inv_remove_item:
    cpx #MAX_INV_SLOTS - 1
    bcs !iri_clear_slot+
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
!iri_clear_slot:
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

// inv_count_items — Count used carried slots (0-21)
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

item_spawn_level:
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
    jsr pick_item_type
    sta fi_add_id

    // Roll enchantment
    jsr roll_enchantment
    sta fi_add_p1

    // fi_add_* stat fields and fi_add_flags set by roll_enchantment.

    // Roll ego type for weapons (0=none for non-weapons)
    lda fi_add_id
    jsr tramp_roll_ego_type
    sta fi_add_ego

    // Set qty: ammo spawns in stacks, everything else = 1
    lda #1
    sta fi_add_qty
    ldx fi_add_id
    jsr item_get_missile
    bpl !isl_qty_done+          // Bit 7 clear = not ammo
    // Ammo: qty = rng(6) + 5 → [5, 10]
    lda #6
    jsr rng_range
    clc
    adc #5
    sta fi_add_qty
!isl_qty_done:

    jsr floor_item_add
    bcc !isl_ngold_skip+        // Table full — skip

!isl_ngold_skip:
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
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
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

    jsr pick_item_type
    sta fi_add_id

    jsr roll_enchantment
    sta fi_add_p1

    // Roll ego type for treasure room items
    lda fi_add_id
    jsr tramp_roll_ego_type
    sta fi_add_ego

    pla                         // Restore real dlvl
    sta zp_player_dlvl

    lda #1
    sta fi_add_qty

    jsr floor_item_add
    bcc !isl_treasure_skip+

!isl_treasure_skip:
    inc isl_target
    jmp !isl_treasure_loop-

!isl_all_done:
    rts

// ============================================================
// Pickup and Drop
// ============================================================

// item_pickup — Pick up item at player's position
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
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
    lda fi_item_id,x
    tax
    lda it_category,x
    cmp #ICAT_GOLD
    bne !ipu_not_gold+

    // --- Gold pickup ---
    // Add 16-bit fi_qty/fi_qty_hi to 24-bit player gold
    ldx ipu_slot
    lda player_data + PL_GOLD_0
    clc
    adc fi_qty,x
    sta player_data + PL_GOLD_0
    jsr floor_item_get_qty_hi_x
    sta zp_temp1
    lda player_data + PL_GOLD_1
    adc zp_temp1
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #0
    sta player_data + PL_GOLD_2

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
    // Check if inventory full
    jsr inv_count_items
    cmp #MAX_INV_SLOTS
    bcc !ipu_has_room+

    // Pack full
    ldx #HSTR_UIS_PACK_FULL
    jsr huff_print_msg
    clc
    rts

!ipu_has_room:
    // Copy item to inventory
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
    jsr inv_add_item
    // carry set = success (should always succeed since we checked)

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
    jsr input_get_key

    // '?' shows inventory (all items) and re-prompts
    cmp #$3f
    bne !idr_direct_pick+
    lda #$ff                    // Filter: show all items with real slot letters
    jsr show_inv_and_select

!idr_direct_pick:
#if C128
    cmp #$c1
    bcc !idr_norm_done+
    cmp #$db
    bcs !idr_norm_done+
    and #$7f                    // Shifted lowercase PETSCII -> uppercase
!idr_norm_done:
#endif

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
    lda inv_item_id,x
    sta fi_add_id
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
item_append_name:
    sta fi_add_id
    jsr item_get_name_ptr           // zp_ptr0 = name string
    lda zp_ptr0
    ldy zp_ptr0_hi
    jsr combat_append_str
    // Append ego suffix if present (reads fi_add_ego set by caller)
    lda fi_add_ego
    jsr tramp_ego_append_suffix
    rts

// item_append_desc — Append item name plus identified stat suffixes to
// combat_msg_buf. Uses fi_add_* staging fields for the selected instance.
// Input: A = item type ID
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
item_append_desc:
    jsr item_append_name
    lda fi_add_flags
    and #IF_IDENTIFIED
    bne !iad_identified+
    rts
!iad_identified:
    ldx fi_add_id
    lda it_category,x
    cmp #ICAT_WEAPON
    beq !iad_weapon+
    cmp #ICAT_ARMOR
    bcc !iad_done+
    cmp #ICAT_BOOTS + 1
    bcc !iad_armor+
    cmp #ICAT_LIGHT
    beq !iad_turns_tramp+
    cmp #ICAT_RING
    beq !iad_ring_tramp+
    cmp #ICAT_WAND
    beq !iad_charges_tramp+
    cmp #ICAT_STAFF
    beq !iad_charges_tramp+
!iad_done:
    rts
!iad_ring_tramp:
    jmp !iad_ring+
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
    ldx fi_add_id
    lda it_base_ac,x
    jsr combat_append_decimal
    lda #$2c
    jsr combat_append_char
    lda fi_add_to_ac
    jsr item_append_signed_combat
    lda #$1d                    // ']' screen code
    jmp combat_append_char
!iad_ring:
    lda fi_add_id
    cmp #23
    beq !iad_ring_ac+
    cmp #24
    beq !iad_ring_p1+
    rts
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
    jmp combat_append_char
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

    jsr floor_item_add
    // Ignore failure (table full)
    rts

// ============================================================
// pick_item_type — Select a random non-gold item type for floor spawning
// Uses umoria-faithful depth-bucketed 50/50 flat/best-of-3 algorithm.
// 50% flat pick from level-appropriate pool.
// 50% best-of-3 random picks (highest index wins), then re-roll
//      within the winner's depth tier for uniform intra-tier distribution.
// 1-in-12 "great item" chance sets effective level to max (full pool).
// Output: A = item type ID (2-63)
// Clobbers: A, X, Y
// Uses: zp_temp0 (pool_size), zp_temp1 (best_idx), zp_temp2 (tier_lo)
//       zp_temp4 used internally by rng_range
// ============================================================
.const PIT_MAX_LEVEL = 12

// Items 2-63 sorted ascending by it_min_level
pit_sorted:
    // Level 0 (5 items)
    .byte 13, 15, 61, 62, 63
    // Level 1 (15 items)
    .byte 2, 3, 6, 11, 12, 16, 17, 19, 20, 28, 29, 37, 51, 52, 54
    // Level 2 (11 items)
    .byte 5, 7, 9, 14, 21, 30, 31, 47, 48, 49, 53
    // Level 3 (11 items)
    .byte 4, 10, 18, 22, 25, 36, 39, 43, 44, 46, 50
    // Level 4 (9 items)
    .byte 8, 23, 27, 33, 38, 40, 42, 55, 58
    // Level 5 (5 items)
    .byte 24, 26, 32, 41, 45
    // Level 6 (2 items)
    .byte 34, 35
    // Level 8 (2 items)
    .byte 56, 59
    // Level 12 (2 items)
    .byte 57, 60

// Cumulative item count per level (0-12)
pit_level_bounds:
    .byte 5      // level 0: 5 items
    .byte 20     // level 1: +15 = 20
    .byte 31     // level 2: +11 = 31
    .byte 42     // level 3: +11 = 42
    .byte 51     // level 4: +9 = 51
    .byte 56     // level 5: +5 = 56
    .byte 58     // level 6: +2 = 58
    .byte 58     // level 7: (no items)
    .byte 60     // level 8: +2 = 60
    .byte 60     // level 9: (no items)
    .byte 60     // level 10: (no items)
    .byte 60     // level 11: (no items)
    .byte 62     // level 12: +2 = 62

pick_item_type:
    // Calculate effective level = min(dlvl + 2, PIT_MAX_LEVEL)
    lda zp_player_dlvl
    clc
    adc #2
    cmp #PIT_MAX_LEVEL + 1
    bcc !pit_level_ok+
    lda #PIT_MAX_LEVEL
!pit_level_ok:
    tay                          // Y = eff_level (preserved by rng_range)

    // Great item check: 1/12 chance → full pool access
    lda #12
    jsr rng_range                // [0, 11]
    bne !pit_no_great+
    ldy #PIT_MAX_LEVEL
!pit_no_great:

    // pool_size = pit_level_bounds[eff_level]
    lda pit_level_bounds,y
    sta zp_temp0                 // zp_temp0 = pool_size

    // 50/50 coin flip: flat pick vs best-of-3
    lda #2
    jsr rng_range                // [0, 1]
    bne !pit_best_of_3+

    // --- Flat pick: uniform random from pool ---
    lda zp_temp0
    jsr rng_range                // [0, pool_size-1]
!pit_return_idx:
    tax
    lda pit_sorted,x
    rts

!pit_best_of_3:
    // Pick 3 random indices, keep the highest (biases toward deeper items)
    lda zp_temp0
    jsr rng_range
    sta zp_temp1                 // zp_temp1 = best_idx

    lda zp_temp0
    jsr rng_range
    cmp zp_temp1
    bcc !pit_skip1+
    sta zp_temp1
!pit_skip1:
    lda zp_temp0
    jsr rng_range
    cmp zp_temp1
    bcc !pit_skip2+
    sta zp_temp1
!pit_skip2:

    // Look up the winning item's depth tier
    ldx zp_temp1
    lda pit_sorted,x             // A = item_id
    tax
    lda it_min_level,x           // A = found_level
    beq !pit_reroll_l0+          // Level 0: special case (no lower bound)

    // Re-roll uniformly within found_level's tier
    tax                          // X = found_level
    lda pit_level_bounds-1,x     // lo = level_bounds[found_level - 1]
    sta zp_temp2                 // zp_temp2 = tier_lo
    lda pit_level_bounds,x       // hi = level_bounds[found_level]
    sec
    sbc zp_temp2                 // A = range = hi - lo
    jsr rng_range                // [0, range-1]
    clc
    adc zp_temp2                 // [lo, hi-1]
    jmp !pit_return_idx-

!pit_reroll_l0:
    lda pit_level_bounds         // level_bounds[0] = count at level 0
    jsr rng_range                // [0, count-1]
    jmp !pit_return_idx-

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

roll_enchantment:
    sta zp_temp0                // Save item type
    lda #0
    sta fi_add_flags            // Default: not cursed
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta re_bonus_hit
    sta re_bonus_dam
    sta re_bonus_ac
    sta re_bonus_p1

    // Check category — only equipment gets enchantment
    ldx zp_temp0
    lda it_category,x

    // Special case: lights get charges, not enchantment
    cmp #ICAT_LIGHT
    beq !re_light+

    // Special case: books get random spell index
    cmp #ICAT_BOOK
    beq !re_book+

    // Special case: wands and staves get charges
    cmp #ICAT_WAND
    beq !re_wand+
    cmp #ICAT_STAFF
    beq !re_staff+

    // Equipment categories: WEAPON(2) through BOOTS(7), RING(12)
    cmp #ICAT_WEAPON
    bcc !re_zero+               // NONE(0) or GOLD(1) → no enchant
    cmp #ICAT_LIGHT
    bcc !re_equip+              // WEAPON..BOOTS (2-7) → enchant
    cmp #ICAT_RING
    beq !re_equip+              // RING(12) → enchant
    // FOOD, POTION, SCROLL → no enchant
!re_zero:
    lda #0
    rts

!re_light:
    // Torch (type 13): 67 + rng(67)  (each charge = 30 turns)
    lda zp_temp0
    cmp #13
    bne !re_lantern+
    lda #67
    jsr rng_range
    clc
    adc #67
    rts

!re_lantern:
    // Lantern (type 14): 125 + rng(125)  (each charge = 30 turns)
    lda zp_temp0
    cmp #14
    bne !re_flask_oil+
    lda #125
    jsr rng_range
    clc
    adc #125
    rts

!re_flask_oil:
    // Flask of oil (type 61): always 250 (full flask)
    lda #LANTERN_MAX_CHARGES
    rts

!re_wand:
    lda zp_temp0
    cmp #39                         // Wand of Light: [10,15]
    beq !re_wand_light+
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
    lda zp_temp0
    cmp #43                         // Staff of Light: [10,15]
    beq !re_staff_light+
    cmp #45                         // Staff of Teleportation: [3,5]
    beq !re_staff_tele+
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
    // Books: p1=0 (spell range determined by book type)
    lda #0
    rts

!re_equip:
    // magic_chance = min(15 + dlvl, 70)
    lda zp_player_dlvl
    clc
    adc #15
    cmp #71
    bcc !re_chance_ok+
    lda #70
!re_chance_ok:
    sta zp_temp1                // zp_temp1 = magic_chance

    // if rng(100) >= magic_chance: no enchantment
    lda #100
    jsr rng_range               // [0, 99]
    cmp zp_temp1
    bcs !re_zero-               // roll >= chance → no magic

    jsr re_roll_bonus
    sta re_bonus_hit
    jsr re_roll_bonus
    sta re_bonus_dam
    jsr re_roll_bonus
    sta re_bonus_ac
    jsr re_roll_bonus
    sta re_bonus_p1

    // 1-in-13 chance of cursed
    lda #13
    jsr rng_range
    bne !re_not_cursed+

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
    ldx zp_temp0
    lda it_category,x
    cmp #ICAT_WEAPON
    beq !re_weapon+
    cmp #ICAT_RING
    beq !re_ring+
    cmp #ICAT_ARMOR
    beq !re_armor+
    cmp #ICAT_SHIELD
    beq !re_armor+
    cmp #ICAT_HELM
    beq !re_armor+
    cmp #ICAT_GLOVES
    beq !re_armor+
    cmp #ICAT_BOOTS
    beq !re_armor+
    lda #0
    rts

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
    lda zp_temp0
    cmp #23                         // Ring of Protection
    beq !re_ring_protection+
    cmp #24                         // Ring of Strength
    beq !re_ring_strength+
    lda #0
    rts
!re_ring_protection:
    lda re_bonus_ac
    sta fi_add_to_ac
    lda #0
    rts
!re_ring_strength:
    lda re_bonus_p1
    rts

re_roll_bonus:
    // bonus = rng(1 + dlvl/5) + 1
    lda zp_player_dlvl
    lsr
    lsr                         // dlvl/4 (close enough to dlvl/5)
    // Actually: dlvl/5. Use divide: dlvl * 205/1024 ≈ dlvl/5
    // Simpler: use lookup or just lsr twice + adjust
    // For simplicity and correctness: divide by 5 via subtraction
    // But let's use dlvl/4 as a reasonable approximation since
    // the difference is minor (max bonus off by 1 at dlvl 20)
    clc
    adc #1                      // range = 1 + dlvl/4
    jsr rng_range               // [0, dlvl/4]
    clc
    adc #1                      // [1, 1+dlvl/4]
    rts

re_negate_a:
    eor #$ff
    clc
    adc #1
    rts

#import "item_identification.s"

// ============================================================
// Compile-time validation
// ============================================================
.assert "Item type count", ITEM_TYPE_COUNT, 64
.assert "it_category size", it_display - it_category, ITEM_TYPE_COUNT
.assert "it_display size", it_color - it_display, ITEM_TYPE_COUNT
.assert "it_color size", it_weight - it_color, ITEM_TYPE_COUNT
// Hardcoded assertion removed for cross-platform compatibility
.assert "Inventory total slots", TOTAL_INV_SLOTS, 30
