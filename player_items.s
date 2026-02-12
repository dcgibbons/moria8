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
// ============================================================
// item_quaff — Quaff a potion from inventory
// Prompts "QUAFF WHICH POTION (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
item_quaff:
    // Print prompt
    lda #<piq_quaff_prompt
    sta zp_ptr0
    lda #>piq_quaff_prompt
    sta zp_ptr0_hi
    jsr msg_print

    // Wait for keypress
    jsr input_get_key

    // Check for ESC ($03) or space ($20) -> cancel
    cmp #$03
    beq !iq_cancel_tramp+
    cmp #$20
    beq !iq_cancel_tramp+

    // Convert PETSCII letter to slot index (A-V = $41-$56 -> 0-21)
    sec
    sbc #$41
    bcc !iq_cancel_tramp+
    cmp #MAX_INV_SLOTS
    bcc !iq_in_range+
!iq_cancel_tramp:
    jmp !iq_cancel+
!iq_in_range:
    sta piw_slot

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !iq_has_item+

    lda #<piw_nothing_str
    sta zp_ptr0
    lda #>piw_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!iq_has_item:
    sta piw_item_id

    // Check it's a potion
    tax
    lda it_category,x
    cmp #ICAT_POTION
    beq !iq_is_potion+

    lda #<piq_not_potion_str
    sta zp_ptr0
    lda #>piq_not_potion_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!iq_is_potion:
    // Identify this potion type
    ldx piw_item_id
    lda #1
    sta id_known,x

    // Remove from inventory
    ldx piw_slot
    jsr inv_remove_item

    // Apply effect based on item type
    lda piw_item_id
    cmp #17                         // Cure Light Wounds
    beq !iq_cure+
    cmp #18                         // Speed
    beq !iq_speed+
    cmp #19                         // Poison
    beq !iq_poison+
    jmp !iq_generic_msg+            // Shouldn't happen

!iq_cure:
    // Heal rng(8) + 4 HP
    lda #8
    jsr rng_range                   // [0, 7]
    clc
    adc #4                          // [4, 11]
    sta piw_qty                     // Reuse as heal amount

    // Add to player HP (16-bit)
    lda zp_player_hp_lo
    clc
    adc piw_qty
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    adc #0
    sta zp_player_hp_hi

    // Cap at max HP
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !iq_hp_ok+
    bne !iq_hp_clamp+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !iq_hp_ok+
    beq !iq_hp_ok+
!iq_hp_clamp:
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
!iq_hp_ok:

    // Sync to player_data
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI

    lda #<piq_feel_better_str
    sta zp_ptr0
    lda #>piq_feel_better_str
    sta zp_ptr0_hi
    jsr msg_print

    sec
    rts

!iq_speed:
    // Set speed effect timer: rng(20) + 10
    lda #20
    jsr rng_range                   // [0, 19]
    clc
    adc #10                         // [10, 29]
    // Add to existing timer (stacks)
    clc
    adc zp_eff_speed
    bcc !iq_speed_ok+
    lda #255                        // Cap at 255
!iq_speed_ok:
    sta zp_eff_speed

    lda #<piq_speed_str
    sta zp_ptr0
    lda #>piq_speed_str
    sta zp_ptr0_hi
    jsr msg_print

    sec
    rts

!iq_poison:
    // Deal rng(6) + 3 damage
    lda #6
    jsr rng_range                   // [0, 5]
    clc
    adc #3                          // [3, 8]
    sta piw_qty                     // Reuse as damage

    // Subtract from HP (16-bit)
    lda zp_player_hp_lo
    sec
    sbc piw_qty
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc #0
    sta zp_player_hp_hi

    // Check for death (HP <= 0)
    bmi !iq_poison_death+
    bne !iq_poison_alive+
    lda zp_player_hp_lo
    bne !iq_poison_alive+
!iq_poison_death:
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    lda zp_game_flags
    ora #$01                        // GF_DEAD
    sta zp_game_flags

!iq_poison_alive:
    // Sync to player_data
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Set poison timer: rng(10) + 5
    lda #10
    jsr rng_range
    clc
    adc #5
    clc
    adc zp_eff_poison               // Stack with existing
    bcc !iq_poi_ok+
    lda #255
!iq_poi_ok:
    sta zp_eff_poison

    lda #<piq_terrible_str
    sta zp_ptr0
    lda #>piq_terrible_str
    sta zp_ptr0_hi
    jsr msg_print

    sec
    rts

!iq_generic_msg:
    lda #<piq_nothing_str
    sta zp_ptr0
    lda #>piq_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    sec
    rts

!iq_cancel:
    lda #<piw_nevermind_str
    sta zp_ptr0
    lda #>piw_nevermind_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

// ============================================================
// item_read_scroll — Read a scroll from inventory
// Prompts "READ WHICH SCROLL (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
irs_target_slot: .byte 0           // Target slot for Identify scroll

item_read_scroll:
    // Print prompt
    lda #<piq_read_prompt
    sta zp_ptr0
    lda #>piq_read_prompt
    sta zp_ptr0_hi
    jsr msg_print

    // Wait for keypress
    jsr input_get_key

    // Check for ESC or space -> cancel
    cmp #$03
    beq !irs_cancel_tramp+
    cmp #$20
    beq !irs_cancel_tramp+

    // Convert PETSCII letter to slot index
    sec
    sbc #$41
    bcc !irs_cancel_tramp+
    cmp #MAX_INV_SLOTS
    bcc !irs_in_range+
!irs_cancel_tramp:
    jmp !irs_cancel+
!irs_in_range:
    sta piw_slot

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !irs_has_item+

    lda #<piw_nothing_str
    sta zp_ptr0
    lda #>piw_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!irs_has_item:
    sta piw_item_id

    // Check it's a scroll
    tax
    lda it_category,x
    cmp #ICAT_SCROLL
    beq !irs_is_scroll+

    lda #<piq_not_scroll_str
    sta zp_ptr0
    lda #>piq_not_scroll_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!irs_is_scroll:
    // Identify this scroll type
    ldx piw_item_id
    lda #1
    sta id_known,x

    // Remove from inventory
    ldx piw_slot
    jsr inv_remove_item

    // Apply effect based on item type
    lda piw_item_id
    cmp #20                         // Light
    beq !irs_light+
    cmp #21                         // Identify
    bne !irs_not_identify+
    jmp !irs_identify+
!irs_not_identify:
    cmp #22                         // Teleportation
    bne !irs_not_teleport+
    jmp !irs_teleport+
!irs_not_teleport:
    jmp !irs_generic_msg+

!irs_light:
    // Light the room the player is in
    // Scan rooms for player position (same bounds check as LOS)
    lda #0
    sta piw_qty                     // Reuse as room loop index

!irs_light_loop:
    ldx piw_qty
    cpx room_count
    bcs !irs_light_corridor+        // Player not in any room

    // Check bounds: player_x in [room_x-1, room_x+room_w]
    lda room_x,x
    sec
    sbc #1
    cmp zp_player_x
    beq !irs_lx_ok+
    bcs !irs_light_next+
!irs_lx_ok:
    lda room_x,x
    clc
    adc room_w,x
    cmp zp_player_x
    bcc !irs_light_next+

    // Check bounds: player_y in [room_y-1, room_y+room_h]
    lda room_y,x
    sec
    sbc #1
    cmp zp_player_y
    beq !irs_ly_ok+
    bcs !irs_light_next+
!irs_ly_ok:
    lda room_y,x
    clc
    adc room_h,x
    cmp zp_player_y
    bcc !irs_light_next+

    // Player is in room X — light it
    lda #1
    sta room_lit,x
    sta vis_room_revealed           // Trigger full redraw
    jmp !irs_light_msg+

!irs_light_next:
    inc piw_qty
    jmp !irs_light_loop-

!irs_light_corridor:
    // In corridor — just set vis_room_revealed for redraw
    lda #1
    sta vis_room_revealed

!irs_light_msg:
    lda #<piq_light_str
    sta zp_ptr0
    lda #>piq_light_str
    sta zp_ptr0_hi
    jsr msg_print

    sec
    rts

!irs_identify:
    // Prompt: "IDENTIFY WHICH ITEM (A-V)?"
    lda #<piq_identify_prompt
    sta zp_ptr0
    lda #>piq_identify_prompt
    sta zp_ptr0_hi
    jsr msg_print

    jsr input_get_key

    // Cancel check
    cmp #$03
    beq !irs_id_cancel+
    cmp #$20
    beq !irs_id_cancel+

    // Convert to slot
    sec
    sbc #$41
    bcc !irs_id_cancel+
    cmp #MAX_INV_SLOTS
    bcs !irs_id_cancel+

    sta irs_target_slot
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !irs_id_cancel+

    // Identify that item type
    tax
    lda #1
    sta id_known,x

    // Set IF_IDENTIFIED on the item instance
    ldx irs_target_slot
    lda inv_flags,x
    ora #IF_IDENTIFIED
    sta inv_flags,x

    // Build message: "THIS IS A <real name>."
    lda #0
    sta cmb_buf_idx

    lda #<piq_thisis_str
    ldy #>piq_thisis_str
    jsr combat_append_str

    ldx irs_target_slot
    lda inv_item_id,x
    tax
    lda it_name_lo,x                // Always real name (type is now known)
    ldy it_name_hi,x
    jsr combat_append_str

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

    sec
    rts

!irs_id_cancel:
    // Scroll already consumed — just print generic message
    lda #<piq_nothing_str
    sta zp_ptr0
    lda #>piq_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    sec
    rts

!irs_teleport:
    // Teleport player to random floor tile
    jsr find_random_floor

    // Clear FLAG_OCCUPIED at old position
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    and #~FLAG_OCCUPIED & $ff
    sta (zp_ptr0),y

    // Move player
    lda df_target_x
    sta zp_player_x
    lda df_target_y
    sta zp_player_y

    // Set FLAG_OCCUPIED at new position
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    lda (zp_ptr0),y
    ora #FLAG_OCCUPIED
    sta (zp_ptr0),y

    // Trigger full visibility update and redraw
    lda #1
    sta vis_room_revealed

    lda #<piq_teleport_str
    sta zp_ptr0
    lda #>piq_teleport_str
    sta zp_ptr0_hi
    jsr msg_print

    sec
    rts

!irs_generic_msg:
    lda #<piq_nothing_str
    sta zp_ptr0
    lda #>piq_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    sec
    rts

!irs_cancel:
    lda #<piw_nevermind_str
    sta zp_ptr0
    lda #>piw_nevermind_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
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

// Quaff/Read strings
piq_quaff_prompt:   .text "QUAFF WHICH POTION (A-V)?" ; .byte 0
piq_read_prompt:    .text "READ WHICH SCROLL (A-V)?" ; .byte 0
piq_not_potion_str: .text "THAT IS NOT A POTION." ; .byte 0
piq_not_scroll_str: .text "THAT IS NOT A SCROLL." ; .byte 0
piq_feel_better_str:.text "YOU FEEL BETTER." ; .byte 0
piq_speed_str:      .text "YOU FEEL YOURSELF MOVING FASTER." ; .byte 0
piq_terrible_str:   .text "THAT TASTED TERRIBLE!" ; .byte 0
piq_nothing_str:    .text "NOTHING SEEMS TO HAPPEN." ; .byte 0
piq_light_str:      .text "THE AREA FILLS WITH LIGHT." ; .byte 0
piq_identify_prompt:.text "IDENTIFY WHICH ITEM (A-V)?" ; .byte 0
piq_thisis_str:     .text "THIS IS A " ; .byte 0
piq_teleport_str:   .text "YOU FEEL DISORIENTED." ; .byte 0
