#importonce
// dungeon_module.s - CX16 loadable dungeon-generation module contract.

#import "dungeon_module_contract.s"

.assert "CX16 dungeon module load base is bank-window base", CX16_DUNGEON_MODULE_LOAD_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 dungeon module load end is bank-window end", CX16_DUNGEON_MODULE_LOAD_END, CX16_BANKED_RAM_END
.assert "CX16 dungeon module bank follows tier cache banks", CX16_DUNGEON_MODULE_BANK > CX16_TIER_BANK_END, true

cx16_dungeon_module_status: .byte 0
cx16_dungeon_module_ret_a: .byte 0
cx16_dungeon_module_ret_x: .byte 0
cx16_dungeon_module_ret_y: .byte 0
cx16_dungeon_module_request_depth: .byte 0

// Output: carry clear = module loaded into bank 8.
//         carry set = KERNAL load error.
// Restores the caller's selected RAM bank before returning.
cx16_load_dungeon_module:
    jsr cx16_save_ram_bank
    lda #CX16_DUNGEON_MODULE_BANK
    jsr cx16_select_ram_bank_a
    lda #<CX16_DUNGEON_MODULE_LOAD_BASE
    sta cx16_asset_load_addr_lo
    lda #>CX16_DUNGEON_MODULE_LOAD_BASE
    sta cx16_asset_load_addr_hi
    lda #cx16_dungeon_module_file_len
    ldx #<cx16_dungeon_module_file
    ldy #>cx16_dungeon_module_file
    jsr hal_asset_load_prg_header
    php
    jsr cx16_restore_ram_bank
    plp
    rts

// Input:  A = dungeon depth to generate.
// Output: carry clear = loaded module generated the map and returned the
//         expected ABI tuple; carry set = load, status, or ABI mismatch.
// Restores the caller's selected RAM bank before returning.
cx16_generate_dungeon_level:
    sta cx16_dungeon_module_request_depth
    jsr cx16_load_dungeon_module
    bcs !fail+
    jsr cx16_save_ram_bank
    lda #CX16_DUNGEON_MODULE_BANK
    jsr cx16_select_ram_bank_a
    lda cx16_dungeon_module_request_depth
    jsr CX16_DUNGEON_MODULE_ENTRY
    sta cx16_dungeon_module_ret_a
    stx cx16_dungeon_module_ret_x
    sty cx16_dungeon_module_ret_y
    php
    jsr cx16_restore_ram_bank
    plp
    bcs !fail+
    lda cx16_dungeon_module_ret_a
    cmp #CX16_DUNGEON_MODULE_MAGIC_A
    bne !fail+
    lda cx16_dungeon_module_ret_x
    cmp #CX16_DUNGEON_MODULE_MAGIC_X
    bne !fail+
    lda cx16_dungeon_module_ret_y
    cmp #CX16_DUNGEON_MODULE_VERSION
    bne !fail+
    jsr cx16_sync_generated_dungeon_state
    lda #1
    sta cx16_dungeon_module_status
    clc
    rts
!fail:
    lda #0
    sta cx16_dungeon_module_status
    sec
    rts

// Compatibility label for existing probes; generation now uses the full output
// ABI and copies generator-owned placement state back to resident variables.
cx16_probe_dungeon_module:
    lda #1
    jmp cx16_generate_dungeon_level

cx16_sync_generated_dungeon_state:
    lda cx16_dungeon_module_request_depth
    sta cx16_dungeon_depth
    lda zp_player_x
    sta cx16_player_x
    lda zp_player_y
    sta cx16_player_y
    rts

cx16_dungeon_module_file:
    .byte $44, $55, $4e, $47, $45, $4f, $4e, $2e, $47, $45, $4e // "DUNGEON.GEN"
.label cx16_dungeon_module_file_len = * - cx16_dungeon_module_file
