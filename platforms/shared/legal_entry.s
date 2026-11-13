#importonce
.label legal_zp_save = LEGAL_BASE + $600
// Resident callers save core ZP before the required asset load.
// LEGALUI code ends below +$600, so loading the PRG cannot overwrite this state.
.macro LegalSnapshot() {
    ldx #$8e
!save:
    dex
    lda $02,x
    sta legal_zp_save,x
    txa
    bne !save-
}

// Keep live modal events at both restoration boundaries. Loaders preserve
// the sound triplet; input polling may advance it while a retry prompt waits.
.macro LegalRestore() {
    // Keep redraw requests raised by the modal and sound that advanced while
    // waiting for input; neither is rolled back to the entry snapshot.
    lda zp_ui_dirty
    ora legal_zp_save + zp_ui_dirty - $02
    sta legal_zp_save + zp_ui_dirty - $02
    ldx #$8d
!restore:
    cpx #zp_snd_phase - $02
    bne !copy+
    ldx #zp_snd_effect - $03
!copy:
    lda legal_zp_save,x
    sta $02,x
    dex
    cpx #$ff
    bne !restore-
    clc
}
