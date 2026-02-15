// overlay.s — Phase overlay loading for $E000 region
//
// Manages code overlays at $E000-$EFFF for different game phases.
// Coexists with creature tier system which also uses $E000.
// When an overlay loads, tier data is invalidated (and vice versa).
//
// Overlay IDs:
//   OVL_NONE    = 0  No overlay (tier data or empty)
//   OVL_STARTUP = 1  Title screen + character creation
//   OVL_TOWN    = 2  Stores
//   OVL_DEATH   = 3  Score + high scores
//
// Disk filenames: OVL.START, OVL.TOWN, OVL.DEATH
// REU: stashed alongside creature tiers at startup

// ============================================================
// Constants
// ============================================================
.const OVL_NONE    = 0
.const OVL_STARTUP = 1
.const OVL_TOWN    = 2
.const OVL_DEATH   = 3
.const OVL_COUNT   = 3

// ============================================================
// State
// ============================================================
current_overlay: .byte OVL_NONE

// ============================================================
// overlay_load — Load a phase overlay to $E000
// ============================================================
// Input: A = overlay ID (OVL_STARTUP, OVL_TOWN, OVL_DEATH)
// Invalidates creature tier state (tier data overwritten).
// Output: carry clear = success, carry set = error (disk only)
// Clobbers: A, X, Y
overlay_load:
    cmp current_overlay
    beq !ol_skip+           // Already loaded — skip
    sta current_overlay

    // Invalidate tier — $E000 will be overwritten with overlay code
    lda #0
    sta current_tier

    lda reu_present
    bne !ol_reu+

    // --- Disk path: KERNAL LOAD overlay PRG ---
    ldx current_overlay
    dex                     // 0-based index (OVL_STARTUP=1 → index 0)
    jsr overlay_load_disk
    rts

!ol_reu:
    // --- REU path: DMA overlay from REU to $E000 ---
    ldx current_overlay
    jsr overlay_fetch_reu
    clc                     // REU always succeeds
    rts

!ol_skip:
    clc
    rts


// ============================================================
// overlay_invalidate — Mark overlay as unloaded
// ============================================================
// Called by tier_load when creature tier data overwrites $E000.
overlay_invalidate:
    lda #OVL_NONE
    sta current_overlay
    rts


// ============================================================
// overlay_load_disk — KERNAL LOAD overlay PRG file to $E000
// ============================================================
// Input: X = 0-based overlay index (0=startup, 1=town, 2=death)
// Output: carry clear = success, carry set = error
// Clobbers: A, X, Y
overlay_load_disk:
    lda ovl_fn_len,x
    pha                     // Save filename length
    lda ovl_fn_addr_lo,x
    pha
    lda ovl_fn_addr_hi,x
    tay
    pla
    tax                     // X = filename addr lo, Y = hi
    pla                     // A = filename length
    jsr $ffbd               // KERNAL SETNAM

    lda #2                  // Logical file number
    ldx #8                  // Device 8
    ldy #1                  // Secondary 1 = load to PRG header address ($E000)
    jsr $ffba               // KERNAL SETLFS

    lda #0                  // 0 = LOAD
    ldx #$00
    ldy #$e0
    jsr $ffd5               // KERNAL LOAD
    // Carry clear = success, carry set = error
    rts


// ============================================================
// overlay_fetch_reu — DMA overlay from REU to $E000
// ============================================================
// Input: X = overlay ID (1-3)
// Fetches overlay from REU memory to $E000 in C64 RAM.
// Clobbers: A, X
overlay_fetch_reu:
    sei
    lda $01
    pha
    lda #$35                // Bank out KERNAL for DMA to write RAM at $E000
    sta $01

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI

    lda ovl_reu_start_lo,x
    sta REU_REULO
    lda ovl_reu_start_hi,x
    sta REU_REUHI
    lda #0
    sta REU_BANK

    lda ovl_reu_size_lo,x
    sta REU_LENLO
    lda ovl_reu_size_hi,x
    sta REU_LENHI
    lda #0
    sta REU_CONTROL
    lda #REU_CMD_FETCH
    sta REU_COMMAND         // DMA completes before next instruction

    pla
    sta $01
    cli
    rts


// ============================================================
// banked_get_key — Input wrapper for $E000 overlay code
// ============================================================
// Temporarily banks in KERNAL to call input_get_key, then
// banks out again. Callable from $E000 overlay code.
// Output: A = key (screen code)
// Clobbers: flags
banked_get_key:
    lda #BANK_NO_BASIC      // $36 — bank in KERNAL
    sta $01
    jsr input_get_key       // Uses KERNAL GETIN
    pha
    lda #BANK_NO_ROMS       // $34 — bank out KERNAL again
    sta $01
    pla
    rts


// ============================================================
// Overlay filename data (PETSCII for KERNAL — NOT screen codes)
// ============================================================
ovl_fn_start: .byte $4f,$56,$4c,$2e,$53,$54,$41,$52,$54  // "OVL.START"
ovl_fn_town:  .byte $4f,$56,$4c,$2e,$54,$4f,$57,$4e      // "OVL.TOWN"
ovl_fn_death: .byte $4f,$56,$4c,$2e,$44,$45,$41,$54,$48   // "OVL.DEATH"

ovl_fn_addr_lo:
    .byte <ovl_fn_start, <ovl_fn_town, <ovl_fn_death
ovl_fn_addr_hi:
    .byte >ovl_fn_start, >ovl_fn_town, >ovl_fn_death
ovl_fn_len:
    .byte 9, 8, 9           // "OVL.START"=9, "OVL.TOWN"=8, "OVL.DEATH"=9


// ============================================================
// REU overlay offset tables (populated by reu_stash_overlays)
// ============================================================
// Index 0 unused (OVL_NONE), indices 1-3 = overlay IDs
ovl_reu_start_lo: .byte 0, 0, 0, 0
ovl_reu_start_hi: .byte 0, 0, 0, 0
ovl_reu_size_lo:  .byte 0, 0, 0, 0
ovl_reu_size_hi:  .byte 0, 0, 0, 0
