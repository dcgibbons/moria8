#importonce
// memory128.s — Bank switching routines and memory map management (C128)
//
// C128 banking uses BOTH the MMU Configuration Register ($FF00/$D500)
// and the 8502 processor port ($01). A ROM is visible only if BOTH
// the MMU and processor port enable it.
//
// Strategy:
//   - At startup, set $FF00 to $0E (MMU_NORMAL: KERNAL+ScreenEd in, I/O).
//     This permanently removes BASIC ROM ($4000-$BFFF) from the memory map.
//   - Set $01 to $36 (KERNAL + I/O, no BASIC).
//   - Use $01 for runtime banking, identical to C64's memory.s approach.
//     Common code modules (reu.s, tier_manager.s, overlay.s, monster.s)
//     all use $01 directly, so this ensures compatibility.
//   - IMPORTANT: Bit 2 of $01 MUST STAY AT 1 on the C128 to keep I/O visible
//     for the KERNAL IRQ handler. If it is ever 0, the CPU sees CharROM
//     instead of CIA registers, leading to unacknowledged IRQs and crash.
//
// C128 MMU $FF00 bits (Configuration Register):
//   Bits 7-6: RAM bank select — 00=Bank 0, 01=Bank 1, 10/11=banks 2-3
//   Bits 5-4: $C000-$FFFF — 00=System ROM (KERNAL+ScreenEd), 11=RAM
//   Bits 3-2: $8000-$BFFF — 00=BASIC HI, 01=Int Func, 10=Ext Func, 11=RAM
//   Bit    1: $4000-$7FFF — 0=BASIC LOW ROM, 1=RAM
//   Bit    0: $D000 I/O — 0=I/O visible, 1=RAM/CharROM
//
// 8502 processor port ($01) bits — same as C64 6510:
//   Bit 0: LORAM  — 1=BASIC ROM, 0=RAM
//   Bit 1: HIRAM  — 1=KERNAL ROM, 0=RAM
//   Bit 2: CHAREN — 1=I/O at $D000, 0=Char ROM
//
// IMPORTANT:
//   - CPU writes ALWAYS go to RAM regardless of banking (same as C64).
//   - ROM must be banked OUT to READ data from RAM underneath.
//   - $E000–$FFFF: must wrap access in SEI/CLI because hardware
//     IRQ/NMI vectors at $FFFE/$FFFF will read from RAM when
//     KERNAL is banked out.

#import "hal/memory_bank_consts.s"
#import "hal/sound_consts.s"
#import "hal/entropy_consts.s"
#import "hal/layout.s"
#import "hal/lifecycle_policy.s"
#import "hal/storage_policy.s"
#import "../common/bank_port_consts.s"
#import "../common/vic_palette_consts.s"

// ============================================================
// MMU Constants (C128-specific)
// ============================================================
.const MMU_CR           = $ff00 // MMU Configuration Register (fast write)
.const MMU_NORMAL       = $0E   // Bank 0, System ROM (KERNAL+ScreenEd) at $C000, RAM $4000-$BFFF, I/O
                                // Bits 7-6=00(Bank0), 5-4=00(SysROM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
.const MMU_RAM_BANK1    = $7E   // Bank 1, all RAM, I/O visible
                                // Bits 7-6=01(Bank1), 5-4=11(RAM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
                                // Bank 1 has no ROMs — $C000-$CFFF is RAM, not Screen Ed ROM.
                                // Use to access Bank 1 data regions. boot128 stages the
                                // program into Bank 1 for the copy-to-Bank-0 step, then
                                // scrubs the staged source pages during that copy.
.const MMU_RAM_BANK1_NOIO = $7F // Bank 1, all RAM, I/O hidden ($D000-$DFFF = Bank 1 RAM)
                                // Bits 7-6=01(Bank1), 5-4=11(RAM), 3-2=11(RAM), 1=1(RAM), 0=1(RAM)
                                // Used only inside SEI-guarded common-RAM helpers ($D506=$0D
                                // keeps 4KB bottom/top common RAM and CPU vectors intact).
.const MMU_ALL_RAM      = $3E   // Bank 0, all RAM, I/O visible
                                // Bits 7-6=00(Bank0), 5-4=11(RAM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
                                // Hides Screen Editor ROM ($C000-$CFFF) AND KERNAL ROM
                                // ($E000-$FFFF) via MMU.  I/O still visible at $D000.
                                // Used as permanent operational mode after init; JMP stubs
                                // at $FFB7-$FFD5 in Bank 0 RAM handle KERNAL calls.
.const MMU_RAM_BANK2      = $BE // Bank 2, all RAM, I/O visible at $D000-$DFFF
.const MMU_RAM_BANK3      = $FE // Bank 3, all RAM, I/O visible at $D000-$DFFF

// ============================================================
// Processor port constants — same values as C64 (used by $01)
// Common code (reu.s, overlay.s, etc.) uses these directly.
// ============================================================
.const CPU_PORT_DDR_DEFAULT = $2F  // Standard 8502 DDR for banking bits as outputs

// ============================================================
// C128 ownership manifest (single source of truth)
// ============================================================
// Bank 1 runtime ownership after boot:
//   - bottom common RAM:       $0000-$0FFF (shared across banks, not cache-safe)
//   - overlay cache UI:        $1000-$1FFF
//   - overlay cache HELP:      $2000-$2FFF
//   - overlay cache ITEMS:     $3000-$3FFF
//   - live map span:           $4000-$730B (Phase 10.3 = 198x66)
//   - DB/data region:          $7400-$7A5F ($7400-$785B = recall[279] BSS)
//   - tier cache window:       $7A60-$9567
//   - title-art cache:         $9568-$97FF
//   - reserved (MODAL uncached):$9800-$9CFF (C128_OVERLAY_MODAL_CACHE_PAGES = 0)
//   - small overlay cache:     $9D00-$9FFF
//   - overlay cache STARTUP:   $A000-$AFFF
//   - overlay cache TOWN:      $B000-$BFFF
//   - overlay cache DEATH:     $C000-$CFFF
//   - Bank 1 high data ($7F):  $D000-$DFFF ($D000-$D8B7 = 128.CEX, $D8B8-$DCB7 = store inv reserve, $DCB8-$DF37 = msg_history)
//   - overlay cache DUNGEON:   $E000-$EFFF
//   - top common RAM:          $F000-$FEFF (shared with Bank 0; not cache-safe)
//   - Bank 1 NMI vector bridge:$FFFA-$FFFB (visible only with top common off)
//
// boot128 staging source span before scrub:
//   - $1C01-$FEFF in Bank 1, copied into Bank 0 and scrubbed page-by-page.
//
// 16 KB physical VDC RAM ownership ($0000-$3FFF):
//   - screen characters:       $0000-$07FF (2,000 B active + 48 B bulk-clear pad)
//   - screen attributes:       $0800-$0FFF (2,000 B active + 48 B bulk-clear pad)
//   - scroll-delta scratch:    $1000-$10FF (RVSD_SCRATCH_CHAR $1000, RVSD_SCRATCH_ATTR $1080)
//   - ITEM.CAT low span:       $1100-$1FFF (3,840 B = ITEM.CAT[0..3839], disk build)
//   - Set 0 & Set 1 charsets:  $2000-$3FFF (512 cells x 16 B:
//       bytes 0..7 per cell  = live 8x8 glyph rasters for Set 0 ($2000) & Set 1 ($3000);
//       bytes 8..15 per cell = unused in 8-scanline text mode -> holds
//                              ITEM.CAT[3840..7477] across 455 cells at $2008-$3C6D)

.macro AssertRegionBefore(desc, left_end, right_base) {
    .assert desc, left_end < right_base, true
}

.const BANK1_COMMON_BASE = $0000
.const BANK1_COMMON_END  = $0fff
.const BANK1_OVERLAY_UI_BASE = $1000
.const BANK1_OVERLAY_UI_END  = $1fff
.const BANK1_OVERLAY_HELP_BASE = $2000
.const BANK1_OVERLAY_HELP_END  = $2fff
.const BANK1_OVERLAY_ITEMS_BASE = $3000
.const BANK1_OVERLAY_ITEMS_END  = $3fff
.const C128_FUTURE_MAP_COLS = 198
.const C128_FUTURE_MAP_ROWS = 66
.const C128_FUTURE_MAP_SIZE = C128_FUTURE_MAP_COLS * C128_FUTURE_MAP_ROWS
.const MAP_BASE         = $4000
.const BANK1_MAP_RESERVED_END = MAP_BASE + C128_FUTURE_MAP_SIZE - 1
.const MMU_COPY_MAP_ROW_LEN = 78
.const MAP_END          = BANK1_MAP_RESERVED_END
.const BANK1_DB_BASE    = $7400
.const BANK1_DB_END     = $7a5f   // $7400-$785B (1,116 B) = recall[279] BSS; $785C-$78E9 (142 B) = zp_save_buf; $78EA-$7A5F = 374 B free
.const BANK1_RECALL_BASE = BANK1_DB_BASE
.const BANK1_RECALL_SIZE = 1116   // 279 * 4 bytes (must match RECALL_DATA_SIZE)
.const BANK1_RECALL_END  = BANK1_RECALL_BASE + BANK1_RECALL_SIZE - 1
.const BANK1_ZP_SAVE_BASE = BANK1_RECALL_END + 1
.const BANK1_ZP_SAVE_END  = BANK1_ZP_SAVE_BASE + 142 - 1
// The tier cache took the DB region's last page when tiers gained the
// cr_treasure SoA field (MON-014): tiers 1-4 needed 5520 bytes. Five DL 1
// creatures added to tier 1 (2026-10-25) needed 5733: the cache's end moved
// to $9567, into the title-art cache's slack (663 bytes left, 593-624
// needed). Twenty-five more the same day: its start moved down to $7a00, into
// the DB region's free tail above the item names ($79e1). The Long Bow,
// Composite Bow and Heavy Crossbow names (2026-10-26) took 16 bytes back.
// The names payload ended with it_unknown_idx at $7a4f, past its name
// streams, until the potions of gain stat (2026-11-07): it_unknown_idx moved
// to the resident items payload and the banked streams took the chest-name
// tokens, so it ends at $79e6 with 121 bytes to grow (main.s checks the
// payload's true end).
.const BANK1_TIER_CACHE_BASE = $7a60
.const BANK1_TIER_CACHE_SIZE = $9568 - BANK1_TIER_CACHE_BASE  // up to reserved gap 0
.const BANK1_TIER_CACHE_END  = BANK1_TIER_CACHE_BASE + BANK1_TIER_CACHE_SIZE - 1
.const BANK1_RESERVED_GAP0_BASE = $9568
.const BANK1_RESERVED_GAP0_END  = $9fff
.const C128_TITLE_CACHE_VALID_MARKER = $a5
.const BANK1_TITLE_CACHE_MARKER_BASE = BANK1_RESERVED_GAP0_BASE
.const BANK1_TITLE_CACHE_DATA_BASE   = BANK1_TITLE_CACHE_MARKER_BASE + 1
.const BANK1_TITLE_CACHE_END         = $97ff
.const BANK1_TITLE_CACHE_MAX_LEN     = BANK1_TITLE_CACHE_END - BANK1_TITLE_CACHE_DATA_BASE + 1
.const C128_TITLE_CACHE_MIN_REQUIRED = 593
// Title-art cache uses reserved gap 0 ($9568-$9cff); ModalMiscOverlay is
// cold on C128 so ui_wizard.s and ui_equipment.s fit below $F000 without Bank 1 cache pressure.
.const BANK1_OVERLAY_MODAL_BASE  = $9800
.const BANK1_OVERLAY_MODAL_END   = $9cff
.const BANK1_OVERLAY_DISARM_BASE  = $9d00
.const BANK1_OVERLAY_DISARM_END   = $9fff
.const BANK1_OVERLAY_STARTUP_BASE = $a000
.const BANK1_OVERLAY_STARTUP_END  = $afff
.const BANK1_OVERLAY_TOWN_BASE    = $b000
.const BANK1_OVERLAY_TOWN_END     = $bfff
.const BANK1_OVERLAY_DEATH_BASE   = $c000
.const BANK1_OVERLAY_DEATH_END    = $cfff
.const BANK1_RESERVED_IO_BASE     = $d000
.const BANK1_RESERVED_IO_END      = $dfff
.const BANK1_HIGH_DATA_BASE       = BANK1_RESERVED_IO_BASE
.const BANK1_HIGH_DATA_END        = BANK1_RESERVED_IO_END
.const BANK1_OVERLAY_DUNGEON_BASE = $e000
.const BANK1_OVERLAY_DUNGEON_END  = $efff
.const BANK1_RESERVED_TOP_BASE    = $f000
.const BANK1_RESERVED_TOP_END     = $feff
// Bank 1 Huffman corpus region (tree/index/compressed strings). Read-only
// data; all reads go through the mmu_safe_db_read thunks via the HuffRead_*
// macros (common/mmu_macros.s). Loader: c128_load_resident_huffman_prg.
.const BANK1_HUFFMAN_BASE         = BANK1_RESERVED_TOP_BASE
.const BANK1_HUFFMAN_END          = BANK1_RESERVED_TOP_END
.const BANK1_HUFFMAN_NMI_VECTOR_BASE = $fffa
.const BANK1_HUFFMAN_NMI_VECTOR_END  = $fffb
#if HAL_PLATFORM_MONSTER_CATALOG
// The monster catalog (docs/MONSTER_CATALOG_DESIGN.md, C128M-002 / C128M-007)
// takes the tier cache window, the STARTUP overlay slot (New Game loads
// OVL_STARTUP from disk), and the Bank 1 $D000-$D8B7 no-I/O data window:
//   $7A60-$7E5F  name pool, 32 species slots x 32 B, written at species fetch
//   $7E60-$9567  128.CAT: the catalog's 21 fields x 279 creatures, at boot
//   $A000-$AFFF  128.CNM: the catalog's Huffman-coded names, at boot
//   $D000-$D8B7  128.CEX: Phase 5 279 x 8 B extended rows, at boot ($7F read)
//   $D8B8-$DCB7  reserved 1,024 B store-inventory window inside $D000-$DFFF
//   $DCB8-$DF37  msg_history (8 x 80 = 640 B BSS via MSG_HISTORY_IN_AUX)
.const BANK1_CATALOG_POOL_BASE   = BANK1_TIER_CACHE_BASE
.const BANK1_CATALOG_POOL_END    = BANK1_CATALOG_POOL_BASE + 32 * 32 - 1
.const BANK1_CATALOG_FIELDS_BASE = BANK1_CATALOG_POOL_END + 1
.const BANK1_CATALOG_FIELDS_END  = BANK1_TIER_CACHE_END
.const BANK1_CATALOG_NAMES_BASE  = BANK1_OVERLAY_STARTUP_BASE
.const BANK1_CATALOG_NAMES_END   = BANK1_OVERLAY_STARTUP_END
#endif
.const BANK1_CATALOG_EXT_BASE        = $d000
.const BANK1_CATALOG_EXT_SIZE        = 279 * 8
.const BANK1_CATALOG_EXT_END         = $d8b7
.const BANK1_STORE_INV_RESERVED_BASE = $d8b8
.const BANK1_STORE_INV_RESERVED_SIZE = 1024
.const BANK1_STORE_INV_RESERVED_END  = $dcb7
.const BANK1_MSG_HISTORY_BASE        = $dcb8
.const BANK1_MSG_HISTORY_SIZE        = 8 * 80
.const BANK1_MSG_HISTORY_END         = $df37
.const BANK1_CACHE_OWNED_BASE     = BANK1_TIER_CACHE_BASE
.const BANK1_CACHE_OWNED_END      = BANK1_OVERLAY_DUNGEON_END

// Bank 2 ownership (256KB C128 MMU expansion, disk builds, MMU_RAM_BANK2 = $BE):
//   $0000-$0FFF  Bottom common RAM (Bank 0, $D506=$0D)
//   $1000-$1FFF  OVL_STARTUP (ID 1)
//   $2000-$2FFF  OVL_CHEST (ID 10)
//   $3000-$3FFF  OVL_HOME (ID 11)
//   $4000-$4FFF  OVL_STORAGE (ID 12)
//   $5000-$59FF  LEGALUI (10 pages covering $E000-$E9FF; below legal_zp_save $EE00)
//   $5A00-$5FFF  1.5 KB reserve
//   $6000-$80FF  128.PLAY (33 pages = full $AF00-$CFFF modal window)
//   $8100-$93FF  128.PERSIST (19 pages covering $AF00-$C1FF; below 128.PLAY live state)
//   $9400-$A3FF  OVL_MODAL_MISC (ID 9)
//   $A400-$CFFF  11.0 KB free; $D000-$DFFF I/O visible ($BE); $E000-$EFFF 4 KB free
.const BANK2_OVERLAY_STARTUP_BASE = $1000
.const BANK2_OVERLAY_STARTUP_END  = $1fff
.const BANK2_OVERLAY_CHEST_BASE   = $2000
.const BANK2_OVERLAY_CHEST_END    = $2fff
.const BANK2_OVERLAY_HOME_BASE    = $3000
.const BANK2_OVERLAY_HOME_END     = $3fff
.const BANK2_OVERLAY_STORAGE_BASE = $4000
.const BANK2_OVERLAY_STORAGE_END  = $4fff
.const BANK2_LEGALUI_BASE         = $5000
.const BANK2_LEGALUI_PAGES        = $0a
.const BANK2_LEGALUI_END          = BANK2_LEGALUI_BASE + (BANK2_LEGALUI_PAGES * $100) - 1
.const BANK2_PLAY_BASE            = $6000
.const BANK2_PLAY_PAGES           = $21
.const BANK2_PLAY_END             = BANK2_PLAY_BASE + (BANK2_PLAY_PAGES * $100) - 1
.const BANK2_PERSIST_BASE         = $8100
.const BANK2_PERSIST_PAGES        = $13
.const BANK2_PERSIST_END          = BANK2_PERSIST_BASE + (BANK2_PERSIST_PAGES * $100) - 1
.const BANK2_OVERLAY_MODAL_BASE   = $9400
.const BANK2_OVERLAY_MODAL_END    = $a3ff
.const C128_BANK2_PLAY_BIT        = $01
.const C128_BANK2_PERSIST_BIT     = $02
.const C128_BANK2_LEGALUI_BIT     = $04

.const MMU_SAVE_01           = $0c00
.const MMU_SAVE_FF00         = $0c01
.const KERNAL_NESTING_DEPTH  = $0c02
.const MMU_IRQ_SAVE_01       = $0c03
.const MMU_IRQ_SAVE_FF00     = $0c04
.const MMU_IRQ_SAVE_D506     = $0c05
.const MMU_COMMON_HELPERS_BASE = $0c06
#if C128_CARTRIDGE
.const MMU_COMMON_CART_CHUNK_MAX = 32
.const MMU_COMMON_CART_BASE      = $0fb0
#endif
.const BANK1_STAGE_SOURCE_BASE = $1c01 // boot128 loads MORIA128 here in Bank 1 before copy
.const BANK1_STAGE_SOURCE_END  = $feff // copy stub stops before $ff00
.const TIER_PRELOAD_REQUIRED = BANK1_TIER_CACHE_SIZE
.const BANK1_STAGE_BASE = BANK1_STAGE_SOURCE_BASE
.const BANK1_TAIL_END   = BANK1_STAGE_SOURCE_END
.const BANK1_FREE_HIGH_BASE = BANK1_TIER_CACHE_BASE
.const BANK1_FREE_HIGH_END  = BANK1_CACHE_OWNED_END
.const OVERLAY_CACHE_SLOT_SIZE = $1000
.const OVERLAY_CACHE_UI_BASE    = BANK1_OVERLAY_UI_BASE
.const OVERLAY_CACHE_HELP_BASE  = BANK1_OVERLAY_HELP_BASE
.const OVERLAY_CACHE_ITEMS_BASE = BANK1_OVERLAY_ITEMS_BASE
.const OVERLAY_CACHE_START_BASE = BANK1_OVERLAY_STARTUP_BASE
.const OVERLAY_CACHE_TOWN_BASE  = BANK1_OVERLAY_TOWN_BASE
.const OVERLAY_CACHE_DEATH_BASE = BANK1_OVERLAY_DEATH_BASE
.const OVERLAY_CACHE_GEN_BASE   = BANK1_OVERLAY_DUNGEON_BASE
.const OVERLAY_CACHE_GEN_END    = BANK1_OVERLAY_DUNGEON_END
.const OVERLAY_CACHE_DISARM_BASE = BANK1_OVERLAY_DISARM_BASE
.const OVERLAY_CACHE_DISARM_END  = BANK1_OVERLAY_DISARM_END
.const C128_OVERLAY_DISARM_CACHE_PAGES = 3
.const C128_OVERLAY_MODAL_CACHE_PAGES = 0
.const FLOOR_ITEM_BASE  = $1a00 // Floor item table (Bank 0)
.const FLOOR_ITEM_END   = $1aff
.const CREATURE_BASE    = $1b00 // Runtime scratch area (Bank 0)
.const CREATURE_END     = $1bff
.const BANKED_DATA_BASE = $e000 // Item tiers, recall, spells (under KERNAL ROM)
.const BANKED_DATA_END  = $ffff
.const SCREEN_RAM       = $0400 // VIC-II screen RAM (used as scratch buffer on C128)
.const COLOR_RAM        = $d800 // VIC-II color RAM (VDC has separate attributes)
.const DUNGEON_GEN_SCAN_SCRATCH_BASE = SCREEN_RAM
.const DUNGEON_GEN_SCAN_SCRATCH_SIZE = 1024
.const DUNGEON_GEN_SCAN_SCRATCH_END  = DUNGEON_GEN_SCAN_SCRATCH_BASE + DUNGEON_GEN_SCAN_SCRATCH_SIZE - 1
.const DUNGEON_GEN_DOOR_SCAN_BASE = $0500
.const DUNGEON_GEN_DOOR_SCAN_SIZE = 65
.const DUNGEON_GEN_DOOR_SCAN_END  = DUNGEON_GEN_DOOR_SCAN_BASE + DUNGEON_GEN_DOOR_SCAN_SIZE - 1
.const DUNGEON_GEN_DOOR_SCAN_LIMIT = $0800

// 16 KB VDC RAM non-overlapping layout constants (C128M-015).
.const VDC_RAM_SIZE              = $4000
.const VDC_SCRATCH_BASE          = $1000
.const VDC_SCRATCH_END           = $10ff
.const VDC_ITEM_CAT_LO_BASE      = $1100
.const VDC_ITEM_CAT_LO_SIZE      = $0f00
.const VDC_ITEM_CAT_LO_END       = VDC_ITEM_CAT_LO_BASE + VDC_ITEM_CAT_LO_SIZE - 1
.const VDC_CHARSET_BASE          = $2000
.const VDC_CHARSET_END           = $3fff
.const VDC_ITEM_CAT_CELL_OFFSET  = $08
.const VDC_ITEM_CAT_CELL_STRIDE  = $10
.const VDC_ITEM_CAT_CELL_BYTES   = $08
.const VDC_ITEM_CAT_HI_CAP       = ((VDC_CHARSET_END - VDC_CHARSET_BASE + 1) / VDC_ITEM_CAT_CELL_STRIDE) * VDC_ITEM_CAT_CELL_BYTES
.const VDC_ITEM_CAT_TOTAL_CAP    = VDC_ITEM_CAT_LO_SIZE + VDC_ITEM_CAT_HI_CAP

// ZP save buffer — stores $02–$8F in Bank 1 ($785C-$78E9) during game, restored on exit.
.const ZP_SAVE_SIZE     = 142   // $02–$8F inclusive
.label zp_save_buf      = BANK1_ZP_SAVE_BASE
zp_save_orig_ptr:       .word 0

// KERNAL ZP save buffer — used during EnterKernal/ExitKernal calls
// to protect game state from KERNAL clobbering.
kernal_zp_save_buf:
    .fill ZP_SAVE_SIZE, 0

// ============================================================
// Macros — use $01 for runtime banking (C64-compatible)
// ============================================================

// Bank out BASIC ROM — exposes RAM at $A000–$BFFF
// (On C128, BASIC is already out via MMU; this is a no-op for safety)
// Must keep bit 2 set for I/O.
.macro BankOutBasic() {
    lda $01
    and #%11111110  // Clear bit 0 (LORAM)
    ora #%00000100  // Ensure bit 2 (CHAREN) is 1
    sta $01
}

// Bank in BASIC ROM — restores ROM at $A000–$BFFF
// (On C128, MMU keeps BASIC out regardless, so this is effectively a no-op)
.macro BankInBasic() {
    lda $01
    ora #%00000101  // Set bit 0 (LORAM) and bit 2 (CHAREN)
    sta $01
}

// Bank out KERNAL ROM — exposes RAM at $E000–$FFFF
// MUST be called after SEI.
.macro BankOutKernal() {
    lda $01
    and #%11111101  // Clear bit 1 (HIRAM)
    ora #%00000100  // Ensure bit 2 (CHAREN) is 1
    sta $01
}

// Bank in KERNAL ROM — restores ROM at $E000–$FFFF
.macro BankInKernal() {
    lda $01
    ora #%00000110  // Set bit 1 (HIRAM) and bit 2 (CHAREN)
    sta $01
}

// Bank out both BASIC and KERNAL — RAM everywhere except I/O
// Caller MUST have called SEI first.
.macro BankOutAll() {
    lda $01
    and #%11111100  // Clear bits 0 and 1
    ora #%00000100  // Ensure bit 2 (CHAREN) is 1
    sta $01
}

// Restore default banking (BASIC + KERNAL + I/O)
.macro BankRestoreDefault() {
    lda #CPU_PORT_DDR_DEFAULT
    sta $00
    lda #BANK_ALL_ROM
    sta $01
}

// MachineRestoreDefault — Ensure MMU and processor port are in a
// safe, operational state for KERNAL/Screen Editor.
// $FF00 = $0E (Bank 0, ROMs, I/O)
// $01   = $36 (HIRAM=1, ROMs visible)
// $D506 = $05 (4KB Bottom Common only — Top Common OFF for KERNAL ROM access)
.macro MachineRestoreDefault() {
    lda #$05
    sta $d506
    lda #MMU_NORMAL
    sta $ff00
    lda #CPU_PORT_DDR_DEFAULT
    sta $00
    lda #$36
    sta $01
}

// MachineRestoreAllRam — Restore the game's operational MMU state.
// $FF00 = $3E (Bank 0, All RAM, I/O visible)
// $D506 = $0D (4KB Bottom/Top ON — Expert Recommended for Vector Safety)
.macro MachineRestoreAllRam() {
    lda #$0D
    sta $d506
    lda #MMU_ALL_RAM
    sta $ff00
    lda #CPU_PORT_DDR_DEFAULT
    sta $00
    lda #BANK_NO_BASIC
    sta $01
}

// EnterKernal — Prepare for KERNAL calls (C128)
.macro EnterKernal() {
    jsr EnterKernal_sub
}

EnterKernal_sub:
#if C128_TEST_STACK_LOW_WATER
    lda #$a1
    jsr c128_stack_low_water_check
#endif
    sei
    inc KERNAL_NESTING_DEPTH
    lda KERNAL_NESTING_DEPTH
    cmp #1
    bne !ek_nest+           // Already in Kernal mode — don't overwrite saved state
    lda $01
    sta MMU_SAVE_01
    lda $ff00
    sta MMU_SAVE_FF00
    jsr save_kernal_zp      // Protect game state in kernal_zp_save_buf
    lda #$ff
    sta zp_screen_editor_state // Force default keyboard row
    
    // Bridge to KERNAL: Top Common MUST be OFF ($05) to expose ROM jump table
    lda #$05
    sta $d506
    :MachineRestoreDefault() // Set MMU/IO for Kernal use
    
    // In KERNAL mode $0314 is the KERNAL software IRQ vector. Keep it on the
    // captured KERNAL target; mmu_common_irq is a hardware-vector entry used
    // only by the all-RAM runtime path and has a different calling convention.
    lda kernal_irq_vec_lo
    sta $0314
    lda kernal_irq_vec_hi
    sta $0315
!ek_nest:
#if C128_TEST_STACK_LOW_WATER
    lda #$a2
    jsr c128_stack_low_water_check
#endif
    rts

// Exit Kernal — Restore game state after KERNAL calls (C128)
.macro ExitKernal() {
    jsr ExitKernal_sub
}

ExitKernal_sub:
#if C128_TEST_STACK_LOW_WATER
    lda #$a3
    jsr c128_stack_low_water_check
#endif
    sei                     // Atomic: KERNAL calls (like LOAD) often re-enable IRQs
    


    dec KERNAL_NESTING_DEPTH
    bne !ex_nest+           // Still nested — don't restore yet
    jsr restore_kernal_zp   // Restore game state from kernal_zp_save_buf
    // Restore Runtime Invariant: Top Common ON ($0D)
    // MUST be done BEFORE restoring $FF00 because $FF00 may be Bank 1 (no vectors)
    lda #$0D
    sta $d506
    lda MMU_SAVE_01
    sta $01
    lda MMU_SAVE_FF00
    sta $ff00
    lda c128_kernal_irq_tail_runtime_owned
    beq !ex_skip_runtime_irq+
    // Software IRQ dispatch — lightweight, no I/O
    lda #<mmu_common_irq
    sta $0314
    lda #>mmu_common_irq
    sta $0315
!ex_skip_runtime_irq:
!ex_nest:
#if C128_TEST_STACK_LOW_WATER
    lda #$a4
    jsr c128_stack_low_water_check
#endif
    rts

// MMU Bank 1 Access Macros
.macro Bank1Read() {
    lda #MMU_RAM_BANK1
    sta MMU_CR
}

.macro Bank1Write() {
    lda #MMU_RAM_BANK1
    sta MMU_CR
}

.macro Bank0Restore() {
    lda #MMU_ALL_RAM
    sta MMU_CR
}

#if C128_TEST_STACK_LOW_WATER
c128_stack_low_water_check:
    sta c128_stack_low_water_stage
    tsx
    stx c128_stack_low_water_sp
    cpx #$20
    bcs !ok+
    lda $01
    sta c128_stack_low_water_port1
    lda $ff00
    sta c128_stack_low_water_mmu
    lda $0101,x
    sta c128_stack_low_water_stack_0
    lda $0102,x
    sta c128_stack_low_water_stack_1
    lda $0103,x
    sta c128_stack_low_water_stack_2
    lda $0104,x
    sta c128_stack_low_water_stack_3
    lda $0105,x
    sta c128_stack_low_water_stack_4
    lda $0106,x
    sta c128_stack_low_water_stack_5
    lda $0107,x
    sta c128_stack_low_water_stack_6
    lda $0108,x
    sta c128_stack_low_water_stack_7
    brk
!ok:
    rts

c128_stack_low_water_stage:   .byte 0
c128_stack_low_water_sp:      .byte 0
c128_stack_low_water_port1:   .byte 0
c128_stack_low_water_mmu:     .byte 0
c128_stack_low_water_stack_0: .byte 0
c128_stack_low_water_stack_1: .byte 0
c128_stack_low_water_stack_2: .byte 0
c128_stack_low_water_stack_3: .byte 0
c128_stack_low_water_stack_4: .byte 0
c128_stack_low_water_stack_5: .byte 0
c128_stack_low_water_stack_6: .byte 0
c128_stack_low_water_stack_7: .byte 0
#endif

// ============================================================
// Subroutines
// ============================================================

// init_common_mmu_helpers — Copy Bank 1-safe helper stubs into bottom common RAM.
// These helpers must execute entirely from $0000-$0FFF because any instruction
// fetched while Bank 1 is selected cannot rely on Bank 0 program space.
init_common_mmu_helpers:
    ldx #0
!copy_page0:
    lda mmu_common_helpers_blob,x
    sta MMU_COMMON_HELPERS_BASE,x
    inx
    bne !copy_page0-
    ldx #0
!copy_tail:
    cpx #mmu_common_helpers_blob_end - mmu_common_helpers_blob - $100
    beq !done+
    lda mmu_common_helpers_blob + $100,x
    sta MMU_COMMON_HELPERS_BASE + $100,x
    inx
    jmp !copy_tail-
!done:
#if C128_CARTRIDGE
    ldx #mmu_common_cart_blob_end - mmu_common_cart_blob - 1
!copy_cart:
    lda mmu_common_cart_blob,x
    sta MMU_COMMON_CART_BASE,x
    dex
    bpl !copy_cart-
#endif
    rts

// mmu_save_p — Static storage for CPU status register during bank switches
mmu_save_p: .byte 0

// mmu_select_bank1 — Select Bank 1 RAM, preserve IRQ state
// Contract: must be paired with mmu_select_bank0. Clobbers: A.
mmu_select_bank1:
    php
    sei
    pla
    sta mmu_save_p
    lda #MMU_RAM_BANK1
    sta MMU_CR
    rts

// mmu_select_bank0 — Restore Bank 0 RAM and prior IRQ state
// Contract: must be paired with mmu_select_bank1. Clobbers: A.
mmu_select_bank0:
    lda #MMU_ALL_RAM
    sta MMU_CR
    lda mmu_save_p
    pha
    plp
    rts

// save_kernal_zp — Copy $02–$8F to kernal_zp_save_buf
save_kernal_zp:
    ldx #0
!loop:
    lda zp_temp0,x
    sta kernal_zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// restore_kernal_zp — Copy kernal_zp_save_buf back to $02–$8F
restore_kernal_zp:
    ldx #0
!loop:
    lda kernal_zp_save_buf,x
    sta zp_temp0,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// save_zp — Copy $02–$8F to Bank 1 BANK1_ZP_SAVE_BASE (original BASIC state)
save_zp:
    lda zp_ptr1
    sta zp_save_orig_ptr
    lda zp_ptr1_hi
    sta zp_save_orig_ptr + 1
    lda #<BANK1_ZP_SAVE_BASE
    sta zp_ptr1
    lda #>BANK1_ZP_SAVE_BASE
    sta zp_ptr1_hi
    ldx #0
!loop:
    lda zp_temp0,x
    cpx #(zp_ptr1 - zp_temp0)
    bne !chk_hi+
    lda zp_save_orig_ptr
!chk_hi:
    cpx #(zp_ptr1_hi - zp_temp0)
    bne !write+
    lda zp_save_orig_ptr + 1
!write:
    ldy #0
    jsr mmu_common_db_write_ptr1
    inc zp_ptr1
    bne !next+
    inc zp_ptr1_hi
!next:
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    lda zp_save_orig_ptr
    sta zp_ptr1
    lda zp_save_orig_ptr + 1
    sta zp_ptr1_hi
    rts

// restore_zp — Copy Bank 1 BANK1_ZP_SAVE_BASE back to $02–$8F (original BASIC state)
restore_zp:
    lda #<BANK1_ZP_SAVE_BASE
    sta zp_ptr0
    lda #>BANK1_ZP_SAVE_BASE
    sta zp_ptr0_hi
    ldx #0
!loop:
    ldy #0
    jsr mmu_common_db_read_ptr0
    cpx #(zp_ptr0 - zp_temp0)
    bne !chk_hi+
    sta zp_save_orig_ptr
    jmp !next+
!chk_hi:
    cpx #(zp_ptr0_hi - zp_temp0)
    bne !store+
    sta zp_save_orig_ptr + 1
    jmp !next+
!store:
    sta zp_temp0,x
!next:
    inc zp_ptr0
    bne !inc_ok+
    inc zp_ptr0_hi
!inc_ok:
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    lda zp_save_orig_ptr
    sta zp_ptr0
    lda zp_save_orig_ptr + 1
    sta zp_ptr0_hi
    rts

// c128_vdc_reassert_mode — Defensive VDC mode restore
// Reasserts cached known-good register values:
//   - Reg 25 (attribute/mode register as configured in init)
//   - Reg 26 (default fg/bg color)
// Safe to call from both KERNAL exit paths and render paths.
c128_vdc_reassert_mode:
    php
    sei

    // Reg 25: restore known-good mode byte.
    jsr c128_vdc_wait
    lda #25
    sta $d600
    jsr c128_vdc_wait
    lda c128_vdc_reg25_cached
    sta $d601

    // Reg 26: restore known-good default fg/bg (white on black).
    jsr c128_vdc_wait
    lda #26
    sta $d600
    jsr c128_vdc_wait
    lda c128_vdc_reg26_cached
    sta $d601
    plp
    rts

c128_vdc_wait:
    bit $d600
    bpl c128_vdc_wait
    rts

// Cached VDC defaults captured during init in main.s.
// Keep explicit initial values so early calls still restore sane mode.
c128_vdc_reg25_cached: .byte $40
c128_vdc_reg26_cached: .byte $f0

// 256KB MMU expansion state (populated by c128_detect_256k; read from Bank 0).
c128_ram_256k:    .byte 0
.label hal_platform_256k_present = c128_ram_256k
c128_xbank_cr:    .byte MMU_RAM_BANK1
c128_bank2_flags: .byte 0

c128_probe_mmu: .byte MMU_ALL_RAM, MMU_RAM_BANK1, MMU_RAM_BANK2, MMU_RAM_BANK3
c128_probe_pat: .byte $a5, $5a, $c3, $3c

// c128_detect_256k — Non-destructive 2-pass probe for 256KB MMU RAM (Banks 0-3).
// Requires init_common_mmu_helpers and $D506=$0D (4KB bottom/top common RAM).
// Output: c128_ram_256k = 1 if Banks 2 & 3 are independent R/W RAM, else 0;
//         c128_bank2_flags = 0.
// Clobbers: A, X, Y, zp_ptr1, zp_temp0, zp_temp1. Preserves caller IRQ state.
c128_detect_256k:
    php
    sei

    ldy #0
    sty zp_ptr1
    sty c128_ram_256k
    sty c128_bank2_flags
    sty zp_temp0
    lda #$e0
    sta zp_ptr1_hi

    lda $e000
    pha
    lda #MMU_RAM_BANK1
    jsr mmu_common_bank_read_ptr1
    pha

!pass:
    ldx #3
!wr:
    lda c128_probe_pat,x
    eor zp_temp0
    pha
    lda c128_probe_mmu,x
    stx zp_temp1
    tax
    pla
    jsr mmu_common_bank_write_ptr1
    ldx zp_temp1
    dex
    bpl !wr-

    ldx #3
!rd:
    lda c128_probe_mmu,x
    jsr mmu_common_bank_read_ptr1
    eor zp_temp0
    cmp c128_probe_pat,x
    bne !done+
    dex
    bpl !rd-

    lda zp_temp0
    eor #$ff
    sta zp_temp0
    bne !pass-
    inc c128_ram_256k

!done:
    ldx #MMU_RAM_BANK1
    pla                         // Y is 0 from !pass/!wr or !rd mismatch
    jsr mmu_common_bank_write_ptr1
    pla
    sta $e000

    plp
    rts

bank1_overlay_cache_slot_lo:
#if HAL_PLATFORM_MONSTER_CATALOG
    .byte 0, <BANK2_OVERLAY_STARTUP_BASE, <BANK1_OVERLAY_TOWN_BASE, <BANK1_OVERLAY_DEATH_BASE, <BANK1_OVERLAY_DUNGEON_BASE, <BANK1_OVERLAY_HELP_BASE, <BANK1_OVERLAY_UI_BASE, <BANK1_OVERLAY_ITEMS_BASE, <BANK1_OVERLAY_DISARM_BASE, <BANK2_OVERLAY_MODAL_BASE, <BANK2_OVERLAY_CHEST_BASE, <BANK2_OVERLAY_HOME_BASE, <BANK2_OVERLAY_STORAGE_BASE
#else
    .byte 0, <BANK1_OVERLAY_STARTUP_BASE, <BANK1_OVERLAY_TOWN_BASE, <BANK1_OVERLAY_DEATH_BASE, <BANK1_OVERLAY_DUNGEON_BASE, <BANK1_OVERLAY_HELP_BASE, <BANK1_OVERLAY_UI_BASE, <BANK1_OVERLAY_ITEMS_BASE, <BANK1_OVERLAY_DISARM_BASE, <BANK2_OVERLAY_MODAL_BASE, <BANK2_OVERLAY_CHEST_BASE, <BANK2_OVERLAY_HOME_BASE, <BANK2_OVERLAY_STORAGE_BASE
#endif
bank1_overlay_cache_slot_hi:
#if HAL_PLATFORM_MONSTER_CATALOG
    .byte 0, >BANK2_OVERLAY_STARTUP_BASE, >BANK1_OVERLAY_TOWN_BASE, >BANK1_OVERLAY_DEATH_BASE, >BANK1_OVERLAY_DUNGEON_BASE, >BANK1_OVERLAY_HELP_BASE, >BANK1_OVERLAY_UI_BASE, >BANK1_OVERLAY_ITEMS_BASE, >BANK1_OVERLAY_DISARM_BASE, >BANK2_OVERLAY_MODAL_BASE, >BANK2_OVERLAY_CHEST_BASE, >BANK2_OVERLAY_HOME_BASE, >BANK2_OVERLAY_STORAGE_BASE
#else
    .byte 0, >BANK1_OVERLAY_STARTUP_BASE, >BANK1_OVERLAY_TOWN_BASE, >BANK1_OVERLAY_DEATH_BASE, >BANK1_OVERLAY_DUNGEON_BASE, >BANK1_OVERLAY_HELP_BASE, >BANK1_OVERLAY_UI_BASE, >BANK1_OVERLAY_ITEMS_BASE, >BANK1_OVERLAY_DISARM_BASE, >BANK2_OVERLAY_MODAL_BASE, >BANK2_OVERLAY_CHEST_BASE, >BANK2_OVERLAY_HOME_BASE, >BANK2_OVERLAY_STORAGE_BASE
#endif
bank1_overlay_cache_pages:
    .byte 0, $10, $10, $10, $10, $10, $10, $10, C128_OVERLAY_DISARM_CACHE_PAGES, $10, $10, $10, $10
bank_overlay_cache_mmu:
#if HAL_PLATFORM_MONSTER_CATALOG
    .byte 0, MMU_RAM_BANK2, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK2, MMU_RAM_BANK2, MMU_RAM_BANK2, MMU_RAM_BANK2
#else
    .byte 0, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK1, MMU_RAM_BANK2, MMU_RAM_BANK2, MMU_RAM_BANK2, MMU_RAM_BANK2
#endif
bank_overlay_cache_mmu_end:

// Common-RAM MMU helpers copied to $0C06 at startup.
// Labels inside the pseudopc block resolve to their runtime common addresses.
mmu_common_helpers_blob:
.pseudopc MMU_COMMON_HELPERS_BASE {
mmu_common_irq:
    cld
mmu_common_irq_after_cld:
    pha
    txa
    pha
    tya
    pha

    // Save current MMU state to IRQ-specific statics in Common RAM
    lda $01
    sta MMU_IRQ_SAVE_01
    lda $ff00
    sta MMU_IRQ_SAVE_FF00
    lda $d506
    sta MMU_IRQ_SAVE_D506

    // Force known-good Bank 0 All-RAM mode with I/O visible
    lda #$0D                    // 4KB Bottom/Top Common ON
    sta $d506
    lda #MMU_ALL_RAM
    sta $ff00
    lda #BANK_NO_BASIC
    sta $01

    // Acknowledge all possible interrupt sources (CIA1 and VIC-II)
    lda $dc0d
    lda #$ff
    sta $d019

    // Restore original MMU state
    lda MMU_IRQ_SAVE_D506
    sta $d506
    lda MMU_IRQ_SAVE_01
    sta $01
    lda MMU_IRQ_SAVE_FF00
    sta $ff00

    pla
    tay
    pla
    tax
    pla
    // C128 MMU saves/restores $FF00 via internal hardware latch on
    // interrupt entry/exit — no extra byte is pushed to the stack.
    // The previous extra PLA here was a dormant bug (stole caller's P
    // register, causing RTI to jump to a garbage address).
    rti

mmu_common_nmi:
    cld
mmu_common_nmi_after_cld:
    pha
    lda $dd0d                   // Acknowledge CIA2 NMI
    pla
    // No extra PLA — see mmu_common_irq comment above.
    rti

mmu_common_map_read_ptr0:
    jsr mmu_common_select_bank1
    lda (zp_ptr0),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

mmu_common_map_write_ptr0:
    pha
    jsr mmu_common_select_bank1
    pla
    sta (zp_ptr0),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

// Input: zp_ptr1 + Y = address, A = non-zero MMU CR (I/O visibility optional; NMI safe with bit 0 = 0).
// Output: A = byte read. Preserves X, Y.
mmu_common_map_read_ptr1:
    lda #MMU_RAM_BANK1_NOIO
mmu_common_bank_read_ptr1:
    jsr mmu_common_select_bank_a
    lda (zp_ptr1),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

// Input: zp_ptr1 + Y = address, A = byte to write, X = non-zero MMU CR (for bank_write).
// Preserves Y, returns written byte in A.
mmu_common_map_write_ptr1:
    pha
    lda #MMU_RAM_BANK1_NOIO
    bne !mcw1_go+
mmu_common_bank_write_ptr1:
    pha
    txa
!mcw1_go:
    jsr mmu_common_select_bank_a
    pla
    sta (zp_ptr1),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

// Input: zp_ptr0 = Bank 1 map row, Y = first column, A = last column.
//        mmu_common_row_mask = flags to OR into each tile.
//        mmu_common_row_detect_new = 1 to report any newly visited tile.
// Output: A = 1 if detect-new was enabled and any tile lacked FLAG_VISITED,
//         0 otherwise.
// Preserves: X. Clobbers Y and caller flags.
mmu_common_mark_visited_row_ptr0:
    sta mmu_common_row_end
    lda #0
    sta mmu_common_row_seen_new
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
!mark:
    lda (zp_ptr0),y
    sta mmu_common_tile_tmp
    lda mmu_common_row_detect_new
    beq !write+
    lda mmu_common_tile_tmp
    and #$04                    // FLAG_VISITED; dungeon_data.s is imported later.
    bne !already_visited+
    lda #1
    sta mmu_common_row_seen_new
!already_visited:
!write:
    lda mmu_common_tile_tmp
    ora mmu_common_row_mask
    sta (zp_ptr0),y
    cpy mmu_common_row_end
    beq !done+
    iny
    jmp !mark-
!done:
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    lda mmu_common_row_seen_new
    rts

// Huffman corpus reads differ from ordinary Bank 1 DB reads: the corpus is
// physically under the runtime's 4KB top-common window. The corpus PRG places
// an NMI vector to mmu_common_nmi in Bank 1 before these helpers can run.
// Entry/return invariant: Bank 0 all-RAM, $D506=$0D. Preserves X and Y.
mmu_common_huff_read_ptr0:
    php
    sei
    jsr mmu_common_huff_select_bank1
    lda (zp_ptr0),y
    jmp mmu_common_huff_restore_bank0

mmu_common_huff_read_ptr1:
    php
    sei
    jsr mmu_common_huff_select_bank1
    lda (zp_ptr1),y
    jmp mmu_common_huff_restore_bank0

mmu_common_huff_select_bank1:
    lda #$05                    // 4KB bottom common; expose Bank 1 at $F000
    sta $d506
    lda #MMU_RAM_BANK1
    sta MMU_CR
    rts

mmu_common_huff_restore_bank0:
    sta mmu_common_huff_value
    lda #MMU_ALL_RAM
    sta MMU_CR
    lda #$0d                    // Restore 4KB bottom/top common invariant
    sta $d506
    plp
    lda mmu_common_huff_value
    rts

#if C128_TEST_COUNT_MAP_ROW_STORES || C128_TEST_MAP_ROW_STORE_HELPER
#import "map_row_store_common.s"
#endif

// Copy A bytes from the Bank 1 row at zp_ptr0 into Bank 0 SCREEN_RAM.
// Input: A = byte count (1-255), zp_ptr0 = Bank 1 source row.
// Preserves: X. Clobbers: A, Y and caller flags.
mmu_common_copy_map_row:
#if C128_TEST_COUNT_MAP_ROW_COPIES
    inc c128_test_row_copy_count_lo
    bne !counted+
    inc c128_test_row_copy_count_hi
!counted:
#endif
    sta mmu_common_row_end
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta SCREEN_RAM,y
    iny
    cpy mmu_common_row_end
    bne !copy-
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts

mmu_common_select_bank1:
    lda #MMU_RAM_BANK1_NOIO
mmu_common_select_bank_a:
    php
    sei
    sta MMU_CR
    pla
    sta mmu_common_save_p
    rts

mmu_common_select_bank0:
    lda #MMU_ALL_RAM
    sta MMU_CR
    lda mmu_common_save_p
    pha
    plp
    rts

#if !C128_CARTRIDGE
// Fast 1-page Bank X -> Bank 0 copy (29 cyc/B). Caller holds SEI, Y=0, X=zp_temp2=MMU_CR (bit 0 = 0 so NMI can ack $DD0D).
mmu_common_xbank_read_page:
    stx MMU_CR
    lda (zp_ptr1),y
    ldx #MMU_ALL_RAM
    stx MMU_CR
    sta (zp_ptr0),y
    ldx zp_temp2
    iny
    bne mmu_common_xbank_read_page
    rts

// Fast 1-page Bank 0 -> Bank X copy (29 cyc/B). Caller holds SEI, Y=0, X=zp_temp2=MMU_CR.
mmu_common_xbank_write_page:
    lda (zp_ptr0),y
    stx MMU_CR
    sta (zp_ptr1),y
    ldx #MMU_ALL_RAM
    stx MMU_CR
    ldx zp_temp2
    iny
    bne mmu_common_xbank_write_page
    rts
#endif

mmu_common_save_p:
    .byte 0
mmu_common_row_end:
    .byte 0
mmu_common_row_mask:
    .byte 0
mmu_common_row_detect_new:
    .byte 0
mmu_common_row_seen_new:
    .byte 0
mmu_common_tile_tmp:
    .byte 0
mmu_common_huff_value:
    .byte 0
#if C128_CARTRIDGE
mmu_common_cart_bank:     .byte 0
mmu_common_cart_dst_mmu:  .byte 0
mmu_common_cart_dst_d506: .byte 0
mmu_common_cart_len:      .byte 0
mmu_common_cart_buf:      .fill MMU_COMMON_CART_CHUNK_MAX, 0
#endif
}
mmu_common_helpers_blob_end:
#if C128_CARTRIDGE
mmu_common_cart_blob:
.pseudopc MMU_COMMON_CART_BASE {
// Copy 1..32 bytes from External Function ROM (zp_ptr0, $8000-$BFFF) through
// bottom-common bounce buffer into Bank 0 or Bank 1 (zp_ptr1).
// Entry: X = byte count (1..32), mmu_common_cart_{bank,dst_mmu,dst_d506} set.
// Clobbers: A, X, Y. Preserves caller MMU_CR, $D506=$0D, interrupt state, ZP ptrs.
mmu_common_cart_copy_chunk:
    stx mmu_common_cart_len
    php
    sei
    lda MMU_CR
    pha
    lda #$3a                        // Bank 0 RAM, Ext Function ROM ($8000-$BFFF), I/O
    sta MMU_CR
    lda mmu_common_cart_bank
    sta $de00
    ldy #0
!rd:
    lda (zp_ptr0),y
    sta mmu_common_cart_buf,y
    iny
    dex
    bne !rd-
    lda mmu_common_cart_dst_d506
    sta $d506
    lda mmu_common_cart_dst_mmu
    sta MMU_CR
    ldx mmu_common_cart_len
    ldy #0
!wr:
    lda mmu_common_cart_buf,y
    sta (zp_ptr1),y
    iny
    dex
    bne !wr-
    lda #$3e                        // Re-enable $D000-$DFFF I/O before writing $D506
    sta MMU_CR
    lda #$0d                        // Restore 4KB bottom/top common invariant
    sta $d506
    pla
    sta MMU_CR
    plp
    rts
mmu_common_cart_copy_end:
}
mmu_common_cart_blob_end:
.assert "Cartridge common stub fits at $0FB0-$0FFF", mmu_common_cart_blob_end - mmu_common_cart_blob <= $1000 - MMU_COMMON_CART_BASE, true
#endif
// The item DB and Bank 1 $D000-$DFFF extended catalog share SEI-guarded
// $7F Bank 1 pointer thunks in bottom common RAM ($D506=$0D preserves 4KB
// bottom/top common RAM and CPU vectors).
.label mmu_common_db_read_ptr0  = mmu_common_map_read_ptr0
.label mmu_common_db_write_ptr0 = mmu_common_map_write_ptr0
.label mmu_common_db_read_ptr1  = mmu_common_map_read_ptr1
.label mmu_common_db_write_ptr1 = mmu_common_map_write_ptr1
.label mmu_common_b1_noio_read_ptr0  = mmu_common_map_read_ptr0
.label mmu_common_b1_noio_write_ptr0 = mmu_common_map_write_ptr0
.label mmu_common_b1_noio_read_ptr1  = mmu_common_map_read_ptr1
.label mmu_common_b1_noio_write_ptr1 = mmu_common_map_write_ptr1


// ============================================================
// Compile-time validation
// ============================================================
.assert "Live map size = 13068", MAP_END - MAP_BASE + 1, 13068
.assert "Reserved future map span = 13068", BANK1_MAP_RESERVED_END - MAP_BASE + 1, 13068
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Dungeon-gen scan scratch remains page-aligned", <DUNGEON_GEN_SCAN_SCRATCH_BASE, 0
.assert "Dungeon-gen scan scratch stays in VIC scratch window", DUNGEON_GEN_SCAN_SCRATCH_END <= $07ff, true
.assert "Full map row fits in dungeon-gen scan scratch", SCREEN_RAM + C128_FUTURE_MAP_COLS <= DUNGEON_GEN_SCAN_SCRATCH_END + 1, true
.assert "Door scan scratch follows the copied map row", DUNGEON_GEN_DOOR_SCAN_BASE >= SCREEN_RAM + C128_FUTURE_MAP_COLS, true
.assert "Door scan scratch stays in VIC scratch window", DUNGEON_GEN_DOOR_SCAN_END < DUNGEON_GEN_DOOR_SCAN_LIMIT, true
.assert "ZP save buffer size", ZP_SAVE_SIZE, 142
.assert "mmu_common_irq begins with CLD", mmu_common_irq_after_cld == mmu_common_irq + 1, true
.assert "mmu_common_nmi begins with CLD", mmu_common_nmi_after_cld == mmu_common_nmi + 1, true
.assert "MMU common helper copy supports current blob lower bound", mmu_common_helpers_blob_end - mmu_common_helpers_blob > $100, true
.assert "MMU common helper copy supports current blob upper bound", mmu_common_helpers_blob_end - mmu_common_helpers_blob <= $1ff, true
:AssertRegionBefore("Bank1 common region ends below staged source span", BANK1_COMMON_END, BANK1_STAGE_SOURCE_BASE)
:AssertRegionBefore("UI overlay cache ends before help overlay cache", BANK1_OVERLAY_UI_END, BANK1_OVERLAY_HELP_BASE)
:AssertRegionBefore("Help overlay cache ends before items overlay cache", BANK1_OVERLAY_HELP_END, BANK1_OVERLAY_ITEMS_BASE)
:AssertRegionBefore("Items overlay cache ends before map region", BANK1_OVERLAY_ITEMS_END, MAP_BASE)
:AssertRegionBefore("Reserved future map span ends before Bank1 DB region", BANK1_MAP_RESERVED_END, BANK1_DB_BASE)
:AssertRegionBefore("Bank1 DB ends before tier cache window", BANK1_DB_END, BANK1_TIER_CACHE_BASE)
.assert "Bank1 recall starts at Bank1 DB base", BANK1_RECALL_BASE, BANK1_DB_BASE
.assert "Bank1 recall fits inside Bank1 DB region", BANK1_RECALL_END <= BANK1_DB_END, true
.assert "Bank1 ZP save follows Bank1 recall", BANK1_ZP_SAVE_BASE, BANK1_RECALL_END + 1
.assert "Bank1 ZP save size matches ZP_SAVE_SIZE", BANK1_ZP_SAVE_END - BANK1_ZP_SAVE_BASE + 1, ZP_SAVE_SIZE
.assert "Bank1 ZP save fits inside Bank1 DB region", BANK1_ZP_SAVE_END <= BANK1_DB_END, true
:AssertRegionBefore("Bank1 recall ends before tier cache window", BANK1_RECALL_END, BANK1_TIER_CACHE_BASE)
:AssertRegionBefore("Tier cache ends before reserved gap 0", BANK1_TIER_CACHE_END, BANK1_RESERVED_GAP0_BASE)
:AssertRegionBefore("Reserved gap 0 ends before STARTUP overlay slot", BANK1_RESERVED_GAP0_END, BANK1_OVERLAY_STARTUP_BASE)
.assert "Title cache marker starts inside reserved gap 0", BANK1_TITLE_CACHE_MARKER_BASE >= BANK1_RESERVED_GAP0_BASE && BANK1_TITLE_CACHE_MARKER_BASE <= BANK1_RESERVED_GAP0_END, true
.assert "Title cache data ends inside reserved gap 0", BANK1_TITLE_CACHE_DATA_BASE <= BANK1_TITLE_CACHE_END && BANK1_TITLE_CACHE_END <= BANK1_RESERVED_GAP0_END, true
.assert "Title cache exceeds current title-art minimum", BANK1_TITLE_CACHE_MAX_LEN >= C128_TITLE_CACHE_MIN_REQUIRED, true
:AssertRegionBefore("Title cache ends before MODAL small-overlay cache", BANK1_TITLE_CACHE_END, BANK1_OVERLAY_MODAL_BASE)
:AssertRegionBefore("MODAL small-overlay cache ends before DISARM small-overlay cache", BANK1_OVERLAY_MODAL_END, BANK1_OVERLAY_DISARM_BASE)
:AssertRegionBefore("Title cache ends before DISARM small-overlay cache", BANK1_TITLE_CACHE_END, BANK1_OVERLAY_DISARM_BASE)
:AssertRegionBefore("DISARM small-overlay cache ends before STARTUP overlay slot", BANK1_OVERLAY_DISARM_END, BANK1_OVERLAY_STARTUP_BASE)
:AssertRegionBefore("STARTUP overlay slot ends before TOWN overlay slot", BANK1_OVERLAY_STARTUP_END, BANK1_OVERLAY_TOWN_BASE)
:AssertRegionBefore("TOWN overlay slot ends before DEATH overlay slot", BANK1_OVERLAY_TOWN_END, BANK1_OVERLAY_DEATH_BASE)
:AssertRegionBefore("DEATH overlay slot ends before reserved I/O window", BANK1_OVERLAY_DEATH_END, BANK1_RESERVED_IO_BASE)
:AssertRegionBefore("Reserved I/O window ends before DUNGEON overlay slot", BANK1_RESERVED_IO_END, BANK1_OVERLAY_DUNGEON_BASE)
:AssertRegionBefore("DUNGEON overlay slot ends before Huffman corpus region", BANK1_OVERLAY_DUNGEON_END, BANK1_HUFFMAN_BASE)
.assert "Bank 1 Huffman corpus ends before its NMI vector bridge", BANK1_HUFFMAN_END < BANK1_HUFFMAN_NMI_VECTOR_BASE, true
.assert "Bank 1 Huffman NMI bridge ends at $FFFB", BANK1_HUFFMAN_NMI_VECTOR_END == $fffb, true
.assert "DISARM small-overlay cache stays inside Bank1 cache span", BANK1_OVERLAY_DISARM_END <= BANK1_CACHE_OWNED_END, true
.assert "DISARM small-overlay cache does not use top common RAM", BANK1_OVERLAY_DISARM_END < BANK1_RESERVED_TOP_BASE, true
.assert "Tier cache window matches required preload footprint", BANK1_TIER_CACHE_SIZE, TIER_PRELOAD_REQUIRED
.assert "Cache-owned Bank1 span stays below top common RAM", BANK1_CACHE_OWNED_END < BANK1_RESERVED_TOP_BASE, true
.assert "Tier cache stays below overlay cache", BANK1_TIER_CACHE_END < BANK1_OVERLAY_STARTUP_BASE, true
#if HAL_PLATFORM_MONSTER_CATALOG
:AssertRegionBefore("Bank1 DB ends before the catalog name pool", BANK1_DB_END, BANK1_CATALOG_POOL_BASE)
:AssertRegionBefore("Catalog name pool ends before the catalog fields", BANK1_CATALOG_POOL_END, BANK1_CATALOG_FIELDS_BASE)
:AssertRegionBefore("Catalog fields end before reserved gap 0", BANK1_CATALOG_FIELDS_END, BANK1_RESERVED_GAP0_BASE)
:AssertRegionBefore("DISARM small-overlay cache ends before the catalog names", BANK1_OVERLAY_DISARM_END, BANK1_CATALOG_NAMES_BASE)
:AssertRegionBefore("Catalog names end before TOWN overlay slot", BANK1_CATALOG_NAMES_END, BANK1_OVERLAY_TOWN_BASE)
.assert "Catalog field segment starts at its Bank1 span", BANK1_CATALOG_FIELDS_BASE, $7e60
.assert "Catalog names segment starts at its Bank1 span", BANK1_CATALOG_NAMES_BASE, $a000
#endif
.assert "Overlay cache avoids $D000-$DFFF", BANK1_OVERLAY_DEATH_END < BANK1_RESERVED_IO_BASE, true
.assert "DUNGEON overlay slot starts after $DFFF", BANK1_OVERLAY_DUNGEON_BASE > BANK1_RESERVED_IO_END, true
.assert "Overlay cache fits in named owned Bank1 span", OVERLAY_CACHE_DISARM_END <= BANK1_CACHE_OWNED_END, true
:AssertRegionBefore("DEATH overlay cache ends before Bank1 extended catalog", BANK1_OVERLAY_DEATH_END, BANK1_CATALOG_EXT_BASE)
.assert "Bank1 extended catalog starts page-aligned at $D000", BANK1_CATALOG_EXT_BASE, $d000
.assert "Bank1 extended catalog ends at $D8B7", BANK1_CATALOG_EXT_END == BANK1_CATALOG_EXT_BASE + BANK1_CATALOG_EXT_SIZE - 1 && BANK1_CATALOG_EXT_END == $d8b7, true
:AssertRegionBefore("Bank1 extended catalog ends before store-inv reserve", BANK1_CATALOG_EXT_END, BANK1_STORE_INV_RESERVED_BASE)
.assert "Bank1 store-inv reserve ends at $DCB7 inside $D000-$DFFF", BANK1_STORE_INV_RESERVED_BASE == BANK1_CATALOG_EXT_END + 1 && BANK1_STORE_INV_RESERVED_END == BANK1_STORE_INV_RESERVED_BASE + BANK1_STORE_INV_RESERVED_SIZE - 1 && BANK1_STORE_INV_RESERVED_END == $dcb7 && BANK1_STORE_INV_RESERVED_END <= BANK1_HIGH_DATA_END, true
:AssertRegionBefore("Bank1 store-inv reserve ends before Bank1 msg_history", BANK1_STORE_INV_RESERVED_END, BANK1_MSG_HISTORY_BASE)
.assert "Bank1 msg_history ends at $DF37 inside $D000-$DFFF", BANK1_MSG_HISTORY_BASE == BANK1_STORE_INV_RESERVED_END + 1 && BANK1_MSG_HISTORY_END == BANK1_MSG_HISTORY_BASE + BANK1_MSG_HISTORY_SIZE - 1 && BANK1_MSG_HISTORY_END == $df37 && BANK1_MSG_HISTORY_END <= BANK1_HIGH_DATA_END, true
:AssertRegionBefore("Bank1 high data window ends before DUNGEON overlay cache", BANK1_HIGH_DATA_END, BANK1_OVERLAY_DUNGEON_BASE)
:AssertRegionBefore("VDC scroll-delta scratch ends before VDC ITEM.CAT low span", VDC_SCRATCH_END, VDC_ITEM_CAT_LO_BASE)
:AssertRegionBefore("VDC ITEM.CAT low span ends before VDC charset base", VDC_ITEM_CAT_LO_END, VDC_CHARSET_BASE)
.assert "VDC ITEM.CAT cell tail stays in unused scanlines 8..15", VDC_ITEM_CAT_CELL_OFFSET == 8 && VDC_ITEM_CAT_CELL_OFFSET + VDC_ITEM_CAT_CELL_BYTES == VDC_ITEM_CAT_CELL_STRIDE, true
.assert "VDC charset ends at top of 16 KB VDC RAM", VDC_CHARSET_END == VDC_RAM_SIZE - 1, true

.assert "Overlay cache slot lo table covers all overlays", bank1_overlay_cache_slot_hi - bank1_overlay_cache_slot_lo, hal_platform_overlay_count + 1
.assert "Overlay cache slot hi table covers all overlays", bank1_overlay_cache_pages - bank1_overlay_cache_slot_hi, hal_platform_overlay_count + 1
.assert "Overlay cache pages table covers all overlays", bank_overlay_cache_mmu - bank1_overlay_cache_pages, hal_platform_overlay_count + 1
.assert "Overlay cache MMU table covers all overlays", bank_overlay_cache_mmu_end - bank_overlay_cache_mmu, hal_platform_overlay_count + 1
:AssertRegionBefore("Bank2 STARTUP cache clears bottom common RAM", BANK1_COMMON_END, BANK2_OVERLAY_STARTUP_BASE)
:AssertRegionBefore("Bank2 STARTUP cache ends before CHEST cache", BANK2_OVERLAY_STARTUP_END, BANK2_OVERLAY_CHEST_BASE)
:AssertRegionBefore("Bank2 CHEST cache ends before HOME cache", BANK2_OVERLAY_CHEST_END, BANK2_OVERLAY_HOME_BASE)
:AssertRegionBefore("Bank2 HOME cache ends before STORAGE cache", BANK2_OVERLAY_HOME_END, BANK2_OVERLAY_STORAGE_BASE)
:AssertRegionBefore("Bank2 STORAGE cache ends before LEGALUI cache", BANK2_OVERLAY_STORAGE_END, BANK2_LEGALUI_BASE)
:AssertRegionBefore("Bank2 LEGALUI cache ends before PLAY cache", BANK2_LEGALUI_END, BANK2_PLAY_BASE)
:AssertRegionBefore("Bank2 PLAY cache ends before PERSIST cache", BANK2_PLAY_END, BANK2_PERSIST_BASE)
:AssertRegionBefore("Bank2 PERSIST cache ends before MODAL cache", BANK2_PERSIST_END, BANK2_OVERLAY_MODAL_BASE)
:AssertRegionBefore("Bank2 MODAL cache ends below I/O window", BANK2_OVERLAY_MODAL_END, BANK1_RESERVED_IO_BASE)
.assert "Bank2 PLAY cache covers full $AF00-$CFFF window", BANK2_PLAY_PAGES * $100, $D000 - $AF00
