#importonce
#define CORE_PLAYER_IMPORTED
// player.s — Player data structure and accessors
//
// The player struct is stored in a contiguous block in main RAM.
// Hot fields are mirrored in ZP (zeropage.s) for fast access.
// This module provides the full struct and sync routines between
// ZP and the main struct.

#import "platform_services_api.s"
//
// Total struct size: ~128 bytes

// ============================================================
// Player struct layout (offsets)
// ============================================================
.const PL_NAME      = 0    // 17 bytes: name (16 chars + null)
.const PL_RACE      = 17   // 1 byte: race index (0–7)
.const PL_CLASS     = 18   // 1 byte: class index (0–5)
.const PL_LEVEL     = 19   // 1 byte: player level (1–40)
.const PL_DLEVEL    = 20   // 1 byte: dungeon level (0=town)
// Base stats (before modifiers)
.const PL_STR_BASE  = 21
.const PL_INT_BASE  = 22
.const PL_WIS_BASE  = 23
.const PL_DEX_BASE  = 24
.const PL_CON_BASE  = 25
.const PL_CHR_BASE  = 26
// Current stats (after race/class/equipment mods)
.const PL_STR_CUR   = 27
.const PL_INT_CUR   = 28
.const PL_WIS_CUR   = 29
.const PL_DEX_CUR   = 30
.const PL_CON_CUR   = 31
.const PL_CHR_CUR   = 32
// Vitals
.const PL_HP_LO     = 33   // Current HP (16-bit)
.const PL_HP_HI     = 34
.const PL_MHP_LO    = 35   // Max HP (16-bit)
.const PL_MHP_HI    = 36
.const PL_MANA      = 37   // Current mana (8-bit, max 255)
.const PL_MAX_MANA  = 38   // Max mana
// Combat
.const PL_AC        = 39   // Armor class
.const PL_TOHIT     = 40   // To-hit bonus (base + modifiers)
.const PL_TODMG     = 41   // To-damage bonus
.const PL_BLOWS     = 42   // Attacks per round
// Economy / XP
.const PL_GOLD_0    = 43   // Gold (24-bit, up to 16M)
.const PL_GOLD_1    = 44
.const PL_GOLD_2    = 45
// GoldCapOnCarry — After a 24-bit addition to the gold whose last step left
// the carry out of PL_GOLD_2: stop at 16,777,215 rather than wrap
// (2026-11-08). VMS Moria and Umoria keep a 32-bit integer no game fills and
// wrap it; Moria8's 24 bits a long game can fill. Preserves: X, Y. 13 bytes.
.macro GoldCapOnCarry() {
    bcc !gcc_done+
    lda #$ff
    sta player_data + PL_GOLD_0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
!gcc_done:
}
.const PL_XP_0      = 46   // Experience (24-bit)
.const PL_XP_1      = 47
.const PL_XP_2      = 48
// Position
.const PL_MAP_X     = 49   // Map X position (0–79)
.const PL_MAP_Y     = 50   // Map Y position (0–47)
// Food / hunger
.const PL_FOOD_LO   = 51   // Food counter (16-bit)
.const PL_FOOD_HI   = 52
.const PL_HUNGER    = 53   // Hunger state (0–3)
// Flags
.const PL_FLAGS     = 54   // Bit flags (see below)
.const PL_LIGHT_RAD = 55   // Light radius
.const PL_MAX_DLVL  = 56   // Deepest dungeon level reached
.const PL_AGE       = 57   // Character age
.const PL_HEIGHT    = 58   // Height (aesthetic)
.const PL_WEIGHT    = 59   // Weight (aesthetic)
.const PL_SPELL_TYPE = 60  // Spell type (0=none, 1=mage, 2=priest)
.const PL_SPELLS_LEARNT_0 = 61 // 32-bit learned mask (bits 0-30 used)
.const PL_SPELLS_LEARNT_1 = 62
.const PL_SPELLS_LEARNT_2 = 63
.const PL_SPELLS_LEARNT_3 = 64
.const PL_SPELLS_WORKED_0 = 65 // 32-bit worked/successfully-cast mask
.const PL_SPELLS_WORKED_1 = 66
.const PL_SPELLS_WORKED_2 = 67
.const PL_SPELLS_WORKED_3 = 68
.const PL_SPELLS_FORGOTTEN_0 = 69 // 32-bit forgotten mask
.const PL_SPELLS_FORGOTTEN_1 = 70
.const PL_SPELLS_FORGOTTEN_2 = 71
.const PL_SPELLS_FORGOTTEN_3 = 72
.const PL_NEW_SPELLS = 73     // Pending spells/prayers the player can learn
.const PL_SPELL_ORDER = 74    // 32 bytes: learn/remember/forget order; 99 = empty
.const PL_SPELL_ORDER_LAST = PL_SPELL_ORDER + 31
// Backward-compatible aliases used by older tests/helpers during the transition.
.const PL_SPELLS_KNOWN = PL_SPELLS_LEARNT_0
.const PL_SPELLS_KNOWN_HI = PL_SPELLS_LEARNT_1
// Experience factor (race_xp% + class_xp%, range 100-165)
.const PL_EXPFACT   = 106
// Reserved
.const PL_RESERVED  = 107   // Pseudo-ID timer
.const PL_SOCIAL_CLASS = 108 // 1 byte: social class (1-100)
.const PL_XP_FRAC_LO = 109  // Hidden fractional XP (16-bit fixed point)
.const PL_XP_FRAC_HI = 110
.const PL_MAX_XP_0   = 111  // Peak experience reached (24-bit, Restore Life Levels)
.const PL_MAX_XP_1   = 112
.const PL_MAX_XP_2   = 113
.const PL_STRUCT_SIZE = 114  // Total struct size

// Player flags
.const PLF_MALE     = $01
.const PLF_SEE_INV  = $02
// $04 is free: Free Action is equipment-derived (player_pflags PFLAG_FREE_ACT)
.const PLF_SLOW_DIG = $08
.const PLF_SEARCHING = $10
.const PLF_RESTING  = $20
.const PLAYER_SEARCH_FLAG_LIT = $08

// ============================================================
// Player struct storage
// ============================================================
player_data:
    .fill PL_STRUCT_SIZE, 0

// Player background text (4 lines x 40 bytes = 160 bytes)
// Populated during character creation, saved/loaded with game.
player_background:
    .fill 160, 0

// ============================================================
// Subroutines
// ============================================================

#if !PLAYER_CHARGEN_EXTERNAL
#import "player_chargen_cold.s"
#endif

// player_sync_to_zp — Copy hot fields from struct to ZP
// Called after loading a save or modifying the struct directly.
// Preserves: nothing
player_sync_to_zp:
    lda player_data + PL_MAP_X
    sta zp_player_x
    lda player_data + PL_MAP_Y
    sta zp_player_y
    ldx #5
!pstz_vitals:
    lda player_data + PL_HP_LO,x
    sta zp_player_hp_lo,x
    lda player_data + PL_STR_CUR,x
    sta zp_player_str,x
    dex
    bpl !pstz_vitals-
    lda player_data + PL_LEVEL
    sta zp_player_lvl
    lda player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda player_data + PL_AC
    sta zp_player_ac
    lda player_data + PL_RACE
    sta zp_player_race
    lda player_data + PL_CLASS
    sta zp_player_class
    lda player_data + PL_FOOD_LO
    sta zp_player_food
    lda player_data + PL_FOOD_HI
    sta zp_player_food_hi
    lda player_data + PL_LIGHT_RAD
    sta zp_light_radius
    lda player_data + PL_RESERVED
    sta zp_pseudo_id_timer
    rts
.assert "PL_HP_LO..PL_MAX_MANA and zp_player_hp_lo..zp_player_mmp are 6 contiguous bytes", PL_HP_HI == PL_HP_LO + 1 && PL_MHP_LO == PL_HP_LO + 2 && PL_MHP_HI == PL_HP_LO + 3 && PL_MANA == PL_HP_LO + 4 && PL_MAX_MANA == PL_HP_LO + 5 && zp_player_mmp - zp_player_hp_lo == 5, true

// player_sync_from_zp — Copy ZP hot fields back to struct
// Called before saving.
// Note: intentionally does NOT sync STR/INT/WIS/DEX/CON/CHR (recalculated
// by player_calc_stats) or race/class (immutable after creation).
// light_radius IS synced because it's mutable (torch/lamp/spell).
// Preserves: nothing
player_sync_from_zp:
    lda zp_player_x
    sta player_data + PL_MAP_X
    lda zp_player_y
    sta player_data + PL_MAP_Y
    ldx #5
!psfz_vitals:
    lda zp_player_hp_lo,x
    sta player_data + PL_HP_LO,x
    dex
    bpl !psfz_vitals-
    lda zp_player_lvl
    sta player_data + PL_LEVEL
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda zp_player_ac
    sta player_data + PL_AC
    lda zp_player_food
    sta player_data + PL_FOOD_LO
    lda zp_player_food_hi
    sta player_data + PL_FOOD_HI
    lda zp_light_radius
    sta player_data + PL_LIGHT_RAD
    rts

// player_calc_stats — Recalculate current stats from the baked base plus
// equipment. Race/class modifiers are folded into the base once at character
// creation (player_bake_creation_stats), so this routine must be deterministic:
// rerolling the randomized exceptional stepping here would change 18+ stats
// on every load and restoration.
// Stats use single-byte encoding: 3-18 literal, 19-118 = 18/01 to 18/100.
// Preserves: nothing
player_calc_stats:
    ldy #STAT_COUNT - 1
    lda #0
!stat_loop:
    sta player_stat_res,y
    dey
    bpl !stat_loop-

!pcs_equipment:
    // Sum each stat's signed equipment p1 across worn items into
    // player_stat_res,y, then apply per-point VMS 18/xx stepping
    // (in_statt/de_statt) from PL_STR_BASE,y so load/restoration rebuilds
    // deterministically match wear/takeoff.
    ldx #EQUIP_CLOAK
!pcs_eq:                        // the weapon slot through the cloak
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pcs_eq_next+
    lda inv_p1,x
    beq !pcs_eq_next+
    jsr equip_stat_mask_x       // A = 6-bit PL_STR..PL_CHR mask, preserves X
    beq !pcs_eq_next+
    ldy #0
!pcs_eq_bit:
    lsr
    bcc !pcs_eq_skip+
    pha
    lda player_stat_res,y
    clc
    adc inv_p1,x
    sta player_stat_res,y
    pla
!pcs_eq_skip:
    beq !pcs_eq_next+
    iny
    cpy #STAT_COUNT
    bcc !pcs_eq_bit-
!pcs_eq_next:
    dex
    cpx #EQUIP_WEAPON
    bcs !pcs_eq-

    // Clamp base stats to [3, 118], sync ZP mirrors, and apply accumulated
    // signed equipment steps via VMS 18/xx stepping (preserving residuals
    // in player_stat_res,y for reversible takeoff and drains).
    ldy #STAT_COUNT - 1
!pcs_zp:
    lda player_stat_res,y
    pha
    lda player_data + PL_STR_BASE,y
    jsr player_store_clamped_stat_y
    pla
    jsr player_step_equip_stat_y
    dey
    bpl !pcs_zp-
.assert "The ZP stat mirrors follow PL_*_CUR order", zp_player_chr - zp_player_str == PL_CHR_CUR - PL_STR_CUR && STAT_COUNT == 6, true

    // Persistent effect flags from the equipment: the routine below, by
    // falling through, or by a jump where a port places it elsewhere.
#if PLAYER_RECALC_PFLAGS_EXTERNAL || PLAYER_PFLAGS_EXTERNAL
    jmp hal_player_recalc_pflags
#elif PFLAGS_SEGMENT_CUSTOM
    jmp player_recalc_pflags_equipment
#endif
.assert "Ring, amulet and left-hand ring slots are contiguous", EQUIP_AMULET == EQUIP_RING + 1 && EQUIP_RING2 == EQUIP_AMULET + 1, true
.assert "All rings and amulets live on Page 1", ITEM_PAGE_RING_OF_STRENGTH == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_SLAYING == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_ADORNMENT_VMS_SUB11 == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_DOOM == ITEM_PAGE_BIT, true
.assert "Weapon, body, shield and head slots are contiguous", EQUIP_BODY == EQUIP_WEAPON + 1 && EQUIP_SHIELD == EQUIP_BODY + 1 && EQUIP_HEAD == EQUIP_SHIELD + 1, true

#if !PLAYER_PFLAGS_EXTERNAL
// The equipment flags: a port short of resident room places them with
// :PflagsSegment()/:PflagsRestoreSegment() (Plus/4 and Atari: their
// always-visible $F000 RuntimeBanked; C64: $F000 RuntimeBanked behind
// PLAYER_RECALC_PFLAGS_EXTERNAL), or imports player_pflags_cold.s into
// an overlay under PLAYER_PFLAGS_EXTERNAL.
#if !PFLAGS_SEGMENT_CUSTOM
.macro PflagsSegment() {}
.macro PflagsRestoreSegment() {}
#endif
:PflagsSegment()
#import "player_pflags_cold.s"
:PflagsRestoreSegment()
#endif

// equip_stat_mask_x — X = equipment slot: A = 6-bit stat mask (bit 0=STR, 1=INT,
// 2=WIS, 3=DEX, 4=CON, 5=CHR; 0 if none), Z reflects A. Preserves X.
equip_stat_mask_x:
    lda inv_ego,x
    and #EGO_ID_MASK
    beq !esm_item+
    ldy #esm_ego_ids_end - esm_ego_ids - 1
!esm_ego_loop:
    cmp esm_ego_ids,y
    beq !esm_ego_hit+
    dey
    bpl !esm_ego_loop-
!esm_item:
    .assert "All stat-modifying rings and amulets live on Page 1", ITEM_PAGE_RING_OF_STRENGTH == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_WISDOM == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_THE_MAGI == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_CHARISMA == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_DOOM == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_WEAKNESS == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_STUPIDITY == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_GAIN_INTELLIGENCE == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_GAIN_DEXTERITY == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_GAIN_CONSTITUTION == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_WOE == ITEM_PAGE_BIT, true
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    beq !esm_zero+
    lda inv_item_id,x
    ldy #esm_p1_ids_end - esm_p1_ids - 1
!esm_p1_loop:
    cmp esm_p1_ids,y
    beq !esm_p1_hit+
    dey
    bpl !esm_p1_loop-
!esm_zero:
    lda #0
    rts
!esm_ego_hit:
    lda esm_ego_masks,y
    rts
!esm_p1_hit:
    lda esm_p1_masks,y
    rts

esm_ego_ids:
    .byte EGO_HOLY_AVENGER, EGO_MAGI, EGO_CLUMSINESS, EGO_WEAKNESS
    .byte EGO_INTELLIGENCE, EGO_WISDOM, EGO_MIGHT, EGO_LORDLINESS
    .byte EGO_BEAUTY, EGO_STUPIDITY, EGO_DULLNESS, EGO_UGLINESS
esm_ego_ids_end:
esm_ego_masks:
    .byte $01, $02, $08, $01, $02, $04, $19, $24, $20, $02, $04, $20
.assert "esm_ego_masks matches esm_ego_ids", * - esm_ego_masks, esm_ego_ids_end - esm_ego_ids
esm_p1_ids:
    .byte ITEM_SLOT_RING_OF_STRENGTH, ITEM_SLOT_AMULET_OF_WISDOM, ITEM_SLOT_AMULET_OF_THE_MAGI
    .byte ITEM_SLOT_AMULET_OF_CHARISMA, ITEM_SLOT_AMULET_OF_DOOM
    .byte ITEM_SLOT_RING_OF_WEAKNESS, ITEM_SLOT_RING_OF_STUPIDITY, ITEM_SLOT_RING_OF_GAIN_INTELLIGENCE
    .byte ITEM_SLOT_RING_OF_GAIN_DEXTERITY, ITEM_SLOT_RING_OF_GAIN_CONSTITUTION, ITEM_SLOT_RING_OF_WOE
esm_p1_ids_end:
esm_p1_masks:
    .byte $01, $04, $02, $20, $3f, $01, $02, $02, $08, $10, $24
.assert "esm_p1_masks matches esm_p1_ids", * - esm_p1_masks, esm_p1_ids_end - esm_p1_ids

// equip_stat_index — X = equipment slot: carry set and Y = primary stat (0..5)
// for its p1 modifier; carry clear if none. Preserves X.
equip_stat_index:
    jsr equip_stat_mask_x
    beq !esi_none+
    ldy #$ff
!esi_bit:
    iny
    lsr
    bcc !esi_bit-
    sec
    rts
!esi_none:
    clc
    rts
.assert "The stat items' slots run from the head to the left hand", EQUIP_HEAD < EQUIP_RING && EQUIP_RING < EQUIP_AMULET && EQUIP_AMULET < EQUIP_RING2, true

// Working bytes for stat modification (survive across increment/decrement calls)
stat_work: .byte 0
stat_step_cnt: .byte 0
// Signed (unclamped - clamped) residual per stat when clamped at 3 or 118.
player_stat_res: .fill STAT_COUNT, 0

// player_step_equip_stat_y — Apply signed equipment bonus A (-128..+127)
// one point at a time to stat Y (0..5) via VMS in_statt/de_statt (moria.inc:33,
// misc.inc:2194: +1 below 18, +10 from 18 capped at 118; 27/18 rules on remove).
// Residual invariant (preserved by all stat mutators here):
// cur == 3 => res <= 0; 4..117 => res == 0; cur == 118 => res >= 0.
// Preserves: X, Y. Clobbers: A, stat_step_cnt.
player_step_equip_stat_y:
    cmp #0
    beq !pses_ret+
    bmi !pses_dec_init+
    sta stat_step_cnt
    lda player_data + PL_STR_CUR,y
!pses_inc_lp:
    cmp #18
    bcs !pses_inc_18+
    cmp #3
    bne !pses_inc_add1+
    lda player_stat_res,y
    beq !pses_inc_from3+
    clc
    adc #1
    sta player_stat_res,y
    lda #3
    bne !pses_inc_next+
!pses_inc_from3:
    lda #3
!pses_inc_add1:
    clc
    adc #1
    bne !pses_inc_next+
!pses_inc_18:
    cmp #118
    beq !pses_inc_at118+
    adc #10
    cmp #119
    bcc !pses_inc_next+
    sbc #118
    bcs !pses_inc_st118+
!pses_inc_at118:
    lda player_stat_res,y
    clc
    adc #10
    bpl !pses_inc_st118+
    lda #127
!pses_inc_st118:
    sta player_stat_res,y
    lda #118
!pses_inc_next:
    dec stat_step_cnt
    bne !pses_inc_lp-
    beq pses_write_cur_y
!pses_ret:
    rts

pses_zero_res_write_y:
    pha
    lda #0
    sta player_stat_res,y
    pla
pses_write_cur_y:
    sta player_data + PL_STR_CUR,y
    sta zp_player_str,y
    rts

!pses_dec_init:
    eor #$ff
    clc
    adc #1
    sta stat_step_cnt
    lda player_data + PL_STR_CUR,y
!pses_dec_lp:
    cmp #118
    bne !pses_dec_not118+
    lda player_stat_res,y
    cmp #10
    bcc !pses_dec_drop118+
    sbc #10
    sta player_stat_res,y
    lda #118
    bne !pses_dec_next+
!pses_dec_drop118:
    clc
    adc #108
    jsr pses_zero_res_write_y
    bne !pses_dec_next+
!pses_dec_not118:
    cmp #28
    bcc !pses_dec_chk19+
    sbc #10
    bcs !pses_dec_next+
!pses_dec_chk19:
    cmp #19
    bcc !pses_dec_chk4+
    lda #18
    bne !pses_dec_next+
!pses_dec_chk4:
    cmp #4
    bcc !pses_dec_at3+
    sbc #1
    bne !pses_dec_next+
!pses_dec_at3:
    lda player_stat_res,y
    cmp #$80
    beq !pses_dec_at3_st+
    sec
    sbc #1
    sta player_stat_res,y
!pses_dec_at3_st:
    lda #3
!pses_dec_next:
    dec stat_step_cnt
    bne !pses_dec_lp-
    beq pses_write_cur_y

// player_apply_stat_delta_y — Add unsigned delta A (0..25 from eff_gain_stat)
// to stat Y (0..5), clamp PL_STR_CUR,y & zp_player_str,y to [3, 118], and
// update player_stat_res,y (saturating positive cap residuals at +127).
// Preserves: X, Y. Clobbers: A.
player_apply_stat_delta_y:
    cmp #0
    beq !pasd_ret+
    pha
    lda player_data + PL_STR_CUR,y
    cmp #118
    bne !pasd_add+
    pla
    clc
    adc player_stat_res,y
    bpl !pasd_hi_store+
    lda #$7f
!pasd_hi_store:
    sta player_stat_res,y
!pasd_ret:
    rts
!pasd_add:
    clc
    adc player_stat_res,y
    sta player_stat_res,y
    pla
    clc
    adc player_stat_res,y
player_store_clamped_stat_y:
    pha
    cmp #$c0
    bcs !pscs_min+
    cmp #3
    bcs !pscs_max+
!pscs_min:
    lda #3
    bne !pscs_set+
!pscs_max:
    cmp #119
    bcc !pscs_set+
    lda #118
!pscs_set:
    jsr pses_write_cur_y
    pla
    sec
    sbc player_data + PL_STR_CUR,y
    sta player_stat_res,y
    rts

// player_award_xp_a — Add 8-bit A to 24-bit PL_XP and ratchet PL_MAX_XP.
// Preserves: X, Y. Clobbers: A.
player_award_xp_a:
    clc
    adc player_data + PL_XP_0
    sta player_data + PL_XP_0
    bcc player_sync_max_xp
    inc player_data + PL_XP_1
    bne player_sync_max_xp
    inc player_data + PL_XP_2
// player_sync_max_xp — Ratchet 24-bit PL_MAX_XP up to PL_XP when PL_XP > PL_MAX_XP.
// Preserves: X, Y. Clobbers: A.
player_sync_max_xp:
    lda player_data + PL_MAX_XP_0
    cmp player_data + PL_XP_0
    lda player_data + PL_MAX_XP_1
    sbc player_data + PL_XP_1
    lda player_data + PL_MAX_XP_2
    sbc player_data + PL_XP_2
    bcs !psmx_done+
    lda player_data + PL_XP_0
    sta player_data + PL_MAX_XP_0
    lda player_data + PL_XP_1
    sta player_data + PL_MAX_XP_1
    lda player_data + PL_XP_2
    sta player_data + PL_MAX_XP_2
!psmx_done:
    rts

// Persistent equipment-granted effect flags, recomputed by player_calc_stats.
player_pflags:      .byte 0
player_pflags2:     .byte 0
player_curse_flags: .byte 0
player_sust_mask:   .byte 0
wield_weight_lo:    .byte 0
wield_weight_hi:    .byte 0
wield_dmg_packed:   .byte 0
wield_missile_type: .byte 0
wield_flags_0:      .byte 0
wield_flags_1:      .byte 0
wield_flags_2:      .byte 0
wield_flags_3:      .byte 0
.assert "wield_* fields are contiguous", wield_flags_3 - wield_weight_lo, 7

#if !HAL_PLATFORM_COMPACT_PLAY_SLOT
// player_apply_slaying_bonuses — Add Ring of Slaying / Damage / To-Hit,
// Slaying glove, and Enveloping cloak bonuses to pcc_eq_tohit/pcc_eq_todam.
// Clobbers: A, X, Y
player_apply_slaying_bonuses:
    .assert "Combat-bonus rings live on Page 1", ITEM_PAGE_RING_OF_SLAYING == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_INCREASE_DAMAGE == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_INCREASE_TO_HIT == ITEM_PAGE_BIT, true
    ldx #EQUIP_RING
!pasb_ring:
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    beq !pasb_next+
    lda inv_item_id,x
    cmp #ITEM_SLOT_RING_OF_SLAYING
    beq !pasb_r_hit+
    cmp #ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    beq !pasb_r_hit+
    cmp #ITEM_SLOT_RING_OF_INCREASE_TO_HIT
    bne !pasb_next+
!pasb_r_hit:
    jsr !pasb_add_x+
!pasb_next:
    cpx #EQUIP_RING2
    beq !pasb_gloves+
    ldx #EQUIP_RING2
    bne !pasb_ring-
!pasb_gloves:
    ldx #EQUIP_HANDS
    lda #EGO_SLAYING
    jsr !pasb_chk_ego+
    ldx #EQUIP_CLOAK
    lda #EGO_ENVELOPING
!pasb_chk_ego:
    ldy inv_item_id,x
    iny
    beq !pasb_done+
    eor inv_ego,x
    and #EGO_ID_MASK
    bne !pasb_done+
!pasb_add_x:
    lda inv_to_hit,x
    clc
    adc pcc_eq_tohit
    sta pcc_eq_tohit
    lda inv_to_dam,x
    clc
    adc pcc_eq_todam
    sta pcc_eq_todam
!pasb_done:
    rts
#endif

// player_drain_stat_y — Drain stat Y (0..5 = STAT_STR..STAT_CHR) by one VMS
// de_statp step, consuming positive player_stat_res,y at 118 (randint(3))
// before lowering PL_STR_CUR,y / zp_player_str,y.
// Input: Y = stat index (0..5)
// Output: C = 1 if stat was >= 4 (drained), C = 0 if stat < 4 (unchanged).
// Preserves: Y. Clobbers: A, X, zp_temp3, zp_temp4, zp_math_a.
player_drain_stat_y:
    lda player_data + PL_STR_CUR,y
    cmp #4
    bcc !pds_done+              // < 4: C = 0, unchanged
    cmp #118
    bne !pds_dec_cur+
    lda player_stat_res,y
    beq !pds_reload_cur+
    lda #3
    jsr rng_range               // 0..2, preserves Y
    sta zp_math_a
    lda player_stat_res,y
    clc
    sbc zp_math_a               // res - randint(3); C=1 if >= 0
    bcc !pds_below_118+
    sta player_stat_res,y
!pds_done:
    rts
!pds_below_118:
    adc #118                    // C=0 -> cur drops into 116..117, residual cleared
    bne !pds_store+
!pds_reload_cur:
    lda #118
!pds_dec_cur:
    jsr decrement_stat
!pds_store:
    jsr pses_zero_res_write_y
    sec
    rts

// decrement_stat — Decrement a stat using VMS Moria's de_statp (misc.inc:2177)
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Preserves: Y. Clobbers: X, zp_temp3, zp_temp4, zp_math_a.
decrement_stat:
    cmp #109
    bcs !range_109_118+
    cmp #19
    bcs !range_19_108+
    cmp #4
    bcc !dec_done+              // stat <= 3: no change
    sbc #1                      // stat 4..18: -1 (C = 1)
    rts
!range_109_118:
    // stat > 108 (109-118): subtract randint(3) = 1-3
    pha
    lda #3
    jsr rng_range
    bpl !dec_sub+
!range_19_108:
    // stat 19-108: subtract randint(10)+5 = 6-15, floor 18
    pha
    lda #10
    jsr rng_range
    clc
    adc #5
!dec_sub:
    sta zp_math_a
    pla
    clc
    sbc zp_math_a
    cmp #19
    bcs !dec_done+
    lda #18
!dec_done:
    rts

// stat_bonus_index — Convert stat value to bonus table index (0-15)
// Stats above 18 (18/xx encoded as 19-118) use index 15 (stat 18 bonus).
// Input: A = stat value (3-118)
// Output: X = bonus table index (0-15)
// Preserves: Y
stat_bonus_index:
    cmp #19
    bcc !normal+
    ldx #15                 // 18/xx → use same bonus as stat 18
    rts
!normal:
    cmp #3
    bcs !above_min+
    lda #3                  // Clamp stat minimum to 3
!above_min:
    sec
    sbc #3                  // index = stat - 3
    tax
    rts

// Umoria combat/stat adjustment helpers. These intentionally do not use
// stat_bonus_index because exceptional 18/xx values have distinct thresholds.
#if !PLAYER_STAT_HELPERS_EXTERNAL
player_str_tohit_adj:
    cmp #4
    bcc player_adj_m3
    cmp #5
    bcc player_adj_m2
    cmp #7
    bcc player_adj_m1
    cmp #18
    bcc player_adj_0
    cmp #94
    bcc player_adj_1
    cmp #109
    bcc player_adj_2
    cmp #117
    bcc player_adj_3
    bcs player_adj_4

player_str_damage_adj:
    cmp #4
    bcc player_adj_m2
    cmp #5
    bcc player_adj_m1
    cmp #16
    bcc player_adj_0
    cmp #17
    bcc player_adj_1
    cmp #18
    bcc player_adj_2
    cmp #94
    bcc player_adj_3
    cmp #109
    bcc player_adj_4
    cmp #117
    bcc player_adj_5
    bcs player_adj_6

player_dex_tohit_adj:
    cmp #4
    bcc player_adj_m3
    cmp #6
    bcc player_adj_m2
    cmp #8
    bcc player_adj_m1
    cmp #16
    bcc player_adj_0
    cmp #17
    bcc player_adj_1
    cmp #18
    bcc player_adj_2
    cmp #69
    bcc player_adj_3
    cmp #118
    bcc player_adj_4
    bcs player_adj_5

// One return sled, midway so every branch above and below reaches it
// (a second copy, player_adj_*, cost 30 bytes until 2026-11-07).
player_adj_0:
    lda #0
    rts
player_adj_m4:
    lda #<-4
    rts
player_adj_m3:
    lda #<-3
    rts
player_adj_m2:
    lda #<-2
    rts
player_adj_m1:
    lda #<-1
    rts
player_adj_1:
    lda #1
    rts
player_adj_2:
    lda #2
    rts
player_adj_3:
    lda #3
    rts
player_adj_4:
    lda #4
    rts
player_adj_5:
    lda #5
    rts
player_adj_6:
    lda #6
    rts

player_dex_ac_adj:
    cmp #4
    bcc player_adj_m4
    cmp #5
    bcc player_adj_m3
    cmp #6
    bcc player_adj_m2
    cmp #7
    bcc player_adj_m1
    cmp #15
    bcc player_adj_0
    cmp #18
    bcc player_adj_1
    cmp #59
    bcc player_adj_2
    cmp #94
    bcc player_adj_3
    cmp #117
    bcc player_adj_4
    bcs player_adj_5

player_con_hp_adj:
    cmp #7
    bcs !check17+
    sec
    sbc #7
    rts
!check17:
    cmp #17
    bcc player_adj_0
    cmp #18
    bcc player_adj_1
    cmp #94
    bcc player_adj_2
    cmp #117
    bcc player_adj_3
    bcs player_adj_4
#endif

// player_calc_combat — Calculate combat bonuses from current stats and the
// worn equipment: stat bonuses, worn AC, plus the weapon, Ring of Slaying and
// weapon-ego bonuses player_recalc_equipment collected (pcc_eq_*), so a
// level-up, load or stat restore keeps them.
// Updates: PL_TOHIT, PL_TODMG, PL_AC, zp_player_ac, PL_BLOWS
// Preserves: nothing
player_calc_combat:
    // STR to-hit bonus
    lda player_data + PL_STR_CUR
    jsr player_str_tohit_adj
    sta zp_temp0            // Accumulate to-hit

    // DEX to-hit bonus
    lda player_data + PL_DEX_CUR
    jsr player_dex_tohit_adj
    clc
    adc zp_temp0
    clc
    adc pcc_eq_tohit
    sta player_data + PL_TOHIT

    // STR damage bonus
    lda player_data + PL_STR_CUR
    jsr player_str_damage_adj
    clc
    adc pcc_eq_todam
    sta player_data + PL_TODMG

    // AC = DEX bonus + equipment AC (base + split to_ac)
    // Start with DEX AC bonus (signed)
    lda player_data + PL_DEX_CUR
    jsr player_dex_ac_adj
    sta pcc_ac_accum            // Signed accumulator (may be negative)

    // Loop armor-relevant equipment slots: body through current equipment end.
    ldx #EQUIP_BODY
!ac_equip_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ac_next_slot+
    // Add base AC for this item type (page-aware via inv_ego,x)
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    ldy inv_item_id,x           // Y = slot_lo
    jsr item_get_base_ac
    jsr pcc_ac_add
    // Add split AC bonus (signed)
    lda inv_to_ac,x
    jsr pcc_ac_add
!ac_next_slot:
    inx
    cpx #EQUIP_END             // Past last armor-relevant slot
    bne !ac_equip_loop-

    // Clamp AC to [0, 60]
    lda pcc_ac_accum
    bmi !ac_zero+               // Negative → 0
    cmp #61
    bcc !ac_store+
    lda #60                     // Cap at 60
    bne !ac_store+              // always
!ac_zero:
    lda #0
!ac_store:
    clc
    adc pcc_eq_ac               // Defender / Holy Avenger, past the cap
    sta player_data + PL_AC
    sta zp_player_ac

    // Blows: simplified lookup
    // Weight class based on STR (higher STR = lighter effective weight)
    // For now, default to 1 blow until weapons are implemented
    lda #1
    sta player_data + PL_BLOWS

    rts

// pcc_ac_add — pcc_ac_accum += A (signed), saturating at -128 / +127: a full
// suit of enchanted heavy armour can sum past +127.
// Preserves: X
pcc_ac_add:
    clc
    adc pcc_ac_accum
    bvc !paa_store+
    lda #$7f                    // overflow: C clear past +127 ($7F),
    adc #0                      // C set past -128 ($7F + 1 = $80)
!paa_store:
    sta pcc_ac_accum
    rts

// Scratch for player_calc_combat
pcc_ac_accum: .byte 0          // AC accumulator (signed during calculation)
// Equipment bonuses player_recalc_equipment collects and player_calc_combat
// adds on every recalc. Not saved: the load path rebuilds them.
pcc_eq_tohit: .byte 0          // weapon + Rings of Slaying to-hit (signed)
pcc_eq_todam: .byte 0          // weapon + Rings of Slaying to-damage (signed)
pcc_eq_ac:    .byte 0          // weapon ego AC (Defender, Holy Avenger)

// player_calc_hp — Calculate max HP based on level, class HD, CON bonus
// Preserves: nothing
player_calc_hp:
    // Combined hit die = class_HD (offset 0) + race_HD (offset 0)
    ldx #0
    ldy #0
    jsr player_get_race_class_property
    sta zp_temp0            // Combined HD

    // CON HP bonus
    lda player_data + PL_CON_CUR
    jsr player_con_hp_adj
    sta zp_temp1            // CON bonus per level

    // HP per level = hit_die/2 + CON bonus (min 1)
    lda zp_temp0
    lsr                     // hit_die / 2
    clc
    adc zp_temp1            // + CON bonus
    bmi !min1+
    bne !ok+
!min1:
    lda #1                  // Minimum 1 HP per level
!ok:
    sta zp_temp1            // HP per additional level

    // Total max HP = hit_die + (level-1) * hp_per_level
    lda player_data + PL_LEVEL
    sec
    sbc #1                  // level - 1
    tax
    lda zp_temp1            // HP per level
    jsr math_multiply       // result in zp_math_a (lo), zp_math_b (hi)
    lda zp_math_a
    clc
    adc zp_temp0            // + base hit die
    sta player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    tax
    lda zp_math_b
    adc #0
    sta player_data + PL_MHP_HI
    sta zp_player_mhp_hi
    cpx zp_player_hp_lo
    sbc zp_player_hp_hi
    bcs !pch_hp_ok+
    stx zp_player_hp_lo
    stx player_data + PL_HP_LO
    lda zp_player_mhp_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
!pch_hp_ok:
    rts

// mul_x_by_a — Helper: multiply X by A, result in A
// Only works for small products (<256)
// Preserves: Y
mul_x_by_a:
    sta zp_temp3
    txa
    ldx zp_temp3
    jsr math_multiply
    lda zp_math_a
    rts

// ============================================================
// Search mode and derived search/perception helpers
// ============================================================

// player_search_mode_on — Enable persistent search mode
// Preserves: nothing
player_search_mode_on:
    lda player_data + PL_FLAGS
    ora #PLF_SEARCHING
    bne !psm_set+           // always (PLF_SEARCHING != 0)

// player_search_mode_off — Disable persistent search mode
// Preserves: nothing
player_search_mode_off:
    lda player_data + PL_FLAGS
    and #($ff - PLF_SEARCHING)
!psm_set:
    cmp player_data + PL_FLAGS
    beq !done+
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
!done:
    rts

// player_search_clear_transient_state — Reset non-persistent search runtime state
player_search_clear_transient_state:
    jsr player_search_mode_off
    lda #0
    sta zp_search_count
    rts

// player_search_has_light — Returns carry set when the player has no local light
// source and is not standing on a lit tile.
player_search_has_no_light:
    lda zp_light_radius
    bne !has_light+

    ldx zp_player_y
    jsr map_row_ptr0_x
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #PLAYER_SEARCH_FLAG_LIT
    beq !no_light+
!has_light:
    clc
    rts
!no_light:
    sec
    rts

// player_search_get_base_chance — Race/class-derived active search chance
// Output: A = base search chance
player_search_get_base_chance:
    ldx #8                      // Class search offset
    ldy #4                      // Race search offset
    jmp player_get_race_class_property

// player_search_get_fos — Race/class-derived passive auto-search frequency
// Output: A = fos (<=1 means always search on movement)
player_search_get_fos:
    ldx #9                      // Class fos offset
    ldy #6                      // Race fos offset
    jsr player_get_race_class_property
    tay
    lda player_pflags2
    and #PFLAG2_SEARCH
    beq !psgf_done+
    tya
    cmp #3
    bcc !psgf_clamp+
    sbc #2
    rts
!psgf_clamp:
    lda #1
    rts
!psgf_done:
    tya
    rts

// player_get_stealth — Race/class-derived stealth used by monster waking.
// Output: A = stealth threshold in 0..9 for the shipped property tables.
// Clobbers: X, Y, zp_temp0/1, zp_math_a/b/tmp0/tmp1.
player_get_stealth:
    ldx #7                      // Class stealth offset
    ldy #5                      // Race stealth offset
    jsr player_get_race_class_property
    bpl !pgs_pos+
    lda #0
!pgs_pos:
    pha
    lda player_pflags2
    and #PFLAG2_STEALTH
    beq !pgs_done+
    pla
    clc
    adc #3
    cmp #10
    bcc !pgs_ret+
    lda #9
!pgs_ret:
    rts
!pgs_done:
    pla
    rts

// Sum one class and race property without duplicating table-stride logic.
// Input: X = class property offset, Y = race property offset.
// Output: A = unsigned byte sum; callers interpret/clamp signed adjustments.
// Clobbers: X, zp_temp0/1, zp_math_a/b/tmp0/tmp1. Preserves Y.
player_get_race_class_property:
    stx zp_temp1
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply
    clc
    adc zp_temp1
    tax
    lda class_properties,x
    sta zp_temp0

    sty zp_temp1
    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    clc
    adc zp_temp1
    tax
    lda race_properties,x
    clc
    adc zp_temp0
    rts

// player_search_get_effective_chance — Apply live status/light penalties
// Output: A = effective chance used by active and passive search scans
player_search_get_effective_chance:
    jsr player_search_get_base_chance
    sta player_search_work

    lda zp_eff_confuse
    beq !not_confused+
    lda player_search_work
    jsr player_search_divide_by_10
    sta player_search_work
!not_confused:

    lda zp_eff_blind
    bne !dim_penalty+
    jsr player_search_has_no_light
    bcc !done+
!dim_penalty:
    lda player_search_work
    jsr player_search_divide_by_10
    sta player_search_work
!done:
    lda player_search_work
    rts

// player_search_divide_by_10 — Floor(A / 10)
// Output: A = quotient
player_search_divide_by_10:
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #10
    jsr math_div_16x8
    lda zp_math_a
    rts

player_search_work: .byte 0

// ui_char_draw_background (HAL_PLATFORM_CHARACTER_BACKGROUND_RESYNC) lives in
// player_bg_draw_cold.s so tight ports can host it in UiOverlay via UI_CHAR_BG_EXTERNAL.
#if !UI_CHAR_BG_EXTERNAL
#import "player_bg_draw_cold.s"
#endif

// ============================================================
// Compile-time validation
// ============================================================
.assert "Player struct size", PL_STRUCT_SIZE, 114
