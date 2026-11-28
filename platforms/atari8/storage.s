#importonce
// storage.s — Atari 8-bit ROM SIOV ($E459) sector loader, DOS 2.5 directory
// lookup, and 130XE extended RAM cache manager.
//
// Linked strictly below $4000 so EnterSio, ExitSio, hal_asset_load_prg_header,
// xe_detect, xe_cache_stash, and xe_cache_fetch never unmap their own code
// when switching PORTB ($D301) between $FE (Game RAM), $FF (OS ROM), and
// $E2/$E6/$EA/$EE (130XE extended RAM banks at $4000-$7FFF).

#import "memory.s"
#import "hal/storage.s"

// ============================================================
// State & Buffers (< $4000)
// ============================================================
sio_sector_buf:
    .fill 128, 0

.label atari_fn_83 = A8_FN83_BASE   // 11 bytes in PRNBUF (memory.s); every writer fills all 11

atari_io_device:    .byte 8
// In PRNBUF (memory.s), each written before it is read.
.label atari_dir_count_lo = A8_STORAGE_VARS_BASE
.label atari_dir_count_hi = A8_STORAGE_VARS_BASE + 1
.label xe_present         = A8_STORAGE_VARS_BASE + 2
.label xe_saved_main      = A8_STORAGE_VARS_BASE + 3
#if !ATARI8_CARTRIDGE
xe_slot_populated:
    .fill 18, 0

// ============================================================
// 130XE Page-Packed Bank Allocation & Slot Geometry (Slots 0..17)
// ============================================================
// Slots 0..9:   OVL.STA, OVL.TWN, OVL.DTH, OVL.GEN, OVL.HLP,
//               OVL.UI,  OVL.ITM, OVL.SPL, OVL.MDL, OVL.CHS  (page-ceil @ $E000)
// Slots 10..13, 15: MONSTER.CAT sector groups, staged at $E000
//               (monster_catalog_a8.s: 4x32 + 1x12 = 140 sectors @ 128 B = 70 pages)
// Slot 14:      TITLE.DAT                                     (3 pages @ $C100)
// Slots 16..17: OVL.HOM, OVL.STO                              (page-ceil @ $E000)
// Cold OVL.TTL (overlay 13) is uncached ($FF) on 130XE so 100% of gameplay
// overlays, MONSTER.CAT, and TITLE.DAT stay RAM-cached within 256/256 pages.
.const XE_SLOT0_PAGES  = 16   // OVL.STA
.const XE_SLOT1_PAGES  = 15   // OVL.TWN
.const XE_SLOT2_PAGES  = 14   // OVL.DTH
.const XE_SLOT3_PAGES  = 15   // OVL.GEN
.const XE_SLOT4_PAGES  = 15   // OVL.HLP
.const XE_SLOT5_PAGES  = 16   // OVL.UI
.const XE_SLOT6_PAGES  = 14   // OVL.ITM
.const XE_SLOT7_PAGES  = 16   // OVL.SPL
.const XE_SLOT8_PAGES  = 16   // OVL.MDL
.const XE_SLOT9_PAGES  = 16   // OVL.CHS
.const XE_SLOT10_PAGES = 16   // MONSTER.CAT sectors 0..31   (4,096 B)
.const XE_SLOT11_PAGES = 16   // MONSTER.CAT sectors 32..63  (4,096 B)
.const XE_SLOT12_PAGES = 16   // MONSTER.CAT sectors 64..95  (4,096 B)
.const XE_SLOT13_PAGES = 16   // MONSTER.CAT sectors 96..127 (4,096 B)
.const XE_SLOT14_PAGES = 3    // TITLE.DAT (621 B)
.const XE_SLOT15_PAGES = 6    // MONSTER.CAT sectors 128..139 (1,536 B)
.const XE_SLOT16_PAGES = 16   // OVL.HOM
.const XE_SLOT17_PAGES = 14   // OVL.STO

// Bank 0 ($E2, $4000-$7FFF): Slots 0, 5, 9, 10 (64/64 pages)
.const XE_SLOT0_WIN_HI     = XE_WIN_BASE_HI
.const XE_SLOT5_WIN_HI     = XE_SLOT0_WIN_HI + XE_SLOT0_PAGES
.const XE_SLOT9_WIN_HI     = XE_SLOT5_WIN_HI + XE_SLOT5_PAGES
.const XE_SLOT10_WIN_HI    = XE_SLOT9_WIN_HI + XE_SLOT9_PAGES
.const XE_BANK0_FREE_HI    = XE_SLOT10_WIN_HI + XE_SLOT10_PAGES
.const XE_BANK0_USED_PAGES = XE_BANK0_FREE_HI - XE_WIN_BASE_HI
.const XE_BANK0_FREE_PAGES = XE_WIN_LIMIT_HI - XE_BANK0_FREE_HI

// Bank 1 ($E6, $4000-$7FFF): Slots 11, 12, 13, 16 (64/64 pages)
.const XE_SLOT11_WIN_HI    = XE_WIN_BASE_HI
.const XE_SLOT12_WIN_HI    = XE_SLOT11_WIN_HI + XE_SLOT11_PAGES
.const XE_SLOT13_WIN_HI    = XE_SLOT12_WIN_HI + XE_SLOT12_PAGES
.const XE_SLOT16_WIN_HI    = XE_SLOT13_WIN_HI + XE_SLOT13_PAGES
.const XE_BANK1_FREE_HI    = XE_SLOT16_WIN_HI + XE_SLOT16_PAGES
.const XE_BANK1_USED_PAGES = XE_BANK1_FREE_HI - XE_WIN_BASE_HI
.const XE_BANK1_FREE_PAGES = XE_WIN_LIMIT_HI - XE_BANK1_FREE_HI

// Bank 2 ($EA, $4000-$7FFF): Slots 1, 3, 7, 4, 14 (64/64 pages)
.const XE_SLOT1_WIN_HI     = XE_WIN_BASE_HI
.const XE_SLOT3_WIN_HI     = XE_SLOT1_WIN_HI + XE_SLOT1_PAGES
.const XE_SLOT7_WIN_HI     = XE_SLOT3_WIN_HI + XE_SLOT3_PAGES
.const XE_SLOT4_WIN_HI     = XE_SLOT7_WIN_HI + XE_SLOT7_PAGES
.const XE_SLOT14_WIN_HI    = XE_SLOT4_WIN_HI + XE_SLOT4_PAGES
.const XE_BANK2_FREE_HI    = XE_SLOT14_WIN_HI + XE_SLOT14_PAGES
.const XE_BANK2_USED_PAGES = XE_BANK2_FREE_HI - XE_WIN_BASE_HI
.const XE_BANK2_FREE_PAGES = XE_WIN_LIMIT_HI - XE_BANK2_FREE_HI

// Bank 3 ($EE, $4000-$7FFF): Slots 2, 17, 6, 8, 15 (64/64 pages)
.const XE_SLOT2_WIN_HI     = XE_WIN_BASE_HI
.const XE_SLOT17_WIN_HI    = XE_SLOT2_WIN_HI + XE_SLOT2_PAGES
.const XE_SLOT6_WIN_HI     = XE_SLOT17_WIN_HI + XE_SLOT17_PAGES
.const XE_SLOT8_WIN_HI     = XE_SLOT6_WIN_HI + XE_SLOT6_PAGES
.const XE_SLOT15_WIN_HI    = XE_SLOT8_WIN_HI + XE_SLOT8_PAGES
.const XE_BANK3_FREE_HI    = XE_SLOT15_WIN_HI + XE_SLOT15_PAGES
.const XE_BANK3_USED_PAGES = XE_BANK3_FREE_HI - XE_WIN_BASE_HI
.const XE_BANK3_FREE_PAGES = XE_WIN_LIMIT_HI - XE_BANK3_FREE_HI

.const XE_TOTAL_USED_PAGES = XE_BANK0_USED_PAGES + XE_BANK1_USED_PAGES + XE_BANK2_USED_PAGES + XE_BANK3_USED_PAGES
.const XE_TOTAL_FREE_PAGES = XE_BANK0_FREE_PAGES + XE_BANK1_FREE_PAGES + XE_BANK2_FREE_PAGES + XE_BANK3_FREE_PAGES

xe_slot_portb:
    .byte PORTB_XE_BANK0, PORTB_XE_BANK2, PORTB_XE_BANK3, PORTB_XE_BANK2
    .byte PORTB_XE_BANK2, PORTB_XE_BANK0, PORTB_XE_BANK3, PORTB_XE_BANK2
    .byte PORTB_XE_BANK3, PORTB_XE_BANK0, PORTB_XE_BANK0, PORTB_XE_BANK1
    .byte PORTB_XE_BANK1, PORTB_XE_BANK1, PORTB_XE_BANK2, PORTB_XE_BANK3
    .byte PORTB_XE_BANK1, PORTB_XE_BANK3

xe_slot_win_hi:
    .byte XE_SLOT0_WIN_HI,  XE_SLOT1_WIN_HI,  XE_SLOT2_WIN_HI,  XE_SLOT3_WIN_HI
    .byte XE_SLOT4_WIN_HI,  XE_SLOT5_WIN_HI,  XE_SLOT6_WIN_HI,  XE_SLOT7_WIN_HI
    .byte XE_SLOT8_WIN_HI,  XE_SLOT9_WIN_HI,  XE_SLOT10_WIN_HI, XE_SLOT11_WIN_HI
    .byte XE_SLOT12_WIN_HI, XE_SLOT13_WIN_HI, XE_SLOT14_WIN_HI, XE_SLOT15_WIN_HI
    .byte XE_SLOT16_WIN_HI, XE_SLOT17_WIN_HI

xe_slot_ram_hi:
    .byte >BANKED_DATA_BASE, >BANKED_DATA_BASE, >BANKED_DATA_BASE, >BANKED_DATA_BASE
    .byte >BANKED_DATA_BASE, >BANKED_DATA_BASE, >BANKED_DATA_BASE, >BANKED_DATA_BASE
    .byte >BANKED_DATA_BASE, >BANKED_DATA_BASE, >BANKED_DATA_BASE, >BANKED_DATA_BASE
    .byte >BANKED_DATA_BASE, >BANKED_DATA_BASE
    .byte >MAP_BASE
    .byte >BANKED_DATA_BASE
    .byte >BANKED_DATA_BASE, >BANKED_DATA_BASE

xe_slot_pages:
    .byte XE_SLOT0_PAGES,  XE_SLOT1_PAGES,  XE_SLOT2_PAGES,  XE_SLOT3_PAGES
    .byte XE_SLOT4_PAGES,  XE_SLOT5_PAGES,  XE_SLOT6_PAGES,  XE_SLOT7_PAGES
    .byte XE_SLOT8_PAGES,  XE_SLOT9_PAGES,  XE_SLOT10_PAGES, XE_SLOT11_PAGES
    .byte XE_SLOT12_PAGES, XE_SLOT13_PAGES, XE_SLOT14_PAGES, XE_SLOT15_PAGES
    .byte XE_SLOT16_PAGES, XE_SLOT17_PAGES

// 3-char overlay extension lookup table for OVL.* (overlays 0..12)
atari_ovl_ext_c0:
    .byte 'S', 'T', 'D', 'G', 'H', 'U', 'I', 'S', 'M', 'C', 'H', 'S', 'T'
atari_ovl_ext_c1:
    .byte 'T', 'W', 'T', 'E', 'L', 'I', 'T', 'P', 'D', 'H', 'O', 'T', 'T'
atari_ovl_ext_c2:
    .byte 'A', 'N', 'H', 'N', 'P', ' ', 'M', 'L', 'L', 'S', 'M', 'O', 'L'
atari_ovl_xe_slot:
    .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 16, 17, $ff
#endif

// ============================================================
// EnterSio & ExitSio — Mandatory Atari OS ROM SIOV ($E459) Wrapper
// ============================================================
// Caller populates DCB_DCOMND, DCB_DSTATS, DCB_DBUFLO/HI, DCB_DBYTLO/HI,
// DCB_DAUX1/2, and atari_io_device (8..11) before calling EnterSio.
EnterSio:
    php
    pla
    and #$04
    sta atari_io_irq_p
    sei
    lda #$00
    sta NMIEN

    // Save shared core ZP ($02-$8F) to zp_save_buf ($DD40) while PORTB = $FE
    jsr save_zp

    // Initialize OS ZP and DCB fields required by SIOV
    lda #$00
    sta OS_WARMST           // $08 = $00 (SYSTEM RESET -> clean coldstart)
    sta OS_POKMSK           // $10 = $00 (no stray timer/keyboard IRQs)
    sta IRQEN               // Disable POKEY IRQs before CLI; SIOV enables serial IRQs
    sta OS_SOUNDR           // $41 = $00 (silence noisy SIO sector beeps)
    sta OS_ATRACT           // $4D = $00 (no attract-mode color cycling)
    lda #$ff
    sta OS_BRKKEY           // $11 = $FF ($00 would abort SIOV with Error $80!)
    lda #$01
    sta OS_CRITIC           // $42 = $01 (inhibit OS Stage 2 VBI during SIOV)

    lda #$31
    sta DCB_DDEVIC
    lda atari_io_device
    sec
    sbc #7
    sta DCB_DUNIT           // HAL 8..11 -> D1:..D4: (1..4)
    lda #$07
    sta DCB_DTIMLO          // 7-second SIO timeout (copied into CDTMV1)

    // Synchronize OS Page 2 display shadows
    lda #$22
    sta OS_SDMCTL
    lda #<ATARI_DISPLAY_LIST
    sta OS_SDLSTL
    lda #>ATARI_DISPLAY_LIST
    sta OS_SDLSTH
    lda #$00
    sta OS_GPRIOR
    sta OS_COLOR2
    sta OS_COLOR4
    lda #$0e
    sta OS_COLOR1
    lda #2
    sta OS_CHACT
    lda #>ATARI_CHARSET_BASE
    sta OS_CHBAS

    // Enable OS ROM ($FF), clear latched NMIs, enable VBI only ($40, DLI off)
    lda #PORTB_OS_ROM
    sta PORTB
    sta NMIRES
    lda #$40
    sta NMIEN

    cli
    jsr OS_SIOV
    sei
    rts

ExitSio:
    sei
    lda #$00
    sta NMIEN
    lda #PORTB_GAME_RAM
    sta PORTB

    // Restore shared core ZP ($02-$8F) from zp_save_buf ($DD40) while PORTB = $FE
    jsr restore_zp

    // Silence all 4 POKEY audio channels (clearing SIOV serial tones) and
    // re-enable POKEY keyboard scan + IRQ
    lda #$00
    sta AUDC1
    sta AUDC2
    sta AUDC3
    sta AUDC4
    sta AUDCTL
    lda #$03
    sta SKCTL
    lda #$00
    sta IRQEN
    lda #$c0
    sta IRQEN

    // Clear latched NMIs and re-enable DLI + VBI ($C0)
    sta NMIRES
    lda #$c0
    sta NMIEN

    // Restore caller I flag without touching Carry
    lda atari_io_irq_p
    bne !keep_sei+
    cli
!keep_sei:
    lda DCB_DSTATS
    cmp #$01
    beq !sio_ok+
    sec
    rts
!sio_ok:
    clc
    rts

#if !ATARI8_CARTRIDGE
// ============================================================
// 130XE Extended RAM Detection & Slot Copy (< $4000)
// ============================================================
xe_detect:
    php
    sei
    lda #$00
    sta NMIEN
    sta xe_present

    ldx #17
!clr_slots:
    sta xe_slot_populated,x
    dex
    bpl !clr_slots-

    // Save Main RAM byte at $4000 and write sentinel $5A
    lda #PORTB_GAME_RAM
    sta PORTB
    lda $4000
    sta xe_saved_main
    lda #$5a
    sta $4000

    // Tag extended banks 0..3 at $4000
    ldx #3
!tag_banks:
    lda xe_bank_table,x
    sta PORTB
    txa
    ora #$a0
    sta $4000
    dex
    bpl !tag_banks-

    // Verify Main RAM at $4000 was not overwritten by bank writes
    lda #PORTB_GAME_RAM
    sta PORTB
    lda $4000
    cmp #$5a
    bne !no_xe+

    // Verify all 4 extended banks retained distinct tags
    ldx #3
!verify_banks:
    lda xe_bank_table,x
    sta PORTB
    txa
    ora #$a0
    cmp $4000
    bne !no_xe+
    dex
    bpl !verify_banks-

    lda #1
    sta xe_present

!no_xe:
    lda #PORTB_GAME_RAM
    sta PORTB
    lda xe_saved_main
    sta $4000
    sta NMIRES
    lda #$c0
    sta NMIEN
    plp
    rts

xe_bank_table:
    .byte PORTB_XE_BANK0, PORTB_XE_BANK1, PORTB_XE_BANK2, PORTB_XE_BANK3

// xe_cache_stash — Copy slot X (0..17) from Main/High RAM to 130XE bank
xe_cache_stash:
    cpx #18
    bcs !done+
    lda xe_slot_ram_hi,x
    sta atari_io_src_hi
    lda xe_slot_win_hi,x
    sta atari_io_dst_hi
    lda xe_slot_portb,x
    sta xe_slot_populated,x
    jmp xe_cache_xfer
!done:
    rts

// xe_cache_fetch — Copy slot X (0..18) from 130XE bank to Main/High RAM
xe_cache_fetch:
    lda xe_slot_win_hi,x
    sta atari_io_src_hi
    lda xe_slot_ram_hi,x
    sta atari_io_dst_hi
xe_cache_xfer:
    php
    sei
    lda #$00
    sta NMIEN
    sta atari_io_src
    sta atari_io_dst
    lda xe_slot_pages,x
    sta atari_io_pages
    lda xe_slot_portb,x
    sta PORTB

    ldy #0
!page_loop:
    lda (atari_io_src),y
    sta (atari_io_dst),y
    iny
    bne !page_loop-
    inc atari_io_src_hi
    inc atari_io_dst_hi
    dec atari_io_pages
    bne !page_loop-

    lda #PORTB_GAME_RAM
    sta PORTB
    sta NMIRES
    lda #$c0
    sta NMIEN
    plp
    clc
    rts

// ============================================================
// Filename Formatting, Slot Matching, & DOS 2.5 Directory Lookup
// ============================================================

// atari_format_83 — Format string at (atari_io_src), len atari_io_cnt into atari_fn_83
atari_format_83:
    ldx #10
    lda #$20
!fill_sp:
    sta atari_fn_83,x
    dex
    bpl !fill_sp-

    ldy #0
    ldx #0
!fmt_loop:
    cpy atari_io_cnt
    bcs !fmt_done+
    lda (atari_io_src),y
    iny
    cmp #'.'
    bne !not_dot+
    ldx #8
    jmp !fmt_loop-
!not_dot:
    cpx #11
    bcs !fmt_done+
    sta atari_fn_83,x
    inx
    jmp !fmt_loop-
!fmt_done:
    rts

// atari_match_cache_slot — Map atari_fn_83 to 130XE slot 0..14 in X ($FF if uncached)
atari_match_cache_slot:
    lda atari_fn_83
    cmp #'O'
    bne !check_monster+
    lda atari_fn_83 + 1
    cmp #'V'
    bne !uncached+
    ldx #hal_platform_overlay_count - 1
!ovl_loop:
    lda atari_fn_83 + 8
    cmp atari_ovl_ext_c0,x
    bne !ovl_next+
    lda atari_fn_83 + 9
    cmp atari_ovl_ext_c1,x
    bne !ovl_next+
    lda atari_fn_83 + 10
    cmp atari_ovl_ext_c2,x
    beq !matched_ovl+
!ovl_next:
    dex
    bpl !ovl_loop-
    jmp !uncached+

!matched_ovl:
    lda atari_ovl_xe_slot,x
    tax
    rts

!check_monster:
    cmp #'M'
    bne !check_title+
    lda atari_fn_83 + 1
    cmp #'O'
    bne !uncached+
    lda atari_fn_83 + 10
    sec
    sbc #'1'
    cmp #4
    bcs !uncached+
    clc
    adc #10
    tax
    rts

!check_title:
    cmp #'T'
    bne !uncached+
    lda atari_fn_83 + 1
    cmp #'I'
    bne !uncached+
    ldx #14
    rts

!uncached:
    ldx #$ff
!matched:
    rts
#endif

// atari_sio_prep_read_sec_buf — Populate DCB to read sector X:A into sio_sector_buf.
atari_sio_prep_read_sec_buf:
    sta DCB_DAUX1
    stx DCB_DAUX2
    lda #'R'
    sta DCB_DCOMND
    lda #$40
    sta DCB_DSTATS
    lda #<sio_sector_buf
    sta DCB_DBUFLO
    lda #>sio_sector_buf
    sta DCB_DBUFHI
    lda #128
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    rts

// atari_sio_read_sec_buf — Read sector X:A into sio_sector_buf (returns C from ExitSio).
atari_sio_read_sec_buf:
    jsr atari_sio_prep_read_sec_buf
    jsr EnterSio
    jmp ExitSio

// atari_find_dir_entry — Locate atari_fn_83 in DOS 2.5 directory (Sectors 361..368)
// Output: C=0 found (atari_io_sec_lo/hi = start sector, atari_dir_count_lo/hi = count,
//         atari_file_idx = 0..63), C=1 not found / I/O error.
atari_find_dir_entry:
    lda #<361
    sta atari_io_sec_lo
    lda #>361
    sta atari_io_sec_hi
    lda #0
    sta atari_file_idx

!dir_sec_loop:
    // Read directory sector into sio_sector_buf
    lda atari_io_sec_lo
    ldx atari_io_sec_hi
    jsr atari_sio_read_sec_buf
    bcs !dir_fail+

    ldx #0
!entry_loop:
    lda sio_sector_buf,x
    beq !dir_fail+          // $00 = end of directory
    bmi !next_entry+        // Bit 7 = deleted entry

    // Compare 11-byte filename at sio_sector_buf + x + 5
    stx atari_io_flags
    ldy #0
!cmp_fn:
    lda sio_sector_buf + 5,x
    cmp atari_fn_83,y
    bne !cmp_miss+
    inx
    iny
    cpy #11
    bcc !cmp_fn-

    // Found! Extract sector count and starting sector
    ldx atari_io_flags
    lda sio_sector_buf + 1,x
    sta atari_dir_count_lo
    lda sio_sector_buf + 2,x
    sta atari_dir_count_hi
    lda sio_sector_buf + 3,x
    sta atari_io_sec_lo
    lda sio_sector_buf + 4,x
    sta atari_io_sec_hi
    clc
    rts

!cmp_miss:
    ldx atari_io_flags
!next_entry:
    inc atari_file_idx
    txa
    clc
    adc #16
    tax
    bpl !entry_loop-

    inc atari_io_sec_lo
    lda atari_io_sec_lo
    cmp #<369
    bcs !dir_fail+
    jmp !dir_sec_loop-

!dir_fail:
    sec
    rts

// ============================================================
// HAL Asset Loader Contract (checked by check_hal_asset_exports.py)
// ============================================================

#if ATARI8_CARTRIDGE
#import "cartridge_copy.s"
.label hal_asset_load_prg_header = cart_load_prg
.label hal_asset_load_title      = cart_load_title

hal_asset_load:
    jmp cart_load_prg

hal_asset_close_channel:
    clc
    rts
#else
// hal_asset_load_prg_header — Load PRG-headed asset (overlay, tier, title, or bank)
// Input: A = filename length, X/Y = filename pointer lo/hi
// Output: Carry clear = success, Carry set = error
hal_asset_load_prg_header:
    sta atari_io_cnt
    stx atari_io_src
    sty atari_io_src_hi
    jsr atari_format_83
    jsr atari_match_cache_slot
    stx atari_io_slot
    cpx #18
    bcs !disk_load+
    cpx #15
    beq !disk_load+
    lda xe_present
    beq !disk_load+
    lda xe_slot_populated,x
    bpl !disk_load+
    jmp xe_cache_fetch

!disk_load:
    lda program_device
    sta atari_io_device
    jsr atari_find_dir_entry
    bcc !found_entry+
    rts

!found_entry:
    lda #1
    sta atari_io_flags      // 1 = first sector (strip 2-byte PRG load header)

!sec_loop:
    lda atari_io_sec_lo
    ora atari_io_sec_hi
    beq !load_done+

    lda atari_io_sec_lo
    ldx atari_io_sec_hi
    jsr atari_sio_prep_read_sec_buf
    jsr EnterSio
    jsr ExitSio
    bcs !load_err+

    lda sio_sector_buf + DOS25_LINK_BYTES
    sta atari_io_cnt
    ldx #0
    lda atari_io_flags
    beq !copy_bytes+
    lda #0
    sta atari_io_flags
    lda sio_sector_buf
    sta atari_io_dst
    lda sio_sector_buf + 1
    sta atari_io_dst_hi
    ldx #2

!copy_bytes:
    ldy #0
!byte_loop:
    cpx atari_io_cnt
    bcs !copy_done+
    lda sio_sector_buf,x
    sta (atari_io_dst),y
    inx
    inc atari_io_dst
    bne !byte_loop-
    inc atari_io_dst_hi
    jmp !byte_loop-

!copy_done:
    // Follow 10-bit DOS 2.5 next-sector link in $7E (bits 1..0) and $7F
    lda sio_sector_buf + DOS25_LINK_HI
    and #$03
    sta atari_io_sec_hi
    lda sio_sector_buf + DOS25_LINK_LO
    sta atari_io_sec_lo
    jmp !sec_loop-

!load_done:
    lda xe_present
    beq !load_ok+
    ldx atari_io_slot
    cpx #18
    bcs !load_ok+
    cpx #15
    beq !load_ok+
    jsr xe_cache_stash
!load_ok:
    clc
    rts

!load_err:
    sec
    rts

// hal_asset_load_title — Load TITLE.DAT into MAP_BASE ($C100)
hal_asset_load_title:
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jmp asset_load_retry

hal_asset_load:
    jmp asset_load_retry

hal_asset_close_channel:
    clc
    rts

.assert "130XE slot tables cover slots 0..17", xe_slot_win_hi - xe_slot_portb == 18 && xe_slot_ram_hi - xe_slot_win_hi == 18 && xe_slot_pages - xe_slot_ram_hi == 18, true
.assert "130XE Bank 0 stays within $4000-$7FFF", XE_BANK0_FREE_HI <= XE_WIN_LIMIT_HI, true
.assert "130XE Bank 1 stays within $4000-$7FFF", XE_BANK1_FREE_HI <= XE_WIN_LIMIT_HI, true
.assert "130XE Bank 2 stays within $4000-$7FFF", XE_BANK2_FREE_HI <= XE_WIN_LIMIT_HI, true
.assert "130XE Bank 3 stays within $4000-$7FFF", XE_BANK3_FREE_HI <= XE_WIN_LIMIT_HI, true
.assert "130XE used + free pages equal 256", XE_TOTAL_USED_PAGES + XE_TOTAL_FREE_PAGES == XE_TOTAL_PAGES, true
.assert "130XE TITLE.DAT slot stays inside MAP_BASE ($C100-$CFFF)", (>MAP_BASE) + XE_SLOT14_PAGES <= (>IO_HOLE_BASE), true
#endif
