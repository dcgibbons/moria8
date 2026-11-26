#importonce
// ui_home.s — Player Home UI (deposit/retrieve items)
//
// Module ownership:
//   owner:
//     !HOME_OVERLAY_SEPARATE: RuntimeBanked on C64/C128 ($F000), TownOverlay on
//       Plus4/Atari8/Apple2/CX16/BBC Master.
//     HOME_OVERLAY_SEPARATE: self-contained HomeOverlay (`ovl.home`) with no
//       calls or data reads into TownOverlay (store.s / ui_store.s).
//   lifetime:
//     !HOME_OVERLAY_SEPARATE: persistent in RuntimeBanked or transient in TownOverlay.
//     HOME_OVERLAY_SEPARATE: transient overlay; loaded on Home entry, released on exit.
//   callers:
//     !HOME_OVERLAY_SEPARATE: store_enter (`core/ui_store.s`) on #STORE_HOME.
//     HOME_OVERLAY_SEPARATE: port `tramp_store_enter` (via `game_loop.s:try_store_entry`)
//       dispatches #STORE_HOME directly into `OVL_HOME` (`home_enter`) and
//       restores the caller's bank/overlay on return.
//   .assert: protected by each port's RuntimeBanked/TownOverlay/HomeOverlay end .assert.
//
// No pricing — items are stored for free.

#import "input_ui_helpers.s"
#import "store_meta_macros.s"
#define UI_HOME_TEXT_MACROS_ONLY
#import "ui_home_text.s"
#undef UI_HOME_TEXT_MACROS_ONLY

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

home_put_col1_string:
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    stx zp_ptr0
    sty zp_ptr0_hi
    jmp hal_screen_put_string

#if HOME_OVERLAY_SEPARATE
.const HOME_GOLD_COL = 21

#if HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL
home_inv_add_carried:
{
    :InvAddCarriedBody()
}
#endif

// Self-contained Home screen renderer when HomeOverlay is separate from TownOverlay.
home_draw_screen:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all

    // Row 0: Home title (white); row 1 remains blank (Home has no shopkeeper).
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    ldx #<hm_title_str
    ldy #>hm_title_str
    jsr home_put_col1_string

    // Row 2: Separator
    lda #COL_DGREY
    sta zp_text_color
    lda #2
    jsr home_draw_separator_at_a

    // Rows 3-18: Item list (no prices)
#if ITEMDESC_STORE_SLOT_DUPLICATED
    :StoreDrawSlotListBody(hm_store_slot, hm_row, hm_save_x, home_put_letter, itemdesc_put_store_slot_home, 0, 0)
#else
    :StoreDrawSlotListBody(hm_store_slot, hm_row, hm_save_x, home_put_letter, itemdesc_put_store_slot, 0, 0)
#endif

    // Row 19: Home menu, then the gold to its right
    lda #COL_WHITE
    sta zp_text_color
    lda #STORE_MENU_ROW
    ldx #<hm_menu_str
    ldy #>hm_menu_str
    jsr home_put_col1_string

    lda #COL_YELLOW
    sta zp_text_color
    lda #STORE_MENU_ROW
    sta zp_cursor_row
    lda #HOME_GOLD_COL
    sta zp_cursor_col
    lda #<hm_gold_str
    ldy #>hm_gold_str
    sta zp_ptr0
    sty zp_ptr0_hi
    jsr hal_screen_put_string

    :StorePutGoldValueBody()

home_draw_separator_at_a:
    sta zp_cursor_row
    :StoreDrawSeparatorBody()

home_put_letter:
    :StorePutLetterBody(hm_save_x)

home_clear_msg_area:
    :StoreClearMsgAreaBody()

home_find_empty_slot:
    :StoreFindEmptySlotBody(hm_save_x)

#if ITEMDESC_STORE_SLOT_DUPLICATED
#import "itemdesc_store_slot_macro.s"
itemdesc_put_store_slot_home:
    :ItemdescPutStoreSlotBody()
#endif
#endif

// ============================================================
// home_enter — Main home mode loop
// Input: zp_store_idx = STORE_HOME (7)
// Clobbers: everything
// ============================================================
home_enter:
#if HOME_OVERLAY_SEPARATE
    jsr home_draw_screen
#else
    jsr store_draw_screen       // Reuses overlay's draw (skips prices for home)

    // Overwrite the store menu with the home menu (the gold stays beside it)
    lda #COL_WHITE
    sta zp_text_color
    lda #STORE_MENU_ROW
    ldx #<hm_menu_str
    ldy #>hm_menu_str
    jsr home_put_col1_string
#endif

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
    jmp ui_help_clear_all

// ============================================================
// home_retrieve — Take an item from home
// ============================================================
home_retrieve:
    // Prompt on row 20
#if HOME_OVERLAY_SEPARATE
    jsr home_clear_msg_area
#else
    jsr store_clear_msg_area
#endif
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    ldx #<hm_retrieve_str
    ldy #>hm_retrieve_str
    jsr home_put_col1_string

    jsr input_prepare_followup_key
    jsr hal_input_get_key

    // Q/ESC/space = cancel
    cmp #PETSCII_HM_Q
    beq !hr_cancel_relay+
    jsr input_is_modal_escape_key
    beq !hr_cancel_relay+
    cmp #PETSCII_HM_SPACE
    beq !hr_cancel_relay+

    // Convert PETSCII letter to slot index (A=0, P=15)
    sec
    sbc #PETSCII_HM_A
    bcc !hr_cancel_relay+       // Below 'A'
    cmp #STORE_MAX_ITEMS
    bcs !hr_cancel_relay+       // Above 'P'

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
    :AuxReadX(si_item_id)
    cmp #FI_EMPTY
    bne !hr_slot_occupied+
    rts                         // Empty slot
!hr_slot_occupied:

    // Copy item from store to inventory: a full pack still takes one that
    // stacks (VMS inven_check_num, Umoria inventoryCanCarryItemCount)
    ldx hm_store_slot
    :AuxReadX(si_item_id)
    sta fi_add_id
    :AuxReadX(si_qty)
    sta fi_add_qty
    :AuxReadX(si_p1)
    sta fi_add_p1
    :AuxReadX(si_to_hit)
    sta fi_add_to_hit
    :AuxReadX(si_to_dam)
    sta fi_add_to_dam
    :AuxReadX(si_to_ac)
    sta fi_add_to_ac
    :LoadStoreFlagsX()
    sta fi_add_flags
    :LoadStoreMetaHiX()
    sta fi_add_ego
#if HOME_OVERLAY_SEPARATE && HAL_PLATFORM_INV_ADD_CARRIED_EXTERNAL
    jsr home_inv_add_carried        // the weight limit, then a slot
#else
    jsr inv_add_carried             // the weight limit, then a slot
#endif
    bcs !hr_has_room+

    // Inventory full, or too heavy (X = the refusal)
    lda #COL_RED
    sta zp_text_color
    cpx #HSTR_UIS_TOO_HEAVY
    bne !hr_full+
    jsr huff_decode_string          // "You can't carry that much weight."
    ldx zp_ptr0
    ldy zp_ptr0_hi
    bne !hr_refusal+                // always: the buffer is not in page zero
!hr_full:
    ldx #<hm_inv_full_str
    ldy #>hm_inv_full_str
!hr_refusal:
    lda #22
    jsr home_put_col1_string
    jmp hal_input_get_key           // Wait, tail call

!hr_has_room:
    // Clear store slot
    ldx hm_store_slot
    lda #FI_EMPTY
    :AuxWriteX(si_item_id)
    lda #0
    :AuxWriteX(si_qty)
    :AuxWriteX(si_p1)
    :AuxWriteX(si_to_hit)
    :AuxWriteX(si_to_dam)
    :AuxWriteX(si_to_ac)
    :AuxWriteX(si_meta)
    :AuxWriteX(si_meta_hi)

    // Success message
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    ldx #<hm_retrieved_str
    ldy #>hm_retrieved_str
    jsr home_put_col1_string

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
    ldx #<hm_deposit_title
    ldy #>hm_deposit_title
    jsr home_put_col1_string

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
    ldx #<hm_which_str
    ldy #>hm_which_str
    jsr home_put_col1_string

    jsr input_prepare_followup_key
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
#if HOME_OVERLAY_SEPARATE
    jsr home_find_empty_slot
#else
    jsr store_find_empty_slot
#endif
    bcs !hd_has_slot+

    // Home full
    lda #COL_RED
    sta zp_text_color
    lda #22
    ldx #<hm_home_full_str
    ldy #>hm_home_full_str
    jsr home_put_col1_string
    jmp hal_input_get_key           // Wait, tail call

!hd_has_slot:
    // X = empty absolute slot
    stx hm_store_slot
    // Transfer item from inventory to home
    ldx hm_inv_slot
    lda inv_item_id,x
    ldy hm_store_slot
    :AuxWriteY(si_item_id)
    lda inv_qty,x
    :AuxWriteY(si_qty)
    lda inv_p1,x
    :AuxWriteY(si_p1)
    lda inv_to_hit,x
    :AuxWriteY(si_to_hit)
    lda inv_to_dam,x
    :AuxWriteY(si_to_dam)
    lda inv_to_ac,x
    :AuxWriteY(si_to_ac)
    :StoreStoreMetaYFromInvX()

    // Remove from inventory
    ldx hm_inv_slot
    jsr inv_remove_item

    // Success message
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    ldx #<hm_deposited_str
    ldy #>hm_deposited_str
    jsr home_put_col1_string

    lda #SFX_PICKUP
    jsr hal_sound_play
!hd_cancel:
    rts
