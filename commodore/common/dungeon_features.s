// dungeon_features.s — Doors, traps, secret doors, search
//
// Phase 4.2: Explicit open/close door commands, stuck door mechanics,
// hidden trap placement and triggering, secret doors found by searching.

// ============================================================
// Constants
// ============================================================
.const MAX_TRAPS = 16

// Trap type indices
.const TRAP_OPEN_PIT    = 0   // 1d4 damage
.const TRAP_ARROW       = 1   // 1d8 damage
.const TRAP_POISON_GAS  = 2   // Set poison timer
.const TRAP_TELEPORT    = 3   // Random teleport
.const TRAP_POISON_DART = 4   // 1d4 damage + 50% CON loss
.const TRAP_ROCKFALL    = 5   // 2d8 damage
.const TRAP_TYPE_COUNT  = 6

// ============================================================
// Trap table — parallel arrays (SoA)
// Hidden traps stored here; NOT in map tiles until triggered/found.
// ============================================================
trap_count: .byte 0
trap_x:     .fill MAX_TRAPS, 0
trap_y:     .fill MAX_TRAPS, 0
trap_type:  .fill MAX_TRAPS, 0

// ============================================================
// Local scratch (safe from rng_range clobbering zp_temp3/4)
// ============================================================
df_target_x: .byte 0   // Target tile X for door commands
df_target_y: .byte 0   // Target tile Y for door commands
df_dir_idx:  .byte 0   // Direction index from get_direction_target
df_found:    .byte 0   // Search found-something flag

// ============================================================
// Trap name Huffman indices (indexed by trap type 0-5)
// ============================================================
trap_name_huff_idx:
    .byte HSTR_DF_TRAP_0, HSTR_DF_TRAP_1, HSTR_DF_TRAP_2
    .byte HSTR_DF_TRAP_3, HSTR_DF_TRAP_4, HSTR_DF_TRAP_5


// ============================================================
// place_traps — Place hidden traps on the dungeon floor
// Called from dungeon_generate after place_doors.
// Number of traps: rng_range(dlvl+1) + 2, capped at MAX_TRAPS.
// Traps placed at random floor tiles (corridors or rooms).
// ============================================================
place_traps:
    // Don't place traps on town level
    lda zp_player_dlvl
    bne !not_town+
    rts
!not_town:
    // Number of traps = rng_range(dlvl+1) + 2
    lda zp_player_dlvl
    clc
    adc #1
    cmp #MAX_TRAPS
    bcc !cap_ok+
    lda #MAX_TRAPS
!cap_ok:
    jsr rng_range           // [0, dlvl]
    clc
    adc #2                  // [2, dlvl+2]
    cmp #MAX_TRAPS + 1
    bcc !count_ok+
    lda #MAX_TRAPS
!count_ok:
    sta trap_count

    lda #0
    sta dg_idx              // Reuse dungeon gen scratch as trap index

!pt_loop:
    lda dg_idx
    cmp trap_count
    beq !pt_done+

    // Find a random floor tile
    jsr find_random_floor

    // Store in trap table
    ldx dg_idx
    lda df_target_x
    sta trap_x,x
    lda df_target_y
    sta trap_y,x

    // Random trap type: rng_range(TRAP_TYPE_COUNT)
    lda #TRAP_TYPE_COUNT
    jsr rng_range
    ldx dg_idx
    sta trap_type,x

    inc dg_idx
    jmp !pt_loop-

!pt_done:
    rts

// ============================================================
// find_random_floor — Find a random walkable floor tile on the map
// Output: df_target_x, df_target_y = floor tile coordinates
// Tries up to 200 times, then gives up (returns last attempt).
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
    lda (zp_ptr0),y
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !frf_next+
    lda zp_temp0
    and #FLAG_OCCUPIED
    bne !frf_next+
    jmp !frf_found+
!frf_next:

    dec frf_attempts
    bne !frf_loop-

!frf_found:
    rts

// ============================================================
// place_secrets — Convert 1-3 random closed doors to secret doors
// Scans map for TILE_DOOR_CLOSED, collects into temp list,
// then picks 1-3 to convert to TILE_SECRET.
// ============================================================

// Temp buffer for door positions found during scan
.const MAX_DOOR_SCAN = 32
door_scan_x: .fill MAX_DOOR_SCAN, 0
door_scan_y: .fill MAX_DOOR_SCAN, 0
door_scan_count: .byte 0

place_secrets:
    // Don't place secrets on town level
    lda zp_player_dlvl
    bne !ps_not_town+
    rts
!ps_not_town:

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

    ldy #1                  // Start at col 1
!ps_col:
    lda (zp_ptr0),y
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
    beq !ps_done+           // None found

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
    beq !ps_convert+
    lda door_scan_count
    sta df_found

!ps_convert:
    lda df_found
    beq !ps_done+

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
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK     // Keep flags
    ora #TILE_SECRET        // Change type to secret
    sta (zp_ptr0),y

    // Remove from scan list: swap picked entry with last, decrement count
    dec door_scan_count
    ldx df_dir_idx          // X = picked index
    ldy door_scan_count     // Y = new last index (was count-1)
    lda door_scan_x,y
    sta door_scan_x,x
    lda door_scan_y,y
    sta door_scan_y,x

    dec df_found
    jmp !ps_convert-

!ps_done:
    rts

// ============================================================
// trap_check_at_player — Check if player stepped on a hidden trap
// Scans trap table for player's (x, y). If found: trigger trap,
// reveal trap on map, remove from trap table.
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
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK     // Keep existing flags
    ora #TILE_TRAP          // Set tile type to trap
    ora #FLAG_VISITED       // Ensure visible
    sta (zp_ptr0),y

    // Trigger the trap effect
    ldx df_dir_idx
    jsr trap_trigger

    // Remove trap from table: swap with last entry, decrement count
    ldx df_dir_idx
    dec trap_count
    ldy trap_count          // Y = index of last entry
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x

    // Done (only one trap per tile)
    sec                     // Carry set = trap fired
    rts

!tcp_next:
    inx
    jmp !tcp_loop-

!tcp_done:
    clc                     // Carry clear = no trap
    rts

// ============================================================
// trap_trigger — Execute a trap's effect
// Input: X = trap table index (trap_type[X] has the type)
// ============================================================
trap_trigger:
    lda trap_type,x

    cmp #TRAP_OPEN_PIT
    bne !not_pit+
    jmp trap_do_pit
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

// Open pit: 1d4 damage
trap_do_pit:
    ldx #HSTR_DF_YOU_FELL
    jsr huff_print_msg
    lda #1              // 1 die
    ldx #4              // d4
    ldy #0              // +0
    jsr trap_apply_damage
    rts

// Arrow trap: 1d8 damage
trap_do_arrow:
    ldx #HSTR_DF_ARROW_HITS
    jsr huff_print_msg
    lda #1
    ldx #8
    ldy #0
    jsr trap_apply_damage
    rts

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
    jsr huff_print_msg
    rts

// Teleport: move player to random floor tile
trap_do_teleport:
    ldx #HSTR_DF_TELEPORTED
    jsr huff_print_msg
    jsr trap_teleport
    rts

// Poison dart: 1d4 damage + 50% chance CON decrement
trap_do_dart:
    ldx #HSTR_DF_DART_HITS
    jsr huff_print_msg
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
    lda #2              // 2 dice
    ldx #8              // d8
    ldy #0              // +0
    jsr trap_apply_damage
    rts

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
    jsr screen_put_string

    pla
    sta zp_text_color

    // Play hit sound
    lda #SFX_HIT
    jsr sound_play

    rts

// ============================================================
// trap_teleport — Move player to a random floor tile
// ============================================================
trap_teleport:
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
    lda (zp_ptr0),y
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

    // Wait for a keypress
    jsr input_get_key

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
// door_try_open — Attempt to open a door at (df_target_x, df_target_y)
// 25% chance the door is stuck (mitigated by STR >= 16).
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
    lda (zp_ptr0),y
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
    // 25% chance stuck (roll 0-3, stuck if 0)
    lda #4
    jsr rng_range           // [0, 3]
    cmp #0
    bne !dto_open_it+

    // Check STR — if >= 16, force open anyway
    lda zp_player_str
    cmp #16
    bcs !dto_open_it+

    // Door is stuck
    ldx #HSTR_DF_DOOR_STUCK
    jsr huff_print_msg
    lda #SFX_BUMP
    jsr sound_play
    sec                     // Turn consumed (attempted)
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
    sta (zp_ptr0),y

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
    lda (zp_ptr0),y
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
    sta (zp_ptr0),y

    ldx #HSTR_DF_DOOR_CLOSED
    jsr huff_print_msg
    sec                     // Turn consumed
    rts

// ============================================================
// do_search — Search adjacent tiles for secrets and traps
// Scans all 8 adjacent tiles. For each:
//   - If TILE_SECRET: 1-in-6 chance to reveal as TILE_DOOR_CLOSED
//   - Check trap table for hidden traps: 1-in-6 chance to reveal
// Always consumes a turn.
// ============================================================
do_search:
    lda #0
    sta df_found            // Track if we found anything

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
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK

    // Check for secret door
    cmp #TILE_SECRET
    bne !ds_check_trap+

    // Secret door found — 1-in-6 chance to reveal
    lda #6
    jsr rng_range           // [0, 5]
    cmp #0
    bne !ds_check_trap+

    // Reveal: change to TILE_DOOR_CLOSED
    ldy df_target_x
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Print message
    ldx #HSTR_DF_FOUND_SECRET
    jsr huff_print_msg
    lda #1
    sta df_found
    jmp !ds_next+

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

    // Hidden trap found — 1-in-6 chance to reveal
    txa
    pha                     // Save trap index on stack

    lda #6
    jsr rng_range           // [0, 5]
    cmp #0
    bne !ds_trap_not_found+

    // Reveal trap: change map tile to TILE_TRAP | flags
    pla                     // Restore trap index
    tax

    // Set map tile
    ldy trap_y,x
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy trap_x,x
    lda (zp_ptr0),y
    and #TILE_FLAG_MASK
    ora #TILE_TRAP
    ora #FLAG_VISITED
    sta (zp_ptr0),y

    // Remove from trap table
    dec trap_count
    ldy trap_count
    lda trap_x,y
    sta trap_x,x
    lda trap_y,y
    sta trap_y,x
    lda trap_type,y
    sta trap_type,x

    // Print message
    ldx #HSTR_DF_FOUND_TRAP
    jsr huff_print_msg
    lda #1
    sta df_found
    jmp !ds_next+           // Move to next direction

!ds_trap_not_found:
    pla                     // Discard saved trap index
    // Fall through to next trap in table scan

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
    // If nothing was found, print "YOU FOUND NOTHING."
    lda df_found
    bne !ds_exit+
    ldx #HSTR_DF_FOUND_NOTHING
    jsr huff_print_msg
!ds_exit:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "MAX_TRAPS", MAX_TRAPS, 16
.assert "TRAP_TYPE_COUNT", TRAP_TYPE_COUNT, 6
