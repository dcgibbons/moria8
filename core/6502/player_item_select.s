#importonce
// player_item_select.s — Shared carried-inventory prompt/select flow.
//
// Placement & ownership:
// - C64, Plus/4, C128, Atari 8-bit: resident in Default (imported by
//   core/player_items.s).
// - Apple IIe, BBC Master 128, Commander X16: placed in ItemActionsOverlay
//   (OVL_ITEMS) via #define PLAYER_ITEM_SELECT_EXTERNAL in port main.s.
//
// Lifetime & cross-overlay callers:
// - Called by resident/banked player_item_commands, item_actions_overlay, and
//   magic book/recharge selectors. When PLAYER_ITEM_SELECT_EXTERNAL is active,
//   the '?' full-inventory selector explicitly sets piw_return_overlay to
//   OVL_ITEMS before invoking resident show_inv_and_select so OVL_ITEMS is
//   reloaded before returning.

#import "input_ui_helpers.s"

// piw_select_filtered_inv — prompt for a carried inventory item and return it.
// Input: A = filter value, X = Huffman prompt string id
// Output: carry set on success, X = carried slot, A = item type ID;
//         carry clear on no choices or cancel. Cancels print "Never mind."
piw_select_filtered_inv:
    jsr piw_prompt_filtered_inv
    bcs !piw_select_have_choices+
    clc
    rts
!piw_select_have_choices:
    jsr input_prepare_followup_key
    jsr hal_input_get_key

piw_select_filtered_inv_key:
    cmp #$3f
    bne !piw_select_not_inv+
#if PLAYER_ITEM_SELECT_EXTERNAL
    lda #OVL_ITEMS
    sta piw_return_overlay
#endif
    lda piw_filter
    jsr show_inv_and_select
!piw_select_not_inv:

    jsr input_is_modal_escape_key
    beq !piw_select_cancel+
    cmp #$20
    beq !piw_select_cancel+

    jsr piw_pick_filtered_inv_key
    bcs !piw_select_done+
!piw_select_cancel:
    ldx #HSTR_PIW_NEVERMIND
    jsr huff_print_msg
    clc
!piw_select_done:
    rts
