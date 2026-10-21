#importonce
// storage_kernal.s — Commander X16 storage HAL & banked asset manager.
//
// Implements the full hal_storage_* and hal_asset_* contract surface for CX16.
// Runtime overlays (Banks 9-20), monster tiers (Banks 5-8), Cx16AuxData
// (Bank 3), Cx16HuffData (Bank 4), and TITLE art (Bank 21) are preloaded into
// banked RAM at boot by cx16_preload_banks (overlay_storage.s). After preload,
// hal_asset_load_prg_header resolves overlay and tier requests in O(1) by
// switching CX16_RAM_BANK_REG ($00) with zero disk I/O.

#import "hal/hal_contract.s"
#import "hal/storage_policy.s"

// ============================================================
// Diagnostic and classification state (contract diag bytes)
// ============================================================
hal_storage_diag_code:    .byte 0
hal_storage_diag_phase:   .byte 0
hal_storage_diag_readst:  .byte 0
hal_storage_diag_device:  .byte 8
hal_storage_diag_dos0:    .byte $30
hal_storage_diag_dos1:    .byte $30

cx16_last_status:         .byte 0
cx16_media_status:        .byte 0

// ============================================================
// OS / drive lifecycle hooks
// ============================================================
hal_storage_enter_os:
    clc
    rts

hal_storage_exit_os:
    clc
    rts

hal_storage_init_selected_drive:
    clc
    rts

// ============================================================
// Media probes & marker helpers
// ============================================================
hal_storage_probe_media:
hal_storage_require_program_media:
    lda #HAL_STORAGE_STATUS_OK
    sta cx16_media_status
    clc
    rts

// On CX16, SD card / HostFS (device 8) is non-removable mass storage with
// ample space for saves alongside program files. When disk_setup_done is
// set, save media is ready immediately.
hal_storage_require_save_media:
disk_require_save_media:
    lda disk_setup_done
    beq !need_setup+
    lda #HAL_STORAGE_STATUS_OK
    sta cx16_media_status
    clc
    rts
!need_setup:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    sta cx16_media_status
    sec
    rts

hal_storage_marker_present:
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr hal_storage_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr hal_storage_setlfs
    jsr hal_storage_open
    bcs !fail+
    ldx #hal_storage_marker_file_num
    jsr hal_storage_chkin
    bcs !close_fail+
    ldx #0
!loop:
    jsr hal_storage_chrin
    cmp hal_storage_marker_magic,x
    bne !close_fail+
    jsr hal_storage_readst
    and #$03
    bne !close_fail+
    inx
    cpx #hal_storage_marker_magic_len
    bcc !loop-
    jsr hal_storage_clrchn
    lda #hal_storage_marker_file_num
    jsr hal_storage_close
    lda #HAL_STORAGE_STATUS_OK
    sta cx16_media_status
    clc
    rts
!close_fail:
    jsr hal_storage_clrchn
    lda #hal_storage_marker_file_num
    jsr hal_storage_close
!fail:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    sta cx16_media_status
    sec
    rts

hal_storage_marker_init:
    lda #hal_storage_marker_write_name_len
    ldx #<hal_storage_marker_write_name
    ldy #>hal_storage_marker_write_name
    jsr hal_storage_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_write
    jsr hal_storage_setlfs
    jsr hal_storage_open
    bcs !fail+
    ldx #hal_storage_marker_file_num
    jsr hal_storage_chkout
    bcs !close_fail+
    ldx #0
!loop:
    lda hal_storage_marker_magic,x
    jsr hal_storage_chrout
    jsr hal_storage_readst
    and #$03
    bne !close_fail+
    inx
    cpx #hal_storage_marker_magic_len
    bcc !loop-
    jsr hal_storage_clrchn
    lda #hal_storage_marker_file_num
    jsr hal_storage_close
    lda #HAL_STORAGE_STATUS_OK
    sta cx16_media_status
    clc
    rts
!close_fail:
    jsr hal_storage_clrchn
    lda #hal_storage_marker_file_num
    jsr hal_storage_close
!fail:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta cx16_media_status
    sec
    rts

// ============================================================
// Status classifiers
// ============================================================
hal_storage_save_media_status:
hal_storage_setup_status:
    lda cx16_media_status
    rts

.label hal_storage_save_stream_status = save_stream_status
.label hal_storage_load_stream_status = load_stream_status

hal_storage_read_command_status:
    clc
    rts

hal_storage_command_status:
    lda cx16_last_status
    rts

// ============================================================
// Asset loaders (bank-switch fast path + KERNAL LOAD fallback)
// ============================================================
// hal_asset_load_prg_header
// Input: A = filename length, X = filename lo, Y = filename hi.
// Output: carry clear = success, carry set = failure.
hal_asset_load_prg_header:
    pha
    txa
    pha
    tya
    pha
    jsr cx16_asset_try_bank_switch
    bcs !disk_fallback+
    pla
    pla
    pla
    clc
    rts
!disk_fallback:
    pla
    tay
    pla
    tax
    pla
    jmp cx16_kernal_load_banked_window

// cx16_kernal_load_banked_window — Load PRG file into $A000 of the currently
// selected CX16_RAM_BANK_REG ($00), preserving ZP $02-$8F across KERNAL LOAD.
// Input: A = filename len, X = filename lo, Y = filename hi.
cx16_kernal_load_banked_window:
    sta cx16_load_fn_len
    stx cx16_load_fn_lo
    sty cx16_load_fn_hi
    lda CX16_RAM_BANK_REG
    sta cx16_load_target_bank
    jsr save_zp
    lda #CX16_ROM_BANK_KERNAL
    sta CX16_ROM_BANK_REG
    lda cx16_load_fn_len
    ldx cx16_load_fn_lo
    ldy cx16_load_fn_hi
    jsr KERNAL_SETNAM
    lda #hal_storage_program_file_num
    ldx program_device
    bne !dev_ok+
    ldx #8
!dev_ok:
    ldy #0                          // SA=0: load to caller X/Y ($A000)
    jsr KERNAL_SETLFS
    lda cx16_load_target_bank
    sta CX16_RAM_BANK_REG
    lda #0                          // A=0: LOAD
    ldx #<BANKED_DATA_BASE
    ldy #>BANKED_DATA_BASE
    jsr KERNAL_LOAD
    php
    pha
    phx
    lda cx16_load_target_bank
    sta CX16_RAM_BANK_REG
    jsr restore_zp
    plx
    pla
    plp
    rts

cx16_load_fn_len:      .byte 0
cx16_load_fn_lo:       .byte 0
cx16_load_fn_hi:       .byte 0
cx16_load_target_bank: .byte 0

hal_asset_load:
hal_storage_load:
    sta cx16_asset_verify
    stx cx16_asset_dest
    sty cx16_asset_dest + 1
    lda CX16_RAM_BANK_REG
    sta cx16_load_target_bank
    jsr save_zp
    stz CX16_ROM_BANK_REG
    lda cx16_load_target_bank
    sta CX16_RAM_BANK_REG
    lda cx16_asset_verify
    ldx cx16_asset_dest
    ldy cx16_asset_dest + 1
    jsr KERNAL_LOAD
    php
    pha
    phx
    lda cx16_load_target_bank
    sta CX16_RAM_BANK_REG
    jsr restore_zp
    plx
    pla
    plp
    rts

cx16_asset_verify: .byte 0
cx16_asset_dest:   .word 0

// ============================================================
// hal_asset_load_title — Copy preloaded TITLE art stream from Bank 21
// ($A000-$A2FF) into MAP_BASE (Bank 1 $A000-$A2FF) so title_render_data
// reads it via mmu_safe_map_read_ptr1.
// ============================================================
hal_asset_load_title:
    lda CX16_RAM_BANK_REG
    pha
    lda #>BANKED_DATA_BASE
    sta cx16_title_page_hi
    stz zp_ptr0
    stz zp_ptr1
    ldx #3                          // 3 pages (768 B covers 622 B TITLE)
!page_loop:
    lda cx16_title_page_hi
    sta zp_ptr0_hi
    sta zp_ptr1_hi
    ldy #0
    lda #CX16_BANK_TITLE_ART
    sta CX16_RAM_BANK_REG
!read_page:
    lda (zp_ptr0),y
    sta CX16_ROW_STAGE_BASE,y
    iny
    bne !read_page-
    lda #CX16_BANK_MAP_LO
    sta CX16_RAM_BANK_REG
!write_page:
    lda CX16_ROW_STAGE_BASE,y
    sta (zp_ptr1),y
    iny
    bne !write_page-
    inc cx16_title_page_hi
    dex
    bne !page_loop-
    pla
    sta CX16_RAM_BANK_REG
    clc
    rts

cx16_title_page_hi: .byte 0

hal_asset_close_channel:
    lda #hal_storage_program_file_num
    jsr hal_storage_close
    jmp hal_storage_clrchn

// ============================================================
// Contract aliases into the shared save engine
// ============================================================
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game

// ============================================================
// Platform-owned filename labels (Commodore PETSCII/ASCII compatible)
// ============================================================
hal_storage_save_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
    .byte $57                                   // spare suffix byte for "THE.GAME2"
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a                              // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
    .byte $52                                   // spare suffix byte for "THE.GAME2"

hal_storage_score_read_name:
    .byte $30, $3a                              // "0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_score_read_name_len = * - hal_storage_score_read_name

hal_storage_score_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_score_write_name_len = * - hal_storage_score_write_name

hal_storage_score_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
.label hal_storage_score_scratch_name_len = * - hal_storage_score_scratch_name

hal_storage_init_command:
    .byte $49, $30                              // "I0"

hal_storage_marker_magic:
    .byte $4d, $38, $53, $41, $56, $45          // "M8SAVE"
.label hal_storage_marker_magic_len = * - hal_storage_marker_magic

hal_storage_marker_read_name:
    .byte $30, $3a                              // "0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_marker_read_name_len = * - hal_storage_marker_read_name

hal_storage_marker_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_marker_write_name_len = * - hal_storage_marker_write_name

hal_storage_marker_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name

// Boot-preloaded data bank filenames
cx16_auxdata_name:
    .byte $43,$58,$31,$36,$2e,$41,$55,$58,$44,$41,$54,$41 // "CX16.AUXDATA"
.label cx16_auxdata_name_len = * - cx16_auxdata_name
    .byte 0

cx16_huffdata_name:
    .byte $43,$58,$31,$36,$2e,$48,$55,$46,$46,$44,$41,$54,$41 // "CX16.HUFFDATA"
.label cx16_huffdata_name_len = * - cx16_huffdata_name
    .byte 0

// Title-art asset name
hal_storage_title_name:
    .byte $54, $49, $54, $4c, $45               // "TITLE"
.label hal_storage_title_name_len = * - hal_storage_title_name
    .byte 0

// Tier data filenames
hal_storage_tier_1_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$31 // "MONSTER.DB.1"
.label hal_storage_tier_1_name_len = * - hal_storage_tier_1_name
    .byte 0
hal_storage_tier_2_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$32 // "MONSTER.DB.2"
.label hal_storage_tier_2_name_len = * - hal_storage_tier_2_name
    .byte 0
hal_storage_tier_3_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$33 // "MONSTER.DB.3"
.label hal_storage_tier_3_name_len = * - hal_storage_tier_3_name
    .byte 0
hal_storage_tier_4_name:
    .byte $4d,$4f,$4e,$53,$54,$45,$52,$2e,$44,$42,$2e,$34 // "MONSTER.DB.4"
.label hal_storage_tier_4_name_len = * - hal_storage_tier_4_name
    .byte 0

hal_storage_tier_name_lo:
    .byte <hal_storage_tier_1_name, <hal_storage_tier_2_name, <hal_storage_tier_3_name, <hal_storage_tier_4_name
hal_storage_tier_name_hi:
    .byte >hal_storage_tier_1_name, >hal_storage_tier_2_name, >hal_storage_tier_3_name, >hal_storage_tier_4_name
hal_storage_tier_name_len:
    .byte hal_storage_tier_1_name_len, hal_storage_tier_2_name_len, hal_storage_tier_3_name_len, hal_storage_tier_4_name_len

// Overlay asset filenames (indexed by overlay ID - 1; IDs 1..12 -> Banks 9..20)
hal_storage_overlay_start_name:
    .byte $4f,$56,$4c,$2e,$53,$54,$41,$52,$54   // "OVL.START"
.label hal_storage_overlay_start_name_len = * - hal_storage_overlay_start_name
    .byte 0
hal_storage_overlay_town_name:
    .byte $4f,$56,$4c,$2e,$54,$4f,$57,$4e       // "OVL.TOWN"
.label hal_storage_overlay_town_name_len = * - hal_storage_overlay_town_name
    .byte 0
hal_storage_overlay_death_name:
    .byte $4f,$56,$4c,$2e,$44,$45,$41,$54,$48   // "OVL.DEATH"
.label hal_storage_overlay_death_name_len = * - hal_storage_overlay_death_name
    .byte 0
hal_storage_overlay_gen_name:
    .byte $4f,$56,$4c,$2e,$47,$45,$4e           // "OVL.GEN"
.label hal_storage_overlay_gen_name_len = * - hal_storage_overlay_gen_name
    .byte 0
hal_storage_overlay_help_name:
    .byte $4f,$56,$4c,$2e,$48,$45,$4c,$50       // "OVL.HELP"
.label hal_storage_overlay_help_name_len = * - hal_storage_overlay_help_name
    .byte 0
hal_storage_overlay_ui_name:
    .byte $4f,$56,$4c,$2e,$55,$49               // "OVL.UI"
.label hal_storage_overlay_ui_name_len = * - hal_storage_overlay_ui_name
    .byte 0
hal_storage_overlay_items_name:
    .byte $4f,$56,$4c,$2e,$49,$54,$45,$4d,$53   // "OVL.ITEMS"
.label hal_storage_overlay_items_name_len = * - hal_storage_overlay_items_name
    .byte 0
hal_storage_overlay_spell_name:
    .byte $4f,$56,$4c,$2e,$53,$50,$45,$4c,$4c   // "OVL.SPELL"
.label hal_storage_overlay_spell_name_len = * - hal_storage_overlay_spell_name
    .byte 0
hal_storage_modal_misc_name:
    .byte $4f,$56,$4c,$2e,$4d,$4f,$44,$41,$4c   // "OVL.MODAL"
.label hal_storage_modal_misc_name_len = * - hal_storage_modal_misc_name
    .byte 0
hal_storage_overlay_chest_name:
    .byte $4f,$56,$4c,$2e,$43,$48,$45,$53,$54   // "OVL.CHEST"
.label hal_storage_overlay_chest_name_len = * - hal_storage_overlay_chest_name
    .byte 0
hal_storage_overlay_storage_name:
    .byte $4f,$56,$4c,$2e,$53,$54,$4f,$52,$41,$47,$45 // "OVL.STORAGE"
.label hal_storage_overlay_storage_name_len = * - hal_storage_overlay_storage_name
    .byte 0
hal_storage_overlay_title_name:
    .byte $4f,$56,$4c,$2e,$54,$49,$54,$4c,$45   // "OVL.TITLE"
.label hal_storage_overlay_title_name_len = * - hal_storage_overlay_title_name
    .byte 0

hal_storage_overlay_name_lo:
    .byte <hal_storage_overlay_start_name, <hal_storage_overlay_town_name, <hal_storage_overlay_death_name, <hal_storage_overlay_gen_name, <hal_storage_overlay_help_name, <hal_storage_overlay_ui_name, <hal_storage_overlay_items_name, <hal_storage_overlay_spell_name, <hal_storage_modal_misc_name, <hal_storage_overlay_chest_name, <hal_storage_overlay_storage_name, <hal_storage_overlay_title_name
hal_storage_overlay_name_hi:
    .byte >hal_storage_overlay_start_name, >hal_storage_overlay_town_name, >hal_storage_overlay_death_name, >hal_storage_overlay_gen_name, >hal_storage_overlay_help_name, >hal_storage_overlay_ui_name, >hal_storage_overlay_items_name, >hal_storage_overlay_spell_name, >hal_storage_modal_misc_name, >hal_storage_overlay_chest_name, >hal_storage_overlay_storage_name, >hal_storage_overlay_title_name
hal_storage_overlay_name_len:
    .byte hal_storage_overlay_start_name_len, hal_storage_overlay_town_name_len, hal_storage_overlay_death_name_len, hal_storage_overlay_gen_name_len, hal_storage_overlay_help_name_len, hal_storage_overlay_ui_name_len, hal_storage_overlay_items_name_len, hal_storage_overlay_spell_name_len, hal_storage_modal_misc_name_len, hal_storage_overlay_chest_name_len, hal_storage_overlay_storage_name_len, hal_storage_overlay_title_name_len

// ============================================================
// Compile-time validation
// ============================================================
.const CX16_OVERLAY_TABLE_COUNT = * - hal_storage_overlay_name_len
.assert "Overlay table matches hal_platform_overlay_count", CX16_OVERLAY_TABLE_COUNT, hal_platform_overlay_count
.assert "Save read name keeps slot-menu digit offset 10", hal_storage_save_read_name_len - 4, 10
.assert "Save write name keeps slot-menu digit offset 11", hal_storage_save_write_name_len - 4, 11
.assert "Probe filename tracks write filename without overwrite marker", hal_storage_save_probe_name_len, hal_storage_save_write_name_len - 1
.assert "Marker magic is 6 bytes", hal_storage_marker_magic_len, 6
