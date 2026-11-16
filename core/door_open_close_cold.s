#importonce
// door_open_close_cold.s — Explicit door open ('o') and close ('c') handlers (S3)
//
// Module ownership:
//   owner: HelpOverlay / TitleOverlay / HomeOverlay when DOOR_OPEN_CLOSE_EXTERNAL
//     is defined; Default resident otherwise (imported by dungeon_features.s).
//   lifetime: one discrete player 'o' or 'c' command.
//   callers: chest_open_route and cmd_close in core/game_loop.s (via
//     tramp_door_try_open / tramp_door_try_close when external). When not
//     co-located with door_pick_roll (DOOR_PICK_CO_LOCATED = 0), port
//     tramp_door_pick_roll must preserve current_overlay across the lock-pick roll.

df_msg_sec:
    jsr huff_print_msg
    sec
    rts

df_msg_clc:
    jsr huff_print_msg
    clc
    rts

// ============================================================
// door_try_open — Attempt to open a door at (df_target_x, df_target_y).
// Consults per-door state: plain doors open, locked doors roll the lock
// pick (door_pick_roll), stuck doors are refused (jam/bash to clear).
// Output: carry set = door opened (or stuck msg shown, turn consumed)
//         carry clear = no door there
// ============================================================
door_try_open:
    jsr df_read_target_tile_type
    cmp #TILE_DOOR_CLOSED
    beq !dto_closed+
    cmp #TILE_DOOR_OPEN
    beq !dto_already_open+

!dto_no_door:
    ldx #HSTR_DF_NO_DOOR
    jmp df_msg_clc

!dto_already_open:
    ldx #HSTR_DF_ALREADY_OPEN
    jmp df_msg_clc

!dto_closed:
    // Real per-door state (replaces the old transient 25% stuck roll):
    // locked (val > 0) -> pick attempt; stuck (val < 0) -> must be bashed.
    jsr door_state_get_target
    sta df_found                // Signed door state
    beq !dto_open_it+           // Plain door -> open
    bmi !dto_stuck+

    // Locked: pick the lock (VMS openobject / Umoria playerOpenClosedObject):
    // success iff disarm_skill - lock > randint(100); +1 XP on success.
    lda zp_eff_confuse
    beq !dto_pick+
    ldx #HSTR_DF_PICK_CONFUSED
    jmp df_msg_sec
!dto_pick:
    // Carry set = picked. Ports co-locating S3 with door_pick_roll (e.g. Plus/4
    // TitleOverlay) define DOOR_PICK_CO_LOCATED to call door_pick_roll directly.
#if DOOR_PICK_EXTERNAL && !DOOR_PICK_CO_LOCATED
    jsr tramp_door_pick_roll
#else
    jsr door_pick_roll
#endif
    bcs !dto_picked+
    ldx #HSTR_DF_PICK_FAIL
    jmp df_msg_sec
!dto_picked:
    ldx #HSTR_DF_PICKED
    jsr huff_print_msg
    // +1 XP (24-bit), once — state clears below, so retries pay nothing
    inc player_data + PL_XP_0
    bne !dto_xp_done+
    inc player_data + PL_XP_1
    bne !dto_xp_done+
    inc player_data + PL_XP_2
!dto_xp_done:
    lda #0
    jsr door_state_set_at       // Unlock (removes the table entry)

!dto_open_it:
    // Open the door: change tile type to TILE_DOOR_OPEN, keep flags
    lda #TILE_DOOR_OPEN
    jsr df_set_target_tile

    ldx #HSTR_DF_DOOR_OPENED
    jmp df_msg_sec

!dto_stuck:
    ldx #HSTR_DF_STUCK
    jsr huff_print_msg
    lda #SFX_BUMP
    jsr hal_sound_play
    sec                         // Turn consumed
    rts

// ============================================================
// door_try_close — Attempt to close a door at (df_target_x, df_target_y)
// Output: carry set = door closed, carry clear = no open door there
// ============================================================
door_try_close:
    jsr df_read_target_tile_type
    cmp #TILE_DOOR_OPEN
    beq !dtc_open+
    cmp #TILE_DOOR_CLOSED
    bne !dto_no_door-

    ldx #HSTR_DF_ALREADY_CLOSED
    jmp df_msg_clc

!dtc_open:
    // Broken doors (state 1 on an open tile) cannot be closed
    // (VMS closeobject / Umoria playerCloseDoor: "The door appears to be
    // broken.", turn consumed).
    jsr door_state_get_target
    cmp #1
    bne !dtc_not_broken+
    ldx #HSTR_DF_DOOR_BROKEN
    jmp df_msg_sec
!dtc_not_broken:
    // A live monster in the doorway blocks the close (VMS closeobject /
    // Umoria playerCloseDoor: refuse with "The <name> is in your way!" and
    // still consume the turn). Resolve FLAG_OCCUPIED against the live monster
    // table and repair stale flags, matching player_move_check_live_occupant.
    lda df_dir_idx
    and #FLAG_OCCUPIED
    beq !dtc_do_close+
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at         // Clobbers zp_ptr0
    bcc !dtc_stale+
    jsr combat_msg_monster_in_way
    sec                         // Turn consumed (upstream refuses without a free turn)
    rts

!dtc_stale:
    // No live monster — repair the stale flag, then close the door.
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()

!dtc_do_close:
    // Close the door
    lda #TILE_DOOR_CLOSED
    jsr df_set_target_tile

    ldx #HSTR_DF_DOOR_CLOSED
    jmp df_msg_sec
