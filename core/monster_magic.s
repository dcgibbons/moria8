#importonce
// monster_magic.s — Monster spellcasting system
//
// Provides spell chance/LOS checking, spell selection, and 8 spell
// handlers for monster casters. Called from monster_process_one when
// the monster is awake, before confused/movement logic.
//
// Wound, Hold Person, blind, confuse and fear follow pinned VMS Moria
// creature.inc cast_spell (spells 8-13; Umoria monster.cpp is identical): the
// player first gets a saving throw (player_save.s) with wis_adj + level
// (ledger MON-011). Breath is spells 20-24 (MON-025).

// ============================================================
// Spell constants (MSF_* flags defined in monster.s)
// ============================================================
.const MAX_CAST_RANGE = 8
.const MM_SPELL_COUNT = 8      // Total spell types (one per cr_spell_flags bit)
.const MM_EFF_BLIND   = 0      // mm_effect_* table rows
.const MM_EFF_CONFUSE = 1
.const MM_EFF_FEAR    = 2
.const MM_EFF_HOLD    = 3
.const MM_SPELL_HOLD  = MM_SPELL_COUNT   // Hold Person's handler, after the MSF bits

#import "los_trace.s"
#import "player_save.s"

// ============================================================
// Scratch variables
// ============================================================
mm_flags:      .byte 0         // Available spell flags for current monster
mm_bit_count:  .byte 0         // Number of set bits (available spells)
mm_chosen:     .byte 0         // Randomly chosen spell index
mm_msf_count:  .byte 0         // How many of the choices are MSF bits
mm_kind:       .byte 0         // Breath element (MS_BREATH_*)
mm_divisor:    .byte 0         // Breath damage divisor

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
    and #MS_FREQ_MASK
    beq !mcc_no+
!mcc_has_chance:

    // Save the 1-in-N frequency for later roll
    sta mm_flags              // Reuse as temp for N

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

    // LOS is clear: VMS randint(N) = 1 casts
    lda mm_flags
    jsr rng_range             // [0, N-1]; Z for A
    bne !mcc_no+

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

    // VMS lists every spell bit as a choice: Hold Person is one more after
    // the MSF bits, and a Multi-Hued dragon's five breaths are five (its
    // MSF_BREATH and four more).
    lda mm_bit_count
    sta mm_msf_count
    ldx zp_mon_type
    lda cr_spell_chance,x
    asl                       // C = Hold Person; the element in bits 5-7
    bcc !mps_no_hold+
    inc mm_bit_count
!mps_no_hold:
    and #$e0
    cmp #MS_BREATH_ALL << (MS_BREATH_SHIFT + 1)
    bne !mps_one_breath+
    lda mm_bit_count
    adc #4 - 1                // C set: four more breaths
    sta mm_bit_count
!mps_one_breath:

    // Pick random spell index [0, bit_count-1]
    lda mm_bit_count
    beq !mps_done+            // No spells (shouldn't happen)
    jsr rng_range
    sta mm_chosen
    cmp mm_msf_count
    bcc !mps_msf+
    // Past the MSF bits: the first is Hold Person if the caster has it,
    // the others (or all of them without it) more breaths.
    bne !mps_breath+          // Not the first past them (Z from the cmp)
    ldy zp_mon_type
    lda cr_spell_chance,y
    bpl !mps_breath+          // No Hold Person: a breath
    ldx #MM_SPELL_HOLD
    bne !mps_dispatch+        // Always
!mps_breath:
    ldx #1                    // MSF_BREATH's handler
    bne !mps_dispatch+        // Always
!mps_msf:

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
    // X = handler: the bit position (0-7), or MM_SPELL_HOLD
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
    monster_cast_confuse, monster_cast_wound_serious, monster_cast_fear,
    monster_cast_hold)
mm_spell_lo:
    .fill MM_SPELL_COUNT + 1, <(mm_spell_handlers.get(i) - 1)
mm_spell_hi:
    .fill MM_SPELL_COUNT + 1, >(mm_spell_handlers.get(i) - 1)

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
// Spell handlers 5, 6, 8 and 9: blind, confuse, fear, Hold Person (VMS
// spells 11-13 and 10). Saved: "casts a spell." + resist message. Failed:
// Moria8's effect message (no status-line indicators, MON-011) and the VMS
// timer: a fresh effect rolls base + randint(sides), an active one is
// extended by a fixed step. Hold Person first leaves a player with Free
// Action (the Amulet of the Magi) unaffected.
// ============================================================
monster_cast_hold:
    lda player_pflags
    and #PFLAG_FREE_ACT
    beq !mch_held+
    jsr mm_print_cast_msg
    ldx #HSTR_CHEST_UNAFFECTED  // VMS "You are unaffected..." (MON-025)
    jmp huff_print_msg
!mch_held:
    ldx #MM_EFF_HOLD
    .byte $2c                 // BIT abs: skip the next ldx
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

//                    blind          confuse          fear           hold
mm_effect_msg:   .byte HSTR_MM_BLIND, HSTR_MM_CONFUSE, HSTR_MAT_FEAR, HSTR_MAT_PARALYZE
mm_effect_base:  .byte 12, 3, 3, 4    // VMS: 12+randint(3), randint(5)+3 x2, randint(5)+4
mm_effect_sides: .byte 3, 5, 5, 5
mm_effect_step:  .byte 6, 2, 2, 2     // Extension when already active
mm_effect_zp:    .byte zp_eff_blind, zp_eff_confuse, 0, zp_eff_paralyze   // fear: eff_fear_timer
.assert "mm_effect_zp holds zero-page timers", zp_eff_blind < $100 && zp_eff_confuse < $100 && zp_eff_paralyze < $100, true

// ============================================================
// Spell handler 2: monster_cast_breath (VMS spells 20-24, MON-025)
// "The <name> breathes lightning." (gas, acid, frost, fire), then the
// element's damage to the player from dam_hp = the breather's HP / 4 for
// lightning, / 3 otherwise, 16-bit and uncapped (VMS moria.inc light_dam,
// poison_gas, acid_dam, cold_dam, fire_dam). Acid: a worn armour piece takes
// it first (minus_ac) and halves it. Frost and fire: div 3 for the Resist
// Cold / Fire ring, div 3 again for the potion's timer. Gas: poisoned +
// 12 + randint(dam). One divide: trunc(trunc(a / b) / c) = trunc(a / bc).
// Moria8 leaves out the ball's effect on monsters, floor items and doors,
// and the pack damage (docs/BACKLOG.md, docs/FEATURE_MAP.md).
// ============================================================
monster_cast_breath:
    ldx zp_mon_type
    lda cr_spell_chance,x
    lsr
    lsr
    lsr
    lsr
    and #MS_BREATH_ALL | 1    // Bits 4-6 (Hold Person shifted out of them)
    cmp #MS_BREATH_ALL
    bcc !mcb_kind+
    lda #5                    // Multi-Hued: one of the five
    jsr rng_range
    adc #1                    // C clear: 1-5
!mcb_kind:
    sta mm_kind
    tax
    lda mm_breath_msg - 1,x
    tax
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg

    ldx mm_kind
    lda mm_breath_div - 1,x
    sta mm_divisor
    cpx #MS_BREATH_ACID
    bne !mcb_not_acid+
    jsr mon_atk_acid_armour   // C set: an armour piece was damaged
    bcc !mcb_divide+
    asl mm_divisor            // dam div 2
    bcc !mcb_divide+          // Always (3 x 2)
!mcb_not_acid:
    bcc !mcb_divide+          // Lightning, gas: no resistance here
    lda player_pflags
    and mm_resist_flag - MS_BREATH_FROST,x
    beq !mcb_no_ring+
    jsr mm_triple_divisor
!mcb_no_ring:
    ldy mm_resist_timer - MS_BREATH_FROST,x
    lda $0000,y
    beq !mcb_divide+
    jsr mm_triple_divisor
!mcb_divide:
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sta zp_math_a
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sta zp_math_b
    ldx mm_divisor
    jsr math_div_16x8
    lda mm_kind
    cmp #MS_BREATH_GAS
    bne !mcb_take+
    // Gas: poisoned + 12 + randint(dam) (randint(0) is 1 upstream), the
    // 8-bit timer saturating
    lda zp_math_a
    sta zp_temp0
    ldx zp_math_b
    stx zp_temp1
    ora zp_math_b
    bne !mcb_gas_roll+
    inc zp_temp0
!mcb_gas_roll:
    jsr rng_range_word        // zp_temp2/3 = randint(dam) - 1
    lda zp_temp3
    bne !mcb_gas_max+
    lda zp_temp2
    clc
    adc #13
    bcs !mcb_gas_max+
    adc zp_eff_poison
    bcc !mcb_gas_set+
!mcb_gas_max:
    lda #255
!mcb_gas_set:
    sta zp_eff_poison
!mcb_take:
    lda zp_math_a
    ldx zp_math_b
    jmp mm_apply_spell_damage_16

// mm_triple_divisor — mm_divisor x 3 (at most 3 x 3 x 3). Clobbers: A
mm_triple_divisor:
    lda mm_divisor
    asl
    adc mm_divisor            // C clear: the divisor is under 128
    sta mm_divisor
    rts

// By element (MS_BREATH_LIGHTNING = 1 .. MS_BREATH_FIRE = 5)
mm_breath_msg:
    .byte HSTR_MM_BREATH_LIGHTNING, HSTR_MM_BREATH_GAS, HSTR_MM_BREATH_ACID
    .byte HSTR_MM_BREATH_FROST, HSTR_MM_BREATH_FIRE
mm_breath_div:   .byte 4, 3, 3, 3, 3
mm_resist_flag:  .byte PFLAG_RESIST_COLD, PFLAG_RESIST_FIRE
mm_resist_timer: .byte eff_resist_cold_timer, zp_eff_resist
.assert "Breath tables follow the elements", MS_BREATH_LIGHTNING == 1 && MS_BREATH_GAS == 2 && MS_BREATH_ACID == 3 && MS_BREATH_FROST == 4 && MS_BREATH_FIRE == 5, true
.assert "Resist timers are zero-page", eff_resist_cold_timer < $100 && zp_eff_resist < $100, true

// mm_apply_spell_damage — A = damage; mm_apply_spell_damage_16: A = lo, X = hi
mm_apply_spell_damage:
    ldx #0
mm_apply_spell_damage_16:
    sta zp_combat_dmg
    stx mad_dmg_hi
    jsr mon_atk_apply_damage_16
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
