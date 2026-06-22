#importonce
// overlay_storage.s - CX16 bank-window overlay payload loader.

.const CX16_OVERLAY_LOAD_BASE = CX16_BANKED_RAM_BASE
.const CX16_OVERLAY_LOAD_END = CX16_BANKED_RAM_END
.const CX16_OVERLAY_PRELOAD_COUNT = 9

.assert "CX16 overlay load base is bank-window base", CX16_OVERLAY_LOAD_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 overlay load end is bank-window end", CX16_OVERLAY_LOAD_END, CX16_BANKED_RAM_END
.assert "CX16 overlay preload count covers named slots", CX16_OVERLAY_PRELOAD_COUNT, CX16_OVERLAY_SLOT_BANK_END - CX16_OVERLAY_SLOT_BANK_BASE + 1

current_overlay: .byte OVL_NONE
cx16_overlay_requested: .byte OVL_NONE
cx16_overlay_target: .byte OVL_NONE
cx16_overlay_preload_index: .byte 0
cx16_overlay_load_bank: .byte 0
cx16_overlay_ready:
    .fill CX16_OVERLAY_PRELOAD_COUNT + 1, 0

// Output: carry clear = all overlay payloads loaded into reserved banks.
//         carry set = first load failure, cx16_overlay_target holds the ID.
cx16_preload_all_overlays:
    lda #0
    sta current_overlay
    ldx #0
!clear:
    sta cx16_overlay_ready,x
    inx
    cpx #(CX16_OVERLAY_PRELOAD_COUNT + 1)
    bcc !clear-

    lda #1
    sta cx16_overlay_preload_index
!loop:
    lda cx16_overlay_preload_index
    jsr cx16_overlay_show_file
    lda cx16_overlay_preload_index
    jsr cx16_load_overlay_to_bank
    bcs !fail+
    inc cx16_overlay_preload_index
    lda cx16_overlay_preload_index
    cmp #(CX16_OVERLAY_PRELOAD_COUNT + 1)
    bcc !loop-
    clc
    rts
!fail:
    sec
    rts

// Input: A = CX16 overlay slot ID.
// Output: carry clear = loaded, carry set = invalid ID or KERNAL load error.
// Restores the caller's selected RAM bank before returning.
cx16_load_overlay_to_bank:
    cmp #1
    bcc !invalid+
    cmp #(CX16_OVERLAY_PRELOAD_COUNT + 1)
    bcs !invalid+
    sta cx16_overlay_target
    tax
    lda cx16_overlay_bank,x
    sta cx16_overlay_load_bank

    jsr cx16_save_ram_bank
    lda cx16_overlay_load_bank
    jsr cx16_select_ram_bank_a
    lda #<CX16_OVERLAY_LOAD_BASE
    sta cx16_asset_load_addr_lo
    lda #>CX16_OVERLAY_LOAD_BASE
    sta cx16_asset_load_addr_hi

    ldx cx16_overlay_target
    dex
    lda cx16_overlay_file_len,x
    pha
    lda cx16_overlay_file_lo,x
    pha
    lda cx16_overlay_file_hi,x
    tay
    pla
    tax
    pla
    jsr hal_asset_load_prg_header
    php
    bcs !restore+
    ldx cx16_overlay_target
    lda #1
    sta cx16_overlay_ready,x
!restore:
    jsr cx16_restore_ram_bank
    plp
    rts
!invalid:
    sec
    rts

// Input: A = CX16 overlay slot ID.
cx16_overlay_show_file:
    cmp #1
    bcc !done+
    cmp #(CX16_OVERLAY_PRELOAD_COUNT + 1)
    bcs !done+
    tax
    dex
    lda cx16_overlay_file_lo,x
    sta zp_ptr0
    lda cx16_overlay_file_hi,x
    sta zp_ptr0_hi
    lda cx16_overlay_file_len,x
    ldx zp_ptr0
    ldy zp_ptr0_hi
    jsr cx16_loader_show_file
!done:
    rts

cx16_overlay_bank:
    .byte 0
    .byte CX16_OVERLAY_STARTUP_BANK
    .byte CX16_OVERLAY_TOWN_BANK
    .byte CX16_OVERLAY_DEATH_BANK
    .byte CX16_OVERLAY_GEN_BANK
    .byte CX16_OVERLAY_HELP_BANK
    .byte CX16_OVERLAY_UI_BANK
    .byte CX16_OVERLAY_ITEMS_BANK
    .byte CX16_OVERLAY_STORAGE_BANK
    .byte CX16_OVERLAY_DISARM_BANK

// Map shared overlay IDs to the CX16 physical slot order.
cx16_overlay_common_to_slot:
    .byte 0
    .byte 1  // OVL_STARTUP
    .byte 2  // OVL_TOWN
    .byte 3  // OVL_DEATH
    .byte 4  // OVL_DUNGEON_GEN
    .byte 5  // OVL_HELP
    .byte 6  // OVL_UI
    .byte 7  // OVL_ITEMS
    .byte 8  // OVL_STORAGE; shared-probe OVL_SPELL aliases here in config.s.
    .byte 0
    .byte 9  // CX16 disarm slot

cx16_overlay_file_lo:
    .byte <cx16_overlay_start_file, <cx16_overlay_town_file, <cx16_overlay_death_file, <cx16_overlay_gen_file
    .byte <cx16_overlay_help_file, <cx16_overlay_ui_file, <cx16_overlay_items_file, <cx16_overlay_storage_file, <cx16_overlay_disarm_file
cx16_overlay_file_hi:
    .byte >cx16_overlay_start_file, >cx16_overlay_town_file, >cx16_overlay_death_file, >cx16_overlay_gen_file
    .byte >cx16_overlay_help_file, >cx16_overlay_ui_file, >cx16_overlay_items_file, >cx16_overlay_storage_file, >cx16_overlay_disarm_file
cx16_overlay_file_len:
    .byte cx16_overlay_start_file_len, cx16_overlay_town_file_len, cx16_overlay_death_file_len, cx16_overlay_gen_file_len
    .byte cx16_overlay_help_file_len, cx16_overlay_ui_file_len, cx16_overlay_items_file_len, cx16_overlay_storage_file_len, cx16_overlay_disarm_file_len

cx16_overlay_start_file:
    .byte $58, $31, $36, $2e, $53, $54, $41, $52, $54 // "X16.START"
.label cx16_overlay_start_file_len = * - cx16_overlay_start_file
cx16_overlay_town_file:
    .byte $58, $31, $36, $2e, $54, $4f, $57, $4e // "X16.TOWN"
.label cx16_overlay_town_file_len = * - cx16_overlay_town_file
cx16_overlay_death_file:
    .byte $58, $31, $36, $2e, $44, $45, $41, $54, $48 // "X16.DEATH"
.label cx16_overlay_death_file_len = * - cx16_overlay_death_file
cx16_overlay_gen_file:
    .byte $58, $31, $36, $2e, $47, $45, $4e // "X16.GEN"
.label cx16_overlay_gen_file_len = * - cx16_overlay_gen_file
cx16_overlay_help_file:
    .byte $58, $31, $36, $2e, $48, $45, $4c, $50 // "X16.HELP"
.label cx16_overlay_help_file_len = * - cx16_overlay_help_file
cx16_overlay_ui_file:
    .byte $58, $31, $36, $2e, $55, $49 // "X16.UI"
.label cx16_overlay_ui_file_len = * - cx16_overlay_ui_file
cx16_overlay_items_file:
    .byte $58, $31, $36, $2e, $49, $54, $45, $4d, $53 // "X16.ITEMS"
.label cx16_overlay_items_file_len = * - cx16_overlay_items_file
cx16_overlay_storage_file:
    .byte $58, $31, $36, $2e, $53, $41, $56, $45 // "X16.SAVE"
.label cx16_overlay_storage_file_len = * - cx16_overlay_storage_file
cx16_overlay_disarm_file:
    .byte $58, $31, $36, $2e, $44, $49, $53, $41, $52, $4d // "X16.DISARM"
.label cx16_overlay_disarm_file_len = * - cx16_overlay_disarm_file
