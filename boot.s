// boot.s — Chain-loading bootloader for Moria C64/C128
//
// Standalone assembly unit. Displays "LOADING MORIA..." and
// chain-loads the game binary (MORIA64) from disk.
//
// Disk layout:
//   "moria"   = this bootloader (autostart)
//   "moria64" = game binary (loaded by this bootloader)
//
// The game binary is also independently loadable via VICE -autostart
// (no bootloader needed for development).

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
.pc = $0801 "BASIC Stub"
:BasicUpstart2(boot_entry)

// ============================================================
// Bootloader entry
// ============================================================
.pc = $080e "Boot"
boot_entry:
    // Clear screen
    lda #$93                // PETSCII clear screen
    jsr $ffd2               // KERNAL CHROUT

    // Set border/background black
    lda #0
    sta $d020
    sta $d021

    // Position cursor at row 12, col 12
    ldx #12                 // row
    ldy #12                 // column
    clc
    jsr $fff0               // KERNAL PLOT (clc = set position)

    // Print "LOADING MORIA..."
    ldx #0
!loop:
    lda loading_msg,x
    beq !done+
    jsr $ffd2               // KERNAL CHROUT
    inx
    bne !loop-
!done:

    // SETNAM — filename for LOAD
    lda #game_filename_end - game_filename
    ldx #<game_filename
    ldy #>game_filename
    jsr $ffbd               // KERNAL SETNAM

    // SETLFS — file#2, device 8, secondary 1 (use PRG load address)
    lda #2                  // logical file number
    ldx #8                  // device number
    ldy #1                  // secondary address (1 = use PRG header address)
    jsr $ffba               // KERNAL SETLFS

    // Copy chain-load stub to cassette buffer ($0340)
    // This stub survives LOAD overwriting $0801+
    ldx #chain_stub_end - chain_stub - 1
!copy:
    lda chain_stub,x
    sta $0340,x
    dex
    bpl !copy-

    // Jump to stub in cassette buffer — it performs LOAD + JMP to game
    jmp $0340

// ============================================================
// Chain-load stub (copied to $0340 before LOAD)
// ============================================================
chain_stub:
    lda #0                  // LOAD mode (0 = load, 1 = verify)
    jsr $ffd5               // KERNAL LOAD
    bcs !err+
    jmp $080e               // Jump to game entry point
!err:
    jmp ($a002)             // BASIC warm start on error
chain_stub_end:

// ============================================================
// Data
// ============================================================
loading_msg:
    .text "LOADING MORIA..."
    .byte 0

game_filename:
    .byte $4d, $4f, $52, $49, $41, $36, $34   // "MORIA64" in PETSCII
game_filename_end:
