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
    ldx #HSTR_PM_NO_CAST
    jsr huff_decode_string
    jsr msg_print
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
    jsr huff_decode_string
    jsr msg_print
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
    jsr huff_decode_string
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
    ldx #HSTR_PM_NO_MANA
    jsr huff_decode_string
    jsr msg_print
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
    jsr huff_decode_string
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
    ldx #HSTR_PM_FAIL
    jsr huff_decode_string
    jsr msg_print
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
// magic_check_new_spells — Learn any spells the player qualifies for
// Checks each spell 0-15: if spell_level <= player_level and not
// already known, set the known bit and print message.
// Called on level-up. Scans inventory for books matching
// the player's class, then learns qualifying spells from
// each book's 4-spell range.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr2
// ============================================================
pm_learn_idx:    .byte 0     // Current spell index being checked
mcns_class:      .byte 0     // Player's spell class
mcns_inv_idx:    .byte 0     // Inventory scan index
mcns_spell_start:.byte 0     // First spell index for current book

magic_check_new_spells:
    lda player_data + PL_SPELL_TYPE
    bne !mcns_has_type+
    rts                             // SPELL_NONE — nothing to learn
!mcns_has_type:
    sta mcns_class

    // Set up table pointers based on class
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
    jmp !mcns_scan_inv+

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

!mcns_scan_inv:
    // Scan inventory for books matching player's class
    lda #0
    sta mcns_inv_idx

!mcns_inv_loop:
    ldx mcns_inv_idx
    cpx #MAX_INV_SLOTS
    bcs !mcns_done+             // Scanned all carried slots

    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !mcns_inv_next+

    // Check if item is a book
    tax
    lda it_category,x
    cmp #ICAT_BOOK
    bne !mcns_inv_next+

    // Look up book info
    txa                         // A = item type
    jsr book_get_info           // A = spell_start, X = spell_class
    bcs !mcns_inv_next+         // Not in book table

    // Check class matches player
    cpx mcns_class
    bne !mcns_inv_next+

    // Learn qualifying spells from this book's range
    sta mcns_spell_start
    jsr mcns_learn_from_book

!mcns_inv_next:
    inc mcns_inv_idx
    jmp !mcns_inv_loop-

!mcns_done:
    rts

// mcns_learn_from_book — Learn qualifying spells from one book
// Input: mcns_spell_start, level/name table pointers set up
// Clobbers: A, X, Y
mcns_learn_from_book:
    lda mcns_spell_start
    sta pm_learn_idx

!mcns_loop:
    // Check if done with this book's 4 spells
    lda pm_learn_idx
    sec
    sbc mcns_spell_start
    cmp #4
    bcc !mcns_cont+
    rts                             // Book done (replaces jmp to mcns_book_done)
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

    ldx #HSTR_PM_LEARNED
    jsr huff_append_combat      // "YOU HAVE LEARNED "

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

    jsr cmb_term_and_print

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
// mage_effect_dispatch — Dispatch mage spell effect by index
// Input: A = spell index (0-15)
// Uses RTS-trick jump table: O(1) dispatch, no CMP/BNE chain
// Clobbers: everything
// ============================================================
mage_effect_dispatch:
    tax
    lda med_tbl_hi,x
    pha
    lda med_tbl_lo,x
    pha
    rts                             // Jump to (table entry)+1

med_tbl_lo:
    .byte <(med_s0-1),  <(eff_detect_monsters-1), <(eff_phase_door-1)
    .byte <(eff_light_room-1), <(med_s4-1), <(med_s5-1)
    .byte <(eff_confuse_adjacent-1), <(med_s7-1), <(med_s8-1)
    .byte <(eff_destroy_traps_doors-1), <(eff_sleep_adjacent-1)
    .byte <(eff_cure_poison-1), <(eff_teleport_self-1)
    .byte <(med_s13-1), <(eff_wall_to_mud-1), <(med_s15-1)
med_tbl_hi:
    .byte >(med_s0-1),  >(eff_detect_monsters-1), >(eff_phase_door-1)
    .byte >(eff_light_room-1), >(med_s4-1), >(med_s5-1)
    .byte >(eff_confuse_adjacent-1), >(med_s7-1), >(med_s8-1)
    .byte >(eff_destroy_traps_doors-1), >(eff_sleep_adjacent-1)
    .byte >(eff_cure_poison-1), >(eff_teleport_self-1)
    .byte >(med_s13-1), >(eff_wall_to_mud-1), >(med_s15-1)

// Mage stubs (inline setup before effect call)
med_s0:    // 0: Magic Missile — bolt, 1d4 + level/2
    lda zp_player_lvl
    lsr
    tay
    lda #1
    ldx #4
    jmp eff_bolt
med_s4:    // 4: Cure Light Wounds — 1d8+1
    lda #1
    ldx #8
    ldy #1
    jmp heal_dice
med_s5:    // 5: Find Traps/Doors
    jsr eff_find_traps
    jmp eff_find_doors
med_s7:    // 7: Confusion — directional, set MX_CONFUSE
    jsr eff_directional_monster
    bcc !med_s7_rts+
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
!med_s7_rts:
    rts
med_s8:    // 8: Lightning Bolt — 3d8
    lda #3
    ldx #8
    ldy #0
    jmp eff_bolt
med_s13:   // 13: Frost Bolt — 5d8
    lda #5
    ldx #8
    ldy #0
    jmp eff_bolt
med_s15:   // 15: Fire Ball — 7d8 area damage to adjacent
    lda #7
    ldx #8
    jmp eff_damage_adjacent

// ============================================================
// priest_effect_dispatch — Dispatch priest prayer effect by index
// Input: A = spell index (0-15)
// Uses RTS-trick jump table: O(1) dispatch, no CMP/BNE chain
// Clobbers: everything
// ============================================================
priest_effect_dispatch:
    tax
    lda ped_tbl_hi,x
    pha
    lda ped_tbl_lo,x
    pha
    rts

ped_tbl_lo:
    .byte <(eff_detect_monsters-1), <(ped_s1-1), <(ped_s2-1)
    .byte <(ped_noop-1), <(eff_light_room-1), <(eff_find_traps-1)
    .byte <(eff_find_doors-1), <(ped_s7-1), <(ped_s8-1)
    .byte <(eff_phase_door-1), <(ped_s10-1), <(ped_s11-1)
    .byte <(eff_sleep_adjacent-1), <(eff_remove_curse-1)
    .byte <(ped_s14-1), <(eff_dispel_undead-1)
ped_tbl_hi:
    .byte >(eff_detect_monsters-1), >(ped_s1-1), >(ped_s2-1)
    .byte >(ped_noop-1), >(eff_light_room-1), >(eff_find_traps-1)
    .byte >(eff_find_doors-1), >(ped_s7-1), >(ped_s8-1)
    .byte >(eff_phase_door-1), >(ped_s10-1), >(ped_s11-1)
    .byte >(eff_sleep_adjacent-1), >(eff_remove_curse-1)
    .byte >(ped_s14-1), >(eff_dispel_undead-1)

// Priest stubs
ped_s1:    // 1: Cure Light Wounds — 1d8+1
    lda #1
    ldx #8
    ldy #1
    jmp heal_dice
ped_s2:    // 2: Bless — random [12, 23] turn timer
    lda #12
    jsr rng_range
    clc
    adc #12
    sta zp_eff_bless
    rts
ped_s7:    // 7: Slow Poison — halve poison timer (min 1)
    lda zp_eff_poison
    beq ped_noop
    lsr
    ora #1
    sta zp_eff_poison
ped_noop:  // 3: Remove Fear — placeholder (also shared RTS)
    rts
ped_s8:    // 8: Blind Creature — directional, set MX_STUN
    jsr eff_directional_monster
    bcc !ped_s8_rts+
    jsr monster_get_ptr
    ldy #MX_STUN
    lda #10
    sta (zp_ptr0),y
!ped_s8_rts:
    rts
ped_s10:   // 10: Cure Medium Wounds — 3d8+3
    lda #3
    ldx #8
    ldy #3
    jmp heal_dice
ped_s11:   // 11: Chant — random [24, 47] turn timer
    lda #24
    jsr rng_range
    clc
    adc #24
    sta zp_eff_bless
    rts
ped_s14:   // 14: Cure Serious Wounds — 5d8+5
    lda #5
    ldx #8
    ldy #5
    jmp heal_dice

// Shared helper: roll NdS+B dice and heal
// Input: A=N, X=S, Y=B
heal_dice:
    jsr math_dice
    lda zp_math_a
    jmp eff_heal

// ============================================================
// String data (screen codes via inherited encoding)
// ============================================================
pm_header_str:
    .text "   Name              Mana Lvl" ; .byte 0
pm_bang_str:
    .byte $21, 0    // "!"

// ============================================================
// Compile-time asserts
// ============================================================
.assert "pm_spell_type mage", SPELL_MAGE, 1
.assert "pm_spell_type priest", SPELL_PRIEST, 2
