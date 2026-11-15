#importonce
// Shared contract between tools/make_c128_md128.py, tools/check_c128_md128.py,
// platforms/commodore/c128/cartridge_boot.s, and cartridge_copy.s.
// Hardware: Commodore 128 Magic Desk 128 (CRT v2.0 Hardware ID 4).

.const CART_ENTRY            = $1c0e
.const CART_DIRECTORY        = $8100
.const CART_DESCRIPTOR_SIZE  = 8
.const CART_ROM_BANK_SIZE    = $4000
.const CART_BANK_COUNT       = 16
.const CART_REG_BANK         = $de00

.const MMU_EXT_ROM_IO        = $3a   // Bank 0 RAM, Ext Function ROM ($8000-$BFFF), I/O

// Descriptor byte 7 destination flags
.const CART_DEST_BANK0         = $00 // $FF00=$3E (Bank 0 RAM + I/O), $D506=$0D
.const CART_DEST_BANK1         = $01 // $FF00=$7E (Bank 1 RAM + I/O), $D506=$0D
.const CART_DEST_BANK1_TOP_OFF = $02 // $FF00=$7E, $D506=$05 under SEI ($F000-$FFFF Bank 1)

.const CART_ASSET_RESIDENT       = 0  // moria128.prg -> $1c01..<$af00 (Bank 0)
.const CART_ASSET_RUNTIME_LOW    = 1  // 128.runtime.prg -> $1000 (Bank 0)
.const CART_ASSET_RUNTIME_INPUT  = 2  // 128.input.prg -> $0b00 (common)
.const CART_ASSET_RUNTIME_PROJ   = 3  // 128.proj.prg -> $0a80 (common)
.const CART_ASSET_RUNTIME_COMMON = 4  // 128.fdisk.prg -> C128_RUNTIME_COMMON_BASE (common)
.const CART_ASSET_BANKED         = 5  // 128.bank.prg -> $f000 (Bank 0 / top common)
.const CART_ASSET_ITEM_CATALOG   = 6  // raw 'ITM2' ITEM.CAT -> byte-read from MD128 ROM ($3A)
.const CART_ASSET_HVEC           = 7  // 128.hvec.prg -> $fffa (Bank 1 top-common off)
.const CART_ASSET_HUFF           = 8  // 128.huff.prg -> $f000 (Bank 1 top-common off)
.const CART_ASSET_CAT            = 9  // 128.cat.prg -> $7e60 (Bank 1)
.const CART_ASSET_CNM            = 10 // 128.cnm.prg -> $a000 (Bank 1)
.const CART_ASSET_PERSIST        = 11 // 128.persist.prg -> $af00 (Bank 0)
.const CART_ASSET_PLAY           = 12 // 128.play.prg -> $af00 (Bank 0)

// Overlays match hal_storage_overlay_name_* order (0..11 -> 13..24)
.const CART_ASSET_OVL_BASE       = 13
.const CART_ASSET_STARTUP        = 13 // ovl.start -> $e000 (Bank 0)
.const CART_ASSET_TOWN           = 14 // ovl.town -> $e000 (Bank 0)
.const CART_ASSET_DEATH          = 15 // ovl.death -> $e000 (Bank 0)
.const CART_ASSET_DUNGEON_GEN    = 16 // ovl.gen -> $e000 (Bank 0)
.const CART_ASSET_HELP           = 17 // ovl.help -> $e000 (Bank 0)
.const CART_ASSET_UI             = 18 // ovl.ui -> $e000 (Bank 0)
.const CART_ASSET_ITEMS          = 19 // ovl.items -> $e000 (Bank 0)
.const CART_ASSET_SPELL          = 20 // ovl.disarm -> $e000 (Bank 0)
.const CART_ASSET_MODAL_MISC     = 21 // ovl.modal -> $e000 (Bank 0)
.const CART_ASSET_CHEST          = 22 // ovl.chest -> $e000 (Bank 0)
.const CART_ASSET_HOME           = 23 // ovl.home -> $e000 (Bank 0)
.const CART_ASSET_STORAGE        = 24 // ovl.storage -> $e000 (Bank 0)
.const CART_OVERLAY_COUNT        = 12

.const CART_ASSET_TITLE          = 25 // title -> $4000 (Bank 1)
.const CART_ASSET_LEGAL_UI       = 26 // legalui -> $e000 (Bank 0)
.const CART_ASSET_LEGAL_NOTICE   = 27 // LICENSE -> page stream to $e700 (Bank 0)
.const CART_ASSET_LEGAL_OFFER    = 28 // SOURCE-OFFER -> page stream to $e700 (Bank 0)
.const CART_ASSET_COUNT          = 29

.assert "Cartridge directory fits in Bank 0 page $8100-$81FF", CART_ASSET_COUNT * CART_DESCRIPTOR_SIZE <= $0100, true
.assert "Cartridge overlays stay contiguous", CART_ASSET_STORAGE - CART_ASSET_STARTUP + 1, CART_OVERLAY_COUNT
