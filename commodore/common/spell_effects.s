#importonce
// spell_effects.s — Shared effect subroutines for spells, potions, scrolls, etc.
//
// Phase 7.0: Extracted from player_items.s inline handlers.
// Each subroutine implements a single effect. Base effect routines stay
// message-light; `*_msg` wrappers own player-facing feedback when a spell or
// item path needs it.
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
.const EFF_ICAT_WAND   = 14
.const EFF_ICAT_STAFF  = 15

eff_target_slot: .byte 0           // Target slot for identify

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
    ldx #0
!elr_loop:
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
    jsr light_room_x
    rts

!elr_next:
    inx
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
    bcc !ets_fail+

// eff_teleport_apply_target — Move player to df_target_x/y
// Input: df_target_x/y = destination, zp_player_x/y = current position
// Output: player moved, FLAG_OCCUPIED updated, vis_room_revealed set
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_teleport_apply_target:
    jsr player_search_mode_off
    // Clear FLAG_OCCUPIED at old position
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()

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
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()

    // Trigger full visibility update and redraw
    lda #1
    sta vis_room_revealed
!ets_fail:
    rts

// ============================================================
// eff_identify_prompt — Interactive item identification
// Input: none (prompts user for slot)
// Output: item type identified (id_known set), instance flagged IF_IDENTIFIED,
//         message printed
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_identify_prompt:
    lda #$fd
    ldx #HSTR_PIQ_IDENTIFY_PROMPT
    jsr piw_prompt_filtered_inv
    bcs !eip_have_choices+
    clc
    rts
!eip_have_choices:
    jsr input_prepare_followup_key
!eip_retry:
    jsr hal_input_get_key

    cmp #$3f
    bne !eip_not_inv+
    lda #$fd
    jsr show_inv_and_select
!eip_not_inv:

    // Cancel check
    cmp #$03
    beq !eip_cancel+
    cmp #$20
    beq !eip_cancel+

    jsr piw_pick_filtered_inv_key
    bcc !eip_cancel+
    stx eff_target_slot

    // Identify that item type
    tay
    pha
    lda #1
    sta id_known,y

    // Set IF_IDENTIFIED on the item instance
    lda inv_flags,x
    and #~IF_SENSED & $ff
    ora #IF_IDENTIFIED
    sta inv_flags,x

    // Build message: "THIS IS A <real name>."
    lda #0
    sta cmb_buf_idx

    ldx #HSTR_PIQ_THISIS
    jsr huff_append_combat

    pla
    ldx eff_target_slot
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
    jsr item_append_name

    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
!eip_print:

    jsr cmb_term_and_print

    rts

!eip_cancel:
    // Scroll already consumed — just print generic message
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
    rts

// Resident scroll-identify completion path. item_read_scroll dispatches here
// with a tail jump so nested inventory/help overlays do not have to return to
// item-overlay code after eff_identify_prompt finishes.
eff_identify_scroll_resident:
    jsr eff_identify_prompt
    sec
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

#if HAL_PLATFORM_CURE_POISON_MSG_EXTERNAL
#else
pmx_cure_poison_msg:
    lda zp_eff_poison
    beq !pcpm_done+
    lda #0
    sta zp_eff_poison
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg
!pcpm_done:
    rts
#endif

// ============================================================
// eff_detect_monsters — Activate detect monsters effect (timer)
// While timer > 0, renderer shows detected monsters regardless
// of tile visibility. No permanent FLAG_VISITED side-effect.
// Input: none
// Output: eff_detect_timer set, vis_room_revealed = 1
// Clobbers: A
// ============================================================
.const DETECT_TIMER_TURNS = 20
.const EDEO_MX_X = 0
.const EDEO_MX_Y = 1
.const EDEO_CF_EVIL = $04

eff_detect_timer: .byte 0

eff_detect_monsters:
    lda #DETECT_TIMER_TURNS
    sta eff_detect_timer
    lda #1
    sta vis_room_revealed
    rts

eff_detect_evil_only:
    lda #0
    sta eff_detect_timer
    tax
    stx vis_room_revealed
!edeo_loop:
    cpx #MAX_MONSTERS
    bcs !edeo_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edeo_next+
    tay
    lda cr_mflags,y
    and #EDEO_CF_EVIL
    beq !edeo_next+

    ldy #EDEO_MX_Y
    lda (zp_ptr0),y
    sta zp_temp1
    sec
    sbc zp_view_y
    bcc !edeo_next+
    cmp #VIEWPORT_H
    bcs !edeo_next+

    ldy #EDEO_MX_X
    lda (zp_ptr0),y
    sta zp_temp0
    sec
    sbc zp_view_x
    bcc !edeo_next+
    cmp #VIEWPORT_W
    bcs !edeo_next+

    txa
    pha
    ldx zp_temp1
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy zp_temp0
    :MapRead_ptr1_y()
    ora #(FLAG_VISITED | FLAG_LIT)
    :MapWrite_ptr1_y()
    lda #1
    sta vis_room_revealed
    pla
    tax
!edeo_next:
    inx
    jmp !edeo_loop-
!edeo_done:
    lda vis_room_revealed
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

// ============================================================
// eff_phase_door — Short-range teleport (up to 10 tiles away)
// Picks a random floor tile; if > 10 distance, retries (max 20).
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_pd_attempts: .byte 0

eff_phase_door:
    lda #20
    sta eff_pd_attempts

!epd_loop:
    jsr find_random_floor
    bcc !epd_retry+

    // Check Chebyshev distance <= 10
    lda df_target_x
    sec
    sbc zp_player_x
    bpl !epd_dx_pos+
    eor #$ff
    clc
    adc #1
!epd_dx_pos:
    sta zp_temp0                    // |dx|

    lda df_target_y
    sec
    sbc zp_player_y
    bpl !epd_dy_pos+
    eor #$ff
    clc
    adc #1
!epd_dy_pos:
    // max(|dx|, |dy|) = Chebyshev distance
    cmp zp_temp0
    bcs !epd_use_dy+
    lda zp_temp0
!epd_use_dy:
    cmp #11
    bcc !epd_ok+

!epd_retry:
    dec eff_pd_attempts
    bne !epd_loop-

    rts
!epd_ok:
    // Move player (df_target_x/y already set by find_random_floor)
    jmp eff_teleport_apply_target

// ============================================================
// eff_find_traps — Reveal all hidden traps in LOS range
// Instantly reveals all traps (no probability).
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_find_traps:
    ldx #0
!eft_loop:
    cpx trap_count
    bcs !eft_done+

    // Reveal trap on map
    ldy trap_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy trap_x,x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_TRAP
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()

    inx
    jmp !eft_loop-

!eft_done:
    // Don't remove traps from table — just reveal them
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// eff_find_doors — Reveal all secret doors on the map
// Converts TILE_SECRET to TILE_DOOR_CLOSED.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_fd_row: .byte 0

eff_find_doors:
    lda #1
    sta eff_fd_row
!efd_row_loop:
    lda eff_fd_row
    cmp #MAP_ROWS - 1
    bcs !efd_done+
    ldx eff_fd_row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #1
!efd_col_loop:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !efd_col_next+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!efd_col_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efd_col_loop-
    inc eff_fd_row
    jmp !efd_row_loop-
!efd_done:
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// for_each_adjacent — Iterate 8 adjacent tiles, call callback
// Sets df_target_x/df_target_y for each direction, then calls
// the function at adj_callback via indirect jump.
// Callbacks may clobber A, X, Y, zp_ptr0, zp_temp0-4 freely.
// Clobbers: A, X, Y
// ============================================================
adj_callback: .word 0       // Function pointer for callback
adj_dir_idx:  .byte 0       // Direction counter 0-7

for_each_adjacent:
    lda #0
    sta adj_dir_idx
!fea_loop:
    lda adj_dir_idx
    cmp #8
    bcs !fea_done+
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
    jsr !fea_dispatch+
    inc adj_dir_idx
    jmp !fea_loop-
!fea_done:
    rts
!fea_dispatch:
    jmp (adj_callback)

// ============================================================
// eff_sleep_adjacent — Put all adjacent monsters to sleep
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-1
// ============================================================
eff_sleep_adjacent:
    lda #<!esa_cb+
    sta adj_callback
    lda #>!esa_cb+
    sta adj_callback+1
    jmp for_each_adjacent
!esa_cb:
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !esa_skip+
    lda #20                         // Sleep for 20 turns
    jsr monster_apply_sleep
!esa_skip:
    rts

// ============================================================
// eff_bolt — Fire a bolt in a direction, damaging first monster hit
// Input: A = dice count, X = dice sides, Y = bonus
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4, zp_math_a/b
// ============================================================
eff_bolt_dice:  .byte 0
eff_bolt_sides: .byte 0
eff_bolt_bonus: .byte 0
// eb_save_char/eb_save_col removed — now handled by screen_flash_at

// Strings migrated to Huffman compression (HSTR_EB_* in huffman_data.s)

eff_bolt:
    sta eff_bolt_dice
    stx eff_bolt_sides
    sty eff_bolt_bonus

    // Get direction from player
    jsr get_direction_target
    bcs !eb_has_dir+
    rts                             // Cancelled
!eb_has_dir:
    jsr calc_direction_index
    bcs !eb_dir_ok+
    rts                             // No valid direction
!eb_dir_ok:

    // Start from player position
    lda zp_player_x
    sta proj_cx
    lda zp_player_y
    sta proj_cy
    lda #20
    sta proj_steps

!eb_trace:
    dec proj_steps
    bne !eb_has_steps+
    rts
!eb_has_steps:
    jsr trace_step
    bcs !eb_check_mon+
    rts                             // Blocked or out of bounds

!eb_check_mon:
    // --- Animate bolt: draw * at current position if on-screen ---
    lda proj_cy
    sec
    sbc zp_view_y
    bcc !eb_no_anim+                // Off-screen (top)
    cmp #VIEWPORT_H
    bcs !eb_no_anim+                // Off-screen (bottom)
    clc
    adc #VIEWPORT_Y                 // Screen row
    tax                             // X = absolute screen row

    lda proj_cx
    sec
    sbc zp_view_x
    bcc !eb_no_anim+                // Off-screen (left)
    cmp #VIEWPORT_W
    bcs !eb_no_anim+                // Off-screen (right)
    clc
    adc #VIEWPORT_X                 // Screen column
    tay                             // Y = absolute screen column

#if hal_screen_spell_bolt_flash_sets_color
    lda #COL_CYAN
    jsr screen_flash_set_color
#endif
    jsr screen_flash_at             // Flash '*' white, restore after delay
#if hal_screen_spell_bolt_flash_sets_color
    jsr screen_flash_reset_color
#endif

!eb_no_anim:
    // Check for monster at this position
    lda proj_cx
    ldy proj_cy
    jsr monster_find_at
    bcs !eb_got_monster+        // Monster found
    jmp !eb_trace-              // No monster, keep going
!eb_got_monster:

    // Hit a monster! X = slot index
    stx cmb_slot
    stx zp_temp2                // Save monster slot

    // Get monster type for messages
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type

    // Roll damage
    lda eff_bolt_dice
    ldx eff_bolt_sides
    ldy eff_bolt_bonus
    jsr math_dice               // Result in zp_math_a

    // Apply damage to monster
    ldx zp_temp2
    jsr combat_apply_damage_16
    bcc !eb_alive+              // Still alive

    // Monster killed — award XP, remove, message
    jsr combat_kill_message     // X preserved by helper
    rts

!eb_alive:
    // Wake the monster
    ldx zp_temp2
    jsr monster_wake

    // Message: "YOUR SPELL HITS THE <name>."
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_EB_SPELL_HITS
    jsr projectile_msg_suffix
    lda #SFX_HIT
    jsr hal_sound_play
    rts

// ============================================================
// eff_damage_adjacent — Damage all adjacent monsters (area effect)
// Input: A = dice count, X = dice sides
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4, zp_math_a/b
// ============================================================
eff_da_dice:  .byte 0
eff_da_sides: .byte 0

eff_damage_adjacent:
    sta eff_da_dice
    stx eff_da_sides
    lda #<!eda_cb+
    sta adj_callback
    lda #>!eda_cb+
    sta adj_callback+1
    jmp for_each_adjacent
!eda_cb:
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !eda_skip+

    // Monster found — roll damage
    stx zp_temp2                    // Save monster slot
    lda eff_da_dice
    ldx eff_da_sides
    ldy #0
    jsr math_dice

    // Apply damage
    ldx zp_temp2
    jsr combat_apply_damage_16
    bcc !eda_skip+              // Still alive
    // Monster killed
    jsr eff_kill_monster        // X preserved by helper
!eda_skip:
    rts

// ============================================================
// eff_directional_monster — Get direction, trace until the first monster hit
// Output: carry SET = monster found (X = slot index),
//         carry CLEAR = no monster along the traced path
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_directional_monster:
    jsr get_direction_target
    bcc !edm_fail+
    jsr calc_direction_index
    bcc !edm_fail+
    lda zp_player_x
    sta proj_cx
    lda zp_player_y
    sta proj_cy
    lda #20
    sta proj_steps
!edm_trace:
    jsr trace_step
    bcc !edm_fail+
    lda proj_cx
    ldy proj_cy
    jsr monster_find_at
    bcs !edm_done+
    dec proj_steps
    bne !edm_trace-

!edm_fail:
!edm_done:
    rts

// ============================================================
// eff_destroy_traps_doors — Destroy traps and jam doors open in radius
// Scans 8 adjacent tiles. Traps removed, closed doors opened.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_destroy_traps_doors:
    // First pass: modify map tiles
    lda #<!edtd_tile_cb+
    sta adj_callback
    lda #>!edtd_tile_cb+
    sta adj_callback+1
    jsr for_each_adjacent
    // Second pass: remove from trap table
    lda #<!edtd_trap_cb+
    sta adj_callback
    lda #>!edtd_trap_cb+
    sta adj_callback+1
    jsr for_each_adjacent
    lda #1
    sta vis_room_revealed
    rts

!edtd_tile_cb:
    // Read map tile
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    sta zp_temp0

    // Check for trap
    cmp #TILE_TRAP
    bne !edtd_check_door+
    // Remove trap — set to floor
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    :MapWrite_ptr0_y()
    rts

!edtd_check_door:
    // Check for closed door or secret door
    lda zp_temp0
    cmp #TILE_DOOR_CLOSED
    beq !edtd_open_door+
    cmp #TILE_SECRET
    bne !edtd_tile_done+

!edtd_open_door:
    // Open the door
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!edtd_tile_done:
    rts

!edtd_trap_cb:
    // Scan trap table for match at df_target_x/df_target_y
    ldx #0
!edtd_scan:
    cpx trap_count
    bcs !edtd_scan_done+

    lda trap_x,x
    cmp df_target_x
    bne !edtd_scan_next+
    lda trap_y,x
    cmp df_target_y
    bne !edtd_scan_next+

    // Match — swap with last entry, decrement count
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    jmp !edtd_scan-             // Re-check this index (swapped entry)

!edtd_scan_next:
    inx
    jmp !edtd_scan-

!edtd_scan_done:
    rts

// ============================================================
// eff_wall_to_mud — Turn a wall tile to floor in chosen direction
// Must call get_direction_target first.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_wall_to_mud:
    jsr get_direction_target
    bcc !ewtm_fail+

    // Boundary check — edge tiles are permanent
    lda df_target_x
    beq !ewtm_fail+
    cmp #MAP_COLS - 1
    beq !ewtm_fail+
    lda df_target_y
    beq !ewtm_fail+
    cmp #MAP_ROWS - 1
    beq !ewtm_fail+

    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta ewtm_save_tile          // Save full tile for treasure check
    and #TILE_TYPE_MASK

    // Check all tunnelable types
    cmp #TILE_WALL_H
    beq !ewtm_dig+
    cmp #TILE_WALL_V
    beq !ewtm_dig+
    cmp #TILE_CORNER_TL
    beq !ewtm_dig+
    cmp #TILE_CORNER_TR
    beq !ewtm_dig+
    cmp #TILE_CORNER_BL
    beq !ewtm_dig+
    cmp #TILE_CORNER_BR
    beq !ewtm_dig+
    cmp #TILE_MAGMA
    beq !ewtm_dig+
    cmp #TILE_QUARTZ
    beq !ewtm_dig+
    cmp #TILE_SECRET
    beq !ewtm_dig+
    // Not a wall
!ewtm_fail:
    rts

!ewtm_dig:
    // Replace with floor + flags (preserve visited/lit from original)
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    :MapWrite_ptr0_y()

    // Check for treasure in vein
    lda ewtm_save_tile
    and #FLAG_HAS_ITEM
    beq !ewtm_no_treasure+
    jsr tunnel_spawn_gold
    ldx #HSTR_TUN_FOUND
    jsr huff_print_msg
    lda #SFX_PICKUP
    jsr hal_sound_play
!ewtm_no_treasure:

    lda #1
    sta vis_room_revealed
    rts

ewtm_save_tile: .byte 0

// ============================================================
// eff_kill_monster — Remove a dead monster and award XP
// Input: X = monster slot index (saved in zp_temp2 by caller)
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0-4, zp_math_a/b
// ============================================================
eff_kill_monster:
    // Get monster type for XP award
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type                    // Set cmb_type for combat_award_xp

    // Remove monster from active list (clears FLAG_OCCUPIED + slot)
    jsr monster_remove
    inc zp_dirty_count              // consumed by turn_post_action

    // Award XP using existing combat function
    jsr combat_award_xp
    jsr combat_check_levelup

    rts

// ============================================================
// eff_aggravate — Wake all monsters (clear sleep timer)
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_aggravate:
    ldx #0
!eag_loop:
    cpx #MAX_MONSTERS
    bcs !eag_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !eag_next+
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y                // Clear sleep
!eag_next:
    inx
    jmp !eag_loop-
!eag_done:
    rts
