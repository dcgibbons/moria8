#importonce
// Coordinate-only town entrance lookup shared by movement and runner tests.

// Input: A=x, Y=y. Output: carry set + A=store index, or carry clear.
// Clobbers: A, X, zp_ptr1, zp_ptr1_hi
check_store_door_at:
    sta zp_ptr1
    sty zp_ptr1_hi
    ldx #7
!loop:
    lda zp_ptr1
    cmp store_door_x,x
    bne !next+
    lda zp_ptr1_hi
    cmp store_door_y,x
    bne !next+
    txa
    sec
    rts
!next:
    dex
    bpl !loop-
    clc
    rts
