// item.s — Item data structures, floor items, inventory, and gold spawning
//
// Phase 6.1: Master item type table (SoA), floor item table at $CF00,
// inventory/equipment table, and subroutines for managing both.
// Gold spawning on dungeon floors.

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
.const ICAT_CLOAK    = 13

// Item Instance Flags
.const IF_CURSED     = $01
.const IF_IDENTIFIED = $02
.const IF_TRIED      = $04

// Floor Item Constants
.const MAX_FLOOR_ITEMS = 32
.const FI_EMPTY        = $ff

// Equipment Slot Constants (indices 22-29 in unified table)
.const EQUIP_WEAPON = 22
.const EQUIP_BODY   = 23
.const EQUIP_SHIELD = 24
.const EQUIP_HEAD   = 25
.const EQUIP_HANDS  = 26
.const EQUIP_FEET   = 27
.const EQUIP_LIGHT  = 28
.const EQUIP_RING   = 29

// Inventory Constants
.const MAX_INV_SLOTS   = 22
.const MAX_EQUIP_SLOTS = 8
.const TOTAL_INV_SLOTS = 30

// Master Item Type Count
.const ITEM_TYPE_COUNT = 25

// ============================================================
// Master Item Type Table — Struct-of-Arrays (25 types)
// ============================================================

// Category
it_category:
    .byte ICAT_GOLD     // 0: Gold (small)
    .byte ICAT_GOLD     // 1: Gold (large)
    .byte ICAT_WEAPON   // 2: Dagger
    .byte ICAT_WEAPON   // 3: Short sword
    .byte ICAT_WEAPON   // 4: Long sword
    .byte ICAT_WEAPON   // 5: Mace
    .byte ICAT_ARMOR    // 6: Robe
    .byte ICAT_ARMOR    // 7: Leather armor
    .byte ICAT_ARMOR    // 8: Chain mail
    .byte ICAT_SHIELD   // 9: Small shield
    .byte ICAT_HELM     // 10: Iron helm
    .byte ICAT_GLOVES   // 11: Leather gloves
    .byte ICAT_BOOTS    // 12: Leather boots
    .byte ICAT_LIGHT    // 13: Wooden torch
    .byte ICAT_LIGHT    // 14: Brass lantern
    .byte ICAT_FOOD     // 15: Ration of food
    .byte ICAT_FOOD     // 16: Slime mold
    .byte ICAT_POTION   // 17: Cure light wounds
    .byte ICAT_POTION   // 18: Speed
    .byte ICAT_POTION   // 19: Poison
    .byte ICAT_SCROLL   // 20: Light
    .byte ICAT_SCROLL   // 21: Identify
    .byte ICAT_SCROLL   // 22: Teleportation
    .byte ICAT_RING     // 23: Protection
    .byte ICAT_RING     // 24: Strength

// Display character (screen codes)
it_display:
    .byte $24   // 0: '$' Gold (small)
    .byte $24   // 1: '$' Gold (large)
    .byte $2f   // 2: '/' Dagger
    .byte $2f   // 3: '/' Short sword
    .byte $2f   // 4: '/' Long sword
    .byte $2f   // 5: '/' Mace
    .byte $5b   // 6: '[' Robe
    .byte $5b   // 7: '[' Leather armor
    .byte $5b   // 8: '[' Chain mail
    .byte $29   // 9: ')' Small shield
    .byte $5d   // 10: ']' Iron helm
    .byte $5d   // 11: ']' Leather gloves
    .byte $5d   // 12: ']' Leather boots
    .byte $2a   // 13: '*' Wooden torch
    .byte $2a   // 14: '*' Brass lantern
    .byte $2c   // 15: ',' Ration of food
    .byte $2c   // 16: ',' Slime mold
    .byte $21   // 17: '!' Cure light wounds
    .byte $21   // 18: '!' Speed
    .byte $21   // 19: '!' Poison
    .byte $3f   // 20: '?' Light
    .byte $3f   // 21: '?' Identify
    .byte $3f   // 22: '?' Teleportation
    .byte $3d   // 23: '=' Protection
    .byte $3d   // 24: '=' Strength

// Color
it_color:
    .byte COL_YELLOW    // 0: Gold (small)
    .byte COL_YELLOW    // 1: Gold (large)
    .byte COL_LGREY     // 2: Dagger
    .byte COL_LGREY     // 3: Short sword
    .byte COL_WHITE     // 4: Long sword
    .byte COL_LGREY     // 5: Mace
    .byte COL_LGREY     // 6: Robe
    .byte COL_BROWN     // 7: Leather armor
    .byte COL_GREY      // 8: Chain mail
    .byte COL_LGREY     // 9: Small shield
    .byte COL_GREY      // 10: Iron helm
    .byte COL_BROWN     // 11: Leather gloves
    .byte COL_BROWN     // 12: Leather boots
    .byte COL_YELLOW    // 13: Wooden torch
    .byte COL_ORANGE    // 14: Brass lantern
    .byte COL_BROWN     // 15: Ration of food
    .byte COL_GREEN     // 16: Slime mold
    .byte COL_WHITE     // 17: Cure light wounds
    .byte COL_LGREEN    // 18: Speed
    .byte COL_GREEN     // 19: Poison
    .byte COL_WHITE     // 20: Light
    .byte COL_LGREY     // 21: Identify
    .byte COL_CYAN      // 22: Teleportation
    .byte COL_YELLOW    // 23: Protection
    .byte COL_LRED      // 24: Strength

// Weight (in 1/10 lbs)
it_weight:
    .byte 0, 0, 12, 30, 50, 50, 20, 80, 120, 50
    .byte 30, 5, 10, 10, 30, 10, 5, 4, 4, 4
    .byte 2, 2, 2, 2, 2

// Damage dice count
it_dmg_dice:
    .byte 0, 0, 1, 1, 1, 2, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0

// Damage dice sides
it_dmg_sides:
    .byte 0, 0, 4, 6, 8, 4, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0

// Base armor class
it_base_ac:
    .byte 0, 0, 0, 0, 0, 0, 2, 4, 6, 2
    .byte 1, 1, 1, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 1, 0

// Base cost (lo)
it_cost_lo:
    .byte <0, <0, <10, <25, <60, <45, <15, <30, <80, <20
    .byte <15, <8, <10, <2, <20, <3, <2, <50, <75, <5
    .byte <15, <50, <40, <100, <120

// Base cost (hi)
it_cost_hi:
    .byte >0, >0, >10, >25, >60, >45, >15, >30, >80, >20
    .byte >15, >8, >10, >2, >20, >3, >2, >50, >75, >5
    .byte >15, >50, >40, >100, >120

// Minimum dungeon level to appear
it_min_level:
    .byte 0, 0, 1, 1, 3, 2, 1, 2, 4, 2
    .byte 3, 1, 1, 0, 2, 0, 1, 1, 3, 1
    .byte 1, 2, 3, 4, 5

// Name pointer tables
it_name_lo:
    .byte <itn_0,  <itn_1,  <itn_2,  <itn_3,  <itn_4
    .byte <itn_5,  <itn_6,  <itn_7,  <itn_8,  <itn_9
    .byte <itn_10, <itn_11, <itn_12, <itn_13, <itn_14
    .byte <itn_15, <itn_16, <itn_17, <itn_18, <itn_19
    .byte <itn_20, <itn_21, <itn_22, <itn_23, <itn_24
it_name_hi:
    .byte >itn_0,  >itn_1,  >itn_2,  >itn_3,  >itn_4
    .byte >itn_5,  >itn_6,  >itn_7,  >itn_8,  >itn_9
    .byte >itn_10, >itn_11, >itn_12, >itn_13, >itn_14
    .byte >itn_15, >itn_16, >itn_17, >itn_18, >itn_19
    .byte >itn_20, >itn_21, >itn_22, >itn_23, >itn_24

// Name strings (screen codes, null-terminated)
itn_0:  .text "GOLD (SMALL)" ; .byte 0
itn_1:  .text "GOLD (LARGE)" ; .byte 0
itn_2:  .text "DAGGER" ; .byte 0
itn_3:  .text "SHORT SWORD" ; .byte 0
itn_4:  .text "LONG SWORD" ; .byte 0
itn_5:  .text "MACE" ; .byte 0
itn_6:  .text "ROBE" ; .byte 0
itn_7:  .text "LEATHER ARMOR" ; .byte 0
itn_8:  .text "CHAIN MAIL" ; .byte 0
itn_9:  .text "SMALL SHIELD" ; .byte 0
itn_10: .text "IRON HELM" ; .byte 0
itn_11: .text "LEATHER GLOVES" ; .byte 0
itn_12: .text "LEATHER BOOTS" ; .byte 0
itn_13: .text "WOODEN TORCH" ; .byte 0
itn_14: .text "BRASS LANTERN" ; .byte 0
itn_15: .text "RATION OF FOOD" ; .byte 0
itn_16: .text "SLIME MOLD" ; .byte 0
itn_17: .text "CURE LIGHT WOUNDS" ; .byte 0
itn_18: .text "SPEED" ; .byte 0
itn_19: .text "POISON" ; .byte 0
itn_20: .text "LIGHT" ; .byte 0
itn_21: .text "IDENTIFY" ; .byte 0
itn_22: .text "TELEPORTATION" ; .byte 0
itn_23: .text "PROTECTION" ; .byte 0
itn_24: .text "STRENGTH" ; .byte 0

// ============================================================
// Floor Item Table — 32 slots x 8 arrays at $CF00 (256 bytes)
// ============================================================
.label fi_item_id = FLOOR_ITEM_BASE + 0       // $CF00: item type (0-24), $FF = empty
.label fi_x       = FLOOR_ITEM_BASE + 32      // $CF20: map X
.label fi_y       = FLOOR_ITEM_BASE + 64      // $CF40: map Y
.label fi_qty     = FLOOR_ITEM_BASE + 96      // $CF60: quantity / gold amount
.label fi_p1      = FLOOR_ITEM_BASE + 128     // $CF80: enchantment / charges
.label fi_flags   = FLOOR_ITEM_BASE + 160     // $CFA0: instance flags
.label fi_spare1  = FLOOR_ITEM_BASE + 192     // $CFC0: reserved
.label fi_spare2  = FLOOR_ITEM_BASE + 224     // $CFE0: reserved

// ============================================================
// Inventory Table — 30 slots (22 carried + 8 equipped)
// ============================================================
inv_item_id: .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_qty:     .fill TOTAL_INV_SLOTS, 0
inv_p1:      .fill TOTAL_INV_SLOTS, 0
inv_flags:   .fill TOTAL_INV_SLOTS, 0

// ============================================================
// Scratch variables
// ============================================================
fi_add_x:   .byte 0       // Position for floor_item_add
fi_add_y:   .byte 0
fi_add_id:  .byte 0       // Item type ID
fi_add_qty: .byte 0       // Quantity / gold amount
fi_add_p1:  .byte 0       // Enchantment / charges
isl_target: .byte 0       // item_spawn_level loop target
isl_idx:    .byte 0       // item_spawn_level loop counter

// ============================================================
// Subroutines
// ============================================================

// item_init_floor — Clear all 32 floor item slots
// Sets all fi_item_id to $FF, zp_item_count = 0
// Clobbers: A, X
item_init_floor:
    ldx #MAX_FLOOR_ITEMS - 1
    lda #FI_EMPTY
!iif_loop:
    sta fi_item_id,x
    dex
    bpl !iif_loop-
    lda #0
    sta zp_item_count
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
    rts

// floor_item_add — Add an item to the floor item table
// Input: fi_add_x, fi_add_y, fi_add_id, fi_add_qty, fi_add_p1
// Output: carry set = success (X = slot), carry clear = table full
// Clobbers: A, X, Y, zp_ptr0
floor_item_add:
    // Find first empty slot
    ldx #0
!fia_scan:
    cpx #MAX_FLOOR_ITEMS
    bcs !fia_full+
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !fia_found+
    inx
    jmp !fia_scan-

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
    lda fi_add_p1
    sta fi_p1,x
    lda #0
    sta fi_flags,x
    sta fi_spare1,x
    sta fi_spare2,x

    // Set FLAG_HAS_ITEM on map tile at (x, y)
    stx zp_temp4                // Save slot index
    ldy fi_add_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy fi_add_x
    lda (zp_ptr0),y
    ora #FLAG_HAS_ITEM
    sta (zp_ptr0),y
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
    sta fi_flags,x

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
    lda (zp_ptr0),y
    and #~FLAG_HAS_ITEM & $ff
    sta (zp_ptr0),y
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
    ldx #0
!fifa_loop:
    cpx #MAX_FLOOR_ITEMS
    bcs !fifa_miss+
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
    sec
    rts
!fifa_next:
    inx
    jmp !fifa_loop-
!fifa_miss:
    clc
    rts

// inv_add_item — Add item to first empty carried slot (0-21)
// Input: fi_add_id, fi_add_qty, fi_add_p1
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
    lda #0
    sta inv_flags,x
    sec
    rts
!iai_full:
    clc
    rts

// inv_remove_item — Remove item from inventory slot X
// Input: X = slot index (0-29)
// Clobbers: A
inv_remove_item:
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    rts

// inv_count_items — Count used carried slots (0-21)
// Output: A = count
// Clobbers: X
inv_count_items:
    lda #0
    sta fi_add_p1               // Reuse scratch as counter
    ldx #0
!ici_loop:
    cpx #MAX_INV_SLOTS
    bcs !ici_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ici_next+
    inc fi_add_p1
!ici_next:
    inx
    jmp !ici_loop-
!ici_done:
    lda fi_add_p1
    rts

// ============================================================
// item_spawn_level — Spawn gold piles on the dungeon floor
// Called after monster_spawn_level at each level transition.
// Count: 2 + rng(3) + dlvl/2, capped at 16. Town = 0.
// Clobbers: everything
// ============================================================
item_spawn_level:
    jsr item_init_floor

    // Town = no items
    lda zp_player_dlvl
    bne !isl_dungeon+
    rts

!isl_dungeon:
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
    bcc !isl_capped+
    lda #16
    sta isl_target
!isl_capped:

    lda #0
    sta isl_idx

!isl_loop:
    lda isl_idx
    cmp isl_target
    bcs !isl_done+

    // Find a random floor tile
    jsr find_random_floor

    // Set up floor item add
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Gold type: rng(2) → ID 0 or 1
    lda #2
    jsr rng_range
    sta fi_add_id

    // Gold qty: rng(dlvl * 10) + 5
    // dlvl * 10 via shift+add: dlvl*8 + dlvl*2
    lda zp_player_dlvl
    asl                         // *2
    sta fi_add_qty              // Temp: dlvl*2
    lda zp_player_dlvl
    asl
    asl
    asl                         // *8
    clc
    adc fi_add_qty              // *8 + *2 = *10
    // Cap at 255 to avoid overflow for high dlvl
    bcc !isl_no_cap+
    lda #255
!isl_no_cap:
    jsr rng_range               // [0, dlvl*10-1]
    clc
    adc #5                      // [5, dlvl*10+4]
    bcc !isl_qty_ok+
    lda #255                    // Cap at 255
!isl_qty_ok:
    sta fi_add_qty

    lda #0
    sta fi_add_p1               // No enchantment for gold

    jsr floor_item_add
    // Ignore failure (table full)

    inc isl_idx
    jmp !isl_loop-

!isl_done:
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
    lda #<ipu_nothing_str
    sta zp_ptr0
    lda #>ipu_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
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
    // Add fi_qty to 24-bit player gold
    ldx ipu_slot
    lda player_data + PL_GOLD_0
    clc
    adc fi_qty,x
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc #0
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #0
    sta player_data + PL_GOLD_2

    // Build message: "YOU FOUND N GOLD PIECES."
    lda #0
    sta cmb_buf_idx
    lda #<ipu_found_str
    ldy #>ipu_found_str
    jsr combat_append_str

    ldx ipu_slot
    lda fi_qty,x
    jsr combat_append_decimal

    lda #<ipu_gold_str
    ldy #>ipu_gold_str
    jsr combat_append_str

    // Null-terminate
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x

    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jsr msg_print

    // Remove from floor
    ldx ipu_slot
    jsr floor_item_remove

    lda #SFX_PICKUP
    jsr sound_play

    sec
    rts

!ipu_not_gold:
    // --- Non-gold item pickup ---
    // Check if inventory full
    jsr inv_count_items
    cmp #MAX_INV_SLOTS
    bcc !ipu_has_room+

    // Pack full
    lda #<ipu_pack_full_str
    sta zp_ptr0
    lda #>ipu_pack_full_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ipu_has_room:
    // Copy item to inventory
    ldx ipu_slot
    lda fi_item_id,x
    sta fi_add_id
    lda fi_qty,x
    sta fi_add_qty
    lda fi_p1,x
    sta fi_add_p1
    jsr inv_add_item
    // carry set = success (should always succeed since we checked)

    // Build message: "YOU PICKED UP A <name>."
    lda #0
    sta cmb_buf_idx
    lda #<ipu_picked_str
    ldy #>ipu_picked_str
    jsr combat_append_str

    lda fi_add_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    // Null-terminate
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x

    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jsr msg_print

    // Remove from floor
    ldx ipu_slot
    jsr floor_item_remove

    lda #SFX_PICKUP
    jsr sound_play

    sec
    rts

// item_drop — Drop first carried inventory item to floor
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4
item_drop:
    // Find first non-empty carried slot (0-21)
    ldx #0
!idr_scan:
    cpx #MAX_INV_SLOTS
    bcs !idr_empty+
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !idr_found+
    inx
    jmp !idr_scan-

!idr_empty:
    // No items to drop
    lda #<idr_no_items_str
    sta zp_ptr0
    lda #>idr_no_items_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!idr_found:
    // X = inventory slot. Save it.
    stx ipu_slot

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

    jsr floor_item_add
    bcs !idr_placed+

    // Floor full
    lda #<idr_floor_full_str
    sta zp_ptr0
    lda #>idr_floor_full_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!idr_placed:
    // Remove from inventory
    ldx ipu_slot
    jsr inv_remove_item

    // Build message: "YOU DROP A <name>."
    lda #0
    sta cmb_buf_idx
    lda #<idr_drop_str
    ldy #>idr_drop_str
    jsr combat_append_str

    lda fi_add_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    // Null-terminate
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x

    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jsr msg_print

    lda #SFX_PICKUP
    jsr sound_play

    sec
    rts

// item_append_name — Append item type name to combat_msg_buf
// Input: A = item type ID
// Clobbers: A, X, Y, zp_ptr1
item_append_name:
    tax
    lda it_name_lo,x
    ldy it_name_hi,x
    jsr combat_append_str
    rts

// Scratch variables for pickup/drop
ipu_slot: .byte 0              // Floor/inventory slot being processed

// ============================================================
// Pickup/Drop strings (screen codes via inherited encoding)
// ============================================================
ipu_nothing_str:   .text "YOU SEE NOTHING HERE." ; .byte 0
ipu_found_str:     .text "YOU FOUND " ; .byte 0
ipu_gold_str:      .text " GOLD PIECES." ; .byte 0
ipu_picked_str:    .text "YOU PICKED UP A " ; .byte 0
ipu_pack_full_str: .text "YOUR PACK IS FULL." ; .byte 0
idr_drop_str:      .text "YOU DROP A " ; .byte 0
idr_no_items_str:  .text "YOU HAVE NOTHING TO DROP." ; .byte 0
idr_floor_full_str: .text "NO ROOM ON THE FLOOR." ; .byte 0

// ============================================================
// Compile-time validation
// ============================================================
.assert "Item type count", ITEM_TYPE_COUNT, 25
.assert "it_category size", it_display - it_category, ITEM_TYPE_COUNT
.assert "it_display size", it_color - it_display, ITEM_TYPE_COUNT
.assert "it_color size", it_weight - it_color, ITEM_TYPE_COUNT
.assert "Floor item base", FLOOR_ITEM_BASE, $cf00
.assert "Inventory total slots", TOTAL_INV_SLOTS, 30
