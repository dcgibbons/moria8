#importonce
// player_magic_state.s — shared spell command scratch/state
//
// These variables must stay resident so both banked spell logic and overlay UI
// can see the same active selection state on C64 and C128.

pm_spell_idx:      .byte 0
pm_spell_type:     .byte 0
pm_mode:           .byte 0
pm_book_idx:       .byte 0
pm_spell_count:    .byte 0
pm_row_counter:    .byte 0
pm_cost_tmp:       .byte 0
pm_fail_work:      .byte 0
pm_book_mask_lo:   .byte 0
pm_book_mask_hi:   .byte 0
pm_mana_tbl_lo:    .byte 0
pm_mana_tbl_hi:    .byte 0
pm_lvl_tbl_lo:     .byte 0
pm_lvl_tbl_hi:     .byte 0
pm_fail_tbl_lo:    .byte 0
pm_fail_tbl_hi:    .byte 0
pm_name_lo_lo:     .byte 0
pm_name_lo_hi:     .byte 0
pm_name_hi_lo:     .byte 0
pm_name_hi_hi:     .byte 0
pm_spell_list:     .fill SPELL_LIST_MAX, 0
#if C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER
c128_test_spell_success_count: .byte 0
c128_test_spell_return_pending: .byte 0
c128_test_spell_return_count: .byte 0
#endif
#if C64_TEST_SCRIPTED_SPELL
c64_test_spell_success_count: .byte 0
c64_test_spell_return_pending: .byte 0
c64_test_spell_return_count: .byte 0
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_spell_success_count: .byte 0
c64_test_spell_return_pending: .byte 0
c64_test_spell_return_count: .byte 0
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_spell_success_count: .byte 0
c64_test_spell_return_pending: .byte 0
c64_test_spell_return_count: .byte 0
#endif
#endif
#endif
