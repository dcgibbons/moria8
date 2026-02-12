// spell_effects.s — Shared effect subroutines for spells, potions, scrolls, etc.
//
// Phase 7.0: Extracted from player_items.s inline handlers.
// Each subroutine implements a single effect and does NOT print messages
// (callers handle messaging) unless noted.
//
// Subroutines:
//   eff_heal            — Heal player HP by amount in A
//   eff_light_room      — Light the room the player occupies
//   eff_teleport_self   — Teleport player to random floor tile
//   eff_identify_prompt — Interactive item identification (prints its own messages)
//   eff_cure_poison     — Clear poison status
//   eff_detect_monsters — Reveal all active monsters on map
//   eff_remove_curse    — Clear IF_CURSED on all equipped items

// ============================================================
// Scratch variables
// ============================================================
eff_target_slot: .byte 0           // Target slot for identify
eff_room_idx:    .byte 0           // Room loop index for light

// ============================================================
// eff_heal — Heal player HP
// Input: A = heal amount (8-bit, pre-rolled)
// Output: HP updated in ZP and player_data, capped at max
// Clobbers: A
// ============================================================
eff_heal:
    clc
    adc zp_player_hp_lo
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    adc #0
    sta zp_player_hp_hi

    // Cap at max HP (16-bit compare)
    lda zp_player_hp_hi
    cmp zp_player_mhp_hi
    bcc !eh_ok+
    bne !eh_clamp+
    lda zp_player_hp_lo
    cmp zp_player_mhp_lo
    bcc !eh_ok+
    beq !eh_ok+
!eh_clamp:
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
!eh_ok:
    // Sync to player_data
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    rts

// ============================================================
// eff_light_room — Light the room the player is in
// Input: none (reads zp_player_x/y, room_* arrays)
// Output: room lit, vis_room_revealed set
// Clobbers: A, X
// ============================================================
eff_light_room:
    lda #0
    sta eff_room_idx

!elr_loop:
    ldx eff_room_idx
    cpx room_count
    bcs !elr_corridor+              // Player not in any room

    // Check bounds: player_x in [room_x-1, room_x+room_w]
    lda room_x,x
    sec
    sbc #1
    cmp zp_player_x
    beq !elr_lx_ok+
    bcs !elr_next+
!elr_lx_ok:
    lda room_x,x
    clc
    adc room_w,x
    cmp zp_player_x
    bcc !elr_next+

    // Check bounds: player_y in [room_y-1, room_y+room_h]
    lda room_y,x
    sec
    sbc #1
    cmp zp_player_y
    beq !elr_ly_ok+
    bcs !elr_next+
!elr_ly_ok:
    lda room_y,x
    clc
    adc room_h,x
    cmp zp_player_y
    bcc !elr_next+

    // Player is in room X — light it
    lda #1
    sta room_lit,x
    sta vis_room_revealed           // Trigger full redraw
    rts

!elr_next:
    inc eff_room_idx
    jmp !elr_loop-

!elr_corridor:
    // In corridor — just set vis_room_revealed for redraw
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_teleport_self — Teleport player to random floor tile
// Input: none (reads zp_player_x/y)
// Output: player moved, FLAG_OCCUPIED updated, vis_room_revealed set
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_teleport_self:
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
    rts

// ============================================================
// eff_identify_prompt — Interactive item identification
// Input: none (prompts user for slot)
// Output: item type identified (id_known set), instance flagged IF_IDENTIFIED,
//         message printed
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_identify_prompt:
    // Prompt: "IDENTIFY WHICH ITEM (A-V)?"
    lda #<piq_identify_prompt
    sta zp_ptr0
    lda #>piq_identify_prompt
    sta zp_ptr0_hi
    jsr msg_print

    jsr input_get_key

    // Cancel check
    cmp #$03
    beq !eip_cancel+
    cmp #$20
    beq !eip_cancel+

    // Convert to slot
    sec
    sbc #$41
    bcc !eip_cancel+
    cmp #MAX_INV_SLOTS
    bcs !eip_cancel+

    sta eff_target_slot
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !eip_cancel+

    // Identify that item type
    tax
    lda #1
    sta id_known,x

    // Set IF_IDENTIFIED on the item instance
    ldx eff_target_slot
    lda inv_flags,x
    ora #IF_IDENTIFIED
    sta inv_flags,x

    // Build message: "THIS IS A <real name>."
    lda #0
    sta cmb_buf_idx

    lda #<piq_thisis_str
    ldy #>piq_thisis_str
    jsr combat_append_str

    ldx eff_target_slot
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

    rts

!eip_cancel:
    // Scroll already consumed — just print generic message
    lda #<piq_nothing_str
    sta zp_ptr0
    lda #>piq_nothing_str
    sta zp_ptr0_hi
    jsr msg_print
    rts

// ============================================================
// eff_cure_poison — Clear poison status
// Input: none
// Output: zp_eff_poison = 0
// Clobbers: A
// ============================================================
eff_cure_poison:
    lda #0
    sta zp_eff_poison
    rts

// ============================================================
// eff_detect_monsters — Reveal all active monsters on map
// Sets FLAG_VISITED on each active monster's tile so it renders.
// Input: none
// Output: vis_room_revealed = 1
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0
// ============================================================
eff_detect_monsters:
    ldx #0
!edm_loop:
    cpx #MAX_MONSTERS
    bcs !edm_done+

    stx zp_temp0                    // Save monster index
    jsr monster_get_ptr             // zp_ptr0 = pointer to monster entry

    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edm_next+

    // Get monster Y coordinate -> map row pointer
    ldy #MX_Y
    lda (zp_ptr0),y
    tax                             // X = monster Y coord
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi

    // Get monster X coordinate
    ldy #MX_X
    lda (zp_ptr0),y
    tay                             // Y = monster X coord

    // Set FLAG_VISITED on tile
    lda (zp_ptr1),y
    ora #FLAG_VISITED
    sta (zp_ptr1),y

!edm_next:
    ldx zp_temp0                    // Restore monster index
    inx
    jmp !edm_loop-

!edm_done:
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_remove_curse — Clear IF_CURSED on all equipped items
// Input: none
// Output: IF_CURSED cleared from all equipment slots
// Clobbers: A, X
// ============================================================
eff_remove_curse:
    ldx #EQUIP_WEAPON               // Equipment starts at slot 22
!erc_loop:
    cpx #TOTAL_INV_SLOTS
    bcs !erc_done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !erc_next+
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
!erc_next:
    inx
    jmp !erc_loop-
!erc_done:
    rts
