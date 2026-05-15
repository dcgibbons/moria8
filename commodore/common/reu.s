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

#if C128
// ============================================================
// c128_preload_asset_load — Shared preload-only LOAD transaction
// ============================================================
// Input:
//   A = filename length
//   X = filename pointer lo
//   Y = filename pointer hi
// Output:
//   carry clear = success
//   carry set   = LOAD failed
// Clobbers: A, X, Y
c128_preload_asset_load:
    php
    sei
#if C128_TEST_STACK_LOW_WATER
    lda #$a5
    jsr c128_stack_low_water_check
#endif
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_a
    stx c128_preload_diag_x
    sty c128_preload_diag_y
    lda #$c1
    sta c128_preload_diag_stage
#endif
    sta c128_preload_fn_len
    stx c128_preload_fn_lo
    sty c128_preload_fn_hi
    pla
    sta c128_preload_saved_p
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$11
    jsr c128_stack_guard_begin
#endif

    lda #0
    ldx #0
    jsr safe_setbnk             // LOAD destination bank = Bank 0

    lda #2
    jsr w_close                 // Pre-close stale preload channel
    jsr w_clrchn                // Restore default I/O channels

    lda c128_preload_fn_len
    ldx c128_preload_fn_lo
    ldy c128_preload_fn_hi
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_a
    stx c128_preload_diag_x
    sty c128_preload_diag_y
    lda #$c2
    sta c128_preload_diag_stage
#endif
    jsr w_setnam

    lda #2
    ldx #8
    ldy #1
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_a
    stx c128_preload_diag_x
    sty c128_preload_diag_y
    lda #$c3
    sta c128_preload_diag_stage
#endif
    jsr w_setlfs                // PRG header address

    lda #0
    ldx #0
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    lda #$00
    sta c128_preload_diag_a
    sta c128_preload_diag_x
    lda #$e0
    sta c128_preload_diag_y
    lda #$c4
    sta c128_preload_diag_stage
#endif
    ldy #$e0
    jsr w_load
#if C128_TEST_STACK_LOW_WATER
    lda #$a6
    jsr c128_stack_low_water_check
#endif
    lda #0
    rol                         // A=1 on error, 0 on success
    sta c128_preload_status
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_preload_diag_status
    lda zp_kernal_status
    sta c128_preload_diag_readst
    lda $01
    sta c128_preload_diag_port1
    lda hal_memory_mmu_config_register
    sta c128_preload_diag_mmu
    lda hal_memory_mmu_preconfig_a
    sta c128_preload_diag_pcra
    lda #$c5
    sta c128_preload_diag_stage
#endif

    lda #2
    jsr w_close
    jsr w_clrchn
    lda #0
    ldx #0
    jsr safe_setbnk             // Restore default LOAD destination bank
#if C128_TEST_STACK_LOW_WATER
    lda #$a7
    jsr c128_stack_low_water_check
#endif
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$19
    jsr c128_stack_guard_snapshot_banking
    jsr c128_diag_validate_runtime_invariants
#endif

    lda c128_preload_status
    beq !c128_preload_ok+
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$12
    jsr c128_stack_guard_check
#endif
    sec
    jmp c128_preload_finish
!c128_preload_ok:
#if C128_TEST_STACK_LOW_WATER
    lda #$a8
    jsr c128_stack_low_water_check
#endif
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    ldx #$13
    jsr c128_stack_guard_check
#endif
    clc
c128_preload_finish:
    php
    lda c128_preload_saved_p
    and #$04
    bne !restore_p+
    pla
    and #$fb
    pha
!restore_p:
    plp
    rts

c128_preload_fn_lo: .byte 0
c128_preload_fn_hi: .byte 0
c128_preload_saved_p: .byte 0
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
    lda $01
    pha
    lda #$35                    // Bank out KERNAL (so REU DMA reads RAM at $E000)
    sta $01

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
    sta $01                     // Restore bank config
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
    lda $01
    pha
    lda #$35                    // Bank out KERNAL for DMA to read/write RAM
    sta $01

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
    sta $01                     // Restore bank config
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
#if C128
    .const REU_OVERLAY_COUNT = 7
#else
    .const REU_OVERLAY_COUNT = 8
#endif
#import "hal_storage_overlay_test_stub.s"
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
    lda $01
    pha
    lda #$35                    // Bank out KERNAL for DMA to read RAM at $E000
    sta $01

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
    sta $01
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

    // Set overlay sizes (all 4KB = $1000) and activate REU path
    ldx #1
!rso_sizes:
    lda #$00
    sta ovl_reu_size_lo,x
    lda #$10
    sta ovl_reu_size_hi,x
    inx
    cpx #(REU_OVERLAY_COUNT + 1)
    bne !rso_sizes-

    lda #1
    sta reu_overlays_stashed
    rts

// Scratch for overlay stashing
reu_ovl_idx: .byte 0


// ============================================================
// REU loading display
// ============================================================

// reu_show_file — Display filename during REU stashing
// Input: zp_ptr0 = PETSCII filename string (null-terminated)
// Uses reu_loading_row for current row, increments after display.
// Clobbers: A, X, Y
reu_show_file:
    lda reu_loading_row
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
#if C128
    jsr hal_screen_put_string
#else
    jsr screen_set_cursor
    ldy #0
!rsf_loop:
    lda (zp_ptr0),y
    beq !rsf_done+
    cmp #$41
    bcc !rsf_write+
    cmp #$5b
    bcc !rsf_upper+
    cmp #$61
    bcc !rsf_write+
    cmp #$7b
    bcs !rsf_write+
!rsf_upper:
    and #$1f
!rsf_write:
    sta (zp_screen_lo),y
    lda zp_text_color
    sta (zp_color_lo),y
    iny
    cpy #40
    bcc !rsf_loop-
!rsf_done:
#endif
    inc reu_loading_row
    rts

reu_loading_row: .byte 0

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
.assert "REU tier filename table count stays in sync", hal_storage_tier_name_hi - hal_storage_tier_name_lo, 4
.assert "REU overlay filename table count stays in sync", hal_storage_overlay_name_hi - hal_storage_overlay_name_lo, REU_OVERLAY_COUNT

// Header string (displayed by tier_init)
reu_loading_hdr: .text "Loading into REU:" ; .byte 0
