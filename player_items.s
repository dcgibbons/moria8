// player_items.s — Equip, Remove, Eat, and equipment recalculation
//
// Phase 6.3: Player item interaction routines.
// item_wear: equip an item from carried inventory
// item_takeoff: remove an equipped item back to carried inventory
// item_eat: eat food from inventory
// player_recalc_equipment: recalculate AC/combat after equip changes

// ============================================================
// Constants
// ============================================================
.const FOOD_RATION_VALUE_LO = <1500
.const FOOD_RATION_VALUE_HI = >1500
.const FOOD_SLIME_VALUE_LO  = <500
.const FOOD_SLIME_VALUE_HI  = >500
.const FOOD_MAX_LO          = <4000
.const FOOD_MAX_HI          = >4000

.const ITEM_RATION     = 15    // Type ID for ration of food
.const ITEM_SLIME_MOLD = 16   // Type ID for slime mold

// Hunger thresholds (duplicated from turn.s — must stay in sync)
.const PIW_FOOD_HUNGRY_AT = 150
.const PIW_FOOD_WEAK_AT   = 50
.const PIW_FOOD_FAINT_AT  = 10

// ============================================================
// Scratch variables
// ============================================================
piw_slot:     .byte 0          // Source carried slot index
piw_equip:    .byte 0          // Target equipment slot index
piw_item_id:  .byte 0          // Item type ID being processed
piw_qty:      .byte 0          // Item qty being processed
piw_p1:       .byte 0          // Item p1 being processed
piw_flags:    .byte 0          // Item flags being processed

// ============================================================
// Category -> equipment slot mapping table
// ============================================================
equip_slot_for_cat:
    .byte $ff              // ICAT_NONE (0) -> invalid
    .byte $ff              // ICAT_GOLD (1) -> invalid
    .byte EQUIP_WEAPON     // ICAT_WEAPON (2) -> slot 22
    .byte EQUIP_BODY       // ICAT_ARMOR (3) -> slot 23
    .byte EQUIP_SHIELD     // ICAT_SHIELD (4) -> slot 24
    .byte EQUIP_HEAD       // ICAT_HELM (5) -> slot 25
    .byte EQUIP_HANDS      // ICAT_GLOVES (6) -> slot 26
    .byte EQUIP_FEET       // ICAT_BOOTS (7) -> slot 27
    .byte EQUIP_LIGHT      // ICAT_LIGHT (8) -> slot 28
    .byte $ff              // ICAT_FOOD (9) -> invalid
    .byte $ff              // ICAT_POTION (10) -> invalid
    .byte $ff              // ICAT_SCROLL (11) -> invalid
    .byte EQUIP_RING       // ICAT_RING (12) -> slot 29
    .byte $ff              // ICAT_CLOAK (13) -> invalid

// ============================================================
// Subroutines
// ============================================================

// item_wear — Wear/wield an item from carried inventory
// Prompts "WEAR WHICH ITEM (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
item_wear:
    // Print prompt
    lda #<piw_wear_prompt
    sta zp_ptr0
    lda #>piw_wear_prompt
    sta zp_ptr0_hi
    jsr msg_print

    // Wait for keypress
    jsr input_get_key

    // Check for ESC ($03) or space ($20) -> cancel
    cmp #$03
    beq !iw_cancel_tramp+
    cmp #$20
    beq !iw_cancel_tramp+

    // Convert PETSCII letter to slot index
    // Uppercase A-V = $41-$56 -> slot 0-21
    sec
    sbc #$41
    bcc !iw_cancel_tramp+       // Below 'A'
    cmp #MAX_INV_SLOTS
    bcc !iw_in_range+
!iw_cancel_tramp:
    jmp !iw_cancel+
!iw_in_range:
    sta piw_slot

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !iw_has_item+

    // Empty slot
    lda #<piw_nothing_str
    sta zp_ptr0
    lda #>piw_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!iw_has_item:
    // Save carried item data into scratch (before any swap)
    sta piw_item_id             // A already has inv_item_id[slot]
    ldx piw_slot
    lda inv_qty,x
    sta piw_qty
    lda inv_p1,x
    sta piw_p1
    lda inv_flags,x
    sta piw_flags

    // Look up category -> equipment slot
    ldx piw_item_id
    lda it_category,x
    cmp #14                     // Out of range check
    bcc !iw_cat_ok+
    jmp !iw_cant_wear+
!iw_cat_ok:
    tax
    lda equip_slot_for_cat,x
    cmp #$ff
    bne !iw_equip_ok+
    jmp !iw_cant_wear+
!iw_equip_ok:
    sta piw_equip

    // Check if equip slot already occupied -> swap
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !iw_no_swap+

    // Swap: copy old equipped item to the source carried slot
    ldx piw_equip
    ldy piw_slot
    lda inv_item_id,x
    sta inv_item_id,y
    lda inv_qty,x
    sta inv_qty,y
    lda inv_p1,x
    sta inv_p1,y
    lda inv_flags,x
    sta inv_flags,y
    jmp !iw_write_equip+

!iw_no_swap:
    // Clear the source carried slot
    ldx piw_slot
    jsr inv_remove_item

!iw_write_equip:
    // Write saved carried item data to equipment slot
    ldx piw_equip
    lda piw_item_id
    sta inv_item_id,x
    lda piw_qty
    sta inv_qty,x
    lda piw_p1
    sta inv_p1,x
    lda piw_flags
    sta inv_flags,x

    // If equipping a light, set light radius
    lda piw_equip
    cmp #EQUIP_LIGHT
    bne !iw_not_light+
    lda #1
    sta zp_light_radius
!iw_not_light:

    // Recalculate combat stats
    jsr player_recalc_equipment

    // Build message: "YOU ARE WIELDING A <name>." or "YOU ARE WEARING A <name>."
    lda #0
    sta cmb_buf_idx

    // Check if weapon
    lda piw_equip
    cmp #EQUIP_WEAPON
    bne !iw_wearing+
    lda #<piw_wield_str
    ldy #>piw_wield_str
    jmp !iw_msg+
!iw_wearing:
    lda #<piw_wearing_str
    ldy #>piw_wearing_str
!iw_msg:
    jsr combat_append_str

    lda piw_item_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

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

    sec                         // Turn consumed
    rts

!iw_cant_wear:
    lda #<piw_cant_wear_str
    sta zp_ptr0
    lda #>piw_cant_wear_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!iw_cancel:
    lda #<piw_nevermind_str
    sta zp_ptr0
    lda #>piw_nevermind_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

// item_takeoff — Remove an equipped item back to carried inventory
// Prompts "TAKE OFF WHICH ITEM (A-H)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
item_takeoff:
    // Print prompt
    lda #<piw_takeoff_prompt
    sta zp_ptr0
    lda #>piw_takeoff_prompt
    sta zp_ptr0_hi
    jsr msg_print

    // Wait for keypress
    jsr input_get_key

    // Check for ESC or space -> cancel
    cmp #$03
    beq !ito_cancel_tramp+
    cmp #$20
    beq !ito_cancel_tramp+

    // Convert PETSCII letter to equip index
    // A-H = $41-$48 -> equip slot 22-29
    sec
    sbc #$41
    bcc !ito_cancel_tramp+
    cmp #MAX_EQUIP_SLOTS
    bcc !ito_in_range+
!ito_cancel_tramp:
    jmp !ito_cancel+
!ito_in_range:
    clc
    adc #EQUIP_WEAPON           // Map 0-7 -> 22-29
    sta piw_equip

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !ito_has_item+

    lda #<piw_nothing_str
    sta zp_ptr0
    lda #>piw_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ito_has_item:
    sta piw_item_id

    // Check cursed flag
    ldx piw_equip
    lda inv_flags,x
    and #IF_CURSED
    beq !ito_not_cursed+

    lda #<piw_cursed_str
    sta zp_ptr0
    lda #>piw_cursed_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ito_not_cursed:
    // Save equipped item's flags before inv_add_item
    ldx piw_equip
    lda inv_flags,x
    sta piw_flags

    // Set up fi_add scratch for inv_add_item
    lda inv_item_id,x
    sta fi_add_id
    lda inv_qty,x
    sta fi_add_qty
    lda inv_p1,x
    sta fi_add_p1

    // Find empty carried slot and add
    jsr inv_add_item
    bcs !ito_added+

    // Pack full
    lda #<ipu_pack_full_str
    sta zp_ptr0
    lda #>ipu_pack_full_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ito_added:
    // X = new carried slot from inv_add_item
    // Copy saved flags to new carried slot
    lda piw_flags
    sta inv_flags,x

    // Clear equipment slot
    ldx piw_equip
    jsr inv_remove_item

    // If removing a light, clear light radius
    lda piw_equip
    cmp #EQUIP_LIGHT
    bne !ito_not_light+
    lda #0
    sta zp_light_radius
!ito_not_light:

    // Recalculate
    jsr player_recalc_equipment

    // Build message: "YOU TAKE OFF THE <name>."
    lda #0
    sta cmb_buf_idx
    lda #<piw_takeoff_str
    ldy #>piw_takeoff_str
    jsr combat_append_str

    lda piw_item_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

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

    sec                         // Turn consumed
    rts

!ito_cancel:
    lda #<piw_nevermind_str
    sta zp_ptr0
    lda #>piw_nevermind_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

// item_eat — Eat a food item from inventory
// Scans carried slots for ICAT_FOOD, eats first found.
// Output: carry set = turn consumed, carry clear = no food
// Clobbers: everything
item_eat:
    lda #0
    sta piw_slot

!ie_scan:
    lda piw_slot
    cmp #MAX_INV_SLOTS
    bcs !ie_no_food+

    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ie_next+

    // Check category: look up it_category[item_type]
    sta piw_item_id             // Save item type
    tax
    lda it_category,x
    cmp #ICAT_FOOD
    beq !ie_found+

!ie_next:
    inc piw_slot
    jmp !ie_scan-

!ie_no_food:
    lda #<piw_no_food_str
    sta zp_ptr0
    lda #>piw_no_food_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!ie_found:
    // piw_slot = inventory slot, piw_item_id = item type
    // Determine food value
    lda piw_item_id
    cmp #ITEM_RATION
    beq !ie_ration+
    // Default to slime mold value
    lda #FOOD_SLIME_VALUE_LO
    sta zp_temp0
    lda #FOOD_SLIME_VALUE_HI
    sta zp_temp1
    jmp !ie_add_food+
!ie_ration:
    lda #FOOD_RATION_VALUE_LO
    sta zp_temp0
    lda #FOOD_RATION_VALUE_HI
    sta zp_temp1

!ie_add_food:
    // Add to 16-bit food counter
    lda zp_player_food
    clc
    adc zp_temp0
    sta zp_player_food
    lda zp_player_food_hi
    adc zp_temp1
    sta zp_player_food_hi

    // Cap at 4000
    lda zp_player_food_hi
    cmp #FOOD_MAX_HI
    bcc !ie_cap_ok+
    bne !ie_clamp+
    lda zp_player_food
    cmp #FOOD_MAX_LO
    bcc !ie_cap_ok+
    beq !ie_cap_ok+
!ie_clamp:
    lda #FOOD_MAX_LO
    sta zp_player_food
    lda #FOOD_MAX_HI
    sta zp_player_food_hi
!ie_cap_ok:

    // Sync to player_data
    lda zp_player_food
    sta player_data + PL_FOOD_LO
    lda zp_player_food_hi
    sta player_data + PL_FOOD_HI

    // Update hunger state
    lda zp_player_food_hi
    bne !ie_full+
    lda zp_player_food
    cmp #PIW_FOOD_HUNGRY_AT
    bcs !ie_full+
    cmp #PIW_FOOD_WEAK_AT
    bcs !ie_hungry+
    cmp #PIW_FOOD_FAINT_AT
    bcs !ie_weak+
    lda #HUNGER_FAINT
    sta zp_hunger_state
    jmp !ie_remove+
!ie_weak:
    lda #HUNGER_WEAK
    sta zp_hunger_state
    jmp !ie_remove+
!ie_hungry:
    lda #HUNGER_HUNGRY
    sta zp_hunger_state
    jmp !ie_remove+
!ie_full:
    lda #HUNGER_FULL
    sta zp_hunger_state

!ie_remove:
    // Remove food from inventory
    ldx piw_slot
    jsr inv_remove_item

    // Build message
    lda #0
    sta cmb_buf_idx

    lda #<piw_eat_str
    ldy #>piw_eat_str
    jsr combat_append_str

    lda piw_item_id
    jsr item_append_name

    // Check if slime mold for different flavor text
    lda piw_item_id
    cmp #ITEM_SLIME_MOLD
    beq !ie_yuck+

    lda #<piw_delicious_str
    ldy #>piw_delicious_str
    jmp !ie_end_msg+
!ie_yuck:
    lda #<piw_yuck_str
    ldy #>piw_yuck_str
!ie_end_msg:
    jsr combat_append_str

    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x

    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jsr msg_print

    sec                         // Turn consumed
    rts

// player_recalc_equipment — Recalculate AC, to-hit, to-damage from equipment
// Called after any equip/unequip action.
// Clobbers: everything
player_recalc_equipment:
    // Start with stat-based bonuses
    jsr player_calc_combat      // Resets PL_AC, PL_TOHIT, PL_TODMG from stats

    // Add armor AC from equipped items
    ldx #EQUIP_BODY
    jsr pre_add_ac
    ldx #EQUIP_SHIELD
    jsr pre_add_ac
    ldx #EQUIP_HEAD
    jsr pre_add_ac
    ldx #EQUIP_HANDS
    jsr pre_add_ac
    ldx #EQUIP_FEET
    jsr pre_add_ac

    // Add ring protection bonus
    ldx #EQUIP_RING
    jsr pre_add_ac

    // Add weapon to-hit and to-damage enchantment bonus
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pre_no_weapon+
    lda inv_p1,x                // Weapon enchantment (+X)
    clc
    adc player_data + PL_TOHIT
    sta player_data + PL_TOHIT
    // Weapon damage bonus from enchantment
    ldx #EQUIP_WEAPON
    lda inv_p1,x
    clc
    adc player_data + PL_TODMG
    sta player_data + PL_TODMG
!pre_no_weapon:

    // Sync back to ZP
    lda player_data + PL_AC
    sta zp_player_ac

    rts

// pre_add_ac — Add base AC + enchantment from an equipment slot
// Input: X = equipment slot index (22-29)
// Clobbers: A, Y
pre_add_ac:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !paa_none+

    // Add base AC
    tay                         // Y = item type
    lda it_base_ac,y
    clc
    adc player_data + PL_AC
    sta player_data + PL_AC

    // Add enchantment bonus (p1)
    lda inv_p1,x
    clc
    adc player_data + PL_AC
    sta player_data + PL_AC

!paa_none:
    rts

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
piw_wear_prompt:    .text "WEAR WHICH ITEM (A-V)?" ; .byte 0
piw_takeoff_prompt: .text "TAKE OFF WHICH ITEM (A-H)?" ; .byte 0
piw_nothing_str:    .text "YOU HAVE NOTHING THERE." ; .byte 0
piw_cant_wear_str:  .text "YOU CANNOT WEAR THAT." ; .byte 0
piw_nevermind_str:  .text "NEVER MIND." ; .byte 0
piw_cursed_str:     .text "YOU CANNOT REMOVE IT, IT IS CURSED!" ; .byte 0
piw_no_food_str:    .text "YOU HAVE NO FOOD." ; .byte 0
piw_wield_str:      .text "YOU ARE WIELDING A " ; .byte 0
piw_wearing_str:    .text "YOU ARE WEARING A " ; .byte 0
piw_takeoff_str:    .text "YOU TAKE OFF THE " ; .byte 0
piw_eat_str:        .text "YOU EAT THE " ; .byte 0
piw_delicious_str:  .text ". DELICIOUS!" ; .byte 0
piw_yuck_str:       .text ". YUCK!" ; .byte 0
