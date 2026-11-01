#importonce
// eff_potion_cure.s — Cure-wounds and Healing potion effects (heal + cure).
// Imported beside player_heal_feedback.s by player_items.s, or by the
// platform (Apple IIe and BBC Master resident; C128 banked runtime).

// ============================================================
// Cure-wounds and Healing potions, every port (VMS Moria 4.8
// `source/include/potions.inc` quaff cases 13-16 and 29-31, flags in
// `values.inc`; Umoria 5.7.15 `src/player_quaff.cpp`, same amounts and cures):
//   Cure Light Wounds    (#17)  2d7 HP, cures blindness
//   Cure Serious Wounds  (#25)  4d7 HP, cures blindness and confusion
//   Cure Critical Wounds (#100) 6d7 HP, cures blindness, confusion and poison
//   Healing              (#96)  1000 HP, cures blindness, confusion and poison
// The heal is VMS `hp_player` (pmx_heal_and_report): nothing at full HP, else
// the message for the rolled amount. A cure is VMS `cure_blindness` /
// `cure_confusion` / `cure_poison` (`spells.inc`): a timer above 1 drops to 1
// and prints nothing; the `turn_tick_effects` of the same `turn_post_action`
// then ends it with its usual expiry message (and, for blindness, the
// viewport redraw).
// ============================================================
// EFF_CURE_* masks live in item_defs.s (callers precede this file).
.assert "Cure timers are poison, blind, confuse in mask-bit order", zp_eff_blind == zp_eff_poison + 1 && zp_eff_confuse == zp_eff_poison + 2, true

// eff_potion_healing — Potion of Healing: hp_player(1000), then cure all.
// 250 + 3 x 250 = 1000, capped at max HP by eff_heal; the message is the
// one for 1000 ("You feel very good.", any amount of 35 or more).
// Output: carry set. Clobbers: A, X, Y
eff_potion_healing:
    lda #250
    jsr pmx_heal_and_report             // Full-HP gate and message
    ldy #3
!eph_heal:
    lda #250
    jsr eff_heal                        // Silent; clobbers A only
    dey
    bne !eph_heal-
    lda #EFF_CURE_ALL
    bne eff_cure_timers                 // Always

// eff_potion_heal_cure — Cure-wounds potion: hp_player(N d S), then cure.
// Input: A = EFF_CURE_* mask, X = sides S, Y = dice count N
// Output: carry set. Clobbers: A, X, Y
eff_potion_heal_cure:
    pha
    tya
    ldy #0
    jsr math_dice                       // zp_math_a = N d S (6d7 <= 42)
    lda zp_math_a
    jsr pmx_heal_and_report
    pla
// eff_cure_timers — Cure the timers named by A (EFF_CURE_* mask): each one
// above 1 becomes 1, so it expires on the next effect tick.
// Output: carry set. Clobbers: A, X, Y
eff_cure_timers:
    ldx #0
!ect_loop:
    lsr
    bcc !ect_next+
    ldy zp_eff_poison,x
    cpy #2
    bcc !ect_next+                      // 0 or 1: nothing to cure
    ldy #1
    sty zp_eff_poison,x
!ect_next:
    inx
    tay                                 // Z = no mask bits left
    bne !ect_loop-
    sec
    rts
