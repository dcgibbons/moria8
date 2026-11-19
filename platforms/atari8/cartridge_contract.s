#importonce
// AtariMax MaxFlash 128 KB (.car type 41) ROM directory ABI.
// Owner: platforms/atari8/ cartridge build. Lifetime: build/boot/runtime constant ABI.
// Callers: platforms/atari8/{cartridge_boot.s,cartridge_copy.s,legal.s,legal_stream.s,main.s}
// and tools/{make_atari8_car.py,check_atari8_car.py}.
// tools/make_atari8_car.py parses these literal constants.

.const CART_WINDOW = $a000
.const CART_WINDOW_END = $c000
.const CART_ROM_BANK_SIZE = $2000
.const CART_ROM_BANK_COUNT = 16
.const CART_BANK_SELECT = $d500
.const CART_DISABLE = $d510
.const CART_TRIG3 = $d013
.const CART_OS_GINTLK = $03fa

.const CART_ENTRY = $0c00
.const CART_DIRECTORY = $a100
.const CART_DESCRIPTOR_SIZE = 8
.const CART_OVERLAY_COUNT = 13

.const CART_ASSET_RESIDENT = 0
.const CART_ASSET_RUNTIME = 1
.const CART_ASSET_TITLE = 2
.const CART_ASSET_STARTUP = 3
.const CART_ASSET_TOWN = 4
.const CART_ASSET_DEATH = 5
.const CART_ASSET_DUNGEON_GEN = 6
.const CART_ASSET_HELP = 7
.const CART_ASSET_UI = 8
.const CART_ASSET_ITEMS = 9
.const CART_ASSET_SPELL = 10
.const CART_ASSET_MODAL_MISC = 11
.const CART_ASSET_CHEST = 12
.const CART_ASSET_HOME = 13
.const CART_ASSET_STORAGE = 14
.const CART_ASSET_TITLE_OVL = 15
.const CART_ASSET_CATALOG = 16
.const CART_ASSET_LEGAL_UI = 17
.const CART_ASSET_LEGAL_NOTICE = 18
.const CART_ASSET_LEGAL_OFFER = 19
.const CART_ASSET_ITEM_CATALOG = 20
.const CART_ASSET_COUNT = 21
.assert "Directory index fits the byte reader", CART_ASSET_COUNT <= 32, true
