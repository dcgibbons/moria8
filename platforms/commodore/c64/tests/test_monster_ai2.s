// test_monster_ai2.s — Phase 5 Wave 5.4b runtime tests for CD_INVISIBLE,
// CM2_PHASE, CM2_EATS_OTHER, and CM2_PICKS_UP in core/6502/monster.s & monster_ai.s.
//
// Results at $0400-$0417 (24 tests): $01 = pass, $00 = fail per test.

.const TEST_COUNT = 24

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_finish:
    ldx #TEST_COUNT - 1
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = * "Test Body"

.encoding "screencode_mixed"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER
#define MONSTER_AI_PRODUCTION_REST_STATE
#define MONSTER_MAGIC_PRODUCTION_EXTENDED

.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$FFF9]
.segmentdef TestUnusedEgoArmour [start=$E100, min=$E100, max=$FFF9]
#define PLAYER_CHARGEN_EXTERNAL
#define TRAP_TRIGGER_EXTERNAL
#define ITEM_SPAWN_EXTERNAL
#define PICK_ITEM_TYPE_EXTERNAL
#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
#define REU_DETECT_EXTERNAL
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/6502/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/6502/rng.s"
#import "../../../../core/6502/math.s"
#import "../../../../core/6502/tables.s"
#import "../../../../core/6502/item_defs.s"
#import "../../../../core/6502/player.s"
#import "../../../../core/6502/ui_messages.s"
status_mark_dirty:
status_draw:
    rts
#import "../../../../core/6502/ui_help_clear.s"
.segment TestCreateOverlay
#import "../../../../core/6502/stat_display.s"
player_create:
    brk
.segment Default
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/6502/huffman.s"
#define CMD_JAM_SEGMENT_CUSTOM
.macro CmdJamSegment() {
    .segment TestCreateOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/6502/monster_ai.s"
#import "../../../../core/6502/recall.s"
#import "../../../../core/6502/monster_magic.s"
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
hal_item_cat_read_byte:
    brk
#import "../../../../core/6502/special_rooms.s"
#define EGO_ARMOUR_SEGMENT_CUSTOM
.macro EgoArmourSegment() {
    .segment TestCreateOverlay
}
.macro EgoArmourRestoreSegment() {
    .segment Default
}
#define EGO_ARMOUR_DATA_SEGMENT_CUSTOM
.macro EgoArmourDataSegment() {
    .segment TestCreateOverlay
}
.macro EgoArmourDataRestoreSegment() {
    .segment Default
}
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
.segment TestCreateOverlay
#import "../../../../core/6502/player_items.s"
.segment Default
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/projectile.s"
#import "../../../../core/6502/spell_effects.s"
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
.segment TestUnusedEgoArmour
#import "../../../../core/6502/trap_trigger_cold.s"
#import "../../../../core/6502/player_chargen_cold.s"
#import "../../../../core/6502/item_spawn_cold.s"
#import "../../../../core/6502/pick_item_type_cold.s"
#import "../../../../core/6502/item_actions_overlay.s"
.segment Default
#import "../dungeon_render.s"
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"

eff_fear_timer: .byte 0
monster_attack_player:
player_update_hunger_state:
    sec
    rts
mad_dmg_hi: .byte 0
mon_atk_acid_armour:
    clc
    rts
mon_atk_apply_damage:
    lda #0
    sta mad_dmg_hi
mon_atk_apply_damage_16:
    clc
    rts
player_death_check:
store_init_all:
store_restock_all:
store_enter:
ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
ui_char_display:
    rts
#import "../../../../core/6502/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

auto_rest_active: .byte 0
tc_results: .fill TEST_COUNT, $00
tai_rng_word_orig: .fill 3, 0

// Species slots in embedded roster used as clean test templates:
//   slot 4 = Kobold (display $0b 'k', speed 1, aaf 20|OPEN_DOOR, level 1, xp 5)
//   slot 1 = Giant White Mouse (display $12 'r', speed 1, aaf 8, level 1, xp 1)
.const T_M1 = 4
.const T_M2 = 1
.const SC_GHOST = $47           // Uppercase 'G' screen code
.const SC_FLOOR_DOT = $2e       // '.' screen code

// ============================================================
// Helpers
// ============================================================

// reset_box — Reset world, map box (0..37, 0..20) to lit visited floor with
// permanent outer rock border on x=0, x=MAP_COLS-1, y=0, y=MAP_ROWS-1;
// reset monsters, floor items, door states, glyphs, player flags, and timers.
reset_box:
    ldx #PL_STRUCT_SIZE - 1
    lda #0
!rb_pdata:
    sta player_data,x
    dex
    bpl !rb_pdata-
    jsr monster_init_table
    jsr item_init_floor
    jsr item_init_inventory
    jsr msg_clear
    lda #0
    sta door_state_count
    sta trap_count
    sta zp_disturb
    sta zp_dirty_count
    sta mat_scene_dirty
    sta zp_eff_blind
    sta zp_eff_speed
    sta zp_eff_see_inv
    sta zp_eff_invis
    sta zp_eff_infra
    sta eff_detect_timer
    sta eff_detect_evil_mode
    sta muv_clear_detected
    sta player_pflags
    sta player_pflags2
    sta auto_rest_active
    sta zp_game_flags
    sta zp_turn_lo
    sta zp_turn_hi
    sta zp_view_x
    sta zp_view_y
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2
    lda #1
    sta zp_player_dlvl
    sta zp_light_radius
    lda #10
    sta zp_player_x
    sta old_player_x
    sta zp_player_y
    sta old_player_y

    // Reset test species slots T_M1 and T_M2 to deterministic baseline
    lda #SC_GHOST
    sta cr_display + T_M1
    lda #COL_WHITE
    sta cr_color + T_M1
    lda #1
    sta cr_speed + T_M1
    sta cr_speed + T_M2
    lda #0
    sta cr_mflags + T_M1
    sta cr_mflags + T_M2
    sta cr_spell_chance + T_M1
    sta cr_spell_chance + T_M2
    sta cr_spell_flags + T_M1
    sta cr_spell_flags + T_M2
    sta cr_spell_flags2 + T_M1
    sta cr_spell_flags2 + T_M2
    sta cr_cdefense + T_M1
    sta cr_cdefense + T_M2
    lda #20
    sta cr_aaf + T_M1
    sta cr_aaf + T_M2
    lda #2
    sta cr_level + T_M1
    sta cr_level + T_M2
    lda #10
    sta cr_hd_num + T_M1
    sta cr_hd_num + T_M2
    lda #8
    sta cr_hd_sides + T_M1
    sta cr_hd_sides + T_M2
    lda #36
    sta cr_xp_lo + T_M1
    lda #0
    sta cr_xp_hi + T_M1
    lda #10
    sta cr_xp_lo + T_M2
    lda #0
    sta cr_xp_hi + T_M2
    lda #$0b
    sta cr_display + T_M2
    lda #COL_GREEN
    sta cr_color + T_M2

    // Fill entire map with lit visited floor inside bounds, rock at edges
    ldx #0
!rb_row:
    jsr map_row_ptr0_x
    ldy #0
!rb_col:
    lda #TILE_WALL_H
    cpx #0
    beq !rb_write+
    cpx #MAP_ROWS - 1
    beq !rb_write+
    cpy #0
    beq !rb_write+
    cpy #MAP_COLS - 1
    beq !rb_write+
    lda #(TILE_FLOOR | FLAG_LIT | FLAG_VISITED)
!rb_write:
    sta (zp_ptr0),y
    iny
    cpy #MAP_COLS
    bcc !rb_col-
    inx
    cpx #MAP_ROWS
    bcc !rb_row-
    rts

// set_tile — Write A to map at (X=col, Y=row)
set_tile:
    pha
    tya
    pha
    txa
    tay                         // Y = col
    pla
    tax                         // X = row
    jsr map_row_ptr0_x
    pla
    sta (zp_ptr0),y
    rts

// get_tile — Read map at (X=col, Y=row) -> A
get_tile:
    tya
    pha
    txa
    tay                         // Y = col
    pla
    tax                         // X = row
    jsr map_row_ptr0_x
    lda (zp_ptr0),y
    rts

// spawn_awake — Spawn species A at (X=col, Y=row), awake
// Returns: X = monster slot
spawn_awake:
    pha
    stx ms_spawn_x
    sty ms_spawn_y
    pla
    jsr monster_spawn_one
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    rts

// spawn_asleep_blocker — Spawn T_M2 asleep at (X=col, Y=row) with sleep 200
spawn_asleep_blocker:
    stx ms_spawn_x
    sty ms_spawn_y
    lda #T_M2
    jsr monster_spawn_one
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #200
    sta (zp_ptr0),y
    rts

// screen_char_at — Read screen code at map (X=col, Y=row) when view=(0,0) -> A, color -> X
screen_char_at:
    iny
    iny                         // VIEWPORT_Y = 2
    lda screen_row_lo,y
    sta zp_ptr1
    lda screen_row_hi,y
    sta zp_ptr1_hi
    lda color_row_lo,y
    sta zp_ptr2
    lda color_row_hi,y
    sta zp_ptr2_hi
    inx                         // VIEWPORT_X = 1
    txa
    tay
    lda (zp_ptr2),y
    and #$0f
    tax
    lda (zp_ptr1),y
    rts

// rng_word_max — Force rng_range_word to return $0bb7 (2999 -> 3000 >= level, glyph holds)
rng_word_max:
    lda #<$0bb7
    sta zp_temp2
    lda #>$0bb7
    sta zp_temp3
    rts

patch_glyph_hold:
    ldx #2
!pgh_save:
    lda rng_range_word,x
    sta tai_rng_word_orig,x
    dex
    bpl !pgh_save-
    lda #$4c
    sta rng_range_word
    lda #<rng_word_max
    sta rng_range_word + 1
    lda #>rng_word_max
    sta rng_range_word + 2
    rts

// rng_word_zero — Force rng_range_word to return 0 (guaranteed door burst)
rng_word_zero:
    lda #0
    sta zp_temp2
    sta zp_temp3
    rts

patch_rng_word_zero:
    ldx #2
!prwz_save:
    lda rng_range_word,x
    sta tai_rng_word_orig,x
    dex
    bpl !prwz_save-
    lda #$4c
    sta rng_range_word
    lda #<rng_word_zero
    sta rng_range_word + 1
    lda #>rng_word_zero
    sta rng_range_word + 2
    rts

restore_glyph_rng:
    ldx #2
!rgr_loop:
    lda tai_rng_word_orig,x
    sta rng_range_word,x
    dex
    bpl !rgr_loop-
    rts

// ============================================================
// Test Entry
// ============================================================
test_start:
    lda #$91
    sta zp_rng_0
    lda #$82
    sta zp_rng_1
    lda #$73
    sta zp_rng_2
    lda #$cf
    sta zp_rng_3

    // ----------------------------------------------------------
    // Test 0: CD_INVISIBLE ($80) stays unseen (!MF_VISIBLE) even adjacent
    // on lit tile when player lacks see-invis; search mode undisturbed;
    // render_viewport renders bare floor '.'.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CD_INVISIBLE
    sta cr_cdefense + T_M1
    lda #2
    sta zp_light_radius
    ldx #11
    ldy #10
    lda #T_M1
    jsr spawn_awake
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    jsr monster_update_visibility_all
    cmp #0
    bne !t0_done+               // Was 0, stays 0 -> no change
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq !t0_done+               // Search mode must stay active
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    bne !t0_done+
    jsr render_viewport
    ldx #11
    ldy #10
    jsr screen_char_at
    cmp #SC_FLOOR_DOT
    bne !t0_done+
    lda #$01
    sta tc_results + 0
!t0_done:

    // ----------------------------------------------------------
    // Test 1: PFLAG_SEE_INVIS reveals CD_INVISIBLE (returns A=1, sets
    // MF_VISIBLE, clears search mode, renders glyph); removing PFLAG_SEE_INVIS
    // returns A=1 and clears MF_VISIBLE.
    // ----------------------------------------------------------
    lda #PFLAG_SEE_INVIS
    sta player_pflags
    jsr monster_update_visibility_all
    cmp #1
    bne !t1_done+
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    bne !t1_done+               // Entering sight disturbs search mode
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    beq !t1_done+
    jsr render_viewport
    ldx #11
    ldy #10
    jsr screen_char_at
    cmp #SC_GHOST
    bne !t1_done+
    lda #0
    sta player_pflags
    jsr monster_update_visibility_all
    cmp #1
    bne !t1_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    bne !t1_done+
    lda #$01
    sta tc_results + 1
!t1_done:

    // ----------------------------------------------------------
    // Test 2: Temporary zp_eff_see_inv and zp_eff_invis each reveal
    // CD_INVISIBLE, while blindness and wall LOS occlusion still hide it.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CD_INVISIBLE
    sta cr_cdefense + T_M1
    lda #3
    sta zp_light_radius
    ldx #12
    ldy #10
    lda #T_M1
    jsr spawn_awake
    // Case A: zp_eff_see_inv > 0
    lda #5
    sta zp_eff_see_inv
    jsr monster_update_visibility_all
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    beq !t2_done+
    // Case B: zp_eff_invis > 0 alone
    lda #0
    sta zp_eff_see_inv
    lda #4
    sta zp_eff_invis
    jsr monster_update_visibility_all
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    beq !t2_done+
    // Case C: blind overrides see-invis
    lda #PFLAG_SEE_INVIS
    sta player_pflags
    lda #2
    sta zp_eff_blind
    jsr monster_update_visibility_all
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    bne !t2_done+
    // Case D: wall at (11,10) blocks LOS to (12,10) even with PFLAG_SEE_INVIS
    lda #0
    sta zp_eff_blind
    ldx #11
    ldy #10
    lda #(TILE_WALL_H | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    jsr monster_update_visibility_all
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    bne !t2_done+
    lda #$01
    sta tc_results + 2
!t2_done:

    // ----------------------------------------------------------
    // Test 3: Detect Monsters (eff_detect_timer) sets MF_DETECTED on a
    // CD_INVISIBLE monster while keeping MF_VISIBLE == 0 (MON-001).
    // ----------------------------------------------------------
    jsr reset_box
    lda #CD_INVISIBLE
    sta cr_cdefense + T_M1
    ldx #14
    ldy #10
    lda #T_M1
    jsr spawn_awake
    lda #5
    sta eff_detect_timer
    jsr monster_update_visibility_all
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    cmp #MF_DETECTED
    bne !t3_done+
    jsr render_viewport
    ldx #14
    ldy #10
    jsr screen_char_at
    cmp #SC_GHOST
    bne !t3_done+
    lda #$01
    sta tc_results + 3
!t3_done:

    // ----------------------------------------------------------
    // Test 4: CM2_PHASE ($20) walks through granite, magma, quartz, and
    // rubble without modifying underlying tile types or lighting flags.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_PHASE
    sta cr_spell_flags2 + T_M1
    ldx #14
    ldy #10
    lda #(TILE_WALL_H | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    ldx #13
    ldy #10
    lda #(TILE_MAGMA | FLAG_VISITED)
    jsr set_tile
    ldx #12
    ldy #10
    lda #(TILE_QUARTZ | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    ldx #11
    ldy #10
    lda #(TILE_RUBBLE | FLAG_VISITED)
    jsr set_tile
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake

    // 4 ticks: (15,10) -> (14,10) -> (13,10) -> (12,10) -> (11,10)
    jsr monster_ai_tick
    jsr monster_ai_tick
    jsr monster_ai_tick
    jsr monster_ai_tick

    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #11
    bne !t4_done+
    ldx #14
    ldy #10
    jsr get_tile
    cmp #(TILE_WALL_H | FLAG_LIT | FLAG_VISITED)
    bne !t4_done+
    ldx #13
    ldy #10
    jsr get_tile
    cmp #(TILE_MAGMA | FLAG_VISITED)
    bne !t4_done+
    ldx #12
    ldy #10
    jsr get_tile
    cmp #(TILE_QUARTZ | FLAG_LIT | FLAG_VISITED)
    bne !t4_done+
    ldx #11
    ldy #10
    jsr get_tile
    cmp #(TILE_RUBBLE | FLAG_VISITED | FLAG_OCCUPIED)
    bne !t4_done+
    lda #$01
    sta tc_results + 4
!t4_done:

    // ----------------------------------------------------------
    // Test 5: CM2_PHASE passes through locked, jammed, and secret doors
    // without opening, unlocking, or mutating door_state.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_PHASE
    sta cr_spell_flags2 + T_M1
    lda #(20 | CD_OPEN_DOOR_BIT)
    sta cr_aaf + T_M1
    // (14,10): locked closed door (state = 15)
    ldx #14
    ldy #10
    lda #(TILE_DOOR_CLOSED | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    lda #14
    sta df_target_x
    lda #10
    sta df_target_y
    lda #15
    jsr door_state_set_at
    // (13,10): jammed closed door (state = $80 | 20 = $94)
    ldx #13
    ldy #10
    lda #(TILE_DOOR_CLOSED | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    lda #13
    sta df_target_x
    lda #10
    sta df_target_y
    lda #$94
    jsr door_state_set_at
    // (12,10): secret door
    ldx #12
    ldy #10
    lda #(TILE_SECRET | FLAG_LIT | FLAG_VISITED)
    jsr set_tile

    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    jsr monster_ai_tick
    jsr monster_ai_tick
    jsr monster_ai_tick

    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #12
    bne !t5_done+
    ldx #14
    ldy #10
    jsr get_tile
    cmp #(TILE_DOOR_CLOSED | FLAG_LIT | FLAG_VISITED)
    bne !t5_done+
    lda #14
    ldy #10
    jsr door_state_get
    cmp #15
    bne !t5_done+
    ldx #13
    ldy #10
    jsr get_tile
    cmp #(TILE_DOOR_CLOSED | FLAG_LIT | FLAG_VISITED)
    bne !t5_done+
    lda #13
    ldy #10
    jsr door_state_get
    cmp #$94
    bne !t5_done+
    ldx #12
    ldy #10
    jsr get_tile
    cmp #(TILE_SECRET | FLAG_LIT | FLAG_VISITED | FLAG_OCCUPIED)
    bne !t5_done+
    lda #$01
    sta tc_results + 5
!t5_done:

    // ----------------------------------------------------------
    // Test 6: CM2_PHASE is blocked by all 4 outer permanent boundary walls
    // (x=0, x=MAP_COLS-1, y=0, y=MAP_ROWS-1) AND town permanent walls.
    // ----------------------------------------------------------
    // West boundary: monster at (1,10) moving toward player at (0,12), blocker at (1,11)
    jsr reset_box
    lda #CM2_PHASE
    sta cr_spell_flags2 + T_M1
    lda #0
    sta zp_player_x
    lda #12
    sta zp_player_y
    ldx #1
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #1
    ldy #11
    jsr spawn_asleep_blocker
    jsr monster_ai_tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #1
    beq !+
    jmp !t6_done+
!:
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #10
    beq !+
    jmp !t6_done+
!:
    // East boundary: monster at (MAP_COLS-2, 10), player at (MAP_COLS-1, 12), blocker at (MAP_COLS-2, 11)
    jsr monster_init_table
    lda #MAP_COLS - 1
    sta zp_player_x
    lda #12
    sta zp_player_y
    ldx #MAP_COLS - 2
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #MAP_COLS - 2
    ldy #11
    jsr spawn_asleep_blocker
    jsr monster_ai_tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #MAP_COLS - 2
    beq !+
    jmp !t6_done+
!:
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #10
    beq !+
    jmp !t6_done+
!:
    // North boundary: monster at (10, 1), player at (12, 0), blocker at (11, 1)
    jsr monster_init_table
    lda #12
    sta zp_player_x
    lda #0
    sta zp_player_y
    ldx #10
    ldy #1
    lda #T_M1
    jsr spawn_awake
    ldx #11
    ldy #1
    jsr spawn_asleep_blocker
    jsr monster_ai_tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #10
    beq !+
    jmp !t6_done+
!:
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #1
    beq !+
    jmp !t6_done+
!:
    // South boundary: monster at (10, MAP_ROWS-2), player at (12, MAP_ROWS-1), blocker at (11, MAP_ROWS-2)
    jsr monster_init_table
    lda #12
    sta zp_player_x
    lda #MAP_ROWS - 1
    sta zp_player_y
    ldx #10
    ldy #MAP_ROWS - 2
    lda #T_M1
    jsr spawn_awake
    ldx #11
    ldy #MAP_ROWS - 2
    jsr spawn_asleep_blocker
    jsr monster_ai_tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #10
    beq !+
    jmp !t6_done+
!:
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp #MAP_ROWS - 2
    beq !+
    jmp !t6_done+
!:

    // Town permanent wall block (zp_player_dlvl = 0): enclosed by walls around (15,10)
    jsr reset_box
    lda #0
    sta zp_player_dlvl
    lda #CM2_PHASE
    sta cr_spell_flags2 + T_M1
    ldx #14
    ldy #9
    lda #(TILE_WALL_V | TOWN_FLAGS)
    jsr set_tile
    ldx #14
    ldy #10
    lda #(TILE_WALL_V | TOWN_FLAGS)
    jsr set_tile
    ldx #14
    ldy #11
    lda #(TILE_WALL_V | TOWN_FLAGS)
    jsr set_tile
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    jsr monster_ai_tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #15
    bne !t6_done+
    lda #$01
    sta tc_results + 6
!t6_done:

    // ----------------------------------------------------------
    // Test 7: CM2_PHASE non-local wall redraw cleanliness (visited room wall
    // with MF_VISIBLE AND unvisited solid rock with MF_DETECTED leave zero
    // ghost glyph artifacts on screen).
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_PHASE
    sta cr_spell_flags2 + T_M1
    lda #1
    sta zp_light_radius
    // Visited lit wall at (16,10) (distance 6 > light_radius + 1)
    ldx #16
    ldy #10
    lda #(TILE_WALL_V | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    ldx #17
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_VISIBLE)
    sta (zp_ptr0),y
    jsr render_viewport
    // Tick 1: (17,10) -> (16,10) wall; screen (17,10)='.', (16,10)='G'
    jsr monster_ai_tick
    ldx #17
    ldy #10
    jsr screen_char_at
    cmp #SC_FLOOR_DOT
    beq !+
    jmp !t7_done+
!:  ldx #16
    ldy #10
    jsr screen_char_at
    cmp #SC_GHOST
    beq !+
    jmp !t7_done+
!:  // Tick 2: (16,10) wall -> (15,10) floor; screen (16,10) restored to wall glyph!
    jsr monster_ai_tick
    ldx #16
    ldy #10
    jsr screen_char_at
    cmp tile_screen_codes + 2   // TILE_WALL_V screen code
    beq !+
    jmp !t7_done+
!:  ldx #15
    ldy #10
    jsr screen_char_at
    cmp #SC_GHOST
    beq !+
    jmp !t7_done+
!:

    // Part B: Unvisited rock with MF_DETECTED restores SC_SPACE + COL_BLACK
    jsr reset_box
    lda #CM2_PHASE
    sta cr_spell_flags2 + T_M1
    lda #1
    sta zp_light_radius
    ldx #17
    ldy #10
    lda #TILE_WALL_H            // Unvisited rock (!FLAG_VISITED)
    jsr set_tile
    ldx #16
    ldy #10
    lda #TILE_WALL_H            // Unvisited rock (!FLAG_VISITED)
    jsr set_tile
    ldx #17
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_DETECTED)
    sta (zp_ptr0),y
    jsr render_viewport
    ldx #17
    ldy #10
    jsr screen_char_at
    cmp #SC_GHOST
    bne !t7_done+
    jsr monster_ai_tick         // Steps (17,10) -> (16,10)
    ldx #17
    ldy #10
    jsr screen_char_at
    cmp #SC_SPACE
    bne !t7_done+
    cpx #COL_BLACK
    bne !t7_done+
    ldx #16
    ldy #10
    jsr screen_char_at
    cmp #SC_GHOST
    bne !t7_done+
    lda #$01
    sta tc_results + 7
!t7_done:

    // ----------------------------------------------------------
    // Test 8: CM2_EATS_OTHER ($40) eats weaker (36 > 10) and equal-mexp
    // (36 == 36) creatures without awarding player XP or staging loot.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_EATS_OTHER
    sta cr_spell_flags2 + T_M1
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake             // slot 0: xp = 36
    ldx #14
    ldy #10
    lda #T_M2
    jsr spawn_awake             // slot 1: asleep/blocked? keep asleep (MF_AWAKE clear)
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #250
    sta (zp_ptr0),y
    lda #1
    sta auto_rest_active        // Suppress ordinary wake so slot 1 stays at (14,10)

    jsr monster_ai_tick
    lda zp_mon_count
    cmp #1
    bne !t8_done+
    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t8_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #14
    bne !t8_done+
    lda md_count
    bne !t8_done+
    lda player_data + PL_XP_0
    ora player_data + PL_XP_1
    ora player_data + PL_XP_2
    bne !t8_done+

    // Equal mexp (36 == 36) also succeeds
    lda #36
    sta cr_xp_lo + T_M2
    ldx #13
    ldy #10
    lda #T_M2
    jsr spawn_awake
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #250
    sta (zp_ptr0),y
    jsr monster_ai_tick
    lda zp_mon_count
    cmp #1
    bne !t8_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #13
    bne !t8_done+
    lda #$01
    sta tc_results + 8
!t8_done:

    // ----------------------------------------------------------
    // Test 9: CM2_EATS_OTHER blocked when cr_xp[m1] < cr_xp[m2] (35 < 36
    // and 16-bit $00FF < $0100), and succeeds across hi-byte ($0100 > $00FF).
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_EATS_OTHER
    sta cr_spell_flags2 + T_M1
    lda #35
    sta cr_xp_lo + T_M1
    lda #36
    sta cr_xp_lo + T_M2
    // Corridor along y=10 (walls at y=9 and y=11) so no diagonal bypass
    ldx #13
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #13
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    lda #1
    sta auto_rest_active

    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #14
    ldy #10
    lda #T_M2
    jsr spawn_awake
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #250
    sta (zp_ptr0),y

    // 35 < 36 -> blocked
    jsr monster_ai_tick
    lda zp_mon_count
    cmp #2
    bne !t9_done+

    // 16-bit $00FF (255) < $0100 (256) -> blocked
    lda #$ff
    sta cr_xp_lo + T_M1
    lda #$00
    sta cr_xp_hi + T_M1
    lda #$00
    sta cr_xp_lo + T_M2
    lda #$01
    sta cr_xp_hi + T_M2
    jsr monster_ai_tick
    lda zp_mon_count
    cmp #2
    bne !t9_done+

    // 16-bit $0100 (256) > $00FF (255) -> eats m2!
    lda #$00
    sta cr_xp_lo + T_M1
    lda #$01
    sta cr_xp_hi + T_M1
    lda #$ff
    sta cr_xp_lo + T_M2
    lda #$00
    sta cr_xp_hi + T_M2
    jsr monster_ai_tick
    lda zp_mon_count
    cmp #1
    bne !t9_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #14
    bne !t9_done+
    lda #$01
    sta tc_results + 9
!t9_done:

    // ----------------------------------------------------------
    // Test 10: CM2_EATS_OTHER never eats a win creature (Balrog, level 100),
    // even if mover's cr_xp exceeds target's cr_xp.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_EATS_OTHER
    sta cr_spell_flags2 + T_M1
    lda #<$1388                 // 5000 XP
    sta cr_xp_lo + T_M1
    lda #>$1388
    sta cr_xp_hi + T_M1
    lda #100                    // Win creature (Balrog)
    sta cr_level + T_M2
    lda #10
    sta cr_xp_lo + T_M2
    lda #0
    sta cr_xp_hi + T_M2
    ldx #14
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    lda #1
    sta auto_rest_active

    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #14
    ldy #10
    lda #T_M2
    jsr spawn_awake
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #250
    sta (zp_ptr0),y

    jsr monster_ai_tick
    lda zp_mon_count
    cmp #2
    bne !t10_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #15
    bne !t10_done+
    lda #$01
    sta tc_results + 10
!t10_done:

    // ----------------------------------------------------------
    // Test 11: CM2_EATS_OTHER blocked by unbroken Glyph of Warding preserves
    // m2; and unseen CD_INVISIBLE eater eating visible m2 at non-local
    // distance immediately erases m2's glyph on screen.
    // ----------------------------------------------------------
    jsr reset_box
    lda #(CM2_EATS_OTHER)
    sta cr_spell_flags2 + T_M1
    lda #CD_INVISIBLE
    sta cr_cdefense + T_M1
    lda #1
    sta zp_light_radius
    sta auto_rest_active
    ldx #16
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #16
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile

    ldx #17
    ldy #10
    lda #T_M1
    jsr spawn_awake             // slot 0: unseen (MF_VISIBLE == 0)
    ldx #16
    ldy #10
    lda #T_M2
    jsr spawn_awake             // slot 1: visible Kobold at distance 6
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_VISIBLE             // Asleep + visible
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #250
    sta (zp_ptr0),y

    // Place unbroken glyph on (16,10) and force glyph hold
    lda #16
    ldy #10
    jsr glyph_add_at
    jsr patch_glyph_hold
    jsr monster_ai_tick
    jsr restore_glyph_rng
    lda zp_mon_count
    cmp #2
    bne !t11_done+              // Glyph blocked move -> m2 survived!

    // Remove glyph, render viewport (shows Kobold '$0b' at (16,10)), then eat!
    ldx #0
    jsr glyph_remove
    jsr render_viewport
    ldx #16
    ldy #10
    jsr screen_char_at
    cmp #$0b
    bne !t11_done+
    jsr monster_ai_tick
    lda zp_mon_count
    cmp #1
    bne !t11_done+
    ldx #16
    ldy #10
    jsr screen_char_at
    cmp #SC_FLOOR_DOT           // Kobold erased to floor dot despite unseen eater!
    bne !t11_done+
    lda #$01
    sta tc_results + 11
!t11_done:

    // ----------------------------------------------------------
    // Test 12: Non-picker leaves floor item intact; CM2_PICKS_UP ($80)
    // removes non-gold floor item and clears FLAG_HAS_ITEM.
    // ----------------------------------------------------------
    jsr reset_box
    jsr fi_add_clear_plain_meta
    lda #14
    sta fi_add_x
    lda #10
    sta fi_add_y
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Cure Light Wounds Potion (ICAT_POTION)
    sta fi_add_id
    lda #1
    sta fi_add_qty
    jsr floor_item_add
    // Non-picker walks over (14,10) -> item remains
    ldx #15
    ldy #10
    lda #T_M2
    jsr spawn_awake
    jsr monster_ai_tick
    lda zp_item_count
    cmp #1
    bne !t12_done+
    // Move non-picker off (14,10) -> (13,10)
    jsr monster_ai_tick
    // Now spawn CM2_PICKS_UP creature at (15,10) -> steps onto (14,10) and removes item
    lda #CM2_PICKS_UP
    sta cr_spell_flags2 + T_M1
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    jsr monster_ai_tick
    lda zp_item_count
    bne !t12_done+
    lda fi_item_id + 0
    cmp #FI_EMPTY
    bne !t12_done+
    ldx #14
    ldy #10
    jsr get_tile
    and #FLAG_HAS_ITEM
    bne !t12_done+
    lda #$01
    sta tc_results + 12
!t12_done:

    // ----------------------------------------------------------
    // Test 13: CM2_PICKS_UP leaves floor gold untouched (VMS creature.inc:826
    // tval < 100 excludes gold tval == 100).
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_PICKS_UP
    sta cr_spell_flags2 + T_M1
    jsr fi_add_clear_plain_meta
    lda #14
    sta fi_add_x
    lda #10
    sta fi_add_y
    lda #ITEM_SLOT_GOLD_SMALL                      // Gold (small), ICAT_GOLD
    sta fi_add_id
    lda #25
    sta fi_add_qty
    jsr floor_item_add
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    jsr monster_ai_tick
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #14
    bne !t13_done+
    lda zp_item_count
    cmp #1
    bne !t13_done+
    lda fi_item_id + 0
    bne !t13_done+
    ldx #14
    ldy #10
    jsr get_tile
    and #FLAG_HAS_ITEM
    beq !t13_done+
    lda #$01
    sta tc_results + 13
!t13_done:

    // ----------------------------------------------------------
    // Test 14: Unbroken Glyph of Warding blocks CM2_PICKS_UP monster before
    // floor item removal.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_PICKS_UP
    sta cr_spell_flags2 + T_M1
    ldx #14
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    jsr fi_add_clear_plain_meta
    lda #14
    sta fi_add_x
    lda #10
    sta fi_add_y
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Potion
    sta fi_add_id
    lda #1
    sta fi_add_qty
    jsr floor_item_add
    lda #14
    ldy #10
    jsr glyph_add_at
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    jsr patch_glyph_hold
    jsr monster_ai_tick
    jsr restore_glyph_rng
    lda zp_item_count
    cmp #1
    bne !t14_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp #15
    bne !t14_done+
    lda #$01
    sta tc_results + 14
!t14_done:

    // ----------------------------------------------------------
    // Test 15: Unseen CD_INVISIBLE | CM2_PICKS_UP creature (Poltergeist)
    // picking up a visible floor item at non-local distance erases the item
    // glyph on screen immediately.
    // ----------------------------------------------------------
    jsr reset_box
    lda #CM2_PICKS_UP
    sta cr_spell_flags2 + T_M1
    lda #CD_INVISIBLE
    sta cr_cdefense + T_M1
    lda #1
    sta zp_light_radius
    jsr fi_add_clear_plain_meta
    lda #16
    sta fi_add_x
    lda #10
    sta fi_add_y
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Potion ('!' = $21)
    sta fi_add_id
    lda #1
    sta fi_add_qty
    jsr floor_item_add
    ldx #17
    ldy #10
    lda #T_M1
    jsr spawn_awake             // Unseen (MF_VISIBLE == 0)
    jsr render_viewport
    ldx #16
    ldy #10
    jsr screen_char_at
    cmp #$21                    // '!' potion glyph on screen before pickup
    bne !t15_done+
    jsr monster_ai_tick
    lda zp_item_count
    bne !t15_done+
    ldx #16
    ldy #10
    jsr screen_char_at
    cmp #SC_FLOOR_DOT           // Redrawn to '.' even though mover is unseen!
    bne !t15_done+
    lda #$01
    sta tc_results + 15
!t15_done:

    // ----------------------------------------------------------
    // Test 16: muvo_apply_visible MF_VISIBLE 0->1 increments zp_disturb;
    // 1->1 stays quiet; CD_INVISIBLE without see-invis stays quiet and with
    // PFLAG_SEE_INVIS disturbs; detected-only behind wall stays quiet.
    // ----------------------------------------------------------
    jsr reset_box
    lda #2
    sta zp_light_radius
    ldx #12
    ldy #10
    lda #T_M1
    jsr spawn_awake             // starts MF_VISIBLE == 0
    lda #0
    sta zp_disturb
    jsr monster_update_visibility_all
    lda zp_disturb
    cmp #1                      // 0 -> 1 sighting disturbs
    beq !+
    jmp !t16_done+
!:  // Second pass: 1 -> 1 already visible stays quiet
    lda #0
    sta zp_disturb
    jsr monster_update_visibility_all
    lda zp_disturb
    beq !+
    jmp !t16_done+
!:  // CD_INVISIBLE without see-invis: stays unseen, no disturb
    jsr reset_box
    lda #CD_INVISIBLE
    sta cr_cdefense + T_M1
    lda #2
    sta zp_light_radius
    ldx #11
    ldy #10
    lda #T_M1
    jsr spawn_awake
    lda #0
    sta zp_disturb
    jsr monster_update_visibility_all
    lda zp_disturb
    beq !+
    jmp !t16_done+
!:  // Grant PFLAG_SEE_INVIS: 0 -> 1 disturbs
    lda #PFLAG_SEE_INVIS
    sta player_pflags
    jsr monster_update_visibility_all
    lda zp_disturb
    cmp #1
    beq !+
    jmp !t16_done+
!:  // Detected-only behind wall: MF_DETECTED set, MF_VISIBLE == 0, no disturb
    jsr reset_box
    ldx #11
    ldy #10
    lda #(TILE_WALL_H | FLAG_LIT | FLAG_VISITED)
    jsr set_tile
    ldx #13
    ldy #10
    lda #T_M1
    jsr spawn_awake
    lda #5
    sta eff_detect_timer
    lda #0
    sta zp_disturb
    jsr monster_update_visibility_all
    lda zp_disturb
    bne !t16_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #(MF_VISIBLE | MF_DETECTED)
    cmp #MF_DETECTED
    bne !t16_done+
    lda #$01
    sta tc_results + 16
!t16_done:

    // ----------------------------------------------------------
    // Test 17: Visible hostile local-radius move (<= zp_light_radius + 1, so
    // mat_scene_dirty / turn_scene_dirty == 0) STILL disturbs via zp_disturb;
    // unseen hostile move (MF_VISIBLE == 0, even with MF_DETECTED) stays quiet.
    // ----------------------------------------------------------
    jsr reset_box
    lda #2
    sta zp_light_radius         // local radius = 3
    ldx #13
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_VISIBLE)
    sta (zp_ptr0),y
    lda #0
    sta zp_disturb
    jsr monster_ai_tick         // (13,10) -> (12,10), both <= local radius 3
    cmp #0                      // mat_scene_dirty == 0 (local move)
    bne !t17_done+
    lda zp_disturb
    beq !t17_done+
    // Unseen hostile mover (MF_DETECTED only, MF_VISIBLE == 0): quiet
    jsr reset_box
    lda #1
    sta zp_light_radius
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_DETECTED)
    sta (zp_ptr0),y
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    lda zp_disturb
    bne !t17_done+
    lda #$01
    sta tc_results + 17
!t17_done:

    // ----------------------------------------------------------
    // Test 18: Unprovoked visible townie wandering stays quiet (mat_action_dirty
    // = $81, bit 1 clear); provoked visible townie moving disturbs ($83).
    // ----------------------------------------------------------
    jsr reset_box
    lda #0
    sta zp_player_dlvl
    ldx #15
    ldy #10
    lda #TOWN_CREATURE_BASE
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_VISIBLE)
    sta (zp_ptr0),y
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    lda mat_action_dirty
    cmp #$81
    bne !t18_done+
    lda zp_disturb
    bne !t18_done+
    // Now provoke the townie -> hostile move sets bit 1 and disturbs
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_VISIBLE | MF_PROVOKED)
    sta (zp_ptr0),y
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    lda mat_action_dirty
    cmp #$83
    bne !t18_done+
    lda zp_disturb
    beq !t18_done+
    lda #$01
    sta tc_results + 18
!t18_done:

    // ----------------------------------------------------------
    // Test 19: Sleeping visible monster during auto-rest (MON-005): stays
    // asleep across monster_ai_tick + monster_update_visibility_all and
    // leaves zp_disturb == 0.
    // ----------------------------------------------------------
    jsr reset_box
    lda #1
    sta auto_rest_active
    lda #2
    sta zp_light_radius
    ldx #12
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #MF_VISIBLE             // Visible but asleep (!MF_AWAKE)
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    lda #50
    sta (zp_ptr0),y
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    jsr monster_update_visibility_all
    lda zp_disturb
    bne !t19_done+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t19_done+
    lda #$01
    sta tc_results + 19
!t19_done:

    // ----------------------------------------------------------
    // Test 20: Door burst (!mts_bash and !mts_stuck) increments zp_disturb
    // even for an unseen monster (MF_VISIBLE == 0); plain closed door open
    // (mts_open_plain) by an unseen opener leaves zp_disturb == 0 in AI.
    // ----------------------------------------------------------
    // Part A: !mts_bash (non-opener) bursts closed door
    jsr reset_box
    ldx #14
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #10
    lda #TILE_DOOR_CLOSED
    jsr set_tile
    ldx #15
    ldy #10
    lda #T_M1                   // cr_aaf = 20 (non-opener)
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #100
    sta (zp_ptr0),y
    jsr patch_rng_word_zero
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    jsr restore_glyph_rng
    ldx #14
    ldy #10
    jsr get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !+
    jmp !t20_done+
!:  lda zp_disturb
    bne !+
    jmp !t20_done+
!:  // Part B: !mts_stuck (door-capable opener) bursts stuck door
    jsr reset_box
    lda #(20 | CD_OPEN_DOOR_BIT)
    sta cr_aaf + T_M1
    ldx #14
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #10
    lda #TILE_DOOR_CLOSED
    jsr set_tile
    lda #14
    sta df_target_x
    lda #10
    sta df_target_y
    lda #$85                    // stuck door (sign bit set)
    jsr door_state_set_at
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #100
    sta (zp_ptr0),y
    jsr patch_rng_word_zero
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    jsr restore_glyph_rng
    ldx #14
    ldy #10
    jsr get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !t20_done+
    lda zp_disturb
    beq !t20_done+
    // Part C: plain closed door open by unseen opener leaves zp_disturb == 0
    jsr reset_box
    lda #(20 | CD_OPEN_DOOR_BIT)
    sta cr_aaf + T_M1
    ldx #14
    ldy #9
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #11
    lda #TILE_WALL_H
    jsr set_tile
    ldx #14
    ldy #10
    lda #TILE_DOOR_CLOSED
    jsr set_tile
    ldx #15
    ldy #10
    lda #T_M1
    jsr spawn_awake
    lda #0
    sta zp_disturb
    jsr monster_ai_tick
    ldx #14
    ldy #10
    jsr get_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !t20_done+
    lda zp_disturb
    bne !t20_done+
    lda #$01
    sta tc_results + 20
!t20_done:

    // ----------------------------------------------------------
    // Test 21: eff_teleport_apply_target moves player, clears PLF_SEARCHING,
    // sets vis_room_revealed, and increments zp_disturb.
    // ----------------------------------------------------------
    jsr reset_box
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda #0
    sta vis_room_revealed
    sta zp_disturb
    lda #20
    ldy #12
    jsr eff_teleport_apply_target
    lda zp_player_x
    cmp #20
    bne !t21_done+
    lda zp_player_y
    cmp #12
    bne !t21_done+
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    bne !t21_done+
    lda vis_room_revealed
    beq !t21_done+
    lda zp_disturb
    cmp #1
    bne !t21_done+
    lda #$01
    sta tc_results + 21
!t21_done:

    // ----------------------------------------------------------
    // Test 22: search_scan_adjacent_silent (!ds_found_common) increments
    // zp_disturb on secret door discovery and trap discovery, and stays quiet
    // when nothing is found.
    // ----------------------------------------------------------
    jsr reset_box
    lda #0
    sta zp_disturb
    lda #100
    jsr search_scan_adjacent_silent
    bcs !t22_done+
    lda zp_disturb
    bne !t22_done+
    // Secret door at (11,10)
    ldx #11
    ldy #10
    lda #TILE_SECRET
    jsr set_tile
    lda #100
    jsr search_scan_adjacent_silent
    bcc !t22_done+
    lda zp_disturb
    cmp #1
    bne !t22_done+
    // Hidden trap at (9,10)
    jsr msg_clear
    lda #0
    sta zp_disturb
    lda #1
    sta trap_count
    lda #9
    sta trap_x
    lda #10
    sta trap_y
    lda #0
    sta trap_type
    lda #100
    jsr search_scan_adjacent_silent
    bcc !t22_done+
    lda zp_disturb
    cmp #1
    bne !t22_done+
    lda #$01
    sta tc_results + 22
!t22_done:

    // ----------------------------------------------------------
    // Test 23: Visible caster casting silent MSF2_BLINK sets mat_action_dirty
    // bit 1 ($03) and increments zp_disturb without printing a message.
    // ----------------------------------------------------------
    jsr reset_box
    lda #1
    sta cr_spell_chance + T_M1  // 1-in-1 cast frequency (always casts)
    lda #0
    sta cr_spell_flags + T_M1
    lda #MSF2_BLINK
    sta cr_spell_flags2 + T_M1
    ldx #13
    ldy #10
    lda #T_M1
    jsr spawn_awake
    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda #(MF_AWAKE | MF_VISIBLE)
    sta (zp_ptr0),y
    lda #0
    sta zp_disturb
    sta zp_msg_flags
    jsr monster_ai_tick
    lda mat_action_dirty
    cmp #$03
    bne !t23_done+
    lda zp_msg_flags
    bne !t23_done+              // Blink is silent (no message)
    lda zp_disturb
    beq !t23_done+              // Still disturbs via visible hostile spell bit 1
    lda #$01
    sta tc_results + 23
!t23_done:

    jmp test_finish

test_end:

.assert "Monster AI2 test body must stay below MAP_BASE", test_end < MAP_BASE, true
