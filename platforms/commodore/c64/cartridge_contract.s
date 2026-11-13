#importonce
// ROM directory ABI. tools/make_easyflash.py reads these literal constants.
.const CART_ENTRY = $080e
.const CART_DIRECTORY = $8100
.const CART_DESCRIPTOR_SIZE = 8
.const CART_ROM_BANK_SIZE = $2000
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
.const CART_OVERLAY_COUNT = 10
.const CART_ASSET_LEGAL_OFFER = 17
.const CART_ASSET_COUNT = 18
.assert "Directory index fits the byte reader", CART_ASSET_COUNT <= 32, true
