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
.const MMU_ALL_RAM      = $3E   // Bank 0, all RAM, I/O visible
                                // Bits 7-6=00(Bank0), 5-4=11(RAM), 3-2=11(RAM), 1=1(RAM), 0=0(I/O)
                                // Hides Screen Editor ROM ($C000-$CFFF) AND KERNAL ROM
                                // ($E000-$FFFF) via MMU.  I/O still visible at $D000.
                                // Used as permanent operational mode after init; JMP stubs
                                // at $FFB7-$FFD5 in Bank 0 RAM handle KERNAL calls.

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
//   - DB/data region:          $7400-$7FFF
//   - tier cache window:       $8000-$94F7
//   - reserved gap 0:          $94F8-$9FFF
//   - overlay cache STARTUP:   $A000-$AFFF
//   - overlay cache TOWN:      $B000-$BFFF
//   - overlay cache DEATH:     $C000-$CFFF
//   - reserved I/O-visible gap:$D000-$DFFF
//   - overlay cache DUNGEON:   $E000-$EFFF
//   - reserved top gap:        $F000-$FEFF
//
// boot128 staging source span before scrub:
//   - $1C01-$FEFF in Bank 1, copied into Bank 0 and scrubbed page-by-page.

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
.const BANK1_DB_END     = $7fff
.const BANK1_TIER_CACHE_BASE = $8000
.const BANK1_TIER_CACHE_SIZE = 5368
.const BANK1_TIER_CACHE_END  = BANK1_TIER_CACHE_BASE + BANK1_TIER_CACHE_SIZE - 1
.const BANK1_RESERVED_GAP0_BASE = $94f8
.const BANK1_RESERVED_GAP0_END  = $9fff
.const C128_TITLE_CACHE_VALID_MARKER = $a5
.const BANK1_TITLE_CACHE_MARKER_BASE = BANK1_RESERVED_GAP0_BASE
.const BANK1_TITLE_CACHE_DATA_BASE   = BANK1_TITLE_CACHE_MARKER_BASE + 1
.const BANK1_TITLE_CACHE_END         = BANK1_RESERVED_GAP0_END
.const BANK1_TITLE_CACHE_MAX_LEN     = BANK1_TITLE_CACHE_END - BANK1_TITLE_CACHE_DATA_BASE + 1
.const C128_TITLE_CACHE_MIN_REQUIRED = 593
.const BANK1_OVERLAY_STARTUP_BASE = $a000
.const BANK1_OVERLAY_STARTUP_END  = $afff
.const BANK1_OVERLAY_TOWN_BASE    = $b000
.const BANK1_OVERLAY_TOWN_END     = $bfff
.const BANK1_OVERLAY_DEATH_BASE   = $c000
.const BANK1_OVERLAY_DEATH_END    = $cfff
.const BANK1_RESERVED_IO_BASE     = $d000
.const BANK1_RESERVED_IO_END      = $dfff
.const BANK1_OVERLAY_DUNGEON_BASE = $e000
.const BANK1_OVERLAY_DUNGEON_END  = $efff
.const BANK1_RESERVED_TOP_BASE    = $f000
.const BANK1_RESERVED_TOP_END     = $feff
.const BANK1_CACHE_OWNED_BASE     = BANK1_TIER_CACHE_BASE
.const BANK1_CACHE_OWNED_END      = BANK1_RESERVED_TOP_END

.const MMU_SAVE_01           = $0c00
.const MMU_SAVE_FF00         = $0c01
.const KERNAL_NESTING_DEPTH  = $0c02
.const MMU_IRQ_SAVE_01       = $0c03
.const MMU_IRQ_SAVE_FF00     = $0c04
.const MMU_IRQ_SAVE_D506     = $0c05
.const MMU_COMMON_HELPERS_BASE = $0c06
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
.const FLOOR_ITEM_BASE  = $1a00 // Floor item table (Bank 0)
.const FLOOR_ITEM_END   = $1aff
.const CREATURE_BASE    = $1b00 // Runtime scratch area (Bank 0)
.const CREATURE_END     = $1bff
.const BANKED_DATA_BASE = $e000 // Item tiers, recall, spells (under KERNAL ROM)
.const BANKED_DATA_END  = $ffff
.const SCREEN_RAM       = $0400 // VIC-II screen RAM (used as scratch buffer on C128)
.const COLOR_RAM        = $d800 // VIC-II color RAM (VDC has separate attributes)
.const DUNGEON_GEN_BFS_QUEUE_BASE = SCREEN_RAM
.const DUNGEON_GEN_BFS_QUEUE_MAX  = 512
.const DUNGEON_GEN_BFS_QUEUE_END  = DUNGEON_GEN_BFS_QUEUE_BASE + (DUNGEON_GEN_BFS_QUEUE_MAX * 2) - 1

// ZP save buffer — stores $02–$8F during game, restored on exit.
// Keep this as owned program data (not a fixed low-RAM page), because
// native C128 KERNAL/BASIC workspace usage differs from C64.
.const ZP_SAVE_SIZE     = 142   // $02–$8F inclusive

zp_save_buf:
    .fill ZP_SAVE_SIZE, 0

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
    
#if C128_TEST_STACK_SLOT_DIAG
    // Diagnostic invariant check: ensure stack hasn't underflowed
    // A stray PLA or missing PHA will make SP too high.
    tsx
    cpx #$f0
    bcc !ex_stack_ok+       // SP < $F0 (Safe)
    jmp c128_stack_leak_trap
!ex_stack_ok:
#endif

#if C128_TEST_STACK_BOTTOM_DIAG
    :C128StackBottomCanaryCheck($91)
#endif

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

// ============================================================
// Diagnostics — Traps for fatal invariant failures
// ============================================================
c128_stack_leak_trap:
    lda #COL_RED
    sta $d020
    jmp *               // Clear JAM for stack leak (SP >= $F0 in ExitKernal)

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

// mmu_copy_map_row — Fast copy from Bank 1 MAP to MMU_LINE_BUF ($0400)
// Input: zp_ptr0/hi = source address in Bank 1
// Output: 38 bytes copied to $0400 in Bank 0
// Preserves: X
mmu_copy_map_row:
    jmp mmu_common_copy_map_row

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

// save_zp — Copy $02–$8F to zp_save_buf (original BASIC state)
save_zp:
    ldx #0
!loop:
    lda zp_temp0,x
    sta zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

// restore_zp — Copy zp_save_buf back to $02–$8F (original BASIC state)
restore_zp:
    ldx #0
!loop:
    lda zp_save_buf,x
    sta zp_temp0,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
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

bank1_overlay_cache_slot_lo:
    .byte 0, <BANK1_OVERLAY_STARTUP_BASE, <BANK1_OVERLAY_TOWN_BASE, <BANK1_OVERLAY_DEATH_BASE, <BANK1_OVERLAY_DUNGEON_BASE, <BANK1_OVERLAY_HELP_BASE, <BANK1_OVERLAY_UI_BASE, <BANK1_OVERLAY_ITEMS_BASE
bank1_overlay_cache_slot_hi:
    .byte 0, >BANK1_OVERLAY_STARTUP_BASE, >BANK1_OVERLAY_TOWN_BASE, >BANK1_OVERLAY_DEATH_BASE, >BANK1_OVERLAY_DUNGEON_BASE, >BANK1_OVERLAY_HELP_BASE, >BANK1_OVERLAY_UI_BASE, >BANK1_OVERLAY_ITEMS_BASE

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

mmu_common_map_read_ptr1:
    jsr mmu_common_select_bank1
    lda (zp_ptr1),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

mmu_common_map_write_ptr1:
    pha
    jsr mmu_common_select_bank1
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

mmu_common_db_read_ptr0:
    jsr mmu_common_select_bank1
    lda (zp_ptr0),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

mmu_common_db_write_ptr0:
    pha
    jsr mmu_common_select_bank1
    pla
    sta (zp_ptr0),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

mmu_common_db_read_ptr1:
    jsr mmu_common_select_bank1
    lda (zp_ptr1),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

mmu_common_db_write_ptr1:
    pha
    jsr mmu_common_select_bank1
    pla
    sta (zp_ptr1),y
    pha
    jsr mmu_common_select_bank0
    pla
    rts

mmu_common_copy_map_row:
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta SCREEN_RAM,y
    iny
    cpy #MMU_COPY_MAP_ROW_LEN
    bne !copy-
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts

mmu_common_select_bank1:
    php
    sei
    pla
    sta mmu_common_save_p
    lda #MMU_RAM_BANK1
    sta MMU_CR
    rts

mmu_common_select_bank0:
    lda #MMU_ALL_RAM
    sta MMU_CR
    lda mmu_common_save_p
    pha
    plp
    rts

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
}
mmu_common_helpers_blob_end:

// read_banked_byte_a000 — Read a byte from RAM under BASIC ROM
// Input:  zp_ptr0/zp_ptr0_hi = address in $A000–$BFFF
//         Y = offset from pointer
// Output: A = byte read
// Preserves: X, Y
read_banked_byte_a000:
    :BankOutBasic()
    lda (zp_ptr0),y
    pha
    :BankInBasic()
    pla
    rts

// read_banked_byte_e000 — Read a byte from Bank 1 RAM
// Input:  zp_ptr0/zp_ptr0_hi = address in $E000–$FFFF
//         Y = offset from pointer
// Output: A = byte read
// Preserves: X, Y
read_banked_byte_e000:
    sei
    lda #MMU_RAM_BANK1
    sta $ff00
    lda (zp_ptr0),y
    pha
    lda #MMU_ALL_RAM
    sta $ff00
    cli
    pla
    rts

// copy_to_e000 — Bulk copy to RAM under KERNAL ROM
// Input:  zp_ptr0 = source address (lo/hi)
//         zp_ptr1 = dest address in $E000–$FFFF (lo/hi)
//         zp_temp0 = byte count lo
//         zp_temp1 = byte count hi
// Preserves: nothing
copy_to_e000:
    ldy #0
    ldx zp_temp1        // Page counter (high byte of count)
    beq !partial+       // Less than 256 bytes
!page:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page-
!partial:
    ldx zp_temp0        // Remaining bytes (low byte of count)
    beq !done+
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail-
!done:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Live map size = 13068", MAP_END - MAP_BASE + 1, 13068
.assert "Reserved future map span = 13068", BANK1_MAP_RESERVED_END - MAP_BASE + 1, 13068
.assert "Floor items fit", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Dungeon-gen BFS queue remains page-aligned", <DUNGEON_GEN_BFS_QUEUE_BASE, 0
.assert "Dungeon-gen BFS queue stays in VIC scratch window", DUNGEON_GEN_BFS_QUEUE_END <= $07ff, true
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
:AssertRegionBefore("Tier cache ends before reserved gap 0", BANK1_TIER_CACHE_END, BANK1_RESERVED_GAP0_BASE)
:AssertRegionBefore("Reserved gap 0 ends before STARTUP overlay slot", BANK1_RESERVED_GAP0_END, BANK1_OVERLAY_STARTUP_BASE)
.assert "Title cache marker starts inside reserved gap 0", BANK1_TITLE_CACHE_MARKER_BASE >= BANK1_RESERVED_GAP0_BASE && BANK1_TITLE_CACHE_MARKER_BASE <= BANK1_RESERVED_GAP0_END, true
.assert "Title cache data ends inside reserved gap 0", BANK1_TITLE_CACHE_DATA_BASE <= BANK1_TITLE_CACHE_END && BANK1_TITLE_CACHE_END <= BANK1_RESERVED_GAP0_END, true
.assert "Title cache exceeds current title-art minimum", BANK1_TITLE_CACHE_MAX_LEN >= C128_TITLE_CACHE_MIN_REQUIRED, true
:AssertRegionBefore("STARTUP overlay slot ends before TOWN overlay slot", BANK1_OVERLAY_STARTUP_END, BANK1_OVERLAY_TOWN_BASE)
:AssertRegionBefore("TOWN overlay slot ends before DEATH overlay slot", BANK1_OVERLAY_TOWN_END, BANK1_OVERLAY_DEATH_BASE)
:AssertRegionBefore("DEATH overlay slot ends before reserved I/O window", BANK1_OVERLAY_DEATH_END, BANK1_RESERVED_IO_BASE)
:AssertRegionBefore("Reserved I/O window ends before DUNGEON overlay slot", BANK1_RESERVED_IO_END, BANK1_OVERLAY_DUNGEON_BASE)
:AssertRegionBefore("DUNGEON overlay slot ends before reserved top gap", BANK1_OVERLAY_DUNGEON_END, BANK1_RESERVED_TOP_BASE)
.assert "Tier cache window matches required preload footprint", BANK1_TIER_CACHE_SIZE, TIER_PRELOAD_REQUIRED
.assert "Cache-owned Bank1 span stays below $FF00", BANK1_CACHE_OWNED_END <= BANK1_RESERVED_TOP_END, true
.assert "Tier cache stays below overlay cache", BANK1_TIER_CACHE_END < BANK1_OVERLAY_STARTUP_BASE, true
.assert "Overlay cache avoids $D000-$DFFF", BANK1_OVERLAY_DEATH_END < BANK1_RESERVED_IO_BASE, true
.assert "DUNGEON overlay slot starts after $DFFF", BANK1_OVERLAY_DUNGEON_BASE > BANK1_RESERVED_IO_END, true
.assert "Overlay cache fits in named owned Bank1 span", OVERLAY_CACHE_GEN_END <= BANK1_CACHE_OWNED_END, true
