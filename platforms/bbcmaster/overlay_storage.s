#importonce
// overlay_storage.s — BBC Master 128 Sideways RAM overlay/tier cache + play-slot check (< $3000).
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md & cache_layout.s.
// Six hot overlay classes (TOWN, GEN, UI, ITEMS, SPELL, MODAL) and Monster Tier 1
// (MONDB1) are preloaded into Sideways RAM Banks 5, 6, and 7 at boot by MORIA8P.
// Cache hits copy the payload pages via beeb_swr_copy_to_window into Bank 4's
// $A800-$BFFF window with zero disk I/O. Cold overlays (OVLSTA, OVLDTH, OVLHLP,
// OVLCHS, OVLSTO, OVLTTL) and MONDB2..4 fall through to DFS.

#import "hal/storage_policy.s"
#import "cache_layout.s"
#import "memory.s"

// ============================================================
// Sideways RAM Cache Lookup Tables (index = overlay ID - 1: 0..11)
// Order: START(0), TOWN(1), DEATH(2), GEN(3), HELP(4), UI(5),
//        ITEMS(6), SPELL(7), MODAL(8), CHEST(9), STORAGE(10), TITLE(11)
// ============================================================
beeb_ovl_cache_bank:
    .byte $00, BEEB_SWR_BANK_TOWN, $00, BEEB_SWR_BANK_GEN, $00, BEEB_SWR_BANK_UI
    .byte BEEB_SWR_BANK_ITEMS, BEEB_SWR_BANK_SPELL, BEEB_SWR_BANK_MODAL, $00, $00, $00

beeb_ovl_cache_hi:
    .byte $00, >BEEB_SWR_ADDR_TOWN, $00, >BEEB_SWR_ADDR_GEN, $00, >BEEB_SWR_ADDR_UI
    .byte >BEEB_SWR_ADDR_ITEMS, >BEEB_SWR_ADDR_SPELL, >BEEB_SWR_ADDR_MODAL, $00, $00, $00

beeb_ovl_cache_pages:
    .byte $00, BEEB_SWR_PAGES_TOWN, $00, BEEB_SWR_PAGES_GEN, $00, BEEB_SWR_PAGES_UI
    .byte BEEB_SWR_PAGES_ITEMS, BEEB_SWR_PAGES_SPELL, BEEB_SWR_PAGES_MODAL, $00, $00, $00

// ============================================================
// beeb_overlay_try_cache — Sideways RAM cache front end for overlays & MONDB1.
// Input:  X = filename pointer lo, Y = filename pointer hi
// Output: C=0 cache hit (Bank 4 $A800 window populated);
//         C=1 miss (caller runs DFS path)
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0, zp_temp1
// ============================================================
beeb_overlay_try_cache:
    stx zp_temp0
    sty zp_temp1

    // Check Monster Tier 1 (hal_storage_tier_1_name) first
    cpx #<hal_storage_tier_1_name
    bne !chk_ovl+
    cpy #>hal_storage_tier_1_name
    bne !chk_ovl+
    lda #$00
    sta zp_ptr0
    lda #>BEEB_SWR_ADDR_MON1
    sta zp_ptr0_hi
    lda #<BANKED_DATA_BASE
    sta zp_ptr1
    lda #>BANKED_DATA_BASE
    sta zp_ptr1_hi
    lda #BEEB_SWR_BANK_MON1
    ldx #BEEB_SWR_PAGES_MON1
    jmp beeb_swr_copy_to_window

!chk_ovl:
    ldx #hal_platform_overlay_count - 1
!find:
    lda hal_storage_overlay_name_lo,x
    cmp zp_temp0
    bne !next+
    lda hal_storage_overlay_name_hi,x
    cmp zp_temp1
    beq !found+
!next:
    dex
    bpl !find-
    sec
    rts

!found:
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
    clc
    rts
!fatal:
    lda #HAL_STATUS_ERR_WRONG_MEDIA
    jmp hal_platform_panic
