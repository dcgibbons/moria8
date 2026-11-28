#importonce
// overlay_storage.s — BBC Master 128 Sideways RAM overlay/tier cache + play-slot check (< $3000).
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md & cache_layout.s.
// Six hot overlay classes (GEN, UI, ITEMS, SPELL, MODAL, TITLE) are preloaded
// into Sideways RAM Banks 5, 6, and 7 at boot by MORIA8P.
// Cache hits copy the payload pages via beeb_swr_copy_to_window into Bank 4's
// $A800-$BFFF window with zero disk I/O. Cold overlays (OVLSTA, OVLTWN,
// OVLDTH, OVLHLP, OVLCHS, OVLHOM, OVLSTO) fall through to DFS; OVLUI holds
// store_restock_overlay (6p Bank 6), OVLMODAL (10p) + OVLTTL (2p) share Bank 5,
// ui_character moved to OVLSTA, ui_inventory+ui_equipment moved to cached
// OVLITM, and bash+tunnel+calc_dig moved to OVLCHS.

#import "hal/storage_policy.s"
#import "cache_layout.s"
#import "memory.s"

// ============================================================
// Sideways RAM Cache Lookup Tables (index = overlay ID - 1: 0..12)
// Order: START(0), TOWN(1), DEATH(2), GEN(3), HELP(4), UI(5),
//        ITEMS(6), SPELL(7), MODAL(8), CHEST(9), HOME(10), STORAGE(11), TITLE(12)
// (check_memory_contract.py --disk reads this Order list; keep its form.)
// ============================================================
beeb_ovl_cache_bank:
    .byte $00, $00, $00, BEEB_SWR_BANK_GEN, $00, BEEB_SWR_BANK_UI
    .byte BEEB_SWR_BANK_ITEMS, BEEB_SWR_BANK_SPELL, BEEB_SWR_BANK_MODAL, $00, $00, $00, BEEB_SWR_BANK_TITLE

beeb_ovl_cache_hi:
    .byte $00, $00, $00, >BEEB_SWR_ADDR_GEN, $00, >BEEB_SWR_ADDR_UI
    .byte >BEEB_SWR_ADDR_ITEMS, >BEEB_SWR_ADDR_SPELL, >BEEB_SWR_ADDR_MODAL, $00, $00, $00, >BEEB_SWR_ADDR_TITLE

beeb_ovl_cache_pages:
    .byte $00, $00, $00, BEEB_SWR_PAGES_GEN, $00, BEEB_SWR_PAGES_UI
    .byte BEEB_SWR_PAGES_ITEMS, BEEB_SWR_PAGES_SPELL, BEEB_SWR_PAGES_MODAL, $00, $00, $00, BEEB_SWR_PAGES_TITLE

// ============================================================
// beeb_overlay_try_cache — Sideways RAM cache front end for overlays.
// Input:  X = filename pointer lo, Y = filename pointer hi
// Output: C=0 cache hit (Bank 4 $A800 window populated);
//         C=1 miss (caller runs DFS path)
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1. The name pointer is compared in
// place (btc_name_lo/hi), not through zp_temp0/1: player_calc_hp keeps the
// hit dice in zp_temp0 across player_con_hp_adj, whose OVL.UI swap reloads
// the caller's overlay through here, and every BBC character had 135 max
// HP, the start overlay's name pointer's low byte ($87) (2026-11-16).
// ============================================================
beeb_overlay_try_cache:
    stx btc_name_lo + 1
    sty btc_name_hi + 1

    // Monster tiers are not cached (tier 1 outgrew its bank 6 slot when
    // 30 DL 1-5 creatures were added, 2026-10-25): all four load from DFS.
    ldx #hal_platform_overlay_count - 1
!find:
    lda hal_storage_overlay_name_lo,x
btc_name_lo:
    cmp #$00                // the name pointer's low byte (self-modified)
    bne !next+
    lda hal_storage_overlay_name_hi,x
btc_name_hi:
    cmp #$00                // ... and its high byte
    beq !found+
!next:
    dex
    bpl !find-
    sec
    rts

!found:
    cpx #3                  // GEN(3) may reuse DUNGEON_GEN_SCAN_SCRATCH_BASE ($3400-$37FF)
    bne !not_gen+
    jsr beeb_icat_inv_lynne
!not_gen:
    lda beeb_ovl_cache_bank,x
    bne !cached+
    sec
    rts

!cached:
    pha
    lda #$00
    sta zp_ptr0
    lda beeb_ovl_cache_hi,x
    sta zp_ptr0_hi
    lda #<BANKED_DATA_BASE
    sta zp_ptr1
    lda #>BANKED_DATA_BASE
    sta zp_ptr1_hi
    lda beeb_ovl_cache_pages,x
    tax
    pla
    jmp beeb_swr_copy_to_window

// ============================================================
// beeb_require_play — Validate the "M8P" play-slot signature in Bank 4 ($8000).
// Preloaded at boot by MORIA8P; panics if corrupted.
// ============================================================
beeb_require_play:
    php
    sei
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda BEEB_PLAY_SLOT_BASE
    cmp #$4d                // 'M'
    bne !fatal+
    lda BEEB_PLAY_SLOT_BASE + 1
    cmp #$38                // '8'
    bne !fatal+
    lda BEEB_PLAY_SLOT_BASE + 2
    cmp #$50                // 'P'
    bne !fatal+
    plp
    clc
    rts
!fatal:
    plp
    lda #HAL_STATUS_ERR_WRONG_MEDIA
    jmp hal_platform_panic
