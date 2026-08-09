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

// ============================================================
// reu_detect — Detect REU and probe size
// ============================================================
// Call once at startup before title screen.
// Sets reu_present, reu_banks, reu_size_kb.
// Clobbers: A, X, Y
reu_detect:
    // --- Phase 1: Write/verify two complementary patterns ---
    // Write $55 to REU address low register, read back
    lda #$55
    sta REU_REULO
    cmp REU_REULO
    beq !phase1b+
    jmp !no_reu+
!phase1b:

    // Write $AA (complement), read back
    lda #$aa
    sta REU_REULO
    cmp REU_REULO
    beq !phase2+
    jmp !no_reu+
!phase2:

    // REU detected
    lda #1
    sta reu_present

    // --- Phase 2: Probe bank count (staged) ---
    // Each stage writes markers (bank+1) to a range of banks, then checks
    // bank 0 for aliasing (wrapping HW) and verifies the boundary bank
    // independently (VICE discard). Supports 128KB–2048KB (2–32 banks).
    //
    // Stage 1: banks 0-7   → detects 2, 4, or 8+ banks
    // Stage 2: banks 8-15  → detects 8 or 16+ banks
    // Stage 3: banks 16-31 → detects 16 or 32 banks

    // === Stage 1: Write markers to banks 0-7 ===
    ldy #0
!write_s1:
    tya
    clc
    adc #1              // Marker = bank + 1
    sta reu_probe_byte
    lda #REU_CMD_STASH
    jsr reu_probe_xfer
    iny
    cpy #8
    bne !write_s1-

    // Check bank 0: should be $01 if 8+ banks
    lda #0
    sta reu_probe_byte
    ldy #0
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$01
    bne !s1_aliased+

    // Bank 0 OK. Verify bank 4 ($05)
    lda #0
    sta reu_probe_byte
    ldy #4
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$05
    beq !at_least_8+

    // Bank 4 failed. Check bank 2.
    jsr reu_check_bank2
    beq !s1_got_4+
    jmp !is_2+
!s1_got_4:
    jmp !is_4+

!s1_aliased:
    // Bank 0 overwritten by alias. Check bank 2.
    jsr reu_check_bank2
    beq !s1a_got_4+
    jmp !is_2+
!s1a_got_4:
    jmp !is_4+

!at_least_8:
    // === Stage 2: Write markers to banks 8-15 ===
    ldy #8
!write_s2:
    tya
    clc
    adc #1
    sta reu_probe_byte
    lda #REU_CMD_STASH
    jsr reu_probe_xfer
    iny
    cpy #16
    bne !write_s2-

    // Check bank 0: aliased by bank 8? ($01 → $09)
    lda #0
    sta reu_probe_byte
    ldy #0
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$01
    bne !is_8+          // Aliased → 8 banks

    // Bank 0 OK. Verify bank 8 ($09)
    lda #0
    sta reu_probe_byte
    ldy #8
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$09
    bne !is_8+          // Discarded → 8 banks

    // === Stage 3: Write markers to banks 16-31 ===
    ldy #16
!write_s3:
    tya
    clc
    adc #1
    sta reu_probe_byte
    lda #REU_CMD_STASH
    jsr reu_probe_xfer
    iny
    cpy #32
    bne !write_s3-

    // Check bank 0: aliased by bank 16? ($01 → $11)
    lda #0
    sta reu_probe_byte
    ldy #0
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$01
    bne !is_16+         // Aliased → 16 banks

    // Bank 0 OK. Verify bank 16 ($11)
    lda #0
    sta reu_probe_byte
    ldy #16
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$11
    bne !is_16+         // Discarded → 16 banks

    // 32 banks (2048KB)
    ldy #32
    jmp !found_size+

!is_16:
    ldy #16
    jmp !found_size+
!is_8:
    ldy #8
    jmp !found_size+
!is_4:
    ldy #4
    jmp !found_size+
!is_2:
    ldy #2

!found_size:
    sty reu_banks

    // Convert banks to KB: banks * 64
    // Y is 2/4/8/16/32; max 32*64=2048 which fits in 16 bits
    tya
    // A * 64 = (A * 256) / 4. Store A in high byte, shift right 2.
    // A*64 = (A*256)/4. Store A in high byte, shift right 2.
    sta reu_size_kb + 1 // High byte = A (banks)
    lda #0
    sta reu_size_kb     // Low byte = 0
    // Now reu_size_kb = banks * 256. Divide by 4 to get banks * 64.
    lsr reu_size_kb + 1
    ror reu_size_kb
    lsr reu_size_kb + 1
    ror reu_size_kb     // reu_size_kb = banks * 64 (in KB)
    rts

!no_reu:
    lda #0
    sta reu_present
    sta reu_banks
    sta reu_size_kb
    sta reu_size_kb + 1
    rts


// reu_check_bank2 — Fetch bank 2 and check for marker $03
// Output: Z flag set if bank 2 holds $03 (4+ banks)
// Clobbers: A, Y
reu_check_bank2:
    lda #0
    sta reu_probe_byte
    ldy #2
    lda #REU_CMD_FETCH
    jsr reu_probe_xfer
    lda reu_probe_byte
    cmp #$03
    rts

// reu_probe_xfer — 1-byte DMA transfer for bank probing
// Input: A = command ($90=stash, $91=fetch), Y = bank number
// Uses reu_probe_byte as C64 address, REU offset $0000, length 1.
// Explicitly sets ALL registers (no autoload dependency).
// Preserves: nothing
reu_probe_xfer:
    pha                     // Save command
    lda #<reu_probe_byte
    sta REU_C64LO
    lda #>reu_probe_byte
    sta REU_C64HI
    lda #0
    sta REU_REULO
    sta REU_REUHI
    sty REU_BANK
    lda #1
    sta REU_LENLO
    lda #0
    sta REU_LENHI
    sta REU_CONTROL         // Both addresses increment
    pla
    sta REU_COMMAND         // Execute DMA
    rts

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
reu_load_all_tiers:
    lda #0
    sta reu_tier_offset_lo
    sta reu_tier_offset_hi
    sta reu_tiers_loaded

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

    // Load tier file from disk to $E000
    jsr tier_load_disk
    bcs !rlt_skip+              // Skip if load failed
    inc reu_tiers_loaded

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

!rlt_skip:
    // Advance REU offset by tier size (even if load failed, reserve space)
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

    // If no tiers loaded successfully, disable REU tier path
    // so tier_load falls back to disk → embedded creature fallback
    lda reu_tiers_loaded
    bne !rlt_done+
    sta reu_present             // A is already 0
!rlt_done:
    rts

// Scratch for REU tier loading
reu_tier_idx:       .byte 0
reu_tier_offset_lo: .byte 0
reu_tier_offset_hi: .byte 0
reu_tier_bank:      .byte 0
reu_tiers_loaded:   .byte 0     // Count of successfully loaded tiers

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


// ============================================================
// reu_stash_overlays — Stash all phase overlays into REU
// ============================================================
// Called at startup after reu_load_all_tiers. Loads each overlay
// PRG from disk to $E000, then stashes 4KB to REU. REU offset
// continues from reu_tier_offset_lo/hi (overlays sit after tiers).
// Clobbers: A, X, Y
reu_stash_overlays:
    // Keep this local count explicit because reu.s is imported before overlay.s.
    // The filename tables below are asserted against it so overlay additions must
    // update this contract deliberately.
#import "compat/hal_storage_overlay_test_stub.s"
    .const REU_OVERLAY_COUNT = hal_storage_overlay_name_hi - hal_storage_overlay_name_lo
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
    jsr overlay_load_disk
    bcs !rso_skip+              // Skip stash if load failed

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

!rso_skip:
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
    lda #13
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
