#importonce
// Apple IIe map access macros. Core map access is exclusively through these
// macros (verified M0: 25 core files); they dispatch to the aux-safe wrappers
// in memory_aux.s. Required by core via -libdir shadowing.

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

// Known item-name streams live in aux RAM on Apple IIe.
.macro ItemNameRead_ptr0_y() {
    jsr mmu_safe_map_read_ptr0
}

// Huffman decoder data reads. huffman_data.s lives in AUX RAM on this
// platform (A2AuxData segment, boot-preloaded to aux $3B0C), so these read
// through the p1 aux thunk. X is preserved by the thunks.
.macro HuffRead_str_index_x() {
    txa
    tay
    lda #<huff_str_index
    sta zp_ptr1
    lda #>huff_str_index
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro HuffRead_str_index_hi_x() {
    txa
    tay
    lda #<huff_str_index+1
    sta zp_ptr1
    lda #>huff_str_index+1
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro HuffRead_str_index256_x() {
    txa
    tay
    lda #<huff_str_index+256
    sta zp_ptr1
    lda #>huff_str_index+256
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro HuffRead_str_index257_x() {
    txa
    tay
    lda #<huff_str_index+257
    sta zp_ptr1
    lda #>huff_str_index+257
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro HuffRead_tree_left_y() {
    lda #<huff_tree_left
    sta zp_ptr1
    lda #>huff_tree_left
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro HuffRead_tree_right_y() {
    lda #<huff_tree_right
    sta zp_ptr1
    lda #>huff_tree_right
    sta zp_ptr1_hi
    jsr mmu_safe_map_read_ptr1
}

.macro HuffRead_ptr0_y() {
    :MapRead_ptr0_y()
}

// Aux-resident mutable data accessors (store inventory, recall counters).
// These blocks live in AUX RAM on this platform (A2AuxData segment), so all
// access goes through the p1 aux thunks. Write macros preserve the stored
// value in A and the index in X/Y through the thunk.
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
    sta a2_zp_scratch
    txa
    tay
    lda #<label
    sta zp_ptr1
    lda #>label
    sta zp_ptr1_hi
    lda a2_zp_scratch
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

// Save/load byte-stream reads/writes through block descriptors. Blocks are
// dispatched per-descriptor: a2_save_block_mode sets a2_save_aux_mode_flag
// for aux-resident blocks (si_item_id, recall_data_start); everything else
// streams through direct main-RAM access (identical to Commodore behavior).
.macro SaveByteRead_ptr0_y() {
    bit a2_save_aux_mode_flag
    bmi !sbr_aux+
    lda (zp_ptr0),y
    jmp !sbr_done+
!sbr_aux:
    jsr mmu_safe_map_read_ptr0
!sbr_done:
}

.macro SaveByteWrite_ptr0_y() {
    bit a2_save_aux_mode_flag
    bmi !sbw_aux+
    sta (zp_ptr0),y
    jmp !sbw_done+
!sbw_aux:
    jsr mmu_safe_map_write_ptr0
!sbw_done:
}
