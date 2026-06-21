#importonce
// monster_active.s — Active monster table and slot helpers.
//
// This is the resident, platform-agnostic active monster contract. Full
// creature catalog data and spawning stay in monster.s.

// ============================================================
// Constants
// ============================================================
.const MAX_MONSTERS       = 32
.const MONSTER_ENTRY_SIZE = 12
.const EMPTY_SLOT         = $ff

// Active monster entry offsets (12 bytes per entry)
.const MX_X         = 0
.const MX_Y         = 1
.const MX_TYPE      = 2
.const MX_HP_LO     = 3
.const MX_HP_HI     = 4
.const MX_FLAGS     = 5
.const MX_SPEED_CNT = 6
.const MX_SLEEP_CUR = 7
.const MX_STUN      = 8
.const MX_CONFUSE   = 9
.const MX_FLEE_LO   = 10   // Flee threshold HP (lo byte)
.const MX_FLEE_HI   = 11   // Flee threshold HP (hi byte)

// Monster flags
.const MF_AWAKE     = $01
.const MF_CONFUSED  = $02
.const MF_PROVOKED  = $04   // Player attacked this monster; town creatures need this to fight back

// ============================================================
// Active monster table — 32 slots x 12 bytes
// ============================================================
#if PLATFORM_ACTIVE_MONSTER_TABLE_ABSOLUTE
.label monster_table = PLATFORM_ACTIVE_MONSTER_TABLE_BASE
#else
monster_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, EMPTY_SLOT
#endif

// Pre-computed offset tables for fast entry access
monster_offset_lo:
    .fill MAX_MONSTERS, <(i * MONSTER_ENTRY_SIZE)
monster_offset_hi:
    .fill MAX_MONSTERS, >(i * MONSTER_ENTRY_SIZE)

// Scratch variables
mfa_x: .byte 0                 // monster_find_at scratch
mfa_y: .byte 0

// monster_get_ptr — Set zp_ptr0 to monster_table entry X
// Input:  X = monster index (0-31)
// Output: zp_ptr0/hi = pointer to entry
// Preserves: X, Y
monster_get_ptr:
    lda monster_offset_lo,x
    clc
    adc #<monster_table
    sta zp_ptr0
    lda monster_offset_hi,x
    adc #>monster_table
    sta zp_ptr0_hi
    rts

// monster_wake — Set MF_AWAKE flag on a monster
// Input: X = monster slot index
// Clobbers: A, Y, zp_ptr0/hi
monster_wake:
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y
    rts

// monster_apply_sleep — Clear awake state and set the live sleep counter
// Input: A = sleep duration, X = monster slot index
// Clobbers: A, Y, zp_ptr0/hi
monster_apply_sleep:
    pha
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #<~MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    pla
    sta (zp_ptr0),y
    rts

// monster_init_table — Mark all 32 slots empty, reset count
// Clears 384 bytes (32 slots x 12 bytes). Two-pass loop because
// cpx #384 truncates to cpx #128 on 6502 (8-bit immediate).
// Preserves: nothing
monster_init_table:
    ldx #0
    lda #EMPTY_SLOT
!loop1:
    sta monster_table,x
    inx
    bne !loop1-                 // Clear bytes 0-255
!loop2:
    sta monster_table + 256,x
    inx
    cpx #(MAX_MONSTERS * MONSTER_ENTRY_SIZE - 256)  // 128
    bne !loop2-                 // Clear bytes 256-383
    lda #0
    sta zp_mon_count
    rts

// monster_find_free_slot — Find first empty slot
// Output: carry set = found, X = index
//         carry clear = table full
// Preserves: Y
monster_find_free_slot:
    ldx #0
!loop:
    cpx #MAX_MONSTERS
    bcs !full+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !found+
    inx
    jmp !loop-
!found:
    sec
    rts
!full:
    clc
    rts

// monster_find_at — Find monster at map position
// Input:  A = x, Y = y
// Output: carry set = found, X = slot index
//         carry clear = not found
// Clobbers: zp_ptr0, mfa_x, mfa_y
monster_find_at:
    sta mfa_x
    sty mfa_y
    ldx #0
!mfa_loop:
    cpx #MAX_MONSTERS
    bcs !mfa_miss+

    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !mfa_next+

    // Check x
    ldy #MX_X
    lda (zp_ptr0),y
    cmp mfa_x
    bne !mfa_next+

    // Check y
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp mfa_y
    bne !mfa_next+

    sec
    rts

!mfa_next:
    inx
    jmp !mfa_loop-

!mfa_miss:
    clc
    rts

// monster_remove — Remove monster at slot X
// Clears FLAG_OCCUPIED on map, marks slot empty, decrements count.
// Input:  X = slot index
// Clobbers: A, Y, zp_ptr0
monster_remove:
    jsr monster_get_ptr

    // Get position for clearing flag
    ldy #MX_X
    lda (zp_ptr0),y
    sta mfa_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta mfa_y

    // Mark slot empty (fill with $ff)
    lda #EMPTY_SLOT
    ldy #0
!mr_clear:
    sta (zp_ptr0),y
    iny
    cpy #MONSTER_ENTRY_SIZE
    bne !mr_clear-

    // Clear FLAG_OCCUPIED on map tile
    ldx mfa_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy mfa_x
    :MapRead_ptr0_y()
    and #~FLAG_OCCUPIED & $ff
    :MapWrite_ptr0_y()

    dec zp_mon_count
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Monster table size", MAX_MONSTERS * MONSTER_ENTRY_SIZE, 384
.assert "Monster table >256 bytes", MAX_MONSTERS * MONSTER_ENTRY_SIZE > 256, true
