#importonce
.const LEGAL_ZP_SNAPSHOT_BASE = $02
.label legal_zp_save = LEGAL_BASE + $e00
// Resident callers save core ZP before the required asset load.
// LEGALUI code ends below +$e00, so loading the PRG cannot overwrite this state.
.macro LegalSnapshot() {
    ldx #$8e
!save:
    dex
    lda LEGAL_ZP_SNAPSHOT_BASE,x
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
    ora legal_zp_save + zp_ui_dirty - LEGAL_ZP_SNAPSHOT_BASE
    sta legal_zp_save + zp_ui_dirty - LEGAL_ZP_SNAPSHOT_BASE
    ldx #$8d
!restore:
    cpx #zp_snd_phase - LEGAL_ZP_SNAPSHOT_BASE
    bne !copy+
    ldx #zp_snd_effect - (LEGAL_ZP_SNAPSHOT_BASE + 1)
!copy:
    lda legal_zp_save,x
    sta LEGAL_ZP_SNAPSHOT_BASE,x
    dex
    cpx #$ff
    bne !restore-
    clc
}
