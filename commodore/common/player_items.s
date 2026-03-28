#importonce
// player_items.s — Equip, Remove, Eat, and equipment recalculation
//
// Phase 6.3: Player item interaction routines.
// item_wear: equip an item from carried inventory
// item_takeoff: remove an equipped item back to carried inventory
// item_eat: eat food from inventory
// player_recalc_equipment: recalculate AC/combat after equip changes

#import "ui_restore.s"
#import "input_ui_helpers.s"

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

// ============================================================
// Scratch variables
// ============================================================
piw_slot:     .byte 0          // Source carried slot index
piw_equip:    .byte 0          // Target equipment slot index
piw_item_id:  .byte 0          // Item type ID being processed
piw_qty:      .byte 0          // Item qty being processed
piw_p1:       .byte 0          // Item p1 being processed
piw_flags:    .byte 0          // Item flags being processed
piw_ego:      .byte 0          // Item ego type being processed
piw_filter:   .byte $ff        // Active inventory filter for prompt/select helpers
piw_visible_count: .byte 0     // Number of cached visible slots
piw_visible_slots: .fill MAX_INV_SLOTS, 0  // Absolute carried/equipped slot indices

// ============================================================
// Category -> equipment slot mapping table
// ============================================================
equip_slot_for_cat:
    .byte EQUIP_WEAPON     // ICAT_DIGGING (0) -> weapon slot 22
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
    .byte $ff              // ICAT_BOOK (13) -> not equippable
    .byte $ff              // ICAT_WAND (14) -> not equippable
    .byte $ff              // ICAT_STAFF (15) -> not equippable

// ============================================================
// Subroutines
// ============================================================

// show_inv_and_restore — Show filtered inventory overlay, wait for key, restore screen
// Input: A = filter value ($FF=all, $FE=wearable, 0-15=exact ICAT match)
// Used by item selection dialogs when player presses '?'.
// NOTE (RP15-4): After return, callers re-prompt without re-validating game
// state. This is safe because the overlay is read-only (no state mutation).
// Preserves: nothing
show_inv_and_restore:
    sta uinv_filter
    jsr tramp_ui_inv_display
    jsr input_get_modal_dismiss_key
    jsr ui_view_restore_modal_overlay
    rts

// show_equip_and_restore — Show equipment overlay, wait for key, restore screen
// Used by item_takeoff when player presses '?'.
// Preserves: nothing
show_equip_and_restore:
    jsr tramp_ui_equip_display
    jsr input_get_modal_dismiss_key
    jsr ui_view_restore_modal_overlay
    rts

// piw_inv_slot_matches_filter — check whether a carried slot is visible
// Input: X = carried slot index, piw_filter = active filter
// Output: carry set if slot is occupied and visible under this filter
// Preserves: X
piw_inv_slot_matches_filter:
    txa
    pha

    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !piw_inv_fail+
    sta piw_item_id

    ldy piw_filter
    cpy #$ff
    beq !piw_inv_match+

    tax
    lda it_category,x
    cpy #$fe
    beq !piw_inv_wearable+
    cmp piw_filter
    bne !piw_inv_fail+
    beq !piw_inv_match+

!piw_inv_wearable:
    tax
    lda piw_item_id
    cmp #ITEM_FLASK_OIL
    beq !piw_inv_fail+
    lda equip_slot_for_cat,x
    cmp #$ff
    bne !piw_inv_match+

!piw_inv_fail:
    clc
    pla
    tax
    rts

!piw_inv_match:
    sec
    pla
    tax
    rts

// piw_build_visible_inv_cache — cache visible carried slots for a filter
// Input: A = filter value
// Output: A = visible count
// Clobbers: X, Y
piw_build_visible_inv_cache:
    sta piw_filter
    ldy #0
    ldx #0
!piw_count_inv_loop:
    tya
    pha
    jsr piw_inv_slot_matches_filter
    pla
    tay
    bcc !piw_count_inv_next+
    txa
    sta piw_visible_slots,y
    iny
!piw_count_inv_next:
    inx
    cpx #MAX_INV_SLOTS
    bcc !piw_count_inv_loop-
    sty piw_visible_count
    tya
    rts

// piw_count_filtered_inv — count visible carried items for a filter
// Input: A = filter value
// Output: A = visible count
// Clobbers: X, Y
piw_count_filtered_inv:
    jmp piw_build_visible_inv_cache

// piw_prompt_filtered_inv — print a filtered inventory prompt or "nothing there"
// Input: A = filter value, X = Huffman prompt string id
// Output: carry set if the prompt was printed, carry clear if no visible items
piw_prompt_filtered_inv:
    sta piw_filter
    txa
    pha
    lda piw_filter
    jsr piw_build_visible_inv_cache
    bne !piw_prompt_inv_have_choices+
    pla
    ldx #HSTR_PIW_NOTHING
    jsr huff_print_msg
    clc
    rts
!piw_prompt_inv_have_choices:
    sta piw_qty
    pla
    tax
    lda piw_qty
    jsr piw_print_prompt_with_count
    sec
    rts

// piw_pick_filtered_inv_key — map a filtered prompt letter to a carried slot
// Input: A = PETSCII key, piw_filter = active filter
// Output: carry set on success, X = carried slot, A = item type ID
//         carry clear if key is outside the visible filtered range
piw_pick_filtered_inv_key:
    sec
    sbc #$41
    bcc !piw_pick_inv_fail+
    tay
    cpy piw_visible_count
    bcs !piw_pick_inv_fail+
    lda piw_visible_slots,y
    tax
    lda inv_item_id,x
    sec
    rts

!piw_pick_inv_fail:
    clc
    rts

// piw_build_visible_equip_cache — cache non-empty equipment slots
// Output: A = non-empty equipment count
// Clobbers: X, Y
piw_build_visible_equip_cache:
    ldy #0
    ldx #EQUIP_WEAPON
!piw_count_eq_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !piw_count_eq_next+
    txa
    sta piw_visible_slots,y
    iny
!piw_count_eq_next:
    inx
    cpx #EQUIP_RING + 1
    bcc !piw_count_eq_loop-
    sty piw_visible_count
    tya
    rts

// piw_count_visible_equip — count equipped items for takeoff prompt mapping
// Output: A = non-empty equipment count
// Clobbers: X, Y
piw_count_visible_equip:
    jmp piw_build_visible_equip_cache

// piw_pick_visible_equip_key — map a contiguous equipment letter to a slot
// Input: A = PETSCII key
// Output: carry set on success, X = absolute equipment slot, A = item type ID
//         carry clear if key is outside the visible equipped-item range
piw_pick_visible_equip_key:
    sec
    sbc #$41
    bcc !piw_pick_eq_fail+
    tay
    cpy piw_visible_count
    bcs !piw_pick_eq_fail+
    lda piw_visible_slots,y
    tax
    lda inv_item_id,x
    sec
    rts

!piw_pick_eq_fail:
    clc
    rts

// piw_print_prompt_with_count — decode, patch, and print a visible range prompt
// Input: A = visible count (> 0), X = Huffman prompt string id
// Output: message printed via the message-line path
piw_print_prompt_with_count:
    sta piw_p1
#if C128
    php
    sei
#endif
    jsr huff_decode_string

    lda piw_p1
    sec
    sbc #1
    clc
    adc #$01                    // Screen code 'A'
    sta piw_qty

    ldy #0
!piw_prompt_patch_loop:
    lda hd_decode_buf,y
    beq !piw_prompt_print+
    cmp #$28                    // '('
    bne !piw_prompt_not_open+
    lda #$01                    // Screen code 'A'
    sta hd_decode_buf + 1,y
    jmp !piw_prompt_next+
!piw_prompt_not_open:
    cmp #$2d                    // '-'
    bne !piw_prompt_next+
    lda piw_qty
    sta hd_decode_buf + 1,y
!piw_prompt_next:
    iny
    cpy #41
    bcc !piw_prompt_patch_loop-

!piw_prompt_print:
#if C128
    lda zp_ptr0
    sta msg_src_lo
    lda zp_ptr0_hi
    sta msg_src_hi
    plp
    jsr msg_print_cached
    rts
#else
    jsr msg_print
    rts
#endif

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
    jsr input_get_key

    // '?' shows inventory (wearable items only) and re-prompts
    cmp #$3f
    bne !iw_not_inv+
    lda #$fe                    // Filter: wearable items
    jsr show_inv_and_restore
    jmp item_wear
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
    lda piw_item_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    jsr cmb_term_and_print

    lda #SFX_PICKUP
    jsr sound_play

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
    jsr input_get_key
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
    lda inv_ego,x
    sta fi_add_ego

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
    lda piw_item_id
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    jsr cmb_term_and_print

    lda #SFX_PICKUP
    jsr sound_play

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

// player_recalc_equipment — Recalculate AC, to-hit, to-damage from equipment
// Called after any equip/unequip action.
// player_calc_combat already handles DEX bonus + equipment AC (R1.6).
// This adds weapon to-hit/to-damage and ego bonuses.
// Clobbers: everything
player_recalc_equipment:
    // Resets PL_AC (with equipment), PL_TOHIT, PL_TODMG from stats
    jsr player_calc_combat

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

    // Ego AC bonus (Defender/HA — checked in banked code at $F000)
    ldx #EQUIP_WEAPON
    lda inv_ego,x
    beq !pre_no_ego_ac+
    jsr tramp_ego_get_ac_bonus
    beq !pre_no_ego_ac+
    clc
    adc player_data + PL_AC
    sta player_data + PL_AC
!pre_no_ego_ac:
!pre_no_weapon:

    // Sync back to ZP
    lda player_data + PL_AC
    sta zp_player_ac

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
    lda #ICAT_POTION
    ldx #HSTR_PIQ_QUAFF_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !iq_have_choices+
    clc
    rts
!iq_have_choices:
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr input_get_key

    // '?' shows inventory (potions only) and re-prompts
    cmp #$3f
    bne !iq_not_inv+
    lda #ICAT_POTION
    jsr show_inv_and_restore
    jmp item_quaff
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

    // Heal player HP (shared subroutine)
    lda piw_qty
    jsr eff_heal

    ldx #HSTR_PIQ_FEEL_BETTER
    jsr huff_print_msg

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
    jsr eff_heal

    ldx #HSTR_PIQ_MUCH_BETTER
    jsr huff_print_msg
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

// ============================================================
// item_read_scroll — Read a scroll from inventory
// Prompts "READ WHICH SCROLL (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
item_read_scroll:
    // Blindness check — can't read while blind
    lda zp_eff_blind
    beq !irs_can_see+
    ldx #HSTR_PIQ_CANT_READ
    jsr huff_print_msg
    clc
    rts
!irs_can_see:
    lda #ICAT_SCROLL
    ldx #HSTR_PIQ_READ_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !irs_have_choices+
    clc
    rts
!irs_have_choices:
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr input_get_key

    // '?' shows inventory (scrolls only) and re-prompts
    cmp #$3f
    bne !irs_not_inv+
    lda #ICAT_SCROLL
    jsr show_inv_and_restore
    jmp !irs_can_see-
!irs_not_inv:

    // Check for ESC or space -> cancel
    cmp #$03
    beq !irs_cancel_tramp+
    cmp #$20
    beq !irs_cancel_tramp+

    jsr piw_pick_filtered_inv_key
    bcs !irs_in_range+
!irs_cancel_tramp:
    jmp irs_cancel
!irs_in_range:
    stx piw_slot
    sta piw_item_id
    // Identify this scroll type
    ldx piw_item_id
    lda #1
    sta id_known,x

    // Remove from inventory
    ldx piw_slot
    jsr inv_remove_item

    // Apply effect based on item type.
    lda piw_item_id
    cmp #20
    bcc !irs_dispatch_generic+
    cmp #39
    bcs !irs_dispatch_generic+
    sec
    sbc #20
    tax
    lda irs_dispatch_lo,x
    sta zp_ptr1
    lda irs_dispatch_hi,x
    sta zp_ptr1_hi
    jmp (zp_ptr1)
!irs_dispatch_generic:
    jmp irs_effect_generic

irs_dispatch_lo:
    .byte <irs_effect_light, <irs_effect_identify, <irs_effect_teleport
    .byte <irs_effect_generic, <irs_effect_generic, <irs_effect_generic, <irs_effect_generic, <irs_effect_generic
    .byte <irs_effect_generic, <irs_effect_generic, <irs_effect_generic, <irs_effect_generic
    .byte <irs_effect_wor, <irs_effect_remove_curse, <irs_effect_enchant_weapon, <irs_effect_enchant_armor
    .byte <irs_effect_mon_confuse, <irs_effect_aggravate, <irs_effect_protect
irs_dispatch_hi:
    .byte >irs_effect_light, >irs_effect_identify, >irs_effect_teleport
    .byte >irs_effect_generic, >irs_effect_generic, >irs_effect_generic, >irs_effect_generic, >irs_effect_generic
    .byte >irs_effect_generic, >irs_effect_generic, >irs_effect_generic, >irs_effect_generic
    .byte >irs_effect_wor, >irs_effect_remove_curse, >irs_effect_enchant_weapon, >irs_effect_enchant_armor
    .byte >irs_effect_mon_confuse, >irs_effect_aggravate, >irs_effect_protect

irs_effect_light:
    // Light the room the player is in (shared subroutine)
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg

    sec
    rts

irs_effect_identify:
    // Interactive item identification (shared subroutine)
    jsr eff_identify_prompt
    sec
    rts

irs_effect_teleport:
    // Teleport player to random floor tile (shared subroutine)
    jsr eff_teleport_self

    ldx #HSTR_PIQ_TELEPORT
    jsr huff_print_msg

    sec
    rts

irs_effect_wor:
    // Word of Recall: set timer rng(15)+15 (overwrites, not stacks — matches umoria)
    lda #15
    jsr rng_range                   // [0, 14]
    clc
    adc #15                         // [15, 29]
    sta zp_eff_word_recall

    ldx #HSTR_PIQ_AIR_CRACKLE
    jsr huff_print_msg
    sec
    rts

irs_effect_remove_curse:
    jsr eff_remove_curse

    ldx #HSTR_PIQ_CLEANSED
    jsr huff_print_msg
    sec
    rts

irs_effect_enchant_weapon:
    // Find weapon in EQUIP_WEAPON slot
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !irs_ew_has+

    // No weapon equipped
    ldx #HSTR_PIQ_VIBRATION
    jsr huff_print_msg
    sec
    rts

!irs_ew_has:
    // If cursed: remove curse, set p1=0, recalc
    ldx #EQUIP_WEAPON
    lda inv_flags,x
    and #IF_CURSED
    beq !irs_ew_not_cursed+
    lda inv_flags + EQUIP_WEAPON
    and #~IF_CURSED & $ff
    sta inv_flags + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    jsr player_recalc_equipment
    jmp !irs_ew_msg+

!irs_ew_not_cursed:
    // Check if already at +5 cap
    ldx #EQUIP_WEAPON
    lda inv_p1,x
    cmp #5
    bcc !irs_ew_inc+

    // Already at cap
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

!irs_ew_inc:
    inc inv_p1 + EQUIP_WEAPON
    jsr player_recalc_equipment

!irs_ew_msg:
    ldx #HSTR_PIQ_WPN_GLOW
    jsr huff_print_msg
    sec
    rts

irs_effect_enchant_armor:
    // Find armor in EQUIP_BODY slot
    ldx #EQUIP_BODY
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !irs_ea_has+

    // No armor equipped
    ldx #HSTR_PIQ_VIBRATION
    jsr huff_print_msg
    sec
    rts

!irs_ea_has:
    // If cursed: remove curse, set p1=0, recalc
    ldx #EQUIP_BODY
    lda inv_flags,x
    and #IF_CURSED
    beq !irs_ea_not_cursed+
    lda inv_flags + EQUIP_BODY
    and #~IF_CURSED & $ff
    sta inv_flags + EQUIP_BODY
    lda #0
    sta inv_p1 + EQUIP_BODY
    jsr player_recalc_equipment
    jmp !irs_ea_msg+

!irs_ea_not_cursed:
    // Check if already at +5 cap
    ldx #EQUIP_BODY
    lda inv_p1,x
    cmp #5
    bcc !irs_ea_inc+

    // Already at cap
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

!irs_ea_inc:
    inc inv_p1 + EQUIP_BODY
    jsr player_recalc_equipment

!irs_ea_msg:
    ldx #HSTR_PIQ_ARM_GLOW
    jsr huff_print_msg
    sec
    rts

irs_effect_mon_confuse:
    // Set confuse-on-melee flag
    lda #1
    sta zp_confuse_melee

    ldx #HSTR_PIQ_HANDS_GLOW
    jsr huff_print_msg
    sec
    rts

irs_effect_aggravate:
    jsr eff_aggravate

    ldx #HSTR_PIQ_HUMMING
    jsr huff_print_msg
    sec
    rts

irs_effect_protect:
    // Protect from Evil: timer rng(25)+25
    // NOTE: Timer is infrastructure only — damage reduction from evil monsters
    // will be integrated when effect consumption is added in a later phase.
    lda #25
    jsr rng_range                   // [0, 24]
    clc
    adc #25                         // [25, 49]
    clc
    adc zp_eff_protect
    bcc !irs_prot_ok+
    lda #255
!irs_prot_ok:
    sta zp_eff_protect

    ldx #HSTR_PIQ_PROTECTED
    jsr huff_print_msg
    sec
    rts

irs_effect_generic:
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    sec
    rts

irs_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
    rts

// ============================================================
// item_aim_wand — Aim a wand from inventory
// Prompts "AIM WHICH WAND (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
item_aim_wand:
    lda #ICAT_WAND
    ldx #HSTR_PIW_AIM_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !iaw_have_choices+
    clc
    rts
!iaw_have_choices:
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr input_get_key

    // '?' shows inventory (wands only) and re-prompts
    cmp #$3f
    bne !iaw_not_inv+
    lda #ICAT_WAND
    jsr show_inv_and_restore
    jmp item_aim_wand
!iaw_not_inv:

    // Check for ESC or space -> cancel
    cmp #$03
    beq !iaw_cancel_tramp+
    cmp #$20
    beq !iaw_cancel_tramp+

    jsr piw_pick_filtered_inv_key
    bcs !iaw_in_range+
!iaw_cancel_tramp:
    jmp !iaw_cancel+
!iaw_in_range:
    stx piw_slot
    sta piw_item_id
    // Check charges > 0
    ldx piw_slot
    lda inv_p1,x
    bne !iaw_has_charges+

    ldx #HSTR_PIW_NO_CHARGES
    jsr huff_print_msg
    clc
    rts

!iaw_has_charges:
    // Decrement charges
    ldx piw_slot
    dec inv_p1,x

    // Auto-identify wand type
    ldx piw_item_id
    lda #1
    sta id_known,x

    // Dispatch by item type
    lda piw_item_id
    cmp #39                         // Wand of Light
    beq !iaw_light+
    cmp #40                         // Wand of Lightning
    beq !iaw_lightning+
    cmp #41                         // Wand of Frost
    beq !iaw_frost+
    cmp #42                         // Wand of Stinking Cloud
    beq !iaw_cloud+
    // Unknown wand type — shouldn't happen
    sec
    rts

!iaw_light:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg
    sec
    rts

!iaw_lightning:
    lda #3
    ldx #8
    ldy #0
    jsr eff_bolt
    ldx #HSTR_PIW_WAND_BOLT
    jsr huff_print_msg
    sec
    rts

!iaw_frost:
    lda #4
    ldx #8
    ldy #0
    jsr eff_bolt
    ldx #HSTR_PIW_WAND_FROST
    jsr huff_print_msg
    sec
    rts

!iaw_cloud:
    jsr eff_directional_monster
    bcc !iaw_cloud_miss+
    // Monster found — set MX_CONFUSE
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
    jsr huff_print_msg
    sec
    rts
!iaw_cloud_miss:
    ldx #HSTR_PIW_WAND_MISS
    jsr huff_print_msg
    sec
    rts

!iaw_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
    rts

// ============================================================
// item_use_staff — Use a staff from inventory
// Prompts "USE WHICH STAFF (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
item_use_staff:
    lda #ICAT_STAFF
    ldx #HSTR_PIW_USE_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !ius_have_choices+
    clc
    rts
!ius_have_choices:
    jsr input_prepare_followup_key

    // Wait for keypress
    jsr input_get_key

    // '?' shows inventory (staves only) and re-prompts
    cmp #$3f
    bne !ius_not_inv+
    lda #ICAT_STAFF
    jsr show_inv_and_restore
    jmp item_use_staff
!ius_not_inv:

    // Check for ESC or space -> cancel
    cmp #$03
    beq !ius_cancel_tramp+
    cmp #$20
    beq !ius_cancel_tramp+

    jsr piw_pick_filtered_inv_key
    bcs !ius_in_range+
!ius_cancel_tramp:
    jmp !ius_cancel+
!ius_in_range:
    stx piw_slot
    sta piw_item_id
    // Check charges > 0
    ldx piw_slot
    lda inv_p1,x
    bne !ius_has_charges+

    ldx #HSTR_PIW_STAFF_EMPTY
    jsr huff_print_msg
    clc
    rts

!ius_has_charges:
    // Decrement charges
    ldx piw_slot
    dec inv_p1,x

    // Auto-identify staff type
    ldx piw_item_id
    lda #1
    sta id_known,x

    // Dispatch by item type
    lda piw_item_id
    cmp #43                         // Staff of Light
    beq !ius_light+
    cmp #44                         // Staff of Detect Monsters
    beq !ius_detect+
    cmp #45                         // Staff of Teleportation
    beq !ius_teleport+
    cmp #46                         // Staff of Cure Light Wounds
    beq !ius_clw+
    // Unknown staff type
    sec
    rts

!ius_light:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg
    sec
    rts

!ius_detect:
    jsr eff_detect_monsters
    ldx #HSTR_PIQ_SENSE
    jsr huff_print_msg
    sec
    rts

!ius_teleport:
    jsr eff_teleport_self
    ldx #HSTR_PIQ_TELEPORT
    jsr huff_print_msg
    sec
    rts

!ius_clw:
    // Roll 1d8+1 for healing
    lda #1
    ldx #8
    ldy #1
    jsr math_dice
    lda zp_math_a                   // Low byte of result (sufficient for 2-9)
    jsr eff_heal
    ldx #HSTR_PIQ_FEEL_BETTER
    jsr huff_print_msg
    sec
    rts

!ius_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
    rts

// Strings migrated to Huffman compression (HSTR_PIW_*, HSTR_PIQ_* in huffman_data.s)

// ============================================================
// item_gain_spell — Study a spell book to learn qualifying spells
// Each book covers 4 spells. Learns all spells in that range where
// player_level >= spell_level and spell not already known.
// Books are NOT consumed.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================

item_gain_spell:
    // Check if player has a spell type at all
    lda player_data + PL_SPELL_TYPE
    bne !igs_can_cast+
    ldx #HSTR_IGS_NO_MAGIC
    jsr huff_print_msg
    clc
    rts

!igs_can_cast:
    lda #ICAT_BOOK
    ldx #HSTR_IGS_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !igs_have_choices+
    clc
    rts
!igs_have_choices:
    jsr input_prepare_followup_key

    jsr input_get_key

    // '?' shows inventory (books only) and re-prompts
    cmp #$3f
    bne !igs_not_inv+
    lda #ICAT_BOOK
    jsr show_inv_and_restore
    jmp !igs_can_cast-
!igs_not_inv:

    // ESC or space → cancel
    cmp #$20
    beq !igs_cancel_early+
    cmp #$1b
    beq !igs_cancel_early+

    jsr piw_pick_filtered_inv_key
    bcs !igs_slot_ok+
!igs_cancel_early:
    clc
    rts
!igs_slot_ok:
    stx piw_slot
    // Look up book metadata: spell range and class
    jsr book_get_info           // A = spell_start, X = spell_class, C=0
    bcc !igs_book_ok+
    jmp !igs_cancel+            // Safety: not in book table
!igs_book_ok:
    sta igs_spell_start
    stx igs_spell_class

    // Check class matches player's spell type
    lda player_data + PL_SPELL_TYPE
    cmp igs_spell_class
    beq !igs_type_ok+
    ldx #HSTR_IGS_WRONG_TYPE
    jsr huff_print_msg
    clc
    rts

!igs_type_ok:
    // Set up spell level table pointer
    lda igs_spell_class
    cmp #SPELL_MAGE
    bne !igs_priest_lvl+
    lda #<mage_spell_level
    sta zp_ptr1
    lda #>mage_spell_level
    sta zp_ptr1_hi
    jmp !igs_lvl_set+
!igs_priest_lvl:
    lda #<priest_spell_level
    sta zp_ptr1
    lda #>priest_spell_level
    sta zp_ptr1_hi
!igs_lvl_set:

    // Loop over 4 spells in this book's range
    lda #0
    sta igs_learned_count
    lda igs_spell_start
    sta igs_spell_idx

!igs_spell_loop:
    // Check player_level >= required spell level
    ldy igs_spell_idx
    lda player_data + PL_LEVEL
    cmp (zp_ptr1),y             // C set if player_level >= req_level
    bcc !igs_next_spell+        // Player level too low, skip

    // Check if spell already known
    lda igs_spell_idx
    cmp #8
    bcs !igs_hi_check+

    // Lo byte (spells 0-7)
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    bne !igs_next_spell+        // Already known
    // Learn: set bit in lo byte
    lda spell_bit_mask,x
    ora player_data + PL_SPELLS_KNOWN
    sta player_data + PL_SPELLS_KNOWN
    inc igs_learned_count
    jmp !igs_next_spell+

!igs_hi_check:
    // Hi byte (spells 8-15)
    sec
    sbc #8
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    bne !igs_next_spell+        // Already known
    // Learn: set bit in hi byte
    lda spell_bit_mask,x
    ora player_data + PL_SPELLS_KNOWN_HI
    sta player_data + PL_SPELLS_KNOWN_HI
    inc igs_learned_count

!igs_next_spell:
    inc igs_spell_idx
    lda igs_spell_idx
    sec
    sbc igs_spell_start
    cmp #4                      // Done 4 spells?
    bcc !igs_spell_loop-

    // Check results
    lda igs_learned_count
    beq !igs_none_learned+

    // Learned at least one spell
    ldx #HSTR_IGS_SUCCESS
    jsr huff_print_msg

    lda #SFX_LEVELUP
    jsr sound_play

    sec                         // Turn consumed
    rts

!igs_none_learned:
    ldx #HSTR_IGS_NO_NEW
    jsr huff_print_msg
    clc                         // No turn consumed
    rts

!igs_cancel:
    clc
    rts

// Gain spell scratch
igs_spell_idx:      .byte 0
igs_spell_start:    .byte 0
igs_spell_class:    .byte 0
igs_learned_count:  .byte 0

// Gain spell strings migrated to Huffman (HSTR_IGS_* in huffman_data.s)

// ============================================================
// item_refuel — Refuel a brass lantern with a flask of oil
// Checks EQUIP_LIGHT for lantern, scans inventory for flask.
// Output: carry set = turn consumed, carry clear = no action
// Clobbers: everything
// ============================================================
item_refuel:
    // 1. Check EQUIP_LIGHT has a brass lantern (type 14)
    ldx #EQUIP_LIGHT
    lda inv_item_id,x
    cmp #14
    beq !ir_has_lamp+

    // Not using a lamp
    ldx #HSTR_PIR_NOT_LAMP
    jsr huff_print_msg
    clc
    rts

!ir_has_lamp:
    // 2. Scan carried inventory for Flask of Oil (type 61)
    ldx #0
!ir_scan:
    cpx #MAX_INV_SLOTS
    bcs !ir_no_oil+
    lda inv_item_id,x
    cmp #ITEM_FLASK_OIL
    beq !ir_found_oil+
    inx
    jmp !ir_scan-

!ir_no_oil:
    ldx #HSTR_PIR_NO_OIL
    jsr huff_print_msg
    clc
    rts

!ir_found_oil:
    stx piw_slot

    // 3. Add flask's p1 to lantern's p1, cap at LANTERN_MAX_CHARGES
    lda inv_p1,x
    clc
    adc inv_p1 + EQUIP_LIGHT
    bcs !ir_overflow+
    cmp #LANTERN_MAX_CHARGES + 1
    bcc !ir_no_overflow+

!ir_overflow:
    lda #LANTERN_MAX_CHARGES
    sta inv_p1 + EQUIP_LIGHT

    // 4. Overflow messages
    ldx #HSTR_PIR_OVERFLOW
    jsr huff_print_msg
    ldx #HSTR_PIR_FULL
    jsr huff_print_msg
    jmp !ir_remove_flask+

!ir_no_overflow:
    sta inv_p1 + EQUIP_LIGHT

    // 5. Refueled message
    ldx #HSTR_PIR_REFUELED
    jsr huff_print_msg

!ir_remove_flask:
    // 6. Remove flask from inventory
    ldx piw_slot
    jsr inv_remove_item

    sec
    rts
