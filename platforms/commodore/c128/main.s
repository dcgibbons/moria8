#define HAL_PLATFORM_LEGAL_VIEWER
#importonce
#import "../../../core/zeropage.s"
#import "../../../core/store_data_defs.s"
// C128 operational layout:
//   - Bank 0 main code = $1C01-$BFFF
//   - Bank 1 map = $4000-$4EFF
//   - Bank 1 ownership manifest lives in memory128.s
//   - BASIC Stub = $1C01 (SYS 7182)
//
// MMU set to $0E at startup (System ROM in, BASIC out via MMU), then $01
// used for runtime banking (same values as C64 for common code compatibility).

// ============================================================
// Overlay segments — produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
//
// $E000 works for both C64 and C128:
//   C64:  KERNAL LOAD secondary=1 uses PRG header ($E000). VIC-II
//         bank must be restored after KERNAL serial I/O (done in
//         overlay_load_disk). Execution: $01=$35 hides KERNAL ROM.
//   C128: KERNAL LOAD secondary=1 uses PRG header ($E000). Writes
//         go to Bank 0 RAM under KERNAL ROM (same as C64). Execution:
//         $FF00=$3E hides KERNAL ROM → $E000+ = Bank 0 RAM.
//
// banked_payload runtime code is forced to start above the dungeon overlay
// footprint so overlays ($E000-$EFFF) never overlap live banked routines.
// ============================================================
// The monster catalog (docs/MONSTER_CATALOG_DESIGN.md) replaces the tiers in
// the product build. The unit tests (tests/*.s) do not import main.s and keep
// the tier roster.
#define HAL_PLATFORM_MONSTER_CATALOG
#define C128_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RUNTIME
#define PLATFORM_PRODUCT_OVERLAY_RELOAD_RESYNC
#define HOME_OVERLAY_SEPARATE
#define RECALL_VIEW_OVERLAYED
#define C128_PRODUCT_MODAL_PERSIST
#define HAL_PLATFORM_GAME_LOOP_MODAL_PERSIST
#define HAL_STORAGE_PROGRAM_MEDIA_PRESENT_EXTERNAL
#define STORAGE_STATUS_HELPER
#define PICKER_IN_CHEST_OVERLAY
#define PLAYER_RECALC_PFLAGS_EXTERNAL
#define PFLAGS_SEGMENT_CUSTOM
#import "../common/save_slot_policy.s"

.macro PflagsSegment() {
    .segment HelpOverlay
}
.macro PflagsRestoreSegment() {
    .segment Default
}

// Huffman data placement: Bank 1 $F000-$FEFF corpus region (read-only; the
// main image has no room for it). All decoder reads go through the HuffRead_*
// macros, which become mmu_safe_db_read Bank 1 thunks on this port
// (HAL_PLATFORM_HUFFMAN_DATA_AUX).
.macro HuffmanDataSegment() {
    .segment C128Bank1Huffman
}
.macro ResidentItemsSegment() {
    .segment Default
}
.macro ResidentWorldSegment() {
    .segment Default
}
.macro ResidentPlaySegment() {
    .segment C128ResidentPlay
}

// Cast/pray cores stay in the $F000 runtime bank on this platform.
.macro PlayerCastSegment() {
    .segment RuntimeBankedCode
}
.macro PlayerCastRestoreResidentSegment() {
    .segment RuntimeBankedCode
}
.macro PmHelpersSegment() {
    .segment RuntimeBankedCode
}
.macro PmHelpersRestoreSegment() {
    .segment RuntimeBankedCode
}
.macro ItemInitIdentSegment() {
    // One-shot new-game identification init runs from the cold chest overlay
    // right alongside store_init_all so cached TownOverlay can host special_rooms.s.
    // Called through tramp_item_init_identification.
    .segment ChestOverlay
}
.macro WizardGenExecSegment() {
    .segment RuntimeBankedCode
}
.macro WizardGenExecRestoreSegment() {
    .segment C128ResidentPlay
}
.macro RecallViewBodySegment() {
    .segment UiOverlay
}
.macro RecallViewBodyRestoreSegment() {
    .segment C128ResidentPlay
}
.macro ItemInitIdentRestoreSegment() {
    .segment Default
}
.macro ChestRouteSegment() {
    // Chest open pre-dispatch stays in the contiguous Bank 0 resident image
    // (< $AF00), leaving the $AF00 PLAY/PERSIST window untouched.
    .segment Default
}
.macro ChestRouteRestoreSegment() {
    .segment C128ResidentPlay
}
.const C128_MEDIA_UNKNOWN = 0
.const C128_MEDIA_PROGRAM = 1
.const C128_MEDIA_SAVE    = 2
.if (!cmdLineVars.containsKey("OVL_OUT")) {
    .error "OVL_OUT is required; generated files belong under build/"
}
.eval var OVL_OUT = cmdLineVars.get("OVL_OUT")
.segmentdef StartupOverlay    [outPrg=OVL_OUT + "/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg=OVL_OUT + "/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg=OVL_OUT + "/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef ModalMiscOverlay      [outPrg=OVL_OUT + "/ovl.modal", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg=OVL_OUT + "/ovl.gen",   start=$e000, min=$e000, max=$efff]
.const LEGAL_BASE = $e000
.const LEGAL_LIMIT = $f000
.segmentdef LegalOverlay [outPrg=OVL_OUT + "/legalui", start=$e000, min=$e000, max=$efff]
.segmentdef HelpOverlay       [outPrg=OVL_OUT + "/ovl.help",  start=$e000, min=$e000, max=$efff]
.segmentdef UiOverlay         [outPrg=OVL_OUT + "/ovl.ui",    start=$e000, min=$e000, max=$efff]
.segmentdef ItemActionsOverlay [outPrg=OVL_OUT + "/ovl.items", start=$e000, min=$e000, max=$efff]
.segmentdef DisarmOverlay     [outPrg=OVL_OUT + "/ovl.disarm", start=$e000, min=$e000, max=$efff]
.segmentdef ChestOverlay      [outPrg=OVL_OUT + "/ovl.chest", start=$e000, min=$e000, max=$efff]
.segmentdef HomeOverlay       [outPrg=OVL_OUT + "/ovl.home", start=$e000, min=$e000, max=$efff]
.segmentdef StorageOverlay    [outPrg=OVL_OUT + "/ovl.storage", start=$e000, min=$e000, max=$efff]
.segmentdef RuntimeInputData  [outPrg=OVL_OUT + "/128.input.prg", start=$0b00, min=$0b00, max=$0bff]
.segmentdef RuntimeProjectileData [outPrg=OVL_OUT + "/128.proj.prg", start=$0a80, min=$0a80, max=$0aff]
.segmentdef RuntimeCommonData [outPrg=OVL_OUT + "/128.fdisk.prg", start=$0d60, min=$0d60, max=$0fff]
.segmentdef RuntimeLowData    [outPrg=OVL_OUT + "/128.runtime.prg", start=$1000, min=$1000, max=$3fff]
// Bank 0 resident code and data before $AF00 are consolidated into Default
// (moria128.prg, $1C01..<$AF00, C128M-011). Later external segments remain
// fixed and bounds-checked independently.
.segmentdef C128ResidentPersist [outPrg=OVL_OUT + "/128.persist.prg", start=$af00, min=$af00, max=$cfff]
.segmentdef C128ResidentPlay [outPrg=OVL_OUT + "/128.play.prg", start=$af00, min=$af00, max=$cfff]
.segmentdef RuntimeBankedCode [outPrg=OVL_OUT + "/128.bank.prg", start=$f000, min=$f000, max=$feff]
.segment RuntimeBankedCode
banked_payload:
.segment Default
.segmentdef C128Bank1Huffman [outPrg=OVL_OUT + "/128.huff.prg", start=$f000, min=$f000, max=$feff]
.segmentdef C128Bank1HuffmanVector [outPrg=OVL_OUT + "/128.hvec.prg", start=$fffa, min=$fffa, max=$fffb]
// The monster catalog's Bank 1 payloads (memory128.s, C128M-007).
.segmentdef C128Bank1Catalog [outPrg=OVL_OUT + "/128.cat.prg", start=$7e60, min=$7e60, max=$9567]
.segmentdef C128Bank1CatalogNames [outPrg=OVL_OUT + "/128.cnm.prg", start=$a000, min=$a000, max=$afff]

#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
#define C128_REAL_BOOT_DIAG
#else
.const C128_REAL_BOOT_DIAG = 0
#endif

#if C128_TEST_CHARGEN_CUTPOINT
.const C128_CHARGEN_CUTPOINT = C128_TEST_CHARGEN_CUTPOINT
#else
.const C128_CHARGEN_CUTPOINT = -1
#endif

#if C128_TEST_TOWN_SELF_DUMP_TARGET
.const C128_TOWN_SELF_DUMP_TARGET = C128_TEST_TOWN_SELF_DUMP_TARGET
#else
.const C128_TOWN_SELF_DUMP_TARGET = $70
#endif

#if C128_TEST_OVERLAY_TRANSITION_DIAG
.const C128_OVERLAY_TRANSITION_DIAG = 1
#else
.const C128_OVERLAY_TRANSITION_DIAG = 0
#endif




// ============================================================
// BASIC stub at $1C01 — SYS 7182 ($1C0E)
// ============================================================
.pc = $1c01 "BASIC Stub"
    .byte $0b, $1c, $0a, $00, $9e, $37, $31, $38, $32, $00, $00, $00

.pc = $1c0e "Program"
entry:
    jmp entry_real

#if C128_TEST_TOWN_SELF_DUMP
c128_town_dump_log:
    ldx c128_town_dump_idx
    sta c128_town_dump_buf,x
    inx
    txa
    and #$1f
    sta c128_town_dump_idx
    rts

c128_town_dump_mark:
    cmp #C128_TOWN_SELF_DUMP_TARGET
    beq !hit+
    jmp c128_town_dump_log
!hit:
    jsr c128_town_dump_log
    jmp c128_town_dump_checkpoint

c128_town_dump_checkpoint:
    jsr c128_town_dump_render_vic
!hang:
    nop
    jmp !hang-

c128_town_dump_render_vic:
    lda #<$0400
    sta zp_ptr0
    lda #>$0400
    sta zp_ptr0_hi
    lda #<$d800
    sta zp_ptr1
    lda #>$d800
    sta zp_ptr1_hi
    lda #19
    sta zp_temp0
!clear_rows:
    ldx #40
!clear_cols:
    lda #$20
    ldy #0
    sta (zp_ptr0),y
    lda #1
    sta (zp_ptr1),y
    inc zp_ptr0
    bne !clr_scr_ok+
    inc zp_ptr0_hi
!clr_scr_ok:
    inc zp_ptr1
    bne !clr_col_ok+
    inc zp_ptr1_hi
!clr_col_ok:
    dex
    bne !clear_cols-
    dec zp_temp0
    bne !clear_rows-

    lda #<$0400
    sta zp_ptr0
    lda #>$0400
    sta zp_ptr0_hi
    lda #<$d800
    sta zp_ptr1
    lda #>$d800
    sta zp_ptr1_hi

    lda #<c128_town_dump_title_str
    sta zp_temp1
    lda #>c128_town_dump_title_str
    sta zp_temp2
    ldy #0
!title:
    lda (zp_temp1),y
    beq !title_done+
    jsr c128_town_dump_put_char
    iny
    bne !title-
!title_done:

    jsr c128_town_dump_next_row
    lda c128_town_dump_idx
    jsr c128_town_dump_put_hex
    lda #$20
    jsr c128_town_dump_put_char
    lda c128_town_dump_countdown
    jsr c128_town_dump_put_hex

    lda #0
    sta zp_temp0
!bc_rows:
    jsr c128_town_dump_next_row
    ldx #16
!bc_cols:
    ldy zp_temp0
    lda c128_town_dump_buf,y
    jsr c128_town_dump_put_hex
    inc zp_temp0
    dex
    bne !bc_cols-
    lda zp_temp0
    cmp #32
    bne !bc_rows-

    ldx #0
!stack_rows:
    jsr c128_town_dump_next_row
    txa
    jsr c128_town_dump_put_hex
    lda #$3a
    jsr c128_town_dump_put_char
    ldy #0
!stack_cols:
    lda $0100,x
    jsr c128_town_dump_put_hex
    inx
    iny
    cpy #16
    bne !stack_cols-
    cpx #0
    bne !stack_rows-
    rts

c128_town_dump_next_row:
    lda zp_ptr0
    clc
    adc #40
    sta zp_ptr0
    bcc !row_scr_ok+
    inc zp_ptr0_hi
!row_scr_ok:
    lda zp_ptr1
    clc
    adc #40
    sta zp_ptr1
    bcc !row_col_ok+
    inc zp_ptr1_hi
!row_col_ok:
    rts

c128_town_dump_put_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr c128_town_dump_put_nibble
    pla
    and #$0f
    jmp c128_town_dump_put_nibble

c128_town_dump_put_nibble:
    cmp #10
    bcc !digit+
    sec
    sbc #9
    jmp c128_town_dump_put_char
!digit:
    clc
    adc #$30
    jmp c128_town_dump_put_char

c128_town_dump_put_char:
    ldy #0
    sta (zp_ptr0),y
    lda #1
    sta (zp_ptr1),y
    inc zp_ptr0
    bne !put_scr_ok+
    inc zp_ptr0_hi
!put_scr_ok:
    inc zp_ptr1
    bne !put_col_ok+
    inc zp_ptr1_hi
!put_col_ok:
    rts

c128_town_dump_title_str:
    .text "BC CD STK" ; .byte 0
c128_town_dump_idx: .byte 0
c128_town_dump_countdown: .byte 8
c128_town_dump_buf:
    .fill 32, 0
#endif

// ============================================================
// Core System & UI Routines — MUST live in Safe Zone (<$C000)
// ============================================================
#import "memory128.s"
#if C128_CARTRIDGE
#import "cartridge_copy.s"
#endif
#import "hal/layout.s"
#import "hal/lifecycle_policy.s"
#import "../../../core/color.s"
#if C128_REAL_BOOT_DIAG
// Diag variants exclude the sound module: scenarios verify no audio, and
// the guard instrumentation needs the Default bytes. Stubs keep the SFX
// call sites linkable; all entry points preserve X, Y like the real ones.
.const SFX_NONE     = $ff
.const SFX_BUMP     = $00
.const SFX_HIT      = $01
.const SFX_MISS     = $02
.const SFX_PICKUP   = $03
.const SFX_DEATH    = $04
.const SFX_LEVELUP     = $05
.const SFX_SPELL      = $06
.const SFX_SPELL_FAIL = $07
.const SFX_HUNGER_WARN  = $08
.const SFX_HUNGER_FAINT = $09
sound_init:
hal_sound_update:
    rts
.label hal_sound_init = sound_init
.label hal_sound_stop = sound_init
.label sound_play = sound_init
.label hal_sound_play = sound_init
#else
#import "../../../core/sound.s"
#endif
#import "config128.s"
#import "screen_vdc.s"

// Bootstrap — sets up MMU and processor port, jumps to main code
entry_real:
    sei
    cld
    ldx #$ff
    txs

    // Hardware Quiet Down — Acknowledge and Clear
    lda #$7f
    sta $dc0d               // CIA1 Interrupt Control Register: disable all
    sta $dd0d               // CIA2 Interrupt Control Register: disable all
    lda $dc0d               // Clear CIA1 ICR
    lda $dd0d               // Clear CIA2 ICR

    lda #$ff
    sta zp_screen_editor_mode  // Screen Editor: 80-col mode

    // Enable 2MHz mode on the C128 (set D030 bit0 while preserving other flags)
    lda $d030
    ora #$01
    sta $d030

    // Mirror KERNAL vectors/stubs into RAM underneath ROM ($FF05-$FFFF)
    // Skipping $FF00-$FF04 to avoid mid-loop MMU bank-switching.
    lda #$00                // Bank 15 (KERNAL + I/O)
    sta $ff00
    ldx #5
!mirror:
    lda $ff00,x
    sta $ff00,x
    inx
    bne !mirror-
    lda #$3E                // Restore All-RAM
    sta $ff00

    // --- Patch KERNAL JMP table in RAM ---
    // Read original targets from ROM stubs and patch stubs to point to our safe wrappers.
    // This allows game code to call JSR $FFxx and have the wrapper manage the MMU.
    
    lda #$4C                    // JMP absolute
    sta $ffb7                   // READST
    sta $ffba                   // SETLFS
    sta $ffbd                   // SETNAM
    sta $ffc0                   // OPEN
    sta $ffc3                   // CLOSE
    sta $ffc6                   // CHKIN
    sta $ffc9                   // CHKOUT
    sta $ffcc                   // CLRCHN
    sta $ffcf                   // CHRIN
    sta $ffd2                   // CHROUT
    sta $ffd5                   // LOAD

    // FFB7 READST
    lda #<w_readst
    sta $ffb8
    lda #>w_readst
    sta $ffb9
    // FFBA SETLFS
    lda #<w_setlfs
    sta $ffbb
    lda #>w_setlfs
    sta $ffbc
    // FFBD SETNAM
    lda #<w_setnam
    sta $ffbe
    lda #>w_setnam
    sta $ffbf
    // FFC0 OPEN
    lda #<w_open
    sta $ffc1
    lda #>w_open
    sta $ffc2
    // FFC3 CLOSE
    lda #<w_close
    sta $ffc4
    lda #>w_close
    sta $ffc5
    // FFC6 CHKIN
    lda #<w_chkin
    sta $ffc7
    lda #>w_chkin
    sta $ffc8
    // FFC9 CHKOUT
    lda #<w_chkout
    sta $ffca
    lda #>w_chkout
    sta $ffcb
    // FFCC CLRCHN
    lda #<w_clrchn
    sta $ffcd
    lda #>w_clrchn
    sta $ffce
    // FFCF CHRIN
    lda #<w_chrin
    sta $ffd0
    lda #>w_chrin
    sta $ffd1
    // FFD2 CHROUT
    lda #<w_chrout
    sta $ffd3
    lda #>w_chrout
    sta $ffd4
    // FFD5 LOAD
    lda #<w_load
    sta $ffd6
    lda #>w_load
    sta $ffd7

    // Save original hardware IRQ/NMI vectors before patching RAM copies.
    lda $fffe
    sta kernal_hw_irq_vec_lo
    lda $ffff
    sta kernal_hw_irq_vec_hi
    lda $fffa
    sta kernal_hw_nmi_vec_lo
    lda $fffb
    sta kernal_hw_nmi_vec_hi

    // Runtime IRQ/NMI vectors are installed only after preload completes.
    // KERNAL LOADs during runtime/tier/overlay preload need the KERNAL
    // interrupt regime; installing the all-RAM bridge here can send KERNAL
    // disk I/O through the runtime IRQ handler.
    // Patch hardware RESET vector ($FFFC/$FFFD) in RAM for All-RAM safety.
    lda #<exit_trampoline
    sta $fffc
    lda #>exit_trampoline
    sta $fffd

    :MachineRestoreDefault()
    jmp entry_main

// ============================================================
// Safe KERNAL Wrappers
// Each wrapper switches to MMU_NORMAL, calls real target,
// then restores MMU_ALL_RAM. Flags (Carry!) are preserved via PHP/PLP.
// ============================================================
// KERNAL calls now use the Official Jump Table ($FF81-$FFF5) safely in Bank 15.

c128_wrapper_saved_a: .byte 0
c128_wrapper_saved_p: .byte 0

.macro C128KernalJumpTableWrapper(target) {
    php
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    pla
    tay
    pla
    tax
    pla
    .if (target == $ffc3) {
        // CLOSE with carry set leaves a disk command channel (SA 15) open in
        // the drive, and EnterKernal's compare sets it: a reread of channel
        // 15 then went on mid-message. Close it in the drive, as C64 does.
        clc
    }
    jsr target
    php
    pha
    :ExitKernal()
    jmp c128_wrapper_finish
}

// c128_wrapper_finish — restore KERNAL result flags while preserving caller I-bit
// Stack on entry (top-first): result A, KERNAL P, caller P
c128_wrapper_finish:
    pla
    sta c128_wrapper_saved_a
    pla
    sta c128_wrapper_saved_p
    pla
    and #$04
    pha
    lda c128_wrapper_saved_p
    and #$fb
    sta c128_wrapper_saved_p
    pla
    ora c128_wrapper_saved_p
    pha
    lda c128_wrapper_saved_a
    plp
    rts

// READST / SETLFS / SETNAM / OPEN / CLOSE / CHKIN / CHKOUT / CLRCHN / CHRIN / CHROUT
w_readst:
    :C128KernalJumpTableWrapper($ffb7)
w_setlfs:
    :C128KernalJumpTableWrapper($ffba)
w_setnam:
    :C128KernalJumpTableWrapper($ffbd)
w_open:
    :C128KernalJumpTableWrapper($ffc0)
w_close:
    :C128KernalJumpTableWrapper($ffc3)
w_chkin:
    :C128KernalJumpTableWrapper($ffc6)
w_chkout:
    :C128KernalJumpTableWrapper($ffc9)
w_clrchn:
    :C128KernalJumpTableWrapper($ffcc)
w_chrin:
    :C128KernalJumpTableWrapper($ffcf)
w_chrout:
    :C128KernalJumpTableWrapper($ffd2)
// LOAD
w_load:
    stx c128_load_arg_x
    sty c128_load_arg_y
#if C128_REAL_BOOT_DIAG
    // Begin before the php/pha so the $54 check at the end compares
    // against the same stack depth (entry SP).
    jsr c128_stack_guard_begin
    .byte $51
#endif
    php
    pha
    :EnterKernal()
#if C128_REAL_BOOT_DIAG
    ldx #$52
    stx c128_stack_guard_stage
    jsr c128_stack_guard_snapshot_banking
#endif
    pla
    ldx c128_load_arg_x
    ldy c128_load_arg_y
    jsr $ffd5
#if C128_REAL_BOOT_DIAG
    ldx #$53
    stx c128_stack_guard_stage
    jsr c128_stack_guard_snapshot_banking
#endif
    php
    pha
    :ExitKernal()
    pla
    sta c128_wrapper_saved_a
    pla
    sta c128_wrapper_saved_p
    pla
    and #$04
    pha
    lda c128_wrapper_saved_p
    and #$fb
    sta c128_wrapper_saved_p
    pla
    ora c128_wrapper_saved_p
    pha
    lda c128_wrapper_saved_a
    plp
#if C128_REAL_BOOT_DIAG
    // Keep LOAD's A/X/Y and carry for the caller: the checks below clobber
    // them. Saved in memory, not on the stack, so the $54 check still sees
    // the entry SP.
    sta c128_wrapper_saved_a
    stx c128_load_arg_x
    sty c128_load_arg_y
    php
    pla
    sta c128_wrapper_saved_p
    jsr c128_stack_guard_check
    .byte $54
    jsr c128_stack_guard_snapshot_banking
    jsr c128_stack_guard_snapshot_return
    lda c128_wrapper_saved_p
    pha
    ldx c128_load_arg_x
    ldy c128_load_arg_y
    lda c128_wrapper_saved_a
    plp
#endif
    rts

// c128_save_stream_chunk / c128_load_stream_chunk
// Execute from low resident RAM while KERNAL ROM is visible. The C128 persist
// save/load code stages bytes in Bank 0 RAM first, then calls these helpers so
// KERNAL mode is entered once per chunk rather than once per byte.
c128_save_stream_chunk:
    :EnterKernal()
    lda #0
    sta save_chunk_idx
!stream_loop:
    ldx save_chunk_idx
    cpx save_chunk_len
    bcs !stream_done+
    lda save_stage_buf,x
    jsr $ffd2                   // CHROUT
    jsr $ffb7                   // READST
    and #$03
    beq !stream_ok+
    lda #1
    sta save_io_error
!stream_ok:
    inc save_chunk_idx
    jmp !stream_loop-
!stream_done:
    :ExitKernal()
    rts

c128_load_stream_chunk:
    :EnterKernal()
    lda #0
    sta save_chunk_idx
!stream_loop:
    ldx save_chunk_idx
    cpx save_chunk_len
    bcs !stream_done+
    jsr $ffcf                   // CHRIN
    ldx save_chunk_idx
    sta save_stage_buf,x
    jsr $ffb7                   // READST
    beq !stream_ok+
    sta save_chunk_status
    lda #1
    sta save_io_error
    inc save_chunk_idx
    lda save_chunk_idx
    sta save_chunk_len
    jmp !stream_done+
!stream_ok:
    inc save_chunk_idx
    jmp !stream_loop-
!stream_done:
    :ExitKernal()
    rts

// safe_irq and safe_nmi have been replaced by Common RAM trampolines
// mmu_common_irq and mmu_common_nmi (see memory128.s).

// kernal_load_safe — KERNAL LOAD wrapper for C128
// Reinstalls keyboard stub on exit. Callers manage MMU.
kernal_load_safe:
    php
    :EnterKernal()
    jsr $ffd5
    php
    pha
    :ExitKernal()
    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303
    jmp c128_wrapper_finish

chrin_keyboard_stub:
    lda #0
    clc
    rts

// c128_restore_runtime_vectors — Reassert the all-RAM IRQ/NMI and CHRIN stubs.
// Use this on long-lived runtime paths that do not need the full helper reinstall.
c128_restore_runtime_state_core:
    :MachineRestoreAllRam()
    // KERNAL-visible paths may leave the CPU in 1 MHz mode. Gameplay and
    // generation use the VDC and are safe at the C128's 2 MHz rate.
    lda $d030
    ora #$01
    sta $d030
    lda #<mmu_common_irq
    sta $fffe
    lda #>mmu_common_irq
    sta $ffff
    lda #<mmu_common_nmi
    sta $fffa
    lda #>mmu_common_nmi
    sta $fffb
    lda #<exit_trampoline
    sta $fffc
    lda #>exit_trampoline
    sta $fffd
    lda #<mmu_common_irq
    sta $0314
    lda #>mmu_common_irq
    sta $0315
    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303
    lda #$ff
    sta zp_screen_editor_state
    rts

c128_restore_runtime_vectors:
    php
    sei
    jsr c128_restore_runtime_state_core
    plp
    rts

// Reassert runtime-owned low/common RAM state after KERNAL-visible work.
// Multiple public entry labels resolve to the same implementation so callers
// can keep their semantic name without paying extra trampoline hops.
c128_restore_runtime_state:
c128_restore_runtime_guards:
c128_return_to_runtime_after_kernal:
    pha
    txa
    pha
    tya
    pha
    php
    sei
    :MachineRestoreAllRam()
    jsr init_common_mmu_helpers
    jsr c128_vdc_reassert_mode
    plp
    pla
    tay
    pla
    tax
    pla
    rts

hal_platform_character_sheet_begin:
    jsr c128_restore_runtime_guards
#if C128_TEST_SCRIPTED_INPUT
    lda #1
    sta c128_test_summary_seen
    inc c128_test_summary_count
#endif
    rts

hal_overlay_post_reload:
    jsr hal_platform_runtime_resync
    lda #MMU_ALL_RAM
    sta hal_memory_mmu_config_register
    sei
    lda #BANK_NO_KERNAL
    sta hal_memory_cpu_port
    rts

hal_platform_item_action_restore_bank:
    pha
    lda #MMU_ALL_RAM
    sta hal_memory_mmu_config_register
    lda #BANK_NO_ROMS
    sta hal_memory_cpu_port
    pla
    rts

platform_services_install128:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api

    lda #<c128_restore_runtime_vectors
    sta platform_main_loop_begin_api + 1
    lda #>c128_restore_runtime_vectors
    sta platform_main_loop_begin_api + 2

    lda #<c128_restore_runtime_vectors
    sta platform_vector_reassert_api + 1
    lda #>c128_restore_runtime_vectors
    sta platform_vector_reassert_api + 2

    lda #<c128_restore_runtime_guards
    sta platform_runtime_resync_api + 1
    lda #>c128_restore_runtime_guards
    sta platform_runtime_resync_api + 2

    jmp platform_services_mark_installed

// safe_setbnk — SETBNK ($FF68) wrapper for C128
// Temporarily enables KERNAL ROM, calls real SETBNK, restores MMU.
// $FF68 is in the banked code range ($F000-$FFB6) so it can't be
// patched via the JMP table — call this routine directly instead.
safe_setbnk:
    php
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    pla
    tay
    pla
    tax
    pla
    jsr $ff68
    php
    pha
    :ExitKernal()
    jmp c128_wrapper_finish

c128_restore_vdc_rom_font:
    pha
    txa
    pha
    tya
    pha
    :EnterKernal()
    jsr $ff62                   // C128 JDLCHR: reload standard VDC charset
    :ExitKernal()
    pla
    tay
    pla
    tax
    pla
    rts

// Exit trampoline — MUST live below $A000
exit_trampoline:
    lda #0
    sta $d418
    sei
#if C128_CARTRIDGE
    // Park Magic Desk 128 on bank 0 and clear top-common before hardware reset
    // so the C128 boot vector sees the cartridge autostart header at $8000.
    sta CART_REG_BANK
    sta $d506
#endif
    // Restore full ROM map before handing control back to ROM.
    lda #$00
    sta $ff00
    lda #BANK_ALL_ROM
    sta $01

    // Native C128 warm-start paths proved unstable after game runtime state
    // mutation. Use the hardware reset vector for deterministic return.
    // This is equivalent to a soft reboot to BASIC.
    jmp ($fffc)
exit_trampoline_end:



// ============================================================
// Critical trampolines — pin these near program start so they
// can never drift into the $D000 I/O hole.
// ============================================================
tramp_player_create:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$71
    jsr c128_town_dump_mark
#endif
#if !C128_TEST_SKIP_PLAYER_CREATE_OVERLAY
    lda #1                      // OVL_STARTUP
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    sta c128_tramp_player_create_overlay_req
#endif
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_begin
    .byte $31
#endif
    jsr overlay_load
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_check
    .byte $32
#endif
    bcc !tpc_loaded+
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
    brk
#endif
    jmp entry_main
!tpc_loaded:
#if !C128_TEST_SKIP_PLAYER_CREATE_GUARDS
    jsr c128_restore_runtime_guards
#endif
#endif
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_begin
    .byte $33
#endif
#if !C128_TEST_SKIP_PLAYER_CREATE_CALL
    lda #1
    sta c128_startup_overlay_executing
    jsr player_create
tramp_player_create_return_site:
    lda #0
    sta c128_startup_overlay_executing
#endif
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_check
    .byte $33
#endif
    jsr c128_restore_runtime_guards
tramp_game_over_disk_setup_failed:
tramp_game_over_prepare:
    rts

tramp_game_over:
tramp_game_over_run:
    lda death_source_saved
    sta zp_death_source

    // 1. Resolve death source text while tier data still at $E000
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !tgo_load_overlay+
    lda zp_death_source
    cmp #DEATH_ALIVE
    beq !tgo_load_overlay+
    cmp #DEATH_CHEST_NEEDLE         // Special sources ($F7-$FF) don't need name
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name

!tgo_load_overlay:
    // 2. Load death overlay at $0400
    lda #3                      // OVL_DEATH
    jsr overlay_load
    bcc !tgo_loaded+
    jmp entry_main
!tgo_loaded:
    jsr c128_restore_runtime_guards

    // 3. Calculate score
    jsr score_calculate

    // 4. Load high scores from disk (needs KERNAL-visible ROM; shares CREATURE_BASE with item_cat_buf)
#if !C128_CARTRIDGE
    lda #0
    sta icr_cache_valid
#endif
    php
    sei
    lda #$ff
    sta zp_screen_editor_state
    lda #$0e                    // MMU_NORMAL
    sta $ff00
    lda #$37                    // BANK_ALL_ROM
    sta $01
    jsr hiscore_load
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    jsr c128_vdc_reassert_mode
    plp

    // 5. Insert/save only for non-wizard characters
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !tgo_skip_hiscore+
    jsr hiscore_insert

    // 6. Save high scores to disk (needs KERNAL-visible ROM)
    php
    sei
    lda #$ff
    sta zp_screen_editor_state
    lda #$0e                    // MMU_NORMAL
    sta $ff00
    lda #$37                    // BANK_ALL_ROM
    sta $01
    jsr hiscore_save
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    jsr c128_vdc_reassert_mode
    plp
!tgo_skip_hiscore:
    lda death_source_saved
    sta zp_death_source

    // 7. Display death screen (death overlay code at $E000)
    jmp score_death_screen

tramp_winner_royal:
    jsr disk_prompt_game
    lda #hal_storage_modal_misc_name_len
    ldx #<hal_storage_modal_misc_name
    ldy #>hal_storage_modal_misc_name
    jsr asset_load_required     // asks for the program disk until it loads
    lda #0
    sta current_overlay
    jmp royal_screen

winner_apply_retirement_bonus:
    :C128OverlayComputeTrampoline(11, winner_apply_retirement_bonus_storage)

tramp_store_init_all:
    lda #10                     // C128_CHEST_OVERLAY_ID: store maintenance (cold)
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_begin
    .byte $34
#endif
    jsr overlay_load
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_check
    .byte $35
#endif
    bcc !tsia_loaded+
    jmp entry_main
!tsia_loaded:
    jsr c128_restore_runtime_guards
#if C128_REAL_BOOT_DIAG
    ldx #$36                    // stage marker: tail call, no matching check
    stx c128_stack_guard_stage
#endif
    jmp store_init_all

tramp_store_enter:
    lda zp_store_idx
    cmp #STORE_HOME
    beq !tse_home+
    lda #2                      // OVL_TOWN
    jsr overlay_load
    bcs !tse_fail+
    jsr c128_restore_runtime_guards
    jmp store_enter
!tse_home:
    lda #11                     // C128_HOME_OVERLAY_ID: home UI (cold)
    jsr overlay_load
    bcs !tse_fail+
    jsr c128_restore_runtime_guards
    jmp home_enter
!tse_fail:
    jmp entry_main

#if C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY
test_expect_screen_string:
    sta test_expect_row
    stx test_expect_col
    lda test_expect_row
    sta zp_cursor_row
    lda test_expect_col
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldy #0
!tes_loop:
    lda (zp_ptr0),y
    beq !tes_ok+
    stx test_expect_save_x
    ldx #31
    jsr vdc_read_reg
    cmp (zp_ptr0),y
    bne !tes_fail+
    ldx test_expect_save_x
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
test_expect_save_x: .byte 0

.encoding "screencode_mixed"
test_inventory_title_str: .text "Inventory" ; .byte 0
test_beginner_book_str:   .text "Spellbook Beginners-Magick" ; .byte 0
test_mage_book_title_str: .text "Mage Book" ; .byte 0
test_magic_missile_str:   .text "Magic Missile" ; .byte 0
// The cast list shows learned spells only (as Umoria); a new mage knows one.
test_cast_one_spell_str:  .text "Cast which? (a-a, esc)" ; .byte 0

#if C128_TEST_SCRIPTED_BOOK_OVERLAY
test_assert_book_overlay:
    lda #<test_inventory_title_str
    sta zp_ptr0
    lda #>test_inventory_title_str
    sta zp_ptr0_hi
    lda #0
    ldx #35
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

    jmp c128_test_book_overlay_pass_sym
!book_fail:
    jmp c128_test_book_overlay_fail_sym
#endif

#if C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY
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

    jmp c128_test_spell_list_overlay_pass_sym
!list_fail:
    jmp c128_test_spell_list_overlay_fail_sym
#endif
#endif

#if C128_TEST_SCRIPTED_INPUT
c128_test_town_fail_sym:
    brk
#elif C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SCROLL_SELECTOR
c128_test_spell_fail_no_cast_sym:
    brk
c128_test_spell_fail_level_sym:
    brk
c128_test_spell_fail_known_sym:
    brk
c128_test_spell_fail_validate_sym:
    brk
#if C128_TEST_SCRIPTED_SPELL_CANCEL
c128_test_spell_fail_roll_sym:  // the cancel build fails on a fizzle
    brk
#endif
c128_test_spell_fail_cancel_sym:
    brk
#if C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER
c128_test_spell_script_exhausted_sym:
    brk
#endif
#if !C128_TEST_SCRIPTED_SPELL && !C128_TEST_SCRIPTED_PRAYER
c128_test_spell_pass_sym:
    brk
#endif
#if C128_TEST_SCRIPTED_SPELL_CANCEL
c128_test_spell_cancel_pass_sym:
    brk
#endif
#if C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY
c128_test_book_overlay_fail_sym:
    brk
c128_test_book_overlay_pass_sym:
    brk
#endif
#if C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY
c128_test_spell_list_overlay_fail_sym:
    brk
c128_test_spell_list_overlay_pass_sym:
    brk
#endif
#if C128_TEST_SCRIPTED_SCROLL_SELECTOR
c128_test_scroll_selector_fail_sym:
    brk
c128_test_scroll_selector_pass_sym:
    brk
#endif
#elif C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
c128_test_chest_open_pass_sym:
    jmp c128_test_chest_open_pass_sym   // Spin: the socket harness polls PC
#elif C128_TEST_SCRIPTED_EXCHANGE_PRODUCT
c128_test_exchange_pass_sym:
    jmp c128_test_exchange_pass_sym     // Spin: the socket harness polls PC
#endif
#if C128_CACHE_TEST_SKIP_TIER
c128_test_partial_cache_fail_sym:
    brk
#endif
#if C128_CACHE_TEST_SKIP_OVERLAY
c128_test_overlay_cache_fail_sym:
    brk
#endif

#if C128_TEST_TITLE_ART_CONTENT
c128_test_title_art_fail_sym:
    brk
c128_test_title_art_pass_sym:
    brk
// The failed check and its stage, for the monitor log (the stack guard's
// bytes until 2026-11-13: its 300 B of guard code, never called here, took
// this build past $6000).
c128_test_title_art_fail_code: .byte 0
c128_test_title_art_substage:  .byte 0
#endif
#if C128_TEST_OVERLAY_TRANSITION_DIAG
c128_overlay_transition_fail_sym:
    brk
c128_overlay_transition_pass_sym:
    nop
    jmp c128_overlay_transition_pass_sym
#endif
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
// Single shared fail trap. Guards jump here with the stage id already in
// c128_stack_guard_stage/substage; the harness breaks at this one address
// and reports the stage from memory. The per-stage stub table + cmp-chain
// dispatcher it replaces cost ~780 Default bytes the diag variant needs.
c128_diag_fail_sym:
    nop
    jmp c128_diag_fail_sym
.label c128_diag_fail_default = c128_diag_fail_sym
#endif

tramp_ui_enter:
    sei
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    lda #$34                    // BANK_NO_ROMS
    sta $01
    rts

tramp_ui_exit:
    lda #$36                    // BANK_NO_BASIC
    sta $01
    lda #$3e                    // MMU_ALL_RAM
    sta $ff00
    jsr c128_restore_runtime_guards
    cli
    rts

.macro C128UIBankedDisplayTrampoline(target) {
    jsr tramp_ui_enter
    jsr target
    jmp tramp_ui_exit
}

#define C128_PRODUCT_SOUND_UPDATE_FROM_INPUT
#import "input128.s"

.const C128_DUNGEON_GEN_OVERLAY_ID = 4
.const C128_HELP_OVERLAY_ID = 5
.const C128_UI_OVERLAY_ID = 6
.const C128_ITEMS_OVERLAY_ID = 7
// C128 does not use the common OVL_SPELL slot; spell execution lives in other
// C128 payloads. Overlay ID 8 is the cached direct-disarm overlay.
.const C128_DISARM_OVERLAY_ID = 8
// The chest overlay keeps the shared OVL_CHEST ID (10), declared here because
// the common overlay loader (and its OVL_CHEST const) is imported after the
// trampoline block. C128 keeps it cold: no Bank 1 cache slot, boot preload
// skips it, and its ready-mask bits stay clear so overlay_load always falls
// through to the disk path.
.const C128_CHEST_OVERLAY_ID = 10
.assert "Store maintenance trampolines load the chest overlay (ID 10)", C128_CHEST_OVERLAY_ID, 10
.const C128_HOME_OVERLAY_ID = 11
.assert "Home trampoline loads the home overlay (ID 11)", C128_HOME_OVERLAY_ID, 11
.const C128_STORAGE_OVERLAY_ID = 12
.assert "Storage trampoline loads the storage overlay (ID 12)", C128_STORAGE_OVERLAY_ID, 12
.const RECALL_VIEW_OVL = C128_UI_OVERLAY_ID

.macro C128UIOverlayDisplayTrampoline(target) {
    jsr tramp_ui_enter
    lda #C128_UI_OVERLAY_ID
    jsr overlay_load
    bcs !done+
    jsr target
!done:
    jmp tramp_ui_exit
}

#import "../../../core/item_defs.s"
#import "legal.s"

tramp_ui_help_display:
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
    lda #<help_pages
    sta help_pages_src_lo
    lda #>help_pages
    sta help_pages_src_hi
    jsr ui_help_display
!done:
    jmp tramp_ui_exit

tramp_ui_ui_overlay_patch_target:
    sta !ui_target+ + 1
    stx !ui_target+ + 2
tramp_ui_ui_overlay_common:
    jsr tramp_ui_enter
    lda #C128_UI_OVERLAY_ID
    jsr overlay_load
    bcs !done+
!ui_target:
    jsr ui_char_display
!done:
    jmp tramp_ui_exit

tramp_ui_inv_select_display:
    lda #<ui_inv_select_display
    ldx #>ui_inv_select_display
tramp_ui_inv_common:
    sta !inv_target+ + 1
    stx !inv_target+ + 2
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
!inv_target:
    jsr ui_inv_display
!done:
    jmp tramp_ui_exit

tramp_ui_equip_select_display:
    lda #<ui_equip_select_display
    ldx #>ui_equip_select_display
tramp_ui_equip_common:
    sta !equip_target+ + 1
    stx !equip_target+ + 2
    jsr tramp_ui_enter
    lda #C128_HELP_OVERLAY_ID
    jsr overlay_load
    bcs !done+
!equip_target:
    jsr ui_equip_display
!done:
    jsr tramp_ui_exit
    ldx c128_equip_return_overlay
    beq !equip_ret_done+
    lda #0
    sta c128_equip_return_overlay
    txa
    jsr overlay_load
    jmp tramp_ui_exit
!equip_ret_done:
    rts

c128_equip_return_overlay: .byte 0
c128_storage_ret_a:        .byte 0
c128_storage_arg_a:        .byte 0

tramp_item_takeoff:
    lda #C128_STORAGE_OVERLAY_ID
    sta c128_equip_return_overlay
    lda #<item_takeoff
    ldx #>item_takeoff
    bne c128_storage_cmd_run

c128_storage_piw_dispatch:
    ldy #C128_STORAGE_OVERLAY_ID
    sty piw_return_overlay
c128_storage_cmd_run:
    sta !scmd_target+ + 1
    stx !scmd_target+ + 2
    lda #C128_STORAGE_OVERLAY_ID
    jsr overlay_load
    bcs !scmd_fail+
    jsr c128_restore_runtime_guards
    sei
    lda $01
    pha
    :BankOutKernal()
!scmd_target:
    jsr item_wear
    pla
    sta $01
    ldy #0
    sty piw_return_overlay
    sty c128_equip_return_overlay
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts
!scmd_fail:
    lda #0
    sta piw_return_overlay
    sta c128_equip_return_overlay
    clc
    rts

c128_target_ovl: .byte 0

hal_player_recalc_pflags:
    ldx #<player_recalc_pflags_equipment
    ldy #>player_recalc_pflags_equipment
    jmp c128_call_help_preserve_ovl

re_equip_entry:
    ldx #<re_equip
    ldy #>re_equip
    jmp c128_call_storage_preserve_ovl

c128_call_gen_preserve_ovl:
    pha
    lda #C128_DUNGEON_GEN_OVERLAY_ID
    bne c128_call_ovl_preserve_common

c128_call_help_preserve_ovl:
    pha
    lda #C128_HELP_OVERLAY_ID
    bne c128_call_ovl_preserve_common

c128_call_storage_preserve_ovl:
    pha
    lda #C128_STORAGE_OVERLAY_ID
c128_call_ovl_preserve_common:
    sta c128_target_ovl
    pla
    sta c128_storage_arg_a
    stx !ovl_target+ + 1
    sty !ovl_target+ + 2
    php
    lda zp_temp0
    pha
    lda current_overlay
    pha
    cmp c128_target_ovl
    beq !ovl_loaded+
    lda c128_target_ovl
    jsr overlay_load
    jsr c128_restore_runtime_guards
!ovl_loaded:
    lda #MMU_ALL_RAM
    sta $ff00
    tsx
    lda $0102,x
    sta zp_temp0
    lda c128_storage_arg_a
!ovl_target:
    jsr re_equip
    sta c128_storage_ret_a
    pla
    beq !ovl_no_restore+
    cmp c128_target_ovl
    beq !ovl_no_restore+
    jsr overlay_load
    jsr c128_restore_runtime_guards
!ovl_no_restore:
    pla
    sta zp_temp0
    lda #MMU_ALL_RAM
    sta $ff00
    plp
    lda c128_storage_ret_a
    rts

.macro C128OverlayComputeTrampoline(overlay_id, target) {
    lda #overlay_id
    jsr overlay_load
    bcs !done+
    jsr c128_restore_runtime_guards
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr target
    pla
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    cli
!done:
    rts
}

.macro C128BankedComputeTrampoline(target) {
    sei
    lda $01
    pha
    :BankOutKernal()
    jsr target
    pla
    sta $01
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts
}

.macro C128BankedPreserveATrampoline(target) {
    pha
    sei
    :BankOutKernal()
    pla
    jsr target
    jmp tramp_sr_epilogue
}

.macro C128BankedPreserveAReturnTrampoline(target) {
    ldx #<target
    ldy #>target
    jmp c128_call_storage_preserve_ovl
}

.macro C128BankedPreserveFlagsTrampoline(target) {
    ldx #<target
    ldy #>target
    jmp c128_call_gen_preserve_ovl
}

.macro C128BankedSharedEpilogueTrampoline(target) {
    ldx #<target
    ldy #>target
    jmp c128_call_gen_preserve_ovl
}

// tramp_ego_get_ac_bonus — Get ego AC bonus from resident Bank 0 table.
// Keep this inline on C128 so resident items does not carry a separate helper.
tramp_ego_get_ac_bonus:
    and #EGO_ID_MASK
    cmp #EGO_RESIST
    bcs !egab_zero+
    tax
    lda ego_ac_bonus,x
    rts
!egab_zero:
    lda #0
    rts

.macro C128BankedStatusTrampoline(target) {
    php
    sei
    lda #$35                    // BANK_NO_KERNAL (I/O visible)
    sta $01
    jsr target
    jsr c128_restore_runtime_guards
    plp
    rts
}

// title_show_sysinfo — trampoline to TownOverlay routine at $E000+.
title_show_sysinfo:
    :C128OverlayComputeTrampoline(2, title_show_sysinfo_banked)

tsi_krev_cached: .byte 0
.const TITLE_MENU_ROW_C128 = 18
.const TITLE_CLEAR_FIRST_ROW_C128 = TITLE_MENU_ROW_C128 + 2
.const TITLE_CLEAR_LAST_ROW_C128 = SCREEN_ROWS - 3
.const TITLE_CLEAR_AFTER_LAST_ROW_C128 = TITLE_CLEAR_LAST_ROW_C128 + 1

title_clear_full_screen:
    ldx #0
!tcf_loop:
    txa
    jsr screen_clear_row
    inx
    cpx #SCREEN_ROWS
    bcc !tcf_loop-
    rts

title_clear_below_menu:
    ldx #TITLE_CLEAR_FIRST_ROW_C128
!tcb_loop:
    txa
    jsr screen_clear_row
    inx
    cpx #TITLE_CLEAR_AFTER_LAST_ROW_C128
    bcc !tcb_loop-
    rts

c128_prepare_cache_loading_screen:
    lda c128_startup_preload_display
    bne !done+
    lda #1
    sta zp_screen_editor_state
    jsr hal_screen_clear
#if HAL_PLATFORM_MONSTER_CATALOG
    lda #7                      // 12 less the four tiers and STARTUP
#else
    lda #12
#endif
    sta c128_load_progress_total
    lda #0
    sta c128_load_progress_count
    jsr c128_render_load_progress
!done:
    rts

c128_prepare_startup_loading_screen:
    jsr screen_clear_for_font_restore
    jsr c128_restore_vdc_rom_font
    jsr hal_screen_clear
    // Total = 9 startup files + 13 cache files (4 tiers + 9 overlays);
    // with the monster catalog, 11 startup files (128.cat, 128.cnm) + 8
    // overlays (no tiers, no STARTUP). c128_cache_enabled lives in Default
    // RAM (moria128.prg, C128M-011), and keeping the count static avoids coupling
    // preload initialization to later state.
#if HAL_PLATFORM_MONSTER_CATALOG
    lda #19
#else
    lda #22
#endif
!total_ready:
    sta c128_load_progress_total
    lda #0
    sta c128_load_progress_count
    lda #1
    sta c128_startup_preload_display
    jsr c128_render_load_progress
    rts

c128_show_load_progress:
    inc c128_load_progress_count
    jmp c128_render_load_progress

c128_render_load_progress:
    lda #12
    jsr hal_screen_clear_row
    lda #COL_LGREY
    sta zp_text_color
    lda #12
    sta zp_cursor_row
    lda #24
    sta zp_cursor_col
    lda #<c128_load_progress_prefix
    sta zp_ptr0
    lda #>c128_load_progress_prefix
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda c128_load_progress_count
    jsr screen_put_decimal
    lda #$2f
    jsr hal_screen_put_char
    lda c128_load_progress_total
    jsr screen_put_decimal
    lda #<c128_load_progress_suffix
    sta zp_ptr0
    lda #>c128_load_progress_suffix
    sta zp_ptr0_hi
    jmp hal_screen_put_string

c128_load_progress_prefix:
    .text "MORIA8 LOADING " ; .byte 0
c128_load_progress_suffix:
    .text " PLEASE WAIT" ; .byte 0


// ============================================================
.label TITLE_MENU_COL = (SCREEN_COLS - (title_menu_str_end - title_menu_str)) / 2
.const SAVE_DISK_IND_COL = (SCREEN_COLS - 10) / 2

game_over_prompt:
    jmp game_restart
game_over_prompt_end:

// ============================================================
// Entry point
// ============================================================
entry_main:
    sei
    cld
    ldx #$ff
    txs
    // The stack was just reset: no KERNAL bridge is open. Nothing else sets
    // the depth: boot128's page copier bounces through $0c00, leaving it the
    // power-on byte of Bank 1 $fe02. Non-zero, the first EnterKernal kept all
    // RAM mapped and JSR $FF62 ran RAM at $C027 (a BRK into the monitor).
    lda #0
    sta KERNAL_NESTING_DEPTH
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG || C128_TEST_STATUS_SP_CANARY
    lda #0                      // the stack was just reset: no guard is open
    sta c128_stack_guard_depth
#endif

    // Mask CIA1 interrupts — game mode uses direct hardware access.
    lda #$7f
    sta $dc0d
    lda $dc0d                   // Acknowledge any pending CIA1 interrupt

    // Reset SETBNK to Bank 0 — boot128 left SETBNK=Bank1 after loading
    // the game PRG. Without this reset, all subsequent KERNAL LOADs
    // (overlays, title, etc.) silently write to Bank1 while game reads Bank0.
    lda #0
    ldx #0
    jsr $ff68                   // SETBNK: reset to Bank 0
    // Install bottom-common MMU thunks before saving BASIC ZP to Bank 1.
    jsr init_common_mmu_helpers
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp
    lda #MMU_NORMAL
    sta $ff00
    jsr disk_reset_session_state

    // Disable hardware cursor (register 10, bits 6-5 = 01 = cursor off)
    // Prevents KERNAL cursor-blink IRQ from writing to VDC regs 14/15/18/19
    lda #$20
    ldx #10
    jsr vdc_write_reg

    // Initialize VDC display/attribute base explicitly (don't rely on KERNAL defaults).
    // Reg 12/13 = display start address ($0000), Reg 20/21 = attribute start ($0800).
    lda #0
    ldx #12
    jsr vdc_write_reg
    inx                         // 13
    jsr vdc_write_reg
    ldx #21
    jsr vdc_write_reg
    lda #8
    dex                         // 20
    jsr vdc_write_reg

    // Ensure VDC uses per-character attributes (reg 25 bit 6 = 1).
    // Some environments leave this mode undefined after reset/ROM paths.
    ldx #25
    jsr vdc_read_reg
    ora #%01000000
    sta c128_vdc_reg25_cached
    jsr vdc_write_reg

    // Set VDC default colors: foreground white, background black.
    // In attribute mode these are defaults/fallbacks, but setting them
    // explicitly avoids emulator-dependent tinting.
    lda #$f0                    // fg=white (F), bg=black (0)
    sta c128_vdc_reg26_cached
    ldx #26
    jsr vdc_write_reg

    // Set border and background to black (VIC-II — harmless in 80-col mode)
    lda #0
    sta $d020               // Border
    sta $d021               // Background

    // Capture the KERNAL-installed IRQ tail vector before preload starts.
    // Shared preload LOAD transactions temporarily restore this vector.
    lda $0314
    sta kernal_irq_vec_lo
    lda $0315
    sta kernal_irq_vec_hi
    lda #0
    sta c128_kernal_irq_tail_runtime_owned
    jsr init_common_mmu_helpers
    jsr generation_busy_install
    jsr platform_services_install128
    jsr platform_services_assert_installed

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine

    // Cache KERNAL revision byte — must read from low RAM (below $C000)
    // because MMU_NORMAL banks Screen Editor ROM over $C000-$CFFF.
    lda #MMU_NORMAL             // Expose KERNAL ROM at $E000-$FFFF
    sta $ff00
    lda KERNAL_REV              // $FF80 — in KERNAL ROM
    sta tsi_krev_cached
    :MachineRestoreAllRam()     // Stable runtime invariant: Top Common ON ($D506=$0D)

    jsr hal_sound_init
    jsr rng_seed

    // Runtime switches to an all-RAM IRQ regime only after preload/KERNAL I/O
    // is complete. Preload asset LOADs require normal CIA/VIC interrupt service.
    lda #$7f
    sta $dc0d               // Mask all CIA1 interrupt sources
    sta $dd0d               // Mask all CIA2 interrupt sources
    lda $dc0d               // Acknowledge pending CIA1
    lda $dd0d               // Acknowledge pending CIA2
    lda #0
    sta $d01a               // Disable all VIC-II interrupt sources
    ldx #$ff
    stx $d019               // Acknowledge any pending VIC-II interrupts

    // Disable Screen Editor software cursor blink.
    // VDC reg 10 only disables hardware cursor display; the Screen Editor
    // blink path still runs unless $CC is non-zero.
    stx zp_screen_editor_state
    stx zp_screen_editor_mode   // Screen Editor: 80-col mode

    lda #<chrin_keyboard_stub
    sta $0302
    lda #>chrin_keyboard_stub
    sta $0303

    lda #COL_LGREY
    sta zp_text_color

    // Use one visible list for every startup resident and cache load.
    jsr c128_prepare_startup_loading_screen

    lda #5
    sta c128_runtime_load_stage
    jsr c128_load_runtime_low_prg
    bcc !runtime_low_loaded+
    jmp runtime_load_failed
!runtime_low_loaded:
    lda #6
    sta c128_runtime_load_stage
    jsr c128_load_runtime_input_prg
    bcc !runtime_input_loaded+
    jmp runtime_load_failed
!runtime_input_loaded:
    lda #7
    sta c128_runtime_load_stage
    jsr c128_load_runtime_projectile_prg
    bcc !runtime_projectile_loaded+
    jmp runtime_load_failed
!runtime_projectile_loaded:
    lda #8
    sta c128_runtime_load_stage
    jsr c128_load_runtime_common_prg
    bcc !runtime_common_loaded+
    jmp runtime_load_failed
!runtime_common_loaded:
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_runtime_banked_prg
    bcc !runtime_banked_loaded+
    jmp runtime_load_failed
!runtime_banked_loaded:
    jsr c128_load_core_residents
    lda #11
    sta c128_runtime_load_stage
    jsr c128_preload_resident_play
    bcc !resident_play_loaded+
    jmp runtime_load_failed
!resident_play_loaded:
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT || C128_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    jsr screen_clear_for_font_restore
    jsr c128_restore_vdc_rom_font
#endif
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    lda c128_test_single_drive_fresh_save_armed
    beq !c128_test_single_drive_fresh_save_start+
c128_test_single_drive_fresh_save_after_restart:
    lda #0
    sta c128_test_single_drive_fresh_save_armed
    jmp c128_test_single_drive_fresh_save_after_restart
!c128_test_single_drive_fresh_save_start:
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc !c128_test_single_drive_fresh_save_persist_loaded+
    jmp runtime_load_failed
!c128_test_single_drive_fresh_save_persist_loaded:
    lda #2                  // C128_MODAL_PERSIST; const is declared later.
    sta c128_modal_slot_state
c128_test_single_drive_fresh_save_wait_for_harness:
    jmp c128_test_single_drive_fresh_save_wait_for_harness
c128_test_single_drive_fresh_save_before_save:
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    jsr c128_modal_save_game
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_NO_INIT
    bcs c128_test_single_drive_fresh_save_unexpected_return
c128_test_single_drive_fresh_save_no_init_return:
    jmp c128_test_single_drive_fresh_save_no_init_return
#else
    bcc c128_test_single_drive_fresh_save_unexpected_return
    lda #1
    sta c128_test_single_drive_fresh_save_armed
    jmp game_over_prompt
#endif
c128_test_single_drive_fresh_save_unexpected_return:
    jmp c128_test_single_drive_fresh_save_unexpected_return
#endif
#if C128_TEST_SCRIPTED_CHANGE_SAVE_DRIVE_PRODUCT && !C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    lda #8
    sta program_device
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    lda #1
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc !c128_change_save_drive_persist_loaded+
    jmp runtime_load_failed
!c128_change_save_drive_persist_loaded:
    lda #2                  // C128_MODAL_PERSIST; const is declared later.
    sta c128_modal_slot_state
c128_test_change_save_drive_wait_for_harness:
    jmp c128_test_change_save_drive_wait_for_harness
c128_test_change_save_drive_before_save:
    lda #10
    sta save_device
    lda #C128_MEDIA_SAVE
    sta c128_media_state
    jsr c128_modal_save_game
    bcc c128_test_change_save_drive_unexpected_return
c128_test_change_save_drive_pass:
    jmp c128_test_change_save_drive_pass
c128_test_change_save_drive_unexpected_return:
    jmp c128_test_change_save_drive_unexpected_return
#endif
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    jsr tier_init
    lda #0
    sta c128_startup_preload_display
    lda #1
    sta c128_kernal_irq_tail_runtime_owned
    jsr c128_restore_runtime_vectors
    cli
title_enter_menu:
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
    // The restart after the save returns here; the startup preload check
    // does not cover this path.
    lda c128_test_single_drive_fresh_save_armed
    beq !fresh_save_not_armed+
    jmp c128_test_single_drive_fresh_save_after_restart
!fresh_save_not_armed:
#endif
    lda #$ff
    sta c128_active_save_slot
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_begin
    .byte $27
#endif
    jsr tramp_title_load_and_draw
title_menu_after_art:
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_check
    .byte $28
#endif
#if C128_TEST_TITLE_ART_CONTENT
    jsr c128_test_title_art_assert
#endif

title_menu_draw:
    sei
    jsr title_clear_below_menu

    jsr title_show_sysinfo

    // --- Show title menu ---
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #TITLE_MENU_COL
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda disk_setup_done
    beq title_menu_ready
    jsr title_draw_save_disk_indicator

title_menu_ready:
#if C128_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda c128_test_disk_setup_single_drive_return_armed
    beq !c128_disk_setup_return_test_not_armed+
    lda #0
    sta c128_test_disk_setup_single_drive_return_armed
c128_test_after_disk_setup_single_drive_return:
    jmp c128_test_after_disk_setup_single_drive_return
!c128_disk_setup_return_test_not_armed:
#endif
#if C128_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    lda #0
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    // The state names the payload the slot holds: load PERSIST (boot left
    // PLAY there) while the Program Disk is still in the drive.
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc *+5
    jmp runtime_load_failed
    lda #2                  // C128_MODAL_PERSIST; const is declared later.
    sta c128_modal_slot_state
c128_test_disk_setup_single_drive_return_wait_for_harness:
    jmp c128_test_disk_setup_single_drive_return_wait_for_harness
c128_test_disk_setup_single_drive_return_before_disk_setup:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$60
    jsr c128_town_dump_mark
#endif
#if C128_TEST_VIC40_BLANKED_BOOT
    jsr c128_vic40_boot_probe
#endif
#if C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_overlay_transition_pass_sym
#endif
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_SAVE_WRONG_MEDIA_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    // The state names the payload the slot holds: load PERSIST (boot left
    // PLAY there) while the Program Disk is still in the drive.
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc *+5
    jmp runtime_load_failed
    lda #2                  // C128_MODAL_PERSIST; const is declared later.
    sta c128_modal_slot_state
c128_test_single_drive_save_wrong_media_wait_for_harness:
c128_test_single_drive_save_wrong_media_before_save:
    jsr c128_modal_save_game
c128_test_single_drive_save_wrong_media_unexpected_return:
    jmp c128_test_single_drive_save_wrong_media_unexpected_return
c128_test_single_drive_save_wrong_media_script_exhausted:
    jmp c128_test_single_drive_save_wrong_media_script_exhausted
#endif
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_WRONG_MEDIA_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    // The state names the payload the slot holds: load PERSIST (boot left
    // PLAY there) while the Program Disk is still in the drive.
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc *+5
    jmp runtime_load_failed
    lda #2                  // C128_MODAL_PERSIST; const is declared later.
    sta c128_modal_slot_state
c128_test_single_drive_load_wrong_media_wait_for_harness:
c128_test_single_drive_load_wrong_media_before_load:
    jmp title_load_game
c128_test_single_drive_load_wrong_media_unexpected_return:
    jmp c128_test_single_drive_load_wrong_media_unexpected_return
c128_test_single_drive_load_wrong_media_script_exhausted:
    jmp c128_test_single_drive_load_wrong_media_script_exhausted
#endif
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    // The state names the payload the slot holds: load PERSIST (boot left
    // PLAY there) while the Program Disk is still in the drive.
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc *+5
    jmp runtime_load_failed
    lda #2                  // C128_MODAL_PERSIST; const is declared later.
    sta c128_modal_slot_state
c128_test_single_drive_load_corrupt_wait_for_harness:
    jmp c128_test_single_drive_load_corrupt_wait_for_harness
c128_test_single_drive_load_corrupt_before_load:
    jmp title_load_game
c128_test_single_drive_load_corrupt_unexpected_gameplay:
    jmp c128_test_single_drive_load_corrupt_unexpected_gameplay
#endif
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
c128_test_single_drive_load_return_wait_for_harness:
    jmp c128_test_single_drive_load_return_wait_for_harness
c128_test_single_drive_load_return_before_load:
    jmp title_load_game
c128_test_single_drive_load_return_load_fail:
    jmp c128_test_single_drive_load_return_load_fail
#endif
#if C128_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
c128_test_load_then_save_new_empty_save:
    ldx #$ff
    txs
    lda #8
    sta program_device
    sta save_device
    lda #1
    sta disk_mode
    sta disk_setup_done
    lda #1
    sta c128_test_load_then_save_new_empty_stage
    jsr c128_modal_require_persist
c128_test_load_then_save_new_empty_save_media_ready:
    jsr disk_marker_init
    bcs c128_test_load_then_save_new_empty_fail
    jsr disk_init_drive
    bcs c128_test_load_then_save_new_empty_fail
    lda #C128_MEDIA_SAVE
    sta c128_media_state
    jsr save_game
    bcc c128_test_load_then_save_new_empty_fail
    jsr c128_test_load_then_save_new_empty_write_proof
    bcc c128_test_load_then_save_new_empty_fail
    lda #2
    sta c128_test_load_then_save_new_empty_stage
c128_test_load_then_save_new_empty_after_save_wait:
    jmp c128_test_load_then_save_new_empty_after_save_wait
c128_test_load_then_save_new_empty_restore_program:
    lda #3
    sta c128_test_load_then_save_new_empty_stage
c128_test_load_then_save_new_empty_done:
    jmp c128_test_load_then_save_new_empty_done
c128_test_load_then_save_new_empty_fail:
    jmp c128_test_load_then_save_new_empty_fail

c128_test_load_then_save_new_empty_write_proof:
    jsr disk_kernal_enter
    lda #hal_storage_save_write_name_len
    ldx #<hal_storage_save_write_name
    ldy #>hal_storage_save_write_name
    jsr $ffbd
    lda #2
    ldx save_device
    ldy #2
    jsr $ffba
    jsr $ffc0
    bcs !proof_fail+
    ldx #2
    jsr $ffc9
    bcs !proof_close_fail+
    lda #$4d
    jsr $ffd2
!proof_close_fail:
    jsr $ffcc
    lda #2
    jsr $ffc3
    jsr disk_kernal_exit
    sec
    rts
!proof_fail:
    jsr disk_kernal_exit
    clc
    rts
#endif
    cli
title_menu_loop:                // Exported for the scripted product harness
!title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
#if C128_TEST_TOWN_SELF_DUMP
    lda #$61
    jsr c128_town_dump_mark
#endif
    jsr c128_modal_require_play
    jmp game_new_start
!not_n:
    cmp #$4c                // 'L' — load game
    beq title_load_game
    cmp #$41                // A: About, before a character exists
    bne !not_legal_title+
    jsr tramp_ui_legal_display
    jmp title_enter_menu
!not_legal_title:
    cmp #$44                // 'D' — disk setup
    bne !title_menu_loop-
    jsr c128_modal_require_persist
    jsr tramp_disk_setup
#if C128_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
    lda #1
    sta c128_test_disk_setup_single_drive_return_armed
#endif
    jmp c128_title_require_program_media

title_load_game:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr hal_sound_play
    jsr msg_init
    jsr c128_modal_require_persist
    jsr title_require_disk_setup
    bcc !title_setup_ready+
    jmp c128_title_require_program_media
!title_setup_ready:
    lda #$ff
    sta save_slot_index
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
c128_test_single_drive_load_return_before_save_media:
#endif
    jsr c128_modal_load_game
    bcc !title_load_fail+
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
c128_test_single_drive_load_return_loaded:
#endif
#if C128_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    // Snapshot load_result while PERSIST still owns the modal slot; the
    // require_play below evicts it, so the harness cannot read it directly.
    lda load_result
    sta c128_test_load_then_save_new_empty_load_result
#endif
    jsr c128_modal_require_play
    jmp load_resume_game
!title_load_fail:
#if C128_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
    jmp c128_test_load_then_save_new_empty_fail
#elif C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_RETURN_PRODUCT
    jmp c128_test_single_drive_load_return_load_fail
#endif
    jsr c128_restore_runtime_vectors
    jsr input_get_modal_dismiss_key
    jmp c128_title_require_program_media

c128_title_require_program_media:
    jsr c128_require_program_media
    bcc !title_program_ready+
    jsr c128_program_media_error_prompt
    jmp c128_title_require_program_media
!title_program_ready:
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_LOAD_CORRUPT_PRODUCT
c128_test_single_drive_load_corrupt_program_ready:
#endif
    jmp title_enter_menu

runtime_load_failed:
    sei
    lda c128_runtime_load_stage
    sta $d020
    sta $d021
!loop:
    lda c128_runtime_load_stage
    jmp !loop-

// ============================================================
// c128_load_runtime_low_prg — Load low-RAM resident runtime code to $1000 in Bank 0
// Output: carry clear = success, carry set = error
// ============================================================
.const RUNTIME_LOW_FILE_NUM = 2
runtime_low_filename:
runtime_low_display_str:
    .text "128.RUNTIME"
runtime_low_filename_end:
    .byte 0
.const RUNTIME_LOW_FILENAME_LEN = runtime_low_filename_end - runtime_low_filename
// `runtime_low_filename` and `runtime_low_display_str` intentionally share one
// string: SETNAM uses the explicit length above, display uses the terminator.
// Do not split these labels into independent literals.
.const RUNTIME_INPUT_FILE_NUM = 3
runtime_input_filename:
    .byte $31, $32, $38, $2e, $49, $4e, $50, $55, $54 // "128.INPUT"
runtime_input_filename_end:
    .byte 0
.const RUNTIME_INPUT_FILENAME_LEN = runtime_input_filename_end - runtime_input_filename
.const RUNTIME_PROJECTILE_FILE_NUM = 4
runtime_projectile_filename:
    .byte $31, $32, $38, $2e, $50, $52, $4f, $4a // "128.PROJ"
runtime_projectile_filename_end:
    .byte 0
.const RUNTIME_PROJECTILE_FILENAME_LEN = runtime_projectile_filename_end - runtime_projectile_filename
.const RUNTIME_COMMON_FILE_NUM = 5
runtime_common_filename:
    .byte $31, $32, $38, $2e, $46, $44, $49, $53, $4b // "128.FDISK"
runtime_common_filename_end:
    .byte 0
.const RUNTIME_COMMON_FILENAME_LEN = runtime_common_filename_end - runtime_common_filename
.const ITEM_IDX_FILE_NUM = 14
.const ITEM_IDX_LOAD_ADDR = $0600
#if !C128_CARTRIDGE
item_idx_filename:
    .text "ITEM.IDX"
item_idx_filename_end:
    .byte 0
.const ITEM_IDX_FILENAME_LEN = item_idx_filename_end - item_idx_filename
#endif
.const RESIDENT_HUFFMAN_FILE_NUM = 15
resident_huffman_filename:
    .text "128.HUFF"
resident_huffman_filename_end:
    .byte 0
.const RESIDENT_HUFFMAN_FILENAME_LEN = resident_huffman_filename_end - resident_huffman_filename
.const RESIDENT_HUFFMAN_VECTOR_FILE_NUM = 15
resident_huffman_vector_filename:
    .text "128.HVEC"
resident_huffman_vector_filename_end:
    .byte 0
.const RESIDENT_HUFFMAN_VECTOR_FILENAME_LEN = resident_huffman_vector_filename_end - resident_huffman_vector_filename
.const RESIDENT_PERSIST_FILE_NUM = 10
resident_persist_filename:
    .text "128.PERSIST"
resident_persist_filename_end:
    .byte 0
.const RESIDENT_PERSIST_FILENAME_LEN = resident_persist_filename_end - resident_persist_filename
.const RESIDENT_PLAY_FILE_NUM = 11
.const C128_PROGRAM_PROBE_FILE_NUM = 7
.const C128_PROGRAM_CMD_FILE_NUM = 15
resident_play_filename:
    .text "128.PLAY"
resident_play_filename_end:
    .byte 0
.const RESIDENT_PLAY_FILENAME_LEN = resident_play_filename_end - resident_play_filename
.const RUNTIME_BANKED_FILE_NUM = 12
runtime_banked_filename:
    .byte $31, $32, $38, $2e, $42, $41, $4e, $4b // "128.BANK"
runtime_banked_filename_end:
    .byte 0
.const RUNTIME_BANKED_FILENAME_LEN = runtime_banked_filename_end - runtime_banked_filename

// In Default, not with overlay.s: C128ResidentWorld has no room for it.
#import "../common/asset_load_retry.s"

// Repeated on failure as asset_load_retry repeats the HAL loads (a drive can
// miss a handshake). The inputs are kept: the load clears the bank, and the
// progress display may use the pointers.
#if C128_CARTRIDGE
c128_load_runtime_low_prg:
    lda #CART_ASSET_RUNTIME_LOW
    jmp cart_load_asset
c128_load_runtime_input_prg:
    lda #CART_ASSET_RUNTIME_INPUT
    jmp cart_load_asset
c128_load_runtime_projectile_prg:
    lda #CART_ASSET_RUNTIME_PROJ
    jmp cart_load_asset
c128_load_runtime_common_prg:
    lda #CART_ASSET_RUNTIME_COMMON
    jmp cart_load_asset
c128_load_resident_huffman_prg:
    lda #CART_ASSET_HUFF
    jmp cart_load_asset
c128_load_resident_huffman_vector_prg:
    lda #CART_ASSET_HVEC
    jmp cart_load_asset
#else
c128_load_runtime_prg:
    lda c128_runtime_load_bank
    sta crl_bank
    lda disk_temp
    sta crl_file
    lda disk_status
    sta crl_name_len
    lda zp_ptr0
    sta crl_name
    lda zp_ptr0_hi
    sta crl_name + 1
    lda zp_ptr1
    sta crl_dest
    lda zp_ptr1_hi
    sta crl_dest + 1
    lda #ASSET_LOAD_ATTEMPTS
    sta crl_left
!crl_try:
    lda crl_bank
    sta c128_runtime_load_bank
    lda crl_file
    sta disk_temp
    lda crl_name_len
    sta disk_status
    lda crl_name
    sta zp_ptr0
    lda crl_name + 1
    sta zp_ptr0_hi
    lda crl_dest
    sta zp_ptr1
    lda crl_dest + 1
    sta zp_ptr1_hi
    jsr crl_load_once
    bcc !crl_done+
    dec crl_left                // carry stays set
    beq !crl_done+
    inc asset_load_retries
    lda c128_startup_preload_display
    beq !crl_try-
    dec c128_load_progress_count    // the repeat shows as the same file
    jmp !crl_try-
!crl_done:
    rts

crl_bank:     .byte 0
crl_file:     .byte 0
crl_name_len: .byte 0
crl_name:     .word 0
crl_dest:     .word 0
crl_left:     .byte 0

crl_load_once:
    lda c128_runtime_load_bank
    ldx #0
    jsr safe_setbnk

    lda disk_status
    ldx zp_ptr0
    ldy zp_ptr0_hi
    jsr w_setnam
    lda c128_startup_preload_display
    beq !runtime_no_display+
    jsr c128_show_load_progress
!runtime_no_display:
    lda disk_temp
    ldx program_device
    ldy #1
    jsr w_setlfs

    lda #0
    ldx zp_ptr1
    ldy zp_ptr1_hi
    jsr w_load
    sta c128_runtime_load_result_a
    php
    jsr w_readst
    sta c128_runtime_load_readst

    lda disk_temp
    jsr w_close
    jsr w_clrchn

    lda #0
    sta c128_runtime_load_bank
    ldx #0
    jsr safe_setbnk

    plp
    bcs !done+

    lda $dd00
    ora #%00000011
    sta $dd00
    lda #0
    sta zp_kernal_status
!done:
    rts

c128_load_runtime_low_prg:
    lda #RUNTIME_LOW_FILE_NUM
    sta disk_temp
    lda #RUNTIME_LOW_FILENAME_LEN
    sta disk_status
    lda #<runtime_low_filename
    sta zp_ptr0
    lda #>runtime_low_filename
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$10
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg

c128_load_runtime_input_prg:
    lda #RUNTIME_INPUT_FILE_NUM
    sta disk_temp
    lda #RUNTIME_INPUT_FILENAME_LEN
    sta disk_status
    lda #<runtime_input_filename
    sta zp_ptr0
    lda #>runtime_input_filename
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$0b
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg

c128_load_runtime_projectile_prg:
    lda #RUNTIME_PROJECTILE_FILE_NUM
    sta disk_temp
    lda #RUNTIME_PROJECTILE_FILENAME_LEN
    sta disk_status
    lda #<runtime_projectile_filename
    sta zp_ptr0
    lda #>runtime_projectile_filename
    sta zp_ptr0_hi
    lda #$70
    sta zp_ptr1
    lda #$0a
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg

c128_load_runtime_common_prg:
    lda #RUNTIME_COMMON_FILE_NUM
    sta disk_temp
    lda #RUNTIME_COMMON_FILENAME_LEN
    sta disk_status
    lda #<runtime_common_filename
    sta zp_ptr0
    lda #>runtime_common_filename
    sta zp_ptr0_hi
    lda #$20
    sta zp_ptr1
    lda #$0d
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg

.macro C128RuntimeLoadFile(file_num, filename_len, filename, load_hi) {
    lda #file_num
    sta disk_temp
    lda #filename_len
    sta disk_status
    lda #<filename
    sta zp_ptr0
    lda #>filename
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #load_hi
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg
}

c128_load_item_idx_prg:
    lda #ITEM_IDX_FILE_NUM
    sta disk_temp
    lda #ITEM_IDX_FILENAME_LEN
    sta disk_status
    lda #<item_idx_filename
    sta zp_ptr0
    lda #>item_idx_filename
    sta zp_ptr0_hi
    lda #<ITEM_IDX_LOAD_ADDR
    sta zp_ptr1
    lda #>ITEM_IDX_LOAD_ADDR
    sta zp_ptr1_hi
    lda #0
    sta c128_runtime_load_bank
    jmp c128_load_runtime_prg

// Load the Huffman corpus into the Bank 1 $F000 region.
c128_load_resident_huffman_prg:
    lda #RESIDENT_HUFFMAN_FILE_NUM
    sta disk_temp
    lda #RESIDENT_HUFFMAN_FILENAME_LEN
    sta disk_status
    lda #<resident_huffman_filename
    sta zp_ptr0
    lda #>resident_huffman_filename
    sta zp_ptr0_hi
    lda #<BANK1_HUFFMAN_BASE
    sta zp_ptr1
    lda #>BANK1_HUFFMAN_BASE
    sta zp_ptr1_hi
    lda #1
    sta c128_runtime_load_bank
    jmp c128_load_runtime_prg

// Load the Bank 1 NMI bridge separately so no PRG crosses the MMU register at
// $FF00. The Huffman read helpers require this bridge before first use.
c128_load_resident_huffman_vector_prg:
    lda #RESIDENT_HUFFMAN_VECTOR_FILE_NUM
    sta disk_temp
    lda #RESIDENT_HUFFMAN_VECTOR_FILENAME_LEN
    sta disk_status
    lda #<resident_huffman_vector_filename
    sta zp_ptr0
    lda #>resident_huffman_vector_filename
    sta zp_ptr0_hi
    lda #<BANK1_HUFFMAN_NMI_VECTOR_BASE
    sta zp_ptr1
    lda #>BANK1_HUFFMAN_NMI_VECTOR_BASE
    sta zp_ptr1_hi
    lda #1
    sta c128_runtime_load_bank
    jmp c128_load_runtime_prg
#endif


c128_load_core_residents:
    lda #3
    sta c128_runtime_load_stage
#if !C128_CARTRIDGE
    jsr c128_load_item_idx_prg
    bcc !item_idx_loaded+
    jmp runtime_load_failed
!item_idx_loaded:
    jsr c128_copy_item_idx_data
#endif
    jsr recall_clear_all
    lda #4
    sta c128_runtime_load_stage
#if C128_CARTRIDGE
    // Install Bank 1 NMI bridge ($FFFA-$FFFB) before populating Bank 1 $F000-$FEC3
    jsr c128_load_resident_huffman_vector_prg
    bcc !resident_huffman_vector_loaded+
    jmp runtime_load_failed
!resident_huffman_vector_loaded:
    jsr c128_load_resident_huffman_prg
    bcc !resident_huffman_loaded+
    jmp runtime_load_failed
!resident_huffman_loaded:
#else
    jsr c128_load_resident_huffman_prg
    bcc !resident_huffman_loaded+
    jmp runtime_load_failed
!resident_huffman_loaded:
    jsr c128_load_resident_huffman_vector_prg
    bcc !resident_huffman_vector_loaded+
    jmp runtime_load_failed
!resident_huffman_vector_loaded:
#endif
#if HAL_PLATFORM_MONSTER_CATALOG
    jsr c128_load_catalog_prg
    bcc !catalog_loaded+
    jmp runtime_load_failed
!catalog_loaded:
    jsr c128_load_catalog_names_prg
    bcc !catalog_names_loaded+
    jmp runtime_load_failed
!catalog_names_loaded:
#endif
    rts

c128_load_resident_persist_prg:
#if C128_CARTRIDGE
    lda #CART_ASSET_PERSIST
    jmp cart_load_asset
#else
    :C128RuntimeLoadFile(RESIDENT_PERSIST_FILE_NUM, RESIDENT_PERSIST_FILENAME_LEN, resident_persist_filename, $af)
#endif

c128_load_resident_play_prg:
#if C128_CARTRIDGE
    lda #CART_ASSET_PLAY
    jmp cart_load_asset
#else
    :C128RuntimeLoadFile(RESIDENT_PLAY_FILE_NUM, RESIDENT_PLAY_FILENAME_LEN, resident_play_filename, $af)
#endif

.const C128_MODAL_UNKNOWN = 0
.const C128_MODAL_PLAY    = 1
.const C128_MODAL_PERSIST = 2
.const C128_RESIDENT_PLAY_SIG0 = $4d
.const C128_RESIDENT_PLAY_SIG1 = $38
.const C128_RESIDENT_PLAY_SIG2 = $50

c128_preload_resident_play:
    jsr c128_load_resident_play_prg
    bcs !play_preload_failed+
    lda c128_resident_play_sig0
    cmp #C128_RESIDENT_PLAY_SIG0
    bne !play_preload_failed+
    lda c128_resident_play_sig1
    cmp #C128_RESIDENT_PLAY_SIG1
    bne !play_preload_failed+
    lda c128_resident_play_sig2
    cmp #C128_RESIDENT_PLAY_SIG2
    bne !play_preload_failed+
    lda #C128_MODAL_PLAY
    sta c128_modal_slot_state
    clc
    rts
!play_preload_failed:
    sec
    rts

c128_require_program_media:
#if C128_CARTRIDGE
    // Cartridge ROM always serves program assets without displacing Drive 8/9 save media.
    clc
    rts
#else
    jsr disk_prompt_game
    bcs !program_fail+
    jsr c128_program_play_exists
    bcc !program_fail+
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    clc
    rts
!program_fail:
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
    sec
    rts
#endif

c128_program_media_error_prompt:
#if C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    lda c128_test_after_save_media_check_active
    beq !not_after_save_check+
    jmp c128_test_unexpected_post_save_program_prompt
!not_after_save_check:
#endif
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
c128_program_media_error_shown:
    jsr c128_restore_runtime_guards
    jmp disk_prompt_game

#if C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
c128_test_unexpected_post_save_program_prompt:
    lda program_device
    sta c128_test_post_save_prompt_diag
    lda save_device
    sta c128_test_post_save_prompt_diag + 1
    lda disk_mode
    sta c128_test_post_save_prompt_diag + 2
    lda c128_media_state
    sta c128_test_post_save_prompt_diag + 3
    jmp c128_test_unexpected_post_save_program_prompt
#endif

c128_require_save_media:
    lda disk_mode
    cmp #1
    bne !prompt_save+
    lda c128_media_state
    cmp #C128_MEDIA_SAVE
    bne !prepare_selected+
    jsr disk_init_drive
    rts
!prepare_selected:
    jsr tramp_disk_prepare_selected
    rts
!prompt_save:
    jsr disk_prompt_save
    rts

c128_modal_require_persist:
!retry:
    lda c128_modal_slot_state
    cmp #C128_MODAL_PERSIST
    beq !persist_loaded+
    jsr c128_require_program_media
    bcs !persist_load_failed+
    lda #10
    sta c128_runtime_load_stage
    jsr c128_load_resident_persist_prg
    bcc !persist_loaded+
!persist_load_failed:
    jsr c128_program_media_error_prompt
    jmp !retry-
!persist_loaded:
    lda #C128_MODAL_PERSIST
    sta c128_modal_slot_state
    rts

c128_modal_save_game:
    jsr c128_modal_require_persist
    jsr c128_require_save_media
    bcs !save_fail+
#if !BYPASS_SLOT_PROMPT
    lda c128_active_save_slot
    sta save_slot_index
    jsr save_select_slot_prompt
#endif
    jsr ui_prepare_fullscreen_transition
    jsr save_game
    bcc !save_done+
    lda save_slot_index
    sta c128_active_save_slot
#if C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
c128_test_after_save_before_play_media:
    lda #1
    sta c128_test_after_save_media_check_active
#endif
    jsr c128_modal_require_play
    sec
!save_done:
    rts
!save_fail:
    clc
    rts

c128_modal_load_game:
    jsr c128_modal_require_persist
    jsr c128_require_save_media
    bcs !load_fail+
#if !BYPASS_SLOT_PROMPT
    lda c128_active_save_slot
    sta save_slot_index
    jsr save_select_slot_prompt
#endif
    jsr ui_prepare_fullscreen_transition
    jsr load_game
    bcc !load_done+
    lda save_slot_index
    sta c128_active_save_slot
!load_done:
    rts
!load_fail:
    clc
    rts

c128_modal_require_play:
!retry:
    lda c128_modal_slot_state
    cmp #C128_MODAL_PLAY
    beq !play_loaded+
    jsr c128_require_program_media
    bcs !play_load_failed+
    lda #11
    sta c128_runtime_load_stage
    jsr c128_load_resident_play_prg
    bcs !play_load_failed+
    lda c128_resident_play_sig0
    cmp #C128_RESIDENT_PLAY_SIG0
    bne !play_load_failed+
    lda c128_resident_play_sig1
    cmp #C128_RESIDENT_PLAY_SIG1
    bne !play_load_failed+
    lda c128_resident_play_sig2
    cmp #C128_RESIDENT_PLAY_SIG2
    beq !play_loaded+
!play_load_failed:
    jsr c128_program_media_error_prompt
    jmp !retry-
!play_loaded:
    lda #C128_MODAL_PLAY
    sta c128_modal_slot_state
    rts

c128_load_runtime_banked_prg:
#if C128_CARTRIDGE
    lda #CART_ASSET_BANKED
    jmp cart_load_asset
#else
    lda #RUNTIME_BANKED_FILE_NUM
    sta disk_temp
    lda #RUNTIME_BANKED_FILENAME_LEN
    sta disk_status
    lda #<runtime_banked_filename
    sta zp_ptr0
    lda #>runtime_banked_filename
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$f0
    sta zp_ptr1_hi
    jmp c128_load_runtime_prg
#endif


// ============================================================
// Dungeon gen overlay trampoline — overlays now at $0400 (Safe Zone)
// ============================================================

tramp_level_generate:
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_begin
    .byte $39
#endif
    jsr level_generate
#if C128_REAL_BOOT_DIAG
    jsr c128_stack_guard_check
    .byte $3a
#endif
    rts

// ============================================================
// Special rooms epilogue — restore MMU after Bank 0 call.
// ============================================================
tramp_sr_epilogue:
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call resident Bank 0 code.
// ============================================================
tramp_ego_append_suffix:
    and #EGO_ID_MASK
    beq !teas_done+
    jsr ego_get_suffix_ptr
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #81
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
!teas_done:
    rts

c128_load_arg_x: .byte 0
c128_load_arg_y: .byte 0
kernal_irq_vec_lo: .byte 0
kernal_irq_vec_hi: .byte 0
c128_kernal_irq_tail_runtime_owned: .byte 0
c128_runtime_load_stage: .byte 0
c128_startup_preload_display: .byte 0
c128_load_progress_count: .byte 0
c128_load_progress_total: .byte 0
c128_runtime_load_bank: .byte 0
c128_runtime_load_result_a: .byte 0
c128_runtime_load_readst: .byte 0
c128_modal_slot_state: .byte C128_MODAL_UNKNOWN
c128_media_state: .byte C128_MEDIA_UNKNOWN
c128_active_save_slot: .byte $ff
#if C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
c128_test_after_save_media_check_active: .byte 0
c128_test_post_save_prompt_diag: .fill 4, 0
// The save-write smoke stops here once the save returns. In the game code
// (the PLAY payload, $C3xx) VICE's "until" also stopped where the
// screen-editor ROM runs the same address at boot: a pass with no save.
// Below $4000 no ROM code runs.
c128_test_after_save_game:
    rts
.assert "save-write smoke stop is below every ROM", c128_test_after_save_game < $4000, true
#endif
#if C128_TEST_SCRIPTED_LOAD_THEN_SAVE_NEW_EMPTY_PRODUCT
c128_test_load_then_save_new_empty_stage: .byte 0
c128_test_load_then_save_new_empty_load_result: .byte 0
#endif
#if C128_TEST_SCRIPTED_SINGLE_DRIVE_FRESH_SAVE_PRODUCT
c128_test_single_drive_fresh_save_armed: .byte 0
#endif
#if C128_TEST_SCRIPTED_DISK_SETUP_SINGLE_DRIVE_RETURN_PRODUCT
c128_test_disk_setup_single_drive_return_armed: .byte 0
#endif
kernal_hw_irq_vec_lo: .byte 0
kernal_hw_irq_vec_hi: .byte 0
kernal_hw_nmi_vec_lo: .byte 0
kernal_hw_nmi_vec_hi: .byte 0

// c128_stack_guard_begin/check — capture and validate stack balance around
// high-risk KERNAL/overlay/runtime boundaries. On mismatch, preserve the
// expected SP, actual SP, and stage tag in RAM and break immediately.
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG || C128_TEST_STATUS_SP_CANARY
.const C128_STACK_GUARD_NEST_MAX = 8
// Call as "jsr c128_stack_guard_begin" (or _check) followed by ".byte stage".
// Both keep the caller's A, X, Y and flags (saved in memory, so SP is
// unchanged for the depth check): sites sit between loading a register and
// using it.
// Guards nest (player_create's spans overlay and asset loads with their own):
// begin pushes the enclosing expected SP and a passing check pops it, so each
// check compares its own begin's depth.
c128_stack_guard_begin:
    sta c128_stack_guard_saved_a
    php
    pla
    sta c128_stack_guard_saved_p
    stx c128_stack_guard_saved_x
    sty c128_stack_guard_saved_y
    jsr c128_stack_guard_verify_canaries
    jsr c128_stack_guard_take_stage
    ldy c128_stack_guard_depth
    cpy #C128_STACK_GUARD_NEST_MAX
    bcc !c128_stack_guard_push+
    lda #$e3                    // nesting deeper than the save stack
    sta c128_stack_guard_fail_code
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_diag_fail_sym
#else
    brk
#endif
!c128_stack_guard_push:
    lda c128_stack_guard_expected
    sta c128_stack_guard_nest,y
    inc c128_stack_guard_depth
    lda #0
    sta c128_stack_guard_fail_code
    sta c128_stack_guard_substage
    tsx
    stx c128_stack_guard_expected
    jmp c128_stack_guard_restore_ap

c128_stack_guard_check:
    sta c128_stack_guard_saved_a
    php
    pla
    sta c128_stack_guard_saved_p
    stx c128_stack_guard_saved_x
    sty c128_stack_guard_saved_y
    jsr c128_stack_guard_verify_canaries
    jsr c128_stack_guard_take_stage
    tsx
    stx c128_stack_guard_actual
    cpx c128_stack_guard_expected
    beq !c128_stack_guard_ok+
    lda #$e1
    sta c128_stack_guard_fail_code
    stx c128_stack_guard_substage
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_diag_fail_sym
#else
    brk
#endif
!c128_stack_guard_ok:
    ldy c128_stack_guard_depth
    beq c128_stack_guard_restore_ap
    dey
    sty c128_stack_guard_depth
    lda c128_stack_guard_nest,y
    sta c128_stack_guard_expected
c128_stack_guard_restore_ap:
    ldx c128_stack_guard_saved_x
    ldy c128_stack_guard_saved_y
    lda c128_stack_guard_saved_p
    pha
    lda c128_stack_guard_saved_a
    plp
    rts

// The stage byte follows the caller's jsr to begin/check: read it and step
// that return address past it.
c128_stack_guard_take_stage:
    tsx
    lda $0103,x                 // begin/check's return address (lo, hi)
    clc
    adc #1
    sta c128_stack_guard_stage_byte + 1
    lda $0104,x
    adc #0
    sta c128_stack_guard_stage_byte + 2
c128_stack_guard_stage_byte:
    lda $ffff                   // operand set above
    sta c128_stack_guard_stage
    inc $0103,x
    bne !c128_stack_guard_take_done+
    inc $0104,x
!c128_stack_guard_take_done:
    rts

c128_stack_guard_verify_canaries:
    lda c128_stack_guard_canary_lo
    cmp #$a5
    bne !c128_stack_guard_bad+
    lda c128_stack_guard_canary_hi
    cmp #$5a
    beq !c128_stack_guard_canaries_ok+
!c128_stack_guard_bad:
    lda #$e0
    sta c128_stack_guard_fail_code
#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
    jmp c128_diag_fail_sym
#else
    brk
#endif
!c128_stack_guard_canaries_ok:
    rts

c128_stack_guard_snapshot_banking:
    lda $00
    sta c128_stack_guard_port0
    lda $01
    sta c128_stack_guard_port1
    lda $ff00
    sta c128_stack_guard_mmu
    rts

c128_stack_guard_snapshot_return:
    tsx
    lda $0103,x
    sta c128_stack_guard_ret_lo
    lda $0104,x
    sta c128_stack_guard_ret_hi
    rts





#if C128_TEST_REAL_BOOT_DIAG || C128_TEST_OVERLAY_TRANSITION_DIAG
c128_diag_validate_runtime_invariants:
    stx c128_stack_guard_stage
    jsr c128_stack_guard_snapshot_banking
    tsx
    stx c128_stack_guard_actual
    cpx #$40
    bcs !stack_ok+
    lda #$e2
    sta c128_stack_guard_fail_code
    stx c128_stack_guard_substage
    jmp c128_diag_fail_sym
!stack_ok:
    lda $00
    cmp #CPU_PORT_DDR_DEFAULT
    beq !port0_ok+
    sta c128_stack_guard_fail_code
    lda #1
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!port0_ok:
    lda $01
    tax
    and #$07
    cmp #(BANK_NO_BASIC & $07)
    beq !port1_ok+
    txa
    sta c128_stack_guard_fail_code
    lda #2
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!port1_ok:
    lda $ff00
    cmp #MMU_ALL_RAM
    beq !mmu_ok+
    sta c128_stack_guard_fail_code
    lda #3
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!mmu_ok:
    // The software IRQ tail is the KERNAL's until the title arms the runtime
    // (c128_kernal_irq_tail_runtime_owned); startup preloads run before that,
    // and ExitKernal leaves the captured KERNAL vector in place.
    lda c128_kernal_irq_tail_runtime_owned
    bne !irq_runtime_owned+
    lda $0314
    cmp kernal_irq_vec_lo
    bne !irq_lo_bad+
    lda $0315
    cmp kernal_irq_vec_hi
    beq !irq_hi_ok+
    bne !irq_hi_bad+
!irq_runtime_owned:
    lda $0314
    cmp #<mmu_common_irq
    beq !irq_lo_ok+
!irq_lo_bad:
    sta c128_stack_guard_fail_code
    lda #4
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!irq_lo_ok:
    lda $0315
    cmp #>mmu_common_irq
    beq !irq_hi_ok+
!irq_hi_bad:
    sta c128_stack_guard_fail_code
    lda #5
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!irq_hi_ok:
    // The hardware NMI/IRQ vectors become the runtime's at the same point
    // (c128_restore_runtime_vectors); before it they are the KERNAL's.
    lda c128_kernal_irq_tail_runtime_owned
    bne !hw_vectors_owned+
    jmp !hw_irq_hi_ok+
!hw_vectors_owned:
    lda $fffa
    cmp #<mmu_common_nmi
    beq !nmi_lo_ok+
    sta c128_stack_guard_fail_code
    lda #6
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!nmi_lo_ok:
    lda $fffb
    cmp #>mmu_common_nmi
    beq !nmi_hi_ok+
    sta c128_stack_guard_fail_code
    lda #7
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!nmi_hi_ok:
    lda $fffe
    cmp #<mmu_common_irq
    beq !hw_irq_lo_ok+
    sta c128_stack_guard_fail_code
    lda #8
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!hw_irq_lo_ok:
    lda $ffff
    cmp #>mmu_common_irq
    beq !hw_irq_hi_ok+
    sta c128_stack_guard_fail_code
    lda #9
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!hw_irq_hi_ok:
    lda $0302
    cmp #<chrin_keyboard_stub
    beq !chrin_lo_ok+
    sta c128_stack_guard_fail_code
    lda #$0a
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!chrin_lo_ok:
    lda $0303
    cmp #>chrin_keyboard_stub
    beq !chrin_hi_ok+
    sta c128_stack_guard_fail_code
    lda #$0b
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!chrin_hi_ok:
    jsr c128_diag_verify_helper_blob
    rts

c128_diag_verify_helper_blob:
    ldx #0
!helper_loop:
    lda MMU_COMMON_HELPERS_BASE,x
    cmp mmu_common_helpers_blob,x
    beq !helper_next+
    sta c128_stack_guard_fail_code
    txa
    sta c128_stack_guard_substage
    jmp c128_diag_fail_sym
!helper_next:
    inx
    cpx #mmu_common_helpers_blob_end - mmu_common_helpers_blob - 1
    bne !helper_loop-
    rts
#endif

#if C128_TEST_STATUS_SP_CANARY
.assert "Status canary trap stays below fixed debug slot", * <= $3ef8, true
c128_status_ret_corrupt:
    nop
    jmp c128_status_ret_corrupt
.assert "Status canary state fits before fixed debug slot", * <= $3efc, true
c128_status_ret_expected_lo: .byte 0
c128_status_ret_expected_hi: .byte 0
c128_status_ret_actual_lo:   .byte 0
c128_status_ret_actual_hi:   .byte 0
#endif

c128_stack_guard_canary_lo: .byte $a5
c128_stack_guard_expected:  .byte 0
c128_stack_guard_actual:    .byte 0
c128_stack_guard_stage:     .byte 0
c128_stack_guard_canary_hi: .byte $5a
c128_stack_guard_port0:     .byte 0
c128_stack_guard_port1:     .byte 0
c128_stack_guard_saved_a:   .byte 0
c128_stack_guard_saved_p:   .byte 0
c128_stack_guard_saved_y:   .byte 0
c128_stack_guard_saved_x:   .byte 0
c128_stack_guard_depth:     .byte 0
c128_stack_guard_nest:      .fill C128_STACK_GUARD_NEST_MAX, 0
c128_stack_guard_mmu:       .byte 0
c128_stack_guard_ret_lo:    .byte 0
c128_stack_guard_ret_hi:    .byte 0
c128_stack_guard_fail_code: .byte 0
c128_stack_guard_substage:  .byte 0
#endif
.assert "Program fits below map area", * <= MAP_BASE, true

.const DUNGEON_GEN_BUSY = 1

// ============================================================
// Imports — Game Engine (Safe to spill past $C000)
// ============================================================
#import "../../../core/tables.s"
#import "../../../core/item_defs.s"
#import "preload128.s"
#import "reu_stub128.s"
#import "../../../core/rng.s"
#import "../../../core/math.s"
#import "../../../core/dungeon_tunnel_guard.s"
#define PLAYER_STAT_HELPERS_EXTERNAL
#import "../../../core/player.s"
#undef PLAYER_STAT_HELPERS_EXTERNAL
#import "../../../core/ui_messages.s"
#define STATUS_TEXT_SEGMENT_CUSTOM
.macro StatusTextSegment() {
    .segment RuntimeBankedCode
}
.macro StatusTextRestoreSegment() {
    .segment Default
}
#import "../../../core/ui_status.s"
#undef STATUS_TEXT_SEGMENT_CUSTOM
#import "../../../core/generation_busy.s"
#import "../../../core/stat_display.s"
#import "../../../core/huffman.s"
// The decoder briefly disables top common RAM to expose the physical Bank 1
// corpus. Keep NMI valid during that window via the bottom-common handler.
c128_bank1_huffman_corpus_end:
.assert "C128 Bank 1 Huffman corpus stays below reserved vector space", c128_bank1_huffman_corpus_end <= BANK1_HUFFMAN_END + 1, true
.segment C128Bank1HuffmanVector
c128_bank1_huffman_nmi_vector:
    .word mmu_common_nmi
c128_bank1_huffman_payload_end:
.assert "Bank 1 Huffman NMI vector starts at $FFFA", c128_bank1_huffman_nmi_vector == BANK1_HUFFMAN_NMI_VECTOR_BASE, true
.assert "Bank 1 Huffman NMI vector is exactly two bytes", c128_bank1_huffman_payload_end == BANK1_HUFFMAN_NMI_VECTOR_END + 1, true
.assert "Bank 1 Huffman NMI target is in bottom common RAM", mmu_common_nmi >= BANK1_COMMON_BASE && mmu_common_nmi <= BANK1_COMMON_END, true
// huffman.s parks the corpus in the Bank 1 huffman segment; resume Default.
.segment Default
#import "../../../core/runtime_ui_strings.s"
#import "../common/compat/io_kernal_consts.s"
#import "hal/storage_policy.s"
#if C128_REAL_BOOT_DIAG
// Diag variants exclude score file I/O: the boot/crash scenarios never
// reach the death flow that calls it (tramp_game_over), and the guard
// instrumentation needs the Default bytes. Constants/state stay so the
// DeathOverlay hiscore_insert path still links.
.const HISCORE_ENTRY_SIZE = 23
.const HISCORE_MAX_ENTRIES = 10
.label hiscore_table = CREATURE_BASE
hiscore_count:  .byte 0
.label hiscore_io_count_lo = save_count_lo
.label hiscore_io_count_hi = save_count_hi
hiscore_load:
hiscore_save:
    rts
#else
#import "../../../core/score_io.s"
#endif

#import "../common/disk_swap.s"

.segment Default
#import "../../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#define CHEST_ROUTING_ENABLED
// Door-state table, runtime helpers, and place_secrets live in Bank 0 Default
// (`moria128.prg`, `$1C01..<$AF00`).
#define DOOR_STATE_IN_DEFAULT_IMAGE
.macro DoorStateSegment() {
    .segment Default
}
.macro DoorStateRestoreSegment() {
    .segment Default
}
// CmdJamSegment rides cold StorageOverlay; game_loop.s reaches it via tramp_cmd_jam.
#define CMD_JAM_EXTERNAL
#define CMD_JAM_SEGMENT_CUSTOM
.macro CmdJamSegment() {
    .segment StorageOverlay
}
.macro CmdJamRestoreSegment() {
    .segment Default
}
// The locked-door pick roll shares the cached Disarm overlay with the
// effective-disarm formula, avoiding the cold Chest overlay.
#define DOOR_PICK_EXTERNAL
#define DOOR_PICK_USE_DISARM_HELPER
.macro DoorPickSegment() {
    .segment DisarmOverlay
}
.macro DoorPickRestoreSegment() {
    .segment Default
}
#import "../../../core/dungeon_features.s"
#undef DOOR_PICK_USE_DISARM_HELPER
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#define MONSTER_DEATH_EXTERNAL
#import "../../../core/monster.s"
// C128 play payload is full, so the door-close refusal helper lives in the
// world payload near its only caller (door_try_close). The suffix string
// stays with the other combat strings in C128ResidentItems.
combat_msg_monster_in_way:
    jsr monster_get_ptr         // zp_ptr0 = entry
    ldy #MX_TYPE
    lda (zp_ptr0),y
    sta cmb_type
    lda #<cmb_in_way_str
    ldy #>cmb_in_way_str
    jmp combat_msg_monster_suffix
#import "hal/storage_drive.s"
#import "hal/storage_tier_names.s"
#import "monster_catalog128.s"
#import "../../../core/monster_catalog.s"
#import "../../../core/tier_manager.s"
#import "../common/overlay.s"
#import "../../../core/monster_ai.s"

#import "look_trampoline.s"

// C128 keeps infravision helpers in the resident world payload so VDC rendering
// can call them without increasing the byte-tight 128.play segment.
player_get_infra_range:
    ldx zp_player_race
    lda #RACE_PROP_SIZE
    jsr math_multiply
    ldx zp_math_a
    lda race_properties + 1,x
    ldx zp_eff_infra
    beq !pgir_done+
    clc
    adc #1
!pgir_done:
    rts

#import "../../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#define FULL_DETECT_EVIL_EFFECT
#define EFF_FIND_DOORS_EXTERNAL
.segment Default
.macro ChestSearchSegment() {
    .segment Default
}
.macro ChestSearchRestoreSegment() {
    .segment Default
}
#import "../../../core/chest_search.s"

#import "../../../core/scene_mat_tile.s"
#import "../../../core/scene_force.s"
#define WALL_TO_MUD_SEGMENT_CUSTOM
.macro WallToMudSegment() {
    .segment DeathOverlay
}
.macro WallToMudRestoreSegment() {
    .segment Default
}
#import "../../../core/spell_effects.s"
#undef WALL_TO_MUD_SEGMENT_CUSTOM
#import "../../../core/spell_effects_overlay.s"
// turn.s's regen/poison tables in bank-0 World RAM: C128ResidentPlay has no
// room (#importonce: turn.s's own import is then a no-op).
#import "../../../core/turn_data.s"
#undef FULL_DETECT_EVIL_EFFECT
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
cmb_you_str:     .text "You " ; .byte 0
cmb_the_str:     .text " the " ; .byte 0
cmb_hit_str:     .text "hit" ; .byte 0
cmb_miss_str:    .text "miss" ; .byte 0
cmb_kill_str:    .text "have slain" ; .byte 0
cmb_period:      .byte $2e, 0
cmb_the_cap_str: .text "The " ; .byte 0
cmb_shudders_str:
    .text " shudders." ; .byte 0
cmb_dissolves_str:
    .text " dissolves!" ; .byte 0
cmb_in_way_str:
    .text " is in your way!" ; .byte 0

// C128 cache/overlay state is loaded with the always-resident world payload.
// Keeping it out of the default image preserves the hard $6000 boundary while
// leaving the state in Bank 0 below the overlay window.
c128_cache_state_start:
c128_cache_enabled:        .byte 1
c128_cache_tiers_ready:    .byte 0
c128_cache_overlays_ready: .byte 0
c128_cache_failed:         .byte 0
c128_cache_tier_bits:      .byte 0
c128_cache_overlay_bits:   .byte 0
c128_cache_overlay_bits_hi: .byte 0   // Overlay IDs 9+ (modal-misc)
c128_preload_fn_len:       .byte 0
c128_preload_status:       .byte 0
#if C128_CACHE_TEST_SKIP_TIER
c128_cache_test_skip_tier: .byte 1
#else
c128_cache_test_skip_tier: .byte 0
#endif
#if C128_CACHE_TEST_SKIP_OVERLAY
c128_cache_test_skip_overlay: .byte 2
#else
c128_cache_test_skip_overlay: .byte 0
#endif
c128_startup_overlay_executing: .byte 0

overlay_state_block_start:
current_overlay: .byte 0
#import "hal/storage_overlay_names.s"
ol_target:        .byte 0
#if C128_TEST_OVERLAY_LOAD_FAIL_TRAP
c128_overlay_load_disk_index:  .byte 0
c128_overlay_load_disk_target: .byte 0
c128_overlay_load_disk_len:    .byte 0
c128_overlay_load_disk_lo:     .byte 0
c128_overlay_load_disk_hi:     .byte 0
c128_tramp_player_create_overlay_req: .byte 0
c128_overlay_load_entry_req:          .byte 0
c128_overlay_load_entry_target:       .byte 0
c128_preload_diag_stage:              .byte 0
c128_preload_diag_a:                  .byte 0
c128_preload_diag_x:                  .byte 0
c128_preload_diag_y:                  .byte 0
c128_preload_diag_status:             .byte 0
c128_preload_diag_readst:             .byte 0
c128_preload_diag_port1:              .byte 0
c128_preload_diag_mmu:                .byte 0
c128_preload_diag_pcra:               .byte 0
#endif
ol_save_p:        .byte 0
ol_status_p:      .byte 0
#if C128_TEST_OVERLAY_FN_GUARD
c128_overlay_fn_guard_stage:   .byte 0
c128_overlay_fn_guard_index:   .byte 0
c128_overlay_fn_guard_actual:  .byte 0
c128_overlay_fn_guard_expect:  .byte 0
#endif
overlay_state_block_end:
ovl_cache_base_lo: .byte 0
ovl_cache_base_hi: .byte 0
ovl_cache_pages:   .byte 0
ovl_ready_mask:
    .byte 0, %00000001, %00000010, %00000100, %00001000, %00010000, %00100000, %01000000, %10000000, 0, 0, 0, 0
ovl_ready_mask_hi:
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, %00000001, 0, 0, 0 // ID 9 = modal-misc; IDs 10..12 = chest/home/storage (cold)
c128_cache_state_end:
.assert "Overlay ready-mask tables cover all overlays", (ovl_ready_mask_hi - ovl_ready_mask) == hal_platform_overlay_count + 1 && (c128_cache_state_end - ovl_ready_mask_hi) == hal_platform_overlay_count + 1, true
#import "../../../core/dungeon_room_center_helpers.s"

.segment Default
death_source_saved:
    .byte 0
recall_query_sc:   .byte 0
recall_found_type: .byte 0
recall_last_sc:    .byte 0
recall_last_idx:   .byte 0
run_input_armed:   .byte 0
auto_rest_active:  .byte 0
ptep_temp: .byte 0
tool_ego_prefix_hi:
    .byte >ego_tool_prefix_gnomish, >ego_tool_prefix_dwarven
    .byte >ego_tool_prefix_orcish,  >ego_tool_prefix_dwarven
    .macro ChestSummonsSegment() {
    .segment RuntimeBankedCode
}
.macro ChestSummonsRestoreSegment() {
    .segment Default
}
.macro ItemPickupSegment() {
    .segment StorageOverlay
}
.macro ItemPickupRestoreSegment() {
    .segment Default
}
#define RE_EQUIP_SEGMENT_CUSTOM
.macro ReEquipSegment() {
    .segment StorageOverlay
}
.macro ReEquipRestoreSegment() {
    .segment Default
}
#define INV_ADD_EXTERNAL   // inv_add.s rides RuntimeLowData ($1000+)
#import "../../../core/item.s"
#undef RE_EQUIP_SEGMENT_CUSTOM
#import "../../../core/chest_summons.s"
// Step-13 chest loot: latch + resident handoff stay on the C128 main image;
// loot_generate_pending rides ChestOverlay alongside pick_item_type_overlay.
.segment Default
.macro ChestLootSegment() {
    .segment ChestOverlay
}
.macro ChestLootRestoreSegment() {
    .segment Default
}
.macro ChestFixtureSegment() {
    .segment Default
}
.macro ChestFixtureRestoreSegment() {
    .segment Default
}
#import "../../../core/chest_loot.s"
// look_flash_target (C128M-010) stays in Bank 0 Default (< $AF00).
#import "../../../core/look_flash_target.s"
#define MON_ATK_ACID_EXTERNAL   // monster_attack.s (play payload) jumps to RuntimeBankedCode

// wizard_wall_walk_active rides the main image (freed by the corpus move);
// the play payload has no headroom for the chest summon hooks. Scripted/diag
// builds omit wizard.s and provide their own stub below, so only assemble the
// real one in normal builds (else it double-defines against the stub).
#if !C128_REAL_BOOT_DIAG && !C128_TEST_SCRIPTED_INPUT && !C128_TEST_SCRIPTED_SPELL && !C128_TEST_SCRIPTED_SPELL_CANCEL && !C128_TEST_SCRIPTED_BOOK_OVERLAY && !C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY && !C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY && !C128_TEST_SCRIPTED_SCROLL_SELECTOR && !C128_TEST_SCRIPTED_PRAYER && !C128_TEST_SCRIPTED_EXCHANGE_PRODUCT
wizard_wall_walk_active:
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    beq !inactive+
    lda wizard_wall_walk_enabled
    rts
!inactive:
    lda #0
    rts
#endif
    // Armour/crown/cursed-armour ego tables and sub-rollers ride StorageOverlay
    // (loaded by tramp_roll_ego_type while roll_ego_type stays in Default).
    #define EGO_ARMOUR_SEGMENT_CUSTOM
    .macro EgoArmourSegment() {
        .segment StorageOverlay
    }
    .macro EgoArmourRestoreSegment() {
        .segment Default
    }
    #define EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    .macro EgoArmourDataSegment() {
        .segment StorageOverlay
    }
    .macro EgoArmourDataRestoreSegment() {
        .segment Default
    }
    #define EGO_SUFFIX_STRINGS_EXTERNAL   // imported in the banked runtime (below)
    #import "../../../core/ego_items.s"
    #undef EGO_ARMOUR_DATA_SEGMENT_CUSTOM
    #undef EGO_ARMOUR_SEGMENT_CUSTOM
    #import "../../../core/store_data.s"

// The program-media probe (and its file name) lives in Bank 0 Default
// resident RAM (< $AF00, C128M-008/C128M-011).
// Detect program media on the selected save drive.
// Output: carry clear = program media present, carry set = not program media
disk_program_media_present:
#if C128_CARTRIDGE
    sec                             // Cartridge ROM holds program assets; save disk is never program media
    rts
#else
    lda program_device
    sta disk_temp
    lda save_device
    sta program_device
    jsr c128_program_play_exists
    php
    lda disk_temp
    sta program_device
    plp
    bcc !not_program+
    clc
    rts
!not_program:
    sec
    rts
#endif

c128_program_play_exists:
    // A status read cut short before its first digit (JiffyDOS) asks the
    // whole probe again: closing channel 15 closed the probe file too.
    lda #3
    sta c128_ppe_tries
!try:
    lda #c128_program_play_read_filename_len
    ldx #<c128_program_play_read_filename
    ldy #>c128_program_play_read_filename
    jsr w_setnam
    lda #C128_PROGRAM_PROBE_FILE_NUM
    ldx program_device
    ldy #0
    jsr w_setlfs
    jsr w_open
    bcs !missing+
    jsr c128_program_read_command_status
    jsr disk_command_status
    cmp #HAL_STORAGE_STATUS_OK
    bne !not_ok+
    sec
    bcs !done+
!not_ok:
    lda disk_diag_readst
    and #$02                    // read timeout
    beq !missing+
    lda disk_diag_cmd_status0
    eor #$30
    cmp #10                     // a digit: the drive answered
    bcc !missing+
    lda #C128_PROGRAM_PROBE_FILE_NUM
    jsr w_close
    jsr w_clrchn
    dec c128_ppe_tries
    bne !try-
!missing:
    clc
!done:
    php
    lda #C128_PROGRAM_PROBE_FILE_NUM
    jsr w_close
    jsr w_clrchn
    plp
    rts

c128_ppe_tries: .byte 0

c128_program_read_command_status:
    lda #$ff
    sta disk_diag_cmd_status0
    sta disk_diag_cmd_status1
    lda #0
    sta disk_diag_readst
    tax
    tay
    jsr w_setnam
    lda #C128_PROGRAM_CMD_FILE_NUM
    ldx program_device
    ldy #C128_PROGRAM_CMD_FILE_NUM
    jsr w_setlfs
    jsr w_open
    bcs !done+
    ldx #C128_PROGRAM_CMD_FILE_NUM
    jsr w_chkin
    bcs !close+
    jsr w_readst
    bne !close+
    jsr w_chrin
    sta disk_diag_cmd_status0
    jsr w_readst
    sta disk_diag_readst
    bne !close+
    jsr w_chrin
    sta disk_diag_cmd_status1
!close:
    jsr w_clrchn
    lda #C128_PROGRAM_CMD_FILE_NUM
    jsr w_close
!done:
    rts

c128_program_play_read_filename:
    .byte $30, $3a                              // "0:"
    .text "128.PLAY"
    .byte $2c, $50, $2c, $52                    // ",P,R"
.label c128_program_play_read_filename_len = * - c128_program_play_read_filename

.segment Default
#import "../../../build/trampolines/c128_trampolines.inc"

// Run a Phase 3 item effect from resident code. The caller is in OVL.ITEMS;
// the dispatch lives in OVL.MODAL_MISC and established handlers may briefly
// load OVL.DEATH. The return continuation remains resident throughout.
tramp_p3_dispatch_items:
    pha
    lda #OVL_MODAL_MISC
    jsr overlay_load
    bcs !failed+
    pla
    jsr irs_dispatch_p3_overlay
tramp_p3_dispatch_items_return:     // the modal handlers return here (scroll_p3_return_smoke)
    lda #OVL_ITEMS
    jsr overlay_load
    sec
    rts
!failed:
    pla
    sec
    rts


// Chest routing (docs/CHEST_DESIGN.md). tramp_chest_open is called from the
// resident cmd_open pre-dispatch. chest_dispatch is tail-called (A/Y =
// handler) from bash_command/disarm_command inside their overlays. Both ride
// the items payload (always resident in Bank 0): the main image has no
// headroom for them. chest_dispatch mirrors the production
// tramp_p3_dispatch_items overlay-to-overlay pattern: the KERNAL RAM stubs
// used by overlay_load preserve the operational MMU/$01 banking, so no bank
// save/restore is needed around the call. Carry from the handler propagates.
chest_dispatch:
    sta cd128_jmp+1
    sty cd128_jmp+2
    lda #C128_CHEST_OVERLAY_ID
    jsr overlay_load
    bcs !done+
cd128_jmp:
    jsr $0000               // SMC dispatch target (never JMP (addr))
!done:
    rts


.segment Default
// recall.s rides the Default image; the world payload funds the monster door
// engine in monster_ai.s.  Placed after monster.s (MAX_CREATURES) and before
// save.s (RECALL_DATA_SIZE).
#import "../../../core/recall.s"
.assert "Recall data size matches C128 Bank 1 allocation", RECALL_DATA_SIZE, BANK1_RECALL_SIZE

hal_recall_tmp_a: .byte 0
hal_recall_tmp_x: .byte 0
hal_recall_tmp_y: .byte 0

// hal_recall_read_byte — Input: recall_off_lo/hi. Output: A. Clobbers: A, Y (preserves X, ZP).
hal_recall_read_byte:
    stx hal_recall_tmp_x
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    clc
    lda #<BANK1_RECALL_BASE
    adc recall_off_lo
    sta zp_ptr0
    lda #>BANK1_RECALL_BASE
    adc recall_off_hi
    sta zp_ptr0_hi
    ldy #0
    jsr mmu_safe_db_read_ptr0
    tay
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    ldx hal_recall_tmp_x
    tya
    rts

// hal_recall_write_byte — Input: A = byte, recall_off_lo/hi. Clobbers: A, Y (preserves X, ZP).
hal_recall_write_byte:
    sta hal_recall_tmp_a
    stx hal_recall_tmp_x
    lda zp_ptr1
    pha
    lda zp_ptr1_hi
    pha
    clc
    lda #<BANK1_RECALL_BASE
    adc recall_off_lo
    sta zp_ptr1
    lda #>BANK1_RECALL_BASE
    adc recall_off_hi
    sta zp_ptr1_hi
    ldy #0
    lda hal_recall_tmp_a
    jsr mmu_safe_db_write_ptr1
    pla
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    ldx hal_recall_tmp_x
    rts

// recall_clear_all — Zero Bank 1 persistent recall BSS ($7400-$785B) at cold boot.
recall_clear_all:
    lda zp_ptr1
    pha
    lda zp_ptr1_hi
    pha
    lda #<BANK1_RECALL_BASE
    sta zp_ptr1
    lda #>BANK1_RECALL_BASE
    sta zp_ptr1_hi
    ldx #>BANK1_RECALL_SIZE
    beq !rca_rem+
    ldy #0
!rca_page:
    stx hal_recall_tmp_x
    sty hal_recall_tmp_y
    lda #0
    jsr mmu_safe_db_write_ptr1
    ldx hal_recall_tmp_x
    ldy hal_recall_tmp_y
    iny
    bne !rca_page-
    inc zp_ptr1_hi
    dex
    bne !rca_page-
!rca_rem:
    ldy #<BANK1_RECALL_SIZE
    beq !rca_done+
!rca_tail:
    dey
    sty hal_recall_tmp_y
    lda #0
    jsr mmu_safe_db_write_ptr1
    ldy hal_recall_tmp_y
    bne !rca_tail-
!rca_done:
    pla
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    rts

#define ITEM_CAT_MAP_CUSTOM
#if C128_CARTRIDGE
#define ITEM_CATALOG_CART
#else
#define ITEM_CAT_BUF_EXTERNAL
.label ITEM_CAT_BUF_BASE = CREATURE_BASE
// Keep MMU_ALL_RAM ($3E) active during ITEM.CAT IEC reads so top-common RAM
// w_* wrappers ($FFB7-$FFD5, including w_close's explicit CLC before $FFC3)
// handle KERNAL calls without shadowing $C000-$CFFF (numeric_format_u8).
.macro ItemCatKernalIn() {
}
.macro ItemCatMap() {
}
.macro ItemCatUnmap() {
}
.macro ItemCatKernalOut() {
    lda $d030
    ora #$01
    sta $d030
}
#endif
#import "../common/item_catalog_records.s"
#if !C128_CARTRIDGE
c128_copy_item_idx_data:
    ldy #ITMCAT_IDX_BODY_SIZE - 1
!item_idx_copy:
    lda ITEM_IDX_LOAD_ADDR,y
    sta item_cat_idx_data,y
    dey
    bpl !item_idx_copy-
    rts
#endif
#if C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY
c128_test_seed_scripted_spell_state:
    lda #0
    sta c128_test_spell_success_count
    sta c128_test_spell_return_pending
    sta c128_test_spell_return_count
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta player_data + PL_SPELLS_FORGOTTEN_0
    sta player_data + PL_SPELLS_FORGOTTEN_1
    sta player_data + PL_SPELLS_FORGOTTEN_2
    sta player_data + PL_SPELLS_FORGOTTEN_3
#if C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY
    lda #1
#else
    lda #0
#endif
    sta player_data + PL_NEW_SPELLS
    lda #99
    ldx #31
!c128_test_spell_order_clear:
    sta player_data + PL_SPELL_ORDER,x
    dex
    bpl !c128_test_spell_order_clear-
    lda #0
    sta player_data + PL_SPELL_ORDER
    rts
#endif

// C128 resident UI transition helpers and selector strings (< $AF00).
// ui_prepare_fullscreen_transition — clear the screen and reset message-row
// state before a C128 full-screen prompt or status transition.
ui_prepare_fullscreen_transition:
    jsr hal_screen_clear
    jsr ui_reset_message_state
    rts

welcome_str:
    .text "Welcome to Moria! ?=help. Shift+Q=quit." ; .byte 0
search_mode_on_str:
    .text "Search mode on." ; .byte 0
search_mode_off_str:
    .text "Search mode off." ; .byte 0
descend_str:
    .text "You descend the staircase." ; .byte 0
ascend_str:
    .text "You ascend the staircase." ; .byte 0
uinv_title_str:
    .text "Inventory" ; .byte 0
uinv_sep_str:
    .text "---------" ; .byte 0

#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#define PLAYER_RECALC_EQUIPMENT_EXTERNAL
#define PLAYER_ITEM_COMMANDS_EXTERNAL
// Potion heal/cure effects go to the banked runtime with the quaff code.
#define EFF_POTION_CURE_EXTERNAL
#import "../../../core/player_items.s"
#undef PLAYER_ITEM_COMMANDS_EXTERNAL
#undef PLAYER_RECALC_EQUIPMENT_EXTERNAL

.segment C128ResidentPersist
c128_resident_persist_start:
#import "../../shared/save.s"
save_prepare_slot_prompt:
    clc
    rts
#import "../common/save_slot_menu.s"
#import "../../../core/ui_disk_setup.s"
c128_resident_persist_end:

#define PRESS_KEY_STR_EXTERNAL
#define WELCOME_STR_EXTERNAL
#define GAME_LOOP_NAV_STRINGS_EXTERNAL
#define GAME_LOOP_NO_STAIRS_STR_EXTERNAL
#define GAME_LOOP_LOW_DATA_EXTERNAL
.segment C128ResidentPlay
c128_resident_play_start:
c128_resident_play_sig0:
    .byte C128_RESIDENT_PLAY_SIG0
c128_resident_play_sig1:
    .byte C128_RESIDENT_PLAY_SIG1
c128_resident_play_sig2:
    .byte C128_RESIDENT_PLAY_SIG2
c128_resident_play_body:
#define C128_PRODUCT_PLAY_SEGMENT
#import "../../../core/dungeon_los.s"
#undef C128_PRODUCT_PLAY_SEGMENT
#import "../../../core/monster_attack.s"
#define PMU_TURN_FEEDBACK_EXTERNAL
#define COMBAT_COMMON_HELPERS_EXTERNAL
#define COMBAT_STRINGS_EXTERNAL
#define CMB_IN_WAY_EXTERNAL
#define CMB_WINNER_STR_EXTERNAL
#define LEVELUP_MAGIC_PENDING_EXTERNAL
#import "../../../core/combat.s"
#undef LEVELUP_MAGIC_PENDING_EXTERNAL
#undef CMB_WINNER_STR_EXTERNAL
#undef CMB_IN_WAY_EXTERNAL
#undef COMBAT_STRINGS_EXTERNAL
#undef COMBAT_COMMON_HELPERS_EXTERNAL
#undef PMU_TURN_FEEDBACK_EXTERNAL
.macro PlayerMoveRestoreResidentSegment() {
    .segment C128ResidentPlay
}
.macro PlayerMoveLookSegment() {
    .segment HelpOverlay
}
#define PLAYER_LOOK_EXTERNAL
#define PLAYER_LOOK_SCRATCH_RESIDENT
#import "../../../core/player_move.s"
#undef PLAYER_LOOK_SCRATCH_RESIDENT
// player_run uses pm_live_occ_x/y defined by the preceding player_move import.
.macro PlayerRunInitializeSegment() {
    .segment ModalMiscOverlay
}
.macro PlayerRunRestoreResidentSegment() {
    .segment C128ResidentPlay
}
#define PLAYER_RUN_INITIALIZE_EXTERNAL
run_initialize:
    :C128OverlayComputeTrampoline(9, run_initialize_impl)
#import "../../../core/player_run.s"
#undef PLAYER_RUN_INITIALIZE_EXTERNAL
#define HELP_TITLE_EXTERNAL
#import "../../../core/ui_help_clear.s"
#undef HELP_TITLE_EXTERNAL
#if C128_REAL_BOOT_DIAG || C128_TEST_SCRIPTED_INPUT || C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SCROLL_SELECTOR || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_EXCHANGE_PRODUCT
// Scripted/diag test variants exclude wizard mode: those scenarios never enter
// wizard commands, and the test instrumentation needs the Play payload bytes.
// Stubs keep the command-dispatch and game-loop references linkable.
wizard_reset_session_state:
cmd_wizard_entry:
    rts
wizard_level_jump_active:
    .byte 0
wizard_wall_walk_active:
    lda #0
    rts
// These builds omit wizard.s, but scroll effects still require the resident
// teleport-level tail to remain linkable.
scroll_teleport_level_exec:
    rts
#else
#define WIZARD_WALL_WALK_EXTERNAL
#define WIZARD_PROMPT_HELPERS_EXTERNAL
#import "../../../core/wizard.s"
#undef WIZARD_PROMPT_HELPERS_EXTERNAL
#undef WIZARD_WALL_WALK_EXTERNAL
#endif
#define C128_SCRIPTED_SPELL_SEED_EXTERNAL
#define DISARM_COMMAND_EXTERNAL
#define CMD_JAM_WRAPPER_CUSTOM
.macro CmdJamWrapperSegment() {
    .segment RuntimeBankedCode
}
.macro CmdJamWrapperRestoreSegment() {
    .segment C128ResidentPlay
}
#import "../../../core/game_loop.s"
#undef CMD_JAM_WRAPPER_CUSTOM
#undef DISARM_COMMAND_EXTERNAL
#undef C128_SCRIPTED_SPELL_SEED_EXTERNAL
// The items payload's end label is at the end of this file: the chest open
// pre-dispatch (ChestRouteSegment) and later imports add to it past here.
.segment Default
// Recall prompt and equip-stat helper stay in Bank 0 Default (< $AF00,
// C128M-010/C128M-011).
recall_prompt_str:
    .text "Recall which? " ; .byte 0
#import "../../../core/player_adjust_equipment_stat.s"
.segment C128ResidentPlay
#import "../../../core/turn.s"
c128_resident_play_end:

.segment Default


#if C128_TEST_TITLE_ART_CONTENT
c128_test_title_art_assert:
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    ldy #0
    jsr mmu_safe_map_read_ptr1
    cmp #1
    beq !check_screen+
    sta c128_test_title_art_fail_code
    lda #$10
    sta c128_test_title_art_substage
    jmp c128_test_title_art_fail_sym
!check_screen:
    lda #1
    sta zp_cursor_row
    lda #21
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$2b
    beq !check_logo+
    sta c128_test_title_art_fail_code
    lda #1
    sta c128_test_title_art_substage
    jmp c128_test_title_art_fail_sym
!check_logo:

    lda #3
    sta zp_cursor_row
    lda #24
    sta zp_cursor_col
    jsr screen_set_cursor
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #$20
    bne !block_fail+
    lda zp_color_hi
    ldy zp_color_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    cmp #(VDC_WHITE | $40)
    beq !pass+
!block_fail:
    sta c128_test_title_art_fail_code
    lda #2
    sta c128_test_title_art_substage
    jmp c128_test_title_art_fail_sym

!pass:
    jmp c128_test_title_art_pass_sym
#endif
#if C128_TEST_TITLE_KEY_TRAP
title_key_trap_base:
    .fill 256, $00
#endif
#if C128_TEST_SCRIPTED_INPUT
c128_test_summary_seen:
    .byte 0
c128_test_summary_count:
    .byte 0
#endif

#if C128_CACHE_TEST_SKIP_TIER || C128_CACHE_TEST_SKIP_OVERLAY
c128_test_expected_tier_bits:
#if HAL_PLATFORM_MONSTER_CATALOG
    lda #0                          // The catalog has no tiers
#else
    lda #%00001111
#endif
#if C128_CACHE_TEST_SKIP_TIER
    ldx c128_cache_test_skip_tier
    beq !ctet_done+
    eor c128_tier_ready_mask_minus1,x
!ctet_done:
#endif
    rts

c128_test_expected_overlay_bits:
#if HAL_PLATFORM_MONSTER_CATALOG
    lda #%11111110                  // STARTUP (bit 0) is not cached
#else
    lda #%11111111
#endif
#if C128_CACHE_TEST_SKIP_OVERLAY
    ldx c128_cache_test_skip_overlay
    beq !cteo_done+
    eor ovl_ready_mask,x
!cteo_done:
#endif
    rts

c128_test_expected_overlay_bits_hi:
    lda #%00000001
#if C128_CACHE_TEST_SKIP_OVERLAY
    ldx c128_cache_test_skip_overlay
    beq !cteo_hi_done+
    eor ovl_ready_mask_hi,x
!cteo_hi_done:
#endif
    rts

// The tier and overlay partial-state checks differ only in the tiers-ready
// flag expected: one body, entered with it in A.
c128_test_validate_tier_partial_state:
    lda #1
    bne c128_test_validate_partial_state      // always
c128_test_validate_overlay_partial_state:
#if HAL_PLATFORM_MONSTER_CATALOG
    lda #0
#else
    lda #1
#endif
c128_test_validate_partial_state:
    cmp c128_cache_tiers_ready
    bne !ctv_fail+
    jsr c128_test_expected_tier_bits
    cmp c128_cache_tier_bits
    bne !ctv_fail+
    lda c128_cache_overlays_ready
    cmp #1
    bne !ctv_fail+
    jsr c128_test_expected_overlay_bits
    cmp c128_cache_overlay_bits
    bne !ctv_fail+
    jsr c128_test_expected_overlay_bits_hi
    cmp c128_cache_overlay_bits_hi
    bne !ctv_fail+
    clc
    rts
!ctv_fail:
    sec
    rts
#endif

#if C128_TEST_VIC40_BLANKED_BOOT
// In Default with its caller: RuntimeLowData has 5 bytes free below
// FLOOR_ITEM_BASE, too few for the probe.
// boot128 blanks the VIC display ($D011 = 0) and the 80-column game never
// turns it on, so nothing can show on the 40-column screen: the display
// must still be off when the game starts.
c128_vic40_boot_probe:
    lda $d011
    and #$10                    // DEN
    bne c128_vic40_boot_probe_fail_sym

    // And nothing was drawn on the screen the VIC reads ($0400; bit 0
    // is unused and reads 1) to show if the display came on.
    lda $d018
    and #$fe
    cmp #$14
    bne c128_vic40_boot_probe_fail_sym
    ldx #0
!vic40_screen_loop:
    lda $0400,x
    cmp #$20                    // boot clears it to spaces
    bne c128_vic40_boot_probe_fail_sym
    inx
    cpx #$40
    bne !vic40_screen_loop-
    // Colour RAM is not checked: nothing writes it while the display is
    // off, so it keeps its power-on pattern.

    jmp c128_vic40_boot_probe_pass_sym

c128_vic40_boot_probe_pass_sym:
    nop
    jmp c128_vic40_boot_probe_pass_sym

c128_vic40_boot_probe_fail_sym:
    nop
    jmp c128_vic40_boot_probe_fail_sym
#endif

.segment RuntimeCommonData
.pseudopc $0d60 {
runtime_common_data_start:
    #import "title_cache_runtime.s"
    #import "restart128.s"
    #import "../../../core/player_magic_slow_runtime.s"
    #import "../../../core/player_magic_state.s"
    #define PMU_TURN_FEEDBACK_ONLY
    #import "../../../core/player_magic_turn_banked.s"
    #undef PMU_TURN_FEEDBACK_ONLY

player_str_tohit_adj:
    cmp #4
    bcc player_adj_m3
    cmp #5
    bcc player_adj_m2
    cmp #7
    bcc player_adj_m1
    cmp #18
    bcc player_adj_0
    cmp #94
    bcc player_adj_1
    cmp #109
    bcc player_adj_2
    cmp #117
    bcc player_adj_3
    bcs player_adj_4

player_str_damage_adj:
    cmp #4
    bcc player_adj_m2
    cmp #5
    bcc player_adj_m1
    cmp #16
    bcc player_adj_0
    cmp #17
    bcc player_adj_1
    cmp #18
    bcc player_adj_2
    cmp #94
    bcc player_adj_3
    cmp #109
    bcc player_adj_4
    cmp #117
    bcc player_adj_5
    bcs player_adj_6

player_dex_tohit_adj:
    cmp #4
    bcc player_adj_m3
    cmp #6
    bcc player_adj_m2
    cmp #8
    bcc player_adj_m1
    cmp #16
    bcc player_adj_0
    cmp #17
    bcc player_adj_1
    cmp #18
    bcc player_adj_2
    cmp #69
    bcc player_adj_3
    cmp #118
    bcc player_adj_4
    bcs player_adj_5

// One return sled, midway so every branch above and below reaches it
// (a second copy, player_adj_*, cost 30 bytes until 2026-11-07).
player_adj_m4:
    lda #<-4
    rts
player_adj_m3:
    lda #<-3
    rts
player_adj_m2:
    lda #<-2
    rts
player_adj_m1:
    lda #<-1
    rts
player_adj_0:
    lda #0
    rts
player_adj_1:
    lda #1
    rts
player_adj_2:
    lda #2
    rts
player_adj_3:
    lda #3
    rts
player_adj_4:
    lda #4
    rts
player_adj_5:
    lda #5
    rts
player_adj_6:
    lda #6
    rts


player_dex_ac_adj:
    cmp #4
    bcc player_adj_m4
    cmp #5
    bcc player_adj_m3
    cmp #6
    bcc player_adj_m2
    cmp #7
    bcc player_adj_m1
    cmp #15
    bcc player_adj_0
    cmp #18
    bcc player_adj_1
    cmp #59
    bcc player_adj_2
    cmp #94
    bcc player_adj_3
    cmp #117
    bcc player_adj_4
    bcs player_adj_5

player_con_hp_adj:
    cmp #7
    bcs !check17+
    sec
    sbc #7
    rts
!check17:
    cmp #17
    bcc player_adj_0
    cmp #18
    bcc player_adj_1
    cmp #94
    bcc player_adj_2
    cmp #117
    bcc player_adj_3
    bcs player_adj_4

combat_add_damage_bonus:
    lda player_data + PL_TODMG
    bmi !cadb_neg+
    clc
    adc cmb_damage
    bcc !cadb_store+
    lda #255
    bne !cadb_store+
!cadb_neg:
    clc
    adc cmb_damage
    bpl !cadb_store+
    lda #0
!cadb_store:
    sta cmb_damage
    rts

    #import "../../../core/special_rooms_find.s"

runtime_common_data_end:
}
.segment Default

// C128 save-media setup and disk-I/O diagnostics (Default < $AF00,
// below ROM-shadowed regions and $B000 boot clear).
    #import "hal/storage.s"
    #import "../common/disk_setup_runtime128.s"

// Shared modal footer text must stay outside the C128 PLAY/PERSIST slot.
// Disk Setup and one-drive swap prompts can run while either modal payload
// owns $AF00, so overlay code must not point into that window for this string.
press_key_str:
    .text "Press any key" ; .byte 0
press_key_str_end:

// The death message (core/game_loop.s, Bank 0 code) is read-only data. It
// moved here from 128.item, which the 33-slot inventory arrays filled.
slain_str:
    .text "You have been slain." ; .byte 0
slain_str_end:

// Always-resident Staff of Speed trampoline: the items overlay calls this
// while either PLAY or PERSIST owns the $AF00 modal slot.
tramp_staff_speed_items:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !staff_speed_done+
    jsr eff_staff_speed
    lda #OVL_ITEMS
    jsr overlay_load
!staff_speed_done:
    sec
    rts

// Keep combat blow summary in resident Bank 0 (< $AF00):
combat_append_blow_summary:
    lda cmb_blow_count
    cmp #2
    bcs !cabs_do+
    rts
!cabs_do:
    dec cmb_buf_idx
    lda #$20
    jsr combat_append_char
    lda #$28
    jsr combat_append_char
    lda cmb_hit_count
    jsr combat_append_decimal
    lda #$2f
    jsr combat_append_char
    lda cmb_blow_count
    jsr combat_append_decimal
    lda #$29
    jsr combat_append_char
    lda #$2e
    jsr combat_append_char
    jsr combat_clamp_msg_idx
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
    rts

// Bow to-hit entry: resident Bank 0 RAM (callable from OVL.ITEMS while the
// modal slot holds either payload); parked outside DiskIo for space.
combat_calc_bow_tohit:
    lda player_data + PL_TOHIT
    sta cmb_total_tohit
    lda #4
    ldx #1
    jmp combat_calc_tohit_common

// tramp_p3_death_items — Run a death-overlay phase-3 effect, then return with// OVL.ITEMS resident. The phase-3 router executes in the modal-misc overlay
// and cannot swap to OVL_DEATH itself: the swap would evict its own
// continuation (the modal and death overlays do not mirror each other).
// Input: A = effect argument, tpdi_target+1/+2 = handler address in OVL_DEATH.
// Output: carry set = effect ran, carry clear = overlay load failed.
tramp_p3_death_items:
    sta tpdi_arg
    lda #OVL_DEATH
    jsr overlay_load
    bcs !tpdi_fail+
    lda tpdi_arg
    jsr tpdi_target
    lda #OVL_ITEMS
    jsr overlay_load
    sec
    rts
!tpdi_fail:
    clc
    rts
tpdi_arg: .byte 0
tpdi_target:
    jsr $0000                 // Operand patched by the modal-side dispatcher
    rts

// tramp_p3_death_cloud — Wand of Stinking Cloud needs monster post-processing
// after the death-overlay effect; run the whole sequence resident.
tramp_p3_death_cloud:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !tpdc_fail+
    jsr eff_directional_monster
    bcc !tpdc_miss+
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda #10
    sta (zp_ptr0),y
    ldx #HSTR_PIW_WAND_CLOUD
    jmp !tpdc_msg+
!tpdc_miss:
    ldx #HSTR_PIW_WAND_MISS
!tpdc_msg:
    jsr huff_print_msg
    lda #OVL_ITEMS
    jsr overlay_load
    sec
    rts
!tpdc_fail:
    clc
    rts

// tramp_p3_death_remove_curse — Staff of Remove Curse: death-overlay effect
// plus the cleansed report, all resident-safe.
tramp_p3_death_remove_curse:
    lda #OVL_DEATH
    jsr overlay_load
    bcs !tpdr_fail+
    jsr eff_remove_curse
    ldx #HSTR_PIQ_CLEANSED
    jsr huff_print_msg
    lda #OVL_ITEMS
    jsr overlay_load
    sec
    rts
!tpdr_fail:
    clc
    rts

// RuntimeProjectileData segment — shared projectile helpers loaded below
// runtime.input so the $F000 banked payload stays below the MMU register page.
.segment RuntimeProjectileData
.pseudopc $0a80 {
runtime_projectile_data_start:
    #import "../../../core/projectile.s"
runtime_projectile_data_end:
}
.segment Default

// RuntimeInputData segment — dedicated raw C128 run-input helpers loaded into
// the reclaimed boot-sector page after boot completes.
.segment RuntimeInputData
.pseudopc $0b00 {
runtime_input_data_start:
    #import "input_run_raw128.s"
runtime_input_data_end:
}
.segment Default

// RuntimeLowData segment — low-RAM resident code loaded into Bank 0 before title.
.label runtime_low_data_start = $1000
.segment RuntimeLowData
    #import "monster_threat_vdc.s"
    #import "dungeon_render_vdc.s"
winner_save_blocked_str:
    .text "Winner: Shift+Q to claim victory." ; .byte 0
at_surface_str:
    .text "You are already at the surface." ; .byte 0
no_stairs_str:
    .text "You see no stairs here." ; .byte 0
pmx_cure_poison_msg:
    lda zp_eff_poison
    beq !pcpm_done+
    lda #0
    sta zp_eff_poison
    ldx #HSTR_EFF_POISON_END
    jmp huff_print_msg
!pcpm_done:
    rts
runtime_low_data_end:
.segment Default

// ============================================================
// Banked code payload — external runtime PRG loaded directly to $F000.
// Runs in Bank 0 at $F000-$FFFA.
// Banked UI/logic functions live in Bank 0 and are accessible with
// $FF00=$3E (MMU_ALL_RAM).
//
// Keep $E000-$EFFF reserved for OVL_* (overlays). Banked UI/logic
// occupies the resident window at $F000-$FFFA. The source bytes are not
// staged inside the main PRG, so overlay loads cannot corrupt a recopy source.
// ============================================================
.segment RuntimeBankedCode
#import "map_row_store_common.s"
ego_tool_prefix_gnomish: .text "Gnomish " ; .byte 0
ego_tool_prefix_orcish:  .text "Orcish " ; .byte 0
ego_tool_prefix_dwarven: .text "Dwarven " ; .byte 0
#import "../../../core/ego_suffix_strings.s"
tool_ego_prefix_lo:
    .byte <ego_tool_prefix_gnomish, <ego_tool_prefix_dwarven
    .byte <ego_tool_prefix_orcish,  <ego_tool_prefix_dwarven
first_banked_function:
    #import "../../../core/item_desc_banked.s"
    #import "../../../core/player_magic_display.s"
    #import "../../../core/player_magic_state_ops.s"
    #import "../../../core/player_magic.s"
    #import "../../../core/player_magic_levelup.s"
    #import "../../../core/player_magic_learn_op.s"
    #import "../../../core/player_magic_tail.s"
    // The equipment flags come from player.s's player_recalc_pflags_equipment
    // in the main image (2026-11-11): the items payload's own copy went to make
    // room for the rings of Lordly Protection; the main image is visible here.
    #import "../../../core/player_recalc_equipment.s"
    #import "../../../core/monster_magic.s"
    #import "../../../core/monster_death.s"
    #import "../../../core/monster_acid.s"
    #import "../../../core/inv_add.s"
    #import "../../../core/eff_potion_cure.s"
combat_calc_melee_total_tohit_bonus:
    lda player_data + PL_TOHIT
    sta cmb_total_tohit

    lda inv_item_id + EQUIP_WEAPON
    cmp #FI_EMPTY
    beq !ccmt_unarmed+

    lda wield_missile_type
    bne !ccmt_done+
    lda wield_weight_lo
    ora wield_weight_hi
    beq !ccmt_unarmed+
    lda player_data + PL_STR_CUR
    ldx #15
    jsr math_multiply           // zp_math_b:zp_math_a = STR * 15
    lda zp_math_a
    sec
    sbc wield_weight_lo
    tay
    lda zp_math_b
    sbc wield_weight_hi
    bcs !ccmt_done+             // STR * 15 >= weapon_weight
    cmp #$ff
    bne !ccmt_cap_pen+
    tya
    bmi !ccmt_apply_pen+
!ccmt_cap_pen:
    lda #$80                    // Clamp heavy penalty to -128
!ccmt_apply_pen:
    clc
    adc cmb_total_tohit
    sta cmb_total_tohit
    rts

!ccmt_unarmed:
    lda cmb_total_tohit
    sec
    sbc #3
    sta cmb_total_tohit
!ccmt_done:
    rts

banked_code_end:
banked_payload_end:
.segment Default

.print "Banked payload: " + (banked_payload_end - banked_payload) + " bytes at $" + toHexString(banked_payload) + "-$" + toHexString(banked_payload_end)
.assert "Banked code fits below MMU register page", banked_code_end <= $FF00, true
.assert "C128 map row store helper lives in top common RAM", mmu_common_store_map_row >= $F000 && mmu_common_store_map_row < $FF00, true
.assert "C128 map span helper lives in top common RAM", mmu_common_and_map_span >= $F000 && mmu_common_and_map_span < $FF00, true
.assert "Banked payload starts above overlay window", first_banked_function >= $F000, true
.assert "Banked payload is emitted as external runtime PRG", banked_payload == $F000, true

// Title brand text is read by the UI-overlay title renderer, but it lives in
// Bank 0 Default (< $AF00) before program_end so UiOverlay keeps headroom and
// moria128.prg has zero trailing bytes past program_end.
title_str:
    .text "MORIA8 C128" ; .byte 0
cmb_winner_str:
    .text "You have won! Shift+Q to claim victory." ; .byte 0

// combat.s's flag, kept here: main_loop shifts it every pass, and in the PLAY
// payload it would land in PERSIST code whenever PERSIST holds the $AF00 slot.
levelup_magic_pending: .byte 0  // 1 = main_loop owes a mana/spell recalc (level-up)
.assert "levelup_magic_pending stays in the resident image, out of the $AF00 modal slot", levelup_magic_pending >= $1c01 && levelup_magic_pending < program_end, true

// Detect Doors/Stairs moved from C128ResidentPlay to Bank 0 Default (< $AF00)
// to relieve the $AF00 play payload while staying Bank 0 resident below I/O.
eff_fd_row: .byte 0

eff_find_doors:
    lda #1
    sta eff_fd_row
!efd_row_loop:
    lda eff_fd_row
    cmp #MAP_ROWS - 1
    bcs !efd_done+
    ldx eff_fd_row
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #1
!efd_col_loop:
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !efd_col_next+
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_DOOR_CLOSED
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!efd_col_next:
    iny
    cpy #MAP_COLS - 1
    bcc !efd_col_loop-
    inc eff_fd_row
    jmp !efd_row_loop-
!efd_done:
    lda #1
    sta vis_room_revealed
    rts

// ============================================================
// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.print "Persist payload: $" + toHexString(c128_resident_persist_start) + "-$" + toHexString(c128_resident_persist_end) + " (" + ($D000 - c128_resident_persist_end) + " B headroom < $D000)"
.print "Play payload: $" + toHexString(c128_resident_play_start) + "-$" + toHexString(c128_resident_play_end) + " (" + ($D000 - c128_resident_play_end) + " B headroom < $D000)"
.print "Common payload: $" + toHexString(runtime_common_data_start) + "-$" + toHexString(runtime_common_data_end) + " (" + ($1000 - runtime_common_data_end) + " B headroom < $1000)"
.print "Low payload: $" + toHexString(runtime_low_data_start) + "-$" + toHexString(runtime_low_data_end) + " (" + (FLOOR_ITEM_BASE - runtime_low_data_end) + " B headroom < FLOOR_ITEM_BASE)"
.print "Program image: $" + toHexString($1c01) + "-$" + toHexString(program_end - 1) + " (" + ($AF00 - program_end) + " B headroom < $AF00)"
#if C128
.assert "C128 consolidated Bank 0 resident image stays below $AF00 modal window (and boot128 $B000 clear)", program_end <= $AF00, true
.assert "Title brand text stays in Bank 0 resident image below $AF00", title_str >= $1c01 && title_str < program_end && program_end <= $AF00, true
.assert "C128 asset load retry stays in Default payload", asset_load_retry >= $1c01 && asset_load_retries < program_end, true
.assert "C128 tunnel guard stays in Default payload", dungeon_tunnel_guard_reset >= $1c01 && dungeon_tunnel_guard_step < program_end, true
.assert "C128 program-media probe stays in Bank 0 resident image below $AF00 (C128M-008/C128M-011)", disk_program_media_present >= $1c01 && c128_program_play_read_filename + c128_program_play_read_filename_len <= program_end && program_end <= $AF00, true
.assert "C128 look flash and equip-stat helper stay in Bank 0 resident image below $AF00 (C128M-010/C128M-011)", look_flash_target >= $1c01 && look_flash_target < program_end && player_adjust_equipment_stat >= $1c01 && player_adjust_equipment_stat < program_end && program_end <= $AF00, true
.assert "C128 Disk Setup stays in Bank 0 resident image below $AF00", disk_marker_init >= $1c01 && disk_setup_run >= $1c01 && disk_setup_run < program_end && program_end <= $AF00, true
.assert "C128 press-key footer stays in Bank 0 resident image below $AF00", press_key_str >= $1c01 && press_key_str_end <= program_end && program_end <= $AF00, true
.assert "C128 death message stays in Bank 0 resident image below $AF00", slain_str >= $1c01 && slain_str_end <= program_end && program_end <= $AF00, true
.assert "Inventory header strings stay in Bank 0 resident image below $AF00", uinv_title_str >= $1c01 && uinv_sep_str < program_end && program_end <= $AF00, true
.assert "C128 modal persist starts at $AF00", c128_resident_persist_start == $AF00, true
.assert "C128 save staging buffer is 128 bytes", save_stage_buf_end - save_stage_buf == 128, true
.assert "C128 save staging buffer lives in persist payload", save_stage_buf >= c128_resident_persist_start && save_stage_buf_end <= c128_resident_persist_end, true
.assert "C128 modal persist stays below the I/O hole", c128_resident_persist_end <= $D000, true
.assert "C128 modal persist stays below player_died/game-over in Play slot", c128_resident_persist_end <= player_died, true
#if !C128_REAL_BOOT_DIAG && !C128_TEST_SCRIPTED_INPUT && !C128_TEST_SCRIPTED_SPELL && !C128_TEST_SCRIPTED_SPELL_CANCEL && !C128_TEST_SCRIPTED_BOOK_OVERLAY && !C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY && !C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY && !C128_TEST_SCRIPTED_SCROLL_SELECTOR && !C128_TEST_SCRIPTED_PRAYER && !C128_TEST_SCRIPTED_EXCHANGE_PRODUCT
.assert "C128 modal persist stays below main_loop in Play slot", c128_resident_persist_end <= main_loop, true
.assert "Wizard item generation lives in banked payload", wizard_generate_item_execute >= banked_payload && wizard_generate_item_execute < banked_code_end, true
#endif
.assert "C128 item.idx load buffer avoids vic40 boot probe ($0400-$043F) and stays in SCREEN_RAM scratch ($0400-$07FF)", ITEM_IDX_LOAD_ADDR >= $0600 && ITEM_IDX_LOAD_ADDR + ITMCAT_IDX_BODY_SIZE <= $0800, true
.assert "C128 Disk Setup UI lives in persist payload", uds_show_insert_prompt >= c128_resident_persist_start && uds_show_insert_prompt < c128_resident_persist_end, true
.assert "C128 resident play starts at $AF00", c128_resident_play_start == $AF00, true
.assert "C128 resident play stays below the I/O hole", c128_resident_play_end <= $D000, true
.assert "Detect Doors/Stairs lives in Default resident image below $AF00", eff_find_doors >= $1c01 && eff_find_doors < program_end && program_end <= $AF00, true
.assert "Recall view body lives in cached UI overlay", recall_view_body >= $E000 && recall_view_body < ovl_ui_end, true
.assert "Staged Bank1 source span matches boot scrub ceiling", BANK1_STAGE_SOURCE_END == BANK1_RESERVED_TOP_END, true
.assert "Tier cache window remains large enough for tier preload", BANK1_TIER_CACHE_SIZE >= TIER_PRELOAD_REQUIRED, true
.assert "Tiers 1-4 fit the Bank 1 tier cache", TIER1_SIZE + TIER2_SIZE + TIER3_SIZE + TIER4_SIZE <= BANK1_TIER_CACHE_SIZE, true
.assert "MMU helper page stays inside common RAM ownership", MMU_COMMON_HELPERS_BASE >= BANK1_COMMON_BASE, true
.assert "MMU helper page ends inside common RAM ownership", MMU_COMMON_HELPERS_BASE + (mmu_common_helpers_blob_end - mmu_common_helpers_blob) - 1 <= BANK1_COMMON_END, true
.assert "C128 visibility row helper lives in common RAM", mmu_common_mark_visited_row_ptr0 >= MMU_COMMON_HELPERS_BASE && mmu_common_mark_visited_row_ptr0 < runtime_common_data_start, true
.assert "C128 visibility row helper flag literal matches FLAG_VISITED", FLAG_VISITED, $04
.assert "C128 shared row helper room flags literal matches FLAG_LIT|FLAG_VISITED", FLAG_LIT | FLAG_VISITED, $0c
.assert "Runtime common starts after MMU common helpers", runtime_common_data_start >= MMU_COMMON_HELPERS_BASE + (mmu_common_helpers_blob_end - mmu_common_helpers_blob), true
.assert "Runtime projectile helpers stay in pre-input low page", runtime_projectile_data_start >= $0a80 && runtime_projectile_data_end <= $0b00, true
.assert "Runtime input code stays inside boot-sector page ownership", runtime_input_data_start >= $0b00 && runtime_input_data_end <= $0c00, true
.assert "C128 FEAT-DISK common runtime stays in common RAM", runtime_common_data_end <= $1000, true
#if C128_CARTRIDGE
.assert "Exit trampoline stays below $4000 BASIC ROM window", exit_trampoline_end <= $4000, true
.assert "Runtime common ends before cartridge common chunk stub", runtime_common_data_end <= MMU_COMMON_CART_BASE, true
#endif
.assert "C128 disk marker logical file avoids runtime loader files", hal_storage_marker_file_num > RUNTIME_BANKED_FILE_NUM && hal_storage_marker_file_num != ITEM_IDX_FILE_NUM && hal_storage_marker_file_num < hal_storage_cmd_channel, true
.assert "C128 item-index logical file avoids marker and command channel", ITEM_IDX_FILE_NUM != hal_storage_marker_file_num && ITEM_IDX_FILE_NUM < hal_storage_cmd_channel, true
.assert "Low runtime code stays below floor-item table", runtime_low_data_end <= FLOOR_ITEM_BASE, true
.assert "Low runtime code stays below C128 scratch page", runtime_low_data_end <= CREATURE_BASE, true
.assert "C128 play signature starts payload", c128_resident_play_sig0 == c128_resident_play_start, true
.assert "C128 play signature is three bytes", c128_resident_play_body - c128_resident_play_sig0, 3
.assert "C128 play body follows signature", c128_resident_play_body == c128_resident_play_start + 3, true
.assert "Ego roll routine stays in Bank 0 resident image below $AF00", roll_ego_type >= $1c01 && roll_ego_type < program_end && program_end <= $AF00, true
.assert "Ego damage routine stays in Bank 0 resident image below $AF00", ego_apply_damage >= $1c01 && ego_apply_damage < program_end && program_end <= $AF00, true
.assert "Ego AC table stays in Bank 0 resident image below $AF00", ego_ac_bonus >= $1c01 && ego_ac_bonus < program_end && program_end <= $AF00, true
.assert "Digging-tool ego tail stays in resident PLAY payload", roll_tool_ego_check >= c128_resident_play_body && roll_tool_ego_check < c128_resident_play_end, true
.assert "Tool ego prefix printer stays in resident PLAY payload", put_tool_ego_prefix >= c128_resident_play_body && put_tool_ego_prefix < c128_resident_play_end, true
.assert "Cache state block stays in Bank0 program RAM", c128_cache_state_start >= $1c01, true
.assert "Cache state block ends before overlay window", c128_cache_state_end < $e000, true
.assert "Overlay state block starts in resident Bank0 RAM", overlay_state_block_start >= c128_cache_state_start && overlay_state_block_start < $e000, true
.assert "Overlay state block ends before overlay window", overlay_state_block_end < $e000, true
.assert "Overlay state block stays inside cache-state ownership", overlay_state_block_end <= c128_cache_state_end, true
#endif
.macro C128AuditBelowIo(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays below the I/O hole", symbol < $D000, true
}

.macro C128AuditOutOfIo(name, symbol, window_start) {
    .assert "AUDIT-IO-C128 " + name + " stays out of the I/O hole", symbol < $D000 || symbol >= window_start, true
}

.macro C128AuditRuntimeLow(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in runtime.low Bank 0 RAM", symbol >= runtime_low_data_start && symbol < runtime_low_data_end, true
}

.macro C128AuditRuntimeInput(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in runtime.input Bank 0 RAM", symbol >= runtime_input_data_start && symbol < runtime_input_data_end, true
}

.macro C128AuditRuntimeProjectile(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in runtime.projectile Bank 0 RAM", symbol >= runtime_projectile_data_start && symbol < runtime_projectile_data_end, true
}

.macro C128AuditStartupOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the startup overlay", symbol >= $E000 && symbol < ovl_start_end, true
}

.macro C128AuditTownOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the town overlay", symbol >= $E000 && symbol < ovl_town_end, true
}

.macro C128AuditDeathOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the death overlay", symbol >= $E000 && symbol < ovl_death_end, true
}

.macro C128AuditHelpOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the help overlay", symbol >= $E000 && symbol < ovl_help_end, true
}

.macro C128AuditUiOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the UI overlay", symbol >= $E000 && symbol < ovl_ui_end, true
}

.macro C128AuditItemsOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the items overlay", symbol >= $E000 && symbol < ovl_items_end, true
}

.macro C128AuditDefault(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the Default payload", symbol >= $1c01 && symbol < program_end, true
}

.macro C128AuditDisarmOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the disarm overlay", symbol >= $E000 && symbol < ovl_disarm_end, true
}

.macro C128AuditChestOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the chest overlay", symbol >= $E000 && symbol < ovl_chest_end, true
}

.macro C128AuditHomeOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the home overlay", symbol >= $E000 && symbol < ovl_home_end, true
}

.macro C128AuditStorageOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the storage overlay", symbol >= $E000 && symbol < ovl_storage_end, true
}

.macro C128AuditDungeonOverlay(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the dungeon overlay", symbol >= $E000 && symbol < ovl_gen_end, true
}

.macro C128AuditBanked(name, symbol) {
    .assert "AUDIT-IO-C128 " + name + " stays in the reloadable banked window", symbol >= $F000 && symbol < banked_code_end, true
}

#import "io_contracts.s"

.assert "Title menu string stays below I/O hole", title_menu_str < $D000, true
.assert "Save-disk indicator stays below I/O hole", ds_ind_pfx < $D000, true
.assert "Game-over prompt end stays below I/O hole", game_over_prompt_end < $D000, true
.assert "Message history buffer matches configured width", (msg_hist_idx - msg_history) == MSG_HIST_BYTES, true
.assert "VDC attribute mode keeps alternate charset enabled", VDC_ATTR_MODE == $80, true


// ============================================================
// Init-only code — lives past CREATURE_BASE, safe because it runs
// once at startup before dungeon map or RLE workspace are used.
// ============================================================

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
.segment TownOverlay
    #import "../../../core/store.s"
    #import "../../../core/ui_store.s"
    #import "../../../core/title_sysinfo_banked.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $f000, true

// ============================================================
// Startup overlay — character creation at $E000
// ============================================================
.segment StartupOverlay
    #import "../../../core/background_data.s"
    #import "../../../core/player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $f000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
.segment DeathOverlay
// The Fire Bolts and Drain Life effects (MON-031, 2026-11-11) beside the other
// Phase 3 wand handlers the death-overlay table calls (tramp_p3_death_items).
#import "../../../core/wand_bolt_entries.s"
    #import "../../../core/score.s"
    #define PMX_EARTHQUAKE_EXTERNAL
    #define PMX_MAP_AREA_EXTERNAL
    #define PMX_DETECT_EFFECTS_EXTERNAL
    #define PMX_DESTROY_AREA_EXTERNAL
    #import "../../../core/player_magic_execute_overlay.s"
    #undef PMX_DESTROY_AREA_EXTERNAL
    #undef PMX_DETECT_EFFECTS_EXTERNAL
    #undef PMX_MAP_AREA_EXTERNAL
    #undef PMX_EARTHQUAKE_EXTERNAL
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $f000, true

// ============================================================
// Modal-misc overlay — winner retirement art at $E000
// ============================================================
.segment ModalMiscOverlay
    #import "../../../core/royal.s"
    #define SCROLL_P3_NEW_OWNER
    #define SCROLL_P3_EXISTING_OWNER
    #import "../../../core/scroll_effects_p3.s"
    #undef SCROLL_P3_EXISTING_OWNER
    #undef SCROLL_P3_NEW_OWNER
ovl_modal_misc_end:
.print "Modal-misc overlay: " + (ovl_modal_misc_end - $e000) + " bytes at $E000-$" + toHexString(ovl_modal_misc_end)
.assert "Modal-misc overlay fits in $E000-$EFFF", ovl_modal_misc_end <= $f000, true

// ============================================================
// Help overlay — dedicated help screen at $E000
// ============================================================
.segment HelpOverlay
    #import "ui_help_data_80.s"
    #import "../../../core/ui_help_title.s"
    #import "../../../core/ui_help.s"
    .macro UiInventoryScratchSegment() { .segment RuntimeLowData }
    .macro UiInventoryCodeSegment() { .segment HelpOverlay }
    .macro UiEquipmentScratchSegment() { .segment RuntimeLowData }
    .macro UiEquipmentCodeSegment() { .segment HelpOverlay }
    #define UI_INVENTORY_SCRATCH_RESIDENT
    #define UI_INVENTORY_HEADER_STRINGS_EXTERNAL
    #define UI_EQUIPMENT_SCRATCH_RESIDENT
    #import "../../../core/ui_inventory.s"
    #import "../../../core/ui_equipment.s"
    #undef UI_EQUIPMENT_SCRATCH_RESIDENT
    #undef UI_INVENTORY_HEADER_STRINGS_EXTERNAL
    #undef UI_INVENTORY_SCRATCH_RESIDENT
    .segment RuntimeLowData
c128_ui_scratch_end:
    .segment HelpOverlay
ovl_help_end:
.print "Help overlay: " + (ovl_help_end - $e000) + " bytes at $E000-$" + toHexString(ovl_help_end)
.assert "Help overlay fits in $E000-$EFFF", ovl_help_end <= $f000, true
.assert "C128 resident UI scratch stays below floor-item storage", c128_ui_scratch_end <= FLOOR_ITEM_BASE, true

// ============================================================
// UI overlay — modal UI and symbol identify screens at $E000
// ============================================================
.segment UiOverlay
    #import "../../../core/ui_character.s"
    #import "../../../core/ui_recall.s"
#if C128_REAL_BOOT_DIAG || C128_TEST_SCRIPTED_INPUT || C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_STUDY_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SCROLL_SELECTOR || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_EXCHANGE_PRODUCT
// Scripted/diag test variants exclude the wizard UI with wizard mode (see
// Play payload).
ui_wizard_display:
    rts
#else
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
    #import "../../../core/ui_wizard.s"
#endif
    #import "../../../core/spell_names.s"
    #import "../../../core/player_magic_select_overlay.s"
    #import "../../../core/player_gain_spell.s"
    #import "../common/title_screen.s"
ovl_ui_end:
.print "UI overlay: " + (ovl_ui_end - $e000) + " bytes at $E000-$" + toHexString(ovl_ui_end)
.assert "UI overlay fits in $E000-$EFFF", ovl_ui_end <= $f000, true
.assert "Help title text stays inside help overlay", help_title_str >= $E000 && help_title_str < ovl_help_end, true
.assert "Help content table stays inside help overlay", help_lines >= $E000 && help_lines < ovl_help_end, true
.assert "LOOK command stays inside cached help overlay", do_look >= $E000 && do_look < ovl_help_end, true
.assert "LOOK cache ID is present in the generic overlay table", C128_HELP_OVERLAY_ID >= 1 && C128_HELP_OVERLAY_ID <= hal_platform_overlay_count, true

// ============================================================
// Item actions overlay — low-frequency read/aim/use/refuel commands
// ============================================================
.segment ItemActionsOverlay
    #define ITEM_ACTIONS_EARTHQUAKE_OWNER
    #define ITEM_ACTIONS_MAP_AREA_OWNER
    #define SCROLL_P3_ROUTER_ENABLED
    #import "../../../core/item_actions_overlay.s"
    #import "../../../core/ranged_fire.s"
    #import "../../../core/tunnel.s"
    #import "../../../core/throw.s"
    #import "../../../core/bash.s"
    #undef ITEM_ACTIONS_MAP_AREA_OWNER
    #undef ITEM_ACTIONS_EARTHQUAKE_OWNER
ovl_items_end:
.print "Items overlay: " + (ovl_items_end - $e000) + " bytes at $E000-$" + toHexString(ovl_items_end)
.assert "Items overlay fits in $E000-$EFFF", ovl_items_end <= $f000, true

// ============================================================
// Disarm overlay — direct trap disarm command and Umoria math
// ============================================================
.segment DisarmOverlay
    #import "../../../core/disarm.s"
    #import "../../../core/disarm_helpers.s"
ovl_disarm_end:
.print "Disarm overlay: " + (ovl_disarm_end - $e000) + " bytes at $E000-$" + toHexString(ovl_disarm_end)
.assert "Disarm overlay fits in $E000-$EFFF", ovl_disarm_end <= $f000, true
.assert "Disarm overlay fits in small Bank 1 cache pages", (ovl_disarm_end - $e000) <= (C128_OVERLAY_DISARM_CACHE_PAGES * $100), true
.assert "Modal-misc overlay fits in its Bank 1 cache slot", (ovl_modal_misc_end - $e000) <= (C128_OVERLAY_MODAL_CACHE_PAGES * $100), true
.assert "Disarm small cache pages fit non-common Bank 1 region", (BANK1_OVERLAY_DISARM_BASE + (C128_OVERLAY_DISARM_CACHE_PAGES * $100) - 1) <= BANK1_OVERLAY_DISARM_END, true

// ============================================================
// Chest overlay — chest open/disarm/bash handlers at $E000 (cold:
// no Bank 1 cache slot; boot preload skips it; disk load only)
// ============================================================
.segment ChestOverlay
    #import "../../../core/chest.s"
    // Store init/restock: transition-only (new game, town re-entry), moved
    // from the full items overlay for store stacking (2026-10-25). Reached
    // via tramp_store_init_all/tramp_store_restock_all; a disk load.
    #import "../../../core/store_restock_overlay.s"
    // Word of Destruction devastation engine: cold overlay home; reached via
    // resident tramp_eff_destroy_area (rare high-level spell, disk load is
    // acceptable). Spell-exec returns through c128_return_to_death_overlay.
    #import "../../../core/player_destroy_area.s"
ovl_chest_end:
.print "Chest overlay: " + (ovl_chest_end - $e000) + " bytes at $E000-$" + toHexString(ovl_chest_end)
.assert "Chest overlay fits in $E000-$EFFF", ovl_chest_end <= $f000, true

// ============================================================
// Home overlay — cold on-demand Player Home UI at $E000
// ============================================================
.segment HomeOverlay
    #import "../../../core/ui_home_text.s"
    #import "../../../core/ui_home.s"
    #import "../../../core/eff_item_p1.s"
winner_apply_retirement_bonus_storage:
    .const WIN_PL_LEVEL = 19
    .const WIN_PL_GOLD_0 = 43
    .const WIN_PL_GOLD_1 = 44
    .const WIN_PL_GOLD_2 = 45
    .const WIN_PL_XP_0 = 46
    .const WIN_PL_XP_1 = 47
    .const WIN_PL_XP_2 = 48
    lda player_data + WIN_PL_LEVEL
    cmp #41
    bcs !gold+
    clc
    adc #40
    sta player_data + WIN_PL_LEVEL
    sta zp_player_lvl
!gold:
    lda player_data + WIN_PL_GOLD_0
    clc
    adc #$90
    sta player_data + WIN_PL_GOLD_0
    lda player_data + WIN_PL_GOLD_1
    adc #$d0
    sta player_data + WIN_PL_GOLD_1
    lda player_data + WIN_PL_GOLD_2
    adc #$03
    sta player_data + WIN_PL_GOLD_2
    bcc !win_gold_capped+
    lda #$ff
    sta player_data + WIN_PL_GOLD_0
    sta player_data + WIN_PL_GOLD_1
    sta player_data + WIN_PL_GOLD_2
!win_gold_capped:
    lda player_data + WIN_PL_XP_0
    clc
    adc #$40
    sta player_data + WIN_PL_XP_0
    lda player_data + WIN_PL_XP_1
    adc #$4b
    sta player_data + WIN_PL_XP_1
    lda player_data + WIN_PL_XP_2
    adc #$4c
    sta player_data + WIN_PL_XP_2
    rts
ovl_home_end:
.print "Home overlay: " + (ovl_home_end - $e000) + " bytes at $E000-$" + toHexString(ovl_home_end)
.assert "Home overlay fits in $E000-$EFFF", ovl_home_end <= $f000, true

// ============================================================
// Storage/Auxiliary item overlay — cold on-demand item commands, enchantment,
// armour ego sub-tables, pickup, door jam, and exchange at $E000
// ============================================================
.segment StorageOverlay
    #import "../../../core/player_item_commands.s"
    #import "../../../core/item_exchange.s"
    #import "../../../core/eff_gain_stat.s"
hal_quaff_p3_dispatch:
c128_quaff_p3_dispatch:
    lda piw_item_id
    cmp #ITEM_TYPE_POT_GAIN_STR
    bcc !iqp3_not_gain+
    jmp eff_potion_gain_stat        // potions of gain stat (140-145)
!iqp3_not_gain:
    cmp #ITEM_TYPE_POT_HEALING
    beq !iqp3_healing+
    cmp #ITEM_TYPE_POT_RESTORATION
    beq !iqp3_restoration+
    cmp #ITEM_TYPE_POT_RESIST_HEAT
    beq !iqp3_resist_heat+
    cmp #ITEM_TYPE_POT_RESIST_COLD
    beq !iqp3_resist_cold+
    cmp #ITEM_TYPE_POT_CURE_CRITICAL
    beq !iqp3_cure_critical+
    cmp #ITEM_TYPE_POT_NEUTRALIZE
    beq !iqp3_neutralize+
    rts

!iqp3_healing:
    jmp eff_potion_healing          // 1000 HP + cures (eff_potion_cure.s)

!iqp3_cure_critical:
    lda #EFF_CURE_ALL
    ldx #7
    ldy #6
    jmp eff_potion_heal_cure

!iqp3_restoration:
    jsr player_calc_stats
    ldx #HSTR_PIQ_RESTORED
    jsr huff_print_msg
    rts

!iqp3_resist_heat:
    lda #10
    jsr rng_range
    sec
    adc #10
    clc
    adc zp_eff_resist
    bcc !iqp3_rh_store+
    lda #255
!iqp3_rh_store:
    sta zp_eff_resist
    rts

!iqp3_resist_cold:
    lda #10
    jsr rng_range
    sec
    adc #10
    clc
    adc eff_resist_cold_timer
    bcc !iqp3_rc_store+
    lda #255
!iqp3_rc_store:
    sta eff_resist_cold_timer
    rts

!iqp3_neutralize:
    jsr eff_cure_poison
    ldx #HSTR_EFF_POISON_END
    jsr huff_print_msg
    rts
ovl_storage_end:
.print "Storage overlay: " + (ovl_storage_end - $e000) + " bytes at $E000-$" + toHexString(ovl_storage_end)
.assert "Storage overlay fits in $E000-$EFFF", ovl_storage_end <= $f000, true

// ============================================================
// Dungeon generation overlay
// ============================================================
.segment DungeonGenOverlay
    #define DUNGEON_TUNNEL_HELPERS_EXTERNAL
    #import "../../../core/dungeon_gen.s"
    #undef DUNGEON_TUNNEL_HELPERS_EXTERNAL
    #import "../../../core/special_rooms.s"
ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $f000, true
.assert "banked_payload_start above overlay ceiling", first_banked_function > ovl_gen_end, true

// ============================================================
// Resident payload ends, past every import: an import that switches back
// into one of these segments adds to it after any earlier label.
// ============================================================

// Cold legal modal: workspace is reserved but not emitted to disk.
.segment LegalOverlay
#import "../../../core/ui_legal.s"
#if C128_CARTRIDGE
#import "legal_stream.s"
#else
#import "../../shared/legal_disk_stream.s"
#endif
legal_code_end:
.assert "Legal code stays below its modal workspace", legal_code_end <= legal_zp_save, true
.assert "Legal ZP snapshot stays below input cache", legal_zp_save + $8e <= legal_input_cache, true
.segment Default
.assert "No Default bytes emitted after program_end", * == program_end, true
