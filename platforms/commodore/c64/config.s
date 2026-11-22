// config.s — System detection (C64 vs C128, column mode)
//
// Detection method: Probe for the C128 VDC (8563) at $D600. The VDC
// status register bit 7 (ready flag) is high most of the time. On a C64
// or C128 in GO64 mode, $D600 is a SID mirror (write-only Voice 1 Freq
// Lo) and reads ~0. This correctly identifies C128 NATIVE mode only —
// C128 in GO64 (C64 mode) is treated as C64, which matches user intent.
//
// Previous $FF80 method was broken: C64 KERNAL rev 3 also has $FF80=$03,
// causing false C128 detection on the most common C64 KERNAL.
//
// C128 column mode: If C128 detected, check $D7 (40/80 column flag).

// KERNAL revision byte (used for revision display + SX-64 detection)
.const KERNAL_REV = $ff80

// C128 40/80 column flag (only valid on C128 native mode)
.const C128_MODE_FLAG = $d7

#import "hal/entropy_consts.s"
#import "hal/lifecycle_policy.s"
#import "hal/storage_title_name.s"

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 42
#if C64_PRODUCT_OVERLAY_RUNTIME
// The product parks pure scratch buffers in page-2 RAM to free main-segment
// bytes below MAP_BASE: $02A7-$02FF, which neither KERNAL nor BASIC uses, and
// BASIC's line-input buffer $0200-$0258 (BASIC is gone after startup; the
// game never reads keyboard lines through CHRIN, and disk CHRIN does not use
// the buffer).
#define PLATFORM_SCRATCH_BUFS_IN_PAGE2
#endif
.const PLATFORM_COMBAT_MSG_BUF_BASE = $02a7
.const PLATFORM_CREATURE_NAME_BUF_BASE = PLATFORM_COMBAT_MSG_BUF_BASE + PLATFORM_COMBAT_MSG_BUF_SIZE
.const PLATFORM_PM_SPELL_LIST_BASE = PLATFORM_CREATURE_NAME_BUF_BASE + 32
.const PLATFORM_LTB_SCRATCH_BASE = PLATFORM_PM_SPELL_LIST_BASE + 9   // monster.s tier-loader counters
.assert "Page-2 scratch buffers stay in $02A7-$02FF", PLATFORM_LTB_SCRATCH_BASE + 2 <= $0300, true
.const PLATFORM_ITEM_NAME_DECODE_BUF_BASE = $0200
.label PLATFORM_LEGAL_NAME_STAGE_BASE = PLATFORM_ITEM_NAME_DECODE_BUF_BASE    // LegalOverlay saves/restores 16 B around KERNAL OPEN/CLOSE
.const PLATFORM_PIW_VISIBLE_SLOTS_BASE = PLATFORM_ITEM_NAME_DECODE_BUF_BASE + 48
.const PLATFORM_MD_QUEUE_BASE = PLATFORM_PIW_VISIBLE_SLOTS_BASE + 22   // monster_death.s queue
.const PLATFORM_CHEST_SCRATCH_BASE = PLATFORM_MD_QUEUE_BASE + 1 + 3 * 4  // chest_loot.s scratch
.assert "BASIC-buffer scratch stays in $0200-$0258", PLATFORM_CHEST_SCRATCH_BASE + 5 <= $0259, true
#define PLATFORM_GET_INFRA_RANGE_INLINE
#define PLATFORM_COPY_DEATH_SOURCE
#if C64_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_REQUIRES_MEDIA_PROBE
#endif
.const PLATFORM_RESIDENT_PLAY = "Default"
// The cassette buffer ($033C-$03FB): from $033C the Huffman decode buffer
// and, during generation, the door scan; at the top of the buffer ($03CB-$03FB),
// the monster catalog record buffer (49 bytes). Identification shuffles (174 B)
// stay in Default (< $C000). main.s asserts the door scan ends before the
// catalog record buffer; huffman.s asserts the decode buffer ends at its limit.
#define PLATFORM_CAT_RECORD_EXTERNAL
.const PLATFORM_CAT_RECORD_BASE = $03fc - 49
.assert "Page-3 buffers end in the cassette buffer", PLATFORM_CAT_RECORD_BASE + 49 <= $03fc, true
.const PLATFORM_HD_DECODE_BUF_BASE = $033c
.const PLATFORM_HD_DECODE_BUF_LIMIT = PLATFORM_CAT_RECORD_BASE

// Machine type constants (stored in zp_machine_type)
.const MACHINE_C64  = $00
.const MACHINE_C128 = $80

// Column mode constants (stored in zp_column_mode)
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

// Machine detection runs once at boot in restart_entry; the C64 product
// places it in the init-only tail past program_end (DETECT_MACHINE_EXTERNAL).
#if !DETECT_MACHINE_EXTERNAL
#import "detect_machine.s"
#endif

// kernal_load — Platform LOAD wrapper (C64: direct KERNAL call)
kernal_load:
    jmp $ffd5

.label hal_asset_load = kernal_load

.macro AssetLoad() {
    jsr hal_asset_load
}

#if C64_CARTRIDGE
#import "cartridge_copy.s"
.label hal_asset_load_prg_header = cart_load_prg
.label hal_asset_load_title = cart_load_title
#else
hal_asset_load_prg_header:
    php
    jsr $ffbd               // SETNAM
    lda #2
#if C64_UNIT_TEST
    ldx #8
#else
    ldx program_device
#endif
    ldy #1                  // Use PRG header address
    jsr $ffba               // SETLFS
    lda #0
    ldx #$00
    ldy #$e0
    jsr hal_asset_load
    php
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    lda $dd00
    ora #%00000011          // Restore VIC-II bank 0 after serial I/O
    sta $dd00
    plp
    php
    pla
    sta asset_load_save_p
    plp
    lda asset_load_save_p
    pha
    plp
    rts

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
hal_asset_load_title:
    php
    lda $01
    pha
    lda #BANK_NO_BASIC
    sta $01
    cli
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr $ffbd               // SETNAM
    lda #2
#if C64_UNIT_TEST
    ldx #8
#else
    ldx program_device
#endif
    ldy #0                  // Use caller destination at MAP_BASE
    jsr $ffba               // SETLFS
    lda #0
    ldx #<MAP_BASE
    ldy #>MAP_BASE
    jsr kernal_load_safe
    php
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    lda $dd00
    ora #%00000011          // Restore VIC-II bank 0 after serial I/O
    sta $dd00
    sei
    jsr c64_install_ram_irq_vectors
    pla
    lsr                     // Carry = kernal_load_safe error bit
    pla
    sta $01                 // Restore caller $01 ($35 if called from TitleOverlay)
    pla
    and #%11111110          // Restore caller P/I flags while keeping load Carry
    bcc !halt_ok+
    ora #%00000001
!halt_ok:
    pha
    plp
    rts
#else
hal_asset_load_title:
    sec
    rts
#endif

#endif
hal_asset_close_channel:
    lda #2
    jsr $ffc3               // CLOSE
    jsr $ffcc               // CLRCHN
    rts

asset_load_save_p: .byte 0

.const DEATH_ALIVE   = $00    // Player is alive
.const DEATH_CHEST_NEEDLE = $F7
.const DEATH_CHEST_EXPLOSION = $F8
.const DEATH_TRAP_PIT      = $F9    // Killed by an open pit
.const DEATH_TRAP_ARROW    = $FA    // Killed by an arrow trap
.const DEATH_TRAP_DART     = $FB    // Killed by a poison dart
.const DEATH_TRAP_ROCKFALL = $FC    // Killed by falling rock
.const DEATH_CURSED  = $FD    // Killed by cursed item
.const DEATH_POISON  = $FE    // Killed by poison
.const DEATH_STARVE  = $FF    // Killed by starvation

// ============================================================
// C64 map-safe pointer wrappers
// ============================================================
// Product builds keep msg_history in hidden DRAM ($D78E-$D8CD) and route
// $D700-$DEFF through SEI + $01=$34 while leaving < $D700 (MAP_BASE) and
// >= $DF00 (REU/cartridge I/O window) on the direct path. Unit tests
// (C64_UNIT_TEST without C64_TEST_HIDDEN_MAP) keep msg_history and
// test_config.s self-contained in regular RAM.
#if !C64_UNIT_TEST || C64_TEST_HIDDEN_MAP
#define MSG_HISTORY_IN_AUX
.segmentdef C64MsgHistory [start=C64_HIDDEN_MSG_HIST_BASE, max=C64_HIDDEN_FREE_BASE - 1, virtual]
.macro MsgHistorySegment() {
    .segment C64MsgHistory
}
.macro MsgHistoryRestoreSegment() {
    .segment Default
}

mmu_safe_map_read_ptr0:
    lda zp_ptr0_hi
    cmp #>C64_HIDDEN_AUX_BASE
    bcc !direct+
    cmp #>C64_HIDDEN_AUX_END + 1
    bcs !direct+
    jmp c64_hidden_read_ptr0
!direct:
    lda (zp_ptr0),y
    rts

mmu_safe_map_write_ptr0:
    pha
    lda zp_ptr0_hi
    cmp #>C64_HIDDEN_AUX_BASE
    bcc !direct+
    cmp #>C64_HIDDEN_AUX_END + 1
    bcs !direct+
    pla
    jmp c64_hidden_write_ptr0
!direct:
    pla
    sta (zp_ptr0),y
    rts

mmu_safe_map_read_ptr1:
    lda zp_ptr1_hi
    cmp #>C64_HIDDEN_AUX_BASE
    bcc !direct+
    cmp #>C64_HIDDEN_AUX_END + 1
    bcs !direct+
    jmp c64_hidden_read_ptr1
!direct:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
    pha
    lda zp_ptr1_hi
    cmp #>C64_HIDDEN_AUX_BASE
    bcc !direct+
    cmp #>C64_HIDDEN_AUX_END + 1
    bcs !direct+
    pla
    jmp c64_hidden_write_ptr1
!direct:
    pla
    sta (zp_ptr1),y
    rts
#else
mmu_safe_map_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_map_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_map_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr1:
    sta (zp_ptr1),y
    rts
#endif

// ============================================================
// C64 DB-safe pointer wrappers (no MMU; direct access)
// ============================================================
mmu_safe_db_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_db_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

db_bulk_enter:
    rts

db_bulk_exit:
    rts
