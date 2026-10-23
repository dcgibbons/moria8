#importonce
// mmu_macros.s — BBC Master 128 map, BeebAuxData, and BeebHuffData access macros.
// Required by core/ via -libdir shadowing. Dispatches to memory_bank.s (< $3000).

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

// Known item-name streams live in Bank 6 BeebAuxData.
.macro ItemNameRead_ptr0_y() {
    jsr mmu_safe_map_read_ptr0
}

// Huffman bitstream lives in 4 KB ANDY ($8000-$8D93, ROMSEL = $84).
.macro HuffRead_ptr0_y() {
    jsr mmu_safe_huff_read_ptr0
}

// Spell data tables live in Bank 6 BeebAuxData.
.macro SpellTblRead_ptr0_y() {
    jsr mmu_safe_map_read_ptr0
}

// Aux-resident mutable data accessors (store inventory, recall counters in Bank 6).
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

// Save/load byte-stream reads/writes through block descriptors.
.macro SaveByteRead_ptr0_y() {
    bit beeb_save_aux_mode_flag
    bmi !sbr_aux+
    lda (zp_ptr0),y
    jmp !sbr_done+
!sbr_aux:
    jsr mmu_safe_map_read_ptr0
!sbr_done:
}

.macro SaveByteWrite_ptr0_y() {
    bit beeb_save_aux_mode_flag
    bmi !sbw_aux+
    sta (zp_ptr0),y
    jmp !sbw_done+
!sbw_aux:
    jsr mmu_safe_map_write_ptr0
!sbw_done:
}
