// test_word_of_destruction.s — Focused runtime tests for the Word of
// Destruction spell row (upstream spellDestroyArea devastation engine).

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
twd_results: .fill 7, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #6
!copy:
    lda twd_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
// dungeon_gen removed for MAP_BASE headroom
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#import "../../../../core/item.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_effects_overlay.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_destroy_area.s"
#import "../../../../core/player_magic_utility.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/ui_trampoline_stubs.s"

store_init_all:
    rts

// Local fill_map_rock (avoids importing all of dungeon_gen.s for map setup).
fill_map_rock:
    ldx #0
!fmr_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!fmr_col:
    lda #TILE_WALL_H
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS
    bne !fmr_col-
    inx
    cpx #MAP_ROWS
    bne !fmr_row-
    rts

// Linker stub — special-room generation is not exercised by this suite.
random_floor_in_room:
    lda #10
    ldy #10
    rts

store_restock_all:
    rts

store_enter:
    rts

ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

twd_spell_exec_calls: .byte 0
twd_huff_calls: .byte 0
twd_last_huff_id: .byte 0
twd_msg_calls: .byte 0
twd_last_spell_idx: .byte $ff
twd_rng_idx: .byte 0
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx twd_last_huff_id
    inc twd_huff_calls
    rts

test_msg_print:
    inc twd_msg_calls
    rts

twd_kill_calls: .byte 0
twd_note_kill_calls: .byte 0

test_eff_kill_monster:
    inc twd_kill_calls
    rts

test_combat_note_kill:
    inc twd_note_kill_calls
    rts


// Scripted rng_range: uniform-fill script, wrapping 8-bit index.
test_rng_range:
    ldx twd_rng_idx
    lda twd_rng_script,x
    inc twd_rng_idx
    rts

// A = fill value for the whole 256-byte script.
twd_rng_fill:
    ldx #255
!loop:
    sta twd_rng_script,x
    dex
    cpx #$ff
    bne !loop-
    lda #0
    sta twd_rng_idx
    rts

twd_rng_script: .fill 256, 0

eff_remove_fear:
    lda #0
    sta eff_fear_timer
    rts

test_tramp_word_of_destruction_execute:
    inc twd_spell_exec_calls
    lda pm_spell_idx
    sta twd_last_spell_idx
    jsr eff_destroy_area
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_3
    sta pm_book_mask_lo
    lda #>book_mask_3
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #29
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #21
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

// X = row, Y = col, A = tile byte
test_write_tile:
    stx zp_ptr1
    sty zp_ptr1_hi
    pha
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1_hi
    pla
    sta (zp_ptr0),y
    rts

// X = row, Y = col -> A = tile byte
test_read_tile:
    stx zp_ptr1
    sty zp_ptr1_hi
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1_hi
    lda (zp_ptr0),y
    rts

test_reset_word_of_destruction_state:
    jsr player_init
    lda #0
    sta twd_spell_exec_calls
    sta twd_huff_calls
    sta twd_last_huff_id
    sta twd_msg_calls
    sta vis_room_revealed
    sta turn_scene_dirty
    sta trap_count
    sta zp_dirty_count
    sta zp_eff_blind
    sta cmb_winner_pending
    sta twd_kill_calls
    sta twd_note_kill_calls
    lda #$ff
    sta twd_last_spell_idx
    sta vis_cached_room_idx
    lda zp_game_flags
    and #~GAME_FLAG_WINNER & $ff
    sta zp_game_flags

    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #23
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    lda #$20
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl

    lda #100
    sta cr_level + CREATURE_BALROG
    rts

test_setup_destruction_map:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta vis_room_revealed

    // 3x3 floor room at rows 11-13, cols 21-23 (player area)
    lda #TILE_FLOOR
    ldx #11
!rows:
    cpx #14
    bcs !room_done+
    ldy #21
!cols:
    jsr test_write_tile
    iny
    cpy #24
    bcc !cols-
    inx
    jmp !rows-
!room_done:

    // Metric probe floor tiles (col,row): dist vs player (x=22,y=12)
    // (38,12) dist 16, (33,20) dist 15, (34,20) dist 16,
    // (31,23) dist 15, (32,23) dist 16, (33,23) dist 16
    lda #TILE_FLOOR
    ldx #12
    ldy #38
    jsr test_write_tile
    lda #TILE_FLOOR
    ldx #20
    ldy #33
    jsr test_write_tile
    lda #TILE_FLOOR
    ldx #20
    ldy #34
    jsr test_write_tile
    lda #TILE_FLOOR
    ldx #23
    ldy #31
    jsr test_write_tile
    lda #TILE_FLOOR
    ldx #23
    ldy #32
    jsr test_write_tile
    lda #TILE_FLOOR
    ldx #23
    ldy #33
    jsr test_write_tile

    // Stairs in radius at (col 24, row 12)
    lda #TILE_STAIRS_DN
    ldx #12
    ldy #24
    jsr test_write_tile

    // Trap tile in radius at (col 22, row 13)
    lda #TILE_TRAP
    ldx #13
    ldy #22
    jsr test_write_tile

    // Monsters: slot 0 in radius (23,12) type 4; slot 1 outside (42,12)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #23
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #12
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    ldx #1
    jsr monster_get_ptr
    ldy #MX_X
    lda #42
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #12
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    lda #2
    sta zp_mon_count
    // FLAG_OCCUPIED on both monster tiles
    ldx #12
    ldy #23
    jsr test_read_tile
    ora #FLAG_OCCUPIED
    ldx #12
    ldy #23
    jsr test_write_tile
    ldx #12
    ldy #42
    jsr test_read_tile
    ora #FLAG_OCCUPIED
    ldx #12
    ldy #42
    jsr test_write_tile

    // Floor items: slot 0 under player (22,12); slot 1 outside (42,12)
    lda #1
    sta fi_item_id
    lda #22
    sta fi_x
    lda #12
    sta fi_y
    lda #2
    sta fi_item_id + 1
    lda #42
    sta fi_x + 1
    lda #12
    sta fi_y + 1
    lda #2
    sta zp_item_count

    // Glyphs: slot 0 in radius (23,13); slot 1 outside (42,12)
    lda #1
    sta glyph_active
    lda #23
    sta glyph_x
    lda #13
    sta glyph_y
    lda #1
    sta glyph_active + 1
    lda #42
    sta glyph_x + 1
    lda #12
    sta glyph_y + 1
    lda #0
    sta glyph_active + 2
    sta glyph_active + 3

    // Trap table: under player (22,12), dist 5 (27,12), dist 20 (42,12)
    lda #3
    sta trap_count
    lda #22
    sta trap_x
    lda #12
    sta trap_y
    lda #0
    sta trap_type
    lda #27
    sta trap_x + 1
    lda #12
    sta trap_y + 1
    lda #1
    sta trap_type + 1
    lda #42
    sta trap_x + 2
    lda #12
    sta trap_y + 2
    lda #2
    sta trap_type + 2

    // Rooms: room 0 covers the player (lit); room 1 outside the box (lit)
    lda #2
    sta room_count
    lda #20
    sta room_x
    lda #10
    sta room_y
    lda #6
    sta room_w
    sta room_h
    lda #1
    sta room_lit
    lda #40
    sta room_x + 1
    lda #10
    sta room_y + 1
    lda #5
    sta room_w + 1
    sta room_h + 1
    lda #1
    sta room_lit + 1
    rts
twd_ok: .byte 0

// A = actual, X = expected; a mismatch clears twd_ok. Checks never branch.
twd_expect_eq:
    sta zp_temp3
    txa
    cmp zp_temp3
    beq !tee_ok+
    lda #0
    sta twd_ok
!tee_ok:
    rts

twd_expect_zero:
    cmp #0
    beq !tez_ok+
    lda #0
    sta twd_ok
!tez_ok:
    rts

twd_expect_nonzero:
    cmp #0
    bne !ten_ok+
    lda #0
    sta twd_ok
!ten_ok:
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(test_spell_execute_selected, test_tramp_word_of_destruction_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1 (result 0): successful cast with all-zero script devastates the
    // area: terrain swept to floor, monsters/items/glyphs/traps in radius
    // silently deleted (outside survivors kept), room darkened, blind 11,
    // redraw flags set, mana spent, worked marked, no XP/winner side effects.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    lda #0
    jsr twd_rng_fill
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq              // cast succeeded
    lda twd_spell_exec_calls
    ldx #1
    jsr twd_expect_eq
    lda twd_last_spell_idx
    ldx #29
    jsr twd_expect_eq
    lda twd_msg_calls
    ldx #1
    jsr twd_expect_eq
    lda zp_eff_blind
    ldx #11
    jsr twd_expect_eq
    lda vis_room_revealed
    ldx #1
    jsr twd_expect_eq
    lda turn_scene_dirty
    ldx #1
    jsr twd_expect_eq
    lda zp_dirty_count
    jsr twd_expect_zero
    // Monsters: in-radius gone, outside alive
    lda #23
    ldy #12
    jsr monster_find_at
    lda #0
    adc #0
    ldx #0
    jsr twd_expect_eq
    lda #42
    ldy #12
    jsr monster_find_at
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    // Items: under-player item deleted, outside kept
    lda zp_item_count
    ldx #1
    jsr twd_expect_eq
    // Glyphs: in-radius cleared, outside kept
    lda glyph_active
    jsr twd_expect_zero
    lda glyph_active + 1
    ldx #1
    jsr twd_expect_eq
    // Traps: only the dist-20 entry survives
    lda trap_count
    ldx #1
    jsr twd_expect_eq
    lda trap_x
    ldx #42
    jsr twd_expect_eq
    // Rooms: intersecting room darkened, far room kept, cache dropped
    lda room_lit
    jsr twd_expect_zero
    lda room_lit + 1
    ldx #1
    jsr twd_expect_eq
    lda vis_cached_room_idx
    ldx #$ff
    jsr twd_expect_eq
    // Terrain: rock at dist 15 swept to floor (exact byte, flags clear)
    ldx #12
    ldy #37
    jsr test_read_tile
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // Stairs destroyed
    ldx #12
    ldy #24
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // Trap tile destroyed
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // dist-16 probe untouched
    ldx #20
    ldy #34
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // Edge walls permanent
    ldx #12
    ldy #0
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    ldx #12
    ldy #79
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    // Player tile forced floor
    ldx #12
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // Monster tile FLAG_OCCUPIED cleared (exact byte: plain floor)
    ldx #12
    ldy #23
    jsr test_read_tile
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // No XP, no winner state
    lda player_data + PL_XP_0
    jsr twd_expect_zero
    lda player_data + PL_XP_1
    jsr twd_expect_zero
    lda player_data + PL_XP_2
    jsr twd_expect_zero
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    jsr twd_expect_zero
    lda cmb_winner_pending
    jsr twd_expect_zero
    // Mana and worked bookkeeping
    lda zp_player_mp
    ldx #2
    jsr twd_expect_eq
    lda player_data + PL_MANA
    ldx #2
    jsr twd_expect_eq
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    jsr twd_expect_nonzero
    lda twd_ok
    sta twd_results + 0

    // Test 2 (result 1): cast failure spends mana, prints HSTR_PM_FAIL, does
    // not execute, and leaves the entire area untouched.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    lda twd_spell_exec_calls
    jsr twd_expect_zero
    lda twd_huff_calls
    ldx #1
    jsr twd_expect_eq
    lda twd_last_huff_id
    ldx #HSTR_PM_FAIL
    jsr twd_expect_eq
    lda twd_msg_calls
    jsr twd_expect_zero
    lda zp_dirty_count
    jsr twd_expect_zero
    lda vis_room_revealed
    jsr twd_expect_zero
    lda turn_scene_dirty
    jsr twd_expect_zero
    lda zp_eff_blind
    jsr twd_expect_zero
    lda #23
    ldy #12
    jsr monster_find_at
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_TRAP
    jsr twd_expect_eq
    ldx #12
    ldy #37
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    lda trap_count
    ldx #3
    jsr twd_expect_eq
    lda zp_item_count
    ldx #2
    jsr twd_expect_eq
    lda room_lit
    ldx #1
    jsr twd_expect_eq
    lda zp_player_mp
    ldx #2
    jsr twd_expect_eq
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    jsr twd_expect_zero
    lda twd_ok
    sta twd_results + 1

    // Test 3 (result 2): town guard — message and blind only; no terrain,
    // list, room, or redraw effects.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    lda #0
    jsr twd_rng_fill
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    lda #0
    sta zp_player_dlvl
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    lda twd_spell_exec_calls
    ldx #1
    jsr twd_expect_eq
    lda twd_msg_calls
    ldx #1
    jsr twd_expect_eq
    lda zp_eff_blind
    ldx #11
    jsr twd_expect_eq
    lda vis_room_revealed
    jsr twd_expect_zero
    lda turn_scene_dirty
    jsr twd_expect_zero
    lda #23
    ldy #12
    jsr monster_find_at
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    ldx #12
    ldy #37
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    lda trap_count
    ldx #3
    jsr twd_expect_eq
    lda zp_item_count
    ldx #2
    jsr twd_expect_eq
    lda room_lit
    ldx #1
    jsr twd_expect_eq
    lda twd_ok
    sta twd_results + 2

    // Test 4 (result 3): all-3 script — typ 4 everywhere, so the whole radius
    // becomes WALL_H except the forced-floor player tile; metric boundary
    // probes prove dist 15 mutates and dist 16 does not; blind 3+11 = 14.
    lda #3
    jsr twd_rng_fill
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    lda zp_eff_blind
    ldx #14
    jsr twd_expect_eq
    // dist-15 probes mutated to WALL_H
    ldx #20
    ldy #33
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    ldx #23
    ldy #31
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    ldx #12
    ldy #37
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    // dist-16 probes untouched (upstream metric, not Chebyshev)
    ldx #20
    ldy #34
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    ldx #23
    ldy #32
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    ldx #23
    ldy #33
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    ldx #12
    ldy #38
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    // Former room floor walled in
    ldx #11
    ldy #21
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    // Player tile forced floor even in the all-wall roll
    ldx #12
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    lda twd_ok
    sta twd_results + 3

    // Test 5 (result 4): a Balrog in radius is silently deleted without
    // setting the winner flag (upstream delete_monster semantics).
    lda #0
    jsr twd_rng_fill
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #CREATURE_BALROG
    sta (zp_ptr0),y
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    lda #23
    ldy #12
    jsr monster_find_at
    lda #0
    adc #0
    ldx #0
    jsr twd_expect_eq
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    jsr twd_expect_zero
    lda cmb_winner_pending
    jsr twd_expect_zero
    lda twd_ok
    sta twd_results + 4

    // Test 6 (result 5): blindness saturates at 255 (250 + 9 + 11).
    lda #9
    jsr twd_rng_fill
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    lda #250
    sta zp_eff_blind
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    lda zp_eff_blind
    ldx #255
    jsr twd_expect_eq
    lda twd_ok
    sta twd_results + 5

    // Test 7 (result 6): cast from (1,1) — no wraparound mutation; dist-15
    // tiles swept, dist-16 and edge tiles untouched.
    lda #0
    jsr twd_rng_fill
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    lda #1
    sta zp_player_x
    sta zp_player_y
    jsr player_cast_spell
    lda #1
    sta twd_ok
    lda #0
    adc #0
    ldx #1
    jsr twd_expect_eq
    ldx #1
    ldy #1
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    ldx #1
    ldy #16
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    ldx #1
    ldy #17
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    ldx #16
    ldy #1
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_FLOOR
    jsr twd_expect_eq
    ldx #17
    ldy #1
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    ldx #1
    ldy #0
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    ldx #0
    ldy #1
    jsr test_read_tile
    and #TILE_TYPE_MASK
    ldx #TILE_WALL_H
    jsr twd_expect_eq
    lda twd_ok
    sta twd_results + 6
    jmp test_finish
