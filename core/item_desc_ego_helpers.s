#importonce
// item_desc_ego_helpers.s — ego-prefix/suffix formatting for item descriptions.

// ============================================================
// put_tool_ego_prefix — Print ego prefix for digging tools
// Input: A = ego (1 or 2), X = item type ID (62 or 63)
// Output: prefix string printed to screen (e.g., "Gnomish ")
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
put_tool_ego_prefix:
    // Compute index = (type - 62) * 2 + (ego - 1)
    sec
    sbc #1                      // ego - 1 (0 or 1)
    sta ptep_temp
    txa
    sec
    sbc #62                     // type - 62 (0=Shovel, 1=Pick)
    asl                         // * 2
    clc
    adc ptep_temp               // + (ego - 1) -> index 0-3
    tax
    lda tool_ego_prefix_lo,x
    sta zp_ptr0
    lda tool_ego_prefix_hi,x
    sta zp_ptr0_hi
    jmp hal_screen_put_string

#if !GAME_LOOP_LOW_DATA_EXTERNAL
ptep_temp: .byte 0

// Prefix strings (screen codes, null-terminated)
ego_tool_prefix_gnomish: .text "Gnomish " ; .byte 0
ego_tool_prefix_orcish:  .text "Orcish " ; .byte 0
ego_tool_prefix_dwarven: .text "Dwarven " ; .byte 0

// Prefix lookup table — indexed 0-3
// Index: (type-62)*2 + (ego-1)
//   0 = Shovel ego=1 -> Gnomish
//   1 = Shovel ego=2 -> Dwarven
//   2 = Pick ego=1   -> Orcish
//   3 = Pick ego=2   -> Dwarven
tool_ego_prefix_lo:
    .byte <ego_tool_prefix_gnomish, <ego_tool_prefix_dwarven
    .byte <ego_tool_prefix_orcish,  <ego_tool_prefix_dwarven
tool_ego_prefix_hi:
    .byte >ego_tool_prefix_gnomish, >ego_tool_prefix_dwarven
    .byte >ego_tool_prefix_orcish,  >ego_tool_prefix_dwarven
#endif

// ============================================================
// banked_ego_put_suffix — Write ego suffix to screen
// Input: A = ego type (0 = no ego)
// Clobbers: A, Y, zp_ptr0
// ============================================================
banked_ego_put_suffix:
    cmp #0
    beq !beps_done+
    jsr ego_get_suffix_ptr
    ldy #0
!beps_loop:
    lda (zp_ptr0),y
    beq !beps_done+
    sty beps_save_y
    jsr hal_screen_put_char
    ldy beps_save_y
    iny
    jmp !beps_loop-
!beps_done:
    rts
beps_save_y: .byte 0
