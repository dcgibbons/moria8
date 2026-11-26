#importonce
#import "monster_polymorph.s"
// eff_item_p1.s — Extended Scroll, Wand, and Staff effect dispatcher & handlers
//
// Imported into HomeOverlay on ports that define HAL_PLATFORM_EFF_ITEM_P1_EXTERNAL
// (reached via tramp_eff_item_p1 from scroll_effects_p3.s), or directly into
// scroll_effects_p3.s otherwise. Calls ONLY resident core helpers so overlay
// swaps never evict the running handler (Staff of Earthquakes is routed
// before entering eff_item_p1_exec inside scroll_effects_p3.s).
//
// Zero new ZP variables, zero new Huffman strings.

ep1_arg:  .byte 0
ep1_cnt:  .byte 0
ep1_idx:  .byte 0
ep1_slot: .byte 0
ep1_x:    .byte 0
ep1_y:    .byte 0
ep1_tmp:  .byte 0

// eff_item_p1_exec — Entry point reading piw_item_id (slot_lo on Page 0: 95..185).
// Preserves no registers; sets vis_room_revealed/zp_dirty_count as needed.
eff_item_p1_exec:
    lda piw_item_id

// ep1_run_slot — Dispatch Page 0 scroll/wand/staff slot_lo in A (52 handlers).
.assert "All eff_item_p1 scrolls, wands, and staves live on Page 0", ITEM_PAGE_SCROLL_OF_ENCHANT_WEAPON_TO_HIT == 0 && ITEM_PAGE_STAFF_OF_DARKNESS_L5 == 0, true
ep1_run_slot:
    ldx #51
!ep1_scan:
    cmp ep1_slot_ids,x
    beq !ep1_jump+
    dex
    bpl !ep1_scan-
    rts
!ep1_jump:
    lda ep1_tbl_lo,x
    sta zp_ptr1
    lda ep1_tbl_hi,x
    sta zp_ptr1_hi
    jmp (zp_ptr1)

ep1_slot_ids:
    .byte ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_HIT, ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_DAM, ITEM_SLOT_SCROLL_OF_SUMMON_MONSTER
    .byte ITEM_SLOT_SCROLL_OF_SLEEP_MONSTER, ITEM_SLOT_SCROLL_OF_TREASURE_DETECTION, ITEM_SLOT_SCROLL_OF_TRAP_DETECTION_L5
    .byte ITEM_SLOT_SCROLL_OF_TRAP_DETECTION_L12, ITEM_SLOT_SCROLL_OF_DOOR_STAIR_LOCATION_L5, ITEM_SLOT_SCROLL_OF_DOOR_STAIR_LOCATION_L15
    .byte ITEM_SLOT_SCROLL_OF_DETECT_INVISIBLE, ITEM_SLOT_SCROLL_OF_TRAP_CREATION, ITEM_SLOT_SCROLL_OF_TRAP_DOOR_DESTRUCTION
    .byte ITEM_SLOT_SCROLL_OF_DOOR_CREATION, ITEM_SLOT_SCROLL_OF_DARKNESS, ITEM_SLOT_SCROLL_OF_CREATE_FOOD
    .byte ITEM_SLOT_SCROLL_OF_DISPEL_UNDEAD, ITEM_SLOT_SCROLL_OF_STAR_ENCHANT_WEAPON, ITEM_SLOT_SCROLL_OF_CURSE_WEAPON
    .byte ITEM_SLOT_SCROLL_OF_STAR_ENCHANT_ARMOR, ITEM_SLOT_SCROLL_OF_CURSE_ARMOR, ITEM_SLOT_SCROLL_OF_SUMMON_UNDEAD
    .byte ITEM_SLOT_SCROLL_OF_BLESSING, ITEM_SLOT_SCROLL_OF_HOLY_CHANT, ITEM_SLOT_SCROLL_OF_HOLY_PRAYER
    .byte ITEM_SLOT_WAND_OF_POLYMORPH, ITEM_SLOT_WAND_OF_HEAL_MONSTER, ITEM_SLOT_WAND_OF_HASTE_MONSTER
    .byte ITEM_SLOT_WAND_OF_CONFUSE_MONSTER, ITEM_SLOT_WAND_OF_SLEEP_MONSTER, ITEM_SLOT_WAND_OF_TRAP_DOOR_DESTRUCTION
    .byte ITEM_SLOT_WAND_OF_MAGIC_MISSILE, ITEM_SLOT_WAND_OF_WALL_BUILDING, ITEM_SLOT_WAND_OF_CLONE_MONSTER
    .byte ITEM_SLOT_WAND_OF_DISARMING, ITEM_SLOT_WAND_OF_WONDER, ITEM_SLOT_STAFF_OF_DOOR_STAIR_LOCATION
    .byte ITEM_SLOT_STAFF_OF_TRAP_LOCATION, ITEM_SLOT_STAFF_OF_TREASURE_LOCATION, ITEM_SLOT_STAFF_OF_OBJECT_LOCATION
    .byte ITEM_SLOT_STAFF_OF_SUMMONING_L10, ITEM_SLOT_STAFF_OF_SUMMONING_L50, ITEM_SLOT_STAFF_OF_STARLITE
    .byte ITEM_SLOT_STAFF_OF_HASTE_MONSTERS, ITEM_SLOT_STAFF_OF_SLOW_MONSTERS, ITEM_SLOT_STAFF_OF_SLEEP_MONSTERS
    .byte ITEM_SLOT_STAFF_OF_DETECT_INVISIBLE, ITEM_SLOT_STAFF_OF_SLOWNESS, ITEM_SLOT_STAFF_OF_MASS_POLYMORPH
    .byte ITEM_SLOT_STAFF_OF_DETECT_EVIL, ITEM_SLOT_STAFF_OF_CURING, ITEM_SLOT_STAFF_OF_DARKNESS_L50
    .byte ITEM_SLOT_STAFF_OF_DARKNESS_L5
ep1_tbl_lo:
    .byte <ep1_ench_wpn_hit, <ep1_ench_wpn_dam, <ep1_summon_one, <ep1_sleep_adj
    .byte <ep1_detect_treasure, <ep1_find_traps, <ep1_find_traps, <ep1_find_doors_stairs
    .byte <ep1_find_doors_stairs, <ep1_detect_invis, <ep1_create_traps, <ep1_destroy_td_area
    .byte <ep1_create_doors, <ep1_darkness, <ep1_create_food, <ep1_dispel_undead
    .byte <ep1_ench_wpn_star, <ep1_curse_weapon, <ep1_ench_arm_star, <ep1_curse_armor
    .byte <ep1_summon_undead, <ep1_blessing, <ep1_holy_chant, <ep1_holy_prayer
    .byte <ep1_wand_polymorph, <ep1_wand_heal, <ep1_wand_haste, <ep1_wand_confuse
    .byte <ep1_wand_sleep, <ep1_wand_td_destr, <ep1_wand_missile, <ep1_wand_wall
    .byte <ep1_wand_clone, <ep1_wand_disarm, <ep1_wand_wonder, <ep1_find_doors_stairs
    .byte <ep1_find_traps, <ep1_detect_treasure, <ep1_detect_objects, <ep1_summon_many
    .byte <ep1_summon_many, <ep1_starlite, <ep1_staff_haste, <ep1_staff_slow
    .byte <ep1_sleep_all, <ep1_detect_invis, <ep1_slowness, <ep1_mass_polymorph
    .byte <ep1_detect_evil, <ep1_curing, <ep1_darkness, <ep1_darkness
ep1_tbl_hi:
    .byte >ep1_ench_wpn_hit, >ep1_ench_wpn_dam, >ep1_summon_one, >ep1_sleep_adj
    .byte >ep1_detect_treasure, >ep1_find_traps, >ep1_find_traps, >ep1_find_doors_stairs
    .byte >ep1_find_doors_stairs, >ep1_detect_invis, >ep1_create_traps, >ep1_destroy_td_area
    .byte >ep1_create_doors, >ep1_darkness, >ep1_create_food, >ep1_dispel_undead
    .byte >ep1_ench_wpn_star, >ep1_curse_weapon, >ep1_ench_arm_star, >ep1_curse_armor
    .byte >ep1_summon_undead, >ep1_blessing, >ep1_holy_chant, >ep1_holy_prayer
    .byte >ep1_wand_polymorph, >ep1_wand_heal, >ep1_wand_haste, >ep1_wand_confuse
    .byte >ep1_wand_sleep, >ep1_wand_td_destr, >ep1_wand_missile, >ep1_wand_wall
    .byte >ep1_wand_clone, >ep1_wand_disarm, >ep1_wand_wonder, >ep1_find_doors_stairs
    .byte >ep1_find_traps, >ep1_detect_treasure, >ep1_detect_objects, >ep1_summon_many
    .byte >ep1_summon_many, >ep1_starlite, >ep1_staff_haste, >ep1_staff_slow
    .byte >ep1_sleep_all, >ep1_detect_invis, >ep1_slowness, >ep1_mass_polymorph
    .byte >ep1_detect_evil, >ep1_curing, >ep1_darkness, >ep1_darkness
.assert "ep1_slot_ids/lo/hi have 52 entries each", (ep1_tbl_lo - ep1_slot_ids == 52) && (ep1_tbl_hi - ep1_tbl_lo == 52) && (* - ep1_tbl_hi == 52), true

// ============================================================
// Detection: Treasure (Scroll of Treasure Detection, Staff of Treasure
// Location) & Objects (Staff of Object Location)
// ============================================================
ep1_detect_treasure:
    lda #1
    .byte $2c                       // BIT abs skips LDA #0
ep1_detect_objects:
    lda #0
    sta ep1_arg                     // 1 = gold only, 0 = all floor items
    ldx #0
!ep1_dfo_loop:
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !ep1_dfo_next+
    lda ep1_arg
    beq !ep1_dfo_mark+
    jsr item_get_category_floor_x
    cmp #ICAT_GOLD
    bne !ep1_dfo_next+
!ep1_dfo_mark:
    lda fi_y,x
    cmp #MAP_ROWS
    bcs !ep1_dfo_next+
    tay
    jsr map_row_ptr0_y
    lda fi_x,x
    cmp #MAP_COLS
    bcs !ep1_dfo_next+
    tay
    :MapRead_ptr0_y()
    ora #(FLAG_VISITED | FLAG_LIT)
    :MapWrite_ptr0_y()
    jsr ep1_set_revealed
!ep1_dfo_next:
    inx
    cpx #MAX_FLOOR_ITEMS
    bcc !ep1_dfo_loop-
    lda #<ep1_msg_objects
    ldy #>ep1_msg_objects
    ldx ep1_arg
    beq !ep1_dfo_msg+
    lda #<ep1_msg_treasure
    ldy #>ep1_msg_treasure
!ep1_dfo_msg:
    jmp msg_print_ay

ep1_msg_treasure:     .text "You sense treasure nearby." ; .byte 0
ep1_msg_objects:      .text "You sense objects nearby." ; .byte 0
ep1_msg_doors_stairs: .text "You sense doors and stairs." ; .byte 0

// ============================================================
// Detect Invisible (Scroll/Staff of Detect Invisible) & Create Food (Scroll)
// ============================================================
ep1_detect_invis:
    lda #24
    ldx #25
    ldy #zp_eff_see_inv
    jsr ep1_add_zp_y
    ldx #HSTR_PIQ_EYES_TINGLE
    jmp huff_print_msg

ep1_create_food:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !ep1_cf_free+
    jsr floor_item_remove
!ep1_cf_free:
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda #ITEM_SLOT_RATION_OF_FOOD   // Ration of Food (Page 0)
    sta fi_add_id
    jsr fi_add_clear_plain_meta
    lda #1
    sta fi_add_qty
    jsr floor_item_add
    bcc !ep1_cf_fail+
    jsr ep1_set_revealed
    ldx #HSTR_PMU_CREATE_FOOD
    jmp huff_print_msg
!ep1_cf_fail:
    rts

// ============================================================
// Scrolls of Blessing, Holy Chant, and Holy Prayer
// ============================================================
ep1_blessing:
    lda #6
    ldx #7
    bne !ep1_bless_add+
ep1_holy_chant:
    lda #12
    ldx #13
!ep1_bless_add:
    jsr ep1_add_bless
    ldx #HSTR_PIQ_HEROIC
    jmp huff_print_msg

ep1_holy_prayer:
    lda #24
    ldx #25
    jsr ep1_add_bless
    lda #0
    sta eff_fear_timer
    lda #4
    ldx #4
    ldy #0
    jsr math_dice
    lda zp_math_a
    jsr eff_heal
    lda #EFF_CURE_ALL
    jsr eff_cure_timers
    ldx #HSTR_PIQ_VERY_GOOD
    jmp huff_print_msg

ep1_add_bless:
    ldy #zp_eff_bless
ep1_add_zp_y:
    stx ep1_tmp
    jsr rng_range
    clc
    adc ep1_tmp
    clc
    adc $0000,y
    bcc !ep1_ba_store+
    lda #255
!ep1_ba_store:
    sta $0000,y
    rts
.assert "ep1_add_zp_y timers are zero-page", zp_eff_see_inv < $100 && zp_eff_bless < $100, true

// ============================================================
// Darkness (Scroll of Darkness, Staff of Darkness L5/L50)
// ============================================================
ep1_darkness:
    // Clear room light if in a room, otherwise 3x3 around player
    ldx #0
!ep1_dk_room:
    cpx room_count
    bcs !ep1_dk_corr+
    lda room_x,x
    sec
    sbc #1
    cmp zp_player_x
    beq !ep1_dk_x0+
    bcs !ep1_dk_rnext+
!ep1_dk_x0:
    lda room_x,x
    clc
    adc room_w,x
    cmp zp_player_x
    bcc !ep1_dk_rnext+
    lda room_y,x
    sec
    sbc #1
    cmp zp_player_y
    beq !ep1_dk_y0+
    bcs !ep1_dk_rnext+
!ep1_dk_y0:
    lda room_y,x
    clc
    adc room_h,x
    cmp zp_player_y
    bcc !ep1_dk_rnext+
    lda #0
    sta room_lit,x
    jsr vis_room_bounds_x
    jmp !ep1_dk_box+
!ep1_dk_rnext:
    inx
    bne !ep1_dk_room-
!ep1_dk_corr:
    ldx zp_player_x
    dex
    bne !ep1_dk_xmin+
    inx
!ep1_dk_xmin:
    stx vis_min_x
    lda zp_player_x
    clc
    adc #1
    cmp #MAP_COLS - 1
    bcc !ep1_dk_xmax+
    lda #MAP_COLS - 2
!ep1_dk_xmax:
    sta vis_max_x
    ldx zp_player_y
    dex
    bne !ep1_dk_ymin+
    inx
!ep1_dk_ymin:
    stx vis_min_y
    lda zp_player_y
    clc
    adc #1
    cmp #MAP_ROWS - 1
    bcc !ep1_dk_ymax+
    lda #MAP_ROWS - 2
!ep1_dk_ymax:
    sta vis_max_y
!ep1_dk_box:
    ldx vis_min_y
!ep1_dk_row:
    jsr map_row_ptr0_x
    ldy vis_min_x
!ep1_dk_col:
    :MapRead_ptr0_y()
    and #~FLAG_LIT & $ff
    :MapWrite_ptr0_y()
    cpy vis_max_x
    beq !ep1_dk_row_done+
    iny
    bne !ep1_dk_col-
!ep1_dk_row_done:
    cpx vis_max_y
    beq !ep1_dk_blind+
    inx
    bne !ep1_dk_row-
!ep1_dk_blind:
    jsr ep1_set_revealed
    inc zp_dirty_count
    lda zp_eff_blind
    bne !ep1_dk_done+
    lda #5
    jsr rng_range
    clc
    adc #2
    sta zp_eff_blind
    ldx #HSTR_PIQ_CANT_SEE
    jmp huff_print_msg
!ep1_dk_done:
    rts

// ============================================================
// Trap Detection (Scroll L5/L12, Staff of Trap Location) & Door/Stair
// Location (Scroll L5/L15, Staff of Door/Stair Location)
// ============================================================
ep1_find_traps:
    lda #0
    sta ep1_cnt
    ldx trap_count
    beq !ep1_ft_chests+
    lda #0
    sta ep1_idx
!ep1_ft_loop:
    ldx ep1_idx
    cpx trap_count
    bcs !ep1_ft_chests+
    lda trap_y,x
    cmp #MAP_ROWS
    bcs !ep1_ft_next+
    tay
    jsr map_row_ptr0_y
    lda trap_x,x
    cmp #MAP_COLS
    bcs !ep1_ft_next+
    tay
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #(TILE_TRAP | FLAG_VISITED | FLAG_LIT)
    :MapWrite_ptr0_y()
    inc ep1_cnt
!ep1_ft_next:
    inc ep1_idx
    bne !ep1_ft_loop-
!ep1_ft_chests:
    jsr chest_mark_found_all
    jsr ep1_set_revealed
    ldx #HSTR_DF_FOUND_TRAP
    lda ep1_cnt
    bne !ep1_ft_msg+
    ldx #HSTR_DF_FOUND_NOTHING
!ep1_ft_msg:
    jmp huff_print_msg

ep1_find_doors_stairs:
    jsr eff_find_doors
    lda #1
    sta ep1_y
!ep1_fds_row:
    ldx ep1_y
    cpx #MAP_ROWS - 1
    bcs !ep1_fds_done+
    jsr map_row_ptr0_x
    ldy #1
!ep1_fds_col:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !ep1_fds_mark+
    cmp #TILE_STAIRS_UP
    bne !ep1_fds_next+
!ep1_fds_mark:
    :MapRead_ptr0_y()
    ora #(FLAG_VISITED | FLAG_LIT)
    :MapWrite_ptr0_y()
!ep1_fds_next:
    iny
    cpy #MAP_COLS - 1
    bcc !ep1_fds_col-
    inc ep1_y
    bne !ep1_fds_row-
!ep1_fds_done:
    jsr ep1_set_revealed
    lda #<ep1_msg_doors_stairs
    ldy #>ep1_msg_doors_stairs
    jmp msg_print_ay

// ============================================================
// Trap Creation, Door Creation, Trap/Door Destruction (Scroll and Wand)
// ============================================================
ep1_create_traps:
    lda #0
    sta ep1_idx
!ep1_ct_loop:
    lda trap_count
    cmp #MAX_TRAPS
    bcs !ep1_ct_done+
    ldx ep1_idx
    cpx #9
    bcs !ep1_ct_done+
    jsr ep1_neighbor_xy             // X = 0..7, or 8 -> player center; C=0 if OOB
    bcc !ep1_ct_next+
    jsr ep1_read_xy
    and #TILE_TYPE_MASK | FLAG_OCCUPIED | FLAG_HAS_ITEM
    bne !ep1_ct_next+               // requires bare TILE_FLOOR (0) unoccupied/no item
    jsr ep1_trap_at_xy
    bcs !ep1_ct_next+               // already trapped
    lda #TRAP_TYPE_COUNT
    jsr rng_range
    ldx trap_count
    sta trap_type,x
    lda ep1_x
    sta trap_x,x
    lda ep1_y
    sta trap_y,x
    inc trap_count
!ep1_ct_next:
    inc ep1_idx
    bne !ep1_ct_loop-
!ep1_ct_done:
    ldx #HSTR_PIQ_AIR_CRACKLE
    jmp huff_print_msg

ep1_create_doors:
    lda #0
    sta ep1_idx
!ep1_cd_loop:
    ldx ep1_idx
    cpx #8                          // 8 adjacent squares only (exclude center)
    bcs !ep1_cd_done+
    jsr ep1_neighbor_xy
    bcc !ep1_cd_next+
    jsr ep1_read_xy
    and #(TILE_TYPE_MASK | FLAG_OCCUPIED)
    bne !ep1_cd_next+               // bare TILE_FLOOR only
    jsr ep1_find_floor_xy
    bcs !ep1_cd_next+
    jsr ep1_trap_at_xy
    bcs !ep1_cd_next+
    jsr ep1_read_xy
    and #TILE_FLAG_MASK
    ora #(TILE_DOOR_CLOSED | FLAG_VISITED)
    :MapWrite_ptr0_y()
    jsr ep1_set_revealed
!ep1_cd_next:
    inc ep1_idx
    bne !ep1_cd_loop-
!ep1_cd_done:
    rts

ep1_destroy_td_area:
    // 5x5 centered at player (x, y clamped within [1..MAP_COLS-2, 1..MAP_ROWS-2])
    lda zp_player_y
    cmp #3
    bcs !ep1_dy_sub+
    lda #1
    bne !ep1_dy0+
!ep1_dy_sub:
    sbc #2                          // C=1: y - 2 >= 1
!ep1_dy0:
    sta ep1_y
    lda zp_player_y
    clc
    adc #2
    cmp #MAP_ROWS - 1
    bcc !ep1_dy1+
    lda #MAP_ROWS - 2
!ep1_dy1:
    sta ep1_cnt                     // y end inclusive
!ep1_dt_y:
    lda zp_player_x
    cmp #3
    bcs !ep1_dx_sub+
    lda #1
    bne !ep1_dx0+
!ep1_dx_sub:
    sbc #2
!ep1_dx0:
    sta ep1_x
    lda zp_player_x
    clc
    adc #2
    cmp #MAP_COLS - 1
    bcc !ep1_dx1+
    lda #MAP_COLS - 2
!ep1_dx1:
    sta ep1_arg                     // x end inclusive
!ep1_dt_x:
    jsr ep1_clear_tile_td
    lda ep1_x
    cmp ep1_arg
    bcs !ep1_dt_ynext+
    inc ep1_x
    bne !ep1_dt_x-
!ep1_dt_ynext:
    lda ep1_y
    cmp ep1_cnt
    bcs !ep1_dt_done+
    inc ep1_y
    bne !ep1_dt_y-
!ep1_dt_done:
    jmp ep1_set_revealed

// Clear traps, chest traps, and closed/secret doors at (ep1_x, ep1_y).
// Clobbers: A, X, Y, zp_ptr0
ep1_clear_tile_td:
    jsr ep1_disarm_tile
    jsr ep1_read_xy
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !ep1_cttd_door+
    cmp #TILE_SECRET
    bne !ep1_cttd_done+
!ep1_cttd_door:
    jsr ep1_floor_visited_reveal
    lda ep1_x
    ldy ep1_y
    jmp door_state_clear_at
!ep1_cttd_done:
    rts

ep1_trap_at_xy:
    lda ep1_x
    sta df_target_x
    lda ep1_y
    sta df_target_y
    jmp trap_find_at_target

ep1_find_floor_xy:
    lda ep1_x
    ldy ep1_y
    jmp floor_item_find_at

ep1_floor_visited_reveal:
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK             // TILE_FLOOR == 0
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
ep1_set_revealed:
    lda #1
    sta vis_room_revealed
    rts

// Disarm floor trap & floor chest trap at (ep1_x, ep1_y).
ep1_disarm_tile:
    jsr ep1_trap_at_xy
    bcc !ep1_dt_chk_map+
    jsr trap_remove_at_index
!ep1_dt_chk_map:
    jsr ep1_read_xy
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !ep1_dt_chk_chest+
    jsr ep1_floor_visited_reveal
!ep1_dt_chk_chest:
    jsr ep1_find_floor_xy
    bcc !ep1_dt_ret+
    jsr item_get_category_floor_x
    cmp #ICAT_CHEST
    bne !ep1_dt_ret+
    lda fi_p1,x
    and #~(CHEST_P1_TRAP_MASK | CHEST_P1_LOCKED) & $ff
    sta fi_p1,x
!ep1_dt_ret:
    rts

// ============================================================
// Weapon & Armor Enchantment / Curses (Enchant Weapon To-Hit/To-Dam,
// *Enchant Weapon*, *Enchant Armor*, Curse Weapon, Curse Armor scrolls)
// ============================================================
ep1_ench_wpn_hit:
    lda #1
    .byte $2c
ep1_ench_wpn_dam:
    lda #2
    .byte $2c
ep1_ench_wpn_star:
    lda #3
    sta ep1_arg                     // bit0 = to_hit, bit1 = to_dam, ==3 = *Ench*
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq ep1_no_gear
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
    lda ep1_arg
    cmp #3
    beq !ep1_ew_star+
    lda #1
    bne !ep1_ew_cnt+
!ep1_ew_star:
    lda #2
    jsr ep1_rng_1_to_a
!ep1_ew_cnt:
    sta ep1_cnt
!ep1_ew_loop:
    lda ep1_arg
    and #1
    beq !ep1_ew_do_dam+
    lda inv_to_hit + EQUIP_WEAPON
    jsr ep1_enchant_try
    bcc !ep1_ew_do_dam+
    inc inv_to_hit + EQUIP_WEAPON
!ep1_ew_do_dam:
    lda ep1_arg
    and #2
    beq !ep1_ew_next+
    lda inv_to_dam + EQUIP_WEAPON
    jsr ep1_enchant_try
    bcc !ep1_ew_next+
    inc inv_to_dam + EQUIP_WEAPON
!ep1_ew_next:
    dec ep1_cnt
    bne !ep1_ew_loop-
#if C64_TEST_SCRIPTED_SCROLL_SELECTOR
    lda #8
    sta c64_test_scroll_selector_return_pending
#endif
    ldx #HSTR_PIQ_WPN_GLOW
    bne !ep1_recalc_msg+

ep1_no_gear:
    ldx #HSTR_PIQ_VIBRATION
    jmp huff_print_msg

ep1_curse_weapon:
    ldx #EQUIP_WEAPON
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq ep1_no_gear
    jsr ep1_curse_slot_common
    jsr ep1_neg_1_to_5
    sta inv_to_hit + EQUIP_WEAPON
    jsr ep1_neg_1_to_5
    sta inv_to_dam + EQUIP_WEAPON
!ep1_curse_finish:
    ldx #HSTR_PIQ_HUMMING
!ep1_recalc_msg:
#if HAL_PLATFORM_CHARGEN_ITEM_RECALC_TRAMPOLINE
    lda #1
    sta piw_recalc_pending
#else
    stx ep1_tmp
    jsr player_recalc_equipment
    ldx ep1_tmp
#endif
    jmp huff_print_msg

ep1_curse_armor:
    jsr ep1_pick_armor_slot         // X = slot (C=0 if none worn)
    bcc ep1_no_gear
    stx ep1_slot
    jsr ep1_curse_slot_common
    jsr ep1_neg_1_to_5
    ldx ep1_slot
    sta inv_to_ac,x
    jmp !ep1_curse_finish-

ep1_ench_arm_star:
    jsr ep1_pick_armor_cursed_or_rand
    bcc ep1_no_gear
    stx ep1_slot
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
    lda #2
    jsr ep1_rng_1_to_a
    sta ep1_cnt
!ep1_eas_loop:
    ldx ep1_slot
    lda inv_to_ac,x
    jsr ep1_enchant_try
    bcc !ep1_eas_next+
    ldx ep1_slot
    inc inv_to_ac,x
!ep1_eas_next:
    dec ep1_cnt
    bne !ep1_eas_loop-
    ldx #HSTR_PIQ_ARM_GLOW
    bne !ep1_recalc_msg-

// C=1 if signed bonus in A (< 15) succeeds enchantment roll.
ep1_enchant_try:
    bmi !ep1_et_yes+
    cmp #15
    bcs !ep1_et_no+
    cmp #10
    bcc !ep1_et_roll+
    sta ep1_tmp
    lda #20
    jsr rng_range
    beq !ep1_et_yes+
!ep1_et_no:
    clc
    rts
!ep1_et_roll:
    sta ep1_tmp
    lda #10
    jsr rng_range
    cmp ep1_tmp
    bcs !ep1_et_yes+
    clc
    rts
!ep1_et_yes:
    sec
    rts

ep1_curse_slot_common:
    lda inv_flags,x
    ora #IF_CURSED
    sta inv_flags,x
#if CORE_ITEM_IMPORTED
    cpx #EQUIP_WEAPON
    bne !ep1_csc_strip+
    jsr item_get_category_inv_x     // preserves X
    cmp #ICAT_DIGGING
    beq !ep1_csc_done+
!ep1_csc_strip:
#endif
#if CORE_PLAYER_IMPORTED
    lda inv_p1,x
    beq !ep1_csc_clr+
    eor #$ff
    clc
    adc #1                          // A = -inv_p1,x
    sta stat_work
    jsr equip_stat_mask_x           // A = 6-bit stat mask, preserves X
    beq !ep1_csc_clr+
    ldy #0
!ep1_csc_stat_lp:
    lsr
    bcc !ep1_csc_stat_nx+
    pha
    lda stat_work
    jsr player_step_equip_stat_y    // preserves X, Y
    cpy #PL_CON_CUR - PL_STR_CUR
    bne !ep1_csc_stat_pop+
    stx ep1_tmp
    jsr player_calc_hp
    ldx ep1_tmp
    ldy #PL_CON_CUR - PL_STR_CUR
!ep1_csc_stat_pop:
    pla
!ep1_csc_stat_nx:
    iny
    cmp #0
    bne !ep1_csc_stat_lp-
!ep1_csc_clr:
#endif
    lda #0
    sta inv_p1,x
    sta inv_to_hit,x
    sta inv_to_dam,x
    lda inv_ego,x
    and #ITEM_PAGE_BIT              // clear ego while preserving Page 1 flag
    sta inv_ego,x
#if CORE_ITEM_IMPORTED
    jmp inven_recalc_weight
#endif
!ep1_csc_done:
    rts

ep1_rng_1_to_a:
    jsr rng_range
    clc
    adc #1
    rts

ep1_neg_1_to_5:
    lda #5
    jsr rng_range
    eor #$ff                        // ~(0..4) == -1..-5
    rts

ep1_armor_slots:
    .byte EQUIP_BODY, EQUIP_SHIELD, EQUIP_HEAD, EQUIP_HANDS, EQUIP_FEET, EQUIP_CLOAK

ep1_pick_armor_slot:
    lda #0
    .byte $2c
ep1_pick_armor_cursed_or_rand:
    lda #1
    sta ep1_tmp                     // 1 = prefer cursed first, 0 = random
    lda #$ff
    sta ep1_slot
    lda #0
    sta ep1_cnt
    tay
!ep1_pa_scan:
    ldx ep1_armor_slots,y
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ep1_pa_snext+
    inc ep1_cnt
    lda ep1_tmp
    beq !ep1_pa_snext+
    lda ep1_slot
    bpl !ep1_pa_snext+
    lda inv_flags,x
    and #IF_CURSED
    beq !ep1_pa_snext+
    stx ep1_slot
!ep1_pa_snext:
    iny
    cpy #6
    bcc !ep1_pa_scan-
    lda ep1_cnt
    bne !ep1_pa_have+
    clc
    rts
!ep1_pa_have:
    ldx ep1_slot
    bpl !ep1_pa_ok+
    jsr rng_range                   // A = ep1_cnt
    sta ep1_idx
    ldy #0
!ep1_pa_pick:
    ldx ep1_armor_slots,y
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ep1_pa_pnext+
    lda ep1_idx
    beq !ep1_pa_ok+
    dec ep1_idx
!ep1_pa_pnext:
    iny
    bpl !ep1_pa_pick-
!ep1_pa_ok:
    sec
    rts

// ============================================================
// Summoning (Scroll of Summon Monster/Undead, Staff of Summoning L10/L50)
// & Dispel Undead (Scroll)
// ============================================================
// VMS scrolls.inc 7 and 36, staffs.inc 8: randint(3) summon_monster, randint(3)
// summon_undead, randint(4) summon_monster at the player's square, awake;
// in town too (summon_monster then picks townspeople).
ep1_summon_many:                    // Staff of Summoning: randint(4)
    lda #4
    ldx #0
    beq !ep1_sum_roll+
ep1_summon_undead:                  // Scroll of Summon Undead: randint(3)
    ldx #CF_UNDEAD
    .byte $2c                       // BIT abs: skip ldx #0
ep1_summon_one:                     // Scroll of Summon Monster: randint(3)
    ldx #0
    lda #3
!ep1_sum_roll:
    stx ep1_arg
    jsr ep1_rng_1_to_a
    sta ep1_cnt
    jsr tier_check_transition
    lda zp_player_x
    sta fae_cx
    lda zp_player_y
    sta fae_cy
!ep1_sum_loop:
    jsr find_adjacent_empty
    bcc !ep1_sum_done+
    lda ep1_arg
    bne !ep1_sum_undead_pick+
    jsr pick_summon_creature_type   // VMS summon_monster: dlvl + mon$summon_adj
    jmp !ep1_sum_spawn+
!ep1_sum_undead_pick:
    jsr pick_undead_creature_type   // VMS summon_undead: any undead
    bcc !ep1_sum_done+
!ep1_sum_spawn:
    jsr monster_spawn_awake
    inc zp_dirty_count
    dec ep1_cnt
    bne !ep1_sum_loop-
!ep1_sum_done:
    ldx #HSTR_PIQ_AIR_CRACKLE
    jmp huff_print_msg

// Load zp_ptr0 + A = MX_TYPE for ep1_idx (< MAX_MONSTERS).
// C=1, Z=1 when ep1_idx >= MAX_MONSTERS; C=0, Z=1 when EMPTY_SLOT;
// C=0, Z=0, A = MX_TYPE when active.
ep1_mon_visible:
    jsr ep1_mon_active
    beq !ep1_mv_ret+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
!ep1_mv_ret:
    rts

ep1_mon_active:
    ldx ep1_idx
    cpx #MAX_MONSTERS
    bcs !ep1_ma_zero+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !ep1_ma_empty+
    rts
!ep1_ma_empty:
    clc
!ep1_ma_zero:
    lda #0
    rts

ep1_dispel_undead:
    lda #0
    sta ep1_idx
!ep1_hvf_loop:
    jsr ep1_mon_active
    bcs !ep1_hvf_ret+
    beq !ep1_hvf_next+
    sta cmb_type
    tay
    lda cr_mflags,y
    and #CF_UNDEAD
    beq !ep1_hvf_next+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    beq !ep1_hvf_next+
    lda #60
    jsr ep1_rng_1_to_a
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx ep1_idx
    stx cmb_slot
    jsr combat_apply_damage_16
    bcs !ep1_hvf_kill+
    jsr combat_msg_monster_shudders
    jmp !ep1_hvf_next+
!ep1_hvf_kill:
    ldx ep1_idx
    jsr eff_kill_monster
    jsr combat_msg_monster_dissolves
    jsr combat_print_winner_message
!ep1_hvf_next:
    inc ep1_idx
    bne !ep1_hvf_loop-
!ep1_hvf_ret:
    rts

// Staff of Starlite: light room + 2d8 light damage to CD_LIGHT monsters
ep1_starlite:
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jmp huff_print_msg

// ============================================================
// Monster Sleep / Haste / Slow / Evil Detect / Slowness / Mass Poly
// ============================================================
ep1_sleep_adj:
    // Sleep adjacent monsters within Chebyshev dist <= 1
    lda #1
    .byte $2c
ep1_sleep_all:
    lda #0
    sta ep1_arg                     // 1 = adjacent only, 0 = all visible
    lda #0
    sta ep1_idx
!ep1_sa_loop:
    jsr ep1_mon_active
    bcs !ep1_sa_done+
    beq !ep1_sa_next+
    lda ep1_arg
    beq !ep1_sa_chk_vis+
    ldy #MX_X
    lda (zp_ptr0),y
    sec
    sbc zp_player_x
    jsr ep1_abs_a
    cmp #2
    bcs !ep1_sa_next+
    ldy #MX_Y
    lda (zp_ptr0),y
    sec
    sbc zp_player_y
    jsr ep1_abs_a
    cmp #2
    bcs !ep1_sa_next+
    bcc !ep1_sa_sleep+
!ep1_sa_chk_vis:
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    beq !ep1_sa_next+
!ep1_sa_sleep:
    ldx ep1_idx
    jsr ep1_sleep_slot
!ep1_sa_next:
    inc ep1_idx
    bne !ep1_sa_loop-
!ep1_sa_done:
    inc zp_dirty_count
    rts

ep1_sleep_slot:
    stx ep1_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tay
    lda cr_cdefense,y
    and #CD_NO_SLEEP
    bne !ep1_ss_immune+
    lda #20
    jsr rng_range
    clc
    adc #10
    ldx ep1_slot
    jmp monster_apply_sleep
!ep1_ss_immune:
    rts

ep1_staff_haste:
    lda #1
    .byte $2c
ep1_staff_slow:
    lda #0
    sta ep1_arg                     // 1 = haste visible, 0 = slow visible
    lda #0
    sta ep1_idx
!ep1_shs_loop:
    jsr ep1_mon_visible
    bcs !ep1_shs_done+
    beq !ep1_shs_next+
    ldx ep1_idx
    lda ep1_arg
    beq !ep1_shs_slow+
    jsr ep1_haste_slot
    jmp !ep1_shs_next+
!ep1_shs_slow:
    jsr ep1_slow_slot
!ep1_shs_next:
    inc ep1_idx
    bne !ep1_shs_loop-
!ep1_shs_done:
    rts

ep1_slow_slot:
    lda #$ff
    .byte $2c
ep1_haste_slot:
    lda #1
    pha
    jsr monster_get_ptr
    ldy #MX_SPEED_CNT
    pla
    clc
    adc (zp_ptr0),y
    cmp #3                          // cap at +2
    beq !ep1_hs_ret+
    cmp #$fd                        // cap at -2
    beq !ep1_hs_ret+
    sta (zp_ptr0),y
!ep1_hs_ret:
    rts

ep1_detect_evil:
    lda #0
    sta vis_room_revealed
    sta ep1_idx
!ep1_de_loop:
    jsr ep1_mon_active
    bcs !ep1_de_done+
    beq !ep1_de_next+
    tay
    lda cr_mflags,y
    and #CF_EVIL
    beq !ep1_de_next+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_DETECTED
    sta (zp_ptr0),y
    lda #1
    sta eff_detect_evil_mode
    sta vis_room_revealed
!ep1_de_next:
    inc ep1_idx
    bne !ep1_de_loop-
!ep1_de_done:
    ldx #HSTR_PIQ_SENSE
    lda vis_room_revealed
    bne !ep1_de_msg+
    ldx #HSTR_PIQ_NOTHING
!ep1_de_msg:
    jmp huff_print_msg

ep1_curing:
    lda #EFF_CURE_ALL
    jsr eff_cure_timers
    ldx #HSTR_PIQ_MIND_CLEAR
    jmp huff_print_msg

ep1_slowness:
    lda #16
    jsr rng_range
    clc
    adc #15
    sta ep1_tmp
    lda zp_eff_speed
    sec
    sbc ep1_tmp
    bvc !ep1_slow_ok+
    lda #$80                        // clamp at -128
!ep1_slow_ok:
    sta zp_eff_speed
    ldx #HSTR_PIQ_DIZZY
    jmp huff_print_msg

// Staff of Mass Polymorph: VMS staffs.inc 19 -> spells.inc mass_poly. Every
// creature nearer than max_sight (Chebyshev, as Moria8 measures monster
// distance), seen or not, except the win creatures, with no resistance roll.
ep1_mass_polymorph:
    jsr tier_check_transition
    lda #0
    sta ep1_idx
!ep1_mp_loop:
    jsr ep1_mon_active
    bcs !ep1_mp_done+
    beq !ep1_mp_next+
    tax
    lda cr_level,x
    cmp #MONS_LEVEL_MAX + 1
    bcs !ep1_mp_next+               // A win creature (VMS cdefense bit 31)
    ldy #MX_X
    lda (zp_ptr0),y
    sta zp_mon_x
    iny                             // MX_Y
    lda (zp_ptr0),y
    sta zp_mon_y
    jsr monster_distance_to_player
    cmp #MONS_MAX_SIGHT
    bcs !ep1_mp_next+               // VMS cdis < max_sight
    ldx ep1_idx
    jsr ep1_poly_slot               // The new creature takes this or a lower slot
!ep1_mp_next:
    inc ep1_idx
    bne !ep1_mp_loop-
!ep1_mp_done:
    rts

// ============================================================
// Wands (Wand of Polymorph .. Wand of Wonder in ep1_slot_ids)
// ============================================================
ep1_wand_missile:
    lda #2
    ldx #6
    ldy #0
    jmp eff_bolt

ep1_wand_heal:
    jsr eff_directional_monster
    bcc !ep1_wh_done+
    stx ep1_slot
    lda #4
    ldx #6
    ldy #0
    jsr math_dice                   // zp_math_a = 4d6 (4..24)
    ldx ep1_slot
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    clc
    adc zp_math_a
    sta (zp_ptr0),y
    iny                             // MX_HP_HI
    lda (zp_ptr0),y
    adc #0
    bpl !ep1_wh_hi_ok+
    lda #$7f
!ep1_wh_hi_ok:
    sta (zp_ptr0),y
!ep1_wh_done:
    rts

ep1_wand_haste:
    jsr eff_directional_monster
    bcc !ep1_wh_done-
    jmp ep1_haste_slot

ep1_wand_clone:
    jsr eff_directional_monster
    bcc !ep1_wh_done-
    stx ep1_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta ep1_arg                     // creature type
    tax
#if HAL_PLATFORM_MONSTER_CATALOG
    jsr catalog_slot_is_balrog
    beq !ep1_wh_done-
#else
    lda cr_level,x
    cmp #100
    bcs !ep1_wh_done-
#endif
    ldy #MX_X
    lda (zp_ptr0),y
    sta ep1_cnt                     // origin X
    ldy #MX_Y
    lda (zp_ptr0),y
    sta ep1_tmp                     // origin Y
    lda #0
    sta ep1_idx
!ep1_wc_dir:
    ldx ep1_idx
    cpx #8
    bcs !ep1_wh_done-
    lda ep1_cnt
    ldy ep1_tmp
    jsr ep1_add_dir_xy
    bcc !ep1_wc_next+
    jsr ep1_read_xy
    tay
    and #FLAG_OCCUPIED
    bne !ep1_wc_next+
    tya
    lsr
    lsr
    lsr
    lsr
    tax
    lda walkable_table,x
    beq !ep1_wc_next+
    lda ep1_x
    sta ms_spawn_x
    lda ep1_y
    sta ms_spawn_y
    lda ep1_arg
    jsr monster_spawn_awake         // VMS multiply_monster(.., false)
    inc zp_dirty_count
    rts
!ep1_wc_next:
    inc ep1_idx
    bne !ep1_wc_dir-

ep1_wand_confuse:
    jsr eff_directional_monster
    bcc !ep1_wcf_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tay
    lda cr_cdefense,y
    and #CD_NO_SLEEP
    bne !ep1_wcf_immune+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_CONFUSED
    sta (zp_ptr0),y
    lda #10
    jsr rng_range
    clc
    adc #10
    ldy #MX_CONFUSE
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
    jmp huff_print_msg
!ep1_wcf_immune:
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
!ep1_wcf_done:
    rts

ep1_wand_sleep:
    jsr eff_directional_monster
    bcc !ep1_wcf_done-
    jsr ep1_sleep_slot
    inc zp_dirty_count
    rts

// Wand of Polymorph: VMS wands.inc 6 -> spells.inc poly_monster.
ep1_wand_polymorph:
    jsr eff_directional_monster
    bcc !ep1_wp_done+
    stx ep1_slot
    jsr tier_check_transition
    ldx ep1_slot
    :PolymorphResist(ep1_slot, ep1_poly_unaffected)
// ep1_poly_slot — Slot X becomes an awake creature of any level (mass_poly).
ep1_poly_slot:
    :PolymorphReplace(ep1_slot)
ep1_poly_unaffected:
    lda #<ep1_unaffected_str
    ldy #>ep1_unaffected_str
    jmp combat_msg_monster_suffix
ep1_unaffected_str:
    .text " is unaffected." ; .byte 0
!ep1_wp_done:
!ep1_wb_done:
    rts

ep1_wand_disarm:
    lda #0
    .byte $2c
ep1_wand_td_destr:
    lda #1
    sta ep1_arg                     // 1 = destroy traps+doors, 0 = disarm traps
    jsr ep1_beam_start
    bcc !ep1_wb_done-
!ep1_wb_step:
    dec proj_steps
    beq !ep1_wb_done-
    jsr trace_step
    bcs !ep1_wb_open+
    // Blocked: if proj_cx/cy is in bounds and TD destr hits closed/secret door, break it & continue
    lda ep1_arg
    beq !ep1_wb_done-
    jsr ep1_proj_xy_chk
    bcc !ep1_wb_done-
    jsr ep1_read_xy
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !ep1_wb_break+
    cmp #TILE_SECRET
    bne !ep1_wb_done-
!ep1_wb_break:
    jsr ep1_clear_tile_td
    jmp !ep1_wb_step-
!ep1_wb_open:
    jsr ep1_proj_xy_chk
    lda ep1_arg
    bne !ep1_wb_break-
    jsr ep1_disarm_tile
    jmp !ep1_wb_step-

ep1_wand_wall:
    jsr ep1_beam_start
    bcc !ep1_ww_done+
!ep1_ww_step:
    dec proj_steps
    beq !ep1_ww_done+
    jsr trace_step
    bcc !ep1_ww_done+
    lda proj_cx
    ldy proj_cy
    jsr monster_find_at
    bcs !ep1_ww_done+
    lda proj_cx
    ldy proj_cy
    jsr floor_item_find_at
    bcs !ep1_ww_step-               // skip squares holding items
    jsr ep1_proj_xy_chk
    jsr ep1_disarm_tile
    jsr ep1_read_xy
    and #TILE_FLAG_MASK
    ora #(TILE_WALL_H | FLAG_VISITED)
    :MapWrite_ptr0_y()
    jsr ep1_set_revealed
    jmp !ep1_ww_step-
!ep1_ww_done:
    rts

ep1_wonder_slots:
    .byte ITEM_SLOT_WAND_OF_HEAL_MONSTER, ITEM_SLOT_WAND_OF_HASTE_MONSTER
    .byte ITEM_SLOT_WAND_OF_CLONE_MONSTER, ITEM_SLOT_WAND_OF_MAGIC_MISSILE
    .byte ITEM_SLOT_WAND_OF_CONFUSE_MONSTER, ITEM_SLOT_WAND_OF_SLEEP_MONSTER
    .byte ITEM_SLOT_WAND_OF_TRAP_DOOR_DESTRUCTION, ITEM_SLOT_WAND_OF_POLYMORPH
    .byte ITEM_SLOT_WAND_OF_DISARMING, ITEM_SLOT_WAND_OF_WALL_BUILDING
.assert "ep1_wonder_slots has 10 Page-0 wand entries", (* - ep1_wonder_slots == 10) && ITEM_PAGE_WAND_OF_HEAL_MONSTER == 0 && ITEM_PAGE_WAND_OF_WALL_BUILDING == 0, true

ep1_wand_wonder:
    lda #13
    jsr rng_range
    cmp #10
    bcs !ep1_wwd_bolt+
    tax
    lda ep1_wonder_slots,x
    jmp ep1_run_slot
!ep1_wwd_bolt:
    tax
    lda ep1_wonder_bolt_dice - 10,x
    ldx #8
    ldy #0
    jmp eff_bolt
ep1_wonder_bolt_dice:
    .byte 3, 4, 6

// ============================================================
// Internal Coordinate & Geometry Helpers
// ============================================================
ep1_beam_start:
    jsr eff_bolt_dir_trace_init
    bcc !ep1_bs_fail+
    inc proj_steps                  // 21 (pre-decremented in loop)
!ep1_bs_fail:
    rts

// Neighbor X = 0..7 -> 8 dirs; X = 8 -> player center. Sets ep1_x/y; C=1 if in bounds.
ep1_neighbor_xy:
    cpx #8
    bne !ep1_nxy_dir+
    lda zp_player_x
    sta ep1_x
    lda zp_player_y
    sta ep1_y
    beq !ep1_nxy_oob+               // row/col 0 is never playable; skip dir add
    bne ep1_chk_xy
!ep1_nxy_dir:
    lda zp_player_x
    ldy zp_player_y
ep1_add_dir_xy:
    clc
    adc dir_dx,x
    sta ep1_x
    tya
    clc
    adc dir_dy,x
    sta ep1_y
// Check ep1_x/ep1_y in playable interior [1..MAP_COLS-2, 1..MAP_ROWS-2]; C=1 if valid.
// Preserves: X, Y
ep1_chk_xy:
    lda ep1_x
    beq !ep1_nxy_oob+
    cmp #MAP_COLS - 1
    bcs !ep1_nxy_oob+
    lda ep1_y
    beq !ep1_nxy_oob+
    cmp #MAP_ROWS - 1
    bcs !ep1_nxy_oob+
    sec
    rts
!ep1_nxy_oob:
    clc
    rts

// Copy trace coords (proj_cx, proj_cy) into (ep1_x, ep1_y) and check interior bounds.
ep1_proj_xy_chk:
    lda proj_cx
    sta ep1_x
    lda proj_cy
    sta ep1_y
    jmp ep1_chk_xy

// Read map tile at (ep1_x, ep1_y); returns A = tile, Y = ep1_x, zp_ptr0 set.
ep1_read_xy:
    ldx ep1_y
    jsr map_row_ptr0_x
    ldy ep1_x
    :MapRead_ptr0_y()
    rts

ep1_abs_a:
    bpl !ep1_abs_ok+
    eor #$ff
    clc
    adc #1
!ep1_abs_ok:
    rts
