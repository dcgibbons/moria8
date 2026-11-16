// boot.s — Atari 8-bit 3-sector DOS 2.5 boot loader ($0800-$097F, 384 bytes).
//
// Loaded by Atari OS ROM from Sectors 1..3 into $0800-$097F (inside SCREEN_RAM
// $0800-$0BFF while ANTIC still displays the OS boot screen).
// Disables BASIC ROM ($A000-$BFFF) via PORTB = $FF, locates MORIA8.RES in the
// DOS 2.5 directory (Sectors 361..368), streams & PackBits-unpacks its sector
// chain via OS SIOV ($E459) into $0C00-$C0FF (switching PORTB = $FE before
// $BF00-$C0FF writes so RAM under OS ROM receives every byte), and jumps to
// $0C00 (entry_main).

#import "memory.s"

.const BOOT_STAGE_BUF = $0980
.const ENTRY_MAIN     = $0c00

.pc = $0800 "Atari Boot Sectors 1..3"

boot_header:
    .byte $00               // +0: Boot flags (unused)
    .byte $03               // +1: Boot sector count (3 sectors = 384 bytes)
    .word boot_header       // +2: Load address ($0800)
    .word boot_entry        // +4: Init address ($0806)

boot_entry:
    sei
    cld
    ldx #$ff
    txs                     // Discard OS JSR return address

    // Disable BASIC ROM ($A000-$BFFF) while keeping OS ROM ($E459) visible
    stx PORTB               // X = $FF = PORTB_OS_ROM
    lda #$01
    sta OS_CRITIC           // Inhibit OS Stage 2 VBI during boot I/O
    sta atari_io_sec_hi     // >361 = $01

    // Install centered black-screen Mode 6 loading banner & zero stream state
    lda #$00
    sta OS_COLOR4
    sta COLBK
    sta OS_SOUNDR
    sta atari_io_cnt
    sta atari_io_src
    lda #$0e
    sta OS_COLOR0
    sta COLPF0
    lda #<boot_dl
    sta OS_SDLSTL
    sta DLISTL
    lda #>boot_dl
    sta OS_SDLSTH
    sta DLISTH

    // Scan DOS 2.5 directory (Sectors 361..368 = $0169..$0170) for "MORIA8  RES"
    lda #<361
    sta atari_io_sec_lo

!dir_loop:
    jsr boot_read_sector

    ldx #0
!ent_loop:
    lda BOOT_STAGE_BUF,x
    beq boot_fatal
    bmi !ent_next+
    stx atari_io_flags
    ldy #0
!cmp_loop:
    lda BOOT_STAGE_BUF + 5,x
    cmp boot_res_name,y
    bne !cmp_miss+
    inx
    iny
    cpy #11
    bcc !cmp_loop-

    // Found MORIA8.RES (X = entry_off + 11, C = 1)! Extract starting sector
    lda BOOT_STAGE_BUF - 8,x
    sta atari_io_sec_lo
    lda BOOT_STAGE_BUF - 7,x
    sta atari_io_sec_hi
    bcs boot_load_resident

!cmp_miss:
    ldx atari_io_flags
!ent_next:
    txa
    clc
    adc #16
    tax
    bpl !ent_loop-

    inc atari_io_sec_lo
    lda atari_io_sec_lo
    cmp #<369
    bcc !dir_loop-
    bcs boot_fatal

boot_load_resident:
    jsr boot_next_byte
    sta atari_io_dst
    jsr boot_next_byte
    sta atari_io_dst_hi

!pb_pkt:
    jsr boot_next_byte          // A = PackBits header ($00..$7F lit, $81..$FF run, $80 EOF)
    cmp #$80
    beq boot_launch
    bcs !pb_run+
    tax
!pb_lit:
    jsr boot_next_byte
    jsr boot_put_byte
    dex
    bpl !pb_lit-
    bmi !pb_pkt-
!pb_run:
    tax                         // X = $81..$FF -> 1 + (256 - X) = 128..2 copies
    jsr boot_next_byte
    jsr boot_put_byte
!pb_fill:
    jsr boot_put_byte
    inx
    bne !pb_fill-
    beq !pb_pkt-

boot_put_byte:
    ldy atari_io_dst_hi
    cpy #$bf
    bcc !bpb_store+
    cpy #>MAP_BASE
    bcs boot_fatal
    jsr boot_game_ram
!bpb_store:
    ldy #0
    sta (atari_io_dst),y
    inc atari_io_dst
    bne !bpb_done+
    inc atari_io_dst_hi
!bpb_done:
    rts

boot_fatal:
    jmp boot_fatal

boot_next_byte:
    ldy atari_io_src
    cpy atari_io_cnt
    bcc !bnb_have+
    lda atari_io_sec_lo
    ora atari_io_sec_hi
    beq boot_fatal
    stx atari_io_slot
    jsr boot_read_sector
    ldx atari_io_slot
    lda BOOT_STAGE_BUF + 125
    beq boot_fatal
    sta atari_io_cnt
    lda BOOT_STAGE_BUF + 126
    and #$03
    sta atari_io_sec_hi
    lda BOOT_STAGE_BUF + 127
    sta atari_io_sec_lo
    ldy #0
!bnb_have:
    lda BOOT_STAGE_BUF,y
    iny
    sty atari_io_src
    rts

boot_launch:
    jsr boot_game_ram
    jmp ENTRY_MAIN

boot_game_ram:
    ldy #$00
    sty NMIEN
    ldy #PORTB_GAME_RAM
    sty PORTB
    rts

// boot_read_sector — Read 128-byte sector atari_io_sec_lo/hi into BOOT_STAGE_BUF
boot_read_sector:
    lda boot_msg + 17
    eor #$0e
    sta boot_msg + 17

    lda #$00
    sta OS_POKMSK
    sta IRQEN
    lda #PORTB_OS_ROM
    sta PORTB
    sta OS_BRKKEY
    sta NMIRES
    lda #$40
    sta NMIEN

    ldx #9
!dcb_init:
    lda boot_dcb_tab,x
    sta DCB_DDEVIC,x
    dex
    bpl !dcb_init-

    lda atari_io_sec_lo
    sta DCB_DAUX1
    lda atari_io_sec_hi
    sta DCB_DAUX2
    cli
    jsr OS_SIOV
    sei
    dec DCB_DSTATS
    bne boot_fatal
    rts

boot_dcb_tab:
    .byte $31, $01, 'R', $40, <BOOT_STAGE_BUF, >BOOT_STAGE_BUF, $07, $00, 128, 0

boot_res_name:
    .byte 'M','O','R','I','A','8',' ',' ','R','E','S'

// Minimal Mode 6 Display List placing 20-col boot_msg at Row 12 on a black screen
boot_dl:
    .fill 14, $70                           // Top overscan + Rows 0..11
    .byte $46, <boot_msg, >boot_msg         // Row 12: 20-col Mode 6 banner
    .byte $41, <boot_dl, >boot_dl           // JVB

// 20-column Mode 6 banner in Atari internal screen codes: "  LOADING MORIA8... "
boot_msg:
    .byte $00, $00
    .byte $2c, $2f, $21, $24, $29, $2e, $27, $00
    .byte $2d, $2f, $32, $29, $21, $18, $0e, $0e, $0e, $00

.assert "boot.s fits in 3 sectors (384 bytes)", * <= $0980, true
.fill $0980 - *, 0
