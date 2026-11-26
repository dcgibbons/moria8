#importonce
// df_target_dir.s — Target tile one step from the player. Imported by every
// user; spell_effects.s imports it first on every platform (resident).

// df_target_from_dir — df_target_x/y = player position + direction X (0-7)
// Output: A = df_target_y. Preserves: X, Y
df_target_from_dir:
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
    rts
