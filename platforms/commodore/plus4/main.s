#define HAL_PLATFORM_LEGAL_VIEWER
// main.s — Entry point for Moria8 Plus/4
//
// BASIC stub at $1001 with SYS entry.
// Saves BASIC ZP state, disables BASIC ROM, runs game,
// restores state and exits cleanly to BASIC.

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
// Overlay segments: produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
// The monster catalog (docs/MONSTER_CATALOG_DESIGN.md) replaces the tiers in
// the product build, its records read from the drive. The unit tests
// (tests/*.s) do not import main.s and keep the tier roster.
#define HAL_PLATFORM_MONSTER_CATALOG
#define HAL_PLATFORM_CATALOG_RECORDS
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#define HAL_PLATFORM_EFF_ITEM_P1_EXTERNAL
#define HAL_PLATFORM_EFF_ITEM_EXTENDED_EXTERNAL
#define PLUS4_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define STORAGE_STATUS_HELPER
#define HELP_TITLE_EXTERNAL
#define HOME_OVERLAY_SEPARATE
#define SAVE_IN_STORAGE_OVERLAY
// Wave 5.2 cold evictions: keep Default (< $C800) and 4.bank (< $FC00) roomy
// for Phase 5 full monster parity while leaving Plus4HighBss ($DF00) untouched.
#define PLAYER_PFLAGS_EXTERNAL
#define UI_CHAR_BG_EXTERNAL
#define TRAP_TRIGGER_EXTERNAL
#define CALC_DIG_EXTERNAL
#define CALC_DIG_CO_LOCATED
#define ITEM_SPAWN_EXTERNAL
#define ITEM_DROP_EXTERNAL
#define HELP_CMD_BODY_EXTERNAL
#define STARTING_KIT_EXTERNAL
#define LOAD_RESUME_RESET_EXTERNAL
#define PLAYER_MAGIC_BROWSE_EXTERNAL
#define PLAYER_CAST_RESIDENT
#define EFF_IDENTIFY_PROMPT_EXTERNAL
#define EFF_DETECT_EVIL_EXTERNAL
#define RECALL_VIEW_OVERLAYED
#define STORE_CHECK_CAT_DUPLICATED
#define ITEMDESC_STORE_SLOT_DUPLICATED
#if !PLUS4_CARTRIDGE
#define HAL_PLATFORM_ITEM_PICKUP_CACHE
.macro ItemPickupCacheMap() {}
.macro ItemPickupCacheUnmap() {}
#define ITEM_PICKUP_CACHE_PREWARM_SEGMENT_CUSTOM
.macro ItemPickupCachePrewarmSegment() {
    .segment RuntimeBanked
}
.macro ItemPickupCachePrewarmRestoreSegment() {
    .segment Default
}
#endif
.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")
.segmentdef StartupOverlay    [outPrg=OVL_OUT + "/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg=OVL_OUT + "/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg=OVL_OUT + "/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef ModalMiscOverlay      [outPrg=OVL_OUT + "/ovl.modal", start=$e000, min=$e000, max=$efff]
.const LEGAL_BASE = $e000
.const LEGAL_LIMIT = $f000
.segmentdef LegalOverlay [outPrg=OVL_OUT + "/legalui", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items", start=$e000, min=$e000, max=$efff]
.segmentdef SpellOverlay      [outPrg=OVL_OUT + "/ovl.spell", start=$e000, min=$e000, max=$efff]
.segmentdef ChestOverlay      [outPrg=OVL_OUT + "/ovl.chest", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",   start=$e000, min=$e000, max=$efff]
.segmentdef HomeOverlay       [outPrg=OVL_OUT + "/ovl.home",    start=$e000, min=$e000, max=$efff]
.segmentdef StorageOverlay    [outPrg=OVL_OUT + "/ovl.storage", start=$e000, min=$e000, max=$efff]
.segmentdef TitleOverlay      [outPrg=OVL_OUT + "/ovl.title",   start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeBanked     [outPrg=OVL_OUT + "/4.bank",    start=$f000, min=$f000, max=$fbff]
// Assembled for free RAM above the catalog index, stored in the init-only tail.
.segmentdef Plus4HuffIndex    [start=$dd00, max=$deff]   // memory.s HUFF_INDEX_HIDDEN_BASE/END
// Virtual high BSS in $DF00-$DFFF (zeroed at boot in entry_main; never emitted to PRG).
.segmentdef Plus4HighBss      [start=$df00, max=$dfff, virtual] // memory.s PLUS4_HIGH_BSS_BASE/END

#import "../common/save_slot_policy.s"

// Huffman data placement: resident on this platform.
.macro HuffmanDataSegment() {
    .segment Default
}
// The Huffman string index lives in free RAM at HUFF_INDEX_HIDDEN_BASE
// (memory.s; 2026-11-08, for the dragon breath's room), copied there at boot.
#define HUFFMAN_INDEX_EXTERNAL
.macro HuffmanIndexSegment() {
    .segment Plus4HuffIndex
}

// Cast/pray selection shell and shared pm_* helpers stay resident so repeat
// casts hit cached OVL_SPELL (0 disk loads) and multi-book '?' browsing hits
// cached OVL_UI (1 load total).
.macro PlayerCastSegment() {
    .segment Default
}
.macro PlayerCastRestoreResidentSegment() {
    .segment Default
}
.macro PmHelpersSegment() {
    .segment Default
}
.macro PmHelpersRestoreSegment() {
    .segment Default
}
.macro ItemInitIdentSegment() {
    // One-shot new-game identification init parks in the death overlay
    // (roomy on this port), funding the resident door-state machinery.
    .segment DeathOverlay
}
.macro WizardGenExecSegment() {
    .segment ModalMiscOverlay
}
.macro WizardGenExecRestoreSegment() {
    .segment Default
}
.macro ItemInitIdentRestoreSegment() {
    .segment Default
}
.macro RecallViewBodySegment() {
    .segment DeathOverlay
}
.macro RecallViewBodyRestoreSegment() {
    .segment Default
}
.macro ChestRouteSegment() {
    .segment Default
}
.macro ChestRouteRestoreSegment() {
    .segment Default
}
.macro ResidentItemsSegment() {
    .segment Default
}
.macro ResidentItemNamesSegment() {
    .segment Default
}
.macro ResidentWorldSegment() {
    .segment Default
}
.macro ResidentPlaySegment() {
    .segment Default
}

.const TED_BG      = $ff15
.const TED_BORDER  = $ff19
.const TED_SOUND_CTRL = $ff11
.const PLUS4_EXIT_ROM_ENABLE = $ff3e
.const PLUS4_EXIT_TED_IRQ_STATUS = $ff09
.const PLUS4_KERNAL_RESTOR = $ff8a
.const PLUS4_KERNAL_RESET = $f2a4
.const BASIC_TXTTAB_LO = $2b
.const BASIC_TXTTAB_HI = $2c
.const BASIC_VARTAB_LO = $2d
.const BASIC_VARTAB_HI = $2e
.const BASIC_ARYTAB_LO = $2f
.const BASIC_ARYTAB_HI = $30
.const BASIC_STREND_LO = $31
.const BASIC_STREND_HI = $32
.const PLUS4_BASIC_START_LO = $01
.const PLUS4_BASIC_START_HI = $10
.const PLUS4_KEYSCAN_STATE = $ef
.const PLUS4_KEY_INDEX = $055d
.const PLUS4_KEY_INDEX_SHADOW = $055e
.const PLUS4_ROM_RESET_REBUILD_FLAG = $0508
.const PLUS4_ROM_RESET_REBUILD_FLAG_2 = $0509

#if PLUS4_CARTRIDGE
#import "cartridge_contract.s"
#endif

.pc = $1001 "BASIC Stub"
.word basic_stub_end
.word 10
.byte $9e
.text "4110"
.byte 0
basic_stub_end:
.word 0

// ============================================================
// Imports — order matters: labels must be defined before use
// ============================================================
.pc = $100e "Program"

// Bootstrap — MUST live below $A000 so BASIC's SYS can reach it
// before BASIC ROM is banked out.
.const KERNAL_SETMSG = $ff90
entry:
#if PLUS4_CARTRIDGE
.assert "Cartridge boot entry ABI", entry, CART_ENTRY
#endif
    sei
    // KERNAL messages off while the ROM is still visible: with them on, every
    // LOAD printed "searching for <file>" over the game screen (2026-11-05,
    // seen on the C64; the C128 boot does the same, boot128.s).
    lda #0
    jsr KERNAL_SETMSG
    jsr plus4_bank_ram
    jmp entry_main

#if !PLUS4_CARTRIDGE
plus4_banked_fname:
    .byte $34,$2e,$42,$41,$4e,$4b  // "4.BANK"
.label plus4_banked_fname_len = * - plus4_banked_fname
#endif

// Exit trampoline — MUST live below $A000 because it banks Plus/4
// ROM back in. If this ran from $A000+ the CPU would start executing
// BASIC ROM as soon as $FF3E makes ROM visible.
exit_trampoline:
#if PLUS4_CARTRIDGE
.assert "Cartridge exit trampoline stays below C1LO ROM", exit_trampoline < $8000, true
    sei
    lda #0
    sta CART_REG_BANK
    sta CART_REG_C1LO_KERNAL
    sta PLUS4_EXIT_ROM_ENABLE
    jmp $fff6               // Hardware reset re-enters cartridge via KERNAL ROM check
#else
    sei
    lda #$ff
    sta PLUS4_EXIT_ROM_ENABLE
    lda #0
    sta PLUS4_EXIT_TED_IRQ_STATUS
    jsr PLUS4_KERNAL_RESTOR
    ldx #$ff
    txs
    lda #PLUS4_BASIC_START_LO
    sta BASIC_TXTTAB_LO
    lda #PLUS4_BASIC_START_HI
    sta BASIC_TXTTAB_HI
    lda #0
    sta BASIC_VARTAB_LO
    sta BASIC_VARTAB_HI
    sta BASIC_ARYTAB_LO
    sta BASIC_ARYTAB_HI
    sta BASIC_STREND_LO
    sta BASIC_STREND_HI
    sta PLUS4_KEYSCAN_STATE
    sta PLUS4_KEY_INDEX
    sta PLUS4_KEY_INDEX_SHADOW
    sta PLUS4_ROM_RESET_REBUILD_FLAG
    sta PLUS4_ROM_RESET_REBUILD_FLAG_2
    jmp PLUS4_KERNAL_RESET
#endif

#import "../../../core/zeropage.s"
#import "legal.s"

plus4_kernal_call_saved_x: .byte 0

plus4_kernal_call:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda $0104,x
    sta zp_vol_2
    clc
    adc #2
    sta $0104,x
    lda $0105,x                 // keeps the carry from the adc
    sta zp_vol_3
    bcc !cdc_target+
    inc $0105,x
!cdc_target:
    ldy #1
    lda (zp_vol_2),y
    sta !cdc_jsr+ + 1
    iny
    lda (zp_vol_2),y
    sta !cdc_jsr+ + 2
    pla
    tay
    pla
    tax
    pla
    jsr plus4_bank_rom
    cli
    // Carry is still the return-address sum's: CLOSE with it set leaves a
    // disk command channel (SA 15) open in the drive, so the next read of
    // channel 15 goes on mid-message, as it did on the C128. No other call
    // here reads carry.
    clc
!cdc_jsr:
    jsr $ffff
    php
    pha
    stx plus4_kernal_call_saved_x
    tsx
    lda $0102,x
    ora #$04                    // Return to all-RAM game code with IRQs disabled.
    sta $0102,x
    sei
    jsr plus4_bank_ram
    jsr plus4_display_resync
    ldx plus4_kernal_call_saved_x
    pla
    plp
    rts

plus4_kernal_setnam:
    jsr plus4_kernal_call
    .word $ffbd
    rts

plus4_kernal_setlfs:
    jsr plus4_kernal_call
    .word $ffba
    rts

plus4_kernal_open:
    jsr plus4_kernal_call
    .word $ffc0
    rts

plus4_kernal_close:
    jsr plus4_kernal_call
    .word $ffc3
    rts

plus4_kernal_chkout:
    jsr plus4_kernal_call
    .word $ffc9
    rts

plus4_kernal_chkin:
    jsr plus4_kernal_call
    .word $ffc6
    rts

plus4_kernal_clrchn:
    jsr plus4_kernal_call
    .word $ffcc
    rts

plus4_kernal_chrin:
    jsr plus4_kernal_call
    .word $ffcf
    rts

plus4_kernal_chrout:
    jsr plus4_kernal_call
    .word $ffd2
    rts

plus4_kernal_readst:
    jsr plus4_kernal_call
    .word $ffb7
    rts

plus4_kernal_load:
    jsr plus4_kernal_call
    .word $ffd5
    rts
plus4_kernal_wrappers_end:
.assert "Plus/4 KERNAL wrappers stay below $8000", plus4_kernal_wrappers_end <= $8000, true

#import "hal/storage.s"
.assert "Plus/4 storage filenames and overlay table stay below $8000", hal_storage_overlay_table_end <= $8000, true

plus4_storage_marker_present:
    lda #$81                    // DISK_ERR_MARKER_OPEN
    jsr disk_error_set_phase
    // A CHKIN on a marker the drive refused (a fresh save disk) can wait
    // forever in the KERNAL's talker turnaround: ask the drive first. Its
    // answer (62) stands; reading the channel again goes on mid-message.
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr storage_file_exists
    bcs !cdmp_there+
    jmp !cdmp_status_done+      // disk_status: the drive's answer, or 2
!cdmp_there:

    lda #1                      // (the probe closed its file and channels)
    sta disk_status
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr plus4_kernal_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    sta disk_error_readst       // the error code, if it failed
    bcs !cdmp_close+
    jsr plus4_kernal_readst
    sta disk_error_readst
    bne !cdmp_close+
    lda #$82                    // DISK_ERR_MARKER_CHKIN
    jsr disk_error_set_phase
    ldx #hal_storage_marker_file_num
    jsr plus4_kernal_chkin
    sta disk_error_readst       // the error code, if it failed
    bcs !cdmp_close+
    lda #$83                    // DISK_ERR_MARKER_READ
    jsr disk_error_set_phase
    lda #0
    sta disk_temp
!cdmp_read:
    jsr plus4_kernal_chrin
    sta disk_error_actual
    ldx disk_temp
    lda hal_storage_marker_magic,x
    sta disk_error_expect
    stx disk_error_index
    cmp disk_error_actual
    bne !cdmp_close+
    jsr plus4_kernal_readst
    sta disk_error_readst
    beq !cdmp_byte_ok+
    cmp #$40
    bne !cdmp_close+
    ldx disk_temp
    cpx #hal_storage_marker_magic_len - 1
    bne !cdmp_close+
!cdmp_byte_ok:
    inc disk_temp
    lda disk_temp
    cmp #hal_storage_marker_magic_len
    bcc !cdmp_read-
    dec disk_status
!cdmp_close:
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
!cdmp_done:
    lda disk_status
    beq !cdmp_status_done+
    lda save_device             // the drive the marker was read from
    sta disk_prompt_device
    jsr plus4_disk_read_command_status
    lda disk_status
    bne !cdmp_status_done+
    inc disk_status             // drive OK, but the marker was missing or wrong
!cdmp_status_done:
    lda disk_status
    beq !cdmp_ok+
    sec
    rts
!cdmp_ok:
    jsr disk_error_clear
    clc
    rts


// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_mixed"

.const DUNGEON_GEN_BUSY = 1

#import "../../../core/zeropage.s"
#import "memory.s"
#import "hal/layout.s"
#import "hal/lifecycle_policy.s"
#import "reu_stub.s"
#import "screen.s"
#import "../../../core/color.s"
#import "config.s"
#import "input.s"
#import "../../../core/rng.s"
#import "../../../core/math.s"
#import "../../../core/tables.s"
#import "../../../core/item_defs.s"
// Equipment effect flags park in ModalMiscOverlay ($E000) behind
// hal_player_recalc_pflags, which saves and restores current_overlay.
#import "../../../core/player.s"
#import "../../../core/ui_messages.s"
#import "../../../core/ui_status.s"
#define GENERATION_BUSY_INSTALL_EXTERNAL
#import "../../../core/generation_busy.s"
#undef GENERATION_BUSY_INSTALL_EXTERNAL
#import "../../../core/stat_display.s"
#import "sound.s"
#import "../../../core/huffman.s"
#import "../../../core/dungeon_data.s"
// The jam command handler parks in the chest overlay (resident budget).
#define CMD_JAM_EXTERNAL
#define CMD_JAM_SEGMENT_CUSTOM
.macro CmdJamSegment() {
    .segment ItemActionsOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
.macro ChestSearchSegment() {
    .segment Default
}
.macro ChestSearchRestoreSegment() {
    .segment Default
}
#define CHEST_ROUTING_ENABLED
// place_secrets parks in the GEN overlay (only generation calls it), funding
// the monster door engine in the resident image.
#define PLACE_SECRETS_EXTERNAL
// Chest loot generator + the shared item picker park in the CHEST overlay
// on this platform (GEN is full); gameplay drops reach the picker through the
// resident pick_item_type wrapper, fulfillment loads OVL_CHEST.
#define PICKER_IN_CHEST_OVERLAY
#import "../../../core/dungeon_features.s"
#import "../../../core/chest_search.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../../core/disarm_helpers.s"
#import "../../../core/monster.s"
#if HAL_PLATFORM_MONSTER_CATALOG
#import "monster_catalog4.s"
#import "../../../core/monster_catalog.s"
.const PLUS4_CATALOG_HIDDEN_TAIL_BASE = cat_hidden_end
.const PLUS4_CATALOG_HIDDEN_TAIL_FREE = CATALOG_HIDDEN_END + 1 - cat_hidden_end
.assert "Catalog hidden span starts at CATALOG_HIDDEN_BASE", cat_level_raw, CATALOG_HIDDEN_BASE
.assert "Catalog hidden unused tail matches remaining bytes in $DC00-$DCFF", PLUS4_CATALOG_HIDDEN_TAIL_FREE == $100 - CATALOG_IDX_SIZE && cat_hidden_end <= HUFF_INDEX_HIDDEN_BASE, true
#if PLUS4_CARTRIDGE
.assert "Cartridge catalog hidden unused tail is 139 bytes ($DC75-$DCFF)", PLUS4_CATALOG_HIDDEN_TAIL_FREE, 139
#else
.assert "Disk catalog hidden unused tail is 9 bytes ($DCF7-$DCFF)", PLUS4_CATALOG_HIDDEN_TAIL_FREE, 9
#endif
.print "Catalog hidden tail free: " + PLUS4_CATALOG_HIDDEN_TAIL_FREE + " bytes at $" + toHexString(PLUS4_CATALOG_HIDDEN_TAIL_BASE) + "-$" + toHexString(CATALOG_HIDDEN_END)
#endif
#import "../../../core/tier_manager.s"

// Overlay state is platform-owned so product/test variant layout changes
// cannot place these bytes inside later resident code.
current_overlay: .byte 0
ol_target:        .byte 0

#define OVERLAY_LOAD_PROMPT_GAME
#import "../common/overlay.s"
#undef OVERLAY_LOAD_PROMPT_GAME
.assert "Shared overlay count matches OVL_TITLE", hal_platform_overlay_count, OVL_TITLE
#if PLUS4_CARTRIDGE
.assert "Cartridge overlay count matches shared table", CART_OVERLAY_COUNT, 13
.assert "Startup overlay asset ABI", CART_ASSET_STARTUP - CART_ASSET_STARTUP + 1, OVL_STARTUP
.assert "Town overlay asset ABI", CART_ASSET_TOWN - CART_ASSET_STARTUP + 1, OVL_TOWN
.assert "Death overlay asset ABI", CART_ASSET_DEATH - CART_ASSET_STARTUP + 1, OVL_DEATH
.assert "Dungeon gen overlay asset ABI", CART_ASSET_DUNGEON_GEN - CART_ASSET_STARTUP + 1, OVL_DUNGEON_GEN
.assert "Help overlay asset ABI", CART_ASSET_HELP - CART_ASSET_STARTUP + 1, OVL_HELP
.assert "UI overlay asset ABI", CART_ASSET_UI - CART_ASSET_STARTUP + 1, OVL_UI
.assert "Items overlay asset ABI", CART_ASSET_ITEMS - CART_ASSET_STARTUP + 1, OVL_ITEMS
.assert "Spell overlay asset ABI", CART_ASSET_SPELL - CART_ASSET_STARTUP + 1, OVL_SPELL
.assert "Modal misc overlay asset ABI", CART_ASSET_MODAL_MISC - CART_ASSET_STARTUP + 1, OVL_MODAL_MISC
.assert "Chest overlay asset ABI", CART_ASSET_CHEST - CART_ASSET_STARTUP + 1, OVL_CHEST
.assert "Home overlay asset ABI", CART_ASSET_HOME - CART_ASSET_STARTUP + 1, OVL_HOME
.assert "Storage overlay asset ABI", CART_ASSET_STORAGE - CART_ASSET_STARTUP + 1, OVL_STORAGE
.assert "Title overlay asset ABI", CART_ASSET_TITLE - CART_ASSET_STARTUP + 1, OVL_TITLE
#endif
#import "../../../core/monster_ai.s"
#import "../../../core/scene_dirty.s"
#import "../../../core/scene_mat_tile.s"
#import "../../../core/scene_force.s"
#import "../../../core/recall.s"
#if !PLUS4_CARTRIDGE
// Disk item catalog 254-byte sector cache lives in Plus4HighBss ($DF00-$DFFD)
// under $FF3F so Default stays below MAP_BASE ($C800); zeroed at boot by
// plus4_high_bss_init. item_catalog_records.s asserts size == 254.
#define ITEM_CAT_BUF_EXTERNAL
.const ITEM_CAT_BUF_BASE = PLUS4_HIGH_BSS_BASE
.segment Plus4HighBss
plus4_high_bss_start:
    .fill 254, 0
plus4_high_bss_end:
.segment Default
.const PLUS4_HIGH_BSS_TAIL_FREE = PLUS4_HIGH_BSS_END + 1 - plus4_high_bss_end
.assert "Plus4HighBss starts at PLUS4_HIGH_BSS_BASE ($DF00)", plus4_high_bss_start == PLUS4_HIGH_BSS_BASE && PLUS4_HIGH_BSS_BASE == $df00 && PLUS4_HIGH_BSS_END == $dfff, true
.assert "Plus4HighBss fits in $DF00-$DFFF", plus4_high_bss_end <= PLUS4_HIGH_BSS_END + 1, true
.print "Plus4HighBss: " + (plus4_high_bss_end - plus4_high_bss_start) + " bytes used, " + PLUS4_HIGH_BSS_TAIL_FREE + " bytes free at $" + toHexString(plus4_high_bss_end) + "-$" + toHexString(PLUS4_HIGH_BSS_END)
#endif
#import "../../../core/monster_magic.s"
.macro ChestSummonsSegment() {
    .segment Default
}
.macro ChestSummonsRestoreSegment() {
    .segment Default
}
// roll_enchantment_body and re_equip co-locate in OVL_CHEST behind resident
// roll_enchantment (item_spawn_level_gen and chest_loot already run inside
// OVL_CHEST with 0 swaps; wizard_generate_item_execute swaps and restores
// OVL_MODAL_MISC), freeing Default for the resident spell-cast shell.
#define ROLL_ENCHANTMENT_SEGMENT_CUSTOM
.macro RollEnchantmentSegment() {
    .segment ChestOverlay
}
.macro RollEnchantmentRestoreSegment() {
    .segment Default
}
#define RE_EQUIP_SEGMENT_CUSTOM
.macro ReEquipSegment() {
    .segment ChestOverlay
}
.macro ReEquipRestoreSegment() {
    .segment Default
}
.label re_equip_entry = re_equip
#import "../../../core/item.s"
#if PLUS4_CARTRIDGE
#define ITEM_CATALOG_CART
#endif
#import "../common/item_catalog_records.s"
#if !PLUS4_CARTRIDGE
.assert "Plus4HighBss item catalog buffer matches ITMCAT_SECTOR_PAYLOAD", plus4_high_bss_end - plus4_high_bss_start, ITMCAT_SECTOR_PAYLOAD
#endif
#import "../../../core/chest_summons.s"
// Step-13 chest loot: latch + resident handoff stay in Default; the generator
// parks in the CHEST overlay with the picker it uses.
.macro ChestLootSegment() {
    .segment ChestOverlay
}
.macro ChestLootRestoreSegment() {
    .segment Default
}
// Scripted chest-open fixture parks in the CHEST overlay on Plus/4: the GEN
// window has no room beside place_secrets and the loot generator.
.macro ChestFixtureSegment() {
    .segment ChestOverlay
}
.macro ChestFixtureRestoreSegment() {
    .segment Default
}
#import "../../../core/chest_loot.s"
#define PLAYER_RECALC_EQUIPMENT_EXTERNAL
#define PLAYER_ITEM_COMMANDS_EXTERNAL
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../../../core/player_items.s"
#import "../../../core/player_recalc_equipment.s"
#undef PLAYER_ITEM_COMMANDS_EXTERNAL
#undef PLAYER_RECALC_EQUIPMENT_EXTERNAL
#import "../../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#define WALL_TO_MUD_SEGMENT_CUSTOM
.macro WallToMudSegment() {
    .segment SpellOverlay
}
.macro WallToMudRestoreSegment() {
    .segment Default
}
#import "../../../core/spell_effects.s"
#undef WALL_TO_MUD_SEGMENT_CUSTOM
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../core/player_magic_state.s"
#import "../../../core/player_magic_state_ops.s"
// Park level-up magic recomputation (cold, level-up-only) in ModalMisc:
// pre-importing here makes player_magic.s's own tail imports no-ops.
// combat.s reaches them via tramp_magic_* (HAL_PLATFORM_LEVELUP_MAGIC_USES_TRAMPOLINE).
.segment ModalMiscOverlay
#import "../../../core/player_magic_levelup.s"
#import "../../../core/player_magic_tail.s"
.segment Default
#import "../../../core/player_magic.s"

#import "dungeon_render.s"
#import "../../../core/dungeon_los.s"
.macro PlayerMoveRestoreResidentSegment() {
    .segment Default
}
.macro PlayerMoveLookSegment() {
    .segment ModalMiscOverlay
}
#define PLAYER_LOOK_EXTERNAL
#import "../../../core/player_move.s"
// player_run uses pm_live_occ_x/y defined by the preceding player_move import;
// both run_initialize and run_step stay resident (< MAP_BASE) for 0-disk Shift+dir.
#import "../../../core/player_run.s"
.assert "Plus/4 runner initialization entry stays resident", run_initialize < MAP_BASE, true
#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../../../core/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../../../core/projectile.s"
#import "../../../core/monster_attack.s"
#import "../../../core/turn.s"
#import "../../../core/store_data.s"
#import "../../../core/runtime_ui_strings.s"
#import "../common/compat/io_kernal_consts.s"
#define SAVE_STATE_SEGMENT_CUSTOM
.macro SaveStateResidentSegment() { .segment Default }
.macro SaveStateRestoreSegment() { .segment StorageOverlay }
#define SAVE_PROBE_SEGMENT_CUSTOM
.macro SaveProbeResidentSegment() { .segment Default }
.macro SaveProbeRestoreSegment() { .segment StorageOverlay }
.segment StorageOverlay
#import "../../shared/save.s"
#import "../common/save_slot_menu.s"
.segment Default
#import "hal/storage_policy.s"
#import "../common/disk_swap.s"
#define WIZARD_PROMPT_HELPERS_EXTERNAL
#import "../../../core/wizard.s"
#undef WIZARD_PROMPT_HELPERS_EXTERNAL
.const RECALL_VIEW_OVL = OVL_DEATH
#define DISARM_COMMAND_EXTERNAL
#import "../../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
#import "hal/storage.s"

// Resident helper for Plus/4 save-disk marker creation. It must execute from
// visible RAM while KERNAL is banked in; the $F000 runtime is hidden then.
plus4_storage_marker_write_resident:
    lda #2
    sta disk_status
    lda #DISK_ERR_MARKER_WRITE_OPEN
    jsr disk_error_set_phase
    jsr plus4_kernal_clrchn
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    // Disk Setup already scratched any stale marker; create a fresh marker.
    lda #hal_storage_marker_write_name_len - 1
    ldx #<(hal_storage_marker_write_name + 1)
    ldy #>(hal_storage_marker_write_name + 1)
    jsr plus4_kernal_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_write
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcc !cdmw_open_ok+
    sta disk_error_readst
    jmp !cdmw_close+
!cdmw_open_ok:
    lda #DISK_ERR_MARKER_CHKOUT
    jsr disk_error_set_phase
    ldx #hal_storage_marker_file_num
    jsr plus4_kernal_chkout
    bcc !cdmw_chkout_ok+
    sta disk_error_readst
    jmp !cdmw_close+
!cdmw_chkout_ok:
    lda #DISK_ERR_MARKER_WRITE
    jsr disk_error_set_phase
    lda #0
    sta disk_temp
!cdmw_write:
    ldx disk_temp
    lda hal_storage_marker_magic,x
    stx disk_error_index
    jsr plus4_kernal_chrout
    jsr plus4_kernal_readst
    sta disk_error_readst
    bne !cdmw_close+
    inc disk_temp
    lda disk_temp
    cmp #hal_storage_marker_magic_len
    bcc !cdmw_write-
    lda #0
    sta disk_status
!cdmw_close:
    jsr plus4_kernal_clrchn
    lda #hal_storage_marker_file_num
    jsr plus4_kernal_close
    lda disk_status
    bne !cdmw_status_done+
    lda save_device             // the drive the marker was written to
    sta disk_prompt_device
    jsr plus4_disk_read_command_status
!cdmw_status_done:
    lda disk_status
    beq !cdmw_ok+
    sec
    rts
!cdmw_ok:
    jsr disk_error_clear
    clc
    rts

plus4_disk_read_command_status:
    // A read that times out (ST bit 1) before any digit came is a lost
    // transfer, not an answer: under JiffyDOS a byte the drive sends while
    // its disk-controller IRQ runs can arrive cut short, as $58 (playtest-disk
    // save_overwrite). p4dcs_lost says so, for a caller that can ask again
    // with a fresh OPEN: reading this channel again goes on mid-message. A
    // digit is the drive's answer and stands.
    // Start with no channel selected: after a write the drive refused, the
    // JiffyDOS Plus/4 KERNAL never completed the CHKIN below (playtest-disk
    // full_disk).
    jsr plus4_kernal_clrchn
    // Failed until the drive answers, as on C64 and C128: a channel that
    // never opens, or a code not mapped below, must not read as OK.
    lda #2
    sta disk_status
    lda #$ff                    // no digits read
    sta disk_error_dos0
    sta disk_error_dos1
    lda #0                      // no command: just read the channel
    sta p4dcs_lost
    tax
    tay
    jsr plus4_kernal_setnam
    lda #hal_storage_cmd_channel
    ldx disk_prompt_device
    ldy #hal_storage_cmd_channel
    jsr plus4_kernal_setlfs
    jsr plus4_kernal_open
    bcs !p4dcs_done+
    ldx #hal_storage_cmd_channel
    jsr plus4_kernal_chkin
    bcs !p4dcs_close+
    jsr plus4_kernal_chrin
    sta disk_error_dos0
    jsr plus4_kernal_readst
    sta disk_error_readst
    bne !p4dcs_first_failed+    // as on C128: no second digit after a failed read
    jsr plus4_kernal_chrin
    sta disk_error_dos1
    jsr plus4_kernal_readst
    sta disk_error_readst
    jsr plus4_disk_status_to_disk_status
!p4dcs_close:
    jsr plus4_kernal_clrchn
    lda #hal_storage_cmd_channel
    jmp plus4_kernal_close
!p4dcs_first_failed:
    and #$02                    // read timeout
    beq !p4dcs_close-
    lda disk_error_dos0
    eor #$30
    cmp #10                     // a digit: the drive answered
    bcc !p4dcs_close-
    inc p4dcs_lost
    bcs !p4dcs_close-           // C = 1 from cmp
!p4dcs_done:
    rts

p4dcs_lost: .byte 0             // nonzero: the last status read lost its byte

plus4_disk_status_to_disk_status:
    // One DOS-code policy for every port: core/storage_status.s.
    lda disk_error_dos0
    ldx disk_error_dos1
    jsr storage_status_from_dos_digits
    cmp #plus4_dos_status_codes_len
    bcs !done+                  // UNKNOWN: disk_status keeps the failure seed
    tax
    lda plus4_dos_status_codes,x
    sta disk_status
    bne !done+
    sta disk_error_dos0         // OK: no error detail to show
    sta disk_error_dos1
!done:
    rts

// disk_status for each HAL_STORAGE_STATUS_* the DOS classifier returns.
plus4_dos_status_codes:
    .fill HAL_STORAGE_STATUS_DEVICE_NOT_READY + 1, i == HAL_STORAGE_STATUS_OK ? 0 : i == HAL_STORAGE_STATUS_NOT_FOUND ? 62 : i == HAL_STORAGE_STATUS_WRITE_PROTECTED ? 26 : i == HAL_STORAGE_STATUS_DISK_FULL ? 72 : i == HAL_STORAGE_STATUS_DEVICE_NOT_READY ? 74 : 2
.label plus4_dos_status_codes_len = * - plus4_dos_status_codes

// ============================================================
// Entry point
// ============================================================
entry_main:
    jsr disk_reset_session_state
    jsr plus4_install_ram_irq_vectors

    // BASIC ROM already banked out by bootstrap above

    // Load banked runtime payload to $F000 before any $F000 trampoline calls.
    jsr init_load_banked
    jsr plus4_huff_index_install    // before any message
    jsr plus4_high_bss_init         // zero-init $DF00-$DFFF before any recall/gameplay access

    jsr generation_busy_install
    jsr plus4_platform_services_install
    jsr platform_services_assert_installed
    jsr input_lock_charset_switch

    lda #COL_BLACK
    tax
    lda plus4_color_attr,x
    sta TED_BORDER
    sta TED_BG

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine
    lda #0
    sta plus4_caller_ovl_restore
    jsr tier_init
#if !PLUS4_CARTRIDGE
    jsr plus4_item_cat_boot_load
#endif
    jsr hal_sound_init
    jsr rng_seed

title_enter_menu:
    lda #$ff
    sta save_slot_index
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    lda plus4_test_single_drive_fresh_save_armed
    beq !plus4_test_single_drive_fresh_save_not_restart+
plus4_test_single_drive_fresh_save_after_restart:
    lda #0
    sta plus4_test_single_drive_fresh_save_armed
!plus4_test_single_drive_fresh_save_not_restart:
#endif

    // Set default text color and render full title screen + menu in OVL_TITLE.
    lda #COL_LGREY
    sta zp_text_color
    jsr tramp_title_load_and_draw

#if PLUS4_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda plus4_test_disk_setup_single_drive_return_armed
    beq !plus4_disk_setup_return_test_not_armed+
    lda #0
    sta plus4_test_disk_setup_single_drive_return_armed
plus4_test_after_disk_setup_single_drive_return:
    jmp plus4_test_after_disk_setup_single_drive_return
!plus4_disk_setup_return_test_not_armed:
#endif
#if PLUS4_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #0
    sta disk_setup_done
plus4_test_disk_setup_single_drive_return_wait_for_harness:
    jmp plus4_test_disk_setup_single_drive_return_wait_for_harness
plus4_test_disk_setup_single_drive_return_before_disk_setup:
#endif

#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
!plus4_test_single_drive_fresh_save_start:
#endif

#if PLUS4_TEST_SCRIPTED_OVERLAY_LOAD_PRODUCT
    jsr plus4_test_overlay_load_all
#endif

#if PLUS4_TEST_SCRIPTED_WAND_SELECTOR_PRODUCT
    jsr plus4_test_wand_selector_overlay_return
#endif

#if PLUS4_TEST_SCRIPTED_RETIREMENT_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
    jsr tramp_winner_royal
plus4_test_retirement_unexpected_return:
    jmp plus4_test_retirement_unexpected_return
plus4_test_retirement_pass_sym:
    jmp plus4_test_retirement_pass_sym
plus4_test_retirement_fail_sym:
    jmp plus4_test_retirement_fail_sym
#endif

#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_LOAD_MISSING_SAVE_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT || PLUS4_TEST_SCRIPTED_LOAD_WRONG_MEDIA_PRODUCT
    ldx #9
    jsr hal_storage_probe_media
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
#endif
#if PLUS4_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
plus4_test_save_media_fail_wait_for_harness:
    jmp plus4_test_save_media_fail_wait_for_harness
plus4_test_save_media_fail_before_save:
    jsr save_game
plus4_test_save_media_fail_unexpected_return:
    brk
#endif
#if PLUS4_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcs plus4_test_change_save_drive_unexpected_return
plus4_test_change_save_drive_wait_for_harness:
    jmp plus4_test_change_save_drive_wait_for_harness
plus4_test_change_save_drive_before_save:
    lda #10
    sta save_device
    jsr save_game
    bcc plus4_test_change_save_drive_unexpected_return
plus4_test_change_save_drive_pass:
    jmp plus4_test_change_save_drive_pass
plus4_test_change_save_drive_unexpected_return:
    brk
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT || PLUS4_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcc !sd_lr_ok+
    brk
!sd_lr_ok:
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
plus4_test_single_drive_load_return_wait_for_harness:
    jmp plus4_test_single_drive_load_return_wait_for_harness
plus4_test_single_drive_load_return_before_load:
    jmp title_load_game
#endif
#if PLUS4_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
plus4_test_load_then_save_new_empty_wait_for_harness:
    jmp plus4_test_load_then_save_new_empty_wait_for_harness
plus4_test_load_then_save_new_empty_before_load:
    jmp title_load_game
plus4_test_load_then_save_new_empty_fail:
    jmp plus4_test_load_then_save_new_empty_fail
#endif
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #1
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcc !sd_lc_ok+
    brk
!sd_lc_ok:
plus4_test_single_drive_load_corrupt_wait_for_harness:
    jmp plus4_test_single_drive_load_corrupt_wait_for_harness
plus4_test_single_drive_load_corrupt_before_load:
    jmp title_load_game
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcc !sd_lwm_ok+
    brk
!sd_lwm_ok:
plus4_test_single_drive_load_wrong_media_wait_for_harness:
    jmp plus4_test_single_drive_load_wrong_media_wait_for_harness
plus4_test_single_drive_load_wrong_media_before_load:
    jmp title_load_game
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcc !sd_swm_ok+
    brk
!sd_swm_ok:
plus4_test_single_drive_save_wrong_media_wait_for_harness:
    jmp plus4_test_single_drive_save_wrong_media_wait_for_harness
plus4_test_single_drive_save_wrong_media_before_save:
    jsr disk_prompt_save
    jsr save_game
plus4_test_single_drive_save_wrong_media_unexpected_return:
    brk
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #2
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcs plus4_test_single_drive_fresh_save_unexpected_return
plus4_test_single_drive_fresh_save_wait_for_harness:
    jmp plus4_test_single_drive_fresh_save_wait_for_harness
plus4_test_single_drive_fresh_save_before_save:
    jsr disk_prompt_save
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT
    bcs plus4_test_single_drive_fresh_save_unexpected_return
    jsr save_game
    bcs plus4_test_single_drive_fresh_save_unexpected_return
plus4_test_single_drive_fresh_save_no_init_return:
    jmp plus4_test_single_drive_fresh_save_no_init_return
#else
    bcs plus4_test_single_drive_fresh_save_unexpected_return
    jsr save_game
    bcc plus4_test_single_drive_fresh_save_unexpected_return
    lda #1
    sta plus4_test_single_drive_fresh_save_armed
    jsr disk_prompt_game_required
    jmp game_over_prompt
#endif
plus4_test_single_drive_fresh_save_unexpected_return:
    brk
#endif
#if PLUS4_TEST_SCRIPTED_DEATH_RETURN_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #2
    sta disk_setup_done
    lda #DEATH_TRAP_PIT
    sta death_source_saved
    sta zp_death_source
plus4_test_death_return_wait_for_harness:
    jmp plus4_test_death_return_wait_for_harness
plus4_test_death_return_before_prepare:
    jsr tramp_game_over_prepare
plus4_test_death_return_after_prepare:
    jsr disk_prompt_save
    jsr tramp_game_over_run
plus4_test_death_return_after_score:
    jmp plus4_test_death_return_after_score
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_RETURN_PRODUCT
    lda plus4_test_single_drive_save_return_ran
    bne !plus4_test_single_drive_save_return_skip+
    inc plus4_test_single_drive_save_return_ran
    lda #8
    sta save_device
    lda #1
    sta disk_mode
    lda #2
    sta disk_setup_done
    lda #OVL_STORAGE
    jsr overlay_load
    bcc !sd_sr_ok+
    jmp plus4_test_single_drive_save_return_fail
!sd_sr_ok:
plus4_test_single_drive_wait_for_harness:
    jmp plus4_test_single_drive_wait_for_harness
plus4_test_single_drive_before_save:
    lda #1
    sta plus4_test_single_drive_stage
    lda #8
    sta save_device
    lda #8
    sta disk_prompt_device
    jsr disk_init_drive
    jsr disk_marker_init
    bcc !marker_ok+
    jmp plus4_test_single_drive_save_return_fail
!marker_ok:
    lda #2
    sta plus4_test_single_drive_stage
    jsr save_game
    bcs !saved+
    jmp plus4_test_single_drive_save_return_fail
!saved:
    lda #3
    sta plus4_test_single_drive_stage
    lda #8
    sta program_device
    jsr disk_prompt_game_required
plus4_test_single_drive_after_program_prompt:
    lda #4
    sta plus4_test_single_drive_stage
    jmp title_enter_menu
!plus4_test_single_drive_save_return_skip:
#endif

title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    lda disk_setup_done
    bne !load_now+
    jsr tramp_disk_setup
    bcs plus4_title_redraw_cached
!load_now:
    jmp title_load_game
!not_l:
    cmp #$41                // A: About, before a character exists
    bne !not_legal_title+
    jsr tramp_ui_legal_display
    jmp title_enter_menu
!not_legal_title:
    cmp #$44                // 'D' — disk setup
    bne title_menu_loop
    jsr tramp_disk_setup
    bcs plus4_title_redraw_cached
    jsr disk_prompt_game_required
#if PLUS4_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda #1
    sta plus4_test_disk_setup_single_drive_return_armed
#endif
    jmp plus4_title_redraw_cached

plus4_title_redraw_cached:
    lda plus4_title_art_cached
    bne !cached+
    jmp title_enter_menu
!cached:
    lda #COL_LGREY
    sta zp_text_color
    jsr tramp_title_render_data
#if PLUS4_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda plus4_test_disk_setup_single_drive_return_armed
    beq !plus4_disk_setup_return_cached_not_armed+
    lda #0
    sta plus4_test_disk_setup_single_drive_return_armed
    jmp plus4_test_after_disk_setup_single_drive_return
!plus4_disk_setup_return_cached_not_armed:
#endif
    jmp title_menu_loop

plus4_title_art_cached: .byte 0

#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_RETURN_PRODUCT
plus4_test_single_drive_save_return_ran: .byte 0
plus4_test_single_drive_stage: .byte 0
plus4_test_single_drive_save_return_fail:
    jmp plus4_test_single_drive_save_return_fail
#endif
#if PLUS4_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
plus4_test_single_drive_fresh_save_armed: .byte 0
#endif
#if PLUS4_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
plus4_test_disk_setup_single_drive_return_armed: .byte 0
#endif

#if PLUS4_TEST_SCRIPTED_OVERLAY_LOAD_PRODUCT
plus4_test_overlay_load_all:
    lda #OVL_STARTUP
    sta plus4_test_overlay_id
!loop:
    lda plus4_test_overlay_id
    jsr overlay_load
    bcs plus4_test_overlay_load_fail_sym
    inc plus4_test_overlay_id
    lda plus4_test_overlay_id
    cmp #(OVL_COUNT + 1)
    bcc !loop-
plus4_test_overlay_load_pass_sym:
    jmp plus4_test_overlay_load_pass_sym
plus4_test_overlay_load_fail_sym:
    jmp plus4_test_overlay_load_fail_sym

plus4_test_overlay_id:
    .byte 0
#endif

#if PLUS4_TEST_SCRIPTED_WAND_SELECTOR_PRODUCT
.assert "Plus/4 wand-selector test wands live on Page 0", ITEM_PAGE_WAND_OF_LIGHT == 0 && ITEM_PAGE_WAND_OF_LIGHTNING == 0 && ITEM_PAGE_WAND_OF_STINKING_CLOUD == 0, true
plus4_test_wand_selector_overlay_return:
    sei
    jsr plus4_bank_ram
    jsr msg_init
    jsr item_init_inventory

    lda #ITEM_SLOT_WAND_OF_LIGHT
    sta inv_item_id + 0
    lda #ITEM_SLOT_WAND_OF_LIGHTNING
    sta inv_item_id + 1
    lda #ITEM_SLOT_WAND_OF_STINKING_CLOUD
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 0
    sta inv_qty + 1
    sta inv_qty + 2
    lda #0
    sta inv_p1 + 0
    sta inv_p1 + 1
    sta inv_p1 + 2
    sta inv_flags + 0
    sta inv_flags + 1
    sta inv_flags + 2
    sta piw_return_overlay

    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    bcs plus4_test_wand_selector_fail_sym
    jsr item_aim_wand
plus4_test_wand_selector_pass_sym:
    jmp plus4_test_wand_selector_pass_sym
plus4_test_wand_selector_fail_sym:
    jmp plus4_test_wand_selector_fail_sym
#endif

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
#if !BYPASS_SLOT_PROMPT
    jsr save_prepare_slot_prompt
    bcs !title_load_fail+
#endif
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr ui_clear_full_screen_safe
    jsr ui_reset_message_state
#if !BYPASS_SLOT_PROMPT
    jsr save_select_slot_prompt
#endif
    jsr load_game
    // Fail closed on the explicit load carry result before resuming gameplay.
    bcc !title_load_fail+
#if PLUS4_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
plus4_test_load_then_save_new_empty_loaded:
plus4_test_load_then_save_new_empty_before_save:
    jsr disk_prompt_save
    bcc !plus4_load_then_save_prompt_ok+
    jmp plus4_test_load_then_save_new_empty_fail
!plus4_load_then_save_prompt_ok:
    jsr save_game
    bcs !plus4_load_then_save_saved+
    jmp plus4_test_load_then_save_new_empty_fail
!plus4_load_then_save_saved:
    jsr disk_prompt_game_required
plus4_test_load_then_save_new_empty_done:
    jmp plus4_test_load_then_save_new_empty_done
#endif
#if PLUS4
    jsr disk_prompt_game
#endif
    jsr disk_prompt_game_required // Swap back for tier loading
    jmp load_resume_game
!title_load_fail:
    jsr input_get_modal_dismiss_key
    jsr disk_prompt_game_required // Verify program media before returning to title
    jmp title_enter_menu

// ============================================================
// IRQ wedge — suppress KERNAL cursor blink
// Forces $CC non-zero before KERNAL IRQ handler checks it.
// Must live in main RAM (always accessible during IRQ).
// ============================================================
irq_no_blink:
    cld
irq_no_blink_after_cld:
    rti

// plus4_irq_hidden_rom — IRQ/NMI handler for all-RAM mode.
// If an interrupt leaks through while Plus/4 ROM is hidden, CPU vectors read
// RAM at $FFFA/$FFFE. Return without touching KERNAL ROM, which is not visible
// in that banking mode.
plus4_irq_hidden_rom:
    lda TED_IRQ_STATUS
    sta TED_IRQ_STATUS
    rti

plus4_install_ram_irq_vectors:
    php
    sei
    jsr plus4_bank_ram
    lda #0
    sta TED_IRQ_ENABLE
    lda TED_IRQ_STATUS
    sta TED_IRQ_STATUS
    lda #<plus4_irq_hidden_rom
    sta $fffa
    sta $fffe
    lda #>plus4_irq_hidden_rom
    sta $fffb
    sta $ffff
    plp
    rts

.label hal_irq_install_runtime = plus4_install_ram_irq_vectors

// ============================================================
// kernal_load_safe — KERNAL LOAD wrapper for Plus/4
// ============================================================
kernal_load_safe:
    jsr plus4_kernal_load   // KERNAL LOAD — carry set on error
    php                     // Preserve carry for caller
    jsr plus4_platform_runtime_resync
    plp
    rts

// ============================================================
#if !PLUS4_CARTRIDGE
// plus4_catalog_cache_invalidate — Invalidate non-generation disk caches
// ($0400-$04FF catalog LRU + $0600-$07FF item pickup cache) on ovl.gen entry
// before DUNGEON_GEN_SCAN_SCRATCH_BASE..END ($0400-$07FF) may reuse it.
// Preserves A/X/Y/flags.
plus4_catalog_cache_invalidate:
    jmp item_pickup_cache_invalidate
#endif

// ============================================================
// Dungeon gen overlay trampoline — bank KERNAL out, call $E000 overlay
// ============================================================
// KERNAL must be off ($34) while executing overlay code at $E000.
// IRQs must stay DISABLED for the entire overlay execution:
//   - tramp_level_generate holds sei from entry to exit
//   - inner trampolines (tramp_assign_special_room, tramp_vault_seal_entrance,
//     verify_connectivity) use php/plp to preserve the caller's interrupt state
//     instead of cli, so IRQs remain disabled throughout dungeon generation
tramp_level_generate:
    sei
#if !PLUS4_CARTRIDGE
    jsr plus4_catalog_cache_invalidate
#endif
    jsr plus4_bank_ram
    jsr level_generate          // executes from DungeonGenOverlay at $E000
    jsr plus4_bank_ram
    rts

// ============================================================
// Special rooms trampolines — SEI + bank in RAM, call $F000 / OVL.MODAL
// ============================================================
tramp_find_special_room:
    pha                         // Save A (room type input)
    sei
    jsr plus4_bank_ram
    pla                         // Restore A
    jsr find_special_room
    // Carry flag preserved — lda/sta don't affect carry
    jmp tramp_sr_epilogue

plus4_caller_ovl_restore:
    .byte 0

// Shared caller-overlay dispatch for OVL_ITEMS / OVL_TITLE commands whose
// nested overlay trampolines (? selectors, extended effects, spell execution)
// must restore the invoking overlay before returning.
// Input: A/Y = target routine, X = caller overlay ID (OVL_*)
// Output: Carry preserved from routine (Carry clear if overlay load fails)
plus4_ovl_caller_dispatch:
    sta plus4_ovl_caller_jmp+1
    sty plus4_ovl_caller_jmp+2
    stx plus4_caller_ovl_restore
    txa
    jsr overlay_load_no_kernal
    bcs !tocd_fail+
plus4_ovl_caller_jmp:
    jsr $0000
    php
    lda #0
    sta plus4_caller_ovl_restore
    jsr plus4_platform_runtime_resync
    plp
    rts
!tocd_fail:
    lda #0
    sta plus4_caller_ovl_restore
    jsr plus4_platform_runtime_resync
    clc
    rts

plus4_ovl_caller_epilogue:
    lda plus4_caller_ovl_restore
    beq !toce_done+
    jsr overlay_load_no_kernal
    bcs !toce_fatal+
!toce_done:
    jmp tramp_sr_epilogue
!toce_fatal:
    jmp entry_main

tramp_item_wear:
    lda #<item_wear
    ldy #>item_wear
    ldx #OVL_ITEMS
    jmp plus4_ovl_caller_dispatch

tramp_item_takeoff:
    lda #<item_takeoff
    ldy #>item_takeoff
    ldx #OVL_ITEMS
    jmp plus4_ovl_caller_dispatch

tramp_item_eat:
    lda #<item_eat
    ldy #>item_eat
    ldx #OVL_ITEMS
    jmp plus4_ovl_caller_dispatch

tramp_item_quaff:
    lda #<item_quaff
    ldy #>item_quaff
    ldx #OVL_ITEMS
    jmp plus4_ovl_caller_dispatch

plus4_disp_items:
    ldx #OVL_ITEMS
    .byte $2c
plus4_disp_help:
    ldx #OVL_HELP
    .byte $2c
plus4_disp_title:
    ldx #OVL_TITLE
    .byte $2c
plus4_disp_modal:
    ldx #OVL_MODAL_MISC
    .byte $2c
plus4_disp_chest:
    ldx #OVL_CHEST
plus4_ovl_sr_dispatch:
    sta plus4_osd_jsr + 1
    sty plus4_osd_jsr + 2
    txa
    jsr overlay_load_no_kernal
    bcs !posd_done+
plus4_osd_jsr:
    jsr $0000
!posd_done:
    jmp tramp_sr_epilogue

tramp_item_drop:
    lda #<item_drop
    ldy #>item_drop
    ldx #OVL_HELP
    jmp plus4_ovl_caller_dispatch

tramp_help_cmd_body:
    lda #<plus4_help_cmd_body
    ldy #>plus4_help_cmd_body
    ldx #OVL_HELP
    jmp plus4_ovl_caller_dispatch

// tramp_trap_trigger — Runs resident $F000 trap_trigger under all-RAM ($FF3F)
// with zero disk/overlay access.
tramp_trap_trigger:
    sei
    jsr plus4_bank_ram
    ldx df_disarm_trap_idx
    jsr trap_trigger
    jmp tramp_sr_epilogue

// item_spawn_level — Resident entry for level floor-item generation.
// Town (dlvl == 0) clears the floor table without touching disk; dungeon
// levels run item_spawn_level_gen co-located with pick_item_type_overlay in
// OVL_CHEST.
item_spawn_level:
    jsr item_init_floor
    lda zp_player_dlvl
    beq !isl_town_done+
    lda current_overlay
    cmp #OVL_CHEST
    beq !isl_loaded+
    ldx #OVL_CHEST - 1
    jsr overlay_load_disk
    lda #OVL_CHEST
    sta current_overlay
!isl_loaded:
    sei
    jsr plus4_bank_ram
    jsr item_spawn_level_gen
    jmp tramp_sr_epilogue
!isl_town_done:
    rts

// tramp_spawn_nest_gold — Called from item_spawn_level_gen (OVL_CHEST).
// Probes find_special_room(RT_NEST) in $F000 first so non-nest levels avoid
// loading OVL_DUNGEON_GEN, and restores the caller overlay before returning.
tramp_spawn_nest_gold:
    sei
    jsr plus4_bank_ram
    lda #RT_NEST
    jsr find_special_room
    bcc !sng_done+
    lda current_overlay
    pha
    cmp #OVL_DUNGEON_GEN
    beq !sng_loaded+
    ldx #OVL_DUNGEON_GEN - 1
    jsr overlay_load_disk
    lda #OVL_DUNGEON_GEN
    sta current_overlay
!sng_loaded:
#if !PLUS4_CARTRIDGE
    jsr plus4_catalog_cache_invalidate
#endif
    sei
    jsr plus4_bank_ram
    jsr spawn_nest_gold
    pla
    beq !sng_done+
    cmp #OVL_DUNGEON_GEN
    beq !sng_done+
    pha
    tax
    dex
    jsr overlay_load_disk
    pla
    sta current_overlay
!sng_done:
    jmp tramp_sr_epilogue

// hal_player_recalc_pflags — Runs player_recalc_pflags_equipment in
// OVL_MODAL_MISC while preserving current_overlay for overlay callers.
hal_player_recalc_pflags:
    lda current_overlay
    pha
    cmp #OVL_MODAL_MISC
    beq !hprp_loaded+
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
    bcs !hprp_fail+
!hprp_loaded:
    sei
    jsr plus4_bank_ram
    jsr player_recalc_pflags_equipment
    pla
    beq !hprp_done+
    cmp #OVL_MODAL_MISC
    beq !hprp_done+
    jsr overlay_load_no_kernal
    bcs !hprp_fatal+
!hprp_done:
    jmp plus4_platform_runtime_resync
!hprp_fail:
    pla
    jmp plus4_platform_runtime_resync
!hprp_fatal:
    jmp entry_main

tramp_load_resume_reset:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !tlrr_done+
    jsr load_resume_reset
    jsr overlay_invalidate
!tlrr_done:
    jmp tramp_sr_epilogue

tramp_ui_inv_select_display:
    lda piw_return_overlay
    bne !tuisd_have_ret+
    lda plus4_caller_ovl_restore
    sta piw_return_overlay
!tuisd_have_ret:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !tuisd_done+
    jsr ui_inv_select_display
!tuisd_done:
    jmp tramp_sr_epilogue

tramp_ui_equip_select_display:
    lda #OVL_HELP
    jsr overlay_load_no_kernal
    bcs !tuesd_done+
    jsr ui_equip_select_display
!tuesd_done:
    jmp plus4_ovl_caller_epilogue

tramp_eff_ext_eat:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !teee_done+
    jsr eff_ext_eat_piw
!teee_done:
    jmp plus4_ovl_caller_epilogue

tramp_eff_ext_quaff:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !teeq_done+
    jsr eff_ext_quaff_piw
!teeq_done:
    jmp plus4_ovl_caller_epilogue

// calc_spell_failure lives in OVL.SPELL co-located with spell_execute_selected;
// carry is the result (C=1 fail, C=0 success), preserved across resync.
tramp_calc_spell_failure:
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !done+
    jsr calc_spell_failure
!done:
    php
    jsr plus4_platform_runtime_resync
    plp
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================

// tramp_ego_append_suffix — Decode ego suffix 1..55 via ITEM.CAT and append
// to combat_msg_buf. Runs in Default without banking RAM over KERNAL so
// IEC/cart item catalog reads execute safely.
// Input: A = ego type (0..EGO_COUNT)
// Clobbers: A, X, Y, zp_ptr0
tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+             // No ego → nothing to append
    cmp #EGO_TYPE_COUNT
    bcs !teas_done+
    jsr item_cat_decode_ego     // zp_ptr0 = decoded suffix in item_name_decode_buf
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #COMBAT_MSG_BUF_LAST    // Buffer overflow protection
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
!teas_done:
    rts

// ============================================================
// tramp_ego_apply_damage — Apply ego slay/bonus damage (banked at $F000)
// Input: A = ego type (1-7), cmb_damage and cmb_type set
// Output: cmb_damage updated
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
tramp_ego_apply_damage:
    pha
    sei
    jsr plus4_bank_ram
    pla
    jsr ego_apply_damage
    jsr plus4_bank_ram
    rts


// tramp_roll_ego_type / roll_enchantment — Swap OVL_CHEST when needed (for
// roll_armour_ego and roll_enchantment_body) while preserving any active caller
// overlay. Level item generation and chest loot already run inside OVL_CHEST (0 swaps).
plus4_tret_arg: .byte 0
plus4_tret_res: .byte 0

tramp_roll_ego_type:
    sta plus4_tret_arg
    lda current_overlay
    pha
    cmp #OVL_CHEST
    beq !tret_loaded+
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !tret_fail+
!tret_loaded:
    sei
    jsr plus4_bank_ram
    lda plus4_tret_arg
    jsr roll_ego_type
    jmp plus4_chest_ovl_restore_ret_a

roll_enchantment:
    sta plus4_tret_arg
    lda current_overlay
    pha
    cmp #OVL_CHEST
    beq !tre_loaded+
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !tret_fail+
!tre_loaded:
    sei
    jsr plus4_bank_ram
    lda plus4_tret_arg
    jsr roll_enchantment_body
plus4_chest_ovl_restore_ret_a:
    sta plus4_tret_res
    pla
    beq !tcor_done+
    cmp #OVL_CHEST
    beq !tcor_done+
    jsr overlay_load_no_kernal
    bcs !tcor_fatal+
!tcor_done:
    jsr plus4_platform_runtime_resync
    lda plus4_tret_res
    rts
!tret_fail:
    pla
    jsr plus4_platform_runtime_resync
    lda #0
    rts
!tcor_fatal:
    jmp entry_main


// Init-only strings — kept in main RAM (small, referenced by title_screen.s)
// ============================================================
title_str:
    .text "MORIA8 PLUS/4" ; .byte 0

// title_show_sysinfo — Trampoline to call banked version at $F000
// Reads KERNAL_REV while KERNAL is still banked in, then banks out.
title_show_sysinfo:
    rts
tsi_krev_cached: .byte 0


plus4_platform_main_loop_begin:
plus4_platform_vector_reassert:
plus4_platform_runtime_resync:
    sei
    jsr plus4_bank_ram
    jmp plus4_display_resync

#import "../../../core/ui_help_clear.s"

// ============================================================
// UI screen trampolines — help and modal UI load from $E000 overlays
// ============================================================
overlay_load_no_kernal:
    jsr overlay_load
    bcs !done+
hal_overlay_post_reload:
    sei
    jsr plus4_install_ram_irq_vectors
    jmp plus4_bank_ram
!done:
    rts

#if !BYPASS_SLOT_PROMPT
save_prepare_slot_prompt:
    lda #OVL_STORAGE
    jmp overlay_load_no_kernal

save_select_slot_prompt:
    sei
    jsr plus4_bank_ram
    jsr save_select_slot_prompt_impl
    jmp plus4_platform_runtime_resync
#endif

save_game:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !sg_fail+
    sei
    jsr plus4_bank_ram
    jsr save_game_impl
    php
    jsr plus4_platform_runtime_resync
    plp
    rts
!sg_fail:
    jsr plus4_platform_runtime_resync
    clc
    rts

load_game:
    lda #OVL_STORAGE
    jsr overlay_load_no_kernal
    bcs !lg_fail+
    sei
    jsr plus4_bank_ram
    jsr load_game_impl
    php
    jsr plus4_platform_runtime_resync
    plp
    rts
!lg_fail:
    jsr plus4_platform_runtime_resync
    clc
    rts

#import "look_trampoline.s"

tramp_ui_recall:
    lda #OVL_DEATH
    jsr overlay_load_no_kernal
    bcs !done+
    sei
    jsr plus4_bank_ram
    jsr ui_recall_display
!done:
    jmp tramp_sr_epilogue

// Chest routing (docs/CHEST_DESIGN.md). tramp_chest_open (generated) is called
// from the resident cmd_open pre-dispatch and owns the epilogue. chest_dispatch
// is tail-called (A/Y = handler) from bash_command/disarm_command inside the
// items overlay; their caller trampolines run the epilogue.
chest_dispatch:
    sta chest_disp_jmp+1
    sty chest_disp_jmp+2
    lda #OVL_CHEST
    jsr overlay_load_no_kernal
    bcs !done+
chest_disp_jmp:
    jmp $0000               // SMC dispatch target (never JMP (addr))
!done:
    rts

tramp_ui_identify:
    lda #OVL_UI
    jsr overlay_load_no_kernal
    bcs !done+
    jsr ui_identify_print
    jsr plus4_bank_ram
    jsr tier_restore_after_overlay
!done:
    jmp tramp_sr_epilogue

tramp_disk_setup:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !tds_done+
    sei
    jsr plus4_bank_ram
    jsr disk_setup_run
    jmp tramp_sr_epilogue

!tds_done:
    rts

tramp_disk_prepare_selected:
    lda #OVL_STORAGE
    jsr overlay_load
    bcs !tdps_done+
    sei
    jsr plus4_bank_ram
    jsr disk_setup_prepare_selected
    php
    jsr plus4_platform_runtime_resync
    plp
!tdps_done:
    rts

// ============================================================
// Store overlay trampolines — load overlay, bank out KERNAL, call $E000+
// ============================================================
// Shared preamble: ensure town overlay is loaded, then bank out KERNAL
store_overlay_preamble:
    lda #OVL_TOWN
    jsr overlay_load
    sei
    jsr plus4_bank_ram
    rts

tramp_store_enter:
    lda zp_store_idx
    cmp #STORE_HOME
    beq !tse_home+
    jsr store_overlay_preamble
    jsr store_enter
    jmp tramp_sr_epilogue
!tse_home:
    lda #OVL_HOME
    jsr overlay_load_no_kernal
    bcs !tse_done+
    sei
    jsr plus4_bank_ram
    jsr home_enter
!tse_done:
    jmp tramp_sr_epilogue

title_overlay_preamble:
    lda #OVL_TITLE
    jsr overlay_load
    bcs !top_fail+
    sei
    jsr plus4_bank_ram
    clc
!top_fail:
    rts

#if C64_TEST_SCRIPTED_BOOK_OVERLAY || C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_expect_screen_string:
    sta test_expect_row
    stx test_expect_col
    ldx test_expect_row
    lda screen_row_lo,x
    clc
    adc test_expect_col
    sta zp_ptr2
    lda screen_row_hi,x
    adc #0
    sta zp_ptr2_hi
    ldy #0
!tes_loop:
    lda (zp_ptr0),y
    beq !tes_ok+
    cmp (zp_ptr2),y
    bne !tes_fail+
    iny
    bne !tes_loop-
!tes_fail:
    clc
    rts
!tes_ok:
    sec
    rts

test_expect_row: .byte 0
test_expect_col: .byte 0

.encoding "screencode_mixed"
test_inventory_title_str: .text "Inventory" ; .byte 0
test_beginner_book_str:   .text "Spellbook Beginners-Magick" ; .byte 0
test_mage_book_title_str: .text "Mage Book" ; .byte 0
test_magic_missile_str:   .text "Magic Missile" ; .byte 0
// The cast list shows learned spells only (as Umoria); a new mage knows one.
test_cast_one_spell_str:  .text "Cast which? (a-a, esc)" ; .byte 0

#if C64_TEST_SCRIPTED_BOOK_OVERLAY
test_assert_book_overlay:
    lda #<test_inventory_title_str
    sta zp_ptr0
    lda #>test_inventory_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #15
    jsr test_expect_screen_string
    bcc !book_fail+

    lda #<test_beginner_book_str
    sta zp_ptr0
    lda #>test_beginner_book_str
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !book_fail+

    jmp c64_test_book_overlay_pass_sym
!book_fail:
    jmp c64_test_book_overlay_fail_sym
#endif

#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_assert_spell_list_overlay:
    lda #<test_mage_book_title_str
    sta zp_ptr0
    lda #>test_mage_book_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #14
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<test_magic_missile_str
    sta zp_ptr0
    lda #>test_magic_missile_str
    sta zp_ptr0_hi
    lda #2
    ldx #4
    jsr test_expect_screen_string
    bcc !list_fail+

    lda #<test_cast_one_spell_str
    sta zp_ptr0
    lda #>test_cast_one_spell_str
    sta zp_ptr0_hi
    lda #24
    ldx #5
    jsr test_expect_screen_string
    bcc !list_fail+

    jmp c64_test_spell_list_overlay_pass_sym
!list_fail:
    jmp c64_test_spell_list_overlay_fail_sym
#endif
#endif

#if C64_TEST_SCRIPTED_SPELL
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_BOOK_OVERLAY
c64_test_book_overlay_fail_sym:
    brk
c64_test_book_overlay_fail_input_sym:
    brk
c64_test_book_overlay_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_SPELL_LIST_OVERLAY
c64_test_spell_list_overlay_fail_sym:
    brk
c64_test_spell_list_overlay_fail_input_sym:
    brk
c64_test_spell_list_overlay_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#else
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_spell_fail_no_cast_sym:
    brk
c64_test_spell_fail_level_sym:
    brk
c64_test_spell_fail_known_sym:
    brk
c64_test_spell_fail_validate_sym:
    brk
c64_test_spell_fail_cancel_sym:
    brk
c64_test_spell_fail_input_sym:
    brk
c64_test_spell_pass_sym:
    brk
#endif
#endif
#endif
#endif
#endif

// ============================================================
// Startup overlay trampoline — load overlay, bank out KERNAL, call $E000+
// ============================================================
tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    sei
    jsr plus4_bank_ram
    jsr player_create
    jmp tramp_sr_epilogue

// ============================================================
// Death overlay trampoline — orchestrates the full game-over sequence
// ============================================================
// Interleaves overlay calls ($E000, $01=$34) with KERNAL I/O ($01=$36).
// Pre-resolves creature name before overlay overwrites tier data.
tramp_game_over_disk_setup:
    jsr tramp_game_over_prepare // Disk Setup loads OVL_STORAGE into $E000.
    jsr tramp_game_over_stash
    jsr tramp_disk_setup
    bcs !done+
    jsr tramp_game_over_restore_stash
    clc
!done:
    rts

tramp_winner_royal:
    jsr disk_prompt_game
    lda #hal_storage_modal_misc_name_len
    ldx #<hal_storage_modal_misc_name
    ldy #>hal_storage_modal_misc_name
    jsr asset_load_required     // asks for the program disk until it loads
    lda #0
    sta current_overlay
    sei
    jsr plus4_bank_ram
    jsr winner_apply_retirement_bonus_overlay
    jsr royal_screen
#if PLUS4_TEST_SCRIPTED_RETIREMENT_PRODUCT
    jmp plus4_test_retirement_pass_sym
#endif
    jsr plus4_bank_ram
    rts

// Generated resident trampolines (tools/gen_trampolines.py -> build/trampolines/)
#import "../../../build/trampolines/plus4_trampolines.inc"

// ============================================================
// game_over_prompt — return to title/menu after save, quit, or death.
// Shown at all exit points (save+quit, voluntary quit, death).
// ============================================================
game_over_prompt:
    jmp restart_entry

// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.assert "Program fits below MAP_BASE", program_end <= MAP_BASE, true

// ============================================================
// Past program_end: code and data the game no longer needs once a map is
// drawn, overwritten from MAP_BASE on. Most runs once at startup; the
// catalog boot load runs again on restart, so it is asserted below MAP_BASE.
// ============================================================

#if HAL_PLATFORM_CATALOG_RECORDS
// The monster catalog's boot load: tier_init runs it at boot and again on
// every restart (game_over_prompt jumps to restart_entry), after a game has
// overwritten the map. So it is not init-only: it sits here, past
// program_end, and must end below MAP_BASE, which the map overwrites.
#import "../common/catalog_boot.s"
.assert "Catalog boot loads follow the resident image", catalog_boot_load >= program_end, true
.assert "Catalog boot loads end below the map (restart runs them again)", catalog_boot_end <= MAP_BASE, true
#if !PLUS4_CARTRIDGE
plus4_item_cat_boot_load:
    lda #picbl_idx_name_end - picbl_idx_name
    ldx #<picbl_idx_name
    ldy #>picbl_idx_name
    jsr asset_load_required     // PRG at CATALOG_IDX_LOAD ($D600)
    ldx #ITMCAT_IDX_BODY_SIZE - 1
!picbl_copy:
    lda CATALOG_IDX_LOAD,x
    sta item_cat_idx_data,x
    dex
    bpl !picbl_copy-
    rts
picbl_idx_name: .text "ITEM.IDX"
picbl_idx_name_end:
plus4_item_cat_boot_end:
.assert "Item catalog index fits in one page boot buffer", ITMCAT_IDX_BODY_SIZE <= $100, true
.assert "Item catalog boot loads end below the map (restart runs them again)", plus4_item_cat_boot_end <= MAP_BASE, true
#endif
#endif

// init_load_banked — Load banked runtime payload to $F000.
// Called once at startup before any $F000 trampoline is used.
// Clobbers: A, X, Y
init_load_banked:
#if PLUS4_CARTRIDGE
    lda #CART_ASSET_RUNTIME
    jmp cart_load_asset
#else
    lda #plus4_banked_fname_len
    ldx #<plus4_banked_fname
    ldy #>plus4_banked_fname
    jsr plus4_kernal_setnam
    lda #2
    ldx program_device
    ldy #1                      // Use PRG header address ($F000)
    jsr plus4_kernal_setlfs
    lda #0
    ldx #$00
    ldy #$f0
    jsr plus4_kernal_load
    php
    lda #2
    jsr plus4_kernal_close
    jsr plus4_kernal_clrchn
    plp
    bcs !load_failed+
    rts
!load_failed:
    lda plus4_color_attr + COL_RED
    sta TED_BORDER
    jmp !load_failed-
#endif

// plus4_huff_index_install — The Huffman string index to its RAM span.
// Exactly the index: the first page, then the rest from its end down.
plus4_huff_index_install:
    ldx #0
!phii_copy:
    lda huff_index_stage,x
    sta HUFF_INDEX_HIDDEN_BASE,x
    inx
    bne !phii_copy-
    ldx #huff_index_stage_end - huff_index_stage - $100
!phii_rest:
    lda huff_index_stage + $ff,x
    sta HUFF_INDEX_HIDDEN_BASE + $ff,x
    dex
    bne !phii_rest-
    rts
huff_index_stage:
    .segmentout [segments="Plus4HuffIndex"]
huff_index_stage_end:
.assert "The Huffman index fits its two staged pages", huff_index_stage_end - huff_index_stage <= $200, true
.assert "The Huffman index is past one page (plus4_huff_index_install)", huff_index_stage_end - huff_index_stage > $100, true
.assert "The Huffman index's stage is the index", huff_index_stage_end - huff_index_stage, huff_str_index_end - huff_str_index
.assert "The Huffman index starts its RAM span", huff_str_index == HUFF_INDEX_HIDDEN_BASE && HUFF_INDEX_HIDDEN_BASE == $dd00 && HUFF_INDEX_HIDDEN_END == $deff, true
.const PLUS4_HUFF_INDEX_TAIL_BASE = huff_str_index_end
.const PLUS4_HUFF_INDEX_TAIL_FREE = HUFF_INDEX_HIDDEN_END + 1 - huff_str_index_end
.assert "Huffman index unused tail matches remaining bytes in $DD00-$DEFF", PLUS4_HUFF_INDEX_TAIL_FREE == $200 - (huff_str_index_end - huff_str_index) && PLUS4_HUFF_INDEX_TAIL_BASE <= PLUS4_HIGH_BSS_BASE, true
.assert "Huffman index unused tail is 16 bytes ($DEF0-$DEFF)", PLUS4_HUFF_INDEX_TAIL_FREE, 16
.print "Huffman index tail free: " + PLUS4_HUFF_INDEX_TAIL_FREE + " bytes at $" + toHexString(PLUS4_HUFF_INDEX_TAIL_BASE) + "-$" + toHexString(HUFF_INDEX_HIDDEN_END)
.assert "The Huffman index install lives in the init-only tail", plus4_huff_index_install >= program_end, true

// plus4_high_bss_init — Zero-initialize $DF00-$DFFF high BSS page at boot.
// Clobbers: A, X
plus4_high_bss_init:
    lda #0
    tax
!phbi_loop:
    sta PLUS4_HIGH_BSS_BASE,x
    inx
    bne !phbi_loop-
    rts
.assert "Plus/4 high BSS zero-init fits one page", PLUS4_HIGH_BSS_SIZE, 256
.assert "Plus/4 high BSS zero-init lives in the init-only tail", plus4_high_bss_init >= program_end, true

// Cold boot vector installers (run once from entry_main before restart_entry).
generation_busy_install:
    lda #$4c
    sta generation_busy_begin_api
    sta generation_busy_tick_api
    sta generation_busy_end_api
    lda #<generation_busy_begin
    sta generation_busy_begin_api + 1
    lda #>generation_busy_begin
    sta generation_busy_begin_api + 2
    lda #<generation_busy_tick
    sta generation_busy_tick_api + 1
    lda #>generation_busy_tick
    sta generation_busy_tick_api + 2
    lda #<generation_busy_end
    sta generation_busy_end_api + 1
    lda #>generation_busy_end
    sta generation_busy_end_api + 2
    lda #0
    sta generation_busy_active_api
    rts

plus4_platform_services_install:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api
    lda #<plus4_platform_main_loop_begin
    sta platform_main_loop_begin_api + 1
    lda #>plus4_platform_main_loop_begin
    sta platform_main_loop_begin_api + 2
    lda #<plus4_platform_vector_reassert
    sta platform_vector_reassert_api + 1
    lda #>plus4_platform_vector_reassert
    sta platform_vector_reassert_api + 2
    lda #<plus4_platform_runtime_resync
    sta platform_runtime_resync_api + 1
    lda #>plus4_platform_runtime_resync
    sta platform_runtime_resync_api + 2
    jmp platform_services_mark_installed
.assert "Cold boot service installers live in the init-only tail", generation_busy_install >= program_end && plus4_platform_services_install >= program_end, true

#if HAL_PLATFORM_CATALOG_RECORDS
// MONSTER.IDX loads past the init-only tail at boot (catalog_boot_load).
catalog_init_tail_end:
.assert "MONSTER.IDX's boot buffer is past the init-only tail", catalog_init_tail_end <= CATALOG_IDX_LOAD, true
#endif

// ============================================================
// Banked runtime payload — loadable PRG at $F000.
// ============================================================
.segment RuntimeBanked
    // find_special_room only: item placement calls it with OVL.CHEST loaded
    // (the rest of special_rooms.s is in OVL.GEN, 2026-11-08).
    #import "../../../core/special_rooms_find.s"
    #define EGO_ARMOUR_SEGMENT_CUSTOM
    .macro EgoArmourSegment() {
        .segment ChestOverlay
    }
    .macro EgoArmourRestoreSegment() {
        .segment RuntimeBanked
    }
    #define EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    .macro EgoArmourDataSegment() {
        .segment ChestOverlay
    }
    .macro EgoArmourDataRestoreSegment() {
        .segment RuntimeBanked
    }
    #import "../../../core/ego_items.s"
    #undef EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    #undef EGO_ARMOUR_SEGMENT_CUSTOM
    #define DISARM_COMMAND_EXTERNAL
    #import "../../../core/trap_trigger_cold.s"
    #undef DISARM_COMMAND_EXTERNAL
    #import "../../../core/item_desc_banked.s"
    #import "../common/disk_setup_banked.s"

tramp_game_over_stash:
    lda #<$e000
    sta zp_ptr0
    lda #>$e000
    sta zp_ptr0_hi
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    jmp plus4_copy_overlay_window

tramp_game_over_restore_stash:
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #<$e000
    sta zp_ptr1
    lda #>$e000
    sta zp_ptr1_hi
    lda #OVL_DEATH
    sta current_overlay
    jmp plus4_copy_overlay_window

plus4_copy_overlay_window:
    lda #$10
    sta zp_temp0
!copy_page:
    ldy #0
!copy_byte:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !copy_byte-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dec zp_temp0
    bne !copy_page-
    rts

// Verify that the selected program disk is actually present.
// Output: carry clear = program media present, carry set = absent/wrong media.
plus4_require_program_media:
#if PLUS4_CARTRIDGE
    clc
    rts
#else
    // Does the drive open a file only the Program Disk holds? Its status after
    // the OPEN says, asked again with a fresh OPEN when a read loses its byte.
    // storage_file_exists asks the save drive: the program drive stands in.
    lda save_device
    pha
    lda program_device
    sta save_device
    lda #hal_storage_overlay_help_name_len
    ldx #<hal_storage_overlay_help_name
    ldy #>hal_storage_overlay_help_name
    jsr storage_file_exists
    pla
    sta save_device             // keeps C
    bcc !fail+
    clc
    rts
!fail:
    lda #0
    sta current_overlay
    sec
    rts
#endif

save_append_disk_detail_plus4:
    lda #$20
    jsr screen_put_char
    lda disk_error_dos0         // 0 or $ff: no DOS digits to show
    beq !no_dos+
    cmp #$ff                    // the drive never answered
    bne !dos+
!no_dos:
    lda disk_error_phase
    ora disk_error_readst
    bne !status+
    rts
!dos:                           // A = disk_error_dos0
    jsr screen_put_char
    lda disk_error_dos1
    cmp #$ff                    // only the first digit arrived
    beq !no_dos1+
    jmp screen_put_char
!no_dos1:
    rts
!status:
    lda #$24                    // $
    jsr screen_put_char
    lda disk_error_readst
    jsr screen_put_hex
    lda #$2f                    // /
    jsr screen_put_char
    lda #$24                    // $
    jsr screen_put_char
    lda disk_error_phase
    jmp screen_put_hex

banked_code_end:

.print "Banked runtime: " + (banked_code_end - $f000) + " bytes at $F000-$" + toHexString(banked_code_end)
.assert "Banked code stays below Plus/4 helper/I/O page", banked_code_end <= $FC00, true

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
// This segment produces the configured OVL.TOWN PRG (loaded from disk as OVL.TOWN).
// Labels resolve to $E000+ but bytes go to the overlay PRG file,
// not the main moria.prg. All main RAM symbols are accessible.
.segment TownOverlay
    #import "../../../core/store.s"
    #import "../../../core/ui_store.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $F000, true

// ============================================================
// Startup overlay — character creation at $E000, output to separate PRG
// ============================================================
// This segment produces the configured OVL.START PRG (loaded from disk as OVL.START).
// Used once during new game, then replaced by town/death overlays.
.segment StartupOverlay
    #import "../../../core/background_data.s"
    #import "../../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $F000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
// This segment produces the configured OVL.DEATH PRG (loaded from disk as OVL.DEATH).
// Used once at game over. Contains scoring math, death screen display,
// and high score insertion/display. KERNAL I/O stays in score_io.s.
.segment DeathOverlay
    // score_io.s lives in the death overlay on this port (same shape as C64):
    // its only callers are the death overlay and tramp_game_over_run below.
    #import "../../../core/score_io.s"
    #import "../../../core/score.s"
    #import "../../../core/ui_recall.s"
    #import "../../../core/eff_item_extended.s"
tramp_game_over_run:
    sei
    jsr plus4_bank_ram
    jsr score_calculate
    jsr plus4_bank_ram
    jsr hiscore_load
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    sei
    jsr plus4_bank_ram
    jsr hiscore_insert
    jsr plus4_bank_ram
    jsr hiscore_save
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source
    sei
    jsr plus4_bank_ram
    jsr score_death_screen
    jsr plus4_bank_ram
    rts
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $F000, true

// ============================================================
// Modal-misc overlay — winner retirement art at $E000
// ============================================================
.segment ModalMiscOverlay
winner_apply_retirement_bonus_overlay:
    lda player_data + PL_LEVEL
    cmp #41
    bcs !gold+
    clc
    adc #40
    sta player_data + PL_LEVEL
    sta zp_player_lvl
!gold:
    lda player_data + PL_GOLD_0
    clc
    adc #$90
    sta player_data + PL_GOLD_0
    lda player_data + PL_GOLD_1
    adc #$d0
    sta player_data + PL_GOLD_1
    lda player_data + PL_GOLD_2
    adc #$03
    sta player_data + PL_GOLD_2
    :GoldCapOnCarry()               // 250,000 more stops at 16,777,215
    lda player_data + PL_XP_0
    clc
    adc #$40
    sta player_data + PL_XP_0
    lda player_data + PL_XP_1
    adc #$4b
    sta player_data + PL_XP_1
    lda player_data + PL_XP_2
    adc #$4c
    sta player_data + PL_XP_2
    rts
    #import "../../../core/royal.s"
    #import "../../../core/ui_wizard.s"
wizard_prompt_clear_digits:
    lda #0
    sta wizard_num_digits
    lda #5
    sta zp_cursor_row
    lda wizard_prompt_input_col
    sta zp_cursor_col
    lda #$20
    jsr hal_screen_put_char
    lda #$20
    jsr hal_screen_put_char
    lda #5
    sta zp_cursor_row
    lda wizard_prompt_input_col
    sta zp_cursor_col
    rts

wizard_prompt_bad_value:
    lda #<wizard_bad_value_str
    ldy #>wizard_bad_value_str
    jsr msg_print_ay
    jmp wizard_prompt_clear_digits

wizard_bad_value_str:
    .text "BAD" ; .byte 0
    // Word of Destruction devastation engine: both callers live in the
    // spell overlay; resident tramp_eff_destroy_area restores OVL_SPELL.
    #import "../../../core/player_destroy_area.s"
    #import "../../../core/player_pflags_cold.s"
ovl_modal_misc_end:
.assert "Wizard prompt helpers run in OVL.MODAL", wizard_prompt_clear_digits >= $e000 && wizard_bad_value_str < ovl_modal_misc_end, true
.print "Modal-misc overlay: " + (ovl_modal_misc_end - $e000) + " bytes at $E000-$" + toHexString(ovl_modal_misc_end)
.assert "Modal-misc overlay fits in $E000-$EFFF", ovl_modal_misc_end <= $F000, true

// ============================================================
// Spell overlay — spell/prayer execution at $E000
// ============================================================
.segment SpellOverlay
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_DETECT_EFFECTS_EXTERNAL
    #define PMX_DESTROY_AREA_EXTERNAL
    #define PMX_MAP_AREA_EXTERNAL
    #define PMX_MAP_AREA_TRAMPOLINE
    #import "../../../core/player_magic_slow_runtime.s"
    #define PMU_TURN_FEEDBACK_ONLY
    #import "../../../core/player_magic_turn_banked.s"
    #undef PMU_TURN_FEEDBACK_ONLY
    #import "../../../core/player_magic_execute_overlay.s"
    #undef PMX_MAP_AREA_TRAMPOLINE
    #undef PMX_MAP_AREA_EXTERNAL
    #undef PMX_DESTROY_AREA_EXTERNAL
    #undef PMX_DETECT_EFFECTS_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
    #import "../../../core/player_magic_display.s"
    #import "../../../core/spell_effects_overlay.s"
    #import "../../../core/eff_identify_prompt_cold.s"
    #import "../../../core/eff_detect_evil_cold.s"
    #define SCROLL_P3_EXISTING_OWNER
    #define SCROLL_P3_NEW_OWNER
    #define HAL_PLATFORM_EFF_EARTHQUAKE_USE_TRAMPOLINE
    #import "../../../core/scroll_effects_p3.s"
    #undef HAL_PLATFORM_EFF_EARTHQUAKE_USE_TRAMPOLINE
    #undef SCROLL_P3_NEW_OWNER
    #undef SCROLL_P3_EXISTING_OWNER
ovl_spell_end:
.print "Spell overlay: " + (ovl_spell_end - $e000) + " bytes at $E000-$" + toHexString(ovl_spell_end)
.assert "Spell overlay fits in $E000-$EFFF", ovl_spell_end <= $F000, true

// ============================================================
// Help overlay — dedicated help modal screen at $E000
// ============================================================
.segment HelpOverlay
    #import "../../../core/ui_help_title.s"
    #import "../../../core/ui_help_data.s"
    #import "../../../core/ui_help_page2_data.s"
    #import "../../../core/ui_help.s"
    #import "../../../core/ui_equipment.s"
plus4_help_cmd_body:
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    #import "../../../core/ui_help_cmd_cold.s"
    #import "../../../core/item_drop_cold.s"
    #import "../../../core/starting_kit_cold.s"
    // Store init/restock: transition-only (new game, town re-entry), moved
    // from ovl.chest so item_spawn_cold.s and door_open_close_cold.s co-locate
    // with pick_item_type_overlay and door_pick_roll in ovl.chest.
    #import "../../../core/store_restock_overlay.s"
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $F000, true

// ============================================================
// UI overlay — low-frequency modal UI and symbol identify screens
// ============================================================
.segment UiOverlay
    #import "../../../core/ui_identify.s"
    #import "../../../core/ui_inventory.s"
    #import "../../../core/spell_names.s"
    #import "../../../core/player_magic_select_overlay.s"
    #import "../../../core/player_gain_spell_impl.s"
    #import "../../../core/player_magic_browse_cold.s"
    #import "../../../core/player_magic_learn_op.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $F000, true

// ============================================================
// Item actions overlay — low-frequency read/aim/use/refuel commands
// ============================================================
.segment ItemActionsOverlay
    #define SCROLL_P3_ROUTER_ENABLED
    #define PLAYER_RECALC_EQUIPMENT_EXTERNAL
    #import "../../../core/item_actions_overlay.s"
    #import "../../../core/item_exchange.s"
    #import "../../../core/ranged_fire.s"
    #import "../../../core/throw.s"
    #import "../../../core/player_item_commands.s"
    #import "../../../core/player_adjust_equipment_stat.s"
    #undef PLAYER_RECALC_EQUIPMENT_EXTERNAL
ovl_items_end:
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $F000, true

// ============================================================
// Dungeon generation overlay — town + dungeon generation at $E000
// ============================================================
// This segment produces the configured OVL.GEN PRG (loaded from disk as OVL.GEN).
// Loaded on demand whenever stairs are used or a new game starts.
// Shared constants and data tables stay in dungeon_data.s (main segment).
.segment DungeonGenOverlay
    #import "../../../core/special_rooms.s"
    #import "../../../core/dungeon_gen.s"
ovl_gen_end:
.assert "Special rooms run in OVL.GEN", assign_special_room >= $e000 && spawn_nest_gold < ovl_gen_end, true
.assert "find_special_room is outside the $E000 window (the CHEST-loaded picker calls it)", find_special_room >= $f000, true
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $F000, true

// ============================================================
// Chest overlay — chest open/disarm/bash handlers at $E000 (cold disk load)
// ============================================================
.segment ChestOverlay
    #import "../../../core/chest.s"
    #import "../../../core/item_spawn_cold.s"
#if PLUS4_TEST_SCRIPTED_BALROG_PRODUCT
// balrog_product_setup — Deterministic Balrog-kill fixture for scripted
// product smokes: a one-HP, permanently stunned Balrog east of the player on
// clear floor, with the player strong enough that every bump attack hits.
// Runs from level_change_generate_current under the scripted define only.
// Parks in the CHEST overlay: GEN has no room beside place_secrets.
balrog_product_setup:
    jsr item_init_floor
    jsr monster_init_table

    lda #20
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #10
    sta zp_player_y
    sta player_data + PL_MAP_Y

    // Combat-ready player: every bump attack lands and one hit kills.
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #18
    sta player_data + PL_STR_CUR
    sta zp_player_str
    lda #118
    sta player_data + PL_DEX_CUR
    lda #127
    sta player_data + PL_TOHIT
    lda #10
    sta player_data + PL_TODMG
    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + EQUIP_WEAPON
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta inv_ego + EQUIP_WEAPON
    }

    // combat_note_kill's level-100 guard reads the active roster row.
    lda #100
    sta cr_level + CREATURE_BALROG

    // Clear floor rows 9-11, cols 19-22.
    ldx #9
!bps_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
!bps_col:
    :MapWrite_ptr0_y()
    iny
    cpy #23
    bne !bps_col-
    inx
    cpx #12
    bne !bps_row-

    // Balrog in slot 0 at (21,10): one HP, stunned so it never acts.
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #CREATURE_BALROG
    sta (zp_ptr0),y
    ldy #MX_X
    lda #21
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_STUN
    lda #$ff
    sta (zp_ptr0),y

    lda #1
    sta zp_mon_count

    // Mark the Balrog tile occupied for bump-attack detection.
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    rts
#endif
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $e000) + " bytes at $E000-$" + toHexString(ovl_chest_end)
.assert "Chest overlay fits in $E000-$EFFF", ovl_chest_end <= $F000, true
.assert "irq_no_blink begins with CLD", irq_no_blink_after_cld == irq_no_blink + 1, true

// ============================================================
// Home overlay — Home inventory deposit/withdraw at $E000
// ============================================================
.segment HomeOverlay
    #import "../../../core/ui_home_text.s"
    #import "../../../core/ui_home.s"
    #import "../../../core/eff_item_p1.s"
ovl_home_end:
.print "Home overlay: " + (ovl_home_end - $e000) + " bytes at $E000-$" + toHexString(ovl_home_end)
.assert "Home overlay fits in $E000-$EFFF", ovl_home_end <= $F000, true

// ============================================================
// Storage overlay — save/load engine + disk setup UI at $E000
// ============================================================
.segment StorageOverlay
    #import "../../../core/ui_disk_setup.s"
    #import "../../../core/load_resume_reset_cold.s"
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $e000) + " bytes at $E000-$" + toHexString(ovl_storage_end)
.assert "Storage overlay fits in $E000-$EFFF", ovl_storage_end <= $F000, true

// ============================================================
// Title overlay — title art loader + renderer at $E000
// ============================================================
.segment TitleOverlay
    #import "../common/title_screen.s"
plus4_title_load_menu_ovl:
    jsr title_clear_full_screen
    jsr title_load_and_draw
    jmp plus4_title_finish_menu_ovl
plus4_title_redraw_menu_ovl:
    jsr title_clear_full_screen
    jsr title_render_data
plus4_title_finish_menu_ovl:
    jsr title_clear_below_menu
    jsr msg_init
    jsr title_show_sysinfo
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #(SCREEN_COLS - (title_menu_str_end - title_menu_str)) / 2
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jmp screen_put_string
    #import "../../../core/ui_character.s"
    #import "../../../core/player_bg_draw_cold.s"
    #import "../../../core/bash.s"
    #import "../../../core/disarm.s"
    #import "../../../core/tunnel.s"
    #import "../../../core/calc_dig_cold.s"
    #import "../../../core/player_magic_earthquake.s"
    #import "../../../core/player_magic_map.s"
ovl_title_end:
.print "Title overlay: " + (ovl_title_end - $e000) + " bytes at $E000-$" + toHexString(ovl_title_end)
.assert "Title overlay fits in $E000-$EFFF", ovl_title_end <= $F000, true
.assert "Plus/4 hot gameplay entries stay resident (< MAP_BASE / $F000-$FBFF) while cold bodies live in $E000 overlays", run_initialize < MAP_BASE && door_try_open < MAP_BASE && door_try_close < MAP_BASE && door_pick_roll < MAP_BASE && player_disarm_get_effective_chance < MAP_BASE && item_pickup < MAP_BASE && tramp_trap_trigger < MAP_BASE && trap_trigger >= $f000 && trap_trigger < banked_code_end && hal_player_recalc_pflags < MAP_BASE && player_recalc_pflags_equipment >= $e000 && player_recalc_pflags_equipment < ovl_modal_misc_end && tramp_load_resume_reset < MAP_BASE && load_resume_reset >= $e000 && load_resume_reset < ovl_storage_end && calc_dig_ability >= $e000 && calc_dig_ability < ovl_title_end && eff_earthquake >= $e000 && eff_earthquake < ovl_title_end && eff_map_area >= $e000 && eff_map_area < ovl_title_end && player_cast_spell < MAP_BASE && player_pray < MAP_BASE && pm_build_known_list_from_book < MAP_BASE && calc_spell_failure >= $e000 && calc_spell_failure < ovl_spell_end && ui_inv_select_display >= $e000 && ui_inv_select_display < ovl_ui_end && eff_wall_to_mud >= $e000 && eff_wall_to_mud < ovl_spell_end && eff_find_traps >= $e000 && eff_find_traps < ovl_spell_end && eff_destroy_traps_doors >= $e000 && eff_destroy_traps_doors < ovl_spell_end && eff_identify_prompt >= $e000 && eff_identify_prompt < ovl_spell_end && eff_detect_evil_only >= $e000 && eff_detect_evil_only < ovl_spell_end && item_spawn_level < MAP_BASE && item_spawn_level_gen >= $e000 && item_spawn_level_gen < ovl_chest_end && re_equip >= $e000 && re_equip < ovl_chest_end && roll_armour_ego >= $e000 && roll_armour_ego < ovl_chest_end && tramp_item_drop < MAP_BASE && item_drop >= $e000 && item_drop < ovl_help_end && tramp_help_cmd_body < MAP_BASE && plus4_help_cmd_body >= $e000 && plus4_help_cmd_body < ovl_help_end, true

// Cold legal modal: workspace is reserved but not emitted to disk.
.segment LegalOverlay
#import "../../../core/ui_legal.s"
#if PLUS4_CARTRIDGE
#import "legal_stream.s"
#else
#import "../../shared/legal_disk_stream.s"
#endif
legal_code_end:
.assert "Legal code stays below its modal workspace", legal_code_end <= legal_zp_save, true
.assert "Legal ZP snapshot stays below input cache", legal_zp_save + $8e <= legal_input_cache, true
.segment Default
