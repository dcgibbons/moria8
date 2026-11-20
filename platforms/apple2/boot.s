// boot.s — MORIA8.SYSTEM: ProDOS 8 SYS bootstrap for moria8 (Apple IIe)
//
// ProDOS loads this file at $2000 and jumps to it. The resident payload
// spans $0A00-$7BFF, which covers $2000, so the loader first relocates
// itself to $A600-$A9FF above HDR ($A400-$A5FF) and below the 4 KB
// compressed read buffer ($AA00-$B9FF).
//
// Boot payload container (docs/APPLE2_MEMORY_POLICY.md boot file list):
//   MORIA8.PAK — one OPEN, one sequential pass:
//     header (512 B): count byte, pad, then count 16-bit compressed lengths
//     boot prefix entries (in table order, raw LZ4 block compressed):
//     RES, UI, ITEMS, SPELL, MODAL, HUFFDATA.
//   Relocated to $A600-$A9FF with a 4 KB read stream buffer at $AA00-$B9FF
//   so MORIA8.RES ($0A00-$7BFF) and STAGE ($7C00-$A3FF) unpack without overlap.
//   A single open sequential read keeps the drive stepping forward; the
//   previous per-file OPEN/GFI/READ/CLOSE cycle seek-thrashed the directory
//   and ProDOS 2.4.3's driver could lose the head after several files.
//   PackBits boot data (A2.AUXDATA, A2.CATALOG, A2.CATEXT) + ITEM.CAT are
//   unpacked/preloaded by TitleOverlay:a2_boot_preload_aux_lc; cold overlays,
//   A2.PLAY, LEGALUI, and TITLE are loaded on demand via MLI_SET_MARK ($CE).
//
// Assembled standalone (no core imports); Kick emits a PRG with the $2000
// header, tools/prg_to_bin.py strips it and AppleCommander inserts it as
// type SYS auxtype $2000.
//
// Progress display: the text page ($0400-$07FF) is untouched by the whole
// boot flow (RES lands at $0A00+, staging at $7C00/$A400/$BB00), so a
// "MORIA8 LOADING n/8" line at row 11 persists from OPEN to the final
// CLOSE. 40-col and 80-col (80STORE) displays are both supported; the
// resident payload reinitializes the screen right after the handoff.

.pc = $2000 "Boot"

.const MLI          = $bf00
.const MLI_OPEN     = $c8
.const MLI_READ     = $ca
.const MLI_CLOSE    = $cc
.const MLI_QUIT     = $29
.const IO_BUFFER    = $bb00   // 1,024-byte page-aligned MLI I/O buffer
                             // ($bc00+ would hit the $bf00 global page)
.const STAGE        = $7c00   // staged-entry buffer (play slot; free until
                             // the game loads A2.PLAY).
.const HDR          = $a400   // pak header staging (512 B at $A400-$A5FF)
.const LOADER_DEST  = $a600   // relocated loader ($A600-$A9FF, 1,024 B)
.const STREAM_BUF   = $aa00   // LZ4 compressed read window ($AA00-$B9FF)
.const STREAM_CAP   = $1000   // 4,096-byte chunks (< $BB00 IO_BUFFER)
.const PAK_COUNT    = 6       // sequential boot entries in MORIA8.PAK (see file_table)
.const BOOT_ROW     = $05a8   // text row 11 half-row base (progress line)
.const BOOT_LINE_DIGIT = 21   // offset of the count digit in boot_line
.const RELOC_SRC    = $f0     // ZP copy pointer during boot relocation (< $F4)
.const RELOC_DST    = $f2
#import "cache_layout.s"

boot_start:
    // Relocate 4 pages ($400 B) to $A600-$A9FF above HDR ($A400-$A5FF) and
    // below STREAM_BUF ($AA00-$B9FF) before any RAM at $0A00+ is written.
    lda #<loader_src
    sta RELOC_SRC
    lda #>loader_src
    sta RELOC_SRC + 1
    lda #<LOADER_DEST
    sta RELOC_DST
    lda #>LOADER_DEST
    sta RELOC_DST + 1
    ldx #4
    ldy #0
!cp:
    lda (RELOC_SRC),y
    sta (RELOC_DST),y
    iny
    bne !cp-
    inc RELOC_SRC + 1
    inc RELOC_DST + 1
    dex
    bne !cp-
    jmp LOADER_DEST

loader_src:
.pseudopc LOADER_DEST {
.const ZP_BUF_REM   = $f0
.const ZP_FILE_REM  = $f2
.const ZP_LEN       = $f4
.const ZP_BUF       = $f6
.const ZP_SRC       = $f8
.const ZP_MAT       = $fa
.const ZP_DST       = $fc

loader:
    // ---- Progress display: mode detect, clear, initial line ----
    lda $c01f               // RD80COL: bit 7 = 80STORE on
    and #$80
    sta mode80
    jsr boot_fill_half      // main half (RAMWRT off)
    sta $c005               // RAMWRT on -> aux half
    jsr boot_fill_half
    sta $c004               // RAMWRT off
    jsr boot_draw_line

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
    lda HDR                 // entry-count sanity check (>= boot prefix count)
    cmp #PAK_COUNT
    bcs !count_ok+
    lda #$f1                // pak/header mismatch
    jmp boot_error
!count_ok:

    ldx #0                  // entry index
!entry_loop:
    stx file_idx
    // ---- per-entry compressed length from header ($a402 + i*2) ----
    txa
    asl
    tay
    lda HDR + 2,y
    sta ZP_FILE_REM
    lda HDR + 3,y
    sta ZP_FILE_REM + 1
    lda #0
    sta ZP_BUF_REM
    sta ZP_BUF_REM + 1

    // ---- dest from the compile-time table ----
    txa
    asl
    asl
    tay
    lda file_table + 0,y
    sta ZP_DST
    lda file_table + 1,y
    sta ZP_DST + 1

#if A2_DEBUG_BOOTDIAG
    // Diagnostic: compressed entry length hi at text row 1
    lda file_idx
    lsr
    tay
    lda ZP_FILE_REM + 1
    sta $0480,y
#endif

    // ---- Stream and LZ4-unpack this entry sequentially ----
    jsr lz4_unpack_entry

    // ---- Compute exact uncompressed size copy_len = ZP_DST - dest ----
    ldx file_idx
    txa
    asl
    asl
    tay
    sec
    lda ZP_DST
    sbc file_table + 0,y
    sta copy_len
    lda ZP_DST + 1
    sbc file_table + 1,y
    sta copy_len + 1

    // ---- aux copy, if this entry has an aux destination ----
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
    inc boot_line + BOOT_LINE_DIGIT
    jsr boot_draw_line
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

// ---- Streaming raw LZ4-block decompressor ----
lz4_unpack_entry:
!seq:
    jsr stream_get_byte
    sta lz4_token
    lsr
    lsr
    lsr
    lsr
    jsr lz4_read_ext_len
!lit_loop:
    lda ZP_LEN
    ora ZP_LEN + 1
    beq !lit_done+
    jsr stream_get_byte
    jsr lz4_put_byte
    jsr lz4_dec_len
    jmp !lit_loop-
!lit_done:
    // Stream terminates cleanly at the end of the final literal run.
    lda ZP_FILE_REM
    ora ZP_FILE_REM + 1
    ora ZP_BUF_REM
    ora ZP_BUF_REM + 1
    bne !has_match+
    rts
!has_match:
    jsr stream_get_byte
    sta lz4_off_lo
    jsr stream_get_byte
    sta lz4_off_hi
    ora lz4_off_lo
    bne !off_ok+
    lda #$f2
    jmp boot_error
!off_ok:
    sec
    lda ZP_DST
    sbc lz4_off_lo
    sta ZP_MAT
    lda ZP_DST + 1
    sbc lz4_off_hi
    sta ZP_MAT + 1

    lda lz4_token
    and #$0f
    jsr lz4_read_ext_len
    clc
    lda ZP_LEN
    adc #4
    sta ZP_LEN
    bcc !mat_loop+
    inc ZP_LEN + 1
!mat_loop:
    ldy #0
    lda (ZP_MAT),y
    inc ZP_MAT
    bne !+
    inc ZP_MAT + 1
!:  jsr lz4_put_byte
    jsr lz4_dec_len
    lda ZP_LEN
    ora ZP_LEN + 1
    bne !mat_loop-
    jmp !seq-

lz4_read_ext_len:
    sta ZP_LEN
    lda #0
    sta ZP_LEN + 1
    lda ZP_LEN
    cmp #15
    bne !ext_done+
!ext_loop:
    jsr stream_get_byte
    pha
    clc
    adc ZP_LEN
    sta ZP_LEN
    bcc !+
    inc ZP_LEN + 1
!:  pla
    cmp #$ff
    beq !ext_loop-
!ext_done:
    rts

lz4_dec_len:
    lda ZP_LEN
    bne !+
    dec ZP_LEN + 1
!:  dec ZP_LEN
    rts

lz4_put_byte:
    ldy #0
    sta (ZP_DST),y
    inc ZP_DST
    bne !+
    inc ZP_DST + 1
!:  rts

stream_get_byte:
    lda ZP_BUF_REM
    ora ZP_BUF_REM + 1
    bne !have_byte+
    jsr stream_refill
!have_byte:
    ldy #0
    lda (ZP_BUF),y
    pha
    inc ZP_BUF
    bne !+
    inc ZP_BUF + 1
!:  lda ZP_BUF_REM
    bne !+
    dec ZP_BUF_REM + 1
!:  dec ZP_BUF_REM
    pla
    rts

stream_refill:
    lda ZP_FILE_REM
    ora ZP_FILE_REM + 1
    bne !nonempty+
    lda #$f3
    jmp boot_error
!nonempty:
    lda ZP_FILE_REM + 1
    cmp #>STREAM_CAP
    bcs !full_cap+
    lda ZP_FILE_REM
    sta read_req
    lda ZP_FILE_REM + 1
    sta read_req + 1
    lda #0
    sta ZP_FILE_REM
    sta ZP_FILE_REM + 1
    beq !do_read+
!full_cap:
    sec
    sbc #>STREAM_CAP
    sta ZP_FILE_REM + 1
    lda #<STREAM_CAP
    sta read_req
    lda #>STREAM_CAP
    sta read_req + 1
!do_read:
    lda #<STREAM_BUF
    sta read_buf
    sta ZP_BUF
    lda #>STREAM_BUF
    sta read_buf + 1
    sta ZP_BUF + 1
    jsr MLI
    .byte MLI_READ
    .word read_params
    bcc !chk_len+
    jmp boot_error
!chk_len:
    lda read_trans
    cmp read_req
    bne !short+
    lda read_trans + 1
    cmp read_req + 1
    bne !short+
    sta ZP_BUF_REM + 1
    lda read_trans
    sta ZP_BUF_REM
    rts
!short:
    lda #$f4
    jmp boot_error

// boot_fill_half — Fill one text half ($0400-$07FF) with spaces, 120
// bytes per 128-byte block so the firmware holes at $x78-$x7F are never
// touched. Clobbers A, X, Y, ZP_DST.
boot_fill_half:
    lda #<$0400
    sta ZP_DST
    lda #>$0400
    sta ZP_DST + 1
    ldx #8
!blk:
    lda #$a0
    ldy #$77
!l:
    sta (ZP_DST),y
    dey
    bpl !l-
    lda ZP_DST
    clc
    adc #$80
    sta ZP_DST
    bcc !n+
    inc ZP_DST + 1
!n:
    dex
    bne !blk-
    rts

// boot_draw_line — Draw boot_line at row 11. 80-col mode (80STORE on)
// interleaves even chars to the aux half and odd chars to the main half
// via PAGE2; 40-col writes the main half only. Clobbers A, X, Y.
boot_draw_line:
    lda mode80
    bne !l80+
    ldx #0
!l40:
    lda boot_line,x
    ora #$80
    sta BOOT_ROW,x
    inx
    cpx #40
    bne !l40-
    rts
!l80:
    sta $c055               // PAGE2 on -> aux half (80STORE on)
    ldy #0
    ldx #0
!ev:
    lda boot_line,x
    ora #$80
    sta BOOT_ROW,y
    inx
    inx
    iny
    cpy #20
    bne !ev-
    sta $c054               // PAGE2 off -> main half
    ldy #0
    ldx #1
!od:
    lda boot_line,x
    ora #$80
    sta BOOT_ROW,y
    inx
    inx
    iny
    cpy #20
    bne !od-
    rts

boot_line:
    .text "    MORIA8  LOADING  0/6  PLEASE WAIT   "
boot_line_end:

mode80:     .byte 0
file_idx:   .byte 0
copy_len:   .word 0
lz4_token:  .byte 0
lz4_off_lo: .byte 0
lz4_off_hi: .byte 0

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
    .word STAGE, A2_AUX_CACHE_UI
    .word STAGE, A2_AUX_CACHE_ITEMS
    .word STAGE, A2_AUX_CACHE_SPELL
    .word STAGE, A2_AUX_CACHE_MODAL
    .word STAGE, A2_AUX_CACHE_HUFF  // A2.HUFFDATA -> the corpus and the catalog's names
}
loader_end:

.assert "Loader fits $A600-$A9FF", loader_end - loader_src <= $400, true
.assert "Stream buffer stays below MLI I/O buffer", STREAM_BUF + STREAM_CAP <= IO_BUFFER, true
.assert "Boot image stays clear of ProDOS global page", * <= $bf00, true
.assert "Boot line is 40 chars", boot_line_end - boot_line, 40
.assert "Boot line digit in range", BOOT_LINE_DIGIT < 40, true
