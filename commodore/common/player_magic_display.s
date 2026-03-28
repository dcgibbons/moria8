#importonce
// player_magic_display.s — spell list rendering and failure calculation
// Split so C128 can keep the spell display/failure tail in the banked payload
// while C64 still links it inline with player_magic.s.

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

    ldx #HSTR_PM_TITLE_MAGE
    lda #14                         // Center "MAGE SPELLS" (11 chars)
    bne !sld_title_ready+

!sld_pray_title:
    ldx #HSTR_PM_TITLE_PRAY
    lda #16                         // Center "PRAYERS" (7 chars)

!sld_title_ready:
    sta zp_cursor_col
    jsr huff_decode_string
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
    ldx #HSTR_PM_FOOTER_CAST
    beq !sld_footer_ready+
    ldx #HSTR_PM_FOOTER_PRAY
!sld_footer_ready:
    jsr huff_decode_string
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
