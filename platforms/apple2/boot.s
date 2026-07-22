// boot.s — MORIA8.SYSTEM: ProDOS 8 SYS bootstrap for moria8 (Apple IIe)
//
// ProDOS loads this file at $2000 and jumps to it. The resident payload
// spans $0A00-$7BFF, which covers $2000, so the loader first relocates
// itself to $0800-$09FF (later reinitialized by core as the floor-item and
// creature tables — safe, they are written before first use).
//
// Boot payload container (docs/APPLE2_MEMORY_POLICY.md boot file list):
//   MORIA8.PAK — one OPEN, one sequential pass:
//     header (512 B): count byte, pad, then count 16-bit lengths
//     entries (in table order): RES, AUXDATA, TOWN, UI, ITEMS, SPELL, MODAL,
//     GEN
//   A single open sequential read keeps the drive stepping forward; the
//   previous per-file OPEN/GFI/READ/CLOSE cycle seek-thrashed the directory
//   and ProDOS 2.4.3's driver could lose the head after several files.
//   Cold payloads (A2.PLAY, OVL.START, OVL.DEATH, OVL.HELP,
//   OVL.STORAGE, OVL.TITLE, MONSTER.DB.1-4, TITLE) are loaded on demand.
//
// Assembled standalone (no core imports); Kick emits a PRG with the $2000
// header, tools/prg_to_bin.py strips it and AppleCommander inserts it as
// type SYS auxtype $2000.

.pc = $2000 "Boot"

.const MLI          = $bf00
.const MLI_OPEN     = $c8
.const MLI_READ     = $ca
.const MLI_CLOSE    = $cc
.const MLI_QUIT     = $29
.const IO_BUFFER    = $bb00   // 1,024-byte page-aligned MLI I/O buffer
                             // ($bc00+ would hit the $bf00 global page)
.const STAGE        = $7c00   // staged-entry buffer (play slot; free until
                             // the game loads A2.PLAY). Must stay below
                             // $bb00 by the largest staged entry.
.const HDR          = $a400   // pak header staging (window; free until the
                             // game runs); holds 512 B for the whole boot.
.const LOADER_DEST  = $0800
.const PAK_COUNT    = 8       // entries in MORIA8.PAK (see file_table)
#import "cache_layout.s"

boot_start:
    // Copy loader to $0800. Two stages because the size exceeds 255:
    // full first page, then the remainder (asserted <= 512 total).
    ldx #0
!c1:
    lda loader_src,x
    sta LOADER_DEST,x
    inx
    bne !c1-
!c2:
    lda loader_src + $100,x
    sta LOADER_DEST + $100,x
    inx
    cpx #loader_end - (loader_src + $100)
    bne !c2-
    jmp LOADER_DEST

loader_src:
.pseudopc LOADER_DEST {
.const ZP_SRC = $fa
.const ZP_DST = $fc

loader:
    // ---- OPEN MORIA8.PAK ----
    jsr MLI
    .byte MLI_OPEN
    .word open_params
    bcc !opened+
    jmp boot_error
!opened:
    lda open_ref
    sta read_ref

    // ---- READ the 512-byte header to HDR ----
    lda #<HDR
    sta read_buf
    lda #>HDR
    sta read_buf + 1
    lda #<512
    sta read_req
    lda #>512
    sta read_req + 1
    jsr MLI
    .byte MLI_READ
    .word read_params
    bcc !hdr_ok+
    jmp boot_error
!hdr_ok:
    lda HDR                 // entry-count sanity check
    cmp #PAK_COUNT
    beq !count_ok+
    lda #$f1                // pak/header mismatch
    jmp boot_error
!count_ok:

    ldx #0                  // entry index
!entry_loop:
    stx file_idx
    // ---- per-entry length from header ($a402 + i*2) ----
    txa
    asl
    tay
    lda HDR + 2,y
    sta read_req
    sta copy_len
    lda HDR + 3,y
    sta read_req + 1
    sta copy_len + 1

    // ---- dest from the compile-time table ----
    txa
    asl
    asl
    tay
    lda file_table + 0,y
    sta read_buf
    lda file_table + 1,y
    sta read_buf + 1

#if A2_DEBUG_BOOTDIAG
    // Diagnostic: per-entry length hi at text row 1, columns 0,4,8...
    lda file_idx
    lsr
    tay
    lda read_req + 1
    sta $0480,y
#endif

    // ---- READ this entry (sequential; position advances) ----
    jsr MLI
    .byte MLI_READ
    .word read_params
    bcc !read_ok+
    jmp boot_error
!read_ok:

    // ---- aux copy, if this entry has an aux destination ----
    ldx file_idx
    txa
    asl
    asl
    tay
    lda file_table + 3,y
    beq !next_entry+            // aux hi = 0 -> main-only
    sta ZP_DST + 1
    lda file_table + 2,y
    sta ZP_DST
    lda file_table + 0,y
    sta ZP_SRC
    lda file_table + 1,y
    sta ZP_SRC + 1
    // page count = ceil(length / 256)
    lda copy_len + 1
    ldx copy_len
    beq !pages_ready+
    clc
    adc #1                      // non-aligned tail still needs a page
!pages_ready:
    tax
    sta $c005                   // RAMWRT on (writes go to aux)
    ldy #0
!page:
    lda (ZP_SRC),y
    sta (ZP_DST),y
    iny
    bne !page-
    inc ZP_SRC + 1
    inc ZP_DST + 1
    dex
    bne !page-
    sta $c004                   // RAMWRT off

!next_entry:
    ldx file_idx
    inx
    cpx #PAK_COUNT
    beq !all_done+
    jmp !entry_loop-
!all_done:

    // ---- CLOSE ----
    jsr MLI
    .byte MLI_CLOSE
    .word close_params
    bcc !closed+
    jmp boot_error
!closed:
    jmp $0a00                   // entry_main

boot_error:
    sta $0400                   // show MLI error code top-left
#if A2_DEBUG_BOOTDIAG
!halt:
    jmp !halt-                  // diag: jam with error on screen
#else
    jsr MLI
    .byte MLI_QUIT
    .word quit_params
!halt:
    jmp !halt-
#endif

file_idx:   .byte 0
copy_len:   .word 0

open_params:
    .byte 3
open_path:
    .word pak_name
    .word IO_BUFFER
open_ref:
    .byte 0

read_params:
    .byte 4
read_ref:
    .byte 0
read_buf:
    .word 0
read_req:
    .word 0
read_trans:
    .word 0

close_params:
    .byte 1
    .byte 0                   // ref 0 = close all

quit_params:
    .byte 4, 0, 0
    .word 0
    .byte 0
    .word 0

pak_name:
    .byte 10
    .text "MORIA8.PAK"

// Entry destinations, in pak order (lengths come from the pak header).
// Aux destinations use the shared cache manifest in cache_layout.s.
file_table:
    .word $0a00, $0000        // MORIA8.RES -> main resident
    .word STAGE, $3b0c        // A2.AUXDATA -> aux data region
    .word STAGE, A2_AUX_CACHE_TOWN
    .word STAGE, A2_AUX_CACHE_UI
    .word STAGE, A2_AUX_CACHE_ITEMS
    .word STAGE, A2_AUX_CACHE_SPELL
    .word STAGE, A2_AUX_CACHE_MODAL
    .word STAGE, A2_AUX_CACHE_GEN
}
loader_end:

.assert "Loader fits $0800-$09FF", loader_end - loader_src <= 512, true
.assert "Loader tail copy is 8-bit", loader_end - (loader_src + $100) <= 255, true
.assert "Boot image stays clear of ProDOS global page", * <= $bf00, true
