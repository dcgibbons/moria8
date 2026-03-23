#importonce
// player_magic.s — Cast spell (m) and Pray (p) commands
//
// Phase 7.2: Spell list display, cast/pray logic, failure calculation.
// Spell effects are stubbed — prints "YOU CAST <name>." or "YOU PRAY <name>."
// Actual effect dispatch comes in steps 7.4/7.5.
//
// Entry points:
//   player_cast_spell — Handle 'm' command (mage spells)
//   player_pray       — Handle 'p' command (priest prayers)
//
// Returns: carry SET = turn consumed, carry CLEAR = cancelled/no turn

.encoding "screencode_mixed"


// ============================================================
// Scratch variables
// ============================================================
pm_spell_idx:    .byte 0     // Selected spell index (0-15)
pm_spell_type:   .byte 0     // 1=mage, 2=priest
pm_mana_tbl_lo:  .byte 0     // Pointer to active mana cost table (lo)
pm_mana_tbl_hi:  .byte 0
pm_lvl_tbl_lo:   .byte 0     // Pointer to active level table (lo)
pm_lvl_tbl_hi:   .byte 0
pm_fail_tbl_lo:  .byte 0     // Pointer to active fail table (lo)
pm_fail_tbl_hi:  .byte 0
pm_name_lo_lo:   .byte 0     // Pointer to name_lo table (lo)
pm_name_lo_hi:   .byte 0
pm_name_hi_lo:   .byte 0     // Pointer to name_hi table (lo)
pm_name_hi_hi:   .byte 0
pm_row_counter:  .byte 0     // Row counter for spell list display
pm_cost_tmp:     .byte 0     // Temp for mana cost during cast
pm_fail_work:    .byte 0     // Working value for failure calc

// ============================================================
// player_cast_spell — Handle 'm' (cast mage spell)
// Output: carry SET = turn consumed, CLEAR = cancelled
// ============================================================
player_cast_spell:
    // Check if player is a mage/rogue/ranger (has mage spells)
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    beq !pm_can_cast+

    // Cannot cast
    ldx #HSTR_PM_NO_CAST
    jsr huff_print_msg
    clc
    rts

!pm_can_cast:
    lda #SPELL_MAGE
    sta pm_spell_type
    ldx #0                      // Mage tables at offset 0
    jsr pm_setup
    jmp pm_do_cast

// ============================================================
// player_pray — Handle 'p' (pray priest prayer)
// Output: carry SET = turn consumed, CLEAR = cancelled
// ============================================================
player_pray:
    // Check if player is a priest/paladin (has priest prayers)
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_PRIEST
    beq !pm_can_pray+

    // Cannot pray
    ldx #HSTR_PM_NO_PRAY
    jsr huff_print_msg
    clc
    rts

!pm_can_pray:
    lda #SPELL_PRIEST
    sta pm_spell_type
    ldx #10                     // Priest tables at offset 10
    jsr pm_setup
    jmp pm_do_cast

// pm_setup — Copy 10 table pointer bytes from pm_tables+X to pm_mana_tbl_lo+
// Input: X = offset into pm_tables (0=mage, 10=priest)
// Clobbers: A, X, Y
pm_setup:
    ldy #9
!pms_loop:
    lda pm_tables,x
    sta pm_mana_tbl_lo,y
    inx
    dey
    bpl !pms_loop-
    rts

// Table pointer data: 10 bytes per spell type (stored in reverse order for dey loop)
// Order: name_hi_hi, name_hi_lo, name_lo_hi, name_lo_lo, fail_hi, fail_lo, lvl_hi, lvl_lo, mana_hi, mana_lo
pm_tables:
    // Mage (offset 0)
    .byte >mage_spell_name_hi, <mage_spell_name_hi
    .byte >mage_spell_name_lo, <mage_spell_name_lo
    .byte >mage_spell_fail,    <mage_spell_fail
    .byte >mage_spell_level,   <mage_spell_level
    .byte >mage_spell_mana,    <mage_spell_mana
    // Priest (offset 10)
    .byte >priest_spell_name_hi, <priest_spell_name_hi
    .byte >priest_spell_name_lo, <priest_spell_name_lo
    .byte >priest_spell_fail,    <priest_spell_fail
    .byte >priest_spell_level,   <priest_spell_level
    .byte >priest_spell_mana,    <priest_spell_mana

// ============================================================
// pm_do_cast — Shared cast/pray logic
// ============================================================
pm_do_cast:
    // Display spell list overlay
    jsr spell_list_display

    // Let the initiating command key release before reading the spell choice.
    jsr input_wait_release

    // Get key selection
    jsr input_get_key

    // Check ESC ($03) or space ($20) → cancel
    cmp #$03
    beq !pm_cancel+
    cmp #$20
    beq !pm_cancel+

    // Convert PETSCII letter to spell index: A=0, B=1, ..., P=15
    sec
    sbc #$41                        // PETSCII 'A'
    bcc !pm_cancel+                 // Below 'A'
    cmp #16
    bcc !pm_valid_key+
!pm_cancel:
    clc
    rts

!pm_valid_key:
    sta pm_spell_idx

    // Restore dungeon screen before executing spell (BUG-27)
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jsr viewport_update
    jsr render_viewport
    jsr status_draw

    // Confused? Random spell instead of player's choice
    lda zp_eff_confuse
    beq !pm_not_confused+
    lda #16
    jsr rng_range                    // A = random [0, 15]
    sta pm_spell_idx
    jmp !pm_known+                   // Skip known check when confused
!pm_not_confused:

    // Check if spell is known
    lda pm_spell_idx
    cmp #8
    bcs !pm_check_hi+

    // Spells 0-7: check lo byte
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    beq !pm_not_known+
    jmp !pm_known+

!pm_check_hi:
    // Spells 8-15: check hi byte
    sec
    sbc #8
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    bne !pm_known+

!pm_not_known:
    ldx #HSTR_PM_NOT_KNOWN
    jsr huff_print_msg
    clc
    rts

!pm_known:
    // Check mana cost
    lda pm_mana_tbl_lo
    sta zp_ptr0
    lda pm_mana_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta pm_cost_tmp                 // Save mana cost

    // Compare with current mana
    lda zp_player_mp
    cmp pm_cost_tmp
    bcs !pm_mana_ok+

    // Not enough mana
    ldx #HSTR_PM_NO_MANA
    jsr huff_print_msg
    clc
    rts

!pm_mana_ok:
    // Confused? Skip level check (umoria behavior)
    lda zp_eff_confuse
    bne !pm_lvl_ok+

    // Check minimum level
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y                 // Spell min level
    cmp zp_player_lvl
    beq !pm_lvl_ok+
    bcc !pm_lvl_ok+

    // Player level too low
    ldx #HSTR_PM_NO_EXP
    jsr huff_print_msg
    clc
    rts

!pm_lvl_ok:
    // Deduct mana
    lda zp_player_mp
    sec
    sbc pm_cost_tmp
    sta zp_player_mp
    sta player_data + PL_MANA

    // Roll failure check
    jsr calc_spell_failure
    bcc !pm_success+

    // Spell failed — turn consumed
    ldx #HSTR_PM_FAIL
    jsr huff_print_msg
    lda #SFX_SPELL_FAIL
    jsr sound_play
    sec
    rts

!pm_success:
    // Build message: "YOU CAST <name>." or "YOU PRAY <name>."
    lda #0
    sta cmb_buf_idx

    // "YOU CAST " or "YOU PRAY "
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !pm_pray_verb+
    ldx #HSTR_PM_YOU_CAST
    jmp !pm_verb_done+
!pm_pray_verb:
    ldx #HSTR_PM_YOU_PRAY
!pm_verb_done:
    jsr huff_append_combat

    // Append spell name
    lda pm_name_lo_lo
    sta zp_ptr0
    lda pm_name_lo_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y                 // Name pointer lo
    sta zp_ptr2                     // Save temporarily

    lda pm_name_hi_lo
    sta zp_ptr0
    lda pm_name_hi_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y                 // Name pointer hi

    tay                             // Y = name hi
    lda zp_ptr2                     // A = name lo
    jsr combat_append_str

    // Append "."
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str

    jsr cmb_term_and_print

    // Dispatch to spell effect
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !pm_priest_dispatch+
    lda pm_spell_idx
    jsr mage_effect_dispatch
    jmp !pm_effect_done+
!pm_priest_dispatch:
    lda pm_spell_idx
    jsr priest_effect_dispatch
!pm_effect_done:

    // Spell success sound
    lda #SFX_SPELL
    jsr sound_play

    // Turn consumed
    sec
    rts

// ============================================================
// spell_list_display — Full-screen overlay showing known spells
// ============================================================
spell_list_display:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    // Title: "MAGE SPELLS" or "PRAYERS"
    lda #0
    sta zp_cursor_row
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !sld_pray_title+

    lda #14                         // Center "MAGE SPELLS" (11 chars)
    sta zp_cursor_col
    ldx #HSTR_PM_TITLE_MAGE
    jsr huff_decode_string
    jmp !sld_title_done+

!sld_pray_title:
    lda #16                         // Center "PRAYERS" (7 chars)
    sta zp_cursor_col
    ldx #HSTR_PM_TITLE_PRAY
    jsr huff_decode_string

!sld_title_done:
    jsr screen_put_string

    // Header row 1: "   NAME              MANA LVL"
    lda #COL_LGREY
    sta zp_text_color
    lda #1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<pm_header_str
    sta zp_ptr0
    lda #>pm_header_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Iterate spells 0-15
    lda #0
    sta pm_row_counter

!sld_loop:
    lda pm_row_counter
    cmp #16
    bcc !sld_not_done+
    jmp !sld_loop_done+
!sld_not_done:

    // Check if this spell is known
    lda pm_row_counter
    cmp #8
    bcs !sld_check_hi+

    // Spells 0-7: check lo byte
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    bne !sld_show+
    jmp !sld_next+

!sld_check_hi:
    // Spells 8-15: check hi byte
    sec
    sbc #8
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    bne !sld_show+
    jmp !sld_next+

!sld_show:
    // Row = pm_row_counter + 2
    lda pm_row_counter
    clc
    adc #2
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Choose color: dim if mana cost > current mana
    lda pm_mana_tbl_lo
    sta zp_ptr0
    lda pm_mana_tbl_hi
    sta zp_ptr0_hi
    ldy pm_row_counter
    lda (zp_ptr0),y                 // Mana cost
    sta pm_cost_tmp
    cmp zp_player_mp
    beq !sld_affordable+
    bcc !sld_affordable+

    // Too expensive — dim
    lda #COL_DGREY
    sta zp_text_color
    jmp !sld_print_entry+

!sld_affordable:
    lda #COL_LGREY
    sta zp_text_color

!sld_print_entry:
    // Print letter: 'A' + index (screen code for 'A' = $01)
    lda pm_row_counter
    clc
    adc #$01                        // Screen code 'A'
    jsr screen_put_char

    // ") "
    lda #$29                        // Screen code ')'
    jsr screen_put_char
    lda #$20                        // Space
    jsr screen_put_char

    // Spell name
    lda pm_name_lo_lo
    sta zp_ptr0
    lda pm_name_lo_hi
    sta zp_ptr0_hi
    ldy pm_row_counter
    lda (zp_ptr0),y                 // Name lo
    sta zp_ptr2                     // Save

    lda pm_name_hi_lo
    sta zp_ptr0
    lda pm_name_hi_hi
    sta zp_ptr0_hi
    ldy pm_row_counter
    lda (zp_ptr0),y                 // Name hi
    sta zp_ptr2_hi

    // Print spell name
    lda zp_ptr2
    sta zp_ptr0
    lda zp_ptr2_hi
    sta zp_ptr0_hi
    jsr screen_put_string

    // Print mana cost at column 30 (right-justified 2 chars)
    lda pm_row_counter
    clc
    adc #2
    sta zp_cursor_row
    lda #30
    sta zp_cursor_col
    lda pm_cost_tmp
    jsr screen_put_decimal_rj2

    // Print min level at column 34 (right-justified 2 chars)
    lda #34
    sta zp_cursor_col
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_row_counter
    lda (zp_ptr0),y
    jsr screen_put_decimal_rj2

!sld_next:
    inc pm_row_counter
    jmp !sld_loop-

!sld_loop_done:
    // Footer row 24: "CAST WHICH? (A-P, ESC)"
    lda #COL_WHITE
    sta zp_text_color
    lda #24
    sta zp_cursor_row
    lda #8
    sta zp_cursor_col

    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !sld_pray_footer+
    ldx #HSTR_PM_FOOTER_CAST
    jsr huff_decode_string
    jmp !sld_footer_done+
!sld_pray_footer:
    ldx #HSTR_PM_FOOTER_PRAY
    jsr huff_decode_string
!sld_footer_done:
    jsr screen_put_string

    rts

// ============================================================
// calc_spell_failure — Calculate adjusted failure rate and roll
//
// Formula: adjusted = fail_base - 3*(player_level - spell_level)
//                     - spell_stat_bonus[stat]
// Clamped to [5, 95].
// Roll rng_range(100): if roll < adjusted → fail (carry SET)
//                      else succeed (carry CLEAR)
// ============================================================
calc_spell_failure:
    // Load fail_base from fail table[pm_spell_idx]
    lda pm_fail_tbl_lo
    sta zp_ptr0
    lda pm_fail_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y
    sta pm_fail_work                // fail_base

    // Load spell_level from level table[pm_spell_idx]
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_spell_idx
    lda (zp_ptr0),y                 // spell_level
    sta zp_temp0                    // Save spell level

    // Compute player_level - spell_level (clamped to 0 if negative)
    lda zp_player_lvl
    sec
    sbc zp_temp0
    bcs !csf_lvl_ok+
    lda #0                          // Clamp to 0
!csf_lvl_ok:
    // Multiply by 3: (val * 2) + val
    sta zp_temp0                    // Save diff
    asl                             // * 2
    bcs !csf_clamp_sub+             // Overflow — big reduction, will clamp later
    clc
    adc zp_temp0                    // + original = * 3
    bcs !csf_clamp_sub+

    // Subtract from fail_base
    sta zp_temp0                    // 3 * level_diff
    lda pm_fail_work
    sec
    sbc zp_temp0
    bcc !csf_clamp_low+             // Underflow → clamp to min
    sta pm_fail_work
    jmp !csf_stat_bonus+

!csf_clamp_sub:
    // Level bonus overflows — failure will be very low
    lda #5
    sta pm_fail_work
    jmp !csf_stat_bonus+

!csf_clamp_low:
    lda #5
    sta pm_fail_work

!csf_stat_bonus:
    // Get relevant stat: mage uses INT, priest uses WIS
    lda pm_spell_type
    cmp #SPELL_MAGE
    bne !csf_wis+
    lda player_data + PL_INT_CUR
    jmp !csf_got_stat+
!csf_wis:
    lda player_data + PL_WIS_CUR

!csf_got_stat:
    // Convert stat to bonus table index (stat - 3, clamped to [0, 15])
    jsr stat_bonus_index            // Returns index in X
    lda spell_stat_bonus,x          // Bonus value

    // Subtract bonus from fail_work
    sta zp_temp0
    lda pm_fail_work
    sec
    sbc zp_temp0
    bcc !csf_clamp_5+              // Underflow
    sta pm_fail_work
    jmp !csf_clamp_range+

!csf_clamp_5:
    lda #5
    sta pm_fail_work

!csf_clamp_range:
    // Clamp to [5, 95]
    lda pm_fail_work
    cmp #5
    bcs !csf_min_ok+
    lda #5
    sta pm_fail_work
!csf_min_ok:
    lda pm_fail_work
    cmp #96
    bcc !csf_max_ok+
    lda #95
    sta pm_fail_work
!csf_max_ok:

    // Faint hunger penalty: +20 to failure
    lda zp_hunger_state
    cmp #HUNGER_FAINT
    bcc !csf_hunger_ok+
    lda pm_fail_work
    clc
    adc #20
    cmp #96
    bcc !csf_hunger_store+
    lda #95
!csf_hunger_store:
    sta pm_fail_work
!csf_hunger_ok:

    // Roll rng_range(100)
    lda #100
    jsr rng_range                   // A = [0, 99]

    // If roll < adjusted_fail → spell fails
    cmp pm_fail_work
    bcc !csf_fail+

    // Success
    clc
    rts

!csf_fail:
    sec
    rts

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
pm_header_str:
    .text "   Name              Mana Lvl" ; .byte 0

#if !C128
    #import "player_magic_levelup.s"
    #import "player_magic_tail.s"
#endif

// ============================================================
// Compile-time asserts
// ============================================================
.assert "pm_spell_type mage", SPELL_MAGE, 1
.assert "pm_spell_type priest", SPELL_PRIEST, 2
