#importonce
// item_catalog.s - CX16 item-catalog bank payload loader.

#import "item_catalog_contract.s"

.const CX16_ITEM_CATALOG_LOAD_BASE = CX16_BANKED_RAM_BASE
.const CX16_ITEM_CATALOG_LOAD_END = CX16_BANKED_RAM_END
.const CX16_ITEM_CATALOG_PRIMARY_BANK = CX16_ITEM_CATALOG_BANK_BASE

.assert "CX16 item catalog load base is bank-window base", CX16_ITEM_CATALOG_LOAD_BASE, CX16_BANKED_RAM_BASE
.assert "CX16 item catalog load end is bank-window end", CX16_ITEM_CATALOG_LOAD_END, CX16_BANKED_RAM_END
.assert "CX16 item catalog primary bank is first catalog bank", CX16_ITEM_CATALOG_PRIMARY_BANK, CX16_ITEM_CATALOG_BANK_BASE

cx16_item_catalog_status: .byte 0
cx16_item_catalog_index: .byte 0
cx16_item_catalog_y_index: .byte 0
cx16_item_catalog_value: .byte 0

// Output: carry clear = item catalog loaded into bank 9.
//         carry set = KERNAL load error.
// Restores the caller's selected RAM bank before returning.
cx16_load_item_catalog:
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    lda #<CX16_ITEM_CATALOG_LOAD_BASE
    sta cx16_asset_load_addr_lo
    lda #>CX16_ITEM_CATALOG_LOAD_BASE
    sta cx16_asset_load_addr_hi
    lda #cx16_item_catalog_file_len
    ldx #<cx16_item_catalog_file
    ldy #>cx16_item_catalog_file
    jsr hal_asset_load_prg_header
    php
    bcs !status+
    lda #1
    sta cx16_item_catalog_status
    bne !restore+
!status:
    lda #0
    sta cx16_item_catalog_status
!restore:
    jsr cx16_restore_ram_bank
    plp
    rts

cx16_item_catalog_file:
    .byte $49, $54, $45, $4d, $43, $41, $54, $2e, $31 // "ITEMCAT.1"
.label cx16_item_catalog_file_len = * - cx16_item_catalog_file

item_load_category_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_CATEGORY_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_display_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_DISPLAY_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_color_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_COLOR_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_weight_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_WEIGHT_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_weight_y:
    sty cx16_item_catalog_y_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldy cx16_item_catalog_y_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_WEIGHT_OFFSET,y
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldy cx16_item_catalog_y_index
    lda cx16_item_catalog_value
    rts

item_load_dmg_dice_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_DMG_DICE_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_dmg_sides_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_DMG_SIDES_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_base_ac_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_BASE_AC_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_base_ac_y:
    sty cx16_item_catalog_y_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldy cx16_item_catalog_y_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_BASE_AC_OFFSET,y
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldy cx16_item_catalog_y_index
    lda cx16_item_catalog_value
    rts

item_load_cost_lo_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_COST_LO_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_cost_hi_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_COST_HI_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_min_level_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_MIN_LEVEL_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_name_lo_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_NAME_LO_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_name_hi_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_NAME_HI_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_token_lo_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_TOKEN_LO_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_token_hi_x:
    stx cx16_item_catalog_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldx cx16_item_catalog_index
    lda CX16_ITEM_CATALOG_LOAD_BASE + CX16_ITEM_CATALOG_TOKEN_HI_OFFSET,x
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldx cx16_item_catalog_index
    lda cx16_item_catalog_value
    rts

item_load_catalog_byte_ptr0_y:
    sty cx16_item_catalog_y_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldy cx16_item_catalog_y_index
    lda (zp_ptr0),y
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldy cx16_item_catalog_y_index
    lda cx16_item_catalog_value
    rts

item_load_catalog_byte_ptr1_y:
    sty cx16_item_catalog_y_index
    jsr cx16_save_ram_bank
    lda #CX16_ITEM_CATALOG_PRIMARY_BANK
    jsr cx16_select_ram_bank_a
    ldy cx16_item_catalog_y_index
    lda (zp_ptr1),y
    sta cx16_item_catalog_value
    jsr cx16_restore_ram_bank
    ldy cx16_item_catalog_y_index
    lda cx16_item_catalog_value
    rts
