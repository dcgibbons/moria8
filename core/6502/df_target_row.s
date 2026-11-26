#importonce
// df_target_row.s — Map row pointer for the door/trap/tunnel target tile.
// Imported by every user; dungeon_features.s imports it first on every
// platform, so it is placed with df_target_x/y.

// df_target_row_ptr — zp_ptr0 = map row df_target_y; X = df_target_y,
// Y = df_target_x, ready for :MapRead_ptr0_y()
df_target_row_ptr:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    rts
