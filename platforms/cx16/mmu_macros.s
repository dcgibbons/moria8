#importonce
// CX16 bring-up keeps the map in ordinary fixed RAM. The shared map access
// macros can therefore be direct zero-page indirect accesses for now.

.macro MapRead_ptr0_y() {
    lda (zp_ptr0),y
}

.macro MapWrite_ptr0_y() {
    sta (zp_ptr0),y
}

.macro MapRead_ptr1_y() {
    lda (zp_ptr1),y
}

.macro MapWrite_ptr1_y() {
    sta (zp_ptr1),y
}
