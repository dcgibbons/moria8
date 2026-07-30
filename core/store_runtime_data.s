#importonce
// store_runtime_data.s — Small mutable/read-only store tables.

// Store category bitmasks (16-bit, bit N = ICAT N).
store_cat_mask_lo:
    .byte <$0301, <$00F8, <$0004, <$0C00, <$0400, <$F000, <$FFFF, <$FFFF
store_cat_mask_hi:
    .byte >$0300, >$00F8, >$0004, >$0C00, >$0400, >$F000, >$FFFF, >$FFFF

bit_mask_table:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

#if !STORE_HOT_DATA_EXTERNAL
#import "store_hot_data.s"
#endif

store_name_lo:
    .byte <sn_general, <sn_armory, <sn_weapon, <sn_temple, <sn_alchemy, <sn_magic, <sn_bmarket, <sn_home
store_name_hi:
    .byte >sn_general, >sn_armory, >sn_weapon, >sn_temple, >sn_alchemy, >sn_magic, >sn_bmarket, >sn_home

store_owner_lo:
    .byte <so_0, <so_1, <so_2, <so_3, <so_4, <so_5, <so_6, <so_7
store_owner_hi:
    .byte >so_0, >so_1, >so_2, >so_3, >so_4, >so_5, >so_6, >so_7
