#importonce
// memory_aux.s — Apple IIe auxiliary-memory mechanics.
//
// THE PORT'S #1 CORRECTNESS HAZARD (docs/APPLE2_MEMORY_POLICY.md):
// RAMRD/RAMWRT ($C002-$C005) bank only $0200-$BFFF; $0000-$01FF follows
// ALTZP (always off here). With RAMRD on, instruction fetches from
// $0200-$BFFF come from aux, so any aux-READ routine must execute from ZP —
// hence the installed thunks at A2_ZP_THUNK_*. RAMWRT affects writes only, so
// main->aux writes are safe from ordinary resident code. The game runs SEI
// with no interrupt sources, so nothing preempts a switched sequence.
//
// AUXMOVE ($C311) is firmware ROM in the internal C3 space; boot selects
// INTC3ROM ($C00A) before first use. It clobbers ZP $3C-$43 — the wrapper
// saves/restores those 8 bytes. Carry convention (to be confirmed by the
// MAME spike; isolated to A2_AUXMOVE_TO_AUX_CARRY): SEC = main->aux,
// CLC = aux->main.

// Soft switches
.const A2_RAMRD_OFF   = $c002
.const A2_RAMRD_ON    = $c003
.const A2_RAMWRT_OFF  = $c004
.const A2_RAMWRT_ON   = $c005
.const A2_INTC3ROM    = $c00a   // internal C3 ROM ON ($c00b = slot 3 ROM;
                                // mapping verified against ProDOS driver
                                // bytes and the IIe boot ROM sequence)
.const A2_AUXMOVE     = $c311
.const A2_AUXMOVE_TO_AUX_CARRY = 1   // SEC moves main->aux (verified by
// trace + $C376 firmware disassembly). NOTE: do not use this in `#if` —
// Kick #if tests definedness, not .const truthiness, and silently takes
// the #else arm. Kept for documentation only; call sites hardcode CLC.

// ============================================================
// ZP thunk templates (assembled in resident payload, copied to ZP
// by a2_install_zp_thunks). The code is position-independent: the only
// absolute references are soft switches and ZP operands bound at assembly
// time, so no relocation is needed.
// ============================================================

a2_thunk_read_p0_src:
    sta A2_RAMRD_ON
    lda (zp_ptr0),y
    sta A2_RAMRD_OFF
    rts
a2_thunk_read_p0_end:
.assert "read-p0 thunk fits 16-byte slot", a2_thunk_read_p0_end - a2_thunk_read_p0_src <= 16, true

a2_thunk_read_p1_src:
    sta A2_RAMRD_ON
    lda (zp_ptr1),y
    sta A2_RAMRD_OFF
    rts
a2_thunk_read_p1_end:
.assert "read-p1 thunk fits slot before block thunk", a2_thunk_read_p1_end - a2_thunk_read_p1_src <= A2_ZP_THUNK_READ_BLOCK - A2_ZP_THUNK_READ_P1, true

a2_thunk_read_block_src:
    sta A2_RAMRD_ON
!loop:
    lda (zp_ptr0),y     // aux read
    sta (zp_ptr1),y     // main write (RAMWRT off)
    iny
    dex
    bne !loop-
    sta A2_RAMRD_OFF
    rts
a2_thunk_read_block_end:
.assert "read-block thunk fits platform ZP", A2_ZP_THUNK_READ_BLOCK + (a2_thunk_read_block_end - a2_thunk_read_block_src) - 1 <= $ef, true

// a2_install_zp_thunks — Install aux-read thunks into platform ZP.
// Called at boot and re-called by the storage adapter after MLI sequences
// (belt and braces; the TRM shows the MLI never touches high ZP).
// Preserves: nothing (uses A, X)
a2_install_zp_thunks:
    ldx #a2_thunk_read_p0_end - a2_thunk_read_p0_src - 1
!p0:
    lda a2_thunk_read_p0_src,x
    sta A2_ZP_THUNK_READ_P0,x
    dex
    bpl !p0-
    ldx #a2_thunk_read_p1_end - a2_thunk_read_p1_src - 1
!p1:
    lda a2_thunk_read_p1_src,x
    sta A2_ZP_THUNK_READ_P1,x
    dex
    bpl !p1-
    ldx #a2_thunk_read_block_end - a2_thunk_read_block_src - 1
!blk:
    lda a2_thunk_read_block_src,x
    sta A2_ZP_THUNK_READ_BLOCK,x
    dex
    bpl !blk-
    rts

// ============================================================
// Map access wrappers (core-facing, via mmu_macros.s)
// ============================================================

// mmu_safe_map_read_ptr0 — A = aux byte at (zp_ptr0),y. Preserves X, Y.
mmu_safe_map_read_ptr0:
    jmp A2_ZP_THUNK_READ_P0

// mmu_safe_map_read_ptr1 — A = aux byte at (zp_ptr1),y. Preserves X, Y.
mmu_safe_map_read_ptr1:
    jmp A2_ZP_THUNK_READ_P1

// mmu_safe_map_write_ptr0 — Write A to aux at (zp_ptr0),y.
// Writes-only switch: safe from resident code; sta leaves A intact, so no
// stacking is needed. Preserves A, X, Y.
mmu_safe_map_write_ptr0:
    sta A2_RAMWRT_ON
    sta (zp_ptr0),y     // write goes to aux
    sta A2_RAMWRT_OFF
    rts

// mmu_safe_map_write_ptr1 — Write A to aux at (zp_ptr1),y. Preserves A, X, Y.
mmu_safe_map_write_ptr1:
    sta A2_RAMWRT_ON
    sta (zp_ptr1),y
    sta A2_RAMWRT_OFF
    rts

// ============================================================
// BANKED_DATA window access (plain main RAM on this platform)
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

// ============================================================
// Bulk aux transfer primitives
// ============================================================

// a2_main_to_aux_block — Copy main->aux under RAMWRT (safe from resident).
// Input: zp_ptr0 = main source, zp_ptr1 = aux dest,
//        zp_temp0 = count lo, zp_temp1 = count hi
// Preserves: nothing
a2_main_to_aux_block:
    sta A2_RAMWRT_ON
    ldy #0
    ldx zp_temp1
    beq !partial+
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
    ldx zp_temp0
    beq !done+
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail-
!done:
    sta A2_RAMWRT_OFF
    rts

// a2_auxmove — Firmware bulk move between main and aux.
// Input: zp_ptr0 = source start, zp_ptr1 = dest start,
//        zp_temp0/zp_temp1 = byte count (16-bit, >= 1)
//        carry: clear = aux -> main, set = main -> aux
// Clobbers: A/X/Y; saves and restores firmware params $3C-$43.
// Entry/result flags are parked in a2_zp_scratch: the register save area
// occupies the stack through the call, so php/plp cannot carry state
// across it without misaligning (a top-of-stack plp reads a saved ZP
// byte, not the pushed flags).
a2_auxmove:
    php
    pla
    sta a2_zp_scratch           // entry flags (direction carry)
    ldx #7                      // save $3C-$43
!save:
    lda $3c,x
    pha
    dex
    bpl !save-
    lda zp_ptr0                 // A1 = source start
    sta $3c
    lda zp_ptr0 + 1
    sta $3d
    clc                         // A2 = source end (start + count - 1)
    lda zp_ptr0
    adc zp_temp0
    tax
    lda zp_ptr0 + 1
    adc zp_temp1
    tay
    txa
    sec
    sbc #1
    sta $3e
    tya
    sbc #0
    sta $3f
    lda zp_ptr1                 // A4 = dest start
    sta $42
    lda zp_ptr1 + 1
    sta $43
    lda a2_zp_scratch
    pha
    plp                         // restore entry direction
#if A2_DEBUG_CACHELOG
    lda zp_ptr0
    sta $2002
    lda zp_ptr0 + 1
    sta $2003
    lda zp_ptr1
    sta $2004
    lda zp_ptr1 + 1
    sta $2005
    lda $a400
    sta $2006               // window byte BEFORE the copy
#endif
    jsr A2_AUXMOVE
#if A2_DEBUG_CACHELOG
    lda $a400
    sta $2007               // window byte AFTER the copy
#endif
    php                         // preserve AUXMOVE result state
    pla
    sta a2_zp_scratch           // park result flags off the stack
    ldx #0                      // restore $3C-$43
!restore:
    pla
    sta $3c,x
    inx
    cpx #8
    bne !restore-
    lda a2_zp_scratch
    pha
    plp
    rts

// Plus/4 banking compatibility stub for shared core paths that select the
// non-C64 branch (e.g. core/monster.s visibility): the Apple II runtime has
// no RAM/ROM bank to select, so the call is a genuine no-op.
plus4_bank_ram:
    rts

// ============================================================
// hal_memory_* contract exports. The Apple II runtime path has no OS banking:
// main RAM is always visible and the MLI is always callable, so enter/exit
// are genuinely no-ops (not placeholders).
// ============================================================

hal_memory_enter_os:
    clc
    rts

hal_memory_exit_os:
    clc
    rts

hal_memory_restore_runtime:
    clc
    rts

// hal_memory_copy — Main-to-main block copy.
// Input: zp_ptr0 = source, zp_ptr1 = dest, zp_temp0 = count lo,
//        zp_temp1 = count hi. Output: C=0.
hal_memory_copy:
    ldy #0
    ldx zp_temp1
    beq !partial+
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
    ldx zp_temp0
    beq !done+
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail-
!done:
    clc
    rts

hal_memory_read_byte:
    lda (zp_ptr0),y
    clc
    rts

hal_memory_write_byte:
    sta (zp_ptr0),y
    clc
    rts
