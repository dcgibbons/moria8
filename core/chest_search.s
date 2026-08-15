#importonce
// chest_search.s — Chest search/Find-Traps reveal helpers (docs/CHEST_DESIGN.md
// step 8). Resident via the platform ChestSearchSegment macros so tight ports
// can place them outside full payloads. Only assembled into builds that
// define CHEST_ROUTING_ENABLED (product mains + the chest search test).

// chest_search_reveal — Search-scan branch for one adjacent tile that has
// FLAG_HAS_ITEM set. Finds an armed chest at (df_target_x, df_target_y):
// unfound traps roll the per-tile search chance and set CHEST_P1_TRAP_FOUND
// with the discovery message on success; already-found trapped chests print
// the upstream repeat message. Uses df_search_chance as the per-tile chance.
// Output: carry set = something found (df_found set), carry clear = nothing
// Clobbers: A, X, Y
:ChestSearchSegment()
chest_search_reveal:
    jsr chest_find_at_df_target
    bcc !csr_none+
    // X = floor slot; armed?
    lda fi_p1,x
    and #CHEST_P1_TRAP_MASK
    beq !csr_none+
    // Already found? Repeat message, no roll (upstream).
    lda fi_p1,x
    and #CHEST_P1_TRAP_FOUND
    bne !csr_repeat+
    // Unfound: roll the normal per-tile search chance
    lda df_search_chance
    beq !csr_none+
    lda #100
    jsr rng_range
    cmp df_search_chance
    bcs !csr_none+
    // Discovery: mark found on the chest instance
    lda fi_p1,x
    ora #CHEST_P1_TRAP_FOUND
    sta fi_p1,x
    ldx #HSTR_CHEST_FOUND_TRAP
    jmp !csr_msg+
!csr_repeat:
    ldx #HSTR_CHEST_TRAPPED
!csr_msg:
    jsr huff_print_msg
    lda #1
    sta df_found
    sec
    rts
!csr_none:
    clc
    rts

// chest_mark_found_all — Find Traps chest branch: mark CHEST_P1_TRAP_FOUND
// on every armed floor chest (upstream Find Traps reveals chest traps too).
// Clobbers: A, X, Y
chest_mark_found_all:
    ldx #MAX_FLOOR_ITEMS - 1
!cmfa_loop:
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !cmfa_next+
    tay
    lda it_category,y
    cmp #ICAT_CHEST
    bne !cmfa_next+
    lda fi_p1,x
    and #CHEST_P1_TRAP_MASK
    beq !cmfa_next+
    lda fi_p1,x
    ora #CHEST_P1_TRAP_FOUND
    sta fi_p1,x
!cmfa_next:
    dex
    bpl !cmfa_loop-
    rts
:ChestSearchRestoreSegment()
