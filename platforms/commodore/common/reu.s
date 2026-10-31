#importonce
// reu.s — REU (RAM Expansion Unit) detection and DMA routines
//
// The REU provides fast DMA transfers between C64 RAM and expansion RAM.
// Register addresses are exported by each REU-capable platform HAL.
// Standard sizes: 128KB (1700), 256KB (1764),
// 512KB (1750). Also emulated in VICE with configurable sizes up to 16MB.
//
// Exports:
//   reu_detect       — Detect REU presence, probe size
//   reu_stash        — C64 → REU transfer
//   reu_fetch        — REU → C64 transfer
//   reu_present      — Flag: 0=no REU, 1=REU detected
//   reu_banks        — Number of 64KB banks (2/4/8, or 0 if no REU)
//   reu_size_kb      — Total size in KB (128/256/512, or 0)

// ============================================================
// REU hardware registers
// ============================================================
.const REU_STATUS   = hal_memory_reu_status   // (R)   Status register
.const REU_COMMAND  = hal_memory_reu_command  // (R/W) Command register
.const REU_C64LO    = hal_memory_reu_c64lo    // (R/W) C64 base address low
.const REU_C64HI    = hal_memory_reu_c64hi    // (R/W) C64 base address high
.const REU_REULO    = hal_memory_reu_reulo    // (R/W) REU address low
.const REU_REUHI    = hal_memory_reu_reuhi    // (R/W) REU address high
.const REU_BANK     = hal_memory_reu_bank     // (R/W) REU bank (bits 2-0)
.const REU_LENLO    = hal_memory_reu_lenlo    // (R/W) Transfer length low
.const REU_LENHI    = hal_memory_reu_lenhi    // (R/W) Transfer length high
.const REU_IRQMASK  = hal_memory_reu_irqmask  // (R/W) Interrupt mask
.const REU_CONTROL  = hal_memory_reu_control  // (R/W) Address control

// Command byte values
.const REU_CMD_STASH     = $90  // Execute + immediate + C64→REU
.const REU_CMD_FETCH     = $91  // Execute + immediate + REU→C64
.const REU_CMD_STASH_AL  = $b0  // + autoload (preserve registers)
.const REU_CMD_FETCH_AL  = $b1  // + autoload

// ============================================================
// State variables (static RAM)
// ============================================================
reu_present:  .byte 0       // 0=no REU, 1=detected
reu_banks:    .byte 0       // Number of 64KB banks (0/2/4/8)
reu_size_kb:  .word 0       // Total KB (0/128/256/512)
reu_overlays_stashed: .byte 0

// Scratch byte for size probing (needs stable RAM address)
reu_probe_byte: .byte 0

// Detection runs once at boot; the C64 product places it in its init-only
// tail (REU_DETECT_EXTERNAL), where the map later overwrites it.
#if !REU_DETECT_EXTERNAL
#import "reu_detect.s"
#endif

// ============================================================
// reu_stash — Transfer C64 RAM → REU
// ============================================================
// Input:
//   zp_ptr0      = C64 source address (lo/hi)
//   REU_REULO/HI = REU dest address (caller sets these)
//   REU_BANK     = REU bank (caller sets)
//   zp_temp0     = transfer length low
//   zp_temp1     = transfer length high
// Clobbers: A
reu_stash:
    lda zp_ptr0
    sta REU_C64LO
    lda zp_ptr0_hi
    sta REU_C64HI
    lda zp_temp0
    sta REU_LENLO
    lda zp_temp1
    sta REU_LENHI
    lda #0
    sta REU_CONTROL     // Both addresses increment
    lda #REU_CMD_STASH
    sta REU_COMMAND     // Execute — DMA completes before next instruction
    rts


// ============================================================
// reu_fetch — Transfer REU → C64 RAM
// ============================================================
// Input:
//   zp_ptr0      = C64 dest address (lo/hi)
//   REU_REULO/HI = REU source address (caller sets these)
//   REU_BANK     = REU bank (caller sets)
//   zp_temp0     = transfer length low
//   zp_temp1     = transfer length high
// Clobbers: A
reu_fetch:
    lda zp_ptr0
    sta REU_C64LO
    lda zp_ptr0_hi
    sta REU_C64HI
    lda zp_temp0
    sta REU_LENLO
    lda zp_temp1
    sta REU_LENHI
    lda #0
    sta REU_CONTROL     // Both addresses increment
    lda #REU_CMD_FETCH
    sta REU_COMMAND     // Execute — DMA completes before next instruction
    rts


// ============================================================
// reu_load_all_tiers — Load all creature tier files into REU
// ============================================================
// Called at startup if REU is detected. Loads each tier PRG from
// disk to $E000 via KERNAL LOAD, then stashes to REU memory.
// REU layout: tier 1 at bank 0 offset $0000, tier 2 follows, etc.
// Clobbers: A, X, Y, zp_ptr0, zp_temp0, zp_temp1
// C64 keeps its own copy in the init-only tail past program_end (one-shot;
// the resident image funds chest search/trap discovery there).
#if !REU_LOAD_ALL_TIERS_EXTERNAL
reu_load_all_tiers:
    lda #0
    sta reu_tier_offset_lo
    sta reu_tier_offset_hi

    ldx #1                      // Start with tier 1
!rlt_loop:
    stx reu_tier_idx

    // Save REU start offset for this tier BEFORE stashing
    lda reu_tier_offset_lo
    sta reu_tier_start_lo,x
    lda reu_tier_offset_hi
    sta reu_tier_start_hi,x

    // Display tier filename
    stx current_tier            // tier_load_disk reads current_tier for filename
    dex                         // 0-based index for display table
    lda reu_fn_tier_lo,x
    sta zp_ptr0
    lda reu_fn_tier_hi,x
    sta zp_ptr0_hi
    jsr reu_show_file

    // Load tier file from disk to $E000 (asset_load_required: a file that
    // will not load asks for the program disk, so every tier is stashed)
    jsr tier_load_disk

    // Stash from $E000 to REU at current offset
    sei
    lda hal_memory_cpu_port
    pha
    lda #$35                    // Bank out KERNAL (so REU DMA reads RAM at $E000)
    sta hal_memory_cpu_port

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI
    ldx reu_tier_idx
    lda reu_tier_start_lo,x
    sta REU_REULO
    lda reu_tier_start_hi,x
    sta REU_REUHI
    lda #0
    sta REU_BANK                // All tier data fits in bank 0
    lda tier_size_lo,x
    sta REU_LENLO
    lda tier_size_hi,x
    sta REU_LENHI
    lda #0
    sta REU_CONTROL             // Both addresses increment
    lda #REU_CMD_STASH
    sta REU_COMMAND             // Execute DMA

    pla
    sta hal_memory_cpu_port     // Restore bank config
    cli

    // Advance REU offset by tier size
    ldx reu_tier_idx
    clc
    lda reu_tier_offset_lo
    adc tier_size_lo,x
    sta reu_tier_offset_lo
    lda reu_tier_offset_hi
    adc tier_size_hi,x
    sta reu_tier_offset_hi

    // Update status display with new usage
    jsr reu_show_status

    ldx reu_tier_idx
    inx
    cpx #5                      // Tiers 1-4
    beq !rlt_all_done+
    jmp !rlt_loop-
!rlt_all_done:

    // Reset game state — no tier active yet (player starts in town)
    lda #0
    sta current_tier
    rts
#endif

// Scratch for REU tier loading
reu_tier_idx:       .byte 0
reu_tier_offset_lo: .byte 0
reu_tier_offset_hi: .byte 0
reu_tier_bank:      .byte 0

// REU start offsets for each tier (filled during reu_load_all_tiers)
// Index 0 unused; tier 1 always starts at offset 0
reu_tier_start_lo:  .byte 0, 0, 0, 0, 0
reu_tier_start_hi:  .byte 0, 0, 0, 0, 0


// ============================================================
// reu_fetch_tier — DMA a tier from REU to $E000
// ============================================================
// Input: current_tier = tier number (1-4)
// Fetches the tier data from REU into RAM at $E000 (under KERNAL ROM).
// Must be called with KERNAL banked in (DMA result stored in RAM).
// Clobbers: A, X
reu_fetch_tier:
    ldx current_tier

    // Set up DMA: REU → $E000
    php
    sei
    lda hal_memory_cpu_port
    pha
    lda #$35                    // Bank out KERNAL for DMA to read/write RAM
    sta hal_memory_cpu_port

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI

    // REU source address for this tier (saved during reu_load_all_tiers)
    lda reu_tier_start_lo,x
    sta REU_REULO
    lda reu_tier_start_hi,x
    sta REU_REUHI
    lda #0                      // All tiers fit in bank 0
    sta REU_BANK

    lda tier_size_lo,x
    sta REU_LENLO
    lda tier_size_hi,x
    sta REU_LENHI
    lda #0
    sta REU_CONTROL             // Both addresses increment
    lda #REU_CMD_FETCH
    sta REU_COMMAND             // Execute DMA

    pla
    sta hal_memory_cpu_port     // Restore bank config
    plp
    rts


// Computed from the platform overlay filename table (labels resolve in a
// later assembler pass); asserted against the table below. Kept outside the
// REU_STASH_OVERLAYS_EXTERNAL guard so the assert still sees it on C64.
.const REU_OVERLAY_COUNT = hal_storage_overlay_name_hi - hal_storage_overlay_name_lo

// ============================================================
// reu_stash_overlays — Stash all phase overlays into REU
// ============================================================
// Called at startup after reu_load_all_tiers. Loads each overlay
// PRG from disk to $E000, then stashes 4KB to REU. REU offset
// continues from reu_tier_offset_lo/hi (overlays sit after tiers).
// Clobbers: A, X, Y
// C64 keeps its own copy in the init-only tail past program_end (one-shot;
// the resident image funds chest spawn initialization there).
#if !REU_STASH_OVERLAYS_EXTERNAL
reu_stash_overlays:
    // Keep this local count explicit because reu.s is imported before overlay.s.
    // The filename tables below are asserted against it so overlay additions must
    // update this contract deliberately.
#import "compat/hal_storage_overlay_test_stub.s"
    ldx #1                      // Start with overlay 1 (OVL_STARTUP)
!rso_loop:
    stx reu_ovl_idx

    // Record REU start offset for this overlay
    lda reu_tier_offset_lo
    sta ovl_reu_start_lo,x
    lda reu_tier_offset_hi
    sta ovl_reu_start_hi,x

    // Display overlay filename
    dex                         // 0-based index
    lda reu_fn_ovl_lo,x
    sta zp_ptr0
    lda reu_fn_ovl_hi,x
    sta zp_ptr0_hi
    jsr reu_show_file

    // Load overlay PRG from disk to $E000
    ldx reu_ovl_idx
    dex                         // 0-based index for overlay_load_disk
    jsr overlay_load_disk       // asks for the disk until it loads

    // Stash $E000 (4KB) to REU at current offset
    sei
    lda hal_memory_cpu_port
    pha
    lda #$35                    // Bank out KERNAL for DMA to read RAM at $E000
    sta hal_memory_cpu_port

    lda #<$e000
    sta REU_C64LO
    lda #>$e000
    sta REU_C64HI
    ldx reu_ovl_idx
    lda ovl_reu_start_lo,x
    sta REU_REULO
    lda ovl_reu_start_hi,x
    sta REU_REUHI
    lda #0
    sta REU_BANK
    sta REU_LENLO               // Length lo = $00
    lda #$10                    // Length hi = $10 → $1000 = 4KB
    sta REU_LENHI
    lda #0
    sta REU_CONTROL
    lda #REU_CMD_STASH
    sta REU_COMMAND             // Execute DMA

    pla
    sta hal_memory_cpu_port
    cli

    // Advance REU offset by $1000 (4KB) — low byte unchanged
    lda reu_tier_offset_hi
    clc
    adc #$10
    sta reu_tier_offset_hi

    // Update status display with new usage
    jsr reu_show_status

    ldx reu_ovl_idx
    inx
    cpx #(REU_OVERLAY_COUNT + 1)
    bne !rso_loop-

    lda #1
    sta reu_overlays_stashed
    rts
#endif

// Scratch for overlay stashing
reu_ovl_idx: .byte 0


// ============================================================
// REU loading display
// ============================================================

// reu_show_file — Advance the centered REU loading progress display.
reu_show_file:
    inc reu_loading_count
    jmp reu_render_progress

reu_render_progress:
    lda #12
    jsr hal_screen_clear_row
    lda #12
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<reu_loading_prefix
    sta zp_ptr0
    lda #>reu_loading_prefix
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda reu_loading_count
    jsr screen_put_decimal
    lda #$2f
    jsr hal_screen_put_char
    lda #(4 + REU_OVERLAY_COUNT)    // tiers + overlays (chest overlay included)
    jsr screen_put_decimal
    lda #<reu_loading_suffix
    sta zp_ptr0
    lda #>reu_loading_suffix
    sta zp_ptr0_hi
    jmp hal_screen_put_string

reu_loading_count: .byte 0

// reu_show_status — Display REU loading progress
// Default: RTS (safe for test builds). At startup, main.s patches
// this to JMP to the banked trampoline after init_copy_banked.
// Clobbers: A, X, Y (when patched)
reu_show_status:
    rts                         // Patched to $4C (JMP abs) at startup
    .byte 0, 0                  // Operand bytes filled by init patch

// Display pointer tables (0-based index). These intentionally point at the
// platform-owned KERNAL filename literals; do not add separate display copies.
.label reu_fn_tier_lo = hal_storage_tier_name_lo
.label reu_fn_tier_hi = hal_storage_tier_name_hi
.label reu_fn_ovl_lo = hal_storage_overlay_name_lo
.label reu_fn_ovl_hi = hal_storage_overlay_name_hi
.assert "Tier filename table count stays in sync", hal_storage_tier_name_hi - hal_storage_tier_name_lo, 4
.assert "Overlay filename table count stays in sync", hal_storage_overlay_name_hi - hal_storage_overlay_name_lo, REU_OVERLAY_COUNT

// Progress message parts (reassembled by reu_render_progress)
reu_loading_prefix: .text "MORIA8 LOADING " ; .byte 0
reu_loading_suffix: .text " PLEASE WAIT" ; .byte 0
