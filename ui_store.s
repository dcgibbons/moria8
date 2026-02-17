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
    lda #0
    sta zp_cursor_col
    lda #<uis_sep_str
    sta zp_ptr0
    lda #>uis_sep_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    beq !sds_empty_slot+

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

    // Item name
    lda #COL_LGREY
    sta zp_text_color
    ldy sb_abs_slot
    lda si_item_id,y
    jsr item_get_name_ptr
    jsr screen_put_string

    // Skip price display for Home (no prices)
    lda zp_store_idx
    cmp #STORE_HOME
    beq !sds_next_slot+

    // Price at column 31
    lda sd_row
    sta zp_cursor_row
    lda #31
    sta zp_cursor_col
    lda #COL_YELLOW
    sta zp_text_color

    ldy sb_abs_slot
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
    lda #0
    sta zp_cursor_col
    lda #<uis_sep_str
    sta zp_ptr0
    lda #>uis_sep_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 16: Gold display
    lda #COL_YELLOW
    sta zp_text_color
    lda #16
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_gold_str
    sta zp_ptr0
    lda #>uis_gold_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    lda #<uis_big_gold_str
    sta zp_ptr0
    lda #>uis_big_gold_str
    sta zp_ptr0_hi
    jsr screen_put_string

!sds_gold_done:
    // Row 18: Menu
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_menu_str
    sta zp_ptr0
    lda #>uis_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_buy_which_str
    sta zp_ptr0
    lda #>uis_buy_which_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Get key
    jsr input_get_key

    // Q/ESC/space = cancel
    cmp #PETSCII_Q
    bne !sb_not_q+
    rts
!sb_not_q:
    cmp #PETSCII_ESC
    bne !sb_not_esc+
    rts
!sb_not_esc:
    cmp #PETSCII_SPACE
    bne !sb_not_spc+
    rts
!sb_not_spc:

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
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_kicked_str
    sta zp_ptr0
    lda #>hg_kicked_str
    sta zp_ptr0_hi
    jsr screen_put_string
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
    jsr inv_add_item

    // Remove from store
    ldx sb_abs_slot
    lda #FI_EMPTY
    sta si_item_id,x
    lda #0
    sta si_qty,x
    sta si_p1,x
    sta si_flags,x

    // Success message
    jsr store_clear_msg_area
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_bought_str
    sta zp_ptr0
    lda #>uis_bought_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #SFX_PICKUP
    jsr sound_play
    rts

// sbuy_show_price — Display price confirmation for buy
sbuy_show_price:
    jsr store_clear_msg_area
    lda #COL_WHITE
    sta zp_text_color
    lda #21
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_price_str
    sta zp_ptr0
    lda #>uis_price_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda sb_price_lo
    sta zp_temp0
    lda sb_price_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    lda #<uis_gp_buy_str
    sta zp_ptr0
    lda #>uis_gp_buy_str
    sta zp_ptr0_hi
    jmp screen_put_string       // Tail call

sbuy_no_gold:
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_no_afford_str
    sta zp_ptr0
    lda #>uis_no_afford_str
    sta zp_ptr0_hi
    jmp screen_put_string       // Tail call

sbuy_full:
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_pack_full_str
    sta zp_ptr0
    lda #>uis_pack_full_str
    sta zp_ptr0_hi
    jmp screen_put_string       // Tail call

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

    lda #COL_WHITE
    sta zp_text_color
    lda #0
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_sell_title_str
    sta zp_ptr0
    lda #>uis_sell_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Separator
    lda #COL_DGREY
    sta zp_text_color
    lda #1
    sta zp_cursor_row
    lda #0
    sta zp_cursor_col
    lda #<uis_sep_str
    sta zp_ptr0
    lda #>uis_sep_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    lda #COL_WHITE
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_sell_which_str
    sta zp_ptr0
    lda #>uis_sell_which_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Get key
    jsr input_get_key

    // Q/ESC/space = cancel
    cmp #PETSCII_Q
    bne !ss_not_q+
    rts
!ss_not_q:
    cmp #PETSCII_ESC
    bne !ss_not_esc+
    rts
!ss_not_esc:
    cmp #PETSCII_SPACE
    bne !ss_not_spc+
    rts
!ss_not_spc:

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
    lda #<uis_no_buy_str
    ldx #>uis_no_buy_str
    jsr ssell_show_error
    rts

!ssell_cat_ok:
    // Check if item is cursed (RP14-4)
    ldx ss_inv_slot
    lda inv_flags,x
    and #IF_CURSED
    beq !ssell_not_cursed+

    lda #<uis_cursed_str
    ldx #>uis_cursed_str
    jsr ssell_show_error
    rts

!ssell_not_cursed:
    // Calculate sell price
    ldx ss_inv_slot
    lda inv_p1,x
    sta sb_item_p1              // Pass enchantment/charges for pricing
    lda ss_item_id
    jsr calc_store_sell_price   // Dispatches to BM or normal pricing

    // Check for worthless items
    lda sb_price_lo
    ora sb_price_hi
    bne !ssell_has_value+

    lda #<uis_worthless_str
    ldx #>uis_worthless_str
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
    jsr input_get_key
    cmp #PETSCII_Y
    beq ssell_execute
    rts

!ssell_haggle_check:
    // Check if kicked from this store
    ldx zp_store_idx
    lda hg_kicked,x
    beq !ssell_do_haggle+
    lda #<hg_kicked_str
    ldx #>hg_kicked_str
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

    lda #<uis_store_full_str
    ldx #>uis_store_full_str
    jsr ssell_show_error
    rts

!ssell_has_slot:
    // X = empty absolute slot
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

    // Remove from inventory
    ldx ss_inv_slot
    jsr inv_remove_item

    // Add gold
    jsr gold_add_price

    // Success
    lda #COL_LGREEN
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_sold_str
    sta zp_ptr0
    lda #>uis_sold_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #SFX_PICKUP
    jsr sound_play
    jsr input_get_key
    rts

// ssell_show_error — Show error message on row 22, wait for key
// Input: A = string ptr lo, X = string ptr hi
ssell_show_error:
    sta zp_ptr0
    stx zp_ptr0_hi
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
    lda #COL_WHITE
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<uis_offer_str
    sta zp_ptr0
    lda #>uis_offer_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda sb_price_lo
    sta zp_temp0
    lda sb_price_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    lda #<uis_gp_sell_str
    sta zp_ptr0
    lda #>uis_gp_sell_str
    sta zp_ptr0_hi
    jmp screen_put_string       // Tail call

// ============================================================
// Helpers
// ============================================================

// store_clear_msg_area — Clear rows 20-23 for messages
// Clobbers: A, X, Y
store_clear_msg_area:
    lda #20
    jsr screen_clear_row
    lda #21
    jsr screen_clear_row
    lda #22
    jsr screen_clear_row
    lda #23
    jsr screen_clear_row
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
    jsr input_get_key

    // RETURN ($0D) = accept (if at least 1 digit)
    cmp #$0d
    bne !irn_not_ret+
    lda hg_digit_cnt
    beq !irn_loop-              // No digits yet
    sec                         // Valid
    rts
!irn_not_ret:

    // Q ($51) or ESC ($1B) or SPACE ($20) = cancel
    cmp #PETSCII_Q
    beq !irn_cancel_relay+
    cmp #$1b
    beq !irn_cancel_relay+
    cmp #$20
    beq !irn_cancel_relay+
    jmp !irn_check_del+
!irn_cancel_relay:
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
// Haggle buy (R6.1)
// ============================================================

// haggle_buy — Multi-round buy haggling
// Input: sb_price_lo/hi = CHR-adjusted asking price, sb_abs_slot = store slot
// Output: carry set = deal (sb_price_lo/hi = agreed price), carry clear = no deal
// Clobbers: everything
haggle_buy:
    // Save asking price as initial ask
    lda sb_price_lo
    sta hg_ask_lo
    lda sb_price_hi
    sta hg_ask_hi

    // Calculate minimum acceptable price (base + p1, no CHR markup)
    ldx sb_abs_slot
    lda si_p1,x
    sta sb_item_p1
    lda si_item_id,x
    jsr calc_buy_min_price      // sb_price_lo/hi = min price
    lda sb_price_lo
    sta hg_min_lo
    lda sb_price_hi
    sta hg_min_hi

    lda #0
    sta hg_round

!hb_loop:
    // Display "ASKS [hg_ask] GP."
    jsr hg_show_ask

    // Get player's offer
    jsr input_read_number
    bcs !hb_got_offer+
    clc                         // Cancelled
    rts

!hb_got_offer:
    // Insult check: offer < min / 2
    lda hg_min_lo
    sta zp_math_a
    lda hg_min_hi
    sta zp_math_b
    // Divide min by 2 (shift right)
    lsr zp_math_b
    ror zp_math_a

    // Compare: hg_input < min/2?
    lda hg_input_hi
    cmp zp_math_b
    bcc !hb_insult_relay+       // input_hi < min/2 hi
    bne !hb_no_insult+          // input_hi > min/2 hi
    lda hg_input_lo
    cmp zp_math_a
    bcc !hb_insult_relay+       // input_lo < min/2 lo
    jmp !hb_no_insult+
!hb_insult_relay:
    jmp !hb_insult+
!hb_no_insult:

    // Accept check: input >= ask?
    lda hg_ask_hi
    cmp hg_input_hi
    bcc !hb_accept_relay+       // ask_hi < input_hi → accept
    bne !hb_counter+            // ask_hi > input_hi → counter
    lda hg_ask_lo
    cmp hg_input_lo
    bcc !hb_accept_relay+       // ask_lo < input_lo → accept
    beq !hb_accept_relay+       // ask = input → accept
    jmp !hb_counter+
!hb_accept_relay:
    jmp !hb_accept+

!hb_counter:
    // gap = ask - min
    lda hg_ask_lo
    sec
    sbc hg_min_lo
    sta hg_tmp0
    lda hg_ask_hi
    sbc hg_min_hi
    sta hg_tmp1

    // step = gap / 4 (shift right twice), min 1
    lsr hg_tmp1
    ror hg_tmp0
    lsr hg_tmp1
    ror hg_tmp0
    // Ensure step >= 1
    lda hg_tmp0
    ora hg_tmp1
    bne !hb_step_ok+
    lda #1
    sta hg_tmp0
!hb_step_ok:

    // ask -= step
    lda hg_ask_lo
    sec
    sbc hg_tmp0
    sta hg_ask_lo
    lda hg_ask_hi
    sbc hg_tmp1
    sta hg_ask_hi

    // Clamp ask to min (if ask < min, ask = min)
    lda hg_ask_hi
    cmp hg_min_hi
    bcc !hb_clamp+
    bne !hb_no_clamp+
    lda hg_ask_lo
    cmp hg_min_lo
    bcs !hb_no_clamp+
!hb_clamp:
    lda hg_min_lo
    sta hg_ask_lo
    lda hg_min_hi
    sta hg_ask_hi
!hb_no_clamp:

    inc hg_round
    lda hg_round
    cmp #4
    bcs !hb_final+

    // Display "HOW ABOUT [ask] GP?"
    jsr hg_show_counter
    jsr input_get_key           // Wait for key before next round
    jmp !hb_loop-

!hb_final:
    // Final offer
    jsr hg_show_final
    jsr input_get_key
    cmp #PETSCII_Y
    beq !hb_accept+
    clc
    rts

!hb_insult:
    inc hg_insults
    lda hg_insults
    cmp #3
    bcs !hb_kick+
    // Show insult message
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #HUFF_STR_COUNT
    jsr rng_range
    tax
    jsr huff_decode_string
    jsr screen_put_string
    jsr input_get_key
    jmp !hb_loop-

!hb_kick:
    ldx zp_store_idx
    lda #1
    sta hg_kicked,x
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_kicked_str
    sta zp_ptr0
    lda #>hg_kicked_str
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr input_get_key
    clc
    rts

!hb_accept:
    // Set agreed price
    lda hg_ask_lo
    sta sb_price_lo
    lda hg_ask_hi
    sta sb_price_hi
    // Show "AGREED!"
    jsr store_clear_msg_area
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_agreed_str
    sta zp_ptr0
    lda #>hg_agreed_str
    sta zp_ptr0_hi
    jsr screen_put_string
    sec
    rts

// ============================================================
// Haggle sell (R6.1)
// ============================================================

// haggle_sell — Multi-round sell haggling
// Input: sb_price_lo/hi = CHR-adjusted sell price (max shopkeeper will pay)
// Output: carry set = deal (sb_price_lo/hi = agreed price), carry clear = no deal
// Clobbers: everything
haggle_sell:
    // Max = CHR-adjusted sell price
    lda sb_price_lo
    sta hg_min_lo               // "min" = max shopkeeper will pay (ceiling)
    lda sb_price_hi
    sta hg_min_hi

    // Starting offer = max / 2 (min 1)
    lsr hg_min_hi               // Temp use — restore after
    lda hg_min_lo
    ror
    sta hg_ask_lo
    lda hg_min_hi
    sta hg_ask_hi
    // Restore min from original price
    lda sb_price_lo
    sta hg_min_lo
    lda sb_price_hi
    sta hg_min_hi

    // Ensure starting offer >= 1
    lda hg_ask_lo
    ora hg_ask_hi
    bne !hs_init_ok+
    lda #1
    sta hg_ask_lo
!hs_init_ok:

    lda #0
    sta hg_round

!hs_loop:
    // Display "OFFERS [hg_ask] GP."
    jsr hg_show_offer

    // Get player's asking price
    jsr input_read_number
    bcs !hs_got_price+
    clc
    rts

!hs_got_price:
    // Insult check: player asking > 2 × max
    // Calculate 2 × max
    lda hg_min_lo
    asl
    sta hg_tmp0
    lda hg_min_hi
    rol
    sta hg_tmp1

    // Compare: input > 2×max?
    lda hg_tmp1
    cmp hg_input_hi
    bcc !hs_insult_relay+       // 2×max hi < input hi
    bne !hs_no_insult+
    lda hg_tmp0
    cmp hg_input_lo
    bcc !hs_insult_relay+       // 2×max lo < input lo
    jmp !hs_no_insult+
!hs_insult_relay:
    jmp !hs_insult+
!hs_no_insult:

    // Accept check: input <= ask? (player accepts shopkeeper's offer)
    lda hg_input_hi
    cmp hg_ask_hi
    bcc !hs_accept_relay+       // input_hi < ask_hi → accept
    bne !hs_counter+            // input_hi > ask_hi → counter
    lda hg_input_lo
    cmp hg_ask_lo
    bcc !hs_accept_relay+       // input_lo < ask_lo → accept
    beq !hs_accept_relay+       // equal → accept
    jmp !hs_counter+
!hs_accept_relay:
    jmp !hs_accept+

!hs_counter:
    // gap = max - ask
    lda hg_min_lo
    sec
    sbc hg_ask_lo
    sta hg_tmp0
    lda hg_min_hi
    sbc hg_ask_hi
    sta hg_tmp1

    // step = gap / 4, min 1
    lsr hg_tmp1
    ror hg_tmp0
    lsr hg_tmp1
    ror hg_tmp0
    lda hg_tmp0
    ora hg_tmp1
    bne !hs_step_ok+
    lda #1
    sta hg_tmp0
!hs_step_ok:

    // ask += step
    lda hg_ask_lo
    clc
    adc hg_tmp0
    sta hg_ask_lo
    lda hg_ask_hi
    adc hg_tmp1
    sta hg_ask_hi

    // Clamp ask to max (if ask > max, ask = max)
    lda hg_min_hi
    cmp hg_ask_hi
    bcc !hs_clamp+
    bne !hs_no_clamp+
    lda hg_min_lo
    cmp hg_ask_lo
    bcs !hs_no_clamp+
!hs_clamp:
    lda hg_min_lo
    sta hg_ask_lo
    lda hg_min_hi
    sta hg_ask_hi
!hs_no_clamp:

    inc hg_round
    lda hg_round
    cmp #4
    bcs !hs_final+

    jsr hg_show_sell_counter
    jsr input_get_key
    jmp !hs_loop-

!hs_final:
    jsr hg_show_sell_final
    jsr input_get_key
    cmp #PETSCII_Y
    beq !hs_accept+
    clc
    rts

!hs_insult:
    inc hg_insults
    lda hg_insults
    cmp #3
    bcs !hs_kick+
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #23
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #HUFF_STR_COUNT
    jsr rng_range
    tax
    jsr huff_decode_string
    jsr screen_put_string
    jsr input_get_key
    jmp !hs_loop-

!hs_kick:
    ldx zp_store_idx
    lda #1
    sta hg_kicked,x
    jsr store_clear_msg_area
    lda #COL_RED
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_kicked_str
    sta zp_ptr0
    lda #>hg_kicked_str
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr input_get_key
    clc
    rts

!hs_accept:
    lda hg_ask_lo
    sta sb_price_lo
    lda hg_ask_hi
    sta sb_price_hi
    jsr store_clear_msg_area
    lda #COL_LGREEN
    sta zp_text_color
    lda #22
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_agreed_str
    sta zp_ptr0
    lda #>hg_agreed_str
    sta zp_ptr0_hi
    jsr screen_put_string
    sec
    rts

// ============================================================
// Haggle display helpers (R6.1)
// ============================================================

// hg_show_ask — Display "ASKS [price] GP." + "YOUR OFFER? (Q=CANCEL)"
hg_show_ask:
    jsr store_clear_msg_area
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_asks_str
    sta zp_ptr0
    lda #>hg_asks_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    lda #<hg_gp_str
    sta zp_ptr0
    lda #>hg_gp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 21: prompt
    lda #21
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_offer_str
    sta zp_ptr0
    lda #>hg_offer_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_offers_str
    sta zp_ptr0
    lda #>hg_offers_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    lda #<hg_gp_str
    sta zp_ptr0
    lda #>hg_gp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 21: prompt
    lda #21
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_price_str
    sta zp_ptr0
    lda #>hg_price_str
    sta zp_ptr0_hi
    jsr screen_put_string

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
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_counter_str
    sta zp_ptr0
    lda #>hg_counter_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    lda #<hg_qmark_str
    sta zp_ptr0
    lda #>hg_qmark_str
    sta zp_ptr0_hi
    jmp screen_put_string

// hg_show_sell_counter — Same as counter for sell
hg_show_sell_counter:
    jmp hg_show_counter         // Same display

// hg_show_final — Display "FINAL OFFER: [ask] GP." + "TAKE IT? (Y/N)"
hg_show_final:
    jsr store_clear_msg_area
    lda #COL_WHITE
    sta zp_text_color
    lda #20
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_final_str
    sta zp_ptr0
    lda #>hg_final_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_YELLOW
    sta zp_text_color
    lda hg_ask_lo
    sta zp_temp0
    lda hg_ask_hi
    sta zp_temp1
    jsr screen_put_decimal_16

    lda #COL_WHITE
    sta zp_text_color
    lda #<hg_gp_str
    sta zp_ptr0
    lda #>hg_gp_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Row 21: "TAKE IT? (Y/N)"
    lda #21
    sta zp_cursor_row
    lda #1
    sta zp_cursor_col
    lda #<hg_take_str
    sta zp_ptr0
    lda #>hg_take_str
    sta zp_ptr0_hi
    jmp screen_put_string

// hg_show_sell_final — Same layout for sell
hg_show_sell_final:
    jmp hg_show_final           // Same display

// ============================================================
// String data (screen codes)
// ============================================================
uis_sep_str:
    .text "----------------------------------------" ; .byte 0
uis_gold_str:
    .text "GOLD: " ; .byte 0
uis_big_gold_str:
    .text ">65535" ; .byte 0
uis_menu_str:
    .text "B)UY  S)ELL  Q)UIT" ; .byte 0
uis_buy_which_str:
    .text "BUY WHICH ITEM? (A-L)" ; .byte 0
uis_price_str:
    .text "PRICE: " ; .byte 0
uis_gp_buy_str:
    .text " GP. BUY? (Y/N)" ; .byte 0
uis_bought_str:
    .text "BOUGHT!" ; .byte 0
uis_no_afford_str:
    .text "YOU CANNOT AFFORD THAT." ; .byte 0
uis_pack_full_str:
    .text "YOUR PACK IS FULL." ; .byte 0
uis_sell_title_str:
    .text "SELL ITEMS" ; .byte 0
uis_sell_which_str:
    .text "SELL WHICH ITEM? (A-V)" ; .byte 0
uis_offer_str:
    .text "OFFER: " ; .byte 0
uis_gp_sell_str:
    .text " GP. SELL? (Y/N)" ; .byte 0
uis_sold_str:
    .text "SOLD!" ; .byte 0
uis_no_buy_str:
    .text "WE DON'T BUY THAT." ; .byte 0
uis_worthless_str:
    .text "THAT IS WORTHLESS." ; .byte 0
uis_store_full_str:
    .text "THE STORE IS FULL." ; .byte 0
uis_cursed_str:
    .text "THAT ITEM IS CURSED." ; .byte 0

// Haggling strings (R6.1)
hg_asks_str:     .text "ASKS "              ; .byte 0
hg_offers_str:   .text "OFFERS "            ; .byte 0
hg_gp_str:       .text " GP."              ; .byte 0
hg_offer_str:    .text "YOUR OFFER? (Q=CANCEL)" ; .byte 0
hg_price_str:    .text "YOUR PRICE? (Q=CANCEL)" ; .byte 0
hg_counter_str:  .text "HOW ABOUT "         ; .byte 0
hg_qmark_str:    .text " GP?"              ; .byte 0
hg_final_str:    .text "FINAL OFFER: "      ; .byte 0
hg_take_str:     .text "TAKE IT? (Y/N)"    ; .byte 0
hg_kicked_str:   .text "GET OUT OF MY STORE!" ; .byte 0
hg_agreed_str:   .text "AGREED!"           ; .byte 0
