// item_catalog_prg.s - CX16 immutable item catalog bank-window PRG.
// Loads at $A000 into CX16 item catalog RAM bank 9.

.encoding "screencode_mixed"

.pc = $A000 "CX16 Item Catalog"

#import "palette_consts.s"
#import "../../core/item_defs.s"
#import "item_catalog_contract.s"

cx16_item_catalog_start:
#define ITEM_TABLES_CATALOG_DATA_ONLY
#import "../../core/item_tables.s"
#undef ITEM_TABLES_CATALOG_DATA_ONLY
cx16_item_catalog_end:

.print "CX16 item catalog: " + (cx16_item_catalog_end - cx16_item_catalog_start) + " bytes at $A000-$" + toHexString(cx16_item_catalog_end - 1)
.assert "CX16 item catalog category offset", it_category - cx16_item_catalog_start, CX16_ITEM_CATALOG_CATEGORY_OFFSET
.assert "CX16 item catalog display offset", it_display - cx16_item_catalog_start, CX16_ITEM_CATALOG_DISPLAY_OFFSET
.assert "CX16 item catalog color offset", it_color - cx16_item_catalog_start, CX16_ITEM_CATALOG_COLOR_OFFSET
.assert "CX16 item catalog weight offset", it_weight - cx16_item_catalog_start, CX16_ITEM_CATALOG_WEIGHT_OFFSET
.assert "CX16 item catalog damage dice offset", it_dmg_dice - cx16_item_catalog_start, CX16_ITEM_CATALOG_DMG_DICE_OFFSET
.assert "CX16 item catalog damage sides offset", it_dmg_sides - cx16_item_catalog_start, CX16_ITEM_CATALOG_DMG_SIDES_OFFSET
.assert "CX16 item catalog base AC offset", it_base_ac - cx16_item_catalog_start, CX16_ITEM_CATALOG_BASE_AC_OFFSET
.assert "CX16 item catalog cost lo offset", it_cost_lo - cx16_item_catalog_start, CX16_ITEM_CATALOG_COST_LO_OFFSET
.assert "CX16 item catalog cost hi offset", it_cost_hi - cx16_item_catalog_start, CX16_ITEM_CATALOG_COST_HI_OFFSET
.assert "CX16 item catalog min-level offset", it_min_level - cx16_item_catalog_start, CX16_ITEM_CATALOG_MIN_LEVEL_OFFSET
.assert "CX16 item catalog missile offset", it_missile - cx16_item_catalog_start, CX16_ITEM_CATALOG_MISSILE_OFFSET
.assert "CX16 item catalog name-lo offset", it_name_lo - cx16_item_catalog_start, CX16_ITEM_CATALOG_NAME_LO_OFFSET
.assert "CX16 item catalog name-hi offset", it_name_hi - cx16_item_catalog_start, CX16_ITEM_CATALOG_NAME_HI_OFFSET
.assert "CX16 item catalog token-lo offset", item_name_token_lo - cx16_item_catalog_start, CX16_ITEM_CATALOG_TOKEN_LO_OFFSET
.assert "CX16 item catalog token-hi offset", item_name_token_hi - cx16_item_catalog_start, CX16_ITEM_CATALOG_TOKEN_HI_OFFSET
.assert "CX16 item catalog fits one banked-RAM window", cx16_item_catalog_end <= $C000, true
