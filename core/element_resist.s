#importonce
// element_resist.s — The player's resistance to an element (MON-025,
// MON-027, MON-028): the divisor breath (core/monster_magic.s) and the fire,
// cold and lightning touches (core/monster_attack.s) both apply. Imported by
// both; #importonce keeps one copy where it first lands.

mm_divisor:    .byte 0         // Breath damage divisor

// The divisor's code and tables: a port short of resident room places them
// with :ElementResistSegment()/:ElementResistRestoreSegment() and enters them
// through its own mm_element_divisor_entry (the C64: its $F000 runtime).
#if !ELEMENT_RESIST_SEGMENT_CUSTOM
.macro ElementResistSegment() {}
.macro ElementResistRestoreSegment() {}
.label mm_element_divisor_entry = mm_element_divisor
#endif
:ElementResistSegment()
// mm_element_divisor — mm_divisor = A, x 3 for the lasting resistance to
// element X (MS_BREATH_*), x 3 again for the frost or fire timer: lightning
// (light_dam), frost and fire (cold_dam, fire_dam) as VMS moria.inc; gas
// (poison_gas) none. Breath and the element touches (MON-028). Keeps X.
// Clobbers: A, Y
mm_element_divisor:
    sta mm_divisor
    lda player_pflags
    and mm_resist_flag - 1,x
    beq !med_no_ring+
    jsr mm_triple_divisor
!med_no_ring:
    cpx #MS_BREATH_FROST
    bcc !med_done+            // Lightning, gas: no timer
    ldy mm_resist_timer - MS_BREATH_FROST,x
    lda $0000,y
    beq !med_done+
    jsr mm_triple_divisor
!med_done:
    rts

// mm_triple_divisor — mm_divisor x 3 (at most 4 x 3, or 3 x 3 x 3). Clobbers: A
mm_triple_divisor:
    lda mm_divisor
    asl
    adc mm_divisor            // C clear: the divisor is under 128
    sta mm_divisor
    rts
mm_resist_flag:  .byte PFLAG_RESIST_LIGHT, 0, 0, PFLAG_RESIST_COLD, PFLAG_RESIST_FIRE   // acid: !mcb_acid
mm_resist_timer: .byte eff_resist_cold_timer, zp_eff_resist
.assert "The resistance tables follow the elements", MS_BREATH_LIGHTNING == 1 && MS_BREATH_FROST == 4 && MS_BREATH_FIRE == 5, true
.assert "Resist timers are zero-page", eff_resist_cold_timer < $100 && zp_eff_resist < $100, true
:ElementResistRestoreSegment()
