// boot.s — Atari 8-bit 3-sector DOS 2.5 boot loader ($0800-$097F, 384 bytes).
//
// Loaded by Atari OS ROM from Sectors 1..3 into $0800-$097F (inside SCREEN_RAM
// $0800-$0BFF while ANTIC still displays the OS boot screen).
// Disables BASIC ROM ($A000-$BFFF) via PORTB = $FF, locates MORIA8.RES in the
// DOS 2.5 directory (Sectors 361..368), streams its sector chain via OS SIOV
// ($E459) into $0C00-$C0FF (switching PORTB = $FE during memory copies so
// $C000-$C0FF writes reach RAM), and jumps to $0C00 (entry_main).

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
    lda #PORTB_OS_ROM
    sta PORTB
    lda #$01
    sta OS_CRITIC           // Inhibit OS Stage 2 VBI during boot I/O

    // Install centered black-screen Mode 6 loading banner
    lda #$00
    sta OS_COLOR2
    sta OS_COLOR4
    sta COLPF2
    sta COLBK
    lda #$0e
    sta OS_COLOR0
    sta COLPF0
    lda #<boot_dl
    sta OS_SDLSTL
    sta DLISTL
    lda #>boot_dl
    sta OS_SDLSTH
    sta DLISTH

    // Scan DOS 2.5 directory (Sectors 361..368) for "MORIA8  RES"
    lda #<361
    sta atari_io_sec_lo
    lda #>361
    sta atari_io_sec_hi

!dir_loop:
    jsr boot_read_sector
    bcs boot_fatal

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

    // Found MORIA8.RES! Extract starting sector
    ldx atari_io_flags
    lda BOOT_STAGE_BUF + 3,x
    sta atari_io_sec_lo
    lda BOOT_STAGE_BUF + 4,x
    sta atari_io_sec_hi
    jmp boot_load_resident

!cmp_miss:
    ldx atari_io_flags
!ent_next:
    txa
    clc
    adc #16
    tax
    bpl !ent_loop-

    inc atari_io_sec_lo
    bne !dir_chk+
    inc atari_io_sec_hi
!dir_chk:
    lda atari_io_sec_lo
    cmp #<369
    bcc !dir_loop-

boot_fatal:
    jmp boot_fatal

boot_load_resident:
    lda #1
    sta atari_io_flags      // 1 = first sector (strip 2-byte PRG header)

!sec_loop:
    lda atari_io_sec_lo
    ora atari_io_sec_hi
    beq boot_launch

    jsr boot_read_sector
    bcs boot_fatal

    lda BOOT_STAGE_BUF + 125
    sta atari_io_cnt
    ldx #0
    lda atari_io_flags
    beq !check_high_ram+
    lda #0
    sta atari_io_flags
    lda BOOT_STAGE_BUF
    sta atari_io_dst
    lda BOOT_STAGE_BUF + 1
    sta atari_io_dst_hi
    ldx #2

!check_high_ram:
    // Only bank out OS ROM ($C000-$CFFF) when copying near/into $C000-$C0FF
    lda atari_io_dst_hi
    cmp #$bf
    bcc !copy_payload+
    sei
    lda #$00
    sta NMIEN
    lda #PORTB_GAME_RAM
    sta PORTB

!copy_payload:
    ldy #0
!byte_loop:
    cpx atari_io_cnt
    bcs !next_link+
    lda BOOT_STAGE_BUF,x
    sta (atari_io_dst),y
    inx
    inc atari_io_dst
    bne !byte_loop-
    inc atari_io_dst_hi
    jmp !byte_loop-

!next_link:
    lda BOOT_STAGE_BUF + 126
    and #$03
    sta atari_io_sec_hi
    lda BOOT_STAGE_BUF + 127
    sta atari_io_sec_lo
    jmp !sec_loop-

boot_launch:
    sei
    lda #$00
    sta NMIEN
    lda #PORTB_GAME_RAM
    sta PORTB
    jmp ENTRY_MAIN

// boot_read_sector — Read 128-byte sector atari_io_sec_lo/hi into BOOT_STAGE_BUF
boot_read_sector:
    lda boot_msg + 17
    eor #$0e
    sta boot_msg + 17

    lda #$00
    sta OS_SOUNDR
    sta OS_POKMSK
    sta IRQEN
    lda #PORTB_OS_ROM
    sta PORTB
    sta NMIRES
    lda #$40
    sta NMIEN
    lda #$ff
    sta OS_BRKKEY

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
    lda DCB_DSTATS
    cmp #$01
    beq !ok+
    sec
    rts
!ok:
    clc
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
