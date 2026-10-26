// boot.s — MORIA8: Acorn DFS / MOS 3.20 bootstrap loader for BBC Master 128
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md & cache_layout.s.
// Loaded at $1900 by !BOOT (*OPT 4,3 -> *RUN MORIA8). Because MORIA8.RES spans
// $0E00-$7FFF (covering $1900), boot_start first relocates the loader to
// $0400-$05FF and jumps there.
//
// Opens MORIA8P (MORIA8.PAK) once and streams 10 entries sequentially:
//   0: MORIA8.RES    -> Main RAM $0E00
//   1: BEEB.PLAY     -> Sideways Bank 4 ($04) $8000
//   2: BEEB.HUFFDATA -> Private RAM ANDY ($84) $8000
//   3: BEEB.AUXDATA  -> Sideways Bank 6 ($06) $8000
//   4: OVL.UI        -> Sideways Bank 5 ($05) $B400
//   5: OVL.TOWN      -> Sideways Bank 6 ($06) $9700
//   6: OVL.MODAL     -> Sideways Bank 6 ($06) $AD00
//   7: OVL.SPELL     -> Sideways Bank 7 ($07) $8000
//   8: OVL.ITEMS     -> Sideways Bank 7 ($07) $9500
//   9: OVL.GEN       -> Sideways Bank 7 ($07) $AA00
// MONSTER.DB1 is no longer cached: tier 1 grew past bank 6's free pages
// (30 creatures added, 2026-10-25) and loads from DFS like tiers 2-4.

.cpu _65c02
.pc = $1900 "Boot"

#import "cache_layout.s"

.const MOS_OSFIND      = $ffce
.const MOS_OSGBPB      = $ffd1
.const MOS_OSWRCH      = $ffee
.const SHEILA_ROMSEL   = $fe30
.const SHEILA_ACCCON   = $fe34
.const ZP_MOS_ROMSEL   = $f4

.const LOADER_DEST     = $0400
.const HDR_BUF         = $0600
.const GBPB_CTRL       = $0680
.const BOUNCE_BUF      = $0700
.const PAK_COUNT       = 10

boot_start:
    cld
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
.const ZP_DST = $70
.const ZP_REM = $72

loader:
    // Save filing-system ROMSEL shadow ($00F4)
    lda ZP_MOS_ROMSEL
    sta mos_romsel

    // Switch MOS to Shadow Mode 7 (VDU 22, 135) so "MORIA8 LOADING..." is
    // displayed in LYNNE ($7C00-$7FFF) while OSGBPB loads MORIA8.RES into
    // Main RAM ($0E00-$7FFF) without corrupting the visible Mode 7 screen.
    lda #22
    jsr MOS_OSWRCH
    lda #135
    jsr MOS_OSWRCH

    // Print "MORIA8 LOADING..." into LYNNE Mode 7 screen
    ldx #0
!msg_loop:
    lda boot_msg,x
    beq !msg_done+
    jsr MOS_OSWRCH
    inx
    bne !msg_loop-
!msg_done:

    // Keep LYNNE displayed (D=1) while forcing all CPU/MOS accesses to Main RAM (E=0, X=0)
    lda #$01
    sta SHEILA_ACCCON

    // Open MORIA8P for input (OSFIND A=$40)
    lda #$40
    ldx #<pak_name
    ldy #>pak_name
    jsr MOS_OSFIND
    cmp #$00
    bne !opened+
    jmp boot_error
!opened:
    sta pak_handle

    // Read first 256 bytes of 512-byte header into HDR_BUF ($0600)
    lda #<HDR_BUF
    ldx #>HDR_BUF
    ldy #$01                // 1 page (256 B)
    jsr read_pages_main

    // Read second 256 bytes of 512-byte header into BOUNCE_BUF ($0700)
    lda #<BOUNCE_BUF
    ldx #>BOUNCE_BUF
    ldy #$01                // 1 page (256 B)
    jsr read_pages_main

    lda HDR_BUF
    cmp #PAK_COUNT
    beq !count_ok+
    jmp boot_error
!count_ok:

    ldx #0
!entry_loop:
    stx file_idx
    // Note: Do NOT call MOS_OSWRCH after Entry 0 (MORIA8.RES) loads into
    // $0E00-$7FFF, because MOS starts in Mode 7 where screen memory is at
    // $7C00-$7FFF in Main RAM and OSWRCH would overwrite resident code at $7Dxx!

    // Fetch 16-bit entry length from HDR_BUF + 2 + i*2
    lda file_idx
    asl
    tay
    lda HDR_BUF + 2,y
    sta ZP_REM
    lda HDR_BUF + 3,y
    sta ZP_REM + 1

    // Fetch destination bank and high byte from file_table
    ldx file_idx
    lda file_bank_table,x
    sta cur_bank
    lda #$00
    sta ZP_DST
    lda file_hi_table,x
    sta ZP_DST + 1

    lda cur_bank
    bne !banked_entry+

    // Entry 0 (MORIA8.RES -> Main RAM $0E00): single sequential OSGBPB read
    jsr setup_gbpb_ctrl
    lda ZP_DST
    sta GBPB_CTRL + 1
    lda ZP_DST + 1
    sta GBPB_CTRL + 2
    lda ZP_REM
    sta GBPB_CTRL + 5
    lda ZP_REM + 1
    sta GBPB_CTRL + 6
    lda #$04
    ldx #<GBPB_CTRL
    ldy #>GBPB_CTRL
    jsr MOS_OSGBPB
    jmp !next_entry+

!banked_entry:
    // Stream in 256-byte (or tail) chunks via BOUNCE_BUF ($0700)
!chunk_loop:
    lda ZP_REM
    ora ZP_REM + 1
    beq !next_entry+

    jsr setup_gbpb_ctrl
    lda #<BOUNCE_BUF
    sta GBPB_CTRL + 1
    lda #>BOUNCE_BUF
    sta GBPB_CTRL + 2

    lda ZP_REM + 1
    bne !full_page+
    // Final partial page (< 256 bytes)
    lda ZP_REM
    sta GBPB_CTRL + 5
    sta chunk_bytes
    lda #$00
    sta GBPB_CTRL + 6
    sta ZP_REM
    jmp !do_read+

!full_page:
    lda #$00
    sta GBPB_CTRL + 5
    sta chunk_bytes         // 0 = 256 bytes
    lda #$01
    sta GBPB_CTRL + 6
    dec ZP_REM + 1

!do_read:
    lda #$04
    ldx #<GBPB_CTRL
    ldy #>GBPB_CTRL
    jsr MOS_OSGBPB

    // Copy chunk_bytes (0 = 256) from BOUNCE_BUF to cur_bank:(ZP_DST)
    sei
    lda cur_bank
    sta ZP_MOS_ROMSEL
    sta SHEILA_ROMSEL
    ldx chunk_bytes
    ldy #0
!copy_byte:
    lda BOUNCE_BUF,y
    sta (ZP_DST),y
    iny
    dex
    bne !copy_byte-
    lda mos_romsel
    sta ZP_MOS_ROMSEL
    sta SHEILA_ROMSEL
    cli

    inc ZP_DST + 1
    jmp !chunk_loop-

!next_entry:
    ldx file_idx
    inx
    cpx #PAK_COUNT
    bcs !all_entries_done+
    jmp !entry_loop-
!all_entries_done:

    // Close MORIA8P
    lda #$00
    ldy pak_handle
    jsr MOS_OSFIND

    // Restore filing-system ROMSEL in $00F4 so hal_platform_init_early can save it
    lda mos_romsel
    sta ZP_MOS_ROMSEL
    sta SHEILA_ROMSEL

    // Jump to resident entry_bootstrap at $0E00
    jmp $0e00

boot_error:
    lda #'!'
    jsr MOS_OSWRCH
!halt:
    jmp !halt-

// read_pages_main — Read Y pages into Main RAM at X:A
read_pages_main:
    pha
    txa
    pha
    tya
    pha
    jsr setup_gbpb_ctrl
    pla
    sta GBPB_CTRL + 6       // hi byte of count (pages)
    pla
    sta GBPB_CTRL + 2       // hi byte of buffer
    pla
    sta GBPB_CTRL + 1       // lo byte of buffer
    lda #$04
    ldx #<GBPB_CTRL
    ldy #>GBPB_CTRL
    jmp MOS_OSGBPB

setup_gbpb_ctrl:
    ldx #12
    lda #0
!z:
    sta GBPB_CTRL,x
    dex
    bpl !z-
    lda pak_handle
    sta GBPB_CTRL + 0
    lda #$ff
    sta GBPB_CTRL + 3
    sta GBPB_CTRL + 4
    rts

mos_romsel:  .byte 0
pak_handle:  .byte 0
file_idx:    .byte 0
cur_bank:    .byte 0
chunk_bytes: .byte 0

boot_msg:
    .text "MORIA8 LOADING..."
    .byte 0

pak_name:
    .text "MORIA8P"
    .byte $0d

// 10 entries in MORIA8P order:
//   0: MORIA8.RES    ($00, $0E00)
//   1: BEEB.PLAY     ($04, $8000)
//   2: BEEB.HUFFDATA ($84, $8000)
//   3: BEEB.AUXDATA  ($06, $8000)
//   4: OVL.UI        ($05, $B400)
//   5: OVL.TOWN      ($06, $9700)
//   6: OVL.MODAL     ($06, $AD00)
//   8: OVL.SPELL     ($07, $8000)
//   9: OVL.ITEMS     ($07, $9500)
//  10: OVL.GEN       ($07, $AA00)
file_bank_table:
    .byte $00
    .byte $04
    .byte $84
    .byte $06
    .byte BEEB_SWR_BANK_UI
    .byte BEEB_SWR_BANK_TOWN
    .byte BEEB_SWR_BANK_MODAL
    .byte BEEB_SWR_BANK_SPELL
    .byte BEEB_SWR_BANK_ITEMS
    .byte BEEB_SWR_BANK_GEN

file_hi_table:
    .byte $0e
    .byte $80
    .byte $80
    .byte $80
    .byte >BEEB_SWR_ADDR_UI
    .byte >BEEB_SWR_ADDR_TOWN
    .byte >BEEB_SWR_ADDR_MODAL
    .byte >BEEB_SWR_ADDR_SPELL
    .byte >BEEB_SWR_ADDR_ITEMS
    .byte >BEEB_SWR_ADDR_GEN
}
loader_end:

.assert "Loader fits $0400-$05FF", loader_end - loader_src <= 512, true
.assert "Loader tail copy is 8-bit", loader_end - (loader_src + $100) <= 255, true
