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

#if !DUNGEON_FEATURES_GENERATION_ONLY
// ============================================================
// Trap name Huffman indices (indexed by trap type 0-5)
// ============================================================
trap_name_huff_idx:
    .byte HSTR_DF_TRAP_0, HSTR_DF_TRAP_1, HSTR_DF_TRAP_2
    .byte HSTR_DF_TRAP_3, HSTR_DF_TRAP_4, HSTR_DF_TRAP_5
#endif

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_HELPERS_EXTERNAL
trap_difficulty:
    .byte 5, 15, 10, 20, 20, 25
#endif

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
trap_disarm_xp:
    .byte 1, 3, 2, 5, 6, 8

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
// Output: carry set = found (df_target_x/y valid)
//         carry clear = failed after 200 tries
// Uses df_found as attempt counter (caller-save).
// ============================================================
frf_attempts: .byte 0

find_random_floor:
    lda #200
    sta frf_attempts

!frf_loop:
    // Random x in [1, MAP_COLS-2]
    lda #MAP_COLS - 2
    jsr rng_range           // [0, 77]
    clc
    adc #1                  // [1, 78]
    sta df_target_x

    // Random y in [1, MAP_ROWS-2]
    lda #MAP_ROWS - 2
    jsr rng_range           // [0, 45]
    clc
    adc #1                  // [1, 46]
    sta df_target_y

    // Check if tile is unoccupied floor
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !frf_next+
    lda zp_temp0
    and #FLAG_OCCUPIED
    bne !frf_next+
    sec
    rts
!frf_next:

    dec frf_attempts
    bne !frf_loop-

    clc
    rts

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
#if C128_PRODUCT_OVERLAY_RUNTIME
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
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    stx df_target_y         // Save row

#if C128_PRODUCT_OVERLAY_RUNTIME
    // The C128 map lives in Bank 1. Copy once per row instead of switching
    // banks for every tile in this full-map generation scan.
    lda #MAP_COLS
    jsr mmu_common_copy_map_row
#endif

    ldy #1                  // Start at col 1
!ps_col:
#if C128_PRODUCT_OVERLAY_RUNTIME
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
    lda df_found
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
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
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
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    stx df_target_y
#if C128_PRODUCT_OVERLAY_RUNTIME
    lda #MAP_COLS
    jsr mmu_common_copy_map_row
#endif
    ldy #1
!pss_col:
#if C128_PRODUCT_OVERLAY_RUNTIME
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

    ldx #0
!tcp_loop:
    cpx trap_count
    bcs !tcp_done+

    lda trap_x,x
    cmp zp_player_x
    bne !tcp_next+
    lda trap_y,x
    cmp zp_player_y
    bne !tcp_next+

    // Found a trap at player position!
    // Save trap index
    stx df_dir_idx

    // Reveal trap on map: change tile to TILE_TRAP | flags
    ldy zp_player_y
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK     // Keep existing flags
    ora #TILE_TRAP          // Set tile type to trap
    ora #FLAG_VISITED       // Ensure visible
    :MapWrite_ptr0_y()

    // Trigger the trap effect
    ldx df_dir_idx
    jsr trap_trigger

    // Done (only one trap per tile)
    sec                     // Carry set = trap fired
    rts

!tcp_next:
    inx
    jmp !tcp_loop-

!tcp_done:
    clc                     // Carry clear = no trap
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
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !not_found+

    ldx #0
!scan:
    cpx trap_count
    bcs !not_found+
    lda trap_x,x
    cmp df_target_x
    bne !next+
    lda trap_y,x
    cmp df_target_y
    bne !next+
    stx df_disarm_trap_idx
    sec
    rts
!next:
    inx
    jmp !scan-
!not_found:
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
    sta zp_ptr0
    lda #>disarm_no_visible_str
    sta zp_ptr0_hi
    jsr msg_print
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
    sta zp_ptr0
    lda #>disarm_fail_str
    sta zp_ptr0_hi
    jsr msg_print
    sec
    rts

!success:
    lda #<disarm_success_str
    sta zp_ptr0
    lda #>disarm_success_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr disarm_award_trap_xp
    jsr disarm_restore_target_floor
    ldx df_disarm_trap_idx
    jsr trap_remove_at_index
    jsr disarm_move_player_to_target
    sec
    rts

!bad_fail:
    lda #<disarm_bad_fail_str
    sta zp_ptr0
    lda #>disarm_bad_fail_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr disarm_move_player_to_target
    ldx df_disarm_trap_idx
    jsr trap_trigger
    sec
    rts

disarm_restore_target_floor:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
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
// trap_trigger — Execute a trap's effect
// Input: X = trap table index (trap_type[X] has the type)
// ============================================================
trap_trigger:
    jsr player_search_mode_off
    lda trap_type,x

    cmp #TRAP_OPEN_PIT
    bne !not_pit+
    // Open pit: 1d4 damage (formerly trap_do_pit, inlined at its only
    // dispatch site)
    ldx #HSTR_DF_YOU_FELL
    jsr huff_print_msg
    lda #DEATH_TRAP_PIT
    sta df_death_source
    lda #HSTR_DF_TRAP_0
    sta df_death_hstr
    lda #1              // 1 die
    ldx #4              // d4
    ldy #0              // +0
    jmp trap_apply_damage
!not_pit:
    cmp #TRAP_ARROW
    bne !not_arrow+
    jmp trap_do_arrow
!not_arrow:
    cmp #TRAP_POISON_GAS
    bne !not_gas+
    jmp trap_do_gas
!not_gas:
    cmp #TRAP_TELEPORT
    bne !not_tele+
    jmp trap_do_teleport
!not_tele:
    cmp #TRAP_POISON_DART
    bne !not_dart+
    jmp trap_do_dart
!not_dart:
    // Must be TRAP_ROCKFALL
    jmp trap_do_rockfall

// --- Trap effect handlers ---

// Arrow trap: 1d8 damage
trap_do_arrow:
    ldx #HSTR_DF_ARROW_HITS
    jsr huff_print_msg
    lda #DEATH_TRAP_ARROW
    sta df_death_source
    lda #HSTR_DF_TRAP_1
    sta df_death_hstr
    lda #1
    ldx #8
    ldy #0
    jmp trap_apply_damage

// Poison gas: set poison timer to 10 + 1d10
trap_do_gas:
    ldx #HSTR_DF_POISON_GAS
    jsr huff_print_msg
    // Set poison timer: 10 + rng_range(10) + 1 = 11..20
    lda #10
    jsr rng_range           // [0, 9]
    clc
    adc #11                 // [11, 20]
    sta zp_eff_poison
    // Print "YOU FEEL POISONED."
    ldx #HSTR_DF_POISONED
    jmp huff_print_msg

// Teleport: move player to random floor tile
trap_do_teleport:
    ldx #HSTR_DF_TELEPORTED
    jsr huff_print_msg
    jmp trap_teleport

// Poison dart: 1d4 damage + 50% chance CON decrement
trap_do_dart:
    ldx #HSTR_DF_DART_HITS
    jsr huff_print_msg
    lda #DEATH_TRAP_DART
    sta df_death_source
    lda #HSTR_DF_TRAP_4
    sta df_death_hstr
    lda #1
    ldx #4
    ldy #0
    jsr trap_apply_damage
    // 50% chance to lose 1 CON
    jsr rng_byte
    and #1
    beq !no_con_drain+
    // Decrement CON
    lda player_data + PL_CON_CUR
    cmp #4                  // Don't go below 3
    bcc !no_con_drain+
    jsr decrement_stat
    sta player_data + PL_CON_CUR
    sta zp_player_con
    ldx #HSTR_DF_CON_DRAIN
    jsr huff_print_msg
!no_con_drain:
    rts

// Rockfall: 2d8 damage
trap_do_rockfall:
    ldx #HSTR_DF_ROCKFALL
    jsr huff_print_msg
    lda #DEATH_TRAP_ROCKFALL
    sta df_death_source
    lda #HSTR_DF_DEATH_ROCKFALL
    sta df_death_hstr
    lda #2              // 2 dice
    ldx #8              // d8
    ldy #0              // +0
    jmp trap_apply_damage

// ============================================================
// trap_apply_damage — Roll damage and subtract from player HP
// Input: A = dice count, X = dice sides, Y = bonus
// Prints "YOU TAKE N DAMAGE." message.
// ============================================================
trap_apply_damage:
    jsr math_dice           // Result in zp_math_a (lo), zp_math_b (hi)

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

    // Clamp lethal trap damage before syncing the player struct.
    lda zp_player_hp_hi
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
    lda zp_player_hp_hi
    ora zp_player_hp_lo
    beq !trap_death+

    lda #SFX_HIT
    jmp hal_sound_play

!trap_death:
    jmp player_death_check

// ============================================================
// trap_resolve_death_name — Resolve lethal trap cause text
// ============================================================
// Copies the existing trap name string into creature_name_buf so the death
// overlay can display it after tier/overlay memory has been replaced.
trap_resolve_death_name:
    ldx df_death_hstr
    jsr huff_decode_string
    ldy #0
!trdn_copy:
    lda hd_decode_buf,y
    sta creature_name_buf,y
    beq !trdn_done+
    iny
    cpy #31
    bne !trdn_copy-
    lda #0
    sta creature_name_buf,y
!trdn_done:
    rts

// ============================================================
// trap_teleport — Move player to a random floor tile
// ============================================================
trap_teleport:
    jsr player_search_mode_off
    // Find a random floor tile using simple scan
    lda #100                // Max attempts
    sta df_found
!tt_loop:
    // Random x in [1, MAP_COLS-2]
    lda #MAP_COLS - 2
    jsr rng_range
    clc
    adc #1
    sta df_target_x

    // Random y in [1, MAP_ROWS-2]
    lda #MAP_ROWS - 2
    jsr rng_range
    clc
    adc #1
    sta df_target_y

    // Check if floor
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !tt_found+

    dec df_found
    bne !tt_loop-
    rts                     // Give up, stay in place

!tt_found:
    // Move player to new position
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
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

// ============================================================
// door_try_open — Attempt to open a door at (df_target_x, df_target_y).
// Consults per-door state: plain doors open, locked doors roll the lock
// pick (door_pick_roll), stuck doors are refused (jam/bash to clear).
// Output: carry set = door opened (or stuck msg shown, turn consumed)
//         carry clear = no door there
// ============================================================
door_try_open:
    // Read map tile at target
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta df_dir_idx          // Save full tile byte

    // Check tile type
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !dto_closed+
    cmp #TILE_DOOR_OPEN
    beq !dto_already_open+
    cmp #TILE_SECRET
    beq !dto_no_door+       // Secret doors can't be opened directly

    // Not a door
!dto_no_door:
    ldx #HSTR_DF_NO_DOOR
    jsr huff_print_msg
    clc                     // No turn consumed
    rts

!dto_already_open:
    ldx #HSTR_DF_ALREADY_OPEN
    jsr huff_print_msg
    clc                     // No turn consumed
    rts

!dto_closed:
    // Real per-door state (replaces the old transient 25% stuck roll):
    // locked (val > 0) → pick attempt; stuck (val < 0) → must be bashed.
    lda df_target_x
    ldy df_target_y
    jsr door_state_get
    sta df_found                // Signed door state
    beq !dto_open_it+           // Plain door → open
    bmi !dto_stuck+

    // Locked: pick the lock (VMS openobject / Umoria playerOpenClosedObject):
    // success iff disarm_skill - lock > randint(100); +1 XP on success.
    lda zp_eff_confuse
    beq !dto_pick+
    ldx #HSTR_DF_PICK_CONFUSED
    jsr huff_print_msg
    sec                         // Turn consumed
    rts
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
    jsr huff_print_msg
    sec                         // Turn consumed (retry allowed)
    rts
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
    jmp !dto_open_it+           // Picked doors open in the same turn

!dto_stuck:
    ldx #HSTR_DF_STUCK
    jsr huff_print_msg
    lda #SFX_BUMP
    jsr hal_sound_play
    sec                         // Turn consumed
    rts

!dto_open_it:
    // Open the door: change tile type to TILE_DOOR_OPEN, keep flags
    lda df_dir_idx          // Original tile byte
    and #TILE_FLAG_MASK     // Keep flags
    ora #TILE_DOOR_OPEN     // Set to open door
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda df_dir_idx
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_OPEN
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_DOOR_OPENED
    jsr huff_print_msg
    sec                     // Turn consumed
    rts

// ============================================================
// door_try_close — Attempt to close a door at (df_target_x, df_target_y)
// Output: carry set = door closed, carry clear = no open door there
// ============================================================
door_try_close:
    // Read map tile at target
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    sta df_dir_idx          // Save full tile byte

    // Check tile type
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !dtc_open+
    cmp #TILE_DOOR_CLOSED
    beq !dtc_already_closed+

    // Not a door
    ldx #HSTR_DF_NO_DOOR
    jsr huff_print_msg
    clc
    rts

!dtc_already_closed:
    ldx #HSTR_DF_ALREADY_CLOSED
    jsr huff_print_msg
    clc
    rts

!dtc_open:
    // Broken doors (state 1 on an open tile) cannot be closed
    // (VMS closeobject / Umoria playerCloseDoor: "The door appears to be
    // broken.", turn consumed).
    lda df_target_x
    ldy df_target_y
    jsr door_state_get
    cmp #1
    bne !dtc_not_broken+
    ldx #HSTR_DF_DOOR_BROKEN
    jsr huff_print_msg
    sec                         // Turn consumed
    rts
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
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()
    lda df_dir_idx
    and #~FLAG_OCCUPIED & $ff
    sta df_dir_idx

!dtc_do_close:
    // Close the door
    lda df_dir_idx
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    lda df_dir_idx
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_DOOR_CLOSED
    jsr huff_print_msg
    sec                     // Turn consumed
    rts

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
    bcc !dsca_done+
    jmp door_state_remove_idx
!dsca_done:
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
    sta door_state_val,x
    inc door_state_count
    rts
!dss_update:
    lda dss_val
    beq !dss_remove+
    sta door_state_val,x
!dss_done:
    rts
!dss_remove:
    jmp door_state_remove_idx
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
    jsr door_jam_at_target
    rts
!djc_free:
    clc
    rts

// door_jam_at_target — Jam logic on (df_target_x, df_target_y).
// Output: carry set = turn consumed, clear = free.
door_jam_at_target:
    // Read map tile at target
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
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
    sta zp_ptr0
    lda #>jam_str_close_first
    sta zp_ptr0_hi
    jsr msg_print
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
    sta zp_ptr0
    lda #>jam_str_no_spikes
    sta zp_ptr0_hi
    jsr msg_print
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
    dec inv_qty,x
    bne !cj_done+
    jsr inv_remove_item
!cj_done:
    lda #<jam_str_jammed
    sta zp_ptr0
    lda #>jam_str_jammed
    sta zp_ptr0_hi
    jsr msg_print
    sec                           // Turn consumed
    rts
!cj_table_full:
    lda #<jam_str_cannot
    sta zp_ptr0
    lda #>jam_str_cannot
    sta zp_ptr0_hi
    jsr msg_print
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

    // Loop through 8 directions (indices 0-7)
    lda #0
    sta df_dir_idx

!ds_loop:
    ldx df_dir_idx

    // Compute adjacent tile coordinates
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x

    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    // Bounds check — use trampoline for distance
    lda df_target_x
    beq !ds_skip+
    cmp #MAP_COLS - 1
    bcs !ds_skip+
    lda df_target_y
    beq !ds_skip+
    cmp #MAP_ROWS - 1
    bcc !ds_bounds_ok+
!ds_skip:
    jmp !ds_next+
!ds_bounds_ok:

    // Read map tile
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK

    // Check for secret door
    cmp #TILE_SECRET
    bne !ds_chest_gate+

    lda df_search_chance
    beq !ds_chest_gate+
    lda #100
    jsr rng_range
    cmp df_search_chance
    bcs !ds_chest_gate+

!ds_secret_found:
    // Reveal: change to TILE_DOOR_CLOSED
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    :MapWrite_ptr0_y()

    ldx #HSTR_DF_FOUND_SECRET
    jsr huff_print_msg
    lda #1
    sta df_found
    jmp !ds_next+

!ds_chest_gate:
#if CHEST_ROUTING_ENABLED
    // Chest branch (docs/CHEST_DESIGN.md): gated on FLAG_HAS_ITEM so the
    // floor-table scan stays off the per-move hot path.
    ldy df_target_x
    :MapRead_ptr0_y()
    and #FLAG_HAS_ITEM
    beq !ds_check_trap+
    jsr chest_search_reveal
    bcc !ds_check_trap+
    jmp !ds_next+
#else
    jmp !ds_check_trap+
#endif

!ds_check_trap:
    // Check trap table for hidden traps at this position
    ldx #0
!ds_trap_scan:
    cpx trap_count
    bcs !ds_next+

    lda trap_x,x
    cmp df_target_x
    bne !ds_trap_next+
    lda trap_y,x
    cmp df_target_y
    bne !ds_trap_next+

    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    beq !ds_trap_next+

    txa
    pha                     // Save trap index on stack

    lda df_search_chance
    beq !ds_trap_not_found+
    lda #100
    jsr rng_range
    cmp df_search_chance
    bcs !ds_trap_not_found+

!ds_trap_found:
    // Reveal trap: change map tile to TILE_TRAP | flags
    pla                     // Restore trap index
    tax

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

    ldx #HSTR_DF_FOUND_TRAP
    jsr huff_print_msg
    lda #1
    sta df_found
    jmp !ds_next+

!ds_trap_not_found:
    pla                     // Discard saved trap index

!ds_trap_next:
    inx
    jmp !ds_trap_scan-

!ds_next:
    inc df_dir_idx
    lda df_dir_idx
    cmp #8
    beq !ds_done+
    jmp !ds_loop-

!ds_done:
    lda df_found
    beq !ds_none+
    sec
    rts
!ds_none:
    clc
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
.assert "TRAP_TYPE_COUNT", TRAP_TYPE_COUNT, 6
#endif
