#importonce
// ui_home.s — Player Home UI (deposit/retrieve items)
//
// Runs at $F000 (banked code area, $01=$35).
// Called directly from store_enter in town overlay ($E000).
// No pricing — items are stored for free.

#import "store_meta_macros.s"

// ============================================================
// PETSCII key constants (duplicated from ui_store.s — overlay segment not visible here)
// ============================================================
.const PETSCII_HM_A      = $41
.const PETSCII_HM_D      = $44
.const PETSCII_HM_Q      = $51
.const PETSCII_HM_R      = $52
.const PETSCII_HM_SPACE  = $20

// ============================================================
// Scratch variables
// ============================================================
hm_inv_slot:   .byte 0     // Player inventory slot for deposit
hm_store_slot: .byte 0     // Store slot for retrieve
hm_row:        .byte 0     // Current screen row
hm_save_x:     .byte 0     // Saved index register

// ============================================================
// home_enter — Main home mode loop
// Input: zp_store_idx = STORE_HOME (7)
// Clobbers: everything
// ============================================================
home_enter:
    jsr store_draw_screen       // Reuses overlay's draw (skips prices for home)

    // Overwrite menu row 18 with home menu
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_menu_str
    sta zp_ptr0
    lda #>hm_menu_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

!he_loop:
    jsr hal_input_get_key

    // D = deposit
    cmp #PETSCII_HM_D
    bne !he_not_dep+
    jsr home_deposit
    jmp home_enter              // Refresh screen
!he_not_dep:

    // R = retrieve
    cmp #PETSCII_HM_R
    bne !he_not_ret+
    jsr home_retrieve
    jmp home_enter              // Refresh screen
!he_not_ret:

    // Q, ESC, or space = exit
    cmp #PETSCII_HM_Q
    beq !he_exit+
    jsr input_is_modal_escape_key
    beq !he_exit+
    cmp #PETSCII_HM_SPACE
    beq !he_exit+

    // Unknown key — ignore
    jmp !he_loop-

!he_exit:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    rts

// ============================================================
// home_retrieve — Take an item from home
// ============================================================
home_retrieve:
    // Prompt on row 20
    jsr store_clear_msg_area
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_retrieve_str
    sta zp_ptr0
    lda #>hm_retrieve_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    jsr hal_input_get_key

    // Q/ESC/space = cancel
    cmp #PETSCII_HM_Q
    beq !hr_cancel_relay+
    jsr input_is_modal_escape_key
    beq !hr_cancel_relay+
    cmp #PETSCII_HM_SPACE
    beq !hr_cancel_relay+

    // Convert PETSCII letter to slot index (A=0, L=11)
    sec
    sbc #PETSCII_HM_A
    bcc !hr_cancel_relay+       // Below 'A'
    cmp #STORE_MAX_ITEMS
    bcs !hr_cancel_relay+       // Above 'L'

    jmp !hr_valid_slot+
!hr_cancel_relay:
    rts                         // Early return relay

!hr_valid_slot:
    sta hm_store_slot

    // Get absolute slot
    ldx zp_store_idx
    lda store_base_idx,x
    clc
    adc hm_store_slot
    sta hm_store_slot           // Now absolute slot

    // Check if slot occupied
    tax
    lda si_item_id,x
    cmp #FI_EMPTY
    bne !hr_slot_occupied+
    rts                         // Empty slot
!hr_slot_occupied:

    // Check inventory room
    jsr inv_count_items
    cmp #MAX_INV_SLOTS
    bcc !hr_has_room+

    // Inventory full
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_inv_full_str
    sta zp_ptr0
    lda #>hm_inv_full_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    jmp hal_input_get_key           // Wait, tail call

!hr_has_room:
    // Copy item from store to inventory
    ldx hm_store_slot
    lda si_item_id,x
    sta fi_add_id
    lda si_qty,x
    sta fi_add_qty
    lda si_p1,x
    sta fi_add_p1
    lda si_to_hit,x
    sta fi_add_to_hit
    lda si_to_dam,x
    sta fi_add_to_dam
    lda si_to_ac,x
    sta fi_add_to_ac
    :LoadStoreFlagsX()
    sta fi_add_flags
    :LoadStoreEgoX()
    sta fi_add_ego
    jsr inv_add_item

    // Clear store slot
    ldx hm_store_slot
    lda #FI_EMPTY
    sta si_item_id,x
    lda #0
    sta si_qty,x
    sta si_p1,x
    sta si_to_hit,x
    sta si_to_dam,x
    sta si_to_ac,x
    sta si_meta,x

    // Success message
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_retrieved_str
    sta zp_ptr0
    lda #>hm_retrieved_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #SFX_PICKUP
    jsr hal_sound_play
!hr_cancel:
    rts

// ============================================================
// home_deposit — Store an item from inventory into home
// ============================================================
home_deposit:
    // Draw inventory list
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_deposit_title
    sta zp_ptr0
    lda #>hm_deposit_title
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    // List inventory items
    lda #2
    sta hm_row
    lda #0
    sta hm_save_x              // Slot counter

!hd_inv_loop:
    lda hm_save_x
    cmp #MAX_INV_SLOTS
    bcs !hd_inv_done+

    // Check if slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !hd_inv_next+

    lda hm_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    lda #COL_LGREY
    sta zp_text_color

    // Letter
    lda hm_save_x
    clc
    adc #$01                    // Screen code 'A'
    jsr hal_screen_put_char
    lda #$29                    // ')'
    jsr hal_screen_put_char
    lda #$20                    // Space
    jsr hal_screen_put_char

    // Item description with ego/status/stat suffixes
    ldx hm_save_x
    jsr itemdesc_put_inv_slot

    inc hm_row

!hd_inv_next:
    inc hm_save_x
    jmp !hd_inv_loop-

!hd_inv_done:
    // Prompt
    lda #COL_WHITE
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_which_str
    sta zp_ptr0
    lda #>hm_which_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    jsr hal_input_get_key

    // Q/escape-equivalent/space = cancel
    cmp #PETSCII_HM_Q
    beq !hd_cancel_relay+
    jsr input_is_modal_escape_key
    beq !hd_cancel_relay+
    cmp #PETSCII_HM_SPACE
    beq !hd_cancel_relay+

    // Convert PETSCII to slot (A=0, V=21)
    sec
    sbc #PETSCII_HM_A
    bcc !hd_cancel_relay+
    cmp #MAX_INV_SLOTS
    bcs !hd_cancel_relay+

    jmp !hd_valid_slot+
!hd_cancel_relay:
    rts                         // Early return relay

!hd_valid_slot:
    sta hm_inv_slot

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !hd_slot_occupied+
    jmp !hd_cancel+
!hd_slot_occupied:

    // Find empty home slot
    jsr store_find_empty_slot
    bcs !hd_has_slot+

    // Home full
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_home_full_str
    sta zp_ptr0
    lda #>hm_home_full_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    jmp hal_input_get_key           // Wait, tail call

!hd_has_slot:
    // X = empty absolute slot
    stx hm_store_slot
    // Transfer item from inventory to home
    ldx hm_inv_slot
    lda inv_item_id,x
    ldy hm_store_slot
    sta si_item_id,y
    lda inv_qty,x
    sta si_qty,y
    lda inv_p1,x
    sta si_p1,y
    lda inv_to_hit,x
    sta si_to_hit,y
    lda inv_to_dam,x
    sta si_to_dam,y
    lda inv_to_ac,x
    sta si_to_ac,y
    :StoreStoreMetaYFromInvX()

    // Remove from inventory
    ldx hm_inv_slot
    jsr inv_remove_item

    // Success message
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hm_deposited_str
    sta zp_ptr0
    lda #>hm_deposited_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #SFX_PICKUP
    jsr hal_sound_play
    jsr hal_input_get_key
!hd_cancel:
    rts
