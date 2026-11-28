#importonce
// wizard.s — Wizard Mode shared state and non-UI helpers

#import "ui_restore.s"

.const WIZARD_MAX_DLVL  = 99
.const WIZARD_MAX_ITEM  = ITEM_TYPE_COUNT - 1

#if !WIZARD_WALL_WALK_EXTERNAL
wizard_wall_walk_enabled: .byte 0
#endif
wizard_num_digits:        .byte 0
wizard_num_buf0:          .byte 0
wizard_num_buf1:          .byte 0
wizard_num_buf2:          .byte 0
wizard_prompt_max:        .byte 0
wizard_prompt_max_hi:     .byte 0
wizard_prompt_value:      .byte 0
wizard_prompt_value_hi:   .byte 0
wizard_prompt_input_col:  .byte 0
wiz_gen_page:             .byte 0
wizard_target_depth:      .byte 0
wizard_entry_dir:         .byte 0
wizard_level_jump_active: .byte 0

// wizard_execute_level_jump — Shared main-resident execution tail for Wizard
// level jumps. This must live outside OVL.UI on C128 because it loads the
// dungeon-generation overlay into the same $E000 window. Apple IIe keeps it
// in the resident play payload (the modal wizard UI is not returned into
// after the level transition).
wizard_execute_level_jump:
    lda zp_player_dlvl
    cmp wizard_target_depth
    bcc !wiz_jump_descend+
    lda #1
    sta wizard_entry_dir
    bne !wiz_jump_go+
!wiz_jump_descend:
    lda #0
    sta wizard_entry_dir
!wiz_jump_go:
    lda wizard_target_depth
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    cmp player_data + PL_MAX_DLVL
    bcc !wiz_max_ok+
    beq !wiz_max_ok+
    sta player_data + PL_MAX_DLVL
!wiz_max_ok:
    lda wizard_target_depth
    bne !wiz_not_town+
    jsr tramp_store_restock_all
!wiz_not_town:
    lda wizard_entry_dir
    sta level_entry_dir
#if !HAL_PLATFORM_NO_RESIDENT_IRS_P3_ROUTER
    jmp wizard_level_jump_generate

// irs_p3_swap_exec — Resident Phase 3 scroll/wand/staff effect router
// for platforms where the items-overlay router (irs_effect_p3_swap) jumps
// here to swap in OVL_SPELL without evicting its own continuation.
// A = item type ID on entry; the dispatch reads it from A, so preserve it
// across the overlay load (overlay_load returns the overlay ID in A).
irs_p3_swap_exec:
    pha                         // save item type ID
    lda #OVL_SPELL
    jsr overlay_load_no_kernal
    bcs !irs3s_fail+
    pla                         // restore item type ID
    jsr irs_dispatch_p3_overlay
    lda #OVL_ITEMS
    jsr overlay_load_no_kernal
    sec
    rts
!irs3s_fail:
    pla
    sec
    rts
#endif

wizard_level_jump_generate:
#if !HAL_PLATFORM_WIZARD_JUMP_INLINE_PLAY
    lda #1
    sta wizard_level_jump_active
    // The generation overlay replaces the current UI overlay. Abandon the
    // wizard call frames before generation so its deep stack use cannot wrap
    // into stale modal return addresses: back to the main loop's level.
    ldx main_loop_sp
    txs
    jsr level_change_generate_current
    jmp main_loop
#endif

// scroll_teleport_level_exec — Resident execution tail for the Scroll of
// Teleport Level. The Phase 3 scroll router runs from an overlay window
// (OVL.SPELL on C64, OVL.MODAL on C128, OVL.DEATH on Apple IIe), but
// level_change_generate_current loads the generation overlay into that same
// window; returning into the evicted overlay would execute generation code.
// Regenerate from resident code, then re-enter the main loop. The read
// flow's frames are abandonable, so reset the stack first: dungeon
// generation pushes ~250 bytes deep, which on top of the read flow's frames
// wraps the 256-byte stack page and overwrites them; later returns would
// then consume generation leftovers as return addresses. The reset goes
// back to the main loop's level (main_loop_sp), not $FF.
scroll_teleport_level_exec:
    ldx main_loop_sp
    txs
    jsr level_change_generate_current
    jmp main_loop

wizard_reset_session_state:
    lda #0
    sta wizard_wall_walk_enabled
    // eff_invuln_timer is not persisted (outside the saved ZP range, no
    // save block); without this clear a loaded game keeps arbitrary ZP
    // residue, granting phantom invulnerability. Runs on both session
    // starts: game_new_start and load_resume_game.
    sta eff_invuln_timer
    rts

wiz_rs_pd_tmp: .byte 0

#if !WIZARD_WALL_WALK_EXTERNAL
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

#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
:WizardGenExecSegment()
#endif
// wizard_generate_item_execute — Create a usable item for Wizard mode.
// Owner (:WizardGenExecSegment()): ModalMiscOverlay (OVL_MODAL_MISC) on C64,
// Plus/4, Apple IIe, CX16, Atari 8-bit, and BBC Master 128; C128ResidentPlay
// (128.play) on C128 (where ui_wizard.s runs in UiOverlay); Default in
// non-overlay unit tests.
// Lifetime: one wizard G (generate item) command.
// Callers: ui_wizard_cmd_generate_item (core/ui_wizard.s, already in
// ModalMiscOverlay or C128 UiOverlay) or resident wizard_cmd_generate_item in
// test builds. On ports with HAL_PLATFORM_WIZARD_EGO_MODAL_TRAMP (C64, Apple IIe,
// CX16, BBC Master), tramp_roll_ego_type_modal reloads OVL_MODAL_MISC after
// rolling an ego in OVL.ITEMS before returning here.
// Non-gold items prefer inventory placement so the item is immediately usable.
// Gold and inventory-overflow cases fall back to floor placement at the
// player's current tile.
// Input: fi_add_id = item type
//        fi_add_x / fi_add_y = desired floor position for fallback
// Output: carry set = success, carry clear = failure
wizard_generate_item_execute:
    lda item_cur_page
    sta wiz_gen_page
    lda fi_add_id
    jsr item_get_category_a
    cmp #ICAT_GOLD
    beq !wiz_make_gold+

    // Roll the normal item fields so Wizard-generated items are usable.
    lda wiz_gen_page
    sta item_cur_page
    lda fi_add_id
    jsr roll_enchantment
    sta fi_add_p1
    lda wiz_gen_page
    sta item_cur_page
    lda fi_add_id
#if HAL_PLATFORM_WIZARD_EGO_MODAL_TRAMP
    jsr tramp_roll_ego_type_modal
#else
    jsr tramp_roll_ego_type
#endif
    sta fi_add_ego
    lda wiz_gen_page
    sta item_cur_page
    ora fi_add_ego
    sta fi_add_ego

    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi

    ldx fi_add_id
    jsr item_get_missile
    bpl !wiz_try_inv+
    lda #6
    jsr rng_range
    clc
    adc #5
    sta fi_add_qty

!wiz_try_inv:
    jsr inv_add_item
    bcs !wiz_item_ok+
    jmp !wiz_try_floor+

!wiz_make_gold:
    .assert "All gold items live on Page 0", ITEM_PAGE_GOLD_SMALL == 0 && ITEM_PAGE_GOLD_MITHRIL == 0, true
    lda fi_add_id
    bne !wiz_large_gold+
    lda #25
    bne !wiz_gold_qty+
!wiz_large_gold:
    lda #100
!wiz_gold_qty:
    sta fi_add_qty
    jsr fi_add_clear_plain_meta

!wiz_try_floor:
    jsr floor_item_add
    bcs !wiz_item_ok+
    clc
    rts

!wiz_item_ok:
    sec
    rts
#if PLATFORM_PRODUCT_OVERLAY_RUNTIME
:WizardGenExecRestoreSegment()
#endif

// wizard_reveal_level — Reveal a floor-plan view of the current level without
// marking every solid-rock tile as explored. Reveals lit room geometry plus
// traversable/special features, then exposes hidden doors.
wizard_reveal_level:
#if HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE
    jmp tramp_reveal_floorplan
#else
    ldx #0
!wrl_row:
    jsr map_row_ptr0_x
    ldy #0
!wrl_col:
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !wrl_visit+
    cmp #TILE_DOOR_OPEN
    bcs !wrl_visit+
    lda zp_temp0
    and #FLAG_LIT
    beq !wrl_next+
!wrl_visit:
    lda zp_temp0
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!wrl_next:
    iny
    cpy #MAP_COLS
    bcc !wrl_col-
    inx
    cpx #MAP_ROWS
    bcc !wrl_row-
!wrl_done:
    jmp eff_find_doors
#endif

#if HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE
// wizard_reveal_level_from_overlay — Reveal wrapper for callers executing
// from an overlay window (ui_wizard.s in ModalMiscOverlay). The reveal
// trampoline loads OVL.SPELL into the same $E000 window, evicting the
// caller's overlay, so the wizard menu overlay must be restored before
// returning. Resident-only callers must use wizard_reveal_level directly.
wizard_reveal_level_from_overlay:
    jsr wizard_reveal_level
    lda #OVL_MODAL_MISC
    jsr overlay_load_no_kernal
!wrfo_done:
    rts
#endif

cmd_wizard_entry:
#if HAL_PLATFORM_WIZARD_ENTRY_OVERLAY
    jsr tramp_ui_wizard_display
    jmp main_loop
#else
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !wizard_open+

    lda #<wiz_confirm_str
    ldy #>wiz_confirm_str
    jsr msg_print_ay
    jsr hal_input_get_key
    cmp #$59                    // Y
    beq !wiz_enable+
    cmp #$D9                    // SHIFT+Y fallback
    beq !wiz_enable+
    jmp main_loop
!wiz_enable:
    lda zp_game_flags
    ora #GAME_FLAG_WIZARD
    sta zp_game_flags
    lda #<wiz_enabled_str
    ldy #>wiz_enabled_str
    jsr msg_print_ay
    jmp main_loop

!wizard_open:
    jsr wizard_40col_menu_display
    jsr hal_input_get_key
    cmp #$51                    // Q
    beq !wiz_cancel+
    cmp #$48                    // H
    beq !wiz_heal+
    cmp #$41                    // A
    beq !wiz_reveal+
    cmp #$49                    // I
    beq !wiz_identify+
    cmp #$58                    // X
    beq !wiz_gain+
    cmp #$54                    // T
    beq !wiz_teleport+
    cmp #$57                    // W
    beq !wiz_wall+
    cmp #$53                    // S
    beq !wiz_summon+
    cmp #$47                    // G
    beq !wiz_item+
    cmp #$4c                    // L
    beq !wiz_jump+
!wiz_cancel:
    jmp ui_view_return_to_gameplay_view
!wiz_heal:
    jmp wizard_cmd_heal_cure
!wiz_reveal:
    jmp wizard_cmd_reveal
!wiz_identify:
    jmp wizard_cmd_identify
!wiz_gain:
    jmp wizard_cmd_gain_level
!wiz_teleport:
    jmp wizard_cmd_teleport
!wiz_wall:
    jmp wizard_cmd_wall_walk
!wiz_summon:
    jmp wizard_cmd_summon
!wiz_item:
    jmp wizard_cmd_generate_item
!wiz_jump:
    jmp wizard_cmd_level_jump
#endif

#if HAL_PLATFORM_WIZARD_40COL_RESIDENT
.error "HAL_PLATFORM_WIZARD_40COL_RESIDENT=1 is unsupported; use ui_wizard.s"
#endif
