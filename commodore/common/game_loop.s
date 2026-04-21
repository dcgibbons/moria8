#importonce
// game_loop.s — Main game loop, command dispatch, and shared gameplay routines
//
// Platform-independent game logic extracted from main.s.
// Called by platform-specific main.s after hardware initialization.
// Forward-references trampoline labels defined in the platform's main.s
// (Kick Assembler resolves all labels globally within the compilation unit).

#import "turn_render_state.s"
#import "generation_busy_api.s"
#import "platform_services_api.s"
#import "input_ui_helpers.s"

#if C128_TEST_FORCE_DEATH
c128_test_force_death_pending: .byte 1
#endif

#if C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_SPELL_CANCEL
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

#if C128_TEST_SCRIPTED_PRAYER
c128_test_seed_scripted_prayer_state:
    lda #0
    sta c128_test_spell_success_count
    sta c128_test_spell_return_pending
    sta c128_test_spell_return_count
    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_WIS_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #%00000111
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
    sta player_data + PL_NEW_SPELLS
    lda #99
    ldx #31
!c128_test_prayer_order_clear:
    sta player_data + PL_SPELL_ORDER,x
    dex
    bpl !c128_test_prayer_order_clear-
    lda #0
    sta player_data + PL_SPELL_ORDER
    rts

c128_test_prayer_msg_str:
    .text "You feel righteous!" ; .byte 0

c128_test_prayer_history_has_bless:
    lda #<msg_history
    sta zp_ptr0
    lda #>msg_history
    sta zp_ptr0_hi
    ldx #MSG_HIST_COUNT
!c128_tp_scan_slot:
    ldy #0
!c128_tp_cmp:
    lda c128_test_prayer_msg_str,y
    beq !c128_tp_found+
    cmp (zp_ptr0),y
    bne !c128_tp_next_slot+
    iny
    jmp !c128_tp_cmp-
!c128_tp_next_slot:
    clc
    lda zp_ptr0
    adc #<MSG_HIST_LEN
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #>MSG_HIST_LEN
    sta zp_ptr0_hi
    dex
    bne !c128_tp_scan_slot-
    clc
    rts
!c128_tp_found:
    sec
    rts
#endif

#if C64_TEST_SCRIPTED_SPELL
c64_test_seed_scripted_spell_state:
    lda #0
    sta c64_test_spell_success_count
    sta c64_test_spell_return_pending
    sta c64_test_spell_return_count
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
    sta player_data + PL_NEW_SPELLS
    lda #99
    ldx #31
!c64_test_spell_order_clear:
    sta player_data + PL_SPELL_ORDER,x
    dex
    bpl !c64_test_spell_order_clear-
    lda #0
    sta player_data + PL_SPELL_ORDER
    rts
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
c64_test_seed_scripted_spell_state:
    lda #0
    sta c64_test_spell_success_count
    sta c64_test_spell_return_pending
    sta c64_test_spell_return_count
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
    sta player_data + PL_NEW_SPELLS
    lda #99
    ldx #31
!c64_test_dungeon_spell_order_clear:
    sta player_data + PL_SPELL_ORDER,x
    dex
    bpl !c64_test_dungeon_spell_order_clear-
    lda #0
    sta player_data + PL_SPELL_ORDER
    rts

c64_test_force_spell_target_monster:
    lda zp_player_dlvl
    bne !ctstm_have_dlvl+
    rts
!ctstm_have_dlvl:
    lda c64_test_spell_return_pending
    beq !ctstm_ready+
    rts
!ctstm_ready:
    lda c64_test_spell_success_count
    cmp active_dungeon_count
    bcc !ctstm_have_type+
    rts
!ctstm_have_type:
    sta c64_test_spell_target_type
    lda zp_player_y
    sta c64_test_spell_target_y
    lda #1
    sta c64_test_spell_path_offset
!ctstm_clear_path:
    lda zp_player_x
    clc
    adc c64_test_spell_path_offset
    sta c64_test_spell_target_x
    lda c64_test_spell_target_x
    ldy c64_test_spell_target_y
    jsr monster_find_at
    bcc !ctstm_clear_tile+
    jsr monster_remove

!ctstm_clear_tile:
    ldx c64_test_spell_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy c64_test_spell_target_x
    lda #TILE_FLOOR
    :MapWrite_ptr0_y()
    inc c64_test_spell_path_offset
    lda c64_test_spell_path_offset
    cmp #7
    bcc !ctstm_clear_path-

    lda c64_test_spell_target_x
    sta ms_spawn_x
    lda c64_test_spell_target_y
    sta ms_spawn_y
    lda c64_test_spell_target_type
    jsr monster_spawn_one
    bcs !ctstm_spawned+
    rts
!ctstm_spawned:
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE
    sta (zp_ptr0),y

    // Force the next hit-message name lookup down the stale-tier reload path.
    // This matches the live C64 dungeon spell crash: current_tier is gone, but
    // spawned dungeon monsters still hold $E0xx name pointers that require
    // creature_get_name -> tier_load -> reu_fetch_tier to recover.
    lda #0
    sta current_tier
    sta tier_loaded
!ctstm_done:
    rts

c64_test_spell_target_x: .byte 0
c64_test_spell_target_y: .byte 0
c64_test_spell_target_type: .byte 0
c64_test_spell_path_offset: .byte 0
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
c64_test_seed_scripted_spell_state:
    lda #0
    sta c64_test_spell_success_count
    sta c64_test_spell_return_pending
    sta c64_test_spell_return_count
    rts

c64_test_force_detect_evil_monster:
    ldx #0
!ctdem_spawn_loop:
    lda zp_player_y
    sta c64_test_detect_row
    ldy c64_test_detect_offsets,x
    sty c64_test_detect_offset
    lda zp_player_x
    clc
    adc c64_test_detect_offset
    sta c64_test_detect_col
    ldy c64_test_detect_row
    lda map_row_lo,y
    sta zp_ptr0
    lda map_row_hi,y
    sta zp_ptr0_hi
    ldy c64_test_detect_col
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !ctdem_next+
    ldy c64_test_detect_col
    :MapRead_ptr0_y()
    and #(TILE_TYPE_MASK | FLAG_LIT)
    :MapWrite_ptr0_y()
    lda c64_test_detect_col
    sta ms_spawn_x
    lda c64_test_detect_row
    sta ms_spawn_y
    lda c64_test_detect_types,x
    jsr monster_spawn_one
!ctdem_next:
    inx
    cpx #5
    bcc !ctdem_spawn_loop-
!ctdem_done:
    rts

c64_test_detect_row: .byte 0
c64_test_detect_col: .byte 0
c64_test_detect_offset: .byte 0
c64_test_detect_offsets:
    .byte 6, 8, 10, 12, 14
c64_test_detect_types:
    .byte 0, 4, 8, 14, 22
#endif

// ============================================================
// game_new_start — New game initialization
// Called from platform main.s after title menu selects "New Game".
// ============================================================
game_new_start:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$70
    jsr c128_town_dump_mark
#endif
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardInit($85)
#endif
#if C128_TEST_STACK_BOTTOM_DIAG
    :C128StackBottomCanaryInit($90)
#endif
    // Re-seed RNG after user input for better entropy
    jsr rng_seed

    // Play sound as acknowledgment
    lda #SFX_PICKUP
    jsr sound_play

    // Initialize message system
    jsr msg_init

#if C128
#if PERF_P1
    // Reset movement responsiveness counters for new sessions.
    jsr perf_p1_reset
#endif
#endif

    lda #0
    sta zp_game_flags
    jsr wizard_reset_session_state

    // Clear status effect timers ($50–$5f) — BASIC ZP may have residual values
    ldx #0
    lda #0
!clear_effects:
    sta zp_eff_poison,x
    inx
    cpx #16                 // $50–$5f = 16 bytes
    bne !clear_effects-

    // Clear static RAM effect timers (not in ZP $50-$5f range)
    lda #0
    sta eff_fear_timer

    jsr tramp_player_create
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardCheck($86)
#endif
#if C128
    jsr platform_runtime_resync_api
#endif

    // Show the post-chargen summary sheet and wait for a fresh dismiss key.
    // The modal helper flushes the gender-selection key on C64 and waits for
    // key release on C128 so the summary is not dismissed immediately.
    jsr tramp_ui_char_display
    jsr input_get_modal_dismiss_key
    jsr screen_clear

#if C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_SPELL_CANCEL
    jsr c128_test_seed_scripted_spell_state
#endif
#if C128_TEST_SCRIPTED_PRAYER
    jsr c128_test_seed_scripted_prayer_state
#endif
#if C64_TEST_SCRIPTED_SPELL
    jsr c64_test_seed_scripted_spell_state
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jsr c64_test_seed_scripted_spell_state
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jsr c64_test_seed_scripted_spell_state
#endif

    // --- Starting equipment ---
    // Wooden torch (type 13) in EQUIP_LIGHT with 134 charges (134 × 30 = 4,020 turns)
    lda #13
    sta inv_item_id + EQUIP_LIGHT
    lda #1
    sta inv_qty + EQUIP_LIGHT
    lda #134
    sta inv_p1 + EQUIP_LIGHT
    lda #0
    sta inv_flags + EQUIP_LIGHT
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD

    // Ration of food (type 15) in carried slot 0
    lda #15
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Dagger (type 2) in EQUIP_WEAPON
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON

    // Leather armor (type 7) in EQUIP_BODY
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #0
    sta inv_p1 + EQUIP_BODY
    sta inv_flags + EQUIP_BODY

    // Starting spellbook for casters (carried slot 1)
    lda player_data + PL_SPELL_TYPE
    beq !no_book+
    cmp #SPELL_MAGE
    bne !priest_book+
    lda #47                 // Beginner's Spellbook
    jmp !store_book+
!priest_book:
    lda #48                 // Holy Prayer Book
!store_book:
    sta inv_item_id + 1     // Carried slot 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1
!no_book:

    // Recalculate combat stats with equipped items
    jsr player_recalc_equipment

    // Randomize item identification (shuffle potion/scroll/ring descriptors)
    jsr item_init_identification
#if C128_TEST_OVERLAY_STATE_CORRUPT
    lda #OVL_TOWN
    sta current_overlay
#endif
    jsr tramp_store_init_all
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardCheck($87)
#endif
#if C128
    jsr platform_runtime_resync_api
#endif

    // --- Main game loop ---
    // Initialize dungeon level and generate map (new game only)
    lda #0
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    clc
    adc #10
#endif
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    sta player_data + PL_MAX_DLVL
    sta level_entry_dir
    lda #$ff
    sta zp_run_dir              // Not running
    lda #OVL_DUNGEON_GEN
#if C128_REAL_BOOT_DIAG
    ldx #$21
    jsr c128_stack_guard_begin
#endif
    jsr overlay_load
#if C128_REAL_BOOT_DIAG
    ldx #$22
    jsr c128_stack_guard_check
#endif
    bcc !gns_ovl_ok+
    jmp entry_main
!gns_ovl_ok:
#if C128_TEST_STACK_SLOT_DIAG
    :C128StackSlotGuardCheck($88)
#endif
#if C128
    jsr platform_runtime_resync_api
#endif
#if C128_REAL_BOOT_DIAG
    ldx #$23
    jsr c128_stack_guard_begin
#endif
    jsr tramp_level_generate
#if C128_REAL_BOOT_DIAG
    ldx #$24
    jsr c128_stack_guard_check
#endif
    jsr monster_spawn_level
    jsr item_spawn_level
#if C128_REAL_BOOT_DIAG
    ldx #$25
    jsr c128_stack_guard_begin
#endif
    jsr update_visibility       // Reveal starting area
#if C128_REAL_BOOT_DIAG
    ldx #$26
    jsr c128_stack_guard_check
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    jsr c64_test_force_detect_evil_monster
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jsr c64_test_force_spell_target_monster
#endif

    // Re-init SID after lengthy init sequence (defensive — ensures volume is set)
    jsr sound_init

    // Clear screen and do initial render
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr screen_unblank
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$91
    jsr c128_stack_guard_begin
#endif
    jsr status_draw
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$92
    jsr c128_stack_guard_check
#endif

    // Welcome message
    lda #<welcome_str
    sta zp_ptr0
    lda #>welcome_str
    sta zp_ptr0_hi
    jsr msg_print

#if C128_TEST_SCRIPTED_INPUT
    lda c128_test_summary_seen
    bne !gns_script_pass+
    jmp c128_test_town_fail_sym
!gns_script_pass:
    lda c128_test_summary_count
    cmp #1
    beq !gns_summary_count_ok+
    jmp c128_test_town_fail_sym
!gns_summary_count_ok:
#if C128_TEST_CACHE_SURVIVAL
    jsr c128_test_verify_cache_survival
    bcc !gns_cache_pass+
    jmp c128_test_cache_survival_fail_sym
!gns_cache_pass:
    jmp c128_test_cache_survival_pass_sym
#else
    jmp c128_test_town_pass_sym
#endif

#elif C128_TEST_CACHE_SURVIVAL
    lda c128_test_summary_seen
    bne !gns_script_pass+
    jmp c128_test_town_fail_sym
!gns_script_pass:
    lda c128_test_summary_count
    cmp #1
    beq !gns_cache_summary_count_ok+
    jmp c128_test_town_fail_sym
!gns_cache_summary_count_ok:
    jsr c128_test_verify_cache_survival
    bcc !gns_cache_pass+
    jmp c128_test_cache_survival_fail_sym
!gns_cache_pass:
    jmp c128_test_cache_survival_pass_sym
#endif

    jmp main_loop

// ============================================================
// load_resume_game — Entry point after successful load
// ============================================================
load_resume_game:
    jsr wizard_reset_session_state
    jsr player_search_clear_transient_state

    // Reset transient tier metadata from any prior runtime state, then
    // load the correct tier for the resumed dungeon level.
    jsr tier_invalidate_state
    jsr tier_check_transition

    // Recalculate derived stats from loaded base values
    jsr player_calc_stats
    jsr player_calc_hp

    // Stop any running
    lda #$ff
    sta zp_run_dir

    // Re-init SID
    jsr sound_init

#if C128
#if PERF_P1
    // Reset movement responsiveness counters after restore.
    jsr perf_p1_reset
#endif
#endif

    // Viewport coords are transient and not restored from saves. Seed a
    // neutral origin before the first post-load deadband update so stale
    // title/UI state cannot leave the renderer starting from $FF rows/cols.
    lda #0
    sta zp_view_x
    sta zp_view_y

    // Clear screen and render the loaded level
    jsr screen_clear
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    jsr status_draw

    // Welcome back message
    lda #<save_welcome_str
    sta zp_ptr0
    lda #>save_welcome_str
    sta zp_ptr0_hi
    jsr msg_print

main_loop:
#if C128
c128_town_move_diag_loop_top:
    jsr platform_main_loop_begin_api
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda c128_town_dump_countdown
    beq !town_dump_trap+
    sec
    sbc #1
    sta c128_town_dump_countdown
    bne !town_dump_log+
!town_dump_trap:
    jmp c128_town_dump_checkpoint
!town_dump_log:
    lda #$10
    jsr c128_town_dump_log
#endif
#if C128_TEST_FORCE_DEATH
    lda c128_test_force_death_pending
    beq !test_force_death_done+
    lda #0
    sta c128_test_force_death_pending
    lda #DEATH_CURSED
    sta zp_death_source
    jsr player_sync_from_zp
    jsr tramp_game_over
!test_force_death_done:
#endif
#if C128_TEST_SCRIPTED_SPELL
    lda c128_test_spell_return_pending
    beq !c128_test_spell_return_done+
    dec c128_test_spell_return_pending
    inc c128_test_spell_return_count
    lda c128_test_spell_return_count
    cmp #8
    bcc !c128_test_spell_return_done+
    jmp c128_test_spell_pass_sym
!c128_test_spell_return_done:
#endif
#if C128_TEST_SCRIPTED_PRAYER
    lda c128_test_spell_return_pending
    beq !c128_test_prayer_return_done+
    dec c128_test_spell_return_pending
    inc c128_test_spell_return_count
    lda c128_test_spell_return_count
    cmp #8
    bcc !c128_test_prayer_return_done+
    lda zp_eff_bless
    beq !c128_test_prayer_return_done+
    jsr c128_test_prayer_history_has_bless
    bcc !c128_test_prayer_return_done+
    jmp c128_test_spell_pass_sym
!c128_test_prayer_return_done:
#endif
#if C64_TEST_SCRIPTED_SPELL
    lda c64_test_spell_return_pending
    beq !c64_test_spell_return_done+
    dec c64_test_spell_return_pending
    inc c64_test_spell_return_count
    lda c64_test_spell_return_count
    cmp #8
    bcc !c64_test_spell_return_done+
    jmp c64_test_spell_pass_sym
!c64_test_spell_return_done:
#endif
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    lda c64_test_spell_return_pending
    beq !c64_test_dungeon_spell_return_done+
    dec c64_test_spell_return_pending
    lda c64_test_spell_return_pending
    bne !c64_test_dungeon_spell_return_done+
    lda c64_test_spell_success_count
    cmp active_dungeon_count
    bcc !c64_test_dungeon_spell_return_done+
    jmp c64_test_spell_pass_sym
!c64_test_dungeon_spell_return_done:
#endif
#if C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT
    lda c64_test_spell_return_pending
    beq !c64_test_detect_return_done+
    dec c64_test_spell_return_pending
    inc c64_test_spell_return_count
    lda c64_test_spell_return_count
    cmp #20
    bcc !c64_test_detect_return_done+
    jmp c64_test_spell_pass_sym
!c64_test_detect_return_done:
#endif

#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jsr c64_test_force_spell_target_monster
#endif

    // --- Running continuation ---
    lda zp_run_dir
    cmp #$ff
    beq !not_running+

    // Confusion cancels running
    lda zp_eff_confuse
    beq !not_conf_run+
    lda #$ff
    sta zp_run_dir
    jmp !not_running+
!not_conf_run:
    // Running cancel is edge-like: ignore the initiating held key(s) until
    // the keyboard returns to neutral once, then any new keypress cancels.
    lda run_input_armed
    bne !run_cancel_check+
    jsr input_run_key_held
    beq !run_arm_cancel+
    jmp run_step                // Still holding initiating key: keep running
!run_arm_cancel:
    lda #1
    sta run_input_armed
    jsr input_run_cancel_reset
    jmp run_step
!run_cancel_check:
    jsr input_run_cancel_check  // Returns nonzero on a new cancel key edge
    bne !run_cancel+
    jmp run_step

!run_cancel:
    jsr input_flush_run_cancel_buffer
    lda #$ff
    sta zp_run_dir
    lda #0
    sta run_input_armed
    jsr input_run_cancel_reset
!not_running:
    // Paralysis check — skip input, just tick the turn
    lda zp_eff_paralyze
    beq !not_paralyzed+
    jsr msg_clear
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$93
    jsr c128_stack_guard_begin
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1e
    jsr c128_town_dump_log
#endif
    jsr status_draw
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$94
    jsr c128_stack_guard_check
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1f
    jsr c128_town_dump_log
#endif
    jmp main_loop
!not_paralyzed:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$11
    jsr c128_town_dump_log
#endif
    // Snapshot the pre-command player/view state once per main-loop
    // iteration so any later stationary command can safely use the shared
    // post-turn redraw helpers.
    ldx zp_player_x
    stx old_player_x
    ldx zp_player_y
    stx old_player_y
    ldx zp_view_x
    stx old_view_x
    ldx zp_view_y
    stx old_view_y
    jsr input_get_command
#if C128
c128_town_move_diag_after_input_get_command:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$12
    jsr c128_town_dump_log
#endif

    // --- Dispatch command ---

    // Save and quit?
    cmp #CMD_SAVE
    bne !not_save+
    lda disk_setup_done
    bne !save_setup_ready+
    jsr tramp_disk_setup
    lda disk_setup_done
    beq !save_return_view+
!save_setup_ready:
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr save_game
    lda #0
    adc #0
    sta zp_temp0
    jsr disk_prompt_game        // Swap back to game disk if dual
    lda zp_temp0
    beq !save_return_main+
    jmp !quit+
!save_return_main:
#if C128
    jsr platform_runtime_resync_api
    jsr input_wait_release
    jmp ui_view_return_to_gameplay_view
#else
    jsr ui_view_redraw_gameplay_view
    jmp main_loop
#endif
!save_return_view:
#if C128
    jsr platform_runtime_resync_api
    jsr input_wait_release
#endif
    jmp ui_view_return_to_gameplay_view
!not_save:

    // Quit?
    cmp #CMD_QUIT
    bne !not_quit+
    jmp !quit+
!not_quit:

    // Character info?
    cmp #CMD_CHAR_INFO
    bne !not_char+
    jmp cmd_show_character_view
!not_char:

    // Help?
    cmp #CMD_HELP
    bne !not_help+
    jmp cmd_show_help_view
!not_help:

    // Wizard mode?
    cmp #CMD_WIZARD
    bne !not_wizard+
    jmp cmd_wizard_entry
!not_wizard:

    cmp #CMD_SEARCH_MODE
    bne !not_search_mode+
    jmp cmd_search_mode
!not_search_mode:

#if C128
#if PERF_P1
    // PERF_P1 counter dump (debug key: 'V')
    cmp #CMD_VERSION
    bne !not_perf_dump+
    jsr perf_p1_dump_overlay
    jmp main_loop
!not_perf_dump:
#endif
#endif

    // Monster recall?
    cmp #CMD_RECALL
    beq !+
    jmp !not_recall+
!:  jmp cmd_recall_view
!not_recall:

    // Movement? (CMD_MOVE_N through CMD_MOVE_SE = $01-$08)
    cmp #CMD_MOVE_N
    bcs !mv_hi_check+
    jmp !not_move+
!mv_hi_check:
    cmp #CMD_MOVE_SE + 1
    bcc !mv_cmd_ok+
    jmp !not_move+
!mv_cmd_ok:

#if C128
#if PERF_P1
    jsr perf_p1_move_start
#endif
#endif

    // Clear message before move so combat messages survive
    pha                         // Save command ID (A) — msg_clear clobbers A
#if C128_TEST_TOWN_SELF_DUMP
    lda #$13
    jsr c128_town_dump_log
#endif
    jsr msg_clear
    pla                         // Restore command ID for player_try_move

    // Try to move
#if C128
c128_town_move_diag_before_player_try_move:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$14
    jsr c128_town_dump_log
#endif
    jsr player_try_move
#if C128
c128_town_move_diag_after_player_try_move:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$15
    jsr c128_town_dump_log
#endif
    bcs !move_ok+
    jmp !move_blocked+
!move_ok:

    // Move or attack succeeded — run AI before render so screen
    // reflects post-AI monster positions (BUG-17 fix)
#if C128_TEST_TOWN_SELF_DUMP
    lda #$16
    jsr c128_town_dump_log
#endif
    jsr trap_check_at_player
#if C128
c128_town_move_diag_after_trap_check:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$17
    jsr c128_town_dump_log
#endif
    bcs !move_trap_fired+
    jsr player_move_maybe_passive_search
!move_trap_fired:
    jsr turn_post_action_searchable_or_die
#if C128
c128_town_move_diag_after_turn_post_action:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$18
    jsr c128_town_dump_log
#endif
    bcc !not_dead+
    jmp !player_died+
!not_dead:
#if C128_TEST_TOWN_SELF_DUMP
    lda #$19
    jsr c128_town_dump_log
#endif
    jsr update_visibility
    jsr viewport_update

    // Did viewport scroll?
    lda zp_view_x
    cmp old_view_x
#if C128
#if PERF_P1
    beq !mv_chk_y+
    jsr perf_p1_mark_scroll
    jmp !full_redraw+
!mv_chk_y:
#else
    bne !full_redraw+
#endif
#else
    bne !full_redraw+
#endif
    lda zp_view_y
    cmp old_view_y
#if C128
#if PERF_P1
    beq !mv_chk_reveal+
    jsr perf_p1_mark_scroll
    jmp !full_redraw+
!mv_chk_reveal:
#else
    bne !full_redraw+
#endif
#else
    bne !full_redraw+
#endif

    // Did a room get revealed?
    lda vis_room_revealed
    bne !full_redraw+

    // Did monsters or other scene elements move this turn?
    lda turn_scene_dirty
    bne !scene_dirty_redraw+

    // No scroll, no room reveal, no remote scene changes — render local area around old+new position
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1a
    jsr c128_town_dump_log
#endif
    jsr render_local_area
#if C128
#if PERF_P1
    jsr perf_p1_mark_local
    jsr perf_p1_move_end
#endif
#endif
    jmp !post_move+

!scene_dirty_redraw:
#if C128
    jmp !full_draw_fallback+
#else
    jsr render_viewport
    jmp !post_move+
#endif

!full_redraw:
#if C128
    lda turn_scene_dirty
    bne !full_draw_fallback+
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1b
    jsr c128_town_dump_log
#endif
    jsr render_viewport_scroll_delta
    bcc !full_draw_fallback+
    // Scroll-delta path handled viewport shift; refresh local dynamic area.
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1c
    jsr c128_town_dump_log
#endif
    jsr render_local_area
#if C128
#if PERF_P1
    jsr perf_p1_mark_scroll_delta
    jsr perf_p1_move_end
#endif
#endif
    jmp !post_move+
!full_draw_fallback:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1d
    jsr c128_town_dump_log
#endif
    jsr render_viewport
#if C128
#if PERF_P1
    jsr perf_p1_mark_scroll_fallback
    jsr perf_p1_move_end
#endif
#endif

!post_move:
    // Check if player stepped on a store door (town only)
    lda zp_player_dlvl
    bne !not_store_entry+
    jsr check_player_on_store_door
    bcc !not_store_entry+
    sta zp_store_idx
    jsr tramp_store_enter
    jsr viewport_update
    jsr render_viewport
!not_store_entry:
#if C128
c128_town_move_diag_before_status_draw:
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1e
    jsr c128_town_dump_log
#endif
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$95
    jsr c128_stack_guard_begin
#endif
    jsr status_draw
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$96
    jsr c128_stack_guard_check
#endif
#if C128_TEST_TOWN_SELF_DUMP
    lda #$1f
    jsr c128_town_dump_log
#endif
#if C128
c128_town_move_diag_after_status_draw:
#endif
    jmp main_loop

!move_blocked:
    // Bump sound already played by player_try_move
    jmp main_loop
!not_move:

    // Running? (CMD_RUN_N through CMD_RUN_SE = $25-$2c)
    cmp #CMD_RUN_N
    bcc !dispatch_discrete+
    cmp #CMD_RUN_SE + 1
    bcs !dispatch_discrete+
    jmp cmd_run

!dispatch_discrete:
    cmp #CMD_STAIRS_DN
    bcc !unknown_command+
    cmp #CMD_TUNNEL + 1
    bcs !unknown_command+
    sec
    sbc #CMD_STAIRS_DN
    tax
    lda command_dispatch_lo,x
    sta zp_ptr0
    lda command_dispatch_hi,x
    sta zp_ptr0_hi
    jmp (zp_ptr0)

!unknown_command:
    // Unknown command — ignore
    jmp main_loop

command_dispatch_lo:
    .byte <cmd_stairs_dn
    .byte <cmd_stairs_up
    .byte <cmd_rest
    .byte <cmd_search
    .byte <cmd_open
    .byte <cmd_close
    .byte <cmd_pickup
    .byte <cmd_drop
    .byte <cmd_inventory
    .byte <cmd_equipment
    .byte <cmd_wear
    .byte <cmd_takeoff
    .byte <cmd_eat
    .byte <cmd_quaff
    .byte <cmd_read
    .byte <cmd_aim
    .byte <cmd_use
    .byte <cmd_cast
    .byte <cmd_pray
    .byte <cmd_dispatch_ignore    // CMD_CHAR_INFO handled above
    .byte <cmd_dispatch_ignore    // CMD_MAP unused
    .byte <cmd_dispatch_ignore    // CMD_RECALL handled above
    .byte <cmd_look
    .byte <cmd_dispatch_ignore    // CMD_RUN meta-command unused
    .byte <cmd_dispatch_ignore    // CMD_SAVE handled above
    .byte <cmd_dispatch_ignore    // CMD_QUIT handled above
    .byte <cmd_dispatch_ignore    // CMD_HELP handled above
    .byte <cmd_dispatch_ignore    // CMD_VERSION handled above / ignored
    .byte <cmd_dispatch_ignore    // CMD_RUN_N handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_S handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_W handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_E handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_NW handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_NE handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_SW handled above
    .byte <cmd_dispatch_ignore    // CMD_RUN_SE handled above
    .byte <cmd_gain
    .byte <cmd_fire
    .byte <cmd_throw
    .byte <cmd_refuel
    .byte <cmd_bash
    .byte <cmd_tunnel
command_dispatch_hi:
    .byte >cmd_stairs_dn
    .byte >cmd_stairs_up
    .byte >cmd_rest
    .byte >cmd_search
    .byte >cmd_open
    .byte >cmd_close
    .byte >cmd_pickup
    .byte >cmd_drop
    .byte >cmd_inventory
    .byte >cmd_equipment
    .byte >cmd_wear
    .byte >cmd_takeoff
    .byte >cmd_eat
    .byte >cmd_quaff
    .byte >cmd_read
    .byte >cmd_aim
    .byte >cmd_use
    .byte >cmd_cast
    .byte >cmd_pray
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_look
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_dispatch_ignore
    .byte >cmd_gain
    .byte >cmd_fire
    .byte >cmd_throw
    .byte >cmd_refuel
    .byte >cmd_bash
    .byte >cmd_tunnel

cmd_dispatch_ignore:
    jmp main_loop

cmd_stairs_dn:
    jsr check_stairs_at_player
    cmp #9                  // Stairs down type
    beq !stairs_dn_ok+
    jmp !no_stairs_dn+
!stairs_dn_ok:
    // Descend: increment dungeon level
    inc zp_player_dlvl
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    // Update max depth if deeper than before
    cmp player_data + PL_MAX_DLVL
    bcc !dn_not_deeper+
    beq !dn_not_deeper+
    sta player_data + PL_MAX_DLVL
!dn_not_deeper:
    lda #0
    sta level_entry_dir         // 0 = descended
    jsr level_change_generate_current
    lda #<descend_str
    sta zp_ptr0
    lda #>descend_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop
!no_stairs_dn:
    lda #<no_stairs_str
    sta zp_ptr0
    lda #>no_stairs_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop

cmd_stairs_up:
    jsr check_stairs_at_player
    cmp #10                 // Stairs up type
    beq !stairs_up_ok+
    jmp !no_stairs_up+
!stairs_up_ok:
    // Ascend
    lda zp_player_dlvl
    bne !stairs_up_not_surface+
    jmp !at_surface+
!stairs_up_not_surface:
    dec zp_player_dlvl
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    // Restock stores when returning to town
    bne !not_entering_town+
    jsr tramp_store_restock_all
!not_entering_town:
    lda #1
    sta level_entry_dir         // 1 = ascended
    jsr level_change_generate_current
    lda #<ascend_str
    sta zp_ptr0
    lda #>ascend_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop
!at_surface:
    lda #<at_surface_str
    sta zp_ptr0
    lda #>at_surface_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop
!no_stairs_up:
    lda #<no_stairs_str
    sta zp_ptr0
    lda #>no_stairs_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop

// level_change_generate_current — Shared tail after caller has already updated
// depth/max-depth/restock state and set level_entry_dir.
// Restores gameplay view and returns.
level_change_generate_current:
    jsr generation_busy_begin_if_dungeon_api
    jsr player_search_mode_off
    lda #$ff
    sta zp_run_dir
    lda #0
    sta eff_detect_timer
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    jsr generation_busy_tick_if_dungeon_api
    bcc !lcgc_ovl_ok+
    jmp entry_main
!lcgc_ovl_ok:
#if C128
    jsr platform_runtime_resync_api
#endif
    jsr tramp_level_generate
    jsr generation_busy_tick_if_dungeon_api
    jsr tier_check_transition
#if C128
    jsr c128_restore_generation_overlay
#endif
    jsr monster_spawn_level
    jsr generation_busy_tick_if_dungeon_api
    jsr item_spawn_level
    jsr generation_busy_tick_if_dungeon_api
#if C64_TEST_SCRIPTED_DUNGEON_SPELL
    jsr c64_test_force_spell_target_monster
#endif
#if C128_TEST_FORCE_DUNGEON_MELEE
    jsr c128_test_force_dungeon_melee
#endif
    jsr update_visibility
    jsr generation_busy_end_if_dungeon_api
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr screen_unblank
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$97
    jsr c128_stack_guard_begin
#endif
    jsr status_draw
#if C128_REAL_BOOT_DIAG || C128_STATUS_SP_CANARY_DIAG
    ldx #$98
    jsr c128_stack_guard_check
#endif
    rts

#if C128
// tier_load reuses the $E000 overlay window for tier payloads. Restore the
// dungeon-generation overlay before any post-generation special-room helpers
// jump back into overlay-resident code.
c128_restore_generation_overlay:
    lda current_overlay
    cmp #OVL_DUNGEON_GEN
    beq !crgo_done+
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcc !crgo_loaded+
    jmp entry_main
!crgo_loaded:
    jsr c128_restore_runtime_guards
!crgo_done:
    rts
#endif

cmd_open:
    jsr msg_clear
    jsr get_direction_target
    bcc !open_no_turn+          // Invalid direction, no turn consumed
    jsr door_try_open
    bcc !open_no_turn+          // No door there, no turn consumed
    // Door opened or stuck — consume turn and re-render
    jmp post_turn_redraw_full_or_die
!open_no_turn:
    jmp main_loop

cmd_close:
    jsr msg_clear
    jsr get_direction_target
    bcc !close_no_turn+
    jsr door_try_close
    bcc !close_no_turn+
    // Door closed — consume turn and re-render
    jmp post_turn_redraw_full_or_die
!close_no_turn:
    jmp main_loop

cmd_search:
    jsr msg_clear
    jsr do_search
    // Always consumes a turn
    jmp post_turn_redraw_full_or_die

cmd_search_mode:
    jsr msg_clear
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq !toggle_on+
    jsr player_search_mode_off
    lda #<search_mode_off_str
    sta zp_ptr0
    lda #>search_mode_off_str
    sta zp_ptr0_hi
    jmp !toggle_print+
!toggle_on:
    jsr player_search_mode_on
    lda #<search_mode_on_str
    sta zp_ptr0
    lda #>search_mode_on_str
    sta zp_ptr0_hi
!toggle_print:
    jsr msg_print
    jsr status_draw
    jmp main_loop

cmd_rest:
    jsr msg_clear
    jmp post_turn_status_only_or_die

cmd_pickup:
    jsr msg_clear
    jsr item_pickup
    jmp command_result_main_or_status_only

cmd_drop:
    jsr msg_clear
    jsr item_drop
    jmp command_result_main_or_redraw_full

cmd_inventory:
    lda #$ff
    sta piw_filter              // Show all items
    jmp cmd_show_inventory_view

cmd_equipment:
    jmp cmd_show_equipment_view

cmd_wear:
    jsr msg_clear
    jsr item_wear
    jmp command_result_main_or_redraw_full

cmd_takeoff:
    jsr msg_clear
    jsr item_takeoff
    jmp command_result_main_or_redraw_full

cmd_eat:
    jsr msg_clear
    jsr item_eat
    jmp command_result_main_or_status_only

cmd_quaff:
    jsr msg_clear
    jsr item_quaff
    jmp command_result_main_or_status_only

cmd_read:
    jsr msg_clear
    jsr tramp_item_read_scroll
    // After teleportation or light, need visibility + render
    jmp command_result_main_or_update_visibility

cmd_aim:
    jsr msg_clear
    jsr tramp_item_aim_wand
    jmp command_result_main_or_update_visibility

cmd_use:
    jsr msg_clear
    jsr tramp_item_use_staff
    jmp command_result_main_or_update_visibility

cmd_cast:
    jsr msg_clear
#if C128
    jsr tramp_player_cast_spell
#else
    jsr player_cast_spell
#endif
    jmp command_result_main_or_update_visibility

cmd_pray:
    jsr msg_clear
#if C128
    jsr tramp_player_pray
#else
    jsr player_pray
#endif
    jmp command_result_main_or_update_visibility

cmd_gain:
    jsr msg_clear
    jsr tramp_item_gain_spell
    jmp command_result_main_or_status_only

cmd_fire:
    jsr msg_clear
#if C128
    jsr tramp_ranged_fire
#else
    jsr ranged_fire
#endif
    jmp command_result_main_or_update_visibility

cmd_throw:
    jsr msg_clear
#if C128
    jsr tramp_throw_item
#else
    jsr throw_item
#endif
    jmp command_result_main_or_update_visibility

cmd_refuel:
    jsr msg_clear
    jsr tramp_item_refuel
    jmp command_result_main_or_status_only

cmd_bash:
    jsr msg_clear
#if C128
    jsr tramp_bash_command
#else
    jsr bash_command
#endif
    jmp command_result_main_or_update_visibility

cmd_tunnel:
    jsr msg_clear
#if C128
    jsr tramp_player_tunnel
#else
    jsr player_tunnel
#endif
    jmp command_result_main_or_update_visibility

cmd_look:
    jsr msg_clear
    jsr do_look
    jmp main_loop

cmd_run:
    pha                         // Save command ID — msg_clear clobbers A
    jsr msg_clear
    pla
    sec
    sbc #CMD_RUN_N              // Direction index 0-7
    sta zp_run_dir
    lda #0
    sta run_input_armed
    jsr input_run_cancel_reset
    jmp run_step                // Take first step

#if C128
run_stop_reset_input_state:
    lda #0
    sta run_input_armed
    jmp input_run_cancel_reset
#endif

// ============================================================
// run_step — Execute one step of corridor running
// ============================================================
run_step:
    // Save positions before move for dirty render
    ldx zp_player_x
    stx old_player_x
    ldx zp_player_y
    stx old_player_y
    ldx zp_view_x
    stx old_view_x
    ldx zp_view_y
    stx old_view_y

    // Save current tile's lit status for room entry/exit detection
    ldx zp_player_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_player_x
    :MapRead_ptr0_y()
    and #FLAG_LIT
    sta run_was_lit

    // Convert running direction to movement command
    lda zp_run_dir
    clc
    adc #CMD_MOVE_N

    // Try to move
    jsr player_try_move
    bcc !run_blocked+           // Wall → stop, no turn consumed

    // Check trap
    jsr msg_clear
    jsr trap_check_at_player
    bcs !run_trap_stop+         // Trap fired → stop, turn consumed

    // Check other stop conditions
    jsr run_check_stop
    bcs !run_stop_move+         // Should stop → final move

    // Continue running — run AI before render (BUG-17 fix)
    jsr player_move_maybe_passive_search
    jsr turn_post_action_searchable_or_die
    bcc !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jsr viewport_update

    // Check for viewport scroll or room reveal
    lda zp_view_x
    cmp old_view_x
    bne !run_full_redraw+
    lda zp_view_y
    cmp old_view_y
    bne !run_full_redraw+
    lda vis_room_revealed
    bne !run_full_redraw+

    jsr render_local_area
    jmp !run_post+

!run_full_redraw:
#if C128
    jsr render_viewport_scroll_delta
    bcc !run_full_fallback+
    jsr render_local_area
    jmp !run_post+
!run_full_fallback:
#endif
    jsr render_viewport

!run_post:
    jsr status_draw
    lda zp_msg_flags
    beq !run_keep_running+
    lda #$ff
    sta zp_run_dir
#if C128
    jsr run_stop_reset_input_state
#endif
!run_keep_running:
    jmp main_loop

!run_blocked:
    lda #$ff
    sta zp_run_dir
#if C128
    jsr run_stop_reset_input_state
#endif
    jmp main_loop

!run_trap_stop:
    lda #$ff
    sta zp_run_dir
#if C128
    jsr run_stop_reset_input_state
#endif
    jsr turn_post_action_searchable_or_die
    bcc !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop

!run_stop_move:
    lda #$ff
    sta zp_run_dir
#if C128
    jsr run_stop_reset_input_state
#endif
    jsr player_move_maybe_passive_search
    jsr turn_post_action_searchable_or_die
    bcc !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jsr viewport_update

    // Check for viewport scroll or room reveal
    lda zp_view_x
    cmp old_view_x
    bne !rsm_full+
    lda zp_view_y
    cmp old_view_y
    bne !rsm_full+
    lda vis_room_revealed
    bne !rsm_full+
    lda turn_scene_dirty
    bne !rsm_scene_full+

    jsr render_local_area
    jmp !rsm_post+
!rsm_scene_full:
    jsr render_viewport
    jmp !rsm_post+
!rsm_full:
#if C128
    jsr render_viewport_scroll_delta
    bcc !rsm_full_fallback+
    jsr render_local_area
    jmp !rsm_post+
!rsm_full_fallback:
#endif
    jsr render_viewport
!rsm_post:
    jsr status_draw
    jmp main_loop

player_died:
!player_died:
    lda zp_death_source
    sta death_source_saved

    // Render current positions before showing death message (BUG-46 fix).
    // All death paths skip the normal post-AI render, leaving stale monster
    // positions on screen. Render now so the killing blow is visible.
    jsr viewport_update
    jsr render_viewport

    // Show "YOU HAVE BEEN SLAIN." with -more- BEFORE disk I/O
    // so the player isn't staring at a frozen screen during file ops
    lda #<slain_str
    sta zp_ptr0
    lda #>slain_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr msg_show_more
    jsr input_get_key

    // Now do disk I/O (player sees -more- prompt, knows they died)
    lda disk_setup_done
    bne !pd_disk_ready+
    jsr tramp_disk_setup
    bcs !pd_skip_disk_io+
!pd_disk_ready:
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr player_sync_from_zp
    lda death_source_saved
    sta zp_death_source
    jsr tramp_game_over         // Score, hiscore load/insert/save, death screen
    jsr disk_prompt_game        // Swap back to game disk if dual
    jmp !pd_done+
!pd_skip_disk_io:
    lda death_source_saved
    sta zp_death_source
    jsr tramp_game_over
!pd_done:
    jsr input_get_modal_dismiss_key
    jmp !quit+

!quit:
    jsr game_over_prompt    // R)EBOOT / S)TART OVER / Q)UIT — Q falls through

    // --- Clean exit to BASIC ---
exit:
    jmp exit_trampoline     // Must run from below $A000 (banks in BASIC ROM)

#import "ui_restore.s"
#import "game_loop_helpers.s"

// ============================================================
// String data — gameplay strings (MUST stay below $C000)
// ============================================================

press_key_str:
    .text "Press any key" ; .byte 0

welcome_str:
    .text "Welcome to Moria8! Shift+Q to quit." ; .byte 0

search_mode_on_str:
    .text "Search mode on." ; .byte 0

search_mode_off_str:
    .text "Search mode off." ; .byte 0

descend_str:
    .text "You descend the staircase." ; .byte 0

ascend_str:
    .text "You ascend the staircase." ; .byte 0

at_surface_str:
    .text "You are already at the surface." ; .byte 0

no_stairs_str:
    .text "You see no stairs here." ; .byte 0

slain_str:
    .text "You have been slain." ; .byte 0

death_source_saved:
    .byte 0

// Recall command variables
recall_prompt_str: .text "Recall which? " ; .byte 0
recall_query_sc:   .byte 0             // Screen code of typed letter
recall_found_type: .byte 0             // Creature type index found
recall_last_sc:    .byte 0             // Screen code of last recall shown (0 = none)
recall_last_idx:   .byte 0             // Creature index last shown (for cycling)
run_input_armed:   .byte 0             // Running cancel armed after first neutral scan

#if C128_TEST_FORCE_DUNGEON_MELEE
c128_test_force_dungeon_melee_pending: .byte 1

c128_test_force_dungeon_melee:
    lda c128_test_force_dungeon_melee_pending
    beq !ctfdm_done+
    lda zp_player_dlvl
    beq !ctfdm_done+

    lda zp_player_y
    sta c128_test_force_melee_y
    lda zp_player_x
    clc
    adc #1
    sta c128_test_force_melee_x

    lda c128_test_force_melee_x
    ldy c128_test_force_melee_y
    jsr monster_find_at
    bcc !ctfdm_clear_tile+
    jsr monster_remove

!ctfdm_clear_tile:
    ldx c128_test_force_melee_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy c128_test_force_melee_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK & (~FLAG_OCCUPIED & $ff)
    :MapWrite_ptr0_y()

    lda c128_test_force_melee_x
    sta ms_spawn_x
    lda c128_test_force_melee_y
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one
    bcc !ctfdm_done+

    lda #0
    sta c128_test_force_dungeon_melee_pending
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE | MF_PROVOKED
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #$ff
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLEE_LO
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLEE_HI
    sta (zp_ptr0),y
!ctfdm_done:
    rts

c128_test_force_melee_x: .byte 0
c128_test_force_melee_y: .byte 0
#endif

// ============================================================
// calc_dig_ability — Calculate digging ability (STR + tool/weapon bonus)
// New formula for R14: (STR>>2) + base_bonus + (ego*12) for digging tools
// Output: tun_dig_ability set
// Clobbers: A, X
// ============================================================
calc_dig_ability:
    // Check equipped weapon
    ldx inv_item_id + EQUIP_WEAPON
    cpx #$FF
    bne !cda_has_weapon+

    // Bare hands: ability = 0
    lda #0
    sta tun_dig_ability
    rts

!cda_has_weapon:
    lda it_category,x
    cmp #ICAT_DIGGING
    beq !cda_dig_tool+

    // Regular weapon: ability = (STR >> 2) + max(0, PL_TODMG >> 1)
    lda zp_player_str
    lsr
    lsr                         // STR >> 2
    sta tun_dig_ability
    lda player_data + PL_TODMG
    bmi !cda_done+              // Negative TODMG → skip (leave ability = STR>>2)
    lsr                         // TODMG >> 1
    clc
    adc tun_dig_ability
    bcc !cda_ok+
    lda #$FF                    // Cap at 255
!cda_ok:
    sta tun_dig_ability
!cda_done:
    rts

!cda_dig_tool:
    // Digging tool: ability = (STR >> 2) + dig_base_table[type-62] + (ego * 12)
    lda zp_player_str
    lsr
    lsr                         // STR >> 2
    sta tun_dig_ability

    // Add base bonus from table
    txa
    sec
    sbc #62                     // Index into dig_base_table (0=Shovel, 1=Pick)
    tax
    lda dig_base_table,x
    clc
    adc tun_dig_ability
    sta tun_dig_ability

    // Add ego bonus: ego * 12
    lda inv_ego + EQUIP_WEAPON
    beq !cda_done-              // ego=0, no bonus
    // Multiply ego (1 or 2) by 12
    // ego * 12 = ego * 8 + ego * 4
    sta zp_temp2                // save ego
    asl                         // *2
    asl                         // *4
    sta zp_temp3                // ego*4
    asl                         // *8
    clc
    adc zp_temp3                // *8 + *4 = *12
    clc
    adc tun_dig_ability
    bcc !cda_ego_ok+
    lda #$FF                    // Cap at 255
!cda_ego_ok:
    sta tun_dig_ability
    rts

dig_base_table:
    .byte 6, 20                 // Shovel base=6, Pick base=20

// ============================================================
// roll_tool_ego_check — Handle ego roll for digging tools
// Called from roll_ego_type ($F000) via JMP when category != ICAT_WEAPON.
// A = category value from it_category lookup
// Returns: A = ego type (0, 1, or 2)
// Clobbers: A, X
// ============================================================
roll_tool_ego_check:
    // A has the category value. ICAT_DIGGING = 0.
    cmp #ICAT_DIGGING           // Re-test A (flags stale from prior CMP in roll_ego_type)
    bne !rtc_zero+              // category != 0 → not a digging tool
    // It IS a digging tool — roll ego based on dungeon level
    lda zp_player_dlvl
    cmp #10
    bcc !rtc_zero+              // DL < 10 → basic only (ego=0)
    lda #100
    jsr rng_range               // [0, 99]
    cmp #10
    bcc !rtc_ego2+              // 10% → check for Dwarven (ego=2)
    cmp #35
    bcc !rtc_ego1+              // 25% → Gnomish/Orcish (ego=1)
!rtc_zero:
    lda #0                      // 65% → basic
    rts
!rtc_ego2:
    lda zp_player_dlvl
    cmp #20
    bcc !rtc_ego1+              // DL 10-19 can't get ego=2, downgrade to ego=1
    lda #2
    rts
!rtc_ego1:
    lda #1
    rts

// ============================================================
// put_tool_ego_prefix — Print ego prefix for digging tools
// Input: A = ego (1 or 2), X = item type ID (62 or 63)
// Output: prefix string printed to screen (e.g., "Gnomish ")
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
put_tool_ego_prefix:
    // Compute index = (type - 62) * 2 + (ego - 1)
    sec
    sbc #1                      // ego - 1 (0 or 1)
    sta ptep_temp
    txa
    sec
    sbc #62                     // type - 62 (0=Shovel, 1=Pick)
    asl                         // * 2
    clc
    adc ptep_temp               // + (ego - 1) → index 0-3
    tax
    lda tool_ego_prefix_lo,x
    sta zp_ptr0
    lda tool_ego_prefix_hi,x
    sta zp_ptr0_hi
    jsr screen_put_string       // Print prefix (e.g., "Dwarven ")
    rts

ptep_temp: .byte 0

// Prefix strings (screen codes, null-terminated)
ego_tool_prefix_gnomish: .text "Gnomish " ; .byte 0
ego_tool_prefix_orcish:  .text "Orcish " ; .byte 0
ego_tool_prefix_dwarven: .text "Dwarven " ; .byte 0

// Prefix lookup table — indexed 0-3
// Index: (type-62)*2 + (ego-1)
//   0 = Shovel ego=1 → Gnomish
//   1 = Shovel ego=2 → Dwarven
//   2 = Pick ego=1   → Orcish
//   3 = Pick ego=2   → Dwarven
tool_ego_prefix_lo:
    .byte <ego_tool_prefix_gnomish, <ego_tool_prefix_dwarven
    .byte <ego_tool_prefix_orcish,  <ego_tool_prefix_dwarven
tool_ego_prefix_hi:
    .byte >ego_tool_prefix_gnomish, >ego_tool_prefix_dwarven
    .byte >ego_tool_prefix_orcish,  >ego_tool_prefix_dwarven

// ============================================================
// banked_ego_put_suffix — Write ego suffix to screen
// Input: A = ego type (0 = no ego)
// Clobbers: A, Y, zp_ptr0
// ============================================================
banked_ego_put_suffix:
    cmp #0
    beq !beps_done+
    cmp #EGO_TYPE_COUNT
    bcs !beps_done+
    jsr ego_get_suffix_ptr
    ldy #0
!beps_loop:
    lda (zp_ptr0),y
    beq !beps_done+
    sty beps_save_y
    jsr screen_put_char
    ldy beps_save_y
    iny
    jmp !beps_loop-
!beps_done:
    rts
beps_save_y: .byte 0

// ============================================================
// put_inv_name_with_ego — Print item name with ego prefix/suffix
// Input: X = inventory slot index
// For ICAT_DIGGING + ego>0: prints "Gnomish Shovel" (prefix + name)
// For other + ego>0: prints "Long Sword (Flame)"
// For auto-sensed unidentified items, appends the persistent "(magik)" marker.
// Clobbers: A, X, Y, zp_ptr0
// ============================================================
put_inv_name_with_ego:
    lda inv_item_id,x
    sta pinwe_item_id
    stx pinwe_slot
    tax
    lda it_category,x
    bne !pinwe_not_tool+
    ldx pinwe_slot
    lda inv_ego,x
    beq !pinwe_not_tool+
    cmp #EGO_TYPE_COUNT
    bcs !pinwe_not_tool+
    ldx pinwe_item_id
    jsr put_tool_ego_prefix
    lda pinwe_item_id
    jsr item_get_name_ptr
    jsr screen_put_string
    jsr put_inv_sensed_suffix
    rts
!pinwe_not_tool:
    lda pinwe_item_id
    jsr item_get_name_ptr
    jsr screen_put_string
    ldx pinwe_slot
    lda inv_ego,x
    cmp #EGO_TYPE_COUNT
    bcc !pinwe_valid_ego+
    lda #0
!pinwe_valid_ego:
    jsr banked_ego_put_suffix
    jsr put_inv_sensed_suffix
    rts

put_inv_sensed_suffix:
    ldx pinwe_slot
    lda inv_flags,x
    and #IF_IDENTIFIED | IF_SENSED
    cmp #IF_SENSED
    bne !pinwe_done+
    lda #<pinwe_sensed_suffix
    sta zp_ptr0
    lda #>pinwe_sensed_suffix
    sta zp_ptr0_hi
    jsr screen_put_string
!pinwe_done:
    rts

pinwe_sensed_suffix: .text " (magik)" ; .byte 0
pinwe_item_id: .byte 0
pinwe_slot:    .byte 0
