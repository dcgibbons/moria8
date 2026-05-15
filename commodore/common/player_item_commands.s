#importonce
// player_item_commands.s — Wear/takeoff/eat/quaff command bodies.
//
// Split from player_items.s so C128 can place these callable bodies in the
// banked runtime window instead of letting them drift into $D000-$DFFF.

// item_wear — Wear/wield an item from carried inventory
// Prompts "WEAR WHICH ITEM (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
item_wear:
    lda #$fe
    ldx #HSTR_PIW_WEAR_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !iw_have_choices+
    clc
    rts
!iw_have_choices:
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr hal_input_get_key

    // '?' shows inventory (wearable items only) and re-prompts
    cmp #$3f
    bne !iw_not_inv+
    lda #$fe                    // Filter: wearable items
    jsr show_inv_and_select
!iw_not_inv:

    // Check for ESC ($03) or space ($20) -> cancel
    cmp #$03
    beq !iw_cancel_tramp+
    cmp #$20
    beq !iw_cancel_tramp+

    jsr piw_pick_filtered_inv_key
    bcs !iw_in_range+
!iw_cancel_tramp:
    jmp !iw_cancel+
!iw_in_range:
    stx piw_slot

    // Save carried item data into scratch (before any swap)
    sta piw_item_id             // A already has inv_item_id[slot]
    ldx piw_slot
    lda inv_qty,x
    sta piw_qty
    lda inv_p1,x
    sta piw_p1
    lda inv_to_hit,x
    sta piw_to_hit
    lda inv_to_dam,x
    sta piw_to_dam
    lda inv_to_ac,x
    sta piw_to_ac
    lda inv_flags,x
    sta piw_flags
    lda inv_ego,x
    sta piw_ego

    // The filtered picker already excludes non-equippable categories and oil.
    ldx piw_item_id
    lda it_category,x
    tax
    lda equip_slot_for_cat,x
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
    lda inv_to_hit,x
    sta inv_to_hit,y
    lda inv_to_dam,x
    sta inv_to_dam,y
    lda inv_to_ac,x
    sta inv_to_ac,y
    lda inv_flags,x
    sta inv_flags,y
    lda inv_ego,x
    sta inv_ego,y
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
    lda piw_to_hit
    sta inv_to_hit,x
    lda piw_to_dam
    sta inv_to_dam,x
    lda piw_to_ac
    sta inv_to_ac,x
    lda piw_flags
    sta inv_flags,x
    lda piw_ego
    sta inv_ego,x

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
    ldx #HSTR_PIW_WIELD
    jmp !iw_msg+
!iw_wearing:
    ldx #HSTR_PIW_WEARING
!iw_msg:
    jsr huff_append_combat

    lda piw_ego
    sta fi_add_ego
    lda piw_p1
    sta fi_add_p1
    lda piw_to_hit
    sta fi_add_to_hit
    lda piw_to_dam
    sta fi_add_to_dam
    lda piw_to_ac
    sta fi_add_to_ac
    lda piw_flags
    sta fi_add_flags
    lda piw_item_id
    jsr item_append_desc

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    jsr cmb_term_and_print

    lda #SFX_PICKUP
    jsr hal_sound_play

    sec                         // Turn consumed
    rts

!iw_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
    rts

// item_takeoff — Remove an equipped item back to carried inventory
// Prompts "TAKE OFF WHICH ITEM (A-H)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
item_takeoff:
    jsr piw_count_visible_equip
    bne !ito_have_choices+
    ldx #HSTR_PIW_NOTHING
    jsr huff_print_msg
    clc
    rts
!ito_have_choices:
    ldx #HSTR_PIW_TAKEOFF_PROMPT
    jsr piw_print_prompt_with_count
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr hal_input_get_key
    and #$7f                    // Accept shifted/unshifted letter selections

    // '?' shows equipment and re-prompts
    cmp #$3f
    bne !ito_not_inv+
    jsr show_equip_and_restore
    jmp item_takeoff
!ito_not_inv:

    // Check for ESC or space -> cancel
    cmp #$03
    beq !ito_cancel_tramp+
    cmp #$20
    beq !ito_cancel_tramp+

    jsr piw_pick_visible_equip_key
    bcs !ito_in_range+
!ito_cancel_tramp:
    jmp !ito_cancel+
!ito_in_range:
    stx piw_equip
    sta piw_item_id

    // Check cursed flag
    ldx piw_equip
    lda inv_flags,x
    and #IF_CURSED
    beq !ito_not_cursed+

    ldx #HSTR_PIW_CURSED
    jsr huff_print_msg
    clc
    rts

!ito_not_cursed:
    // Save equipped item's fields before inv_add_item
    ldx piw_equip
    lda inv_flags,x
    sta piw_flags
    lda inv_ego,x
    sta piw_ego

    // Set up fi_add scratch for inv_add_item
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
    lda inv_ego,x
    sta fi_add_ego
    lda piw_flags
    sta fi_add_flags

    // Find empty carried slot and add
    jsr inv_add_item
    bcs !ito_added+

    // Pack full
    ldx #HSTR_UIS_PACK_FULL
    jsr huff_print_msg
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
    ldx #HSTR_PIW_TAKEOFF
    jsr huff_append_combat

    lda piw_ego
    sta fi_add_ego
    lda piw_flags
    sta fi_add_flags
    lda piw_item_id
    jsr item_append_desc

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    jsr cmb_term_and_print

    lda #SFX_PICKUP
    jsr hal_sound_play

    sec                         // Turn consumed
    rts

!ito_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
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
    ldx #HSTR_PIW_NO_FOOD
    jsr huff_print_msg
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

    // Reuse the shared hunger-state classifier; starvation damage remains
    // turn-owned because eating can only increase the food counter.
    jsr player_update_hunger_state

!ie_remove:
    // Remove food from inventory
    ldx piw_slot
    jsr inv_remove_item

    // Build message
    lda #0
    sta cmb_buf_idx

    ldx #HSTR_PIW_EAT
    jsr huff_append_combat

    lda #0
    sta fi_add_ego              // Food has no ego
    lda piw_item_id
    jsr item_append_name

    // Check if slime mold for different flavor text
    lda piw_item_id
    cmp #ITEM_SLIME_MOLD
    beq !ie_yuck+

    ldx #HSTR_PIW_DELICIOUS
    jmp !ie_end_msg+
!ie_yuck:
    ldx #HSTR_PIW_YUCK
!ie_end_msg:
    jsr huff_append_combat

    jsr cmb_term_and_print

    sec                         // Turn consumed
    rts

#if !PLAYER_RECALC_EQUIPMENT_EXTERNAL
    #import "player_recalc_equipment.s"
#endif

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
    lda #ICAT_POTION
    ldx #HSTR_PIQ_QUAFF_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !iq_have_choices+
    clc
    rts
!iq_have_choices:
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr hal_input_get_key

    // '?' shows inventory (potions only) and re-prompts
    cmp #$3f
    bne !iq_not_inv+
    lda #ICAT_POTION
    jsr show_inv_and_select
!iq_not_inv:

    // Check for ESC ($03) or space ($20) -> cancel
    cmp #$03
    beq !iq_cancel_tramp+
    cmp #$20
    beq !iq_cancel_tramp+

    jsr piw_pick_filtered_inv_key
    bcs !iq_in_range+
!iq_cancel_tramp:
    jmp iq_cancel
!iq_in_range:
    stx piw_slot
    sta piw_item_id
    // Identify this potion type
    ldx piw_item_id
    lda #1
    sta id_known,x

    // Remove from inventory
    ldx piw_slot
    jsr inv_remove_item

    // Apply effect based on item type.
    lda piw_item_id
    cmp #17
    bcc !iq_dispatch_generic+
    cmp #32
    bcs !iq_dispatch_generic+
    sec
    sbc #17
    tax
    lda iq_dispatch_lo,x
    sta zp_ptr1
    lda iq_dispatch_hi,x
    sta zp_ptr1_hi
    jmp (zp_ptr1)
!iq_dispatch_generic:
    jmp iq_effect_generic

iq_dispatch_lo:
    .byte <iq_effect_cure, <iq_effect_speed, <iq_effect_poison
    .byte <iq_effect_generic, <iq_effect_generic, <iq_effect_generic, <iq_effect_generic, <iq_effect_generic
    .byte <iq_effect_csw, <iq_effect_restore_mana, <iq_effect_heroism, <iq_effect_blindness
    .byte <iq_effect_confusion, <iq_effect_detect_mon, <iq_effect_infravision
iq_dispatch_hi:
    .byte >iq_effect_cure, >iq_effect_speed, >iq_effect_poison
    .byte >iq_effect_generic, >iq_effect_generic, >iq_effect_generic, >iq_effect_generic, >iq_effect_generic
    .byte >iq_effect_csw, >iq_effect_restore_mana, >iq_effect_heroism, >iq_effect_blindness
    .byte >iq_effect_confusion, >iq_effect_detect_mon, >iq_effect_infravision

iq_effect_cure:
    // Heal rng(8) + 4 HP
    lda #8
    jsr rng_range                   // [0, 7]
    clc
    adc #4                          // [4, 11]
    sta piw_qty                     // Reuse as heal amount

    lda piw_qty
    jsr pmx_heal_and_report
    sec
    rts

iq_effect_speed:
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

    ldx #HSTR_PIQ_SPEED
    jsr huff_print_msg
    sec
    rts

iq_effect_poison:
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
    lda #DEATH_POISON
    sta zp_death_source
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

    ldx #HSTR_PIQ_TERRIBLE
    jsr huff_print_msg

    sec
    rts

iq_effect_csw:
    // Cure Serious Wounds: heal 5d8+5 = [10, 45]
    lda #5                          // N = 5 dice
    ldx #8                          // S = 8 sides
    ldy #5                          // bonus = 5
    jsr math_dice                   // Result in zp_math_a (max 45, fits 8 bits)
    lda zp_math_a
    jsr pmx_heal_and_report
    sec
    rts

iq_effect_restore_mana:
    // Restore Mana: set MP = max MP
    lda zp_player_mmp
    sta zp_player_mp
    sta player_data + PL_MANA

    ldx #HSTR_PIQ_MIND_CLEAR
    jsr huff_print_msg
    sec
    rts

iq_effect_heroism:
    // Set zp_eff_hero timer (rng(25)+25), stacks
    // NOTE: Timer is infrastructure only — gameplay effects (to-hit/HP bonus)
    // will be integrated when effect consumption is added in a later phase.
    lda #25
    jsr rng_range                   // [0, 24]
    clc
    adc #25                         // [25, 49]
    clc
    adc zp_eff_hero
    bcc !iq_hero_ok+
    lda #255
!iq_hero_ok:
    sta zp_eff_hero

    ldx #HSTR_PIQ_HEROIC
    jsr huff_print_msg
    sec
    rts

iq_effect_blindness:
    // Set zp_eff_blind timer (rng(100)+100)
    lda #100
    jsr rng_range                   // [0, 99]
    clc
    adc #100                        // [100, 199]
    clc
    adc zp_eff_blind
    bcc !iq_blind_ok+
    lda #255
!iq_blind_ok:
    sta zp_eff_blind

    ldx #HSTR_PIQ_CANT_SEE
    jsr huff_print_msg
    sec
    rts

iq_effect_confusion:
    // Set zp_eff_confuse timer (rng(15)+10)
    lda #15
    jsr rng_range                   // [0, 14]
    clc
    adc #10                         // [10, 24]
    clc
    adc zp_eff_confuse
    bcc !iq_conf_ok+
    lda #255
!iq_conf_ok:
    sta zp_eff_confuse

    ldx #HSTR_PIQ_DIZZY
    jsr huff_print_msg
    sec
    rts

iq_effect_detect_mon:
    jsr eff_detect_monsters
    ldx #HSTR_PIQ_SENSE
    jsr huff_print_msg
    sec
    rts

iq_effect_infravision:
    // Set zp_eff_infra timer (rng(50)+50)
    // NOTE: Timer is infrastructure only — monster reveal effect will be
    // integrated when effect consumption is added in a later phase.
    lda #50
    jsr rng_range                   // [0, 49]
    clc
    adc #50                         // [50, 99]
    clc
    adc zp_eff_infra
    bcc !iq_infra_ok+
    lda #255
!iq_infra_ok:
    sta zp_eff_infra

    ldx #HSTR_PIQ_EYES_TINGLE
    jsr huff_print_msg
    sec
    rts

iq_effect_generic:
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

iq_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
    rts
