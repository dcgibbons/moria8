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
    jsr piw_select_filtered_inv
    bcs !iw_in_range+
    rts
!iw_in_range:
    stx piw_slot

    // Save carried item data into the fi_add scratch (before any swap);
    // nothing below writes it before the message reads it back
    sta piw_item_id             // A already has inv_item_id[slot]
    ldx piw_slot
    jsr inv_slot_to_fi_add

    // The filtered picker already excludes non-equippable categories and oil.
    ldx piw_slot
    jsr item_get_category_inv_x
    tax
    lda equip_slot_for_cat,x
    cmp #EQUIP_RING             // VMS moria.inc:528: the right hand when free,
    bne !iw_slot+               // else the left, replacing its ring
    ldy inv_item_id + EQUIP_RING
    iny                         // FI_EMPTY ($ff): free
    beq !iw_slot+
    lda #EQUIP_RING2
!iw_slot:
    sta piw_equip

    // VMS wear (moria.inc:539-552): a cursed item in the target slot stays on.
    // Checked before the swap and the stack paths; empty slots hold flags 0.
    tax
    lda inv_flags,x
    and #IF_CURSED
    beq !iw_not_cursed+
    ldx #HSTR_PIW_CURSED
    jmp piw_msg_no_turn         // no turn, nothing moved
!iw_not_cursed:

    // A stack (wooden torches, VMS/Umoria): one goes on, the rest stay, and
    // what was worn goes back through inv_add_item.
    ldy piw_slot
    lda inv_qty,y
    cmp #2
    bcs !iw_stack+

    // Check if equip slot already occupied -> swap
    ldx piw_equip
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !+
    jmp !iw_no_swap+
!:

    // Remove the old item's direct current-stat adjustment before the swap.
    clc
    jsr player_adjust_equipment_stat

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

!iw_stack:
    ldx piw_equip
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !iw_stack_one+
    jsr inv_slot_to_fi_add      // what is worn now goes to the pack
    jsr inv_add_item
    bcs !iw_stack_off+
    lda zp_player_x             // the pack overflows: it drops at the player's
    sta fi_add_x                // feet (VMS inven_carry overflow, Umoria pack
    lda zp_player_y             // overflow); refused until 2026-10-25
    sta fi_add_y
    jsr floor_item_add          // under the player: hidden by '@', no redraw
    bcs !iw_stack_off+
    jmp piw_pack_full           // no room on the floor either: nothing changes
!iw_stack_off:
    ldx piw_equip
    clc
    jsr player_adjust_equipment_stat
    ldx piw_equip
    jsr inv_remove_item         // Drop old worn item from equip & weight
!iw_stack_one:
    ldx piw_slot
    dec inv_qty,x
    jsr inv_slot_to_fi_add      // one of the stack goes on
    lda #1
    sta fi_add_qty
    bne !iw_write_equip+        // always

!iw_no_swap:
    // Clear the source carried slot; restore the single worn item's weight.
    ldx piw_slot
    jsr inv_remove_item
    jsr inven_add_fi_add_weight

!iw_write_equip:
    // Write saved carried item data to equipment slot
    ldx piw_equip
    jsr fi_add_to_inv_slot

    // Add the new item's direct current-stat adjustment.
    sec
    jsr player_adjust_equipment_stat

    // If equipping a light, set light radius: none from a burnt-out one
    lda piw_equip
    cmp #EQUIP_LIGHT
    bne !iw_not_light+
    lda inv_p1 + EQUIP_LIGHT
    beq !iw_light_radius+
    lda #1
!iw_light_radius:
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
    jmp piw_report_item_use     // fi_add_* still hold the worn item

// piw_report_item_use — Shared "used item" report tail: describe item,
// period, print, pickup sound, consume turn. Input: piw_item_id set.
piw_report_item_use:
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

// item_takeoff — Remove an equipped item back to carried inventory
// Prompts "TAKE OFF WHICH ITEM (A-H)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
item_takeoff:
    jsr piw_count_visible_equip
    bne !ito_have_choices+
    ldx #HSTR_PIW_NOTHING
    jmp piw_msg_no_turn
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
    jsr show_equip_and_select
    and #$7f
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
    jmp piw_msg_no_turn

!ito_not_cursed:
    // Save equipped item's fields before inv_add_item
    ldx piw_equip
    lda inv_flags,x
    sta piw_flags
    lda inv_ego,x
    sta piw_ego

    // Set up fi_add scratch for inv_add_item
    jsr inv_slot_to_fi_add

    // Find empty carried slot and add
    jsr inv_add_item
    bcs !ito_added+

    // Pack full
piw_pack_full:
    ldx #HSTR_UIS_PACK_FULL
// piw_msg_no_turn — print Huffman message X, no turn consumed (carry clear)
piw_msg_no_turn:
    jsr huff_print_msg
    clc
    rts

!ito_added:
    // X = new carried slot from inv_add_item
    // Copy saved flags to new carried slot
    lda piw_flags
    sta inv_flags,x

    // Remove the equipped item's direct current-stat adjustment.
#if HAL_PLATFORM_COMPACT_PLAY_SLOT
    ldx piw_equip
#endif
    clc
    jsr player_adjust_equipment_stat

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
    jmp piw_report_item_use

!ito_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jmp piw_msg_no_turn

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

    // Check category via page-aware inventory helper (preserves X)
    sta piw_item_id             // Save slot_lo
    jsr item_get_category_inv_x
    cmp #ICAT_FOOD
    beq !ie_found+

!ie_next:
    inc piw_slot
    jmp !ie_scan-

!ie_no_food:
    ldx #HSTR_PIW_NO_FOOD
    jmp piw_msg_no_turn

!ie_found:
    // piw_slot = inventory slot, piw_item_id = slot_lo, item_cur_page = $00
    .assert "All food items occupy Page 0 20..49 with mushrooms 20..40 and Waybreads 43..44", ITEM_MUSHROOM_OF_POISON == 20 && ITEM_HAIRY_MOLD_OF_CURE_SERIOUS_WOUNDS == 40 && ITEM_RATION_OF_FOOD == 41 && ITEM_FOOD_SLIME_MOLD == 42 && ITEM_PIECE_OF_ELVISH_WAYBREAD_L6 == 43 && ITEM_PIECE_OF_ELVISH_WAYBREAD_L20 == 44 && ITEM_PINT_OF_FINE_WINE == 49 && ITEM_PAGE_PINT_OF_FINE_WINE == 0, true
    lda item_cur_page
    sta piw_ego                 // Save page bit across inv_consume_one
    bne !ie_slime+
    lda piw_item_id
    cmp #ITEM_RATION
    beq !ie_ration+
    sec
    sbc #ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L6
    cmp #2
    bcc !ie_waybread+
!ie_slime:
    // Default to slime mold food value
    lda #FOOD_SLIME_VALUE_LO
    sta zp_temp0
    lda #FOOD_SLIME_VALUE_HI
    sta zp_temp1
    jmp !ie_add_food+
!ie_waybread:
    lda #FOOD_MAX_LO
    sta zp_temp0
    lda #FOOD_MAX_HI
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
    lda #FOOD_MAX_LO
    cmp zp_player_food
    lda #FOOD_MAX_HI
    sbc zp_player_food_hi
    bcs !ie_cap_ok+             // Food <= 4000 (unsigned)
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
    // Use one food from the stack
    ldx piw_slot
    jsr inv_consume_one

    // Build message
    lda #0
    sta cmb_buf_idx

    ldx #HSTR_PIW_EAT
    jsr huff_append_combat

    lda piw_ego
    sta fi_add_ego              // Preserve page bit (food has ego 0)
    lda piw_item_id
    jsr item_append_name

    // Check if slime mold for different flavor text (Page 0 only)
    lda piw_ego
    bne !ie_delicious+
    lda piw_item_id
    cmp #ITEM_SLIME_MOLD
    beq !ie_yuck+

!ie_delicious:
    ldx #HSTR_PIW_DELICIOUS
    jmp !ie_end_msg+
!ie_yuck:
    ldx #HSTR_PIW_YUCK
!ie_end_msg:
    jsr huff_append_combat

    jsr cmb_term_and_print

    // Extended mushroom (20..40) / Elvish Waybread (43..44) effects; skip Ration, Slime Mold, and plain foods
    lda piw_ego
    bne !ie_done+
    lda piw_item_id
    cmp #ITEM_SLOT_MUSHROOM_OF_POISON
    bcc !ie_done+
    cmp #ITEM_SLOT_HAIRY_MOLD_OF_CURE_SERIOUS_WOUNDS + 1
    bcc !ie_ext_effect+
    sec
    sbc #ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L6
    cmp #2
    bcs !ie_done+
!ie_ext_effect:
#if HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
    jsr tramp_eff_ext_eat
#else
    jsr eff_ext_eat_piw
#endif
!ie_done:
    sec                         // Turn consumed
    rts

#if !PLAYER_RECALC_EQUIPMENT_EXTERNAL
    #import "player_recalc_equipment.s"
#endif

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
// ============================================================
// piq_quaff_identify — Mark item type X identified, but only when quaffing it
// produces a noticeable effect (upstream VMS hp_player). Heal-family potions
// at full HP are a silent no-op: no message and no identification. Everything
// else identifies on quaff.
// On C128 the identical helper lives in item_defs.s (this file is in the C128
// banked runtime, which has only ~9 bytes free).
// Input: X = item type ID. Clobbers: A, Y (X preserved via id_known_set).
// ============================================================
piq_quaff_identify:
    bit item_cur_page
    bvs !pqi_ident+             // All Page 1 potions identify unconditionally on quaff
    txa
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    beq !pqi_heal+
    cmp #ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS
    beq !pqi_heal+
    cmp #ITEM_SLOT_POTION_OF_HEALING
    beq !pqi_heal+
    cmp #ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS
    beq !pqi_heal+
!pqi_ident:
    jmp id_known_set        // X = item type ID
!pqi_heal:
    // Full HP -> the heal is a no-op -> stays unidentified.
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    lda zp_player_hp_hi
    sbc zp_player_mhp_hi
    bcc !pqi_ident-             // HP < max HP (unsigned)
    rts
#endif

// ============================================================
// item_quaff — Quaff a potion from inventory
// Prompts "QUAFF WHICH POTION (A-V)?", waits for keypress.
// Output: carry set = turn consumed, carry clear = cancelled
// Clobbers: everything
// ============================================================
item_quaff:
    lda #ICAT_POTION
    ldx #HSTR_PIQ_QUAFF_PROMPT
    jsr piw_select_filtered_inv
    bcs !iq_in_range+
    rts
!iq_in_range:
    stx piw_slot
    sta piw_item_id
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta piw_ego
    sta item_cur_page
    // The prompt has been answered; clear it so an effect that prints nothing
    // (e.g. a heal at full HP) doesn't leave it lingering like a -more- prompt.
    jsr msg_clear
    // Identify the potion type only when its effect will be noticeable
    // (upstream VMS hp_player): heal-family potions at full HP are a silent
    // no-op, so those stay unidentified. Only A2/C128 have room for the gate;
    // C64/Plus4 item test/product layouts are full, so they keep the legacy
    // unconditional identify (documented layout exemption).
#if HAL_PLATFORM_AUX_PERSISTENT_DATA || HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
    ldx piw_item_id
    jsr piq_quaff_identify
#else
    ldx piw_item_id
    jsr id_known_set
#endif

    // Use one potion from the stack (clobbers item_cur_page via weight helper)
    ldx piw_slot
    jsr inv_consume_one

    // All 45 VMS potions live on Page 0 (50..94)
    .assert "All 45 VMS potions occupy Page 0 50..94", ITEM_POTION_OF_GAIN_STRENGTH == 50 && ITEM_POTION_OF_INFRAVISION == 94 && ITEM_PAGE_POTION_OF_INFRAVISION == 0, true
    lda piw_ego
    sta item_cur_page
    bne !iq_gen_jmp+

    lda piw_item_id
    cmp #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    bcc !iq_gen_jmp+
    cmp #ITEM_SLOT_POTION_OF_INFRAVISION + 1
    bcs !iq_gen_jmp+

    ldx #8
!iq_loc_scan:
    cmp iq_local_ids,x
    beq !iq_loc_hit+
    dex
    bpl !iq_loc_scan-

    ldx #10
!iq_p3_scan:
    cmp iq_p3_ids,x
    beq !iqd_phase3+
    dex
    bpl !iq_p3_scan-

    // Extended Page-0 potion (25 types)
#if HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
    jsr tramp_eff_ext_quaff
#else
    jsr eff_ext_quaff_piw
#endif
    sec
    rts
!iq_gen_jmp:
    jmp iq_effect_generic
!iq_loc_hit:
    lda iq_dispatch_lo,x
    sta zp_ptr1
    lda iq_dispatch_hi,x
    sta zp_ptr1_hi
    jmp (zp_ptr1)

!iqd_phase3:
#if HAL_PLATFORM_ITEM_TABLES_SPLIT_RESIDENT
    // Phase 3 potion handlers are resident; no overlay or disk access.
    jsr hal_quaff_p3_dispatch
    sec
    rts
#elif HAL_PLATFORM_COMPACT_PLAY_SLOT
    // Phase 3 potion handlers live in the spell overlay (items
    // overlay is full). Loading it here would evict this items-overlay
    // continuation, so the swap runs through the resident trampoline.
    lda #<iq_dispatch_p3_spell
    ldy #>iq_dispatch_p3_spell
    jsr piw_call_spell_a_y
    sec
    rts
#else
    cmp #ITEM_SLOT_POTION_OF_HEALING
    beq !iq_effect_healing+
    cmp #ITEM_SLOT_POTION_OF_RESIST_HEAT
    beq !iq_effect_resist_heat+
    cmp #ITEM_SLOT_POTION_OF_RESIST_COLD
    beq !iq_effect_resist_cold+
    cmp #ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS
    beq !iq_effect_cure_critical+
    cmp #ITEM_SLOT_POTION_OF_NEUTRALIZE_POISON
    beq !iq_effect_neutralize+
    jsr eff_potion_gain_stat        // A = the potion's type (6 gain-stat potions)
    sec
    rts

!iq_effect_healing:
    jmp eff_potion_healing          // 1000 HP + cures (eff_potion_cure.s)

!iq_effect_cure_critical:
    // 6d7 HP, cures blindness, confusion and poison
    lda #EFF_CURE_ALL
    ldx #7
    ldy #6
    jmp eff_potion_heal_cure

!iq_effect_resist_heat:
    // Resist heat/fire for randint(10) + 10 turns
    lda #10
    jsr rng_range
    sec                             // + 1: VMS randint(10) + 10, 11-20
    adc #10
    clc
    adc zp_eff_resist
    bcc !iq_rh_store+
    lda #255
!iq_rh_store:
    sta zp_eff_resist
    sec
    rts

!iq_effect_resist_cold:
    // Resist cold for randint(10) + 10 turns (frost breath divides by it)
    lda #10
    jsr rng_range
    sec                             // + 1: VMS randint(10) + 10, 11-20
    adc #10
    clc
    adc eff_resist_cold_timer
    bcc !iq_rc_store+
    lda #255
!iq_rc_store:
    sta eff_resist_cold_timer
    sec
    rts

!iq_effect_neutralize:
    jsr eff_cure_poison
    ldx #HSTR_EFF_POISON_END
    jmp iq_msg_turn
#import "eff_gain_stat.s"
#endif

iq_local_ids:
    .byte ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS, ITEM_SLOT_POTION_OF_SPEED, ITEM_SLOT_POTION_OF_POISON
    .byte ITEM_SLOT_POTION_OF_CURE_SERIOUS_WOUNDS, ITEM_SLOT_POTION_OF_RESTORE_MANA, ITEM_SLOT_POTION_OF_HEROISM
    .byte ITEM_SLOT_POTION_OF_BLINDNESS, ITEM_SLOT_POTION_OF_CONFUSION, ITEM_SLOT_POTION_OF_INFRAVISION
iq_dispatch_lo:
    .byte <iq_effect_cure, <iq_effect_speed, <iq_effect_poison
    .byte <iq_effect_csw, <iq_effect_restore_mana, <iq_effect_heroism
    .byte <iq_effect_blindness, <iq_effect_confusion, <iq_effect_infravision
iq_dispatch_hi:
    .byte >iq_effect_cure, >iq_effect_speed, >iq_effect_poison
    .byte >iq_effect_csw, >iq_effect_restore_mana, >iq_effect_heroism
    .byte >iq_effect_blindness, >iq_effect_confusion, >iq_effect_infravision
.assert "iq_local_ids/lo/hi have 9 entries each", (iq_dispatch_lo - iq_local_ids == 9) && (iq_dispatch_hi - iq_dispatch_lo == 9) && (* - iq_dispatch_hi == 9), true

iq_p3_ids:
    .byte ITEM_SLOT_POTION_OF_GAIN_STRENGTH, ITEM_SLOT_POTION_OF_GAIN_INTELLIGENCE, ITEM_SLOT_POTION_OF_GAIN_WISDOM
    .byte ITEM_SLOT_POTION_OF_CHARISMA, ITEM_SLOT_POTION_OF_GAIN_CONSTITUTION, ITEM_SLOT_POTION_OF_GAIN_DEXTERITY
    .byte ITEM_SLOT_POTION_OF_CURE_CRITICAL_WOUNDS, ITEM_SLOT_POTION_OF_HEALING, ITEM_SLOT_POTION_OF_RESIST_HEAT
    .byte ITEM_SLOT_POTION_OF_RESIST_COLD, ITEM_SLOT_POTION_OF_NEUTRALIZE_POISON
.assert "iq_p3_ids has 11 entries", * - iq_p3_ids, 11

iq_effect_cure:
    // Cure Light Wounds: 2d7 HP, cures blindness (eff_potion_cure.s)
    lda #EFF_CURE_BLIND
    ldx #7
    ldy #2
    jmp eff_potion_heal_cure

iq_effect_speed:
    // Potion of Speed: fast += randint(25) + 15 (VMS Moria potions.inc;
    // Umoria player_quaff.cpp), 16-40 turns. zp_eff_speed is one signed
    // timer (> 0 haste, < 0 slow): a signed add, so haste while slowed
    // cancels slow turn for turn, and stacking stops at +127 instead of
    // wrapping into slow (as pmx_add_speed_msg).
    lda #25
    jsr rng_range                   // [0, 24]
    sec
    adc #15                         // [16, 40]; carry clear
    adc zp_eff_speed
    bvc !iq_speed_ok+
    lda #$7f                        // Cap at +127
!iq_speed_ok:
    sta zp_eff_speed

    ldx #HSTR_PIQ_SPEED
    jmp iq_msg_turn

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
    jmp iq_msg_turn

iq_effect_csw:
    // Cure Serious Wounds: 4d7 HP, cures blindness and confusion
    lda #EFF_CURE_BLIND | EFF_CURE_CONFUSE
    ldx #7
    ldy #4
    jmp eff_potion_heal_cure

iq_effect_restore_mana:
    // Restore Mana: set MP = max MP
    lda zp_player_mmp
    sta zp_player_mp
    sta player_data + PL_MANA

    ldx #HSTR_PIQ_MIND_CLEAR
    jmp iq_msg_turn

iq_effect_heroism:
    // Heroism: first activation grants +10 max/current HP and clears fear.
    lda zp_eff_hero
    bne !iq_hero_timer+
    lda player_data + PL_MHP_LO
    clc
    adc #10
    sta player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    adc #0
    sta player_data + PL_MHP_HI
    sta zp_player_mhp_hi

    lda player_data + PL_HP_LO
    clc
    adc #10
    sta player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_HP_HI
    adc #0
    sta player_data + PL_HP_HI
    sta zp_player_hp_hi
!iq_hero_timer:
    lda #0
    sta eff_fear_timer

    // Set zp_eff_hero timer (rng(25)+25), stacks
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
    jmp iq_msg_turn

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
    jmp iq_msg_turn

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
    jmp iq_msg_turn

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
    jmp iq_msg_turn

iq_effect_generic:
    ldx #HSTR_PIQ_NOTHING
// iq_msg_turn — print Huffman message X, turn consumed (carry set)
iq_msg_turn:
    jsr huff_print_msg
    sec
    rts

#if HAL_PLATFORM_COMPACT_PLAY_SLOT
piw_call_spell_a_y:
    sta tsci_target+1
    sty tsci_target+2
    lda piw_ego
    sta item_cur_page
    lda piw_item_id
    sta hal_tsci_arg
    jmp tramp_spell_call_items
#endif
#if !HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
    #import "eff_item_extended.s"
#endif
