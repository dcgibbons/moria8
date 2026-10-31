#importonce
// reu_detect.s — REU detection and size probing (boot only), for reu.s.

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
