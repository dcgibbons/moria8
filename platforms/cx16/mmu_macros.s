#importonce
// mmu_macros.s — Commander X16 map, AuxData, and HuffData access macros.
// Required by core/ via -libdir shadowing. Dispatches to memory_bank.s.

.macro MapRead_ptr0_y() {
    jsr mmu_safe_map_read_ptr0
}

.macro MapWrite_ptr0_y() {
    jsr mmu_safe_map_write_ptr0
}

.macro MapRead_ptr1_y() {
    jsr mmu_safe_map_read_ptr1
}

.macro MapWrite_ptr1_y() {
    jsr mmu_safe_map_write_ptr1
}

.macro ItemNameRead_ptr0_y() {
    jsr mmu_safe_map_read_ptr0
}

.macro HuffRead_ptr0_y() {
    :MapRead_ptr0_y()
}

.macro SpellTblRead_ptr0_y() {
    :MapRead_ptr0_y()
}

.macro AuxReadX(label) {
    txa
    tay
    lda #<label
    sta zp_ptr1
    lda #>label
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro AuxReadY(label) {
    lda #<label
    sta zp_ptr1
    lda #>label
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro AuxWriteX(label) {
    pha
    txa
    tay
    lda #<label
    sta zp_ptr1
    lda #>label
    sta zp_ptr1_hi
    pla
    jsr mmu_safe_map_write_ptr1
}

.macro AuxWriteY(label) {
    pha
    lda #<label
    sta zp_ptr1
    lda #>label
    sta zp_ptr1_hi
    pla
    jsr mmu_safe_map_write_ptr1
}

.macro AuxIncX(label) {
    txa
    tay
    lda #<label
    sta zp_ptr1
    lda #>label
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
    clc
    adc #1
    jsr mmu_safe_map_write_ptr1
}

.macro SaveByteRead_ptr0_y() {
    bit cx16_save_aux_mode_flag
    bmi !sbr_aux+
    lda (zp_ptr0),y
    bra !sbr_done+
!sbr_aux:
    jsr mmu_safe_map_read_ptr0
!sbr_done:
}

.macro SaveByteWrite_ptr0_y() {
    bit cx16_save_aux_mode_flag
    bmi !sbw_aux+
    sta (zp_ptr0),y
    bra !sbw_done+
!sbw_aux:
    jsr mmu_safe_map_write_ptr0
!sbw_done:
}
