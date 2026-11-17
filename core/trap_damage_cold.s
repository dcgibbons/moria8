#importonce
// trap_damage_cold.s — Trap/chest damage application and death-cause staging (S2b)
//
// Module ownership:
//   owner: ChestOverlay when TRAP_DAMAGE_EXTERNAL is defined (co-located with
//     both trap_trigger_cold.s and core/chest.s, e.g. Apple IIe); Default
//     resident otherwise so ports splitting disarm.s and chest.s across
//     overlays (e.g. Plus/4) share it without cross-overlay calls.
//   lifetime: one floor-trap or chest-trap damage roll.
//   callers: trap_trigger_cold.s (trap_apply_damage, trap_apply_rolled_damage)
//     and core/chest.s (trap_apply_damage, which always sets df_death_hstr != 0).

// ============================================================
// trap_apply_damage — Roll damage and subtract from player HP
// Input: A = dice count, X = dice sides (no bonus: every trap is plain dice)
// Prints "YOU TAKE N DAMAGE." message.
// ============================================================
trap_apply_damage:
    ldy #0                  // +0
    jsr math_dice           // Result in zp_math_a (lo), zp_math_b (hi)
trap_apply_rolled_damage:

    // Save damage amount
    lda zp_math_a
    sta df_target_x         // Reuse scratch for damage value

    // Subtract from player HP (16-bit)
    lda zp_player_hp_lo
    sec
    sbc zp_math_a
    sta zp_player_hp_lo
    lda zp_player_hp_hi
    sbc zp_math_b
    sta zp_player_hp_hi

    // Clamp lethal trap damage before syncing the player struct (A and N
    // still hold the high byte).
    bmi !trap_lethal+
    ora zp_player_hp_lo
    bne !trap_sync+

!trap_lethal:
    lda #0
    sta zp_player_hp_lo
    sta zp_player_hp_hi
    lda df_death_source
    sta zp_death_source
    jsr trap_resolve_death_name

!trap_sync:
    // Sync to player struct
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Print "You take N damage." as one message, built in combat_msg_buf as
    // "You found N gold pieces." is (core/item.s). Printed as "You take " with
    // the number and " damage." written past it, the message row's length
    // ended at column 9 and a following -more- covered the number: "You take
    // -more-ge." on every port, about one trap hit in four, and the history
    // kept "You take " alone (build queue, 2026-11-16).
    lda #0
    sta cmb_buf_idx
    ldx #HSTR_DF_DAMAGE_PRE
    jsr huff_append_combat
    lda df_target_x
    jsr combat_append_decimal
    ldx #HSTR_DF_DAMAGE_POST
    jsr huff_append_combat
    jsr cmb_term_and_print

    // Play hit sound for surviving hits; lethal trap damage uses the
    // standard death path so the death sound is not overwritten.
    // Returns Z=1 if dead, Z=0 if alive.
    lda zp_player_hp_hi
    ora zp_player_hp_lo
    beq !trap_death+

    lda #SFX_HIT
    jsr hal_sound_play
    lda #1
    rts

!trap_death:
    jsr player_death_check
    lda #0
    rts

// ============================================================
// trap_resolve_death_name — Resolve lethal trap cause text
// ============================================================
// Copies the existing trap name string into creature_name_buf so the death
// overlay can display it after tier/overlay memory has been replaced.
trap_resolve_death_name:
    ldx df_death_hstr
    beq !trdn_done+         // Plain-string traps pre-staged creature_name_buf
    jsr huff_decode_string
    ldy #0
!trdn_copy:
    lda hd_decode_buf,y
    sta creature_name_buf,y
    beq !trdn_done+         // Static trap death names are <= 13 bytes (< 32)
    iny
    bne !trdn_copy-
!trdn_done:
    rts
