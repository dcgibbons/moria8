#importonce
// storage.s — BBC Master 128 Acorn DFS / MOS ($FFDD/$FFCE/$FFD1/$FFF1) storage
// and cold-asset loader (< $3000).
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
// All routines and buffers in this file reside below $3000 in unbanked Main RAM
// so MOS/DFS ROM calls (which page the DFS Sideways ROM into $8000-$BFFF) never
// unmap their caller or target buffers.

#import "memory.s"
#import "hal/storage.s"
#import "hal/hal_contract.s"
#import "hal/storage_policy.s"
#import "overlay_storage.s"

// ============================================================
// Low-RAM Storage State (< $3000)
// ============================================================
// Note: beeb_ss_buf is fixed at $0700-$07FF (defined in memory.s).

program_device:         .byte 8
save_device:            .byte 8
disk_prompt_device:     .byte 8
disk_mode:              .byte 1
disk_setup_done:        .byte 0

stream_nam_len:         .byte 0
stream_nam_lo:          .byte 0
stream_nam_hi:          .byte 0

beeb_io_device:         .byte 8
beeb_load_target_bank:  .byte ROMSEL_BANK4
beeb_load_target_hi:    .byte >BANKED_DATA_BASE
beeb_dfs_handle:        .byte 0

beeb_name_write:        .byte 0
beeb_name_replace:      .byte 0
beeb_name_scratch:      .byte 0
beeb_name_drive:        .byte 0

// ============================================================
// Safe MOS / DFS Call Wrappers (BRKV-protected, < $3000)
// ============================================================
// Acorn DFS signals disk errors (File not found, Disk full, Write protect,
// Drive fault) by executing BRK and jumping through BRKV ($0202).
// Each wrapper below records the stack pointer in beeb_mos_saved_sp and sets
// beeb_mos_active = 1 before calling MOS; if DFS raises BRK, beeb_brk_handler
// (services.s) unwinds S to beeb_mos_saved_sp and returns from the wrapper
// with Carry set and A = fault code.

beeb_close_icat_in_mos:
    pha
    phx
    phy
    ldy beeb_icat_handle
    beq !bci_mext+
    stz beeb_icat_handle
    jsr beeb_call_osfind_close
!bci_mext:
    ldy beeb_mext_handle
    beq !bci_ret+
    stz beeb_mext_handle
    jsr beeb_call_osfind_close
!bci_ret:
    ply
    plx
    pla
    rts

beeb_call_osfile:
    jsr beeb_close_icat_in_mos
    tsx
    stx beeb_mos_saved_sp
    ldx #1
    stx beeb_mos_active
    ldx #<BEEB_OS_CTRL_BASE
    ldy #>BEEB_OS_CTRL_BASE
    jsr MOS_OSFILE
    bra !mos_done+

beeb_call_osfind:
    jsr beeb_close_icat_in_mos
beeb_call_osfind_keep_icat:
    tsx
    stx beeb_mos_saved_sp
    ldx #1
    stx beeb_mos_active
    ldx #<BEEB_OS_PATH_BASE
    ldy #>BEEB_OS_PATH_BASE
    jsr MOS_OSFIND
    bra !mos_done+

beeb_call_osfind_close:
    tsx
    stx beeb_mos_saved_sp
    ldx #1
    stx beeb_mos_active
    lda #$00
    jsr MOS_OSFIND
    bra !mos_done+

beeb_call_osgbpb:
    tsx
    stx beeb_mos_saved_sp
    ldx #1
    stx beeb_mos_active
    ldx #<BEEB_OS_CTRL_BASE
    ldy #>BEEB_OS_CTRL_BASE
    jsr MOS_OSGBPB
    bra !mos_done+

beeb_call_osword7f:
    jsr beeb_close_icat_in_mos
    tsx
    stx beeb_mos_saved_sp
    ldx #1
    stx beeb_mos_active
    lda #$7f
    ldx #<BEEB_OS_CTRL_BASE
    ldy #>BEEB_OS_CTRL_BASE
    jsr MOS_OSWORD
!mos_done:
    ldx #0
    stx beeb_mos_active
    clc
    rts

// beeb_mos_osword7f — Safe resident (< $3000) EnterMos..ExitMos wrapper for
// StorageOverlay ($A800-$BFFF) Track 0 formatting so Bank 4 is restored before rts.
beeb_mos_osword7f:
    jsr EnterMos
    jsr beeb_call_osword7f
    jmp ExitMos

// ============================================================
// beeb_zero_os_ctrl — Clear 18-byte control block at BEEB_OS_CTRL_BASE
// ============================================================
// beeb_mos_open_read — Enter MOS and open BEEB_OS_PATH_BASE for input.
// Output: Carry clear = handle in A (>0, MOS still active); Carry set = closed/ExitMos done.
beeb_mos_open_read:
    jsr EnterMos
    lda #$40                // Open for input (read-only)
    jsr beeb_call_osfind_keep_icat
    bcs !bmor_fail+
    cmp #$00
    beq !bmor_fail+
    clc
    rts
!bmor_fail:
    jsr ExitMos
    sec
    rts

beeb_zero_os_ctrl:
    ldx #17
    lda #0
!zloop:
    sta BEEB_OS_CTRL_BASE,x
    dex
    bpl !zloop-
    rts

// beeb_prep_ss_osgbpb — Zero OS control block and target beeb_ss_buf with handle A.
beeb_prep_ss_osgbpb:
    pha
    jsr beeb_zero_os_ctrl
    pla
    sta BEEB_OS_CTRL_BASE + 0
    lda #<beeb_ss_buf
    sta BEEB_OS_CTRL_BASE + 1
    lda #>beeb_ss_buf
    sta BEEB_OS_CTRL_BASE + 2
    lda #$ff
    sta BEEB_OS_CTRL_BASE + 3
    sta BEEB_OS_CTRL_BASE + 4
    rts

// ============================================================
// beeb_set_pathname — Convert HAL/Commodore filename to Acorn DFS ":d.NAME\r"
// Input: A = length, X = name_lo, Y = name_hi, beeb_io_device = 8..11
// Output: CR-terminated string at BEEB_OS_PATH_BASE ($06A0);
//         beeb_name_write / beeb_name_replace / beeb_name_scratch set.
// ============================================================
beeb_set_pathname:
    sta beeb_io_cnt
    stx beeb_io_src
    sty beeb_io_src_hi
    ldx #3
    lda #0
!clr_flags:
    sta beeb_name_write,x
    dex
    bpl !clr_flags-

    // Prefix ":d." where d = '0' + ((beeb_io_device - 8) & 3)
    lda #$3a                // ':'
    sta BEEB_OS_PATH_BASE
    lda beeb_io_device
    sec
    sbc #8
    and #$03
    ora #$30
    sta BEEB_OS_PATH_BASE + 1
    lda #$2e                // '.'
    sta BEEB_OS_PATH_BASE + 2

    ldy #0
!prefix_loop:
    sty beeb_io_pages       // Stash start/rollback index
    cpy beeb_io_cnt
    bcc !prefix_body+
    jmp !parse_done+
!prefix_body:
    lda (beeb_io_src),y
    cmp #$40                // '@' (ASCII/PETSCII $40; 'screencode_mixed' maps '@' to $00!)
    bne !not_at+
    lda #1
    sta beeb_name_replace
    sta beeb_name_write
    iny
    bne !prefix_loop-
!not_at:
    ldx #0
    cmp #'S'
    bne !chk_drive0+
    inx
    iny
    cpy beeb_io_cnt
    bcs !check_base+
    lda (beeb_io_src),y
!chk_drive0:
    cmp #'0'
    bne !check_base+
    iny
    cpy beeb_io_cnt
    bcs !check_base+
    lda (beeb_io_src),y
    cmp #':'
    bne !check_base+
    lda #1
    sta beeb_name_drive
    cpx #0
    beq !prefix_next+
    sta beeb_name_scratch
!prefix_next:
    iny
    bne !prefix_loop-

!check_base:
    // Roll back Y if drive prefix matched only partially, then check trailing ",W"
    ldy beeb_io_cnt
    cpy #2
    bcc !map_name+
    dey
    lda (beeb_io_src),y
    cmp #'W'
    bne !map_name+
    dey
    lda (beeb_io_src),y
    cmp #','
    bne !map_name+
    lda #1
    sta beeb_name_write

!map_name:
    ldy beeb_io_pages
    cpy beeb_io_cnt
    bcs !parse_done+
    lda (beeb_io_src),y

    // Map Commodore mutable filenames to 7-char Acorn DFS names:
    //   "MORIA8.ID"    -> "MORIAID"
    //   "HALL.OF.FAME" -> "HISCORE"
    //   "THE.GAME[2-4]"-> "SAVE0".."SAVE3"
    cmp #'H'
    bne !chk_mor+
    ldy #8
    jsr !copy_mapped+
    bra !terminate_x+

!chk_mor:
    cmp #'M'
    bne !chk_save+
    iny
    cpy beeb_io_cnt
    bcs !copy_raw+
    lda (beeb_io_src),y
    cmp #'O'
    bne !copy_raw+
    iny
    cpy beeb_io_cnt
    bcs !copy_raw+
    lda (beeb_io_src),y
    cmp #'R'
    bne !copy_raw+
    ldy #0
    jsr !copy_mapped+
    bra !terminate_x+

!chk_save:
    cmp #'T'
    bne !copy_raw+
    iny
    cpy beeb_io_cnt
    bcs !copy_raw+
    lda (beeb_io_src),y
    cmp #'H'
    bne !copy_raw+
    ldy #16
    jsr !copy_mapped+
    lda beeb_io_pages
    clc
    adc #8
    tay
    cpy beeb_io_cnt
    bcs !terminate_x+
    lda (beeb_io_src),y
    cmp #'2'
    bcc !terminate_x+
    cmp #'5'
    bcs !terminate_x+
    sec
    sbc #1                  // '2' -> '1', '3' -> '2', '4' -> '3'
    sta BEEB_OS_PATH_BASE + 3 + 4
    bra !terminate_x+

!copy_raw:
    ldy beeb_io_pages
    ldx #0
!raw_loop:
    cpy beeb_io_cnt
    bcs !terminate_x+
    lda (beeb_io_src),y
    beq !terminate_x+
    cmp #','
    beq !terminate_x+
    sta BEEB_OS_PATH_BASE + 3,x
    inx
    iny
    cpx #7
    bcc !raw_loop-

!terminate_x:
    lda #$0d
    sta BEEB_OS_PATH_BASE + 3,x
    rts

!parse_done:
    ldx #0
    beq !terminate_x-

!copy_mapped:
    ldx #0
!cm_loop:
    lda beeb_fn_table,y
    beq !cm_done+
    sta BEEB_OS_PATH_BASE + 3,x
    inx
    iny
    bne !cm_loop-
!cm_done:
    rts

beeb_fn_table:
    .text "MORIAID" ; .byte 0
    .text "HISCORE" ; .byte 0
    .text "SAVE0"   ; .byte 0

// ============================================================
// beeb_dfs_file_exists — Check if BEEB_OS_PATH_BASE exists via OSFILE A=$05
// Output: Carry clear = file exists, Carry set = not found / DFS fault
// ============================================================
beeb_dfs_file_exists:
    jsr beeb_mos_osfile_path_05
    bcs !no+
    cmp #1
    bne !no+
    clc
    rts
!no:
    sec
    rts

// beeb_mos_osfile_path_05 / beeb_mos_osfile_a — Safe resident (< $3000) OSFILE
// wrappers so callers in StorageOverlay ($A800-$BFFF) never unmap Bank 4 across
// EnterMos/ExitMos or BRKV unwind.
beeb_mos_osfile_path_05:
    jsr beeb_zero_os_ctrl
    lda #<BEEB_OS_PATH_BASE
    sta BEEB_OS_CTRL_BASE + 0
    lda #>BEEB_OS_PATH_BASE
    sta BEEB_OS_CTRL_BASE + 1
    lda #$05
beeb_mos_osfile_a:
    pha
    jsr EnterMos
    pla
    jsr beeb_call_osfile
    jmp ExitMos

// ============================================================
// HAL Asset Loader Contract (checked by check_hal_asset_exports.py)
// ============================================================

// hal_asset_load_prg_header — Load overlay or monster tier into Bank 4 ($A800)
// Input: A = filename length, X/Y = filename pointer lo/hi
// Output: Carry clear = success, Carry set = error
hal_asset_load_prg_header:
    pha
    phx
    phy
    jsr beeb_overlay_try_cache
    bcs !cache_miss+
    ply
    plx
    pla
    clc
    rts

!cache_miss:
    ply
    plx
    pla
    pha
    lda #ROMSEL_BANK4
    sta beeb_load_target_bank
    lda #>BANKED_DATA_BASE
    sta beeb_load_target_hi
    pla
    jmp beeb_dfs_load_to_bank

// hal_asset_load_title — Load TITLE into Bank 5 MAP_BASE ($8000)
hal_asset_load_title:
    lda #ROMSEL_BANK5
    sta beeb_load_target_bank
    lda #>MAP_BASE
    sta beeb_load_target_hi
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jmp beeb_dfs_load_to_bank

// hal_asset_load — Load asset to caller X/Y address (or verify when A != 0)
hal_asset_load:
    cmp #0
    beq !do_load+
    lda stream_nam_len
    ldx stream_nam_lo
    ldy stream_nam_hi
    pha
    lda program_device
    sta beeb_io_device
    pla
    jsr beeb_set_pathname
    jmp beeb_dfs_file_exists
!do_load:
    sty beeb_load_target_hi
    lda #ROMSEL_BANK4
    sta beeb_load_target_bank
    lda stream_nam_len
    ldx stream_nam_lo
    ldy stream_nam_hi
    jmp beeb_dfs_load_to_bank

hal_asset_close_channel:
    clc
    rts

// ============================================================
// beeb_dfs_load_to_bank — Stream DFS file via beeb_ss_buf ($0700) into
// target Sideways RAM bank (beeb_load_target_bank, address beeb_load_target_hi:00).
// Streams in 256-byte chunks via OSFIND + OSGBPB so the DFS Sideways ROM at
// $8000-$BFFF never conflicts with the destination Sideways RAM bank!
// ============================================================
beeb_dfs_load_to_bank:
    pha
    lda program_device
    sta beeb_io_device
    pla
    jsr beeb_set_pathname

    // Program the SWR destination pointer via < $3000 SMC so MOS_OSGBPB never
    // reads or increments a ZP pointer across MOS ownership ($00-$AF).
    stz bdl_sta + 1
    lda beeb_load_target_hi
    sta bdl_sta + 2

    jsr beeb_mos_open_read
    bcs !open_done_err+
    sta beeb_dfs_handle

!chunk_loop:
    lda beeb_dfs_handle
    jsr beeb_prep_ss_osgbpb
    lda #$01                // Request 256 ($0100) bytes
    sta BEEB_OS_CTRL_BASE + 6

    lda #$04                // Read bytes from current sequential pointer
    jsr beeb_call_osgbpb
    bcs !read_err+

    // Compute bytes transferred = $0100 - residual (BEEB_OS_CTRL_BASE + 5..6)
    lda BEEB_OS_CTRL_BASE + 6
    bne !eof_done+          // Residual == $0100 -> 0 bytes transferred (EOF)

    // Copy transferred bytes (1..256) from beeb_ss_buf to target Sideways RAM bank
    php
    sei
    lda beeb_load_target_bank
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL

    lda #$00
    sec
    sbc BEEB_OS_CTRL_BASE + 5
    tax                     // X = transferred byte count (0 means full 256 bytes)
    ldy #0
!copy_loop:
    lda beeb_ss_buf,y
bdl_sta:
    sta $ff00,y             // Destination page patched before open and between pages
    iny
    dex
    bne !copy_loop-

    lda beeb_boot_romsel
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    plp

    inc bdl_sta + 2
    // If residual_lo != 0, this was the final partial page
    lda BEEB_OS_CTRL_BASE + 5
    beq !chunk_loop-

!eof_done:
    ldy beeb_dfs_handle
    jsr beeb_call_osfind_close
    jsr ExitMos
    clc
    rts

!read_err:
    ldy beeb_dfs_handle
    jsr beeb_call_osfind_close
    jsr ExitMos
!open_done_err:
    sec
    rts
