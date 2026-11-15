#importonce
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
.const PL_STRUCT_SIZE = 111  // Total struct size

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

// Character sheet strings (main RAM — referenced by $F000 banked code)
char_sex_label:
    .text "Sex: " ; .byte 0
char_sex_male:
    .text "Male" ; .byte 0
char_sex_female:
    .text "Female" ; .byte 0
char_sc_label:
    .text "  SC: " ; .byte 0

// ============================================================
// Subroutines
// ============================================================

// player_init — Zero out player struct
// Preserves: nothing
player_init:
    lda #0
    ldx #PL_STRUCT_SIZE - 1
!loop:
    sta player_data,x
    dex
    bpl !loop-
    lda #99
    ldx #31
!spell_order_loop:
    sta player_data + PL_SPELL_ORDER,x
    dex
    bpl !spell_order_loop-
    // Clear player_background (160 bytes = 2 x 80)
    lda #0
    ldx #79
!bg_loop:
    sta player_background,x
    sta player_background + 80,x
    dex
    bpl !bg_loop-
    rts

// player_sync_to_zp — Copy hot fields from struct to ZP
// Called after loading a save or modifying the struct directly.
// Preserves: nothing
player_sync_to_zp:
    lda player_data + PL_MAP_X
    sta zp_player_x
    lda player_data + PL_MAP_Y
    sta zp_player_y
    lda player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_HP_HI
    sta zp_player_hp_hi
    lda player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    sta zp_player_mhp_hi
    lda player_data + PL_MANA
    sta zp_player_mp
    lda player_data + PL_MAX_MANA
    sta zp_player_mmp
    lda player_data + PL_LEVEL
    sta zp_player_lvl
    lda player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda player_data + PL_AC
    sta zp_player_ac
    lda player_data + PL_STR_CUR
    sta zp_player_str
    lda player_data + PL_INT_CUR
    sta zp_player_int
    lda player_data + PL_WIS_CUR
    sta zp_player_wis
    lda player_data + PL_DEX_CUR
    sta zp_player_dex
    lda player_data + PL_CON_CUR
    sta zp_player_con
    lda player_data + PL_CHR_CUR
    sta zp_player_chr
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
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda zp_player_mhp_hi
    sta player_data + PL_MHP_HI
    lda zp_player_mp
    sta player_data + PL_MANA
    lda zp_player_mmp
    sta player_data + PL_MAX_MANA
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
// equipment. Race/class modifiers are folded into the base once at creation
// (player_bake_creation_stats) or at legacy-save migration
// (player_bake_race_class_mods), so this routine must be deterministic:
// rerolling the randomized exceptional stepping here would change 18+ stats
// on every load and restoration.
// Stats use single-byte encoding: 3-18 literal, 19-118 = 18/01 to 18/100.
// Preserves: nothing
player_calc_stats:
    ldy #0                  // Stat index
!stat_loop:
    lda player_data + PL_STR_BASE,y
    sta player_data + PL_STR_CUR,y
    iny
    cpy #STAT_COUNT
    bne !stat_loop-
    jmp !pcs_equipment+

// player_bake_creation_stats — Character-creation entry: fold race/class
// modifiers into base stats with the upstream randomized exceptional
// stepping, making the roll permanent. The only randomizing stat path.
player_bake_creation_stats:
    lda #1
    sta stat_bake_mode
    jmp player_bake_stat_modifiers

// player_bake_stat_modifiers — Fold race/class modifiers into base stats and
// mirror the result into current stats, making the roll permanent.
// stat_bake_mode nonzero (character creation): upstream randomized stepping
// for the 18+ band — the only place stats may randomize.
// stat_bake_mode zero (legacy-save migration): exact signed arithmetic, so
// pre-baked saves convert deterministically.
// Preserves: nothing
stat_bake_mode: .byte 0

player_bake_stat_modifiers:
    // Precompute race*6 into zp_temp0 (safe across math_dice)
    lda player_data + PL_RACE
    asl
    sta zp_temp0
    asl
    clc
    adc zp_temp0
    sta zp_temp0            // zp_temp0 = race * 6

    // Precompute class*6 into zp_temp2 (safe across math_dice)
    lda player_data + PL_CLASS
    asl
    sta zp_temp2
    asl
    clc
    adc zp_temp2
    sta zp_temp2            // zp_temp2 = class * 6

    ldy #0                  // Stat index
!bake_loop:
    sty zp_temp1            // Save stat index (safe across math_dice)

    // Start with base stat
    lda player_data + PL_STR_BASE,y
    sta stat_work

    // Apply race modifier
    lda zp_temp0            // race*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda race_stat_adj,x
    jsr player_bake_apply_one

    // Apply class modifier
    lda zp_temp2            // class*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda class_stat_adj,x
    jsr player_bake_apply_one

    // Bake result into base and current
    ldy zp_temp1
    lda stat_work
    sta player_data + PL_STR_BASE,y
    sta player_data + PL_STR_CUR,y

    iny
    cpy #STAT_COUNT
    bne !bake_loop-
    rts

// player_bake_apply_one — Apply modifier A to stat_work per stat_bake_mode.
player_bake_apply_one:
    ldx stat_bake_mode
    bne !pbao_roll+
    clc
    adc stat_work
    sta stat_work
    rts
!pbao_roll:
    jmp apply_modifier

!pcs_equipment:
    // The equipment's stat bonuses (equip_stat_mask_x) use p1 as a signed
    // modifier. Equipment bonuses must be exact: apply_modifier's randomized
    // chargen steps would ratchet stats upward on every save/load rebuild,
    // while wear/takeoff apply p1 as raw arithmetic.
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
    lda player_data + PL_STR_CUR,y
    clc
    adc inv_p1,x
    sta player_data + PL_STR_CUR,y
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

    // The ZP stat mirrors (bash, throw, the to-hit) follow at once: a
    // restore (Holy Word, a Potion of Restoration) left them stale until the
    // next load, and Holy Word's player_sync_to_zp, which refreshed them, also
    // undid the heal with the last save's HP (C64 Balrog queue, 2026-11-11).
    ldy #STAT_COUNT - 1
!pcs_zp:
    lda player_data + PL_STR_CUR,y
    sta zp_player_str,y             // absolute,y: no zp,y sta
    dey
    bpl !pcs_zp-
.assert "The ZP stat mirrors follow PL_*_CUR order", zp_player_chr - zp_player_str == PL_CHR_CUR - PL_STR_CUR && STAT_COUNT == 6, true

    // Persistent effect flags from the equipment: the routine below, by
    // falling through, or by a jump where a port places it elsewhere.
#if PLAYER_RECALC_PFLAGS_EXTERNAL
    jmp hal_player_recalc_pflags
#elif PFLAGS_SEGMENT_CUSTOM
    jmp player_recalc_pflags_equipment
#endif
.assert "Ring, amulet and left-hand ring slots are contiguous", EQUIP_AMULET == EQUIP_RING + 1 && EQUIP_RING2 == EQUIP_AMULET + 1, true
.assert "The jewels' flag ranges do not overlap (player_recalc_pflags_equipment)", ITEM_TYPE_RING_SLAYING <= ITEM_TYPE_AMULET_MAGI && ITEM_TYPE_AMULET_MAGI < ITEM_TYPE_RING_LORDLY_FIRE, true
.assert "Weapon, body, shield and head slots are contiguous", EQUIP_BODY == EQUIP_WEAPON + 1 && EQUIP_SHIELD == EQUIP_BODY + 1 && EQUIP_HEAD == EQUIP_SHIELD + 1, true

// The equipment flags: a port short of resident room places them with
// :PflagsSegment()/:PflagsRestoreSegment() (Plus/4 and Atari: their
// always-visible $F000 RuntimeBanked; C64: $F000 RuntimeBanked behind
// PLAYER_RECALC_PFLAGS_EXTERNAL).
#if !PFLAGS_SEGMENT_CUSTOM
.macro PflagsSegment() {}
.macro PflagsRestoreSegment() {}
#endif
:PflagsSegment()
player_recalc_pflags_equipment:
    lda #0
    sta pfe_f0
    sta pfe_f1
    sta pfe_f2
    sta pfe_f3
    sta player_sust_mask
    ldx #7
!pfe_zero_wield:
    sta wield_weight_lo,x
    dex
    bpl !pfe_zero_wield-

    ldx #EQUIP_WEAPON
!pfe_slot:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pfe_chk_ego+
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    sta item_cur_page
    lda inv_item_id,x
    jsr item_cat_select_id
    jsr item_cat_get_effects
    jsr !pfe_merge_flags+
    lda icat_flags_2
    and #ITR2_SUST_STAT
    beq !pfe_not_item_sust+
    ldy icat_p1_lo
    cpy #7
    bcc !pfe_sust_ok+
    ldy #0
!pfe_sust_ok:
    lda sust_p1_to_mask,y
    ora player_sust_mask
    sta player_sust_mask
!pfe_not_item_sust:
    cpx #EQUIP_WEAPON
    bne !pfe_chk_ego+
    // Cache hot wielded weapon stats so combat/turn never touch ITEM.CAT
    jsr item_cat_get_weight         // A=lo, Y=hi
    sta wield_weight_lo
    sty wield_weight_hi
    jsr item_cat_get_dmg_packed
    sta wield_dmg_packed
    jsr item_get_category_inv_x     // preserves X
    cmp #ICAT_WEAPON
    bne !pfe_wield_flags+
    jsr item_cat_get_missile_type
    sta wield_missile_type
!pfe_wield_flags:
    ldy #3
!pfe_wf_loop:
    lda icat_flags_0,y
    sta wield_flags_0,y
    dey
    bpl !pfe_wf_loop-
!pfe_chk_ego:
    lda inv_ego,x
    and #EGO_ID_MASK
    beq !pfe_next+
    // Digging tools store prefix IDs (1..4) in inv_ego, not weapon ego IDs.
    tay
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pfe_load_ego+
    jsr item_get_category_inv_x
    cmp #ICAT_DIGGING
    beq !pfe_next+
!pfe_load_ego:
    tya
    jsr item_cat_get_ego
    lda inv_ego,x
    and #EGO_ID_MASK
    cmp #EGO_SLOWNESS
    bne !pfe_ego_ok+
    lda icat_flags_1
    and #($ff ^ ITR1_SPEED)
    sta icat_flags_1
!pfe_ego_ok:
    jsr !pfe_merge_flags+
    lda icat_flags_2
    and #ITR2_SUST_STAT
    beq !pfe_ego_wield+
    lda icat_flags_0
    and #ITR0_STR
    beq !pfe_ego_wield+
    lda #SUST_STR
    ora player_sust_mask
    sta player_sust_mask
!pfe_ego_wield:
    cpx #EQUIP_WEAPON
    bne !pfe_next+
    ldy #3
!pfe_we_loop:
    lda wield_flags_0,y
    ora icat_flags_0,y
    sta wield_flags_0,y
    dey
    bpl !pfe_we_loop-
!pfe_next:
    inx
    cpx #EQUIP_END
    beq !pfe_slots_done+
    jmp !pfe_slot-
!pfe_slots_done:

    lda #0
    sta player_pflags
    sta player_pflags2
    ldx #14
!pfe_map_loop:
    ldy pfe_src_off,x
    lda pfe_f0,y
    and pfe_src_mask,x
    beq !pfe_map_next+
    cpx #8
    bcs !pfe_map_pf2+
    lda player_pflags
    ora pfe_dst_mask,x
    sta player_pflags
    bne !pfe_map_next+              // always non-zero
!pfe_map_pf2:
    lda player_pflags2
    ora pfe_dst_mask,x
    sta player_pflags2
!pfe_map_next:
    dex
    bpl !pfe_map_loop-

    // Update combat bonuses from stats
    jmp player_calc_combat

!pfe_merge_flags:
    ldy #3
!pmf_loop:
    lda pfe_f0,y
    ora icat_flags_0,y
    sta pfe_f0,y
    dey
    bpl !pmf_loop-
    rts

pfe_f0: .byte 0
pfe_f1: .byte 0
pfe_f2: .byte 0
pfe_f3: .byte 0
sust_p1_to_mask:
    .byte SUST_ALL, SUST_STR, SUST_INT, SUST_WIS, SUST_CON, SUST_DEX, SUST_CHR
.assert "sust_p1_to_mask covers 0..6", * - sust_p1_to_mask, 7

pfe_src_off:
    .byte 2, 2, 1, 3, 2, 2, 3, 3
    .byte 0, 1, 1, 1, 1, 0, 3
pfe_src_mask:
    .byte ITR2_RES_FIRE, ITR2_RES_COLD, ITR1_SPEED, ITR3_SEE_INVIS
    .byte ITR2_FREE_ACT, ITR2_RES_ACID, ITR3_RES_LIGHT, ITR3_FFALL
    .byte ITR0_SLOW_DIGEST, ITR1_REGEN, ITR1_STEALTH, ITR1_AGGRAVATE
    .byte ITR1_TELEPORT, ITR0_SEARCH, ITR3_INFRA
pfe_dst_mask:
    .byte PFLAG_RESIST_FIRE, PFLAG_RESIST_COLD, PFLAG_SPEED, PFLAG_SEE_INVIS
    .byte PFLAG_FREE_ACT, PFLAG_RESIST_ACID, PFLAG_RESIST_LIGHT, PFLAG_FFALL
    .byte PFLAG2_SLOW_DIGEST, PFLAG2_REGEN, PFLAG2_STEALTH, PFLAG2_AGGRAVATE
    .byte PFLAG2_TELEPORT, PFLAG2_SEARCH, PFLAG2_INFRA
.assert "pfe flag maps have 15 aligned entries", * - pfe_dst_mask, 15
:PflagsRestoreSegment()

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
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    bne !esm_page1+
    lda inv_item_id,x
    ldy #esm_p0_ids_end - esm_p0_ids - 1
!esm_p0_loop:
    cmp esm_p0_ids,y
    beq !esm_p0_hit+
    dey
    bpl !esm_p0_loop-
!esm_zero:
    lda #0
    rts
!esm_page1:
    lda inv_item_id,x
    ldy #esm_p1_ids_end - esm_p1_ids - 1
!esm_p1_loop:
    cmp esm_p1_ids,y
    beq !esm_p1_hit+
    dey
    bpl !esm_p1_loop-
    bmi !esm_zero-
!esm_ego_hit:
    lda esm_ego_masks,y
    rts
!esm_p0_hit:
    lda esm_p0_masks,y
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
esm_p0_ids:
    .byte ITEM_TYPE_RING_STRENGTH, ITEM_TYPE_AMULET_WISDOM, ITEM_TYPE_AMULET_MAGI, 212, 213
esm_p0_ids_end:
esm_p0_masks:
    .byte $01, $04, $02, $20, $3f
esm_p1_ids:
    .byte 318 - ITEM_PAGE_SIZE, 326 - ITEM_PAGE_SIZE, 329 - ITEM_PAGE_SIZE
    .byte 330 - ITEM_PAGE_SIZE, 331 - ITEM_PAGE_SIZE
esm_p1_ids_end:
esm_p1_masks:
    .byte $01, $02, $02, $08, $10

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

// Working byte for stat modification (survives across increment/decrement calls)
stat_work: .byte 0

// Persistent equipment-granted effect flags, recomputed by player_calc_stats.
player_pflags:      .byte 0
player_pflags2:     .byte 0
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
// player_apply_slaying_bonuses — Add Ring of Slaying / Damage / To-Hit and
// Slaying/Enveloping glove bonuses to pcc_eq_tohit/pcc_eq_todam.
// Clobbers: A, X
player_apply_slaying_bonuses:
    ldx #EQUIP_RING
!pasb_ring:
    lda inv_ego,x
    and #ITEM_PAGE_BIT
    bne !pasb_p1+
    lda inv_item_id,x
    cmp #ITEM_TYPE_RING_SLAYING
    beq !pasb_add+
    bne !pasb_next+
!pasb_p1:
    lda inv_item_id,x
    cmp #327 - ITEM_PAGE_SIZE       // Ring of Increase Damage
    beq !pasb_add+
    cmp #328 - ITEM_PAGE_SIZE       // Ring of Increase To-Hit
    bne !pasb_next+
!pasb_add:
    lda inv_to_hit,x
    clc
    adc pcc_eq_tohit
    sta pcc_eq_tohit
    lda inv_to_dam,x
    clc
    adc pcc_eq_todam
    sta pcc_eq_todam
!pasb_next:
    cpx #EQUIP_RING2
    beq !pasb_gloves+
    ldx #EQUIP_RING2
    bne !pasb_ring-
!pasb_gloves:
    ldx #EQUIP_HANDS
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !pasb_done+
    lda inv_ego,x
    and #EGO_ID_MASK
    cmp #EGO_SLAYING
    beq !pasb_add_g+
    cmp #EGO_ENVELOPING
    bne !pasb_done+
!pasb_add_g:
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

// apply_modifier — Apply a signed modifier to stat_work using increment/decrement
// Each +1 or -1 is applied individually via incrementStat/decrementStat (umoria).
// Input: A = signed modifier (-128 to +127)
//        stat_work = current stat value
// Output: stat_work = modified stat
// Clobbers: X, zp_temp3, zp_temp4, zp_math*
// Note: Uses am_count instead of X for loop counter because
//       increment_stat/decrement_stat clobber X via math_dice.
apply_modifier:
    cmp #0
    beq !done+
    bpl !positive+
    // Negative modifier: negate to get count
    eor #$ff
    clc
    adc #1
    sta am_count
!dec_loop:
    lda stat_work
    jsr decrement_stat
    sta stat_work
    dec am_count
    bne !dec_loop-
    rts
!positive:
    sta am_count
!inc_loop:
    lda stat_work
    jsr increment_stat
    sta stat_work
    dec am_count
    bne !inc_loop-
!done:
    rts

am_count: .byte 0  // Loop counter for apply_modifier (safe from X clobber)

// increment_stat — Increment a stat using umoria's randomized step logic
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Clobbers: zp_temp3, zp_temp4, zp_math* (via math_dice)
increment_stat:
    cmp #18
    bcs !above_17+
    // stat < 18: simple +1
    clc
    adc #1
    rts
!above_17:
    cmp #88
    bcs !above_87+
    // stat 18-87: add rng(15)+5 = add 6-20
    pha
    lda #1
    ldx #15
    ldy #5
    jsr math_dice           // 1d15+5 = 6..20
    pla
    clc
    adc zp_math_a
    cmp #119
    bcc !inc_ok+
    lda #118                // Cap at 118 (18/100)
!inc_ok:
    rts
!above_87:
    cmp #108
    bcs !above_107+
    // stat 88-107: add rng(6)+2 = add 3-8
    pha
    lda #1
    ldx #6
    ldy #2
    jsr math_dice           // 1d6+2 = 3..8
    pla
    clc
    adc zp_math_a
    cmp #119
    bcc !inc_ok2+
    lda #118
!inc_ok2:
    rts
!above_107:
    // stat > 107: +1
    clc
    adc #1
    cmp #119
    bcc !inc_ok3+
    lda #118
!inc_ok3:
    rts

// decrement_stat — Decrement a stat using umoria's randomized step logic
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Clobbers: zp_temp3, zp_temp4, zp_math* (via math_dice)
decrement_stat:
    cmp #109
    bcs !above_108+
    cmp #88
    bcs !range_88_108+
    cmp #19
    bcs !range_19_87+
    // stat <= 18
    cmp #4
    bcc !dec_done+          // stat <= 3: no change
    // stat 4-18: simple -1
    sec
    sbc #1
    rts
!above_108:
    // stat > 108: -1
    sec
    sbc #1
    rts
!range_88_108:
    // stat 88-108: subtract rng(6)+2 = 3-8
    pha
    lda #1
    ldx #6
    ldy #2
    jsr math_dice           // 1d6+2 = 3..8
    pla
    sec
    sbc zp_math_a
    rts
!range_19_87:
    // stat 19-87: subtract rng(15)+5 = 6-20
    pha
    lda #1
    ldx #15
    ldy #5
    jsr math_dice           // 1d15+5 = 6..20
    pla
    sec
    sbc zp_math_a
    // If result < 19, clamp to 18
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
    // Max HP = class_hit_die + (level-1) * (class_hit_die/2 + CON_bonus)
    // Simplified: at level 1, HP = hit die. Each level adds hit_die/2 + CON bonus.
    lda player_data + PL_CLASS
    tax
    // Get class properties — hp die is first byte
    lda #CLASS_PROP_SIZE
    jsr mul_x_by_a          // A = class * CLASS_PROP_SIZE
    tax
    lda class_properties,x  // Class hit die
    sta zp_temp0            // Save class HD

    // Add race hit die (umoria: combined HD = race_HD + class_HD)
    lda player_data + PL_RACE
    tax
    lda #RACE_PROP_SIZE
    jsr mul_x_by_a          // A = race * RACE_PROP_SIZE
    tax
    lda race_properties,x   // Race HD (offset 0)
    clc
    adc zp_temp0
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
    bpl !min_check+
    lda #1                  // Minimum 1 HP per level
!min_check:
    cmp #1
    bcs !ok+
    lda #1
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
    lda zp_math_b
    adc #0
    sta player_data + PL_MHP_HI
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
    cmp player_data + PL_FLAGS
    beq !done+
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
!done:
    rts

// player_search_mode_off — Disable persistent search mode
// Preserves: nothing
player_search_mode_off:
    lda player_data + PL_FLAGS
    and #($ff - PLF_SEARCHING)
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

// ============================================================
// ui_char_draw_background — Draw sex, social class, background on char sheet
// Called from ui_char_display in OVL.UI on C64 and C128.
// Main RAM so no banking issues.
// Renders rows 12-16 of the character sheet.
// Preserves: nothing
// ============================================================
.const UDBG_COL = hal_layout_character_background_col

ui_char_draw_background:
#if HAL_PLATFORM_CHARACTER_BACKGROUND_RESYNC
    jsr hal_platform_runtime_resync
#endif
    // --- Sex / Social Class (row 12) ---
    lda #12
    sta zp_cursor_row
    lda #UDBG_COL
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<char_sex_label
    ldy #>char_sex_label
    jsr screen_put_string_ay

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_FLAGS
    and #PLF_MALE
    beq !udb_female+
    lda #<char_sex_male
    sta zp_ptr0
    lda #>char_sex_male
    sta zp_ptr0_hi
    jmp !udb_print_sex+
!udb_female:
    lda #<char_sex_female
    sta zp_ptr0
    lda #>char_sex_female
    sta zp_ptr0_hi
!udb_print_sex:
    jsr hal_screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #<char_sc_label
    ldy #>char_sc_label
    jsr screen_put_string_ay
    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_SOCIAL_CLASS
    jsr screen_put_decimal

    // --- Background text (rows 13-16) ---
    lda #COL_LGREY
    sta zp_text_color
    ldx #0
!udb_line_loop:
    txa
    pha
    clc
    adc #13
    sta zp_cursor_row
    lda #UDBG_COL
    sta zp_cursor_col
    pla
    tax
    pha
    lda udb_line_lo,x
    sta zp_ptr0
    lda udb_line_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    pla
    tax
    inx
    cpx #4
    bcc !udb_line_loop-
    rts

// Background line pointer lookup table
udb_line_lo:
    .byte <player_background, <(player_background + 40)
    .byte <(player_background + 80), <(player_background + 120)
udb_line_hi:
    .byte >player_background, >(player_background + 40)
    .byte >(player_background + 80), >(player_background + 120)

// ============================================================
// Compile-time validation
// ============================================================
.assert "Player struct size", PL_STRUCT_SIZE, 111
