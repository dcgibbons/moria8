#importonce
// boot128.s — Bootloader for Moria8 C128 (Standard Model Refined)
//
// Relocates 4 pages to $2000. Filenames at $2300.
// Preserves KERNAL workspace by staying clear of $0200-$03FF.

.const MMU_NORMAL       = $0E   // Bank 0, ROMs, I/O
.const MMU_RAM_BANK1    = $7E   // Bank 1, all RAM, I/O visible
.const MMU_ALL_RAM      = $3E   // Bank 0, all RAM, I/O visible
// For copy loop: hide I/O so $D000-$DFFF accesses RAM, not VDC/SID/CIA
.const MMU_RAM_BANK1_NOIO = $7F // Bank 1, all RAM, RAM at $D000 (no I/O)
.const MMU_ALL_RAM_NOIO   = $3F // Bank 0, all RAM, RAM at $D000 (no I/O)

.const BANK_ALL_ROM     = $37   // KERNAL + BASIC + I/O visible

// Border colors for heartbeat
.const COL_BLACK  = 0
.const COL_WHITE  = 1
.const COL_RED    = 2
.const COL_CYAN   = 3
.const COL_BLUE   = 6

// ============================================================
// BASIC stub at $1C01 — SYS 7182 ($1C0E)
// ============================================================
.const BOOT_DIAG_SIG_BASE = $0bf0

.pc = $1C01 "BASIC Stub"
    .byte $0b, $1c, $0a, $00, $9e, $37, $31, $38, $32, $00, $00, $00

// ============================================================
// Bootstrap at $1C0E — Relocate 1KB (4 pages) to $2000
// ============================================================
.pc = $1C0E "Bootstrap"
bootstrap_entry:
    sei
    cld                     // Ensure KERNAL-safe binary mode
    ldx #$ff
    txs                     // Stack safety

    // DIAGNOSTIC: White Border = Relocating
    lda #COL_WHITE
    sta $d020

    // 1. EXPOSE ALL RAM
    lda #MMU_ALL_RAM
    sta $ff00

    // 2. Relocate 4 pages (1024 bytes) to $2000
    ldx #0
!loop:
    .for (var i=0; i<4; i++) {
        lda loader_data_src + [i*$100],x
        sta $2000 + [i*$100],x
    }
    inx
    bne !loop-
    
    jmp $2000

loader_data_src:
.pseudopc $2000 {
loader_start:
#if BOOT_DIAG
    lda #$c1
    sta BOOT_DIAG_SIG_BASE + 0
    lda $d506
    sta BOOT_DIAG_SIG_BASE + 1
#endif

    // 3. RESTORE KERNAL: Bank in ROMs for I/O
    lda #MMU_NORMAL
    sta $ff00
    lda #COL_BLACK
    sta $d020
    
    // 4. Machine State — 4KB bottom common ($0000-$0FFF)
    // The copy stub lives at $0B00. It must be in common area so the CPU
    // still fetches stub instructions from Bank 0 when $FF00 switches to Bank 1.
    // $05 = bit 0 (bottom common on) + bits 3-2=01 (4KB size)
    lda #$05
    sta $d506
    lda #$ff
    sta $d8                 // 80-column mode defense
    cli                     // Enable interrupts for Disk Driver

    // Blank screen / Clear VDC
    lda #0
    sta $d011
    sta $0a26
    lda #$93
    jsr $ffd2

    // 5. SETBNK (Bank 1 data, Bank 0 filenames)
    // Filenames are at $2300 (Bank 0 RAM, visible to Bank 15)
    lda #1
    ldx #0
    jsr $ff68

    // 6. Stage 1: LOAD Main Program (MORIA128) into Bank 1
    lda #game_filename_end - game_filename
    ldx #<game_filename
    ldy #>game_filename
    jsr $ffbd
    
    lda #2
    ldx #8
    ldy #1
    jsr $ffba

    lda #COL_BLUE
    sta $d020
    lda #0
    jsr $ffd5
    bcs load_err

#if BOOT_DIAG
    lda #$c2
    sta BOOT_DIAG_SIG_BASE + 0
    lda $d506
    sta BOOT_DIAG_SIG_BASE + 2
#endif
    
    // 7. SUCCESS: Relocate stub to $0B00 and Hand-off
    // Data load (BANK1.DAT) will be handled by the engine in Stage 2.
    lda #COL_BLACK
    sta $d020
    sei
    
    ldx #stub_end - stub_start
!reloc:
    lda stub_reloc_src_relocated - 1,x
    sta $0b00 - 1,x
    dex
    bne !reloc-
    
    jmp $0b00

load_err:
    inc $d020               // Flashing Red Scream
    jmp load_err

loading_msg:
    .text "LOADING MORIA8..." ; .byte 0

// Filenames at $2300 (inside the 1KB payload)
.fill $2300 - *, 0
game_filename:
    .byte $4d, $4f, $52, $49, $41, $31, $32, $38   // "MORIA128"
game_filename_end:

.label stub_reloc_src_relocated = *
}

// Stub source - virtual address $0B00
stub_reloc_src:
.pseudopc $0b00 {
stub_start:
    lda #$05
    sta $d506               // 4KB bottom common ($0000-$0FFF) — stub at $0B00 must be common

#if BOOT_DIAG
    lda #$d1
    sta BOOT_DIAG_SIG_BASE + 0
    lda $d506
    sta BOOT_DIAG_SIG_BASE + 3
#endif

    // Clear Overlay $B000-$BFFF
    lda #0
    ldx #$b0
    sta $60
    stx $61
    ldx #$10
!clr:
    ldy #0
!pg:
    sta ($60),y
    iny
    bne !pg-
    inc $61
    dex
    bne !clr-

    // Atomic Bank Copy (1 -> 0) with staged-source scrub
    // Page-buffered copy via common RAM to avoid MMU thrashing.
    // Once a source page is buffered into common RAM, clear that Bank 1 page
    // so the staged program image is reclaimed during boot.
    // MUST use _NOIO variants ($7F/$3F) to hide I/O at $D000-$DFFF.
    lda #$00
    sta $60
    lda #$1c
    sta $61
    ldx #$e3                // Copy $E3 pages ($1C00 to $FEFF) -> stops exactly at $FF00

#if BOOT_DIAG
    // Capture source signature byte from Bank 1 before copy
    lda #MMU_RAM_BANK1_NOIO
    sta $ff00
    lda $1c0e
    sta BOOT_DIAG_SIG_BASE + 4
    lda #MMU_ALL_RAM_NOIO
    sta $ff00
#endif

copy_loop:
    // Read 256 bytes from Bank 1 into common RAM buffer ($0C00)
    lda #MMU_RAM_BANK1_NOIO
    sta $ff00
    ldy #0
!read_pg:
    lda ($60),y
    sta $0c00,y
    iny
    bne !read_pg-

    // Scrub the staged source page in Bank 1 once it is buffered.
    lda #0
    ldy #0
!clear_pg:
    sta ($60),y
    iny
    bne !clear_pg-

    // Write 256 bytes from common RAM buffer to Bank 0
    lda #MMU_ALL_RAM_NOIO
    sta $ff00
    ldy #0
!write_pg:
    lda $0c00,y
    sta ($60),y
    iny
    bne !write_pg-

    inc $61
    dex
    bne copy_loop

#if BOOT_DIAG
    // Verify destination signature byte in Bank 0 after copy
    lda $1c0e
    sta BOOT_DIAG_SIG_BASE + 5
    cmp BOOT_DIAG_SIG_BASE + 4
    beq !diag_ok+
    lda #$ee
    sta BOOT_DIAG_SIG_BASE + 6
!diag_fail:
    jmp !diag_fail-
!diag_ok:
    lda #$aa
    sta BOOT_DIAG_SIG_BASE + 6
#endif

    // Restore operational bank (ROMs visible)
    lda #MMU_NORMAL
    sta $ff00
    lda #BANK_ALL_ROM
    sta $01
    
    // Jump to real entry point, skipping redundant relocation
    jmp $1c0e               // Skip to robust init
stub_end:
}
