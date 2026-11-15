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
place_secrets:
    // Only caller is dungeon_generate (dungeon levels); town uses
    // town_generate and never reaches here.

    // Scan entire map for TILE_DOOR_CLOSED
    lda #0
    sta door_scan_count

    ldx #1                  // Start at row 1
!ps_row:
    jsr map_row_ptr0_x
    stx df_target_y         // Save row

#if HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP
    // The C128 map lives in Bank 1. Copy once per row instead of switching
    // banks for every tile in this full-map generation scan.
    lda #MAP_COLS
    jsr mmu_common_copy_map_row
#endif

    ldy #1                  // Start at col 1
!ps_col:
#if HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP
    lda SCREEN_RAM,y
#else
    :MapRead_ptr0_y()
#endif
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !ps_next+

    // Found a closed door — add to scan list
    lda door_scan_count
    cmp #MAX_DOOR_SCAN
    bcs !ps_next+           // List full

    tax
    lda df_target_y
    sta door_scan_y,x
    tya
    sta door_scan_x,x
    inc door_scan_count

!ps_next:
    iny
    cpy #MAP_COLS - 1
    bne !ps_col-

    ldx df_target_y         // Restore row
    inx
    cpx #MAP_ROWS - 1
    bne !ps_row-

    // How many doors did we find?
    lda door_scan_count
    bne !ps_some+
    rts                     // None found
!ps_some:

    // Pick 1-3 doors to convert (don't exceed count)
    lda #3
    jsr rng_range           // [0, 2]
    clc
    adc #1                  // [1, 3]
    sta df_found            // Number to convert

    // Clamp to door_scan_count
    cmp door_scan_count
    bcc !ps_convert+
    lda door_scan_count
    sta df_found

!ps_convert:
    // Pick a random door from the list
    lda door_scan_count
    jsr rng_range           // [0, count-1]
    sta df_dir_idx          // Save random index

    // Get its coordinates
    tax
    lda door_scan_y,x
    sta df_target_y
    lda door_scan_x,x
    sta df_target_x

    // Convert map tile to TILE_SECRET (keep flags)
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK     // Keep flags
    ora #TILE_SECRET        // Change type to secret
    :MapWrite_ptr0_y()

    // Remove from scan list: swap picked entry with last, decrement count
    dec door_scan_count
    ldx df_dir_idx          // X = picked index
    ldy door_scan_count     // Y = new last index (was count-1)
    lda door_scan_x,y
    sta door_scan_x,x
    lda door_scan_y,y
    sta door_scan_y,x

    dec df_found
    bne !ps_convert-


    // ---- Locked/stuck door state roll (second map pass) ----
    // Rescan the map after secret conversion so every remaining closed door
    // is eligible, including doors beyond the bounded secret-selection list.
    // Upstream closed-door branch (VMS place_door /
    // Umoria dungeonPlaceDoor): 2/12 locked, 1/12 stuck, 9/12 plain, with
    // uniform magnitude randint(10)+10. One rng_range(120) draw per door
    // encodes class and magnitude exactly: [0,20) locked (mag 11+roll/2),
    // [60,70) stuck (mag roll-49, negated), else plain. Draws append after
    // all existing generation draws, preserving topology seeds. Every
    // remaining closed door is rolled; rolling stops when the state table fills
    // (MAX_DOOR_STATES entries) and any remaining doors stay plain.
    // Keep this loop in sync with the PLACE_SECRETS_EXTERNAL copy in
    // core/dungeon_gen.s (C64/Plus4/A2).
    // Capping either the roll count or the secret-selection scratch list
    // would bias locked/stuck doors toward the top of the row-major map.
    ldx #1
!pss_row:
    jsr map_row_ptr0_x
    stx df_target_y
#if HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP
    lda #MAP_COLS
    jsr mmu_common_copy_map_row
#endif
    ldy #1
!pss_col:
#if HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP
    lda SCREEN_RAM,y
#else
    :MapRead_ptr0_y()
#endif
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !pss_next+
    ldx door_state_count
    cpx #MAX_DOOR_STATES
    bcs !pss_done+              // State table full: rest stay plain
    lda #120
    jsr rng_range
    cmp #20
    bcc !pss_locked+
    cmp #60
    bcc !pss_next+              // [20, 60) plain
    cmp #70
    bcs !pss_next+              // [70, 120) plain
    // Stuck: roll in [60, 70) -> magnitude roll-49 in [11, 20], sign bit set
    sec
    sbc #49
    ora #$80
    jmp !pss_store+
!pss_locked:
    // roll in [0, 20) -> magnitude 11 + roll/2 in [11, 20] (each twice)
    lsr
    clc
    adc #11
!pss_store:
    ldx door_state_count
    sta door_state_val,x
    tya
    sta door_state_x,x
    lda df_target_y
    sta door_state_y,x
    inc door_state_count
!pss_next:
    iny
    cpy #MAP_COLS - 1
    bne !pss_col-
    ldx df_target_y
    inx
    cpx #MAP_ROWS - 1
    bne !pss_row-
!pss_done:
!ps_done:
    rts
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
    jsr trap_trigger
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

// ============================================================
// trap_trigger — Execute a trap's effect (traps 0..17, VMS §4.5)
// Input: X = trap table index (trap_type[X] has the type)
// ============================================================
trap_trigger:
    jsr player_search_mode_off   // Must stay first (test_main_loop PatchJump)
    lda trap_type,x
    sta df_search_chance
    tay
    lda trap_handler_hi,y
    pha
    lda trap_handler_lo,y
    pha
    rts

// Covered pit converts into a revealed open pit, then falls through to 2d6.
trap_do_covered_pit:
    lda #TRAP_OPEN_PIT
    sta trap_type,x

// Open pit (and converted covered pit): 2d6 damage (VMS open/covered pits).
trap_do_pit:
    bit player_pflags           // PFLAG_FFALL == $80
    bmi !tdp_ffall+
    lda #0
    beq trap_do_huff_dmg    // Always
!tdp_ffall:
    ldx #HSTR_DF_YOU_FELL
    jsr huff_print_msg
    ldx #HSTR_CHEST_UNAFFECTED
    jmp huff_print_msg

trap_do_arrow:
    lda #1
    bne trap_do_huff_dmg    // Always

// Rockfall: 2d6 damage and tile becomes rubble (removed from trap table).
trap_do_rockfall:
    lda #TILE_RUBBLE | FLAG_VISITED
    jsr trap_remove_set_tile
    lda #2

// Shared handler for Huffman-messaged fixed-dice damage traps (0..3).
trap_do_huff_dmg:
    tay
    lda trap_huff_dsrc_t,y
    sta df_death_source
    lda trap_huff_dhst_t,y
    sta df_death_hstr
    lda trap_huff_dice_t,y
    pha
    lda trap_huff_side_t,y
    pha
    ldx trap_huff_msg_t,y
    jsr huff_print_msg
    pla
    tax
    pla
    jmp trap_apply_damage

// Gas traps: 2=poison (11..20), 12=sleep (5..8 unless Free Action),
// 13=blind (26..75 + invalidate lit room), 14=confuse (16..30).
// Input: Y = trap type (2, 12, 13, 14).
trap_do_gas:
    tya
    sec
    sbc #11
    bpl !tdg_idx+
    lda #0                  // TRAP_POISON_GAS (2) -> 0
!tdg_idx:
    sta df_found
    ldx #HSTR_DF_POISON_GAS
    jsr huff_print_msg
    ldy df_found
    cpy #1                  // Sleep gas: Free Action suppresses
    bne !tdg_not_sleep+
    lda player_pflags
    and #PFLAG_FREE_ACT
    beq !tdg_roll+
    ldx #HSTR_CHEST_UNAFFECTED
    bne !tdg_msg+           // HSTR_CHEST_UNAFFECTED > 0
!tdg_not_sleep:
    cpy #2                  // Blindness gas: invalidate cached room visibility
    bne !tdg_roll+
    lda #1
    sta vis_room_revealed
!tdg_roll:
    lda gas_rng_max,y
    jsr rng_range           // Preserves Y (= df_found)
    clc
    adc gas_rng_base,y
    ldx gas_zp_eff,y
    sta $0000,x
    ldx gas_msg_hstr,y
!tdg_msg:
    jmp huff_print_msg

// Teleport: move player to random floor tile
trap_do_teleport:
    ldx #HSTR_DF_TELEPORTED
    jsr huff_print_msg
// trap_teleport — Move player to a random unoccupied floor tile
trap_teleport:
    jsr find_random_floor
    bcc !tt_done+
#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
    jmp disarm_move_player_to_target
#else
    ldx #1
!tt_loop:
    lda df_target_x,x
    sta zp_player_x,x
    sta player_data + PL_MAP_X,x
    dex
    bpl !tt_loop-
#endif
!tt_done:
    rts

// Poison dart (1d4 + 50% -1 CON, min 3) and STR dart (1d4 + -1 STR, min 3)
trap_do_dart:
    lda #3
    jsr trap_do_huff_dmg
    beq !tdd_done+
    lda df_search_chance
    cmp #TRAP_POISON_DART
    bne !tdd_str+
    jsr rng_byte
    and #1
    beq !tdd_done+
    ldy #PL_CON_CUR - PL_STR_CUR
    lda #HSTR_DF_CON_DRAIN
    bne !tdd_drain+         // HSTR_DF_CON_DRAIN > 0
!tdd_str:
    ldy #0
    lda #HSTR_CHEST_WEAKENED
!tdd_drain:
    pha
    tya
    bne !tdd_chk_con_sust+
    lda #SUST_STR
    .byte $2c
!tdd_chk_con_sust:
    lda #SUST_CON
    and player_sust_mask
    bne !tdd_pop_done+
    lda player_data + PL_STR_CUR,y
    cmp #4
    bcc !tdd_pop_done+
    sty df_found
    jsr decrement_stat
    ldy df_found
    sta player_data + PL_STR_CUR,y
    sta zp_player_str,y
    pla
    tax
    jmp huff_print_msg
!tdd_pop_done:
    pla
!tdd_done:
    rts

// Hidden object: remove trap -> floor, stage buried object drop at player tile.
trap_do_hidden_obj:
    jsr trap_remove_floor
// Local mirrors of constants declared later in monster_death.s / monster.s
// (MS_BREATH_FIRE == 5 is asserted in element_resist.s; MD_QUEUE_MAX == 4
// in monster_death.s). Declared here so KickAss resolves immediate operands
// during pass 0 before those files are imported.
.const DF_MD_QUEUE_MAX   = 4
.const DF_MS_BREATH_FIRE = 5

df_stage_hidden_drop:
    ldx md_count
    cpx #DF_MD_QUEUE_MAX
    bcs !dshd_msg+
    lda zp_player_x
    sta md_x,x
    lda zp_player_y
    sta md_y,x
    lda #$11                // Object (bit 0) + randint(2) drops (bit 4)
    sta md_flags,x
    inc md_count
!dshd_msg:
    ldx #HSTR_TUN_FOUND
    jmp huff_print_msg

// Summon monster rune: remove trap -> floor, stage 3..5 (randint(3)+2) summons.
trap_do_summon:
    jsr trap_remove_floor
    lda zp_player_x
    sta chest_summon_x
    lda zp_player_y
    sta chest_summon_y
    lda #3
    jsr rng_range
    clc
    adc #3
    sta chest_pending_summons
    ldx #HSTR_PMU_GLYPH_OK
    jmp huff_print_msg

// Remove trap X and rewrite its tile preserving TILE_FLAG_MASK flags.
trap_remove_floor:
    lda #TILE_FLOOR | FLAG_VISITED
trap_remove_set_tile:
    pha
    lda trap_x,x
    sta df_target_x
    lda trap_y,x
    sta df_target_y
    jsr trap_remove_at_index
    pla
df_set_target_tile:
    sta df_tile_tmp
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora df_tile_tmp
    :MapWrite_ptr0_y()
    rts

// Aggravate chute: shriek and wake all monsters on the level.
trap_do_aggravate:
    ldx #HSTR_MAT_SHRIEK
    jsr huff_print_msg
    jmp monster_aggravate_all

// Plain-message damage traps (8..11: TRAP_DOOR, CORRODE, FIRE, ACID).
trap_do_trap_door:
    bit player_pflags           // PFLAG_FFALL == $80
    bmi !td_ffall+
    jsr trap_do_plain_apply
    beq !td_done+
    bne !td_descend+
!td_ffall:
    ldx #0                      // "You fell through a trap door!"
    jsr trap_get_8_str_x
    jsr msg_print
    ldx #HSTR_CHEST_UNAFFECTED
    jsr huff_print_msg
!td_descend:
    // Trap door: descend 1 level (clamped at 99) and regenerate
    lda zp_player_dlvl
    cmp #99
    bcs !td_regen+
    inc zp_player_dlvl
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    cmp player_data + PL_MAX_DLVL
    bcc !td_regen+
    sta player_data + PL_MAX_DLVL
!td_regen:
    lda #0
    sta level_entry_dir
    jmp scroll_teleport_level_exec

trap_do_corrode:
    jsr trap_do_plain_apply
    beq !td_done+
    jmp mon_atk_acid_armour

trap_do_acid:
    jsr trap_do_plain_setup
    lda zp_math_a           // 4d6 <= 24; preserve rolled damage across overlay recalc
    pha
    jsr mon_atk_acid_armour
    lda #1
    adc #0                  // Divisor 2 when worn piece took acid (C=1), else 1
    tax
    pla
    sta zp_math_a
    lda #0
    sta zp_math_b
    lda player_pflags
    and #PFLAG_RESIST_ACID
    beq trap_div_apply
    inx
    inx                     // +2 for Resist Acid -> divisor 3 or 4
    bne trap_div_apply      // Always (X is 3 or 4)

trap_do_fire:
    jsr trap_do_plain_setup
    lda #1
    ldx #DF_MS_BREATH_FIRE
    jsr mm_element_divisor_entry
    ldx mm_divisor
trap_div_apply:
    jsr math_div_16x8       // X >= 1 (divisor 1 leaves quotient unchanged)
    jmp trap_apply_rolled_damage
!td_done:
    rts

trap_do_plain_apply:
    jsr trap_do_plain_setup
    jmp trap_apply_rolled_damage

// Set up plain-string trap (df_search_chance in 8..11): death metadata,
// message, and rolled dice.
trap_do_plain_setup:
    lda df_search_chance
    sec
    sbc #TRAP_TRAP_DOOR
    tax
    lda trap_dsrc_8,x
    sta df_death_source
    lda #0
    sta df_death_hstr
    jsr trap_get_8_str_x
    jsr msg_print
    ldx #6
    lda #4                  // 4d6 for CORRODE, FIRE, ACID
    ldy df_death_source
    cpy #DEATH_TRAP_PIT
    bne !tdps_roll+
    lda #2                  // 2d8 for TRAP_TRAP_DOOR
    ldx #8
!tdps_roll:
    ldy #0
    jmp math_dice

// Point zp_ptr0/hi at plain trap string X (0..3=hit msg, 4..7=death noun).
// Preserves Y, clobbers A.
trap_get_8_str_x:
    lda #<trap_8_strs
    clc
    adc trap_8_off,x
    sta zp_ptr0
    lda #>trap_8_strs
    adc #0
    sta zp_ptr0_hi
    rts

trap_handler_lo:
    .byte <(trap_do_pit - 1),        <(trap_do_arrow - 1),     <(trap_do_gas - 1),       <(trap_do_teleport - 1)
    .byte <(trap_do_dart - 1),       <(trap_do_rockfall - 1),  <(trap_do_covered_pit - 1), <(trap_do_dart - 1)
    .byte <(trap_do_trap_door - 1),  <(trap_do_corrode - 1),   <(trap_do_fire - 1),      <(trap_do_acid - 1)
    .byte <(trap_do_gas - 1),        <(trap_do_gas - 1),       <(trap_do_gas - 1)
    .byte <(trap_do_hidden_obj - 1), <(trap_do_summon - 1),    <(trap_do_aggravate - 1)
trap_handler_lo_end:
.assert "trap_handler_lo covers TRAP_TYPE_COUNT", trap_handler_lo_end - trap_handler_lo, TRAP_TYPE_COUNT

trap_handler_hi:
    .byte >(trap_do_pit - 1),        >(trap_do_arrow - 1),     >(trap_do_gas - 1),       >(trap_do_teleport - 1)
    .byte >(trap_do_dart - 1),       >(trap_do_rockfall - 1),  >(trap_do_covered_pit - 1), >(trap_do_dart - 1)
    .byte >(trap_do_trap_door - 1),  >(trap_do_corrode - 1),   >(trap_do_fire - 1),      >(trap_do_acid - 1)
    .byte >(trap_do_gas - 1),        >(trap_do_gas - 1),       >(trap_do_gas - 1)
    .byte >(trap_do_hidden_obj - 1), >(trap_do_summon - 1),    >(trap_do_aggravate - 1)
trap_handler_hi_end:
.assert "trap_handler_hi covers TRAP_TYPE_COUNT", trap_handler_hi_end - trap_handler_hi, TRAP_TYPE_COUNT

trap_huff_msg_t:  .byte HSTR_DF_YOU_FELL, HSTR_DF_ARROW_HITS, HSTR_DF_ROCKFALL, HSTR_DF_DART_HITS
trap_huff_dsrc_t: .byte DEATH_TRAP_PIT, DEATH_TRAP_ARROW, DEATH_TRAP_ROCKFALL, DEATH_TRAP_DART
trap_huff_dhst_t: .byte HSTR_DF_TRAP_0, HSTR_DF_TRAP_1, HSTR_DF_DEATH_ROCKFALL, HSTR_DF_TRAP_4
trap_huff_dice_t: .byte 2, 1, 2, 1
trap_huff_side_t: .byte 6, 8, 6, 4

gas_rng_max:  .byte 10, 4, 50, 15
gas_rng_base: .byte 11, 5, 26, 16
gas_zp_eff:   .byte zp_eff_poison, zp_eff_paralyze, zp_eff_blind, zp_eff_confuse
gas_msg_hstr: .byte HSTR_DF_POISONED, HSTR_CHEST_CHOKE, HSTR_PIQ_CANT_SEE, HSTR_PIQ_DIZZY
.assert "Gas timers are zero-page", zp_eff_poison < $100 && zp_eff_paralyze < $100 && zp_eff_blind < $100 && zp_eff_confuse < $100, true

trap_dsrc_8: .byte DEATH_TRAP_PIT, DEATH_TRAP_ARROW, DEATH_TRAP_ROCKFALL, DEATH_TRAP_ROCKFALL
trap_8_off:
    .byte trap_8_s0 - trap_8_strs, trap_8_s1 - trap_8_strs, trap_8_s2 - trap_8_strs, trap_8_s3 - trap_8_strs
    .byte trap_8_s4 - trap_8_strs, trap_8_s5 - trap_8_strs, trap_8_s6 - trap_8_strs, trap_8_s7 - trap_8_strs
trap_8_strs:
trap_8_s0: .text "A trap door opens!" ; .byte 0
trap_8_s1: .text "A blade hits you!" ; .byte 0
trap_8_s2: .text "Flames hit you!" ; .byte 0
trap_8_s3: .text "Acid hits you!" ; .byte 0
trap_8_s4: .text "a trap door" ; .byte 0
trap_8_s5: .text "a blade" ; .byte 0
trap_8_s6: .text "a fire trap" ; .byte 0
trap_8_s7: .text "an acid trap" ; .byte 0
trap_8_strs_end:
.assert "trap_8_strs fits 256 bytes", trap_8_strs_end - trap_8_strs <= 256, true

// ============================================================
// trap_apply_damage — Roll damage and subtract from player HP
// Input: A = dice count, X = dice sides (no bonus: every trap is plain dice)
// Prints "YOU TAKE N DAMAGE." message.
// ============================================================
trap_apply_damage:
    ldy #0                  // +0
    jsr math_dice           // Result in zp_math_a (lo), zp_math_b (hi)
trap_apply_rolled_damage:

    // Save damage amount
    lda zp_math_a
    sta df_target_x         // Reuse scratch for damage value

    // Subtract from player HP (16-bit)
    lda zp_player_hp_lo
    sec
    sbc zp_math_a
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc zp_math_b
    sta zp_player_hp_hi

    // Clamp lethal trap damage before syncing the player struct (A and N
    // still hold the high byte).
    bmi !trap_lethal+
    ora zp_player_hp_lo
    bne !trap_sync+

!trap_lethal:
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    lda df_death_source
    sta zp_death_source
    jsr trap_resolve_death_name

!trap_sync:
    // Sync to player struct
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Print "YOU TAKE N DAMAGE."
    ldx #HSTR_DF_DAMAGE_PRE
    jsr huff_print_msg

    // Print damage number and " DAMAGE." inline on same row
    // msg_print left cursor at end of "YOU TAKE "
    // Set message color for inline text
    lda zp_text_color
    pha
    lda #COL_MSG_TEXT
    sta zp_text_color

    lda df_target_x
    jsr screen_put_decimal

    ldx #HSTR_DF_DAMAGE_POST
    jsr huff_decode_string
    jsr hal_screen_put_string

    pla
    sta zp_text_color

    // Play hit sound for surviving hits; lethal trap damage uses the
    // standard death path so the death sound is not overwritten.
    // Returns Z=1 if dead, Z=0 if alive.
    lda zp_player_hp_hi
    ora zp_player_hp_lo
    beq !trap_death+

    lda #SFX_HIT
    jsr hal_sound_play
    lda #1
    rts

!trap_death:
    jsr player_death_check
    lda #0
    rts

// ============================================================
// trap_resolve_death_name — Resolve lethal trap cause text
// ============================================================
// Copies the existing trap name string into creature_name_buf so the death
// overlay can display it after tier/overlay memory has been replaced.
trap_resolve_death_name:
    ldx df_death_hstr
    beq !trdn_plain+
    jsr huff_decode_string
    lda #<hd_decode_buf
    sta zp_ptr0
    lda #>hd_decode_buf
    sta zp_ptr0_hi
    bne !trdn_copy_ptr+     // hd_decode_buf hi-byte is non-zero
!trdn_plain:
    lda df_search_chance
    sec
    sbc #TRAP_TRAP_DOOR - 4
    tax
    jsr trap_get_8_str_x
!trdn_copy_ptr:
    ldy #0
!trdn_copy:
    lda (zp_ptr0),y
    sta creature_name_buf,y
    beq !trdn_done+         // Static trap death names are <= 13 bytes (< 32)
    iny
    bne !trdn_copy-
!trdn_done:
    rts

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
    // locked (val > 0) → pick attempt; stuck (val < 0) → must be bashed.
    jsr door_state_get_target
    sta df_found                // Signed door state
    beq !dto_open_it+           // Plain door → open
    bmi !dto_stuck+

    // Locked: pick the lock (VMS openobject / Umoria playerOpenClosedObject):
    // success iff disarm_skill - lock > randint(100); +1 XP on success.
    lda zp_eff_confuse
    beq !dto_pick+
    ldx #HSTR_DF_PICK_CONFUSED
    jmp df_msg_sec
!dto_pick:
    // The effective-disarm formula is overlay-parked on every product build,
    // so resident callers reach the colocated roll via tramp_door_pick_roll.
    // Carry set = picked.
#if DOOR_PICK_EXTERNAL
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
