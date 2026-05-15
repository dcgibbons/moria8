#importonce
// player_create.s — Character creation flow
//
// 1. Race selection
// 2. Class selection (filtered by race)
// 3. Stat rolling (umoria: d3+d4+d5 per stat, constrained total, increment/decrement modifiers)
// 4. Name entry (max 16 chars, uppercase only)
// 5. Gender selection
// 6. Background generation (social class + flavor text)
// 7. Initialize starting HP, mana, gold, food, position

#import "platform_services_api.s"

// Starting values
.const START_FOOD_LO  = <2000  // 2000 turns of food (lo = $D0)
.const START_FOOD_HI  = >2000  // (hi = $07)
.const START_LIGHT    = 1    // Starting light radius (torch)

// ============================================================
// Subroutines
// ============================================================

// player_create — Full character creation flow
// Output: player_data struct fully initialized
// Preserves: nothing
//
// Incident-scoped cutpoints are kept here for chargen bisection because they
// were high-signal during the overlay/payload failure investigation. The normal
// build uses C128_CHARGEN_CUTPOINT=-1, so none of these early returns fire.
#if !C128
.const C128_CHARGEN_CUTPOINT = -1
#endif

player_create:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$72
    jsr c128_town_dump_mark
#endif
    .if (C128_CHARGEN_CUTPOINT == -2) { rts }
    jsr player_init
    .if (C128_CHARGEN_CUTPOINT == 0) { rts }

    jsr create_select_race
    .if (C128_CHARGEN_CUTPOINT == 1) { rts }
    jsr create_roll_stats
    .if (C128_CHARGEN_CUTPOINT == 2) { rts }
    jsr create_select_class
    .if (C128_CHARGEN_CUTPOINT == 3) { rts }
    jsr create_enter_name
    .if (C128_CHARGEN_CUTPOINT == 4) { rts }
    jsr create_select_gender
    .if (C128_CHARGEN_CUTPOINT == 5) { rts }
#if C128
    jsr hal_platform_runtime_resync
#endif
    .if (C128_CHARGEN_CUTPOINT == 6) { rts }
    jsr create_gen_background
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardCheck($89)
#endif
#if C128
    jsr hal_platform_runtime_resync
#endif
    .if (C128_CHARGEN_CUTPOINT == 7) { rts }
    jsr create_init_character
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardCheck($8a)
#endif
#if C128
#if C128_TEST_FINAL_RETURN_DIAG
    :C128FinalReturnCapture($92)
#endif
    jsr hal_platform_runtime_resync
#if C128_TEST_FINAL_RETURN_DIAG
    :C128FinalReturnCapture($93)
#endif
#endif
    .if (C128_CHARGEN_CUTPOINT == 8) { jmp player_create_epilogue }

player_create_epilogue:
#if C128_TEST_FINAL_RETURN_DIAG
    :C128FinalReturnCapture($94)
    :C128FinalReturnCheck($95)
#endif
    rts

// ============================================================
// Race selection
// ============================================================
create_select_race:
    // Use the platform-safe full-screen clear helper:
    // C64 keeps row-by-row, C128 takes the bulk-clear fast path.
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_clear_full_screen_safe

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #11
    sta zp_cursor_col
    lda #<create_race_title
    sta zp_ptr0
    lda #>create_race_title
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // List races with letter keys a-h
    ldx #0                  // Race index
!race_loop:
    txa
    pha

    // Row = index + 2
    clc
    adc #2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    // Print letter (A-H) — screen code $01-$08
    lda #COL_LGREY
    sta zp_text_color
    pla
    pha
    clc
    adc #$01                // A=01, B=02, etc.
    jsr hal_screen_put_char

    // ") "
    lda #$29                // ')'
    jsr hal_screen_put_char
    lda #$20                // space
    jsr hal_screen_put_char

    // Race name
    lda #COL_WHITE
    sta zp_text_color
    pla
    pha
    tax
    lda race_name_ptrs_lo,x
    sta zp_ptr0
    lda race_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    pla
    tax
    inx
    cpx #RACE_COUNT
    bcc !race_loop-

    // Prompt: "CHOOSE (A-H)"
    lda #COL_LGREY
    sta zp_text_color
    lda #12
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col
    lda #<create_choose_str
    sta zp_ptr0
    lda #>create_choose_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    // Append final letter and closing paren
    lda #RACE_COUNT         // 8 options → last letter = 'H'
    jsr put_choose_suffix

    // Wait for valid key (A-H = PETSCII $41-$48)
!race_key:
    jsr input_get_key
    sec
    sbc #$41                // Convert PETSCII 'A' to index 0
    bmi !race_key-          // < 'A'
    cmp #RACE_COUNT
    bcs !race_key-          // >= RACE_COUNT

    sta player_data + PL_RACE
    rts

// ============================================================
// Class selection (filtered by race)
// ============================================================
create_select_class:
    jsr hal_screen_clear

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #<create_class_title
    sta zp_ptr0
    lda #>create_class_title
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Get race class restriction bitmask
    ldx player_data + PL_RACE
    lda race_class_flags,x
    sta zp_temp2            // Allowed class bitmask

    // List allowed classes
    // Use ZP variables instead of X/Y — screen routines clobber both
    lda #0
    sta zp_temp3            // Class index (0..CLASS_COUNT-1)
    sta zp_temp4            // Display row counter / valid class count

!class_loop:
    // Check if this class is allowed
    ldx zp_temp3
    lda #1
!shift:
    cpx #0
    beq !check+
    asl
    dex
    jmp !shift-
!check:
    and zp_temp2            // Test bit
    beq !class_next+        // Not allowed, skip

    // Display this class
    lda zp_temp4
    clc
    adc #2                  // Row = display_row + 2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    // Store mapping: display position → class index
    ldx zp_temp4
    lda zp_temp3
    sta create_class_map,x

    // Letter
    lda #COL_LGREY
    sta zp_text_color
    lda zp_temp4
    clc
    adc #$01                // A, B, C...
    jsr hal_screen_put_char
    lda #$29                // ')'
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char

    // Class name
    lda #COL_WHITE
    sta zp_text_color
    ldx zp_temp3
    lda class_name_ptrs_lo,x
    sta zp_ptr0
    lda class_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    inc zp_temp4            // Next display row

!class_next:
    inc zp_temp3
    lda zp_temp3
    cmp #CLASS_COUNT
    bcc !class_loop-

    // zp_temp4 = number of valid classes displayed
    // Prompt: "CHOOSE (A-X)" where X = last valid letter
    lda #COL_LGREY
    sta zp_text_color
    lda zp_temp4
    clc
    adc #3
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col
    lda #<create_choose_str
    sta zp_ptr0
    lda #>create_choose_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda zp_temp4            // Number of valid classes
    jsr put_choose_suffix

    // Wait for valid key
!class_key:
    jsr input_get_key
    sec
    sbc #$41                // Convert to index
    bmi !class_key-
    cmp zp_temp4            // Compare to count of displayed classes
    bcs !class_key-

    // Look up actual class index from display map
    tax
    lda create_class_map,x
    sta player_data + PL_CLASS
    rts

// Mapping table: display position → class index
create_class_map:
    .fill CLASS_COUNT, 0

// ============================================================
// Stat rolling
// ============================================================
create_roll_stats:
!reroll:
    jsr hal_screen_clear

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #12
    sta zp_cursor_col
    lda #<create_stats_title
    sta zp_ptr0
    lda #>create_stats_title
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Roll stats using umoria algorithm:
    // Per stat: d3 + d4 + d5 + 5 (range 8-17)
    // Constraint: sum of all 6 stats must be 73-84
    // zp_temp0 = running stat total (safe across math_dice)
!reroll_all:
    lda #0
    sta zp_temp0            // Stat total accumulator
    ldx #0                  // Stat index
!roll_loop:
    txa
    pha                     // Save stat index on stack

    // Roll d3
    lda #1
    ldx #3
    ldy #0
    jsr math_dice
    lda zp_math_a
    pha                     // Push d3 result

    // Roll d4
    lda #1
    ldx #4
    ldy #0
    jsr math_dice
    lda zp_math_a
    pha                     // Push d4 result

    // Roll d5
    lda #1
    ldx #5
    ldy #0
    jsr math_dice

    // Sum: d3 + d4 + d5 + 5
    pla                     // d4
    clc
    adc zp_math_a           // d4 + d5
    sta zp_math_a
    pla                     // d3
    clc
    adc zp_math_a           // d3 + d4 + d5
    clc
    adc #5                  // + 5 = stat value (range 8-17)
    sta zp_temp1            // Save stat value (safe across math_dice)

    // Store base stat
    pla                     // stat index
    tax
    pha                     // re-save stat index
    lda zp_temp1            // Retrieve stat value
    sta player_data + PL_STR_BASE,x

    // Accumulate total
    clc
    adc zp_temp0
    sta zp_temp0

    pla
    tax
    inx
    cpx #STAT_COUNT
    bcc !roll_loop-

    // Check constraint: stat total must be 73-84
    lda zp_temp0
    cmp #73
    bcc !reroll_all-        // Total < 73, re-roll
    cmp #85
    bcs !reroll_all-        // Total > 84, re-roll

    // Display each stat
    ldx #0
!display_loop:
    txa
    pha

    // Row = stat_index + 2, col 3
    txa
    clc
    adc #2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    // Stat name
    pla
    tax
    pha
    lda #COL_LGREY
    sta zp_text_color
    lda stat_name_ptrs_lo,x
    sta zp_ptr0
    lda stat_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // ":"
    lda #$3a
    jsr hal_screen_put_char

    // Base value (right-justified, always 8-17)
    lda #COL_WHITE
    sta zp_text_color
    pla
    tax
    pha
    lda player_data + PL_STR_BASE,x
    jsr put_stat_val

    // Show race-modified value in parens
    pla
    tax
    pha
    jsr create_calc_modified_stat  // A = modified stat (single-byte encoding)
    pha                     // Save modified stat

    lda #$20                // space
    jsr hal_screen_put_char
    lda #$28                // '('
    jsr hal_screen_put_char

    lda #COL_CYAN
    sta zp_text_color
    pla                     // Modified stat value
    jsr put_stat_val

    lda #COL_LGREY
    sta zp_text_color
    lda #$29                // ')'
    jsr hal_screen_put_char

    pla
    tax
    inx
    cpx #STAT_COUNT
    bcc !display_loop-

    // Prompt: R to reroll, ENTER to accept
    lda #COL_LGREY
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col
    lda #<create_reroll_str
    sta zp_ptr0
    lda #>create_reroll_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

!stat_key:
    jsr input_get_key
    cmp #$52                // 'R' — reroll
    bne !not_reroll+
    jmp !reroll-            // Too far for beq, use JMP
!not_reroll:
    cmp #$0d                // RETURN — accept
    bne !stat_key-
    rts

// create_calc_modified_stat — Calculate stat with race modifiers only
// Called during stat rolling (before class selection).
// Uses umoria incrementStat/decrementStat for each +1/-1 of the modifier.
// Input: X = stat index (0–5)
// Output: A = modified stat (single-byte encoding, 3–118)
// Preserves: X
create_calc_modified_stat:
    stx zp_temp1            // Save stat index (safe across math_dice)

    // Start with base stat
    lda player_data + PL_STR_BASE,x
    sta stat_work

    // Race adj offset = race * 6 + stat_index
    lda player_data + PL_RACE
    asl
    sta zp_temp2
    asl
    clc
    adc zp_temp2            // race * 6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda race_stat_adj,x     // Signed modifier
    jsr apply_modifier

    lda stat_work
    ldx zp_temp1            // Restore X
    rts

// ============================================================
// Name entry
// ============================================================
create_enter_name:
    jsr hal_screen_clear

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #<create_name_title
    sta zp_ptr0
    lda #>create_name_title
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col
    lda #<create_name_prompt
    sta zp_ptr0
    lda #>create_name_prompt
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Input cursor on row 4
    lda #4
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    lda #COL_WHITE
    sta zp_text_color

    lda #0
    sta cen_count           // Character count (X clobbered by GETIN)
!name_loop:
    jsr input_get_key
    ldx cen_count           // Restore count after GETIN

    // RETURN = accept (if at least 1 char)
    cmp #$0d
    bne !not_return+
    cpx #0
    beq !name_loop-         // Empty name, keep waiting
    jmp !name_done+
!not_return:

    // DEL/backspace = $14 (PETSCII DELETE)
    cmp #$14
    bne !not_del+
    cpx #0
    beq !name_loop-         // Nothing to delete
    dex
    stx cen_count
    // Erase char on screen
    dec zp_cursor_col
    lda #$20                // Space
    jsr hal_screen_put_char
    dec zp_cursor_col        // Move back again
    jmp !name_loop-
!not_del:

    // Check if it's a letter
    // Unshifted (PETSCII $41-$5A) → lowercase screen codes ($01-$1A)
    cmp #$41
    bcc !check_shifted+
    cmp #$5b
    bcs !check_shifted+
    sec
    sbc #$40                // $41→$01 (lowercase a)
    jmp !store_char+
!check_shifted:
    // Shifted (PETSCII $C1-$DA) → uppercase screen codes ($41-$5A)
    cmp #$c1
    bcc !check_other+
    cmp #$db
    bcs !check_other+
    and #$3f                // $C1→$01
    ora #$40                // $01→$41 (uppercase A)
    jmp !store_char+

!check_other:
    // Allow space ($20) and hyphen ($2D) and digits ($30-$39)
    cmp #$20                // Space
    beq !store_sc+
    cmp #$2d                // Hyphen '-'
    beq !store_sc+
    cmp #$30
    bcc !name_loop-
    cmp #$3a
    bcs !name_loop-
    // Digit — screen code same as PETSCII for $30-$39
!store_sc:
    // Screen code = same for these characters
    jmp !store_char+

!store_char:
    // Check max length
    cpx #16
    bcs !name_loop-         // Name full

    // Store screen code in player name
    sta player_data + PL_NAME,x
    // Display it
    jsr hal_screen_put_char
    inx
    stx cen_count
    jmp !name_loop-

!name_done:
    // Null-terminate
    lda #0
    sta player_data + PL_NAME,x
    rts

cen_count: .byte 0          // Name char count (survives GETIN clobber)

// ============================================================
// Initialize character
// ============================================================
create_init_character:
    // Level 1
    lda #1
    sta player_data + PL_LEVEL

    // Dungeon level 0 (town)
    lda #0
    sta player_data + PL_DLEVEL

    // Calculate stats with modifiers
#if C128_REAL_BOOT_DIAG
    ldx #$71
    jsr c128_stack_guard_begin
#endif
    jsr player_calc_stats
#if C128_REAL_BOOT_DIAG
    ldx #$72
    jsr c128_stack_guard_check
#endif

    // Calculate max HP
#if C128_REAL_BOOT_DIAG
    ldx #$73
    jsr c128_stack_guard_begin
#endif
    jsr player_calc_hp
#if C128_REAL_BOOT_DIAG
    ldx #$74
    jsr c128_stack_guard_check
#endif
    // Set current HP = max HP
    lda player_data + PL_MHP_LO
    sta player_data + PL_HP_LO
    lda player_data + PL_MHP_HI
    sta player_data + PL_HP_HI

    // Calculate mana (for spell-casting classes)
    lda player_data + PL_CLASS
    tax
    lda #CLASS_PROP_SIZE
    jsr mul_x_by_a
    tax
    lda class_properties + 1,x  // Spell type
    sta player_data + PL_SPELL_TYPE
    beq !no_mana+           // No spells = no mana

    ldx player_data + PL_CLASS
    lda class_spell_min_level,x
    cmp player_data + PL_LEVEL
    beq !can_cast_start+
    bcc !can_cast_start+
    jmp !no_mana+

    // Starting mana = spell stat / 2 (INT for mage affinity, WIS for priest)
!can_cast_start:
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    bne !priest_mana+
    lda player_data + PL_INT_CUR
    jmp !calc_mana+
!priest_mana:
    lda player_data + PL_WIS_CUR
!calc_mana:
    lsr                     // / 2
    cmp #1
    bcs !mana_ok+
    lda #1                  // Minimum 1 mana
!mana_ok:
    sta player_data + PL_MAX_MANA
    sta player_data + PL_MANA
    jmp !mana_done+
!no_mana:
    lda #0
    sta player_data + PL_MAX_MANA
    sta player_data + PL_MANA
!mana_done:

    // Starting gold — umoria formula based on social class, stats, gender
#if C128_REAL_BOOT_DIAG
    ldx #$75
    jsr c128_stack_guard_begin
#endif
    jsr create_calc_gold
#if C128_REAL_BOOT_DIAG
    ldx #$76
    jsr c128_stack_guard_check
#endif

    // Experience factor = race_xp% + class_xp% (range 100-165)
    ldx player_data + PL_RACE
    lda #RACE_PROP_SIZE
    jsr mul_x_by_a
    tax
    lda race_properties + 2,x      // Race XP%
    sta player_data + PL_EXPFACT
    ldx player_data + PL_CLASS
    lda #CLASS_PROP_SIZE
    jsr mul_x_by_a
    tax
    lda class_properties + 2,x     // Class XP%
    clc
    adc player_data + PL_EXPFACT
    sta player_data + PL_EXPFACT

    // Starting XP = 0
    lda #0
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    // Food
    lda #START_FOOD_LO
    sta player_data + PL_FOOD_LO
    lda #START_FOOD_HI
    sta player_data + PL_FOOD_HI
    lda #HUNGER_FULL
    sta player_data + PL_HUNGER

    // Light
    lda #START_LIGHT
    sta player_data + PL_LIGHT_RAD

    // Starting position is set by town_generate (called after player_create)

    // Flags: gender already set by create_select_gender

    // Sync to ZP
#if C128_REAL_BOOT_DIAG
    ldx #$77
    jsr c128_stack_guard_begin
#endif
    jsr player_sync_to_zp
#if C128_REAL_BOOT_DIAG
    ldx #$78
    jsr c128_stack_guard_check
#endif

    // player_init already zeroes the widened spell-state and sets spell order to 99.
    ldx player_data + PL_CLASS
    lda #$07                    // Priest/paladin start with prayers 0-2
    ldy #2
    cpx #CLASS_MAGE
    bne !not_start_mage+
    lda #$0f                    // Mage starts with spells 0-3
    ldy #3
    bne !store_start_spells+
!not_start_mage:
    cpx #CLASS_PRIEST
    beq !store_start_spells+
    cpx #CLASS_PALADIN
    bne !no_start_spells+
!store_start_spells:
    sta player_data + PL_SPELLS_LEARNT_0
!spell_order_loop:
    tya
    sta player_data + PL_SPELL_ORDER,y
    dey
    bpl !spell_order_loop-
!no_start_spells:

    // Initialize HP regen counter from CON
    lda player_data + PL_CON_CUR
    sec
    sbc #3                      // Index = CON - 3
    tax
    lda regen_rate,x
    sta zp_regen_counter

    // Pseudo-ID rate based on class
    ldx player_data + PL_CLASS
    lda pid_class_rate,x
    sta player_data + PL_RESERVED

    rts

// Pseudo-ID class rates (turns between pseudo-ID attempts)
// Warrior=50, Mage=150, Priest=100, Rogue=75, Ranger=75, Paladin=100
pid_class_rate:
    .byte 50, 150, 100, 75, 75, 100

// put_stat_val — extracted to stat_display.s (main RAM, always accessible)

// put_choose_suffix — Append final letter and ")" to "CHOOSE (A-" prompt
// Input: A = count of options (e.g., 8 → prints "H)")
// Cursor must be positioned after the "A-" part of the string.
// Preserves: nothing
put_choose_suffix:
    // Convert count to last letter screen code: count-1 + $01 (A=$01)
    sec
    sbc #1
    clc
    adc #$01                // A=$01, B=$02, ..., H=$08
    jsr hal_screen_put_char
    lda #$29                // ')'
    jsr hal_screen_put_char
    rts

// ============================================================
// String data (screen codes)
// ============================================================
create_race_title:
    .text "Choose your race" ; .byte $00
create_class_title:
    .text "Choose your class" ; .byte $00
create_stats_title:
    .text "Roll Statistics" ; .byte $00
create_name_title:
    .text "Enter your name" ; .byte $00
create_choose_str:
    .text "Choose (a-" ; .byte $00
create_reroll_str:
    .text "r) Reroll  RETURN) Accept" ; .byte $00
create_name_prompt:
    .text "Name (16 chars max):" ; .byte $00
create_gender_title:
    .text "Choose your gender" ; .byte $00
create_gender_m:
    .text "a) Male" ; .byte $00
create_gender_f:
    .text "b) Female" ; .byte $00

// ============================================================
// Gender selection
// ============================================================
create_select_gender:
    // Use the same platform-safe full-screen clear helper as the other
    // creation screens.
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_clear_full_screen_safe

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #<create_gender_title
    sta zp_ptr0
    lda #>create_gender_title
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Option A) Male
    lda #COL_LGREY
    sta zp_text_color
    lda #2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col
    lda #<create_gender_m
    sta zp_ptr0
    lda #>create_gender_m
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // Option B) Female
    lda #3
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col
    lda #<create_gender_f
    sta zp_ptr0
    lda #>create_gender_f
    sta zp_ptr0_hi
    jsr hal_screen_put_string

!gender_key:
    jsr input_get_key
    cmp #$41                // 'A' — male
    beq !gender_male+
    cmp #$61                // 'a' — male (lowercase PETSCII, e.g. C64 lowercase mode)
    beq !gender_male+
    cmp #$42                // 'B' — female
    beq !gender_female+
    cmp #$62                // 'b' — female (lowercase PETSCII)
    beq !gender_female+
    jmp !gender_key-
!gender_male:
    lda #PLF_MALE
    sta player_data + PL_FLAGS
    jsr input_wait_release
    rts
!gender_female:
    lda #0
    sta player_data + PL_FLAGS
    jsr input_wait_release
    rts

// ============================================================
// Background generation — chain walker
// Walks umoria background charts, accumulates text + social class.
// Output: player_background filled, PL_SOCIAL_CLASS set.
// ============================================================

// Scratch variables (overlay-local)
bg_history_id: .byte 0     // Current chart ID
bg_text_len:   .byte 0     // Current length in bg_text_buf
bg_sc_lo:      .byte 0     // Social class accumulator (16-bit signed)
bg_sc_hi:      .byte 0
bg_scan_idx:   .byte 0     // Current scan index
bg_roll_val:   .byte 0     // Current d100 roll result

create_gen_background:
    // Initialize social class = rng_range(4) + 1 → [1, 4]
    lda #4
    jsr rng_range           // A = [0, 3]
    clc
    adc #1                  // A = [1, 4]
    sta bg_sc_lo
    lda #0
    sta bg_sc_hi
    sta bg_text_len

    // Starting chart = bg_race_start[race]
    ldx player_data + PL_RACE
    lda bg_race_start,x
    sta bg_history_id

!bg_chain_loop:
    // Find first entry where bg_chart[idx] == history_id
    ldx #0
!bg_find_chart:
    lda bg_chart,x
    cmp bg_history_id
    beq !bg_found_chart+
    inx
    cpx #BG_ENTRY_COUNT
    bcc !bg_find_chart-
    jmp !bg_chain_done+     // Should never happen — safety exit

!bg_found_chart:
    stx bg_scan_idx

    // Roll d100: rng_range(100) + 1 → [1, 100]
    lda #100
    jsr rng_range           // A = [0, 99]
    clc
    adc #1                  // A = [1, 100]
    sta bg_roll_val

    // Scan forward until bg_roll[idx] >= roll
    ldx bg_scan_idx
!bg_roll_scan:
    lda bg_roll,x
    cmp bg_roll_val
    bcs !bg_roll_match+     // bg_roll >= roll → match
    inx
    jmp !bg_roll_scan-      // Always terminates — last entry in chart has roll=100

!bg_roll_match:
    // Append string at bg_str[x] to bg_text_buf
    stx bg_scan_idx         // Save matched index
    lda bg_str_lo,x
    sta zp_ptr0
    lda bg_str_hi,x
    sta zp_ptr0_hi
    ldx bg_text_len
    ldy #0
!bg_copy_str:
    lda (zp_ptr0),y
    beq !bg_copy_done+
    cpx #199                // Reserve final byte for null terminator
    bcs !bg_copy_done+
    sta bg_text_buf,x
    inx
    iny
    jmp !bg_copy_str-
!bg_copy_done:
    stx bg_text_len

    // Accumulate social class: sc += bonus[idx] - 50
    ldx bg_scan_idx
    lda bg_bonus,x
    sec
    sbc #50                 // A = signed adjustment (-40 to +100)
    bmi !bg_sc_neg+
    // Positive or zero adjustment
    clc
    adc bg_sc_lo
    sta bg_sc_lo
    bcc !bg_sc_ok+
    inc bg_sc_hi
    jmp !bg_sc_ok+
!bg_sc_neg:
    // Negative adjustment: sign-extend, add
    clc
    adc bg_sc_lo
    sta bg_sc_lo
    lda bg_sc_hi
    adc #$ff                // Sign-extend negative
    sta bg_sc_hi
!bg_sc_ok:

    // Follow chain: next = bg_next[idx]
    ldx bg_scan_idx
    lda bg_next,x
    beq !bg_chain_done+     // next == 0 → end of chain
    sta bg_history_id
    jmp !bg_chain_loop-

!bg_chain_done:
    // Null-terminate text buffer
    ldx bg_text_len
    cpx #200
    bcc !bg_text_term_ok+
    ldx #199
    stx bg_text_len
!bg_text_term_ok:
    lda #0
    sta bg_text_buf,x

    // Clamp social class to [1, 100]
    // Check if negative (hi byte has bit 7 set or hi != 0 with negative)
    lda bg_sc_hi
    bmi !bg_sc_clamp_lo+    // Negative → clamp to 1
    bne !bg_sc_clamp_hi+    // Hi > 0 → clamp to 100
    // Hi == 0, check lo
    lda bg_sc_lo
    cmp #1
    bcc !bg_sc_clamp_lo+    // < 1 → clamp to 1
    cmp #101
    bcc !bg_sc_store+        // 1-100 → valid
!bg_sc_clamp_hi:
    lda #100
    jmp !bg_sc_store+
!bg_sc_clamp_lo:
    lda #1
!bg_sc_store:
    sta player_data + PL_SOCIAL_CLASS

    // Word-wrap text into player_background
    jsr bg_word_wrap
    rts

// ============================================================
// bg_word_wrap — Wrap bg_text_buf into player_background
// Input: bg_text_buf (null-terminated), bg_text_len
// Output: player_background filled (4 lines x 40 bytes)
// ============================================================
.const BG_LINE_WIDTH = 38   // Max visible chars per line
.const BG_LINE_STRIDE = 40  // Bytes per line in player_background

bg_wrap_src:  .byte 0       // Current source offset in bg_text_buf
bg_wrap_line: .byte 0       // Current output line (0-3)

bg_word_wrap:
    lda #0
    sta bg_wrap_src
    sta bg_wrap_line

!bgw_next_line:
    lda bg_wrap_line
    cmp #4
    bcc !bgw_not_full+
    jmp !bgw_done+          // All 4 lines filled
!bgw_not_full:

    // Skip leading spaces
!bgw_skip_space:
    ldx bg_wrap_src
    lda bg_text_buf,x
    bne !bgw_not_end+
    jmp !bgw_done+          // End of text
!bgw_not_end:
    cmp #$20                // Space
    bne !bgw_no_skip+
    inc bg_wrap_src
    jmp !bgw_skip_space-
!bgw_no_skip:

    // Calculate remaining text length
    ldx bg_wrap_src
    lda #0
    sta zp_temp0            // Remaining count
!bgw_count:
    lda bg_text_buf,x
    beq !bgw_counted+
    inc zp_temp0
    inx
    jmp !bgw_count-
!bgw_counted:

    // Calculate dest pointer: player_background + line * 40
    lda bg_wrap_line
    asl                     // *2
    asl                     // *4
    asl                     // *8
    sta zp_temp1
    asl                     // *16
    asl                     // *32
    clc
    adc zp_temp1            // *32 + *8 = *40
    clc
    adc #<player_background
    sta zp_ptr1
    lda #>player_background
    adc #0
    sta zp_ptr1 + 1

    // If remaining <= BG_LINE_WIDTH, copy all and done
    lda zp_temp0
    cmp #BG_LINE_WIDTH + 1
    bcs !bgw_need_break+

    // Copy remaining text to this line
    ldx bg_wrap_src
    ldy #0
!bgw_copy_rest:
    lda bg_text_buf,x
    beq !bgw_null_rest+
    sta (zp_ptr1),y
    inx
    iny
    jmp !bgw_copy_rest-
!bgw_null_rest:
    // Null-terminate and trim trailing spaces
    jsr bgw_trim_line
    jmp !bgw_done+          // All text consumed

!bgw_need_break:
    // Find word break: scan backward from position BG_LINE_WIDTH for space
    lda bg_wrap_src
    clc
    adc #BG_LINE_WIDTH
    tax                     // X = src + BG_LINE_WIDTH (position past line end)
!bgw_scan_back:
    cpx bg_wrap_src
    beq !bgw_force_break+   // No space found — force break at BG_LINE_WIDTH
    dex
    lda bg_text_buf,x
    cmp #$20                // Space
    beq !bgw_found_break+
    jmp !bgw_scan_back-

!bgw_force_break:
    // No word break found — break at exactly BG_LINE_WIDTH
    lda bg_wrap_src
    clc
    adc #BG_LINE_WIDTH
    tax
    jmp !bgw_do_copy+

!bgw_found_break:
    // X = position of space (break point)
    inx                     // Break AFTER the space (next line starts after it)

!bgw_do_copy:
    // Copy from bg_wrap_src to X-1 into dest line
    stx zp_temp1            // Save break position
    ldx bg_wrap_src
    ldy #0
!bgw_copy_line:
    cpx zp_temp1
    bcs !bgw_line_done+
    lda bg_text_buf,x
    sta (zp_ptr1),y
    inx
    iny
    jmp !bgw_copy_line-
!bgw_line_done:
    // Null-terminate and trim trailing spaces
    jsr bgw_trim_line
    // Advance source
    lda zp_temp1
    sta bg_wrap_src
    inc bg_wrap_line
    jmp !bgw_next_line-

!bgw_done:
    rts

// bgw_trim_line — Null-terminate line, trim trailing spaces
// Input: zp_ptr1 = line start, Y = length written
// Clobbers: A, Y
bgw_trim_line:
    // Scan backward to trim trailing spaces
!bgw_trim:
    cpy #0
    beq !bgw_null+
    dey
    lda (zp_ptr1),y
    cmp #$20
    beq !bgw_trim-
    iny                     // Keep the non-space char
!bgw_null:
    lda #0
    sta (zp_ptr1),y
    rts

// ============================================================
// Gold formula — umoria starting gold based on social class, stats, gender
// gold = SC*6 + rng(25)+326 - 5*(STR+INT+WIS+DEX+CON-CHR-50) + (female?50:0)
// min 80
// Must be called AFTER player_calc_stats (current stats needed).
// ============================================================

// Scratch variables for gold calculation
gold_lo:       .byte 0
gold_hi:       .byte 0
gold_stat_adj: .byte 0     // Net stat adjustment (signed 8-bit)

// Stat offsets for the 5 "subtract" stats (STR, INT, WIS, DEX, CON)
gold_stat_offsets:
    .byte PL_STR_CUR, PL_INT_CUR, PL_WIS_CUR, PL_DEX_CUR, PL_CON_CUR

create_calc_gold:
    // Step 1: gold = social_class * 6
    lda player_data + PL_SOCIAL_CLASS
    ldx #6
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda zp_math_a
    sta gold_lo
    lda zp_math_b
    sta gold_hi

    // Step 2: gold += rng_range(25) + 326
    lda #25
    jsr rng_range               // A = [0, 24]
    clc
    adc gold_lo
    sta gold_lo
    bcc !ccg_no_c1+
    inc gold_hi
!ccg_no_c1:
    // Add 326 ($0146)
    lda gold_lo
    clc
    adc #$46                    // lo byte of 326
    sta gold_lo
    lda gold_hi
    adc #$01                    // hi byte of 326
    sta gold_hi

    // Step 3: Compute net stat adjustment
    // net_adj = sum of (min(stat,18)-10) for STR,INT,WIS,DEX,CON
    //         - (min(CHR,18)-10)
    lda #0
    sta gold_stat_adj

    ldx #0
!ccg_stat_loop:
    stx zp_temp2                // Save loop index (safe across rng calls — rng not called here)
    ldy gold_stat_offsets,x
    lda player_data,y
    cmp #19
    bcc !ccg_no_cap+
    lda #18
!ccg_no_cap:
    sec
    sbc #10                     // Signed: -7 to +8
    clc
    adc gold_stat_adj
    sta gold_stat_adj
    ldx zp_temp2
    inx
    cpx #5
    bcc !ccg_stat_loop-

    // Subtract CHR adjustment (CHR goes the other way)
    lda player_data + PL_CHR_CUR
    cmp #19
    bcc !ccg_chr_ok+
    lda #18
!ccg_chr_ok:
    sec
    sbc #10
    sta zp_temp0
    lda gold_stat_adj
    sec
    sbc zp_temp0
    sta gold_stat_adj           // net_adj = sum_5_stats - CHR

    // Step 4: gold -= 5 * net_adj (16-bit)
    lda gold_stat_adj
    bpl !ccg_adj_pos+

    // Negative net_adj → gold += 5 * |net_adj| (subtracting a negative)
    eor #$ff
    clc
    adc #1                      // A = |net_adj|
    ldx #5
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda gold_lo
    clc
    adc zp_math_a
    sta gold_lo
    lda gold_hi
    adc zp_math_b
    sta gold_hi
    jmp !ccg_adj_done+

!ccg_adj_pos:
    beq !ccg_adj_done+          // net_adj == 0, skip
    // Positive net_adj → gold -= 5 * net_adj
    ldx #5
    jsr math_multiply           // zp_math_a = lo, zp_math_b = hi
    lda gold_lo
    sec
    sbc zp_math_a
    sta gold_lo
    lda gold_hi
    sbc zp_math_b
    sta gold_hi

!ccg_adj_done:
    // Step 5: If female, add 50
    lda player_data + PL_FLAGS
    and #PLF_MALE
    bne !ccg_not_female+
    lda gold_lo
    clc
    adc #50
    sta gold_lo
    bcc !ccg_not_female+
    inc gold_hi
!ccg_not_female:

    // Step 6: Clamp minimum 80
    lda gold_hi
    bne !ccg_gold_ok+           // Hi > 0 → at least 256, no clamp needed
    lda gold_lo
    cmp #80
    bcs !ccg_gold_ok+
    lda #80
    sta gold_lo
!ccg_gold_ok:

    // Store in player struct (24-bit, hi byte = 0)
    lda gold_lo
    sta player_data + PL_GOLD_0
    lda gold_hi
    sta player_data + PL_GOLD_1
    lda #0
    sta player_data + PL_GOLD_2
    rts
