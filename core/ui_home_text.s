// ui_home_text.s — Shared Home/Store helper macros and Home UI strings
//
// Module ownership:
//   owner:
//     !HOME_OVERLAY_SEPARATE: same segment as ui_home.s (RuntimeBanked on C64/C128,
//       TownOverlay on Plus4/Atari8/Apple2/CX16/BBC Master)
//     HOME_OVERLAY_SEPARATE: HomeOverlay (`ovl.home`)
//     Helper macros (`UI_HOME_TEXT_MACROS_ONLY`): expanded by store.s / ui_store.s
//       (TownOverlay) and ui_home.s without duplicating shared logic.
//   lifetime: transient overlay/banked during store or home UI (strings); inline
//     macro expansions live in their caller segments.
//   callers: ui_home.s (strings & macros); store.s, ui_store.s (macros only).

#if !HOME_STORE_SHARED_MACROS_DEFINED
#define HOME_STORE_SHARED_MACROS_DEFINED

// Clear rows 20-23 for store/home prompt and status messages.
// Clobbers: A, X, Y
.macro StoreClearMsgAreaBody() {
    lda #20
!scma_loop:
    pha
    jsr hal_screen_clear_row
    pla
    clc
    adc #1
    cmp #24
    bcc !scma_loop-
    rts
}

// Draw a full-width '-' separator at zp_cursor_row.
// Clobbers: A, X, Y
.macro StoreDrawSeparatorBody() {
    lda #0
    sta zp_cursor_col
    ldx #SCREEN_COLS
!ds_loop:
    lda #$2d                    // Screen code '-'
    jsr hal_screen_put_char
    dex
    bne !ds_loop-
    rts
}

// Print "A)" for the 0-based slot index in counter_var (screen code 'A' = $01).
// Clobbers: A, X, Y
.macro StorePutLetterBody(counter_var) {
    lda counter_var
    clc
    adc #$01                    // Screen code 'A'
    jsr hal_screen_put_char
    lda #$29                    // ')'
    jmp hal_screen_put_char
}

// Scan STORE_MAX_ITEMS slots of store zp_store_idx for FI_EMPTY.
// Output: carry set + X = absolute slot index; carry clear = full.
// Clobbers: A, X
.macro StoreFindEmptySlotBody(counter_var) {
    ldx zp_store_idx
    lda store_base_idx,x
    tax                         // X = base slot
    lda #0
    sta counter_var             // Counter 0..STORE_MAX_ITEMS-1
!sfes_loop:
    lda counter_var
    cmp #STORE_MAX_ITEMS
    bcs !sfes_full+
    :AuxReadX(si_item_id)
    cmp #FI_EMPTY
    beq !sfes_found+
    inx
    inc counter_var
    jmp !sfes_loop-
!sfes_found:
    sec
    rts
!sfes_full:
    clc
    rts
}

// Render rows 3-18 of store/home inventory items.
// Macro parameters keep store (TownOverlay) and home (HomeOverlay) self-contained
// without sharing overlay subroutines when HOME_OVERLAY_SEPARATE is enabled.
.macro StoreDrawSlotListBody(abs_slot_var, row_var, counter_var, put_letter_fn, put_slot_fn, with_price, price_hook_fn) {
    lda #COL_LGREY
    sta zp_text_color

    ldx zp_store_idx
    lda store_base_idx,x
    sta abs_slot_var            // Starting absolute slot

    lda #3
    sta row_var                 // Current display row
    lda #0
    sta counter_var             // Slot counter 0-15

!sds_item_loop:
    lda counter_var
    cmp #STORE_MAX_ITEMS
    bcc !sds_item_cont+
    jmp !sds_items_done+
!sds_item_cont:

    lda row_var
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Check if slot occupied
    ldy abs_slot_var
    :AuxReadY(si_item_id)
    cmp #FI_EMPTY
    bne !sds_has_item+
    jmp !sds_empty_slot+
!sds_has_item:

    // Letter: A + slot_counter (screen code A = $01)
    lda #COL_WHITE
    sta zp_text_color
    jsr put_letter_fn
    lda #$20                    // Space
    jsr hal_screen_put_char

    // Item description
    lda #COL_LGREY
    sta zp_text_color
    ldx abs_slot_var
    jsr put_slot_fn

    .if (with_price != 0) {
        jsr price_hook_fn
    }
    jmp !sds_next_slot+

!sds_empty_slot:
    // Show dash for empty slot
    lda #COL_DGREY
    sta zp_text_color
    jsr put_letter_fn

!sds_next_slot:
    lda #COL_LGREY
    sta zp_text_color
    inc row_var
    inc abs_slot_var
    inc counter_var
    jmp !sds_item_loop-

!sds_items_done:
}

// Tail-call print the player's 24-bit gold total at the current cursor.
.macro StorePutGoldValueBody() {
    lda player_data + PL_GOLD_0
    sta zp_temp0
    lda player_data + PL_GOLD_1
    sta zp_temp1
    lda player_data + PL_GOLD_2
    sta nf_value_2
    jmp screen_put_decimal_u24
}

#endif

#if !UI_HOME_TEXT_MACROS_ONLY && !UI_HOME_TEXT_EMITTED
#define UI_HOME_TEXT_EMITTED

#if HOME_OVERLAY_SEPARATE
hm_title_str:
    .text "Home" ; .byte 0
hm_gold_str:
    .text "Gold: " ; .byte 0
#endif

// Padded to the store menu's 18 columns: it is written over that menu.
hm_menu_str:
    .text "D)ep R)et Q)uit   " ; .byte 0
hm_retrieve_str:
    .text "Which? (a-p)" ; .byte 0
hm_deposit_title:
    .text "Deposit" ; .byte 0
hm_which_str:
    .text "Which item? (Q)" ; .byte 0
hm_deposited_str:
    .text "Deposited!" ; .byte 0
hm_retrieved_str:
    .text "Retrieved!" ; .byte 0
hm_home_full_str:
    .text "Home full!" ; .byte 0
hm_inv_full_str:
    .text "Pack full!" ; .byte 0

#endif
