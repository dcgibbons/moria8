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
.macro HuffRead_ptr0_y() {
    lda (zp_ptr0),y
}

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
