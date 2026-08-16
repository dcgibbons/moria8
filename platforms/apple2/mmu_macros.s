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

.macro HuffRead_ptr0_y() {
    :MapRead_ptr0_y()
}

// Spell data table reads (player_magic* selection/list UIs) via zp_ptr0.
// The spell tables are aux-resident on this port, so these use the map-read
// aux thunk — never the Bank 1 Huffman corpus path.
.macro SpellTblRead_ptr0_y() {
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
