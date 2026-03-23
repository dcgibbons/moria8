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
