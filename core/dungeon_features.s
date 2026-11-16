#importonce
// dungeon_features.s — Doors, traps, secret doors, search
//
// Phase 4.2: Explicit open/close door commands, stuck door mechanics,
// hidden trap placement and triggering, secret doors found by searching.

#if !DUNGEON_FEATURES_GENERATION_ONLY
#import "input_ui_helpers.s"
#endif

#if !DOOR_STATE_IN_DEFAULT_IMAGE
.macro DoorStateSegment() {}
.macro DoorStateRestoreSegment() {}
#endif
// ============================================================
// Trap table — parallel arrays (SoA)
// Hidden traps stored here; NOT in map tiles until triggered/found.
// ============================================================
trap_count: .byte 0
trap_x:     .fill MAX_TRAPS, 0
trap_y:     .fill MAX_TRAPS, 0
trap_type:  .fill MAX_TRAPS, 0

:DoorStateSegment()
// ============================================================
// Door-state table — parallel arrays (SoA), position-keyed.
// Tracks only stateful doors: val > 0 (bit 7 clear) = locked with
// difficulty 11-20; bit 7 set = stuck/jammed with magnitude in bits 0-6
// (11-20); val = 1 on an open-door tile = broken.
// Plain doors have no entry. Cleared on every level/town generation.
// Contiguous for the save block (save.s asserts the layout).
// ============================================================
door_state_count: .byte 0
door_state_x:     .fill MAX_DOOR_STATES, 0
door_state_y:     .fill MAX_DOOR_STATES, 0
door_state_val:   .fill MAX_DOOR_STATES, 0
:DoorStateRestoreSegment()



// ============================================================
// Local scratch (safe from rng_range clobbering zp_temp3/4)
// ============================================================
df_target_x: .byte 0   // Target tile X for door commands
df_target_y: .byte 0   // Target tile Y for door commands
df_dir_idx:  .byte 0   // Direction index from get_direction_target
df_found:    .byte 0   // Search found-something flag
df_search_chance: .byte 0
df_death_source: .byte 0 // Trap death source for lethal trap damage
df_death_hstr:   .byte 0 // Trap death cause string for lethal trap damage
df_disarm_chance: .byte 0
df_disarm_trap_idx: .byte 0
df_disarm_total: .byte 0
df_disarm_base: .byte 0
df_tile_tmp:    .byte 0

#import "df_target_row.s"

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_HELPERS_EXTERNAL
trap_difficulty:
    .byte 5, 15, 10, 20, 20, 25, 10, 20, 20, 30, 30, 30, 15, 20, 20, 0, 25, 20
trap_difficulty_end:
.assert "dungeon_features trap_difficulty covers TRAP_TYPE_COUNT", trap_difficulty_end - trap_difficulty, TRAP_TYPE_COUNT
#endif

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
trap_disarm_xp:
    .byte 1, 3, 2, 5, 6, 8, 2, 6, 5, 10, 10, 10, 3, 5, 5, 0, 8, 5
trap_disarm_xp_end:
.assert "dungeon_features trap_disarm_xp covers TRAP_TYPE_COUNT", trap_disarm_xp_end - trap_disarm_xp, TRAP_TYPE_COUNT

disarm_no_visible_str:
    .text "I do not see anything to disarm there." ; .byte 0
disarm_success_str:
    .text "You have disarmed the trap." ; .byte 0
disarm_fail_str:
    .text "You failed to disarm the trap." ; .byte 0
disarm_bad_fail_str:
    .text "You set the trap off!" ; .byte 0
#endif


// ============================================================
// find_random_floor — Find a random walkable floor tile on the map
// find_random_floor_near — The same within distance A (1-255) of the player:
// VMS Moria teleport(dis) (moria.inc; Umoria player.cpp playerTeleport). A
// random square farther than dis (VMS distance: max(dy,dx) + min(dy,dx)
// div 2) moves halfway toward the player, truncating the step, until it is
// within dis. Moria8 also refuses the player's own square (upstream accepts
// it), so the player always moves when any other square qualifies.
// Input (near): A = dis (1-255)
// Output: carry set = found (df_target_x/y valid)
//         carry clear = failed after 1,793-2,048 tries (the low count byte
//         is not reset: whatever a previous search left, at most 256)
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4
// ============================================================
frf_attempts:    .byte 0
frf_attempts_hi: .byte 0
frf_limit:       .byte 0    // dis; 0 = no distance limit

// df_roll_interior_xy — df_target_x/y = a random square off the map edge:
// x in [1, MAP_COLS-2], then y in [1, MAP_ROWS-2]. Clobbers: A, X
df_roll_interior_xy:
    lda #MAP_COLS - 2
    jsr rng_range           // [0, 77]
    clc
    adc #1                  // [1, 78]
    sta df_target_x
    lda #MAP_ROWS - 2
    jsr rng_range           // [0, 45]
    clc
    adc #1                  // [1, 46]
    sta df_target_y
    rts

find_random_floor:
    lda #0                  // No distance limit
find_random_floor_near:
    sta frf_limit
    lda #8                  // Up to 8 x 256 tries
    sta frf_attempts_hi

!frf_loop:
    jsr df_roll_interior_xy

    lda frf_limit
    beq !frf_check+         // No limit: any square
!frf_pull:
    // zp_temp1 = |dx|, zp_temp2 = |dy|
    ldx #1
!frf_abs:
    lda df_target_x,x
    sec
    sbc zp_player_x,x
    bcs !frf_abs_pos+
    eor #$ff
    adc #1                  // Carry clear: negate
!frf_abs_pos:
    sta zp_temp1,x
    dex
    bpl !frf_abs-
    // Distance = max + min div 2 = |dx| + |dy| - ceil(min / 2); A = it - 1
    lda zp_temp1
    cmp zp_temp2
    bcc !frf_min+           // |dx| < |dy|: |dx| is the min
    lda zp_temp2
!frf_min:
    lsr
    adc #0                  // ceil(min / 2) (<= 39); carry clear
    sta zp_temp0
    lda zp_temp1
    adc zp_temp2            // <= 122: carry clear
    sbc zp_temp0            // Carry clear: distance - 1
    bmi !frf_next+          // Distance 0: the player's own square
    cmp frf_limit
    bcc !frf_check+         // Distance - 1 < dis: within dis
    // Halfway toward the player, the step truncated: a square at t moves
    // to (t + p + 1) div 2 when t >= p, else (t + p) div 2 (never onto p
    // unless t = p).
    ldx #1
!frf_half:
    lda df_target_x,x
    cmp zp_player_x,x       // Carry = t >= p
    adc zp_player_x,x       // <= 157: no carry out
    lsr
    sta df_target_x,x
    dex
    bpl !frf_half-
    bmi !frf_pull-          // Always

!frf_check:
    // Unoccupied floor: TILE_FLOOR is type 0 and no creature flag
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK | FLAG_OCCUPIED
    bne !frf_next+
    sec
    rts
!frf_next:
    dec frf_attempts
    bne !frf_loop-
    dec frf_attempts_hi
    bne !frf_loop-
    clc
    rts
.assert "find_random_floor: TILE_FLOOR is tile type 0", TILE_FLOOR, 0
.assert "find_random_floor: df_target_y follows df_target_x", df_target_y, df_target_x + 1
.assert "find_random_floor: zp_player_y follows zp_player_x", zp_player_y, zp_player_x + 1
.assert "find_random_floor: zp_temp2 follows zp_temp1", zp_temp2, zp_temp1 + 1

// ============================================================
// place_secrets — Convert 1-3 random closed doors to secret doors
// Scans map for TILE_DOOR_CLOSED, collects into temp list,
// then picks 1-3 to convert to TILE_SECRET.
// ============================================================

// Temp buffer for door positions found during scan.
// Generation-only door scan scratch. This must not alias visible screen RAM:
// the generation busy screen stays visible while secrets are placed.
.const MAX_DOOR_SCAN = 32
.label door_scan_x = hal_layout_dungeon_door_scan_base
.label door_scan_y = door_scan_x + MAX_DOOR_SCAN
.label door_scan_count = door_scan_y + MAX_DOOR_SCAN
.assert "Door scan scratch stays inside platform scratch window", door_scan_count < hal_layout_dungeon_door_scan_limit, true
#if HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP
.assert "C128 HAL door scan base matches memory ownership", door_scan_x == DUNGEON_GEN_DOOR_SCAN_BASE, true
.assert "Door scan scratch does not overlap C128 copied map row", door_scan_x >= SCREEN_RAM + MAP_COLS, true
#endif

#if !PLACE_SECRETS_EXTERNAL
:DoorStateSegment()
#import "place_secrets_cold.s"
:DoorStateRestoreSegment()
#endif

#if !DUNGEON_FEATURES_GENERATION_ONLY

// ============================================================
// trap_check_at_player — Check if player stepped on a trap
// Scans trap table for player's (x, y). If found: reveal trap on map and
// trigger it. Matching umoria, ordinary triggered floor traps remain live and
// can still be disarmed later.
// Called from main.s after successful move.
// ============================================================
trap_check_at_player:
    lda trap_count
    beq !tcp_done+          // No traps
    lda zp_player_x
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    jsr trap_find_at_target
    bcc !tcp_done+

    // Reveal trap on map: change tile to TILE_TRAP | flags
    lda #TILE_TRAP | FLAG_VISITED
    jsr df_set_target_tile

    // Trigger the trap effect (df_disarm_trap_idx set by trap_find_at_target)
    ldx df_disarm_trap_idx
#if TRAP_TRIGGER_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME
    jsr tramp_trap_trigger
#else
    jsr trap_trigger
#endif
    jsr chest_run_pending_summons  // Deferred TRAP_SUMMON spawns (preserves C)

    // Done (only one trap per tile)
    sec                     // Carry set = trap fired
    rts

!tcp_done:
    clc                     // Carry clear = no trap
    rts

// trap_find_at_target — Scan trap table for (df_target_x, df_target_y).
// Output: carry set + X/df_disarm_trap_idx = index if found; carry clear if not.
trap_find_at_target:
    ldx #0
!tfat_loop:
    cpx trap_count
    bcs !tfat_no+
    lda trap_x,x
    cmp df_target_x
    bne !tfat_next+
    lda trap_y,x
    cmp df_target_y
    bne !tfat_next+
    stx df_disarm_trap_idx
    sec
    rts
!tfat_next:
    inx
    bne !tfat_loop-         // MAX_TRAPS <= 16
!tfat_no:
    clc
    rts

// trap_remove_at_index — Remove trap table entry X by swapping with the last.
trap_remove_at_index:
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x
    rts

// trap_find_target_visible — Find a visible target trap with matching table entry.
// Requires df_target_x/df_target_y from get_direction_target.
// Output: carry set = found, X/index stored in df_disarm_trap_idx.
trap_find_target_visible:
    jsr df_read_target_tile_type
    cmp #TILE_TRAP
    beq trap_find_at_target
    clc
    rts

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
// disarm_command — Direct visible floor-trap disarm command.
// Output: carry set = turn consumed, carry clear = no turn.
disarm_command:
    jsr get_direction_target
    bcc !no_turn+
    jsr trap_find_target_visible
    bcs !has_trap+
    lda #<disarm_no_visible_str
    ldy #>disarm_no_visible_str
    jsr msg_print_ay
!no_turn:
    clc
    rts

!has_trap:
    jsr player_disarm_get_effective_chance
    sta df_disarm_total
    ldx df_disarm_trap_idx
    lda trap_type,x
    tax
    lda df_disarm_total
    jsr disarm_calc_success_threshold
    sta df_disarm_chance
    lda #100
    jsr rng_range
    cmp df_disarm_chance
    bcc !success+

    lda df_disarm_total
    jsr disarm_roll_bad_fail
    bcs !bad_fail+
    lda #<disarm_fail_str
    ldy #>disarm_fail_str
    jsr msg_print_ay
    sec
    rts

!success:
    jsr disarm_award_trap_xp
    jsr disarm_restore_target_floor
    ldx df_disarm_trap_idx
    lda trap_type,x
    pha
    jsr trap_remove_at_index
    jsr disarm_move_player_to_target
    pla
    cmp #TRAP_HIDDEN_OBJECT
    bne !normal_ok+
    jsr df_stage_hidden_drop
    sec
    rts
!normal_ok:
    lda #<disarm_success_str
    ldy #>disarm_success_str
    jsr msg_print_ay
    sec
    rts

!bad_fail:
    lda #<disarm_bad_fail_str
    ldy #>disarm_bad_fail_str
    jsr msg_print_ay
    jsr disarm_move_player_to_target
    ldx df_disarm_trap_idx
    jsr trap_trigger
    sec
    rts

disarm_restore_target_floor:
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    rts

disarm_move_player_to_target:
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts

disarm_award_trap_xp:
    ldx df_disarm_trap_idx
    lda trap_type,x
    tax
    lda player_data + PL_XP_0
    clc
    adc trap_disarm_xp,x
    sta player_data + PL_XP_0
    bcc !done+
    inc player_data + PL_XP_1
    bne !done+
    inc player_data + PL_XP_2
!done:
    rts

#endif

#if !DISARM_HELPERS_EXTERNAL
#import "disarm_helpers.s"
#endif

df_set_target_tile:
    sta df_tile_tmp
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora df_tile_tmp
    :MapWrite_ptr0_y()
    rts

#if !TRAP_TRIGGER_EXTERNAL
#import "trap_trigger_cold.s"
#endif

#if !TRAP_DAMAGE_EXTERNAL
#import "trap_damage_cold.s"
#endif

// ============================================================
// get_direction_target — Prompt for direction and compute target
// Prints "DIRECTION?", waits for a direction key.
// Output: df_target_x, df_target_y = adjacent tile coordinates
//         carry set = valid direction entered
//         carry clear = invalid key (ESC, non-direction)
// ============================================================
get_direction_target:
    // Print "DIRECTION?" on message line
    ldx #HSTR_DF_DIRECTION
    jsr huff_print_msg

    // Ensure the command key that triggered the action is released so the
    // direction prompt consumes a fresh follow-up keypress.
    jsr input_prepare_followup_key

    // Wait for a keypress
    jsr hal_input_get_key

    // Convert PETSCII to command ID
    jsr petscii_to_command

    // Check if it's a movement command (CMD_MOVE_N through CMD_MOVE_SE)
    cmp #CMD_MOVE_N
    bcc !gdt_invalid+
    cmp #CMD_MOVE_SE + 1
    bcs !gdt_invalid+

    // Valid direction — compute target tile
    sec
    sbc #CMD_MOVE_N         // Direction index 0-7
    tax

    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    sec                     // Carry set = valid
    rts

!gdt_invalid:
    clc                     // Carry clear = invalid
    rts

df_read_target_tile_type:
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    sta df_dir_idx          // Save full tile byte
    and #TILE_TYPE_MASK
    rts

#if !DOOR_OPEN_CLOSE_EXTERNAL
#import "door_open_close_cold.s"
#endif

:DoorStateSegment()
// ============================================================
// Door-state runtime helpers (see table definition at the trap table)
// ============================================================
dsf_x: .byte 0
dsf_y: .byte 0
dss_val: .byte 0

// door_state_find — Input: A=x, Y=y.
// Output: carry set + X = table index if tracked; carry clear if plain.
// Clobbers: A, X
door_state_find:
    sta dsf_x
    sty dsf_y
    ldx #0
!dsf_loop:
    cpx door_state_count
    bcs !dsf_miss+
    lda door_state_x,x
    cmp dsf_x
    bne !dsf_next+
    lda door_state_y,x
    cmp dsf_y
    bne !dsf_next+
    sec
    rts
!dsf_next:
    inx
    bne !dsf_loop-
!dsf_miss:
    clc
    rts

// door_state_get_target — Input: df_target_x/y. Output: A = signed state (0 = plain).
door_state_get_target:
    lda df_target_x
    ldy df_target_y
// door_state_get — Input: A=x, Y=y. Output: A = signed state (0 = plain).
// Clobbers: A, X
door_state_get:
    jsr door_state_find
    bcc !dsg_plain+
    lda door_state_val,x
    rts
!dsg_plain:
    lda #0
    rts

// door_state_remove_idx — Remove table entry X (swap with last).
// Clobbers: A, Y
door_state_remove_idx:
    dec door_state_count
    ldy door_state_count
    lda door_state_x,y
    sta door_state_x,x
    lda door_state_y,y
    sta door_state_y,x
    lda door_state_val,y
    sta door_state_val,x
    rts

// door_state_clear_at — Drop any state at (A=x, Y=y), e.g. the door tile
// was destroyed by an earthquake or a door-destruction effect.
// Clobbers: A, X, Y
door_state_clear_at:
    jsr door_state_find
    bcs door_state_remove_idx
    rts

// door_state_set_at — Set state at (df_target_x, df_target_y); A = val.
// val = 0 removes any entry. New entries beyond the table cap are dropped
// (the door stays plain).
// Clobbers: A, X, Y
door_state_set_at:
    sta dss_val
    lda df_target_x
    ldy df_target_y
    jsr door_state_find
    bcs !dss_update+
    lda dss_val
    beq !dss_done+          // Clearing an untracked door: nothing to do
    ldx door_state_count
    cpx #MAX_DOOR_STATES
    bcs !dss_done+          // Full: degrade to plain
    lda df_target_x
    sta door_state_x,x
    lda df_target_y
    sta door_state_y,x
    lda dss_val
    inc door_state_count
    bne !dss_write+         // Count is 1..MAX_DOOR_STATES (> 0)
!dss_update:
    lda dss_val
    beq door_state_remove_idx
!dss_write:
    sta door_state_val,x
!dss_done:
    rts
:DoorStateRestoreSegment()

// ============================================================
// cmd_jam — Jam a door with an iron spike (CTRL+D command; VMS jamdoor).
// Target must be a closed door, unoccupied, with a spike in the pack.
// Each spike: state magnitude += 20 (VMS flat p1 = -|p1| - 20), sign bit
// set, capped at 127; a locked door becomes stuck. One spike consumed.
// Turn policy (Umoria dungeonJamDoor): not-a-door and must-close-first are
// free; occupied, no-spikes, and success consume the turn.
// ============================================================
#if !CMD_JAM_SEGMENT_CUSTOM
.macro CmdJamSegment() {}
.macro CmdJamRestoreSegment() {}
#endif
cj_slot: .byte 0

:CmdJamSegment()
door_jam_command:
    jsr get_direction_target
    bcc !djc_free+                // Invalid direction: free
    jmp door_jam_at_target              // tail call
!djc_free:
    clc
    rts

// door_jam_at_target — Jam logic on (df_target_x, df_target_y).
// Output: carry set = turn consumed, clear = free.
door_jam_at_target:
    // Read map tile at target
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    sta df_dir_idx
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !cj_closed+
    cmp #TILE_DOOR_OPEN
    beq !cj_open+
    ldx #HSTR_DF_NO_DOOR
    jsr huff_print_msg
!cj_free:
    clc                           // Free turn
    rts
!cj_open:
    lda #<jam_str_close_first
    ldy #>jam_str_close_first
    jsr msg_print_ay
    clc                           // Free turn
    rts
!cj_closed:
    // A live monster in the doorway blocks the jam (upstream: occupied
    // refusal still costs the turn)
    lda df_dir_idx
    and #FLAG_OCCUPIED
    beq !cj_unoccupied+
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !cj_unoccupied+
    jsr combat_msg_monster_in_way
    sec
    rts
!cj_unoccupied:
    // Spike in the pack? (carried slots only)
    ldx #0
!cj_scan:
    cpx #EQUIP_WEAPON
    bcs !cj_no_spike+
    lda inv_item_id,x
    cmp #ITEM_TYPE_IRON_SPIKE
    beq !cj_have+
    inx
    bne !cj_scan-
!cj_no_spike:
    lda #<jam_str_no_spikes
    ldy #>jam_str_no_spikes
    jsr msg_print_ay
    sec                           // Turn consumed (Umoria)
    rts
!cj_have:
    stx cj_slot
    // state magnitude += 20, capped at 127, sign bit set (stuck)
    lda df_target_x
    ldy df_target_y
    jsr door_state_get
    bne !cj_mag+              // Existing entry: update in place
    // New entry: refuse when the state table is full — set_at would drop
    // the write silently and the spike would be lost for nothing.
    ldx door_state_count
    cpx #MAX_DOOR_STATES
    bcs !cj_table_full+
    lda #0
!cj_mag:
    and #$7f                      // Current magnitude (locked or stuck)
    clc
    adc #20
    cmp #128
    bcc !cj_mag_ok+
    lda #127
!cj_mag_ok:
    ora #$80
    jsr door_state_set_at
    // Consume one spike
    ldx cj_slot
    jsr inv_consume_one
!cj_done:
    lda #<jam_str_jammed
    ldy #>jam_str_jammed
    jsr msg_print_ay
    sec                           // Turn consumed
    rts
!cj_table_full:
    lda #<jam_str_cannot
    ldy #>jam_str_cannot
    jsr msg_print_ay
    sec                           // Turn consumed (attempt made); spike kept
    rts

// Jam messages live beside the handler: on C64 that's the items overlay and
// on Plus4/A2 the chest overlay; C128 keeps it in resident Default RAM.
jam_str_jammed:      .text "You jam the door with a spike." ; .byte 0
jam_str_no_spikes:   .text "But you have no spikes." ; .byte 0
jam_str_close_first: .text "The door must be closed first." ; .byte 0
jam_str_cannot:      .text "The door will not hold a spike." ; .byte 0
:CmdJamRestoreSegment()

// ============================================================
// door_pick_roll — Locked-door pick roll (VMS openobject / Umoria
// playerOpenClosedObject): success iff disarm_skill - lock > randint(100),
// i.e. roll < skill - lock with roll in [1,100].
//
// The effective-disarm formula is overlay-parked on every product build, so
// this lives beside the selected platform helper; resident door_try_open
// reaches it via tramp_door_pick_roll. Test builds link it resident (empty
// segment macros) and use the disarm_helpers.s original.
//
// Input:  df_found = lock difficulty (11-20)
// Output: carry set = picked, carry clear = failed
// ============================================================
#if !DOOR_PICK_EXTERNAL
.macro DoorPickSegment() {}
.macro DoorPickRestoreSegment() {}
#endif

:DoorPickSegment()
door_pick_roll:
#if DOOR_PICK_USE_DISARM_HELPER
    jsr player_disarm_get_effective_chance
#else
#if DOOR_PICK_EXTERNAL
    jsr chest_disarm_skill      // A = signed effective disarm skill
#else
    jsr player_disarm_get_effective_chance
#endif
#endif
    beq !dpr_fail+              // Skill 0: no chance
    bmi !dpr_fail+              // Negative skill: no chance
    sec
    sbc df_found                // skill - lock; skill 1..127, lock 11..20
    beq !dpr_fail+              // diff 0: randint(100) < 0 never succeeds
    bcc !dpr_fail+              // skill < lock: hopeless (no unsigned wrap)
    sta df_disarm_base          // diff in 1..116
    lda #100
    jsr rng_range               // [0, 99]
    clc
    adc #1                      // [1, 100] — randint(100) parity
    cmp df_disarm_base          // success iff roll < skill - lock
    bcc !dpr_picked+
!dpr_fail:
    clc
    rts
!dpr_picked:
    sec
    rts
:DoorPickRestoreSegment()

// ============================================================
// search_scan_effective_silent — Shared search scan using the live player chance
// Output: carry set = something found, carry clear = nothing found
search_scan_effective_silent:
    jsr player_search_get_effective_chance
    // Fall through into search_scan_adjacent_silent

// search_scan_adjacent_silent — Search adjacent tiles without printing a
// "nothing found" message. Found-object messages still print.
// Input: A = per-tile search chance in percent
// Output: carry set = something found, carry clear = nothing found
search_scan_adjacent_silent:
    sta df_search_chance
    lda #0
    sta df_found
    sta df_dir_idx

!ds_loop:
    ldx df_dir_idx

    // Compute adjacent tile coordinates; check Y bounds immediately in A
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
    beq !ds_skip+
    cmp #MAP_ROWS - 1
    bcs !ds_skip+
    lda df_target_x
    beq !ds_skip+
    cmp #MAP_COLS - 1
    bcc !ds_bounds_ok+
!ds_skip:
    jmp !ds_next+
!ds_bounds_ok:

    // Read map tile once and cache full byte across secret/chest/trap checks
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    sta df_tile_tmp
    and #TILE_TYPE_MASK

    // Check for secret door
    cmp #TILE_SECRET
    bne !ds_chest_gate+

    jsr df_roll_search_chance
    bcc !ds_chest_gate+

!ds_secret_found:
    // Reveal: change to TILE_DOOR_CLOSED
    lda #TILE_DOOR_CLOSED
    jsr df_set_target_tile
    ldx #HSTR_DF_FOUND_SECRET
!ds_found_common:
    jsr huff_print_msg
    inc df_found
    bne !ds_next+

!ds_chest_gate:
#if CHEST_ROUTING_ENABLED
    // Chest branch (docs/CHEST_DESIGN.md): gated on FLAG_HAS_ITEM so the
    // floor-table scan stays off the per-move hot path.
    lda df_tile_tmp
    and #FLAG_HAS_ITEM
    beq !ds_check_trap+
    jsr chest_search_reveal
    bcs !ds_next+
#endif

!ds_check_trap:
    jsr trap_find_at_target
    bcc !ds_next+

    lda df_tile_tmp
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    beq !ds_next+

    jsr df_roll_search_chance
    bcc !ds_next+

!ds_trap_found:
    // Reveal trap: change map tile to TILE_TRAP | flags
    lda #TILE_TRAP | FLAG_VISITED
    jsr df_set_target_tile
    ldx #HSTR_DF_FOUND_TRAP
    bne !ds_found_common-   // HSTR_DF_FOUND_TRAP > 0

!ds_next:
    inc df_dir_idx
    lda df_dir_idx
    cmp #8
    beq !ds_done+
    jmp !ds_loop-

!ds_done:
    lda df_found
    cmp #1
    rts

df_roll_search_chance:
    lda df_search_chance
    beq !drsc_no+
    lda #100
    jsr rng_range
    cmp df_search_chance
    bcc !drsc_yes+
!drsc_no:
    clc
    rts
!drsc_yes:
    sec
    rts

// do_search — Search adjacent tiles for secrets and traps
// Always consumes a turn; if nothing was found, prints the standard message.
// ============================================================
do_search:
    jsr search_scan_effective_silent
    bcs !ds_exit+
    ldx #HSTR_DF_FOUND_NOTHING
    jsr huff_print_msg
!ds_exit:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "MAX_TRAPS", MAX_TRAPS, 16
.assert "TRAP_TYPE_COUNT", TRAP_TYPE_COUNT, 18
.assert "trap_teleport: PL_MAP_Y follows PL_MAP_X", PL_MAP_Y, PL_MAP_X + 1
#endif
