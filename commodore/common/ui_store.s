#importonce
// ui_store.s — Store screen rendering, buy/sell UI, entry detection
//
// The store is a separate mode with its own input loop.
// Player enters by stepping on a store door tile in town.

// ============================================================
// PETSCII key constants for store UI
// ============================================================
.const PETSCII_B      = $42
.const PETSCII_S      = $53
.const PETSCII_Y      = $59
.const PETSCII_N      = $4e
.const PETSCII_Q      = $51
.const PETSCII_ESC    = $1b   // RUN/STOP mapped as ESC
.const PETSCII_SPACE  = $20
.const PETSCII_A      = $41
.const HG_MIN_CONCESSION = 5
.const HG_MAX_CONCESSION = 15

#if C128
.const USTORE_PRICE_COL = SCREEN_COLS - 12
#else
.const USTORE_PRICE_COL = 31
#endif

// Message table indices for show_msg
.const MSG_GOLD       = 0
.const MSG_MENU       = 1
.const MSG_BUY_WHICH  = 2
.const MSG_KICKED     = 3
.const MSG_BOUGHT     = 4
.const MSG_PRICE      = 5
.const MSG_NO_AFFORD  = 6
.const MSG_PACK_FULL  = 7
.const MSG_SELL_TITLE = 8
.const MSG_SELL_WHICH = 9
.const MSG_OFFER      = 10
.const MSG_SOLD       = 11
.const MSG_ASKS       = 12
.const MSG_YOUR_OFFER = 13
.const MSG_OFFERS     = 14
.const MSG_YOUR_PRICE = 15
.const MSG_COUNTER    = 16
.const MSG_FINAL      = 17
.const MSG_TAKE       = 18
.const MSG_AGREED     = 19

// ============================================================
// Subroutines
// ============================================================
// Note: check_player_on_store_door is in store_data.s (main RAM)

// store_enter — Main store mode loop
// Input: zp_store_idx = store index (0-5)
// Clobbers: everything
store_enter:
    // Home uses separate UI at $F000
    lda zp_store_idx
    cmp #STORE_HOME
    bne !se_not_home+
    jmp home_enter              // $F000 banked code, same $01=$35
!se_not_home:
    lda #0
    sta hg_insults              // Reset insult counter for this visit
    jsr store_draw_screen

!se_loop:
    jsr input_get_key

    // B = buy
    cmp #PETSCII_B
    bne !se_not_buy+
    jsr store_buy
    jsr store_draw_screen       // Refresh after transaction
    jmp !se_loop-
!se_not_buy:

    // S = sell
    cmp #PETSCII_S
    bne !se_not_sell+
    jsr store_sell
    jsr store_draw_screen       // Refresh after transaction
    jmp !se_loop-
!se_not_sell:

    // Q, ESC, or space = exit
    cmp #PETSCII_Q
    beq !se_exit+
    cmp #PETSCII_ESC
    beq !se_exit+
    cmp #PETSCII_SPACE
    beq !se_exit+

    // Unknown key — ignore
    jmp !se_loop-

!se_exit:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    rts

// ============================================================
// Screen drawing
// ============================================================

// store_draw_screen — Draw the full store UI
// Input: zp_store_idx
// Clobbers: everything
store_draw_screen:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all

    // Row 0: Store name (white)
    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    ldx zp_store_idx
    lda store_name_lo,x
    sta zp_ptr0
    lda store_name_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 1: Owner name (light grey)
    lda #COL_LGREY
    sta zp_text_color
    lda #1
    sta zp_cursor_row
    lda #2
    sta zp_cursor_col
    ldx zp_store_idx
    lda store_owner_lo,x
    sta zp_ptr0
    lda store_owner_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 2: Separator
    lda #COL_DGREY
    sta zp_text_color
    lda #2
    sta zp_cursor_row
    jsr draw_separator

    // Rows 3-14: Item list
    lda #COL_LGREY
    sta zp_text_color

    ldx zp_store_idx
    lda store_base_idx,x
    sta sb_abs_slot             // Starting absolute slot

    lda #3
    sta sd_row                  // Current display row
    lda #0
    sta sd_save_x               // Slot counter 0-11

!sds_item_loop:
    lda sd_save_x
    cmp #STORE_MAX_ITEMS
    bcc !sds_item_cont+
    jmp !sds_items_done+
!sds_item_cont:

    lda sd_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Check if slot occupied
    ldy sb_abs_slot
    lda si_item_id,y
    cmp #FI_EMPTY
    bne !sds_has_item+
    jmp !sds_empty_slot+
!sds_has_item:

    // Letter: A + slot_counter (screen code A = $01)
    lda #COL_WHITE
    sta zp_text_color
    lda sd_save_x
    clc
    adc #$01                    // Screen code 'A'
    jsr screen_put_char
    lda #$29                    // ')'
    jsr screen_put_char
    lda #$20                    // Space
    jsr screen_put_char

    // Item name — check for tool ego prefix (R14)
    lda #COL_LGREY
    sta zp_text_color
    ldy sb_abs_slot
    lda si_item_id,y
    sta sd_save_item_id
    tax
    lda it_category,x
    bne !sds_normal_name+
    ldy sb_abs_slot
    lda si_ego,y
    beq !sds_normal_name+
    // Tool ego prefix
    ldx sd_save_item_id
    jsr put_tool_ego_prefix
!sds_normal_name:
    lda sd_save_item_id
    jsr item_get_name_ptr
    jsr screen_put_string

    // Skip price display for Home (no prices)
    lda zp_store_idx
    cmp #STORE_HOME
    beq !sds_next_slot+

    // Price column is platform-tuned (C128 uses wider right anchor).
    lda sd_row
    sta zp_cursor_row
    lda #USTORE_PRICE_COL
    sta zp_cursor_col
    lda #COL_YELLOW
    sta zp_text_color

    ldy sb_abs_slot
    lda si_ego,y
    sta sb_item_ego             // Pass ego for pricing (R14)
    lda si_p1,y
    sta sb_item_p1              // Pass enchantment/charges for pricing
    lda si_item_id,y
    jsr calc_store_buy_price    // Dispatches to BM or normal pricing

    lda sb_price_lo
    sta zp_temp0
    lda sb_price_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    // "GP" label
    lda #$20                    // Space
    jsr screen_put_char
    lda #$07                    // Screen code 'G'
    jsr screen_put_char
    lda #$10                    // Screen code 'P'
    jsr screen_put_char

    jmp !sds_next_slot+

!sds_empty_slot:
    // Show dash for empty slot
    lda #COL_DGREY
    sta zp_text_color
    lda sd_save_x
    clc
    adc #$01
    jsr screen_put_char
    lda #$29                    // ')'
    jsr screen_put_char

!sds_next_slot:
    lda #COL_LGREY
    sta zp_text_color
    inc sd_row
    inc sb_abs_slot
    inc sd_save_x
    jmp !sds_item_loop-

!sds_items_done:
    // Row 15: Separator
    lda #COL_DGREY
    sta zp_text_color
    lda #15
    sta zp_cursor_row
    jsr draw_separator

    // Row 16: Gold display
    ldx #MSG_GOLD
    jsr show_msg

    // Check for >65535 gold
    lda player_data + PL_GOLD_2
    bne !sds_big_gold+

    // Normal display
    lda player_data + PL_GOLD_0
    sta zp_temp0
    lda player_data + PL_GOLD_1
    sta zp_temp1
    jsr screen_put_decimal_16
    jmp !sds_gold_done+

!sds_big_gold:
    ldx #HSTR_UIS_BIG_GOLD
    jsr huff_decode_string
    jsr screen_put_string

!sds_gold_done:
    // Row 18: Menu
    ldx #MSG_MENU
    jsr show_msg

    rts

// ============================================================
// Buy flow
// ============================================================

// store_buy — Buy an item from the store
// Input: zp_store_idx
// Clobbers: everything
store_buy:
    // Prompt: "BUY WHICH ITEM? (A-L)"
    jsr store_clear_msg_area
    ldx #MSG_BUY_WHICH
    jsr show_msg

    // Get key
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key

    // Q/ESC/space = cancel
    jsr check_cancel
    bne !sb_not_cancel+
    rts
!sb_not_cancel:

    // Convert PETSCII letter to slot index (A=0, L=11)
    sec
    sbc #PETSCII_A
    bcs !sb_above_a+
    rts                         // Below 'A'
!sb_above_a:
    cmp #STORE_MAX_ITEMS
    bcc !sb_valid_slot+
    rts                         // Above 'L'
!sb_valid_slot:

    sta zp_store_slot

    // Get absolute slot
    ldx zp_store_idx
    lda store_base_idx,x
    clc
    adc zp_store_slot
    sta sb_abs_slot

    // Check if slot is occupied
    tax
    lda si_item_id,x
    cmp #FI_EMPTY
    bne !sb_occupied+
    rts                         // Empty slot
!sb_occupied:

    // Calculate buy price
    ldx sb_abs_slot
    lda si_ego,x
    sta sb_item_ego             // Pass ego for pricing (R14)
    lda si_p1,x
    sta sb_item_p1              // Pass enchantment/charges for pricing
    lda si_item_id,x
    jsr calc_store_buy_price    // Dispatches to BM or normal pricing

    // Cheap items (≤ 10 GP) or BM: use simple Y/N flow (no haggling)
    ldx zp_store_idx
    cpx #STORE_BM
    beq !sb_yn_confirm+         // BM never haggles
    lda sb_price_hi
    bne !sb_haggle_check+       // > 255, definitely not cheap
    lda sb_price_lo
    cmp #11
    bcs !sb_haggle_check+       // > 10 GP

!sb_yn_confirm:
    // --- Y/N confirm (cheap item or BM) ---
    jsr sbuy_show_price
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    cmp #PETSCII_Y
    beq sbuy_execute
    rts

!sb_haggle_check:
    // Check if kicked from this store
    ldx zp_store_idx
    lda hg_kicked,x
    beq !sb_do_haggle+
    jsr store_clear_msg_area
    ldx #MSG_KICKED
    jsr show_msg
    jmp input_get_key           // Wait for key, tail call returns

!sb_do_haggle:
    jsr haggle_buy
    bcs sbuy_execute            // Carry set = deal made
    rts                         // Cancelled or no deal

sbuy_execute:
    // Check if player can afford it
    jsr gold_check_afford
    bcs !sb_can_afford+
    jmp sbuy_no_gold
!sb_can_afford:

    // Check inventory room
    jsr inv_count_items
    cmp #MAX_INV_SLOTS
    bcc !sb_has_room+
    jmp sbuy_full
!sb_has_room:
    jsr hg_decrease_insults

    // --- Execute purchase ---
    jsr gold_subtract_price

    // Copy item from store to inventory
    ldx sb_abs_slot
    lda si_item_id,x
    sta fi_add_id
    lda si_qty,x
    sta fi_add_qty
    lda si_p1,x
    sta fi_add_p1
    lda si_flags,x
    sta fi_add_flags
    lda si_ego,x
    sta fi_add_ego
    jsr inv_add_item

    // Remove from store
    ldx sb_abs_slot
    lda #FI_EMPTY
    sta si_item_id,x
    lda #0
    sta si_qty,x
    sta si_p1,x
    sta si_flags,x
    sta si_ego,x

    // Success message
    jsr store_clear_msg_area
    ldx #MSG_BOUGHT
    jsr show_msg

    lda #SFX_PICKUP
    jsr sound_play
    rts

// sbuy_show_price — Display price confirmation for buy
sbuy_show_price:
    jsr store_clear_msg_area
    ldx #MSG_PRICE
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda sb_price_lo
    sta zp_temp0
    lda sb_price_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_UIS_GP_BUY
    jsr huff_decode_string
    jmp screen_put_string       // Tail call

sbuy_no_gold:
    jsr store_clear_msg_area
    ldx #MSG_NO_AFFORD
    jmp show_msg                // Tail call

sbuy_full:
    jsr store_clear_msg_area
    ldx #MSG_PACK_FULL
    jmp show_msg                // Tail call

// ============================================================
// Sell flow
// ============================================================

// store_sell — Sell an item to the store
// Input: zp_store_idx
// Clobbers: everything
store_sell:
    // Draw sell sub-screen: inventory list
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all

    ldx #MSG_SELL_TITLE
    jsr show_msg

    // Separator
    lda #COL_DGREY
    sta zp_text_color
    lda #1
    sta zp_cursor_row
    jsr draw_separator

    // List inventory items (A-V = slots 0-21)
    lda #2
    sta sd_row
    lda #0
    sta sd_save_x               // Slot counter

!ssl_inv_loop:
    lda sd_save_x
    cmp #MAX_INV_SLOTS
    bcc !ssl_inv_cont+
    jmp !ssl_inv_done+
!ssl_inv_cont:

    // Check if slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !ssl_inv_next+

    lda sd_row
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col

    // Check if store buys this category
    ldx sd_save_x
    lda inv_item_id,x
    tax
    lda it_category,x
    jsr check_store_category
    bcs !ssl_buyable+

    // Store doesn't buy it — grey
    lda #COL_DGREY
    sta zp_text_color
    jmp !ssl_print_item+

!ssl_buyable:
    lda #COL_LGREY
    sta zp_text_color

!ssl_print_item:
    // Letter
    lda sd_save_x
    clc
    adc #$01                    // Screen code 'A'
    jsr screen_put_char
    lda #$29                    // ')'
    jsr screen_put_char
    lda #$20                    // Space
    jsr screen_put_char

    // Item name
    ldx sd_save_x
    lda inv_item_id,x
    jsr item_get_name_ptr
    jsr screen_put_string

    inc sd_row

!ssl_inv_next:
    inc sd_save_x
    jmp !ssl_inv_loop-

!ssl_inv_done:
    // Prompt
    ldx #MSG_SELL_WHICH
    jsr show_msg

    // Get key
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key

    // Q/ESC/space = cancel
    jsr check_cancel
    bne !ss_not_cancel+
    rts
!ss_not_cancel:

    // Convert PETSCII to slot (A=0, V=21)
    sec
    sbc #PETSCII_A
    bcs !ss_above_a+
    rts
!ss_above_a:
    cmp #MAX_INV_SLOTS
    bcc !ss_valid+
    rts
!ss_valid:

    sta ss_inv_slot

    // Check slot occupied
    tax
    lda inv_item_id,x
    cmp #FI_EMPTY
    bne !ss_occupied+
    rts
!ss_occupied:
    sta ss_item_id

    // Check if store buys this category
    tax
    lda it_category,x
    jsr check_store_category
    bcs !ssell_cat_ok+

    // Store doesn't buy it
    ldx #HSTR_UIS_NO_BUY
    jsr ssell_show_error
    rts

!ssell_cat_ok:
    // Check if item is cursed (RP14-4)
    ldx ss_inv_slot
    lda inv_flags,x
    and #IF_CURSED
    beq !ssell_not_cursed+

    ldx #HSTR_UIS_CURSED
    jsr ssell_show_error
    rts

!ssell_not_cursed:
    // Calculate sell price
    ldx ss_inv_slot
    lda inv_ego,x
    sta sb_item_ego             // Pass ego for pricing (R14)
    lda inv_p1,x
    sta sb_item_p1              // Pass enchantment/charges for pricing
    lda ss_item_id
    jsr calc_store_sell_price   // Dispatches to BM or normal pricing

    // Check for worthless items
    lda sb_price_lo
    ora sb_price_hi
    bne !ssell_has_value+

    ldx #HSTR_UIS_WORTHLESS
    jsr ssell_show_error
    rts

!ssell_has_value:
    // Cheap items (≤ 10 GP) or BM: use simple Y/N flow (no haggling)
    ldx zp_store_idx
    cpx #STORE_BM
    beq !ssell_yn_confirm+      // BM never haggles
    lda sb_price_hi
    bne !ssell_haggle_check+
    lda sb_price_lo
    cmp #11
    bcs !ssell_haggle_check+

!ssell_yn_confirm:
    // --- Y/N confirm (cheap item or BM) ---
    jsr ssell_show_offer
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    cmp #PETSCII_Y
    beq ssell_execute
    rts

!ssell_haggle_check:
    // Check if kicked from this store
    ldx zp_store_idx
    lda hg_kicked,x
    beq !ssell_do_haggle+
    ldx #HSTR_HG_KICKED
    jsr ssell_show_error
    rts

!ssell_do_haggle:
    jsr haggle_sell
    bcs ssell_execute
    rts

ssell_execute:
    // Find empty store slot
    jsr store_find_empty_slot
    bcs !ssell_has_slot+

    ldx #HSTR_UIS_STORE_FULL
    jsr ssell_show_error
    rts

!ssell_has_slot:
    // X = empty absolute slot
    jsr hg_decrease_insults

    // Transfer item from inventory to store
    stx sb_abs_slot
    ldx ss_inv_slot
    lda inv_item_id,x
    ldy sb_abs_slot
    sta si_item_id,y
    lda inv_qty,x
    sta si_qty,y
    lda inv_p1,x
    sta si_p1,y
    lda inv_flags,x
    sta si_flags,y
    lda inv_ego,x
    sta si_ego,y

    // Remove from inventory
    ldx ss_inv_slot
    jsr inv_remove_item

    // Add gold
    jsr gold_add_price

    // Success
    ldx #MSG_SOLD
    jsr show_msg

    lda #SFX_PICKUP
    jsr sound_play
    jsr input_get_key
    rts

// ssell_show_error — Show error message on row 22, wait for key
// Input: X = Huffman string ID (HSTR_*)
ssell_show_error:
    jsr huff_decode_string
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    jsr screen_put_string
    jmp input_get_key           // Tail call

// ssell_show_offer — Display sell offer with price
ssell_show_offer:
    ldx #MSG_OFFER
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda sb_price_lo
    sta zp_temp0
    lda sb_price_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_UIS_GP_SELL
    jsr huff_decode_string
    jmp screen_put_string       // Tail call

// ============================================================
// Helpers
// ============================================================

// show_msg — Display a table-driven message (Huffman-decoded)
// Input: X = message index (MSG_* constant)
// All messages use column 1.
// Clobbers: A, X, Y
show_msg:
    lda msg_tbl_color,x
    sta zp_text_color
    lda msg_tbl_row,x
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda msg_tbl_hstr_id,x
    tax
    jsr huff_decode_string
    jmp screen_put_string

// check_cancel — Check if A is a cancel key (Q, ESC, SPACE)
// Input: A = key code
// Output: Z set if cancel, Z clear if not; A preserved
// Clobbers: flags only
check_cancel:
    cmp #PETSCII_Q
    beq !cc_yes+
    cmp #PETSCII_ESC
    beq !cc_yes+
    cmp #PETSCII_SPACE
!cc_yes:
    rts

// draw_separator — Draw SCREEN_COLS dashes across current row
// Input: zp_cursor_row set
// Clobbers: A, X, Y
draw_separator:
    lda #0
    sta zp_cursor_col
    ldx #SCREEN_COLS
!ds_loop:
    lda #$2d                    // Screen code '-'
    jsr screen_put_char
    dex
    bne !ds_loop-
    rts

// store_clear_msg_area — Clear rows 20-23 for messages
// Clobbers: A, X, Y
store_clear_msg_area:
    lda #20
!scma_loop:
    pha
    jsr screen_clear_row
    pla
    clc
    adc #1
    cmp #24
    bcc !scma_loop-
    rts

// ============================================================
// Number input (R6.1 haggling)
// ============================================================

// input_read_number — Read a 16-bit number from keyboard
// Input: cursor positioned, color set
// Output: hg_input_lo/hi = result, carry set = valid, carry clear = cancelled
// Clobbers: everything
input_read_number:
    lda #0
    sta hg_input_lo
    sta hg_input_hi
    sta hg_digit_cnt

!irn_loop:
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key

    // RETURN ($0D) = accept (if at least 1 digit)
    cmp #$0d
    bne !irn_not_ret+
    lda hg_digit_cnt
    beq !irn_loop-              // No digits yet
    sec                         // Valid
    rts
!irn_not_ret:

    // Q/ESC/space = cancel
    jsr check_cancel
    bne !irn_check_del+
    jmp !irn_cancel+
!irn_check_del:

    // DELETE ($14) = erase last digit
    cmp #$14
    bne !irn_not_del+
    lda hg_digit_cnt
    beq !irn_loop-              // Nothing to delete

    // Divide current value by 10
    lda hg_input_lo
    sta zp_math_a
    lda hg_input_hi
    sta zp_math_b
    ldx #10
    jsr math_div_16x8
    lda zp_math_a
    sta hg_input_lo
    lda zp_math_b
    sta hg_input_hi

    // Erase char on screen
    dec zp_cursor_col
    lda #$20
    jsr screen_put_char
    dec zp_cursor_col
    dec hg_digit_cnt
    jmp !irn_loop-
!irn_not_del:

    // Check if digit ($30-$39 PETSCII)
    cmp #$30
    bcc !irn_loop-
    cmp #$3a
    bcs !irn_loop-

    // Max 5 digits
    ldx hg_digit_cnt
    cpx #5
    bcs !irn_loop-

    // Save digit value (0-9) in hg_tmp0
    sec
    sbc #$30
    sta hg_tmp0

    // Multiply current value by 10
    lda hg_input_lo
    sta zp_temp0
    lda hg_input_hi
    sta zp_temp1
    ldx #10
    jsr math_mul_16x8

    // Check overflow (×10 > 65535)
    lda mul_result_2
    bne !irn_ignore+            // Overflow — ignore digit

    // Add digit value, check overflow
    lda mul_result_0
    clc
    adc hg_tmp0
    tax                         // Save lo in X
    lda mul_result_1
    adc #0
    bcs !irn_ignore+            // Overflow past 65535 — ignore digit

    // Accept: store result
    sta hg_input_hi
    stx hg_input_lo

    // Display digit (screen code $30-$39 same as PETSCII)
    lda hg_tmp0
    ora #$30
    jsr screen_put_char
    inc hg_digit_cnt
    jmp !irn_loop-

!irn_ignore:
    jmp !irn_loop-

!irn_cancel:
    clc
    rts

// ============================================================
// Haggle helpers / buy / sell (R6.1)
// ============================================================

// hg_decrease_insults — Successful business cools the visit down.
hg_decrease_insults:
    lda hg_insults
    beq !done+
    dec hg_insults
!done:
    rts

// hg_increment_insults — Add one insult, return carry set if that kicks.
hg_increment_insults:
    inc hg_insults
    lda hg_insults
    cmp #3
    bcs !kicked+
    clc
    rts
!kicked:
    sec
    rts

// hg_wait_for_ack — Wait for an acknowledgement key.
hg_wait_for_ack:
#if C128
    jsr input_wait_release
#endif
    jmp input_get_key

// hg_div_mul_result_24x8 — Divide mul_result_0/1/2 by X, quotient in-place.
hg_div_mul_result_24x8:
    stx hg_den_lo
    lda #0
    sta zp_temp4
    ldx #24
!loop:
    asl mul_result_0
    rol mul_result_1
    rol mul_result_2
    rol zp_temp4
    lda zp_temp4
    cmp hg_den_lo
    bcc !skip+
    sbc hg_den_lo
    sta zp_temp4
    inc mul_result_0
!skip:
    dex
    bne !loop-
    rts

// hg_calc_percent_from_tmp_den — Convert tmp/den concession ratio into percent.
// Input: hg_tmp0/1 = numerator, hg_den_lo/hi = denominator
// Output: A = percentage (0-255, saturated)
hg_calc_percent_from_tmp_den:
!scale:
    lda hg_den_hi
    beq !scaled+
    lsr hg_den_hi
    ror hg_den_lo
    lsr hg_tmp1
    ror hg_tmp0
    jmp !scale-
!scaled:
    ldx hg_den_lo
    bne !do+
    lda #$ff
    rts
!do:
    lda hg_tmp0
    sta zp_temp0
    lda hg_tmp1
    sta zp_temp1
    ldx #100
    jsr math_mul_16x8
    ldx hg_den_lo
    jsr hg_div_mul_result_24x8
    lda mul_result_2
    bne !overflow+
    lda mul_result_1
    bne !overflow+
    lda mul_result_0
    rts
!overflow:
    lda #$ff
    rts

// hg_show_retry_msg — Display a neutral retry reaction for overshoot/undershoot.
hg_show_retry_msg:
    jsr store_clear_msg_area
    lda #COL_WHITE
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_retry_str
    sta zp_ptr0
    lda #>hg_retry_str
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr hg_wait_for_ack
    rts

// hg_show_final_prompt — Display final offer line plus numeric input prompt.
// Input: A = prompt message index (MSG_YOUR_OFFER / MSG_YOUR_PRICE)
hg_show_final_prompt:
    pha
    jsr store_clear_msg_area
    ldx #MSG_FINAL
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_HG_GP
    jsr huff_decode_string
    jsr screen_put_string

    pla
    tax
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    rts

// haggle_buy — Multi-round buy haggling
// Input: sb_price_lo/hi = CHR-adjusted asking price, sb_abs_slot = store slot
// Output: carry set = deal (sb_price_lo/hi = agreed price), carry clear = no deal
// Clobbers: everything
haggle_buy:
    lda sb_price_lo
    sta hg_ask_lo
    lda sb_price_hi
    sta hg_ask_hi

    ldx sb_abs_slot
    lda si_p1,x
    sta sb_item_p1
    lda si_item_id,x
    jsr calc_buy_min_price
    lda sb_price_lo
    sta hg_min_lo
    lda sb_price_hi
    sta hg_min_hi

    lda hg_min_hi
    lsr
    sta hg_last_hi
    lda hg_min_lo
    ror
    sta hg_last_lo
    lda hg_last_lo
    ora hg_last_hi
    bne !hb_last_ok+
    lda #1
    sta hg_last_lo
!hb_last_ok:
    lda #0
    sta hg_round

!hb_loop:
    lda hg_round
    beq !hb_normal_prompt+
    lda #MSG_YOUR_OFFER
    jsr hg_show_final_prompt
    jmp !hb_read+
!hb_normal_prompt:
    jsr hg_show_ask
!hb_read:
    jsr input_read_number
    bcs !hb_got_offer+
    clc
    rts

!hb_got_offer:
    // Backwards or insultingly low offer: input < last offer.
    lda hg_input_hi
    cmp hg_last_hi
    bcs !hb_hi_ok+
    jmp !hb_insult+
!hb_hi_ok:
    bne !hb_check_retry+
    lda hg_input_lo
    cmp hg_last_lo
    bcs !hb_check_retry+
    jmp !hb_insult+

!hb_check_retry:
    // Overshoot: input > current ask.
    lda hg_input_hi
    cmp hg_ask_hi
    bcc !hb_counter+
    bne !hb_retry+
    lda hg_input_lo
    cmp hg_ask_lo
    bcc !hb_counter+
    bne !hb_retry+
    jmp !hb_accept_input+
!hb_retry:
    jsr hg_show_retry_msg
    jmp !hb_loop-

!hb_counter:
    // concession = input - last
    lda hg_input_lo
    sec
    sbc hg_last_lo
    sta hg_tmp0
    lda hg_input_hi
    sbc hg_last_hi
    sta hg_tmp1

    // span = ask - last
    lda hg_ask_lo
    sec
    sbc hg_last_lo
    sta hg_den_lo
    lda hg_ask_hi
    sbc hg_last_hi
    sta hg_den_hi

    jsr hg_calc_percent_from_tmp_den
    cmp #HG_MIN_CONCESSION
    bcs !hb_pct_floor_ok+
    jmp !hb_insult+
!hb_pct_floor_ok:
    cmp #HG_MAX_CONCESSION + 1
    bcc !hb_pct_ok+
    sta hg_pct
    lsr
    lsr
    sta hg_tmp0
    lda hg_pct
    sec
    sbc hg_tmp0
    cmp #HG_MAX_CONCESSION
    bcs !hb_pct_ok+
    lda #HG_MAX_CONCESSION
!hb_pct_ok:
    sta hg_pct

    // step = ((ask - input) * pct) / 100 + 1
    lda hg_ask_lo
    sec
    sbc hg_input_lo
    sta zp_temp0
    lda hg_ask_hi
    sbc hg_input_hi
    sta zp_temp1
    ldx hg_pct
    jsr math_mul_16x8
    ldx #100
    jsr hg_div_mul_result_24x8
    lda mul_result_0
    clc
    adc #1
    sta hg_tmp0
    lda mul_result_1
    adc #0
    sta hg_tmp1

    // ask -= step
    lda hg_ask_lo
    sec
    sbc hg_tmp0
    sta hg_ask_lo
    lda hg_ask_hi
    sbc hg_tmp1
    sta hg_ask_hi

    // Clamp to final offer. Reaching final offer does not auto-accept.
    lda hg_ask_hi
    cmp hg_min_hi
    bcc !hb_clamp+
    bne !hb_post_counter_accept+
    lda hg_ask_lo
    cmp hg_min_lo
    bcs !hb_post_counter_accept+
!hb_clamp:
    lda hg_min_lo
    sta hg_ask_lo
    lda hg_min_hi
    sta hg_ask_hi
    inc hg_round
    lda hg_round
    cmp #4
    bcc !hb_store_last+
    jsr hg_increment_insults
    bcs !hb_kick+
    clc
    rts

!hb_post_counter_accept:
    // If the store moved past the player's offer, take the player's price.
    lda hg_input_hi
    cmp hg_ask_hi
    bcc !hb_store_last+
    bne !hb_accept_input+
    lda hg_input_lo
    cmp hg_ask_lo
    bcc !hb_store_last+
!hb_accept_input:
    lda hg_input_lo
    sta hg_ask_lo
    lda hg_input_hi
    sta hg_ask_hi
    jmp hg_do_accept

!hb_store_last:
    lda hg_input_lo
    sta hg_last_lo
    lda hg_input_hi
    sta hg_last_hi
    jsr hg_show_counter
    jsr hg_wait_for_ack
    jmp !hb_loop-

!hb_insult:
    jsr hg_increment_insults
    bcs !hb_kick+
    jsr hg_show_insult_msg
    jmp !hb_loop-
!hb_kick:
    jmp hg_do_kick

// haggle_sell — Multi-round sell haggling
// Input: sb_price_lo/hi = CHR-adjusted sell price (max shopkeeper will pay)
// Output: carry set = deal (sb_price_lo/hi = agreed price), carry clear = no deal
// Clobbers: everything
haggle_sell:
    lda sb_price_lo
    sta hg_min_lo
    lda sb_price_hi
    sta hg_min_hi

    // Starting offer = max / 2 (minimum 1 GP).
    lda hg_min_hi
    lsr
    sta hg_ask_hi
    lda hg_min_lo
    ror
    sta hg_ask_lo
    lda hg_ask_lo
    ora hg_ask_hi
    bne !hs_init_ok+
    lda #1
    sta hg_ask_lo
!hs_init_ok:

    // First acceptable player ask anchor = 2 * max, saturated.
    lda hg_min_lo
    asl
    sta hg_last_lo
    lda hg_min_hi
    rol
    sta hg_last_hi
    bcc !hs_last_ok+
    lda #$ff
    sta hg_last_lo
    sta hg_last_hi
!hs_last_ok:
    lda #0
    sta hg_round

!hs_loop:
    lda hg_round
    beq !hs_normal_prompt+
    lda #MSG_YOUR_PRICE
    jsr hg_show_final_prompt
    jmp !hs_read+
!hs_normal_prompt:
    jsr hg_show_offer
!hs_read:
    jsr input_read_number
    bcs !hs_got_price+
    clc
    rts

!hs_got_price:
    // Backwards or insultingly high ask: input > last ask.
    lda hg_input_hi
    cmp hg_last_hi
    bcc !hs_check_retry+
    beq !hs_hi_equal+
    jmp !hs_insult+
!hs_hi_equal:
    lda hg_input_lo
    cmp hg_last_lo
    bcc !hs_check_retry+
    beq !hs_check_retry+
    jmp !hs_insult+

!hs_check_retry:
    // Undershoot: input < current offer.
    lda hg_input_hi
    cmp hg_ask_hi
    bcs !hs_hi_retry_ok+
    jmp !hs_retry+
!hs_hi_retry_ok:
    bne !hs_counter+
    lda hg_input_lo
    cmp hg_ask_lo
    bcs !hs_lo_retry_ok+
    jmp !hs_retry+
!hs_lo_retry_ok:
    bne !hs_counter+
    jmp !hs_accept_input+

!hs_counter:
    // concession = last - input
    lda hg_last_lo
    sec
    sbc hg_input_lo
    sta hg_tmp0
    lda hg_last_hi
    sbc hg_input_hi
    sta hg_tmp1

    // span = last - ask
    lda hg_last_lo
    sec
    sbc hg_ask_lo
    sta hg_den_lo
    lda hg_last_hi
    sbc hg_ask_hi
    sta hg_den_hi

    jsr hg_calc_percent_from_tmp_den
    cmp #HG_MIN_CONCESSION
    bcs !hs_pct_floor_ok+
    jmp !hs_insult+
!hs_pct_floor_ok:
    cmp #HG_MAX_CONCESSION + 1
    bcc !hs_pct_ok+
    sta hg_pct
    lsr
    lsr
    sta hg_tmp0
    lda hg_pct
    sec
    sbc hg_tmp0
    cmp #HG_MAX_CONCESSION
    bcs !hs_pct_ok+
    lda #HG_MAX_CONCESSION
!hs_pct_ok:
    sta hg_pct

    // step = ((input - ask) * pct) / 100 + 1
    lda hg_input_lo
    sec
    sbc hg_ask_lo
    sta zp_temp0
    lda hg_input_hi
    sbc hg_ask_hi
    sta zp_temp1
    ldx hg_pct
    jsr math_mul_16x8
    ldx #100
    jsr hg_div_mul_result_24x8
    lda mul_result_0
    clc
    adc #1
    sta hg_tmp0
    lda mul_result_1
    adc #0
    sta hg_tmp1

    // ask += step
    lda hg_ask_lo
    clc
    adc hg_tmp0
    sta hg_ask_lo
    lda hg_ask_hi
    adc hg_tmp1
    sta hg_ask_hi

    // Clamp to final offer. Reaching final offer does not auto-accept.
    lda hg_min_hi
    cmp hg_ask_hi
    bcc !hs_clamp+
    bne !hs_post_counter_accept+
    lda hg_min_lo
    cmp hg_ask_lo
    bcs !hs_post_counter_accept+
!hs_clamp:
    lda hg_min_lo
    sta hg_ask_lo
    lda hg_min_hi
    sta hg_ask_hi
    inc hg_round
    lda hg_round
    cmp #4
    bcc !hs_store_last+
    jsr hg_increment_insults
    bcs !hs_kick+
    clc
    rts

!hs_post_counter_accept:
    // If the store moved up to the player's price, take the player's ask.
    lda hg_input_hi
    cmp hg_ask_hi
    bcc !hs_accept_input+
    bne !hs_store_last+
    lda hg_input_lo
    cmp hg_ask_lo
    bcc !hs_accept_input+
    beq !hs_accept_input+
    jmp !hs_store_last+

!hs_retry:
    jsr hg_show_retry_msg
    jmp !hs_loop-

!hs_accept_input:
    lda hg_input_lo
    sta hg_ask_lo
    lda hg_input_hi
    sta hg_ask_hi
    jmp hg_do_accept

!hs_store_last:
    lda hg_input_lo
    sta hg_last_lo
    lda hg_input_hi
    sta hg_last_hi
    jsr hg_show_counter
    jsr hg_wait_for_ack
    jmp !hs_loop-

!hs_insult:
    jsr hg_increment_insults
    bcs !hs_kick+
    jsr hg_show_insult_msg
    jmp !hs_loop-
!hs_kick:
    jmp hg_do_kick

// ============================================================
// Shared haggle handlers
// ============================================================

// hg_do_kick — Shared kick handler (terminal)
// Sets kicked flag, shows message, returns with carry clear
hg_do_kick:
    ldx zp_store_idx
    lda #1
    sta hg_kicked,x
    jsr store_clear_msg_area
    ldx #MSG_KICKED
    jsr show_msg
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    clc
    rts

// hg_do_accept — Shared accept handler (terminal)
// Copies ask to price, shows "AGREED!", returns with carry set
hg_do_accept:
    lda hg_ask_lo
    sta sb_price_lo
    lda hg_ask_hi
    sta sb_price_hi
    jsr store_clear_msg_area
    ldx #MSG_AGREED
    jsr show_msg
    sec
    rts

// hg_show_insult_msg — Display random insult, wait for key
// Clobbers: everything
hg_show_insult_msg:
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #HSTR_INSULT_COUNT
    jsr rng_range
    tax
    jsr huff_decode_string
    jsr screen_put_string
#if C128
    jsr input_wait_release
#endif
    jmp input_get_key           // Tail call

// ============================================================
// Haggle display helpers (R6.1)
// ============================================================

// hg_show_ask — Display "ASKS [price] GP." + "YOUR OFFER? (Q=CANCEL)"
hg_show_ask:
    jsr store_clear_msg_area
    ldx #MSG_ASKS
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_HG_GP
    jsr huff_decode_string
    jsr screen_put_string

    // Row 21: prompt
    ldx #MSG_YOUR_OFFER
    jsr show_msg

    // Position cursor for number input on row 22
    lda #COL_YELLOW
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    rts

// hg_show_offer — Display "OFFERS [price] GP." + "YOUR PRICE? (Q=CANCEL)"
hg_show_offer:
    jsr store_clear_msg_area
    ldx #MSG_OFFERS
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_HG_GP
    jsr huff_decode_string
    jsr screen_put_string

    // Row 21: prompt
    ldx #MSG_YOUR_PRICE
    jsr show_msg

    // Position cursor for number input on row 22
    lda #COL_YELLOW
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    rts

// hg_show_counter — Display "HOW ABOUT [ask] GP?"
hg_show_counter:
    jsr store_clear_msg_area
    ldx #MSG_COUNTER
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_HG_QMARK
    jsr huff_decode_string
    jmp screen_put_string

// hg_show_final — Display "FINAL OFFER: [ask] GP." + "TAKE IT? (Y/N)"
hg_show_final:
    jsr store_clear_msg_area
    ldx #MSG_FINAL
    jsr show_msg

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    ldx #HSTR_HG_GP
    jsr huff_decode_string
    jsr screen_put_string

    // Row 21: "TAKE IT? (Y/N)"
    ldx #MSG_TAKE
    jmp show_msg

hg_retry_str:
    .text "WHAT WAS THAT?" ; .byte 0

// ============================================================
// Message display tables (indexed by MSG_* constants)
// Strings are Huffman-compressed in main RAM (huffman_data.s)
// ============================================================
msg_tbl_color:
    .byte COL_YELLOW, COL_WHITE, COL_WHITE, COL_RED, COL_LGREEN
    .byte COL_WHITE, COL_RED, COL_RED, COL_WHITE, COL_WHITE
    .byte COL_WHITE, COL_LGREEN, COL_WHITE, COL_WHITE, COL_WHITE
    .byte COL_WHITE, COL_WHITE, COL_WHITE, COL_WHITE, COL_LGREEN
msg_tbl_row:
    .byte 16, 18, 20, 22, 22
    .byte 21, 22, 22, 0, 23
    .byte 22, 23, 20, 21, 20
    .byte 21, 20, 20, 21, 22
msg_tbl_hstr_id:
    .byte HSTR_UIS_GOLD, HSTR_UIS_MENU, HSTR_UIS_BUY_WHICH, HSTR_HG_KICKED, HSTR_UIS_BOUGHT
    .byte HSTR_UIS_PRICE, HSTR_UIS_NO_AFFORD, HSTR_UIS_PACK_FULL, HSTR_UIS_SELL_TITLE, HSTR_UIS_SELL_WHICH
    .byte HSTR_UIS_OFFER, HSTR_UIS_SOLD, HSTR_HG_ASKS, HSTR_HG_YOUR_OFFER, HSTR_HG_OFFERS
    .byte HSTR_HG_YOUR_PRICE, HSTR_HG_COUNTER, HSTR_HG_FINAL, HSTR_HG_TAKE, HSTR_HG_AGREED
