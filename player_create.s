// player_create.s — Character creation flow
//
// 1. Race selection
// 2. Class selection (filtered by race)
// 3. Stat rolling (3d6 + race + class modifiers, re-roll option)
// 4. Name entry (max 16 chars, uppercase only)
// 5. Initialize starting HP, mana, gold, food, position

// Starting values
.const START_FOOD_LO  = $c8  // 200 turns of food (lo)
.const START_FOOD_HI  = $00  // (hi)
.const START_GOLD     = 200  // Starting gold pieces
.const START_LIGHT    = 1    // Starting light radius (torch)

// ============================================================
// Subroutines
// ============================================================

// player_create — Full character creation flow
// Output: player_data struct fully initialized
// Preserves: nothing
player_create:
    jsr player_init

    jsr create_select_race
    jsr create_roll_stats
    jsr create_select_class
    jsr create_enter_name
    jsr create_init_character

    // Show final character sheet
    jsr ui_char_display
    jsr input_get_key

    rts

// ============================================================
// Race selection
// ============================================================
create_select_race:
    jsr screen_clear

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
    jsr screen_put_string

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
    jsr screen_put_char

    // ") "
    lda #$29                // ')'
    jsr screen_put_char
    lda #$20                // space
    jsr screen_put_char

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
    jsr screen_put_string

    pla
    tax
    inx
    cpx #RACE_COUNT
    bcc !race_loop-

    // Prompt
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
    jsr screen_put_string

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
    jsr screen_clear

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
    jsr screen_put_string

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
    jsr screen_put_char
    lda #$29                // ')'
    jsr screen_put_char
    lda #$20
    jsr screen_put_char

    // Class name
    lda #COL_WHITE
    sta zp_text_color
    ldx zp_temp3
    lda class_name_ptrs_lo,x
    sta zp_ptr0
    lda class_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    inc zp_temp4            // Next display row

!class_next:
    inc zp_temp3
    lda zp_temp3
    cmp #CLASS_COUNT
    bcc !class_loop-

    // zp_temp4 = number of valid classes displayed
    // Prompt
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
    jsr screen_put_string

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
    jsr screen_clear

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
    jsr screen_put_string

    // Roll 3d6 for each base stat
    ldx #0
!roll_loop:
    txa
    pha

    // Roll 3d6
    lda #3                  // 3 dice
    ldx #6                  // 6 sides
    ldy #0                  // +0 bonus
    jsr math_dice
    // Result in zp_math_a (we only need lo byte, max 18)
    lda zp_math_a

    // Clamp to 3–18
    cmp #3
    bcs !min_ok+
    lda #3
!min_ok:
    cmp #19
    bcc !max_ok+
    lda #18
!max_ok:
    sta zp_temp4            // Save rolled value (pla would destroy A)
    pla
    tax
    pha
    lda zp_temp4            // Restore rolled value
    // Store as base stat
    sta player_data + PL_STR_BASE,x

    // Roll exceptional STR if base STR = 18
    cpx #0                  // STR stat?
    bne !display_stat+      // Not STR → skip exceptional handling
    cmp #18                 // Rolled 18?
    bne !no_exceptional+
    // Roll 1d100 for exceptional
    lda #1
    ldx #100
    ldy #0
    jsr math_dice           // Result in zp_math_a (1–100)
    lda zp_math_a
    sta player_data + PL_STR_EXTRA
    jmp !display_stat+
!no_exceptional:
    lda #0
    sta player_data + PL_STR_EXTRA

!display_stat:
    // Restore stat_index (may have been clobbered by math_dice)
    pla
    tax
    pha

    // Display: row = stat_index + 2, col 3
    txa
    clc
    adc #2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    // Stat name
    lda #COL_LGREY
    sta zp_text_color
    lda stat_name_ptrs_lo,x
    sta zp_ptr0
    lda stat_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // ":"
    lda #$3a
    jsr screen_put_char

    // Base value (right-justified, 18/xx aware)
    lda #COL_WHITE
    sta zp_text_color
    pla
    tax
    pha
    lda player_data + PL_STR_BASE,x
    ldy #0                  // No exceptional by default
    cpx #0                  // STR?
    bne !base_disp+
    ldy player_data + PL_STR_EXTRA
!base_disp:
    jsr put_stat_val

    // Show modified value: base + race + class adjustments
    pla
    tax
    pha
    jsr create_calc_modified_stat  // A = modified stat
    sta zp_temp4

    // " (" then modified value then ")"
    lda #$20                // space
    jsr screen_put_char
    lda #$28                // '('
    jsr screen_put_char

    lda #COL_CYAN
    sta zp_text_color
    pla
    tax
    pha
    ldy #0
    cpx #0                  // STR?
    bne !mod_disp+
    lda zp_temp4
    cmp #18                 // Modified = 18?
    bne !mod_disp+
    ldy player_data + PL_STR_EXTRA
!mod_disp:
    lda zp_temp4
    jsr put_stat_val

    lda #COL_LGREY
    sta zp_text_color
    lda #$29                // ')'
    jsr screen_put_char

    pla
    tax
    inx
    cpx #STAT_COUNT
    bcs !roll_done+
    jmp !roll_loop-
!roll_done:

    // Calculate final stats for display
    jsr player_calc_stats

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
    jsr screen_put_string

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
// Input: X = stat index (0–5)
// Output: A = modified stat (clamped 3–18)
// Preserves: X
create_calc_modified_stat:
    stx zp_temp3            // Save stat index

    // Race adj offset = race * 6 + stat_index
    lda player_data + PL_RACE
    asl
    sta zp_temp0
    asl
    clc
    adc zp_temp0            // race * 6
    clc
    adc zp_temp3            // + stat_index
    tay

    // Base + race modifier
    ldx zp_temp3
    lda player_data + PL_STR_BASE,x
    clc
    adc race_stat_adj,y

    // Clamp 3–18 (handle signed underflow: negative wraps to 128+)
    bmi !clow+              // Bit 7 set = went negative
    cmp #3
    bcc !clow+
    cmp #19
    bcc !cdone+
    lda #18
    jmp !cdone+
!clow:
    lda #3
!cdone:
    ldx zp_temp3            // Restore X
    rts

// ============================================================
// Name entry
// ============================================================
create_enter_name:
    jsr screen_clear

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
    jsr screen_put_string

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
    jsr screen_put_string

    // Input cursor on row 4
    lda #4
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    lda #COL_WHITE
    sta zp_text_color

    ldx #0                  // Character count
!name_loop:
    jsr input_get_key

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
    // Erase char on screen
    dec zp_cursor_col
    lda #$20                // Space
    jsr screen_put_char
    dec zp_cursor_col        // Move back again
    jmp !name_loop-
!not_del:

    // Check if it's a letter (A-Z = $41-$5A in PETSCII)
    cmp #$41
    bcc !check_other+
    cmp #$5b
    bcs !check_other+
    // It's a letter — convert PETSCII to screen code
    sec
    sbc #$40                // A=$01, B=$02, ..., Z=$1A
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
    jsr screen_put_char
    inx
    jmp !name_loop-

!name_done:
    // Null-terminate
    lda #0
    sta player_data + PL_NAME,x
    rts

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
    jsr player_calc_stats

    // Calculate max HP
    jsr player_calc_hp
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

    // Starting mana = spell_stat / 2 (INT for mage, WIS for priest)
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

    // Starting gold
    lda #<START_GOLD
    sta player_data + PL_GOLD_0
    lda #>START_GOLD
    sta player_data + PL_GOLD_1
    lda #0
    sta player_data + PL_GOLD_2

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

    // Starting position (town center, set properly in Phase 3)
    lda #20
    sta player_data + PL_MAP_X
    lda #12
    sta player_data + PL_MAP_Y

    // Flags: male by default
    lda #PLF_MALE
    sta player_data + PL_FLAGS

    // Sync to ZP
    jsr player_sync_to_zp

    rts

// put_stat_val — Display a stat value, handling 18/xx exceptional STR
// Input:  A = stat value (3–18)
//         Y = exceptional (0 = none, 1–100 = exceptional percentage)
// If A=18 and Y>0: prints "18/XX" (5 chars)
// Otherwise: prints value right-justified in 2 chars
// Preserves: nothing
put_stat_val:
    cpy #0
    beq !rj+                // No exceptional → right-justified normal
    cmp #18
    bne !rj+                // Not 18 → right-justified normal
    // 18/xx format: A=18, Y=exceptional
    tya
    pha                     // Save exceptional on stack
    lda #18
    jsr screen_put_decimal  // Print "18"
    lda #$2f                // '/'
    jsr screen_put_char
    pla                     // A = exceptional value
    cmp #100
    bne !not_100+
    lda #0                  // 18/100 → display as "00"
!not_100:
    jmp screen_put_decimal_lz2  // Print with leading zero
!rj:
    jmp screen_put_decimal_rj2  // Right-justified in 2 chars

// ============================================================
// String data (screen codes)
// ============================================================
create_race_title:
    .text "CHOOSE YOUR RACE" ; .byte $00
create_class_title:
    .text "CHOOSE YOUR CLASS" ; .byte $00
create_stats_title:
    .text "ROLL STATISTICS" ; .byte $00
create_name_title:
    .text "ENTER YOUR NAME" ; .byte $00
create_choose_str:
    .text "CHOOSE (A-" ; .byte $00
create_reroll_str:
    .text "R) REROLL  RETURN) ACCEPT" ; .byte $00
create_name_prompt:
    .text "NAME (16 CHARS MAX):" ; .byte $00
