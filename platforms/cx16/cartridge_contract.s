#importonce
// Binary layout shared by cartridge_boot.s, cartridge_copy.s, and tools/make_cx16_cart.py.
// Target hardware: Commander X16 Cartridge ROM (16 KB banks starting at ROM bank 32).

.const CART_ROM_BANK_SIZE    = $4000
.const CART_ROM_WINDOW_BASE  = $c000
.const CART_ROM_WINDOW_END   = $10000
.const CART_ROM_BANK_START   = 32
.const CART_BANK_COUNT       = 8
.const CART_IMAGE_SIZE       = CART_BANK_COUNT * CART_ROM_BANK_SIZE

.const CART_BOOT_LIMIT       = $c100
.const CART_DIRECTORY        = $c100
.const CART_DESCRIPTOR_SIZE  = 8
.const CART_ENTRY            = $080d

.const CART_DESC_BANK        = 0
.const CART_DESC_ROM_LO      = 1
.const CART_DESC_ROM_HI      = 2
.const CART_DESC_DEST_LO     = 3
.const CART_DESC_DEST_HI     = 4
.const CART_DESC_RAM_BANK    = 5
.const CART_DESC_SIZE_LO     = 6
.const CART_DESC_SIZE_HI     = 7

.const CART_RAM_BANK_NONE    = $ff
.const CART_COPY_STUB_ADDR   = $0400

// x16emu signature ($9FBE/$9FBF = "16") and testbench handoff scratch ($07FC-$07FF).
.const CART_EMU_SIG0         = $9fbe
.const CART_EMU_SIG1         = $9fbf
.const CART_TB_MAGIC_ADDR    = $07fc

.const CART_ASSET_MORIA8_PRG   = 0
.const CART_ASSET_AUXDATA      = 1
.const CART_ASSET_HUFFDATA     = 2
.const CART_ASSET_OVL_START    = 3
.const CART_ASSET_OVL_TOWN     = 4
.const CART_ASSET_OVL_DEATH    = 5
.const CART_ASSET_OVL_GEN      = 6
.const CART_ASSET_OVL_HELP     = 7
.const CART_ASSET_OVL_UI       = 8
.const CART_ASSET_OVL_ITEMS    = 9
.const CART_ASSET_OVL_SPELL    = 10
.const CART_ASSET_OVL_MODAL    = 11
.const CART_ASSET_OVL_CHEST    = 12
.const CART_ASSET_OVL_STORAGE  = 13
.const CART_ASSET_OVL_TITLE    = 14
.const CART_ASSET_TITLE        = 15
.const CART_ASSET_MONSTER_CAT  = 16
.const CART_ASSET_LEGALUI      = 17
.const CART_ASSET_LICENSE      = 18
.const CART_ASSET_SOURCE_OFFER = 19
.const CART_ASSET_COUNT        = 20

.assert "Cartridge directory fits in Bank 32 $C100-$C1FF", CART_DIRECTORY + (CART_ASSET_COUNT * CART_DESCRIPTOR_SIZE) <= $c200, true
