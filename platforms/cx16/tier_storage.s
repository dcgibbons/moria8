#importonce
// tier_storage.s - CX16 bank-window tier payload loader.

#import "creature_data/creature_tiers.s"

.const CX16_TIER_LOAD_BASE = CX16_BANKED_RAM_BASE
.const CX16_TIER_LOAD_END = CX16_TIER_LOAD_BASE + TIER4_SIZE - 1

.assert "CX16 tier load base is bank-window base", CX16_TIER_LOAD_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 largest creature tier fits one banked-RAM window", TIER4_SIZE <= CX16_BANKED_RAM_SIZE, true
.assert "CX16 tier load end stays inside banked-RAM window", CX16_TIER_LOAD_END <= CX16_BANKED_RAM_END, true

cx16_tier_load_index: .byte 0
cx16_tier_load_bank: .byte 0

// Input: A = tier number 1-4.
// Output: carry clear = loaded, carry set = invalid tier or KERNAL load error.
// Restores the caller's selected RAM bank before returning.
// Tier 1-4 map to CX16 RAM banks 4-7.
cx16_load_tier_to_bank:
    cmp #1
    bcc !invalid+
    cmp #5
    bcs !invalid+
    sta cx16_tier_load_index
    clc
    adc #(CX16_TIER_BANK_BASE - 1)
    sta cx16_tier_load_bank

    jsr cx16_save_ram_bank
    lda cx16_tier_load_bank
    jsr cx16_select_ram_bank_a
    lda #<CX16_TIER_LOAD_BASE
    sta cx16_asset_load_addr_lo
    lda #>CX16_TIER_LOAD_BASE
    sta cx16_asset_load_addr_hi

    ldx cx16_tier_load_index
    dex
    lda cx16_tier_file_len,x
    pha
    lda cx16_tier_file_lo,x
    pha
    lda cx16_tier_file_hi,x
    tay
    pla
    tax
    pla
    jsr hal_asset_load_prg_header
    php
    jsr cx16_restore_ram_bank
    plp
    rts

!invalid:
    sec
    rts

cx16_tier_file_lo:
    .byte <cx16_tier_file_1, <cx16_tier_file_2, <cx16_tier_file_3, <cx16_tier_file_4
cx16_tier_file_hi:
    .byte >cx16_tier_file_1, >cx16_tier_file_2, >cx16_tier_file_3, >cx16_tier_file_4
cx16_tier_file_len:
    .byte cx16_tier_file_1_len, cx16_tier_file_2_len, cx16_tier_file_3_len, cx16_tier_file_4_len

cx16_tier_file_1:
    .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $31 // "MONSTER.DB.1"
.label cx16_tier_file_1_len = * - cx16_tier_file_1

cx16_tier_file_2:
    .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $32 // "MONSTER.DB.2"
.label cx16_tier_file_2_len = * - cx16_tier_file_2

cx16_tier_file_3:
    .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $33 // "MONSTER.DB.3"
.label cx16_tier_file_3_len = * - cx16_tier_file_3

cx16_tier_file_4:
    .byte $4d, $4f, $4e, $53, $54, $45, $52, $2e, $44, $42, $2e, $34 // "MONSTER.DB.4"
.label cx16_tier_file_4_len = * - cx16_tier_file_4
