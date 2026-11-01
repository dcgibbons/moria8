#importonce
// monster_magic.s — Monster spellcasting system
//
// Provides spell chance/LOS checking, spell selection, and 8 spell
// handlers for monster casters. Called from monster_process_one when
// the monster is awake, before confused/movement logic.
//
// Wound, blind, confuse and fear follow pinned VMS Moria creature.inc
// cast_spell (spells 8, 9, 11, 12, 13; Umoria monster.cpp is identical): the
// player first gets a saving throw (player_save.s) with wis_adj + level
// (ledger MON-011).

// ============================================================
// Spell constants (MSF_* flags defined in monster.s)
// ============================================================
.const MAX_CAST_RANGE = 8
.const MM_SPELL_COUNT = 8      // Total spell types (one per cr_spell_flags bit)
.const MM_EFF_BLIND   = 0      // mm_effect_* table rows
.const MM_EFF_CONFUSE = 1
.const MM_EFF_FEAR    = 2

#import "los_trace.s"
#import "player_save.s"

// ============================================================
// Scratch variables
// ============================================================
mm_flags:      .byte 0         // Available spell flags for current monster
mm_bit_count:  .byte 0         // Number of set bits (available spells)
mm_chosen:     .byte 0         // Randomly chosen spell index

// ============================================================
// monster_can_cast — Check if monster wants to cast a spell
// Input:  zp_mon_type = creature type, zp_mon_x/y = position
// Output: carry set = cast, carry clear = no cast
// Clobbers: A, X, Y, zp_ptr0, zp_ptr0_hi, zp_temp0-3
// ============================================================
monster_can_cast:
    // Check spell chance — if 0, never casts
    ldx zp_mon_type
    lda cr_spell_chance,x
    beq !mcc_no+
!mcc_has_chance:

    // Save spell chance for later roll
    sta mm_flags              // Reuse as temp for chance

    jsr monster_distance_to_player
    sta zp_los_step
    cmp #MAX_CAST_RANGE + 1
    bcs !mcc_no+              // Too far
!mcc_in_range:

    // LOS check: step from monster toward player.
    lda zp_player_x
    sta zp_los_dx
    lda zp_player_y
    sta zp_los_dy
    lda zp_mon_x
    sta mm_los_cx
    lda zp_mon_y
    sta mm_los_cy
    jsr mm_los_clear_to_target
    bcc !mcc_no+

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
    // X = bit position (spell index 0-7)
    // Track spell in recall
#if HAL_PLATFORM_AUX_PERSISTENT_DATA
    ldy zp_mon_type
    :AuxReadY(recall_spells)
    ora recall_spell_bit,x
    :AuxWriteY(recall_spells)
#else
    lda recall_spell_bit,x
    ldy zp_mon_type
    ora recall_spells,y
    :AuxWriteY(recall_spells)
#endif
    // Dispatch through the handler table (RTS jump: push address - 1)
    lda mm_spell_hi,x
    pha
    lda mm_spell_lo,x
    pha
    rts

// Handlers in cr_spell_flags bit order (MSF_* in monster.s)
.var mm_spell_handlers = List().add(monster_cast_wound_light, monster_cast_breath,
    monster_cast_summon, monster_cast_teleport, monster_cast_blind,
    monster_cast_confuse, monster_cast_wound_serious, monster_cast_fear)
mm_spell_lo:
    .fill MM_SPELL_COUNT, <(mm_spell_handlers.get(i) - 1)
mm_spell_hi:
    .fill MM_SPELL_COUNT, >(mm_spell_handlers.get(i) - 1)

// ============================================================
// mm_print_spell_msg — Print "THE <name> <suffix>"
// Input: zp_ptr2/hi = suffix string pointer
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, cmb_buf_idx
// ============================================================
mm_print_spell_msg:
    // Same "THE <name><suffix>" build as monster melee messages; the name
    // comes from cmb_type, which player combat always sets before reading.
    lda zp_mon_type
    sta cmb_type
    jmp mon_atk_build_effect_msg

// ============================================================
// Spell handlers 1 and 7: Cause Light / Serious Wounds
// "THE <name> casts a spell.", then 3d8 / 8d8 damage unless the player
// saves (VMS spells 8 and 9).
// ============================================================
monster_cast_wound_serious:
    lda #8
    .byte $2c                 // BIT abs: skip the next lda #3
monster_cast_wound_light:
    lda #3
    pha                       // Dice count
    jsr mm_print_cast_msg
    jsr mm_spell_save
    pla
    bcc mm_print_resist       // Saved: no damage
    ldx #8                    // d8
    ldy #0
    jsr math_dice             // 3..24 or 8..64
    lda zp_math_a
    jmp mm_apply_spell_damage

// mm_print_cast_msg — "THE <name> casts a spell."
mm_print_cast_msg:
    ldx #HSTR_MM_CAST
    jsr huff_decode_to_ptr2
    jmp mm_print_spell_msg

// mm_spell_save — Saving throw against a monster spell: VMS
// player_saves(wis_adj + lev). Output: carry clear = resisted.
mm_spell_save:
    lda player_data + PL_WIS_CUR
    jsr player_wis_save_adj
    clc
    adc zp_player_lvl
    jmp player_saving_throw

// mm_cast_resisted — "THE <name> casts a spell." + the resist message.
mm_cast_resisted:
    jsr mm_print_cast_msg
mm_print_resist:
    ldx #HSTR_MM_RESIST
    jmp huff_print_msg

// ============================================================
// Spell handlers 5, 6 and 8: blind, confuse, fear (VMS spells 11-13)
// Saved: "casts a spell." + resist message. Failed: Moria8's effect message
// (no status-line indicators, MON-011) and the VMS timer: a fresh effect
// rolls base + randint(sides), an active one is extended by a fixed step.
// ============================================================
monster_cast_blind:
    ldx #MM_EFF_BLIND
    .byte $2c                 // BIT abs: skip the next ldx
monster_cast_confuse:
    ldx #MM_EFF_CONFUSE
    jsr mm_effect_save
    bcc !done+
    ldx mm_chosen
    ldy mm_effect_zp,x        // Zero-page timer of this effect
    lda $0000,y
    jsr mm_effect_timer       // Preserves Y
    sta $0000,y
!done:
    rts

// Heroism makes the player immune, as for the fear touch (monster_attack.s).
monster_cast_fear:
    lda zp_eff_hero
    bne mm_cast_resisted
    ldx #MM_EFF_FEAR
    jsr mm_effect_save
    bcc !done+
    lda eff_fear_timer
    jsr mm_effect_timer
    sta eff_fear_timer
!done:
    rts

// mm_effect_save — Saving throw for effect X, then its message.
// Output: carry clear = resisted (messages printed), carry set = affected
// (effect message printed). Saves X in mm_chosen for mm_effect_timer.
mm_effect_save:
    stx mm_chosen
    jsr mm_spell_save
    bcs !affected+
    jsr mm_cast_resisted
    clc
    rts
!affected:
    ldx mm_chosen
    lda mm_effect_msg,x
    tax
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg
    sec
    rts

// mm_effect_timer — New effect timer (VMS stacking), saturating at 255.
// Input: A = current timer, mm_chosen = effect. Output: A = new timer.
// Preserves: Y (rng_range preserves Y)
mm_effect_timer:
    ldx mm_chosen
    cmp #0
    beq !fresh+
    clc
    adc mm_effect_step,x
    bcc !done+
    lda #255
!done:
    rts
!fresh:
    lda mm_effect_sides,x
    jsr rng_range             // 0..sides-1
    ldx mm_chosen
    sec                       // + 1: randint(sides)
    adc mm_effect_base,x
    rts

//                    blind          confuse          fear
mm_effect_msg:   .byte HSTR_MM_BLIND, HSTR_MM_CONFUSE, HSTR_MAT_FEAR
mm_effect_base:  .byte 12, 3, 3       // VMS: 12+randint(3), randint(5)+3 x2
mm_effect_sides: .byte 3, 5, 5
mm_effect_step:  .byte 6, 2, 2        // Extension when already active
mm_effect_zp:    .byte zp_eff_blind, zp_eff_confuse

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

    // HP div 3, then (this path models only fire breath) VMS Moria
    // fire_dam (moria.inc; Umoria inventory.cpp damageFire): the Resist
    // Fire ring divides by 3 and the Resist Heat timer by 3 again, so both
    // together leave dam div 9. Resistance applies before the 8-bit damage
    // cap. Resist Cold has no cold damage to reduce in Moria8.
    lda player_pflags
    and #PFLAG_RESIST_FIRE    // 1 with the ring
    ldy zp_eff_resist
    beq !mcb_no_timer+
    clc
    adc #1                    // +1 with the timer
!mcb_no_timer:
    tay
    iny                       // Y = 1-3 divides by 3
!mcb_div3:
    ldx #3
    jsr math_div_16x8         // zp_math_a/b = quotient; preserves Y
    dey
    bne !mcb_div3-

    // Cap at 255 (if hi byte nonzero)
    lda zp_math_b
    beq !mcb_no_cap+
    lda #255
    bne !mcb_apply+             // Always
!mcb_no_cap:
    lda zp_math_a
!mcb_apply:
    // Fall through
.assert "monster_cast_breath counts PFLAG_RESIST_FIRE as 1", PFLAG_RESIST_FIRE, 1

mm_apply_spell_damage:
    sta zp_combat_dmg
    jsr mon_atk_apply_damage
    bcs !masd_dead+
    lda #SFX_HIT
    jmp hal_sound_play
!masd_dead:
    ldx zp_mon_type
    :AuxIncX(recall_deaths)
    stx zp_death_source
    jmp player_death_check

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
    jsr map_row_ptr0_x
    ldy ms_spawn_x
    :MapRead_ptr0_y()
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

    // Spawn a depth-appropriate dungeon creature using the shared selector.
    lda zp_player_dlvl
    beq !mcs_fail+
    jsr tier_check_transition
    jsr pick_creature_type
    jsr monster_spawn_one
    // Ignore failure (table could be full)

!mcs_fail:
    rts

// ============================================================
// Spell handler 4: monster_cast_teleport — Teleport To (VMS spell 7)
// "THE <name> casts a spell.", then the player lands on a free floor square
// next to the caster (VMS spells.inc teleport_to; Umoria
// spellTeleportPlayerTo). Upstream tries squares within 1 of the caster and
// widens the ring after 10 misses; Moria8 tries the 8 neighbours
// (find_adjacent_empty, never the player's own square) and leaves the
// player in place when all are blocked.
// ============================================================
monster_cast_teleport:
    jsr mm_print_cast_msg
    jsr find_adjacent_empty_mon // → ms_spawn_x/y
    bcc !mct_done+
    lda ms_spawn_x
    ldy ms_spawn_y
    jmp eff_teleport_apply_target
!mct_done:
    rts


// Strings migrated to Huffman compression (HSTR_MM_* in huffman_data.s)
