// overlay_storage.s — Apple IIe overlay aux cache + play-slot loader.
//
// 1. Aux overlay cache (docs/APPLE2_MEMORY_POLICY.md aux manifest, v7).
//    Six hot/runtime-critical classes are preloaded into aux RAM at boot;
//    hal_asset_load_prg_header (storage_mli.s) calls a2_overlay_try_cache
//    first for overlay-class filenames. Cache hit = AUXMOVE into the $A400
//    window (~ms). Cold classes (START, DEATH, HELP, STORAGE, TITLE)
//    always fall through to MLI.
//
// 2. Play-slot loader ($7C00-$9FFF). All 11 overlay classes fit the window,
//    so there is no runtime slot swap: a2_require_play loads the play payload
//    from disk once per session (boot or first N/L title action) and
//    validates the 3-byte signature main.s emits at the slot base. The play
//    payload is pure code + rodata; all state lives in resident BSS/ZP.

#import "hal/storage_policy.s"
#import "cache_layout.s"

// ============================================================
// Aux cache manifest v7 (page-aligned slots sized to current overlays;
// the boot loader copies exact byte lengths from the pak header, so a
// slot only needs the payload rounded up to a page). Six classes
// are cached; DEATH, HELP, and STORAGE are cold (disk loads on rare
// flows) because the current overlay set no longer fits the region.
// Layout: auxdata $3B0C-$4FDA, unused slack $4FDB-$56FF, overlay cache
// payloads $5700-$BFFF.
// Cache hits read a full $1600-byte window; ITEMS is deliberately last at
// $AA00 so the final full-window read ends exactly at $C000. Bytes after a
// payload are irrelevant because no overlay can execute beyond its end.
// Slot addresses must match boot.s file_table.
// ============================================================

// Cache slot lookup, parallel to the hal_storage_overlay_name_* tables
// (index = overlay ID - 1; START=1 .. TITLE=11). $0000 = cold (not cached).
a2_ovl_cache_lo:
    .byte $00, <A2_AUX_CACHE_TOWN, $00, <A2_AUX_CACHE_GEN, $00, <A2_AUX_CACHE_UI, <A2_AUX_CACHE_ITEMS, <A2_AUX_CACHE_SPELL, <A2_AUX_CACHE_MODAL, $00, $00
a2_ovl_cache_hi:
    .byte $00, >A2_AUX_CACHE_TOWN, $00, >A2_AUX_CACHE_GEN, $00, >A2_AUX_CACHE_UI, >A2_AUX_CACHE_ITEMS, >A2_AUX_CACHE_SPELL, >A2_AUX_CACHE_MODAL, $00, $00

// ============================================================
// a2_overlay_try_cache — Aux-cache front end for overlay loads.
// Input:  X = filename pointer lo, Y = filename pointer hi (a table entry in
//         hal_storage_overlay_name_lo/hi)
// Output: C=0 cache hit (window populated, nothing more to do);
//         C=1 miss (caller runs the MLI path)
// Clobbers: A, X, Y, zp_ptr0/zp_ptr1/zp_temp0/zp_temp1
// ============================================================
a2_overlay_try_cache:
    stx zp_temp0
    sty zp_temp1
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
    sec                     // not an overlay-class filename -> MLI
    rts
!found:
    lda a2_ovl_cache_hi,x   // cold class?
    bne !cached+
    sec
    rts
!cached:
#if A2_DEBUG_CACHELOG
    stx $2000               // matched overlay index
    sta $2001               // cache slot hi
#endif
    sta zp_ptr0_hi          // source = aux cache slot
    lda a2_ovl_cache_lo,x
    sta zp_ptr0
    lda #<BANKED_DATA_BASE  // dest = window $A400
    sta zp_ptr1
    lda #>BANKED_DATA_BASE
    sta zp_ptr1_hi
    lda #$00                // count = 5,632 window code region (page-rounded
    sta zp_temp0            // slots are contiguous; slack bytes beyond the
    lda #$16                // payload are never referenced by the overlay)
    sta zp_temp1
    clc                     // aux -> main (AUXMOVE direction: CLC = aux to
                            // main, SEC = main to aux — verified against the
                            // $C376 firmware and traces; do NOT route this
                            // through a Kick #if on a .const, which tests
                            // definedness and silently picks the #else arm)
    jsr a2_auxmove
    clc
    rts

// ============================================================
// a2_require_play — Ensure the play payload is resident in the slot.
// Load-once semantics: after the first successful load the slot is never
// touched again. Output: C=0 resident and signature-valid; on unrecoverable
// failure does not return (panics).
// ============================================================
a2_require_play:
    jsr a2_play_signature_ok
    bcs !load+
    clc
    rts
!load:
    jsr a2_load_file_to_slot
    bcs !fatal+
    jsr a2_play_signature_ok
    bcs !fatal+
    clc
    rts
!fatal:
    lda #HAL_STATUS_ERR_WRONG_MEDIA
    jmp hal_platform_panic

a2_play_signature_ok:
    lda A2_PLAY_SLOT_BASE
    cmp #$4d                // 'M'
    bne !bad+
    lda A2_PLAY_SLOT_BASE + 1
    cmp #$38                // '8'
    bne !bad+
    lda A2_PLAY_SLOT_BASE + 2
    cmp #$50                // 'P'
    bne !bad+
    clc
    rts
!bad:
    sec
    rts

// a2_load_file_to_slot — MLI-load A2.PLAY into the slot; the file's BIN
// auxtype ($7C00, from the segmentdef) drives the destination.
a2_load_file_to_slot:
    lda #a2_play_file_name_len
    ldx #<a2_play_file_name
    ldy #>a2_play_file_name
    jmp hal_asset_load_prg_header

a2_play_file_name:
    .text "A2.PLAY"
.label a2_play_file_name_len = * - a2_play_file_name
    .byte 0
