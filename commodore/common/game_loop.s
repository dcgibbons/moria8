// game_loop.s — Main game loop, command dispatch, and shared gameplay routines
//
// Platform-independent game logic extracted from main.s.
// Called by platform-specific main.s after hardware initialization.
// Forward-references trampoline labels defined in the platform's main.s
// (Kick Assembler resolves all labels globally within the compilation unit).

#if C128_TEST_FORCE_DEATH
c128_test_force_death_pending: .byte 1
#endif

// ============================================================
// game_new_start — New game initialization
// Called from platform main.s after title menu selects "New Game".
// ============================================================
game_new_start:
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

    // --- Character creation ---
    jsr tramp_player_create
#if C128
    jsr c128_restore_runtime_guards
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

    // Blank screen during lengthy init (hides BFS queue garbage + KERNAL messages)
    jsr screen_blank
    jsr screen_clear

    // Randomize item identification (shuffle potion/scroll/ring descriptors)
    jsr item_init_identification
#if C128_TEST_OVERLAY_STATE_CORRUPT
    lda #OVL_TOWN
    sta current_overlay
#endif
    jsr tramp_store_init_all
#if C128
    jsr c128_restore_runtime_guards
#endif

    // --- Main game loop ---
    // Initialize dungeon level and generate map (new game only)
    lda #0
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
#if C128_REAL_BOOT_DIAG
    ldx #$23
    jsr c128_stack_guard_begin
#endif
    jsr tramp_level_generate
#if C128_REAL_BOOT_DIAG
    ldx #$24
    jsr c128_stack_guard_check
#endif
#if C128
    jsr c128_restore_runtime_guards
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

    // Re-init SID after lengthy init sequence (defensive — ensures volume is set)
    jsr sound_init

    // Clear screen and do initial render
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr screen_unblank
    jsr status_draw

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
    jsr c128_restore_runtime_vectors
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
    lda #0
    sta KBDBUF_COUNT            // Flush keyboard buffer (C64 only; harmless on C128)
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
    jsr status_draw
    jmp main_loop
!not_paralyzed:
    jsr input_get_command
#if C128
c128_town_move_diag_after_input_get_command:
#endif

    // --- Dispatch command ---

    // Save and quit?
    cmp #CMD_SAVE
    bne !not_save+
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr save_game
    jsr disk_prompt_game        // Swap back to game disk if dual
    jmp !quit+
!not_save:

    // Quit?
    cmp #CMD_QUIT
    bne !not_quit+
    jmp !quit+
!not_quit:

    // Character info?
    cmp #CMD_CHAR_INFO
    bne !not_char+
    jsr tramp_ui_char_display
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    // Redraw map on return
    jsr screen_clear
    jmp vp_render_status_loop
!not_char:

    // Help?
    cmp #CMD_HELP
    bne !not_help+
    jsr tramp_ui_help_display
    lda #0
    sta KBDBUF_COUNT            // Clear keyboard buffer (prevent key repeat from dismissing)
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    // Redraw map on return — clear all rows then redraw
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jmp vp_render_status_loop
!not_help:

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
!:  jsr msg_clear
    // Show prompt on message row
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #<recall_prompt_str
    sta zp_ptr0
    lda #>recall_prompt_str
    sta zp_ptr0_hi
    jsr screen_put_string
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    // Convert PETSCII letter to screen code (lowercase/uppercase mode)
    // Unshifted letters ($41-$5A) → lowercase screen codes ($01-$1A)
    cmp #$41                    // 'A' unshifted
    bcc !recall_try_shifted+
    cmp #$5b                    // 'Z'+1
    bcs !recall_try_shifted+
    sec
    sbc #$40                    // PETSCII→screen code: $41→$01 (lowercase)
    sta recall_query_sc
    jmp !recall_start+
!recall_try_shifted:
    // Shifted letters ($C1-$DA) → uppercase screen codes ($41-$5A)
    cmp #$c1                    // shifted 'A'
    bcc !recall_done+
    cmp #$db                    // shifted 'Z'+1
    bcs !recall_done+
    and #$3f                    // $C1→$01
    clc
    adc #$40                    // $01→$41 (uppercase screen code)
    sta recall_query_sc
!recall_start:
    // Cycling: same char as last recall → start after last match, else start from 0
    lda recall_query_sc
    cmp recall_last_sc
    bne !recall_new_char+
    lda recall_last_idx
    clc
    adc #1
    cmp #MAX_CREATURES
    bcc !recall_set_start+
    lda #0
    jmp !recall_set_start+
!recall_new_char:
    lda #0
!recall_set_start:
    tax                         // X = search start index
    lda #MAX_CREATURES
    sta zp_temp1                // Loop counter (search all MAX_CREATURES slots)
!recall_search:
    lda cr_display,x
    cmp recall_query_sc
    bne !recall_next+
    lda recall_kills,x
    ora recall_deaths,x
    ora recall_attacks,x
    ora recall_spells,x
    bne !recall_found+
!recall_next:
    inx
    cpx #MAX_CREATURES
    bcc !recall_no_wrap+
    ldx #0
!recall_no_wrap:
    dec zp_temp1
    bne !recall_search-
    lda #0                      // No match — clear cycling state
    sta recall_last_sc
    jmp !recall_done+
!recall_found:
    stx recall_found_type
    lda recall_query_sc         // Update cycling state for next recall
    sta recall_last_sc
    stx recall_last_idx
    jsr creature_get_name       // Populates creature_name_buf
    jsr tramp_ui_recall
    lda #0
    sta KBDBUF_COUNT            // Clear keyboard buffer (prevent key repeat from dismissing)
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key           // Wait for dismiss
!recall_done:
    jsr screen_clear
    jmp vp_render_status_loop
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

    // Save positions before move for dirty render
    ldx zp_player_x
    stx old_player_x
    ldx zp_player_y
    stx old_player_y
    ldx zp_view_x
    stx old_view_x
    ldx zp_view_y
    stx old_view_y

    // Clear message before move so combat messages survive
    pha                         // Save command ID (A) — msg_clear clobbers A
    jsr msg_clear
    pla                         // Restore command ID for player_try_move

    // Try to move
#if C128
c128_town_move_diag_before_player_try_move:
#endif
    jsr player_try_move
#if C128
c128_town_move_diag_after_player_try_move:
#endif
    bcc !move_blocked+

    // Move or attack succeeded — run AI before render so screen
    // reflects post-AI monster positions (BUG-17 fix)
    jsr trap_check_at_player
#if C128
c128_town_move_diag_after_trap_check:
#endif
    jsr turn_post_action
#if C128
c128_town_move_diag_after_turn_post_action:
#endif
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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

    // No scroll, no room reveal — render local area around old+new position
    jsr render_local_area
#if C128
#if PERF_P1
    jsr perf_p1_mark_local
    jsr perf_p1_move_end
#endif
#endif
    jmp !post_move+

!full_redraw:
#if C128
    jsr render_viewport_scroll_delta
    bcc !full_draw_fallback+
    // Scroll-delta path handled viewport shift; refresh local dynamic area.
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
    jsr render_viewport
#if C128
#if PERF_P1
    jsr perf_p1_mark_scroll_fallback
    jsr perf_p1_mark_full
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
    jsr status_draw
#if C128
c128_town_move_diag_after_status_draw:
#endif
    jmp main_loop

!move_blocked:
    // Bump sound already played by player_try_move
    jmp main_loop
!not_move:

    // Stairs down?
    cmp #CMD_STAIRS_DN
    beq !stairs_dn+
    jmp !not_stairs_dn+
!stairs_dn:
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
    jsr screen_blank
    jsr screen_clear            // Clear old level before lengthy load/generate
    jsr tier_check_transition   // Load new tier if crossing boundary
    lda #0
    sta level_entry_dir         // 0 = descended
    lda #$ff
    sta zp_run_dir              // Stop running on level change
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcc !stairs_dn_ovl_ok+
    jmp entry_main
!stairs_dn_ovl_ok:
    jsr tramp_level_generate
#if C128
    jsr c128_restore_runtime_guards
#endif
    jsr monster_spawn_level
    jsr item_spawn_level
#if C128_TEST_FORCE_DUNGEON_MELEE
    jsr c128_test_force_dungeon_melee
#endif
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr screen_unblank
    jsr status_draw
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
!not_stairs_dn:

    // Stairs up?
    cmp #CMD_STAIRS_UP
    beq !stairs_up+
    jmp !not_stairs_up+
!stairs_up:
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
    jsr screen_blank
    jsr screen_clear            // Clear old level before lengthy load/generate
    jsr tier_check_transition   // Load new tier if crossing boundary
    lda #1
    sta level_entry_dir         // 1 = ascended
    lda #$ff
    sta zp_run_dir              // Stop running on level change
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    bcc !stairs_up_ovl_ok+
    jmp entry_main
!stairs_up_ovl_ok:
    jsr tramp_level_generate
#if C128
    jsr c128_restore_runtime_guards
#endif
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr screen_unblank
    jsr status_draw
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
!not_stairs_up:

    // Open door?
    cmp #CMD_OPEN
    bne !not_open+
    jsr msg_clear
    jsr get_direction_target
    bcc !open_no_turn+          // Invalid direction, no turn consumed
    jsr door_try_open
    bcc !open_no_turn+          // No door there, no turn consumed
    // Door opened or stuck — consume turn and re-render
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!open_no_turn:
    jmp main_loop
!not_open:

    // Close door?
    cmp #CMD_CLOSE
    bne !not_close+
    jsr msg_clear
    jsr get_direction_target
    bcc !close_no_turn+
    jsr door_try_close
    bcc !close_no_turn+
    // Door closed — consume turn and re-render
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!close_no_turn:
    jmp main_loop
!not_close:

    // Search?
    cmp #CMD_SEARCH
    bne !not_search+
    jsr msg_clear
    jsr do_search
    // Always consumes a turn
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!not_search:

    // Rest?
    cmp #CMD_REST
    bne !not_rest+
    jsr msg_clear
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp main_loop
!not_rest:

    // Pickup?
    cmp #CMD_PICKUP
    bne !not_pickup+
    jsr msg_clear
    jsr item_pickup
    bcc !pickup_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!pickup_no_turn:
    jmp main_loop
!not_pickup:

    // Drop?
    cmp #CMD_DROP
    bne !not_drop+
    jsr msg_clear
    jsr item_drop
    bcc !drop_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!drop_no_turn:
    jmp main_loop
!not_drop:

    // Inventory? (display only, no turn consumed)
    cmp #CMD_INVENTORY
    bne !not_inventory+
    lda #$ff
    sta uinv_filter             // Show all items
    jsr tramp_ui_inv_display
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    // Redraw map on return
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jmp vp_render_status_loop
!not_inventory:

    // Equipment? (display only, no turn consumed)
    cmp #CMD_EQUIPMENT
    bne !not_equipment+
    jsr tramp_ui_equip_display
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    // Redraw map on return
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jmp vp_render_status_loop
!not_equipment:

    // Wear/Wield?
    cmp #CMD_WEAR
    bne !not_wear+
    jsr msg_clear
    jsr item_wear
    bcc !wear_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!wear_no_turn:
    jmp main_loop
!not_wear:

    // Take off?
    cmp #CMD_TAKEOFF
    bne !not_takeoff+
    jsr msg_clear
    jsr item_takeoff
    bcc !takeoff_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!takeoff_no_turn:
    jmp main_loop
!not_takeoff:

    // Eat?
    cmp #CMD_EAT
    bne !not_eat+
    jsr msg_clear
    jsr item_eat
    bcc !eat_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp main_loop
!eat_no_turn:
    jmp main_loop
!not_eat:

    // Quaff potion?
    cmp #CMD_QUAFF
    bne !not_quaff+
    jsr msg_clear
    jsr item_quaff
    bcc !quaff_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp main_loop
!quaff_no_turn:
    jmp main_loop
!not_quaff:

    // Read scroll?
    cmp #CMD_READ
    bne !not_read+
    jsr msg_clear
    jsr item_read_scroll
    bcc !read_no_turn+
    // After teleportation or light, need visibility + render
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!read_no_turn:
    jmp main_loop
!not_read:

    // Aim wand?
    cmp #CMD_AIM
    bne !not_aim+
    jsr msg_clear
    jsr item_aim_wand
    bcc !aim_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!aim_no_turn:
    jmp main_loop
!not_aim:

    // Use staff?
    cmp #CMD_USE
    bne !not_use+
    jsr msg_clear
    jsr item_use_staff
    bcc !use_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!use_no_turn:
    jmp main_loop
!not_use:

    // Cast spell?
    cmp #CMD_CAST
    bne !not_cast+
    jsr msg_clear
#if C128
    jsr tramp_player_cast_spell
#else
    jsr player_cast_spell
#endif
    bcc !cast_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!cast_no_turn:
    // Restore screen after spell list overlay
    jsr screen_clear
    jmp vp_render_status_loop
!not_cast:

    // Pray?
    cmp #CMD_PRAY
    bne !not_pray+
    jsr msg_clear
#if C128
    jsr tramp_player_pray
#else
    jsr player_pray
#endif
    bcc !pray_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!pray_no_turn:
    jsr screen_clear
    jmp vp_render_status_loop
!not_pray:

    // Gain spell from book?
    cmp #CMD_GAIN
    bne !not_gain+
    jsr msg_clear
    jsr item_gain_spell
    bcc !gain_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp main_loop
!gain_no_turn:
    jmp main_loop
!not_gain:

    // Fire ranged weapon?
    cmp #CMD_FIRE
    bne !not_fire+
    jsr msg_clear
#if C128
    jsr tramp_ranged_fire
#else
    jsr ranged_fire
#endif
    bcc !fire_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!fire_no_turn:
    jmp main_loop
!not_fire:

    // Throw item?
    cmp #CMD_THROW
    bne !not_throw+
    jsr msg_clear
#if C128
    jsr tramp_throw_item
#else
    jsr throw_item
#endif
    bcc !throw_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!throw_no_turn:
    jmp main_loop
!not_throw:

    // Refuel lamp?
    cmp #CMD_REFUEL
    bne !not_refuel+
    jsr msg_clear
    jsr item_refuel
    bcc !refuel_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp main_loop
!refuel_no_turn:
    jmp main_loop
!not_refuel:

    // Bash?
    cmp #CMD_BASH
    bne !not_bash+
    jsr msg_clear
#if C128
    jsr tramp_bash_command
#else
    jsr bash_command
#endif
    bcc !bash_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!bash_no_turn:
    jmp main_loop
!not_bash:

    // Tunnel?
    cmp #CMD_TUNNEL
    bne !not_tunnel+
    jsr msg_clear
    jsr player_tunnel
    bcc !tunnel_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !tun_not_dead+
    jmp !player_died+
!tun_not_dead:
    jsr update_visibility
    jmp vp_render_status_loop
!tunnel_no_turn:
    jmp main_loop
!not_tunnel:

    // Look?
    cmp #CMD_LOOK
    bne !not_look+
    jsr msg_clear
    jsr do_look
    jmp main_loop
!not_look:

    // Running? (CMD_RUN_N through CMD_RUN_SE = $25-$2c)
    cmp #CMD_RUN_N
    bcc !not_run+
    cmp #CMD_RUN_SE + 1
    bcs !not_run+

    sec
    sbc #CMD_RUN_N              // Direction index 0-7
    sta zp_run_dir
    lda #0
    sta run_input_armed
    jsr input_run_cancel_reset
    jmp run_step                // Take first step
!not_run:

    // Unknown command — ignore
    jmp main_loop

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
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
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
    jmp main_loop

!run_blocked:
    lda #$ff
    sta zp_run_dir
    jmp main_loop

!run_trap_stop:
    lda #$ff
    sta zp_run_dir
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr update_visibility
    jmp vp_render_status_loop

!run_stop_move:
    lda #$ff
    sta zp_run_dir
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
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

    jsr render_local_area
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

!player_died:
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
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr delete_savefile
    jsr player_sync_from_zp
    jsr tramp_game_over         // Score, hiscore load/insert/save, death screen
    jsr disk_prompt_game        // Swap back to game disk if dual
    jsr input_get_key
    jmp !quit+

!quit:
    jsr game_over_prompt    // R)EBOOT / S)TART OVER / Q)UIT — Q falls through

    // --- Clean exit to BASIC ---
exit:
    jmp exit_trampoline     // Must run from below $A000 (banks in BASIC ROM)

// ============================================================
// Shared tail — viewport update + render + status + main loop
// Used by most command handlers after turn_post_action.
// ============================================================
vp_render_status_loop:
    lda #INPUT_ROW
    jsr screen_clear_row
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp main_loop

// ============================================================
// String data — gameplay strings (MUST stay below $C000)
// ============================================================

press_key_str:
    .text "Press any key" ; .byte 0

welcome_str:
    .text "Welcome to Moria8! Shift+Q to quit." ; .byte 0

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
// banked_ego_put_suffix — Write ego suffix to screen
// Relocated from $F000 to main RAM (R14). Calls ego_get_suffix_ptr
// ($F000) — requires KERNAL banked out (always true when called).
// Input: A = ego type (0 = no ego)
// Clobbers: A, Y, zp_ptr0
// ============================================================
banked_ego_put_suffix:
    cmp #0
    beq !beps_done+
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string (in $F000 RAM)
    ldy #0
!beps_loop:
    :MapRead_ptr0_y()
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
// put_inv_name_with_ego — Print item name with ego prefix/suffix
// Shared helper to avoid duplicating prefix check logic in $F000.
// Input: X = inventory slot index
// For ICAT_DIGGING + ego>0: prints "Gnomish Shovel" (prefix + name)
// For other + ego>0: prints "Long Sword (Flame)" (name + suffix)
// For ego=0: prints base name only
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
    // Tool ego prefix + base name (no suffix)
    ldx pinwe_item_id
    jsr put_tool_ego_prefix
    lda pinwe_item_id
    jsr item_get_name_ptr
    jsr screen_put_string
    rts
!pinwe_not_tool:
    lda pinwe_item_id
    jsr item_get_name_ptr
    jsr screen_put_string
    ldx pinwe_slot
    lda inv_ego,x
    jsr banked_ego_put_suffix
    rts
pinwe_item_id: .byte 0
pinwe_slot:    .byte 0
