#importonce
// Shared carried-inventory prompt/select flow.

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
