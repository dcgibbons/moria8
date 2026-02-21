// test_bash.s — Runtime tests for bash.s
//
// Tests: bash_door (success/fail), bash_monster (hit + HP decrease),
//        bash_stun_check (stun applied), bash_off_balance (paralyze set/safe).
//
// Results at $0400-$0405: $01 = pass, $00 = fail per test (6 tests)
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #5
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#import "../zeropage.s"
#import "../memory.s"
#import "../reu.s"
#import "../screen.s"
#import "../color.s"
#import "../config.s"
#import "../input.s"
#import "../rng.s"
#import "../math.s"
#import "../tables.s"
#import "../item_defs.s"
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_data.s"
#import "../dungeon_gen.s"
#import "../huffman.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../overlay.s"
#import "../monster_ai.s"
#import "../recall.s"
#import "../monster_magic.s"
#import "../item.s"
#import "../special_rooms.s"
#import "../ego_items.s"
#import "../special_rooms_stubs.s"
#import "../player_items.s"
#import "../spell_data.s"
#import "../projectile.s"
#import "../spell_effects.s"
#import "../player_magic.s"
#import "../ui_inventory.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../combat.s"
#import "../ranged_fire.s"
#import "../throw.s"
#import "../bash.s"
#import "../monster_attack.s"
#import "../turn.s"
#import "../store_data.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"
#import "../ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 6, $ff      // Result buffer (copied to $0400 at end)
tc_saved_hp_lo: .byte 0
tc_saved_hp_hi: .byte 0

test_start:
    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Initialize message system
    jsr msg_init

    // Initialize sound (needed to avoid crash on sound_play)
    jsr sound_init

    // Pre-stuff keyboard buffer for -more- prompts
    lda #8
    sta $c6
    lda #$20
    sta $0277
    sta $0278
    sta $0279
    sta $027a
    sta $027b
    sta $027c
    sta $027d
    sta $027e

    // ==========================================
    // Test 1: bash_door_success — STR 18, loop until door opens
    // Set TILE_DOOR_CLOSED at map position (10,10), bash it.
    // STR 18 → rng_range(28), need >= 5 → 23/28 chance per try.
    // Loop up to 50 attempts — at least one should succeed.
    // ==========================================

    // Set up target position
    lda #10
    sta df_target_x
    lda #10
    sta df_target_y

    // Write TILE_DOOR_CLOSED at (10,10) on map
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Set high STR
    lda #18
    sta zp_player_str

    // Clear confusion, fear, paralysis
    lda #0
    sta zp_eff_confuse
    sta eff_fear_timer
    sta zp_eff_paralyze

    // Loop: try bash_door up to 50 times
    lda #50
    sta tc_loop
!t1_loop:
    // Reset tile to TILE_DOOR_CLOSED each iteration
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    // Set bash_save_tile (bash_door reads this)
    lda #TILE_DOOR_CLOSED
    sta bash_save_tile

    // Re-stuff keyboard buffer for msg_print -more- prompts
    lda #8
    sta $c6

    jsr bash_door

    // Check if tile changed to TILE_DOOR_OPEN
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t1_pass+

    dec tc_loop
    bne !t1_loop-
    // All 50 attempts failed — fail
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_pass:
    lda #$01
    sta tc_results + 0

    // ==========================================
    // Test 2: bash_door_fail — STR 3, verify at least one attempt
    //   keeps door closed.
    // STR 3 → rng_range(13), need < 5 → 5/13 chance of fail per try.
    // Loop 50 attempts — at least one should fail (door stays closed).
    // ==========================================
!t2:
    lda #3
    sta zp_player_str

    lda #50
    sta tc_loop
    lda #0
    sta tc_ok                   // Will set to 1 if any attempt fails
!t2_loop:
    // Reset tile to TILE_DOOR_CLOSED
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_DOOR_CLOSED
    sta (zp_ptr0),y

    lda #TILE_DOOR_CLOSED
    sta bash_save_tile

    lda #8
    sta $c6

    jsr bash_door

    // Check if tile is still TILE_DOOR_CLOSED
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t2_next+
    // Door stayed closed — this is a successful fail!
    lda #1
    sta tc_ok
!t2_next:
    dec tc_loop
    bne !t2_loop-

    lda tc_ok
    sta tc_results + 1

    // ==========================================
    // Test 3: bash_monster_hit — Set up monster, bash it, verify HP decreased
    // Create a monster with HP=20 in slot 0. Set STR=18, equip shield.
    // bash_monster should hit at least once in 30 attempts.
    // ==========================================
!t3:
    jsr monster_init_table

    // Place monster at position (11,10) — same row as player
    lda #10
    sta zp_player_x
    sta zp_player_y

    // Create monster in slot 0
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold (type 4, cr_ac=16)
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #20
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y

    lda #1
    sta zp_mon_count

    // Set STR=18
    lda #18
    sta zp_player_str

    // Equip Small Shield (type 9, weight=50) in shield slot
    lda #9
    sta inv_item_id + EQUIP_SHIELD

    // Set player level (needed for combat)
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS

    // Loop up to 30 attempts — bash_monster directly
    lda #30
    sta tc_loop
    lda #0
    sta tc_ok
!t3_loop:
    // Re-stuff keyboard buffer
    lda #8
    sta $c6

    // Restore monster HP to 20 if it's alive, or reinit
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t3_still_alive+
    // Monster was killed, reinit
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y
!t3_still_alive:
    ldy #MX_HP_LO
    lda #20
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    // Set up cmb_slot for bash_monster (it expects X = slot)
    ldx #0
    stx cmb_slot

    // Call bash_monster (it reads X from stack entry, but actually
    // it does stx cmb_slot itself — we just need X=0 on entry)
    jsr bash_monster

    // Check if HP decreased from 20
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #20
    bcs !t3_next+              // HP >= 20 → miss, try again
    // HP < 20 → hit!
    lda #1
    sta tc_ok
    jmp !t3_done+
!t3_next:
    dec tc_loop
    bne !t3_loop-
!t3_done:
    lda tc_ok
    sta tc_results + 2

    // ==========================================
    // Test 4: bash_stun_check — Weak monster, verify MX_STUN > 0
    // Use type 1 (Fruit Bat): cr_hd_num=1, cr_hd_sides=3, cr_ac=4.
    // Set HP=2 (low). bash_power = 25 + rng(100) + rng(100) ∈ [25,223].
    // mon_hp_q = 2/4 = 0. avg_max_q = 1*(3+1)/8 = 0.
    // mon_tough = 0 + 0 = 0. bash_power (25-223) > 0 → always stuns!
    // ==========================================
!t4:
    jsr monster_init_table

    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1                      // Fruit Bat
    sta (zp_ptr0),y
    ldy #MX_X
    lda #11
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #2
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #0
    sta (zp_ptr0),y

    lda #1
    sta zp_mon_count

    // Set combat variables for bash_stun_check
    lda #0
    sta cmb_slot
    lda #1
    sta cmb_type                // Fruit Bat

    // Re-stuff keyboard buffer
    lda #8
    sta $c6

    jsr bash_stun_check

    // Check MX_STUN > 0
    ldx #0
    jsr monster_get_ptr
    ldy #MX_STUN
    lda (zp_ptr0),y
    cmp #1
    bcs !t4_pass+
    lda #$00
    sta tc_results + 3
    jmp !t5+
!t4_pass:
    lda #$01
    sta tc_results + 3

    // ==========================================
    // Test 5: bash_off_balance — Low DEX, run 50 times.
    // DEX=3. rng_range(150) returns [0,149].
    // Off-balance if roll > DEX (i.e., roll > 3).
    // Chance: 146/150 ≈ 97% per try. At least one in 50 should trigger.
    // Verify zp_eff_paralyze > 0 at least once.
    // ==========================================
!t5:
    lda #3
    sta zp_player_dex

    lda #50
    sta tc_loop
    lda #0
    sta tc_ok
!t5_loop:
    lda #0
    sta zp_eff_paralyze

    jsr bash_off_balance

    lda zp_eff_paralyze
    beq !t5_next+
    // Paralyzed! Success.
    lda #1
    sta tc_ok
    jmp !t5_done+
!t5_next:
    dec tc_loop
    bne !t5_loop-
!t5_done:
    lda tc_ok
    sta tc_results + 4

    // ==========================================
    // Test 6: bash_off_balance_safe — High DEX, run 50 times.
    // DEX=150 (well, max stat is 18, but zp_player_dex is just a byte).
    // Actually: rng_range(150) returns [0,149]. If DEX >= 150 then
    // roll is always < DEX → always safe. But DEX caps at 18.
    // DEX=18 → roll > 18 fails (131/150 ≈ 87%). Not guaranteed safe.
    //
    // Instead: Verify that with DEX=18, at least one trial stays safe
    // (roll <= 18 → 19/150 ≈ 13% → in 50 tries, P(all fail) = 0.87^50 ≈ 0.001).
    // ==========================================
!t6:
    lda #18
    sta zp_player_dex

    lda #50
    sta tc_loop
    lda #0
    sta tc_ok
!t6_loop:
    lda #0
    sta zp_eff_paralyze

    jsr bash_off_balance

    lda zp_eff_paralyze
    bne !t6_next+
    // Stayed balanced! Success.
    lda #1
    sta tc_ok
    jmp !t6_done+
!t6_next:
    dec tc_loop
    bne !t6_loop-
!t6_done:
    lda tc_ok
    sta tc_results + 5

!tests_done:
    jmp test_exit_trampoline
