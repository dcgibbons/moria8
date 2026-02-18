// store_data.s — Store persistent data and main-RAM helpers
//
// Store inventory arrays must persist across overlay loads ($E000).
// When creature tiers overwrite $E000, store data survives here.
// check_player_on_store_door also stays in main RAM since it's
// called on every town move (loading the overlay each time would
// be wasteful).
//
// Constants defined here (not in store.s) because store_data.s
// is imported first in main RAM, before the overlay segment.

// ============================================================
// Constants
// ============================================================
.const STORE_MAX_ITEMS   = 12
.const STORE_TOTAL_SLOTS = 96   // 8 × 12
.const STORE_PICK_RETRIES = 30  // Max rejection sampling attempts
.const STORE_BM   = 6          // Black Market store index
.const STORE_HOME = 7          // Player Home store index

// ============================================================
// Store inventory arrays (Struct-of-Arrays, 288 bytes)
// ============================================================
si_item_id:     .fill STORE_TOTAL_SLOTS, $FF   // $FF = empty
si_qty:         .fill STORE_TOTAL_SLOTS, 0
si_p1:          .fill STORE_TOTAL_SLOTS, 0
si_flags:       .fill STORE_TOTAL_SLOTS, 0

// Base index into SoA arrays for each store (store * 12)
store_base_idx:
    .byte 0, 12, 24, 36, 48, 60, 72, 84

// ============================================================
// check_player_on_store_door — Check if player is on a store door
// ============================================================
// Input: zp_player_x/y
// Output: carry set + A = store index (0-7) if on door
//         carry clear if not on any door
// Clobbers: A, X
check_player_on_store_door:
    ldx #7
!cpsd_loop:
    lda zp_player_x
    cmp store_door_x,x
    bne !cpsd_next+
    lda zp_player_y
    cmp store_door_y,x
    bne !cpsd_next+
    // Match
    txa
    sec
    rts
!cpsd_next:
    dex
    bpl !cpsd_loop-
    clc
    rts
