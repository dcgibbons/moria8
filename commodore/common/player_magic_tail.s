#importonce
// player_magic_tail.s — C128-relocatable spell dispatch tail
//
// Split from player_magic.s so the dispatch tables and directional spell
// helpers can live in the resident banked compute window without moving the
// whole spell-command UI/selection path.

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
