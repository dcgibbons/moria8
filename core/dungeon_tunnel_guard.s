#importonce
// UMoria's 2,000-iteration emergency guard for one staged tunnel.

.const DUN_TUNNEL_MAX_STEPS = 2000

dg_tun_count_lo: .byte 0
dg_tun_count_hi: .byte 0

dungeon_tunnel_guard_reset:
    lda #0
    sta dg_tun_count_lo
    sta dg_tun_count_hi
    rts

// Carry set after 2,000 iterations have already been admitted.
dungeon_tunnel_guard_step:
    inc dg_tun_count_lo
    bne !check+
    inc dg_tun_count_hi
!check:
    lda dg_tun_count_hi
    cmp #>DUN_TUNNEL_MAX_STEPS
    bcc !admit+
    bne !reject+
    lda dg_tun_count_lo
    cmp #<(DUN_TUNNEL_MAX_STEPS + 1)
    bcs !reject+
!admit:
    clc
    rts
!reject:
    sec
    rts
