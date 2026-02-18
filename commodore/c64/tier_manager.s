// tier_manager.s — Creature tier loading and transition management
//
// Manages the active creature tier. Detects tier boundaries on stair
// transitions and loads new tier data from disk or REU.
//
// Tier data is stored as standalone PRG files on the d64 disk.
// Files load to $E000 (RAM under KERNAL ROM). After loading, the
// SoA arrays are copied into the active creature buffer via
// load_tier_to_buffer. Name strings remain at $E000+ and are
// accessed through creature_get_name (which handles banking).
//
// Tier ranges (overlapping for hysteresis):
//   Tier 1: DL 1-8    (24 creatures)
//   Tier 2: DL 5-15   (32 creatures)
//   Tier 3: DL 11-25  (39 creatures)
//   Tier 4: DL 20-100 (57 creatures)
//
// Exports:
//   tier_init              — Call at startup to load all tiers to REU (if present)
//   tier_check_transition  — Call after dlvl change; loads new tier if needed

#import "creature_data/creature_tiers.s"

// ============================================================
// State variables
// ============================================================
current_tier:   .byte 0     // 0 = no tier (town/embedded), 1-4 = active tier
tier_loaded:    .byte 0     // 1 = a tier has been loaded from disk/REU

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

// Tier data sizes (for REU stash/fetch)
tier_size_lo:
    .byte 0
    .byte <TIER1_SIZE, <TIER2_SIZE, <TIER3_SIZE, <TIER4_SIZE
tier_size_hi:
    .byte 0
    .byte >TIER1_SIZE, >TIER2_SIZE, >TIER3_SIZE, >TIER4_SIZE


// ============================================================
// tier_init — Initialize tier system at startup
// ============================================================
// If REU is present: load all tier files from disk into REU
// for instant DMA on tier transitions. No tier is activated
// yet (player starts in town).
// If no REU: nothing to do now; tiers load on demand.
// Clobbers: A, X, Y, zp_ptr0, zp_temp0, zp_temp1
tier_init:
    lda #0
    sta current_tier
    sta tier_loaded

    lda reu_present
    beq !ti_done+

    // Clear screen and show loading progress
    jsr screen_clear
    lda #1
    sta $cc                     // Suppress cursor blink during loading
    lda #COL_LGREY
    sta zp_text_color
    lda #1
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<reu_loading_hdr
    sta zp_ptr0
    lda #>reu_loading_hdr
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #3
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


// ============================================================
// tier_load — Load a specific tier into the active creature buffer
// ============================================================
// Input: current_tier = tier number (1-4)
// Uses REU (DMA) if available, otherwise KERNAL LOAD from disk.
// After loading, SoA arrays are copied to the active buffer.
// Name strings remain at $E000+ (accessed via creature_get_name).
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1, zp_temp0, zp_temp1
tier_load:
    // Invalidate overlay — tier data will overwrite $E000
    jsr overlay_invalidate

    // Show loading message
    lda #<tier_loading_str
    sta zp_ptr0
    lda #>tier_loading_str
    sta zp_ptr0_hi
    jsr msg_print

    lda reu_present
    bne !tl_reu+

    // --- Disk path: KERNAL LOAD tier file to $E000 ---
    jsr tier_load_disk
    bcs !tl_failed+
    jmp !tl_activate+

!tl_reu:
    // --- REU path: DMA tier data from REU to $E000 ---
    jsr reu_fetch_tier
    // REU DMA always succeeds (data was loaded at startup)

!tl_activate:
    // Data is now in RAM at $E000 (under KERNAL ROM).
    // Bank out KERNAL to read, copy SoA to active buffer.
    sei
    lda $01
    pha                         // Save bank config
    lda #$35                    // Bank out KERNAL + BASIC (all RAM)
    sta $01

    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    ldx current_tier
    lda tier_count_table,x      // A = creature count for this tier
    jsr load_tier_to_buffer

    pla
    sta $01                     // Restore bank config
    cli

    lda #1
    sta tier_loaded
    rts

!tl_failed:
    // Disk load failed — keep embedded data as fallback
    rts


// ============================================================
// tier_load_disk — KERNAL LOAD tier file from disk to $E000
// ============================================================
// Input: current_tier = tier number (1-4)
// Output: carry clear = success, carry set = error
// Clobbers: A, X, Y
tier_load_disk:
    // Select filename from table
    ldx current_tier
    dex                         // 0-based index (tier 1 → index 0)
    lda tier_fn_addr_lo,x
    pha
    lda tier_fn_addr_hi,x
    tay
    pla
    tax                         // X = filename addr lo, Y = hi

    // SETNAM: 12-character filename
    lda #12
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
    jsr $FFD5                   // KERNAL LOAD
    // Carry clear = success, carry set = error
    php                         // Save carry (load result)
    lda $dd00
    ora #%00000011              // Restore VIC-II bank 0 after serial I/O
    sta $dd00
    plp                         // Restore carry
    rts


// ============================================================
// Filename data (PETSCII — NOT screen codes)
// ============================================================
// "MONSTER.DB.1" through "MONSTER.DB.4" — matches d64 directory entries
tier_fn_1:  .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $31  // "MONSTER.DB.1"
tier_fn_2:  .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $32  // "MONSTER.DB.2"
tier_fn_3:  .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $33  // "MONSTER.DB.3"
tier_fn_4:  .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $34  // "MONSTER.DB.4"

tier_fn_addr_lo:
    .byte <tier_fn_1, <tier_fn_2, <tier_fn_3, <tier_fn_4
tier_fn_addr_hi:
    .byte >tier_fn_1, >tier_fn_2, >tier_fn_3, >tier_fn_4

tier_loading_str:
    .text "LOADING..." ; .byte 0
