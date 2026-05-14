#importonce
#import "generation_busy_api.s"
#import "hal_storage_tier_test_stub.s"
// tier_manager.s — Creature tier loading and transition management
//
// Manages the active creature tier. Detects tier boundaries on stair
// transitions and loads new tier data from disk or REU.
//
// Tier data is stored as standalone PRG files on the d64 disk.
// Files load to $E000 (RAM under KERNAL ROM). After loading, the
// SoA arrays are copied into the active creature buffer via
// load_tier_to_buffer. C64 copies active tier names into hidden RAM under
// I/O so gameplay no longer depends on the $E000 staging window; C128 keeps
// names in its Bank 1 tier cache.
//
// Tier ranges (overlapping for hysteresis):
//   Tier 1: DL 1-8    (24 creatures)
//   Tier 2: DL 5-15   (32 creatures)
//   Tier 3: DL 11-25  (39 creatures)
//   Tier 4: DL 20-100 (57 creatures)
//
// Exports:
//   tier_init              — Startup preload/init for REU or C128 tier cache
//   tier_check_transition  — Call after dlvl change; loads new tier if needed

#import "creature_data/creature_tiers.s"

// ============================================================
// State variables
// ============================================================
current_tier:   .byte 0     // 0 = no tier (town/embedded), 1-4 = active tier
tier_loaded:    .byte 0     // 1 = a tier has been loaded from disk/REU
tier_silent_restore: .byte 0    // 1 = suppress transient "Loading..." during overlay restore
// C128 tier cache metadata: active tier payload mirrored into the named Bank 1
// tier-cache ownership window from memory128.s.
c128_tier_cache_base_lo: .byte 0
c128_tier_cache_base_hi: .byte 0
c128_tier_cache_size_lo: .byte 0
c128_tier_cache_size_hi: .byte 0
c128_tier_soa_end_lo: .byte 0
c128_tier_soa_end_hi: .byte 0
#if !C128
platform_tier_name_src_lo: .byte 0
platform_tier_name_src_hi: .byte 0
#endif

// tier_invalidate_state — Clear active tier state + derived metadata
// Safe to call from any module before loading an overlay/string bank.
// Clobbers: A
tier_invalidate_state:
    lda #0
    sta current_tier
    sta tier_loaded
    sta tier_silent_restore
    sta c128_tier_cache_size_lo
    sta c128_tier_cache_size_hi
#if C128
    sta tier_name_lo_addr
    sta tier_name_lo_addr+1
    sta tier_name_hi_addr
    sta tier_name_hi_addr+1
#endif
#if !C128
    sta platform_tier_name_src_lo
    sta platform_tier_name_src_hi
#endif
    rts

// ============================================================
// Tier boundary tables (indexed by tier 1-4; index 0 unused)
// ============================================================
tier_min_dlvl:
    .byte 0                         // [0] unused
    .byte TIER1_MIN_DLVL            // [1] = 1
    .byte TIER2_MIN_DLVL            // [2] = 5
    .byte TIER3_MIN_DLVL            // [3] = 11
    .byte TIER4_MIN_DLVL            // [4] = 20

tier_max_dlvl:
    .byte 0                         // [0] unused
    .byte TIER1_MAX_DLVL            // [1] = 8
    .byte TIER2_MAX_DLVL            // [2] = 15
    .byte TIER3_MAX_DLVL            // [3] = 25
    .byte TIER4_MAX_DLVL            // [4] = 100

tier_count_table:
    .byte 0                         // [0] unused
    .byte TIER1_COUNT               // [1] = 24
    .byte TIER2_COUNT               // [2] = 32
    .byte TIER3_COUNT               // [3] = 39
    .byte TIER4_COUNT               // [4] = 57

// Tier data sizes (for REU stash/fetch and C128 cache slots)
tier_size_lo:
    .byte 0
    .byte <TIER1_SIZE, <TIER2_SIZE, <TIER3_SIZE, <TIER4_SIZE
tier_size_hi:
    .byte 0
    .byte >TIER1_SIZE, >TIER2_SIZE, >TIER3_SIZE, >TIER4_SIZE

#if C128
.const C128_TIER1_CACHE_BASE = BANK1_TIER_CACHE_BASE
.const C128_TIER2_CACHE_BASE = C128_TIER1_CACHE_BASE + TIER1_SIZE
.const C128_TIER3_CACHE_BASE = C128_TIER2_CACHE_BASE + TIER2_SIZE
.const C128_TIER4_CACHE_BASE = C128_TIER3_CACHE_BASE + TIER3_SIZE
.const C128_TIER_CACHE_END   = C128_TIER4_CACHE_BASE + TIER4_SIZE - 1

c128_tier_cache_slot_lo:
    .byte 0
    .byte <C128_TIER1_CACHE_BASE, <C128_TIER2_CACHE_BASE, <C128_TIER3_CACHE_BASE, <C128_TIER4_CACHE_BASE
c128_tier_cache_slot_hi:
    .byte 0
    .byte >C128_TIER1_CACHE_BASE, >C128_TIER2_CACHE_BASE, >C128_TIER3_CACHE_BASE, >C128_TIER4_CACHE_BASE

.assert "Tier cache stays inside named Bank1 tier-cache window", C128_TIER_CACHE_END <= BANK1_TIER_CACHE_END, true
#endif


// ============================================================
// tier_init — Initialize tier system at startup
// ============================================================
// C128: preload all monster tiers into the named Bank 1 tier-cache window.
// C64/REU: load all tier files into REU for instant DMA on tier transitions.
// No tier is activated yet (player starts in town).
// Without cache/REU: nothing to do now; tiers load on demand.
// Clobbers: A, X, Y, zp_ptr0, zp_temp0, zp_temp1
tier_init:
    jsr tier_invalidate_state

#if C128
    lda #0
    sta c128_cache_tiers_ready
    sta c128_cache_overlays_ready
    sta c128_cache_failed
    sta c128_cache_tier_bits
    sta c128_cache_overlay_bits

    lda c128_cache_enabled
    beq !ti_done+

    lda #1
    sta zp_screen_editor_state  // Suppress cursor blink during loading
    lda #COL_LGREY
    sta zp_text_color
    jsr screen_clear
    lda #1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<c128_cache_loading_hdr
    sta zp_ptr0
    lda #>c128_cache_loading_hdr
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #4
    sta reu_loading_row
    jsr c128_preload_all_tiers
    jsr c128_preload_all_overlays
#if C128_TEST_CACHE_SURVIVAL
    jsr c128_test_snapshot_cache_probes
#endif
    rts
#endif

    lda reu_present
    beq !ti_done+

    // Clear screen and show loading progress
    lda #1
    sta zp_screen_editor_state  // Suppress cursor blink during loading
    lda #COL_LGREY
    sta zp_text_color
    jsr screen_clear
    lda #1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<reu_loading_hdr
    sta zp_ptr0
    lda #>reu_loading_hdr
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr reu_show_status         // Show initial "0/XXXKB"
    lda #4
    sta reu_loading_row

    // REU present: load all 4 tier files from disk into REU
    jsr reu_load_all_tiers
    jsr reu_stash_overlays

    // Clean up KERNAL file table — LOAD's internal close is unreliable
    // across multiple calls. Stale file #2 entry would cause load_game's
    // OPEN to fail with "FILE ALREADY OPEN".
    lda #2
    jsr $ffc3               // KERNAL CLOSE — release file #2
    jsr $ffcc               // KERNAL CLRCHN — restore default I/O

!ti_done:
    rts


// ============================================================
// tier_check_transition — Check if a tier change is needed
// ============================================================
// Call after zp_player_dlvl has been updated (stair handlers).
// If the new dlvl falls outside the current tier's range,
// loads the appropriate tier.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0, zp_temp1
tier_check_transition:
    lda zp_player_dlvl
    beq !tct_done+              // Town = no tier needed

    ldx current_tier
    beq !tct_first_entry+       // No tier loaded yet

    // Check: is dlvl within current tier's [min, max]?
    cmp tier_max_dlvl,x
    beq !tct_done+              // dlvl == max → in range
    bcs !tct_need_next+         // dlvl > max → need next tier

    cmp tier_min_dlvl,x
    bcc !tct_need_prev+         // dlvl < min → need previous tier

!tct_done:
    rts

!tct_need_next:
    inx
    cpx #5                      // Already at tier 4?
    bcs !tct_done-              // Yes → stay (tier 4 covers all deep levels)
    stx current_tier
    jsr tier_load
    rts

!tct_need_prev:
    dex
    beq !tct_done-              // Can't go below tier 1
    stx current_tier
    jsr tier_load
    rts

!tct_first_entry:
    // Determine initial tier from dungeon level
    lda zp_player_dlvl
    cmp #9
    bcc !tct_set1+
    cmp #16
    bcc !tct_set2+
    cmp #26
    bcc !tct_set3+
    lda #4
    jmp !tct_do_load+
!tct_set3:
    lda #3
    jmp !tct_do_load+
!tct_set2:
    lda #2
    jmp !tct_do_load+
!tct_set1:
    lda #1
!tct_do_load:
    sta current_tier
    jsr tier_load
    rts

// tier_restore_after_overlay — re-establish current tier data after an overlay
// or modal UI action without surfacing the transient "Loading..." message.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0, zp_temp1
tier_restore_after_overlay:
    lda #1
    sta tier_silent_restore
    jsr tier_check_transition
    lda #0
    sta tier_silent_restore
    rts

// ============================================================
// tier_load — Load a specific tier into the active creature buffer
// ============================================================
// Input: current_tier = tier number (1-4)
// Uses C128 tier cache, REU (DMA), or KERNAL LOAD from disk.
// After loading, SoA arrays are copied to the active buffer.
// Name strings remain at $E000+ (accessed via creature_get_name).
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0, zp_temp1
tier_load:
    // Invalidate overlay — tier data will overwrite $E000
    jsr overlay_invalidate

    // Show loading message only when we are not already presenting the
    // full-screen generation busy UI.
    lda generation_busy_active_api
    bne !tl_skip_loading_msg+
    lda tier_silent_restore
    bne !tl_skip_loading_msg+
    lda #<tier_loading_str
    sta zp_ptr0
    lda #>tier_loading_str
    sta zp_ptr0_hi
    jsr msg_print
!tl_skip_loading_msg:

#if C128
    lda c128_cache_tiers_ready
    beq !tl_check_reu+
    ldx current_tier
    lda c128_tier_ready_mask_minus1,x
    and c128_cache_tier_bits
    beq !tl_check_reu+
    jsr c128_fetch_tier_from_cache
    bcc !tl_cache_ok+
    lda #0
    sta c128_cache_tiers_ready
    sta c128_cache_failed
!tl_check_reu:
#endif
    lda reu_present
    bne !tl_reu+

    // --- Disk path: KERNAL LOAD tier file to $E000 ---
#if C128_CACHE_TEST_SKIP_TIER
    lda current_tier
    cmp c128_cache_test_skip_tier
    bne !tl_partial_state_done+
    jsr c128_test_validate_tier_partial_state
    bcc !tl_partial_state_done+
    jmp c128_test_partial_cache_fail_sym
!tl_partial_state_done:
#endif
    jsr tier_load_disk
    bcc !tl_disk_ok+
    jmp !tl_failed+
!tl_disk_ok:
    jmp !tl_activate+

#if C128
!tl_cache_ok:
    jmp !tl_activate+
#endif

!tl_reu:
    // --- REU path: DMA tier data from REU to $E000 ---
    jsr reu_fetch_tier
    // REU DMA always succeeds (data was loaded at startup)

!tl_activate:
    // Data is now in RAM at $E000 (under KERNAL ROM).
    // Bank out KERNAL to read, copy SoA to active buffer.
#if !C128
    php
    sei
    lda $01
    pha                         // Save bank config
    :BankOutKernal()
#endif

    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    ldx current_tier
    lda tier_count_table,x      // A = creature count for this tier
    jsr load_tier_to_buffer

#if C128
    // Compute tier name table addresses in $E000 region.
    // After load_tier_to_buffer, zp_ptr0 is past all 22 arrays.
    // name_hi starts at zp_ptr0 - count, name_lo at zp_ptr0 - 2*count.
    sec
    lda zp_ptr0
    sbc active_dungeon_count
    sta tier_name_hi_addr
    lda zp_ptr0_hi
    sbc #0
    sta tier_name_hi_addr+1

    sec
    lda tier_name_hi_addr
    sbc active_dungeon_count
    sta tier_name_lo_addr
    lda tier_name_hi_addr+1
    sbc #0
    sta tier_name_lo_addr+1

    // Preserve end-of-SoA pointer before cache-base remap clobbers zp_ptr0.
    lda zp_ptr0
    sta c128_tier_soa_end_lo
    lda zp_ptr0_hi
    sta c128_tier_soa_end_hi
#endif

#if C128
    lda c128_cache_tiers_ready
    beq !tl_keep_e000_names+
    ldx current_tier
    lda c128_tier_ready_mask_minus1,x
    and c128_cache_tier_bits
    beq !tl_keep_e000_names+
    jsr c128_set_tier_name_tables_from_cache
!tl_keep_e000_names:
#else
    jsr platform_copy_tier_names_to_pool
#endif

#if !C128
    pla
    sta $01                     // Restore bank config
    plp
#endif

    // Clear stale name pointers for indices beyond this tier's range.
    // A previous larger tier may have left $E0xx pointers in
    // cr_name_hi[count..prev_count-1]. Zero them to prevent the
    // "?" fallback from triggering on out-of-range lookups.
    ldx active_dungeon_count
!tl_clear_names:
    cpx #MAX_DUNGEON_CREATURES
    bcs !tl_names_done+
    lda #0
    sta cr_name_hi,x
    inx
    bne !tl_clear_names-
!tl_names_done:

    lda #1
    sta tier_loaded
    rts

!tl_failed:
    // Disk load failed — reset tier state so creature_get_name
    // uses embedded name pointers (main RAM) instead of the
    // tier path which reads from $E000 (now invalid).
    jsr tier_invalidate_state
    rts

#if !C128
// platform_copy_tier_names_to_pool — Copy the active tier name block
// from the staged $E000 tier PRG into hidden RAM under I/O, then rewrite
// cr_name pointers. Called while interrupts are masked and $E000 RAM is visible.
// Output: carry clear
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_ptr2
platform_copy_tier_names_to_pool:
    lda zp_ptr0
    sta platform_tier_name_src_lo
    lda zp_ptr0_hi
    sta platform_tier_name_src_hi

    ldx current_tier
    lda tier_size_lo,x
    sta zp_ptr2
    lda tier_size_hi,x
    clc
    adc #>BANKED_DATA_BASE
    sta zp_ptr2_hi

    lda #<PLATFORM_TIER_NAME_POOL_BASE
    sta zp_ptr1
    lda #>PLATFORM_TIER_NAME_POOL_BASE
    sta zp_ptr1_hi

    // C64 only: hide I/O so writes to $D000-$D7FF reach RAM, not registers.
#if !PLUS4
    lda #BANK_ALL_RAM
    sta $01
#endif

    ldy #0
!ctnp_copy_loop:
    lda zp_ptr0
    cmp zp_ptr2
    bne !ctnp_copy_byte+
    lda zp_ptr0_hi
    cmp zp_ptr2_hi
    beq !ctnp_remap+
!ctnp_copy_byte:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    inc zp_ptr0
    bne !ctnp_src_ok+
    inc zp_ptr0_hi
!ctnp_src_ok:
    inc zp_ptr1
    bne !ctnp_copy_loop-
    inc zp_ptr1_hi
    jmp !ctnp_copy_loop-

!ctnp_remap:
    ldx #0
!ctnp_remap_loop:
    cpx active_dungeon_count
    bcs !ctnp_done+
    lda cr_name_lo,x
    sec
    sbc platform_tier_name_src_lo
    sta cr_name_lo,x
    lda cr_name_hi,x
    sbc platform_tier_name_src_hi
    clc
    adc #>PLATFORM_TIER_NAME_POOL_BASE
    sta cr_name_hi,x
    inx
    jmp !ctnp_remap_loop-
!ctnp_done:
    clc
    rts

.assert "Platform tier name pool fits largest name blob", TIER4_SIZE - (TIER4_COUNT * 22) <= (PLATFORM_TIER_NAME_POOL_END - PLATFORM_TIER_NAME_POOL_BASE + 1), true
#endif

#if C128
c128_preload_all_tiers:
    ldx #1
!cpat_loop:
    stx current_tier

    txa
    cmp c128_cache_test_skip_tier
    bne !cpat_show_file+
    jmp !cpat_next+

!cpat_show_file:
    dex
    lda hal_storage_tier_name_lo,x
    sta zp_ptr0
    lda hal_storage_tier_name_hi,x
    sta zp_ptr0_hi
    jsr reu_show_file

    ldx current_tier
    dex
    lda hal_storage_tier_name_len,x
    pha
    lda hal_storage_tier_name_lo,x
    pha
    lda hal_storage_tier_name_hi,x
    tay
    pla
    tax
    pla
    jsr c128_preload_asset_load
    bcs !cpat_next+

    jsr c128_stage_tier_to_cache
    bcs !cpat_next+

    ldx current_tier
    lda c128_tier_ready_mask_minus1,x
    ora c128_cache_tier_bits
    sta c128_cache_tier_bits

!cpat_next:
    ldx current_tier
    inx
    cpx #5
    bne !cpat_loop-

    lda c128_cache_tier_bits
    beq !cpat_none+
    lda #1
    sta c128_cache_tiers_ready
!cpat_none:
    lda #0
    sta current_tier
    rts

c128_set_tier_name_tables_from_cache:
    jsr c128_select_tier_cache_slot

    sec
    lda c128_tier_soa_end_lo
    sbc #<$e000
    sta zp_ptr1
    lda c128_tier_soa_end_hi
    sbc #>$e000
    sta zp_ptr1_hi

    clc
    lda c128_tier_cache_base_lo
    adc zp_ptr1
    sta zp_ptr1
    lda c128_tier_cache_base_hi
    adc zp_ptr1_hi
    sta zp_ptr1_hi

    sec
    lda zp_ptr1
    sbc active_dungeon_count
    sta tier_name_hi_addr
    lda zp_ptr1_hi
    sbc #0
    sta tier_name_hi_addr+1

    sec
    lda tier_name_hi_addr
    sbc active_dungeon_count
    sta tier_name_lo_addr
    lda tier_name_hi_addr+1
    sbc #0
    sta tier_name_lo_addr+1
    rts

c128_select_tier_cache_slot:
    ldx current_tier
    lda c128_tier_cache_slot_lo,x
    sta c128_tier_cache_base_lo
    lda c128_tier_cache_slot_hi,x
    sta c128_tier_cache_base_hi
    lda tier_size_lo,x
    sta c128_tier_cache_size_lo
    lda tier_size_hi,x
    sta c128_tier_cache_size_hi
    rts
#endif


// ============================================================
// tier_load_disk — KERNAL LOAD tier file from disk to $E000
// ============================================================
// Input: current_tier = tier number (1-4)
// Output: carry clear = success, carry set = error
// Clobbers: A, X, Y
tier_load_disk:
#if !C128
    :EnterKernal()
#endif
    // Select filename from table
    ldx current_tier
    dex                         // 0-based index (tier 1 → index 0)
    lda hal_storage_tier_name_len,x
    pha
    lda hal_storage_tier_name_lo,x
    pha
    lda hal_storage_tier_name_hi,x
    tay
    pla
    tax                         // X = filename addr lo, Y = hi
    pla                         // A = filename length

    // SETNAM: platform-owned tier filename
    jsr $ffbd                   // KERNAL SETNAM

    // SETLFS: file 2, device 8, secondary 1 (load to header address)
    lda #2                      // Logical file number
    ldx #8                      // Device 8
    ldy #1                      // Secondary 1 = load to PRG header address ($E000)
    jsr $ffba                   // KERNAL SETLFS

    // LOAD
    lda #0                      // 0 = LOAD (not VERIFY)
    ldx #$00                    // Ignored with secondary 1
    ldy #$e0
    :AssetLoad()                // Platform asset LOAD (handles C128 Bank 1)
    // Carry clear = success, carry set = error
    php                         // Save carry (load result)
    lda #2
    jsr $ffc3                   // KERNAL CLOSE — release file #2
    jsr $ffcc                   // KERNAL CLRCHN — restore default I/O
#if !C128
    lda $dd00
    ora #%00000011              // Restore VIC-II bank 0 after serial I/O
    sta $dd00
#endif
    plp                         // Restore carry
#if !C128
    :ExitKernal()
#endif
    rts


tier_loading_str:
    .text "Loading..." ; .byte 0

#if C128
// ============================================================
// c128_stage_tier_to_bank1 — Legacy entry name, now writes to the high Bank 1 cache slot
// ============================================================
// Precondition: caller has BankOutKernal active so Bank 0 $E000 RAM is readable.
// Input: current_tier set; tier_size tables valid.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0, zp_temp1
c128_stage_tier_to_bank1:
    jsr c128_stage_tier_to_cache
    rts

c128_stage_tier_to_cache:
    php
    sei
    jsr c128_select_tier_cache_slot

    // Source = Bank 0 $E000 (loaded tier payload)
    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi

    // Destination = Bank 1 cache slot
    lda c128_tier_cache_base_lo
    sta zp_ptr1
    lda c128_tier_cache_base_hi
    sta zp_ptr1_hi

    lda c128_tier_cache_size_lo
    sta zp_temp0
    lda c128_tier_cache_size_hi
    sta zp_temp1

    // Quick exit on zero length
    lda zp_temp0
    ora zp_temp1
    bne !cs_copy+
    plp
    rts

!cs_copy:
    ldy #0

    // Copy whole pages first (zp_temp1 pages)
!cs_page_loop:
    lda zp_temp1
    beq !cs_tail+
!cs_page:
    lda (zp_ptr0),y
    jsr mmu_safe_db_write_ptr1
    iny
    bne !cs_page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    jmp !cs_page_loop-

    // Copy trailing bytes (zp_temp0)
!cs_tail:
    ldx zp_temp0
    beq !cs_done+
!cs_tail_loop:
    lda (zp_ptr0),y
    jsr mmu_safe_db_write_ptr1
    iny
    dex
    bne !cs_tail_loop-
!cs_done:
    jsr c128_verify_tier_cache_slot
    bcc !cs_ok+
    plp
    sec
    rts
!cs_ok:
    plp
    clc
    rts

c128_verify_tier_cache_slot:
    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    lda c128_tier_cache_base_lo
    sta zp_ptr1
    lda c128_tier_cache_base_hi
    sta zp_ptr1_hi
    lda c128_tier_cache_size_lo
    sta zp_temp0
    lda c128_tier_cache_size_hi
    sta zp_temp1

    lda zp_temp0
    ora zp_temp1
    bne !cv_copy+
    clc
    rts

!cv_copy:
    ldy #0
!cv_page_loop:
    lda zp_temp1
    beq !cv_tail+
!cv_page:
    lda (zp_ptr0),y
    sta zp_temp2
    jsr mmu_safe_db_read_ptr1
    cmp zp_temp2
    bne !cv_fail+
    iny
    bne !cv_page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    jmp !cv_page_loop-
!cv_tail:
    ldx zp_temp0
    beq !cv_ok+
!cv_tail_loop:
    lda (zp_ptr0),y
    sta zp_temp2
    jsr mmu_safe_db_read_ptr1
    cmp zp_temp2
    bne !cv_fail+
    iny
    dex
    bne !cv_tail_loop-
!cv_ok:
    clc
    rts
!cv_fail:
    sec
    rts

c128_fetch_tier_from_cache:
    php
    sei
    jsr c128_select_tier_cache_slot

    lda c128_tier_cache_base_lo
    sta zp_ptr1
    lda c128_tier_cache_base_hi
    sta zp_ptr1_hi
    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    lda c128_tier_cache_size_lo
    sta zp_temp0
    lda c128_tier_cache_size_hi
    sta zp_temp1

    lda zp_temp0
    ora zp_temp1
    bne !cft_copy+
    plp
    clc
    rts

!cft_copy:
    ldy #0
!cft_page_loop:
    lda zp_temp1
    beq !cft_tail+
!cft_page:
    jsr mmu_safe_db_read_ptr1
    sta (zp_ptr0),y
    iny
    bne !cft_page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp1
    jmp !cft_page_loop-
!cft_tail:
    ldx zp_temp0
    beq !cft_ok+
!cft_tail_loop:
    jsr mmu_safe_db_read_ptr1
    sta (zp_ptr0),y
    iny
    dex
    bne !cft_tail_loop-
!cft_ok:
    plp
    clc
    rts

c128_tier_ready_mask_minus1:
    .byte 0, %00000001, %00000010, %00000100, %00001000

c128_cache_loading_hdr:
    .text "Preloading files:" ; .byte 0
#endif
