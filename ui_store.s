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
    jsr calc_buy_price          // sb_price_lo/hi = buy price

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
    jsr calc_buy_price          // sb_price_lo/hi

    // Display price and confirm
    jsr sbuy_show_price

    // Wait for Y/N
    jsr input_get_key
    cmp #PETSCII_Y
    beq !sb_confirmed+
    rts
!sb_confirmed:

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
    jsr calc_sell_price

    // Check for worthless items
    lda sb_price_lo
    ora sb_price_hi
    bne !ssell_has_value+

    lda #<uis_worthless_str
    ldx #>uis_worthless_str
    jsr ssell_show_error
    rts

!ssell_has_value:
    // Display offer and confirm
    jsr ssell_show_offer

    // Y/N confirmation
    jsr input_get_key
    cmp #PETSCII_Y
    beq !ssell_confirmed+
    rts
!ssell_confirmed:

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
