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
.const MAX_CAST_RANGE   = 8
.const MM_SPELL_COUNT   = 8      // Total MSF_* spell bits (handlers 0..7)
#if !C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED
.const MM_SPELL2_COUNT  = 5      // Extended MSF2_* spell bits (handlers 8..12)
#else
.const MM_SPELL2_COUNT  = 0      // Legacy C64 unit tests park monster_magic in 4 KB TestCreateOverlay
#endif
.const MSF2_SPELL_MASK  = $1f
.const MM_EFF_BLIND     = 0      // mm_effect_* table rows
.const MM_EFF_CONFUSE   = 1
.const MM_EFF_FEAR      = 2
.const MM_EFF_HOLD      = 3
.const MM_RECALL_HOLD   = MM_SPELL_COUNT      // 8: recall_spell_bit[8] == 1
.const MM_SPELL_HOLD    = MM_SPELL_COUNT + MM_SPELL2_COUNT
.const MM_HANDLER_COUNT = MM_SPELL_HOLD + 1

#import "los_trace.s"
#import "player_save.s"
#import "element_resist.s"

// ============================================================
// Scratch variables
// ============================================================
mm_flags:      .byte 0         // Available MSF spell flags for current monster
mm_flags2:     .byte 0         // Available MSF2 spell flags (& $1f)
mm_bit_count:  .byte 0         // Number of set bits (available spells)
mm_chosen:     .byte 0         // Randomly chosen spell index / handler scratch
mm_msf_count:  .byte 0         // How many of the choices are MSF + MSF2 bits
mm_kind:       .byte 0         // Breath element (MS_BREATH_*) / temp scratch

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
    // Save the 1-in-N frequency; also require >= 1 spell in MSF, MSF2[4:0], or MS_HOLD
    sta mm_flags              // Reuse as temp for N
    lda cr_spell_flags2,x
    and #MSF2_SPELL_MASK
    ora cr_spell_flags,x
    bne !mcc_has_chance+
    lda cr_spell_chance,x
    bpl !mcc_no+
!mcc_has_chance:

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

// mm_count_bits_a — Add set-bit count of A into mm_bit_count. Clobbers: A
mm_count_bits_a:
!mcba_loop:
    beq !mcba_done+
    lsr
    bcc !mcba_loop-
    inc mm_bit_count
    bne !mcba_loop-           // Always (<= 13)
!mcba_done:
    rts

// ============================================================
// monster_pick_spell — Select and execute a random spell
// Input:  zp_mon_type, zp_mon_idx = monster index
// Clobbers: everything
// ============================================================
monster_pick_spell:
    // Load and count spell flags (MSF + MSF2[4:0]) for this creature type
    lda #0
    sta mm_bit_count
    ldx zp_mon_type
    lda cr_spell_flags,x
    sta mm_flags
    jsr mm_count_bits_a
    lda cr_spell_flags2,x
    and #MSF2_SPELL_MASK
    sta mm_flags2
    jsr mm_count_bits_a

    // VMS lists every spell bit as a choice: Hold Person is one more after
    // the MSF/MSF2 bits, and a Multi-Hued dragon's five breaths are five
    // (its MSF_BREATH and four more).
    lda mm_bit_count
    sta mm_msf_count
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
    // Past the MSF+MSF2 bits: the first is Hold Person if the caster has it,
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

    // Walk 13 bits across (mm_flags2:mm_flags) -> handler 0..12
    ldx #0                    // Handler index
    ldy #0                    // Set bit counter
!mps_find:
    lsr mm_flags2
    ror mm_flags
    bcc !mps_skip+
    cpy mm_chosen
    beq !mps_dispatch+
    iny
!mps_skip:
    inx
    cpx #MM_SPELL_HOLD
    bcc !mps_find-

!mps_done:
    rts

!mps_dispatch:
    // X = handler (0..13); clamp recall bit lookup to <= 8 (recall_spell_bit[8] == 1)
    stx mm_chosen
    cpx #MM_RECALL_HOLD
    bcc !mps_recall_ok+
    ldx #MM_RECALL_HOLD
!mps_recall_ok:
#if HAL_PLATFORM_MONSTER_CATALOG
    ldy zp_mon_type
    jsr recall_or_spell_slot
#else
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
#endif
    // Dispatch through the handler table (RTS jump: push address - 1)
    ldx mm_chosen
    lda mm_spell_hi,x
    pha
    lda mm_spell_lo,x
    pha
    rts

// Handlers in cr_spell_flags bit order (0..7), cr_spell_flags2[4:0] (8..12), and Hold Person
#if !C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED
.var mm_spell_handlers = List().add(monster_cast_wound_light, monster_cast_breath,
    monster_cast_summon, monster_cast_teleport, monster_cast_blind,
    monster_cast_confuse, monster_cast_wound_serious, monster_cast_fear,
    monster_cast_blink, monster_cast_tele_self, monster_cast_summon_undead,
    monster_cast_slow, monster_cast_drain_mana,
    monster_cast_hold)
#else
.var mm_spell_handlers = List().add(monster_cast_wound_light, monster_cast_breath,
    monster_cast_summon, monster_cast_teleport, monster_cast_blind,
    monster_cast_confuse, monster_cast_wound_serious, monster_cast_fear,
    monster_cast_hold)
#endif
mm_spell_lo:
    .fill MM_HANDLER_COUNT, <(mm_spell_handlers.get(i) - 1)
mm_spell_hi:
    .fill MM_HANDLER_COUNT, >(mm_spell_handlers.get(i) - 1)

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
mm_unaffected_cast:
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

#if !C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED
// MSF2_SLOW ($08): VMS spell 16 — Free Action + wis save, else slow player
monster_cast_slow:
    lda player_pflags
    and #PFLAG_FREE_ACT
    bne mm_unaffected_cast
    jsr mm_print_cast_msg
    jsr mm_spell_save
    bcc mm_print_resist
    lda zp_eff_speed
    bmi !mcsl_ext+
    lda #5
    jsr rng_range
    adc #4                      // C clear: VMS randint(5) + 3 = 4..8
    bne !mcsl_apply+
!mcsl_ext:
    lda #2                      // Extend active slow by 2
!mcsl_apply:
    sta mm_kind
    lda zp_eff_speed
    sec
    sbc mm_kind
    bvc !mcsl_store+
    lda #$80                    // Clamp at -128
!mcsl_store:
    sta zp_eff_speed
    ldx #HSTR_EFF_HASTE_END
    jmp huff_print_msg
#endif

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
    cpx #MS_BREATH_ACID
    beq !mcb_acid+
    jsr mm_element_divisor_entry
    jmp !mcb_divide+
!mcb_acid:
    sta mm_divisor
    // VMS acid_dam: an armour piece damaged (or resisting) halves, acid
    // resistance divides by 3, both by 4: 3 x 1, 2, 3 or 4.
    jsr mon_atk_acid_armour   // C set: a piece took it (damaged or resisted)
    bcc !mcb_acid_resist+
    lda #3 * 2
    sta mm_divisor
!mcb_acid_resist:
    lda player_pflags
    and #PFLAG_RESIST_ACID
    beq !mcb_divide+
    lda mm_divisor
    clc
    adc #3 * 2                // 3 -> 9 (div 3), 6 -> 12 (div 4)
    sta mm_divisor
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


// By element (MS_BREATH_LIGHTNING = 1 .. MS_BREATH_FIRE = 5)
mm_breath_msg:
    .byte HSTR_MM_BREATH_LIGHTNING, HSTR_MM_BREATH_GAS, HSTR_MM_BREATH_ACID
    .byte HSTR_MM_BREATH_FROST, HSTR_MM_BREATH_FIRE
mm_breath_div:   .byte 4, 3, 3, 3, 3
.assert "Breath tables follow the elements", MS_BREATH_LIGHTNING == 1 && MS_BREATH_GAS == 2 && MS_BREATH_ACID == 3 && MS_BREATH_FROST == 4 && MS_BREATH_FIRE == 5, true

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
#if HAL_PLATFORM_MONSTER_CATALOG
    jsr recall_inc_deaths_slot
#else
    :AuxIncX(recall_deaths)
#endif
    stx zp_death_source
    jmp player_death_check

// ============================================================
// Spell handlers 3 & 11: monster_cast_summon / monster_cast_summon_undead
// VMS creature.inc cast_spell 14/15: summon_monster / summon_undead at the
// player's square (char_row/char_col), the creature placed awake (slp false).
// ============================================================
monster_cast_summon:
#if !C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED
    lda #0
    .byte $2c                   // BIT abs: skip lda #1
monster_cast_summon_undead:
    lda #1
    sta mm_chosen
#endif
    ldx #HSTR_MM_SUMMON
    jsr huff_decode_to_ptr2
    jsr mm_print_spell_msg
    jsr find_adjacent_empty_player  // → ms_spawn_x/y
    bcc !mcs_done+
#if !C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED
    lda mm_chosen
    beq !mcs_monster+
    jsr pick_undead_creature_type
    bcs !mcs_spawn+
    rts
!mcs_monster:
#endif
    jsr tier_check_transition
    jsr pick_summon_creature_type   // VMS summon_monster: dlvl + mon$summon_adj
!mcs_spawn:
    jsr monster_spawn_awake
    inc zp_dirty_count
!mcs_done:
    rts

// pick_undead_creature_type — VMS misc.inc summon_undead's creature: an undead
// from the whole catalog, any level (cat_undead[35], MON-033), whatever the
// depth. The monster spell and the Summon Undead scroll. A port short of
// resident room may place it beside cat_undead with :UndeadPickSegment() /
// :UndeadPickRestoreSegment() (the Atari: ATARI.BNK, RAM in game banking).
// Output: C = 1, A = creature slot; C = 0 none (a tier roster without undead)
// Clobbers: X, Y, zp_temp0-4
#if !UNDEAD_PICK_SEGMENT_CUSTOM
.macro UndeadPickSegment() {}
.macro UndeadPickRestoreSegment() {}
#endif
:UndeadPickSegment()
pick_undead_creature_type:
#if HAL_PLATFORM_MONSTER_CATALOG
    lda #35
    jsr rng_range
    tax
    :CatalogMap()
!mcsu_byte:
    lda cat_undead,x
    bne !mcsu_found_byte+
    inx
    cpx #35
    bcc !mcsu_byte-
    ldx #0
    beq !mcsu_byte-
!mcsu_found_byte:
    ldy #0
!mcsu_scan_bits:
    lsr
    bcs !mcsu_got_id+
    iny
    bne !mcsu_scan_bits-
!mcsu_got_id:
    lda #0
    sta cat_id_hi
    txa
    asl
    asl
    asl
    rol cat_id_hi
    sty mm_kind
    ora mm_kind
    sta cat_id_lo
    :CatalogUnmap()
    jsr catalog_slot_for_id
    sec
    rts
#else
    jsr tier_check_transition
    lda #0
    sta mm_bit_count
    tay
!mcsu_cnt_loop:
    cpy active_dungeon_count
    bcs !mcsu_cnt_done+
    lda cr_mflags,y
    and #CF_UNDEAD
    beq !mcsu_cnt_next+
    inc mm_bit_count
!mcsu_cnt_next:
    iny
    bne !mcsu_cnt_loop-
!mcsu_cnt_done:
    lda mm_bit_count
    clc
    beq !mcsu_none+
    jsr rng_range
    sta mm_kind
    ldy #0
!mcsu_pick_loop:
    lda cr_mflags,y
    and #CF_UNDEAD
    beq !mcsu_pick_next+
    lda mm_kind
    beq !mcsu_got_slot+
    dec mm_kind
!mcsu_pick_next:
    iny
    bne !mcsu_pick_loop-
!mcsu_got_slot:
    tya
    sec
!mcsu_none:
    rts
#endif
:UndeadPickRestoreSegment()

// ============================================================
// Spell handler 4: monster_cast_teleport — Teleport To (VMS spell 7)
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

#if !C64_UNIT_TEST || MONSTER_MAGIC_PRODUCTION_EXTENDED
// ============================================================
// Extended MSF2_* spell handlers (VMS creature.inc cast_spell 5, 6, 16, 17)
// ============================================================

// MSF2_BLINK ($01) & MSF2_TELE_SELF ($02): self-teleport ~10 or long-range
monster_cast_blink:
    lda #10
    .byte $2c                   // BIT abs: skip lda #60
monster_cast_tele_self:
    lda #60                     // Long-range across floor; >0 rejects own tile
    sta mm_kind
    lda #8
    sta mm_bit_count
    lda zp_player_x
    sta mm_flags
    lda zp_player_y
    sta mm_flags2
    lda zp_mon_x
    sta zp_player_x
    lda zp_mon_y
    sta zp_player_y
!mcts_try:
    lda mm_kind
    jsr find_random_floor_near
    bcc !mcts_restore+
    lda df_target_x
    cmp mm_flags
    bne !mcts_apply+
    lda df_target_y
    cmp mm_flags2
    bne !mcts_apply+
    dec mm_bit_count
    bne !mcts_try-
    beq !mcts_restore+
!mcts_apply:
#if HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
    jsr eff_move_caster_to_target
#else
    ldx zp_mon_y
    ldy zp_mon_x
    jsr mm_toggle_occ_xy
    ldx df_target_y
    stx zp_mon_y
    ldy df_target_x
    sty zp_mon_x
    jsr mm_toggle_occ_xy
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda zp_mon_x
    sta (zp_ptr0),y
    iny                         // MX_Y
    lda zp_mon_y
    sta (zp_ptr0),y
    inc zp_dirty_count
#endif
!mcts_restore:
    lda mm_flags
    sta zp_player_x
    lda mm_flags2
    sta zp_player_y
    rts

#if !HAL_PLATFORM_MONSTER_BANK1_TIER_NAMES
mm_toggle_occ_xy:
    jsr map_row_ptr0_x
    :MapRead_ptr0_y()
    eor #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    rts
#endif

// MSF2_DRAIN_MANA ($10): VMS spell 17 — drain randint(lev)/2 + 1 MP, heal 6*r1 HP
monster_cast_drain_mana:
    lda zp_player_mp
    beq !mcdm_done+
    sta mm_flags2               // Save current player MP
    ldx zp_mon_type
    lda cr_level,x
    jsr rng_range               // 0..lev-1 (rng_range(0) -> 0)
    lsr                         // C = r & 1; A = r >> 1
    adc #1                      // (r >> 1) + (r & 1) + 1 == floor((r + 1) / 2) + 1
    cmp mm_flags2
    bcc !mcdm_sub+
    lda mm_flags2               // Clamp drained amount to current MP
!mcdm_sub:
    sta mm_kind                 // r1 drained
    lda mm_flags2
    sec
    sbc mm_kind
    sta zp_player_mp
    sta player_data + PL_MANA
    // Heal monster by 6 * r1 (16-bit, clamped at $7fff)
    lda mm_kind
    ldx #6
    jsr math_multiply
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    clc
    adc zp_math_a
    sta (zp_ptr0),y
    iny                         // MX_HP_HI
    lda (zp_ptr0),y
    adc zp_math_b
    bpl !mcdm_hp_ok+
    lda #$7f
!mcdm_hp_ok:
    sta (zp_ptr0),y
    lda #<mm_drain_mana_suffix
    sta zp_ptr2
    lda #>mm_drain_mana_suffix
    sta zp_ptr2_hi
    jmp mm_print_spell_msg
!mcdm_done:
    rts

.encoding "screencode_mixed"
mm_drain_mana_suffix:
    .text " drains mana!"
    .byte 0
#endif
