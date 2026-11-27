#importonce
// player_gain_stat_helpers.s — Gain-stat potion helpers split from player.s.
//
// Owner: inline in Default via player.s on ports/tests with resident room,
// or placed with / alongside eff_gain_stat.s via PLAYER_GAIN_STAT_HELPERS_EXTERNAL
// (C64 TitleOverlay, Plus/4 ItemActionsOverlay, C128 C128ResidentPlay).
// Callers: eff_gain_stat.s (plus test_player.s unit tests where Default keeps
// them inline). Only calls resident pses_zero_res_write_y / pses_write_cur_y
// and player_step_equip_stat_y in player.s.

// player_step_healthy_sum_y — Step stat Y (0..5) from clamped base A (3..118)
// by signed eq_mod in stat_work (< 0) and return ((cur + res) - X) & $FF.
// Preserves: X, Y. Clobbers: A, stat_step_cnt.
player_step_healthy_sum_y:
    jsr pses_zero_res_write_y
    lda stat_work
    jsr player_step_equip_stat_y    // returns A == PL_STR_CUR[Y]
    clc
    adc player_stat_res,y
    stx stat_step_cnt
    sec
    sbc stat_step_cnt
    rts

// player_apply_stat_delta_y — Add unsigned delta A (0..25 from eff_gain_stat,
// Z reflects A) to stat Y (0..5), clamp PL_STR_CUR,y & zp_player_str,y to [3, 118],
// and update player_stat_res,y (preserving negative residuals at cur == 3 and
// saturating positive cap residuals at +127).
// Preserves: X, Y. Clobbers: A.
player_apply_stat_delta_y:
    beq !pasd_ret+
    pha
    lda player_data + PL_STR_CUR,y
    cmp #118
    bne !pasd_not118+
    pla
    clc
    adc player_stat_res,y
    bpl !pasd_hi_store+
    lda #$7f
!pasd_hi_store:
    sta player_stat_res,y
!pasd_ret:
    rts
!pasd_not118:
    cmp #3
    bne !pasd_mid+
    lda player_stat_res,y
    bpl !pasd_mid+
    // cur == 3 with negative residual (-128..-1): pay down residual before lifting cur
    pla
    clc
    adc player_stat_res,y
    bcc !pasd_hi_store-
    adc #2                      // C=1 when bcc not taken -> +3
    bne !pasd_zero_res+
!pasd_mid:
    pla
    clc
    adc player_data + PL_STR_CUR,y
    cmp #119
    bcc !pasd_zero_res+
    sbc #118                    // C=1 when bcc not taken
    sta player_stat_res,y
    lda #118
    jmp pses_write_cur_y
!pasd_zero_res:
    jmp pses_zero_res_write_y
