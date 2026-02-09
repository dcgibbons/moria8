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
    jsr create_select_class
    jsr create_roll_stats
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
    ldx #0                  // Class index
    ldy #0                  // Display row counter
!class_loop:
    // Check if this class is allowed
    lda #1
    stx zp_temp3            // Save class index
!shift:
    cpx #0
    beq !check+
    asl
    dex
    jmp !shift-
!check:
    ldx zp_temp3            // Restore class index
    and zp_temp2            // Test bit
    beq !class_next+        // Not allowed, skip

    // Display this class
    tya
    clc
    adc #2                  // Row = display_row + 2
    sta zp_cursor_row
    lda #3
    sta zp_cursor_col

    // Store mapping: display row Y → class index X
    txa
    sta create_class_map,y  // Save class index for this display position

    // Letter
    lda #COL_LGREY
    sta zp_text_color
    tya
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
    lda class_name_ptrs_lo,x
    sta zp_ptr0
    lda class_name_ptrs_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    iny                     // Next display row

!class_next:
    inx
    cpx #CLASS_COUNT
    bcc !class_loop-

    // Y = number of valid classes displayed
    sty zp_temp3            // Save count

    // Prompt
    lda #COL_LGREY
    sta zp_text_color
    tya
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
    cmp zp_temp3            // Compare to count of displayed classes
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
    pla
    tax
    pha
    // Store as base stat
    sta player_data + PL_STR_BASE,x

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

    // ": "
    lda #$3a
    jsr screen_put_char
    lda #$20
    jsr screen_put_char

    // Base value
    lda #COL_WHITE
    sta zp_text_color
    pla
    tax
    pha
    lda player_data + PL_STR_BASE,x
    jsr screen_put_decimal

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
    lda zp_temp4
    jsr screen_put_decimal

    lda #COL_LGREY
    sta zp_text_color
    lda #$29                // ')'
    jsr screen_put_char

    pla
    tax
    inx
    cpx #STAT_COUNT
    bcc !roll_loop-

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

// create_calc_modified_stat — Calculate stat with race+class modifiers
// Input: X = stat index (0–5)
// Output: A = modified stat (clamped 3–18)
// Preserves: X
create_calc_modified_stat:
    // Get base stat
    lda player_data + PL_STR_BASE,x

    // Add race modifier
    stx zp_temp3
    // Race offset = race * 6 + stat_index
    lda player_data + PL_RACE
    asl
    sta zp_temp0
    asl
    clc
    adc zp_temp0            // x6
    clc
    adc zp_temp3            // + stat index
    tay
    lda player_data + PL_STR_BASE,x   // Re-read base
    clc
    adc race_stat_adj,y     // + race modifier (signed)

    // Add class modifier
    lda player_data + PL_CLASS
    asl
    sta zp_temp0
    asl
    clc
    adc zp_temp0            // class * 6
    clc
    adc zp_temp3            // + stat index
    tay
    ldx zp_temp3            // Restore X
    lda player_data + PL_STR_BASE,x
    clc
    adc race_stat_adj + 0   // Oops, wrong — need to accumulate properly

    // Let me redo this correctly
    ldx zp_temp3
    lda player_data + PL_STR_BASE,x

    // Race adj offset
    stx zp_temp0
    lda player_data + PL_RACE
    asl
    sta zp_temp1
    asl
    clc
    adc zp_temp1            // race * 6
    clc
    adc zp_temp0            // + stat_index
    tay
    ldx zp_temp0
    lda player_data + PL_STR_BASE,x
    clc
    adc race_stat_adj,y

    // Class adj offset
    pha
    lda player_data + PL_CLASS
    asl
    sta zp_temp1
    asl
    clc
    adc zp_temp1            // class * 6
    clc
    adc zp_temp0            // + stat_index
    tay
    pla
    clc
    adc class_stat_adj,y

    // Clamp 3–18
    cmp #3
    bcs !cmin+
    lda #3
!cmin:
    cmp #19
    bcc !cmax+
    lda #18
!cmax:
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
