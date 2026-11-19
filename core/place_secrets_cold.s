// place_secrets_cold.s — Secret-door conversion and locked/stuck door-state roll
//
// Module ownership:
//   owner: DungeonGenOverlay when PLACE_SECRETS_EXTERNAL is defined (imported
//     by core/dungeon_gen.s or explicitly by the port); Default / DoorStateSegment
//     otherwise (imported by core/dungeon_features.s).
//   lifetime: one dungeon-level generation call.
//   callers: dungeon_generate (core/dungeon_gen.s) exclusively.
//   guard: PLACE_SECRETS_EMITTED prevents duplicate global labels if a port
//     both defines PLACE_SECRETS_EXTERNAL and imports place_secrets_cold.s.

#if !PLACE_SECRETS_EMITTED
#define PLACE_SECRETS_EMITTED

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

#endif
