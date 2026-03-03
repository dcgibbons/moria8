// overlay.s — Phase overlay loading for $E000 region
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
//
// Disk filenames: OVL.START, OVL.TOWN, OVL.DEATH, OVL.GEN
// REU: stashed alongside creature tiers at startup

// ============================================================
// Constants
// ============================================================
.const OVL_NONE        = 0
.const OVL_STARTUP     = 1
.const OVL_TOWN        = 2
.const OVL_DEATH       = 3
.const OVL_DUNGEON_GEN = 4
.const OVL_COUNT       = 4

// ============================================================
// State
// ============================================================
current_overlay: .byte OVL_NONE
reu_overlays_stashed: .byte 0   // Set to 1 after overlays are stashed in REU

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
    sta ol_target

    // Invalidate tier state/metadata — $E000 will be overwritten by overlay code.
    jsr tier_invalidate_state

    lda reu_overlays_stashed
    bne !ol_reu+

    // --- Disk path: KERNAL LOAD overlay PRG ---
    ldx ol_target
    dex                     // 0-based index (OVL_STARTUP=1 → index 0)
    jsr overlay_load_disk
    bcs !ol_disk_fail+
    lda ol_target
    sta current_overlay
    rts
!ol_disk_fail:
    lda #OVL_NONE
    sta current_overlay
    rts

!ol_reu:
    // --- REU path: DMA overlay from REU to $E000 ---
    ldx ol_target
    jsr overlay_fetch_reu
    lda ol_target
    sta current_overlay
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
// overlay_load_disk — KERNAL LOAD overlay PRG file
// ============================================================
// Input: X = 0-based overlay index (0=startup, 1=town, 2=death)
// Output: carry clear = success, carry set = error
// Clobbers: A, X, Y
overlay_load_disk:
    :EnterKernal()
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
    ldy #1                  // Secondary 1 = use PRG header address ($E000)
    jsr $ffba               // KERNAL SETLFS

    lda #0                  // 0 = LOAD
    ldx #$00                // Load address low ($E000 low byte = $00)
    ldy #$e0                // Load address high ($E000)

!ol_do_load:
    :AssetLoad()            // Platform asset LOAD (handles C128 Bank 1)
    // Carry clear = success, carry set = error
    php                     // Save carry (load result)
    lda #2
    jsr $ffc3               // KERNAL CLOSE — release file #2
    jsr $ffcc               // KERNAL CLRCHN — restore default I/O
    
    lda zp_machine_type
    cmp #MACHINE_C128
    beq !ol_done+
    
    // Restore VIC-II bank 0 — KERNAL serial I/O uses CIA2 ($DD00)
    // bits 3-5 for the serial bus; bits 0-1 select VIC bank.
    // Ensure bank 0 ($0000-$3FFF) so VIC sees screen RAM at $0400.
    lda $dd00
    ora #%00000011
    sta $dd00

!ol_done:
    plp                     // Restore carry
    :ExitKernal()
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
// Overlay filename data (PETSCII for KERNAL — NOT screen codes)
// ============================================================
ovl_fn_start: .byte $4f,$56,$4c,$2e,$53,$54,$41,$52,$54  // "OVL.START"
ovl_fn_town:  .byte $4f,$56,$4c,$2e,$54,$4f,$57,$4e      // "OVL.TOWN"
ovl_fn_death: .byte $4f,$56,$4c,$2e,$44,$45,$41,$54,$48  // "OVL.DEATH"
ovl_fn_gen:   .byte $4f,$56,$4c,$2e,$47,$45,$4e          // "OVL.GEN"

ovl_fn_addr_lo:
    .byte <ovl_fn_start, <ovl_fn_town, <ovl_fn_death, <ovl_fn_gen
ovl_fn_addr_hi:
    .byte >ovl_fn_start, >ovl_fn_town, >ovl_fn_death, >ovl_fn_gen
ovl_fn_len:
    .byte 9, 8, 9, 7        // "OVL.START"=9, "OVL.TOWN"=8, "OVL.DEATH"=9, "OVL.GEN"=7


// ============================================================
// REU overlay offset tables (populated by reu_stash_overlays)
// ============================================================
// Index 0 unused (OVL_NONE), indices 1-4 = overlay IDs
ovl_reu_start_lo: .byte 0, 0, 0, 0, 0
ovl_reu_start_hi: .byte 0, 0, 0, 0, 0
ovl_reu_size_lo:  .byte 0, 0, 0, 0, 0
ovl_reu_size_hi:  .byte 0, 0, 0, 0, 0
ol_target:        .byte 0
