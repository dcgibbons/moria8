#importonce
#import "df_target_dir.s"
#import "df_target_row.s"
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

#import "eff_heal.s"

// ============================================================
// eff_light_room — Light the room the player is in (and hurt CD_LIGHT monsters)
// Input: none (reads zp_player_x/y, room_* arrays)
// Output: room lit, vis_room_revealed set; CD_LIGHT monsters in lit box take 2d8
// Clobbers: A, X, Y
// ============================================================
#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
elr_min_x:   .byte 0
elr_w:       .byte 0
elr_min_y:   .byte 0
elr_h:       .byte 0
elr_mon_idx: .byte 0

eff_light_room:
    ldx #0
!elr_loop:
    cpx room_count
    bcs !elr_corridor+              // Player not in any room
    ldy room_x,x
    dey
    sty elr_min_x
    lda room_w,x
    clc
    adc #2
    sta elr_w
    lda zp_player_x
    sec
    sbc elr_min_x
    cmp elr_w
    bcs !elr_next+
    ldy room_y,x
    dey
    sty elr_min_y
    lda room_h,x
    clc
    adc #2
    sta elr_h
    lda zp_player_y
    sec
    sbc elr_min_y
    cmp elr_h
    bcs !elr_next+
    jsr light_room_x
    jmp !elr_hurt_light+
!elr_next:
    inx
    bne !elr_loop-

!elr_corridor:
    lda #1
    sta vis_room_revealed
    ldx zp_player_x
    dex
    stx elr_min_x
    ldx zp_player_y
    dex
    stx elr_min_y
    lda #3
    sta elr_w
    sta elr_h

!elr_hurt_light:
    ldx #MAX_MONSTERS - 1
    stx elr_mon_idx
!elr_mon_loop:
    ldx elr_mon_idx
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !elr_mon_next+
    sta cmb_type
    tay
    lda cr_cdefense,y
    and #CD_LIGHT
    beq !elr_mon_next+
    ldy #MX_X
    lda (zp_ptr0),y
    sec
    sbc elr_min_x
    cmp elr_w
    bcs !elr_mon_next+
    ldy #MX_Y
    lda (zp_ptr0),y
    sec
    sbc elr_min_y
    cmp elr_h
    bcs !elr_mon_next+
    lda #2
    ldx #8
    ldy #0
    jsr math_dice                   // VMS light_room / light_line: 2d8
    ldx elr_mon_idx
    stx cmb_slot
    jsr combat_apply_damage_16
    ldx elr_mon_idx
    bcc !elr_mon_wake+
    jsr combat_kill_message
    jmp !elr_mon_next+
!elr_mon_wake:
    jsr monster_wake
    inc zp_dirty_count
!elr_mon_next:
    dec elr_mon_idx
    bpl !elr_mon_loop-
    rts
#else
eff_light_room:
    ldx #0
!elr_loop:
    cpx room_count
    bcs !elr_corridor+              // Player not in any room
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
    jmp light_room_x
!elr_next:
    inx
    jmp !elr_loop-
!elr_corridor:
    lda #1
    sta vis_room_revealed
    rts
#endif

// ============================================================
// eff_phase_door — Phase Door: VMS Moria teleport(10) (moria.inc; Umoria
// playerTeleport(10)): a random square pulled within distance 10.
// eff_teleport_self — Teleport player to random floor tile (no limit)
// Input: none (reads zp_player_x/y)
// Output: player moved, vis_room_revealed set
// Clobbers: A, X, Y, zp_ptr0, zp_temp0-4
// ============================================================
eff_phase_door:
    lda #10
    .byte $2c                       // BIT abs: skip the lda #0 below
eff_teleport_self:
    lda #0                          // No distance limit
    jsr find_random_floor_near
    bcc !ets_fail+
    lda df_target_x
    ldy df_target_y

// eff_teleport_apply_target — Move player to (A, Y)
// Input: A = destination x, Y = destination y (also monster Teleport To)
// Output: player moved, vis_room_revealed set. FLAG_OCCUPIED marks creatures
//         only (dungeon_data.s): the player's tiles are left as they are, as
//         for a step or trap_teleport; setting it here left a stale creature
//         flag wherever the player landed (M5b playtest round 12).
// Clobbers: A
// ============================================================
eff_teleport_apply_target:
    // Move player
    sta zp_player_x
    sty zp_player_y
    jsr player_search_mode_off

    // Trigger full visibility update and redraw
    lda #1
    sta vis_room_revealed
!ets_fail:
    rts

#if HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED)
eff_move_caster_to_target:
    ldx zp_mon_y
    ldy zp_mon_x
    jsr !emct_occ+
    ldx df_target_y
    stx zp_mon_y
    ldy df_target_x
    sty zp_mon_x
    jsr !emct_occ+
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda zp_mon_x
    sta (zp_ptr0),y
    iny
    lda zp_mon_y
    sta (zp_ptr0),y
    inc zp_dirty_count
    rts
!emct_occ:
    jsr map_row_ptr0_x
    :MapRead_ptr0_y()
    eor #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    rts
#endif

#if SPELL_EFFECTS_INCLUDE_IDENTIFY
#if !EFF_IDENTIFY_PROMPT_EXTERNAL
#import "eff_identify_prompt_cold.s"
#endif

// Resident scroll-identify completion path. item_read_scroll dispatches here
// with a tail jump so nested inventory/help overlays do not have to return to
// item-overlay code after eff_identify_prompt finishes.
eff_identify_scroll_resident:
#if EFF_IDENTIFY_PROMPT_EXTERNAL
    jsr tramp_eff_identify_scroll_resident
#else
    jsr eff_identify_prompt
#endif
    sec
    rts
#else
eff_identify_prompt:
eff_identify_scroll_resident:
    rts
#endif

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

eff_detect_timer: .byte 0
eff_detect_evil_mode: .byte 0

eff_detect_monsters:
    lda #0
    sta eff_detect_evil_mode
    lda #DETECT_TIMER_TURNS
    sta eff_detect_timer
    lda #1
    sta vis_room_revealed
    rts

#if HAL_PLATFORM_DETECT_EVIL_RESIDENT_ITEMS && FULL_DETECT_EVIL_EFFECT
:ResidentItemsSegment()
#endif
#if !HAL_PLATFORM_DETECT_EVIL_RESIDENT_ITEMS || FULL_DETECT_EVIL_EFFECT
#import "player_magic_detect_evil_effect.s"
#endif
#if HAL_PLATFORM_DETECT_EVIL_RESIDENT_ITEMS && FULL_DETECT_EVIL_EFFECT
:ResidentWorldSegment()
#endif

// ============================================================
// eff_remove_curse — Clear IF_CURSED on all equipped items
// Input: none
// Output: IF_CURSED cleared from all equipment slots
// Clobbers: A, X
// ============================================================
eff_remove_curse:
    ldx #EQUIP_WEAPON               // Equipment starts at slot 22
!erc_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !erc_next+
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
!erc_next:
    inx
    cpx #TOTAL_INV_SLOTS
    bcc !erc_loop-
    rts

// ============================================================
// eff_find_traps / eff_destroy_traps_doors live in
// spell_effects_overlay.s (imported next to this file on platforms with
// resident headroom; Apple IIe places them in the spell overlay).
// ============================================================

// ============================================================
// eff_find_doors — Reveal all secret doors on the map
// Converts TILE_SECRET to TILE_DOOR_CLOSED.
// Clobbers: A, X, Y, zp_ptr0
// C128 keeps its own copy in the resident items payload (the world payload
// funds chest search/trap discovery). Apple IIe keeps its copy in the spell
// overlay (the resident image funds chest gameplay there).
// ============================================================
#if !EFF_FIND_DOORS_EXTERNAL
#define EFF_DOORS_TRAPS_EMIT_DOORS_ONLY
#import "eff_doors_traps_cold.s"
#undef EFF_DOORS_TRAPS_EMIT_DOORS_ONLY
#endif

// adj_dir_idx — direction counter for spell_effects_overlay.s's adjacent
// scans. for_each_adjacent and eff_sleep_adjacent, which nothing called (the
// Sleep prayers and spells run pmx_sleep_adjacent_msg, with VMS's saving
// throw), went on 2026-11-11 to fund the VMS wands.
adj_dir_idx:  .byte 0       // Direction counter 0-7

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

    jsr eff_bolt_dir_trace_init
    bcs !eb_trace+
    rts

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

#if HAL_SCREEN_SPELL_BOLT_FLASH_SETS_COLOR
    lda #COL_CYAN
    jsr screen_flash_set_color
#endif
    jsr screen_flash_at             // Flash '*' white, restore after delay
#if HAL_SCREEN_SPELL_BOLT_FLASH_SETS_COLOR
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
#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    lda eff_bolt_sides
    cmp #8
    bne !eb_no_elem+
    ldy eff_bolt_dice
    cpy #3
    bcc !eb_no_elem+
    cpy #7
    bcs !eb_no_elem+
    lda eff_bolt_typ_tbl - 3,y  // 3->Light(1), 4->Frost(4), 5->Acid(3), 6->Fire(5)
    ldx cmb_type
    jsr eff_scale_elem_damage
!eb_no_elem:
#endif

    // Apply damage to monster
eff_bolt_apply_damage:
    ldx zp_temp2
    jsr combat_apply_damage_16
    bcc !eb_alive+              // Still alive

    // Monster killed — award XP, remove, message
    ldx zp_temp2
    jmp combat_kill_message     // X = killed monster slot

!eb_alive:
eff_bolt_alive:
    jsr eff_bolt_wake_hit_msg
    lda #SFX_HIT
    jmp hal_sound_play

eff_bolt_wake_hit_msg:
    // Wake the monster and print "YOUR SPELL HITS THE <name>."
    ldx zp_temp2
    jsr monster_wake
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_EB_SPELL_HITS
    jmp projectile_msg_suffix

#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
// eff_scale_elem_damage — VMS spells.inc get_flags/fire_bolt/fire_ball:
// *2 when (cr_cdefense[X] & harm_type) != 0, else /4 if creature X breathes
// element A (or MS_BREATH_ALL).
eff_scale_elem_damage:
    tay
    beq !esed_done+
    sty zp_temp0
    lda eff_elem_harm_tbl - 1,y
    and cr_cdefense,x
    beq !esed_chk_res+
    asl zp_math_a
    rol zp_math_b
    rts
!esed_chk_res:
    lda cr_spell_flags,x
    and #MSF_BREATH
    beq !esed_done+
    lda cr_spell_chance,x
    lsr
    lsr
    lsr
    lsr
    and #7
    cmp #MS_BREATH_ALL
    beq !esed_div4+
    cmp zp_temp0
    bne !esed_done+
!esed_div4:
    lsr zp_math_b
    ror zp_math_a
    lsr zp_math_b
    ror zp_math_a
!esed_done:
    rts

eff_bolt_typ_tbl:
    .byte 1, 4, 3, 5            // 3d8 Light, 4d8 Frost, 5d8 Acid, 6d8 Fire
eff_elem_harm_tbl:
    .byte CD_LIGHT, CD_POISON, CD_ACID, CD_FROST, CD_FIRE
#endif

// ============================================================
// eff_directional_monster — Get direction, trace until the first monster hit
// Output: carry SET = monster found (X = slot index),
//         carry CLEAR = no monster along the traced path
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
eff_bolt_dir_trace_init:
    jsr get_direction_target
    bcc !edm_fail+
eff_trace_init_from_dir:
    jsr calc_direction_index
    bcc !edm_fail+
    lda zp_player_x
    sta proj_cx
    lda zp_player_y
    sta proj_cy
    lda #20
    sta proj_steps
    sec
    rts

eff_directional_monster:
    jsr eff_bolt_dir_trace_init
    bcc !edm_fail+
    bcs !edm_trace+
eff_trace_monster_from_dir:
    jsr eff_trace_init_from_dir
    bcc !edm_fail+
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
// eff_destroy_traps_doors — moved to spell_effects_overlay.s (see note at
// the top of this file).
// ============================================================

// Stone-to-Mud's code: a port whose only callers of it (the spell table and
// the Phase 3 wand dispatch) share an overlay may place it there with
// :WallToMudSegment()/:WallToMudRestoreSegment() (the Atari: OVL.SPELL).
#if !WALL_TO_MUD_SEGMENT_CUSTOM
.macro WallToMudSegment() {}
.macro WallToMudRestoreSegment() {}
#endif
:WallToMudSegment()
// ============================================================
// eff_wall_to_mud — Turn a wall tile to floor in chosen direction
// Must call get_direction_target first.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
.assert "Wall-to-Mud contiguous wall tiles", TILE_WALL_H == $10 && TILE_WALL_V == $20 && TILE_CORNER_TL == $30 && TILE_CORNER_TR == $40 && TILE_CORNER_BL == $50 && TILE_CORNER_BR == $60 && TILE_DOOR_OPEN == $70, true
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

    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    sta ewtm_save_tile          // Save full tile for treasure/occupant check
    and #TILE_TYPE_MASK

    // Check all tunnelable types: $10..$60 walls/corners, plus veins & secret
    cmp #TILE_WALL_H
    bcc !ewtm_not_wall+
    cmp #TILE_DOOR_OPEN
    bcc !ewtm_dig+
    cmp #TILE_MAGMA
    beq !ewtm_dig+
    cmp #TILE_QUARTZ
    beq !ewtm_dig+
    cmp #TILE_SECRET
    beq !ewtm_dig+
!ewtm_not_wall:
#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    // Not an adjacent wall — trace ray for a CD_STONE creature (VMS wall_to_mud)
    jsr eff_trace_monster_from_dir
    bcc !ewtm_fail+
    jmp ewrs_stone_mon
#endif
!ewtm_fail:
    rts

!ewtm_dig:
    // Replace with floor + visited/lit while preserving any FLAG_OCCUPIED bit
    lda ewtm_save_tile
    and #FLAG_OCCUPIED
    ora #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
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
#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
    jmp ewrs_dug_stone
#else
    rts
#endif

ewtm_save_tile: .byte 0
#if HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
:WallToMudRestoreSegment()
#endif

#if (!C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED) && (PLACE_SECRETS_EXTERNAL || PLACE_SECRETS_EMITTED) && !C64_TEST_FULL_ITEMDESC_STUB
ewrs_dug_stone:
    lda df_target_x
    ldy df_target_y
    jsr monster_find_at
    bcc !ewrs_done+
ewrs_stone_mon:
    stx zp_temp2
    stx cmb_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    tay
    lda cr_cdefense,y
    and #CD_STONE
    beq !ewrs_done+
    lda #100                        // VMS spells.inc wall_to_mud: mon_take_hit(cptr, 100)
    sta zp_math_a
    lda #0
    sta zp_math_b
    inc zp_dirty_count
    jmp eff_bolt_apply_damage
!ewrs_done:
    rts
#endif

#if !HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
:WallToMudRestoreSegment()
#endif

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
    jmp combat_note_kill
