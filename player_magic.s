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
    lda #<pm_no_cast_str
    sta zp_ptr0
    lda #>pm_no_cast_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!pm_can_cast:
    // Set up table pointers to mage spell tables
    lda #SPELL_MAGE
    sta pm_spell_type

    lda #<mage_spell_mana
    sta pm_mana_tbl_lo
    lda #>mage_spell_mana
    sta pm_mana_tbl_hi

    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi

    lda #<mage_spell_fail
    sta pm_fail_tbl_lo
    lda #>mage_spell_fail
    sta pm_fail_tbl_hi

    lda #<mage_spell_name_lo
    sta pm_name_lo_lo
    lda #>mage_spell_name_lo
    sta pm_name_lo_hi

    lda #<mage_spell_name_hi
    sta pm_name_hi_lo
    lda #>mage_spell_name_hi
    sta pm_name_hi_hi

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
    lda #<pm_no_pray_str
    sta zp_ptr0
    lda #>pm_no_pray_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!pm_can_pray:
    // Set up table pointers to priest prayer tables
    lda #SPELL_PRIEST
    sta pm_spell_type

    lda #<priest_spell_mana
    sta pm_mana_tbl_lo
    lda #>priest_spell_mana
    sta pm_mana_tbl_hi

    lda #<priest_spell_level
    sta pm_lvl_tbl_lo
    lda #>priest_spell_level
    sta pm_lvl_tbl_hi

    lda #<priest_spell_fail
    sta pm_fail_tbl_lo
    lda #>priest_spell_fail
    sta pm_fail_tbl_hi

    lda #<priest_spell_name_lo
    sta pm_name_lo_lo
    lda #>priest_spell_name_lo
    sta pm_name_lo_hi

    lda #<priest_spell_name_hi
    sta pm_name_hi_lo
    lda #>priest_spell_name_hi
    sta pm_name_hi_hi

    jmp pm_do_cast

// ============================================================
// pm_do_cast — Shared cast/pray logic
// ============================================================
pm_do_cast:
    // Display spell list overlay
    jsr spell_list_display

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
    lda #<pm_not_known_str
    sta zp_ptr0
    lda #>pm_not_known_str
    sta zp_ptr0_hi
    jsr msg_print
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
    lda #<pm_no_mana_str
    sta zp_ptr0
    lda #>pm_no_mana_str
    sta zp_ptr0_hi
    jsr msg_print
    clc
    rts

!pm_mana_ok:
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
    lda #<pm_no_exp_str
    sta zp_ptr0
    lda #>pm_no_exp_str
    sta zp_ptr0_hi
    jsr msg_print
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
    lda #<pm_fail_str
    sta zp_ptr0
    lda #>pm_fail_str
    sta zp_ptr0_hi
    jsr msg_print
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
    lda #<pm_you_cast_str
    ldy #>pm_you_cast_str
    jmp !pm_verb_done+
!pm_pray_verb:
    lda #<pm_you_pray_str
    ldy #>pm_you_pray_str
!pm_verb_done:
    jsr combat_append_str

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

    // Null-terminate
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x

    // Print the message
    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jsr msg_print

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
    lda #<pm_title_mage_str
    sta zp_ptr0
    lda #>pm_title_mage_str
    sta zp_ptr0_hi
    jmp !sld_title_done+

!sld_pray_title:
    lda #16                         // Center "PRAYERS" (7 chars)
    sta zp_cursor_col
    lda #<pm_title_pray_str
    sta zp_ptr0
    lda #>pm_title_pray_str
    sta zp_ptr0_hi

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
    lda #<pm_footer_cast_str
    sta zp_ptr0
    lda #>pm_footer_cast_str
    sta zp_ptr0_hi
    jmp !sld_footer_done+
!sld_pray_footer:
    lda #<pm_footer_pray_str
    sta zp_ptr0
    lda #>pm_footer_pray_str
    sta zp_ptr0_hi
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
// magic_check_new_spells — Learn any spells the player qualifies for
// Checks each spell 0-15: if spell_level <= player_level and not
// already known, set the known bit and print message.
// Called on level-up and at character creation.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr2
// ============================================================
pm_learn_idx:    .byte 0     // Loop counter for learn check

magic_check_new_spells:
    lda player_data + PL_SPELL_TYPE
    bne !mcns_has_type+
    rts                             // SPELL_NONE — nothing to learn
!mcns_has_type:
    cmp #SPELL_MAGE
    bne !mcns_priest+

    // Mage: use mage tables
    lda #<mage_spell_level
    sta pm_lvl_tbl_lo
    lda #>mage_spell_level
    sta pm_lvl_tbl_hi
    lda #<mage_spell_name_lo
    sta pm_name_lo_lo
    lda #>mage_spell_name_lo
    sta pm_name_lo_hi
    lda #<mage_spell_name_hi
    sta pm_name_hi_lo
    lda #>mage_spell_name_hi
    sta pm_name_hi_hi
    jmp !mcns_scan+

!mcns_priest:
    // Priest: use priest tables
    lda #<priest_spell_level
    sta pm_lvl_tbl_lo
    lda #>priest_spell_level
    sta pm_lvl_tbl_hi
    lda #<priest_spell_name_lo
    sta pm_name_lo_lo
    lda #>priest_spell_name_lo
    sta pm_name_lo_hi
    lda #<priest_spell_name_hi
    sta pm_name_hi_lo
    lda #>priest_spell_name_hi
    sta pm_name_hi_hi

!mcns_scan:
    lda #0
    sta pm_learn_idx

!mcns_loop:
    lda pm_learn_idx
    cmp #16
    bcc !mcns_cont+
    rts
!mcns_cont:

    // Check if already known
    lda pm_learn_idx
    cmp #8
    bcs !mcns_hi_check+

    // Spells 0-7: check lo byte
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN
    beq !mcns_check_level+
    jmp !mcns_next+             // Already known, skip

!mcns_hi_check:
    // Spells 8-15: check hi byte
    sec
    sbc #8
    tax
    lda spell_bit_mask,x
    and player_data + PL_SPELLS_KNOWN_HI
    beq !mcns_check_level+
    jmp !mcns_next+             // Already known, skip

!mcns_check_level:
    // Check spell_level[i] <= player_level
    lda pm_lvl_tbl_lo
    sta zp_ptr0
    lda pm_lvl_tbl_hi
    sta zp_ptr0_hi
    ldy pm_learn_idx
    lda (zp_ptr0),y             // Spell min level
    cmp zp_player_lvl
    beq !mcns_learn+
    bcc !mcns_learn+
    jmp !mcns_next+             // Spell level too high

!mcns_learn:
    // Set known bit
    lda pm_learn_idx
    cmp #8
    bcs !mcns_set_hi+

    // Set bit in lo byte
    tax
    lda player_data + PL_SPELLS_KNOWN
    ora spell_bit_mask,x
    sta player_data + PL_SPELLS_KNOWN
    jmp !mcns_msg+

!mcns_set_hi:
    // Set bit in hi byte
    sec
    sbc #8
    tax
    lda player_data + PL_SPELLS_KNOWN_HI
    ora spell_bit_mask,x
    sta player_data + PL_SPELLS_KNOWN_HI

!mcns_msg:
    // Print "YOU HAVE LEARNED <spell name>!"
    lda #0
    sta cmb_buf_idx

    lda #<pm_learned_str
    ldy #>pm_learned_str
    jsr combat_append_str       // "YOU HAVE LEARNED "

    // Append spell name
    lda pm_name_lo_lo
    sta zp_ptr0
    lda pm_name_lo_hi
    sta zp_ptr0_hi
    ldy pm_learn_idx
    lda (zp_ptr0),y
    sta zp_ptr2

    lda pm_name_hi_lo
    sta zp_ptr0
    lda pm_name_hi_hi
    sta zp_ptr0_hi
    ldy pm_learn_idx
    lda (zp_ptr0),y

    tay
    lda zp_ptr2
    jsr combat_append_str

    // Append "!"
    lda #<pm_bang_str
    ldy #>pm_bang_str
    jsr combat_append_str

    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x

    lda #<combat_msg_buf
    sta zp_ptr0
    lda #>combat_msg_buf
    sta zp_ptr0_hi
    jsr msg_print

!mcns_next:
    inc pm_learn_idx
    jmp !mcns_loop-

// ============================================================
// magic_recalc_mana — Recalculate max mana based on level + stat
// Formula: max_mana = (level * stat) / 8 + spell_stat_bonus[stat-3]
// Clamped to [1, 255]. Called on level-up.
// Clobbers: A, X, Y, zp_math_a/b
// ============================================================
magic_recalc_mana:
    lda player_data + PL_SPELL_TYPE
    bne !mrm_has_spells+

    // No spell type — max_mana = 0
    lda #0
    sta player_data + PL_MAX_MANA
    sta zp_player_mmp
    sta player_data + PL_MANA
    sta zp_player_mp
    rts

!mrm_has_spells:
    // Get relevant stat
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    bne !mrm_wis+
    lda player_data + PL_INT_CUR
    jmp !mrm_got_stat+
!mrm_wis:
    lda player_data + PL_WIS_CUR

!mrm_got_stat:
    sta pm_cost_tmp                 // Save stat value

    // max_mana = (level * stat) / 8
    lda zp_player_lvl              // A = level
    ldx pm_cost_tmp                // X = stat
    jsr math_multiply              // zp_math_a = lo, zp_math_b = hi

    // Divide by 8: shift right 3 times
    lsr zp_math_b
    ror zp_math_a
    lsr zp_math_b
    ror zp_math_a
    lsr zp_math_b
    ror zp_math_a

    // If hi byte > 0 after division, clamp to 255
    lda zp_math_b
    bne !mrm_clamp_max+
    lda zp_math_a
    sta pm_cost_tmp                 // base mana

    // Add spell_stat_bonus[stat-3]
    lda player_data + PL_SPELL_TYPE
    cmp #SPELL_MAGE
    bne !mrm_wis_bonus+
    lda player_data + PL_INT_CUR
    jmp !mrm_bonus+
!mrm_wis_bonus:
    lda player_data + PL_WIS_CUR
!mrm_bonus:
    jsr stat_bonus_index            // X = index
    lda spell_stat_bonus,x
    clc
    adc pm_cost_tmp
    bcs !mrm_clamp_max+             // Overflow → 255

    // Clamp minimum to 1
    cmp #1
    bcs !mrm_store+
    lda #1
    jmp !mrm_store+

!mrm_clamp_max:
    lda #255

!mrm_store:
    sta player_data + PL_MAX_MANA
    sta zp_player_mmp

    // If current mana > new max, clamp
    lda zp_player_mp
    cmp player_data + PL_MAX_MANA
    bcc !mrm_done+
    beq !mrm_done+
    lda player_data + PL_MAX_MANA
    sta zp_player_mp
    sta player_data + PL_MANA

!mrm_done:
    rts

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
pm_no_cast_str:
    .text "YOU CANNOT CAST SPELLS." ; .byte 0
pm_no_pray_str:
    .text "YOU CANNOT PRAY." ; .byte 0
pm_not_known_str:
    .text "YOU DON'T KNOW THAT SPELL." ; .byte 0
pm_no_mana_str:
    .text "NOT ENOUGH MANA." ; .byte 0
pm_no_exp_str:
    .text "YOU'RE NOT EXPERIENCED ENOUGH." ; .byte 0
pm_fail_str:
    .text "YOUR SPELL FAILS." ; .byte 0
pm_you_cast_str:
    .text "YOU CAST " ; .byte 0
pm_you_pray_str:
    .text "YOU PRAY " ; .byte 0
pm_title_mage_str:
    .text "MAGE SPELLS" ; .byte 0
pm_title_pray_str:
    .text "PRAYERS" ; .byte 0
pm_header_str:
    .text "   NAME              MANA LVL" ; .byte 0
pm_footer_cast_str:
    .text "CAST WHICH? (A-P, ESC)" ; .byte 0
pm_footer_pray_str:
    .text "PRAY WHICH? (A-P, ESC)" ; .byte 0
pm_learned_str:
    .text "YOU HAVE LEARNED " ; .byte 0
pm_bang_str:
    .byte $21, 0    // "!"

// ============================================================
// Compile-time asserts
// ============================================================
.assert "pm_spell_type mage", SPELL_MAGE, 1
.assert "pm_spell_type priest", SPELL_PRIEST, 2
