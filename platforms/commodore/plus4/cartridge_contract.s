#importonce
// Binary layout shared by cartridge_boot.s, cartridge_copy.s and tools/make_plus4_magic.py.
// Target hardware: Plus/4 c264 magic cart (CRT Type 1, 16 x 16 KB C1LO banks).
.const CART_ENTRY = $100e
.const CART_DIRECTORY = $8100
.const CART_DESCRIPTOR_SIZE = 8
.const CART_ROM_BANK_SIZE = $4000
.const CART_ROM_WINDOW_BASE = $8000
.const CART_ROM_WINDOW_END = $c000
.const CART_BANK_COUNT = 16

.const CART_REG_BANK = $fdfe
.const CART_REG_BASIC_KERNAL = $fdd0
.const CART_REG_C1LO_KERNAL = $fdd2

.const CART_ASSET_RESIDENT = 0
.const CART_ASSET_RUNTIME = 1
.const CART_ASSET_INDEX = 2
.const CART_ASSET_TITLE = 3
.const CART_ASSET_STARTUP = 4
.const CART_ASSET_TOWN = 5
.const CART_ASSET_DEATH = 6
.const CART_ASSET_DUNGEON_GEN = 7
.const CART_ASSET_HELP = 8
.const CART_ASSET_UI = 9
.const CART_ASSET_ITEMS = 10
.const CART_ASSET_SPELL = 11
.const CART_ASSET_MODAL_MISC = 12
.const CART_ASSET_CHEST = 13
.const CART_ASSET_CATALOG = 14
.const CART_ASSET_LEGAL_UI = 15
.const CART_ASSET_LEGAL_NOTICE = 16
.const CART_ASSET_LEGAL_OFFER = 17
.const CART_OVERLAY_COUNT = 10
.const CART_ASSET_COUNT = 18
