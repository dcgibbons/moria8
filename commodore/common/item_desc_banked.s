#importonce
// item_desc_banked.s — Shared item-description formatter.
//
// C64 hosts this in the stable $F000 runtime payload. It is callable from
// $E000 overlays as long as callers have KERNAL banked out.

#import "store_meta_macros.s"

// itemdesc_put_inv_slot — Print inventory/equipment item description.
// Input: X = inventory/equipment slot index.
// Clobbers: A, X, Y, zp_ptr0
put_inv_name_with_ego:
itemdesc_put_inv_slot:
    lda inv_item_id,x
    sta itemdesc_item_id
    lda inv_qty,x
    sta itemdesc_qty
    lda inv_p1,x
    sta itemdesc_p1
    lda inv_to_hit,x
    sta itemdesc_to_hit
    lda inv_to_dam,x
    sta itemdesc_to_dam
    lda inv_to_ac,x
    sta itemdesc_to_ac
    lda inv_flags,x
    sta itemdesc_flags
    lda inv_ego,x
    sta itemdesc_ego
    jmp itemdesc_put_staged

// itemdesc_put_store_slot — Print store/home item description.
// Input: X = absolute store/home slot index.
// Clobbers: A, X, Y, zp_ptr0
itemdesc_put_store_slot:
    lda si_item_id,x
    sta itemdesc_item_id
    lda #1
    sta itemdesc_qty
    lda si_p1,x
    sta itemdesc_p1
    lda si_to_hit,x
    sta itemdesc_to_hit
    lda si_to_dam,x
    sta itemdesc_to_dam
    lda si_to_ac,x
    sta itemdesc_to_ac
    :LoadStoreFlagsX()
    sta itemdesc_flags
    :LoadStoreEgoX()
    sta itemdesc_ego
    jmp itemdesc_put_staged

// itemdesc_put_staged — Print staged item name, ego, sensed marker, and stats.
// Uses itemdesc_* fields. Callable from $F000 banked code and $E000 overlays.
itemdesc_put_staged:
    jsr itemdesc_put_qty_prefix
    lda itemdesc_item_id
    tax
    lda it_category,x
    bne !idps_not_tool+
    lda itemdesc_ego
    beq !idps_not_tool+
    cmp #EGO_TYPE_COUNT
    bcs !idps_not_tool+
    ldx itemdesc_item_id
    jsr put_tool_ego_prefix
    lda itemdesc_item_id
    jsr item_get_name_ptr
    jsr hal_screen_put_string
    jsr itemdesc_put_stats
    jsr itemdesc_put_sensed_suffix
    rts
!idps_not_tool:
    lda itemdesc_item_id
    jsr item_get_name_ptr
    jsr hal_screen_put_string
    lda itemdesc_ego
    cmp #EGO_TYPE_COUNT
    bcc !idps_valid_ego+
    lda #0
!idps_valid_ego:
    jsr banked_ego_put_suffix
    jsr itemdesc_put_stats
    jsr itemdesc_put_sensed_suffix
    rts

itemdesc_put_qty_prefix:
    lda itemdesc_qty
    cmp #2
    bcc !idqp_done+
    lda itemdesc_item_id
    cmp #52
    bcc !idqp_done+
    cmp #55
    bcs !idqp_done+
    lda itemdesc_qty
    jsr screen_put_decimal
    lda #$20
    jsr hal_screen_put_char
!idqp_done:
    rts

itemdesc_put_sensed_suffix:
    lda itemdesc_flags
    and #IF_IDENTIFIED | IF_SENSED
    cmp #IF_SENSED
    bne !idps_done+
    lda #<itemdesc_sensed_suffix
    sta zp_ptr0
    lda #>itemdesc_sensed_suffix
    sta zp_ptr0_hi
    jsr hal_screen_put_string
!idps_done:
    rts

itemdesc_put_stats:
    lda itemdesc_flags
    and #IF_IDENTIFIED
    bne !idps_identified+
    rts
!idps_identified:
    ldx itemdesc_item_id
    lda it_category,x
    cmp #ICAT_WEAPON
    beq !idps_weapon+
    cmp #ICAT_ARMOR
    beq !idps_armor+
    cmp #ICAT_SHIELD
    beq !idps_armor+
    cmp #ICAT_HELM
    beq !idps_armor+
    cmp #ICAT_GLOVES
    beq !idps_armor+
    cmp #ICAT_BOOTS
    beq !idps_armor+
    cmp #ICAT_RING
    beq !idps_ring+
    cmp #ICAT_WAND
    bne !idps_not_wand+
    jmp !idps_charges+
!idps_not_wand:
    cmp #ICAT_STAFF
    bne !idps_not_staff+
    jmp !idps_charges+
!idps_not_staff:
    cmp #ICAT_LIGHT
    bne !idps_not_light+
    jmp !idps_turns+
!idps_not_light:
    rts
!idps_weapon:
    lda itemdesc_to_hit
    ora itemdesc_to_dam
    bne !idps_weapon_has_bonus+
    rts
!idps_weapon_has_bonus:
    lda #$20
    jsr hal_screen_put_char
    lda #$28
    jsr hal_screen_put_char
    lda itemdesc_to_hit
    jsr itemdesc_put_signed
    lda #$2c
    jsr hal_screen_put_char
    lda itemdesc_to_dam
    jsr itemdesc_put_signed
    lda #$29
    jmp hal_screen_put_char
!idps_armor:
    lda #$20
    jsr hal_screen_put_char
    lda #$1b                    // '[' screen code
    jsr hal_screen_put_char
    ldx itemdesc_item_id
    lda it_base_ac,x
    jsr screen_put_decimal
    lda #$2c
    jsr hal_screen_put_char
    lda itemdesc_to_ac
    jsr itemdesc_put_signed
    lda #$1d                    // ']' screen code
    jmp hal_screen_put_char
!idps_ring:
    lda itemdesc_item_id
    cmp #23
    beq !idps_ring_ac+
    cmp #24
    beq !idps_ring_p1+
    rts
!idps_ring_ac:
    lda itemdesc_to_ac
    bne !idps_ring_ac_has_bonus+
    rts
!idps_ring_ac_has_bonus:
    lda #$20
    jsr hal_screen_put_char
    lda #$1b                    // '[' screen code
    jsr hal_screen_put_char
    lda itemdesc_to_ac
    jsr itemdesc_put_signed
    lda #$1d                    // ']' screen code
    jmp hal_screen_put_char
!idps_ring_p1:
    lda itemdesc_p1
    bne !idps_ring_p1_has_bonus+
    rts
!idps_ring_p1_has_bonus:
    lda #$20
    jsr hal_screen_put_char
    lda #$28
    jsr hal_screen_put_char
    lda itemdesc_p1
    jsr itemdesc_put_signed
    lda #$29
    jmp hal_screen_put_char
!idps_charges:
    lda #<itemdesc_charges_str
    ldy #>itemdesc_charges_str
    jmp itemdesc_put_count_suffix
!idps_turns:
    lda #<itemdesc_turns_str
    ldy #>itemdesc_turns_str
itemdesc_put_count_suffix:
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #$20
    jsr hal_screen_put_char
    lda #$28
    jsr hal_screen_put_char
    lda itemdesc_p1
    jsr screen_put_decimal
    lda #$20
    jsr hal_screen_put_char
    jsr hal_screen_put_string
    lda #$29
    jmp hal_screen_put_char

itemdesc_put_signed:
    sta itemdesc_signed
    bmi !idps_negative+
    lda #$2b
    jsr hal_screen_put_char
    lda itemdesc_signed
    jmp screen_put_decimal
!idps_negative:
    lda #$2d
    jsr hal_screen_put_char
    lda itemdesc_signed
    eor #$ff
    clc
    adc #1
    jmp screen_put_decimal

itemdesc_sensed_suffix: .text " (magik)" ; .byte 0
itemdesc_charges_str: .text "charges" ; .byte 0
itemdesc_turns_str: .text "turns" ; .byte 0
itemdesc_item_id: .byte 0
itemdesc_qty:     .byte 0
itemdesc_p1:      .byte 0
itemdesc_to_hit:  .byte 0
itemdesc_to_dam:  .byte 0
itemdesc_to_ac:   .byte 0
itemdesc_flags:   .byte 0
itemdesc_ego:     .byte 0
itemdesc_signed:  .byte 0
