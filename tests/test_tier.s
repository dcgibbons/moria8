// test_tier.s — Runtime tests for tier_manager.s
//
// Tests: tier_check_transition logic (first entry, in-range, step up/down,
//        town, tier 4 cap), load_tier_to_buffer.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test (10 tests)
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $0810 "Test Code"

.encoding "screencode_upper"

// Bootstrap — must be before imports so it's in RAM below $A000.
bootstrap:
    lda $01
    and #%11111110          // Clear bit 0 -> bank out BASIC ROM
    sta $01
    jmp test_start

// test_finish — Copy results to $0400 and halt.
test_finish:
    ldx #9
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

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
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_gen.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../overlay.s"
#import "../monster_ai.s"
#import "../monster_magic.s"
#import "../item.s"
#import "../special_rooms.s"
#import "../ego_items.s"
#import "../special_rooms_stubs.s"
#import "../player_items.s"
#import "../spell_data.s"
#import "../spell_effects.s"
#import "../player_magic.s"
#import "../ui_inventory.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../combat.s"
#import "../monster_attack.s"
#import "../turn.s"
#import "../store_data.s"
#import "../huffman.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"
#import "../ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 12, $ff

test_start:
    // Initialize result area to $ff (untested)
    ldx #9
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Initialize message system (tier_load calls msg_print)
    jsr msg_init

    // Ensure REU is not present (tests are pure logic, no DMA)
    lda #0
    sta reu_present

    // ============================================================
    // Stub tier_load to skip disk/REU loading
    // Replace first 6 bytes with: lda #1 / sta tier_loaded / rts
    // ============================================================
    lda #$a9                    // LDA #imm opcode
    sta tier_load
    lda #$01                    // immediate value: 1
    sta tier_load + 1
    lda #$8d                    // STA abs opcode
    sta tier_load + 2
    lda #<tier_loaded
    sta tier_load + 3
    lda #>tier_loaded
    sta tier_load + 4
    lda #$60                    // RTS opcode
    sta tier_load + 5

    // ============================================================
    // Test 1: First entry DL1 -> tier 1
    // current_tier=0 (no tier), dlvl=1 -> should pick tier 1
    // ============================================================
    lda #0
    sta current_tier
    sta tier_loaded
    lda #1
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #1
    bne !t1_fail+
    lda #$01
    jmp !t1_store+
!t1_fail:
    lda #$00
!t1_store:
    sta tc_results + 0

    // ============================================================
    // Test 2: First entry DL10 -> tier 2
    // ============================================================
    lda #0
    sta current_tier
    sta tier_loaded
    lda #10
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #2
    bne !t2_fail+
    lda #$01
    jmp !t2_store+
!t2_fail:
    lda #$00
!t2_store:
    sta tc_results + 1

    // ============================================================
    // Test 3: First entry DL20 -> tier 3
    // ============================================================
    lda #0
    sta current_tier
    sta tier_loaded
    lda #20
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #3
    bne !t3_fail+
    lda #$01
    jmp !t3_store+
!t3_fail:
    lda #$00
!t3_store:
    sta tc_results + 2

    // ============================================================
    // Test 4: First entry DL30 -> tier 4
    // ============================================================
    lda #0
    sta current_tier
    sta tier_loaded
    lda #30
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #4
    bne !t4_fail+
    lda #$01
    jmp !t4_store+
!t4_fail:
    lda #$00
!t4_store:
    sta tc_results + 3

    // ============================================================
    // Test 5: In-range — no transition needed
    // current_tier=1, dlvl=5 (within 1-8)
    // ============================================================
    lda #1
    sta current_tier
    lda #5
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #1
    bne !t5_fail+
    lda #$01
    jmp !t5_store+
!t5_fail:
    lda #$00
!t5_store:
    sta tc_results + 4

    // ============================================================
    // Test 6: Step up — tier 1->2 at DL9
    // dlvl=9, current_tier=1 (max=8), 9 > 8 -> step to tier 2
    // ============================================================
    lda #1
    sta current_tier
    sta tier_loaded
    lda #9
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #2
    bne !t6_fail+
    lda #$01
    jmp !t6_store+
!t6_fail:
    lda #$00
!t6_store:
    sta tc_results + 5

    // ============================================================
    // Test 7: Step down — tier 2->1 at DL4
    // dlvl=4, current_tier=2 (min=5), 4 < 5 -> step to tier 1
    // ============================================================
    lda #2
    sta current_tier
    sta tier_loaded
    lda #4
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #1
    bne !t7_fail+
    lda #$01
    jmp !t7_store+
!t7_fail:
    lda #$00
!t7_store:
    sta tc_results + 6

    // ============================================================
    // Test 8: Town — no transition
    // dlvl=0, current_tier=2 -> should stay tier 2 (town early-exit)
    // ============================================================
    lda #2
    sta current_tier
    lda #0
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #2
    bne !t8_fail+
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    // ============================================================
    // Test 9: load_tier_to_buffer
    // Write known SoA data to $E000 (bank out KERNAL), then call
    // load_tier_to_buffer(count=3). Verify cr_display[0..2] and
    // active_dungeon_count == 3.
    // ============================================================

    // Bank out KERNAL to write test data at $E000
    sei
    lda $01
    pha
    lda #$35                    // All RAM
    sta $01

    // Fill $E000 with sequential bytes: $41, $42, $43, $44...
    // 22 SoA fields x 3 bytes each = 66 bytes
    ldx #0
    ldy #$41                   // Start value
!t9_fill:
    tya
    sta $e000,x
    iny
    inx
    cpx #66
    bne !t9_fill-

    // Restore KERNAL
    pla
    sta $01
    cli

    // Now call load_tier_to_buffer with zp_ptr0=$E000, A=3
    sei
    lda $01
    pha
    lda #$35
    sta $01

    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    lda #3
    jsr load_tier_to_buffer

    pla
    sta $01
    cli

    // Verify: cr_display[0] = $41, cr_display[1] = $42, cr_display[2] = $43
    // and active_dungeon_count = 3
    lda cr_display
    cmp #$41
    bne !t9_fail+
    lda cr_display + 1
    cmp #$42
    bne !t9_fail+
    lda cr_display + 2
    cmp #$43
    bne !t9_fail+
    lda active_dungeon_count
    cmp #3
    bne !t9_fail+
    // Also verify second array (cr_color): $44, $45, $46
    lda cr_color
    cmp #$44
    bne !t9_fail+
    lda cr_color + 1
    cmp #$45
    bne !t9_fail+
    lda cr_color + 2
    cmp #$46
    bne !t9_fail+
    lda #$01
    jmp !t9_store+
!t9_fail:
    lda #$00
!t9_store:
    sta tc_results + 8

    // ============================================================
    // Test 10: Tier 4 cap — no overflow
    // Part A: current_tier=4, dlvl=50 (within 20-100) -> stays tier 4
    // Part B: current_tier=4, dlvl=101 (>100) -> stays tier 4 (cpx #5 guard)
    // ============================================================
    // Part A: in-range
    lda #4
    sta current_tier
    lda #50
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #4
    bne !t10_fail+

    // Part B: beyond max, but cpx #5 prevents going to tier 5
    lda #4
    sta current_tier
    lda #101
    sta zp_player_dlvl
    jsr tier_check_transition
    lda current_tier
    cmp #4
    bne !t10_fail+

    lda #$01
    jmp !t10_store+
!t10_fail:
    lda #$00
!t10_store:
    sta tc_results + 9

    // ============================================================
    // Done — copy results and halt
    // ============================================================
    jmp test_finish
