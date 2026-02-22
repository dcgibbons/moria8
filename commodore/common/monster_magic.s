// monster_magic.s — Monster spellcasting system
//
// Provides spell chance/LOS checking, spell selection, and 7 spell
// handlers for monster casters. Called from monster_process_one when
// the monster is awake, before confused/movement logic.
//
// Six spellcasting creatures (IDs 20-25) have nonzero spell_chance,
// active on dungeon levels 3-5.

// ============================================================
// Spell constants (MSF_* flags defined in monster.s)
// ============================================================
.const MAX_CAST_RANGE = 8
.const MM_SPELL_COUNT = 7      // Total spell types

// ============================================================
// Scratch variables
// ============================================================
mm_flags:      .byte 0         // Available spell flags for current monster
mm_bit_count:  .byte 0         // Number of set bits (available spells)
mm_chosen:     .byte 0         // Randomly chosen spell index
mm_los_cx:     .byte 0         // LOS trace current X
mm_los_cy:     .byte 0         // LOS trace current Y
mm_los_sdx:    .byte 0         // LOS step direction X (-1/0/+1)
mm_los_sdy:    .byte 0         // LOS step direction Y (-1/0/+1)

// ============================================================
// monster_can_cast — Check if monster wants to cast a spell
// Input:  zp_mon_type = creature type, zp_mon_x/y = position
// Output: carry set = cast, carry clear = no cast
// Clobbers: A, X, Y, zp_ptr0, zp_temp3, zp_temp4
// ============================================================
monster_can_cast:
    // Check spell chance — if 0, never casts
    ldx zp_mon_type
    lda cr_spell_chance,x
    bne !mcc_has_chance+
    jmp !mcc_no+
!mcc_has_chance:

    // Save spell chance for later roll
    sta mm_flags              // Reuse as temp for chance

    // Compute Chebyshev distance to player
    lda zp_player_x
    sec
    sbc zp_mon_x
    bcs !mcc_dx_pos+
    eor #$ff
    clc
    adc #1
!mcc_dx_pos:
    sta zp_mon_scratch0       // abs_dx

    lda zp_player_y
    sec
    sbc zp_mon_y
    bcs !mcc_dy_pos+
    eor #$ff
    clc
    adc #1
!mcc_dy_pos:
    // A = abs_dy, compare with abs_dx for max
    cmp zp_mon_scratch0
    bcs !mcc_have_dist+
    lda zp_mon_scratch0
!mcc_have_dist:
    // A = Chebyshev distance
    cmp #MAX_CAST_RANGE + 1
    bcc !mcc_in_range+
    jmp !mcc_no+              // Too far
!mcc_in_range:

    // LOS check: step from monster toward player
    // Compute sign(dx) and sign(dy)
    lda zp_player_x
    cmp zp_mon_x
    beq !mcc_sdx_zero+
    bcs !mcc_sdx_pos+
    lda #$ff
    sta mm_los_sdx
    jmp !mcc_sdy+
!mcc_sdx_pos:
    lda #$01
    sta mm_los_sdx
    jmp !mcc_sdy+
!mcc_sdx_zero:
    lda #$00
    sta mm_los_sdx

!mcc_sdy:
    lda zp_player_y
    cmp zp_mon_y
    beq !mcc_sdy_zero+
    bcs !mcc_sdy_pos+
    lda #$ff
    sta mm_los_sdy
    jmp !mcc_los_trace+
!mcc_sdy_pos:
    lda #$01
    sta mm_los_sdy
    jmp !mcc_los_trace+
!mcc_sdy_zero:
    lda #$00
    sta mm_los_sdy

!mcc_los_trace:
    // Start from monster position
    lda zp_mon_x
    sta mm_los_cx
    lda zp_mon_y
    sta mm_los_cy

!mcc_los_step:
    // Step toward player
    lda mm_los_cx
    clc
    adc mm_los_sdx
    sta mm_los_cx
    lda mm_los_cy
    clc
    adc mm_los_sdy
    sta mm_los_cy

    // Check if we reached player position
    lda mm_los_cx
    cmp zp_player_x
    bne !mcc_los_check_tile+
    lda mm_los_cy
    cmp zp_player_y
    beq !mcc_los_clear+       // Reached player — LOS clear

!mcc_los_check_tile:
    // Read map tile and check walkability
    ldx mm_los_cy
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mm_los_cx
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr                       // Tile type index 0-15
    tax
    lda walkable_table,x
    bne !mcc_los_cont+
    jmp !mcc_no+              // Blocked — no LOS
!mcc_los_cont:
    jmp !mcc_los_step-

!mcc_los_clear:
    // LOS is clear — roll to decide if monster casts
    lda #100
    jsr rng_range             // [0, 99]
    cmp mm_flags              // Compare with spell chance
    bcs !mcc_no+              // roll >= chance → chose melee

    sec                       // Monster casts
    rts

!mcc_no:
    clc                       // No cast
    rts

// ============================================================
// monster_pick_spell — Select and execute a random spell
// Input:  zp_mon_type, zp_mon_idx = monster index
// Clobbers: everything
// ============================================================
monster_pick_spell:
    // Load spell flags for this creature type
    ldx zp_mon_type
    lda cr_spell_flags,x
    sta mm_flags

    // Count set bits
    lda #0
    sta mm_bit_count
    lda mm_flags
    ldx #MM_SPELL_COUNT
!mps_count:
    lsr                       // Shift bit into carry
    bcc !mps_no_bit+
    inc mm_bit_count
!mps_no_bit:
    dex
    bne !mps_count-

    // Pick random spell index [0, bit_count-1]
    lda mm_bit_count
    beq !mps_done+            // No spells (shouldn't happen)
    jsr rng_range
    sta mm_chosen

    // Walk bits again to find the Nth set bit
    lda mm_flags
    ldx #0                    // Bit position counter
    ldy #0                    // Set bit counter
!mps_find:
    lsr                       // Shift bit 0 into carry
    bcc !mps_skip+
    // This bit is set — is it the one we want?
    cpy mm_chosen
    beq !mps_dispatch+
    iny
!mps_skip:
    inx
    cpx #MM_SPELL_COUNT
    bcc !mps_find-

!mps_done:
    rts

!mps_dispatch:
    // X = bit position (spell index 0-6)
    // Track spell in recall
    lda recall_spell_bit,x
    ldy zp_mon_type
    ora recall_spells,y
    sta recall_spells,y
    // Dispatch
    cpx #0
    beq !mps_bolt+
    cpx #1
    beq !mps_breath+
    cpx #2
    beq !mps_summon+
    cpx #3
    beq !mps_teleport+
    cpx #4
    beq !mps_blind+
    cpx #5
    beq !mps_confuse+
    cpx #6
    beq !mps_heal+
    rts

!mps_bolt:
    jmp monster_cast_bolt
!mps_breath:
    jmp monster_cast_breath
!mps_summon:
    jmp monster_cast_summon
!mps_teleport:
    jmp monster_cast_teleport
!mps_blind:
    jmp monster_cast_blind
!mps_confuse:
    jmp monster_cast_confuse
!mps_heal:
    jmp monster_cast_heal

// ============================================================
// mm_print_monster_name — Print "THE <name>" to message line
// Input: zp_mon_type = creature type
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, cmb_buf_idx
// ============================================================
mm_print_monster_name:
    lda #0
    sta cmb_buf_idx

    lda #<cmb_the_str + 1
    ldy #>cmb_the_str + 1
    jsr combat_append_str

    ldx zp_mon_type
    jsr creature_get_name       // A=lo, Y=hi (handles KERNAL banking)
    jsr combat_append_str
    rts

// ============================================================
// mm_print_spell_msg — Print "THE <name> <suffix>"
// Input: zp_ptr2/hi = suffix string pointer
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, cmb_buf_idx
// ============================================================
mm_print_spell_msg:
    jsr mm_print_monster_name

    lda zp_ptr2
    ldy zp_ptr2_hi
    jsr combat_append_str

    // Null-terminate
    jsr cmb_term_and_print
    rts

// ============================================================
// Spell handler 1: monster_cast_bolt
// Bolt does 2d8 + creature level damage to player
// ============================================================
monster_cast_bolt:
    // Print "THE <name> CASTS A BOLT!"
    ldx #HSTR_MM_BOLT
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    // Roll 2d8 + level
    ldx zp_mon_type
    lda cr_level,x
    tay                       // Y = bonus (level)
    lda #2                    // A = 2 dice
    ldx #8                    // X = 8 sides
    jsr math_dice             // → zp_math_a

    lda zp_math_a
    sta zp_combat_dmg
    jsr mon_atk_apply_damage
    bcs !mcb_dead+

    lda #SFX_HIT
    jsr sound_play
    rts
!mcb_dead:
    ldx zp_mon_type
    inc recall_deaths,x
    stx zp_death_source
    jsr player_death_check
    rts

// ============================================================
// Spell handler 2: monster_cast_breath
// Breath does monster HP/3 damage (capped at 255)
// ============================================================
monster_cast_breath:
    // Print "THE <name> BREATHES FIRE!"
    ldx #HSTR_MM_BREATH
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    // Get monster HP (16-bit)
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sta zp_math_a
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sta zp_math_b

    // Divide by 3
    ldx #3
    jsr math_div_16x8         // zp_math_a = quotient lo, zp_math_b = quotient hi

    // Cap at 255 (if hi byte nonzero)
    lda zp_math_b
    beq !mcb_no_cap+
    lda #255
    jmp !mcb_apply+
!mcb_no_cap:
    lda zp_math_a
!mcb_apply:
    sta zp_combat_dmg
    jsr mon_atk_apply_damage
    bcs !mcbr_dead+

    lda #SFX_HIT
    jsr sound_play
    rts
!mcbr_dead:
    ldx zp_mon_type
    inc recall_deaths,x
    stx zp_death_source
    jsr player_death_check
    rts

// ============================================================
// Spell handler 3: monster_cast_summon
// Summon a random monster adjacent to the caster
// ============================================================
monster_cast_summon:
    // Print "THE <name> SUMMONS HELP!"
    ldx #HSTR_MM_SUMMON
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    // Try to find a walkable adjacent tile
    lda #8
    jsr rng_range             // Random direction [0, 7]
    tax
    lda zp_mon_x
    clc
    adc dir_dx,x
    sta ms_spawn_x
    lda zp_mon_y
    clc
    adc dir_dy,x
    sta ms_spawn_y

    // Check if tile is walkable and unoccupied
    ldx ms_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    lda (zp_ptr0),y
    sta zp_mon_scratch2       // Save tile byte

    // Check walkable
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    tax
    lda walkable_table,x
    beq !mcs_fail+            // Not walkable

    // Check not occupied
    lda zp_mon_scratch2
    and #FLAG_OCCUPIED
    bne !mcs_fail+

    // Spawn random dungeon creature (not town)
    lda active_dungeon_count
    beq !mcs_fail+              // No dungeon creatures → skip
    jsr rng_range
    jsr monster_spawn_one
    // Ignore failure (table could be full)

!mcs_fail:
    rts

// ============================================================
// Spell handler 4: monster_cast_teleport
// Teleport the player to a random floor tile
// ============================================================
monster_cast_teleport:
    // Print "THE <name> TELEPORTS YOU!"
    ldx #HSTR_MM_TELEPORT
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    jsr eff_teleport_self
    rts

// ============================================================
// Spell handler 5: monster_cast_blind
// Blind the player for 1d10+10 turns
// ============================================================
monster_cast_blind:
    // Print "THE <name> BLINDS YOU!"
    ldx #HSTR_MM_BLIND
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    // Roll 1d10+10
    lda #1                    // 1 die
    ldx #10                   // 10 sides
    ldy #10                   // +10 bonus
    jsr math_dice
    lda zp_math_a
    sta zp_eff_blind
    rts

// ============================================================
// Spell handler 6: monster_cast_confuse
// Confuse the player for 1d5+5 turns
// ============================================================
monster_cast_confuse:
    // Print "THE <name> CONFUSES YOU!"
    ldx #HSTR_MM_CONFUSE
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    // Roll 1d5+5
    lda #1                    // 1 die
    ldx #5                    // 5 sides
    ldy #5                    // +5 bonus
    jsr math_dice
    lda zp_math_a
    sta zp_eff_confuse
    rts

// ============================================================
// Spell handler 7: monster_cast_heal
// Heal the monster for 3d8 HP (capped at max)
// ============================================================
monster_cast_heal:
    // Print "THE <name> HEALS ITSELF."
    ldx #HSTR_MM_HEAL
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    // Roll 3d8
    lda #3                    // 3 dice
    ldx #8                    // 8 sides
    ldy #0                    // No bonus
    jsr math_dice             // → zp_math_a (lo), zp_math_b (hi)

    // Add to monster HP
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    clc
    adc zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    adc zp_math_b
    sta (zp_ptr0),y

    // Cap at max HP (cr_hd_num * cr_hd_sides)
    // Compute max HP for this creature type
    ldx zp_mon_type
    lda cr_hd_num,x
    sta zp_temp0
    lda cr_hd_sides,x
    tax                       // X = sides
    lda zp_temp0              // A = num
    jsr math_multiply         // zp_math_a = max HP lo, zp_math_b = max HP hi

    // Compare current HP (16-bit) with max
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    cmp zp_math_b
    bcc !mch_ok+              // HP hi < max hi → ok
    bne !mch_clamp+           // HP hi > max hi → clamp
    // Hi bytes equal, compare lo
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp zp_math_a
    bcc !mch_ok+              // HP lo < max lo → ok
    beq !mch_ok+              // Equal → ok

!mch_clamp:
    // Clamp to max
    ldy #MX_HP_LO
    lda zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda zp_math_b
    sta (zp_ptr0),y

!mch_ok:
    rts

// Strings migrated to Huffman compression (HSTR_MM_* in huffman_data.s)
