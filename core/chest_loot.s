#importonce
// chest_loot.s — Step-13 chest loot fulfillment (docs/CHEST_DESIGN.md
// "Contents" + "Loot fulfillment handoff"). Contents are generated lazily at
// open time from the static VMS per-type flags, never pre-generated or stored.
//
// The chest overlay stores a pending profile here (resident latch); the
// resident handoff (chest_fulfill_loot) loads the overlay that owns the
// picker (pick_item_type_overlay + pit_sorted) and runs chest_generate_loot.
// Picker placement is platform-specific: the CHEST overlay on C64/Plus4
// (PICKER_IN_CHEST_OVERLAY) and the GEN overlay on A2 and C128. Placed via
// the platform ChestLootSegment macros.

// ---- Resident pending-loot latch (written by the chest overlay) ------------
chest_loot_pending: .byte 0   // 1 = contents pending fulfillment
chest_loot_x:       .byte 0   // chest map position
chest_loot_y:       .byte 0
chest_loot_flags:   .byte 0   // VMS flags byte (bits 0-5 = VMS bits 24-29)

// Triggering chest position for the deferred summon runner, staged by
// chest_trigger_traps before any trap effect runs: trap_apply_damage reuses
// df_target_x for the damage roll and an explosion removes the floor slot,
// so neither source is readable by the time the resident handoff executes.
// Lives with the loot latch because tight ports park this block outside the
// play payload where chest_summons.s runs.
chest_summon_x:     .byte 0
chest_summon_y:     .byte 0
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
chest_product_path_stage:    .byte 0
chest_product_loot_placed:   .byte 0
chest_product_runtime_state: .byte 0
#endif

// ---- Generator scratch (resident) ------------------------------------------
cl_typ:     .byte 0           // 1=object, 2=gold, 3=mixed (from flags bits 0-1)
cl_drops:   .byte 0           // drops remaining to place
cl_tries:   .byte 0           // bounded placement attempts

// ============================================================
// chest_run_deferred — Resident deferred-work handoff after a chest open:
// deferred summoning-trap spawns, then contents fulfillment. One call from
// cmd_open (saves play-payload bytes vs two). Preserves flags so the caller's
// turn-consumed carry is undisturbed.
// ============================================================
chest_run_deferred:
    php
    jsr chest_run_pending_summons
    jsr chest_fulfill_loot
    plp
    rts

// ============================================================
// chest_fulfill_loot — Resident loot handoff. If contents are pending, first
// validate that a chest still exists at the staged position: the latch is
// transient (set and cleared within one cmd_open), so any latch left staged by
// a death/new-game/load floor reset references a cleared floor and is discarded
// here (docs/CHEST_DESIGN.md stale-latch guarantee, enforced at point of use).
// Then load the GEN overlay and fulfill, clearing the latch. Overlay-load
// failure also clears the latch and discards this chest's contents.
// ============================================================
chest_fulfill_loot:
    lda chest_loot_pending
    bne !cfl_has+
    rts
!cfl_has:
    // Stale-latch guard: no staged loot without a chest still at the position.
    lda chest_loot_x
    ldy chest_loot_y
    jsr floor_item_find_at
    bcc !cfl_clear+           // Nothing there -> stale latch, discard
    ldy fi_item_id,x
    lda it_category,y
    cmp #ICAT_CHEST
    bne !cfl_clear+           // Not a chest -> stale latch, discard
#if PICKER_IN_CHEST_OVERLAY
    lda #OVL_CHEST
#else
    lda #OVL_DUNGEON_GEN
#endif
#if C64_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
    // Disk loading exposes platform ROM over $E000; restore RAM before calling
    // the freshly loaded picker overlay. REU-backed C64 loads use the same path.
    jsr overlay_load_no_kernal
    bcc !cfl_loaded+
    jsr hal_platform_runtime_resync
    jmp !cfl_clear+
#else
    jsr overlay_load
    bcs !cfl_clear+           // Load failed: discard this chest's contents
#endif
!cfl_loaded:
    jsr chest_generate_loot
#if C64_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
chest_product_after_generate_sym:
#endif
    jsr hal_platform_runtime_resync
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
    lda chest_product_path_stage
    cmp #4
    beq !cfl_product_resynced+
    lda #$ff
    bne !cfl_product_store_stage+
!cfl_product_resynced:
    lda #5
!cfl_product_store_stage:
    sta chest_product_path_stage
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
    lda $01
#else
    lda TED_SCREEN_ADDR
#endif
    sta chest_product_runtime_state
#endif
#endif
#if C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
chest_product_after_generate_sym:
    // C128 fulfillment runs the resident generator after a cache-backed GEN
    // fetch, so there is no runtime resync; stage 5 lands directly.
    lda chest_product_path_stage
    cmp #4
    beq !cfl_product_done+
    lda #$ff
    bne !cfl_product_store+
!cfl_product_done:
    lda #5
!cfl_product_store:
    sta chest_product_path_stage
#endif
!cfl_clear:
    lda #0
    sta chest_loot_pending
    rts

// ============================================================
// chest_generate_loot — Roll and place a chest's contents. Runs with the GEN
// overlay loaded. VMS drop decode (moria.inc chest/monster_death flags):
//   bit0 (VMS 24) carry object, bit1 (VMS 25) carry gold -> drop type
//   bit2 (VMS 26) 60% one drop, bit3 (VMS 27) 90% one drop
//   bit4 (VMS 28) randint(2) drops, bit5 (VMS 29) damroll(2d2) drops
// Each mixed drop is 50/50 object/gold (VMS summon_object typ 3). Content
// depth = current dungeon level. Placement: bounded 10 attempts per drop in a
// 5x5 box around the chest, walkable + monster-free + item-free; failure
// discards that drop. Clobbers: A, X, Y, zp_*, fi_add_*.
// ============================================================
:ChestLootSegment()
chest_generate_loot:
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
    lda chest_product_path_stage
    cmp #2
    beq !cgl_product_entered+
    lda #$ff
    bne !cgl_product_store_stage+
!cgl_product_entered:
    lda #3
!cgl_product_store_stage:
    sta chest_product_path_stage
#endif
    // Drop type from flags bits 0-1
    lda chest_loot_flags
    and #$03
    sta cl_typ

    lda #0
    sta cl_drops

    // bit2: 60% one drop
    lda chest_loot_flags
    and #$04
    beq !cgl_no60+
    lda #100
    jsr rng_range
    cmp #60
    bcs !cgl_no60+
    inc cl_drops
!cgl_no60:

    // bit3: 90% one drop
    lda chest_loot_flags
    and #$08
    beq !cgl_no90+
    lda #100
    jsr rng_range
    cmp #90
    bcs !cgl_no90+
    inc cl_drops
!cgl_no90:

    // bit4: randint(2) drops
    lda chest_loot_flags
    and #$10
    beq !cgl_no1d2+
    lda #2
    jsr rng_range               // [0,1]
    clc
    adc #1                      // randint(2) = [1,2]
    clc
    adc cl_drops
    sta cl_drops
!cgl_no1d2:

    // bit5: damroll(2d2) drops
    lda chest_loot_flags
    and #$20
    beq !cgl_no2d2+
    lda #2
    jsr rng_range
    clc
    adc #1                      // first d2 [1,2]
    sta cl_tries                // scratch
    lda #2
    jsr rng_range
    clc
    adc #1                      // second d2 [1,2]
    clc
    adc cl_tries                // 2d2 total [2,4]
    clc
    adc cl_drops
    sta cl_drops
!cgl_no2d2:

    // Place each drop
!cgl_drop_loop:
    lda cl_drops
    beq !cgl_done+
    jsr chest_loot_place_one
    dec cl_drops
    jmp !cgl_drop_loop-
!cgl_done:
    rts

// ============================================================
// chest_loot_place_one — Place a single drop near the chest. Resolves
// object-vs-gold for this drop (mixed = 50/50), finds a free tile in the 5x5
// box (bounded 10 attempts), and places it. Failures discard the drop.
// ============================================================
chest_loot_place_one:
    // Resolve this drop's type (mixed rolls 50/50)
    lda cl_typ
    cmp #3
    bne !clpo_typed+
    lda #100
    jsr rng_range
    cmp #50
    bcs !clpo_gold+
    lda #1                      // object
    bne !clpo_typed+
!clpo_gold:
    lda #2                      // gold
!clpo_typed:
    sta cl_drops_this           // 1=object, 2=gold (see var below)

    // Bounded 10 attempts for a free tile
    lda #10
    sta cl_tries
!clpo_try:
    // tx = chest_x - 2 + rng(5); ty = chest_y - 2 + rng(5)  (5x5 box)
    lda #5
    jsr rng_range
    clc
    adc chest_loot_x
    sec
    sbc #2
    sta fi_add_x
    lda #5
    jsr rng_range
    clc
    adc chest_loot_y
    sec
    sbc #2
    sta fi_add_y

    // Bounds: reject candidates outside the map before any row-table or map
    // access. The unsigned compare also rejects the $ff wrap produced when an
    // edge chest (coordinate 1) combines with a zero RNG offset.
    lda fi_add_x
    cmp #MAP_COLS
    bcs !clpo_next+
    lda fi_add_y
    cmp #MAP_ROWS
    bcs !clpo_next+

    // Walkable (floor or open door)?
    ldx fi_add_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy fi_add_x
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !clpo_walkable+
    cmp #TILE_DOOR_OPEN
    bne !clpo_next+
!clpo_walkable:
    // Monster-free?
    lda fi_add_x
    ldy fi_add_y
    jsr monster_find_at
    bcs !clpo_next+
    // Item-free?
    lda fi_add_x
    ldy fi_add_y
    jsr floor_item_find_at
    bcs !clpo_next+
    jmp !clpo_place+

!clpo_next:
    dec cl_tries
    bne !clpo_try-
    rts                         // No free tile: discard this drop

!clpo_place:
    // Place the drop at fi_add_x/fi_add_y
    lda cl_drops_this
    cmp #2
    beq !clpo_place_gold+

    // --- Object ---
#if C64_PRODUCT_OVERLAY_RUNTIME || C128_PRODUCT_OVERLAY_RUNTIME || PLUS4_PRODUCT_OVERLAY_RUNTIME || APPLE2_PRODUCT_OVERLAY_RUNTIME
    // Product: the picker lives in the overlay the handoff loaded (CHEST on
    // C64/Plus4, GEN on C128/A2), so call the overlay impl directly — the
    // resident pick_item_type wrapper would reload over the executing overlay.
    jsr pick_item_type_overlay  // A = item ID (handoff-window picker)
#else
    jsr pick_item_type          // Unit assemblies have no GEN overlay
#endif
    sta fi_add_id
    jsr roll_enchantment        // sets fi_add_p1 + combat/armor stats
    sta fi_add_p1
    lda fi_add_id
#if C64_PRODUCT_OVERLAY_RUNTIME
    // The ordinary C64 trampoline exposes KERNAL before returning, which would
    // hide this GEN-overlay continuation at $E000.
    jsr tramp_roll_ego_type_modal
#elif APPLE2_PRODUCT_OVERLAY_RUNTIME
    // The A2 trampoline would load OVL.ITEMS over this executing GEN overlay;
    // the gen variant restores OVL.GEN before returning.
    jsr tramp_roll_ego_type_gen
#else
    jsr tramp_roll_ego_type
#endif
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
    pha
    lda chest_product_path_stage
    cmp #3
    beq !clpo_product_first_ego+
    cmp #4
    beq !clpo_product_ego_done+
    lda #$ff
    bne !clpo_product_store_stage+
!clpo_product_first_ego:
    lda #4
!clpo_product_store_stage:
    sta chest_product_path_stage
!clpo_product_ego_done:
    pla
#endif
    sta fi_add_ego
    lda #1
    sta fi_add_qty
    ldx fi_add_id
    jsr item_get_missile
    bpl !clpo_qty_done+         // not ammo
    lda #6
    jsr rng_range
    clc
    adc #5                      // ammo stack [5,10]
    sta fi_add_qty
!clpo_qty_done:
    jsr floor_item_add
    bcc !clpo_object_done+      // Table full — discard this drop
    inc zp_dirty_count          // Enclosing turn must redraw newly visible loot
!clpo_object_done:
#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
    bcc !clpo_product_not_placed+
    lda #1
    sta chest_product_loot_placed
!clpo_product_not_placed:
#endif
    rts

!clpo_place_gold:
    // --- Gold (ID 0 or 1), qty = rng_range_word(dlvl*10) + 5 ---
    lda #2
    jsr rng_range
    sta fi_add_id
    jsr fi_add_clear_plain_meta
    // Chests are portable/wizard-spawnable into town, where dlvl=0 would make
    // rng_range_word(0) reject every draw and hang; clamp the depth to 1.
    lda zp_player_dlvl
    bne !clpo_dlvl_ok+
    lda #1
!clpo_dlvl_ok:
    ldx #10
    jsr math_multiply           // N = dlvl * 10
    lda zp_math_a
    sta zp_temp0
    lda zp_math_b
    sta zp_temp1
    jsr rng_range_word          // result zp_temp2/3
    lda zp_temp2
    clc
    adc #5
    sta fi_add_qty
    lda zp_temp3
    adc #0
    sta fi_add_qty_hi
    jsr floor_item_add
    bcc !clpo_gold_done+        // Table full — discard this drop
    inc zp_dirty_count          // Enclosing turn must redraw newly visible loot
!clpo_gold_done:
    rts

cl_drops_this: .byte 0          // This drop's resolved type (1=object, 2=gold)

#if C64_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || PLUS4_TEST_SCRIPTED_CHEST_OPEN_PRODUCT || C128_TEST_SCRIPTED_CHEST_OPEN_PRODUCT
// Deterministic product-path fixture: an unlocked Large Wooden Chest directly
// east of the player, with a clear local area and RNG seed that guarantees at
// least one object drop through the real picker and ego trampoline.
:ChestFixtureSegment()
chest_product_setup:
    jsr item_init_floor
    jsr monster_init_table

    lda #0
    sta chest_loot_pending
    sta chest_pending_summons
    sta chest_product_path_stage
    sta chest_product_loot_placed
    sta chest_product_runtime_state

    lda #20
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #10
    sta zp_player_y
    sta player_data + PL_MAP_Y

    ldx #8
!cps_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
!cps_col:
    :MapWrite_ptr0_y()
    iny
    cpy #24
    bne !cps_col-
    inx
    cpx #13
    bne !cps_row-

    lda #$12
    sta zp_rng_0
    lda #$34
    sta zp_rng_1
    lda #$56
    sta zp_rng_2
    lda #$78
    sta zp_rng_3

    jsr fi_add_clear_plain_meta
    lda #21
    sta fi_add_x
    lda #10
    sta fi_add_y
    lda #ITEM_TYPE_CHEST_LARGE_WOOD
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #15
    sta fi_add_to_hit
    jsr floor_item_add
    bcs !cps_done+
    lda #$ff
    sta chest_product_path_stage
!cps_done:
    rts
:ChestFixtureRestoreSegment()
#endif
:ChestLootRestoreSegment()
