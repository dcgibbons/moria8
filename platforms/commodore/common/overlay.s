#importonce
// overlay.s — Phase overlay loading for $E000 region
//
// Module ownership:
//   owner: Resident main/common across Commodore and non-Commodore ports
//     importing it; C64 unit tests link with hal_storage_overlay_test_stub.s.
//   lifetime: permanent resident overlay loader and current_overlay tracker.
//   callers: resident trampolines (`tramp_*`), `c128_preload_all_overlays`,
//     disk/title startup loaders.
//
// Manages code overlays at $E000-$EFFF for different game phases.
// Coexists with creature tier system which also uses $E000.
// When an overlay loads, tier data is invalidated (and vice versa).
//
// Overlay IDs:
//   OVL_NONE        = 0  No overlay (tier data or empty)
//   OVL_STARTUP     = 1  Title screen + character creation
//   OVL_TOWN        = 2  Stores
//   OVL_DEATH       = 3  Score + high scores
//   OVL_DUNGEON_GEN = 4  Town + dungeon generation
//   OVL_HELP        = 5  Dedicated help screen overlay
//   OVL_UI          = 6  Inventory/equipment/character/wizard modal UI
//   OVL_ITEMS       = 7  Low-frequency item actions (read/aim/use/refuel)
//   OVL_SPELL       = 8  Spell/prayer effect execution
//   OVL_MODAL_MISC  = 9  Modal misc: winner retirement / save-slot selector
//   OVL_CHEST       = 10 Chest interactions (open/disarm/bash); cold everywhere
//                        (C128: never staged into the Bank 1 overlay cache)
//   OVL_HOME        = 11 Dedicated Player Home overlay (Phase 2 cold eviction)
//   OVL_STORAGE     = 12 Save/load engine overlay (Phase 2 cold eviction)
//   OVL_TITLE       = 13 Title screen overlay (Phase 2 cold eviction)
//   (Ports setting HAL_PLATFORM_MAP_GET_TILE_USES_SUBROUTINE define legacy
//    11=OVL_STORAGE, 12=OVL_TITLE directly in their main.s.)
//
// Disk filenames are platform-owned by the storage HAL:
// `hal_storage_overlay_name_{lo,hi,len}`.
// REU: stashed alongside creature tiers at startup

// ============================================================
// Constants
// ============================================================
.const OVL_NONE        = 0
.const OVL_STARTUP     = 1
.const OVL_TOWN        = 2
.const OVL_DEATH       = 3
.const OVL_DUNGEON_GEN = 4
.const OVL_HELP        = 5
.const OVL_UI          = 6
.const OVL_ITEMS       = 7
.const OVL_SPELL       = 8
.const OVL_MODAL_MISC  = 9
.const OVL_CHEST       = 10
#if !HAL_PLATFORM_MAP_GET_TILE_USES_SUBROUTINE
.const OVL_HOME        = 11
.const OVL_STORAGE     = 12
.const OVL_TITLE       = 13
#endif
.const OVL_COUNT       = hal_platform_overlay_count

#import "compat/hal_storage_overlay_test_stub.s"

// ============================================================
// State
// ============================================================
#if HAL_PLATFORM_OVERLAY_STATE_LOCAL
current_overlay: .byte 0
#endif

// ============================================================
// overlay_load — Load a phase overlay to $E000
// ============================================================
// Input: A = overlay ID
// Invalidates creature tier state (tier data overwritten).
// Output: carry clear = success, carry set = error (disk only)
// Clobbers: A, X, Y
overlay_load:
#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED && C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_entry_req
#endif
#if C128_TEST_OVERLAY_FN_GUARD
    pha
    lda #$b1
    jsr c128_overlay_fn_guard_check
    pla
#endif
#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED
    // C128 overlay transitions are cache-backed and cheap. Always resolve the
    // requested overlay instead of trusting current_overlay, because stale
    // overlay-state bytes can otherwise skip the load and execute whatever
    // old image still occupies $E000.
    sta ol_target
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_entry_target
#endif
#elif HAL_PLATFORM_OVERLAY_FORCE_RELOAD
    // Kept for ports that share $E000 between overlays, tier staging, and
    // KERNAL-loaded assets without a stronger ownership guard: prefer a fresh
    // disk reload over trusting stale overlay state.
    sta ol_target
#else
    cmp current_overlay
    beq !ol_skip+           // Already loaded — skip
    sta ol_target
#endif

    // C64 active tier names are copied to hidden RAM at activation time, so an
    // overlay load no longer invalidates the logical tier. C128 keeps the
    // existing cache-backed guard because its tier pointers may resolve through
    // Bank 1 overlay/tier ownership. The monster catalog has no tiers.
#if HAL_PLATFORM_OVERLAY_TIER_CACHE_GUARD && !HAL_PLATFORM_MONSTER_CATALOG
    lda current_tier
    beq !ol_invalidate_tier+
    tax
    lda c128_cache_tiers_ready
    beq !ol_invalidate_tier+
    lda c128_tier_ready_mask_minus1,x
    and c128_cache_tier_bits
    bne !ol_keep_tier_state+
!ol_invalidate_tier:
    jsr tier_invalidate_state
!ol_keep_tier_state:
#endif

#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED
    // C128 preloads all overlays, including the Disk Setup/help UI, into the
    // Bank 1 overlay cache at boot. Title-time Disk Setup must use that cache
    // so one-drive users can swap program media out of drive 8 before pressing L.
    lda c128_cache_overlays_ready
    beq ol_check_disk
    ldx ol_target
    lda ovl_ready_mask,x
    and c128_cache_overlay_bits
    bne !ol_cached+
    lda ovl_ready_mask_hi,x
    and c128_cache_overlay_bits_hi
    beq ol_check_disk
!ol_cached:
    jsr c128_fetch_overlay_from_cache
    bcc !ol_cache_ok+
    lda #0
    sta c128_cache_overlays_ready
    sta c128_cache_overlay_bits
    sta c128_cache_overlay_bits_hi
    sta c128_cache_failed
ol_check_disk:
#elif HAL_PLATFORM_OVERLAY_REU_STASH_ENABLED
!ol_check_reu:
    lda reu_overlays_stashed
    bne !ol_reu+
ol_check_disk:
#endif

    // --- Disk path: KERNAL LOAD overlay PRG ---
#if HAL_PLATFORM_OVERLAY_PROMPT_PROGRAM_MEDIA && OVERLAY_LOAD_PROMPT_GAME
#if HAL_PLATFORM_OVERLAY_PROMPT_GAME_REQUIRED
    jsr disk_prompt_game_required
#else
    jsr disk_prompt_game
#endif
#endif
#if C128_CACHE_TEST_SKIP_OVERLAY
    lda ol_target
    cmp c128_cache_test_skip_overlay
    bne !ol_partial_state_done+
    jsr c128_test_validate_overlay_partial_state
    bcc !ol_partial_state_done+
    jmp c128_test_overlay_cache_fail_sym
!ol_partial_state_done:
#endif
    ldx ol_target
    dex                     // 0-based index (OVL_STARTUP=1 → index 0)
    jsr overlay_load_disk
#if C64_UNIT_TEST
    bcs !ol_disk_fail+          // only unit tests see a load fail (asset_load_retry.s)
#endif
    lda ol_target
    sta current_overlay
    rts
#if C64_UNIT_TEST
!ol_disk_fail:
    lda #OVL_NONE
    sta current_overlay
    rts
#endif

#if HAL_PLATFORM_OVERLAY_REU_STASH_ENABLED
!ol_reu:
    // --- REU path: DMA overlay from REU to $E000 ---
    ldx ol_target
    jsr overlay_fetch_reu
    lda ol_target
    sta current_overlay
    clc                     // REU always succeeds
    rts
#endif

#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED
!ol_cache_ok:
    lda ol_target
    sta current_overlay
    clc
    rts
#endif

#if HAL_PLATFORM_OVERLAY_SKIP_IF_CURRENT
!ol_skip:
    clc
    rts
#endif


// ============================================================
// overlay_invalidate — Mark overlay as unloaded
// ============================================================
// Called by tier_load when creature tier data overwrites $E000.
overlay_invalidate:
    lda #OVL_NONE
    sta current_overlay
    rts

#if C128_TEST_OVERLAY_FN_GUARD
c128_overlay_fn_guard_check:
    pha
    txa
    pha
    sta c128_overlay_fn_guard_stage
    ldx #0
!fn_loop:
    lda ovl_fn_guard_expected,x
    cmp hal_storage_overlay_start_name,x
    beq !next+
    sta c128_overlay_fn_guard_expect
    stx c128_overlay_fn_guard_index
    lda hal_storage_overlay_start_name,x
    sta c128_overlay_fn_guard_actual
    brk
!next:
    inx
    cpx #ovl_fn_guard_expected_end - ovl_fn_guard_expected
    bne !fn_loop-
    pla
    tax
    pla
    rts

ovl_fn_guard_expected:
#if HAL_PLATFORM_OVERLAY_FN_GUARD_CACHE_NAMES
    .byte $31,$32,$38,$2e,$53,$54,$41,$52,$54,$00
    .byte $31,$32,$38,$2e,$54,$4f,$57,$4e,$00
    .byte $31,$32,$38,$2e,$44,$45,$41,$54,$48,$00
    .byte $31,$32,$38,$2e,$47,$45,$4e,$00
    .byte $31,$32,$38,$2e,$48,$45,$4c,$50,$00
    .byte $31,$32,$38,$2e,$55,$49,$00
    .byte $31,$32,$38,$2e,$49,$54,$45,$4d,$53,$00
#else
    .byte $36,$34,$2e,$53,$54,$41,$52,$54,$00
    .byte $36,$34,$2e,$54,$4f,$57,$4e,$00
    .byte $36,$34,$2e,$44,$45,$41,$54,$48,$00
    .byte $36,$34,$2e,$47,$45,$4e,$00
    .byte $36,$34,$2e,$48,$45,$4c,$50,$00
    .byte $36,$34,$2e,$55,$49,$00
    .byte $36,$34,$2e,$49,$54,$45,$4d,$53,$00
#endif
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len
ovl_fn_guard_expected_end:
#if HAL_PLATFORM_OVERLAY_FN_GUARD_LEGACY_NAMES
c128_overlay_fn_guard_stage:   .byte 0
c128_overlay_fn_guard_index:   .byte 0
c128_overlay_fn_guard_actual:  .byte 0
c128_overlay_fn_guard_expect:  .byte 0
#endif
#endif


// ============================================================
// overlay_load_disk — KERNAL LOAD overlay PRG file
// ============================================================
// Input: X = 0-based overlay index (0=startup, 1=town, 2=death)
// Output: C = 0: a file that will not load asks for the program disk until
// it does (asset_load_required; C64 unit-test builds fail back with C = 1)
// Clobbers: A, X, Y
overlay_load_disk:
#if C128_TEST_OVERLAY_FN_GUARD
    lda #$b2
    jsr c128_overlay_fn_guard_check
#endif
#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED
    // C128: delegate to hal_asset_load_prg_header which handles the full
    // KERNAL environment setup (SETBNK Bank 0, ROM banking, IRQ enable,
    // SETNAM/SETLFS/LOAD/CLOSE/CLRCHN, and runtime restore).
    // Without proper SETBNK, KERNAL LOAD puts data in the wrong bank.
    //
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    stx c128_overlay_load_disk_index
    lda ol_target
    sta c128_overlay_load_disk_target
#endif
    lda hal_storage_overlay_name_len,x
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_disk_len
#endif
    pha
    lda hal_storage_overlay_name_lo,x
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_disk_lo
#endif
    pha
    lda hal_storage_overlay_name_hi,x
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_disk_hi
#endif
    tay
    pla
    tax
    pla
    jmp asset_load_required
#else
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    stx c128_overlay_load_disk_index
    lda ol_target
    sta c128_overlay_load_disk_target
#endif
    lda hal_storage_overlay_name_len,x
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_disk_len
#endif
    pha
    lda hal_storage_overlay_name_lo,x
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_disk_lo
#endif
    pha
    lda hal_storage_overlay_name_hi,x
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_overlay_load_disk_hi
#endif
    tay
    pla
    tax
    pla
    jmp asset_load_required
#endif

#import "asset_load_retry.s"


#if HAL_PLATFORM_OVERLAY_REU_STASH_ENABLED
// ============================================================
// overlay_fetch_reu — DMA overlay from REU to $E000
// ============================================================
// Input: X = overlay ID (1-3)
// Fetches overlay from REU memory to $E000 in C64 RAM.
// Clobbers: A, X
overlay_fetch_reu:
    php
    sei
#if HAL_PLATFORM_OVERLAY_CPU_PORT_DMA_BANK
    lda hal_memory_cpu_port
    pha
    lda #$35                // Bank out KERNAL for DMA to write RAM at $E000
    sta hal_memory_cpu_port
#endif

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI

    lda ovl_reu_start_lo,x
    sta REU_REULO
    lda ovl_reu_start_hi,x
    sta REU_REUHI
#if HAL_PLATFORM_OVERLAY_REU_BANK1_TITLE
    cpx #OVL_TITLE
    bcc !ofr_b0+
    lda #1
    .byte $2c
!ofr_b0:
    lda #0
#else
    lda #0
#endif
    sta REU_BANK

    lda #0
    sta REU_LENLO
    lda #$10
    sta REU_LENHI
    lda #0
    sta REU_CONTROL
    lda #REU_CMD_FETCH
    sta REU_COMMAND         // DMA completes before next instruction

#if HAL_PLATFORM_OVERLAY_CPU_PORT_DMA_BANK
    pla
    sta hal_memory_cpu_port
#endif
    plp
    rts
#endif

#if HAL_PLATFORM_OVERLAY_STATE_LOCAL

// ============================================================
// REU overlay offset tables (populated by reu_stash_overlays)
// ============================================================
// Index 0 unused; indices 1-OVL_COUNT = overlay IDs
ovl_reu_start_lo: .fill OVL_COUNT + 1, 0
ovl_reu_start_hi: .fill OVL_COUNT + 1, 0
ol_target:        .byte 0
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
c128_overlay_load_disk_index:  .byte 0
c128_overlay_load_disk_target: .byte 0
c128_overlay_load_disk_len:    .byte 0
c128_overlay_load_disk_lo:     .byte 0
c128_overlay_load_disk_hi:     .byte 0
#endif
#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED
ol_status_p:      .byte 0
#endif
#endif

#if HAL_PLATFORM_OVERLAY_CACHE_ENABLED
c128_preload_all_overlays:
    lda #0
    sta c128_cache_overlays_ready
    sta c128_cache_overlay_bits
    sta c128_cache_overlay_bits_hi

    ldx #1
!cpao_loop:
    stx ol_target

#if HAL_PLATFORM_OVERLAY_CACHE_EXTENDED_256K
    // 256KB C128 caches all 12 overlays when Bank 2 PLAY is healthy (IDs 1 &
    // 10-12 in Bank 2, 2-9 in Bank 1). If Bank 2 PLAY verification failed,
    // skip Bank 2 overlays cleanly and keep all Bank 1 hot overlays cached.
    lda c128_bank2_flags
    and #C128_BANK2_PLAY_BIT
    bne !cpao_keep+
#endif
    // The chest overlay is cold on 128KB C128 (docs/CHEST_DESIGN.md): no Bank 1
    // cache slot exists for it, so boot preload must not stage it. Its
    // ready-mask bits stay clear and overlay_load falls through to disk.
    cpx #OVL_CHEST
    beq cpao_next
#if !HAL_PLATFORM_MAP_GET_TILE_USES_SUBROUTINE
    // Phase 2 cold overlays have no Bank 1 cache slot either; load on demand.
    cpx #OVL_MODAL_MISC
    beq cpao_next
    cpx #OVL_HOME
    beq cpao_next
    cpx #OVL_STORAGE
    beq cpao_next
#endif
#if HAL_PLATFORM_MONSTER_CATALOG
    // STARTUP is not cached in Bank 1 either: its slot holds the monster
    // catalog's names (memory128.s, C128M-007). New Game loads it from disk.
    cpx #OVL_STARTUP
    beq cpao_next
#endif
!cpao_keep:

#if C128_CACHE_TEST_SKIP_OVERLAY
    txa
    cmp c128_cache_test_skip_overlay
    bne !cpao_show_file+
    jmp cpao_next
!cpao_show_file:
#endif

    dex
    lda reu_fn_ovl_lo,x
    sta zp_ptr0
    lda reu_fn_ovl_hi,x
    sta zp_ptr0_hi
    jsr reu_show_file

    ldx ol_target
    dex
    lda hal_storage_overlay_name_len,x
    pha
    lda hal_storage_overlay_name_lo,x
    pha
    lda hal_storage_overlay_name_hi,x
    tay
    pla
    tax
    pla
    jsr asset_load_retry
    bcs !cpao_check_b2_fail+

    ldx ol_target
    jsr c128_stage_overlay_to_cache
    bcc !cpao_mark_ready+
!cpao_check_b2_fail:
#if HAL_PLATFORM_OVERLAY_CACHE_EXTENDED_256K
    ldx ol_target
    lda bank_overlay_cache_mmu,x
    cmp #MMU_RAM_BANK2
    bne !cpao_fail+
    beq cpao_next
#else
    jmp !cpao_fail+
#endif
!cpao_mark_ready:

    ldx ol_target
    lda ovl_ready_mask,x
    ora c128_cache_overlay_bits
    sta c128_cache_overlay_bits
    lda ovl_ready_mask_hi,x
    ora c128_cache_overlay_bits_hi
    sta c128_cache_overlay_bits_hi

cpao_next:
    ldx ol_target
    inx
    cpx #(OVL_COUNT + 1)
    bne !cpao_loop-

    lda #1
    sta c128_cache_overlays_ready
#if HAL_PLATFORM_MONSTER_CATALOG
    // The window holds the last overlay staged, not a loaded one.
    lda #OVL_NONE
    sta current_overlay
    rts
#endif
    // Leave the startup overlay resident at $E000 for the title -> New Game
    // path. This avoids an immediate redundant reload of OVL.START after
    // preload has already cached and validated it.
    lda #OVL_STARTUP
    sta ol_target
    jsr c128_fetch_overlay_from_cache
    bcs !cpao_fail+
    lda #OVL_STARTUP
    sta current_overlay
#if C128_TEST_OVERLAY_FN_GUARD
    lda #$b3
    jsr c128_overlay_fn_guard_check
#endif
    // No end-of-operation validate here: the preload asset-load helper
    // already validates internally, and the diag world payload is 4 bytes
    // from the items-payload boundary.
    rts

!cpao_fail:
    lda #0
    sta c128_cache_overlays_ready
    sta c128_cache_overlay_bits
    sta c128_cache_overlay_bits_hi
    sta c128_cache_failed
    lda #OVL_NONE
    sta current_overlay
    rts

c128_select_overlay_cache_slot:
    lda bank1_overlay_cache_slot_lo,x
    sta ovl_cache_base_lo
    lda bank1_overlay_cache_slot_hi,x
    sta ovl_cache_base_hi
    lda bank1_overlay_cache_pages,x
    sta ovl_cache_pages
    lda bank_overlay_cache_mmu,x
    sta c128_xbank_cr
    rts

c128_setup_overlay_xbank_ptrs:
    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    lda ovl_cache_base_lo
    sta zp_ptr1
    lda ovl_cache_base_hi
    sta zp_ptr1_hi
    lda ovl_cache_pages
    sta zp_temp1
    rts

#if HAL_PLATFORM_OVERLAY_CACHE_EXTENDED_256K
// Copy zp_temp1 (>=1) pages between Bank 0 zp_ptr0 and c128_xbank_cr zp_ptr1 (29 cyc/B).
// Preserves caller IRQ state. Clobbers A, X, Y, zp_ptr0_hi, zp_ptr1_hi, zp_temp1, zp_temp2.
c128_copy_to_xbank:
    sec
    .byte $24                   // BIT zp — skips clc
c128_copy_from_xbank:
    clc
    php
    sei
    ldy #0
    ldx c128_xbank_cr
    stx zp_temp2
!cx_page:
    bcs !cx_write+
    jsr mmu_common_xbank_read_page
    bcc !cx_next+               // mmu_common_xbank_read_page preserves C=0
!cx_write:
    jsr mmu_common_xbank_write_page
!cx_next:
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    bne !cx_page-
    plp
    clc
    rts
#else
// Copy zp_temp1 (>=1) pages from Bank 0 zp_ptr0 into c128_xbank_cr zp_ptr1.
// Preserves caller IRQ state. Clobbers A, X, Y, zp_ptr0_hi, zp_ptr1_hi, zp_temp1.
c128_copy_to_xbank:
    php
    sei
    ldy #0
    ldx c128_xbank_cr
!cxw_byte:
    lda (zp_ptr0),y
    jsr mmu_common_bank_write_ptr1
    iny
    bne !cxw_byte-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    bne !cxw_byte-
    plp
    clc
    rts

// Copy zp_temp1 (>=1) pages from c128_xbank_cr zp_ptr1 into Bank 0 zp_ptr0.
// Preserves caller IRQ state. Clobbers A, X, Y, zp_ptr0_hi, zp_ptr1_hi, zp_temp1.
c128_copy_from_xbank:
    php
    sei
    ldy #0
!cxr_byte:
    lda c128_xbank_cr
    jsr mmu_common_bank_read_ptr1
    sta (zp_ptr0),y
    iny
    bne !cxr_byte-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    bne !cxr_byte-
    plp
    clc
    rts
#endif

// Verify zp_temp1 (>=1) pages between Bank 0 zp_ptr0 and c128_xbank_cr zp_ptr1.
// Output: carry clear = match, carry set = mismatch.
c128_verify_xbank:
    php
    sei
    ldy #0
!cxv_byte:
    lda c128_xbank_cr
    jsr mmu_common_bank_read_ptr1
    cmp (zp_ptr0),y
    bne !cxv_fail+
    iny
    bne !cxv_byte-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    bne !cxv_byte-
    plp
    clc
    rts
!cxv_fail:
    plp
    sec
    rts

c128_stage_overlay_to_cache:
    jsr c128_select_overlay_cache_slot
    jsr c128_setup_overlay_xbank_ptrs
    jsr c128_copy_to_xbank
c128_verify_overlay_cache_slot:
    jsr c128_setup_overlay_xbank_ptrs
    jmp c128_verify_xbank

c128_fetch_overlay_from_cache:
    ldx ol_target
    jsr c128_select_overlay_cache_slot
    jsr c128_setup_overlay_xbank_ptrs
    jmp c128_copy_from_xbank
#endif
