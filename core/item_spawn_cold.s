#importonce
// item_spawn_cold.s — Level-entry floor gold, item, and treasure-room spawner
//
// Module ownership:
//   owner: DungeonGenOverlay / ChestOverlay / HelpOverlay via ItemSpawnSegment
//     (ITEM_SPAWN_IN_GEN_OVERLAY) or explicit import (ITEM_SPAWN_EXTERNAL);
//     TestUnused in C64 unit tests that do not exercise floor spawning;
//     Default resident otherwise (imported by core/item.s).
//   lifetime: one level-transition call after monster_spawn_level.
//   callers: game_new_start and level_change_generate_current (core/game_loop.s)
//     via resident item_spawn_level dispatcher when overlay-hosted.
//     Ports placing item_spawn_cold.s in a different overlay than
//     pick_item_type_overlay (e.g. Plus/4 & C128 HelpOverlay) define
//     ITEM_SPAWN_PICKER_SEPARATE -> tramp_pick_item_type_spawn.

// ============================================================
// item_spawn_level — Spawn gold and items on the dungeon floor
// Called after monster_spawn_level at each level transition.
// Phase 1: Gold (2 + rng(3) + dlvl/2, cap 16)
// Phase 2: Non-gold items (1 + rng(2) + dlvl/3, cap 8)
// Phase 3: Treasure room (dlvl >= 3, one room gets extra items)
// Town = 0 items.
// Clobbers: everything
// ============================================================
isl_ngold_target: .byte 0      // Non-gold item count target
isl_treasure_dlvl: .byte 0     // Effective dlvl for treasure room enchant

#if ITEM_SPAWN_IN_GEN_OVERLAY || (ITEM_SPAWN_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME)
item_spawn_level_gen:
#else
item_spawn_level:
#endif
    jsr item_init_floor

    // Town = no items
    lda zp_player_dlvl
    bne !isl_dungeon+
    rts

!isl_dungeon:
    // ---- Phase 1: Gold ----
    // Base count = 2
    lda #2
    sta isl_target

    // + rng(3) -> [0, 2]
    lda #3
    jsr rng_range
    clc
    adc isl_target
    sta isl_target

    // + dlvl / 2
    lda zp_player_dlvl
    lsr                         // A = dlvl / 2
    clc
    adc isl_target
    sta isl_target

    // Cap at 16
    cmp #17
    bcc !isl_gold_capped+
    lda #16
    sta isl_target
!isl_gold_capped:

    lda #0
    sta isl_idx

!isl_gold_loop:
    lda isl_idx
    cmp isl_target
    bcs !isl_gold_done+

    // Find a random floor tile
    jsr find_random_floor
    bcc !isl_gold_done+

    // Set up floor item add
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Gold type: rng(2) -> ID 0 or 1
    lda #2
    jsr rng_range
    sta fi_add_id
    jsr fi_add_clear_plain_meta

    // Gold qty: rng_range_word(dlvl * 10) + 5 (16-bit)
    lda zp_player_dlvl
    ldx #10
    jsr math_multiply           // zp_math_a=lo, zp_math_b=hi
    lda zp_math_a
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1                // N = dlvl * 10
    jsr rng_range_word          // result in zp_temp2/3
    // Add 5 to 16-bit result
    lda zp_temp2
    clc
    adc #5
    sta fi_add_qty
    lda zp_temp3
    adc #0
    sta fi_add_qty_hi

    jsr floor_item_add
    // Ignore failure (table full)

    inc isl_idx
    jmp !isl_gold_loop-

!isl_gold_done:

    // ---- Phase 2: Non-gold items ----
    // Count: 1 + rng(2) + dlvl/3, cap 8
    lda #1
    sta isl_ngold_target

    lda #2
    jsr rng_range               // [0, 1]
    clc
    adc isl_ngold_target
    sta isl_ngold_target

    // + dlvl / 3
    lda zp_player_dlvl
    ldx #0
!isl_div3:
    cmp #3
    bcc !isl_div3_done+
    sec
    sbc #3
    inx
    jmp !isl_div3-
!isl_div3_done:
    txa
    clc
    adc isl_ngold_target
    sta isl_ngold_target

    // Cap at 8
    cmp #9
    bcc !isl_ngold_capped+
    lda #8
    sta isl_ngold_target
!isl_ngold_capped:

    lda #0
    sta isl_idx

!isl_ngold_loop:
    lda isl_idx
    cmp isl_ngold_target
    bcs !isl_ngold_done+

    // Find a random floor tile
    jsr find_random_floor
    bcc !isl_ngold_done+
    lda df_target_x
    sta fi_add_x
    lda df_target_y
    sta fi_add_y

    // Pick item type
#if ITEM_SPAWN_PICKER_SEPARATE
    jsr tramp_pick_item_type_spawn
#elif ITEM_SPAWN_IN_GEN_OVERLAY || (ITEM_SPAWN_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME)
    jsr pick_item_type_overlay
#else
    jsr pick_item_type
#endif
    jsr isl_roll_item           // id, enchantment, ego

    // Set qty: ammo spawns in stacks, everything else = 1
    lda #1
    sta fi_add_qty
    lda fi_add_ego
    and #ITEM_PAGE_BIT
    sta item_cur_page
    ldx fi_add_id
    jsr item_get_missile
    bpl !isl_qty_done+          // Bit 7 clear = not ammo
    // Ammo: qty = 7d6 -> [7, 42] (VMS magic_treasure, misc.inc)
    lda #7
    ldx #6
    ldy #0
    jsr math_dice
    lda zp_math_a
    sta fi_add_qty
!isl_qty_done:

    jsr floor_item_add          // a full table skips it

    inc isl_idx
    jmp !isl_ngold_loop-

!isl_ngold_done:

    // ---- Phase 3: Treasure room ----
    // Only on dlvl >= 3
    lda zp_player_dlvl
    cmp #3
    bcs !isl_has_treasure+
    jmp !isl_all_done+
!isl_has_treasure:

    // Check for vault room -> enhanced treasure
    lda #RT_VAULT
#if ITEM_SPAWN_DIRECT_FIND_SPECIAL_ROOM
    jsr find_special_room
#else
    jsr tramp_find_special_room
#endif
    bcc !isl_no_vault+

    // Vault: use vault room, dlvl+8, 4-8 items
    stx isl_idx
    lda zp_player_dlvl
    clc
    adc #8                      // dlvl+8
    sta isl_treasure_dlvl
    lda #5
    jsr rng_range               // [0, 4]
    clc
    adc #4                      // [4, 8]
    sta isl_ngold_target
    jmp !isl_treasure_setup_done+

!isl_no_vault:
    // Spawn nest gold if applicable (no-op if no nest)
    jsr tramp_spawn_nest_gold

    // Normal treasure room (pick random room)
    lda room_count
    bne !isl_has_rooms+
    jmp !isl_all_done+
!isl_has_rooms:
    jsr rng_range               // [0, room_count-1]
    sta isl_idx                 // Reuse as room index

    // Effective dlvl for treasure = dlvl + 5
    lda zp_player_dlvl
    clc
    adc #5
    sta isl_treasure_dlvl

    // Extra items: 2 + rng(3)
    lda #3
    jsr rng_range               // [0, 2]
    clc
    adc #2                      // [2, 4]
    sta isl_ngold_target        // Reuse as treasure count

!isl_treasure_setup_done:
    lda #0
    sta isl_target              // Reuse as treasure loop counter

!isl_treasure_loop:
    lda isl_target
    cmp isl_ngold_target
    bcs !isl_all_done+

    // Random position within room bounds
    // x = room_x[idx] + rng(room_w[idx])
    ldx isl_idx
    lda room_w,x
    jsr rng_range
    ldx isl_idx
    clc
    adc room_x,x
    sta fi_add_x

    // y = room_y[idx] + rng(room_h[idx])
    ldx isl_idx
    lda room_h,x
    jsr rng_range
    ldx isl_idx
    clc
    adc room_y,x
    sta fi_add_y

    // Verify it's a floor tile
    ldy fi_add_y
    jsr map_row_ptr0_y
    ldy fi_add_x
    :MapRead_ptr0_y()
    and #$f0                    // TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !isl_treasure_skip+

    // Pick item with boosted dlvl
    // Temporarily boost dlvl for pick + enchant
    lda zp_player_dlvl
    pha                         // Save real dlvl
    lda isl_treasure_dlvl
    sta zp_player_dlvl

#if ITEM_SPAWN_PICKER_SEPARATE
    jsr tramp_pick_item_type_spawn
#elif ITEM_SPAWN_IN_GEN_OVERLAY || (ITEM_SPAWN_EXTERNAL && PLATFORM_PRODUCT_OVERLAY_RUNTIME)
    jsr pick_item_type_overlay
#else
    jsr pick_item_type
#endif
    jsr isl_roll_item           // id, enchantment, ego

    pla                         // Restore real dlvl
    sta zp_player_dlvl

    lda #1
    sta fi_add_qty

    jsr floor_item_add          // a full table skips it

!isl_treasure_skip:
    inc isl_target
    jmp !isl_treasure_loop-

!isl_all_done:
    rts

// isl_roll_item — A = the item type picked: store it, roll its enchantment
// (roll_enchantment also sets the fi_add_* stat fields and flags) and its ego
// type (0 for non-weapons).
isl_roll_item:
    sta fi_add_id
    lda item_cur_page
    sta isl_page
    jsr roll_enchantment
    sta fi_add_p1
    lda isl_page
    sta item_cur_page
    lda fi_add_id
#if HAL_PLATFORM_CHEST_LOOT_EGO_GEN_TRAMP
    // A2/CX16: generation executes in the GEN overlay window; the ego trampoline
    // must restore it or the item_spawn_level continuation runs OVL.ITEMS.
    jsr tramp_roll_ego_type_gen
#elif HAL_PLATFORM_CHEST_LOOT_EGO_MODAL_TRAMP || ITEM_SPAWN_EGO_MODAL_TRAMP
    jsr tramp_roll_ego_type_modal
#else
    jsr tramp_roll_ego_type
#endif
    ora isl_page
    sta fi_add_ego
    rts
isl_page: .byte 0
