#importonce

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

// Known item-name streams use the platform's non-default data bank.
.macro ItemNameRead_ptr0_y() {
    jsr mmu_safe_db_read_ptr0
}

// Indirect class-spell table reads are resident on Commodore platforms.
// C128 routes them through the Bank 1 safe-read thunks: its Huffman corpus
// lives in the Bank 1 $F000 region (HAL_PLATFORM_HUFFMAN_DATA_AUX).
#if HAL_PLATFORM_HUFFMAN_DATA_AUX
.macro HuffRead_ptr0_y() {
    jsr mmu_safe_db_read_ptr0
}
#else
.macro HuffRead_ptr0_y() {
    lda (zp_ptr0),y
}
#endif

// Spell data table reads (player_magic* selection/list UIs) via zp_ptr0.
// These tables live in resident/overlay memory on Commodore, aux on Apple II
// — never in the Huffman corpus region, so this macro stays direct even when
// HAL_PLATFORM_HUFFMAN_DATA_AUX banks the corpus reads.
.macro SpellTblRead_ptr0_y() {
    lda (zp_ptr0),y
}

#if HAL_PLATFORM_HUFFMAN_DATA_AUX
.macro HuffRead_str_index_x() {
    txa
    tay
    lda #<huff_str_index
    sta zp_ptr1
    lda #>huff_str_index
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
}

.macro HuffRead_str_index_hi_x() {
    txa
    tay
    lda #<huff_str_index+1
    sta zp_ptr1
    lda #>huff_str_index+1
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
}

.macro HuffRead_str_index256_x() {
    txa
    tay
    lda #<huff_str_index+256
    sta zp_ptr1
    lda #>huff_str_index+256
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
}

.macro HuffRead_str_index257_x() {
    txa
    tay
    lda #<huff_str_index+257
    sta zp_ptr1
    lda #>huff_str_index+257
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
}

.macro HuffRead_tree_left_y() {
    lda #<huff_tree_left
    sta zp_ptr1
    lda #>huff_tree_left
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
}

.macro HuffRead_tree_right_y() {
    lda #<huff_tree_right
    sta zp_ptr1
    lda #>huff_tree_right
    sta zp_ptr1_hi
    jsr mmu_safe_db_read_ptr1
}
#endif

// Aux-resident mutable data accessors (store inventory, recall counters).
// Commodore platforms keep these blocks in main RAM: direct access, zero
// codegen change. Apple II moves them to aux RAM and binds these to thunked
// reads/writes (platforms/apple2/mmu_macros.s).
.macro AuxReadX(label) {
    lda label,x
}

.macro AuxReadY(label) {
    lda label,y
}

.macro AuxWriteX(label) {
    sta label,x
}

.macro AuxWriteY(label) {
    sta label,y
}

.macro AuxIncX(label) {
    inc label,x
}

// Save/load byte-stream reads/writes through block descriptors.
// Commodore blocks are all main RAM: direct access, zero codegen change.
// Apple II dispatches per-descriptor via a2_save_aux_mode_flag (set by
// a2_save_block_mode) between main-RAM and aux-thunk access.
.macro SaveByteRead_ptr0_y() {
    lda (zp_ptr0),y
}

.macro SaveByteWrite_ptr0_y() {
    sta (zp_ptr0),y
}
